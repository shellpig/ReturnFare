/**
 * ReturnFare Web — 完整條件求值器（W4-A）。
 *
 * 對齊 Godot scripts/core/condition_eval.gd 與 data/vocabulary.ts 的 17 個封閉運算子：
 * - null / undefined → true（僅頂層缺條件視為恆成立）
 * - 非單鍵物件（空物件、多鍵、非物件、未知運算子或參數型別不符）→ 拋出 ConditionError（對應 data_conflict）
 * - 完整支援：day、day_at_least、has_card、has_knowledge、switch、switch_progress_at_least、
 *   flag、relation_at_least、madness_at_least、night_seen、opening_choice、ending_seen、
 *   festival_proxy_is、count_at_least、not、all、any
 * - 純查詢、無副作用、不讀全域 Game、不從卡片 registry 存在推導為持有
 */

import type { Condition, GameData } from '../data/types';
import { isConditionOperator } from '../data/vocabulary';
import { hasCard, hasKnowledge } from './cards';
import type { DeepReadonly, GameSnapshot } from './state-types';

export class ConditionError extends Error {
  readonly reason_code = 'data_conflict' as const;

  constructor(message: string) {
    super(message);
    this.name = 'ConditionError';
  }
}

export class UnsupportedConditionError extends Error {
  readonly reason_code = 'not_implemented' as const;
  readonly operator: string;

  constructor(operator: string) {
    super(`ConditionEval: 運算子 '${operator}' 尚未實作`);
    this.name = 'UnsupportedConditionError';
    this.operator = operator;
  }
}

function isPlainObject(val: unknown): val is Record<string, unknown> {
  return typeof val === 'object' && val !== null && !Array.isArray(val);
}

export function hasSeenEnding(
  state: DeepReadonly<GameSnapshot>,
  endingId: string,
): boolean {
  if (!endingId) {
    return false;
  }
  return state.meta.ending_history.some((record) => record.ending_id === endingId);
}

export function hasSeenNightLocation(
  state: DeepReadonly<GameSnapshot>,
  locationId: string,
): boolean {
  if (!locationId) {
    return false;
  }
  return (
    Object.prototype.hasOwnProperty.call(
      state.meta.night_locations_seen,
      locationId,
    ) && state.meta.night_locations_seen[locationId] === true
  );
}

export function relationAtLeast(
  state: DeepReadonly<GameSnapshot>,
  npc: string,
  targetState: string,
  data: GameData,
): boolean {
  const rawThreshold = Object.prototype.hasOwnProperty.call(
    data.relationScale,
    targetState,
  )
    ? data.relationScale[targetState]
    : undefined;

  if (typeof rawThreshold !== 'number' || !Number.isInteger(rawThreshold)) {
    throw new ConditionError(
      `ConditionEval: relation_at_least 未知的關係狀態 '${targetState}'`,
    );
  }

  const currentRelation = Object.prototype.hasOwnProperty.call(
    state.run.relations,
    npc,
  )
    ? (state.run.relations[npc] ?? 0)
    : 0;

  return currentRelation >= rawThreshold;
}

function evalConditionNode(
  node: unknown,
  state: DeepReadonly<GameSnapshot>,
  data: GameData,
): boolean {
  if (!isPlainObject(node)) {
    throw new ConditionError('ConditionEval: 條件必須是單鍵物件');
  }

  const keys = Object.keys(node);
  if (keys.length !== 1) {
    throw new ConditionError(
      `ConditionEval: 條件物件必須恰好包含 1 個運算子鍵（實際為 ${keys.length} 個）`,
    );
  }

  const op = keys[0];
  if (!isConditionOperator(op)) {
    throw new ConditionError(`ConditionEval: 未知的條件運算子 '${op}'`);
  }

  const val = node[op];

  switch (op) {
    case 'day': {
      if (typeof val !== 'number' || !Number.isInteger(val)) {
        throw new ConditionError('ConditionEval: day 參數必須為整數');
      }
      return state.run.day === val;
    }

    case 'day_at_least': {
      if (typeof val !== 'number' || !Number.isInteger(val)) {
        throw new ConditionError('ConditionEval: day_at_least 參數必須為整數');
      }
      return state.run.day >= val;
    }

    case 'has_card': {
      if (typeof val !== 'string' || val.length === 0) {
        throw new ConditionError('ConditionEval: has_card 參數必須為非空字串');
      }
      return hasCard(state, val);
    }

    case 'has_knowledge': {
      if (typeof val !== 'string' || val.length === 0) {
        throw new ConditionError(
          'ConditionEval: has_knowledge 參數必須為非空字串',
        );
      }
      return hasKnowledge(state, val);
    }

    case 'switch': {
      if (typeof val !== 'string' || val.length === 0) {
        throw new ConditionError('ConditionEval: switch 參數必須為非空字串');
      }
      return (
        Object.prototype.hasOwnProperty.call(state.run.switches, val) &&
        state.run.switches[val] === true
      );
    }

    case 'switch_progress_at_least': {
      if (!isPlainObject(val)) {
        throw new ConditionError(
          'ConditionEval: switch_progress_at_least 參數必須為物件',
        );
      }
      const spKeys = Object.keys(val);
      if (
        spKeys.length !== 2 ||
        !spKeys.includes('switch') ||
        !spKeys.includes('n')
      ) {
        throw new ConditionError(
          'ConditionEval: switch_progress_at_least 參數必須僅包含 switch 與 n',
        );
      }
      const switchId = val.switch;
      const minProgress = val.n;
      if (
        typeof switchId !== 'string' ||
        switchId.length === 0 ||
        typeof minProgress !== 'number' ||
        !Number.isInteger(minProgress)
      ) {
        throw new ConditionError(
          'ConditionEval: switch_progress_at_least 的 switch 必須為非空字串且 n 必須為整數',
        );
      }
      const currentProgress = Object.prototype.hasOwnProperty.call(
        state.run.switch_progress,
        switchId,
      )
        ? (state.run.switch_progress[switchId] ?? 0)
        : 0;
      return currentProgress >= minProgress;
    }

    case 'flag': {
      if (typeof val !== 'string' || val.length === 0) {
        throw new ConditionError('ConditionEval: flag 參數必須為非空字串');
      }
      return (
        Object.prototype.hasOwnProperty.call(state.run.flags, val) &&
        state.run.flags[val] === true
      );
    }

    case 'relation_at_least': {
      if (!isPlainObject(val)) {
        throw new ConditionError(
          'ConditionEval: relation_at_least 參數必須為物件',
        );
      }
      const raKeys = Object.keys(val);
      if (
        raKeys.length !== 2 ||
        !raKeys.includes('npc') ||
        !raKeys.includes('state')
      ) {
        throw new ConditionError(
          'ConditionEval: relation_at_least 參數必須僅包含 npc 與 state',
        );
      }
      const npc = val.npc;
      const targetState = val.state;
      if (
        typeof npc !== 'string' ||
        npc.length === 0 ||
        typeof targetState !== 'string' ||
        targetState.length === 0
      ) {
        throw new ConditionError(
          'ConditionEval: relation_at_least 的 npc 與 state 必須為非空字串',
        );
      }
      return relationAtLeast(state, npc, targetState, data);
    }

    case 'madness_at_least': {
      if (typeof val !== 'number' || !Number.isInteger(val)) {
        throw new ConditionError(
          'ConditionEval: madness_at_least 參數必須為整數',
        );
      }
      const count = Object.keys(state.run.madness_clock).length;
      return count >= val;
    }

    case 'night_seen': {
      if (typeof val !== 'string' || val.length === 0) {
        throw new ConditionError('ConditionEval: night_seen 參數必須為非空字串');
      }
      return hasSeenNightLocation(state, val);
    }

    case 'opening_choice': {
      if (typeof val !== 'string' || val.length === 0) {
        throw new ConditionError(
          'ConditionEval: opening_choice 參數必須為非空字串',
        );
      }
      return (state.run.opening_choice_id ?? '') === val;
    }

    case 'ending_seen': {
      if (typeof val !== 'string' || val.length === 0) {
        throw new ConditionError('ConditionEval: ending_seen 參數必須為非空字串');
      }
      return hasSeenEnding(state, val);
    }

    case 'festival_proxy_is': {
      if (typeof val !== 'string' || val.length === 0) {
        throw new ConditionError(
          'ConditionEval: festival_proxy_is 參數必須為非空字串',
        );
      }
      return (state.run.selected_festival_proxy_npc ?? '') === val;
    }

    case 'count_at_least': {
      if (!isPlainObject(val)) {
        throw new ConditionError('ConditionEval: count_at_least 參數必須為物件');
      }
      const caKeys = Object.keys(val);
      if (
        caKeys.length !== 2 ||
        !caKeys.includes('n') ||
        !caKeys.includes('of')
      ) {
        throw new ConditionError(
          'ConditionEval: count_at_least 參數必須僅包含 n 與 of',
        );
      }
      const n = val.n;
      const ofList = val.of;
      if (
        typeof n !== 'number' ||
        !Number.isInteger(n) ||
        !Array.isArray(ofList)
      ) {
        throw new ConditionError(
          'ConditionEval: count_at_least 的 n 必須為整數且 of 必須為陣列',
        );
      }
      let count = 0;
      for (let i = 0; i < ofList.length; i += 1) {
        if (evalConditionNode(ofList[i], state, data)) {
          count += 1;
        }
      }
      return count >= n;
    }

    case 'not': {
      return !evalConditionNode(val, state, data);
    }

    case 'all': {
      if (!Array.isArray(val)) {
        throw new ConditionError('ConditionEval: all 參數必須為條件陣列');
      }
      let result = true;
      for (let i = 0; i < val.length; i += 1) {
        if (!evalConditionNode(val[i], state, data)) {
          result = false;
        }
      }
      return result;
    }

    case 'any': {
      if (!Array.isArray(val)) {
        throw new ConditionError('ConditionEval: any 參數必須為條件陣列');
      }
      let result = false;
      for (let i = 0; i < val.length; i += 1) {
        if (evalConditionNode(val[i], state, data)) {
          result = true;
        }
      }
      return result;
    }
  }
}

export function evalCondition(
  condition: Condition | null | undefined,
  state: DeepReadonly<GameSnapshot>,
  data: GameData,
): boolean {
  if (condition === null || condition === undefined) {
    return true;
  }
  return evalConditionNode(condition, state, data);
}
