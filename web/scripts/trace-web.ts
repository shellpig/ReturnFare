/**
 * ReturnFare Web — Web 端 Golden Trace 匯出 CLI（W3-B）。
 *
 * 用法：
 *   npm run trace:web -- --output ../_qa/web/trace-web.json
 */

import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildManifest, loadGameDataNode } from '../src/data/load-node';
import { runGreedyFull } from '../tests/support/greedy';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '..', '..');

function parseArgs(argv: readonly string[]): { output: string } {
  let output = '';
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--output' && i + 1 < argv.length) {
      output = argv[i + 1];
      i += 1;
    } else if (arg.startsWith('--output=')) {
      output = arg.slice('--output='.length);
    }
  }
  if (!output) {
    throw new Error('用法：npm run trace:web -- --output <path>');
  }
  return { output };
}

function getGitRevision(): string {
  try {
    return execSync('git rev-parse HEAD', {
      cwd: REPO_ROOT,
      encoding: 'utf-8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
  } catch {
    return 'unknown';
  }
}

export async function buildWebTrace(dataDir?: string) {
  const data = await loadGameDataNode(dataDir);
  const manifest = await buildManifest(dataDir);
  const { checkpoints } = runGreedyFull(data);
  return {
    schema_version: 1 as const,
    policy: 'greedy-v1',
    source_revision: getGitRevision(),
    data_manifest: manifest.map((f) => ({
      path: f.path,
      sha256: f.sha256,
    })),
    checkpoints,
  };
}

async function main(): Promise<void> {
  const { output } = parseArgs(process.argv.slice(2));
  const outPath = path.resolve(process.cwd(), output);
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  const trace = await buildWebTrace();
  fs.writeFileSync(outPath, `${JSON.stringify(trace, null, 2)}\n`, 'utf-8');
  console.log(
    `[trace:web] 已輸出 ${trace.checkpoints.length} 個 checkpoints 至 ${outPath}`,
  );
}

const isDirectRun =
  process.argv[1] !== undefined &&
  path.resolve(process.argv[1]) === path.resolve(__filename);

if (isDirectRun) {
  main().catch((err: unknown) => {
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(1);
  });
}
