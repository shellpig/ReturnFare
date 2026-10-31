/**
 * ReturnFare Web — 純結構事實（W2-A）。
 *
 * 移植 scripts/core/data_facts.gd：章節、四時段、行動時段、刻意留空／純演出／
 * choice-only 名單、已接受的待建卡引用、beatMatchesTime、cardBaseId。
 * 純函式，不 import React、DOM 或 node：*；玩法數值皆從 tuning 透過 tuningValue 取得，
 * 不把 tuning.phases_per_day 當成時段機的自由參數。
 */

import { PHASES, type Beat, type Phase, type When } from '../data/types';

/** 全時段與行動時段只定義在 data/types.ts，這裡轉出，不另存一份。 */
export { PHASES, ACTION_PHASES } from '../data/types';

/** 單輪最後一天（D45 黃昏收束，無第 45 夜） */
export const LAST_DAY = 45;

/** 章節起始天數（第 1、2、3 章） */
export const CHAPTER_START_DAYS: readonly number[] = [1, 16, 33];

/** 刻意設計為完全無任何 beat 的行動時段 */
export const BY_DESIGN_EMPTY_PHASES: readonly { readonly day: number; readonly phase: Phase }[] = [
  { day: 32, phase: 'afternoon' },
];

/** 純演出時段：有 fixed auto_enter beat，玩家不選地點也不放卡 */
export const NARRATION_ONLY_PHASES: readonly { readonly day: number; readonly phase: Phase }[] = [
  { day: 1, phase: 'morning' },
  { day: 1, phase: 'afternoon' },
];

/** 有 beat 僅有 choice 槽、無主角卡槽的行動時段 */
export const BY_DESIGN_CHOICE_ONLY_PHASES: readonly { readonly day: number; readonly phase: Phase }[] = [
  { day: 35, phase: 'afternoon' },
  { day: 40, phase: 'morning' },
  { day: 43, phase: 'afternoon' },
];

/** 差免費槽 beat 名單（lint 豁免） */
export const BY_DESIGN_CHOICE_ONLY_BEATS: readonly string[] = [
  'd35_pm_answer',
  'd40_tell_someone',
  'd43_conclusion',
  'd43_morning_ask_paper',
];

/** 待決尚未建檔但已知在 requires 佔位的卡片 id */
export const BY_DESIGN_PENDING_CARD_REFS: readonly string[] = ['card_money'];

export function chapterForDay(day: number): number {
  for (let i = CHAPTER_START_DAYS.length - 1; i >= 0; i -= 1) {
    if (day >= CHAPTER_START_DAYS[i]) {
      return i + 1;
    }
  }
  return 1;
}

export function isEmptyPhaseByDesign(day: number, phase: Phase): boolean {
  return BY_DESIGN_EMPTY_PHASES.some((p) => p.day === day && p.phase === phase);
}

export function isNarrationOnlyPhase(day: number, phase: Phase): boolean {
  return NARRATION_ONLY_PHASES.some((p) => p.day === day && p.phase === phase);
}

export function isChoiceOnlyPhaseByDesign(day: number, phase: Phase): boolean {
  return BY_DESIGN_CHOICE_ONLY_PHASES.some((p) => p.day === day && p.phase === phase);
}

export function isPendingCardRefByDesign(cardId: string): boolean {
  return BY_DESIGN_PENDING_CARD_REFS.includes(cardId);
}

const DAY_45_PHASES: readonly Phase[] = ['morning', 'afternoon', 'evening'];

/** 該日存在哪些時段（D45 收束於黃昏，無夜間）。 */
export function phasesForDay(day: number): readonly Phase[] {
  if (day === LAST_DAY) {
    return DAY_45_PHASES;
  }
  return PHASES;
}

/**
 * 時段先後（同一輪內）：morning → afternoon → evening → night；夜後為 null。
 * 若提供 day === 45，evening 之後即為 null（無第 45 夜）。
 */
export function nextPhase(phase: Phase, day?: number): Phase | null {
  const dayPhases = day !== undefined ? phasesForDay(day) : PHASES;
  const index = dayPhases.indexOf(phase);
  if (index < 0 || index === dayPhases.length - 1) {
    return null;
  }
  return dayPhases[index + 1];
}

/**
 * 單一時段推進的下一個 (day, phase) 目標（Godot GameState.next_phase_target）。
 * 當日時段走到底時進到 day + 1 的 morning（例如 D45 evening 會得到 { day: 46, phase: 'morning' }，由呼叫端攔截結局或越界）。
 */
export function nextPhaseTarget(day: number, phase: Phase): { day: number; phase: Phase } {
  const next = nextPhase(phase, day);
  if (next === null) {
    return { day: day + 1, phase: 'morning' };
  }
  return { day, phase: next };
}

/**
 * 某一天某個時段有哪些 beat（不解 condition，只挑時間對的，保留 beats 原序）。
 * 對應 DataLoader.beats_at(day, phase)。
 */
export function beatsAt(beats: readonly Beat[], day: number, phase: Phase): Beat[] {
  const out: Beat[] = [];
  for (let i = 0; i < beats.length; i += 1) {
    const b = beats[i];
    if (beatMatchesTime(b.when, day, phase)) {
      out.push(b);
    }
  }
  return out;
}

/**
 * beat 在給定 (day, phase) 是否成立。僅負責有 when beat 的日期／時段判準。
 * 複製 data_facts.gd beat_matches_time 邏輯，含 day+day_from 拒絕。
 */
export function beatMatchesTime(when: When | null | undefined, day: number, phase: Phase): boolean {
  if (!when || typeof when !== 'object') {
    return false;
  }

  const w = when as { day?: number; day_from?: number; day_to?: number; phase?: unknown };

  // day 與 day_from 不得同時出現
  if (w.day !== undefined && w.day_from !== undefined) {
    return false;
  }

  // 日期比對
  if (w.day !== undefined) {
    if (w.day !== day) {
      return false;
    }
  } else if (w.day_from !== undefined || w.day_to !== undefined) {
    const from_d = w.day_from !== undefined ? w.day_from : 1;
    const to_d = w.day_to !== undefined ? w.day_to : 45;
    if (day < from_d || day > to_d) {
      return false;
    }
  } else {
    return false;
  }

  // 時段比對：字串或陣列，缺欄不成立
  const p_val = w.phase;
  if (Array.isArray(p_val)) {
    if (!p_val.includes(phase)) {
      return false;
    }
  } else if (typeof p_val === 'string') {
    if (p_val !== phase) {
      return false;
    }
  } else {
    return false;
  }

  return true;
}

/** 取得卡片 base id（去除最後一個 #... 實例後綴，madness#1 -> madness）。 */
export function cardBaseId(id: string): string {
  const hashIdx = id.lastIndexOf('#');
  if (hashIdx >= 0) {
    return id.slice(0, hashIdx);
  }
  return id;
}

/**
 * tuning 點路徑查詢（例：tuningValue(tuning, 'indulgence.soak_phase_cost')）。
 * 鍵缺失一律拋錯，不靜默預設。
 */
export function tuningValue(tuning: unknown, dotPath: string): unknown {
  let node: unknown = tuning;
  const parts = dotPath.split('.');
  for (let i = 0; i < parts.length; i += 1) {
    const part = parts[i];
    if (
      node === null ||
      node === undefined ||
      typeof node !== 'object' ||
      Array.isArray(node) ||
      !(part in (node as Record<string, unknown>))
    ) {
      throw new Error(`tuning 缺少必要鍵：${dotPath}`);
    }
    node = (node as Record<string, unknown>)[part];
  }
  return node;
}
