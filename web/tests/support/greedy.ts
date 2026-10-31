/**
 * ReturnFare Web — Greedy 走查輔助（W3-B 初期子集：seq 0～4；後續階段擴充至全輪）。
 *
 * 對齊 Godot tests/headless/playthrough_greedy.gd 的無開局走查基線：
 * - 使用 trace-entry.ts 的 createRunForTrace(data)
 * - 記錄 seq 0 (run_start) 與 D1 四個時段收尾 checkpoint (seq 1～4)，並推進至 D2 morning
 */

import type { GameData } from '../../src/data/types';
import { createRunForTrace } from '../../src/core/trace-entry';
import type { Game, GameSnapshot } from '../../src/core/state-types';

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
      const nfRes = game.playNightFixed();
      if (!nfRes.ok) {
        throw new Error(
          `[D${day} ${phase}] playNightFixed 失敗：${nfRes.reason_code} (${nfRes.reason_text})`,
        );
      }
      const afterNf = game.getSnapshot();
      const chosen = afterNf.run.night_location_chosen;
      if (chosen === '' || !afterNf.meta.night_locations_seen[chosen]) {
        throw new Error(
          `[D${day} ${phase}] night-layer fixed beat 強制到訪未生效（night_location_chosen='${chosen}'）`,
        );
      }
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
