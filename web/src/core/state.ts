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

import type { Beat, Condition, GameData } from '../data/types';
import { ConditionError, UnsupportedConditionError, evalCondition } from './condition';
import { planEffects } from './effect';
import {
   ACTION_PHASES,
  LAST_DAY,
  beatsAt,
  chapterForDay,
  isNarrationOnlyPhase,
  nextPhaseTarget,
} from './facts';
import { nightBeatCandidates, recordForcedNightVisit } from './night';
import {
  cloneSnapshot,
  createInitialSnapshot,
  initializeRun,
} from './run-initialization';
import type {
  AdvanceResult,
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

  let next = cloneSnapshot(draft);
  const isFirst = !next.run.beats_entered[beatId];

  if (isFirst) {
    const pf = planEffects([beat.on_enter], next, data);
    if (!pf.ok) {
      return {
        ok: false,
        reason_code: pf.reason_code,
        reason_text: pf.reason_text,
        lines: [],
        nextState: draft,
      };
    }
    if (pf.endingRequest !== null) {
      return {
        ok: false,
        reason_code: 'not_implemented',
        reason_text: '結局轉換將於 W7-A 實作',
        lines: [],
        nextState: draft,
      };
    }
    next = pf.nextState;
    lines.push(...pf.lines);
    next.run.beats_entered[beatId] = true;
  }

  if (typeof beat.location === 'string' && beat.location.length > 0) {
    const loc = data.locationsById.get(beat.location);
    if (loc?.layer === 'day') {
      next.meta.day_locations_visited[beat.location] = true;
    }
  }

  return {
    ok: true,
    reason_code: '',
    reason_text: '',
    lines,
    nextState: next,
  };
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

function isWithinW3PlayableRange(day: number, phase: string): boolean {
  return day === 1 || (day === 2 && phase === 'morning');
}

export function createGame(
  data: GameData,
  initialState?: GameSnapshot,
): Game {
  let state: GameSnapshot = initialState
    ? cloneSnapshot(initialState)
    : createInitialSnapshot();

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
    state = cloneSnapshot(nextState);
  }

  function getSnapshot(): Readonly<GameSnapshot> {
    return state;
  }

  function serialize(): GameSnapshot {
    return cloneSnapshot(state);
  }

  function subscribe(listener: () => void): () => void {
    listeners.add(listener);
    return () => {
      listeners.delete(listener);
    };
  }

  function getOpeningScreenView(): OpeningScreenView {
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

  function getOpeningView(): readonly OpeningOptionView[] {
    const out: OpeningOptionView[] = [];
    for (let i = 0; i < data.openingChoices.length; i += 1) {
      const choice = data.openingChoices[i];
      let available = false;
      try {
        available = evalCondition(choice.requires, state, data);
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
    if (state.flow.mode !== 'run') {
      return false;
    }
    if (Object.keys(state.run.active_encounter).length > 0) {
      return false;
    }
    const gate = evaluatePhaseExitGate(state, data);
    if (!gate.ok) {
      return false;
    }
    if (gate.has_gate && !gate.satisfied) {
      return false;
    }
    if (
      state.run.day === LAST_DAY &&
      state.run.phase === 'evening' &&
      gate.ending === ''
    ) {
      return false;
    }
    if (gate.ending !== '') {
      return false;
    }
    const target = nextPhaseTarget(state.run.day, state.run.phase);
    if (target.day > LAST_DAY) {
      return false;
    }
    if (!isWithinW3PlayableRange(target.day, target.phase)) {
      return false;
    }
    return true;
  }

  function getPhaseView(): PhaseView {
    const day = state.run.day;
    const phase = state.run.phase;
    const chapter = chapterForDay(day);
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
      chapter,
      narration_only: narrationOnly,
      isNarrationOnly: narrationOnly,
      lines,
      can_advance: canAdv,
      canAdvance: canAdv,
    };
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
      unlocked = evalCondition(choice.requires, state, data);
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
      const endingId = String(rawChoice.ending);
      if (!data.endingsById.has(endingId)) {
        return mutationReject('data_conflict', `未知的結局：${endingId}`);
      }
      return mutationReject(
        'not_implemented',
        '開局直通結局將於 W7-A 實作',
      );
    }

    // on_select 分支：在複本上初始化 run 並預演 on_select 與 D1 morning auto_enter
    const initDraft = initializeRun(state, data);
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
    const res = playBeatOnDraft(state, beatId, data);
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

    let draft = cloneSnapshot(state);
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

    let draft = cloneSnapshot(state);
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
    // ① flow.mode !== 'run' -> not_run
    if (state.flow.mode !== 'run') {
      return advanceReject('not_run', REASON_TEXT_NOT_RUN);
    }

    // ② active_encounter 非空 -> encounter_active
    if (Object.keys(state.run.active_encounter).length > 0) {
      return advanceReject('encounter_active', '遭遇進行中，無法推進時段');
    }

    // ③ 夜間停拍：當 phase === 'night' && night_location_chosen === '' && !night_sleep_pending 時檢查就寢候選
    if (
      state.run.phase === 'night' &&
      state.run.night_location_chosen === '' &&
      !state.run.night_sleep_pending
    ) {
      const candidates = nightBeatCandidates(
        state.run.day,
        'sanquan',
        chapterForDay(state.run.day),
        data,
      );
      const allSleepCandidates = [...candidates.primaries, ...candidates.addons];
      for (let i = 0; i < allSleepCandidates.length; i += 1) {
        const sb = allSleepCandidates[i];
        let condOk = false;
        try {
          condOk = evalCondition(sb.condition, state, data);
        } catch (err) {
          if (err instanceof UnsupportedConditionError) {
            return advanceReject(
              'not_implemented',
              '夜間就寢解析將於 W6-E1 實作',
            );
          }
          if (err instanceof ConditionError) {
            return advanceReject('data_conflict', err.message);
          }
          throw err;
        }
        if (condOk) {
          return advanceReject(
            'not_implemented',
            '夜間就寢停拍將於 W6-E1 實作',
          );
        }
      }
    }

    // ④ 逾期 choice group default 預檢（在 draft 上 preflight，不直接落地）
    let draft = cloneSnapshot(state);
    const defaultLines: string[] = [];
    const currentBeats = beatsAt(data.beats, state.run.day, state.run.phase);

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
          return advanceReject('not_implemented', err.message);
        }
        if (err instanceof ConditionError) {
          return advanceReject('unresolved_choice_conflict', err.message);
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
            return advanceReject('not_implemented', pf.reason_text);
          }
          return advanceReject('unresolved_choice_conflict', pf.reason_text);
        }
        if (pf.endingRequest !== null) {
          return advanceReject(
            'unresolved_choice_conflict',
            '逾期預設不得啟動結局',
          );
        }
        draft = pf.nextState;
        defaultLines.push(...pf.lines);
      }
    }

    // ⑤ fixed beat 的 phase_exit 門檻檢查
    const gate = evaluatePhaseExitGate(state, data);
    if (!gate.ok) {
      return advanceReject(gate.reason_code, gate.reason_text);
    }
    if (gate.has_gate && !gate.satisfied) {
      return advanceReject(
        'phase_requirements_incomplete',
        '本時段的內容尚未完成',
      );
    }
    if (
      state.run.day === LAST_DAY &&
      state.run.phase === 'evening' &&
      gate.ending === ''
    ) {
      return advanceReject(
        'phase_requirements_incomplete',
        '本時段的內容尚未完成',
      );
    }

    // ⑥ 目標時段與可能結局／到期遭遇預檢
    if (gate.ending !== '') {
      if (!data.endingsById.has(gate.ending)) {
        return advanceReject('data_conflict', `未知的結局：${gate.ending}`);
      }
      return advanceReject('not_implemented', 'D45 結局收束將於 W7-A 實作');
    }

    const target = nextPhaseTarget(state.run.day, state.run.phase);
    if (target.day > LAST_DAY) {
      return advanceReject('data_conflict', '推進目標超出最後一天');
    }

    // 目標時段 fixed encounter 預檢
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
          return advanceReject('not_implemented', err.message);
        }
        if (err instanceof ConditionError) {
          return advanceReject('data_conflict', err.message);
        }
        throw err;
      }
      if (!encActive) {
        continue;
      }
      const errText = encounterDataError(tb);
      if (errText.length > 0) {
        return advanceReject('data_conflict', errText);
      }
      return advanceReject('not_implemented', '固定遭遇啟動將於 W6-D 實作');
    }

    // W3 公開推進範圍與後續子階段換時段機制守衛
    if (!isWithinW3PlayableRange(target.day, target.phase)) {
      return advanceReject(
        'not_implemented',
        'D2 morning 之後的時段推進將於 W4 接手',
      );
    }
    if (
      state.run.phase === 'night' &&
      Object.keys(draft.run.madness_clock).length > 0
    ) {
      return advanceReject('not_implemented', '發狂倒數計時將於 W6-A 實作');
    }
    if (draft.run.actions_spent_ahead > 0) {
      return advanceReject(
        'not_implemented',
        '預扣行動格將於 W6-B 實作',
      );
    }
    if (
      (ACTION_PHASES as readonly string[]).includes(target.phase) &&
      draft.run.forced_pending.length > 0
    ) {
      return advanceReject('not_implemented', '強制縱慾結算將於 W6-B 實作');
    }
    if (
      target.phase === 'morning' &&
      (draft.run.pending_delegation_reports.length > 0 ||
        Object.keys(draft.run.delegates_used_today).length > 0)
    ) {
      return advanceReject('not_implemented', '委託隔日回報將於 W6-C 實作');
    }

    // ⑦ 原子提交：更新 day/phase、重設當日時段狀態、在 draft 上結算新時段 auto_enter
    draft.run.day = target.day;
    draft.run.phase = target.phase;
    draft.run.action_spent = false;
    draft.run.night_location_chosen = '';
    draft.run.night_sleep_pending = false;

    const autoRes = settleAutoEnterBeatsOnDraft(draft, data);
    if (!autoRes.ok) {
      return advanceReject(autoRes.reason_code, autoRes.reason_text);
    }

    commitState(autoRes.nextState);
    lastChoiceDefaultLines = defaultLines;
    lastAutoEnterLines = autoRes.lines;
    phaseNarrationLines = null;
    notifyListeners();

    return {
      ok: true,
      reason_code: '',
      reason_text: '',
      lines: defaultLines,
      phase_advanced: true,
    };
  }

  return {
    getSnapshot,
    serialize,
    subscribe,
    getOpeningScreenView,
    getOpeningView,
    getPhaseView,
    chooseOpening,
    playBeat,
    playEvening,
    playNightFixed,
    advancePhase,
  };
}
