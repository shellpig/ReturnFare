/**
 * ReturnFare Web — 開輪初始化與快照工具（W3-B）。
 *
 * 對齊 Godot scripts/autoload/game_state.gd 的 _reset_run_state() 與 _apply_run_initialization()：
 * 供 chooseOpening 的 on_select 分支與 trace-entry.ts 共用。
 */

import type { GameData } from '../data/types';
import { gainCard } from './cards';
import type { DeepReadonly, GameSnapshot, RunState } from './state-types';

/** 建立乾淨的單輪（run 層）初值，不放入 protagonist 卡。 */
export function createEmptyRunState(): RunState {
  return {
    day: 1,
    phase: 'morning',
    opening_choice_id: null,
    knowledge_at_start: {},
    selected_festival_proxy_npc: null,
    action_spent: false,
    actions_spent_ahead: 0,
    hand: [],
    madness_clock: {},
    _madness_counter: 0,
    beats_entered: {},
    slots_placed: {},
    choices: {},
    flags: {},
    switches: {},
    switch_progress: {},
    relations: {},
    npc_action_counts: {},
    night_location_chosen: '',
    night_sleep_pending: false,
    indulgence_count: 0,
    madness_cards_cleared: 0,
    forced_pending: [],
    delegates_used_today: {},
    pending_delegation_reports: [],
    active_encounter: {},
  };
}

/** 建立開局前（fresh boot）的完整初值快照。 */
export function createInitialSnapshot(): GameSnapshot {
  return {
    flow: {
      mode: 'opening',
      active_ending: null,
    },
    run: createEmptyRunState(),
    meta: {
      knowledge: {},
      night_locations_seen: {},
      night_once_beats_seen: {},
      day_locations_visited: {},
      delegation_tutorial_seen: false,
      run_number: 1,
      ending_history: [],
      loop_persistent_item_ids: {},
    },
  };
}

/** 深拷貝 GameSnapshot，確保呼叫端修改回傳值不會污染 store 內部狀態。 */
export function cloneSnapshot(state: Readonly<GameSnapshot>): GameSnapshot {
  return structuredClone(state as GameSnapshot);
}

/** 遞迴凍結物件／陣列，確保 getSnapshot() 的巢狀欄位不可被外部直接改動。 */
export function deepFreeze<T>(obj: T): DeepReadonly<T> {
  if (obj === null || typeof obj !== 'object') {
    return obj as DeepReadonly<T>;
  }
  if (Object.isFrozen(obj)) {
    return obj as DeepReadonly<T>;
  }
  Object.freeze(obj);
  if (Array.isArray(obj)) {
    for (let i = 0; i < obj.length; i += 1) {
      deepFreeze(obj[i]);
    }
  } else {
    const record = obj as Record<string, unknown>;
    const keys = Object.keys(record);
    for (let i = 0; i < keys.length; i += 1) {
      deepFreeze(record[keys[i]]);
    }
  }
  return obj as DeepReadonly<T>;
}

/**
 * 執行單輪初始化（純函式，回傳新的 GameSnapshot 複本）：
 * 1. 重置 run 全部欄位（保留 meta）
 * 2. 放入 protagonist 卡（恆在 hand[0]）
 * 3. 按 data.cards 順序恢復 meta.loop_persistent_item_ids 中的跨輪物品
 * 4. 將 meta.knowledge 複製凍結為 run.knowledge_at_start
 */
export function initializeRun(
  state: Readonly<GameSnapshot>,
  data: GameData,
): GameSnapshot {
  const next = cloneSnapshot(state);
  next.run = createEmptyRunState();

  gainCard(next, 'protagonist', data);

  for (const card of data.cards) {
    if (next.meta.loop_persistent_item_ids[card.id]) {
      gainCard(next, card.id, data);
    }
  }

  next.run.knowledge_at_start = { ...next.meta.knowledge };
  return next;
}
