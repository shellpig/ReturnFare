import { beforeAll, describe, expect, it } from 'vitest';
import { createGame } from '../src/core/state';
import type { EndingHistoryRecord } from '../src/core/state-types';
import { loadGameDataNode } from '../src/data/load-node';
import type { GameData } from '../src/data/types';

function makeReplacedHistoryRecord(): EndingHistoryRecord {
  return {
    run_number: 1,
    ending_id: 'ending_replaced',
    opening_choice_id: 'take_family_album',
    ended_day: 45,
    ended_phase: 'evening',
    partner_variant: 'partner_none',
    livelihood_variant: 'livelihood_default',
    inn_appearance_variant: 'inn_default',
    festival_proxy_npc: 'npc_lin',
    knowledge_gained_this_run: [],
  };
}

describe('W3-B opening view, rejection matrix, and formal opening paths (D1 -> D2 morning)', () => {
  let data: GameData;

  beforeAll(async () => {
    data = await loadGameDataNode();
  });

  it('chapter(), openingScreenView(), and openingView() match contract API and project choices in data order without leaking requires/on_select/ending', () => {
    const game = createGame(data);
    expect(typeof game.chapter).toBe('function');
    expect(typeof game.openingScreenView).toBe('function');
    expect(typeof game.openingView).toBe('function');

    expect(game.chapter()).toBe(1);
    const screen = game.openingScreenView();
    expect(screen).toEqual({
      title: data.openingScreen.title,
      prompt: data.openingScreen.prompt,
    });
    expect(game.getOpeningScreenView()).toEqual(screen);

    const view = game.openingView();
    expect(game.getOpeningView()).toEqual(view);
    expect(view.map((o) => o.id)).toEqual([
      'take_family_album',
      'return_missed_call',
      'refuse_boarding',
    ]);
    expect(view[0].available).toBe(true);
    expect(view[0].reason_text).toBe('');
    expect(view[1].available).toBe(true);
    expect(view[1].reason_text).toBe('');
    expect(view[2].available).toBe(false);
    expect(view[2].reason_text.length).toBeGreaterThan(0);

    for (const option of view) {
      expect(Object.keys(option).sort()).toEqual([
        'available',
        'confirm_text',
        'id',
        'label',
        'preview',
        'reason_text',
      ]);
    }
  });

  it('chooseOpening() rejects unknown, locked, unlocked ending-branch (W3 not_implemented), repeat call, and on_select ending conflict with zero state mutation', () => {
    const game = createGame(data);
    const initialSerialized = JSON.stringify(game.serialize());

    // 1. Unknown choice id
    const unknownRes = game.chooseOpening('non_existent_choice');
    expect(unknownRes.ok).toBe(false);
    expect(unknownRes.reason_code).toBe('unknown_opening_choice');
    expect(unknownRes.lines).toEqual([]);
    expect(JSON.stringify(game.serialize())).toBe(initialSerialized);

    // 2. Locked refuse_boarding on run 1
    const lockedRes = game.chooseOpening('refuse_boarding');
    expect(lockedRes.ok).toBe(false);
    expect(lockedRes.reason_code).toBe('opening_choice_locked');
    expect(lockedRes.reason_text).toBe(
      data.openingChoicesById.get('refuse_boarding')?.reject_reason,
    );
    expect(lockedRes.lines).toEqual([]);
    expect(JSON.stringify(game.serialize())).toBe(initialSerialized);

    // 3. Unlocked refuse_boarding in W3 -> not_implemented with zero state mutation
    const unlockedInit = game.serialize();
    unlockedInit.meta.run_number = 2;
    unlockedInit.meta.ending_history.push(makeReplacedHistoryRecord());
    const unlockedGame = createGame(data, unlockedInit);
    const unlockedBefore = JSON.stringify(unlockedGame.serialize());
    expect(unlockedGame.getOpeningView()[2].available).toBe(true);

    const refuseRes = unlockedGame.chooseOpening('refuse_boarding');
    expect(refuseRes.ok).toBe(false);
    expect(refuseRes.reason_code).toBe('not_implemented');
    expect(refuseRes.lines).toEqual([]);
    expect(JSON.stringify(unlockedGame.serialize())).toBe(unlockedBefore);

    // 4. Repeat chooseOpening after entering run -> not_opening with zero mutation
    const okRes = game.chooseOpening('take_family_album');
    expect(okRes.ok).toBe(true);
    const afterOpenSerialized = JSON.stringify(game.serialize());
    const repeatRes = game.chooseOpening('return_missed_call');
    expect(repeatRes.ok).toBe(false);
    expect(repeatRes.reason_code).toBe('not_opening');
    expect(repeatRes.lines).toEqual([]);
    expect(JSON.stringify(game.serialize())).toBe(afterOpenSerialized);

    // 5. Malformed opening choice where on_select contains ending -> data_conflict with zero mutation
    const badOpeningChoices = data.openingChoices.map((c) =>
      c.id === 'take_family_album'
        ? {
            ...c,
            on_select: {
              gain: ['item_family_album'],
              ending: 'ending_inventory_be',
            },
          }
        : c,
    );
    const badData: GameData = {
      ...data,
      openingChoices: badOpeningChoices,
      openingChoicesById: new Map(badOpeningChoices.map((c) => [c.id, c])),
    };
    const badGame = createGame(badData);
    const badBefore = JSON.stringify(badGame.serialize());
    const conflictRes = badGame.chooseOpening('take_family_album');
    expect(conflictRes.ok).toBe(false);
    expect(conflictRes.reason_code).toBe('data_conflict');
    expect(conflictRes.lines).toEqual([]);
    expect(JSON.stringify(badGame.serialize())).toBe(badBefore);
  });

  it('formal path 1: take_family_album walks D1 morning -> afternoon -> evening -> night -> D2 morning', () => {
    const game = createGame(data);
    const openRes = game.chooseOpening('take_family_album');
    expect(openRes.ok).toBe(true);

    const departureBeat = data.beatsById.get('d1_morning_departure')!;
    // Album path does not satisfy d1_morning_phone, only settles d1_morning_departure
    expect(openRes.lines).toEqual([departureBeat.text!]);

    let snap = game.getSnapshot();
    expect(snap.flow.mode).toBe('run');
    expect(snap.run.day).toBe(1);
    expect(snap.run.phase).toBe('morning');
    expect(snap.run.opening_choice_id).toBe('take_family_album');
    expect(snap.run.hand).toEqual(['protagonist', 'item_family_album']);
    expect(snap.run.flags).toEqual({});
    expect(snap.run.beats_entered).toEqual({ d1_morning_departure: true });
    expect(snap.meta.day_locations_visited).toEqual({ busstop: true });
    expect(game.getPhaseView().narration_only).toBe(true);
    expect(game.getPhaseView().lines).toEqual([departureBeat.text!]);

    // D1 morning -> D1 afternoon (auto_enter: d1_pm_mountain_road)
    const toAfternoon = game.advancePhase();
    expect(toAfternoon.ok).toBe(true);
    expect(toAfternoon.phase_advanced).toBe(true);
    snap = game.getSnapshot();
    expect(snap.run.day).toBe(1);
    expect(snap.run.phase).toBe('afternoon');
    expect(snap.run.beats_entered).toEqual({
      d1_morning_departure: true,
      d1_pm_mountain_road: true,
    });
    expect(snap.meta.day_locations_visited).toEqual({ busstop: true });
    const pmBeat = data.beatsById.get('d1_pm_mountain_road')!;
    expect(game.getPhaseView().lines).toEqual([pmBeat.text!]);

    // D1 afternoon -> D1 evening
    const toEvening = game.advancePhase();
    expect(toEvening.ok).toBe(true);
    expect(game.getSnapshot().run.phase).toBe('evening');
    const evRes = game.playEvening();
    expect(evRes.ok).toBe(true);
    expect(evRes.lines.length).toBeGreaterThanOrEqual(3); // d1_arrival text + on_enter text + d1_ambient_couple text
    snap = game.getSnapshot();
    // d1_arrival on_enter gains protagonist, which must remain unique at index 0
    expect(snap.run.hand).toEqual(['protagonist', 'item_family_album']);
    expect(snap.run.beats_entered).toEqual({
      d1_morning_departure: true,
      d1_pm_mountain_road: true,
      d1_arrival: true,
      d1_ambient_couple: true,
    });
    expect(snap.meta.day_locations_visited).toEqual({
      busstop: true,
      sanquan: true,
    });

    // D1 evening -> D1 night
    const toNight = game.advancePhase();
    expect(toNight.ok).toBe(true);
    expect(game.getSnapshot().run.phase).toBe('night');
    const nfRes = game.playNightFixed();
    expect(nfRes.ok).toBe(true);
    const nCorridorBeat = data.beatsById.get('n_corridor_ch1')!;
    expect(nfRes.lines).toEqual([nCorridorBeat.text!]);
    snap = game.getSnapshot();
    expect(snap.run.night_location_chosen).toBe('n_corridor');
    expect(snap.meta.night_locations_seen).toEqual({ n_corridor: true });
    expect(snap.meta.night_once_beats_seen).toEqual({ n_corridor_ch1: true });
    expect(snap.run.hand).toEqual(['protagonist', 'item_family_album']);

    // D1 night -> D2 morning
    const toD2Morning = game.advancePhase();
    expect(toD2Morning.ok).toBe(true);
    expect(toD2Morning.phase_advanced).toBe(true);
    snap = game.getSnapshot();
    expect(snap.run.day).toBe(2);
    expect(snap.run.phase).toBe('morning');
    expect(snap.run.night_location_chosen).toBe('');
    expect(game.getPhaseView().narration_only).toBe(false);
    expect(game.getPhaseView().lines).toEqual([]);
  });

  it('formal path 2: return_missed_call settles d1_morning_phone + d1_morning_departure auto_enter once and walks D1 -> D2 morning', () => {
    const game = createGame(data);
    const openRes = game.chooseOpening('return_missed_call');
    expect(openRes.ok).toBe(true);

    const phoneBeat = data.beatsById.get('d1_morning_phone')!;
    const departureBeat = data.beatsById.get('d1_morning_departure')!;
    const expectedMorningLines = [phoneBeat.text!, departureBeat.text!];
    expect(openRes.lines).toEqual(expectedMorningLines);
    expect(game.getPhaseView().lines).toEqual(expectedMorningLines);

    let snap = game.getSnapshot();
    expect(snap.flow.mode).toBe('run');
    expect(snap.run.day).toBe(1);
    expect(snap.run.phase).toBe('morning');
    expect(snap.run.opening_choice_id).toBe('return_missed_call');
    expect(snap.run.flags).toEqual({ outside_job_waiting: true });
    expect(snap.run.hand).toEqual(['protagonist']);
    expect(snap.run.beats_entered).toEqual({
      d1_morning_phone: true,
      d1_morning_departure: true,
    });
    expect(snap.meta.day_locations_visited).toEqual({ busstop: true });

    // Walk D1 morning -> D1 afternoon -> D1 evening -> D1 night -> D2 morning
    expect(game.advancePhase().ok).toBe(true);
    expect(game.getSnapshot().run.phase).toBe('afternoon');
    expect(game.getSnapshot().run.beats_entered).toEqual({
      d1_morning_phone: true,
      d1_morning_departure: true,
      d1_pm_mountain_road: true,
    });

    expect(game.advancePhase().ok).toBe(true);
    expect(game.playEvening().ok).toBe(true);
    expect(game.getSnapshot().run.hand).toEqual(['protagonist']);

    expect(game.advancePhase().ok).toBe(true);
    expect(game.playNightFixed().ok).toBe(true);
    expect(game.getSnapshot().run.night_location_chosen).toBe('n_corridor');

    expect(game.advancePhase().ok).toBe(true);
    snap = game.getSnapshot();
    expect(snap.run.day).toBe(2);
    expect(snap.run.phase).toBe('morning');
    expect(snap.run.hand).toEqual(['protagonist']);
  });

  it('chooseOpening() restores meta.loop_persistent_item_ids in data.cards order after protagonist and freezes run.knowledge_at_start', () => {
    // Mark two non-protagonist slot-taking cards as loop_persistent in fixture to verify data.cards catalog order
    const targetIds = new Set(
      data.cards
        .filter(
          (c) =>
            c.type !== 'protagonist' &&
            c.type !== 'madness' &&
            c.slotless !== true,
        )
        .slice(0, 2)
        .map((c) => c.id),
    );
    expect(targetIds.size).toBe(2);
    const customCards = data.cards.map((c) =>
      targetIds.has(c.id) ? { ...c, loop_persistent: true } : c,
    );
    const fixtureData: GameData = {
      ...data,
      cards: customCards,
      cardsById: new Map(customCards.map((c) => [c.id, c])),
    };

    const expectedOrder = customCards
      .filter((c) => targetIds.has(c.id))
      .map((c) => c.id);

    const init = createGame(fixtureData).serialize();
    // Insert in reverse order to verify restoration follows data.cards catalog order
    for (let i = expectedOrder.length - 1; i >= 0; i -= 1) {
      init.meta.loop_persistent_item_ids[expectedOrder[i]] = true;
    }
    init.meta.knowledge['k_i_returned'] = true;

    const game = createGame(fixtureData, init);
    const res = game.chooseOpening('return_missed_call');
    expect(res.ok).toBe(true);

    const snap = game.getSnapshot();
    expect(snap.run.hand).toEqual(['protagonist', ...expectedOrder]);
    expect(snap.run.knowledge_at_start).toEqual({ k_i_returned: true });
  });
});
