import { beforeAll, describe, expect, it } from 'vitest';
import {
  ConditionError,
  evalCondition,
  hasSeenEnding,
  hasSeenNightLocation,
  relationAtLeast,
} from '../src/core/condition';
import { createGame } from '../src/core/state';
import type { EndingHistoryRecord, GameSnapshot } from '../src/core/state-types';
import { loadGameDataNode } from '../src/data/load-node';
import type { Condition, GameData } from '../src/data/types';
import {
  CONDITION_OPERATORS,
  type ConditionOperator,
} from '../src/data/vocabulary';

function makeHistoryRecord(endingId: string): EndingHistoryRecord {
  return {
    run_number: 1,
    ending_id: endingId,
    opening_choice_id: 'take_family_album',
    ended_day: 45,
    ended_phase: 'evening',
    partner_variant: 'partner_none',
    livelihood_variant: 'livelihood_default',
    inn_appearance_variant: 'inn_default',
    festival_proxy_npc: 'ajie',
    knowledge_gained_this_run: [],
  };
}

interface OperatorCase {
  readonly operator: ConditionOperator;
  readonly label: string;
  readonly condition: Condition;
  readonly setup?: (state: GameSnapshot) => void;
  readonly expected: boolean;
}

const OPERATOR_TABLE: readonly OperatorCase[] = [
  // 1. day
  {
    operator: 'day',
    label: 'day matches current run.day',
    condition: { day: 3 },
    setup: (s) => {
      s.run.day = 3;
    },
    expected: true,
  },
  {
    operator: 'day',
    label: 'day does not match current run.day',
    condition: { day: 3 },
    setup: (s) => {
      s.run.day = 2;
    },
    expected: false,
  },

  // 2. day_at_least
  {
    operator: 'day_at_least',
    label: 'day_at_least true when run.day >= target',
    condition: { day_at_least: 10 },
    setup: (s) => {
      s.run.day = 10;
    },
    expected: true,
  },
  {
    operator: 'day_at_least',
    label: 'day_at_least false when run.day < target',
    condition: { day_at_least: 10 },
    setup: (s) => {
      s.run.day = 9;
    },
    expected: false,
  },

  // 3. has_card
  {
    operator: 'has_card',
    label: 'has_card true when card is in run.hand',
    condition: { has_card: 'info_ahong_private' },
    setup: (s) => {
      s.run.hand.push('info_ahong_private');
    },
    expected: true,
  },
  {
    operator: 'has_card',
    label: 'has_card true when card is in meta.knowledge',
    condition: { has_card: 'k_forty_something' },
    setup: (s) => {
      s.meta.knowledge.k_forty_something = true;
    },
    expected: true,
  },
  {
    operator: 'has_card',
    label: 'has_card false when card is in neither hand nor knowledge',
    condition: { has_card: 'info_ahong_private' },
    expected: false,
  },

  // 4. has_knowledge
  {
    operator: 'has_knowledge',
    label: 'has_knowledge true when id is in meta.knowledge',
    condition: { has_knowledge: 'k_forty_something' },
    setup: (s) => {
      s.meta.knowledge.k_forty_something = true;
    },
    expected: true,
  },
  {
    operator: 'has_knowledge',
    label: 'has_knowledge false when id is only in run.hand or absent',
    condition: { has_knowledge: 'item_family_album' },
    setup: (s) => {
      s.run.hand.push('item_family_album');
    },
    expected: false,
  },

  // 5. switch
  {
    operator: 'switch',
    label: 'switch true when run.switches[id] is true',
    condition: { switch: 's1' },
    setup: (s) => {
      s.run.switches.s1 = true;
    },
    expected: true,
  },
  {
    operator: 'switch',
    label: 'switch false when run.switches[id] is absent',
    condition: { switch: 's1' },
    expected: false,
  },

  // 6. switch_progress_at_least
  {
    operator: 'switch_progress_at_least',
    label: 'switch_progress_at_least true when progress >= n',
    condition: { switch_progress_at_least: { switch: 's6', n: 3 } },
    setup: (s) => {
      s.run.switch_progress.s6 = 3;
    },
    expected: true,
  },
  {
    operator: 'switch_progress_at_least',
    label: 'switch_progress_at_least false when progress < n or absent',
    condition: { switch_progress_at_least: { switch: 's6', n: 3 } },
    setup: (s) => {
      s.run.switch_progress.s6 = 2;
    },
    expected: false,
  },

  // 7. flag
  {
    operator: 'flag',
    label: 'flag true when run.flags[name] is true',
    condition: { flag: 'ahong_missing' },
    setup: (s) => {
      s.run.flags.ahong_missing = true;
    },
    expected: true,
  },
  {
    operator: 'flag',
    label: 'flag false when run.flags[name] is false or absent',
    condition: { flag: 'ahong_missing' },
    setup: (s) => {
      s.run.flags.ahong_missing = false;
    },
    expected: false,
  },

  // 8. relation_at_least
  {
    operator: 'relation_at_least',
    label: 'relation_at_least true when relation >= scale threshold',
    condition: { relation_at_least: { npc: 'awei', state: '疑似' } },
    setup: (s) => {
      s.run.relations.awei = 1;
    },
    expected: true,
  },
  {
    operator: 'relation_at_least',
    label: 'relation_at_least false when relation < scale threshold (default 0 < 1)',
    condition: { relation_at_least: { npc: 'awei', state: '疑似' } },
    expected: false,
  },

  // 9. madness_at_least
  {
    operator: 'madness_at_least',
    label: 'madness_at_least true when madness_clock instance count >= n',
    condition: { madness_at_least: 3 },
    setup: (s) => {
      s.run.madness_clock = { 'madness#1': 3, 'madness#2': 2, 'madness#3': 1 };
    },
    expected: true,
  },
  {
    operator: 'madness_at_least',
    label: 'madness_at_least false when madness_clock instance count < n',
    condition: { madness_at_least: 3 },
    setup: (s) => {
      s.run.madness_clock = { 'madness#1': 3, 'madness#2': 2 };
    },
    expected: false,
  },

  // 10. count_at_least
  {
    operator: 'count_at_least',
    label: 'count_at_least true when at least n sub-conditions hold',
    condition: {
      count_at_least: {
        n: 2,
        of: [
          { flag: 'acai_obs_knee' },
          { flag: 'acai_obs_hands' },
          { flag: 'acai_obs_scar' },
        ],
      },
    },
    setup: (s) => {
      s.run.flags.acai_obs_knee = true;
      s.run.flags.acai_obs_scar = true;
    },
    expected: true,
  },
  {
    operator: 'count_at_least',
    label: 'count_at_least false when fewer than n sub-conditions hold',
    condition: {
      count_at_least: {
        n: 2,
        of: [
          { flag: 'acai_obs_knee' },
          { flag: 'acai_obs_hands' },
          { flag: 'acai_obs_scar' },
        ],
      },
    },
    setup: (s) => {
      s.run.flags.acai_obs_knee = true;
    },
    expected: false,
  },

  // 11. not
  {
    operator: 'not',
    label: 'not true when inner condition is false',
    condition: { not: { flag: 'couple_softened' } },
    expected: true,
  },
  {
    operator: 'not',
    label: 'not false when inner condition is true',
    condition: { not: { flag: 'couple_softened' } },
    setup: (s) => {
      s.run.flags.couple_softened = true;
    },
    expected: false,
  },

  // 12. all
  {
    operator: 'all',
    label: 'all true when every sub-condition holds',
    condition: { all: [{ day: 1 }, { flag: 'outside_job_waiting' }] },
    setup: (s) => {
      s.run.day = 1;
      s.run.flags.outside_job_waiting = true;
    },
    expected: true,
  },
  {
    operator: 'all',
    label: 'all false when at least one sub-condition is false',
    condition: { all: [{ day: 1 }, { flag: 'outside_job_waiting' }] },
    setup: (s) => {
      s.run.day = 1;
    },
    expected: false,
  },

  // 13. any
  {
    operator: 'any',
    label: 'any true when at least one sub-condition holds',
    condition: {
      any: [
        { has_card: 'info_husband_version' },
        { has_card: 'info_wife_version' },
      ],
    },
    setup: (s) => {
      s.run.hand.push('info_wife_version');
    },
    expected: true,
  },
  {
    operator: 'any',
    label: 'any false when no sub-condition holds',
    condition: {
      any: [
        { has_card: 'info_husband_version' },
        { has_card: 'info_wife_version' },
      ],
    },
    expected: false,
  },

  // 14. night_seen
  {
    operator: 'night_seen',
    label: 'night_seen true when location is in meta.night_locations_seen',
    condition: { night_seen: 'n_ahong_1' },
    setup: (s) => {
      s.meta.night_locations_seen.n_ahong_1 = true;
    },
    expected: true,
  },
  {
    operator: 'night_seen',
    label: 'night_seen false when location is not in meta.night_locations_seen',
    condition: { night_seen: 'n_ahong_1' },
    expected: false,
  },

  // 15. opening_choice
  {
    operator: 'opening_choice',
    label: 'opening_choice true when run.opening_choice_id matches',
    condition: { opening_choice: 'take_family_album' },
    setup: (s) => {
      s.run.opening_choice_id = 'take_family_album';
    },
    expected: true,
  },
  {
    operator: 'opening_choice',
    label: 'opening_choice false when run.opening_choice_id is null or different',
    condition: { opening_choice: 'take_family_album' },
    setup: (s) => {
      s.run.opening_choice_id = 'return_missed_call';
    },
    expected: false,
  },

  // 16. ending_seen
  {
    operator: 'ending_seen',
    label: 'ending_seen true when meta.ending_history contains ending_id',
    condition: { ending_seen: 'ending_replaced' },
    setup: (s) => {
      s.meta.ending_history.push(makeHistoryRecord('ending_replaced'));
    },
    expected: true,
  },
  {
    operator: 'ending_seen',
    label: 'ending_seen false when meta.ending_history does not contain ending_id',
    condition: { ending_seen: 'ending_replaced' },
    setup: (s) => {
      s.meta.ending_history.push(makeHistoryRecord('ending_madness_be'));
    },
    expected: false,
  },

  // 17. festival_proxy_is
  {
    operator: 'festival_proxy_is',
    label: 'festival_proxy_is true when run.selected_festival_proxy_npc matches',
    condition: { festival_proxy_is: 'ajie' },
    setup: (s) => {
      s.run.selected_festival_proxy_npc = 'ajie';
    },
    expected: true,
  },
  {
    operator: 'festival_proxy_is',
    label: 'festival_proxy_is false when run.selected_festival_proxy_npc is null or different',
    condition: { festival_proxy_is: 'ajie' },
    setup: (s) => {
      s.run.selected_festival_proxy_npc = 'awei';
    },
    expected: false,
  },
];

describe('W4-A ConditionEval full operator vocabulary, purity, and formal data rules', () => {
  let data: GameData;

  beforeAll(async () => {
    data = await loadGameDataNode();
  });

  it('parameterized table covers both true and false cases for all 17 CONDITION_OPERATORS with zero state mutation', () => {
    const trueOps = new Set(
      OPERATOR_TABLE.filter((c) => c.expected === true).map((c) => c.operator),
    );
    const falseOps = new Set(
      OPERATOR_TABLE.filter((c) => c.expected === false).map((c) => c.operator),
    );
    expect([...trueOps].sort()).toEqual([...CONDITION_OPERATORS].sort());
    expect([...falseOps].sort()).toEqual([...CONDITION_OPERATORS].sort());

    for (const tc of OPERATOR_TABLE) {
      const game = createGame(data);
      const state = game.serialize();
      tc.setup?.(state);
      const beforeJson = JSON.stringify(state);

      const actual = evalCondition(tc.condition, state, data);
      expect(actual, `[${tc.operator}] ${tc.label}`).toBe(tc.expected);
      expect(JSON.stringify(state)).toBe(beforeJson);
    }
  });

  it('handles null/undefined as true, all:[] as true, and any:[] as false without mutating state', () => {
    const game = createGame(data);
    const beforeSerialized = JSON.stringify(game.serialize());
    const snap = game.getSnapshot();

    expect(evalCondition(null, snap, data)).toBe(true);
    expect(evalCondition(undefined, snap, data)).toBe(true);
    expect(evalCondition({ all: [] }, snap, data)).toBe(true);
    expect(evalCondition({ any: [] }, snap, data)).toBe(false);

    expect(JSON.stringify(game.serialize())).toBe(beforeSerialized);
  });

  it('evaluates formal nested combinations from data (d22_pm_sandbags::obs_hands and ending_replaced::uncle_high)', () => {
    // 1. Formal slot requires on d22_pm_sandbags::obs_hands (any + count_at_least + flag)
    const d22Beat = data.beatsById.get('d22_pm_sandbags');
    expect(d22Beat).toBeDefined();
    const obsHandsSlot = d22Beat!.slots?.find((s) => s.id === 'obs_hands');
    expect(obsHandsSlot?.requires).toBeDefined();
    const obsRequires = obsHandsSlot!.requires!;

    const state = createGame(data).serialize();
    // 0 flags -> false
    expect(evalCondition(obsRequires, state, data)).toBe(false);

    // 1 observation flag (< 2) -> still false
    state.run.flags.acai_obs_knee = true;
    expect(evalCondition(obsRequires, state, data)).toBe(false);

    // 2 observation flags (>= 2) -> true via count_at_least branch
    state.run.flags.acai_obs_scar = true;
    expect(evalCondition(obsRequires, state, data)).toBe(true);

    // Reset observation flags, set polaroid_acai -> true via first any branch
    state.run.flags = { polaroid_acai: true };
    expect(evalCondition(obsRequires, state, data)).toBe(true);

    // 2. Formal ending rule when on ending_replaced -> variant_groups[livelihood] -> uncle_high (all + flag + count_at_least + switch + switch_progress_at_least)
    const replacedEnding = data.endingsById.get('ending_replaced');
    expect(replacedEnding?.kind).toBe('composite');
    if (replacedEnding?.kind === 'composite') {
      const livelihoodGroup = replacedEnding.variant_groups.find(
        (g) => g.id === 'livelihood',
      )!;
      const uncleHighRule = livelihoodGroup.rules.find(
        (r) => r.id === 'uncle_high',
      )!;
      const uncleHighWhen = uncleHighRule.when!;

      const endState = createGame(data).serialize();
      endState.run.flags.accepted_inn = true;
      endState.run.switches = { s1: true, s2: true, s3: true };
      endState.run.switch_progress = { s6: 2 };
      // Only 3 of 6 sub-conditions hold (s6 progress is 2 < 3) -> false
      expect(evalCondition(uncleHighWhen, endState, data)).toBe(false);

      // Advance s6 progress to 3 -> 4 of 6 sub-conditions hold -> true
      endState.run.switch_progress.s6 = 3;
      const beforeJson = JSON.stringify(endState);
      expect(evalCondition(uncleHighWhen, endState, data)).toBe(true);
      expect(JSON.stringify(endState)).toBe(beforeJson);
    }
  });

  it('verifies formal cards in registry do not count as has_card unless held in hand or knowledge, checks formal panel requires, and preserves serialize() byte-for-byte', () => {
    const game = createGame(data);
    expect(game.chooseOpening('return_missed_call').ok).toBe(true);
    const beforeSerialize = JSON.stringify(game.serialize());
    const snap = game.getSnapshot();

    // Formal cards exist in data.cardsById registry, but are NOT held on return_missed_call opening
    const formalUnheldCards = [
      'item_family_album',
      'info_husband_version',
      'info_wife_version',
      'k_forty_something',
    ];
    for (const cardId of formalUnheldCards) {
      expect(data.cardsById.has(cardId)).toBe(true);
      expect(evalCondition({ has_card: cardId }, snap, data)).toBe(false);
    }
    // Protagonist IS in hand
    expect(evalCondition({ has_card: 'protagonist' }, snap, data)).toBe(true);

    // Formal panel slot requires: d3_pm_sanquan::show_version requires any(has_card: info_husband_version, has_card: info_wife_version)
    const d3Sanquan = data.beatsById.get('d3_pm_sanquan')!;
    const showVersionSlot = d3Sanquan.slots!.find(
      (s) => s.id === 'show_version',
    )!;
    expect(showVersionSlot.requires).toBeDefined();
    expect(evalCondition(showVersionSlot.requires, snap, data)).toBe(false);

    // Formal panel beat requires: d19_pm_upstream requires has_knowledge: k_forty_something
    const d19Upstream = data.beatsById.get('d19_pm_upstream')!;
    expect(d19Upstream.requires).toBeDefined();
    expect(evalCondition(d19Upstream.requires, snap, data)).toBe(false);

    // Game.serialize() is strictly unchanged after all queries
    expect(JSON.stringify(game.serialize())).toBe(beforeSerialize);

    // When holding info_husband_version in hand, d3_pm_sanquan::show_version requires becomes true
    const draft = game.serialize();
    draft.run.hand.push('info_husband_version');
    expect(evalCondition(showVersionSlot.requires, draft, data)).toBe(true);

    // When holding k_forty_something in meta.knowledge, both has_knowledge and has_card become true, unlocking d19_pm_upstream.requires
    draft.meta.knowledge.k_forty_something = true;
    expect(evalCondition(d19Upstream.requires, draft, data)).toBe(true);
    expect(evalCondition({ has_card: 'k_forty_something' }, draft, data)).toBe(
      true,
    );
  });

  it('evaluates relation_at_least against formal relation_scale.json using default 0 for unrecorded NPCs', () => {
    const state = createGame(data).serialize();
    const beforeJson = JSON.stringify(state);

    // Unrecorded NPC 'awei' defaults to 0:
    // 死敵 (-2), 債主 (-1), 陌生 (0) -> true
    expect(
      evalCondition(
        { relation_at_least: { npc: 'awei', state: '死敵' } },
        state,
        data,
      ),
    ).toBe(true);
    expect(
      evalCondition(
        { relation_at_least: { npc: 'awei', state: '債主' } },
        state,
        data,
      ),
    ).toBe(true);
    expect(
      evalCondition(
        { relation_at_least: { npc: 'awei', state: '陌生' } },
        state,
        data,
      ),
    ).toBe(true);

    // 疑似 (1), 同謀 (2), 恩人 (3), 戀人 (4) -> false at default 0
    expect(
      evalCondition(
        { relation_at_least: { npc: 'awei', state: '疑似' } },
        state,
        data,
      ),
    ).toBe(false);
    expect(
      evalCondition(
        { relation_at_least: { npc: 'awei', state: '同謀' } },
        state,
        data,
      ),
    ).toBe(false);
    expect(
      evalCondition(
        { relation_at_least: { npc: 'awei', state: '恩人' } },
        state,
        data,
      ),
    ).toBe(false);
    expect(
      evalCondition(
        { relation_at_least: { npc: 'awei', state: '戀人' } },
        state,
        data,
      ),
    ).toBe(false);
    expect(JSON.stringify(state)).toBe(beforeJson);

    // Negative relation (-1): 債主 (-1) is true, 陌生 (0) is false
    state.run.relations.awei = -1;
    expect(relationAtLeast(state, 'awei', '債主', data)).toBe(true);
    expect(relationAtLeast(state, 'awei', '陌生', data)).toBe(false);
    expect(hasSeenEnding(state, '')).toBe(false);
    expect(hasSeenNightLocation(state, '')).toBe(false);
  });

  it('rejects unknown operators, non-single-key objects, and malformed operands with ConditionError, never defaulting to true', () => {
    const state = createGame(data).serialize();
    const beforeJson = JSON.stringify(state);

    const invalidInputs: unknown[] = [
      {},
      [],
      'day',
      123,
      { day: 1, flag: 'x' },
      { unknown_operator: 'x' },
      { day: '1' },
      { day: 1.5 },
      { day_at_least: '2' },
      { has_card: '' },
      { has_knowledge: '' },
      { switch: '' },
      { switch_progress_at_least: { switch: 's6' } },
      { switch_progress_at_least: { switch: '', n: 1 } },
      { switch_progress_at_least: { switch: 's6', n: '1' } },
      { flag: '' },
      { relation_at_least: { npc: 'awei', state: '不存在的狀態' } },
      { relation_at_least: { npc: 'awei', state: '_comment' } },
      { relation_at_least: { npc: '', state: '疑似' } },
      { madness_at_least: '1' },
      { night_seen: '' },
      { opening_choice: '' },
      { ending_seen: '' },
      { festival_proxy_is: '' },
      { count_at_least: { n: 1 } },
      { count_at_least: { n: 1, of: [null] } },
      { not: null },
      { all: 'not_an_array' },
      { all: [{ day: 99 }, { unknown_nested: 1 }] },
      { any: [{ day: 1 }, { unknown_nested: 1 }] },
    ];

    for (const bad of invalidInputs) {
      expect(() =>
        evalCondition(bad as Condition, state, data),
      ).toThrow(ConditionError);
    }

    expect(JSON.stringify(state)).toBe(beforeJson);
  });

  it('evaluates every authored condition across formal locations, npcs, openingChoices, beats, slots, card entries, and endings without error or state mutation', () => {
    const game = createGame(data);
    expect(game.chooseOpening('take_family_album').ok).toBe(true);
    const snap = game.getSnapshot();
    const beforeSerialize = JSON.stringify(game.serialize());

    let evaluatedCount = 0;
    const checkCond = (cond: Condition | null | undefined) => {
      const res = evalCondition(cond, snap, data);
      expect(typeof res).toBe('boolean');
      evaluatedCount += 1;
    };

    for (const loc of data.locations) {
      if (loc.requires !== undefined) {
        checkCond(loc.requires);
      }
    }
    for (const npc of data.npcs) {
      if (npc.reveal !== undefined) {
        checkCond(npc.reveal);
      }
    }
    for (const oc of data.openingChoices) {
      if (oc.requires !== undefined) {
        checkCond(oc.requires);
      }
    }
    for (const beat of data.beats) {
      if (beat.condition !== undefined) {
        checkCond(beat.condition);
      }
      if (beat.requires !== undefined) {
        checkCond(beat.requires);
      }
      if (beat.echo?.condition !== undefined) {
        checkCond(beat.echo.condition);
      }
      for (const slot of beat.slots ?? []) {
        if (slot.condition !== undefined) {
          checkCond(slot.condition);
        }
        if (slot.requires !== undefined) {
          checkCond(slot.requires);
        }
      }
    }
    for (const ending of data.endings) {
      if (ending.kind === 'composite') {
        for (const vg of ending.variant_groups) {
          for (const rule of vg.rules) {
            if (rule.when !== undefined) {
              checkCond(rule.when);
            }
          }
        }
      }
    }

    expect(evaluatedCount).toBeGreaterThan(100);
    expect(JSON.stringify(game.serialize())).toBe(beforeSerialize);
  });
});
