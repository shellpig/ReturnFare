import { describe, expect, it } from 'vitest';
import { loadGameDataNode } from '../src/data/load-node';
import { planEffects } from '../src/core/effect';
import { createGame } from '../src/core/state';
import { createInitialSnapshot } from '../src/core/run-initialization';
import type { GameSnapshot } from '../src/core/state-types';

describe('planEffects (W5-B)', async () => {
  const data = await loadGameDataNode();

  it('executes lose before gain within the same effect block so conditional entries read updated draft', () => {
    const state = createInitialSnapshot();
    state.flow.mode = 'run';
    state.run.hand = ['protagonist', 'info_husband_version'];

    // Block loses info_husband_version, and conditionally gains info_wife_version ONLY IF info_husband_version is NOT held
    const plan = planEffects(
      [
        {
          lose: ['info_husband_version'],
          gain: [
            {
              card: 'info_wife_version',
              if: { not: { has_card: 'info_husband_version' } },
            },
          ],
        },
      ],
      state,
      data,
    );

    expect(plan.ok).toBe(true);
    expect(plan.nextState.run.hand).not.toContain('info_husband_version');
    expect(plan.nextState.run.hand).toContain('info_wife_version');
  });

  it('evaluates prior-block state mutations before subsequent blocks conditional checks', () => {
    const state = createInitialSnapshot();
    state.flow.mode = 'run';
    state.run.hand = ['protagonist'];

    const plan = planEffects(
      [
        {
          flag: { step_one_completed: true },
        },
        {
          gain: [
            {
              card: 'info_husband_version',
              if: { flag: 'step_one_completed' },
            },
          ],
        },
      ],
      state,
      data,
    );

    expect(plan.ok).toBe(true);
    expect(plan.nextState.run.flags.step_one_completed).toBe(true);
    expect(plan.nextState.run.hand).toContain('info_husband_version');
  });

  it('supports ordinary vs permanent lose semantics for loop_persistent items and prevents protagonist discard', () => {
    // Construct representative fixture data marking item_family_album as loop_persistent: true
    const customCards = data.cards.map((c) =>
      c.id === 'item_family_album' ? { ...c, loop_persistent: true } : c,
    );
    const fixtureData = {
      ...data,
      cards: customCards,
      cardsById: new Map(customCards.map((c) => [c.id, c])),
    };

    const state = createInitialSnapshot();
    state.flow.mode = 'run';
    state.run.hand = ['protagonist', 'item_family_album'];
    state.meta.loop_persistent_item_ids['item_family_album'] = true;

    // 1. Ordinary lose: removes from hand, retains in loop_persistent_item_ids
    const ordinaryPlan = planEffects(
      [{ lose: ['item_family_album'] }],
      state,
      fixtureData,
    );
    expect(ordinaryPlan.ok).toBe(true);
    expect(ordinaryPlan.nextState.run.hand).not.toContain('item_family_album');
    expect(
      ordinaryPlan.nextState.meta.loop_persistent_item_ids['item_family_album'],
    ).toBe(true);

    // 2. Permanent lose: removes from hand and removes from loop_persistent_item_ids
    const permPlan = planEffects(
      [{ lose: [{ card: 'item_family_album', permanent: true }] }],
      state,
      fixtureData,
    );
    expect(permPlan.ok).toBe(true);
    expect(permPlan.nextState.run.hand).not.toContain('item_family_album');
    expect(
      permPlan.nextState.meta.loop_persistent_item_ids['item_family_album'],
    ).toBeUndefined();

    // 3. Protagonist card discard rejection
    const discardProtagonist = planEffects(
      [{ lose: ['protagonist'] }],
      state,
      data,
    );
    expect(discardProtagonist.ok).toBe(false);
    expect(discardProtagonist.reason_code).toBe('data_conflict');
    expect(discardProtagonist.nextState.run.hand).toEqual(state.run.hand);
  });

  it('losing a known card that is not held is a no-op like effect_apply.gd, while unknown ids still reject', () => {
    const state = createInitialSnapshot();
    state.flow.mode = 'run';
    state.run.hand = ['protagonist'];

    const plan = planEffects(
      [{ text: '後續照常', lose: ['k_not_today'], flag: { after_missing_lose: true } }],
      state,
      data,
    );
    expect(plan.ok).toBe(true);
    expect(plan.lines).toEqual(['後續照常']);
    expect(plan.nextState.run.flags.after_missing_lose).toBe(true);
    expect(plan.nextState.run.hand).toEqual(['protagonist']);

    const unknown = planEffects([{ lose: ['no_such_card'] }], state, data);
    expect(unknown.ok).toBe(false);
    expect(unknown.reason_code).toBe('data_conflict');
  });

  it('accumulates relation and switch_progress additively per block', () => {
    const state = createInitialSnapshot();
    state.flow.mode = 'run';

    const plan = planEffects(
      [
        {
          relation: { npc: 'ajie', delta: 2 },
          switch_progress: { s6: 1 },
        },
        {
          relation: { npc: 'ajie', delta: 3 },
          switch_progress: { s6: 2 },
        },
      ],
      state,
      data,
    );

    expect(plan.ok).toBe(true);
    expect(plan.nextState.run.relations.ajie).toBe(5);
    expect(plan.nextState.run.switch_progress.s6).toBe(3);
  });

  it('supports switch string syntax and rejects switch array syntax as data_conflict', () => {
    const state = createInitialSnapshot();
    state.flow.mode = 'run';
    const originalSerialized = JSON.stringify(state);

    // String shape succeeds
    const strPlan = planEffects([{ switch: 's1' }], state, data);
    expect(strPlan.ok).toBe(true);
    expect(strPlan.nextState.run.switches.s1).toBe(true);

    // Array shape rejected as data_conflict, unchanged state, empty lines
    const arrPlan = planEffects(
      [{ switch: ['s2', 's3'] as unknown as string }],
      state,
      data,
    );
    expect(arrPlan.ok).toBe(false);
    expect(arrPlan.reason_code).toBe('data_conflict');
    expect(arrPlan.lines).toEqual([]);
    expect(JSON.stringify(arrPlan.nextState)).toBe(originalSerialized);
  });

  it('strictly validates flag dictionary structure and rejects non-boolean values', () => {
    const state = createInitialSnapshot();
    state.flow.mode = 'run';

    const goodPlan = planEffects(
      [{ flag: { valid_flag: true, off_flag: false } }],
      state,
      data,
    );
    expect(goodPlan.ok).toBe(true);
    expect(goodPlan.nextState.run.flags.valid_flag).toBe(true);
    expect(goodPlan.nextState.run.flags.off_flag).toBe(false);

    // Malformed flag value
    const badPlan = planEffects(
      [
        {
          flag: { invalid_flag: 'not_a_bool' as unknown as boolean },
        },
      ],
      state,
      data,
    );
    expect(badPlan.ok).toBe(false);
    expect(badPlan.reason_code).toBe('data_conflict');
  });

  it('atomically rolls back all earlier gains, flags, and lines if a later unimplemented effect (festival_proxy) is encountered', () => {
    const state = createInitialSnapshot();
    state.flow.mode = 'run';
    state.run.hand = ['protagonist'];
    const originalSerialized = JSON.stringify(state);

    // 1. madness effect (W6-A): applied in fixed key order after text/lose/gain/relation, before flag; each card gets its own full countdown
    const madnessPlan = planEffects(
      [
        {
          text: '這段文字照常輸出',
          gain: ['info_husband_version'],
          flag: { madness_flag: true },
          madness: 2,
        },
      ],
      state,
      data,
    );
    expect(madnessPlan.ok).toBe(true);
    expect(madnessPlan.lines).toEqual(['這段文字照常輸出']);
    expect(madnessPlan.endingRequest).toBeNull();
    expect(madnessPlan.nextState.run.hand).toEqual([
      'protagonist',
      'info_husband_version',
      'madness#1',
      'madness#2',
    ]);
    expect(madnessPlan.nextState.run.madness_clock).toEqual({
      'madness#1': data.tuning.madness_countdown_days,
      'madness#2': data.tuning.madness_countdown_days,
    });
    expect(madnessPlan.nextState.run.flags.madness_flag).toBe(true);
    expect(JSON.stringify(state)).toBe(originalSerialized);

    // 1b. Invalid madness count (non-integer / negative) rejects the whole plan with zero leakage
    for (const bad of [-1, 1.5, '2']) {
      const badPlan = planEffects(
        [{ text: '不該外洩', gain: ['info_husband_version'], madness: bad as unknown as number }],
        state,
        data,
      );
      expect(badPlan.ok).toBe(false);
      expect(badPlan.reason_code).toBe('data_conflict');
      expect(badPlan.lines).toEqual([]);
      expect(JSON.stringify(badPlan.nextState)).toBe(originalSerialized);
    }

    // 2. Encountering bad festival_proxy (non-eligible candidate) atomically rejects with data_conflict
    const proxyPlan = planEffects(
      [
        {
          text: '這段也不該外洩',
          flag: { leaked_flag2: true },
          festival_proxy: { mode: 'fixed', npc: 'uncle' },
        },
      ],
      state,
      data,
    );
    expect(proxyPlan.ok).toBe(false);
    expect(proxyPlan.reason_code).toBe('data_conflict');
    expect(proxyPlan.lines).toEqual([]);
    expect(JSON.stringify(proxyPlan.nextState)).toBe(originalSerialized);

    // 3. Direct gain of the madness card shares the same primitive; a later bad festival_proxy key still rolls everything back
    const gainMadnessPlan = planEffects(
      [{ text: '繞道取得發狂卡', gain: ['madness'] }],
      state,
      data,
    );
    expect(gainMadnessPlan.ok).toBe(true);
    expect(gainMadnessPlan.nextState.run.hand).toEqual(['protagonist', 'madness#1']);
    expect(gainMadnessPlan.nextState.run.madness_clock).toEqual({
      'madness#1': data.tuning.madness_countdown_days,
    });
    const madnessThenProxy = planEffects(
      [
        {
          text: '這段文字不該外洩',
          gain: ['madness'],
          madness: 1,
          festival_proxy: { mode: 'highest_eligible', fallback: 'uncle' },
        },
      ],
      state,
      data,
    );
    expect(madnessThenProxy.ok).toBe(false);
    expect(madnessThenProxy.reason_code).toBe('data_conflict');
    expect(madnessThenProxy.lines).toEqual([]);
    expect(JSON.stringify(madnessThenProxy.nextState)).toBe(originalSerialized);

    // 4. Valid ending request (W6-E1: collected, not rejected) after an earlier block
    const validEndingPlan = planEffects(
      [
        {
          text: '這段文字與取得物不該外洩',
          gain: ['info_husband_version'],
          flag: { leaked_ending_pre_flag: true },
        },
        {
          text: '結局區塊',
          ending: 'ending_replaced',
        },
      ],
      state,
      data,
    );
    expect(validEndingPlan.ok).toBe(true);
    expect(validEndingPlan.endingRequest).toEqual({
      ending_id: 'ending_replaced',
      source_id: 'ending_effect',
    });
    expect(validEndingPlan.lines).toEqual(['這段文字與取得物不該外洩', '結局區塊']);
    // planEffects only simulates on a copy: the input state stays untouched
    expect(JSON.stringify(state)).toBe(originalSerialized);

    // 5. Two different ending requests in one action: whole plan data_conflict, no leaked lines
    const conflictPlan = planEffects(
      [
        { text: '第一個結局', ending: 'ending_inventory_be' },
        { text: '第二個結局', ending: 'ending_madness_be' },
      ],
      state,
      data,
    );
    expect(conflictPlan.ok).toBe(false);
    expect(conflictPlan.reason_code).toBe('data_conflict');
    expect(conflictPlan.lines).toEqual([]);
    expect(conflictPlan.endingRequest).toBeNull();
    expect(JSON.stringify(conflictPlan.nextState)).toBe(originalSerialized);

    // 6. Identical requests from two blocks collapse to one request
    const samePlan = planEffects(
      [{ ending: 'ending_inventory_be' }, { ending: 'ending_inventory_be' }],
      state,
      data,
    );
    expect(samePlan.ok).toBe(true);
    expect(samePlan.endingRequest).toEqual({
      ending_id: 'ending_inventory_be',
      source_id: 'ending_effect',
    });
  });

  it('shared settle Game rejects a mismatched ending request (ending_replaced via ending_effect) with invalid_ending_source, zero state mutation, zero bookkeeping, and zero notify', () => {
    // Construct isolated fixture beat with a valid ending on slot on_place
    const customBeats = [
      ...data.beats,
      {
        id: 'test_ending_beat',
        location: 'sanquan',
        when: { day: 1, phase: 'morning' as const },
        fixed: false,
        title: '結局測試格',
        text: '測試開場文本',
        slots: [
          {
            id: 'trigger_ending_slot',
            occupant: null,
            label: '觸發結局',
            accepts: ['protagonist'],
            on_place: {
              text: '準備進入結局',
              gain: ['info_husband_version'],
              flag: { ending_flag_leaked: true },
              ending: 'ending_replaced',
            },
          },
        ],
      },
    ];
    const fixtureData = {
      ...data,
      beats: customBeats,
      beatsById: new Map(customBeats.map((b) => [b.id, b])),
    };

    const game = createGame(fixtureData);
    game.chooseOpening('take_family_album');

    const beforeState = game.serialize();
    const beforeSerialized = JSON.stringify(beforeState);

    let notifyCount = 0;
    const unsubscribe = game.subscribe(() => {
      notifyCount += 1;
    });

    const res = game.tryPlace(
      'protagonist',
      'test_ending_beat',
      'trigger_ending_slot',
    );

    unsubscribe();

    expect(res.ok).toBe(false);
    expect(res.reason_code).toBe('invalid_ending_source');
    expect(res.lines).toEqual([]);
    expect(notifyCount).toBe(0);

    const afterSerialized = JSON.stringify(game.serialize());
    expect(afterSerialized).toBe(beforeSerialized);
  });

  it('rejects unknown effect keys and unknown endings with explicit data errors', () => {
    const state = createInitialSnapshot();
    state.flow.mode = 'run';

    // Unknown key
    const unknownKeyPlan = planEffects(
      [{ unknown_effect_key: 123 } as unknown as Record<string, unknown>],
      state,
      data,
    );
    expect(unknownKeyPlan.ok).toBe(false);
    expect(unknownKeyPlan.reason_code).toBe('data_conflict');

    // Unknown ending
    const unknownEndingPlan = planEffects(
      [{ ending: 'non_existent_ending_id' }],
      state,
      data,
    );
    expect(unknownEndingPlan.ok).toBe(false);
    expect(unknownEndingPlan.reason_code).toBe('unknown_ending');
  });
});
