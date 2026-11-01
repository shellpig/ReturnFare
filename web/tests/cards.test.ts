import { beforeAll, describe, expect, it } from 'vitest';
import {
  cardView,
  gainCard,
  handSlotsUsed,
  handView,
  hasCard,
  hasKnowledge,
  knowledgeView,
  loseCard,
} from '../src/core/cards';
import { createGame } from '../src/core/state';
import type { GameSnapshot } from '../src/core/state-types';
import { loadGameDataNode } from '../src/data/load-node';
import type { GameData } from '../src/data/types';

describe('W5-A cards, hand, knowledge, and Game queries', () => {
  let data: GameData;

  beforeAll(async () => {
    data = await loadGameDataNode();
  });

  it('ordinary duplicate gain stays one (idempotent)', () => {
    const game = createGame(data);
    const snap = game.serialize();
    // Use actual formal card 'item_family_album'
    const res1 = gainCard(snap, 'item_family_album', data);
    expect(res1.ok).toBe(true);
    expect(snap.run.hand).toContain('item_family_album');
    expect(snap.run.hand.filter((id) => id === 'item_family_album').length).toBe(1);
    expect(handSlotsUsed(snap)).toBe(1);

    const res2 = gainCard(snap, 'item_family_album', data);
    expect(res2.ok).toBe(true);
    expect(snap.run.hand.filter((id) => id === 'item_family_album').length).toBe(1);
    expect(handSlotsUsed(snap)).toBe(1);
  });

  it('knowledge card goes only to meta.knowledge, not in hand, and excludes from slots', () => {
    const game = createGame(data);
    const snap = game.serialize();
    // Use actual formal knowledge card 'k_i_returned'
    const res = gainCard(snap, 'k_i_returned', data);
    expect(res.ok).toBe(true);
    expect(hasKnowledge(snap, 'k_i_returned')).toBe(true);
    expect(hasCard(snap, 'k_i_returned')).toBe(true);
    expect(snap.run.hand).not.toContain('k_i_returned');
    expect(snap.meta.knowledge['k_i_returned']).toBe(true);
    expect(handSlotsUsed(snap)).toBe(0);

    // Duplicate knowledge gain is also idempotent
    const res2 = gainCard(snap, 'k_i_returned', data);
    expect(res2.ok).toBe(true);
    expect(handSlotsUsed(snap)).toBe(0);
  });

  it('protagonist cannot be lost (normal or permanent) and serialize remains byte-for-byte unchanged', () => {
    const game = createGame(data);
    const snap = game.serialize();
    gainCard(snap, 'protagonist', data);
    const beforeStr = JSON.stringify(snap);

    // Normal loss
    const normalLoss = loseCard(snap, 'protagonist', data, false);
    expect(normalLoss.ok).toBe(false);
    expect(normalLoss.reason_code).toBe('data_conflict');
    expect(JSON.stringify(snap)).toBe(beforeStr);

    // Permanent loss
    const permLoss = loseCard(snap, 'protagonist', data, true);
    expect(permLoss.ok).toBe(false);
    expect(permLoss.reason_code).toBe('data_conflict');
    expect(JSON.stringify(snap)).toBe(beforeStr);
  });

  it('cardView fields exactly match actual formal cards and countdown is undefined for non-madness cards', () => {
    const game = createGame(data);
    const snap = game.serialize();
    const formalAlbum = data.cardsById.get('item_family_album')!;
    const view = cardView(snap, 'item_family_album', data);

    expect(view.instanceId).toBe('item_family_album');
    expect(view.baseId).toBe('item_family_album');
    expect(view.type).toBe(formalAlbum.type);
    expect(view.name).toBe(formalAlbum.name);
    expect(view.text).toBe(formalAlbum.text);
    expect(view.countdown).toBeUndefined();
  });

  it('two madness instances in trusted snapshot have distinct IDs and their own countdowns', () => {
    const game = createGame(data);
    const snap: GameSnapshot = {
      ...game.serialize(),
      run: {
        ...game.serialize().run,
        hand: ['protagonist', 'madness#1', 'madness#2'],
        madness_clock: {
          'madness#1': 3,
          'madness#2': 1,
        },
        _madness_counter: 2,
      },
    };

    const v1 = cardView(snap, 'madness#1', data);
    const v2 = cardView(snap, 'madness#2', data);
    const formalMadness = data.cardsById.get('madness')!;

    expect(v1.instanceId).toBe('madness#1');
    expect(v1.baseId).toBe('madness');
    expect(v1.name).toBe(formalMadness.name);
    expect(v1.text).toBe(formalMadness.text);
    expect(v1.countdown).toBe(3);

    expect(v2.instanceId).toBe('madness#2');
    expect(v2.baseId).toBe('madness');
    expect(v2.name).toBe(formalMadness.name);
    expect(v2.text).toBe(formalMadness.text);
    expect(v2.countdown).toBe(1);

    expect(v1.instanceId).not.toBe(v2.instanceId);

    const hv = handView(snap, data);
    expect(hv.map((c) => c.instanceId)).toEqual([
      'protagonist',
      'madness#1',
      'madness#2',
    ]);
  });

  it('ordinary gain of madness creates a new countdown instance each time (W6-A shared primitive; cap is checked by the caller)', () => {
    const game = createGame(data);
    const snap = game.serialize();
    const res = gainCard(snap, 'madness', data);

    expect(res.ok).toBe(true);
    expect(snap.run.hand).toEqual(['madness#1']);
    expect(snap.run.madness_clock).toEqual({
      'madness#1': data.tuning.madness_countdown_days,
    });
    expect(snap.run._madness_counter).toBe(1);

    expect(gainCard(snap, 'madness', data).ok).toBe(true);
    expect(snap.run.hand).toEqual(['madness#1', 'madness#2']);
    expect(Object.keys(snap.run.madness_clock)).toEqual(['madness#1', 'madness#2']);
  });

  it('loop_persistent normal vs permanent removal, normal->permanent without hand copy, and repeated permanent loss is idempotent', () => {
    // Construct representative fixture data marking item_family_album as loop_persistent: true
    const customCards = data.cards.map((c) =>
      c.id === 'item_family_album' ? { ...c, loop_persistent: true } : c,
    );
    const fixtureData: GameData = {
      ...data,
      cards: customCards,
      cardsById: new Map(customCards.map((c) => [c.id, c])),
    };

    const game = createGame(fixtureData);
    const snap = game.serialize();

    // 1. Gain item_family_album -> written to meta.loop_persistent_item_ids and run.hand
    const gainRes = gainCard(snap, 'item_family_album', fixtureData);
    expect(gainRes.ok).toBe(true);
    expect(snap.meta.loop_persistent_item_ids['item_family_album']).toBe(true);
    expect(snap.run.hand).toContain('item_family_album');

    // 2. Normal loss (permanent = false) removes from hand but PRESERVES meta set
    const normalLossRes = loseCard(
      snap,
      'item_family_album',
      fixtureData,
      false,
    );
    expect(normalLossRes.ok).toBe(true);
    expect(snap.run.hand).not.toContain('item_family_album');
    expect(snap.meta.loop_persistent_item_ids['item_family_album']).toBe(true);

    // 3. Normal loss THEN permanent loss (card no longer in hand) removes from meta set
    const permLossRes = loseCard(
      snap,
      'item_family_album',
      fixtureData,
      true,
    );
    expect(permLossRes.ok).toBe(true);
    expect(
      snap.meta.loop_persistent_item_ids['item_family_album'],
    ).toBeUndefined();

    // 4. Repeated permanent loss is idempotent
    const repeatPermRes = loseCard(
      snap,
      'item_family_album',
      fixtureData,
      true,
    );
    expect(repeatPermRes.ok).toBe(true);
    expect(
      snap.meta.loop_persistent_item_ids['item_family_album'],
    ).toBeUndefined();
  });

  it('missing or unknown card loss returns data_conflict with zero side effects', () => {
    const game = createGame(data);
    const snap = game.serialize();
    const beforeStr = JSON.stringify(snap);

    // Unknown card ID
    const unknownRes = loseCard(snap, 'non_existent_card_id', data, false);
    expect(unknownRes.ok).toBe(false);
    expect(unknownRes.reason_code).toBe('data_conflict');
    expect(JSON.stringify(snap)).toBe(beforeStr);

    // Valid card not held in hand or knowledge
    const notHeldRes = loseCard(snap, 'item_family_album', data, false);
    expect(notHeldRes.ok).toBe(false);
    expect(notHeldRes.reason_code).toBe('data_conflict');
    expect(JSON.stringify(snap)).toBe(beforeStr);
  });

  it('knowledge order preserves meta.knowledge acquisition order', () => {
    const game = createGame(data);
    const snap = game.serialize();

    gainCard(snap, 'k_night_sanquan', data);
    gainCard(snap, 'k_night_clinic', data);
    gainCard(snap, 'k_i_returned', data);

    const kv = knowledgeView(snap, data);
    expect(kv.map((k) => k.instanceId)).toEqual([
      'k_night_sanquan',
      'k_night_clinic',
      'k_i_returned',
    ]);
  });

  it('view queries cause zero state mutation (serialize before/after identical)', () => {
    const game = createGame(data);
    game.chooseOpening('take_family_album');
    const beforeSerialized = JSON.stringify(game.serialize());

    // Call all view queries on Game instance
    game.hasCard('protagonist');
    game.hasKnowledge('k_i_returned');
    game.handSlotsUsed();
    game.handCapacity();
    game.cardView('protagonist');
    game.handView();
    game.knowledgeView();

    expect(JSON.stringify(game.serialize())).toBe(beforeSerialized);
  });

  it('highest-level normal chooseOpening path proves protagonist and album each once via production gain path', () => {
    const game = createGame(data);
    const res = game.chooseOpening('take_family_album');
    expect(res.ok).toBe(true);

    const hand = game.handView();
    expect(hand.map((c) => c.instanceId)).toEqual([
      'protagonist',
      'item_family_album',
    ]);
    expect(hand.length).toBe(2);
    expect(game.handSlotsUsed()).toBe(2);
    expect(game.hasCard('protagonist')).toBe(true);
    expect(game.hasCard('item_family_album')).toBe(true);
    expect(game.handCapacity()).toBe(data.tuning.hand_size);
  });

  it('loseCard handles formal knowledge removal and exact madness instances in trusted snapshot', () => {
    const game = createGame(data);
    // Trusted snapshot with formal knowledge and two madness instances
    const snap: GameSnapshot = {
      ...game.serialize(),
      run: {
        ...game.serialize().run,
        hand: ['protagonist', 'madness#1', 'madness#2'],
        madness_clock: {
          'madness#1': 3,
          'madness#2': 1,
        },
        madness_cards_cleared: 0,
        _madness_counter: 2,
      },
      meta: {
        ...game.serialize().meta,
        knowledge: {
          k_i_returned: true,
        },
      },
    };

    // 1. Lose knowledge removes exactly that entry without changing hand
    const loseKRes = loseCard(snap, 'k_i_returned', data, false);
    expect(loseKRes.ok).toBe(true);
    expect(hasKnowledge(snap, 'k_i_returned')).toBe(false);
    expect(snap.meta.knowledge['k_i_returned']).toBeUndefined();
    expect(snap.run.hand).toEqual(['protagonist', 'madness#1', 'madness#2']);
    expect(snap.run.madness_cards_cleared).toBe(0);

    // 2. Lose madness#1 removes only that instance/clock, keeps madness#2 and its countdown, madness_cards_cleared increments once
    const loseM1Res = loseCard(snap, 'madness#1', data, false);
    expect(loseM1Res.ok).toBe(true);
    expect(snap.run.hand).toEqual(['protagonist', 'madness#2']);
    expect(snap.run.madness_clock['madness#1']).toBeUndefined();
    expect(snap.run.madness_clock['madness#2']).toBe(1);
    expect(snap.run.madness_cards_cleared).toBe(1);

    // 3. Missing repeat loses rejects without extra increments or other state mutation
    const beforeRepeat = JSON.stringify(snap);

    // Repeat losing k_i_returned (already lost)
    const repeatKRes = loseCard(snap, 'k_i_returned', data, false);
    expect(repeatKRes.ok).toBe(false);
    expect(repeatKRes.reason_code).toBe('data_conflict');
    expect(JSON.stringify(snap)).toBe(beforeRepeat);

    // Repeat losing madness#1 (already lost)
    const repeatM1Res = loseCard(snap, 'madness#1', data, false);
    expect(repeatM1Res.ok).toBe(false);
    expect(repeatM1Res.reason_code).toBe('data_conflict');
    expect(JSON.stringify(snap)).toBe(beforeRepeat);
    expect(snap.run.madness_cards_cleared).toBe(1);
  });
});
