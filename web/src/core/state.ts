/**
 * ReturnFare Web — GameState 核心容器與初期推進規則（W3-B）。
 *
 * 對齊 Godot scripts/autoload/game_state.gd：
 * - createGame(data, initialState?)
 * - getSnapshot() / serialize() / subscribe()
 * - getOpeningScreenView() / getOpeningView() / chooseOpening(choiceId)
 * - getPhaseView() / playBeat(beatId) / playEvening() / playNightFixed()
 * - advancePhase() 七步骨架
 */

import type { Beat, Condition, Effect, Encounter, GameData, Slot } from '../data/types';
import { strings } from '../ui/strings';
import {
  cardView as calcCardView,
  gainCard,
  handSlotsUsed as calcHandSlotsUsed,
  handView as calcHandView,
  hasCard as checkHasCard,
  hasKnowledge as checkHasKnowledge,
  isOverloaded,
  knowledgeView as calcKnowledgeView,
  loseCard,
} from './cards';
import {
  ConditionError,
  UnsupportedConditionError,
  evalCondition,
  hasSeenEnding as checkHasSeenEnding,
} from './condition';
import { planEffects } from './effect';
import {
  advanceEndingPage as stepAdvanceEndingPage,
  completeEnding as stepCompleteEnding,
  endingView as calcEndingView,
  revealEndingPage as stepRevealEndingPage,
  skipSeenEnding as stepSkipSeenEnding,
  startEndingOnDraft,
  type EndingStep,
  type EndingView,
} from './ending';
import {
  buildEncounterView,
  findMatchingResponse,
  getFirstRoundId,
  getRound,
  hasLegalMoves,
} from './encounter';
import {
  ACTION_PHASES,
  LAST_DAY,
  beatsAt,
  cardBaseId,
  chapterForDay,
  isNarrationOnlyPhase,
  nextPhaseTarget,
} from './facts';
import { levelFor, pickExit } from './indulgence';
import {
  gainMadnessCardOnDraft,
  madnessCapRequest,
  tickMadnessOnDraft,
} from './madness';
import {
  alignmentOffer as calcAlignmentOffer,
  checkNightAlignment,
  nightBeatList,
  nightLocationSummary as calcNightLocationSummary,
  recordForcedNightVisit,
  resolveNightBeats,
  resolvedNightContent as calcResolvedNightContent,
  wouldNightEntryEndRun,
  type AlignmentOffer,
  type AlignmentResult,
  type NightLocationSummary,
  type ResolvedNightContent,
} from './night';
import {
  availableLocations as calcAvailableLocations,
  buildPanel as calcBuildPanel,
  mapView as calcMapView,
  remainingActionsToday as calcRemainingActionsToday,
  type MapLocationView,
  type PanelView,
} from './panel';
import {
  calcDelegationStatus,
  type DelegationStatus,
} from './delegation';
import {
  checkPlace,
  checkSlotState,
  hasAnyLegalAction as calcHasAnyLegalAction,
  hasUnseenContent as calcHasUnseenContent,
  isBeatTimeValid,
  placeableCards as calcPlaceableCards,
  previewSlot as calcPreviewSlot,
} from './placement';
import {
  cloneSnapshot,
  createInitialSnapshot,
  deepFreeze,
  initializeRun,
} from './run-initialization';
import type {
  ActiveEncounterState,
  AdvanceResult,
  CardView,
  DeepReadonly,
  EncounterAckResult,
  EncounterView,
  Game,
  GameSnapshot,
  MutationResult,
  NightAdvanceStage,
  OpeningOptionView,
  OpeningScreenView,
  PendingDelegationReport,
  PhaseView,
  ReasonCode,
} from './state-types';

const REASON_LOCKED_FALLBACK = '（條件不足）';
const REASON_TEXT_NOT_RUN = '目前不在單輪進行中';

function isPlainObject(val: unknown): val is Record<string, unknown> {
  return typeof val === 'object' && val !== null && !Array.isArray(val);
}

function mutationReject(
  reason_code: ReasonCode,
  reason_text: string,
): MutationResult {
  return {
    ok: false,
    reason_code,
    reason_text,
    lines: [],
  };
}

function advanceReject(
  reason_code: ReasonCode,
  reason_text: string,
): AdvanceResult {
  return {
    ok: false,
    reason_code,
    reason_text,
    lines: [],
    phase_advanced: false,
  };
}

interface DraftBeatResult {
  readonly ok: boolean;
  readonly reason_code: ReasonCode;
  readonly reason_text: string;
  readonly lines: string[];
  readonly nextState: GameSnapshot;
}

interface SettleBookkeeping {
  beat_entered?: string;
  choice_key?: string;
  choice_slot_id?: string;
  slot_key?: string;
  consume_action?: boolean;
  action_cost?: number;
  attention_npc?: string;
  day_location_visited?: string;
  forced_pop?: string;
  lose_cards?: readonly string[];
  indulgence_delta?: number;
  delegate_person?: string;
  pending_report?: PendingDelegationReport;
  report_removed?: PendingDelegationReport;
  encounter_set?: ActiveEncounterState;
}

interface SettleResult {
  ok: boolean;
  reason_code: ReasonCode;
  reason_text: string;
  lines: string[];
  nextState: GameSnapshot;
}

function applyBookkeepingOnDraft(
  target: GameSnapshot,
  bk: SettleBookkeeping,
  data: GameData,
): void {
  if (bk.beat_entered) {
    target.run.beats_entered[bk.beat_entered] = true;
  }
  if (bk.choice_key && bk.choice_slot_id) {
    target.run.choices[bk.choice_key] = bk.choice_slot_id;
  }
  if (bk.slot_key) {
    target.run.slots_placed[bk.slot_key] = true;
  }
  // 對齊 _apply_bookkeeping：consume_action 與 action_cost 是兩條獨立記帳。
  if (bk.consume_action) {
    target.run.action_spent = true;
    if (bk.attention_npc) {
      target.run.npc_action_counts[bk.attention_npc] =
        (target.run.npc_action_counts[bk.attention_npc] ?? 0) + 1;
    }
  }
  const actionCost = bk.action_cost ?? 0;
  if (actionCost > 0) {
    target.run.action_spent = true;
    if (actionCost > 1) {
      target.run.actions_spent_ahead += actionCost - 1;
    }
  }
  if (bk.lose_cards && bk.lose_cards.length > 0) {
    for (let i = 0; i < bk.lose_cards.length; i += 1) {
      loseCard(target, bk.lose_cards[i], data);
    }
  }
  const indulgenceDelta = bk.indulgence_delta ?? 0;
  if (indulgenceDelta !== 0) {
    target.run.indulgence_count += indulgenceDelta;
  }
  if (bk.forced_pop) {
    const pos = target.run.forced_pending.indexOf(bk.forced_pop);
    if (pos >= 0) {
      target.run.forced_pending.splice(pos, 1);
    }
  }
  if (bk.delegate_person) {
    target.run.delegates_used_today[bk.delegate_person] = true;
  }
  if (bk.pending_report) {
    target.run.pending_delegation_reports.push({ ...bk.pending_report });
  }
  if (bk.report_removed) {
    const targetRep = bk.report_removed;
    const idx = target.run.pending_delegation_reports.findIndex(
      (item) =>
        item.due_day === targetRep.due_day &&
        item.beat_id === targetRep.beat_id &&
        item.slot_id === targetRep.slot_id &&
        item.person_id === targetRep.person_id,
    );
    if (idx >= 0) {
      target.run.pending_delegation_reports.splice(idx, 1);
    }
  }
  if (bk.day_location_visited) {
    recordDayLocationVisitedOnDraft(target, bk.day_location_visited, data);
  }
  if (bk.encounter_set !== undefined) {
    target.run.active_encounter = { ...bk.encounter_set };
    if (bk.encounter_set.attempted_card_ids) {
      target.run.active_encounter.attempted_card_ids = [
        ...bk.encounter_set.attempted_card_ids,
      ];
    }
    if (bk.encounter_set.visited_round_ids) {
      target.run.active_encounter.visited_round_ids = [
        ...bk.encounter_set.visited_round_ids,
      ];
    }
  }
}

function hasAnyEffect(
  blocks: readonly (Effect | Record<string, unknown> | null | undefined)[],
): boolean {
  for (let i = 0; i < blocks.length; i += 1) {
    const b = blocks[i];
    if (b && typeof b === 'object' && Object.keys(b).length > 0) {
      return true;
    }
  }
  return false;
}

/**
 * action bookkeeping 與效果合併的唯一入口（對齊 Godot GameState._settle_effects）。
 * 全部在 draft 上操作；成功才一次提交，失敗零副作用。
 */
function settleEffectsOnDraft(
  blocks: readonly (Effect | Record<string, unknown> | null | undefined)[],
  bookkeeping: SettleBookkeeping,
  preBookkeeping: SettleBookkeeping,
  state: GameSnapshot,
  data: GameData,
): SettleResult {
  const draft = cloneSnapshot(state);

  if (!hasAnyEffect(blocks)) {
    applyBookkeepingOnDraft(draft, preBookkeeping, data);
    applyBookkeepingOnDraft(draft, bookkeeping, data);
    return {
      ok: true,
      reason_code: '',
      reason_text: '',
      lines: [],
      nextState: draft,
    };
  }

  // Pre-bookkeeping applied on shadow
  applyBookkeepingOnDraft(draft, preBookkeeping, data);

  const pf = planEffects(blocks, draft, data);
  if (!pf.ok) {
    return {
      ok: false,
      reason_code: pf.reason_code,
      reason_text: pf.reason_text,
      lines: [],
      nextState: cloneSnapshot(state),
    };
  }

  const afterEffectsDraft = pf.nextState;

  // Bookkeeping applied on draft
  applyBookkeepingOnDraft(afterEffectsDraft, bookkeeping, data);

  // 結局請求：效果與記帳都已在 draft 上成功，最後才驗配對／資料／快照並凍結結果。
  // 任何一步失敗都回原狀態（零副作用）；成功則與效果、記帳同一筆提交。
  if (pf.endingRequest !== null) {
    const started = startEndingOnDraft(
      afterEffectsDraft,
      pf.endingRequest.ending_id,
      pf.endingRequest.source_id,
      data,
      { fromMode: 'run' },
    );
    if (!started.ok) {
      return {
        ok: false,
        reason_code: started.reason_code,
        reason_text: started.reason_text,
        lines: [],
        nextState: cloneSnapshot(state),
      };
    }
  }

  return {
    ok: true,
    reason_code: '',
    reason_text: '',
    lines: [...pf.lines],
    nextState: afterEffectsDraft,
  };
}

/**
 * 縱慾效果的共用結算：基底 on_place 與當次強度級追加塊合併成同一個動作。
 * 出口槽不記入 slots_placed（可重複使用）。
 */
function settleIndulgenceEffects(
  slot: Slot,
  preBookkeeping: SettleBookkeeping,
  state: GameSnapshot,
  data: GameData,
): SettleResult {
  const blocks: (Effect | Record<string, unknown>)[] = [slot.on_place ?? {}];
  const byLevel = slot.on_place_by_level;
  if (byLevel && typeof byLevel === 'object') {
    // 強度級看的是「含這一次」的縱慾次數，因此用尚未落地的 delta 先加上去。
    const effectiveCount =
      state.run.indulgence_count + (preBookkeeping.indulgence_delta ?? 0);
    const lvl = levelFor(effectiveCount, data.tuning);
    const lvlEffect = byLevel[lvl];
    if (lvlEffect && typeof lvlEffect === 'object') {
      blocks.push(lvlEffect);
    }
  }
  return settleEffectsOnDraft(blocks, {}, preBookkeeping, state, data);
}

/** 在 draft 上執行單一 beat 的呈現與首次 on_enter 結算。 */
function playBeatOnDraft(
  draft: GameSnapshot,
  beatId: string,
  data: GameData,
): DraftBeatResult {
  if (draft.flow.mode !== 'run') {
    return {
      ok: false,
      reason_code: 'not_run',
      reason_text: REASON_TEXT_NOT_RUN,
      lines: [],
      nextState: draft,
    };
  }

  const beat = data.beatsById.get(beatId);
  if (!beat) {
    return {
      ok: false,
      reason_code: 'unknown_beat',
      reason_text: `未知的 beat：${beatId}`,
      lines: [],
      nextState: draft,
    };
  }

  const lines: string[] = [];
  if (typeof beat.text === 'string' && beat.text.length > 0) {
    lines.push(beat.text);
  }

  const isFirst = !draft.run.beats_entered[beatId];
  if (isFirst) {
    const bk: SettleBookkeeping = {
      beat_entered: beatId,
      day_location_visited: beat.location,
    };
    const settleRes = settleEffectsOnDraft(
      [beat.on_enter],
      bk,
      {},
      draft,
      data,
    );
    if (!settleRes.ok) {
      return {
        ok: false,
        reason_code: settleRes.reason_code,
        reason_text: settleRes.reason_text,
        lines: [],
        nextState: draft,
      };
    }
    lines.push(...settleRes.lines);
    return {
      ok: true,
      reason_code: '',
      reason_text: '',
      lines,
      nextState: settleRes.nextState,
    };
  }

  const next = cloneSnapshot(draft);
  recordDayLocationVisitedOnDraft(next, beat.location, data);

  return {
    ok: true,
    reason_code: '',
    reason_text: '',
    lines,
    nextState: next,
  };
}

/**
 * 記錄白天地點造訪（對應 Godot GameState.mark_day_location_visited）。
 * 僅在 locationId 非空、存在於 data.locationsById 且 layer === 'day' 時寫入。
 */
function recordDayLocationVisitedOnDraft(
  draft: GameSnapshot,
  locationId: string | undefined,
  data: GameData,
): boolean {
  if (typeof locationId !== 'string' || locationId.length === 0) {
    return false;
  }
  const loc = data.locationsById.get(locationId);
  if (!loc || loc.layer !== 'day') {
    return false;
  }
  draft.meta.day_locations_visited[locationId] = true;
  return true;
}

/** 在 draft 上依陣列順序自動結算當前 (day, phase) 的 fixed + auto_enter beat。 */
function settleAutoEnterBeatsOnDraft(
  draft: GameSnapshot,
  data: GameData,
): DraftBeatResult {
  if (draft.flow.mode !== 'run') {
    return {
      ok: true,
      reason_code: '',
      reason_text: '',
      lines: [],
      nextState: draft,
    };
  }

  let current = cloneSnapshot(draft);
  const lines: string[] = [];
  const candidates = beatsAt(data.beats, current.run.day, current.run.phase);

  for (let i = 0; i < candidates.length; i += 1) {
    const b = candidates[i];
    if (b.fixed !== true || b.auto_enter !== true) {
      continue;
    }

    let condOk = false;
    try {
      condOk =
        evalCondition(b.condition, current, data) &&
        evalCondition(b.requires, current, data);
    } catch (err) {
      if (err instanceof UnsupportedConditionError) {
        return {
          ok: false,
          reason_code: 'not_implemented',
          reason_text: err.message,
          lines: [],
          nextState: draft,
        };
      }
      if (err instanceof ConditionError) {
        return {
          ok: false,
          reason_code: 'data_conflict',
          reason_text: err.message,
          lines: [],
          nextState: draft,
        };
      }
      throw err;
    }

    if (!condOk) {
      continue;
    }

    const res = playBeatOnDraft(current, b.id, data);
    if (!res.ok) {
      return {
        ok: false,
        reason_code: res.reason_code,
        reason_text: res.reason_text,
        lines: [],
        nextState: draft,
      };
    }
    current = res.nextState;
    lines.push(...res.lines);

    if (current.flow.mode !== 'run') {
      break;
    }
  }

  return {
    ok: true,
    reason_code: '',
    reason_text: '',
    lines,
    nextState: current,
  };
}

/** 條件求值錯誤轉拒絕碼（與全檔其他 try/catch 同義）；非條件錯誤回 null，由呼叫端重拋。 */
function conditionFailure(
  err: unknown,
): { reason_code: ReasonCode; reason_text: string } | null {
  if (err instanceof UnsupportedConditionError) {
    return { reason_code: 'not_implemented', reason_text: err.message };
  }
  if (err instanceof ConditionError) {
    return { reason_code: 'data_conflict', reason_text: err.message };
  }
  return null;
}

/** 直接睡＝解析旅館（sanquan）的夜間內容（規格書第九節、P3-C）。 */
const SLEEP_LOCATION_ID = 'sanquan';

/**
 * 在 draft 上播出睡覺內容（對應 GameState.sleep_night）：面板與睡覺共用同一份解析，
 * 只播 requires 成立者（requires 在每個 beat 播放前依當時狀態求值，如 Godot）。
 * 任一 beat 結算失敗整筆失敗，呼叫端的原 state 不受影響；睡覺效果把玩家推進結局時就地停止。
 */
function sleepNightOnDraft(base: GameSnapshot, data: GameData): DraftBeatResult {
  let current = base;
  const lines: string[] = [];
  let sleepBeats: Beat[];
  try {
    sleepBeats = nightBeatList(resolveNightBeats(current, SLEEP_LOCATION_ID, data));
  } catch (err) {
    const failure = conditionFailure(err);
    if (failure === null) throw err;
    return { ok: false, ...failure, lines: [], nextState: base };
  }
  for (let i = 0; i < sleepBeats.length; i += 1) {
    if (current.flow.mode !== 'run') {
      break;
    }
    let playable = false;
    try {
      playable = evalCondition(sleepBeats[i].requires, current, data);
    } catch (err) {
      const failure = conditionFailure(err);
      if (failure === null) throw err;
      return { ok: false, ...failure, lines: [], nextState: base };
    }
    if (!playable) {
      continue;
    }
    const played = playBeatOnDraft(current, sleepBeats[i].id, data);
    if (!played.ok) {
      return {
        ok: false,
        reason_code: played.reason_code,
        reason_text: played.reason_text,
        lines: [],
        nextState: base,
      };
    }
    current = played.nextState;
    lines.push(...played.lines);
  }
  return { ok: true, reason_code: '', reason_text: '', lines, nextState: current };
}

interface NightEntryPlan {
  readonly ok: boolean;
  readonly reason_code: ReasonCode;
  readonly reason_text: string;
  readonly lines: readonly string[];
  readonly nextState: GameSnapshot;
}

function nightEntryReject(
  state: Readonly<GameSnapshot>,
  reason_code: ReasonCode,
  reason_text = '',
): NightEntryPlan {
  return { ok: false, reason_code, reason_text, lines: [], nextState: cloneSnapshot(state) };
}

/**
 * 主動進入夜間地點的唯一規劃（對應 GameState.enter_night_location）。
 * 拒絕順序固定：not_run → not_night → encounter_active → overloaded → unknown_location →
 * not_night_layer → teaser → too_early → locked → already_chosen → already_slept。
 * 成功順序：chosen → seen（先於發卡）→ 終身首次才依 madness_cost 發卡並批次檢查 cap →
 * 撞 cap 就在同一個 draft 啟動 madness_cap 結局（到訪仍保留）。全部在 draft 上完成，失敗零副作用。
 */
function planEnterNightLocation(
  state: Readonly<GameSnapshot>,
  locationId: string,
  data: GameData,
): NightEntryPlan {
  if (state.flow.mode !== 'run') {
    return nightEntryReject(state, 'not_run', REASON_TEXT_NOT_RUN);
  }
  if (state.run.phase !== 'night') {
    return nightEntryReject(state, 'not_night');
  }
  if (Object.keys(state.run.active_encounter).length > 0) {
    return nightEntryReject(state, 'encounter_active', '遭遇進行中，無法進入地點');
  }
  if (isOverloaded(state, data)) {
    return nightEntryReject(state, 'overloaded', strings.reasonCodes.overloaded);
  }
  const loc = data.locationsById.get(locationId);
  if (!loc) {
    return nightEntryReject(state, 'unknown_location');
  }
  if (loc.layer !== 'night') {
    return nightEntryReject(state, 'not_night_layer');
  }
  if (loc.teaser_only === true) {
    return nightEntryReject(state, 'teaser');
  }
  if (state.run.day < (loc.earliest_night ?? 1)) {
    return nightEntryReject(state, 'too_early');
  }
  let gateOk = false;
  try {
    gateOk = evalCondition(loc.requires, state, data);
  } catch (err) {
    const failure = conditionFailure(err);
    if (failure === null) throw err;
    return nightEntryReject(state, failure.reason_code, failure.reason_text);
  }
  if (!gateOk) {
    return nightEntryReject(state, 'locked', loc.reject_reason ?? '');
  }
  if (state.run.night_location_chosen !== '') {
    return nightEntryReject(state, 'already_chosen');
  }
  if (state.run.night_sleep_pending) {
    return nightEntryReject(state, 'already_slept');
  }

  const draft = cloneSnapshot(state);
  const isFirstTime = !state.meta.night_locations_seen[locationId];
  const willEndRun = wouldNightEntryEndRun(state, locationId, data);
  draft.run.night_location_chosen = locationId;
  draft.meta.night_locations_seen[locationId] = true;

  const lines: string[] = [];
  const cost = loc.madness_cost ?? 0;
  if (isFirstTime && cost > 0) {
    for (let i = 0; i < cost; i += 1) {
      gainMadnessCardOnDraft(draft, data);
    }
    const capRequest = madnessCapRequest(draft, data);
    if (capRequest !== null) {
      const started = startEndingOnDraft(
        draft,
        capRequest.ending_id,
        capRequest.source_id,
        data,
        { fromMode: 'run' },
      );
      if (!started.ok) {
        return nightEntryReject(state, started.reason_code, started.reason_text);
      }
    }
    if (!willEndRun) {
      lines.push(strings.nightEnterMadness(cost));
    }
  }
  return { ok: true, reason_code: '', reason_text: '', lines, nextState: draft };
}

interface PhaseExitGateResult {
  readonly ok: boolean;
  readonly reason_code: ReasonCode;
  readonly reason_text: string;
  readonly has_gate: boolean;
  readonly satisfied: boolean;
  readonly ending: string;
  readonly source: string;
}

function evaluatePhaseExitGate(
  state: Readonly<GameSnapshot>,
  data: GameData,
): PhaseExitGateResult {
  const candidates = beatsAt(data.beats, state.run.day, state.run.phase);
  for (let i = 0; i < candidates.length; i += 1) {
    const b = candidates[i];
    if (b.fixed !== true) {
      continue;
    }
    if (!isPlainObject(b.phase_exit)) {
      continue;
    }

    let condOk = false;
    try {
      condOk =
        evalCondition(b.condition, state, data) &&
        evalCondition(b.requires, state, data);
    } catch (err) {
      if (err instanceof UnsupportedConditionError) {
        return {
          ok: false,
          reason_code: 'not_implemented',
          reason_text: err.message,
          has_gate: false,
          satisfied: true,
          ending: '',
          source: '',
        };
      }
      if (err instanceof ConditionError) {
        return {
          ok: false,
          reason_code: 'data_conflict',
          reason_text: err.message,
          has_gate: false,
          satisfied: true,
          ending: '',
          source: '',
        };
      }
      throw err;
    }

    if (!condOk) {
      continue;
    }

    const pe = b.phase_exit;
    let satisfied = true;
    const reqSlots = Array.isArray(pe.required_slots) ? pe.required_slots : [];
    for (let s = 0; s < reqSlots.length; s += 1) {
      const slotId = String(reqSlots[s]);
      if (!state.run.slots_placed[`${b.id}::${slotId}`]) {
        satisfied = false;
      }
    }

    const reqGroups = Array.isArray(pe.required_choice_groups)
      ? pe.required_choice_groups
      : [];
    for (let g = 0; g < reqGroups.length; g += 1) {
      const groupId = String(reqGroups[g]);
      if (!state.run.choices[`${b.id}::${groupId}`]) {
        satisfied = false;
      }
    }

    return {
      ok: true,
      reason_code: '',
      reason_text: '',
      has_gate: true,
      satisfied,
      ending: typeof pe.ending === 'string' ? pe.ending : '',
      source: typeof pe.source === 'string' ? pe.source : '',
    };
  }

  return {
    ok: true,
    reason_code: '',
    reason_text: '',
    has_gate: false,
    satisfied: true,
    ending: '',
    source: '',
  };
}

/** 檢查遭遇資料形狀是否合法（對應 Godot _encounter_data_error）。 */
function encounterDataError(beat: Beat): string {
  const encRaw = (beat as unknown as Record<string, unknown>).encounter;
  if (!isPlainObject(encRaw)) {
    return '遭遇資料格式錯誤';
  }
  if (!Array.isArray(encRaw.rounds) || encRaw.rounds.length === 0) {
    return '遭遇資料缺少回合定義';
  }
  if (
    typeof encRaw.per_round_slot_cost !== 'number' ||
    encRaw.per_round_slot_cost < 0
  ) {
    return '遭遇資料 slot_cost 錯誤';
  }
  if (typeof encRaw.after_finish !== 'string' || encRaw.after_finish.length === 0) {
    return '遭遇資料缺少 after_finish';
  }
  return '';
}

/**
 * 啟動遭遇（規格書第十節、開發設計方針 P4-D）。
 * 檢查順序固定：
 * 1. active: 已有進行中遭遇（encounter_active）
 * 2. unknown beat: 未知的 beat id 或無 encounter 欄位（unknown_beat）
 * 3. data conflict: 遭遇資料結構異常（data_conflict）
 * 成功建立 stage === "intro"，blocked_slots 初始化為 0。
 */
function startEncounterOnDraft(
  draft: GameSnapshot,
  beatId: string,
  data: GameData,
): { ok: boolean; reason_code: ReasonCode; reason_text: string } {
  if (draft.flow.mode !== 'run') {
    return {
      ok: false,
      reason_code: 'not_run',
      reason_text: REASON_TEXT_NOT_RUN,
    };
  }

  // 1. active
  if (Object.keys(draft.run.active_encounter).length > 0) {
    return {
      ok: false,
      reason_code: 'encounter_active',
      reason_text: '已有進行中的遭遇',
    };
  }

  // 2. unknown beat
  const beat = data.beatsById.get(beatId);
  if (!beat || !('encounter' in beat) || !beat.encounter) {
    return {
      ok: false,
      reason_code: 'unknown_beat',
      reason_text: '未知的遭遇事件',
    };
  }

  // 3. data conflict（與換時段前的預檢共用同一份檢查）
  const encErr = encounterDataError(beat);
  if (encErr.length > 0) {
    return {
      ok: false,
      reason_code: 'data_conflict',
      reason_text: encErr,
    };
  }

  draft.run.active_encounter = {
    beat_id: beatId,
    stage: 'intro',
    round_id: '',
    blocked_slots: 0,
    attempted_card_ids: [],
    visited_round_ids: [],
  };

  return { ok: true, reason_code: '', reason_text: '' };
}

/** 檢查可用格數是否歸零或小於 0（容量超載失敗，K-135/K-136）。 */
function checkEncounterCapacityFailure(
  state: GameSnapshot,
  data: GameData,
): boolean {
  const handSize = Number(data.tuning.hand_size);
  const blocked = state.run.active_encounter.blocked_slots ?? 0;
  if (blocked <= 0) {
    return state.run.hand.length > handSize;
  }
  return handSize - state.run.hand.length - blocked <= 0;
}

interface AdvancePlanResult {
  readonly ok: boolean;
  readonly reason_code: ReasonCode;
  readonly reason_text: string;
  readonly nextState: GameSnapshot;
  readonly defaultLines: string[];
  readonly forcedLines: string[];
  readonly autoEnterLines: string[];
  readonly delegationReportLines: string[];
  /** false＝夜間睡覺停拍（或睡覺把玩家推進結局）：狀態已更新但時段不動。 */
  readonly phaseAdvanced: boolean;
  /** 停拍時要讀的睡覺內容；時段真的推進時為空。 */
  readonly stopLines: string[];
}

function rejectAdvancePlan(
  currentState: Readonly<GameSnapshot>,
  reason_code: ReasonCode,
  reason_text: string,
): AdvancePlanResult {
  return {
    ok: false,
    reason_code,
    reason_text,
    nextState: cloneSnapshot(currentState),
    defaultLines: [],
    forcedLines: [],
    autoEnterLines: [],
    delegationReportLines: [],
    phaseAdvanced: false,
    stopLines: [],
  };
}

/**
 * 強制縱慾結算（規格書第八節、P2-C、開發設計方針 P2-C）。
 * 由 advance_phase 於行動時段開始時自動呼叫：
 * 1. 取 forced_pending 隊首有效的發狂卡（若已被消則取下一張）
 * 2. pickExit 挑選當前條件成立之最高權重出口
 * 3. 隊首出列、消耗行動格、消除發狂卡、縱慾次數+1、套用效果同屬一個動作
 * 結算失敗則債留在 forced_pending，行動格與手牌都不動。
 */
function settleForcedIndulgenceOnDraft(
  draft: GameSnapshot,
  data: GameData,
): { ok: boolean; lines: string[]; nextState: GameSnapshot } {
  if (draft.run.forced_pending.length === 0 || draft.run.action_spent) {
    return { ok: true, lines: [], nextState: draft };
  }

  // 清理前面已不在手上的無效實例
  while (
    draft.run.forced_pending.length > 0 &&
    !checkHasCard(draft, draft.run.forced_pending[0])
  ) {
    draft.run.forced_pending.shift();
  }

  if (draft.run.forced_pending.length === 0) {
    return { ok: true, lines: [], nextState: draft };
  }

  // 先驗證出口，若出口異常或找不到槽則不 pop 隊首，債留在 forced_pending（帳不豁免）
  const exitResult = pickExit(draft, data);
  if (!exitResult) {
    console.error(
      '_settle_forced_indulgence: Indulgence.pick_exit returned empty exit (data bug)',
    );
    return { ok: true, lines: [], nextState: draft };
  }

  const beat = data.beatsById.get(exitResult.beatId);
  const slot = (beat?.slots ?? []).find((s) => s.id === exitResult.slotId);
  if (!beat || !slot) {
    console.error(
      `_settle_forced_indulgence: slot not found '${exitResult.beatId}::${exitResult.slotId}'`,
    );
    return { ok: true, lines: [], nextState: draft };
  }

  // 隊首出列、行動格、發狂卡與效果同屬一個動作：結算失敗則債留在 forced_pending，
  // 行動格與手牌都不動（帳不豁免，也不會被扣兩次）。
  const cardInstId = draft.run.forced_pending[0];
  const preBk: SettleBookkeeping = {
    forced_pop: cardInstId,
    action_cost: 1,
    lose_cards: [cardInstId],
    indulgence_delta: 1,
  };

  const settle = settleIndulgenceEffects(slot, preBk, draft, data);
  if (!settle.ok) {
    console.error(
      `_settle_forced_indulgence: 效果結算失敗 → ${settle.reason_code}`,
    );
    return { ok: true, lines: [], nextState: draft };
  }

  return { ok: true, lines: settle.lines, nextState: settle.nextState };
}

/**
 * 隔日上午待回報委託結算（規格書第十三節、P4-B、開發設計方針 P4-B）。
 * 依 pending 順序回查 beat/slot 的 report 字典並原子結算。
 * 接點失效或結算失敗時保留於 pending 並 console.error（不靜默丟棄）。
 */
function settlePendingDelegationReportsOnDraft(
  draft: GameSnapshot,
  data: GameData,
): { ok: boolean; lines: string[]; nextState: GameSnapshot } {
  if (
    draft.flow.mode !== 'run' ||
    draft.run.pending_delegation_reports.length === 0
  ) {
    return { ok: true, lines: [], nextState: draft };
  }

  const currentDay = draft.run.day;
  const dueReports: PendingDelegationReport[] = [];

  for (let i = 0; i < draft.run.pending_delegation_reports.length; i += 1) {
    const r = draft.run.pending_delegation_reports[i];
    if (r.due_day > currentDay) {
      continue;
    }

    // 驗證接點合法性（beat 存在、slot 存在、delegation 為 next_morning 且 report 為非空物件）
    const bId = r.beat_id;
    const sId = r.slot_id;
    const beat = data.beatsById.get(bId);
    const slot = (beat?.slots ?? []).find((s) => s.id === sId);
    const del = slot?.delegation;
    const isValidDel = Boolean(del && del.result_timing === 'next_morning');
    const rep = isValidDel ? del?.report : undefined;
    const isValidRep = Boolean(
      rep &&
        typeof rep === 'object' &&
        !Array.isArray(rep) &&
        Object.keys(rep).length > 0,
    );

    if (!beat || !slot || !isValidDel || !isValidRep) {
      console.error(
        `GameState: pending delegation report data conflict on beat '${bId}', slot '${sId}' (retaining in pending)`,
      );
    } else {
      dueReports.push(r);
    }
  }

  // pending 不在這裡整份覆寫：每一筆回報的「出列」與它自己的效果同屬一個動作，
  // 由 pre bookkeeping 一起落地。未到期、資料壞掉與結算失敗的三種都原樣留在原位。
  let currentDraft = draft;
  const repLines: string[] = [];

  for (let i = 0; i < dueReports.length; i += 1) {
    const r = dueReports[i];
    const beat = data.beatsById.get(r.beat_id)!;
    const slot = (beat.slots ?? []).find((s) => s.id === r.slot_id)!;
    const repDict = slot.delegation!.report!;

    const genBefore = currentDraft.meta.run_number;
    const preBk: SettleBookkeeping = {
      report_removed: r,
    };

    const settle = settleEffectsOnDraft(
      [repDict],
      {},
      preBk,
      currentDraft,
      data,
    );
    if (!settle.ok) {
      console.error(
        `_settle_pending_delegation_reports: 回報效果結算失敗 → ${settle.reason_code}`,
      );
      return { ok: true, lines: repLines, nextState: currentDraft };
    }

    currentDraft = settle.nextState;

    // K-65 防呆：若回報效果觸發 BE / 結局，立即中斷結算、不寫入文字
    if (
      currentDraft.meta.run_number !== genBefore ||
      currentDraft.run.day !== currentDay ||
      currentDraft.flow.mode !== 'run'
    ) {
      return { ok: true, lines: repLines, nextState: currentDraft };
    }

    repLines.push(...settle.lines);
  }

  return { ok: true, lines: repLines, nextState: currentDraft };
}

/**
 * 時段推進的唯一純預檢：
 * 供 getPhaseView().can_advance 與 advancePhase() 共用同一套七步檢查與入場預演，
 * 確保 UI 可推進標記與實際命令結果永遠一致。
 */
function preflightAdvancePhase(
  currentState: Readonly<GameSnapshot>,
  data: GameData,
): AdvancePlanResult {
  // ① flow.mode !== 'run' -> not_run
  if (currentState.flow.mode !== 'run') {
    return rejectAdvancePlan(currentState, 'not_run', REASON_TEXT_NOT_RUN);
  }

  // ② active_encounter 非空 -> encounter_active
  if (Object.keys(currentState.run.active_encounter).length > 0) {
    return rejectAdvancePlan(
      currentState,
      'encounter_active',
      '遭遇進行中，無法推進時段',
    );
  }

  // ③ 夜間停拍：尚未選地點也尚未睡才解析睡覺。有文字就只停拍（睡覺效果與 pending 一起提交、時段不動），
  //    無文字續行；睡覺效果把玩家推進結局時同樣不再推進。全部在 draft 上完成，後面任一步拒絕都整筆丟棄。
  let draft = cloneSnapshot(currentState);
  if (
    currentState.run.phase === 'night' &&
    currentState.run.night_location_chosen === '' &&
    !currentState.run.night_sleep_pending
  ) {
    const slept = sleepNightOnDraft(draft, data);
    if (!slept.ok) {
      return rejectAdvancePlan(currentState, slept.reason_code, slept.reason_text);
    }
    draft = slept.nextState;
    if (slept.lines.length > 0) {
      draft.run.night_sleep_pending = true;
      return { ...rejectAdvancePlan(currentState, '', ''), ok: true, nextState: draft, stopLines: slept.lines };
    }
    if (draft.flow.mode !== 'run') {
      return { ...rejectAdvancePlan(currentState, '', ''), ok: true, nextState: draft };
    }
  }

  // ④ 逾期 choice group default 預檢（在 draft 上 preflight，不直接落地）
  const defaultLines: string[] = [];
  const currentBeats = beatsAt(
    data.beats,
    currentState.run.day,
    currentState.run.phase,
  );

  for (let i = 0; i < currentBeats.length; i += 1) {
    const b = currentBeats[i];
    if (b.fixed !== true) {
      continue;
    }
    let beatActive = false;
    try {
      beatActive =
        evalCondition(b.condition, draft, data) &&
        evalCondition(b.requires, draft, data);
    } catch (err) {
      if (err instanceof UnsupportedConditionError) {
        return rejectAdvancePlan(currentState, 'not_implemented', err.message);
      }
      if (err instanceof ConditionError) {
        return rejectAdvancePlan(
          currentState,
          'unresolved_choice_conflict',
          err.message,
        );
      }
      throw err;
    }
    if (!beatActive) {
      continue;
    }

    const slots = b.slots ?? [];
    for (let s = 0; s < slots.length; s += 1) {
      const slot = slots[s];
      if (slot.default_if_unresolved !== true) {
        continue;
      }
      const groupId = slot.choice_group ?? '';
      if (groupId.length === 0) {
        continue;
      }
      const choiceKey = `${b.id}::${groupId}`;
      if (draft.run.choices[choiceKey] !== undefined) {
        continue;
      }

      // 先在複本寫入 bookkeeping，再預演 slot.on_place
      draft.run.choices[choiceKey] = slot.id;
      draft.run.slots_placed[`${b.id}::${slot.id}`] = true;

      const pf = planEffects([slot.on_place], draft, data);
      if (!pf.ok) {
        if (pf.reason_code === 'not_implemented') {
          return rejectAdvancePlan(
            currentState,
            'not_implemented',
            pf.reason_text,
          );
        }
        return rejectAdvancePlan(
          currentState,
          'unresolved_choice_conflict',
          pf.reason_text,
        );
      }
      if (pf.endingRequest !== null) {
        return rejectAdvancePlan(
          currentState,
          'unresolved_choice_conflict',
          '逾期預設不得啟動結局',
        );
      }
      draft = pf.nextState;
      defaultLines.push(...pf.lines);
    }
  }

  // ⑤ fixed beat 的 phase_exit 門檻檢查
  const gate = evaluatePhaseExitGate(draft, data);
  if (!gate.ok) {
    return rejectAdvancePlan(currentState, gate.reason_code, gate.reason_text);
  }
  if (gate.has_gate && !gate.satisfied) {
    return rejectAdvancePlan(
      currentState,
      'phase_requirements_incomplete',
      '本時段的內容尚未完成',
    );
  }
  if (
    currentState.run.day === LAST_DAY &&
    currentState.run.phase === 'evening' &&
    gate.ending === ''
  ) {
    return rejectAdvancePlan(
      currentState,
      'phase_requirements_incomplete',
      '本時段的內容尚未完成',
    );
  }

  // ⑥ 目標時段與可能結局／到期遭遇預檢
  if (gate.ending !== '') {
    const started = startEndingOnDraft(draft, gate.ending, gate.source, data, {
      fromMode: 'run',
    });
    if (!started.ok) {
      return rejectAdvancePlan(
        currentState,
        started.reason_code,
        started.reason_text,
      );
    }
    return {
      ok: true,
      reason_code: '',
      reason_text: '',
      nextState: draft,
      defaultLines,
      forcedLines: [],
      autoEnterLines: [],
      delegationReportLines: [],
      phaseAdvanced: false,
      stopLines: [],
    };
  }

  const target = nextPhaseTarget(currentState.run.day, currentState.run.phase);
  if (target.day > LAST_DAY) {
    return rejectAdvancePlan(
      currentState,
      'data_conflict',
      '推進目標超出最後一天',
    );
  }

  // ⑦ 在 draft 上更新 day/phase、重設當日時段狀態
  draft.run.day = target.day;
  draft.run.phase = target.phase;
  draft.run.night_location_chosen = '';
  draft.run.night_sleep_pending = false;

  // 每日進 morning 才 tick；剛歸零的卡入列 forced_pending（已歸零者 clamp，不會重複入列）。
  if (currentState.run.phase === 'night') {
    draft.run.forced_pending.push(...tickMadnessOnDraft(draft));
  }

  // prepaid actions（泡湯預扣）：
  if (
    draft.run.actions_spent_ahead > 0 &&
    (ACTION_PHASES as readonly string[]).includes(target.phase)
  ) {
    draft.run.actions_spent_ahead -= 1;
    draft.run.action_spent = true;
  } else {
    draft.run.action_spent = false;
  }

  if (!(ACTION_PHASES as readonly string[]).includes(target.phase)) {
    draft.run.actions_spent_ahead = 0;
  }

  // P2-C: 行動時段開始時執行強制縱慾（每個行動時段最多一次）
  let forcedLines: string[] = [];
  if (
    (ACTION_PHASES as readonly string[]).includes(target.phase) &&
    !draft.run.action_spent &&
    draft.run.forced_pending.length > 0
  ) {
    const forcedRes = settleForcedIndulgenceOnDraft(draft, data);
    draft = forcedRes.nextState;
    forcedLines = forcedRes.lines;
  }

  // P4-B: 換日上午先完成既有發狂倒數／強制縱慾，若未進結局再依 pending 順序回查並套 report，最後清前一日 daily set
  let delegationLines: string[] = [];
  if (target.phase === 'morning') {
    if (draft.flow.mode === 'run') {
      const delRes = settlePendingDelegationReportsOnDraft(draft, data);
      draft = delRes.nextState;
      delegationLines = delRes.lines;
    }
    draft.run.delegates_used_today = {};
  }

  // 換時段途中若被強制縱慾推進到結局，就不再結算 auto_enter 或新遭遇
  let autoLines: string[] = [];
  if (draft.flow.mode === 'run') {
    const autoRes = settleAutoEnterBeatsOnDraft(draft, data);
    if (!autoRes.ok) {
      return rejectAdvancePlan(
        currentState,
        autoRes.reason_code,
        autoRes.reason_text,
      );
    }
    draft = autoRes.nextState;
    autoLines = autoRes.lines;
  }

  // 目標時段 fixed encounter 預檢（在 auto_enter 之後檢查，以涵蓋 auto_enter 寫入之條件）
  if (draft.flow.mode === 'run' && target.phase !== 'night') {
    const targetBeats = beatsAt(data.beats, target.day, target.phase);
    for (let i = 0; i < targetBeats.length; i += 1) {
      const tb = targetBeats[i];
      if (tb.fixed !== true) {
        continue;
      }
      const rawTb = tb as unknown as Record<string, unknown>;
      if (!('encounter' in rawTb) || rawTb.encounter === undefined) {
        continue;
      }
      const errText = encounterDataError(tb);
      if (errText.length > 0) {
        return rejectAdvancePlan(currentState, 'data_conflict', errText);
      }
    }

    for (let i = 0; i < targetBeats.length; i += 1) {
      const tb = targetBeats[i];
      if (tb.fixed !== true) {
        continue;
      }
      const rawTb = tb as unknown as Record<string, unknown>;
      if (!('encounter' in rawTb) || rawTb.encounter === undefined) {
        continue;
      }
      const isMetaOnce = tb.meta_once === true;
      if (isMetaOnce && draft.meta.night_once_beats_seen[tb.id]) {
        continue;
      }
      let encActive = false;
      try {
        encActive =
          evalCondition(tb.condition, draft, data) &&
          evalCondition(tb.requires, draft, data);
      } catch (err) {
        if (err instanceof UnsupportedConditionError) {
          return rejectAdvancePlan(currentState, 'not_implemented', err.message);
        }
        if (err instanceof ConditionError) {
          return rejectAdvancePlan(currentState, 'data_conflict', err.message);
        }
        throw err;
      }
      if (!encActive) {
        continue;
      }
      const startRes = startEncounterOnDraft(draft, tb.id, data);
      if (!startRes.ok) {
        return rejectAdvancePlan(
          currentState,
          startRes.reason_code,
          startRes.reason_text,
        );
      }
      break;
    }
  }

  return {
    ok: true,
    reason_code: '',
    reason_text: '',
    nextState: draft,
    defaultLines,
    forcedLines,
    autoEnterLines: autoLines,
    delegationReportLines: delegationLines,
    phaseAdvanced: true,
    stopLines: [],
  };
}

/**
 * 遭遇 action plan 的共用組裝：有出口就把出口效果併進同一批 blocks 並清掉遭遇。
 */
function planEncounterAction(
  enc: Encounter,
  blocks: Effect[],
  loseCards: string[],
  finalEnc: ActiveEncounterState,
  outcome: string,
): {
  blocks: Effect[];
  pre: SettleBookkeeping;
  advance_after: boolean;
} {
  const pre: SettleBookkeeping = {
    lose_cards: loseCards,
    encounter_set: { ...finalEnc },
  };
  let advanceAfter = false;
  const outBlocks = [...blocks];
  if (outcome.length > 0) {
    const exitKey = `on_${outcome}` as 'on_victory' | 'on_failure' | 'on_escape';
    const exitEffect = enc[exitKey];
    if (exitEffect && Object.keys(exitEffect).length > 0) {
      outBlocks.push(exitEffect);
    }
    pre.encounter_set = {};
    advanceAfter = enc.after_finish === 'advance_phase';
  }
  return {
    blocks: outBlocks,
    pre,
    advance_after: advanceAfter,
  };
}

export function createGame(
  data: GameData,
  initialState?: GameSnapshot,
): Game {
  let state: DeepReadonly<GameSnapshot> = deepFreeze(
    initialState ? cloneSnapshot(initialState) : createInitialSnapshot(),
  );

  // 暫態演出文字（不住在 GameSnapshot / serialize 內）
  let lastChoiceDefaultLines: string[] = [];
  let lastForcedLines: string[] = [];
  let lastAutoEnterLines: string[] = [];
  let lastDelegationReportLines: string[] = [];
  let phaseNarrationLines: string[] | null = null;

  const listeners = new Set<() => void>();

  function notifyListeners(): void {
    for (const listener of [...listeners]) {
      listener();
    }
  }

  function commitState(nextState: GameSnapshot): void {
    state = deepFreeze(cloneSnapshot(nextState));
  }

  function getSnapshot(): DeepReadonly<GameSnapshot> {
    return state;
  }

  function serialize(): GameSnapshot {
    return cloneSnapshot(state as GameSnapshot);
  }

  function subscribe(listener: () => void): () => void {
    listeners.add(listener);
    return () => {
      listeners.delete(listener);
    };
  }

  function chapter(): number {
    return chapterForDay(state.run.day);
  }

  function openingScreenView(): OpeningScreenView {
    return {
      title:
        typeof data.openingScreen.title === 'string'
          ? data.openingScreen.title
          : '',
      prompt:
        typeof data.openingScreen.prompt === 'string'
          ? data.openingScreen.prompt
          : '',
    };
  }

  function openingView(): readonly OpeningOptionView[] {
    const out: OpeningOptionView[] = [];
    for (let i = 0; i < data.openingChoices.length; i += 1) {
      const choice = data.openingChoices[i];
      let available = false;
      try {
        available = evalCondition(choice.requires, state as GameSnapshot, data);
      } catch {
        available = false;
      }
      const rejectReason =
        typeof choice.reject_reason === 'string' &&
        choice.reject_reason.length > 0
          ? choice.reject_reason
          : REASON_LOCKED_FALLBACK;
      out.push({
        id: choice.id,
        label: choice.label,
        preview: choice.preview,
        confirm_text: choice.confirm_text,
        available,
        reason_text: available ? '' : rejectReason,
      });
    }
    return out;
  }

  function canCurrentlyAdvance(): boolean {
    return preflightAdvancePhase(state as GameSnapshot, data).ok;
  }

  /** 夜間主按鈕三態（scenes/main.gd）：睡覺停拍後＝進入隔天；已到訪＝結束今晚；其餘＝直接睡。 */
  function nightAdvanceStage(): NightAdvanceStage | null {
    if (state.run.phase !== 'night') {
      return null;
    }
    if (state.run.night_sleep_pending) {
      return 'next_day';
    }
    return state.run.night_location_chosen !== '' ? 'end_night' : 'sleep';
  }

  function getPhaseView(): PhaseView {
    const day = state.run.day;
    const phase = state.run.phase;
    const ch = chapterForDay(day);
    const narrationOnly = isNarrationOnlyPhase(day, phase);
    const canAdv = canCurrentlyAdvance();
    const hasPersonCard =
      state.flow.mode === 'run' &&
      state.run.hand.some((cid) => {
        const baseId = cardBaseId(cid);
        return data.cardsById.get(baseId)?.type === 'person';
      });
    const delegationTutorialAvailable = Boolean(
      hasPersonCard && !state.meta.delegation_tutorial_seen,
    );
    const lines: string[] = [
      ...lastChoiceDefaultLines,
      ...lastAutoEnterLines,
      ...(phaseNarrationLines ?? []),
    ];
    if (state.run.active_encounter.stage === 'intro') {
      const intro = data.beatsById.get(state.run.active_encounter.beat_id ?? '')?.text;
      if (intro && !lines.includes(intro)) lines.push(intro);
    }
    return {
      day,
      phase,
      chapter: ch,
      narration_only: narrationOnly,
      isNarrationOnly: narrationOnly,
      lines,
      forced_lines: [...lastForcedLines],
      delegation_report_lines: [...lastDelegationReportLines],
      delegation_tutorial_available: delegationTutorialAvailable,
      can_advance: canAdv,
      canAdvance: canAdv,
      night_advance: nightAdvanceStage(),
    };
  }

  function availableLocations(): readonly string[] {
    return calcAvailableLocations(state, data);
  }

  function mapView(): readonly MapLocationView[] {
    return calcMapView(state, data);
  }

  function buildPanel(locationId: string): PanelView {
    return calcBuildPanel(locationId, state, data);
  }

  function remainingActionsToday(): number {
    return calcRemainingActionsToday(state);
  }

  function markDayLocationVisited(locationId: string): void {
    if (Object.keys(state.run.active_encounter).length > 0) return;
    const draft = cloneSnapshot(state as GameSnapshot);
    if (!recordDayLocationVisitedOnDraft(draft, locationId, data)) {
      return;
    }
    commitState(draft);
    notifyListeners();
  }

  function hasCard(cardId: string): boolean {
    return checkHasCard(state, cardId);
  }

  function hasKnowledge(cardId: string): boolean {
    return checkHasKnowledge(state, cardId);
  }

  function handSlotsUsed(): number {
    return calcHandSlotsUsed(state);
  }

  function handCapacity(): number {
    return Number(data.tuning.hand_size);
  }

  function cardView(instanceId: string): CardView {
    return calcCardView(state, instanceId, data);
  }

  function handView(): readonly CardView[] {
    return calcHandView(state, data);
  }

  function knowledgeView(): readonly CardView[] {
    return calcKnowledgeView(state, data);
  }

  function chooseOpening(choiceId: string): MutationResult {
    // 1. mode opening
    if (state.flow.mode !== 'opening') {
      return mutationReject('not_opening', '目前不在開局中');
    }

    // 2. choice 存在
    const choice = data.openingChoicesById.get(choiceId);
    if (!choice) {
      return mutationReject(
        'unknown_opening_choice',
        `未知的開局選項：${choiceId}`,
      );
    }

    // 3. requires 成立
    let unlocked = false;
    try {
      unlocked = evalCondition(choice.requires, state as GameSnapshot, data);
    } catch (err) {
      if (err instanceof UnsupportedConditionError) {
        return mutationReject('not_implemented', err.message);
      }
      if (err instanceof ConditionError) {
        return mutationReject('data_conflict', err.message);
      }
      throw err;
    }

    if (!unlocked) {
      const rejectText =
        typeof choice.reject_reason === 'string' &&
        choice.reject_reason.length > 0
          ? choice.reject_reason
          : REASON_LOCKED_FALLBACK;
      return mutationReject('opening_choice_locked', rejectText);
    }

    // 4. on_select vs ending 二擇一
    const rawChoice = choice as unknown as Record<string, unknown>;
    const hasEnding =
      typeof rawChoice.ending === 'string' && rawChoice.ending.length > 0;
    const hasSelect =
      isPlainObject(rawChoice.on_select) &&
      Object.keys(rawChoice.on_select).length > 0;
    if (hasEnding === hasSelect) {
      return mutationReject(
        'data_conflict',
        `開局選項必須恰有一個 on_select 或 ending：${choiceId}`,
      );
    }

    if (hasEnding) {
      // 不上車：不初始化 run，直接以 opening_choice 來源進結局（對應 _start_ending_from_opening）。
      const endingDraft = cloneSnapshot(state as GameSnapshot);
      const started = startEndingOnDraft(
        endingDraft,
        String(rawChoice.ending),
        'opening_choice',
        data,
        { fromMode: 'opening' },
      );
      if (!started.ok) {
        return mutationReject(started.reason_code, started.reason_text);
      }
      lastChoiceDefaultLines = [];
      lastForcedLines = [];
      lastAutoEnterLines = [];
      lastDelegationReportLines = [];
      phaseNarrationLines = null;
      commitState(endingDraft);
      notifyListeners();
      return {
        ok: true,
        reason_code: '',
        reason_text: '',
        lines: [],
      };
    }

    // on_select 分支：在複本上初始化 run 並預演 on_select 與 D1 morning auto_enter
    if (
      isPlainObject(choice.on_select) &&
      'ending' in choice.on_select &&
      choice.on_select.ending !== undefined
    ) {
      return mutationReject(
        'data_conflict',
        '開局選項的 on_select 不得啟動結局',
      );
    }

    const initDraft = initializeRun(state as GameSnapshot, data);
    const pf = planEffects([choice.on_select], initDraft, data);
    if (!pf.ok) {
      const code: ReasonCode =
        pf.reason_code === 'not_implemented'
          ? 'not_implemented'
          : 'data_conflict';
      return mutationReject(code, pf.reason_text);
    }
    if (pf.endingRequest !== null) {
      return mutationReject(
        'data_conflict',
        '開局選項的 on_select 不得啟動結局',
      );
    }

    const runDraft = pf.nextState;
    runDraft.run.opening_choice_id = choiceId;
    runDraft.flow.mode = 'run';
    runDraft.flow.active_ending = null;

    const autoRes = settleAutoEnterBeatsOnDraft(runDraft, data);
    if (!autoRes.ok) {
      return mutationReject(autoRes.reason_code, autoRes.reason_text);
    }

    const combinedLines = [...pf.lines, ...autoRes.lines];
    commitState(autoRes.nextState);
    lastChoiceDefaultLines = [];
    lastForcedLines = [];
    lastAutoEnterLines = combinedLines;
    lastDelegationReportLines = [];
    phaseNarrationLines = null;
    notifyListeners();

    return {
      ok: true,
      reason_code: '',
      reason_text: '',
      lines: combinedLines,
    };
  }

  function playBeat(beatId: string): MutationResult {
    if (state.flow.mode === 'run' && Object.keys(state.run.active_encounter).length > 0) {
      return mutationReject('encounter_active', '遭遇進行中，無法播放其他事件');
    }
    const res = playBeatOnDraft(state as GameSnapshot, beatId, data);
    if (!res.ok) {
      return mutationReject(res.reason_code, res.reason_text);
    }
    commitState(res.nextState);
    notifyListeners();
    return {
      ok: true,
      reason_code: '',
      reason_text: '',
      lines: res.lines,
    };
  }

  function playEvening(): MutationResult {
    if (state.flow.mode !== 'run') {
      return mutationReject('not_run', REASON_TEXT_NOT_RUN);
    }
    if (Object.keys(state.run.active_encounter).length > 0) {
      return mutationReject('encounter_active', '遭遇進行中，無法播放其他事件');
    }

    let draft = cloneSnapshot(state as GameSnapshot);
    const lines: string[] = [];
    const curDay = draft.run.day;

    // 1. 當日 evening fixed beats（依陣列順序）
    const eveningBeats = beatsAt(data.beats, curDay, 'evening');
    for (let i = 0; i < eveningBeats.length; i += 1) {
      const b = eveningBeats[i];
      if (b.fixed !== true) {
        continue;
      }
      let condOk = false;
      try {
        condOk =
          evalCondition(b.condition, draft, data) &&
          evalCondition(b.requires, draft, data);
      } catch (err) {
        if (err instanceof UnsupportedConditionError) {
          return mutationReject('not_implemented', err.message);
        }
        if (err instanceof ConditionError) {
          return mutationReject('data_conflict', err.message);
        }
        throw err;
      }
      if (!condOk) {
        continue;
      }

      const beatRes = playBeatOnDraft(draft, b.id, data);
      if (!beatRes.ok) {
        return mutationReject(beatRes.reason_code, beatRes.reason_text);
      }
      draft = beatRes.nextState;
      lines.push(...beatRes.lines);
      // 效果可能把玩家推進結局，之後就不該再播下一個 beat（殘響文字沿 Godot 照收）。
      if (draft.flow.mode !== 'run') {
        break;
      }
    }

    // 2. 當日殘響（echo.day === curDay）
    for (let i = 0; i < data.beats.length; i += 1) {
      const b = data.beats[i];
      if (!isPlainObject(b.echo)) {
        continue;
      }
      const echo = b.echo;
      if (echo.day !== curDay) {
        continue;
      }
      let echoOk = false;
      try {
        echoOk =
          evalCondition(echo.condition as Condition | undefined, draft, data) &&
          evalCondition(
            (echo as unknown as { requires?: Condition }).requires,
            draft,
            data,
          );
      } catch (err) {
        if (err instanceof UnsupportedConditionError) {
          return mutationReject('not_implemented', err.message);
        }
        if (err instanceof ConditionError) {
          return mutationReject('data_conflict', err.message);
        }
        throw err;
      }
      if (echoOk) {
        const text = typeof echo.text === 'string' ? echo.text.trim() : '';
        if (text.length > 0) {
          lines.push(text);
        }
      }
    }

    const isFirstPhaseNarration = phaseNarrationLines === null;
    if (isFirstPhaseNarration) {
      phaseNarrationLines = [...lines];
      commitState(draft);
      notifyListeners();
    } else if (JSON.stringify(draft) !== JSON.stringify(state)) {
      commitState(draft);
      notifyListeners();
    }

    return {
      ok: true,
      reason_code: '',
      reason_text: '',
      lines,
    };
  }

  function playNightFixed(): MutationResult {
    if (state.flow.mode !== 'run') {
      return mutationReject('not_run', REASON_TEXT_NOT_RUN);
    }
    if (Object.keys(state.run.active_encounter).length > 0) {
      return mutationReject('encounter_active', '遭遇進行中，無法播放其他事件');
    }

    let draft = cloneSnapshot(state as GameSnapshot);
    const lines: string[] = [];
    const curDay = draft.run.day;
    const nightBeats = beatsAt(data.beats, curDay, 'night');

    for (let i = 0; i < nightBeats.length; i += 1) {
      const b = nightBeats[i];
      if (b.fixed !== true) {
        continue;
      }
      const bid = b.id;
      const isMetaOnce = b.meta_once === true;
      if (isMetaOnce) {
        if (draft.meta.night_once_beats_seen[bid]) {
          continue;
        }
      } else if (draft.run.beats_entered[bid]) {
        continue;
      }

      let condOk = false;
      try {
        condOk =
          evalCondition(b.condition, draft, data) &&
          evalCondition(b.requires, draft, data);
      } catch (err) {
        if (err instanceof UnsupportedConditionError) {
          return mutationReject('not_implemented', err.message);
        }
        if (err instanceof ConditionError) {
          return mutationReject('data_conflict', err.message);
        }
        throw err;
      }
      if (!condOk) {
        continue;
      }

      const loc = data.locationsById.get(b.location);
      if (loc && loc.layer === 'night') {
        const wasSeen = Boolean(draft.meta.night_locations_seen[b.location]);
        if (!recordForcedNightVisit(draft, b.location, data)) {
          continue;
        }
        // charge_first_visit（P4-A）：強制到訪前保存是否終身 seen，此前未 seen 才按 madness_cost 收一次。
        const chargeCost_w6a = loc.madness_cost ?? 0;
        if (
          isPlainObject(b.encounter) &&
          b.encounter.charge_first_visit === true &&
          !wasSeen &&
          chargeCost_w6a > 0
        ) {
          for (let c = 0; c < chargeCost_w6a; c += 1) {
            gainMadnessCardOnDraft(draft, data);
          }
          const capRequest_w6a = madnessCapRequest(draft, data);
          if (capRequest_w6a !== null) {
            const started_w6a = startEndingOnDraft(
              draft,
              capRequest_w6a.ending_id,
              capRequest_w6a.source_id,
              data,
              { fromMode: 'run' },
            );
            if (!started_w6a.ok) {
              return mutationReject(started_w6a.reason_code, started_w6a.reason_text);
            }
            // 首次收費撞 BE：已進 ending，不可再播本 beat（否則文字與 beats_entered 會寫進已結束的輪）。
            break;
          }
        }
      }

      if (isMetaOnce) {
        draft.meta.night_once_beats_seen[bid] = true;
      }

      const beatRes = playBeatOnDraft(draft, bid, data);
      if (!beatRes.ok) {
        return mutationReject(beatRes.reason_code, beatRes.reason_text);
      }
      draft = beatRes.nextState;
      lines.push(...beatRes.lines);
      if (draft.flow.mode !== 'run') {
        break;
      }

      if (isPlainObject(b.encounter) && Object.keys(b.encounter).length > 0) {
        const startRes = startEncounterOnDraft(draft, bid, data);
        if (!startRes.ok) {
          return mutationReject(startRes.reason_code, startRes.reason_text);
        }
        // 遭遇啟動後不再播同夜後續 fixed beat（對齊 Godot play_night_fixed）
        break;
      }
    }

    const isFirstPhaseNarration = phaseNarrationLines === null;
    if (isFirstPhaseNarration) {
      phaseNarrationLines = [...lines];
      commitState(draft);
      notifyListeners();
    } else if (JSON.stringify(draft) !== JSON.stringify(state)) {
      commitState(draft);
      notifyListeners();
    }

    return {
      ok: true,
      reason_code: '',
      reason_text: '',
      lines,
    };
  }

  function advancePhase(): AdvanceResult {
    const plan = preflightAdvancePhase(state as GameSnapshot, data);
    if (!plan.ok) {
      return advanceReject(plan.reason_code, plan.reason_text);
    }

    commitState(plan.nextState);
    if (!plan.phaseAdvanced) {
      // 夜間睡覺停拍（或睡覺效果把玩家推進結局）：時段不動，睡覺文字成為這個時段要讀的演出。
      // D45 phase_exit 結局：時段不動，逾期預設文字依序保留。
      if (plan.stopLines.length > 0) {
        lastChoiceDefaultLines = [];
        lastForcedLines = [];
        lastAutoEnterLines = [];
        lastDelegationReportLines = [];
        phaseNarrationLines = [...plan.stopLines];
      } else {
        lastChoiceDefaultLines = plan.defaultLines;
      }
      notifyListeners();
      return {
        ok: true,
        reason_code: '',
        reason_text: '',
        lines: plan.stopLines.length > 0 ? plan.stopLines : plan.defaultLines,
        phase_advanced: false,
      };
    }
    lastChoiceDefaultLines = plan.defaultLines;
    lastForcedLines = plan.forcedLines;
    lastAutoEnterLines = plan.autoEnterLines;
    lastDelegationReportLines = plan.delegationReportLines;
    phaseNarrationLines = null;
    notifyListeners();

    return {
      ok: true,
      reason_code: '',
      reason_text: '',
      lines: plan.defaultLines,
      phase_advanced: true,
    };
  }

  function nightLocationSummary(locationId: string): NightLocationSummary {
    return calcNightLocationSummary(state, locationId, data);
  }

  function resolvedNightContent(locationId: string): ResolvedNightContent {
    return calcResolvedNightContent(state, locationId, data);
  }

  function enterNightLocation(locationId: string): MutationResult {
    const planned = planEnterNightLocation(state as GameSnapshot, locationId, data);
    if (!planned.ok) {
      return mutationReject(planned.reason_code, planned.reason_text);
    }
    commitState(planned.nextState);
    notifyListeners();
    return { ok: true, reason_code: '', reason_text: '', lines: planned.lines };
  }

  function alignmentOffer(dayLocationId: string): AlignmentOffer {
    return calcAlignmentOffer(state, dayLocationId, data);
  }

  function confirmNightAlignment(dayLocationId: string): AlignmentResult {
    const rejectAlignment = (code: ReasonCode, text: string): AlignmentResult => ({
      ...mutationReject(code, text),
      knowledge_id: '',
    });
    const check = checkNightAlignment(state, dayLocationId, data);
    if (!check.ok) {
      return rejectAlignment(check.reason_code, check.reason_text);
    }
    const draft = cloneSnapshot(state as GameSnapshot);
    const gained = gainCard(draft, check.knowledge_id, data);
    if (!gained.ok) {
      return rejectAlignment(gained.reason_code, gained.reason_text);
    }
    commitState(draft);
    notifyListeners();
    return {
      ok: true,
      reason_code: '',
      reason_text: '',
      lines: [],
      knowledge_id: check.knowledge_id,
    };
  }

  function choose(
    beatId: string,
    groupId: string,
    slotId: string,
    cardId = '',
  ): MutationResult {
    // 1. mode not run -> not_run
    if (state.flow.mode !== 'run') {
      return mutationReject('not_run', REASON_TEXT_NOT_RUN);
    }

    // 2. active encounter -> encounter_active
    if (Object.keys(state.run.active_encounter).length > 0) {
      return mutationReject('encounter_active', '遭遇進行中，無法選擇');
    }

    // 3. choices[beatId::groupId] exists -> resolved (no second effect)
    const choiceKey = `${beatId}::${groupId}`;
    if (state.run.choices[choiceKey] !== undefined) {
      return mutationReject('resolved', '');
    }

    // 4. unknown beat -> unknown_beat
    const beat = data.beatsById.get(beatId);
    if (!beat) {
      return mutationReject('unknown_beat', '');
    }

    // 5. slot missing OR slot.choice_group != groupId -> unknown_slot
    const slot = (beat.slots ?? []).find((s) => s.id === slotId);
    if (!slot || slot.choice_group !== groupId) {
      return mutationReject('unknown_slot', '');
    }

    // 6. slot has delegation -> route to delegate
    if (slot.delegation) {
      return delegate(beatId, slotId, cardId);
    }

    // 7. choice_requires_card && empty cardId -> card_required
    if (slot.choice_requires_card === true && (!cardId || cardId.length === 0)) {
      return mutationReject('card_required', '');
    }

    // 8. checkSlotState fail -> its code/text
    const stateResult = checkSlotState(beat, slot, state, data);
    if (!stateResult.ok) {
      return mutationReject(stateResult.reason_code, stateResult.reason_text);
    }

    // 9. cardId given -> shared checkPlace fail -> its code/text
    if (cardId && cardId.length > 0) {
      const placeResult = checkPlace(cardId, beat, slot, state, data);
      if (!placeResult.ok) {
        return mutationReject(placeResult.reason_code, placeResult.reason_text);
      }
    }

    // 10. bookkeeping {choice_key, choice_slot_id, slot_key};
    // ONLY when choice_requires_card && card is protagonist && action phase -> consume_action + attention_npc
    const bk: SettleBookkeeping = {
      choice_key: choiceKey,
      choice_slot_id: slotId,
      slot_key: `${beatId}::${slotId}`,
    };
    if (slot.choice_requires_card === true && cardId && cardId.length > 0) {
      const crBase = cardBaseId(cardId);
      const crCard = data.cardsById.get(crBase);
      const inActionPhase = (ACTION_PHASES as readonly string[]).includes(
        state.run.phase,
      );
      if (crCard?.type === 'protagonist' && inActionPhase) {
        bk.consume_action = true;
        if (
          typeof slot.attention_npc === 'string' &&
          slot.attention_npc.length > 0
        ) {
          bk.attention_npc = slot.attention_npc;
        }
      }
    }

    // 11. settle [slot.on_place] through existing shared settle
    const settleRes = settleEffectsOnDraft(
      [slot.on_place],
      bk,
      {},
      state as GameSnapshot,
      data,
    );
    if (!settleRes.ok) {
      return mutationReject(settleRes.reason_code, settleRes.reason_text);
    }

    commitState(settleRes.nextState);
    notifyListeners();
    return {
      ok: true,
      reason_code: '',
      reason_text: '',
      lines: settleRes.lines,
    };
  }

  function tryPlace(
    cardId: string,
    beatId: string,
    slotId: string,
  ): MutationResult {
    // 1. mode !== 'run'
    if (state.flow.mode !== 'run') {
      return mutationReject('not_run', REASON_TEXT_NOT_RUN);
    }

    // 2. active_encounter
    if (Object.keys(state.run.active_encounter).length > 0) {
      return mutationReject('encounter_active', '遭遇進行中，無法放置卡片');
    }

    // 3. cardId empty -> not_held
    if (cardId.length === 0) {
      return mutationReject('not_held', '');
    }

    // 4. madness instance routed BEFORE beat lookup
    const baseId = cardBaseId(cardId);
    if (baseId === 'madness') {
      return indulge(beatId, slotId, cardId);
    }

    // 5. beat exists
    const beat = data.beatsById.get(beatId);
    if (!beat) {
      return mutationReject('unknown_beat', `未知的 beat：${beatId}`);
    }

    // 6. slot exists
    const slot = (beat.slots ?? []).find((s) => s.id === slotId);
    if (!slot) {
      return mutationReject('unknown_slot', `未知的 slot：${slotId}`);
    }

    // 7. delegation route
    if (slot.delegation) {
      return delegate(beatId, slotId, cardId);
    }

    // 8. choice_group route
    if (
      typeof slot.choice_group === 'string' &&
      slot.choice_group.length > 0
    ) {
      return choose(beatId, slot.choice_group, slotId, cardId);
    }

    // 9. checkPlace
    const checkResult = checkPlace(cardId, beat, slot, state, data);
    if (!checkResult.ok) {
      return mutationReject(
        checkResult.reason_code,
        checkResult.reason_text,
      );
    }

    const card = data.cardsById.get(baseId);
    const isProtagonist = card?.type === 'protagonist';
    const inActionPhase = (ACTION_PHASES as readonly string[]).includes(
      state.run.phase,
    );

    const bk: SettleBookkeeping = {
      slot_key: `${beatId}::${slotId}`,
    };
    if (isProtagonist && inActionPhase) {
      bk.consume_action = true;
      if (
        typeof slot.attention_npc === 'string' &&
        slot.attention_npc.length > 0
      ) {
        bk.attention_npc = slot.attention_npc;
      }
    }

    const settleRes = settleEffectsOnDraft(
      [slot.on_place],
      bk,
      {},
      state as GameSnapshot,
      data,
    );
    if (!settleRes.ok) {
      return mutationReject(settleRes.reason_code, settleRes.reason_text);
    }

    commitState(settleRes.nextState);
    notifyListeners();
    return {
      ok: true,
      reason_code: '',
      reason_text: '',
      lines: settleRes.lines,
    };
  }

  function indulge(
    beatId: string,
    slotId: string,
    cardInstanceId: string,
  ): MutationResult {
    // 1. flow mode gate
    if (state.flow.mode !== 'run') {
      return mutationReject('not_run', REASON_TEXT_NOT_RUN);
    }

    // 2. encounter active
    if (Object.keys(state.run.active_encounter).length > 0) {
      return mutationReject('encounter_active', '遭遇進行中，無法縱慾');
    }

    // 3. card possession & base_id check
    if (!cardInstanceId || !checkHasCard(state, cardInstanceId)) {
      return mutationReject('not_held', '');
    }
    const baseId = cardBaseId(cardInstanceId);
    if (baseId !== 'madness') {
      return mutationReject('not_accepted', '');
    }

    // 4. beat & slot existence, indulgence presence, checkSlotState
    const beat = data.beatsById.get(beatId);
    if (!beat) {
      return mutationReject('unknown_beat', `未知的 beat：${beatId}`);
    }
    const slot = (beat.slots ?? []).find((s) => s.id === slotId);
    if (!slot) {
      return mutationReject('unknown_slot', `未知的 slot：${slotId}`);
    }
    if (!slot.indulgence || typeof slot.indulgence !== 'object') {
      return mutationReject('not_accepted', '');
    }

    const stateResult = checkSlotState(beat, slot, state, data);
    if (!stateResult.ok) {
      return mutationReject(stateResult.reason_code, stateResult.reason_text);
    }

    // 5. soak special case or action spent check
    const isSoak = slot.indulgence.soak === true;
    const soakCost = data.tuning.indulgence.soak_phase_cost;
    if (isSoak) {
      if (state.run.phase !== 'morning') {
        return mutationReject('locked', strings.soakMorningOnly);
      }
      const remActions = remainingActionsToday();
      if (remActions < soakCost) {
        return mutationReject('locked', strings.soakInsufficientActions);
      }
    } else {
      if (
        (ACTION_PHASES as readonly string[]).includes(state.run.phase) &&
        state.run.action_spent
      ) {
        return mutationReject('action_spent', '');
      }
    }

    // 6. cards to lose
    const cardsToLose: string[] = [cardInstanceId];
    if (isSoak) {
      const cardsCleared = data.tuning.indulgence.soak_cards_cleared;
      if (cardsCleared > 1) {
        for (let i = 0; i < state.run.hand.length; i += 1) {
          const c = state.run.hand[i];
          if (cardBaseId(c) === 'madness' && c !== cardInstanceId) {
            cardsToLose.push(c);
            if (cardsToLose.length === cardsCleared) {
              break;
            }
          }
        }
      }
    }

    const preBk: SettleBookkeeping = {
      action_cost: isSoak ? soakCost : 1,
      lose_cards: cardsToLose,
      indulgence_delta: 1,
    };

    const settleRes = settleIndulgenceEffects(
      slot,
      preBk,
      state as GameSnapshot,
      data,
    );
    if (!settleRes.ok) {
      return mutationReject(settleRes.reason_code, settleRes.reason_text);
    }

    commitState(settleRes.nextState);
    notifyListeners();
    return {
      ok: true,
      reason_code: '',
      reason_text: '',
      lines: settleRes.lines,
    };
  }

  function delegate(
    beatId: string,
    slotId: string,
    personCardId: string,
  ): MutationResult {
    // 0. mode not run -> not_run
    if (state.flow.mode !== 'run') {
      return mutationReject('not_run', REASON_TEXT_NOT_RUN);
    }

    // 0.5. active encounter -> encounter_active
    if (Object.keys(state.run.active_encounter).length > 0) {
      return mutationReject('encounter_active', '遭遇進行中，無法委託');
    }

    // 1. 白天行動時段
    if (!(ACTION_PHASES as readonly string[]).includes(state.run.phase)) {
      return mutationReject('not_action_phase', '');
    }

    // 2. beat 存在、時段吻合且 condition 成立
    const beat = data.beatsById.get(beatId);
    if (
      !beat ||
      !isBeatTimeValid(beat, state, data) ||
      !evalCondition(beat.condition, state as GameSnapshot, data)
    ) {
      return mutationReject('unknown_beat', '');
    }

    // 3. slot 存在且 condition 成立
    const slot = (beat.slots ?? []).find((s) => s.id === slotId);
    if (!slot || !evalCondition(slot.condition, state as GameSnapshot, data)) {
      return mutationReject('unknown_slot', '');
    }

    // 4. slot 必須帶 delegation
    if (!isPlainObject(slot.delegation)) {
      return mutationReject('not_delegation', '');
    }
    const delegation = slot.delegation;

    // 5. 卡在手
    if (!personCardId || personCardId.length === 0 || !checkHasCard(state, personCardId)) {
      return mutationReject('not_held', '');
    }

    // 6. 卡型別為 person
    const baseId = cardBaseId(personCardId);
    const card = data.cardsById.get(baseId);
    if (card?.type !== 'person') {
      return mutationReject('not_person', '');
    }

    // 7. accepts 包含該卡 base_id
    const accepts = slot.accepts ?? [];
    if (!accepts.includes(baseId)) {
      return mutationReject('not_accepted', '');
    }

    // 8. 今日未曾受託
    if (state.run.delegates_used_today[baseId] === true) {
      return mutationReject('already_delegated_today', '');
    }

    // 9. beat / slot requires 成立（失敗帶 reject_reason）
    if (!evalCondition(beat.requires, state as GameSnapshot, data)) {
      const text =
        typeof beat.reject_reason === 'string' && beat.reject_reason.length > 0
          ? beat.reject_reason
          : REASON_LOCKED_FALLBACK;
      return mutationReject('locked', text);
    }
    if (!evalCondition(slot.requires, state as GameSnapshot, data)) {
      const text =
        typeof slot.reject_reason === 'string' && slot.reject_reason.length > 0
          ? slot.reject_reason
          : REASON_LOCKED_FALLBACK;
      return mutationReject('locked', text);
    }

    // 10. choice_group 未結算、槽未放置過
    const slotKey = `${beatId}::${slotId}`;
    if (state.run.slots_placed[slotKey] === true) {
      return mutationReject('already_resolved', '');
    }
    const choiceGroup =
      typeof slot.choice_group === 'string' ? slot.choice_group : '';
    if (
      choiceGroup.length > 0 &&
      state.run.choices[`${beatId}::${choiceGroup}`] !== undefined
    ) {
      return mutationReject('already_resolved', '');
    }

    // 11. timing / report 結構合法
    const timing = delegation.result_timing;
    if (timing !== 'immediate' && timing !== 'next_morning') {
      return mutationReject('data_conflict', '');
    }
    if (timing === 'next_morning') {
      if (!isPlainObject(delegation.report)) {
        return mutationReject('data_conflict', '');
      }
    } else if (timing === 'immediate') {
      if ('report' in delegation) {
        return mutationReject('data_conflict', '');
      }
    }

    // ── 成功（原子操作：preflight 全過才 commit）──
    const bookkeeping: SettleBookkeeping = {
      slot_key: slotKey,
      delegate_person: baseId,
    };
    if (choiceGroup.length > 0) {
      bookkeeping.choice_key = `${beatId}::${choiceGroup}`;
      bookkeeping.choice_slot_id = slotId;
    }
    if (timing === 'next_morning') {
      bookkeeping.pending_report = {
        due_day: state.run.day + 1,
        beat_id: beatId,
        slot_id: slotId,
        person_id: baseId,
      };
    }

    const settleRes = settleEffectsOnDraft(
      [slot.on_place],
      bookkeeping,
      {},
      state as GameSnapshot,
      data,
    );
    if (!settleRes.ok) {
      return mutationReject(settleRes.reason_code, settleRes.reason_text);
    }

    commitState(settleRes.nextState);
    notifyListeners();
    return {
      ok: true,
      reason_code: '',
      reason_text: '',
      lines: settleRes.lines,
    };
  }

  function delegationStatus(personCardId: string): DelegationStatus {
    return calcDelegationStatus(state, personCardId);
  }

  function markDelegationTutorialSeen(): void {
    if (!state.meta.delegation_tutorial_seen) {
      const draft = cloneSnapshot(state as GameSnapshot);
      draft.meta.delegation_tutorial_seen = true;
      commitState(draft);
      notifyListeners();
    }
  }

  function endingView(): EndingView {
    return calcEndingView(state, data);
  }

  function hasSeenEnding(endingId: string): boolean {
    return checkHasSeenEnding(state, endingId);
  }

  /** 頁面／結算步驟的共用提交：成功才換入新狀態並通知，失敗零副作用。 */
  function commitEndingStep(step: EndingStep, clearTransientLines = false): MutationResult {
    if (!step.ok) {
      return mutationReject(step.reason_code, step.reason_text);
    }
    commitState(step.nextState);
    if (clearTransientLines) {
      lastChoiceDefaultLines = [];
      lastForcedLines = [];
      lastAutoEnterLines = [];
      lastDelegationReportLines = [];
      phaseNarrationLines = null;
    }
    notifyListeners();
    return { ok: true, reason_code: '', reason_text: '', lines: [] };
  }

  function revealEndingPage(): MutationResult {
    return commitEndingStep(stepRevealEndingPage(state, data));
  }

  function advanceEndingPage(): MutationResult {
    return commitEndingStep(stepAdvanceEndingPage(state, data));
  }

  function skipSeenEnding(): MutationResult {
    return commitEndingStep(stepSkipSeenEnding(state, data));
  }

  function completeEnding(): MutationResult {
    // 唯一收尾：run 的暫態演出文字隨輪結束一併清掉，避免進下一輪殘留。
    return commitEndingStep(stepCompleteEnding(state, data), true);
  }

  function placeableCards(
    beatId: string,
    slotId: string,
  ): readonly string[] {
    return calcPlaceableCards(state, data, beatId, slotId);
  }

  function previewSlot(
    beatId: string,
    slotId: string,
  ): { cards: readonly string[]; reason: string } {
    return calcPreviewSlot(state, data, beatId, slotId);
  }

  function hasAnyLegalAction(): boolean {
    return calcHasAnyLegalAction(state, data);
  }

  function hasUnseenContent(): boolean {
    return calcHasUnseenContent(state, data);
  }

  /** 遭遇 action plan 的唯一落地點（對齊 Godot _commit_encounter_action）。 */
  function commitEncounterAction(plan: {
    blocks: Effect[];
    pre: SettleBookkeeping;
    advance_after: boolean;
  }): MutationResult {
    const settleRes = settleEffectsOnDraft(
      plan.blocks,
      {},
      plan.pre,
      state as GameSnapshot,
      data,
    );
    if (!settleRes.ok) {
      return mutationReject(settleRes.reason_code, settleRes.reason_text);
    }

    if (state.run.active_encounter.stage === 'intro') phaseNarrationLines = null;
    commitState(settleRes.nextState);
    notifyListeners();

    const lines = [...settleRes.lines];
    if (plan.advance_after && state.flow.mode === 'run') {
      const advRes = advancePhase();
      lines.push(...advRes.lines);
    }
    return {
      ok: true,
      reason_code: '',
      reason_text: '',
      lines,
    };
  }

  function encounterView(): EncounterView {
    if (
      Object.keys(state.run.active_encounter).length === 0 ||
      state.flow.mode !== 'run'
    ) {
      return {};
    }
    const beatId = state.run.active_encounter.beat_id ?? '';
    const beat = data.beatsById.get(beatId);
    if (!beat || !beat.encounter) {
      return {};
    }
    return buildEncounterView(
      beat.encounter,
      state.run.active_encounter as ActiveEncounterState,
      state as GameSnapshot,
      data,
    );
  }

  function acknowledgeEncounterIntro(): EncounterAckResult {
    if (state.flow.mode !== 'run') {
      return {
        ...mutationReject('not_run', REASON_TEXT_NOT_RUN),
        entered_round: false,
      };
    }

    // 1. inactive
    if (Object.keys(state.run.active_encounter).length === 0) {
      return {
        ...mutationReject('no_active_encounter', '目前沒有進行中的遭遇'),
        entered_round: false,
      };
    }

    // 2. wrong stage
    if (state.run.active_encounter.stage !== 'intro') {
      return {
        ...mutationReject('wrong_stage', '目前不是開場演出階段'),
        entered_round: false,
      };
    }

    // 3. data conflict
    const beatId = state.run.active_encounter.beat_id ?? '';
    const beat = data.beatsById.get(beatId);
    if (!beat || !beat.encounter) {
      return {
        ...mutationReject('data_conflict', '未知的遭遇事件'),
        entered_round: false,
      };
    }
    const enc = beat.encounter;
    const firstRoundId = getFirstRoundId(enc);
    if (!firstRoundId) {
      return {
        ...mutationReject('data_conflict', '遭遇資料缺少第一回合定義'),
        entered_round: false,
      };
    }
    const firstRound = getRound(enc, firstRoundId);
    if (!firstRound) {
      return {
        ...mutationReject('data_conflict', '遭遇第一回合資料遺失'),
        entered_round: false,
      };
    }

    // 進場與「開場就結束」的失敗出口屬同一個動作：先在複本推演，再一次落地。
    const draft = cloneSnapshot(state as GameSnapshot);
    const shEnc = draft.run.active_encounter;
    let enteredRound = true;
    let outcome = '';

    if (isOverloaded(draft, data)) {
      // 超載時確認開場後立即結算 failure 出口（不進入第一回合、不增加佔格）
      enteredRound = false;
      outcome = 'failure';
    } else {
      const cost = enc.per_round_slot_cost;
      shEnc.stage = 'round';
      shEnc.round_id = firstRoundId;
      shEnc.blocked_slots = (shEnc.blocked_slots ?? 0) + cost;
      const visited = shEnc.visited_round_ids
        ? [...shEnc.visited_round_ids]
        : [];
      if (!visited.includes(firstRoundId)) {
        visited.push(firstRoundId);
      }
      shEnc.visited_round_ids = visited;

      // 佔格達/超出手牌上限，或第一回合就沒有合法動作，都直接走 failure 出口
      if (checkEncounterCapacityFailure(draft, data)) {
        outcome = 'failure';
      } else if (!hasLegalMoves(enc, firstRound, shEnc, draft, data)) {
        outcome = 'failure';
      }
    }

    const plan = planEncounterAction(enc, [], [], shEnc, outcome);
    const res = commitEncounterAction(plan);
    return {
      ...res,
      entered_round: res.ok ? enteredRound : false,
    };
  }

  function respondToEncounter(cardId: string): MutationResult {
    if (state.flow.mode !== 'run') {
      return mutationReject('not_run', REASON_TEXT_NOT_RUN);
    }

    // 1. inactive
    if (Object.keys(state.run.active_encounter).length === 0) {
      return mutationReject('no_active_encounter', '目前沒有進行中的遭遇');
    }

    // 2. wrong stage
    if (state.run.active_encounter.stage !== 'round') {
      return mutationReject('wrong_stage', '目前不是回應回合階段');
    }

    // 3. unknown card
    if (!cardId || typeof cardId !== 'string') {
      return mutationReject('unknown_card', '未知的卡片');
    }
    const baseId = cardBaseId(cardId);
    if (!data.cardsById.has(baseId)) {
      return mutationReject('unknown_card', '未知的卡片');
    }

    // 4. not held
    if (!hasCard(cardId)) {
      return mutationReject('not_held', '未持有該卡片');
    }

    // 5. madness
    if (baseId === 'madness' || state.run.madness_clock[cardId] !== undefined) {
      return mutationReject('madness_blocked', '發狂卡不可作為回應提交');
    }

    // 6. already attempted
    const attempted = state.run.active_encounter.attempted_card_ids ?? [];
    if (attempted.includes(baseId)) {
      return mutationReject('already_attempted', '此卡片本場已嘗試過');
    }

    // 取得當前回合定義
    const beatId = state.run.active_encounter.beat_id ?? '';
    const beat = data.beatsById.get(beatId);
    const enc = beat?.encounter;
    const roundId = state.run.active_encounter.round_id ?? '';
    const roundData = enc ? getRound(enc, roundId) : null;

    const cardDef = data.cardsById.get(baseId)!;
    const isDiscardable = cardDef.discardable === true;
    const matchingResp = roundData
      ? findMatchingResponse(roundData, cardId, baseId)
      : null;
    const fallback = roundData?.fallback;
    const reqDiscardable = fallback?.requires_discardable === true;

    // 7. card not submittable (K-132: 依方針順序先於 data_conflict)
    if (matchingResp === null && reqDiscardable && !isDiscardable) {
      return mutationReject('card_not_submittable', '該卡無法作為錯答提交');
    }

    // 8. data conflict
    if (!roundData || !enc) {
      return mutationReject('data_conflict', '當前回合資料遺失');
    }

    // 通過所有檢查 → 先在複本上把整回合推演到出口
    let draft = cloneSnapshot(state as GameSnapshot);
    let shEnc = draft.run.active_encounter;
    const loseCards: string[] = [];
    const blocks: Effect[] = [];

    const currentAttempted = shEnc.attempted_card_ids
      ? [...shEnc.attempted_card_ids]
      : [];
    currentAttempted.push(baseId);
    shEnc.attempted_card_ids = currentAttempted;

    const cost = enc.per_round_slot_cost;
    const hit = matchingResp !== null;
    const branch = hit ? matchingResp : fallback;

    if (hit) {
      if (matchingResp.consume_card && isDiscardable) {
        loseCards.push(cardId);
      }
      // 正解釋放本回合佔格
      shEnc.blocked_slots = Math.max(0, (shEnc.blocked_slots ?? 0) - cost);
    } else if (isDiscardable) {
      // 錯答保留佔格（不釋放）
      loseCards.push(cardId);
    }

    for (let i = 0; i < loseCards.length; i += 1) {
      loseCard(draft, loseCards[i], data);
    }

    if (branch?.on_resolve && Object.keys(branch.on_resolve).length > 0) {
      blocks.push(branch.on_resolve);
      const pf = planEffects([branch.on_resolve], draft, data);
      if (!pf.ok) return mutationReject(pf.reason_code, pf.reason_text);
      draft = pf.nextState;
      shEnc = draft.run.active_encounter;
    }

    let outcome = '';
    const nextRoundVal = branch?.next_round;
    if (!nextRoundVal) {
      outcome = hit ? 'victory' : 'failure';
    } else {
      const nextRid = nextRoundVal;
      const visited = shEnc.visited_round_ids
        ? [...shEnc.visited_round_ids]
        : [];
      if (visited.includes(nextRid)) {
        // cycle detected
        outcome = 'failure';
      } else {
        visited.push(nextRid);
        shEnc.visited_round_ids = visited;
        shEnc.round_id = nextRid;
        shEnc.blocked_slots = (shEnc.blocked_slots ?? 0) + cost;

        const nextRoundData = getRound(enc, nextRid);
        if (checkEncounterCapacityFailure(draft, data)) {
          outcome = 'failure';
        } else if (
          !nextRoundData ||
          !hasLegalMoves(enc, nextRoundData, shEnc, draft, data)
        ) {
          outcome = 'failure';
        }
      }
    }

    const plan = planEncounterAction(enc, blocks, loseCards, shEnc, outcome);
    return commitEncounterAction(plan);
  }

  function discardInEncounter(cardId: string): MutationResult {
    if (state.flow.mode !== 'run') {
      return mutationReject('not_run', REASON_TEXT_NOT_RUN);
    }

    // 1. inactive
    if (Object.keys(state.run.active_encounter).length === 0) {
      return mutationReject('no_active_encounter', '目前沒有進行中的遭遇');
    }

    // 2. wrong stage
    if (state.run.active_encounter.stage !== 'round') {
      return mutationReject('wrong_stage', '目前不是回應回合階段');
    }

    // 3. discard disabled
    const beatId = state.run.active_encounter.beat_id ?? '';
    const beat = data.beatsById.get(beatId);
    const enc = beat?.encounter;
    if (enc?.allow_discard === false) {
      return mutationReject('discard_disabled', '此遭遇不允許主動丟棄');
    }

    // 4. unknown card
    if (!cardId || typeof cardId !== 'string') {
      return mutationReject('unknown_card', '未知的卡片');
    }
    const baseId = cardBaseId(cardId);
    if (!data.cardsById.has(baseId)) {
      return mutationReject('unknown_card', '未知的卡片');
    }

    // 5. not held
    if (!hasCard(cardId)) {
      return mutationReject('not_held', '未持有該卡片');
    }

    // 6. not discardable
    if (baseId === 'madness' || state.run.madness_clock[cardId] !== undefined) {
      return mutationReject('not_discardable', '發狂卡不可丟棄');
    }
    const cardDef = data.cardsById.get(baseId)!;
    if (cardDef.discardable !== true) {
      return mutationReject('not_discardable', '此卡片不可丟棄');
    }

    const roundId = state.run.active_encounter.round_id ?? '';
    const roundData = enc ? getRound(enc, roundId) : null;
    if (!enc || !roundData) {
      return mutationReject('data_conflict', '當前回合資料遺失');
    }
    // 丟棄先在複本判定，再一次落地
    const draft = cloneSnapshot(state as GameSnapshot);
    loseCard(draft, cardId, data);
    const shEnc = draft.run.active_encounter;
    const outOfMoves = !hasLegalMoves(enc, roundData, shEnc, draft, data);
    const plan = planEncounterAction(
      enc,
      [],
      [cardId],
      shEnc,
      outOfMoves ? 'failure' : '',
    );
    return commitEncounterAction(plan);
  }

  function escapeEncounter(cardIds: readonly string[]): MutationResult {
    if (state.flow.mode !== 'run') {
      return mutationReject('not_run', REASON_TEXT_NOT_RUN);
    }

    // 1. inactive
    if (Object.keys(state.run.active_encounter).length === 0) {
      return mutationReject('no_active_encounter', '目前沒有進行中的遭遇');
    }

    // 2. wrong stage
    if (state.run.active_encounter.stage !== 'round') {
      return mutationReject('wrong_stage', '目前不是回應回合階段');
    }

    // 3. cannot escape
    const beatId = state.run.active_encounter.beat_id ?? '';
    const beat = data.beatsById.get(beatId);
    const enc = beat?.encounter;
    const escVal = enc?.escape_cost;
    if (escVal === null || escVal === undefined) {
      return mutationReject('cannot_escape', '此遭遇無法逃離');
    }

    // 4. wrong escape count
    const escCost = escVal;
    if (cardIds.length !== escCost) {
      return mutationReject('wrong_escape_count', '逃離支付張數不正確');
    }

    // 5. duplicate payment
    const seenIds = new Set<string>();
    for (let i = 0; i < cardIds.length; i += 1) {
      const cid = cardIds[i];
      if (seenIds.has(cid)) {
        return mutationReject('duplicate_payment', '支付卡片重複');
      }
      seenIds.add(cid);
    }

    // 6. unknown card, 7. not held, 8. not discardable
    for (let i = 0; i < cardIds.length; i += 1) {
      const cid = cardIds[i];
      if (!cid || typeof cid !== 'string') {
        return mutationReject('unknown_card', '未知的卡片');
      }
      const baseId = cardBaseId(cid);
      if (!data.cardsById.has(baseId)) {
        return mutationReject('unknown_card', '未知的卡片');
      }
      if (!hasCard(cid)) {
        return mutationReject('not_held', '未持有支付卡片');
      }
      if (baseId === 'madness' || state.run.madness_clock[cid] !== undefined) {
        return mutationReject('not_discardable', '發狂卡不可作為逃離代價');
      }
      const cardDef = data.cardsById.get(baseId)!;
      if (cardDef.discardable !== true) {
        return mutationReject(
          'not_discardable',
          '不可丟棄卡無法作為逃離代價',
        );
      }
    }

    const paid = [...cardIds];
    const plan = planEncounterAction(enc!, [], paid, {}, 'escape');
    return commitEncounterAction(plan);
  }

  return {
    getSnapshot,
    serialize,
    subscribe,
    chapter,
    openingScreenView,
    openingView,
    getOpeningScreenView: openingScreenView,
    getOpeningView: openingView,
    getPhaseView,
    availableLocations,
    mapView,
    buildPanel,
    remainingActionsToday,
    markDayLocationVisited,
    hasCard,
    hasKnowledge,
    handSlotsUsed,
    handCapacity,
    cardView,
    handView,
    knowledgeView,
    chooseOpening,
    playBeat,
    playEvening,
    playNightFixed,
    choose,
    tryPlace,
    delegate,
    delegationStatus,
    markDelegationTutorialSeen,
    indulge,
    placeableCards,
    previewSlot,
    hasAnyLegalAction,
    hasUnseenContent,
    advancePhase,
    nightLocationSummary,
    resolvedNightContent,
    enterNightLocation,
    alignmentOffer,
    confirmNightAlignment,
    endingView,
    hasSeenEnding,
    revealEndingPage,
    advanceEndingPage,
    skipSeenEnding,
    completeEnding,
    encounterView,
    acknowledgeEncounterIntro,
    respondToEncounter,
    discardInEncounter,
    escapeEncounter,
  };
}
