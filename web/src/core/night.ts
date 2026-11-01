/**
 * ReturnFare Web — 夜間規則（W3-B 初期子集；W6-A 補齊候選／解析／摘要／對位）。
 *
 * 對齊 Godot：
 * - scripts/data_loader.gd night_beat_candidates（純結構候選，不求值條件）
 * - scripts/autoload/game_state.gd resolved_night_content／_record_forced_night_visit／
 *   would_night_entry_end_run／night_location_seen
 * - scripts/core/panel_builder.gd location_summary／alignment_offer
 *
 * 候選產生（nightBeatCandidates）與有狀態解析（resolveNightBeats）分兩層；睡覺、面板與合法性
 * 共用 resolveNightBeats 這一份，不各掃一次 when。本檔都是純查詢，狀態寫入由 state.ts 的 draft 負責。
 */

import type { Beat, GameData, Location } from '../data/types';
import { strings } from '../ui/strings';
import { evalCondition } from './condition';
import { beatMatchesTime, chapterForDay } from './facts';
import { wouldReachMadnessCap } from './madness';
import type {
  DeepReadonly,
  GameSnapshot,
  MutationResult,
  ReasonCode,
} from './state-types';

type StateView = DeepReadonly<GameSnapshot>;

/**
 * fixed 夜間到訪（playNightFixed 專用）：
 * 當 run.night_location_chosen 為空、未 night_sleep_pending、且地點存在於 data.locationsById 時，
 * 寫入 run.night_location_chosen 與 meta.night_locations_seen[locationId] = true，
 * 明確跳過一般夜間進場的 madness_cost，並回傳 true；否則回傳 false 且狀態零變化。
 */
export function recordForcedNightVisit(
  state: GameSnapshot,
  locationId: string,
  data: GameData,
): boolean {
  if (state.run.night_location_chosen !== '') {
    return false;
  }
  if (state.run.night_sleep_pending) {
    return false;
  }
  if (!data.locationsById.has(locationId)) {
    return false;
  }
  state.run.night_location_chosen = locationId;
  state.meta.night_locations_seen[locationId] = true;
  return true;
}

/**
 * 取得某地點在夜間的結構候選（對應 DataLoader.night_beat_candidates，純資料形狀選擇，不求值條件）。
 */
export function nightBeatCandidates(
  day: number,
  locationId: string,
  currentChapter: number,
  data: GameData,
): { primaries: Beat[]; addons: Beat[] } {
  const primaries: Beat[] = [];
  const addons: Beat[] = [];

  // 1. 定日夜間候選（同地點、non-fixed、exact when.day 且 beatMatchesTime(when, day, 'night') 成立）
  for (let i = 0; i < data.beats.length; i += 1) {
    const b = data.beats[i];
    if (b.location !== locationId) {
      continue;
    }
    if (b.fixed === true) {
      continue;
    }
    const w = b.when as { day?: number; day_from?: number; day_to?: number } | undefined;
    if (!w || typeof w !== 'object') {
      continue;
    }
    if (w.day === undefined || w.day_from !== undefined || w.day_to !== undefined) {
      continue;
    }
    if (beatMatchesTime(b.when, day, 'night')) {
      primaries.push(b);
    }
  }

  // 2. 章節變體（同地點、無 when、有 chapter <= currentChapter，chapter 由高至低排序，同章保留原序）
  for (let ch = currentChapter; ch >= 1; ch -= 1) {
    for (let i = 0; i < data.beats.length; i += 1) {
      const b = data.beats[i];
      if (b.location !== locationId) {
        continue;
      }
      if (b.when !== undefined) {
        continue;
      }
      if (b.chapter !== undefined && b.chapter === ch) {
        primaries.push(b);
      }
    }
  }

  // 3. 附加 beat（同地點、無 when、無 chapter，保留原序）
  for (let i = 0; i < data.beats.length; i += 1) {
    const b = data.beats[i];
    if (b.location !== locationId) {
      continue;
    }
    if (b.when === undefined && b.chapter === undefined) {
      addons.push(b);
    }
  }

  return { primaries, addons };
}

/** 某地點當下有狀態解析後的夜間 beat（內部用，帶完整 beat 資料）。 */
export interface NightBeatSelection {
  readonly primary: Beat | null;
  readonly addons: readonly Beat[];
}

/**
 * 夜間內容唯一有狀態解析入口（對應 GameState.resolved_night_content）。
 * condition 成立的第一個 primary 勝出（定日不成立則退回章節變體）；addons 只留 condition 成立者。
 * requires 不參與選擇：不成立的 primary 仍是被選中的 LOCKED 內容，不退回下一個版本。
 * 條件求值錯誤原樣拋出，由呼叫端轉成拒絕碼。
 */
export function resolveNightBeats(
  state: StateView,
  locationId: string,
  data: GameData,
): NightBeatSelection {
  const candidates = nightBeatCandidates(
    state.run.day,
    locationId,
    chapterForDay(state.run.day),
    data,
  );
  let primary: Beat | null = null;
  for (let i = 0; i < candidates.primaries.length; i += 1) {
    if (evalCondition(candidates.primaries[i].condition, state, data)) {
      primary = candidates.primaries[i];
      break;
    }
  }
  const addons = candidates.addons.filter((b) =>
    evalCondition(b.condition, state, data),
  );
  return { primary, addons };
}

/** 依序（primary 在前、addons 保序）攤平的 beat 清單。 */
export function nightBeatList(selection: NightBeatSelection): Beat[] {
  return selection.primary ? [selection.primary, ...selection.addons] : [...selection.addons];
}

export interface ResolvedNightBeatRef {
  readonly id: string;
  readonly title: string;
}

/** Game.resolvedNightContent() 的唯讀投影：只給 id 與標題，原始 beat JSON 不外露。 */
export interface ResolvedNightContent {
  readonly primary: ResolvedNightBeatRef | null;
  readonly addons: readonly ResolvedNightBeatRef[];
}

function beatRef(b: Beat): ResolvedNightBeatRef {
  return { id: b.id, title: typeof b.title === 'string' ? b.title : '' };
}

export function resolvedNightContent(
  state: StateView,
  locationId: string,
  data: GameData,
): ResolvedNightContent {
  const selection = resolveNightBeats(state, locationId, data);
  return {
    primary: selection.primary ? beatRef(selection.primary) : null,
    addons: selection.addons.map(beatRef),
  };
}

/** 夜間 non-fixed beat 的時間合法性：只接受該地點當下解析選中的 primary／addons（K-30）。 */
export function isResolvedNightBeat(
  state: StateView,
  beat: Beat,
  data: GameData,
): boolean {
  if (beat.location.length === 0) {
    return false;
  }
  const selection = resolveNightBeats(state, beat.location, data);
  return nightBeatList(selection).some((b) => b.id === beat.id);
}

// ── 地點摘要與進入預檢 ───────────────────────────────────────────────────────

export interface NightLocationSummary {
  readonly display_name: string;
  readonly status_text: string;
  readonly desc: string;
  readonly can_enter: boolean;
  readonly reason_code: ReasonCode;
  readonly reason_text: string;
  readonly warning: string;
  readonly teaser_only: boolean;
}

/** 夜間地點是否曾到訪（meta night_locations_seen）。 */
export function nightLocationSeen(state: StateView, locationId: string): boolean {
  return state.meta.night_locations_seen[locationId] === true;
}

/** 對位已持有：該地點 night_reveal 非空且在 knowledge。 */
function hasRevealKnowledge(state: StateView, loc: Location): boolean {
  const reveal = loc.night_reveal;
  return typeof reveal === 'string' && reveal.length > 0 && state.meta.knowledge[reveal] === true;
}

/** 資料側可進入的地點門檻（teaser／too_early／requires）；不含當夜狀態。 */
function entryGateOk(state: StateView, loc: Location, data: GameData): boolean {
  if (loc.teaser_only === true) {
    return false;
  }
  if (state.run.day < (loc.earliest_night ?? 1)) {
    return false;
  }
  return evalCondition(loc.requires, state, data);
}

/**
 * 純查詢：進入該夜間地點是否會因首次 marker cost 觸發發瘋 BE（would_night_entry_end_run）。
 * 已 seen、免費、LOCKED、teaser 一律 false；UI 不自行數卡。
 */
export function wouldNightEntryEndRun(
  state: StateView,
  locationId: string,
  data: GameData,
): boolean {
  if (nightLocationSeen(state, locationId)) {
    return false;
  }
  const loc = data.locationsById.get(locationId);
  if (!loc || loc.layer !== 'night') {
    return false;
  }
  if (!entryGateOk(state, loc, data)) {
    return false;
  }
  return wouldReachMadnessCap(state, loc.madness_cost ?? 0, data);
}

function dayCounterpartOf(loc: Location): string {
  return typeof loc.day_counterpart === 'string' ? loc.day_counterpart : '';
}

/** 已對位的夜間 row 顯示名：一對一用白天地點名，多對一用「白天名・夜間引子名」。 */
function alignedDisplayName(loc: Location, dayId: string, data: GameData): string {
  const dayName = data.locationsById.get(dayId)?.name ?? dayId;
  let siblings = 0;
  for (let i = 0; i < data.locations.length; i += 1) {
    const other = data.locations[i];
    if (other.layer === 'night' && dayCounterpartOf(other) === dayId) {
      siblings += 1;
    }
  }
  return siblings > 1 ? strings.nightMultiName(dayName, loc.name) : dayName;
}

/**
 * 夜間地點摘要（對應 PanelBuilder.location_summary）。名稱、狀態、門檻理由與風險警告的唯一來源。
 * 已對位與否由「seen」與「knowledge 含 night_reveal」即時衍生，不存第三份狀態。
 * 只顯示外部可觀察的 name／desc；尚未到訪不顯示 madness_cost。reason_code 順序同 enter_night_location。
 */
export function nightLocationSummary(
  state: StateView,
  locationId: string,
  data: GameData,
): NightLocationSummary {
  const loc = data.locationsById.get(locationId);
  if (!loc) {
    return {
      display_name: locationId,
      status_text: '',
      desc: '',
      can_enter: false,
      reason_code: 'unknown_location',
      reason_text: '',
      warning: '',
      teaser_only: false,
    };
  }

  const teaser = loc.teaser_only === true;
  const dayId = dayCounterpartOf(loc);
  const seen = nightLocationSeen(state, locationId);
  const aligned = seen && hasRevealKnowledge(state, loc);

  const display_name =
    dayId.length > 0 && aligned ? alignedDisplayName(loc, dayId, data) : loc.name;

  let status_text: string = strings.nightStatusUnseen;
  if (!teaser && seen) {
    if (dayId.length === 0) {
      status_text = strings.nightStatusSeen;
    } else {
      status_text = aligned ? strings.nightStatusAligned : strings.nightStatusSeenUnaligned;
    }
  }

  let can_enter = false;
  let reason_code: ReasonCode = '';
  let reason_text = '';
  if (state.run.phase !== 'night') {
    reason_code = 'not_night';
  } else if (loc.layer !== 'night') {
    reason_code = 'not_night_layer';
  } else if (teaser) {
    reason_code = 'teaser';
    reason_text = loc.reject_reason ?? '';
  } else if (state.run.day < (loc.earliest_night ?? 1)) {
    reason_code = 'too_early';
  } else if (!evalCondition(loc.requires, state, data)) {
    reason_code = 'locked';
    reason_text = loc.reject_reason ?? strings.reasonFallback;
  } else if (state.run.night_location_chosen !== '') {
    reason_code = 'already_chosen';
  } else if (state.run.night_sleep_pending) {
    reason_code = 'already_slept';
  } else {
    can_enter = true;
  }

  return {
    display_name,
    status_text,
    desc: (loc.desc ?? '').trim(),
    can_enter,
    reason_code,
    reason_text,
    warning: wouldNightEntryEndRun(state, locationId, data) ? strings.nightWarning : '',
    teaser_only: teaser,
  };
}

// ── 對位 ─────────────────────────────────────────────────────────────────────

export interface AlignmentOffer {
  readonly available: boolean;
  readonly knowledge_id: string;
  readonly night_ids: readonly string[];
}

export interface AlignmentResult extends MutationResult {
  readonly knowledge_id: string;
}

type AlignmentRows =
  | { readonly kind: 'no_seen_row' }
  | { readonly kind: 'data_conflict' }
  | { readonly kind: 'ok'; readonly knowledge_id: string; readonly night_ids: string[] };

/**
 * 反查所有 day_counterpart 指向該白天地點且已到訪的夜間 row，並驗它們共用同一張 night_reveal。
 * offer 與 confirm 共用，避免兩邊判準分岔。
 */
function alignmentRows(
  state: StateView,
  dayLocationId: string,
  data: GameData,
): AlignmentRows {
  const nightIds: string[] = [];
  const reveals: string[] = [];
  for (let i = 0; i < data.locations.length; i += 1) {
    const loc = data.locations[i];
    if (loc.layer !== 'night' || dayCounterpartOf(loc) !== dayLocationId) {
      continue;
    }
    if (!nightLocationSeen(state, loc.id)) {
      continue;
    }
    nightIds.push(loc.id);
    const reveal = loc.night_reveal;
    if (typeof reveal === 'string' && reveal.length > 0) {
      if (!reveals.includes(reveal)) {
        reveals.push(reveal);
      }
    } else {
      reveals.push('');
    }
  }
  if (nightIds.length === 0) {
    return { kind: 'no_seen_row' };
  }
  if (reveals.length !== 1 || reveals[0].length === 0) {
    return { kind: 'data_conflict' };
  }
  return { kind: 'ok', knowledge_id: reveals[0], night_ids: nightIds };
}

const NO_OFFER: AlignmentOffer = Object.freeze({
  available: false,
  knowledge_id: '',
  night_ids: Object.freeze([]) as readonly string[],
});

/**
 * 白天地點是否可對位（對應 PanelBuilder.alignment_offer）。純查詢。
 * 與 checkNightAlignment 同一套判準；另補 mode／遭遇守衛，讓「offer 給了 confirm 必收」。
 */
export function alignmentOffer(
  state: StateView,
  dayLocationId: string,
  data: GameData,
): AlignmentOffer {
  const check = checkNightAlignment(state, dayLocationId, data);
  if (check.ok) {
    return {
      available: true,
      knowledge_id: check.knowledge_id,
      night_ids: check.night_ids,
    };
  }
  if (check.reason_code === 'already_known') {
    return { available: false, knowledge_id: check.knowledge_id, night_ids: check.night_ids };
  }
  return NO_OFFER;
}

export type AlignmentCheck =
  | { readonly ok: true; readonly knowledge_id: string; readonly night_ids: readonly string[] }
  | {
      readonly ok: false;
      readonly reason_code: ReasonCode;
      readonly reason_text: string;
      readonly knowledge_id: string;
      readonly night_ids: readonly string[];
    };

function alignmentReject(
  reason_code: ReasonCode,
  reason_text = '',
  knowledge_id = '',
  night_ids: readonly string[] = [],
): AlignmentCheck {
  return { ok: false, reason_code, reason_text, knowledge_id, night_ids };
}

/**
 * 對位六碼拒絕矩陣（依序，對應 confirm_night_alignment）：
 * not_run → not_day_phase → encounter_active → unknown_location → not_day_layer →
 * no_seen_row → data_conflict → already_known。成功回知識卡與已到訪 row。
 */
export function checkNightAlignment(
  state: StateView,
  dayLocationId: string,
  data: GameData,
): AlignmentCheck {
  if (state.flow.mode !== 'run') {
    return alignmentReject('not_run', '本輪已結束，無法再進行遊戲操作');
  }
  if (state.run.phase !== 'morning' && state.run.phase !== 'afternoon') {
    return alignmentReject('not_day_phase');
  }
  if (Object.keys(state.run.active_encounter).length > 0) {
    return alignmentReject('encounter_active', '遭遇進行中，無法對位');
  }
  const dayLoc = data.locationsById.get(dayLocationId);
  if (!dayLoc) {
    return alignmentReject('unknown_location');
  }
  if (dayLoc.layer === 'night') {
    return alignmentReject('not_day_layer');
  }
  const rows = alignmentRows(state, dayLocationId, data);
  if (rows.kind === 'no_seen_row') {
    return alignmentReject('no_seen_row');
  }
  if (rows.kind === 'data_conflict') {
    return alignmentReject('data_conflict', `對位資料衝突或缺少 night_reveal：${dayLocationId}`);
  }
  if (state.meta.knowledge[rows.knowledge_id] === true) {
    return alignmentReject('already_known', '', rows.knowledge_id, rows.night_ids);
  }
  return { ok: true, knowledge_id: rows.knowledge_id, night_ids: rows.night_ids };
}
