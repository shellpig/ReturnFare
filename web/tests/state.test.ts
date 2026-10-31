import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { beforeAll, describe, expect, it } from 'vitest';
import {
  compareTraces,
  type CompareOptions,
  type Trace,
} from '../../tools/trace/compare';
import {
  gainCard,
  handSlotsUsed,
  hasCard,
  hasKnowledge,
  loseCard,
} from '../src/core/cards';
import {
  ConditionError,
  UnsupportedConditionError,
  evalCondition,
} from '../src/core/condition';
import { planEffects } from '../src/core/effect';
import { createGame } from '../src/core/state';
import { createRunForTrace } from '../src/core/trace-entry';
import { loadGameDataNode } from '../src/data/load-node';
import type { GameData } from '../src/data/types';
import { buildWebTrace } from '../scripts/trace-web';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '..', '..');

describe('W3-B GameState store, core engines, and trace parity', () => {
  let data: GameData;

  beforeAll(async () => {
    data = await loadGameDataNode();
  });

  it('createGame() initializes fresh boot state in opening mode with empty hand and deep-cloned serialize()', () => {
    const game = createGame(data);
    const snap1 = game.getSnapshot();
    const snap2 = game.getSnapshot();
    expect(snap1).toBe(snap2);

    expect(snap1.flow).toEqual({
      mode: 'opening',
      active_ending: null,
    });
    expect(snap1.run.day).toBe(1);
    expect(snap1.run.phase).toBe('morning');
    expect(snap1.run.hand).toEqual([]);
    expect(snap1.run.opening_choice_id).toBeNull();
    expect(snap1.meta.run_number).toBe(1);

    const serialized = game.serialize();
    expect(serialized).toEqual(snap1);
    expect(serialized).not.toBe(snap1);

    // Mutating serialized copy must not affect internal store state
    serialized.run.day = 99;
    serialized.run.hand.push('protagonist');
    serialized.meta.knowledge['k_i_returned'] = true;
    expect(game.getSnapshot().run.day).toBe(1);
    expect(game.getSnapshot().run.hand).toEqual([]);
    expect(game.getSnapshot().meta.knowledge).toEqual({});
  });

  it('getSnapshot() enforces deep runtime read-only protection while keeping reference identity stable', () => {
    const game = createGame(data);
    let notified = 0;
    game.subscribe(() => {
      notified += 1;
    });

    const snap = game.getSnapshot();
    expect(Object.is(snap, game.getSnapshot())).toBe(true);

    // Top-level and nested mutations on getSnapshot() must throw TypeError at runtime
    expect(() => {
      (snap as unknown as { flow: unknown }).flow = {
        mode: 'run',
        active_ending: null,
      };
    }).toThrow(TypeError);
    expect(() => {
      (snap.run as unknown as { day: number }).day = 99;
    }).toThrow(TypeError);
    expect(() => {
      (snap.run.hand as unknown as string[]).push('protagonist');
    }).toThrow(TypeError);
    expect(() => {
      (snap.run.flags as unknown as Record<string, boolean>).probe = true;
    }).toThrow(TypeError);
    expect(() => {
      (snap.meta.knowledge as unknown as Record<string, boolean>).k_i_returned =
        true;
    }).toThrow(TypeError);

    expect(game.getSnapshot().run.day).toBe(1);
    expect(game.getSnapshot().run.hand).toEqual([]);
    expect(notified).toBe(0);
    expect(Object.is(snap, game.getSnapshot())).toBe(true);

    // After a valid mutation, the new snapshot must also be deeply frozen and stable
    expect(game.chooseOpening('take_family_album').ok).toBe(true);
    const runSnap = game.getSnapshot();
    expect(Object.is(runSnap, game.getSnapshot())).toBe(true);
    expect(() => {
      (runSnap.run.hand as unknown as string[]).pop();
    }).toThrow(TypeError);
    expect(() => {
      (runSnap.run.beats_entered as unknown as Record<string, boolean>).hacked =
        true;
    }).toThrow(TypeError);
    expect(game.getSnapshot().run.hand).toEqual([
      'protagonist',
      'item_family_album',
    ]);
  });

  it('subscribe() notifies on state commits, does not notify on rejected mutations, and respects unsubscribe', () => {
    const game = createGame(data);
    let count = 0;
    const unsubscribe = game.subscribe(() => {
      count += 1;
    });

    // Rejected mutation in opening mode -> no notification
    const rej = game.advancePhase();
    expect(rej.ok).toBe(false);
    expect(rej.reason_code).toBe('not_run');
    expect(count).toBe(0);

    // Valid opening choice -> notifies once and updates snapshot reference
    const beforeSnap = game.getSnapshot();
    const okRes = game.chooseOpening('take_family_album');
    expect(okRes.ok).toBe(true);
    expect(count).toBe(1);
    expect(game.getSnapshot()).not.toBe(beforeSnap);

    unsubscribe();
    const advRes = game.advancePhase();
    expect(advRes.ok).toBe(true);
    expect(count).toBe(1);
  });

  it('cards.ts, condition.ts, and effect.ts enforce W3 subset and reject unimplemented operators/effects atomically', () => {
    const game = createGame(data);
    const draft = game.serialize();

    // gainCard: protagonist at index 0, unique item, slotless knowledge, loop_persistent item
    expect(gainCard(draft, 'protagonist', data).ok).toBe(true);
    expect(gainCard(draft, 'item_family_album', data).ok).toBe(true);
    expect(gainCard(draft, 'item_family_album', data).ok).toBe(true); // idempotent
    expect(gainCard(draft, 'k_i_returned', data).ok).toBe(true);
    expect(draft.run.hand).toEqual(['protagonist', 'item_family_album']);
    expect(handSlotsUsed(draft)).toBe(2);
    expect(hasCard(draft, 'item_family_album')).toBe(true);
    expect(hasCard(draft, 'k_i_returned')).toBe(true);
    expect(hasKnowledge(draft, 'k_i_returned')).toBe(true);

    // madness card gain is rejected in W3 with not_implemented
    expect(gainCard(draft, 'madness', data).reason_code).toBe('not_implemented');
    // lose protagonist is rejected with data_conflict
    expect(loseCard(draft, 'protagonist', data).reason_code).toBe(
      'data_conflict',
    );

    // evalCondition: unimplemented operator throws UnsupportedConditionError, never defaults to true
    expect(() =>
      evalCondition({ flag: 'returned_opening_call' }, draft, data),
    ).toThrow(UnsupportedConditionError);
    expect(() =>
      evalCondition(
        {} as unknown as Parameters<typeof evalCondition>[0],
        draft,
        data,
      ),
    ).toThrow(ConditionError);

    // planEffects: if a later key in the same or subsequent block is unimplemented, zero state and zero lines leak
    const beforeJson = JSON.stringify(draft);
    const failedPlan = planEffects(
      [
        {
          text: '這段文字不應流出',
          gain: ['k_not_today'],
          switch: 'some_switch',
        },
      ],
      draft,
      data,
    );
    expect(failedPlan.ok).toBe(false);
    expect(failedPlan.reason_code).toBe('not_implemented');
    expect(failedPlan.lines).toEqual([]);
    expect(JSON.stringify(draft)).toBe(beforeJson);
    expect(JSON.stringify(failedPlan.nextState)).toBe(beforeJson);

    // planEffects: flag strictly requires Dictionary (Record<string, boolean>); string or array shapes are rejected atomically with data_conflict
    const badFlagString = planEffects(
      [{ text: '不應流出', flag: 'probe' as unknown as Record<string, boolean> }],
      draft,
      data,
    );
    expect(badFlagString.ok).toBe(false);
    expect(badFlagString.reason_code).toBe('data_conflict');
    expect(badFlagString.lines).toEqual([]);
    expect(JSON.stringify(badFlagString.nextState)).toBe(beforeJson);

    const badFlagArray = planEffects(
      [
        {
          text: '不應流出',
          flag: ['probe'] as unknown as Record<string, boolean>,
        },
      ],
      draft,
      data,
    );
    expect(badFlagArray.ok).toBe(false);
    expect(badFlagArray.reason_code).toBe('data_conflict');
    expect(badFlagArray.lines).toEqual([]);
    expect(JSON.stringify(badFlagArray.nextState)).toBe(beforeJson);

    const validFlagDict = planEffects(
      [{ flag: { outside_job_waiting: true } }],
      draft,
      data,
    );
    expect(validFlagDict.ok).toBe(true);
    expect(validFlagDict.nextState.run.flags).toEqual({
      outside_job_waiting: true,
    });
  });

  it('advancePhase() 7-step skeleton and getPhaseView().can_advance stay strictly in sync across all guards', () => {
    // 1. encounter_active
    const encInitial = createRunForTrace(data).serialize();
    encInitial.run.active_encounter = { beat_id: 'dummy', stage: 'intro' };
    const encGame = createGame(data, encInitial);
    const encBefore = JSON.stringify(encGame.serialize());
    expect(encGame.getPhaseView().can_advance).toBe(false);
    const encRes = encGame.advancePhase();
    expect(encRes.ok).toBe(false);
    expect(encRes.reason_code).toBe('encounter_active');
    expect(encRes.phase_advanced).toBe(false);
    expect(JSON.stringify(encGame.serialize())).toBe(encBefore);

    // 2. phase_requirements_incomplete via isolated fixture
    const gateBeats = [
      ...data.beats,
      {
        id: 'test_d1_gate_beat',
        location: 'busstop',
        when: { day: 1, phase: 'morning' as const },
        fixed: true,
        text: '門檻測試',
        slots: [{ id: 'req_slot', label: '必填槽', accepts: ['protagonist'] }],
        phase_exit: { required_slots: ['req_slot'] },
      },
    ];
    const gateData: GameData = {
      ...data,
      beats: gateBeats,
      beatsById: new Map(gateBeats.map((b) => [b.id, b])),
    };
    const gateGame = createRunForTrace(gateData);
    const gateBefore = JSON.stringify(gateGame.serialize());
    expect(gateGame.getPhaseView().can_advance).toBe(false);
    const gateRes = gateGame.advancePhase();
    expect(gateRes.ok).toBe(false);
    expect(gateRes.reason_code).toBe('phase_requirements_incomplete');
    expect(JSON.stringify(gateGame.serialize())).toBe(gateBefore);

    // 3. Night sleep check guard: when a sanquan sleep candidate exists on D1 night, before playNightFixed() (night_location_chosen === ''), Step 3 blocks advancePhase -> can_advance must be false; after playNightFixed() sets night_location_chosen, can_advance becomes true
    const sleepBeats = [
      ...data.beats,
      {
        id: 'test_sleep_sanquan_ch1',
        location: 'sanquan',
        chapter: 1,
        text: '旅館就寢演出',
        slots: [],
      },
    ];
    const sleepData: GameData = {
      ...data,
      beats: sleepBeats,
      beatsById: new Map(sleepBeats.map((b) => [b.id, b])),
    };
    const nightGame = createGame(sleepData);
    expect(nightGame.chooseOpening('take_family_album').ok).toBe(true);
    expect(nightGame.advancePhase().ok).toBe(true); // -> D1 afternoon
    expect(nightGame.advancePhase().ok).toBe(true); // -> D1 evening
    expect(nightGame.playEvening().ok).toBe(true);
    expect(nightGame.advancePhase().ok).toBe(true); // -> D1 night
    expect(nightGame.getSnapshot().run.night_location_chosen).toBe('');
    expect(nightGame.getPhaseView().can_advance).toBe(false);
    const sleepAdvRes = nightGame.advancePhase();
    expect(sleepAdvRes.ok).toBe(false);
    expect(sleepAdvRes.reason_code).toBe('not_implemented');
    expect(nightGame.playNightFixed().ok).toBe(true);
    expect(nightGame.getSnapshot().run.night_location_chosen).toBe('n_corridor');
    expect(nightGame.getPhaseView().can_advance).toBe(true);

    // 4. madness_clock guard on night
    const madnessNightInit = nightGame.serialize();
    madnessNightInit.run.madness_clock = { test_clock: 2 };
    const madnessNightGame = createGame(data, madnessNightInit);
    expect(madnessNightGame.getPhaseView().can_advance).toBe(false);
    expect(madnessNightGame.advancePhase().reason_code).toBe('not_implemented');

    // 5. actions_spent_ahead guard
    const aheadInit = createRunForTrace(data).serialize();
    aheadInit.run.actions_spent_ahead = 1;
    const aheadGame = createGame(data, aheadInit);
    expect(aheadGame.getPhaseView().can_advance).toBe(false);
    expect(aheadGame.advancePhase().reason_code).toBe('not_implemented');

    // 6. forced_pending guard when advancing to an action phase (D1 morning -> D1 afternoon)
    const forcedInit = createRunForTrace(data).serialize();
    forcedInit.run.forced_pending = ['indulgence'];
    const forcedGame = createGame(data, forcedInit);
    expect(forcedGame.getPhaseView().can_advance).toBe(false);
    expect(forcedGame.advancePhase().reason_code).toBe('not_implemented');

    // 7. pending_delegation_reports / delegates_used_today guard when advancing to morning (D1 night -> D2 morning)
    const delegInit = nightGame.serialize();
    delegInit.run.delegates_used_today = { npc_lin: true };
    const delegGame = createGame(data, delegInit);
    expect(delegGame.getPhaseView().can_advance).toBe(false);
    expect(delegGame.advancePhase().reason_code).toBe('not_implemented');
  });

  it('createRunForTrace(data) matches greedy-godot.json seq 0..4 with W3.json scope (0 diff) and is not imported by browser entry/UI', async () => {
    const baselinePath = path.join(
      REPO_ROOT,
      'tools/trace/baselines/greedy-godot.json',
    );
    const scopePath = path.join(REPO_ROOT, 'tools/trace/scopes/W3.json');
    const baseline = JSON.parse(fs.readFileSync(baselinePath, 'utf-8')) as Trace;
    const scope = JSON.parse(
      fs.readFileSync(scopePath, 'utf-8'),
    ) as CompareOptions;

    // Direct check on seq 0 (run_start)
    const traceGame = createRunForTrace(data);
    expect(traceGame.serialize()).toEqual(baseline.checkpoints[0].state);

    // Full W3 trace comparison (seq 0..4)
    const actualTrace = (await buildWebTrace()) as unknown as Trace;
    const cmp = compareTraces(baseline, actualTrace, scope);
    expect(cmp.equal).toBe(true);
    expect(cmp.comparedCheckpoints).toBe(5);
    expect(cmp.difference).toBeNull();

    // Verify browser entrypoint does not import trace-entry
    const mainTsx = fs.readFileSync(
      path.join(REPO_ROOT, 'web/src/main.tsx'),
      'utf-8',
    );
    expect(mainTsx).not.toContain('trace-entry');
    expect(mainTsx).not.toContain('createRunForTrace');
  });
});
