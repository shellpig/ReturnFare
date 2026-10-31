import { beforeAll, describe, expect, it } from 'vitest';
import {
  TriState,
  availableLocations,
  buildPanel,
  mapView,
  remainingActionsToday,
} from '../src/core/panel';
import { createGame } from '../src/core/state';
import type { GameSnapshot } from '../src/core/state-types';
import { createRunForTrace } from '../src/core/trace-entry';
import { loadGameDataNode } from '../src/data/load-node';
import type { GameData } from '../src/data/types';

function makeDayPhaseSnapshot(
  data: GameData,
  day: number,
  phase: 'morning' | 'afternoon' | 'evening' | 'night',
): GameSnapshot {
  const snap = createRunForTrace(data).serialize();
  snap.run.day = day;
  snap.run.phase = phase;
  snap.run.action_spent = false;
  snap.run.actions_spent_ahead = 0;
  return snap;
}

describe('W4-B panel.ts tri-state evaluation, mapView(), and visit recording', () => {
  let data: GameData;

  beforeAll(async () => {
    data = await loadGameDataNode();
  });

  it('evaluates D3 afternoon three active locations (sanquan, oldstreet, temple) beat/slot order, HIDDEN/LOCKED/OPEN/RESOLVED states, and acceptTypes without leaking specific card IDs', () => {
    const snap = makeDayPhaseSnapshot(data, 3, 'afternoon');
    const game = createGame(data, snap);

    // 1. D3 afternoon availableLocations & mapView
    const avail = game.availableLocations();
    expect(avail).toEqual(availableLocations(game.getSnapshot(), data));
    expect(avail).toContain('sanquan');
    expect(avail).toContain('oldstreet');
    expect(avail).toContain('temple');
    expect(avail).toContain('clinic');

    // Only sanquan, oldstreet, temple have visible beats on D3 afternoon (indulgence exits are HIDDEN without madness card)
    const mv = game.mapView();
    const enabledIds = mv.filter((loc) => loc.enabled).map((loc) => loc.id);
    expect(enabledIds).toEqual(['sanquan', 'oldstreet', 'temple']);

    // 2. sanquan on D3 afternoon: d3_pm_sanquan is OPEN, exit_sanquan is HIDDEN (omitted)
    const sanquanPanel = game.buildPanel('sanquan');
    expect(sanquanPanel.location).toEqual({
      id: 'sanquan',
      name: '山泉閣',
      desc: data.locationsById.get('sanquan')!.desc!,
    });
    expect(sanquanPanel.beats.map((b) => b.id)).toEqual(['d3_pm_sanquan']);
    const sanquanBeat = sanquanPanel.beats[0];
    expect(sanquanBeat.tri).toBe(TriState.OPEN);
    expect(sanquanBeat.reason).toBe('');
    expect(sanquanBeat.slots.map((s) => s.id)).toEqual([
      'help_ahong',
      'handle_couple',
      'ledger',
      'show_version',
      'soak',
    ]);

    // Check OPEN vs LOCKED slots on d3_pm_sanquan
    const slotById = new Map(sanquanBeat.slots.map((s) => [s.id, s]));
    expect(slotById.get('help_ahong')?.tri).toBe(TriState.OPEN);
    expect(slotById.get('handle_couple')?.tri).toBe(TriState.OPEN);
    expect(slotById.get('ledger')?.tri).toBe(TriState.OPEN);
    expect(slotById.get('soak')?.tri).toBe(TriState.OPEN);

    // show_version requires info_husband_version or info_wife_version -> LOCKED by default
    const showVersionSlot = slotById.get('show_version')!;
    expect(showVersionSlot.tri).toBe(TriState.LOCKED);
    expect(showVersionSlot.reason).toBe('（你不知道他們兩個私下說了什麼。）');
    // accepts has 2 specific card IDs ['info_husband_version', 'info_wife_version'], but acceptTypes deduplicates to card type name ['情報卡']
    expect(showVersionSlot.accepts).toEqual([
      'info_husband_version',
      'info_wife_version',
    ]);
    expect(showVersionSlot.acceptTypes).toEqual(['情報卡']);

    // When holding info_husband_version and ledger is placed, show_version becomes OPEN and ledger becomes RESOLVED
    const snapWithInfo = game.serialize();
    snapWithInfo.run.hand.push('info_husband_version');
    snapWithInfo.run.slots_placed['d3_pm_sanquan::ledger'] = true;
    const panelAfter = buildPanel('sanquan', snapWithInfo, data);
    const afterSlots = new Map(
      panelAfter.beats[0].slots.map((s) => [s.id, s]),
    );
    expect(afterSlots.get('show_version')?.tri).toBe(TriState.OPEN);
    expect(afterSlots.get('show_version')?.reason).toBe('');
    expect(afterSlots.get('ledger')?.tri).toBe(TriState.RESOLVED);

    // 3. oldstreet on D3 afternoon: d3_pm_oldstreet
    const oldstreetPanel = game.buildPanel('oldstreet');
    expect(oldstreetPanel.beats.map((b) => b.id)).toEqual(['d3_pm_oldstreet']);
    expect(oldstreetPanel.beats[0].tri).toBe(TriState.OPEN);
    expect(oldstreetPanel.beats[0].slots.map((s) => s.id)).toEqual(['wander']);
    expect(oldstreetPanel.beats[0].slots[0].tri).toBe(TriState.OPEN);
    expect(oldstreetPanel.beats[0].slots[0].acceptTypes).toEqual(['主角卡']);

    // 4. temple on D3 afternoon: d3_pm_temple with occupant npc_jinbo -> 金伯
    const templePanel = game.buildPanel('temple');
    expect(templePanel.beats.map((b) => b.id)).toEqual(['d3_pm_temple']);
    expect(templePanel.beats[0].tri).toBe(TriState.OPEN);
    expect(templePanel.beats[0].slots.map((s) => s.id)).toEqual(['jinbo']);
    expect(templePanel.beats[0].slots[0].occupant).toEqual({
      id: 'npc_jinbo',
      name: '金伯',
    });
    expect(templePanel.beats[0].slots[0].acceptTypes).toEqual(['主角卡']);
  });

  it('handles slot-level HIDDEN (d17_19_prescription) and choice_group RESOLVED collapsing unchosen options (d2_pm_oldstreet)', () => {
    // 1. d17_19_prescription on D17 afternoon at sanquan: ask_ajie, ask_azhu, ask_acai have condition: { has_card: ... }
    const d17Snap = makeDayPhaseSnapshot(data, 17, 'afternoon');
    const p1 = buildPanel('sanquan', d17Snap, data);
    const prescBeat1 = p1.beats.find((b) => b.id === 'd17_19_prescription')!;
    expect(prescBeat1).toBeDefined();
    // Without NPC cards, only find_self is visible; the 3 delegation slots are HIDDEN (omitted)
    expect(prescBeat1.slots.map((s) => s.id)).toEqual(['find_self']);

    // Holding npc_ajie reveals ask_ajie with delegation metadata and acceptTypes: ['人物卡']
    d17Snap.run.hand.push('npc_ajie');
    const p2 = buildPanel('sanquan', d17Snap, data);
    const prescBeat2 = p2.beats.find((b) => b.id === 'd17_19_prescription')!;
    expect(prescBeat2.slots.map((s) => s.id)).toEqual(['find_self', 'ask_ajie']);
    const ajieSlot = prescBeat2.slots[1];
    expect(ajieSlot.acceptTypes).toEqual(['人物卡']);
    expect(ajieSlot.delegation?.resultTiming).toBe('immediate');

    // 2. Choice group RESOLVED on d17_19_prescription (choice_group: prescription_route)
    expect(prescBeat2.slots.every((s) => s.isChoice)).toBe(true);
    expect(prescBeat2.slots.every((s) => s.choiceGroup === 'prescription_route')).toBe(true);
    d17Snap.run.choices['d17_19_prescription::prescription_route'] = 'ask_ajie';
    const p3 = buildPanel('sanquan', d17Snap, data);
    const prescBeat3 = p3.beats.find((b) => b.id === 'd17_19_prescription')!;
    expect(prescBeat3.slots.map((s) => s.id)).toEqual(['ask_ajie']);
    expect(prescBeat3.slots[0].tri).toBe(TriState.RESOLVED);
    expect(prescBeat3.slots[0].isChoice).toBe(true);
  });

  it('propagates beat LOCKED state and reject_reason to non-RESOLVED slots on D19 afternoon upstream, and greedy buildPanel() scan never writes visit records', () => {
    const d19Snap = makeDayPhaseSnapshot(data, 19, 'afternoon');
    const game = createGame(data, d19Snap);
    const beforeSerialized = JSON.stringify(game.serialize());

    // Greedy scan across all available locations via buildPanel() and mapView()
    for (const locId of game.availableLocations()) {
      game.buildPanel(locId);
    }
    const mv = game.mapView();
    const upstreamMapEntry = mv.find((m) => m.id === 'upstream')!;
    // D19 afternoon upstream has a LOCKED beat (visible in panel.beats), so it is enabled on the map
    expect(upstreamMapEntry.enabled).toBe(true);

    const upstreamPanel = game.buildPanel('upstream');
    expect(upstreamPanel.beats.map((b) => b.id)).toEqual(['d19_pm_upstream']);
    const beat = upstreamPanel.beats[0];
    expect(beat.tri).toBe(TriState.LOCKED);
    expect(beat.reason).toBe('（你還不知道這條山路的線索。）');
    expect(beat.slots).toHaveLength(1);
    expect(beat.slots[0].id).toBe('look');
    expect(beat.slots[0].tri).toBe(TriState.LOCKED);
    expect(beat.slots[0].reason).toBe('（你還不知道這條山路的線索。）');
    expect(beat.slots[0].occupant).toEqual({
      id: 'npc_aqin',
      name: '阿欽伯',
    });

    // Pure queries (availableLocations, buildPanel, mapView) must leave serialize() byte-for-byte identical
    expect(game.getSnapshot().meta.day_locations_visited.upstream).toBeUndefined();
    expect(JSON.stringify(game.serialize())).toBe(beforeSerialized);

    // When k_forty_something is acquired, beat and slot become OPEN
    const unlockedSnap = game.serialize();
    unlockedSnap.meta.knowledge['k_forty_something'] = true;
    const unlockedPanel = buildPanel('upstream', unlockedSnap, data);
    expect(unlockedPanel.beats[0].tri).toBe(TriState.OPEN);
    expect(unlockedPanel.beats[0].reason).toBe('');
    expect(unlockedPanel.beats[0].slots[0].tri).toBe(TriState.OPEN);
    expect(unlockedPanel.beats[0].slots[0].reason).toBe('');
  });

  it('tracks visited vs unvisited empty locations in mapView() and records daytime visits via both playBeat() and markDayLocationVisited() while ignoring invalid/night locations', () => {
    const d3Snap = makeDayPhaseSnapshot(data, 3, 'afternoon');
    const game = createGame(data, d3Snap);

    // Initially clinic and upstream are unvisited and have no beats on D3 afternoon -> enabled: false
    const mvBefore = game.mapView();
    expect(mvBefore.find((m) => m.id === 'clinic')?.enabled).toBe(false);

    // Repeated mapView() and buildPanel() calls do not mutate serialize()
    const beforeJson = JSON.stringify(game.serialize());
    game.mapView();
    game.buildPanel('sanquan');
    game.buildPanel('clinic');
    expect(JSON.stringify(game.serialize())).toBe(beforeJson);

    // 1. Invalid / empty / night location calls to markDayLocationVisited do not mutate serialize() or notify
    let notifyCount = 0;
    const unsub = game.subscribe(() => {
      notifyCount += 1;
    });
    game.markDayLocationVisited('');
    game.markDayLocationVisited('non_existent_location');
    game.markDayLocationVisited('n_corridor');
    expect(notifyCount).toBe(0);
    expect(JSON.stringify(game.serialize())).toBe(beforeJson);

    // 2. Explicit markDayLocationVisited('clinic') records visit and enables empty location on mapView()
    game.markDayLocationVisited('clinic');
    expect(notifyCount).toBe(1);
    expect(game.getSnapshot().meta.day_locations_visited.clinic).toBe(true);
    expect(game.mapView().find((m) => m.id === 'clinic')?.enabled).toBe(true);

    // 3. playBeat() on a daytime beat (d3_pm_temple) also records meta.day_locations_visited.temple = true
    expect(game.getSnapshot().meta.day_locations_visited.temple).toBeUndefined();
    const playRes = game.playBeat('d3_pm_temple');
    expect(playRes.ok).toBe(true);
    expect(game.getSnapshot().meta.day_locations_visited.temple).toBe(true);

    // 4. playBeat() on a night-layer beat (n_corridor_ch1) does NOT record n_corridor in day_locations_visited
    const nightBeatRes = game.playBeat('n_corridor_ch1');
    expect(nightBeatRes.ok).toBe(true);
    expect(
      game.getSnapshot().meta.day_locations_visited.n_corridor,
    ).toBeUndefined();

    unsub();
  });

  it('evaluates indulgence_exits.json exit_sanquan.x_soak across morning (2 actions vs 1 action left) and afternoon', () => {
    // 1. Morning with madness card and 2 remaining actions -> OPEN
    const morningSnap = makeDayPhaseSnapshot(data, 5, 'morning');
    morningSnap.run.hand.push('madness');
    morningSnap.run.madness_clock['madness#1'] = 3;
    expect(remainingActionsToday(morningSnap)).toBe(2);

    const morningPanel = buildPanel('sanquan', morningSnap, data);
    const exitMorning = morningPanel.beats.find(
      (b) => b.id === 'exit_sanquan',
    )!;
    expect(exitMorning).toBeDefined();
    expect(exitMorning.tri).toBe(TriState.OPEN);
    const soakMorningOpen = exitMorning.slots.find((s) => s.id === 'x_soak')!;
    expect(soakMorningOpen.tri).toBe(TriState.OPEN);
    expect(soakMorningOpen.reason).toBe('');

    // 2a. Morning with action_spent === true (1 action left < soak_phase_cost 2) -> LOCKED '（格數不足）'
    const morningSpentSnap = structuredClone(morningSnap);
    morningSpentSnap.run.action_spent = true;
    expect(remainingActionsToday(morningSpentSnap)).toBe(1);
    const panelSpent = buildPanel('sanquan', morningSpentSnap, data);
    const soakSpent = panelSpent.beats
      .find((b) => b.id === 'exit_sanquan')!
      .slots.find((s) => s.id === 'x_soak')!;
    expect(soakSpent.tri).toBe(TriState.LOCKED);
    expect(soakSpent.reason).toBe('（格數不足）');

    // 2b. Morning with actions_spent_ahead > 0 (1 action left < soak_phase_cost 2) -> LOCKED '（格數不足）'
    const morningAheadSnap = structuredClone(morningSnap);
    morningAheadSnap.run.actions_spent_ahead = 1;
    expect(remainingActionsToday(morningAheadSnap)).toBe(1);
    const panelAhead = buildPanel('sanquan', morningAheadSnap, data);
    const soakAhead = panelAhead.beats
      .find((b) => b.id === 'exit_sanquan')!
      .slots.find((s) => s.id === 'x_soak')!;
    expect(soakAhead.tri).toBe(TriState.LOCKED);
    expect(soakAhead.reason).toBe('（格數不足）');

    // 3. Afternoon with madness card -> LOCKED '（只能在上午發動）'
    const pmSnap = makeDayPhaseSnapshot(data, 5, 'afternoon');
    pmSnap.run.hand.push('madness');
    pmSnap.run.madness_clock['madness#1'] = 3;
    expect(remainingActionsToday(pmSnap)).toBe(1);
    const pmPanel = buildPanel('sanquan', pmSnap, data);
    const soakPm = pmPanel.beats
      .find((b) => b.id === 'exit_sanquan')!
      .slots.find((s) => s.id === 'x_soak')!;
    expect(soakPm.tri).toBe(TriState.LOCKED);
    expect(soakPm.reason).toBe('（只能在上午發動）');
  });
});
