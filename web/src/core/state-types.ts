/**
 * ReturnFare Web — Runtime 狀態與查詢／變更介面型別（W3-B）。
 *
 * 對齊 Godot scripts/autoload/game_state.gd 的 serialize() 三區（flow、run、meta）、
 * 變更結果 MutationResult / AdvanceResult、以及開局與時段查詢 View 型別。
 */

import type { Phase } from '../data/types';
import type { DelegationStatus } from './delegation';
import type { EncounterView } from './encounter';
export type { EncounterCandidateView, EncounterIntroView, EncounterRoundView, EncounterView } from './encounter';

import type { EndingView } from './ending';
import type {
  AlignmentOffer,
  AlignmentResult,
  NightLocationSummary,
  ResolvedNightContent,
} from './night';
import type { MapLocationView, PanelView } from './panel';

export type FlowMode = 'opening' | 'run' | 'ending';

export type DeepReadonly<T> = T extends (infer R)[]
  ? readonly DeepReadonly<R>[]
  : T extends readonly (infer R)[]
    ? readonly DeepReadonly<R>[]
    : T extends object
      ? { readonly [K in keyof T]: DeepReadonly<T[K]> }
      : T;

export type ReasonCode =
  | ''
  | 'not_opening'
  | 'unknown_opening_choice'
  | 'opening_choice_locked'
  | 'not_run'
  | 'not_ending'
  | 'no_active_ending'
  | 'wrong_ending_stage'
  | 'already_revealed'
  | 'page_not_revealed'
  | 'last_page'
  | 'ending_not_seen'
  | 'not_ready'
  | 'ending_active'
  | 'unknown_ending'
  | 'invalid_ending_source'
  | 'encounter_active'
  | 'no_active_encounter'
  | 'wrong_stage'
  | 'unknown_card'
  | 'madness_blocked'
  | 'already_attempted'
  | 'card_not_submittable'
  | 'discard_disabled'
  | 'not_discardable'
  | 'cannot_escape'
  | 'wrong_escape_count'
  | 'duplicate_payment'
  | 'unresolved_choice_conflict'
  | 'phase_requirements_incomplete'
  | 'unknown_beat'
  | 'unknown_slot'
  | 'not_held'
  | 'hidden'
  | 'locked'
  | 'resolved'
  | 'not_accepted'
  | 'action_spent'
  | 'card_required'
  | 'not_action_phase'
  | 'not_delegation'
  | 'not_person'
  | 'already_delegated_today'
  | 'already_resolved'
  | 'not_night'
  | 'overloaded'
  | 'unknown_location'
  | 'not_night_layer'
  | 'teaser'
  | 'too_early'
  | 'already_chosen'
  | 'already_slept'
  | 'not_day_phase'
  | 'not_day_layer'
  | 'no_seen_row'
  | 'already_known'
  | 'invalid_save_shape'
  | 'data_conflict'
  | 'not_implemented';

/** 歷輪結局摘要紀錄（HISTORY_RECORD_KEYS 十欄） */
export interface EndingHistoryRecord {
  run_number: number;
  ending_id: string;
  opening_choice_id: string | null;
  ended_day: number | null;
  ended_phase: Phase | null;
  partner_variant: string | null;
  livelihood_variant: string | null;
  inn_appearance_variant: string | null;
  festival_proxy_npc: string | null;
  knowledge_gained_this_run: string[];
}

/** 進行中結局快照（ENDING_SNAPSHOT_KEYS 十五欄） */
export interface ActiveEndingSnapshot extends EndingHistoryRecord {
  source_id: string;
  page_refs: string[];
  page_index: number;
  page_revealed: boolean;
  ready_to_complete: boolean;
}

/** 隔日上午待回報委託紀錄 */
export interface PendingDelegationReport {
  due_day: number;
  beat_id: string;
  slot_id: string;
  person_id: string;
}

/** 遭遇進行中快照（無遭遇時為空物件 `{}`） */
export interface ActiveEncounterState {
  beat_id?: string;
  stage?: string;
  round_id?: string;
  blocked_slots?: number;
  attempted_card_ids?: string[];
  visited_round_ids?: string[];
  [key: string]: unknown;
}

export interface FlowState {
  mode: FlowMode;
  active_ending: ActiveEndingSnapshot | null;
}

export interface RunState {
  day: number;
  phase: Phase;
  opening_choice_id: string | null;
  knowledge_at_start: Record<string, boolean>;
  selected_festival_proxy_npc: string | null;
  action_spent: boolean;
  actions_spent_ahead: number;
  hand: string[];
  madness_clock: Record<string, number>;
  _madness_counter: number;
  beats_entered: Record<string, boolean>;
  slots_placed: Record<string, boolean>;
  choices: Record<string, string>;
  flags: Record<string, boolean>;
  switches: Record<string, boolean>;
  switch_progress: Record<string, number>;
  relations: Record<string, number>;
  npc_action_counts: Record<string, number>;
  night_location_chosen: string;
  night_sleep_pending: boolean;
  indulgence_count: number;
  madness_cards_cleared: number;
  forced_pending: string[];
  delegates_used_today: Record<string, boolean>;
  pending_delegation_reports: PendingDelegationReport[];
  active_encounter: ActiveEncounterState;
}

export interface MetaState {
  knowledge: Record<string, boolean>;
  night_locations_seen: Record<string, boolean>;
  night_once_beats_seen: Record<string, boolean>;
  day_locations_visited: Record<string, boolean>;
  delegation_tutorial_seen: boolean;
  run_number: number;
  ending_history: EndingHistoryRecord[];
  loop_persistent_item_ids: Record<string, boolean>;
}

/**
 * 完整可序列化狀態快照（對齊 Godot GameState.serialize() 三區）。
 * 暫態演出文字（lines）不住在此結構內。
 */
export interface GameSnapshot {
  flow: FlowState;
  run: RunState;
  meta: MetaState;
}

/** 開局畫面頂部故事文案投影 */
export interface OpeningScreenView {
  readonly title: string;
  readonly prompt: string;
}

/** 開局選項投影（不暴露 requires、on_select、ending、condition、note） */
export interface OpeningOptionView {
  readonly id: string;
  readonly label: string;
  readonly preview: string;
  readonly confirm_text: string;
  readonly available: boolean;
  readonly reason_text: string;
}

/** 夜間主按鈕的三態（scenes/main.gd）：尚未選地點＝sleep、已到訪＝end_night、睡覺停拍後＝next_day。 */
export type NightAdvanceStage = 'sleep' | 'end_night' | 'next_day';

/** phase_exit 門檻投影 */
export interface PhaseExitView {
  readonly location_id: string;
  readonly satisfied: boolean;
}

/** 當前時段純演出與狀態投影 */
export interface PhaseView {
  readonly day: number;
  readonly phase: Phase;
  readonly chapter: number;
  readonly narration_only: boolean;
  readonly isNarrationOnly: boolean;
  readonly lines: readonly string[];
  readonly forced_lines: readonly string[];
  readonly delegation_report_lines: readonly string[];
  readonly delegation_tutorial_available: boolean;
  readonly can_advance: boolean;
  readonly canAdvance: boolean;
  /** 非夜間為 null；夜間由 night_sleep_pending／night_location_chosen 衍生。 */
  readonly night_advance: NightAdvanceStage | null;
  /** 當前時段有生效的 phase_exit 門檻時非空；供 UI 建立通用離場入口。 */
  readonly phase_exit: PhaseExitView | null;
}

/** 一般變更操作的回傳結果 */
export interface MutationResult {
  readonly ok: boolean;
  readonly reason_code: ReasonCode;
  readonly reason_text: string;
  readonly lines: readonly string[];
}

/** 時段推進的回傳結果 */
export interface AdvanceResult extends MutationResult {
  readonly phase_advanced: boolean;
}

/** 遭遇開場確認結果 */
export interface EncounterAckResult extends MutationResult {
  readonly entered_round?: boolean;
}

/** 卡片與知識唯讀投影（W5-A） */
export interface CardView {
  readonly instanceId: string;
  readonly baseId: string;
  readonly type: string;
  readonly name: string;
  readonly text: string;
  readonly countdown?: number;
}

/** Game store 公開介面 */
export interface Game {
  getSnapshot(): DeepReadonly<GameSnapshot>;
  serialize(): GameSnapshot;
  subscribe(listener: () => void): () => void;
  chapter(): number;
  openingScreenView(): OpeningScreenView;
  openingView(): readonly OpeningOptionView[];
  getOpeningScreenView(): OpeningScreenView;
  getOpeningView(): readonly OpeningOptionView[];
  getPhaseView(): PhaseView;
  availableLocations(): readonly string[];
  mapView(): readonly MapLocationView[];
  buildPanel(locationId: string): PanelView;
  remainingActionsToday(): number;
  markDayLocationVisited(locationId: string): void;
  hasCard(cardId: string): boolean;
  hasKnowledge(cardId: string): boolean;
  handSlotsUsed(): number;
  handCapacity(): number;
  cardView(instanceId: string): CardView;
  handView(): readonly CardView[];
  knowledgeView(): readonly CardView[];
  chooseOpening(choiceId: string): MutationResult;
  playBeat(beatId: string): MutationResult;
  playEvening(): MutationResult;
  playNightFixed(): MutationResult;
  choose(
    beatId: string,
    groupId: string,
    slotId: string,
    cardId?: string,
  ): MutationResult;
  tryPlace(cardId: string, beatId: string, slotId: string): MutationResult;
  delegate(
    beatId: string,
    slotId: string,
    personCardId: string,
  ): MutationResult;
  delegationStatus(personCardId: string): DelegationStatus;
  markDelegationTutorialSeen(): void;
  indulge(
    beatId: string,
    slotId: string,
    cardInstanceId: string,
  ): MutationResult;
  placeableCards(beatId: string, slotId: string): readonly string[];
  previewSlot(
    beatId: string,
    slotId: string,
  ): { cards: readonly string[]; reason: string };
  hasAnyLegalAction(): boolean;
  hasUnseenContent(): boolean;
  advancePhase(): AdvanceResult;
  nightLocationSummary(locationId: string): NightLocationSummary;
  resolvedNightContent(locationId: string): ResolvedNightContent;
  enterNightLocation(locationId: string): MutationResult;
  alignmentOffer(dayLocationId: string): AlignmentOffer;
  confirmNightAlignment(dayLocationId: string): AlignmentResult;
  endingView(): EndingView;
  hasSeenEnding(endingId: string): boolean;
  revealEndingPage(): MutationResult;
  advanceEndingPage(): MutationResult;
  skipSeenEnding(): MutationResult;
  completeEnding(): MutationResult;
  encounterView(): EncounterView;
  acknowledgeEncounterIntro(): EncounterAckResult;
  respondToEncounter(cardId: string): MutationResult;
  discardInEncounter(cardId: string): MutationResult;
  escapeEncounter(cardIds: readonly string[]): MutationResult;
}
