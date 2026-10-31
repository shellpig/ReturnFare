/**
 * ReturnFare Web — 效果預演與兩階段交易器（W3-B 初期子集；W5-B／W6 補齊完整 10 鍵）。
 *
 * 對齊 Godot scripts/core/effect_apply.gd：
 * - 在獨立狀態複本（draft）上按固定順序預演：
 *   text → lose → gain → switch → switch_progress → relation → madness → flag → festival_proxy → ending
 * - W3 實作：text、gain（字串與 { card, if }）、flag，以及 ending 請求攔截與驗證。
 * - 遇到未實作效果鍵（lose、switch、switch_progress、relation、madness、festival_proxy）或未知鍵時，
 *   整筆交易回傳 ok: false（not_implemented 或 data_conflict），零半套狀態、零已收集文字。
 */

import type { Condition, Effect, GameData } from '../data/types';
import { EFFECT_KEYS } from '../data/vocabulary';
import { gainCard } from './cards';
import { ConditionError, UnsupportedConditionError, evalCondition } from './condition';
import { cloneSnapshot } from './run-initialization';
import type { GameSnapshot, ReasonCode } from './state-types';

export interface EndingRequest {
  readonly ending_id: string;
  readonly source_id: string;
}

export interface EffectPlan {
  readonly ok: boolean;
  readonly reason_code: ReasonCode;
  readonly reason_text: string;
  readonly lines: readonly string[];
  readonly nextState: GameSnapshot;
  readonly endingRequest: EndingRequest | null;
}

const KNOWN_KEY_SET: ReadonlySet<string> = new Set(EFFECT_KEYS);

function isPlainObject(val: unknown): val is Record<string, unknown> {
  return typeof val === 'object' && val !== null && !Array.isArray(val);
}

function rejectPlan(
  originalState: Readonly<GameSnapshot>,
  reason_code: ReasonCode,
  reason_text: string,
): EffectPlan {
  return {
    ok: false,
    reason_code,
    reason_text,
    lines: [],
    nextState: cloneSnapshot(originalState),
    endingRequest: null,
  };
}

export function planEffects(
  blocks: readonly (Effect | Record<string, unknown> | null | undefined)[],
  state: Readonly<GameSnapshot>,
  data: GameData,
): EffectPlan {
  const draft = cloneSnapshot(state);
  const lines: string[] = [];
  let endingRequest: EndingRequest | null = null;

  for (let i = 0; i < blocks.length; i += 1) {
    const raw = blocks[i];
    if (raw === null || raw === undefined) {
      continue;
    }
    if (!isPlainObject(raw)) {
      return rejectPlan(state, 'data_conflict', 'EffectApply: 效果區塊必須為物件');
    }

    const keys = Object.keys(raw);
    for (let k = 0; k < keys.length; k += 1) {
      const key = keys[k];
      if (!KNOWN_KEY_SET.has(key)) {
        return rejectPlan(
          state,
          'data_conflict',
          `EffectApply: 未知的效果鍵 '${key}'`,
        );
      }
    }

    // 1. text
    if ('text' in raw && raw.text !== undefined) {
      if (typeof raw.text !== 'string') {
        return rejectPlan(state, 'data_conflict', 'EffectApply: text 必須為字串');
      }
      if (raw.text.length > 0) {
        lines.push(raw.text);
      }
    }

    // 2. lose（W5-B 接手）
    if ('lose' in raw && raw.lose !== undefined) {
      return rejectPlan(
        state,
        'not_implemented',
        'EffectApply: lose 效果將於 W5-B 實作',
      );
    }

    // 3. gain
    if ('gain' in raw && raw.gain !== undefined) {
      if (!Array.isArray(raw.gain)) {
        return rejectPlan(state, 'data_conflict', 'EffectApply: gain 必須為陣列');
      }
      for (let g = 0; g < raw.gain.length; g += 1) {
        const entry = raw.gain[g];
        if (typeof entry === 'string') {
          if (entry.length === 0) {
            return rejectPlan(
              state,
              'data_conflict',
              'EffectApply: gain 卡片 id 不得為空字串',
            );
          }
          const res = gainCard(draft, entry, data);
          if (!res.ok) {
            return rejectPlan(state, res.reason_code, res.reason_text);
          }
        } else if (isPlainObject(entry)) {
          const entryKeys = Object.keys(entry);
          for (let ek = 0; ek < entryKeys.length; ek += 1) {
            const eKey = entryKeys[ek];
            if (eKey === 'permanent') {
              return rejectPlan(
                state,
                'data_conflict',
                'EffectApply: gain 項目不支援 permanent 欄位',
              );
            }
            if (eKey !== 'card' && eKey !== 'if') {
              return rejectPlan(
                state,
                'data_conflict',
                `EffectApply: gain 項目含未知鍵 '${eKey}'`,
              );
            }
          }
          const cardId = entry.card;
          if (typeof cardId !== 'string' || cardId.length === 0) {
            return rejectPlan(
              state,
              'data_conflict',
              'EffectApply: gain 項目缺少有效 card 字串',
            );
          }
          if ('if' in entry && entry.if !== undefined) {
            let condPassed = false;
            try {
              condPassed = evalCondition(entry.if as Condition, draft, data);
            } catch (err) {
              if (err instanceof UnsupportedConditionError) {
                return rejectPlan(state, 'not_implemented', err.message);
              }
              if (err instanceof ConditionError) {
                return rejectPlan(state, 'data_conflict', err.message);
              }
              throw err;
            }
            if (!condPassed) {
              continue;
            }
          }
          const res = gainCard(draft, cardId, data);
          if (!res.ok) {
            return rejectPlan(state, res.reason_code, res.reason_text);
          }
        } else {
          return rejectPlan(
            state,
            'data_conflict',
            'EffectApply: gain 項目必須為字串或物件',
          );
        }
      }
    }

    // 4. switch（W5-B 接手）
    if ('switch' in raw && raw.switch !== undefined) {
      return rejectPlan(
        state,
        'not_implemented',
        'EffectApply: switch 效果將於 W5-B 實作',
      );
    }

    // 5. switch_progress（W5-B 接手）
    if ('switch_progress' in raw && raw.switch_progress !== undefined) {
      return rejectPlan(
        state,
        'not_implemented',
        'EffectApply: switch_progress 效果將於 W5-B 實作',
      );
    }

    // 6. relation（W5-B 接手）
    if ('relation' in raw && raw.relation !== undefined) {
      return rejectPlan(
        state,
        'not_implemented',
        'EffectApply: relation 效果將於 W5-B 實作',
      );
    }

    // 7. madness（W6 接手）
    if ('madness' in raw && raw.madness !== undefined) {
      return rejectPlan(
        state,
        'not_implemented',
        'EffectApply: madness 效果將於 W6 實作',
      );
    }

    // 8. flag
    if ('flag' in raw && raw.flag !== undefined) {
      const fVal = raw.flag;
      if (!isPlainObject(fVal)) {
        return rejectPlan(
          state,
          'data_conflict',
          'EffectApply: flag 必須為 Dictionary',
        );
      }
      const fKeys = Object.keys(fVal);
      for (let fk = 0; fk < fKeys.length; fk += 1) {
        const flagName = fKeys[fk];
        const flagBool = fVal[flagName];
        if (flagName.length === 0 || typeof flagBool !== 'boolean') {
          return rejectPlan(
            state,
            'data_conflict',
            `EffectApply: flag '${flagName}' 值必須為 boolean`,
          );
        }
        draft.run.flags[flagName] = flagBool;
      }
    }

    // 9. festival_proxy（W6-E2 接手）
    if ('festival_proxy' in raw && raw.festival_proxy !== undefined) {
      return rejectPlan(
        state,
        'not_implemented',
        'EffectApply: festival_proxy 效果將於 W6-E2 實作',
      );
    }

    // 10. ending
    if ('ending' in raw && raw.ending !== undefined) {
      if (typeof raw.ending !== 'string' || raw.ending.length === 0) {
        return rejectPlan(
          state,
          'data_conflict',
          'EffectApply: ending 必須為非空字串',
        );
      }
      if (!data.endingsById.has(raw.ending)) {
        return rejectPlan(
          state,
          'unknown_ending',
          `EffectApply: 未知的結局 id '${raw.ending}'`,
        );
      }
      if (
        endingRequest !== null &&
        (endingRequest.ending_id !== raw.ending ||
          endingRequest.source_id !== 'ending_effect')
      ) {
        return rejectPlan(
          state,
          'data_conflict',
          'EffectApply: 同一批效果含衝突的結局請求',
        );
      }
      endingRequest = {
        ending_id: raw.ending,
        source_id: 'ending_effect',
      };
    }
  }

  return {
    ok: true,
    reason_code: '',
    reason_text: '',
    lines,
    nextState: draft,
    endingRequest,
  };
}
