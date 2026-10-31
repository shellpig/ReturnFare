import { describe, it, expect } from 'vitest';
import { mkdir, mkdtemp, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
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
});
