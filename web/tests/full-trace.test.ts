/**
 * ReturnFare Web — 45 天全程軌跡與黃金基線對帳測試（W6-E2-3 / W7-A）。
 *
 * 驗收規格：
 * 1. 使用現行資料產生完整軌跡，呼叫生產 compareTraces 進行嚴格無 options 全程對帳（193 checkpoints，0 diff，真實 data_manifest 一致）。
 * 2. 179 phase_end 排程（含 D45 afternoon 遭遇結算 auto-advance 使 seq 178/179 均為 evening）。
 * 3. 結局逐頁 reveal/advance 序列（2 * page_count - 1 = 11 steps）與 opening_ready 結算狀態。
 * 4. 兩次獨立走查具備完全決定論。
 * 5. 異常路徑防護：透過 vi.spyOn 注入單一異常時，真實 runGreedyFull 必須立即拋出上下文例外並中斷；生產 trace:web CLI 缺參數非零退出。
 * 6. 旗標型別對齊 Godot effect_apply.gd:142（字串真值強制轉為 boolean）。
 */

import { describe, it, expect, vi } from 'vitest';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadGameDataNode } from '../src/data/load-node';
import { runGreedyFull } from './support/greedy';
import { buildWebTrace } from '../scripts/trace-web';
import { compareTraces, type Trace } from '../../tools/trace/compare';
import { createInitialSnapshot } from '../src/core/run-initialization';
import { planEffects } from '../src/core/effect';
import * as traceEntry from '../src/core/trace-entry';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '..', '..');
const BASELINE_PATH = path.join(
  REPO_ROOT,
  'tools/trace/baselines/greedy-godot.json',
);

describe('W6-E2-3 / W7-A full-trace verification', () => {
  it('1. current-data full trace strictly matches golden baseline across all 193 checkpoints and manifest with zero options', async () => {
    const baseline = JSON.parse(
      fs.readFileSync(BASELINE_PATH, 'utf-8'),
    ) as Trace;
    // 使用生產 buildWebTrace()，保留真實 current data_manifest（不偽造為 baseline manifest）
    const actualTrace = (await buildWebTrace()) as unknown as Trace;

    expect(actualTrace.checkpoints).toHaveLength(193);

    // W7-A：呼叫生產 compareTraces(baseline, actualTrace) 無任何 options（無 scope、無 ignorePaths）進行嚴格全量對帳
    const result = compareTraces(baseline, actualTrace);
    expect(result.equal).toBe(true);
    expect(result.difference).toBeNull();
    expect(result.comparedCheckpoints).toBe(193);
    expect(result.comparedFields).toBeGreaterThan(0);

    // 文案更新後 Godot 基準已於 A1 重產，真實 data_manifest 與所有 checkpoint 全數嚴格相等
    expect(actualTrace.checkpoints).toEqual(baseline.checkpoints);

    // 變異保真：翻轉記憶體中單一純量欄位時，compareTraces 必須精確回報差異且轉為 false
    const mutatedTrace = JSON.parse(JSON.stringify(actualTrace)) as Trace;
    mutatedTrace.checkpoints[0].state.meta.run_number = 999;
    const mutatedResult = compareTraces(baseline, mutatedTrace);
    expect(mutatedResult.equal).toBe(false);
    expect(mutatedResult.difference?.seq).toBe(0);
    expect(mutatedResult.difference?.path).toBe('/meta/run_number');
  });

  it('2. reproduces 179 phase_end schedule with D45 afternoon auto-advance (seq 178/179 both evening)', async () => {
    const data = await loadGameDataNode();
    const { checkpoints } = runGreedyFull(data);

    expect(checkpoints[0].label).toBe('run_start');
    expect(checkpoints[0].day).toBe(1);
    expect(checkpoints[0].phase).toBe('morning');

    const phaseEndCps = checkpoints.filter((cp) => cp.label === 'phase_end');
    expect(phaseEndCps).toHaveLength(179);

    // D1～D44: 4 phases per day
    let phaseIdx = 1;
    for (let d = 1; d <= 44; d += 1) {
      for (const expectedPhase of ['morning', 'afternoon', 'evening', 'night']) {
        const cp = checkpoints[phaseIdx];
        expect(cp.label).toBe('phase_end');
        expect(cp.day).toBe(d);
        expect(cp.phase).toBe(expectedPhase);
        phaseIdx += 1;
      }
    }

    // D45: seq 177 morning, seq 178 evening (auto-advanced), seq 179 evening
    const cp177 = checkpoints[177];
    expect(cp177.label).toBe('phase_end');
    expect(cp177.day).toBe(45);
    expect(cp177.phase).toBe('morning');

    const cp178 = checkpoints[178];
    expect(cp178.label).toBe('phase_end');
    expect(cp178.day).toBe(45);
    expect(cp178.phase).toBe('evening');

    const cp179 = checkpoints[179];
    expect(cp179.label).toBe('phase_end');
    expect(cp179.day).toBe(45);
    expect(cp179.phase).toBe('evening');

    // seq 178 vs 179: evening after coda choice
    expect(cp178.state.run.choices['d45_then::d45_coda']).toBeUndefined();
    expect(cp179.state.run.choices['d45_then::d45_coda']).toBe('empty_handed');
  });

  it('3. reproduces full ending page sequence (2*page_count-1 steps) and stops at opening_ready', async () => {
    const data = await loadGameDataNode();
    const { checkpoints } = runGreedyFull(data);

    // seq 180: ending_started
    const cp180 = checkpoints[180];
    expect(cp180.label).toBe('ending_started');
    expect(cp180.day).toBe(45);
    expect(cp180.phase).toBe('evening');
    expect(cp180.state.flow.mode).toBe('ending');
    const active = cp180.state.flow.active_ending!;
    expect(active.ending_id).toBe('ending_replaced');
    expect(active.page_index).toBe(0);
    expect(active.page_revealed).toBe(false);
    expect(active.ready_to_complete).toBe(false);
    const pageCount = active.page_refs.length;
    expect(pageCount).toBe(6);

    // seq 181～191: ending_step (2 * 6 - 1 = 11 steps)
    const expectedSteps = 2 * pageCount - 1;
    for (let s = 0; s < expectedSteps; s += 1) {
      const cp = checkpoints[181 + s];
      expect(cp.label).toBe('ending_step');
      expect(cp.day).toBe(45);
      expect(cp.phase).toBe('evening');
      expect(cp.state.flow.mode).toBe('ending');
      const stepActive = cp.state.flow.active_ending!;
      const expectedPage = Math.floor((s + 1) / 2);
      const expectedRevealed = s % 2 === 0;
      const expectedReady =
        expectedPage === pageCount - 1 && expectedRevealed;
      expect(stepActive.page_index).toBe(expectedPage);
      expect(stepActive.page_revealed).toBe(expectedRevealed);
      expect(stepActive.ready_to_complete).toBe(expectedReady);
    }

    // seq 192: opening_ready
    const cp192 = checkpoints[192];
    expect(cp192.label).toBe('opening_ready');
    expect(cp192.day).toBe(1);
    expect(cp192.phase).toBe('morning');
    expect(cp192.state.flow.mode).toBe('opening');
    expect(cp192.state.flow.active_ending).toBeNull();
    expect(cp192.state.meta.run_number).toBe(2);
    expect(cp192.state.meta.ending_history).toHaveLength(1);
    expect(cp192.state.meta.ending_history[0].ending_id).toBe(
      'ending_replaced',
    );
    expect(cp192.state.meta.knowledge['k_not_today']).toBe(true);
    expect(cp192.state.meta.knowledge['k_i_returned']).toBe(true);
    expect(checkpoints).toHaveLength(193);
  });

  it('4. is fully deterministic across consecutive runs', async () => {
    const data = await loadGameDataNode();
    const run1 = runGreedyFull(data);
    const run2 = runGreedyFull(data);

    expect(run1.checkpoints).toHaveLength(193);
    expect(run2.checkpoints).toHaveLength(193);
    for (let i = 0; i < 193; i += 1) {
      expect(run1.checkpoints[i].seq).toBe(run2.checkpoints[i].seq);
      expect(run1.checkpoints[i].label).toBe(run2.checkpoints[i].label);
      expect(run1.checkpoints[i].day).toBe(run2.checkpoints[i].day);
      expect(run1.checkpoints[i].phase).toBe(run2.checkpoints[i].phase);
      expect(run1.checkpoints[i].state).toEqual(run2.checkpoints[i].state);
    }
  });

  it('5. fails fast on unexpected Game rejection or premature mode exit instead of silently skipping', async () => {
    const data = await loadGameDataNode();
    const origCreateRun = traceEntry.createRunForTrace;

    // 5a. Rejected advancePhase must fail runner with contextual error
    const spyAdv = vi.spyOn(traceEntry, 'createRunForTrace').mockImplementation((d) => {
      const g = origCreateRun(d);
      g.advancePhase = () => ({
        ok: false,
        reason_code: 'phase_requirements_incomplete',
        reason_text: '測試注入之異常阻斷',
        lines: [],
        phase_advanced: false,
      });
      return g;
    });

    try {
      expect(() => runGreedyFull(data)).toThrowError(
        /\[D1 morning\] advancePhase 失敗：phase_requirements_incomplete \(測試注入之異常阻斷\)/,
      );
    } finally {
      spyAdv.mockRestore();
    }

    // 5b. Rejected completeEnding must fail runner with contextual error
    const spyComp = vi.spyOn(traceEntry, 'createRunForTrace').mockImplementation((d) => {
      const g = origCreateRun(d);
      g.completeEnding = () => ({
        ok: false,
        reason_code: 'not_ending',
        reason_text: '模擬結算失敗',
        lines: [],
      });
      return g;
    });

    try {
      expect(() => runGreedyFull(data)).toThrowError(
        /completeEnding 失敗：not_ending \(模擬結算失敗\)/,
      );
    } finally {
      spyComp.mockRestore();
    }

    // 5c. Premature mode change during ending without completing must fail invariant check
    const spyPremature = vi.spyOn(traceEntry, 'createRunForTrace').mockImplementation((d) => {
      const g = origCreateRun(d);
      const origAdvance = g.advanceEndingPage;
      let prematureExited = false;
      g.advanceEndingPage = () => {
        const res = origAdvance();
        prematureExited = true;
        return res;
      };
      const origSnapshot = g.getSnapshot.bind(g);
      g.getSnapshot = () => {
        const snap = origSnapshot();
        if (prematureExited) {
          return {
            ...snap,
            flow: {
              ...snap.flow,
              mode: 'run',
            },
          };
        }
        return snap;
      };
      return g;
    });

    try {
      expect(() => runGreedyFull(data)).toThrowError(
        /runGreedyFull 異常終止：未完成 completeEnding 且未抵達 opening_ready/,
      );
    } finally {
      spyPremature.mockRestore();
    }

    // 5d. Production trace:web CLI fails with non-zero exit code on malformed input (missing --output)
    const npmCmd = process.platform === 'win32' ? ['cmd', '/c', 'npm'] : ['npm'];
    const cliResult = spawnSync(
      npmCmd[0],
      npmCmd.slice(1).concat('run', 'trace:web', '--'),
      {
        cwd: path.join(REPO_ROOT, 'web'),
        encoding: 'utf8',
      },
    );
    expect(cliResult.status).toBe(1);
    expect(cliResult.stdout + cliResult.stderr).toContain('用法：npm run trace:web -- --output <path>');
  });

  it('6. correctly coerces string flag values to boolean true matching Godot effect_apply.gd:142', async () => {
    const data = await loadGameDataNode();
    const state = createInitialSnapshot();
    state.flow.mode = 'run';

    // Positive cases: string flag values are coerced to boolean by nonempty truthiness
    const plan = planEffects(
      [
        {
          flag: {
            inherit_version: 'high',
            empty_flag: '',
            mid_flag: 'mid',
          },
        },
      ],
      state,
      data,
    );
    expect(plan.ok).toBe(true);
    expect(plan.nextState.run.flags['inherit_version']).toBe(true);
    expect(plan.nextState.run.flags['empty_flag']).toBe(false);
    expect(plan.nextState.run.flags['mid_flag']).toBe(true);

    // Negative case: unsupported value shapes (e.g. object / array) are rejected
    const badPlan = planEffects(
      [
        {
          flag: {
            nested_flag: { invalid: true } as unknown as boolean,
          },
        },
      ],
      state,
      data,
    );
    expect(badPlan.ok).toBe(false);
    expect(badPlan.reason_code).toBe('data_conflict');
  });
});
