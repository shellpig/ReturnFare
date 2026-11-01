/**
 * ReturnFare Web — Greedy 走查輔助（W3-B: seq 0～4；W5-B: seq 0～11 共 12 個 checkpoints）。
 *
 * 對齊 Godot tests/headless/playthrough_greedy.gd 的無開局走查基線：
 * - 使用 trace-entry.ts 的 createRunForTrace(data)
 * - W3: 記錄 seq 0 (run_start) 與 D1 四個時段收尾 checkpoint (seq 1～4)
 * - W5: 記錄 seq 0 (run_start) + D1/D2 四個時段收尾 (seq 1～8) + D3 morning/afternoon/evening (seq 9～11)
 */

import type { GameData } from '../../src/data/types';
import { TriState } from '../../src/core/panel';
import { createRunForTrace } from '../../src/core/trace-entry';
import type { DeepReadonly, Game, GameSnapshot } from '../../src/core/state-types';

export interface GreedyCheckpoint {
  seq: number;
  label: string;
  day: number;
  phase: 'morning' | 'afternoon' | 'evening' | 'night';
  state: GameSnapshot;
}

export interface GreedyWalkResult {
  game: Game;
  checkpoints: GreedyCheckpoint[];
}

export function assertNightFixedPlayback(
  before: DeepReadonly<GameSnapshot>,
  after: DeepReadonly<GameSnapshot>,
  data: GameData,
): void {
  const newlyEntered = Object.keys(after.run.beats_entered).filter(
    (bid) => after.run.beats_entered[bid] && !before.run.beats_entered[bid],
  );

  for (let i = 0; i < newlyEntered.length; i += 1) {
    const bid = newlyEntered[i];
    const b = data.beatsById.get(bid);
    if (!b || b.fixed !== true) {
      continue;
    }
    const loc = data.locationsById.get(b.location);
    if (loc && loc.layer === 'night') {
      const chosen = after.run.night_location_chosen;
      if (chosen !== b.location || !after.meta.night_locations_seen[chosen]) {
        throw new Error(
          `[D${after.run.day} night] night-layer fixed beat '${bid}' 強制到訪未生效（night_location_chosen='${chosen}'）`,
        );
      }
    }
  }
}

export function runGreedyW3(data: GameData): GreedyWalkResult {
  const game = createRunForTrace(data);
  const checkpoints: GreedyCheckpoint[] = [];
  let seq = 0;

  const recordCheckpoint = (label: string): void => {
    const snap = game.serialize();
    checkpoints.push({
      seq,
      label,
      day: snap.run.day,
      phase: snap.run.phase,
      state: snap,
    });
    seq += 1;
  };

  // seq 0: run_start (D1 morning 初態)
  recordCheckpoint('run_start');

  // D1 四個時段：morning -> afternoon -> evening -> night -> (advance to D2 morning)
  for (let step = 0; step < 4; step += 1) {
    const current = game.getSnapshot();
    const { day, phase } = current.run;

    if (phase === 'evening') {
      const evRes = game.playEvening();
      if (!evRes.ok) {
        throw new Error(
          `[D${day} ${phase}] playEvening 失敗：${evRes.reason_code} (${evRes.reason_text})`,
        );
      }
    } else if (phase === 'night') {
      const beforeNf = game.getSnapshot();
      const nfRes = game.playNightFixed();
      if (!nfRes.ok) {
        throw new Error(
          `[D${day} ${phase}] playNightFixed 失敗：${nfRes.reason_code} (${nfRes.reason_text})`,
        );
      }
      assertNightFixedPlayback(beforeNf, game.getSnapshot(), data);
    }

    // 記錄該時段收尾（在 advancePhase 之前）
    recordCheckpoint('phase_end');

    const advRes = game.advancePhase();
    if (!advRes.ok || !advRes.phase_advanced) {
      throw new Error(
        `[D${day} ${phase}] advancePhase 失敗：${advRes.reason_code} (${advRes.reason_text})`,
      );
    }
  }

  return { game, checkpoints };
}

function executeGreedyActionPhase(game: Game): void {
  const locs = game.availableLocations();
  const playedBeats: Record<string, boolean> = {};
  let changed = true;
  while (changed) {
    changed = false;
    for (let l = 0; l < locs.length; l += 1) {
      const locId = locs[l];
      const panel = game.buildPanel(locId);
      for (let b = 0; b < panel.beats.length; b += 1) {
        const beatView = panel.beats[b];
        if (beatView.tri !== TriState.OPEN) continue;
        if (playedBeats[beatView.id]) continue;
        const res = game.playBeat(beatView.id);
        if (!res.ok) {
          throw new Error(`playBeat 失敗：${beatView.id}: ${res.reason_text}`);
        }
        playedBeats[beatView.id] = true;
        changed = true;
      }
    }
  }

  // 貪心尋找第一個可放主角卡的 OPEN 槽
  let placed = false;
  for (let l = 0; l < locs.length; l += 1) {
    const locId = locs[l];
    const panel = game.buildPanel(locId);
    for (let b = 0; b < panel.beats.length; b += 1) {
      const beatView = panel.beats[b];
      if (beatView.tri !== TriState.OPEN) continue;
      for (let s = 0; s < beatView.slots.length; s += 1) {
        const slotView = beatView.slots[s];
        if (slotView.tri !== TriState.OPEN) continue;
        if (slotView.accepts.includes('protagonist')) {
          const res = game.tryPlace('protagonist', beatView.id, slotView.id);
          if (res.ok) {
            placed = true;
            break;
          }
        }
      }
      if (placed) break;
    }
    if (placed) break;
  }
}

/**
 * W5 Greedy 走查（共 12 個 checkpoints：seq 0～11）：
 * seq 0: run_start
 * seq 1～4: D1 morning, afternoon, evening, night
 * seq 5～8: D2 morning, afternoon, evening, night
 * seq 9～11: D3 morning, afternoon, evening (停在 D3 evening 收尾，不推進過界)
 */
export function runGreedyW5(data: GameData): GreedyWalkResult {
  const game = createRunForTrace(data);
  const checkpoints: GreedyCheckpoint[] = [];
  let seq = 0;

  const recordCheckpoint = (label: string): void => {
    const snap = game.serialize();
    checkpoints.push({
      seq,
      label,
      day: snap.run.day,
      phase: snap.run.phase,
      state: snap,
    });
    seq += 1;
  };

  // seq 0: run_start (D1 morning 初態)
  recordCheckpoint('run_start');

  // 總共 11 個時段步數：D1 (4 steps) + D2 (4 steps) + D3 morning, afternoon, evening (3 steps) = 11 steps
  const totalPhaseSteps = 11;

  for (let step = 0; step < totalPhaseSteps; step += 1) {
    const current = game.getSnapshot();
    const { day, phase } = current.run;

    if (phase === 'morning' || phase === 'afternoon') {
      executeGreedyActionPhase(game);
    } else if (phase === 'evening') {
      const evRes = game.playEvening();
      if (!evRes.ok) {
        throw new Error(
          `[D${day} ${phase}] playEvening 失敗：${evRes.reason_code} (${evRes.reason_text})`,
        );
      }
    } else if (phase === 'night') {
      const beforeNf = game.getSnapshot();
      const nfRes = game.playNightFixed();
      if (!nfRes.ok) {
        throw new Error(
          `[D${day} ${phase}] playNightFixed 失敗：${nfRes.reason_code} (${nfRes.reason_text})`,
        );
      }
      assertNightFixedPlayback(beforeNf, game.getSnapshot(), data);
    }

    // 記錄該時段收尾 checkpoint (seq 1..11)
    recordCheckpoint('phase_end');

    // 若已是 D3 evening（最後一步），停止推進，不強制跨越開發界線
    if (step === totalPhaseSteps - 1) {
      break;
    }

    const advRes = game.advancePhase();
    if (!advRes.ok || !advRes.phase_advanced) {
      throw new Error(
        `[D${day} ${phase}] advancePhase 失敗：${advRes.reason_code} (${advRes.reason_text})`,
      );
    }
  }

  return { game, checkpoints };
}
