import { describe, it, expect } from 'vitest';
import {
  LAST_DAY,
  beatMatchesTime,
  beatsAt,
  cardBaseId,
  chapterForDay,
  isNarrationOnlyPhase,
  nextPhase,
  nextPhaseTarget,
  phasesForDay,
  tuningValue,
} from '../src/core/facts';
import type { Beat, Tuning } from '../src/data/types';

const tuning: Tuning = {
  hand_size: 14,
  phases_per_day: 3,
  madness_cap: 8,
  madness_countdown_days: 7,
  madness_vision_threshold: 3,
  reserve_capacity: null,
  indulgence: {
    soak_phase_cost: 2,
    soak_cards_cleared: 3,
    forced_light_count: 1,
    forced_normal_until: 2,
  },
};

describe('W2-A core facts', () => {
  it('tuningValue reads a nested key and throws for a missing key', () => {
    expect(tuningValue(tuning, 'indulgence.soak_phase_cost')).toBe(2);
    expect(tuningValue(tuning, 'hand_size')).toBe(14);
    expect(() => tuningValue(tuning, 'no.such.key')).toThrow(
      'tuning 缺少必要鍵：no.such.key',
    );
    expect(() => tuningValue(tuning, 'indulgence.nope')).toThrow();
  });

  it('chapterForDay boundaries 15/16 and 32/33', () => {
    expect(chapterForDay(1)).toBe(1);
    expect(chapterForDay(15)).toBe(1);
    expect(chapterForDay(16)).toBe(2);
    expect(chapterForDay(32)).toBe(2);
    expect(chapterForDay(33)).toBe(3);
    expect(chapterForDay(45)).toBe(3);
  });

  it('isNarrationOnlyPhase list', () => {
    expect(isNarrationOnlyPhase(1, 'morning')).toBe(true);
    expect(isNarrationOnlyPhase(1, 'afternoon')).toBe(true);
    expect(isNarrationOnlyPhase(1, 'evening')).toBe(false);
    expect(isNarrationOnlyPhase(2, 'morning')).toBe(false);
  });

  it('cardBaseId strips the last # suffix', () => {
    expect(cardBaseId('madness#1')).toBe('madness');
    expect(cardBaseId('a#b#c')).toBe('a#b');
    expect(cardBaseId('protagonist')).toBe('protagonist');
    expect(cardBaseId('k_not_today')).toBe('k_not_today');
  });

  it('beatMatchesTime: exact day', () => {
    expect(beatMatchesTime({ day: 3, phase: 'morning' }, 3, 'morning')).toBe(true);
    expect(beatMatchesTime({ day: 3, phase: 'morning' }, 4, 'morning')).toBe(false);
    expect(beatMatchesTime({ day: 3, phase: 'morning' }, 3, 'afternoon')).toBe(false);
  });

  it('beatMatchesTime: day_from/day_to range with phase array', () => {
    const when = { day_from: 1, day_to: 45, phase: ['morning', 'afternoon'] as const };
    expect(beatMatchesTime(when, 10, 'morning')).toBe(true);
    expect(beatMatchesTime(when, 10, 'afternoon')).toBe(true);
    expect(beatMatchesTime(when, 10, 'evening')).toBe(false);
    expect(beatMatchesTime(when, 46, 'morning')).toBe(false);
    expect(beatMatchesTime(when, 0, 'morning')).toBe(false);
  });

  it('beatMatchesTime: day_from default 1, day_to default 45, missing when false', () => {
    const rangeOnly = { day_from: 5, day_to: 10, phase: 'afternoon' } as const;
    expect(beatMatchesTime(rangeOnly, 7, 'afternoon')).toBe(true);
    expect(beatMatchesTime(rangeOnly, 4, 'afternoon')).toBe(false);
    expect(beatMatchesTime(rangeOnly, 11, 'afternoon')).toBe(false);
    expect(beatMatchesTime(undefined, 3, 'morning')).toBe(false);
    expect(beatMatchesTime(null, 3, 'morning')).toBe(false);
  });

  it('beatMatchesTime: day + day_from is rejected', () => {
    expect(beatMatchesTime({ day: 3, day_from: 1 }, 3, 'morning')).toBe(false);
  });

  it('phasesForDay and nextPhaseTarget handle normal days and D45 (no night)', () => {
    expect(phasesForDay(1)).toEqual(['morning', 'afternoon', 'evening', 'night']);
    expect(phasesForDay(LAST_DAY)).toEqual(['morning', 'afternoon', 'evening']);
    expect(nextPhase('evening', 1)).toBe('night');
    expect(nextPhase('evening', LAST_DAY)).toBeNull();
    expect(nextPhaseTarget(1, 'morning')).toEqual({ day: 1, phase: 'afternoon' });
    expect(nextPhaseTarget(1, 'night')).toEqual({ day: 2, phase: 'morning' });
    expect(nextPhaseTarget(LAST_DAY, 'afternoon')).toEqual({ day: LAST_DAY, phase: 'evening' });
    expect(nextPhaseTarget(LAST_DAY, 'evening')).toEqual({ day: LAST_DAY + 1, phase: 'morning' });
  });

  it('beatsAt filters beats by (day, phase) preserving array order', () => {
    const sampleBeats: Beat[] = [
      { id: 'b1', location: 'busstop', when: { day: 1, phase: 'morning' }, text: 'a' },
      { id: 'b2', location: 'busstop', when: { day: 1, phase: 'afternoon' }, text: 'b' },
      { id: 'b3', location: 'sanquan', when: { day_from: 1, day_to: 3, phase: ['morning', 'evening'] }, text: 'c' },
    ];
    expect(beatsAt(sampleBeats, 1, 'morning').map((b) => b.id)).toEqual(['b1', 'b3']);
    expect(beatsAt(sampleBeats, 1, 'afternoon').map((b) => b.id)).toEqual(['b2']);
    expect(beatsAt(sampleBeats, 2, 'evening').map((b) => b.id)).toEqual(['b3']);
  });
});
