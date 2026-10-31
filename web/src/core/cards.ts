/**
 * ReturnFare Web — 手牌與知識卡操作（W3-B 初期子集；W5-A／W6-A 擴充）。
 *
 * 對齊 Godot scripts/autoload/game_state.gd 手牌區：
 * - hasCard(state, cardId)：hand ∪ meta.knowledge
 * - hasKnowledge(state, cardId)：meta.knowledge
 * - handSlotsUsed(state)：hand.length
 * - gainCard(state, cardId, data)：
 *   - slotless:true → 寫入 meta.knowledge（冪等）
 *   - type === 'madness' → W6 接手（W3 回傳 not_implemented）
 *   - 其餘佔格卡 → unique（已持有則 no-op），loop_persistent:true 同步寫入 meta.loop_persistent_item_ids，加入 run.hand
 */

import type { GameData } from '../data/types';
import { cardBaseId } from './facts';
import type { GameSnapshot, ReasonCode } from './state-types';

export interface CardOpResult {
  readonly ok: boolean;
  readonly reason_code: ReasonCode;
  readonly reason_text: string;
}

/** 持有檢查：hand ∪ meta.knowledge。 */
export function hasCard(state: Readonly<GameSnapshot>, cardId: string): boolean {
  return state.run.hand.includes(cardId) || Boolean(state.meta.knowledge[cardId]);
}

/** 知識集合檢查：meta.knowledge。 */
export function hasKnowledge(state: Readonly<GameSnapshot>, cardId: string): boolean {
  return Boolean(state.meta.knowledge[cardId]);
}

/** 手牌佔格數（hand 內每個元素佔一格；knowledge 不算）。 */
export function handSlotsUsed(state: Readonly<GameSnapshot>): number {
  return state.run.hand.length;
}

/**
 * 取得卡片（在傳入的 state 或 draft 上直接變更）。
 * W3 支援 slotless 知識卡與一般佔格卡（含 protagonist、loop_persistent）；
 * madness 多實例與倒數／上限由 W6 接手。
 */
export function gainCard(
  state: GameSnapshot,
  cardId: string,
  data: GameData,
): CardOpResult {
  const card = data.cardsById.get(cardId);
  if (!card) {
    return {
      ok: false,
      reason_code: 'data_conflict',
      reason_text: `gainCard: 未知的卡片 id '${cardId}'`,
    };
  }

  if (card.slotless === true) {
    if (!state.meta.knowledge[cardId]) {
      state.meta.knowledge[cardId] = true;
    }
    return { ok: true, reason_code: '', reason_text: '' };
  }

  if (card.type === 'madness') {
    return {
      ok: false,
      reason_code: 'not_implemented',
      reason_text: 'madness 實例與倒數計時將於 W6 實作',
    };
  }

  // 其餘佔格卡：unique（已在 hand 或 knowledge 內即為冪等 no-op）
  if (hasCard(state, cardId)) {
    return { ok: true, reason_code: '', reason_text: '' };
  }

  if (card.loop_persistent === true) {
    state.meta.loop_persistent_item_ids[cardId] = true;
  }

  if (card.type === 'protagonist') {
    state.run.hand.unshift(cardId);
  } else {
    state.run.hand.push(cardId);
  }

  return { ok: true, reason_code: '', reason_text: '' };
}

/**
 * 丟棄卡片（W5-A 正式接手；W3 保留拒絕主角卡與未實作守衛）。
 */
export function loseCard(
  _state: GameSnapshot,
  cardId: string,
  data: GameData,
  _permanent = false,
): CardOpResult {
  const baseId = cardBaseId(cardId);
  const card = data.cardsById.get(baseId);
  if (card?.type === 'protagonist') {
    return {
      ok: false,
      reason_code: 'data_conflict',
      reason_text: 'loseCard: 不可丟棄主角卡',
    };
  }
  return {
    ok: false,
    reason_code: 'not_implemented',
    reason_text: 'loseCard 將於 W5-A 實作',
  };
}
