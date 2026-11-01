/**
 * ReturnFare Web — 卡槽放置合法性檢查、預覽與候選卡片查詢（W5-B）。
 *
 * 對齊 Godot scripts/autoload/game_state.gd：
 * - _check_slot_state / _check_place
 * - placeable_cards / preview_slot
 * - has_any_legal_action / has_unseen_content
 */

import type { Beat, GameData, Slot } from '../data/types';
import { strings } from '../ui/strings';
import { hasCard } from './cards';
import { evalCondition } from './condition';
import { ACTION_PHASES, beatMatchesTime, cardBaseId } from './facts';
import { isResolvedNightBeat } from './night';
import {
  TriState,
  availableLocations,
  buildPanel,
  remainingActionsToday,
} from './panel';
import type { DeepReadonly, GameSnapshot, ReasonCode } from './state-types';

const REASON_LOCKED_FALLBACK = '（條件不足）';

/**
 * beat 在當前天與時段是否合法（對應 _is_beat_time_valid）。
 * 非夜間與夜間 fixed 看 when；夜間 non-fixed 只接受該地點當下解析選中的 primary／addons。
 */
export function isBeatTimeValid(
  beat: Beat,
  state: DeepReadonly<GameSnapshot> | GameSnapshot,
  data: GameData,
): boolean {
  if (state.run.phase !== 'night' || beat.fixed === true) {
    return beatMatchesTime(beat.when, state.run.day, state.run.phase);
  }
  return isResolvedNightBeat(state, beat, data);
}

/**
 * 只檢查槽當前三態與時間，不檢查傳入卡片。
 * _check_place() 與 preview_slot() 共用這段，確保灰槽理由一致。
 * 檢查順序固定：時間 -> beat condition -> beat requires -> slot condition ->
 *             slots_placed -> choices -> slot requires。
 */
export function checkSlotState(
  beat: Beat,
  slot: Slot,
  state: DeepReadonly<GameSnapshot> | GameSnapshot,
  data: GameData,
): { ok: boolean; reason_code: ReasonCode; reason_text: string } {
  const beatId = beat.id;
  const slotId = slot.id;

  // 1. time
  if (!isBeatTimeValid(beat, state, data)) {
    return { ok: false, reason_code: 'hidden', reason_text: '' };
  }

  // 2. beat condition
  if (!evalCondition(beat.condition, state as GameSnapshot, data)) {
    return { ok: false, reason_code: 'hidden', reason_text: '' };
  }

  // 3. beat requires
  if (!evalCondition(beat.requires, state as GameSnapshot, data)) {
    const text =
      typeof beat.reject_reason === 'string' && beat.reject_reason.length > 0
        ? beat.reject_reason
        : REASON_LOCKED_FALLBACK;
    return { ok: false, reason_code: 'locked', reason_text: text };
  }

  // 4. slot condition
  if (!evalCondition(slot.condition, state as GameSnapshot, data)) {
    return { ok: false, reason_code: 'hidden', reason_text: '' };
  }

  // 5. slot already placed
  const slotKey = `${beatId}::${slotId}`;
  if (state.run.slots_placed[slotKey] === true) {
    return { ok: false, reason_code: 'resolved', reason_text: '' };
  }

  // 6. choice group already resolved
  const choiceGroup =
    typeof slot.choice_group === 'string' ? slot.choice_group : '';
  if (choiceGroup.length > 0) {
    const groupKey = `${beatId}::${choiceGroup}`;
    if (state.run.choices[groupKey] !== undefined) {
      return { ok: false, reason_code: 'resolved', reason_text: '' };
    }
  }

  // 7. slot requires
  if (!evalCondition(slot.requires, state as GameSnapshot, data)) {
    const text =
      typeof slot.reject_reason === 'string' && slot.reject_reason.length > 0
        ? slot.reject_reason
        : REASON_LOCKED_FALLBACK;
    return { ok: false, reason_code: 'locked', reason_text: text };
  }

  return { ok: true, reason_code: '', reason_text: '' };
}

/**
 * 放置前共用判斷。try_place() 與 preview_slot() 必須走同一條規則。
 * 順序固定：持有 -> 時間與槽三態 -> accepts -> protagonist action_spent。
 */
export function checkPlace(
  cardId: string,
  beat: Beat,
  slot: Slot,
  state: DeepReadonly<GameSnapshot> | GameSnapshot,
  data: GameData,
): { ok: boolean; reason_code: ReasonCode; reason_text: string } {
  // 1. possession (exact instance ID in hand ∪ knowledge)
  if (cardId.length === 0 || !hasCard(state, cardId)) {
    return { ok: false, reason_code: 'not_held', reason_text: '' };
  }

  // 2. slot state & time
  const stateResult = checkSlotState(beat, slot, state, data);
  if (!stateResult.ok) {
    return stateResult;
  }

  // 3. accepts (type OR base ID, [] never accepted)
  const baseId = cardBaseId(cardId);
  const card = data.cardsById.get(baseId);
  const cardType = card?.type ?? '';
  const accepts = slot.accepts ?? [];
  if (!accepts.includes(baseId) && !accepts.includes(cardType)) {
    return { ok: false, reason_code: 'not_accepted', reason_text: '' };
  }

  // 4. protagonist action_spent
  const isProtagonist = cardType === 'protagonist';
  const inActionPhase = (ACTION_PHASES as readonly string[]).includes(
    state.run.phase,
  );
  if (isProtagonist && inActionPhase && state.run.action_spent) {
    return { ok: false, reason_code: 'action_spent', reason_text: '' };
  }

  // 5. madness indulgence soak / action check
  const isMadness = cardType === 'madness';
  if (isMadness) {
    if (slot.indulgence?.soak === true) {
      const soakCost = data.tuning.indulgence.soak_phase_cost;
      const remActions = remainingActionsToday(state);
      if (remActions < soakCost) {
        const lockReason =
          state.run.phase !== 'morning'
            ? strings.soakMorningOnly
            : strings.soakInsufficientActions;
        return { ok: false, reason_code: 'locked', reason_text: lockReason };
      }
    } else {
      if (inActionPhase && state.run.action_spent) {
        return { ok: false, reason_code: 'action_spent', reason_text: '' };
      }
    }
  }

  return { ok: true, reason_code: '', reason_text: '' };
}

/** 取得所有持有卡片與知識卡實例清單（hand ∪ meta.knowledge）。 */
export function heldCards(
  state: DeepReadonly<GameSnapshot> | GameSnapshot,
): readonly string[] {
  const result: string[] = [];
  for (let i = 0; i < state.run.hand.length; i += 1) {
    result.push(state.run.hand[i]);
  }
  const knowledgeKeys = Object.keys(state.meta.knowledge);
  for (let i = 0; i < knowledgeKeys.length; i += 1) {
    const kId = knowledgeKeys[i];
    if (state.meta.knowledge[kId] === true) {
      result.push(kId);
    }
  }
  return result;
}

/** 取得某個槽當前可放置的手牌或知識卡 id 列表。 */
export function placeableCards(
  state: DeepReadonly<GameSnapshot> | GameSnapshot,
  data: GameData,
  beatId: string,
  slotId: string,
): readonly string[] {
  const beat = data.beatsById.get(beatId);
  if (!beat) {
    return [];
  }
  const slot = (beat.slots ?? []).find((s) => s.id === slotId);
  if (!slot) {
    return [];
  }
  const candidates = heldCards(state);
  const result: string[] = [];
  for (let i = 0; i < candidates.length; i += 1) {
    const cardId = candidates[i];
    if (checkPlace(cardId, beat, slot, state, data).ok) {
      result.push(cardId);
    }
  }
  return result;
}

/** 右鍵預覽的規則層入口。純查詢，不結算任何效果。 */
export function previewSlot(
  state: DeepReadonly<GameSnapshot> | GameSnapshot,
  data: GameData,
  beatId: string,
  slotId: string,
): { cards: readonly string[]; reason: string } {
  const beat = data.beatsById.get(beatId);
  if (!beat) {
    return { cards: [], reason: 'unknown_beat' };
  }
  const slot = (beat.slots ?? []).find((s) => s.id === slotId);
  if (!slot) {
    return { cards: [], reason: 'unknown_slot' };
  }

  const stateResult = checkSlotState(beat, slot, state, data);
  if (!stateResult.ok) {
    const reason =
      stateResult.reason_text.length > 0
        ? stateResult.reason_text
        : stateResult.reason_code;
    return { cards: [], reason };
  }

  const cardsResult = placeableCards(state, data, beatId, slotId);
  if (cardsResult.length > 0) {
    return { cards: cardsResult, reason: '' };
  }

  // OPEN 槽沒有可用卡時仍維持唯讀空清單；若是 action_spent 等狀態，
  // 用同一個規則檢查取得理由，避免預覽與實放分岔。
  const candidates = heldCards(state);
  for (let i = 0; i < candidates.length; i += 1) {
    const cardId = candidates[i];
    const checkResult = checkPlace(cardId, beat, slot, state, data);
    if (!checkResult.ok) {
      const reason =
        checkResult.reason_text.length > 0
          ? checkResult.reason_text
          : checkResult.reason_code;
      if (reason.length > 0 && reason !== 'not_held') {
        return { cards: [], reason };
      }
    }
  }

  return { cards: [], reason: '' };
}

/** 當前時段是否仍有任一動作可做（合法卡放置或未結算選擇題）。純查詢，不推進時段。 */
export function hasAnyLegalAction(
  state: DeepReadonly<GameSnapshot> | GameSnapshot,
  data: GameData,
): boolean {
  const locations = availableLocations(state, data);
  for (let i = 0; i < locations.length; i += 1) {
    const locId = locations[i];
    const panel = buildPanel(locId, state, data);
    for (let b = 0; b < panel.beats.length; b += 1) {
      const beatView = panel.beats[b];
      if (beatView.tri !== TriState.OPEN) {
        continue;
      }
      for (let s = 0; s < beatView.slots.length; s += 1) {
        const slotView = beatView.slots[s];
        if (slotView.tri !== TriState.OPEN) {
          continue;
        }
        if (slotView.isChoice) {
          return true;
        }
        if (placeableCards(state, data, beatView.id, slotView.id).length > 0) {
          return true;
        }
      }
    }
  }
  return false;
}

/** 當前時段是否仍有尚未進入過的 OPEN beat。純查詢。 */
export function hasUnseenContent(
  state: DeepReadonly<GameSnapshot> | GameSnapshot,
  data: GameData,
): boolean {
  const locations = availableLocations(state, data);
  for (let i = 0; i < locations.length; i += 1) {
    const locId = locations[i];
    const panel = buildPanel(locId, state, data);
    for (let b = 0; b < panel.beats.length; b += 1) {
      const beatView = panel.beats[b];
      if (beatView.tri !== TriState.OPEN) {
        continue;
      }
      if (!beatView.id) {
        continue;
      }
      if (state.run.beats_entered[beatView.id] !== true) {
        return true;
      }
    }
  }
  return false;
}
