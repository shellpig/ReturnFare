import { beforeAll, describe, expect, it } from 'vitest';
import { createGame } from '../src/core/state';
import { loadGameDataNode } from '../src/data/load-node';
import type { GameData } from '../src/data/types';

describe('W3-B phase narration view idempotence, transient text lifecycle, and default ordering', () => {
  let data: GameData;

  beforeAll(async () => {
    data = await loadGameDataNode();
  });

  it('D1 evening and night getPhaseView() retains d1_arrival on_enter text and n_corridor_ch1 text across multiple reads and repeated playEvening()/playNightFixed() calls without re-applying on_enter or wiping text, and never serializes lines', () => {
    const game = createGame(data);
    expect(game.chooseOpening('return_missed_call').ok).toBe(true);

    // D1 morning transient lines (d1_morning_phone + d1_morning_departure) do not enter serialize()
    expect(game.getPhaseView().lines.length).toBe(2);
    const morningSerialized = game.serialize() as unknown as Record<
      string,
      unknown
    >;
    expect(morningSerialized.lines).toBeUndefined();
    expect(
      (morningSerialized.run as Record<string, unknown>).lines,
    ).toBeUndefined();
    expect(JSON.stringify(morningSerialized)).not.toContain(
      game.getPhaseView().lines[0],
    );

    // Advance to D1 afternoon -> previous D1 morning lines cleared, D1 afternoon auto_enter lines present
    expect(game.advancePhase().ok).toBe(true);
    const pmBeat = data.beatsById.get('d1_pm_mountain_road')!;
    expect(game.getPhaseView().lines).toEqual([pmBeat.text!]);

    // Advance to D1 evening -> afternoon lines cleared before playEvening()
    expect(game.advancePhase().ok).toBe(true);
    expect(game.getPhaseView().lines).toEqual([]);

    const arrivalBeat = data.beatsById.get('d1_arrival')!;
    const coupleBeat = data.beatsById.get('d1_ambient_couple')!;
    const expectedEveningLines = [
      arrivalBeat.text!,
      arrivalBeat.on_enter!.text!,
      coupleBeat.text!,
    ];

    const ev1 = game.playEvening();
    expect(ev1.ok).toBe(true);
    expect(ev1.lines).toEqual(expectedEveningLines);

    // Multiple getPhaseView() reads return the exact same narration lines (including d1_arrival on_enter text)
    expect(game.getPhaseView().lines).toEqual(expectedEveningLines);
    expect(game.getPhaseView().lines).toEqual(expectedEveningLines);

    // Calling playEvening() a second time in the same phase must NOT re-apply on_enter,
    // must NOT duplicate lines in getPhaseView(), and must NOT drop d1_arrival on_enter text from getPhaseView()
    const beforeEv2Snap = JSON.stringify(game.serialize());
    const ev2 = game.playEvening();
    expect(ev2.ok).toBe(true);
    expect(JSON.stringify(game.serialize())).toBe(beforeEv2Snap);
    expect(game.getPhaseView().lines).toEqual(expectedEveningLines);
    expect(game.getPhaseView().lines).toContain(arrivalBeat.on_enter!.text!);

    // Advance to D1 night -> evening lines cleared before playNightFixed()
    expect(game.advancePhase().ok).toBe(true);
    expect(game.getPhaseView().lines).toEqual([]);

    const corridorBeat = data.beatsById.get('n_corridor_ch1')!;
    const expectedNightLines = [corridorBeat.text!];

    const nf1 = game.playNightFixed();
    expect(nf1.ok).toBe(true);
    expect(nf1.lines).toEqual(expectedNightLines);

    // Multiple getPhaseView() reads retain n_corridor_ch1 text
    expect(game.getPhaseView().lines).toEqual(expectedNightLines);
    expect(game.getPhaseView().lines).toEqual(expectedNightLines);

    // Calling playNightFixed() a second time in the same phase must NOT wipe getPhaseView().lines
    const beforeNf2Snap = JSON.stringify(game.serialize());
    const nf2 = game.playNightFixed();
    expect(nf2.ok).toBe(true);
    expect(nf2.lines).toEqual([]); // meta_once beat already seen on direct return
    expect(JSON.stringify(game.serialize())).toBe(beforeNf2Snap);
    // Crucial contract check: getPhaseView().lines still retains the first call's n_corridor_ch1 text!
    expect(game.getPhaseView().lines).toEqual(expectedNightLines);

    // Advance to D2 morning -> night lines cleared
    expect(game.advancePhase().ok).toBe(true);
    expect(game.getPhaseView().lines).toEqual([]);
  });

  it('isolated fixture: proves on_enter effect runs strictly once even if state is mutated before a second playBeat/playEvening call', () => {
    const customBeats = data.beats.map((b) =>
      b.id === 'd1_arrival'
        ? {
            ...b,
            on_enter: {
              text: b.on_enter?.text,
              gain: ['protagonist'],
              flag: { evening_arrival_once_probe: true },
            },
          }
        : b,
    );
    const fixtureData: GameData = {
      ...data,
      beats: customBeats,
      beatsById: new Map(customBeats.map((b) => [b.id, b])),
    };

    const game = createGame(fixtureData);
    expect(game.chooseOpening('take_family_album').ok).toBe(true);
    expect(game.advancePhase().ok).toBe(true); // D1 afternoon
    expect(game.advancePhase().ok).toBe(true); // D1 evening

    expect(game.playEvening().ok).toBe(true);
    expect(game.getSnapshot().run.flags.evening_arrival_once_probe).toBe(true);

    // Re-create game from snapshot with flag cleared to false while beats_entered.d1_arrival remains true
    const tampered = game.serialize();
    tampered.run.flags.evening_arrival_once_probe = false;
    const tamperedGame = createGame(fixtureData, tampered);
    expect(tamperedGame.playEvening().ok).toBe(true);
    // Because beats_entered.d1_arrival is true, on_enter was NOT re-executed
    expect(
      tamperedGame.getSnapshot().run.flags.evening_arrival_once_probe,
    ).toBe(false);
  });

  it('isolated fixture: unresolved choice group default_if_unresolved text precedes new phase narration after advancePhase()', () => {
    const customBeats = [
      ...data.beats,
      {
        id: 'test_d1_morning_default_choice',
        location: 'busstop',
        when: { day: 1, phase: 'morning' as const },
        fixed: true,
        text: '上午固定事件',
        slots: [
          {
            id: 'opt_a',
            label: '選項 A',
            accepts: [],
            choice_group: 'test_group',
            on_place: { text: '選了 A' },
          },
          {
            id: 'opt_default',
            label: '逾期預設選項',
            accepts: [],
            choice_group: 'test_group',
            default_if_unresolved: true,
            on_place: {
              text: '【逾期預設結算文字】',
              flag: { default_settled: true },
            },
          },
        ],
      },
    ];
    const fixtureData: GameData = {
      ...data,
      beats: customBeats,
      beatsById: new Map(customBeats.map((b) => [b.id, b])),
    };

    const game = createGame(fixtureData);
    expect(game.chooseOpening('return_missed_call').ok).toBe(true);
    // In D1 morning, phone narration is present
    expect(game.getPhaseView().lines.length).toBe(2);

    // Advance from D1 morning -> D1 afternoon without resolving test_group
    const adv = game.advancePhase();
    expect(adv.ok).toBe(true);
    expect(adv.phase_advanced).toBe(true);
    expect(adv.lines).toEqual(['【逾期預設結算文字】']);

    const snap = game.getSnapshot();
    expect(snap.run.day).toBe(1);
    expect(snap.run.phase).toBe('afternoon');
    expect(snap.run.choices['test_d1_morning_default_choice::test_group']).toBe(
      'opt_default',
    );
    expect(
      snap.run.slots_placed['test_d1_morning_default_choice::opt_default'],
    ).toBe(true);
    expect(snap.run.flags.default_settled).toBe(true);

    // Previous D1 morning lines were cleared; default text precedes D1 afternoon auto_enter text
    const pmBeat = fixtureData.beatsById.get('d1_pm_mountain_road')!;
    expect(game.getPhaseView().lines).toEqual([
      '【逾期預設結算文字】',
      pmBeat.text!,
    ]);

    // Advancing again to D1 evening clears the morning-to-afternoon default text
    expect(game.advancePhase().ok).toBe(true);
    expect(game.getPhaseView().lines).toEqual([]);
  });
});
