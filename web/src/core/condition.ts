/**
 * ReturnFare Web — 條件求值器（W3-B 初期子集；W4-A 補齊全部 17 個運算子）。
 *
 * 對齊 Godot scripts/core/condition_eval.gd：
 * - null / undefined → true
 * - 非單鍵物件（空物件、多鍵、非物件）→ 拋出 ConditionError（對應 data_conflict）
 * - W3 支援：opening_choice、ending_seen
 * - 其餘運算子在 W3 明確拋出 UnsupportedConditionError（對應 not_implemented），絕不預設為 true
 */

import type { Condition, GameData } from '../data/types';
import type { GameSnapshot } from './state-types';

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
    super(`ConditionEval: 運算子 '${operator}' 尚未在 W3 實作（將於 W4-A 補齊）`);
    this.name = 'UnsupportedConditionError';
    this.operator = operator;
  }
}

export function hasSeenEnding(state: Readonly<GameSnapshot>, endingId: string): boolean {
  if (!endingId) {
    return false;
  }
  return state.meta.ending_history.some((record) => record.ending_id === endingId);
}

export function evalCondition(
  condition: Condition | null | undefined,
  state: Readonly<GameSnapshot>,
  _data: GameData,
): boolean {
  if (condition === null || condition === undefined) {
    return true;
  }

  if (typeof condition !== 'object' || Array.isArray(condition)) {
    throw new ConditionError('ConditionEval: 條件必須是單鍵物件');
  }

  const record = condition as Record<string, unknown>;
  const keys = Object.keys(record);
  if (keys.length !== 1) {
    throw new ConditionError(
      `ConditionEval: 條件物件必須恰好包含 1 個運算子鍵（實際為 ${keys.length} 個）`,
    );
  }

  const op = keys[0];
  const val = record[op];

  switch (op) {
    case 'opening_choice': {
      if (typeof val !== 'string' || val.length === 0) {
        throw new ConditionError('ConditionEval: opening_choice 參數必須為非空字串');
      }
      return (state.run.opening_choice_id ?? '') === val;
    }
    case 'ending_seen': {
      if (typeof val !== 'string' || val.length === 0) {
        throw new ConditionError('ConditionEval: ending_seen 參數必須為非空字串');
      }
      return hasSeenEnding(state, val);
    }
    default:
      throw new UnsupportedConditionError(op);
  }
}
