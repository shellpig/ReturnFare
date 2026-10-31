/**
 * ReturnFare Web — 封閉語彙鍵表（W2-A）。
 *
 * 供 W2-B lint 與 W3+ 條件／效果執行器共用。鍵與 Godot 來源的封閉集合
 * （ConditionEval.KNOWN_KEYS、EffectApply.KNOWN_KEYS、CARD_ENTRY_KEYS）同順序。
 */

export const CONDITION_OPERATORS = [
  'day',
  'day_at_least',
  'has_card',
  'has_knowledge',
  'switch',
  'switch_progress_at_least',
  'flag',
  'relation_at_least',
  'madness_at_least',
  'count_at_least',
  'not',
  'all',
  'any',
  'night_seen',
  'opening_choice',
  'ending_seen',
  'festival_proxy_is',
] as const;

export const EFFECT_KEYS = [
  'text',
  'gain',
  'lose',
  'switch',
  'switch_progress',
  'relation',
  'madness',
  'flag',
  'festival_proxy',
  'ending',
] as const;

export const CARD_ENTRY_KEYS = ['card', 'if', 'permanent'] as const;

export type ConditionOperator = typeof CONDITION_OPERATORS[number];
export type EffectKey = typeof EFFECT_KEYS[number];
export type CardEntryKey = typeof CARD_ENTRY_KEYS[number];

export function isConditionOperator(key: string): key is ConditionOperator {
  return CONDITION_OPERATORS.includes(key as ConditionOperator);
}

export function isEffectKey(key: string): key is EffectKey {
  return EFFECT_KEYS.includes(key as EffectKey);
}

export function isCardEntryKey(key: string): key is CardEntryKey {
  return CARD_ENTRY_KEYS.includes(key as CardEntryKey);
}
