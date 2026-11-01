/**
 * ReturnFare Web — 發狂卡時鐘與上限（W6-A）。
 *
 * 對齊 Godot scripts/autoload/game_state.gd：gain_card（madness 分支）、tick_madness、
 * _check_madness_cap、would_night_entry_end_run 的數卡部分。
 *
 * 所有發狂來源（夜間標記收費、madness 效果、直接 gain madness）共用同一個發卡 primitive，
 * 讓實例編號與 madness_clock 永遠同步。這裡的函式都直接改傳入的 draft，原子性由呼叫端的 draft 提交負責。
 * 本檔不 import cards／effect／ending，避免循環依賴；上限只產出結局請求，啟動留給呼叫端。
 */

import type { GameData } from '../data/types';
import { cardBaseId } from './facts';
import type { DeepReadonly, GameSnapshot } from './state-types';

/** 發狂卡的 cards.json id（唯一的多實例卡，實例 id 為 `madness#N`）。 */
export const MADNESS_CARD_ID = 'madness';

/** 撞發狂上限的結局與來源；配對由 ending.ts 的 ENDING_SOURCE_PAIRS 驗證。 */
export const MADNESS_CAP_ENDING_ID = 'ending_madness_be';
export const MADNESS_CAP_SOURCE_ID = 'madness_cap';

export interface MadnessCapRequest {
  readonly ending_id: string;
  readonly source_id: string;
}

/** 手牌上的發狂卡實例數（cap 的唯一計法；視野門檻另以 madness_clock 計，與 Godot 相同）。 */
export function madnessCardCount(state: DeepReadonly<GameSnapshot>): number {
  let count = 0;
  for (let i = 0; i < state.run.hand.length; i += 1) {
    if (cardBaseId(state.run.hand[i]) === MADNESS_CARD_ID) {
      count += 1;
    }
  }
  return count;
}

/** 在 draft 上新增一張發狂卡實例並建立滿值倒數，回傳實例 id。不檢查上限。 */
export function gainMadnessCardOnDraft(
  draft: GameSnapshot,
  data: GameData,
  cardId: string = MADNESS_CARD_ID,
): string {
  draft.run._madness_counter += 1;
  const instanceId = `${cardId}#${draft.run._madness_counter}`;
  draft.run.hand.push(instanceId);
  draft.run.madness_clock[instanceId] = Number(data.tuning.madness_countdown_days);
  return instanceId;
}

/** 手牌發狂卡實例數已達 madness_cap 時回傳結局請求，否則 null。cap ≤ 0 視為未啟用。 */
export function madnessCapRequest(
  state: DeepReadonly<GameSnapshot>,
  data: GameData,
): MadnessCapRequest | null {
  const cap = Number(data.tuning.madness_cap);
  if (!(cap > 0)) {
    return null;
  }
  if (madnessCardCount(state) < cap) {
    return null;
  }
  return { ending_id: MADNESS_CAP_ENDING_ID, source_id: MADNESS_CAP_SOURCE_ID };
}

/** 純查詢：再多拿 extraCards 張發狂卡是否會到達上限（would_night_entry_end_run 的數卡）。 */
export function wouldReachMadnessCap(
  state: DeepReadonly<GameSnapshot>,
  extraCards: number,
  data: GameData,
): boolean {
  const cap = Number(data.tuning.madness_cap);
  if (!(cap > 0) || extraCards <= 0) {
    return false;
  }
  return madnessCardCount(state) + extraCards >= cap;
}

/**
 * 每日進 morning 時全體倒數 −1；回傳這次歸零的實例 id（依 madness_clock 鍵序）。
 * 已歸零（≤ 0）的卡 clamp 在 0，不重複回報；不碰 forced_pending，由換日轉換負責入列。
 */
export function tickMadnessOnDraft(draft: GameSnapshot): string[] {
  const zeroed: string[] = [];
  const clock = draft.run.madness_clock;
  const ids = Object.keys(clock);
  for (let i = 0; i < ids.length; i += 1) {
    const id = ids[i];
    const current = clock[id];
    if (current > 0) {
      clock[id] = current - 1;
      if (current - 1 === 0) {
        zeroed.push(id);
      }
    } else {
      clock[id] = 0;
    }
  }
  return zeroed;
}
