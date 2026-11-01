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
  evalCondition,
} from '../src/core/condition';
import { planEffects } from '../src/core/effect';
import { createGame } from '../src/core/state';
import { createRunForTrace } from '../src/core/trace-entry';
import { loadGameDataNode } from '../src/data/load-node';
import type { GameData } from '../src/data/types';
import { buildWebTrace } from '../scripts/trace-web';
import { assertNightFixedPlayback } from './support/greedy';

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

    // madness card gain creates a countdown instance (W6-A); the cap is checked by the caller
    expect(gainCard(draft, 'madness', data).ok).toBe(true);
    expect(draft.run.hand).toEqual(['protagonist', 'item_family_album', 'madness#1']);
    expect(draft.run.madness_clock['madness#1']).toBe(data.tuning.madness_countdown_days);
    loseCard(draft, 'madness#1', data);
    expect(draft.run.hand).toEqual(['protagonist', 'item_family_album']);
    // lose protagonist is rejected with data_conflict
    expect(loseCard(draft, 'protagonist', data).reason_code).toBe(
      'data_conflict',
    );

    // evalCondition: W4-A implements full operator vocabulary; unknown operator or empty object throws ConditionError, never defaults to true
    expect(evalCondition({ flag: 'returned_opening_call' }, draft, data)).toBe(
      false,
    );
    expect(() =>
      evalCondition(
        { unknown_op: 'whatever' } as unknown as Parameters<
          typeof evalCondition
        >[0],
        draft,
        data,
      ),
    ).toThrow(ConditionError);
    expect(() =>
      evalCondition(
        {} as unknown as Parameters<typeof evalCondition>[0],
        draft,
        data,
      ),
    ).toThrow(ConditionError);

    // planEffects: if a later key in the same or subsequent block has bad data, zero state and zero lines leak
    const beforeJson = JSON.stringify(draft);
    const failedPlan = planEffects(
      [
        {
          text: '這段文字不應流出',
          gain: ['k_not_today'],
          festival_proxy: { mode: 'fixed', npc: 'nonexistent_candidate' },
        },
      ],
      draft,
      data,
    );
    expect(failedPlan.ok).toBe(false);
    expect(failedPlan.reason_code).toBe('data_conflict');
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

    // 3. Night sleep (W6-A): a resolved sanquan sleep beat stops the first advance (phase_advanced:false, night_sleep_pending) and the second advance changes day
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
    // 未選地點時 can_advance 為 true（直接睡），按下去只停拍、不換日
    expect(nightGame.getPhaseView().can_advance).toBe(true);
    expect(nightGame.getPhaseView().night_advance).toBe('sleep');
    const sleepAdvRes = nightGame.advancePhase();
    expect(sleepAdvRes.ok).toBe(true);
    expect(sleepAdvRes.phase_advanced).toBe(false);
    expect(sleepAdvRes.lines).toEqual(['旅館就寢演出']);
    expect(nightGame.getSnapshot().run.phase).toBe('night');
    expect(nightGame.getSnapshot().run.night_sleep_pending).toBe(true);
    expect(nightGame.getPhaseView().night_advance).toBe('next_day');
    expect(nightGame.getPhaseView().lines).toEqual(['旅館就寢演出']);
    // 停拍後不能再進地點，playNightFixed 也不會把今晚改成強制到訪
    expect(nightGame.enterNightLocation('n_corridor').reason_code).toBe('already_slept');
    expect(nightGame.playNightFixed().ok).toBe(true);
    expect(nightGame.getSnapshot().run.night_location_chosen).toBe('');
    // 先走 D1 的強制到訪也一樣，只是改走另一條：重建一局，先 playNightFixed 再推進，不再解析睡覺
    const fixedFirstGame = createGame(sleepData);
    expect(fixedFirstGame.chooseOpening('take_family_album').ok).toBe(true);
    expect(fixedFirstGame.advancePhase().ok).toBe(true);
    expect(fixedFirstGame.advancePhase().ok).toBe(true);
    expect(fixedFirstGame.playEvening().ok).toBe(true);
    expect(fixedFirstGame.advancePhase().ok).toBe(true);
    expect(fixedFirstGame.playNightFixed().ok).toBe(true);
    expect(fixedFirstGame.getSnapshot().run.night_location_chosen).toBe('n_corridor');
    expect(fixedFirstGame.getPhaseView().night_advance).toBe('end_night');
    expect(fixedFirstGame.getPhaseView().can_advance).toBe(true);
    const fixedFirstAdv = fixedFirstGame.advancePhase();
    expect(fixedFirstAdv.phase_advanced).toBe(true);
    expect(fixedFirstGame.getSnapshot().run.day).toBe(2);

    // 4. madness_clock (W6-A): the night→morning transition ticks every card once; no more date/clock guard
    const madnessNightInit = fixedFirstGame.serialize();
    madnessNightInit.run.day = 1;
    madnessNightInit.run.phase = 'night';
    madnessNightInit.run.night_location_chosen = 'n_corridor';
    madnessNightInit.run.madness_clock = { test_clock: 2 };
    const madnessNightGame = createGame(data, madnessNightInit);
    expect(madnessNightGame.getPhaseView().can_advance).toBe(true);
    expect(madnessNightGame.advancePhase().phase_advanced).toBe(true);
    expect(madnessNightGame.getSnapshot().run.madness_clock).toEqual({ test_clock: 1 });

    // 5. actions_spent_ahead applies prepaid action in next action phase (W6-B)
    const aheadInit = createRunForTrace(data).serialize();
    aheadInit.run.actions_spent_ahead = 1;
    const aheadGame = createGame(data, aheadInit);
    expect(aheadGame.getPhaseView().can_advance).toBe(true);
    expect(aheadGame.advancePhase().phase_advanced).toBe(true);
    expect(aheadGame.getSnapshot().run.phase).toBe('afternoon');
    expect(aheadGame.getSnapshot().run.action_spent).toBe(true);
    expect(aheadGame.getSnapshot().run.actions_spent_ahead).toBe(0);

    // 6. forced_pending settles at action phase (W6-B)
    const forcedInit = createRunForTrace(data).serialize();
    forcedInit.run.hand.push('madness#1');
    forcedInit.run.madness_clock['madness#1'] = 0;
    forcedInit.run.forced_pending = ['madness#1'];
    const forcedGame = createGame(data, forcedInit);
    expect(forcedGame.getPhaseView().can_advance).toBe(true);
    const forcedAdv = forcedGame.advancePhase();
    expect(forcedAdv.phase_advanced).toBe(true);
    expect(forcedGame.getSnapshot().run.forced_pending).toEqual([]);
    expect(forcedGame.getSnapshot().run.action_spent).toBe(true);

    // 7. delegates_used_today is cleared when advancing to morning (D1 night -> D2 morning)
    const delegInit = nightGame.serialize();
    delegInit.run.night_sleep_pending = false;
    delegInit.run.night_location_chosen = 'n_corridor';
    delegInit.run.delegates_used_today = { npc_lin: true };
    const delegGame = createGame(data, delegInit);
    expect(delegGame.getPhaseView().can_advance).toBe(true);
    expect(delegGame.advancePhase().ok).toBe(true);
    expect(delegGame.getSnapshot().run.delegates_used_today).toEqual({});
  });

  it('assertNightFixedPlayback correctly tracks night-layer fixed beats with empty text and does not mistake skipped meta_once for playback', () => {
    // 1. Fixture with an empty-text fixed night beat on night layer
    const emptyTextNightBeat = {
      id: 'test_empty_text_night_beat',
      location: 'n_corridor',
      chapter: 1,
      when: { day: 1, phase: 'night' as const },
      fixed: true,
      text: '',
      slots: [],
    };
    const beatsMap1 = new Map(data.beatsById);
    beatsMap1.set(emptyTextNightBeat.id, emptyTextNightBeat);
    const fixtureData: GameData = {
      ...data,
      beats: [
        ...data.beats.filter(
          (b) => !(b.when?.day === 1 && b.when?.phase === 'night' && b.fixed),
        ),
        emptyTextNightBeat,
      ],
      beatsById: beatsMap1,
    };

    // Initial night state
    const nightState = createRunForTrace(fixtureData).serialize();
    nightState.run.day = 1;
    nightState.run.phase = 'night';
    const game = createGame(fixtureData, nightState);

    const before = game.getSnapshot();
    const playRes = game.playNightFixed();
    expect(playRes.ok).toBe(true);
    expect(playRes.lines).toEqual([]); // empty text emits zero lines

    const after = game.getSnapshot();
    // assertNightFixedPlayback must still recognize newly entered beat and assert forced visit
    expect(() =>
      assertNightFixedPlayback(before, after, fixtureData),
    ).not.toThrow();
    expect(after.run.night_location_chosen).toBe('n_corridor');
    expect(after.meta.night_locations_seen.n_corridor).toBe(true);

    // 2. Skipped meta_once: second play of a meta_once beat should not enter beats_entered and must NOT assert forced visit
    const metaOnceBeat = {
      id: 'test_meta_once_night_beat',
      location: 'n_exit',
      chapter: 1,
      when: { day: 2, phase: 'night' as const },
      fixed: true,
      meta_once: true,
      text: '一次性固定夜晚演出',
      slots: [],
    };
    const beatsMap2 = new Map(data.beatsById);
    beatsMap2.set(metaOnceBeat.id, metaOnceBeat);
    const metaOnceData: GameData = {
      ...data,
      beats: [
        ...data.beats.filter(
          (b) => !(b.when?.day === 2 && b.when?.phase === 'night' && b.fixed),
        ),
        metaOnceBeat,
      ],
      beatsById: beatsMap2,
    };

    const metaState = createRunForTrace(metaOnceData).serialize();
    metaState.run.day = 2;
    metaState.run.phase = 'night';
    // Mark as already seen in meta
    metaState.meta.night_once_beats_seen[metaOnceBeat.id] = true;
    metaState.run.night_location_chosen = ''; // not visited

    const metaGame = createGame(metaOnceData, metaState);
    const beforeSkip = metaGame.getSnapshot();
    const skipRes = metaGame.playNightFixed();
    expect(skipRes.ok).toBe(true);
    const afterSkip = metaGame.getSnapshot();

    // assertNightFixedPlayback sees zero newly entered fixed night beats, so it does NOT throw even though night_location_chosen is empty
    expect(() =>
      assertNightFixedPlayback(beforeSkip, afterSkip, metaOnceData),
    ).not.toThrow();
    expect(afterSkip.run.night_location_chosen).toBe('');
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
