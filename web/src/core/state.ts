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

import type { Beat, Condition, Effect, GameData } from '../data/types';
import {
  cardView as calcCardView,
  handSlotsUsed as calcHandSlotsUsed,
  handView as calcHandView,
  hasCard as checkHasCard,
  hasKnowledge as checkHasKnowledge,
  knowledgeView as calcKnowledgeView,
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
  ACTION_PHASES,
  LAST_DAY,
  beatsAt,
  cardBaseId,
  chapterForDay,
  isNarrationOnlyPhase,
  nextPhaseTarget,
} from './facts';
import { nightBeatCandidates, recordForcedNightVisit } from './night';
import {
  availableLocations as calcAvailableLocations,
  buildPanel as calcBuildPanel,
  mapView as calcMapView,
  remainingActionsToday as calcRemainingActionsToday,
  type MapLocationView,
  type PanelView,
} from './panel';
import {
  checkPlace,
  checkSlotState,
  hasAnyLegalAction as calcHasAnyLegalAction,
  hasUnseenContent as calcHasUnseenContent,
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
  AdvanceResult,
  CardView,
  DeepReadonly,
  Game,
  GameSnapshot,
  MutationResult,
  OpeningOptionView,
  OpeningScreenView,
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
  if (bk.day_location_visited) {
    recordDayLocationVisitedOnDraft(target, bk.day_location_visited, data);
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

function isWithinPlayableRange(day: number, phase: string): boolean {
  if (day === 1 || day === 2) {
    return true;
  }
  if (day === 3) {
    return phase === 'morning' || phase === 'afternoon' || phase === 'evening';
  }
  return false;
}

interface AdvancePlanResult {
  readonly ok: boolean;
  readonly reason_code: ReasonCode;
  readonly reason_text: string;
  readonly nextState: GameSnapshot;
  readonly defaultLines: string[];
  readonly autoEnterLines: string[];
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
    autoEnterLines: [],
  };
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

  // ③ 夜間停拍：當 phase === 'night' && night_location_chosen === '' && !night_sleep_pending 時檢查就寢候選
  if (
    currentState.run.phase === 'night' &&
    currentState.run.night_location_chosen === '' &&
    !currentState.run.night_sleep_pending
  ) {
    const candidates = nightBeatCandidates(
      currentState.run.day,
      'sanquan',
      chapterForDay(currentState.run.day),
      data,
    );
    const allSleepCandidates = [...candidates.primaries, ...candidates.addons];
    for (let i = 0; i < allSleepCandidates.length; i += 1) {
      const sb = allSleepCandidates[i];
      let condOk = false;
      try {
        condOk = evalCondition(sb.condition, currentState, data);
      } catch (err) {
        if (err instanceof UnsupportedConditionError) {
          return rejectAdvancePlan(
            currentState,
            'not_implemented',
            '夜間就寢解析將於 W6-E1 實作',
          );
        }
        if (err instanceof ConditionError) {
          return rejectAdvancePlan(currentState, 'data_conflict', err.message);
        }
        throw err;
      }
      if (condOk) {
        return rejectAdvancePlan(
          currentState,
          'not_implemented',
          '夜間就寢停拍將於 W6-E1 實作',
        );
      }
    }
  }

  // ④ 逾期 choice group default 預檢（在 draft 上 preflight，不直接落地）
  let draft = cloneSnapshot(currentState);
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
  const gate = evaluatePhaseExitGate(currentState, data);
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
    if (!data.endingsById.has(gate.ending)) {
      return rejectAdvancePlan(
        currentState,
        'data_conflict',
        `未知的結局：${gate.ending}`,
      );
    }
    return rejectAdvancePlan(
      currentState,
      'not_implemented',
      'D45 結局收束將於 W7-A 實作',
    );
  }

  const target = nextPhaseTarget(currentState.run.day, currentState.run.phase);
  if (target.day > LAST_DAY) {
    return rejectAdvancePlan(
      currentState,
      'data_conflict',
      '推進目標超出最後一天',
    );
  }

  // W5 公開推進範圍與後續子階段換時段機制守衛
  if (!isWithinPlayableRange(target.day, target.phase)) {
    return rejectAdvancePlan(
      currentState,
      'not_implemented',
      'D3 evening 之後的時段推進將於 W6 接手',
    );
  }
  if (
    currentState.run.phase === 'night' &&
    Object.keys(draft.run.madness_clock).length > 0
  ) {
    return rejectAdvancePlan(
      currentState,
      'not_implemented',
      '發狂倒數計時將於 W6-A 實作',
    );
  }
  if (draft.run.actions_spent_ahead > 0) {
    return rejectAdvancePlan(
      currentState,
      'not_implemented',
      '預扣行動格將於 W6-B 實作',
    );
  }
  if (
    (ACTION_PHASES as readonly string[]).includes(target.phase) &&
    draft.run.forced_pending.length > 0
  ) {
    return rejectAdvancePlan(
      currentState,
      'not_implemented',
      '強制縱慾結算將於 W6-B 實作',
    );
  }
  if (
    target.phase === 'morning' &&
    (draft.run.pending_delegation_reports.length > 0 ||
      Object.keys(draft.run.delegates_used_today).length > 0)
  ) {
    return rejectAdvancePlan(
      currentState,
      'not_implemented',
      '委託隔日回報將於 W6-C 實作',
    );
  }

  // ⑦ 在 draft 上更新 day/phase、重設當日時段狀態、結算新時段 auto_enter 與固定遭遇檢查
  draft.run.day = target.day;
  draft.run.phase = target.phase;
  draft.run.action_spent = false;
  draft.run.night_location_chosen = '';
  draft.run.night_sleep_pending = false;

  const autoRes = settleAutoEnterBeatsOnDraft(draft, data);
  if (!autoRes.ok) {
    return rejectAdvancePlan(
      currentState,
      autoRes.reason_code,
      autoRes.reason_text,
    );
  }
  draft = autoRes.nextState;

  // 目標時段 fixed encounter 預檢（在 auto_enter 之後檢查，以涵蓋 auto_enter 寫入之條件）
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
    const errText = encounterDataError(tb);
    if (errText.length > 0) {
      return rejectAdvancePlan(currentState, 'data_conflict', errText);
    }
    return rejectAdvancePlan(
      currentState,
      'not_implemented',
      '固定遭遇啟動將於 W6-D 實作',
    );
  }

  return {
    ok: true,
    reason_code: '',
    reason_text: '',
    nextState: draft,
    defaultLines,
    autoEnterLines: autoRes.lines,
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
  let lastAutoEnterLines: string[] = [];
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

  function getPhaseView(): PhaseView {
    const day = state.run.day;
    const phase = state.run.phase;
    const ch = chapterForDay(day);
    const narrationOnly = isNarrationOnlyPhase(day, phase);
    const canAdv = canCurrentlyAdvance();
    const lines: string[] = [
      ...lastChoiceDefaultLines,
      ...lastAutoEnterLines,
      ...(phaseNarrationLines ?? []),
    ];
    return {
      day,
      phase,
      chapter: ch,
      narration_only: narrationOnly,
      isNarrationOnly: narrationOnly,
      lines,
      can_advance: canAdv,
      canAdvance: canAdv,
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
    lastAutoEnterLines = combinedLines;
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
        if (
          isPlainObject(b.encounter) &&
          b.encounter.charge_first_visit === true &&
          !wasSeen &&
          (loc.madness_cost ?? 0) > 0
        ) {
          return mutationReject(
            'not_implemented',
            'charge_first_visit 發狂卡計費將於 W6 實作',
          );
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
        return mutationReject('not_implemented', '遭遇戰將於 W6-D 實作');
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
    lastChoiceDefaultLines = plan.defaultLines;
    lastAutoEnterLines = plan.autoEnterLines;
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

    // 6. slot has delegation -> route to delegate (W6: atomic not_implemented)
    if (slot.delegation) {
      return mutationReject('not_implemented', '委託系統將於 W6-C 實作');
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
      return mutationReject('not_implemented', '縱慾系統將於 W6-B 實作');
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
      return mutationReject('not_implemented', '委託系統將於 W6-C 實作');
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
      lastAutoEnterLines = [];
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
    placeableCards,
    previewSlot,
    hasAnyLegalAction,
    hasUnseenContent,
    advancePhase,
    endingView,
    hasSeenEnding,
    revealEndingPage,
    advanceEndingPage,
    skipSeenEnding,
    completeEnding,
  };
}
