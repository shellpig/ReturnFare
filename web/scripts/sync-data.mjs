import { copyFile, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { join, resolve, relative, sep, isAbsolute } from 'node:path';
import { tmpdir } from 'node:os';

// Resolve repository/web paths from this script's location, never from caller cwd.
// web/scripts/sync-data.mjs -> web/ -> repository root
const SCRIPT_FILE = fileURLToPath(import.meta.url);
const SCRIPT_DIR = resolve(SCRIPT_FILE, '..');
const WEB_DIR = resolve(SCRIPT_DIR, '..');
const REPO_ROOT = resolve(WEB_DIR, '..');

const DEFAULT_SOURCE = resolve(REPO_ROOT, 'data');
const DEFAULT_TARGET = resolve(WEB_DIR, 'public', 'data');

function isAncestor(ancestor, child) {
  const rel = relative(ancestor, child);
  return rel !== '' && rel !== '..' && !rel.startsWith(`..${sep}`) && !isAbsolute(rel);
}

function isWithinRepo(targetAbs) {
  return targetAbs === REPO_ROOT || isAncestor(REPO_ROOT, targetAbs);
}

// Validate the resolved absolute target before any destructive operation.
//
// Within the repository the only allowed target is the generated
// web/public/data directory; every other in-repo target (public/, art/,
// web/, repo root, and any descendant such as art/*) is rejected.
// Outside the repository only source/target pairs within OS temp are allowed.
// Source/target equality or either being an ancestor of the other is rejected.
function validateTarget(targetAbs, sourceAbs) {
  if (targetAbs === sourceAbs) {
    throw new Error(
      `syncData: target must not be the source directory: ${targetAbs}`,
    );
  }
  if (isAncestor(targetAbs, sourceAbs)) {
    throw new Error(
      `syncData: target must not be an ancestor of the source directory: ${targetAbs}`,
    );
  }
  if (isAncestor(sourceAbs, targetAbs)) {
    throw new Error(
      `syncData: source must not be an ancestor of the target directory: ${targetAbs}`,
    );
  }
  if (isWithinRepo(targetAbs) && targetAbs !== DEFAULT_TARGET) {
    throw new Error(
      `syncData: in-repo target must be exactly ${DEFAULT_TARGET}: ${targetAbs}`,
    );
  }
  if (targetAbs !== DEFAULT_TARGET &&
      !(isAncestor(resolve(tmpdir()), sourceAbs) && isAncestor(resolve(tmpdir()), targetAbs))) {
    throw new Error('syncData: custom source and target must be temporary fixture directories');
  }
}

async function collectFiles(dir, prefix, out) {
  const entries = await readdir(dir, { withFileTypes: true });
  for (const entry of entries) {
    const abs = join(dir, entry.name);
    if (entry.isDirectory()) {
      await collectFiles(abs, [...prefix, entry.name], out);
    } else if (entry.isFile()) {
      out.set([...prefix, entry.name].join('/'), abs);
    }
  }
  return out;
}

async function collectJson(dir) {
  const json = new Map();
  const all = await collectFiles(dir, [], json);
  // Keep only .json (this excludes SCHEMA.md and any non-JSON material).
  for (const [rel] of all) {
    if (!rel.endsWith('.json')) json.delete(rel);
  }
  return json;
}

export async function syncData(sourceDir, targetDir) {
  const sourceAbs = resolve(sourceDir);
  const targetAbs = resolve(targetDir);

  // Validate before any removal.
  validateTarget(targetAbs, sourceAbs);

  // Read the source before deleting any outputs.
  const sourceJson = await collectJson(sourceAbs);

  await mkdir(targetAbs, { recursive: true });

  // Rebuild only the generated target: remove every stale file inside it
  // (JSON and non-JSON alike) so source deletions remove stale targets.
  // Neighbouring material outside the target (e.g. public/art) is untouched.
  let removed = 0;
  const targetFiles = await collectFiles(targetAbs, [], new Map());
  for (const [rel, tgtAbs] of targetFiles) {
    if (!sourceJson.has(rel)) {
      await rm(tgtAbs, { force: true });
      removed += 1;
    }
  }

  // Copy / refresh every source JSON into target, preserving bytes and relative paths.
  let copied = 0;
  for (const [rel, srcAbs] of sourceJson) {
    const targetFile = join(targetAbs, ...rel.split('/'));
    await mkdir(resolve(targetFile, '..'), { recursive: true });
    await copyFile(srcAbs, targetFile);
    copied += 1;
  }

  // 額外產生 data-manifest.json，置於產出資料目錄之外（public/data-manifest.json）。
  // path 相對資料根、/ 分隔符、sha256 取來源檔案 bytes、依路徑排序。
  const manifestFiles = [];
  for (const [rel, srcAbs] of [...sourceJson.entries()].sort((a, b) =>
    a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0,
  )) {
    const bytes = await readFile(srcAbs);
    manifestFiles.push({
      path: rel,
      sha256: createHash('sha256').update(bytes).digest('hex'),
    });
  }
  const manifestFile = resolve(targetDir, '..', 'data-manifest.json');
  await writeFile(manifestFile, JSON.stringify({ files: manifestFiles }, null, 2));

  return { source: sourceAbs, target: targetAbs, copied, removed };
}

// CLI entry: synchronises repository data -> web/public/data.
// Paths are resolved from import.meta.url, never caller cwd.
// Merely importing this module does NOT run synchronization (guarded by import.meta.main).
if (import.meta.main) {
  (async () => {
    try {
      const result = await syncData(DEFAULT_SOURCE, DEFAULT_TARGET);
      console.log(
        `syncData: ${result.copied} JSON copied, ${result.removed} stale removed (${result.source} -> ${result.target})`,
      );
    } catch (err) {
      console.error(err instanceof Error ? err.message : String(err));
      process.exit(1);
    }
  })();
}
