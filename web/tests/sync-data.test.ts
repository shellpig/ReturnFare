import { describe, it, expect } from 'vitest';
import { mkdir, mkdtemp, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { dirname, join, resolve, sep } from 'node:path';
import { tmpdir } from 'node:os';
import { syncData } from '../scripts/sync-data.mjs';

async function exists(path: string): Promise<boolean> {
  try {
    await stat(path);
    return true;
  } catch {
    return false;
  }
}

describe('syncData', () => {
  it('syncs nested JSON under generated data, excludes SCHEMA.md, preserves sibling art, removes stale files', async () => {
    const tempRoot = resolve(tmpdir());
    const root = await mkdtemp(join(tempRoot, 'rf-w1a-'));
    const sourceDir = join(root, 'source');
    const publicDir = join(root, 'public');
    const targetDir = join(publicDir, 'data');
    const artDir = join(publicDir, 'art');

    try {
      await mkdir(sourceDir, { recursive: true });
      await mkdir(join(sourceDir, 'beats'), { recursive: true });
      await mkdir(targetDir, { recursive: true });
      await mkdir(artDir, { recursive: true });
      await writeFile(join(sourceDir, 'tuning.json'), JSON.stringify({ a: 1 }));
      await writeFile(
        join(sourceDir, 'beats', 'ch1.json'),
        JSON.stringify({ b: 2 }),
      );
      await writeFile(join(sourceDir, 'SCHEMA.md'), '# schema');

      // Stale non-JSON inside the generated target must be removed on rebuild.
      await writeFile(join(targetDir, 'stale.txt'), 'stale');
      // Sibling art (outside the generated target) must survive.
      await writeFile(join(artDir, 'town.webp'), 'fake-art');

      await expect(syncData(sourceDir, sourceDir)).rejects.toThrow('target must not be the source');

      const result = await syncData(sourceDir, targetDir);
      expect(result.copied).toBe(2);
      expect(result.removed).toBe(1);

      // Exact bytes and relative paths.
      expect(await readFile(join(targetDir, 'tuning.json'), 'utf8')).toBe(
        JSON.stringify({ a: 1 }),
      );
      expect(await readFile(join(targetDir, 'beats', 'ch1.json'), 'utf8')).toBe(
        JSON.stringify({ b: 2 }),
      );

      // SCHEMA.md excluded.
      expect(await exists(join(targetDir, 'SCHEMA.md'))).toBe(false);
      // Stale non-JSON inside generated data removed.
      expect(await exists(join(targetDir, 'stale.txt'))).toBe(false);
      // Sibling art preserved (not inside generated data).
      expect(await readFile(join(artDir, 'town.webp'), 'utf8')).toBe(
        'fake-art',
      );

      // Source deletion removes stale JSON on re-sync.
      await rm(join(sourceDir, 'beats', 'ch1.json'), { force: true });
      const second = await syncData(sourceDir, targetDir);
      expect(second.removed).toBe(1);
      expect(await exists(join(targetDir, 'beats', 'ch1.json'))).toBe(false);
      expect(await readFile(join(targetDir, 'tuning.json'), 'utf8')).toBe(
        JSON.stringify({ a: 1 }),
      );
      expect(await readFile(join(artDir, 'town.webp'), 'utf8')).toBe(
        'fake-art',
      );
    } finally {
      // Cleanup only this test's verified fixture root.
      if (dirname(resolve(root)) !== tempRoot) throw new Error('Unexpected fixture cleanup path');
      await rm(root, { recursive: true, force: true });
    }
  });

  it('produces sorted data-manifest.json outside public/data with source-byte sha256', async () => {
    const tempRoot = resolve(tmpdir());
    const root = await mkdtemp(join(tempRoot, 'rf-w2a-manifest-'));
    const sourceDir = join(root, 'source');
    const publicDir = join(root, 'public');
    const targetDir = join(publicDir, 'data');
    const manifestFile = join(publicDir, 'data-manifest.json');

    try {
      await mkdir(sourceDir, { recursive: true });
      await mkdir(join(sourceDir, 'beats'), { recursive: true });
      await mkdir(targetDir, { recursive: true });

      await writeFile(join(sourceDir, 'tuning.json'), JSON.stringify({ hand_size: 14 }));
      await writeFile(
        join(sourceDir, 'beats', 'ch1_d01_d03.json'),
        JSON.stringify({ beats: [{ id: 'd1_morning_phone', location: 'sanquan' }] }),
      );
      // Non-JSON and non-data material must not appear in the manifest.
      await writeFile(join(sourceDir, 'SCHEMA.md'), '# schema');
      await writeFile(join(sourceDir, 'notes.txt'), 'ignore');

      await syncData(sourceDir, targetDir);

      const manifestText = await readFile(manifestFile, 'utf8');
      const manifest = JSON.parse(manifestText) as {
        files: Array<{ path: string; sha256: string }>;
      };
      expect(Array.isArray(manifest.files)).toBe(true);

      const paths = manifest.files.map((f) => f.path);
      // 依路徑排序
      expect(paths).toEqual([...paths].sort());
      // 僅 JSON，排除 SCHEMA.md / txt
      expect(paths).toEqual(expect.arrayContaining(['tuning.json', 'beats/ch1_d01_d03.json']));
      expect(paths).not.toContain('SCHEMA.md');
      expect(paths).not.toContain('notes.txt');

      // 置於 public/data 之外（與 data 目錄為同層，不在 targetDir 內）
      const manifestAbs = resolve(manifestFile);
      const targetAbs = resolve(targetDir);
      expect(manifestAbs === targetAbs || manifestAbs.startsWith(`${targetAbs}${sep}`)).toBe(false);

      // sha256 與來源檔案 bytes 一致
      for (const f of manifest.files) {
        const srcAbs = resolve(sourceDir, ...f.path.split('/'));
        const bytes = await readFile(srcAbs);
        const expected = createHash('sha256').update(bytes).digest('hex');
        expect(f.sha256).toBe(expected);
      }
    } finally {
      if (dirname(resolve(root)) !== tempRoot) throw new Error('Unexpected fixture cleanup path');
      await rm(root, { recursive: true, force: true });
    }
  });
});
