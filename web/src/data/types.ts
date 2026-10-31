/**
 * ReturnFare Web — 資料內容型別（W2-A）。
 *
 * 描述 `data/` JSON 載入後的收窄目標。JSON 邊界以 unknown 進入 loader，
 * 再收窄到本型別；絕不以 Record<string, unknown> 代替整份 schema。
 *
 * `note` 欄位可保留於資料物件，之後的 UI view model 不會將其傳給玩家。
 * 這裡只描述資料形狀，不執行任何規則（條件求值／效果結算屬 W3+）。
 */

/** 時段：白天三時段 + 夜間。固定清單，不以 tuning.phases_per_day 為自由參數。 */
export type Phase = 'morning' | 'afternoon' | 'evening' | 'night';
export type ActionPhase = 'morning' | 'afternoon';

export const PHASES: readonly Phase[] = ['morning', 'afternoon', 'evening', 'night'];
export const ACTION_PHASES: readonly ActionPhase[] = ['morning', 'afternoon'];

/** card_types.json 的型別鍵（對應 DataLoader.CARD_TYPES 的封閉清單）。 */
export type CardTypeId =
  | 'protagonist'
  | 'person'
  | 'group'
  | 'equipment'
  | 'consumable'
  | 'info'
  | 'inference'
  | 'document'
  | 'knowledge'
  | 'mood'
  | 'madness'
  | 'routine';

export interface CardType {
  readonly id: CardTypeId;
  readonly name: string;
  readonly note?: string;
}

export interface Card {
  readonly id: string;
  readonly type: CardTypeId;
  readonly name: string;
  readonly text?: string;
  readonly slotless?: boolean;
  readonly discardable: boolean;
  readonly stashable?: boolean;
  readonly loop_persistent: boolean;
  readonly note?: string;
}

export interface Location {
  readonly id: string;
  readonly name: string;
  readonly desc?: string;
  readonly phases?: readonly Phase[];
  readonly layer: 'day' | 'night' | 'both';
  readonly chapter?: number;
  readonly earliest_night?: number;
  readonly requires?: Condition;
  readonly reject_reason?: string;
  readonly reject_reason_tag?: string;
  readonly night_reveal?: string | null;
  readonly day_counterpart?: string | null;
  readonly madness_cost?: number;
  readonly teaser_only?: boolean;
  readonly map?: { readonly x: number; readonly y: number };
  readonly note?: string;
}

export interface NpcAt {
  readonly location: string;
  readonly phases: readonly Phase[];
  readonly from_day?: number;
  readonly to_day?: number;
}

export interface Npc {
  readonly id: string;
  readonly name: string;
  readonly locked_name?: string | null;
  readonly reveal?: Condition | null;
  readonly card?: string | null;
  readonly festival_proxy_eligible: boolean;
  readonly at: readonly NpcAt[];
  readonly note?: string;
}

/** beat 成立的日期／時段條件。day 與 day_from 不得同時出現（載入時攔截）。 */
export interface When {
  readonly day?: number;
  readonly day_from?: number;
  readonly day_to?: number;
  readonly phase?: Phase | readonly Phase[];
}

/** 封閉條件運算子，鍵與 data_facts.gd / ConditionEval.KNOWN_KEYS 同順序。 */
export type Condition =
  | { readonly day: number }
  | { readonly day_at_least: number }
  | { readonly has_card: string }
  | { readonly has_knowledge: string }
  | { readonly switch: string }
  | { readonly switch_progress_at_least: { readonly switch: string; readonly n: number } }
  | { readonly flag: string }
  | { readonly relation_at_least: { readonly npc: string; readonly state: string } }
  | { readonly madness_at_least: number }
  | { readonly count_at_least: { readonly n: number; readonly of: readonly Condition[] } }
  | { readonly not: Condition }
  | { readonly all: readonly Condition[] }
  | { readonly any: readonly Condition[] }
  | { readonly night_seen: string }
  | { readonly opening_choice: string }
  | { readonly ending_seen: string }
  | { readonly festival_proxy_is: string };

export interface FestivalProxyFixed {
  readonly mode: 'fixed';
  readonly npc: string;
}
export interface FestivalProxyHighest {
  readonly mode: 'highest_eligible';
  readonly fallback: string;
}
export type FestivalProxy = FestivalProxyFixed | FestivalProxyHighest;

/** gain / lose 的陣列元素：字串卡 id，或帶條件的物件。 */
export type CardEntry =
  | string
  | { readonly card: string; readonly if?: Condition; readonly permanent?: boolean };

export interface Effect {
  readonly text?: string;
  readonly gain?: readonly CardEntry[];
  readonly lose?: readonly CardEntry[];
  readonly switch?: string;
  readonly switch_progress?: { readonly [switchId: string]: number };
  readonly relation?: { readonly npc: string; readonly delta: number };
  readonly madness?: number;
  readonly flag?: { readonly [flagName: string]: boolean };
  readonly festival_proxy?: FestivalProxy;
  readonly ending?: string;
}

export interface Indulgence {
  /** 正式資料中 auto:false 的泡湯出口沒有 weight。 */
  readonly weight?: number;
  readonly auto?: boolean;
  readonly soak?: boolean;
}

export interface Delegation {
  readonly result_timing: 'immediate' | 'next_morning';
  readonly preview: string;
  readonly tendency: string;
  readonly report?: Effect;
}

export interface PhaseExit {
  readonly required_slots?: readonly string[];
  readonly required_choice_groups?: readonly string[];
  readonly ending?: string;
  readonly source?: string;
}

export interface Slot {
  readonly id: string;
  readonly label?: string;
  readonly occupant?: string | null;
  readonly condition?: Condition;
  readonly accepts?: readonly string[];
  readonly requires?: Condition;
  readonly reject_reason?: string;
  readonly on_place?: Effect;
  readonly delegation?: Delegation;
  readonly indulgence?: Indulgence;
  readonly on_place_by_level?: {
    readonly light?: Effect;
    readonly normal?: Effect;
    readonly heavy?: Effect;
  };
  readonly choice_group?: string;
  readonly choice_requires_card?: boolean;
  readonly default_if_unresolved?: boolean;
  readonly attention_npc?: string;
  readonly note?: string;
}

export interface Echo {
  readonly day: number;
  readonly text: string;
  readonly condition?: Condition;
}

export interface Response {
  readonly id: string;
  readonly accepts: readonly string[];
  readonly consume_card: boolean;
  readonly next_round: string | null;
  readonly on_resolve: Effect;
}

export interface Fallback {
  readonly requires_discardable?: boolean;
  readonly next_round: string | null;
  readonly on_resolve: Effect;
}

export interface Round {
  readonly id: string;
  readonly demand: string;
  readonly responses: readonly Response[];
  readonly fallback: Fallback;
}

export interface Encounter {
  readonly repeat_each_run?: boolean;
  readonly charge_first_visit?: boolean;
  readonly per_round_slot_cost: number;
  readonly escape_cost: number | null;
  readonly allow_discard?: boolean;
  readonly after_finish: 'stay' | 'advance_phase';
  readonly rounds: readonly Round[];
  readonly on_victory: Effect;
  readonly on_failure: Effect;
  readonly on_escape: Effect;
}

export interface Beat {
  readonly id: string;
  readonly location: string;
  readonly when?: When;
  readonly fixed?: boolean;
  readonly condition?: Condition;
  readonly requires?: Condition;
  readonly reject_reason?: string;
  readonly meta_once?: boolean;
  readonly title?: string;
  readonly text?: string;
  readonly slots?: readonly Slot[];
  readonly on_enter?: Effect;
  readonly auto_enter?: boolean;
  readonly echo?: Echo;
  readonly encounter?: Encounter;
  readonly phase_exit?: PhaseExit;
  readonly chapter?: number;
  readonly note?: string;
}

export interface OpeningChoice {
  readonly id: string;
  readonly label: string;
  readonly preview: string;
  readonly confirm_text: string;
  readonly requires?: Condition;
  readonly reject_reason?: string;
  readonly on_select?: Effect;
  readonly ending?: string;
  readonly note?: string;
}

/**
 * 開局畫面文案的原始資料。相容的頂層陣列格式沒有 screen，欄位可能整個缺；
 * 畫面查詢（W3）再依 Godot opening_screen_view() 以空字串補。
 */
export interface OpeningScreen {
  readonly title?: string;
  readonly prompt?: string;
  readonly note?: string;
}

export interface Page {
  readonly id: string;
  readonly text: string;
  readonly narrative_beats?: readonly string[];
}

export interface EndingRule {
  readonly id: string;
  readonly when?: Condition;
  readonly fallback?: boolean;
  readonly first_seen_pages: readonly Page[];
  readonly repeat_pages: readonly Page[];
}

export interface VariantGroup {
  readonly id: string;
  readonly history_field: string;
  readonly rules: readonly EndingRule[];
}

export interface LookupEntry {
  readonly value: string;
  readonly first_seen_pages: readonly Page[];
  readonly repeat_pages: readonly Page[];
}

export interface LookupFragment {
  readonly id: string;
  readonly when_group: { readonly group: string; readonly variant: string };
  readonly source_field: string;
  readonly entries: readonly LookupEntry[];
}

export interface EndingLinear {
  readonly id: string;
  readonly kind: 'linear';
  readonly draft?: boolean;
  readonly draft_note?: string;
  readonly first_seen: { readonly pages: readonly Page[] };
  readonly repeat: { readonly pages: readonly Page[]; readonly skip_to: string };
}

export interface EndingComposite {
  readonly id: string;
  readonly kind: 'composite';
  readonly draft?: boolean;
  readonly draft_note?: string;
  readonly first_seen: {
    readonly prefix_pages: readonly Page[];
    readonly suffix_pages: readonly Page[];
  };
  readonly repeat: {
    readonly prefix_pages: readonly Page[];
    readonly suffix_pages: readonly Page[];
    readonly skip_to: string;
  };
  readonly variant_groups: readonly VariantGroup[];
  readonly lookup_fragments: readonly LookupFragment[];
}

export type Ending = EndingLinear | EndingComposite;

export interface IndulgenceTuning {
  readonly soak_phase_cost: number;
  readonly soak_cards_cleared: number;
  readonly forced_light_count: number;
  readonly forced_normal_until: number;
}

export interface Tuning {
  readonly _comment?: string;
  readonly _pending?: unknown;
  readonly hand_size: number;
  readonly phases_per_day: number;
  readonly madness_cap: number;
  readonly madness_countdown_days: number;
  readonly madness_vision_threshold: number;
  readonly reserve_capacity: number | null;
  readonly indulgence: IndulgenceTuning;
}

/**
 * relation_scale.json 原樣保留：關係狀態名 → 整數門檻，另有 `_comment` 等
 * 字串 metadata。取門檻時須先確認值是 number，不能假設每個鍵都是狀態。
 */
export interface RelationScale {
  readonly _comment?: string;
  readonly [state: string]: number | string | undefined;
}

export interface DataFile {
  readonly path: string;
  readonly sha256: string;
}

export type ReadText = (relativeDataPath: string) => Promise<string>;

export interface GameData {
  readonly cards: readonly Card[];
  readonly locations: readonly Location[];
  readonly npcs: readonly Npc[];
  readonly beats: readonly Beat[];
  readonly endings: readonly Ending[];
  readonly openingChoices: readonly OpeningChoice[];
  readonly cardsById: ReadonlyMap<string, Card>;
  readonly locationsById: ReadonlyMap<string, Location>;
  readonly npcsById: ReadonlyMap<string, Npc>;
  readonly beatsById: ReadonlyMap<string, Beat>;
  readonly endingsById: ReadonlyMap<string, Ending>;
  readonly openingChoicesById: ReadonlyMap<string, OpeningChoice>;
  readonly tuning: Tuning;
  readonly relationScale: RelationScale;
  readonly cardTypes: readonly CardType[];
  readonly cardTypesById: ReadonlyMap<string, CardType>;
  readonly openingScreen: OpeningScreen;
}
