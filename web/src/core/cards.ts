/**
 * ReturnFare Web — 手牌與知識卡操作（W3-B 初期子集；W5-A 完整實作）。
 *
 * 對齊 Godot scripts/autoload/game_state.gd 手牌區：
 * - hasCard(state, cardId)：hand ∪ meta.knowledge
 * - hasKnowledge(state, cardId)：meta.knowledge
 * - handSlotsUsed(state)：hand.length
 * - cardView(state, instanceId, data)：單張卡面／時計唯讀投影
 * - handView(state, data)：當前手牌清單投影
 * - knowledgeView(state, data)：當前知識清單投影（保持取得順序）
 * - gainCard(state, cardId, data)：
 *   - slotless:true → 寫入 meta.knowledge（冪等）
 *   - type === 'madness' → 新增實例 madness#N 並建立倒數（共用 madness.ts primitive；上限由呼叫端檢查）
 *   - 其餘佔格卡 → unique（已持有則 no-op），loop_persistent:true 同步寫入 meta.loop_persistent_item_ids，加入 run.hand
 * - loseCard(state, cardId, data, permanent)：
 *   - 主角卡不可丟棄（data_conflict，零副作用）
 *   - hand 實例或 knowledge 條目移除
 *   - loop_persistent 普通失去保留 meta，permanent 失去自 meta 移除（支援先普通後永久，多次永久冪等）
 *   - 查無卡片且非有效永久失去回傳 data_conflict（零副作用）
 */

import type { GameData } from '../data/types';
import { cardBaseId } from './facts';
import { gainMadnessCardOnDraft } from './madness';
import type {
  CardView,
  DeepReadonly,
  GameSnapshot,
  ReasonCode,
} from './state-types';

export type { CardView };

export interface CardOpResult {
  readonly ok: boolean;
  readonly reason_code: ReasonCode;
  readonly reason_text: string;
}

/** 持有檢查：hand ∪ meta.knowledge。 */
export function hasCard(
  state: DeepReadonly<GameSnapshot>,
  cardId: string,
): boolean {
  return (
    state.run.hand.includes(cardId) || state.meta.knowledge[cardId] === true
  );
}

/** 知識集合檢查：meta.knowledge。 */
export function hasKnowledge(
  state: DeepReadonly<GameSnapshot>,
  cardId: string,
): boolean {
  return state.meta.knowledge[cardId] === true;
}

/** 手牌佔格數（hand 內每個元素佔一格；knowledge 不算）。 */
export function handSlotsUsed(state: DeepReadonly<GameSnapshot>): number {
  return state.run.hand.length;
}

/** 手牌超載：佔格數超過 tuning.hand_size（對應 GameState.is_overloaded）。 */
export function isOverloaded(
  state: DeepReadonly<GameSnapshot>,
  data: GameData,
): boolean {
  return handSlotsUsed(state) > Number(data.tuning.hand_size);
}

/** 單張卡面或知識項目的唯讀投影。 */
export function cardView(
  state: DeepReadonly<GameSnapshot>,
  instanceId: string,
  data: GameData,
): CardView {
  const baseId = cardBaseId(instanceId);
  const card = data.cardsById.get(baseId);
  if (!card) {
    throw new Error(`cardView: 未知的卡片 id '${instanceId}'`);
  }
  const clock = state.run.madness_clock[instanceId];
  const view: CardView = {
    instanceId,
    baseId,
    type: card.type,
    name: card.name,
    text: card.text ?? '',
    ...(typeof clock === 'number' ? { countdown: clock } : {}),
  };
  return Object.freeze(view);
}

/** 當前手牌清單投影。 */
export function handView(
  state: DeepReadonly<GameSnapshot>,
  data: GameData,
): readonly CardView[] {
  return Object.freeze(state.run.hand.map((id) => cardView(state, id, data)));
}

/** 當前知識清單投影（保持 meta.knowledge 取得順序）。 */
export function knowledgeView(
  state: DeepReadonly<GameSnapshot>,
  data: GameData,
): readonly CardView[] {
  return Object.freeze(
    Object.keys(state.meta.knowledge)
      .filter((id) => state.meta.knowledge[id] === true)
      .map((id) => cardView(state, id, data)),
  );
}

/**
 * 取得卡片（在傳入的 state 或 draft 上直接變更）。
 * 支援 slotless 知識卡、一般佔格卡（含 protagonist、loop_persistent）與 madness 多實例；
 * madness 只發卡與建倒數，不檢查上限——上限由呼叫端以 madness.ts 的 madnessCapRequest 統一處理。
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
    gainMadnessCardOnDraft(state, data, cardId);
    return { ok: true, reason_code: '', reason_text: '' };
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
 * 丟棄卡片（W5-A 完整實作）。
 * 作用於 hand 與 meta.knowledge；主角卡拒絕移除。
 * permanent:true 同步從 meta.loop_persistent_item_ids 移除。
 */
export function loseCard(
  state: GameSnapshot,
  cardId: string,
  data: GameData,
  permanent = false,
): CardOpResult {
  const baseId = cardBaseId(cardId);
  const card = data.cardsById.get(baseId);
  if (!card) {
    return {
      ok: false,
      reason_code: 'data_conflict',
      reason_text: `loseCard: 未知的卡片 id '${cardId}'`,
    };
  }

  if (card.type === 'protagonist') {
    return {
      ok: false,
      reason_code: 'data_conflict',
      reason_text: 'loseCard: 不可丟棄主角卡',
    };
  }

  const breaksPersistence = permanent === true && card.loop_persistent === true;
  if (breaksPersistence) {
    delete state.meta.loop_persistent_item_ids[baseId];
  }

  const handIdx = state.run.hand.indexOf(cardId);
  if (handIdx >= 0) {
    state.run.hand.splice(handIdx, 1);
    if (card.type === 'madness') {
      delete state.run.madness_clock[cardId];
      state.run.madness_cards_cleared += 1;
    }
    return { ok: true, reason_code: '', reason_text: '' };
  }

  if (state.meta.knowledge[cardId] === true) {
    delete state.meta.knowledge[cardId];
    return { ok: true, reason_code: '', reason_text: '' };
  }

  if (breaksPersistence) {
    return { ok: true, reason_code: '', reason_text: '' };
  }

  return {
    ok: false,
    reason_code: 'data_conflict',
    reason_text: `loseCard: 卡片 '${cardId}' 不在手牌或知識中`,
  };
}
