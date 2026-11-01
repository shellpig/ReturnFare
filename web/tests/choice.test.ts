import { describe, expect, it } from 'vitest';
import { loadGameDataNode } from '../src/data/load-node';
import { createGame } from '../src/core/state';
import { createInitialSnapshot } from '../src/core/run-initialization';
import { TriState } from '../src/core/panel';

describe('choice_group Mutual Exclusion and Slot Resolution (W5-C)', async () => {
  const data = await loadGameDataNode();

  it('formal d22_pm_sandbags: direct choose vs with equip_polaroid produce byte-identical serialize, panel-close leaves state unchanged, and repeat choose is rejected without duplicate effects', () => {
    // 1. Snapshot setup for D22 afternoon minimal required state:
    // Beat condition requires any of [acai_obs_knee, acai_obs_hands, acai_obs_scar, polaroid_acai].
    // Held state includes protagonist and equip_polaroid (accepted by obs_walk).
    function makeD22Snapshot() {
      const snap = createInitialSnapshot();
      snap.flow.mode = 'run';
      snap.run.day = 22;
      snap.run.phase = 'afternoon';
      snap.run.flags.acai_obs_knee = true;
      snap.run.hand = ['protagonist', 'equip_polaroid'];
      return snap;
    }

    // Panel-close with no choice: opening location panel and closing/navigating away leaves serialize unchanged.
    const panelGame = createGame(data, makeD22Snapshot());
    const beforeOpen = JSON.stringify(panelGame.serialize());
    const sanquanPanel = panelGame.buildPanel('sanquan');
    expect(sanquanPanel.beats.length).toBeGreaterThan(0);
    expect(JSON.stringify(panelGame.serialize())).toBe(beforeOpen);

    // (a) Direct choose obs_walk without card
    const gameA = createGame(data, makeD22Snapshot());
    const resA = gameA.choose('d22_pm_sandbags', 'acai_read', 'obs_walk');
    expect(resA.ok).toBe(true);
    expect(resA.reason_code).toBe('');
    expect(resA.lines.length).toBeGreaterThan(0);

    // Verify choice state in gameA
    const snapA = gameA.getSnapshot();
    expect(snapA.run.choices['d22_pm_sandbags::acai_read']).toBe('obs_walk');
    expect(snapA.run.slots_placed['d22_pm_sandbags::obs_walk']).toBe(true);
    expect(snapA.run.hand).toContain('info_acai_walk');
    expect(snapA.run.action_spent).toBe(false);

    // (b) Place with equip_polaroid into obs_walk (via tryPlace -> choose)
    const gameB = createGame(data, makeD22Snapshot());
    const resB = gameB.tryPlace('equip_polaroid', 'd22_pm_sandbags', 'obs_walk');
    expect(resB.ok).toBe(true);
    expect(resB.reason_code).toBe('');
    expect(resB.lines).toEqual(resA.lines);

    // Compare full JSON.stringify(serialize()) equal:
    // Both direct choose and placement with equip_polaroid yield identical state because:
    // 1) equip_polaroid is equipment (neither consumed nor discarded).
    // 2) obs_walk does not specify choice_requires_card: true, so neither route consumes an action.
    // 3) Both routes execute the exact same on_place effects (gain info_acai_walk) and bookkeeping.
    expect(JSON.stringify(gameA.serialize())).toBe(JSON.stringify(gameB.serialize()));

    // PanelView reflection: chosen slot stays visible as RESOLVED, other acai_read options disappear
    const panelAfter = gameA.buildPanel('sanquan');
    const sandbagsBeat = panelAfter.beats.find((b) => b.id === 'd22_pm_sandbags');
    expect(sandbagsBeat).toBeDefined();
    const acaiSlots = sandbagsBeat!.slots.filter((s) => s.choiceGroup === 'acai_read');
    expect(acaiSlots.length).toBe(1);
    expect(acaiSlots[0].id).toBe('obs_walk');
    expect(acaiSlots[0].tri).toBe(TriState.RESOLVED);

    // Repeat choose -> rejected with resolved, serialize byte-identical, no duplicate effect
    const serializedAfterA = JSON.stringify(gameA.serialize());
    const repeatRes = gameA.choose('d22_pm_sandbags', 'acai_read', 'obs_walk');
    expect(repeatRes.ok).toBe(false);
    expect(repeatRes.reason_code).toBe('resolved');
    expect(repeatRes.lines).toEqual([]);
    expect(JSON.stringify(gameA.serialize())).toBe(serializedAfterA);

    // Repeat choose on another slot in the same group also rejected with resolved
    const otherSlotRes = gameA.choose('d22_pm_sandbags', 'acai_read', 'obs_hands');
    expect(otherSlotRes.ok).toBe(false);
    expect(otherSlotRes.reason_code).toBe('resolved');
    expect(otherSlotRes.lines).toEqual([]);
    expect(JSON.stringify(gameA.serialize())).toBe(serializedAfterA);

    // Cumulative counter verification: choice recorded once, card gained once
    expect(Object.keys(gameA.getSnapshot().run.choices).length).toBe(1);
    expect(
      gameA.getSnapshot().run.hand.filter((c) => c === 'info_acai_walk').length,
    ).toBe(1);
  });

  it('formal d43_pm_zhou leaving: empty card rejects with card_required without mutation; protagonist consumes action and sets attention_npc if defined', () => {
    function makeD43Snapshot() {
      const snap = createInitialSnapshot();
      snap.flow.mode = 'run';
      snap.run.day = 43;
      snap.run.phase = 'afternoon';
      snap.run.flags.outside_job_waiting = true;
      snap.run.hand = ['protagonist'];
      return snap;
    }

    // 1. Empty card -> card_required with zero change
    const game = createGame(data, makeD43Snapshot());
    const beforeEmpty = JSON.stringify(game.serialize());
    const emptyRes = game.choose('d43_pm_zhou', 'leaving', 'say_yes_boss');
    expect(emptyRes.ok).toBe(false);
    expect(emptyRes.reason_code).toBe('card_required');
    expect(emptyRes.lines).toEqual([]);
    expect(JSON.stringify(game.serialize())).toBe(beforeEmpty);

    // Also empty string passed explicitly
    const emptyStrRes = game.choose('d43_pm_zhou', 'leaving', 'say_yes_boss', '');
    expect(emptyStrRes.ok).toBe(false);
    expect(emptyStrRes.reason_code).toBe('card_required');
    expect(JSON.stringify(game.serialize())).toBe(beforeEmpty);

    // 2. Protagonist in action phase -> action_spent becomes true
    expect(game.getSnapshot().run.action_spent).toBe(false);
    const placeRes = game.tryPlace('protagonist', 'd43_pm_zhou', 'say_yes_boss');
    expect(placeRes.ok).toBe(true);
    expect(placeRes.lines.length).toBeGreaterThan(0);

    const snap = game.getSnapshot();
    expect(snap.run.action_spent).toBe(true);
    expect(snap.run.flags.accepted_outside_job).toBe(true);
    expect(snap.run.choices['d43_pm_zhou::leaving']).toBe('say_yes_boss');
    expect(snap.run.slots_placed['d43_pm_zhou::say_yes_boss']).toBe(true);

    // 3. Attention NPC and ordinary choice check:
    // In formal data (data/beats/*.json), every slot with choice_group that accepts protagonist
    // has choice_requires_card: true (e.g. d43_pm_zhou, d17_19_prescription.find_self, d23_d26_repairs).
    // Formal data offers no ordinary choice (choice_requires_card: false) that accepts protagonist.
    // We explicitly verify that when an ordinary choice does not have choice_requires_card: true,
    // placing protagonist does NOT consume an action.
    const customBeats = data.beats.map((b) =>
      b.id === 'd22_pm_sandbags'
        ? {
            ...b,
            slots: (b.slots ?? []).map((s) =>
              s.id === 'obs_walk'
                ? {
                    ...s,
                    accepts: ['protagonist'],
                    attention_npc: 'acai',
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

    const ordinarySnap = createInitialSnapshot();
    ordinarySnap.flow.mode = 'run';
    ordinarySnap.run.day = 22;
    ordinarySnap.run.phase = 'afternoon';
    ordinarySnap.run.flags.acai_obs_knee = true;
    ordinarySnap.run.hand = ['protagonist'];

    const ordinaryGame = createGame(fixtureData, ordinarySnap);
    expect(ordinaryGame.getSnapshot().run.action_spent).toBe(false);
    const ordinaryRes = ordinaryGame.choose('d22_pm_sandbags', 'acai_read', 'obs_walk', 'protagonist');
    expect(ordinaryRes.ok).toBe(true);
    // Crucially: ordinary choice with protagonist does NOT consume action!
    expect(ordinaryGame.getSnapshot().run.action_spent).toBe(false);
    expect(ordinaryGame.getSnapshot().run.npc_action_counts.acai).toBeUndefined();
  });

  it('representative refusals: wrong group -> unknown_slot, unheld card -> not_held, delegation -> not_implemented, not_run, encounter_active', () => {
    function makeD22Snapshot() {
      const snap = createInitialSnapshot();
      snap.flow.mode = 'run';
      snap.run.day = 22;
      snap.run.phase = 'afternoon';
      snap.run.flags.acai_obs_knee = true;
      snap.run.hand = ['protagonist', 'equip_polaroid'];
      return snap;
    }

    const game = createGame(data, makeD22Snapshot());
    const baseState = JSON.stringify(game.serialize());

    // 1. Wrong group -> unknown_slot
    const wrongGroupRes = game.choose('d22_pm_sandbags', 'nonexistent_group', 'obs_walk');
    expect(wrongGroupRes.ok).toBe(false);
    expect(wrongGroupRes.reason_code).toBe('unknown_slot');
    expect(wrongGroupRes.lines).toEqual([]);
    expect(JSON.stringify(game.serialize())).toBe(baseState);

    // 2. Unheld card -> not_held
    const unheldRes = game.choose('d22_pm_sandbags', 'acai_read', 'obs_walk', 'card_not_held_xyz');
    expect(unheldRes.ok).toBe(false);
    expect(unheldRes.reason_code).toBe('not_held');
    expect(unheldRes.lines).toEqual([]);
    expect(JSON.stringify(game.serialize())).toBe(baseState);

    // 3. Delegation slot -> routes to delegate (W6-C)
    const delegationSnap = createInitialSnapshot();
    delegationSnap.flow.mode = 'run';
    delegationSnap.run.day = 17;
    delegationSnap.run.phase = 'afternoon';
    delegationSnap.run.hand = ['npc_ajie'];
    const delegationGame = createGame(data, delegationSnap);
    const delRes = delegationGame.choose('d17_19_prescription', 'prescription_route', 'ask_ajie', 'npc_ajie');
    expect(delRes.ok).toBe(true);
    expect(delegationGame.hasCard('doc_prescription')).toBe(true);

    // 4. Mode not run -> not_run
    const openingGame = createGame(data);
    const beforeOpening = JSON.stringify(openingGame.serialize());
    const notRunRes = openingGame.choose('d22_pm_sandbags', 'acai_read', 'obs_walk');
    expect(notRunRes.ok).toBe(false);
    expect(notRunRes.reason_code).toBe('not_run');
    expect(JSON.stringify(openingGame.serialize())).toBe(beforeOpening);

    // 5. Active encounter -> encounter_active
    const encounterSnap = makeD22Snapshot();
    encounterSnap.run.active_encounter = { stage: 'intro', beat_id: 'd8_night_encounter' };
    const encounterGame = createGame(data, encounterSnap);
    const beforeEncounter = JSON.stringify(encounterGame.serialize());
    const encRes = encounterGame.choose('d22_pm_sandbags', 'acai_read', 'obs_walk');
    expect(encRes.ok).toBe(false);
    expect(encRes.reason_code).toBe('encounter_active');
    expect(JSON.stringify(encounterGame.serialize())).toBe(beforeEncounter);
  });
});
