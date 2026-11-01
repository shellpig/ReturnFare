/**
 * ReturnFare Web — 效果預演與交易器（W5-B；W6 補齊未開放機制）。
 *
 * 對齊 Godot scripts/core/effect_apply.gd：
 * - 在獨立狀態複本（draft）上按固定順序預演：
 *   text → lose → gain → switch → switch_progress → relation → madness → flag → festival_proxy → ending
 * - W5 實作：text、lose、gain、switch、switch_progress、relation、flag。
 * - 遇到未實作效果鍵（madness、festival_proxy、ending）或未知鍵時，
 *   整筆交易回傳 ok: false（not_implemented 或 data_conflict），零半套狀態、零已收集文字。
 */

import type { Condition, Effect, GameData } from '../data/types';
import { EFFECT_KEYS } from '../data/vocabulary';
import { gainCard, hasCard, loseCard } from './cards';
import { cardBaseId } from './facts';
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

interface ProcessCardEntriesOptions {
  readonly kind: 'gain' | 'lose';
  readonly entries: unknown;
  readonly draft: GameSnapshot;
  readonly originalState: Readonly<GameSnapshot>;
  readonly data: GameData;
  readonly mutate: (
    cardId: string,
    permanent: boolean,
  ) => { ok: boolean; reason_code: ReasonCode; reason_text: string };
}

function processCardEntries(
  opts: ProcessCardEntriesOptions,
): EffectPlan | null {
  const { kind, entries, draft, originalState, data, mutate } = opts;
  if (!Array.isArray(entries)) {
    return rejectPlan(
      originalState,
      'data_conflict',
      `EffectApply: ${kind} 必須為陣列`,
    );
  }
  for (let i = 0; i < entries.length; i += 1) {
    const entry = entries[i];
    let cardId: string;
    let permanent = false;
    if (typeof entry === 'string') {
      if (entry.length === 0) {
        return rejectPlan(
          originalState,
          'data_conflict',
          `EffectApply: ${kind} 卡片 id 不得為空字串`,
        );
      }
      cardId = entry;
    } else if (isPlainObject(entry)) {
      const entryKeys = Object.keys(entry);
      for (let ek = 0; ek < entryKeys.length; ek += 1) {
        const eKey = entryKeys[ek];
        if (kind === 'gain' && eKey === 'permanent') {
          return rejectPlan(
            originalState,
            'data_conflict',
            'EffectApply: gain 項目不支援 permanent 欄位',
          );
        }
        if (
          eKey !== 'card' &&
          eKey !== 'if' &&
          (kind !== 'lose' || eKey !== 'permanent')
        ) {
          return rejectPlan(
            originalState,
            'data_conflict',
            `EffectApply: ${kind} 項目含未知鍵 '${eKey}'`,
          );
        }
      }
      if (typeof entry.card !== 'string' || entry.card.length === 0) {
        return rejectPlan(
          originalState,
          'data_conflict',
          `EffectApply: ${kind} 項目缺少有效 card 字串`,
        );
      }
      cardId = entry.card;
      if (
        kind === 'lose' &&
        'permanent' in entry &&
        entry.permanent !== undefined
      ) {
        if (typeof entry.permanent !== 'boolean') {
          return rejectPlan(
            originalState,
            'data_conflict',
            'EffectApply: permanent 必須為 boolean',
          );
        }
        permanent = entry.permanent;
      }
      if ('if' in entry && entry.if !== undefined) {
        let condPassed = false;
        try {
          condPassed = evalCondition(entry.if as Condition, draft, data);
        } catch (err) {
          if (err instanceof UnsupportedConditionError) {
            return rejectPlan(originalState, 'not_implemented', err.message);
          }
          if (err instanceof ConditionError) {
            return rejectPlan(originalState, 'data_conflict', err.message);
          }
          throw err;
        }
        if (!condPassed) {
          continue;
        }
      }
    } else {
      return rejectPlan(
        originalState,
        'data_conflict',
        `EffectApply: ${kind} 項目必須為字串或物件`,
      );
    }

    const res = mutate(cardId, permanent);
    if (!res.ok) {
      return rejectPlan(originalState, res.reason_code, res.reason_text);
    }
  }
  return null;
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

    // 2. lose
    if ('lose' in raw && raw.lose !== undefined) {
      const errPlan = processCardEntries({
        kind: 'lose',
        entries: raw.lose,
        draft,
        originalState: state,
        data,
        // 對齊 effect_apply.gd：lose_card 找不到卡只報資料錯，不中止效果；
        // 未持有的已知卡視為 no-op（永久失去的 meta 仍由 loseCard 處理）。
        mutate: (cid, perm) => {
          if (!hasCard(draft, cid) && data.cardsById.has(cardBaseId(cid))) {
            if (perm) {
              loseCard(draft, cid, data, perm);
            }
            return { ok: true, reason_code: '', reason_text: '' };
          }
          return loseCard(draft, cid, data, perm);
        },
      });
      if (errPlan !== null) {
        return errPlan;
      }
    }

    // 3. gain
    if ('gain' in raw && raw.gain !== undefined) {
      const errPlan = processCardEntries({
        kind: 'gain',
        entries: raw.gain,
        draft,
        originalState: state,
        data,
        mutate: (cid) => gainCard(draft, cid, data),
      });
      if (errPlan !== null) {
        return errPlan;
      }
    }

    // 4. switch
    if ('switch' in raw && raw.switch !== undefined) {
      if (typeof raw.switch !== 'string' || raw.switch.length === 0) {
        return rejectPlan(
          state,
          'data_conflict',
          'EffectApply: switch 必須為非空字串',
        );
      }
      draft.run.switches[raw.switch] = true;
    }

    // 5. switch_progress
    if ('switch_progress' in raw && raw.switch_progress !== undefined) {
      if (!isPlainObject(raw.switch_progress)) {
        return rejectPlan(
          state,
          'data_conflict',
          'EffectApply: switch_progress 必須為 Dictionary',
        );
      }
      const spEntries = Object.entries(raw.switch_progress);
      for (let sp = 0; sp < spEntries.length; sp += 1) {
        const [swId, n] = spEntries[sp];
        if (
          typeof swId !== 'string' ||
          swId.length === 0 ||
          typeof n !== 'number' ||
          !Number.isInteger(n)
        ) {
          return rejectPlan(
            state,
            'data_conflict',
            `EffectApply: switch_progress '${swId}' 值必須為整數`,
          );
        }
        draft.run.switch_progress[swId] =
          (draft.run.switch_progress[swId] ?? 0) + n;
      }
    }

    // 6. relation
    if ('relation' in raw && raw.relation !== undefined) {
      if (!isPlainObject(raw.relation)) {
        return rejectPlan(
          state,
          'data_conflict',
          'EffectApply: relation 必須為 Dictionary',
        );
      }
      const relKeys = Object.keys(raw.relation);
      for (let rk = 0; rk < relKeys.length; rk += 1) {
        const rKey = relKeys[rk];
        if (rKey !== 'npc' && rKey !== 'delta') {
          return rejectPlan(
            state,
            'data_conflict',
            `EffectApply: relation 含未知鍵 '${rKey}'`,
          );
        }
      }
      const npc = raw.relation.npc;
      const delta = raw.relation.delta;
      if (typeof npc !== 'string' || npc.length === 0) {
        return rejectPlan(
          state,
          'data_conflict',
          'EffectApply: relation 缺少有效 npc 字串',
        );
      }
      if (!data.npcsById.has(npc)) {
        return rejectPlan(
          state,
          'data_conflict',
          `EffectApply: 未知的 NPC id '${npc}'`,
        );
      }
      if (typeof delta !== 'number' || !Number.isInteger(delta)) {
        return rejectPlan(
          state,
          'data_conflict',
          'EffectApply: relation delta 必須為整數',
        );
      }
      draft.run.relations[npc] = (draft.run.relations[npc] ?? 0) + delta;
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

    // 10. ending（W6 接手實作執行；W5 契約驗證結構並回傳 not_implemented）
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
      return rejectPlan(
        state,
        'not_implemented',
        `EffectApply: ending 效果 ('${raw.ending}') 將於 W6 實作`,
      );
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
