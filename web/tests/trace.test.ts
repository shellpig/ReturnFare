import { describe, it, expect } from 'vitest';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';
import { compareTraces, MISSING, TraceConfigError, type Trace } from '../../tools/trace/compare';

const __dirname = dirname(fileURLToPath(import.meta.url));
const BASELINE = resolve(__dirname, '../../tools/trace/baselines/greedy-godot.json');
const WEB_DIR = resolve(__dirname, '..');

function deepClone<TraceLike>(value: TraceLike): TraceLike {
  return JSON.parse(JSON.stringify(value)) as TraceLike;
}

function makeFixture(): Trace {
  return {
    schema_version: 1,
    policy: 'greedy-v1',
    source_revision: 'test-fixture',
    data_manifest: [],
    checkpoints: [
      {
        seq: 0,
        label: 'run_start',
        day: 1,
        phase: 'morning',
        state: {
          flow: { mode: 'run', active_ending: null },
          run: { action_spent: false, hand: ['protagonist', 'altar'], flags: { a: 1, b: 2 } },
          meta: { run_number: 1 },
        },
      },
    ],
  };
}

describe('W1-C trace comparator', () => {
  it('case 1: real baseline equals itself and its deep copy', async () => {
    const baseline = JSON.parse(await readFile(BASELINE, 'utf8')) as unknown as Trace;
    const self = compareTraces(baseline, baseline);
    const copied = compareTraces(baseline, deepClone(baseline));
    for (const result of [self, copied]) {
      expect(result.equal).toBe(true);
      expect(result.comparedCheckpoints).toBe(baseline.checkpoints.length);
      expect(result.comparedFields).toBeGreaterThan(0);
      expect(result.difference).toBeNull();
    }
  });

  it('case 2: single boolean flip reports exact checkpoint and field; expected unchanged', async () => {
    const text = await readFile(BASELINE, 'utf8');
    const baseline = JSON.parse(text) as Trace;
    const mutated = JSON.parse(text) as Trace;
    mutated.checkpoints[0].state.run.action_spent = !mutated.checkpoints[0].state.run.action_spent;

    const result = compareTraces(baseline, mutated);
    expect(result.equal).toBe(false);
    expect(result.difference).not.toBeNull();
    const difference = result.difference!;
    expect(difference.seq).toBe(0);
    expect(difference.label).toBe('run_start');
    expect(difference.day).toBe(1);
    expect(difference.phase).toBe('morning');
    expect(difference.path).toBe('/run/action_spent');
    expect(difference.expected).toBe(false);
    expect(difference.actual).toBe(true);

    // Expected input and source file must be unchanged by the comparison.
    expect(baseline.checkpoints[0].state.run.action_spent).toBe(false);
    expect(await readFile(BASELINE, 'utf8')).toBe(text);
  });

  it('case 3: object key order swap is equal; array element order swap is a difference', () => {
    const base = makeFixture();

    const keySwapped = deepClone(base);
    const run = keySwapped.checkpoints[0].state.run;
    keySwapped.checkpoints[0].state.run = {
      flags: run.flags,
      hand: run.hand,
      action_spent: run.action_spent,
    };
    expect(compareTraces(base, keySwapped).equal).toBe(true);

    const arraySwapped = deepClone(base);
    const hand = (arraySwapped.checkpoints[0].state.run.hand as string[]).slice().reverse();
    arraySwapped.checkpoints[0].state.run.hand = hand;
    const result = compareTraces(base, arraySwapped);
    expect(result.equal).toBe(false);
    expect(result.difference!.path).toBe('/run/hand/0');
    expect(result.difference!.expected).toBe('protagonist');
    expect(result.difference!.actual).toBe('altar');
  });

  it('case 4: added key, removed key (missing marker), null value, fewer checkpoint each detected', () => {
    const base = makeFixture();

    const added = deepClone(base);
    added.checkpoints[0].state.run.extra_flag = true;
    let result = compareTraces(base, added);
    expect(result.equal).toBe(false);
    expect(result.difference!.path).toBe('/run/extra_flag');

    const removed = deepClone(base);
    const { action_spent: _removedKey, ...runWithoutActionSpent } = removed.checkpoints[0].state.run;
    removed.checkpoints[0].state.run = runWithoutActionSpent;
    void _removedKey;
    result = compareTraces(base, removed);
    expect(result.equal).toBe(false);
    expect(result.difference!.path).toBe('/run/action_spent');
    expect(result.difference!.expected).toBe(false);
    expect(result.difference!.actual).toBe(MISSING);

    const nulled = deepClone(base);
    nulled.checkpoints[0].state.run.action_spent = null;
    result = compareTraces(base, nulled);
    expect(result.equal).toBe(false);
    expect(result.difference!.path).toBe('/run/action_spent');
    expect(result.difference!.expected).toBe(false);
    expect(result.difference!.actual).toBe(null);

    const fewer = deepClone(base);
    fewer.checkpoints = [];
    result = compareTraces(base, fewer);
    expect(result.equal).toBe(false);
    expect(result.difference).not.toBeNull();
    expect(result.difference!.path).toBe('/checkpoints');
    expect(result.difference!.actual).toBe(MISSING);
  });

  it('case 5: throughSeq plus one ignorePath excludes the ignored difference but catches others; config errors rejected', () => {
    const base = makeFixture();
    const mutated = deepClone(base);
    mutated.checkpoints[0].state.run.action_spent = true;
    mutated.checkpoints[0].state.meta.run_number = 2;

    const kept = compareTraces(base, mutated, { throughSeq: 0, ignorePaths: ['/run/action_spent'] });
    expect(kept.equal).toBe(false);
    expect(kept.difference!.path).toBe('/meta/run_number');
    expect(kept.comparedCheckpoints).toBe(1);

    // An ignored field may be absent on one side.
    const absent = deepClone(base);
    delete absent.checkpoints[0].state.run.action_spent;
    expect(compareTraces(base, absent, { ignorePaths: ['/run/action_spent'] }).equal).toBe(true);

    // Actual trace shorter than the requested prefix is a mismatch, not a config error.
    const twoStep = deepClone(base);
    twoStep.checkpoints.push({ ...deepClone(base.checkpoints[0]), seq: 1, label: 'phase_end' });
    const short = compareTraces(twoStep, base, { throughSeq: 1 });
    expect(short.equal).toBe(false);
    expect(short.difference!.path).toBe('/checkpoints');

    // Configuration errors (exit 2 through the CLI).
    expect(() => compareTraces(base, base, { throughSeq: -1 })).toThrow(TraceConfigError);
    expect(() => compareTraces(base, base, { throughSeq: 99 })).toThrow(TraceConfigError); // zero-checkpoint scope
    expect(() => compareTraces(base, base, { ignorePaths: ['/run'] })).toThrow(TraceConfigError);
    expect(() => compareTraces(base, base, { ignorePaths: [''] })).toThrow(TraceConfigError); // root
    expect(() => compareTraces(base, base, { ignorePaths: ['/flow'] })).toThrow(TraceConfigError);
    expect(() => compareTraces(base, base, { ignorePaths: ['/meta'] })).toThrow(TraceConfigError);
    expect(() => compareTraces(base, base, { ignorePaths: ['/run/action_spennt'] })).toThrow(TraceConfigError); // misspelled
  });

  it('case 6: different manifest is baseline-not-applicable; CLI exits 0 / 1 / 2', async () => {
    const text = await readFile(BASELINE, 'utf8');
    const baseline = JSON.parse(text) as Trace;

    const wrongManifest = deepClone(baseline);
    wrongManifest.data_manifest = [
      { path: 'beats/ch1_d01_d03.json', sha256: '0000000000000000000000000000000000000000000000000000000000000000' },
    ];
    const manifestResult = compareTraces(baseline, wrongManifest);
    expect(manifestResult.equal).toBe(false);
    expect(manifestResult.comparedCheckpoints).toBe(0);
    expect(manifestResult.comparedFields).toBe(0);
    expect(manifestResult.difference).not.toBeNull();
    expect(manifestResult.difference!.seq).toBeNull();
    expect(manifestResult.difference!.path).toBe('/data_manifest');

    const tempRoot = resolve(tmpdir());
    const root = await mkdtemp(join(tempRoot, 'rf-w1c-'));
    try {
      const copy = join(root, 'copy.json');
      await writeFile(copy, text, 'utf8');
      const badJson = join(root, 'bad.json');
      await writeFile(badJson, '{ not valid json', 'utf8');
      const flipped = deepClone(baseline);
      flipped.checkpoints[0].state.run.action_spent = !flipped.checkpoints[0].state.run.action_spent;
      const flippedPath = join(root, 'flipped.json');
      await writeFile(flippedPath, JSON.stringify(flipped), 'utf8');

      const npmCommand = process.platform === 'win32' ? ['cmd', '/c', 'npm'] : ['npm'];
      const runCli = (expectedPath: string, actualPath: string) =>
        spawnSync(npmCommand[0], npmCommand.slice(1).concat('run', 'trace:compare', '--', expectedPath, actualPath), {
          cwd: WEB_DIR,
          encoding: 'utf8',
        });

      const exit0 = runCli(BASELINE, copy);
      expect(exit0.status).toBe(0);
      expect(exit0.stdout).toContain('equal=true');

      const exit1 = runCli(BASELINE, flippedPath);
      expect(exit1.status).toBe(1);
      expect(exit1.stdout).toContain('seq=0 day=1 phase=morning path=/run/action_spent expected=false actual=true');

      const exit2 = runCli(BASELINE, badJson);
      expect(exit2.status).toBe(2);
    } finally {
      // Cleanup only this test's verified fixture root (mirrors W1-A test guard).
      if (dirname(resolve(root)) !== tempRoot) throw new Error('Unexpected fixture cleanup path');
      await rm(root, { recursive: true, force: true });
    }
  });
});
