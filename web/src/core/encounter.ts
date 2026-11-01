/**
 * ReturnFare Web — 遭遇系統純判斷與 View Model 處理（W6-D）。
 *
 * 對齊 Godot scripts/core/encounter.gd：
 * Encounter 模組不持有 runtime 狀態，所有狀態由 GameState.active_encounter 持有。
 * View Model 嚴格對齊 P4-D allowlist 契約，絕不外洩未到回合或 accepts 答案集合。
 */

import type { Encounter, GameData, Round, Response } from '../data/types';
import type {
  ActiveEncounterState,
  GameSnapshot,
} from './state-types';
import { cardBaseId } from './facts';

/** 遭遇候選卡片 View Model（對齊 P4-D 嚴格 allowlist） */
export interface EncounterCandidateView {
  readonly card_id: string;
  readonly base_id: string;
  readonly source: 'hand' | 'knowledge';
  readonly name: string;
  readonly submittable: boolean;
  readonly disabled_reason: string;
  readonly discardable: boolean;
}

/** 遭遇開場演出 View Model */
export interface EncounterIntroView {
  readonly stage: 'intro';
  readonly beat_id: string;
  readonly blocked_slots: number;
  readonly capacity: number;
  readonly available_slots: number;
}

/** 遭遇回合 View Model */
export interface EncounterRoundView {
  readonly stage: 'round';
  readonly beat_id: string;
  readonly round_id: string;
  readonly demand: string;
  readonly blocked_slots: number;
  readonly capacity: number;
  readonly available_slots: number;
  readonly can_escape: boolean;
  readonly escape_cost: number | null;
  readonly allow_discard: boolean;
  readonly candidates: readonly EncounterCandidateView[];
  readonly attempted_card_ids: readonly string[];
}

/** 遭遇 View Model（無遭遇時為空物件 `{}`） */
export type EncounterView =
  | EncounterIntroView
  | EncounterRoundView
  | Record<string, never>;

/** 取得特定回合定義 */
export function getRound(encounter: Encounter, roundId: string): Round | null {
  for (let i = 0; i < encounter.rounds.length; i += 1) {
    const r = encounter.rounds[i];
    if (r.id === roundId) {
      return r;
    }
  }
  return null;
}

/** 取得第一回合 ID */
export function getFirstRoundId(encounter: Encounter): string {
  if (encounter.rounds.length > 0) {
    return encounter.rounds[0].id;
  }
  return '';
}

/** 尋找命中之 response 分支（依資料順序搜尋） */
export function findMatchingResponse(
  round: Round,
  cardId: string,
  baseCardId: string,
): Response | null {
  for (let i = 0; i < round.responses.length; i += 1) {
    const resp = round.responses[i];
    if (resp.accepts.includes(cardId) || resp.accepts.includes(baseCardId)) {
      return resp;
    }
  }
  return null;
}

/** 檢查是否命中任一 response 分支 */
export function matchesAnyResponse(
  round: Round,
  cardId: string,
  baseCardId: string,
): boolean {
  return findMatchingResponse(round, cardId, baseCardId) !== null;
}

/**
 * 檢查是否有任何合法動作（卡片提交、丟棄、逃離）。
 * 對齊 scripts/core/encounter.gd has_legal_moves。
 */
export function hasLegalMoves(
  encounter: Encounter,
  round: Round,
  activeState: ActiveEncounterState,
  state: GameSnapshot,
  data: GameData,
): boolean {
  const attempted = activeState.attempted_card_ids ?? [];
  const fallback = round.fallback;
  const reqDiscardable = fallback?.requires_discardable === true;

  // 1. 檢查 hand ∪ knowledge 是否有未嘗試的合法提交卡
  for (let i = 0; i < state.run.hand.length; i += 1) {
    const cid = state.run.hand[i];
    const baseId = cardBaseId(cid);

    // 發狂卡不可提交
    if (baseId === 'madness') {
      continue;
    }
    // 同一 base card 本場只能嘗試一次
    if (attempted.includes(baseId)) {
      continue;
    }

    // 命中 response 恆為合法提交
    if (matchesAnyResponse(round, cid, baseId)) {
      return true;
    }

    // 未命中 response，檢查 fallback 規則
    const cardDef = data.cardsById.get(baseId);
    const isDiscardable = cardDef?.discardable === true;
    if (!reqDiscardable || isDiscardable) {
      return true;
    }
  }

  const knowledgeKeys = Object.keys(state.meta.knowledge);
  for (let i = 0; i < knowledgeKeys.length; i += 1) {
    const kid = knowledgeKeys[i];
    if (!state.meta.knowledge[kid]) {
      continue;
    }
    const baseId = kid;
    if (attempted.includes(baseId)) {
      continue;
    }
    if (matchesAnyResponse(round, kid, baseId)) {
      return true;
    }
    const cardDef = data.cardsById.get(baseId);
    const isDiscardable = cardDef?.discardable === true;
    if (!reqDiscardable || isDiscardable) {
      return true;
    }
  }

  // 2. 檢查是否可主動丟棄（allow_discard !== false 且手上有至少一張可丟棄的非發狂卡）
  if (encounter.allow_discard !== false) {
    for (let i = 0; i < state.run.hand.length; i += 1) {
      const cid = state.run.hand[i];
      const baseId = cardBaseId(cid);
      if (baseId === 'madness') {
        continue;
      }
      const cardDef = data.cardsById.get(baseId);
      if (cardDef?.discardable === true) {
        return true;
      }
    }
  }

  // 3. 檢查是否可逃離
  if (encounter.escape_cost !== null) {
    const escCost = encounter.escape_cost;
    if (escCost === 0) {
      return true;
    }
    let discardableCount = 0;
    for (let i = 0; i < state.run.hand.length; i += 1) {
      const cid = state.run.hand[i];
      const baseId = cardBaseId(cid);
      if (baseId === 'madness') {
        continue;
      }
      const cardDef = data.cardsById.get(baseId);
      if (cardDef?.discardable === true) {
        discardableCount += 1;
      }
    }
    if (discardableCount >= escCost) {
      return true;
    }
  }

  return false;
}

/**
 * 建立 View Model（供 UI 或測試走查，絕不外洩未到回合或 accepts 答案集合）。
 * 頂層與候選 key 採嚴格 allowlist 契約（對齊開發設計方針 P4-D）。
 */
export function buildEncounterView(
  encounter: Encounter,
  activeState: ActiveEncounterState,
  state: GameSnapshot,
  data: GameData,
): EncounterView {
  if (Object.keys(activeState).length === 0) {
    return {};
  }

  const stage = activeState.stage ?? 'intro';
  const beatId = activeState.beat_id ?? '';
  const blockedSlots = activeState.blocked_slots ?? 0;
  const handSize = Number(data.tuning.hand_size);
  const handLength = state.run.hand.length;
  const availableSlots = handSize - handLength - blockedSlots;

  if (stage === 'intro') {
    return {
      stage: 'intro',
      beat_id: beatId,
      blocked_slots: blockedSlots,
      capacity: handSize,
      available_slots: availableSlots,
    };
  }

  const roundId = activeState.round_id ?? '';
  const roundData = getRound(encounter, roundId);
  const attempted = activeState.attempted_card_ids ?? [];
  const fallback = roundData?.fallback;
  const reqDiscardable = fallback?.requires_discardable === true;

  const candidates: EncounterCandidateView[] = [];

  // Hand 卡片
  for (let i = 0; i < state.run.hand.length; i += 1) {
    const cid = state.run.hand[i];
    const baseId = cardBaseId(cid);
    const cardDef = data.cardsById.get(baseId);
    const isMadness = baseId === 'madness';
    const isAttempted = attempted.includes(baseId);
    const isDiscardable = cardDef?.discardable === true;
    let submittable = true;
    let disabledReason = '';

    if (isMadness) {
      submittable = false;
      disabledReason = 'madness_blocked';
    } else if (isAttempted) {
      submittable = false;
      disabledReason = 'already_attempted';
    } else if (reqDiscardable) {
      const matchesResp = roundData
        ? matchesAnyResponse(roundData, cid, baseId)
        : false;
      if (!matchesResp && !isDiscardable) {
        submittable = false;
        disabledReason = 'card_not_submittable';
      }
    }

    candidates.push({
      card_id: cid,
      base_id: baseId,
      source: 'hand',
      name: cardDef?.name ?? '',
      submittable,
      disabled_reason: disabledReason,
      discardable: isDiscardable,
    });
  }

  // Knowledge 卡片
  const knowledgeKeys = Object.keys(state.meta.knowledge);
  for (let i = 0; i < knowledgeKeys.length; i += 1) {
    const kid = knowledgeKeys[i];
    if (!state.meta.knowledge[kid]) {
      continue;
    }
    const baseId = kid;
    const cardDef = data.cardsById.get(baseId);
    const isAttempted = attempted.includes(baseId);
    const isDiscardable = cardDef?.discardable === true;
    let submittable = true;
    let disabledReason = '';

    if (isAttempted) {
      submittable = false;
      disabledReason = 'already_attempted';
    } else if (reqDiscardable) {
      const matchesResp = roundData
        ? matchesAnyResponse(roundData, kid, baseId)
        : false;
      if (!matchesResp && !isDiscardable) {
        submittable = false;
        disabledReason = 'card_not_submittable';
      }
    }

    candidates.push({
      card_id: kid,
      base_id: baseId,
      source: 'knowledge',
      name: cardDef?.name ?? '',
      submittable,
      disabled_reason: disabledReason,
      discardable: isDiscardable,
    });
  }

  const escCostVar = encounter.escape_cost;
  return {
    stage: 'round',
    beat_id: beatId,
    round_id: roundId,
    demand: roundData?.demand ?? '',
    blocked_slots: blockedSlots,
    capacity: handSize,
    available_slots: availableSlots,
    can_escape: escCostVar !== null,
    escape_cost: escCostVar,
    allow_discard: encounter.allow_discard !== false,
    candidates,
    attempted_card_ids: [...attempted],
  };
}
