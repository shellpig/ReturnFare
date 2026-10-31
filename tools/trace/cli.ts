// W1-C CLI entry: `npm run trace:compare -- <expected> <actual> [--scope <scope.json>]` (cwd: web/).
// Imports only Node built-ins plus the local compare module.

import { compareTraces, MISSING, TraceConfigError, TraceShapeError, type TraceCompareResult } from './compare';
import { readFileSync } from 'node:fs';
import { exit } from 'node:process';

interface CliArguments {
  expected: string;
  actual: string;
  scope?: { throughSeq?: number; ignorePaths?: string[] };
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function parseArguments(argv: string[]): CliArguments {
  const positional: string[] = [];
  let scopePath: string | undefined = undefined;
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--scope') {
      scopePath = argv[i + 1];
      if (scopePath === undefined) throw new Error('missing value for --scope');
      i += 1;
    } else if (arg.startsWith('--')) {
      throw new Error(`unknown option: ${arg}`);
    } else {
      positional.push(arg);
    }
  }
  if (positional.length !== 2) {
    throw new Error('usage: trace:compare <expected> <actual> [--scope <scope.json>]');
  }
  const arguments_: CliArguments = { expected: positional[0], actual: positional[1] };
  if (scopePath !== undefined) {
    const scope = JSON.parse(readFileSync(scopePath, 'utf8')) as Record<string, unknown>;
    if (!isPlainObject(scope)) throw new Error('scope must be a JSON object');
    const parsed: { throughSeq?: number; ignorePaths?: string[] } = {};
    const throughSeq = scope['throughSeq'];
    if (throughSeq !== undefined) {
      if (typeof throughSeq !== 'number' || !Number.isInteger(throughSeq)) {
        throw new Error('scope.throughSeq must be an integer');
      }
      parsed.throughSeq = throughSeq;
    }
    const ignorePaths = scope['ignorePaths'];
    if (ignorePaths !== undefined) {
      if (!Array.isArray(ignorePaths) || ignorePaths.some((path) => typeof path !== 'string')) {
        throw new Error('scope.ignorePaths must be an array of strings');
      }
      parsed.ignorePaths = ignorePaths;
    }
    arguments_.scope = parsed;
  }
  return arguments_;
}

function formatValue(value: unknown): string {
  if (value === MISSING) return '<missing>';
  if (value === null) return 'null';
  if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') return String(value);
  if (Array.isArray(value)) return '[array]';
  if (typeof value === 'object') return '{object}';
  return String(value);
}

function printResult(result: TraceCompareResult): void {
  const counts = `comparedCheckpoints=${result.comparedCheckpoints} comparedFields=${result.comparedFields}`;
  if (result.equal && result.difference === null) {
    console.log(`${counts} equal=true`);
    return;
  }
  if (result.difference === null) {
    console.log(`${counts} equal=false`);
    return;
  }
  const { seq, label, day, phase, path, expected, actual } = result.difference;
  if (seq === null && ['/schema_version', '/policy', '/data_manifest'].includes(path)) {
    console.log(`baseline not applicable: ${path} differs`);
    return;
  }
  console.log(
    `${counts} equal=false first difference: seq=${seq === null ? '-' : seq} day=${day === null ? '-' : day} phase=${phase === null ? '-' : phase} path=${path} expected=${formatValue(expected)} actual=${formatValue(actual)}`,
  );
}

function main(): void {
  try {
    const args = parseArguments(process.argv.slice(2));
    const expected = JSON.parse(readFileSync(args.expected, 'utf8'));
    const actual = JSON.parse(readFileSync(args.actual, 'utf8'));
    const result = compareTraces(expected, actual, args.scope);
    printResult(result);
    exit(result.equal ? 0 : 1);
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    exit(2);
  }
}

main();
