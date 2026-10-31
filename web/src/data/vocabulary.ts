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

export const CARD_TYPE_IDS = [
  'protagonist',
  'person',
  'group',
  'equipment',
  'consumable',
  'info',
  'inference',
  'document',
  'knowledge',
  'mood',
  'madness',
  'routine',
] as const;

export const LEGAL_NARRATIVE_BEAT_TAGS = [
  'observable_exit_sanquan',
  'reveals_replacement_truth',
  'marriage',
  'no_marriage',
  'no_children',
  'twenty_years',
  'single_twenty_years',
  'spouse_dies_first',
  'protagonist_same_illness',
  'protagonist_dies_early_forties',
  'switch_subject_to_protagonist',
  'proxy_reminisce',
  'died_early_forties',
  'died_of_cancer',
  'died_rapidly',
  'black_screen',
  'blessing_reactivated',
  'outside_ordinary_life',
  'refuse_boarding_summary',
] as const;

export const LEGAL_REJECT_REASON_TAGS = [
  'prev_trail',
  'route_knowledge_1',
  'route_knowledge_2',
  'three_points',
] as const;

export const REQUIRED_TUNING_KEYS = [
  'hand_size',
  'phases_per_day',
  'madness_cap',
  'madness_countdown_days',
  'madness_vision_threshold',
  'indulgence.soak_phase_cost',
  'indulgence.soak_cards_cleared',
  'indulgence.forced_light_count',
  'indulgence.forced_normal_until',
] as const;

export const INDULGENCE_LEVEL_KEYS = ['light', 'normal', 'heavy'] as const;

export const EXPECTED_ENDING_IDS = [
  'ending_replaced',
  'ending_madness_be',
  'ending_inventory_be',
  'ending_refuse_boarding',
] as const;

export const EXPECTED_OPENING_CHOICE_IDS = [
  'take_family_album',
  'return_missed_call',
  'refuse_boarding',
] as const;

export type ConditionOperator = typeof CONDITION_OPERATORS[number];
export type EffectKey = typeof EFFECT_KEYS[number];
export type CardEntryKey = typeof CARD_ENTRY_KEYS[number];
export type NarrativeBeatTag = typeof LEGAL_NARRATIVE_BEAT_TAGS[number];
export type RejectReasonTag = typeof LEGAL_REJECT_REASON_TAGS[number];
export type RequiredTuningKey = typeof REQUIRED_TUNING_KEYS[number];

export function isConditionOperator(key: string): key is ConditionOperator {
  return CONDITION_OPERATORS.includes(key as ConditionOperator);
}

export function isEffectKey(key: string): key is EffectKey {
  return EFFECT_KEYS.includes(key as EffectKey);
}

export function isCardEntryKey(key: string): key is CardEntryKey {
  return CARD_ENTRY_KEYS.includes(key as CardEntryKey);
}

