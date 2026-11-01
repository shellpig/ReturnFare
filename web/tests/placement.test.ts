import { describe, expect, it } from 'vitest';
import { loadGameDataNode } from '../src/data/load-node';
import { createGame } from '../src/core/state';
import { createInitialSnapshot } from '../src/core/run-initialization';

describe('Card Placement and Slot Execution (W5-B)', async () => {
  const data = await loadGameDataNode();

  it('Production E2E: walks naturally from normal opening to D3 afternoon, performs free compare then protagonist action, and verifies refusal atomicity', () => {
    const game = createGame(data);

    // 1. Choose opening: take_family_album
    const openRes = game.chooseOpening('take_family_album');
    expect(openRes.ok).toBe(true);

    // D1 morning -> afternoon -> evening -> night -> D2 morning
    expect(game.advancePhase().ok).toBe(true); // -> D1 afternoon
    expect(game.advancePhase().ok).toBe(true); // -> D1 evening
    const ev1 = game.playEvening();
    expect(ev1.ok).toBe(true);
    expect(game.advancePhase().ok).toBe(true); // -> D1 night
    const nf1 = game.playNightFixed();
    expect(nf1.ok).toBe(true);
    expect(game.advancePhase().ok).toBe(true); // -> D2 morning

    // D2 morning: play d2_morning_intro at sanquan
    expect(game.getPhaseView().day).toBe(2);
    expect(game.getPhaseView().phase).toBe('morning');
    const d2mIntro = game.playBeat('d2_morning_intro');
    expect(d2mIntro.ok).toBe(true);

    // Advance D2 morning -> D2 afternoon
    const advD2pm = game.advancePhase();
    expect(advD2pm.ok).toBe(true);
    expect(game.getPhaseView().day).toBe(2);
    expect(game.getPhaseView().phase).toBe('afternoon');

    // D2 afternoon: play d2_pm_work
    const d2pmWorkBeat = game.playBeat('d2_pm_work');
    expect(d2pmWorkBeat.ok).toBe(true);

    // Place protagonist into d2_pm_work.work
    expect(game.getSnapshot().run.action_spent).toBe(false);
    const placeWorkRes = game.tryPlace('protagonist', 'd2_pm_work', 'work');
    expect(placeWorkRes.ok).toBe(true);
    expect(placeWorkRes.lines.length).toBeGreaterThan(0);
    expect(game.getSnapshot().run.action_spent).toBe(true);
    expect(game.getSnapshot().run.hand).toContain('protagonist'); // Protagonist card kept
    expect(game.getSnapshot().run.hand).toContain('info_husband_version');
    expect(game.getSnapshot().run.hand).toContain('info_wife_version');
    expect(
      game.getSnapshot().run.slots_placed['d2_pm_work::work'],
    ).toBe(true);

    // Advance D2 afternoon -> D2 evening -> D2 night -> D3 morning -> D3 afternoon
    expect(game.advancePhase().ok).toBe(true); // -> D2 evening
    expect(game.playEvening().ok).toBe(true);
    expect(game.advancePhase().ok).toBe(true); // -> D2 night
    expect(game.playNightFixed().ok).toBe(true);
    expect(game.advancePhase().ok).toBe(true); // -> D3 morning

    // D3 morning: play d3_morning_ahong
    expect(game.playBeat('d3_morning_ahong').ok).toBe(true);
    expect(game.advancePhase().ok).toBe(true); // -> D3 afternoon

    expect(game.getPhaseView().day).toBe(3);
    expect(game.getPhaseView().phase).toBe('afternoon');
    expect(game.getSnapshot().run.action_spent).toBe(false);

    // Play d3_pm_sanquan
    expect(game.playBeat('d3_pm_sanquan').ok).toBe(true);

    // Free comparison: place info_husband_version into show_version
    const freeRes = game.tryPlace(
      'info_husband_version',
      'd3_pm_sanquan',
      'show_version',
    );
    expect(freeRes.ok).toBe(true);
    expect(freeRes.lines.length).toBeGreaterThan(0);
    expect(game.getSnapshot().run.flags.couple_softened).toBe(true);
    expect(
      game.getSnapshot().run.slots_placed['d3_pm_sanquan::show_version'],
    ).toBe(true);
    // CRITICAL: Free comparison costs NO action!
    expect(game.getSnapshot().run.action_spent).toBe(false);
    expect(game.getSnapshot().run.hand).toContain('info_husband_version');

    // Now place protagonist into help_ahong
    const ahongRes = game.tryPlace('protagonist', 'd3_pm_sanquan', 'help_ahong');
    expect(ahongRes.ok).toBe(true);
    expect(ahongRes.lines.length).toBeGreaterThan(0);
    expect(game.getSnapshot().run.flags.ahong_last_normal_contact).toBe(true);
    expect(game.getSnapshot().run.hand).toContain('info_ahong_private');
    expect(
      game.getSnapshot().run.slots_placed['d3_pm_sanquan::help_ahong'],
    ).toBe(true);
    expect(game.getSnapshot().run.hand).toContain('protagonist'); // Protagonist card kept
    expect(game.getSnapshot().run.action_spent).toBe(true); // Action consumed!

    // Second protagonist placement in the same phase (handle_couple): refused with action_spent
    const beforeSecondProtagonist = JSON.stringify(game.serialize());
    const secondProtagonistRes = game.tryPlace(
      'protagonist',
      'd3_pm_sanquan',
      'handle_couple',
    );
    expect(secondProtagonistRes.ok).toBe(false);
    expect(secondProtagonistRes.reason_code).toBe('action_spent');
    expect(secondProtagonistRes.lines).toEqual([]);
    expect(JSON.stringify(game.serialize())).toBe(beforeSecondProtagonist);

    // Repeat placement into already resolved slot: refused with resolved
    const repeatRes = game.tryPlace(
      'info_husband_version',
      'd3_pm_sanquan',
      'show_version',
    );
    expect(repeatRes.ok).toBe(false);
    expect(repeatRes.reason_code).toBe('resolved');
    expect(JSON.stringify(game.serialize())).toBe(beforeSecondProtagonist);

    // Placement with unheld card: refused with not_held
    const unheldRes = game.tryPlace(
      'k_unheld_card_xyz',
      'd3_pm_sanquan',
      'show_version',
    );
    expect(unheldRes.ok).toBe(false);
    expect(unheldRes.reason_code).toBe('not_held');
    expect(JSON.stringify(game.serialize())).toBe(beforeSecondProtagonist);
  });

  it('records attention_npc strictly once on protagonist action placement', () => {
    // Construct isolated fixture beat with an attention_npc slot
    const customBeats = data.beats.map((b) =>
      b.id === 'd2_pm_work'
        ? {
            ...b,
            slots: (b.slots ?? []).map((s) =>
              s.id === 'work'
                ? {
                    ...s,
                    attention_npc: 'ajie',
                    on_place: {
                      ...s.on_place,
                      switch_progress: { s6: 1 },
                      relation: { npc: 'ajie', delta: 1 },
                    },
                  }
                : s,
            ),
          }
        : b,
    );
    const fixtureData = {
      ...data,
      beats: customBeats,
      beatsById: new Map(customBeats.map((b) => [b.id, b])),
    };

    const game = createGame(fixtureData);
    game.chooseOpening('take_family_album');
    game.advancePhase(); // D1 pm
    game.advancePhase(); // D1 eve
    game.playEvening();
    game.advancePhase(); // D1 night
    game.playNightFixed();
    game.advancePhase(); // D2 morning
    game.playBeat('d2_morning_intro');
    game.advancePhase(); // D2 afternoon

    expect(game.getSnapshot().run.npc_action_counts['ajie']).toBeUndefined();
    const res = game.tryPlace('protagonist', 'd2_pm_work', 'work');
    expect(res.ok).toBe(true);
    expect(game.getSnapshot().run.npc_action_counts['ajie']).toBe(1);
    expect(game.getSnapshot().run.switch_progress.s6).toBe(1);
    expect(game.getSnapshot().run.relations.ajie).toBe(1);

    // Second placement refused; counter does not increment
    const beforeRepeat = JSON.stringify(game.serialize());
    const repeat = game.tryPlace('protagonist', 'd2_pm_work', 'work');
    expect(repeat.ok).toBe(false);
    expect(repeat.reason_code).toBe('resolved');
    expect(game.getSnapshot().run.npc_action_counts['ajie']).toBe(1);
    expect(game.getSnapshot().run.switch_progress.s6).toBe(1);
    expect(game.getSnapshot().run.relations.ajie).toBe(1);
    expect(JSON.stringify(game.serialize())).toBe(beforeRepeat);
  });

  it('second protagonist refuses with action_spent after a successful first placement', () => {
    const snapshot = createInitialSnapshot();
    snapshot.flow.mode = 'run';
    snapshot.run.day = 3;
    snapshot.run.phase = 'afternoon';
    snapshot.run.hand = ['protagonist'];
    const game = createGame(data, snapshot);
    expect(game.tryPlace('protagonist', 'd3_pm_sanquan', 'help_ahong').ok).toBe(true);
    const beforeSecond = JSON.stringify(game.serialize());
    const second = game.tryPlace('protagonist', 'd3_pm_sanquan', 'handle_couple');
    expect(second.ok).toBe(false);
    expect(second.reason_code).toBe('action_spent');
    expect(second.lines).toEqual([]);
    expect(JSON.stringify(game.serialize())).toBe(beforeSecond);
  });

  it('tryPlace routing order strictly adheres to Godot contract and isolates special routes', () => {
    // 1. not_run when opening
    const openingGame = createGame(data);
    const notRunRes = openingGame.tryPlace(
      'protagonist',
      'd2_pm_work',
      'work',
    );
    expect(notRunRes.ok).toBe(false);
    expect(notRunRes.reason_code).toBe('not_run');

    // 2. encounter_active
    const encInit = createInitialSnapshot();
    encInit.flow.mode = 'run';
    encInit.run.active_encounter = { stage: 'intro' };
    const encGame = createGame(data, encInit);
    const encRes = encGame.tryPlace('protagonist', 'd2_pm_work', 'work');
    expect(encRes.ok).toBe(false);
    expect(encRes.reason_code).toBe('encounter_active');

    // 3. empty cardId -> not_held
    const runInit = createInitialSnapshot();
    runInit.flow.mode = 'run';
    const runGame = createGame(data, runInit);
    const emptyCardRes = runGame.tryPlace('', 'd2_pm_work', 'work');
    expect(emptyCardRes.ok).toBe(false);
    expect(emptyCardRes.reason_code).toBe('not_held');

    // 4. madness instance routed to indulge (W6-B)
    runInit.run.hand.push('madness#1');
    const madnessGame = createGame(data, runInit);
    const madnessRes = madnessGame.tryPlace(
      'madness#1',
      'unknown_beat_123',
      'unknown_slot',
    );
    expect(madnessRes.ok).toBe(false);
    expect(madnessRes.reason_code).toBe('unknown_beat');

    // 5. unknown beat
    const unknownBeatRes = runGame.tryPlace(
      'protagonist',
      'unknown_beat_xyz',
      'slot_xyz',
    );
    expect(unknownBeatRes.ok).toBe(false);
    expect(unknownBeatRes.reason_code).toBe('unknown_beat');

    // 6. unknown slot
    const unknownSlotRes = runGame.tryPlace(
      'protagonist',
      'd2_pm_work',
      'unknown_slot_xyz',
    );
    expect(unknownSlotRes.ok).toBe(false);
    expect(unknownSlotRes.reason_code).toBe('unknown_slot');
  });

  it('previewSlot returns placeable cards or exact reasons without mutating game state', () => {
    const init = createInitialSnapshot();
    init.flow.mode = 'run';
    init.run.day = 2;
    init.run.phase = 'afternoon';
    init.run.hand = ['protagonist'];
    const game = createGame(data, init);

    const serializedBefore = JSON.stringify(game.serialize());

    // 1. Preview OPEN slot with protagonist
    const preview1 = game.previewSlot('d2_pm_work', 'work');
    expect(preview1.cards).toEqual(['protagonist']);
    expect(preview1.reason).toBe('');
    expect(JSON.stringify(game.serialize())).toBe(serializedBefore);

    // 2. Preview placeableCards
    const cards = game.placeableCards('d2_pm_work', 'work');
    expect(cards).toEqual(['protagonist']);

    // 3. Preview locked slot
    const lockedInit = createInitialSnapshot();
    lockedInit.flow.mode = 'run';
    lockedInit.run.day = 19;
    lockedInit.run.phase = 'afternoon';
    lockedInit.run.hand = ['protagonist'];
    const lockedGame = createGame(data, lockedInit);
    const lockedPreview = lockedGame.previewSlot(
      'd19_pm_upstream',
      'look',
    );
    expect(lockedPreview.cards).toEqual([]);
    expect(lockedPreview.reason).toContain('這條山路的線索');
    const beforeLocked = JSON.stringify(lockedGame.serialize());
    const lockedPlacement = lockedGame.tryPlace('protagonist', 'd19_pm_upstream', 'look');
    expect(lockedPlacement.ok).toBe(false);
    expect(lockedPlacement.reason_code).toBe('locked');
    expect(lockedPlacement.lines).toEqual([]);
    expect(JSON.stringify(lockedGame.serialize())).toBe(beforeLocked);
  });

  it('hasAnyLegalAction and hasUnseenContent queries match time and state without mutating state', () => {
    const game = createGame(data);
    game.chooseOpening('take_family_album');

    // D1 morning: narration only -> no legal actions, unseen is false (isNarrationOnly)
    expect(game.hasAnyLegalAction()).toBe(false);
    expect(game.hasUnseenContent()).toBe(false);

    // Advance to D2 morning
    game.advancePhase(); // D1 pm
    game.advancePhase(); // D1 eve
    game.playEvening();
    game.advancePhase(); // D1 night
    game.playNightFixed();
    game.advancePhase(); // D2 morning

    // D2 morning: sanquan is open and has d2_morning_intro which is not entered yet
    expect(game.hasUnseenContent()).toBe(true);
    // D2 morning has only slots with accepts: [] -> no legal action
    expect(game.hasAnyLegalAction()).toBe(false);

    // After entering d2_morning_intro
    game.playBeat('d2_morning_intro');
    expect(game.hasUnseenContent()).toBe(false);
  });
});
