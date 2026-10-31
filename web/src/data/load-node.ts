/**
 * ReturnFare Web — Node 端資料載入（W2-A）。
 *
 * 直接讀 repo data/（node:fs），從同一來源清單建立 manifest，不依賴 Vite
 * 先行建置。呼叫 loader.ts 的共用解析；不維護第二份讀取規則。
 */

import { createHash } from 'node:crypto';
import { readdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import {
  loadGameData,
  type DataFile,
  type GameData,
  type ReadText,
} from './loader';

// Resolve repository root from this file's location (web/src/data/load-node.ts),
// never from caller cwd, so it works without Vite having run.
const SCRIPT_FILE = fileURLToPath(import.meta.url);
const SCRIPT_DIR = resolve(SCRIPT_FILE, '..');
const REPO_ROOT = resolve(SCRIPT_DIR, '..', '..', '..');
const DATA_DIR = resolve(REPO_ROOT, 'data');

export const readText: ReadText = async (relativeDataPath: string): Promise<string> => {
  const abs = resolve(DATA_DIR, relativeDataPath);
  return readFile(abs, 'utf8');
};

export async function buildManifest(): Promise<DataFile[]> {
  const files: DataFile[] = [];

  const collect = async (dir: string, prefix: string): Promise<void> => {
    const entries = await readdir(dir, { withFileTypes: true });
    for (const entry of entries) {
      const abs = resolve(dir, entry.name);
      const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
      if (entry.isDirectory()) {
        await collect(abs, rel);
      } else if (entry.isFile() && rel.endsWith('.json')) {
        const bytes = await readFile(abs);
        files.push({
          path: rel,
          sha256: createHash('sha256').update(bytes).digest('hex'),
        });
      }
    }
  };

  await collect(DATA_DIR, '');
  files.sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
  return files;
}

export async function loadGameDataNode(): Promise<GameData> {
  const manifest = await buildManifest();
  return loadGameData(readText, manifest);
}
