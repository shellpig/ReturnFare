/**
 * ReturnFare Web — Greedy 走查輔助（W3-B: seq 0～4；W5-B: seq 0～11；W6-E2-3: seq 0～192 全程 45 天）。
 *
 * 對齊 Godot tests/headless/playthrough_greedy.gd 與 generate_greedy_trace.gd 的無開局走查基線：
 * - 使用 trace-entry.ts 的 createRunForTrace(data)
 * - W3: 記錄 seq 0 (run_start) 與 D1 四個時段收尾 checkpoint (seq 1～4)
 * - W5: 記錄 seq 0 (run_start) + D1/D2 四個時段收尾 (seq 1～8) + D3 morning/afternoon/evening (seq 9～11)
 * - W6-E2-3: 45 天完整走查 193 筆快照：
 *   - seq 0: run_start (D1 morning 初態)
 *   - seq 1～179: 179 個 phase_end（含 D45 afternoon 遭遇結算 auto-advance 使 seq 178/179 均為 evening）
 *   - seq 180: ending_started (D45 evening, mode='ending', page_index=0, page_revealed=false, ready_to_complete=false)
 *   - seq 181～191: 11 個 ending_step 逐頁 reveal/advance 序列 (2 * page_count - 1)
 *   - seq 192: opening_ready (completeEnding 後回到 D1 morning, mode='opening'，停在開局選擇)
 * - 夜間一律走 executeGreedyNightPhase（fixed → 查可進地點 → 進入），睡覺停拍由 advanceGreedyPhase 吸收
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

/** 這次 playNightFixed 是否實際播出了掛在 night-layer 地點上的 fixed beat（即強制到訪）。 */
function playedNightLayerFixed(
  before: DeepReadonly<GameSnapshot>,
  after: DeepReadonly<GameSnapshot>,
  data: GameData,
): boolean {
  return Object.keys(after.run.beats_entered).some((bid) => {
    if (!after.run.beats_entered[bid] || before.run.beats_entered[bid]) {
      return false;
    }
    const b = data.beatsById.get(bid);
    return (
      b?.fixed === true && data.locationsById.get(b.location)?.layer === 'night'
    );
  });
}

/**
 * 自動完整結算遭遇（對齊 Godot playthrough_greedy.gd solve_active_encounter_if_any，K-142）。
 * 依序嘗試：intro 確認 -> round 合法回應 -> 逃離 -> 主動丟棄。
 */
export function solveActiveEncounterIfAny(game: Game): void {
  let safetyCap = 25;
  while ('stage' in game.encounterView() && safetyCap > 0) {
    safetyCap -= 1;
    const view = game.encounterView();
    if (view.stage === 'intro') {
      const ackRes = game.acknowledgeEncounterIntro();
      if (!ackRes.ok) {
        break;
      }
      continue;
    } else if (view.stage === 'round') {
      let responded = false;
      for (const cand of view.candidates) {
        if (cand.submittable) {
          const res = game.respondToEncounter(cand.card_id);
          if (res.ok) {
            responded = true;
            break;
          }
        }
      }
      if (responded) {
        continue;
      }

      // 無法回應時嘗試逃離
      if (view.can_escape) {
        const escCost = view.escape_cost ?? 0;
        const discCards: string[] = [];
        for (const cand of view.candidates) {
          if (discCards.length === escCost) break;
          if (cand.source === 'hand' && cand.discardable) {
            discCards.push(cand.card_id);
            if (discCards.length === escCost) {
              break;
            }
          }
        }
        if (discCards.length === escCost) {
          const escRes = game.escapeEncounter(discCards);
          if (escRes.ok) {
            break;
          }
        }
      }

      // 無法逃離時嘗試主動丟棄
      if (view.allow_discard) {
        let discarded = false;
        for (const cand of view.candidates) {
          if (cand.source === 'hand' && cand.discardable) {
            const dRes = game.discardInEncounter(cand.card_id);
            if (dRes.ok) {
              discarded = true;
              break;
            }
          }
        }
        if (discarded) {
          continue;
        }
      }

      break;
    }
  }
  if ('stage' in game.encounterView()) {
    throw new Error('Greedy 遭遇未能結算，不得略過仍進行中的遭遇');
  }
}

/**
 * 夜間走法（對照 Godot playthrough_greedy.gd execute_night_phase）：
 * 1. 先 playNightFixed（fixed／遭遇）。
 * 2. 只有本次實際播出 night-layer fixed 並強制到訪，才套 chosen／seen 斷言，並確認沒有第二個可進地點；
 *    meta_once 已看而未播不佔名額，不靠日期特例略過。
 * 3. 其餘夜晚查正式夜間地點：優先未 seen 的收費 row，否則依來源順序第一個可進的，進入後播 OPEN beat。
 */
export function executeGreedyNightPhase(game: Game, data: GameData): void {
  const { day } = game.getSnapshot().run;
  const beforeNf = game.getSnapshot();
  const nfRes = game.playNightFixed();
  if (!nfRes.ok) {
    throw new Error(
      `[D${day} night] playNightFixed 失敗：${nfRes.reason_code} (${nfRes.reason_text})`,
    );
  }
  solveActiveEncounterIfAny(game);
  const afterNf = game.getSnapshot();
  const locationIds = game.availableLocations();

  if (playedNightLayerFixed(beforeNf, afterNf, data)) {
    assertNightFixedPlayback(beforeNf, afterNf, data);
    const second = locationIds.filter((id) => game.nightLocationSummary(id).can_enter);
    if (second.length > 0) {
      throw new Error(`[D${day} night] 強制到訪後仍有可進地點：${second.join(',')}`);
    }
    return;
  }

  const enterable = locationIds.filter((id) => game.nightLocationSummary(id).can_enter);
  const unseenPaid = enterable.find(
    (id) =>
      (data.locationsById.get(id)?.madness_cost ?? 0) > 0 &&
      !afterNf.meta.night_locations_seen[id],
  );
  const chosen = unseenPaid ?? enterable[0];
  if (chosen === undefined) {
    return;
  }
  const entry = game.enterNightLocation(chosen);
  if (!entry.ok) {
    throw new Error(`[D${day} night] enterNightLocation(${chosen}) 失敗：${entry.reason_code}`);
  }
  if (game.getSnapshot().flow.mode !== 'run') {
    return;
  }
  for (const beatView of game.buildPanel(chosen).beats) {
    if (beatView.tri !== TriState.OPEN) continue;
    const res = game.playBeat(beatView.id);
    if (!res.ok) {
      throw new Error(`playBeat 失敗：${beatView.id}: ${res.reason_text}`);
    }
  }
}

function executeGreedyEveningPhase(game: Game, day: number): void {
  const evRes = game.playEvening();
  if (!evRes.ok) {
    throw new Error(
      `[D${day} evening] playEvening 失敗：${evRes.reason_code} (${evRes.reason_text})`,
    );
  }
  if (day === 45) {
    if (game.hasCard('info_registry')) {
      const res = game.tryPlace('info_registry', 'd45_then', 'compare_registry');
      if (!res.ok) {
        throw new Error(
          `[D45 evening] tryPlace info_registry 失敗：${res.reason_code} (${res.reason_text})`,
        );
      }
    } else {
      const res = game.choose('d45_then', 'd45_coda', 'empty_handed');
      if (!res.ok) {
        throw new Error(
          `[D45 evening] choose empty_handed 失敗：${res.reason_code} (${res.reason_text})`,
        );
      }
    }
  }
}

/** 推進一個時段；夜間睡覺停拍（phase_advanced:false）時再按一次「進入隔天」。 */
function advanceGreedyPhase(game: Game, day: number, phase: string): void {
  solveActiveEncounterIfAny(game);
  let advRes = game.advancePhase();
  if (
    advRes.ok &&
    !advRes.phase_advanced &&
    (game.getPhaseView().night_advance === 'next_day' || game.getSnapshot().flow.mode === 'run')
  ) {
    advRes = game.advancePhase();
  }
  if (!advRes.ok || !advRes.phase_advanced) {
    throw new Error(
      `[D${day} ${phase}] advancePhase 失敗：${advRes.reason_code} (${advRes.reason_text})`,
    );
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
      executeGreedyNightPhase(game, data);
    }

    // 記錄該時段收尾（在 advancePhase 之前）
    recordCheckpoint('phase_end');

    advanceGreedyPhase(game, day, phase);
  }

  return { game, checkpoints };
}

function executeGreedyActionPhase(game: Game): void {
  if ('stage' in game.encounterView()) {
    solveActiveEncounterIfAny(game);
    return;
  }
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
 * 45 天完整貪心走查（W6-E2-3：193 個 checkpoints：seq 0～192）。
 *
 * 走查時序與觀測點（對齊 Godot playthrough_greedy.gd 與 generate_greedy_trace.gd）：
 * - seq 0: run_start (D1 morning 初態)
 * - seq 1～176: D1～D44 每天 4 個時段收尾 (176 phase_end)
 * - seq 177: D45 morning phase_end
 * - seq 178: D45 afternoon phase_end（因 D45 afternoon 遭遇結算 auto-advance 至 evening，採樣時 phase 為 evening）
 * - seq 179: D45 evening phase_end（執行 coda 選擇後、advancePhase 進結局前採樣）
 *   （合計 179 個 phase_end）
 * - seq 180: ending_started (D45 evening, mode='ending', page_index=0, page_revealed=false, ready_to_complete=false)
 * - seq 181～191: ending_step (共 2 * page_count - 1 = 11 步逐頁 reveal 與 advance)
 * - seq 192: opening_ready (completeEnding 後回到 D1 morning, mode='opening'，不自動開始下一輪)
 */
export function runGreedyFull(data: GameData): GreedyWalkResult {
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

  for (let d = 1; d <= 45; d += 1) {
    // 1. Morning
    const snapM = game.getSnapshot();
    if (snapM.run.day !== d || snapM.run.phase !== 'morning') {
      throw new Error(
        `時間同步錯誤 (morning): 預期第 ${d} 天 morning，實際第 ${snapM.run.day} 天 ${snapM.run.phase}`,
      );
    }
    executeGreedyActionPhase(game);
    recordCheckpoint('phase_end');
    const advM = game.advancePhase();
    if (!advM.ok || !advM.phase_advanced) {
      throw new Error(
        `[D${d} morning] advancePhase 失敗：${advM.reason_code} (${advM.reason_text})`,
      );
    }

    // 2. Afternoon
    const snapA = game.getSnapshot();
    if (snapA.run.day !== d || snapA.run.phase !== 'afternoon') {
      throw new Error(
        `時間同步錯誤 (afternoon): 預期第 ${d} 天 afternoon，實際第 ${snapA.run.day} 天 ${snapA.run.phase}`,
      );
    }
    executeGreedyActionPhase(game);
    recordCheckpoint('phase_end');
    if (game.getSnapshot().run.phase === 'afternoon') {
      const advA = game.advancePhase();
      if (!advA.ok || !advA.phase_advanced) {
        throw new Error(
          `[D${d} afternoon] advancePhase 失敗：${advA.reason_code} (${advA.reason_text})`,
        );
      }
    }

    // 3. Evening
    const snapE = game.getSnapshot();
    if (snapE.run.day !== d || snapE.run.phase !== 'evening') {
      throw new Error(
        `時間同步錯誤 (evening): 預期第 ${d} 天 evening，實際第 ${snapE.run.day} 天 ${snapE.run.phase}`,
      );
    }
    executeGreedyEveningPhase(game, d);
    recordCheckpoint('phase_end');
    const advE = game.advancePhase();
    if (!advE.ok) {
      throw new Error(
        `[D${d} evening] advancePhase 失敗：${advE.reason_code} (${advE.reason_text})`,
      );
    }

    if (d === 45) {
      break;
    }

    // 4. Night
    const snapN = game.getSnapshot();
    if (snapN.run.day !== d || snapN.run.phase !== 'night') {
      throw new Error(
        `時間同步錯誤 (night): 預期第 ${d} 天 night，實際第 ${snapN.run.day} 天 ${snapN.run.phase}`,
      );
    }
    executeGreedyNightPhase(game, data);
    recordCheckpoint('phase_end');
    advanceGreedyPhase(game, d, 'night');
  }

  // 結局走查
  let completedEnding = false;
  if (game.getSnapshot().flow.mode === 'ending') {
    recordCheckpoint('ending_started');
    let pageCap = 200;
    while (game.getSnapshot().flow.mode === 'ending' && pageCap > 0) {
      pageCap -= 1;
      const view = game.endingView();
      if (view.can_complete) {
        const completeRes = game.completeEnding();
        if (!completeRes.ok) {
          throw new Error(
            `completeEnding 失敗：${completeRes.reason_code} (${completeRes.reason_text})`,
          );
        }
        if (game.getSnapshot().flow.mode === 'opening') {
          recordCheckpoint('opening_ready');
          completedEnding = true;
        } else {
          throw new Error(
            `completeEnding 成功但 flow.mode 為 ${game.getSnapshot().flow.mode}，預期為 opening`,
          );
        }
        break;
      }
      if (!view.page_revealed) {
        const res = game.revealEndingPage();
        if (!res.ok) {
          throw new Error(
            `revealEndingPage 失敗：${res.reason_code} (${res.reason_text})`,
          );
        }
        recordCheckpoint('ending_step');
      } else {
        const res = game.advanceEndingPage();
        if (!res.ok) {
          throw new Error(
            `advanceEndingPage 失敗：${res.reason_code} (${res.reason_text})`,
          );
        }
        recordCheckpoint('ending_step');
      }
    }
    if (pageCap === 0) {
      throw new Error('ending 翻頁超過安全上限 200');
    }
  } else {
    throw new Error(
      `D45 推進後 flow.mode 為 ${game.getSnapshot().flow.mode}，預期為 ending`,
    );
  }

  if (!completedEnding || game.getSnapshot().flow.mode !== 'opening') {
    throw new Error(
      `runGreedyFull 異常終止：未完成 completeEnding 且未抵達 opening_ready (flow.mode=${game.getSnapshot().flow.mode})`,
    );
  }

  return { game, checkpoints };
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
      executeGreedyNightPhase(game, data);
    }

    // 記錄該時段收尾 checkpoint (seq 1..11)
    recordCheckpoint('phase_end');

    // 若已是 D3 evening（最後一步），停止推進，不強制跨越開發界線
    if (step === totalPhaseSteps - 1) {
      break;
    }

    advanceGreedyPhase(game, day, phase);
  }

  return { game, checkpoints };
}
