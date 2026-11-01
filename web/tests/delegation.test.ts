/**
 * ReturnFare Web — 委託系統核心規則與隔日上午回報測試（W6-C）。
 */

import { describe, expect, it, vi } from 'vitest';
import { loadGameDataNode } from '../src/data/load-node';
import type { Beat, Delegation, GameData, Phase, Slot } from '../src/data/types';
import { TriState } from '../src/core/panel';
import { createGame } from '../src/core/state';
import type { GameSnapshot } from '../src/core/state-types';
import { createRunForTrace } from '../src/core/trace-entry';

describe('W6-C delegation system (core rules & next morning settlement)', async () => {
  const data = await loadGameDataNode();

  function injectAt(
    day: number,
    phase: Phase,
    tweak?: (snap: GameSnapshot) => void,
  ): GameSnapshot {
    const snap = createRunForTrace(data).serialize();
    snap.run.day = day;
    snap.run.phase = phase;
    tweak?.(snap);
    return snap;
  }

  it('1. Tutorial meta: acquiring person card leaves delegation_tutorial_seen false, markDelegationTutorialSeen is idempotent', () => {
    const snap = injectAt(17, 'morning');
    const game = createGame(data, snap);

    // Initial meta
    expect(game.getSnapshot().meta.delegation_tutorial_seen).toBe(false);

    // Play official D17 morning beat which gives npc_ajie
    const playRes = game.playBeat('d17_morning_phone');
    expect(playRes.ok).toBe(true);
    expect(game.hasCard('npc_ajie')).toBe(true);

    // Acquisition MUST NOT set meta
    expect(game.getSnapshot().meta.delegation_tutorial_seen).toBe(false);

    // Explicit UI dismissal marks tutorial seen
    let notified = 0;
    const unsub = game.subscribe(() => {
      notified += 1;
    });

    game.markDelegationTutorialSeen();
    expect(game.getSnapshot().meta.delegation_tutorial_seen).toBe(true);
    expect(notified).toBe(1);

    // Idempotent call
    game.markDelegationTutorialSeen();
    expect(game.getSnapshot().meta.delegation_tutorial_seen).toBe(true);
    expect(notified).toBe(1); // not notified if already true
    unsub();
  });

  it('2. Official D17 afternoon prescription: immediate delegation via ask_ajie', () => {
    // Acquire npc_ajie via official beat
    const snap = injectAt(17, 'morning');
    const morningGame = createGame(data, snap);
    expect(morningGame.playBeat('d17_morning_phone').ok).toBe(true);
    expect(morningGame.hasCard('npc_ajie')).toBe(true);

    // Advance to afternoon
    expect(morningGame.advancePhase().ok).toBe(true);
    const d17pmSnap = morningGame.serialize();
    expect(d17pmSnap.run.day).toBe(17);
    expect(d17pmSnap.run.phase).toBe('afternoon');

    const game = createGame(data, d17pmSnap);
    const actionsBefore = game.remainingActionsToday();
    expect(actionsBefore).toBe(1);

    // Initial status before delegation
    const statusBefore = game.delegationStatus('npc_ajie');
    expect(statusBefore).toEqual({
      held: true,
      delegated_today: false,
      available: true,
      has_pending_report: false,
    });

    // Delegate ask_ajie
    const delRes = game.delegate('d17_19_prescription', 'ask_ajie', 'npc_ajie');
    expect(delRes.ok).toBe(true);
    expect(delRes.reason_code).toBe('');
    expect(delRes.lines.length).toBeGreaterThan(0);
    expect(delRes.lines[0]).toContain('阿婕動作俐落');

    // Immediate rewards
    expect(game.hasCard('doc_prescription')).toBe(true);
    expect(game.hasCard('info_ajie_saw_parents')).toBe(true);

    // Person card stays in hand
    expect(game.hasCard('npc_ajie')).toBe(true);

    // Protagonist actions and counts untouched
    expect(game.remainingActionsToday()).toBe(actionsBefore);
    expect(game.getSnapshot().run.action_spent).toBe(false);
    expect(game.getSnapshot().run.npc_action_counts).toEqual({});

    // Shared choice group resolved
    expect(game.getSnapshot().run.choices['d17_19_prescription::prescription_route']).toBe(
      'ask_ajie',
    );
    expect(game.getSnapshot().run.slots_placed['d17_19_prescription::ask_ajie']).toBe(true);

    // Mutual exclusion: other route choices rejected
    const chooseOther = game.choose('d17_19_prescription', 'prescription_route', 'find_self');
    expect(chooseOther.ok).toBe(false);
    expect(chooseOther.reason_code).toBe('resolved');

    // Second use of same person on same day is rejected with already_delegated_today
    const snapBeforeSecond = JSON.stringify(game.serialize());
    const secondDel = game.delegate('d17_19_prescription', 'ask_ajie', 'npc_ajie');
    expect(secondDel.ok).toBe(false);
    expect(secondDel.reason_code).toBe('already_delegated_today');
    expect(JSON.stringify(game.serialize())).toBe(snapBeforeSecond);

    // Status after delegation
    const statusAfter = game.delegationStatus('npc_ajie');
    expect(statusAfter).toEqual({
      held: true,
      delegated_today: true,
      available: false,
      has_pending_report: false,
    });
  });

  it('3. Official D17 afternoon prescription: next_morning delegation via ask_azhu and D18 morning report', () => {
    // Acquire npc_azhu on D17 morning by setting azhu_shared_abnormal_medicine flag
    const snap = injectAt(17, 'morning', (s) => {
      s.run.flags.azhu_shared_abnormal_medicine = true;
    });
    const morningGame = createGame(data, snap);
    expect(morningGame.playBeat('d17_morning_phone').ok).toBe(true);
    expect(morningGame.hasCard('npc_azhu')).toBe(true);

    // Advance to afternoon
    expect(morningGame.advancePhase().ok).toBe(true);
    const d17pmSnap = morningGame.serialize();
    expect(d17pmSnap.run.day).toBe(17);
    expect(d17pmSnap.run.phase).toBe('afternoon');

    const game = createGame(data, d17pmSnap);

    // Delegate ask_azhu
    const delRes = game.delegate('d17_19_prescription', 'ask_azhu', 'npc_azhu');
    expect(delRes.ok).toBe(true);
    expect(delRes.lines.length).toBeGreaterThan(0);
    expect(delRes.lines[0]).toContain('阿珠眼神閃爍地接下了請求');

    // Immediate rewards are NOT gained yet
    expect(game.hasCard('doc_prescription')).toBe(false);
    expect(game.hasKnowledge('info_uncle_treated_20y')).toBe(false);

    // Pending delegation reports stores ONLY data pointers (no effect copy)
    const pending = game.getSnapshot().run.pending_delegation_reports;
    expect(pending).toEqual([
      {
        due_day: 18,
        beat_id: 'd17_19_prescription',
        slot_id: 'ask_azhu',
        person_id: 'npc_azhu',
      },
    ]);

    // Status shows pending report
    expect(game.delegationStatus('npc_azhu')).toEqual({
      held: true,
      delegated_today: true,
      available: false,
      has_pending_report: true,
    });

    // Advance to evening
    expect(game.advancePhase().ok).toBe(true);
    expect(game.getPhaseView().phase).toBe('evening');
    expect(game.playEvening().ok).toBe(true);

    // Advance to night
    expect(game.advancePhase().ok).toBe(true);
    expect(game.getPhaseView().phase).toBe('night');
    expect(game.playNightFixed().ok).toBe(true);

    // Night advance (actual morning transition)
    const advD18m = game.advancePhase();
    expect(advD18m.ok).toBe(true);
    expect(advD18m.phase_advanced).toBe(true);
    expect(game.getPhaseView().day).toBe(18);
    expect(game.getPhaseView().phase).toBe('morning');

    // Next morning report executed atomically:
    // 1. Pending reports emptied
    expect(game.getSnapshot().run.pending_delegation_reports).toEqual([]);

    // 2. Report rewards applied
    expect(game.hasCard('doc_prescription')).toBe(true);
    expect(game.hasCard('info_uncle_treated_20y')).toBe(true);

    // 3. delegates_used_today cleared at morning
    expect(game.getSnapshot().run.delegates_used_today).toEqual({});

    // 4. Status reflects available on the new day
    expect(game.delegationStatus('npc_azhu')).toEqual({
      held: true,
      delegated_today: false,
      available: true,
      has_pending_report: false,
    });

    // 5. Advancing further does NOT apply report again
    expect(game.advancePhase().ok).toBe(true); // -> D18 afternoon
    expect(game.getSnapshot().run.pending_delegation_reports).toEqual([]);
  });

  it('4. Routing: tryPlace and choose route delegation slots to delegate', () => {
    // Acquire npc_ajie on D17
    const snap = injectAt(17, 'morning');
    const mGame = createGame(data, snap);
    mGame.playBeat('d17_morning_phone');
    mGame.advancePhase();

    // Test tryPlace routing
    const game1 = createGame(data, mGame.serialize());
    const tryRes = game1.tryPlace('npc_ajie', 'd17_19_prescription', 'ask_ajie');
    expect(tryRes.ok).toBe(true);
    expect(game1.hasCard('doc_prescription')).toBe(true);

    // Test choose routing
    const game2 = createGame(data, mGame.serialize());
    const chooseRes = game2.choose(
      'd17_19_prescription',
      'prescription_route',
      'ask_ajie',
      'npc_ajie',
    );
    expect(chooseRes.ok).toBe(true);
    expect(game2.hasCard('doc_prescription')).toBe(true);
  });

  it('5. Core view model: panel shows delegated_today and LOCKED, placeableCards excludes used person', () => {
    const snap = injectAt(17, 'afternoon', (s) => {
      s.run.hand.push('npc_ajie');
      s.run.delegates_used_today.npc_ajie = true;
    });
    const game = createGame(data, snap);

    // Panel view
    const panel = game.buildPanel('sanquan');
    const beatView = panel.beats.find((b) => b.id === 'd17_19_prescription');
    expect(beatView).toBeDefined();

    // ask_ajie slot should be LOCKED with '今日已受託'
    const ajieSlot = beatView!.slots.find((s) => s.id === 'ask_ajie');
    expect(ajieSlot).toBeDefined();
    expect(ajieSlot!.tri).toBe(TriState.LOCKED);
    expect(ajieSlot!.reason).toBe('今日已受託');
    expect(ajieSlot!.delegation?.taskTitle).toBe('叔叔的舊藥單');
    expect(ajieSlot!.delegation?.delegationState).toBe('delegated_today');

    // Unacquired person (ask_acai / ask_azhu not in hand) is HIDDEN (not in slots)
    const acaiSlot = beatView!.slots.find((s) => s.id === 'ask_acai');
    expect(acaiSlot).toBeUndefined();

    // placeableCards must exclude daily-used person
    const placeable = game.placeableCards('d17_19_prescription', 'ask_ajie');
    expect(placeable).not.toContain('npc_ajie');

    // previewSlot returns reason '今日已受託'
    const preview = game.previewSlot('d17_19_prescription', 'ask_ajie');
    expect(preview.cards).toEqual([]);
    expect(preview.reason).toBe('今日已受託');
  });

  function appendSlots(beat: Beat, ...slots: Slot[]): void {
    (beat as unknown as { slots: Slot[] }).slots = [...(beat.slots ?? []), ...slots];
  }

  type MutableGameData = Omit<GameData, 'beats' | 'beatsById' | 'cardsById'> & {
    beats: Beat[];
    beatsById: Map<string, Beat>;
    cardsById: Map<string, any>;
  };

  function createSyntheticData(modifier: (d: MutableGameData) => void): GameData {
    const clonedBeats = new Map<string, Beat>();
    for (const [id, beat] of data.beatsById.entries()) {
      clonedBeats.set(id, JSON.parse(JSON.stringify(beat)));
    }
    const clonedCards = new Map(data.cardsById);
    const syn: MutableGameData = {
      ...data,
      beats: [...data.beats],
      beatsById: clonedBeats,
      cardsById: clonedCards,
    };
    modifier(syn);
    return syn as unknown as GameData;
  }

  it('6. Rejection matrix: exact machine codes (13 cases) and byte-identical state snapshot', () => {
    const testData = createSyntheticData((d) => {
      const beat = d.beatsById.get('d17_19_prescription')!;
      // Add slot with requires for 'locked' rejection test
      const lockedSlot: Slot = {
        id: 'test_locked_slot',
        occupant: null,
        label: '需要前置的委託',
        accepts: ['npc_ajie'],
        requires: { flag: 'must_have_test_flag' },
        reject_reason: '前置條件不足',
        delegation: {
          result_timing: 'immediate',
          preview: '測試預覽',
          tendency: '測試傾向',
        },
      };
      // Add slot with broken delegation config for 'data_conflict' rejection test
      const conflictSlot: Slot = {
        id: 'test_conflict_slot',
        occupant: null,
        label: '壞掉的隔日委託',
        accepts: ['npc_ajie'],
        delegation: {
          result_timing: 'next_morning',
          preview: '測試預覽',
          tendency: '測試傾向',
          // missing report object!
        } as unknown as Delegation,
      };
      appendSlots(beat, lockedSlot, conflictSlot);
    });

    const snap = injectAt(17, 'afternoon', (s) => {
      s.run.hand.push('npc_ajie', 'npc_azhu');
    });

    const cases: Array<{
      desc: string;
      setup: (s: GameSnapshot) => void;
      action: (g: ReturnType<typeof createGame>) => { ok: boolean; reason_code: string };
      expectedCode: string;
    }> = [
      {
        desc: '1. not_run: flow mode is opening',
        setup: (s) => {
          s.flow.mode = 'opening';
        },
        action: (g) => g.delegate('d17_19_prescription', 'ask_ajie', 'npc_ajie'),
        expectedCode: 'not_run',
      },
      {
        desc: '2. encounter_active: active encounter ongoing',
        setup: (s) => {
          s.run.active_encounter = { beat_id: 'test_enc', stage: 'intro' };
        },
        action: (g) => g.delegate('d17_19_prescription', 'ask_ajie', 'npc_ajie'),
        expectedCode: 'encounter_active',
      },
      {
        desc: '3. not_action_phase: phase is evening',
        setup: (s) => {
          s.run.phase = 'evening';
        },
        action: (g) => g.delegate('d17_19_prescription', 'ask_ajie', 'npc_ajie'),
        expectedCode: 'not_action_phase',
      },
      {
        desc: '4. unknown_beat: beat does not exist',
        setup: () => {},
        action: (g) => g.delegate('non_existent_beat', 'ask_ajie', 'npc_ajie'),
        expectedCode: 'unknown_beat',
      },
      {
        desc: '5. unknown_slot: slot does not exist',
        setup: () => {},
        action: (g) => g.delegate('d17_19_prescription', 'non_existent_slot', 'npc_ajie'),
        expectedCode: 'unknown_slot',
      },
      {
        desc: '6. not_delegation: slot has no delegation block',
        setup: () => {},
        action: (g) => g.delegate('d17_19_prescription', 'find_self', 'npc_ajie'),
        expectedCode: 'not_delegation',
      },
      {
        desc: '7. not_held: card not held in hand',
        setup: (s) => {
          s.run.hand = ['protagonist', 'npc_ajie'];
        },
        action: (g) => g.delegate('d17_19_prescription', 'ask_ajie', 'npc_azhu'),
        expectedCode: 'not_held',
      },
      {
        desc: '8. not_person: card is protagonist not person',
        setup: () => {},
        action: (g) => g.delegate('d17_19_prescription', 'ask_ajie', 'protagonist'),
        expectedCode: 'not_person',
      },
      {
        desc: '9. not_accepted: person card not in slot.accepts',
        setup: () => {},
        action: (g) => g.delegate('d17_19_prescription', 'ask_azhu', 'npc_ajie'),
        expectedCode: 'not_accepted',
      },
      {
        desc: '10. already_delegated_today: person used today',
        setup: (s) => {
          s.run.delegates_used_today.npc_ajie = true;
        },
        action: (g) => g.delegate('d17_19_prescription', 'ask_ajie', 'npc_ajie'),
        expectedCode: 'already_delegated_today',
      },
      {
        desc: '11. locked: slot requires condition unsatisfied',
        setup: () => {},
        action: (g) => g.delegate('d17_19_prescription', 'test_locked_slot', 'npc_ajie'),
        expectedCode: 'locked',
      },
      {
        desc: '12. already_resolved: slot or choice group already placed',
        setup: (s) => {
          s.run.choices['d17_19_prescription::prescription_route'] = 'find_self';
        },
        action: (g) => g.delegate('d17_19_prescription', 'ask_ajie', 'npc_ajie'),
        expectedCode: 'already_resolved',
      },
      {
        desc: '13. data_conflict: next_morning delegation missing report object',
        setup: () => {},
        action: (g) => g.delegate('d17_19_prescription', 'test_conflict_slot', 'npc_ajie'),
        expectedCode: 'data_conflict',
      },
    ];

    expect(cases.length).toBe(13);

    for (const c of cases) {
      const cloned = JSON.parse(JSON.stringify(snap)) as GameSnapshot;
      c.setup(cloned);
      const beforeJson = JSON.stringify(cloned);
      const game = createGame(testData, cloned);
      const res = c.action(game);
      expect(res.ok, `${c.desc} ok must be false`).toBe(false);
      expect(res.reason_code, `${c.desc} reason_code`).toBe(c.expectedCode);
      expect(JSON.stringify(game.serialize()), `${c.desc} state unchanged`).toBe(beforeJson);
    }
  });

  it('7. Pending delegation error handling: bad reference and bad effect transactions retain pending and log explicit error', () => {
    // Part A: Night transition with bad reference (non_existent_beat)
    const snapA = injectAt(17, 'night', (s) => {
      s.run.night_location_chosen = 'n_exit';
      s.run.night_sleep_pending = true;
      s.run.pending_delegation_reports = [
        {
          due_day: 18,
          beat_id: 'non_existent_beat',
          slot_id: 'non_existent_slot',
          person_id: 'npc_ajie',
        },
      ];
    });

    const spyA = vi.spyOn(console, 'error').mockImplementation(() => {});
    try {
      const gameA = createGame(data, snapA);
      const advA = gameA.advancePhase();
      expect(advA.ok).toBe(true);
      expect(advA.phase_advanced).toBe(true);
      expect(gameA.getPhaseView().day).toBe(18);
      expect(gameA.getPhaseView().phase).toBe('morning');

      // Bad reference report retained in pending
      expect(gameA.getSnapshot().run.pending_delegation_reports).toEqual([
        {
          due_day: 18,
          beat_id: 'non_existent_beat',
          slot_id: 'non_existent_slot',
          person_id: 'npc_ajie',
        },
      ]);
      expect(spyA).toHaveBeenCalled();
      const hasConflictMsg = spyA.mock.calls.some((args) =>
        args.some((a) => String(a).includes('pending delegation report data conflict')),
      );
      expect(hasConflictMsg).toBe(true);
    } finally {
      spyA.mockRestore();
    }

    // Part B: Valid reference but invalid report effect transaction (invalid gain item)
    const testDataB = createSyntheticData((d) => {
      const beat = d.beatsById.get('d17_19_prescription')!;
      const badReportSlot: Slot = {
        id: 'bad_report_slot',
        occupant: null,
        label: '無效回報效果',
        accepts: ['npc_azhu'],
        delegation: {
          result_timing: 'next_morning',
          preview: '預覽',
          tendency: '傾向',
          report: {
            gain: ['invalid_non_existent_card_id'],
          },
        },
      };
      appendSlots(beat, badReportSlot);
    });

    const snapB = injectAt(17, 'night', (s) => {
      s.run.night_location_chosen = 'n_exit';
      s.run.night_sleep_pending = true;
      s.run.pending_delegation_reports = [
        {
          due_day: 18,
          beat_id: 'd17_19_prescription',
          slot_id: 'bad_report_slot',
          person_id: 'npc_azhu',
        },
      ];
    });

    const spyB = vi.spyOn(console, 'error').mockImplementation(() => {});
    try {
      const gameB = createGame(testDataB, snapB);
      const handBefore = [...gameB.getSnapshot().run.hand];
      const advB = gameB.advancePhase();
      expect(advB.ok).toBe(true);
      expect(gameB.getPhaseView().day).toBe(18);

      // Report transaction failed -> retained in pending
      expect(gameB.getSnapshot().run.pending_delegation_reports).toEqual([
        {
          due_day: 18,
          beat_id: 'd17_19_prescription',
          slot_id: 'bad_report_slot',
          person_id: 'npc_azhu',
        },
      ]);
      // Zero partial effect applied to hand
      expect(gameB.getSnapshot().run.hand).toEqual(handBefore);
      expect(spyB).toHaveBeenCalled();
      const hasSettleFailMsg = spyB.mock.calls.some((args) =>
        args.some((a) => String(a).includes('回報效果結算失敗')),
      );
      expect(hasSettleFailMsg).toBe(true);
    } finally {
      spyB.mockRestore();
    }
  });

  it('8. Ending stops subsequent delegation reports from executing, and forced settlement entering ending halts reports', () => {
    // Part A: Two due reports on D18 morning:
    // First report triggers madness cap ending; second report has countable effect.
    const testDataA = createSyntheticData((d) => {
      const beat = d.beatsById.get('d17_19_prescription')!;
      const endingSlot: Slot = {
        id: 'slot_ending_report',
        occupant: null,
        label: '結局回報',
        accepts: ['npc_azhu'],
        delegation: {
          result_timing: 'next_morning',
          preview: '預覽',
          tendency: '傾向',
          report: {
            ending: 'ending_inventory_be',
          },
        },
      };
      const counterSlot: Slot = {
        id: 'slot_counter_report',
        occupant: null,
        label: '計數回報',
        accepts: ['npc_ajie'],
        delegation: {
          result_timing: 'next_morning',
          preview: '預覽',
          tendency: '傾向',
          report: {
            switch_progress: { test_counter: 1 },
          },
        },
      };
      appendSlots(beat, endingSlot, counterSlot);
    });

    const snapA = injectAt(17, 'night', (s) => {
      s.run.night_location_chosen = 'n_exit';
      s.run.night_sleep_pending = true;
      s.run.pending_delegation_reports = [
        {
          due_day: 18,
          beat_id: 'd17_19_prescription',
          slot_id: 'slot_ending_report',
          person_id: 'npc_azhu',
        },
        {
          due_day: 18,
          beat_id: 'd17_19_prescription',
          slot_id: 'slot_counter_report',
          person_id: 'npc_ajie',
        },
      ];
    });

    const gameA = createGame(testDataA, snapA);
    const advA = gameA.advancePhase();
    expect(advA.ok).toBe(true);

    // Mode is now ending
    expect(gameA.getSnapshot().flow.mode).toBe('ending');
    // First report removed; second report retained/unapplied
    expect(gameA.getSnapshot().run.pending_delegation_reports).toEqual([
      {
        due_day: 18,
        beat_id: 'd17_19_prescription',
        slot_id: 'slot_counter_report',
        person_id: 'npc_ajie',
      },
    ]);
    // Second report was NEVER applied
    expect(gameA.getSnapshot().run.switch_progress.test_counter).toBeUndefined();

    // Part B: Forced settlement enters ending before reports run
    // Using tests/indulgence.test.ts pattern: forced indulgence exit triggers ending on morning entry
    const testDataB = createSyntheticData((d) => {
      const exit: Beat = {
        id: 'test_forced_ending_exit',
        location: 'sanquan',
        slots: [
          {
            id: 'ending_exit',
            occupant: null,
            label: '結局出口',
            accepts: ['madness'],
            indulgence: { weight: 100 },
            on_place: { ending: 'ending_inventory_be' },
          },
        ],
      };
      d.beats = [...d.beats, exit];
      d.beatsById.set(exit.id, exit);
    });

    const snapB = injectAt(17, 'night', (s) => {
      s.run.night_location_chosen = 'n_exit';
      s.run.night_sleep_pending = true;
      s.run.hand.push('madness#1');
      s.run.forced_pending = ['madness#1'];
      s.run.pending_delegation_reports = [
        {
          due_day: 18,
          beat_id: 'd17_19_prescription',
          slot_id: 'ask_azhu',
          person_id: 'npc_azhu',
        },
      ];
    });

    const gameB = createGame(testDataB, snapB);
    const advB = gameB.advancePhase();
    expect(advB.ok).toBe(true);
    expect(gameB.getSnapshot().flow.mode).toBe('ending');
    // Pending reports remain unapplied
    expect(gameB.getSnapshot().run.pending_delegation_reports.length).toBe(1);
    expect(gameB.hasCard('doc_prescription')).toBe(false);
  });

  it('9. Once-only proof with countable effect & pending serialize roundtrip with person removed', () => {
    const testData = createSyntheticData((d) => {
      const beat = d.beatsById.get('d17_19_prescription')!;
      const countableSlot: Slot = {
        id: 'slot_countable_report',
        occupant: null,
        label: '計數回報',
        accepts: ['npc_azhu'],
        delegation: {
          result_timing: 'next_morning',
          preview: '查探診所',
          tendency: '傾向',
          report: {
            switch_progress: { test_countable_switch: 1 },
            relation: { npc: 'azhu', delta: 1 },
          },
        },
      };
      appendSlots(beat, countableSlot);
    });

    // Delegate on D17 afternoon
    const snap = injectAt(17, 'afternoon', (s) => {
      s.run.hand.push('npc_azhu');
    });
    const game = createGame(testData, snap);
    const delRes = game.delegate('d17_19_prescription', 'slot_countable_report', 'npc_azhu');
    expect(delRes.ok).toBe(true);
    expect(game.getSnapshot().run.pending_delegation_reports.length).toBe(1);

    // Remove person card from hand and perform serialize/deserialize roundtrip
    const serialized = game.serialize();
    serialized.run.hand = serialized.run.hand.filter((c) => c !== 'npc_azhu');
    expect(serialized.run.hand.includes('npc_azhu')).toBe(false);

    const roundtripSnap = JSON.parse(JSON.stringify(serialized)) as GameSnapshot;
    const restoredGame = createGame(testData, roundtripSnap);

    // Advance through evening -> night
    expect(restoredGame.advancePhase().ok).toBe(true); // afternoon -> evening
    expect(restoredGame.playEvening().ok).toBe(true);
    expect(restoredGame.advancePhase().ok).toBe(true); // evening -> night
    expect(restoredGame.playNightFixed().ok).toBe(true);

    // Night advance (sleep to D18 morning)
    const advToD18 = restoredGame.advancePhase();
    expect(advToD18.ok).toBe(true);
    expect(restoredGame.getPhaseView().day).toBe(18);
    expect(restoredGame.getPhaseView().phase).toBe('morning');

    // Even though person card was removed, pending report applied once
    expect(restoredGame.getSnapshot().run.switch_progress.test_countable_switch).toBe(1);
    expect(restoredGame.getSnapshot().run.relations.azhu).toBe(1);
    expect(restoredGame.getSnapshot().run.pending_delegation_reports.length).toBe(0);

    // Advance through another entire day to verify effect is NEVER re-applied
    expect(restoredGame.advancePhase().ok).toBe(true); // D18 morning -> afternoon
    expect(restoredGame.advancePhase().ok).toBe(true); // D18 afternoon -> evening
    expect(restoredGame.playEvening().ok).toBe(true);
    expect(restoredGame.advancePhase().ok).toBe(true); // D18 evening -> night
    expect(restoredGame.playNightFixed().ok).toBe(true);
    expect(restoredGame.advancePhase().ok).toBe(true); // D18 night -> D19 morning
    expect(restoredGame.getPhaseView().day).toBe(19);

    // Count stays exactly once
    expect(restoredGame.getSnapshot().run.switch_progress.test_countable_switch).toBe(1);
    expect(restoredGame.getSnapshot().run.relations.azhu).toBe(1);
  });

  it('10. Same-person daily limit independent of choice resolution & next day available on different group', () => {
    const testData = createSyntheticData((d) => {
      const beat = d.beatsById.get('d17_19_prescription')!;
      // Second slot in a DIFFERENT choice group
      const otherGroupSlot: Slot = {
        id: 'slot_other_group',
        occupant: null,
        label: '另一組委託',
        accepts: ['npc_ajie'],
        choice_group: 'different_choice_group',
        delegation: {
          result_timing: 'immediate',
          preview: '其他事情',
          tendency: '傾向',
        },
        on_place: {
          flag: { other_group_done: true },
        },
      };
      appendSlots(beat, otherGroupSlot);
    });

    const snap = injectAt(17, 'afternoon', (s) => {
      s.run.hand.push('npc_ajie');
    });
    const game = createGame(testData, snap);

    // 1. Delegate ask_ajie (group: prescription_route)
    const del1 = game.delegate('d17_19_prescription', 'ask_ajie', 'npc_ajie');
    expect(del1.ok).toBe(true);

    // 2. Try delegating npc_ajie to slot_other_group (different choice group, unresolved)
    const del2 = game.delegate('d17_19_prescription', 'slot_other_group', 'npc_ajie');
    expect(del2.ok).toBe(false);
    expect(del2.reason_code).toBe('already_delegated_today');

    // 3. Advance to D18 morning -> delegates_used_today clears
    expect(game.advancePhase().ok).toBe(true); // afternoon -> evening
    expect(game.playEvening().ok).toBe(true);
    expect(game.advancePhase().ok).toBe(true); // evening -> night
    expect(game.playNightFixed().ok).toBe(true);
    expect(game.advancePhase().ok).toBe(true); // night -> D18 morning
    expect(game.getSnapshot().run.delegates_used_today.npc_ajie).toBeUndefined();

    // 4. Advance to D18 afternoon -> npc_ajie can now be delegated to the other group
    expect(game.advancePhase().ok).toBe(true);
    expect(game.getPhaseView().phase).toBe('afternoon');

    const del3 = game.delegate('d17_19_prescription', 'slot_other_group', 'npc_ajie');
    expect(del3.ok).toBe(true);
    expect(game.getSnapshot().run.flags.other_group_done).toBe(true);
  });

  it('11. Date window: formal d17_19_prescription valid on D18 and D19 afternoon, expired on D20', () => {
    // D18 afternoon
    const snap18 = injectAt(18, 'afternoon', (s) => {
      s.run.hand.push('npc_ajie');
    });
    const game18 = createGame(data, snap18);
    const panel18 = game18.buildPanel('sanquan');
    const beat18 = panel18.beats.find((b) => b.id === 'd17_19_prescription');
    expect(beat18).toBeDefined();
    expect(beat18!.tri).toBe(TriState.OPEN);
    expect(game18.delegate('d17_19_prescription', 'ask_ajie', 'npc_ajie').ok).toBe(true);

    // D19 afternoon
    const snap19 = injectAt(19, 'afternoon', (s) => {
      s.run.hand.push('npc_ajie');
    });
    const game19 = createGame(data, snap19);
    const panel19 = game19.buildPanel('sanquan');
    const beat19 = panel19.beats.find((b) => b.id === 'd17_19_prescription');
    expect(beat19).toBeDefined();
    expect(beat19!.tri).toBe(TriState.OPEN);
    expect(game19.delegate('d17_19_prescription', 'ask_ajie', 'npc_ajie').ok).toBe(true);

    // D20 afternoon (day_to was 19, so beat is not active)
    const snap20 = injectAt(20, 'afternoon', (s) => {
      s.run.hand.push('npc_ajie');
    });
    const game20 = createGame(data, snap20);
    const del20 = game20.delegate('d17_19_prescription', 'ask_ajie', 'npc_ajie');
    expect(del20.ok).toBe(false);
    expect(del20.reason_code).toBe('unknown_beat');
  });

  it('12. Query purity: delegationStatus, buildPanel, and previewSlot produce zero state mutations', () => {
    const snap = injectAt(17, 'afternoon', (s) => {
      s.run.hand.push('npc_ajie', 'npc_azhu');
    });
    const game = createGame(data, snap);
    const initialJson = JSON.stringify(game.serialize());

    // Execute queries repeatedly
    game.delegationStatus('npc_ajie');
    game.delegationStatus('npc_azhu');
    game.delegationStatus('npc_acai');
    game.buildPanel('sanquan');
    game.previewSlot('d17_19_prescription', 'ask_ajie');
    game.previewSlot('d17_19_prescription', 'ask_azhu');
    game.placeableCards('d17_19_prescription', 'ask_ajie');

    expect(JSON.stringify(game.serialize())).toBe(initialJson);
  });
});
