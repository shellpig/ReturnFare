/**
 * ReturnFare Web — 遭遇系統核心規則與生命週期測試（W6-D）。
 *
 * 覆蓋：
 * 1. 正式 D8 night 生命週期（advancePhase -> playNightFixed 啟動 intro、ack、候選與正解、出口）
 * 2. 正式 D45 afternoon 生命週期（advancePhase 自動啟動、滿手 14 張不容量失敗、after_finish advance_phase 恰好推進一次至 evening）
 * 3. 錯答 fallback（扣丟棄卡、保留壓力、推進回合）與 card_not_submittable 原子拒絕
 * 4. 主動丟棄（扣手牌、不改壓力與回合、allow_discard 守衛、不可丟棄卡拒絕）
 * 5. 逃離遭遇（escape_cost 扣卡、cannot_escape、wrong_escape_count、duplicate_payment、not_discardable 拒絕）
 * 6. 超載開場立即 failure 且 entered_round: false、無首回合 cost
 * 7. 容量上限耗盡（blocked_slots > 0 時可用格 <= 0 失敗）與無棋可走（no legal moves 失敗）
 * 8. D8 repeat_each_run 與 charge_first_visit（未 seen 收費、已 seen 不重複收費）
 * 9. 重複 base card 拒絕（hand 與 knowledge 皆過濾）、未持有／發狂卡拒絕、原子性 serialize 逐字不變
 * 10. 序列化 roundtrip
 */

import { describe, expect, it } from 'vitest';
import { loadGameDataNode } from '../src/data/load-node';
import type { Phase } from '../src/data/types';
import type { GameSnapshot } from '../src/core/state-types';
import { createGame } from '../src/core/state';
import { createRunForTrace } from '../src/core/trace-entry';

describe('W6-D encounter system (core rules & lifecycle)', async () => {
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

  function expectRejectsWithoutChange(
    game: ReturnType<typeof createGame>,
    act: () => { ok: boolean; reason_code: string; reason_text: string },
    expectedCode: string,
  ) {
    const before = JSON.stringify(game.serialize());
    const res = act();
    expect(res.ok).toBe(false);
    expect(res.reason_code).toBe(expectedCode);
    expect(JSON.stringify(game.serialize())).toBe(before);
    return res;
  }

  it('1. 正式 D8 night 生命週期：advancePhase -> playNightFixed 啟動、首次收費、intro -> round -> 正解勝利', () => {
    // 從 D8 evening 開始
    const eveSnap = injectAt(8, 'evening', (s) => {
      s.run.hand = ['protagonist', 'item_gradphoto', 'routine_debt'];
      s.meta.knowledge = {
        k_not_today: true,
      };
    });
    const game = createGame(data, eveSnap);

    // 1.1 Advance to night
    const advToNight = game.advancePhase();
    expect(advToNight.ok).toBe(true);
    expect(game.getSnapshot().run.phase).toBe('night');

    // 尚未 playNightFixed 前無遭遇
    expect(game.encounterView()).toEqual({});

    // 1.2 playNightFixed 觸發 n_manydoors_ch1
    // 首次訪問 n_manydoors（madness_cost: 1），收取 1 張發狂卡
    const nightFixedRes = game.playNightFixed();
    expect(nightFixedRes.ok).toBe(true);
    expect(game.getSnapshot().meta.night_locations_seen.n_manydoors).toBe(true);
    expect(
      game.getSnapshot().run.hand.some((c) => c.startsWith('madness')),
    ).toBe(true);

    // 遭遇進入 intro stage
    const introView = game.encounterView();
    expect(introView).toEqual({
      stage: 'intro',
      beat_id: 'n_manydoors_ch1',
      blocked_slots: 0,
      capacity: 14,
      available_slots: 14 - game.getSnapshot().run.hand.length,
    });

    // 遭遇進行中，非遭遇入口拒絕 encounter_active
    expectRejectsWithoutChange(game, () => game.advancePhase(), 'encounter_active');
    expectRejectsWithoutChange(
      game,
      () => game.tryPlace('protagonist', 'd8_pm_observe', 'talk'),
      'encounter_active',
    );
    expectRejectsWithoutChange(game, () => game.enterNightLocation('n_manydoors'), 'encounter_active');

    // 1.3 acknowledgeEncounterIntro 進入第一回合
    const ackRes = game.acknowledgeEncounterIntro();
    expect(ackRes.ok).toBe(true);
    expect(ackRes.entered_round).toBe(true);
    expect(game.getPhaseView().lines).not.toContain(data.beatsById.get('n_manydoors_ch1')!.text);

    const r1View = game.encounterView();
    if (r1View.stage !== 'round') throw new Error('Expected round stage');
    expect(r1View.round_id).toBe('name_since_when');
    expect(r1View.blocked_slots).toBe(1); // per_round_slot_cost = 1
    expect(r1View.can_escape).toBe(true);
    expect(r1View.escape_cost).toBe(1);
    expect(r1View.allow_discard).toBe(true);
    expect(r1View.attempted_card_ids).toEqual([]);

    // 候選包含 hand 與 knowledge，發狂卡標記 madness_blocked
    const madnessCand = r1View.candidates.find((c) => c.base_id === 'madness');
    expect(madnessCand).toBeDefined();
    expect(madnessCand?.submittable).toBe(false);
    expect(madnessCand?.disabled_reason).toBe('madness_blocked');

    const knowCand = r1View.candidates.find((c) => c.card_id === 'k_not_today');
    expect(knowCand).toBeDefined();
    expect(knowCand?.source).toBe('knowledge');
    expect(knowCand?.submittable).toBe(true);

    // 1.4 回應第一回合：提交 k_not_today（正解，釋放壓力並推進至 who_remembers）
    const r1Resp = game.respondToEncounter('k_not_today');
    expect(r1Resp.ok).toBe(true);

    const r2View = game.encounterView();
    if (r2View.stage !== 'round') throw new Error('Expected round stage');
    expect(r2View.round_id).toBe('who_remembers');
    expect(r2View.blocked_slots).toBe(1); // 1 - 1 + 1 = 1
    expect(r2View.attempted_card_ids).toContain('k_not_today');

    // 已嘗試過的 base card 再次提交會被 rejected
    expectRejectsWithoutChange(game, () => game.respondToEncounter('k_not_today'), 'already_attempted');

    // 1.5 第二回合給予正解卡 info_chunama_pause
    // 注入卡片並回應
    const d8MidSnap = game.serialize();
    d8MidSnap.run.hand.push('info_chunama_pause');
    const gameR2 = createGame(data, d8MidSnap);

    const r2Resp = gameR2.respondToEncounter('info_chunama_pause');
    expect(r2Resp.ok).toBe(true);

    const r3View = gameR2.encounterView();
    if (r3View.stage !== 'round') throw new Error('Expected round stage');
    expect(r3View.round_id).toBe('what_remains');
    expect(r3View.blocked_slots).toBe(1);

    // 1.6 第三回合提交 routine_debt（正解，next_round 為 null -> victory 出口）
    const r3Resp = gameR2.respondToEncounter('routine_debt');
    expect(r3Resp.ok).toBe(true);

    // 勝利效果已套用：flag d8_encounter_victory
    expect(gameR2.getSnapshot().run.flags.d8_encounter_victory).toBe(true);
    // 遭遇已結算清空，留在 night（after_finish: "stay"）
    expect(gameR2.encounterView()).toEqual({});
    expect(gameR2.getSnapshot().run.phase).toBe('night');
  });

  it('2. D8 repeat_each_run 與 charge_first_visit：已 seen 時不重複收取發狂卡', () => {
    const d8Snap = injectAt(8, 'night', (s) => {
      s.meta.night_locations_seen.n_manydoors = true; // 已經看過
      s.run.hand = ['protagonist'];
    });
    const game = createGame(data, d8Snap);
    const initialHandCount = game.getSnapshot().run.hand.length;

    const res = game.playNightFixed();
    expect(res.ok).toBe(true);
    // 未收費：手牌張數不變
    expect(game.getSnapshot().run.hand.length).toBe(initialHandCount);
    // 遭遇仍正常啟動（repeat_each_run）
    expect(game.encounterView().stage).toBe('intro');
  });

  it('3. 正式 D45 afternoon 生命週期：advancePhase 自動啟動、滿手 14 張不容量失敗、after_finish advance_phase 自動推進至 evening', () => {
    const d45Morning = injectAt(45, 'morning', (s) => {
      // 14 張手牌（全滿手牌，含主角卡與 13 張不重複丟棄卡）
      s.run.hand = [
        'protagonist',
        'item_gradphoto',
        'routine_debt',
        'item_old_paper',
        'inf_health_disappearance',
        'inf_jinghe_does_it',
        'inf_hotspring_kills',
        'info_zhou_waiting',
        'info_uncle_gap',
        'npc_ajie',
        'npc_awei',
        'equip_polaroid',
        'info_chunama_pause',
        'info_ahong_private',
      ];
      s.run.flags.final_day = true;
    });
    const game = createGame(data, d45Morning);
    expect(game.getSnapshot().run.hand.length).toBe(14);

    // 3.1 推進時段：morning -> afternoon，自動啟動 d45_encounter
    const advRes = game.advancePhase();
    expect(advRes.ok).toBe(true);
    expect(advRes.phase_advanced).toBe(true);
    expect(game.getSnapshot().run.phase).toBe('afternoon');

    const introView = game.encounterView();
    expect(introView.stage).toBe('intro');
    expect(introView.beat_id).toBe('d45_encounter');
    expect(introView.blocked_slots).toBe(0);
    expect(game.getPhaseView().lines).toContain(data.beatsById.get('d45_encounter')!.text);

    // 3.2 acknowledgeEncounterIntro：D45 per_round_slot_cost 為 0
    // 雖然手牌滿 14 張，但 blocked_slots <= 0 且 hand <= 14，不得判定容量失敗！
    const ackRes = game.acknowledgeEncounterIntro();
    expect(ackRes.ok).toBe(true);
    expect(ackRes.entered_round).toBe(true);

    const rView = game.encounterView();
    if (rView.stage !== 'round') throw new Error('Expected round stage');
    expect(rView.round_id).toBe('final_demand');
    expect(rView.blocked_slots).toBe(0);
    expect(rView.can_escape).toBe(false);
    expect(rView.escape_cost).toBeNull();
    expect(rView.allow_discard).toBe(false);

    // 3.3 提交 protagonist（正解，next_round: null -> victory）
    // after_finish 為 "advance_phase"，遭遇結束後由規則層恰好推進一次至 evening！
    const respRes = game.respondToEncounter('protagonist');
    expect(respRes.ok).toBe(true);
    expect(respRes.lines.length).toBeGreaterThan(0);

    // 勝利演出已套用
    expect(respRes.lines).toContain('走廊的風漸漸停了，周圍只剩下濃黑的霧。');
    // 遭遇結束
    expect(game.encounterView()).toEqual({});
    // 時段已自動推進至 evening
    expect(game.getSnapshot().run.day).toBe(45);
    expect(game.getSnapshot().run.phase).toBe('evening');
    expect(game.hasCard('protagonist')).toBe(true);
  });

  it('4. 錯答 fallback：requires_discardable 時消耗可丟棄卡、保留壓力、推進回合', () => {
    const snap = injectAt(8, 'night', (s) => {
      s.meta.night_locations_seen.n_manydoors = true;
      s.run.hand = ['protagonist', 'item_gradphoto', 'equip_polaroid'];
      s.run.active_encounter = {
        beat_id: 'n_manydoors_ch1',
        stage: 'round',
        round_id: 'name_since_when',
        blocked_slots: 1,
        attempted_card_ids: [],
        visited_round_ids: ['name_since_when'],
      };
    });
    const game = createGame(data, snap);

    // 提交 item_gradphoto（未命中 response，但 item_gradphoto 可丟棄）
    const respRes = game.respondToEncounter('item_gradphoto');
    expect(respRes.ok).toBe(true);

    // fallback 扣除 item_gradphoto
    expect(game.hasCard('item_gradphoto')).toBe(false);

    // 錯答保留壓力：原本 1 格不釋放，進入第二回合再加 1 格，blocked_slots 變為 2
    const rView = game.encounterView();
    if (rView.stage !== 'round') throw new Error('Expected round stage');
    expect(rView.round_id).toBe('who_remembers');
    expect(rView.blocked_slots).toBe(2);
    expect(rView.attempted_card_ids).toContain('item_gradphoto');
  });

  it('5. 錯答 card_not_submittable：requires_discardable 時不可丟棄卡被原子拒絕', () => {
    const snap = injectAt(8, 'night', (s) => {
      s.meta.night_locations_seen.n_manydoors = true;
      s.run.hand = ['protagonist']; // protagonist 為 discardable: false
      s.run.active_encounter = {
        beat_id: 'n_manydoors_ch1',
        stage: 'round',
        round_id: 'name_since_when',
        blocked_slots: 1,
        attempted_card_ids: [],
        visited_round_ids: ['name_since_when'],
      };
    });
    const game = createGame(data, snap);

    // protagonist 未命中 response，且 fallback.requires_discardable === true
    expectRejectsWithoutChange(
      game,
      () => game.respondToEncounter('protagonist'),
      'card_not_submittable',
    );
  });

  it('6. 主動丟棄 discardInEncounter：成功扣卡、不改壓力與回合；守衛與拒絕碼逐字一致', () => {
    const snap = injectAt(8, 'night', (s) => {
      s.meta.night_locations_seen.n_manydoors = true;
      s.run.hand = ['protagonist', 'item_gradphoto', 'equip_polaroid'];
      s.run.active_encounter = {
        beat_id: 'n_manydoors_ch1',
        stage: 'round',
        round_id: 'name_since_when',
        blocked_slots: 1,
        attempted_card_ids: [],
        visited_round_ids: ['name_since_when'],
      };
    });
    const game = createGame(data, snap);

    // 6.1 丟棄 item_gradphoto 成功
    const discardRes = game.discardInEncounter('item_gradphoto');
    expect(discardRes.ok).toBe(true);
    expect(game.hasCard('item_gradphoto')).toBe(false);

    // 壓力和回合不變
    const rView = game.encounterView();
    if (rView.stage !== 'round') throw new Error('Expected round stage');
    expect(rView.round_id).toBe('name_since_when');
    expect(rView.blocked_slots).toBe(1);
    expect(rView.attempted_card_ids).toEqual([]);

    // 6.2 不可丟棄卡拒絕：protagonist
    expectRejectsWithoutChange(
      game,
      () => game.discardInEncounter('protagonist'),
      'not_discardable',
    );

    // 6.3 未知卡與未持有卡拒絕
    expectRejectsWithoutChange(
      game,
      () => game.discardInEncounter('non_existent_card'),
      'unknown_card',
    );
    expectRejectsWithoutChange(
      game,
      () => game.discardInEncounter('item_festival_photo'),
      'not_held',
    );

    // 6.4 allow_discard: false 守衛（在 D45）
    const d45Snap = injectAt(45, 'afternoon', (s) => {
      s.run.hand = ['protagonist', 'item_gradphoto'];
      s.run.active_encounter = {
        beat_id: 'd45_encounter',
        stage: 'round',
        round_id: 'final_demand',
        blocked_slots: 0,
        attempted_card_ids: [],
        visited_round_ids: ['final_demand'],
      };
    });
    const d45Game = createGame(data, d45Snap);
    expectRejectsWithoutChange(
      d45Game,
      () => d45Game.discardInEncounter('item_gradphoto'),
      'discard_disabled',
    );
  });

  it('7. 逃離 escapeEncounter：支付成功套用出口；守衛與拒絕碼精準無誤', () => {
    const snap = injectAt(8, 'night', (s) => {
      s.meta.night_locations_seen.n_manydoors = true;
      s.run.hand = ['protagonist', 'item_gradphoto'];
      s.run.active_encounter = {
        beat_id: 'n_manydoors_ch1',
        stage: 'round',
        round_id: 'name_since_when',
        blocked_slots: 1,
        attempted_card_ids: [],
        visited_round_ids: ['name_since_when'],
      };
    });
    const game = createGame(data, snap);

    // 7.1 張數不符拒絕
    expectRejectsWithoutChange(
      game,
      () => game.escapeEncounter([]),
      'wrong_escape_count',
    );
    expectRejectsWithoutChange(
      game,
      () => game.escapeEncounter(['item_gradphoto', 'item_gradphoto']),
      'wrong_escape_count',
    );

    // 7.2 不可逃離守衛（D45 escape_cost 為 null）
    const d45Snap = injectAt(45, 'afternoon', (s) => {
      s.run.hand = ['protagonist', 'item_gradphoto'];
      s.run.active_encounter = {
        beat_id: 'd45_encounter',
        stage: 'round',
        round_id: 'final_demand',
        blocked_slots: 0,
        attempted_card_ids: [],
        visited_round_ids: ['final_demand'],
      };
    });
    const d45Game = createGame(data, d45Snap);
    expectRejectsWithoutChange(
      d45Game,
      () => d45Game.escapeEncounter(['item_gradphoto']),
      'cannot_escape',
    );

    // 7.3 不可丟棄卡不能作為逃離代價（如主角卡）
    expectRejectsWithoutChange(
      game,
      () => game.escapeEncounter(['protagonist']),
      'not_discardable',
    );

    // 7.4 成功逃離
    const escRes = game.escapeEncounter(['item_gradphoto']);
    expect(escRes.ok).toBe(true);
    expect(game.hasCard('item_gradphoto')).toBe(false);
    expect(game.getSnapshot().run.flags.d8_encounter_escaped).toBe(true);
    expect(game.encounterView()).toEqual({});
  });

  it('8. 超載開場立即 failure：entered_round 為 false、無首回合 cost', () => {
    // 建立 15 張手牌（超過上限 14）
    const snap = injectAt(8, 'night', (s) => {
      s.meta.night_locations_seen.n_manydoors = true;
      s.run.hand = [
        'protagonist',
        'item_gradphoto',
        'routine_debt',
        'item_old_paper',
        'inf_health_disappearance',
        'inf_jinghe_does_it',
        'inf_hotspring_kills',
        'info_zhou_waiting',
        'info_uncle_gap',
        'npc_ajie',
        'npc_awei',
        'equip_polaroid',
        'info_chunama_pause',
        'info_ahong_private',
        'madness', // 第 15 張
      ];
      s.run.active_encounter = {
        beat_id: 'n_manydoors_ch1',
        stage: 'intro',
        round_id: '',
        blocked_slots: 0,
        attempted_card_ids: [],
        visited_round_ids: [],
      };
    });
    const game = createGame(data, snap);

    const ackRes = game.acknowledgeEncounterIntro();
    expect(ackRes.ok).toBe(true);
    expect(ackRes.entered_round).toBe(false);

    // 直接觸發 failure 出口
    expect(game.getSnapshot().run.flags.d8_encounter_failure).toBe(true);
    expect(game.encounterView()).toEqual({});
  });

  it('9. 容量上限耗盡：blocked_slots > 0 且可用格歸零時走 failure 出口', () => {
    // 13 張手牌，若進第一回合 blocked_slots + 1 = 1，可用格為 14 - 13 - 1 = 0 -> 歸零失敗
    const snap = injectAt(8, 'night', (s) => {
      s.meta.night_locations_seen.n_manydoors = true;
      s.run.hand = [
        'protagonist',
        'item_gradphoto',
        'routine_debt',
        'item_old_paper',
        'inf_health_disappearance',
        'inf_jinghe_does_it',
        'inf_hotspring_kills',
        'info_zhou_waiting',
        'info_uncle_gap',
        'npc_ajie',
        'npc_awei',
        'equip_polaroid',
        'info_chunama_pause',
      ];
      s.run.active_encounter = {
        beat_id: 'n_manydoors_ch1',
        stage: 'intro',
        round_id: '',
        blocked_slots: 0,
        attempted_card_ids: [],
        visited_round_ids: [],
      };
    });
    const game = createGame(data, snap);

    const ackRes = game.acknowledgeEncounterIntro();
    expect(ackRes.ok).toBe(true);
    // 進入了第一回合，但立即因容量歸零走 failure 出口
    expect(ackRes.entered_round).toBe(true);
    expect(game.getSnapshot().run.flags.d8_encounter_failure).toBe(true);
    expect(game.encounterView()).toEqual({});
  });

  it('10. 無棋可走（no legal moves）：若既無合法提交、不能丟棄且不能逃離，立即走 failure 出口', () => {
    // 只有主角卡（不可丟棄、不可逃離、在 D8 第 1 回合非正解且 fallback 要求丟棄卡）
    const snap = injectAt(8, 'night', (s) => {
      s.meta.night_locations_seen.n_manydoors = true;
      s.run.hand = ['protagonist'];
      s.run.active_encounter = {
        beat_id: 'n_manydoors_ch1',
        stage: 'intro',
        round_id: '',
        blocked_slots: 0,
        attempted_card_ids: [],
        visited_round_ids: [],
      };
    });
    const game = createGame(data, snap);

    const ackRes = game.acknowledgeEncounterIntro();
    expect(ackRes.ok).toBe(true);
    expect(ackRes.entered_round).toBe(true);

    // 因無合法提交／丟棄／逃離，立即判定 failure
    expect(game.getSnapshot().run.flags.d8_encounter_failure).toBe(true);
    expect(game.encounterView()).toEqual({});
  });

  it('11. 序列化 roundtrip：遭遇暫態完整保存與還原', () => {
    const snap = injectAt(8, 'night', (s) => {
      s.meta.night_locations_seen.n_manydoors = true;
      s.run.hand = ['protagonist', 'item_gradphoto'];
      s.run.active_encounter = {
        beat_id: 'n_manydoors_ch1',
        stage: 'round',
        round_id: 'name_since_when',
        blocked_slots: 1,
        attempted_card_ids: ['k_some_base'],
        visited_round_ids: ['name_since_when'],
      };
    });
    const game1 = createGame(data, snap);
    const serialized = game1.serialize();

    const game2 = createGame(data, serialized);
    expect(game2.encounterView()).toEqual(game1.encounterView());
    expect(game2.getSnapshot().run.active_encounter).toEqual(
      game1.getSnapshot().run.active_encounter,
    );
  });

  it('capacity after effects includes newly entered round pressure', () => {
    const enc = data.beatsById.get('n_manydoors_ch1')!.encounter!;
    const snap = injectAt(8, 'night', (s) => {
      s.run.hand = data.cards.filter((c) => !c.slotless && c.type !== 'madness')
        .slice(0, Number(data.tuning.hand_size) - 2).map((c) => c.id);
      s.meta.knowledge.k_not_today = true;
      s.run.active_encounter = {
        beat_id: 'n_manydoors_ch1', stage: 'round', round_id: enc.rounds[0].id,
        blocked_slots: 2 * enc.per_round_slot_cost,
        attempted_card_ids: [], visited_round_ids: [enc.rounds[0].id],
      };
    });
    const game = createGame(data, snap);
    const result = game.respondToEncounter('k_not_today');
    expect(result.ok).toBe(true);
    expect(result.lines).toContain(enc.on_failure.text);
    expect(game.encounterView()).toEqual({});
  });

  it('formal D45 transformation loses its theory and grants knowledge through the lifecycle', () => {
    const enc = data.beatsById.get('d45_encounter')!.encounter!;
    const branch = enc.rounds[0].responses.find((r) => r.on_resolve.lose && r.on_resolve.gain)!;
    const card = branch.accepts[0];
    const game = createGame(data, injectAt(45, 'morning', (s) => {
      s.run.flags.final_day = true;
      s.run.hand = ['protagonist', card];
    }));
    expect(game.advancePhase().ok).toBe(true);
    expect(game.acknowledgeEncounterIntro().ok).toBe(true);
    const result = game.respondToEncounter(card);
    expect(result.ok).toBe(true);
    expect(result.lines).toContain(branch.on_resolve.text);
    expect(game.hasCard(card)).toBe(false);
    for (const entry of branch.on_resolve.gain!) {
      const gained = typeof entry === 'string' ? entry : entry.card;
      expect(game.hasKnowledge(gained)).toBe(true);
      expect(game.getSnapshot().run.hand).not.toContain(gained);
    }
    expect(game.getSnapshot().run.phase).toBe('evening');
  });

  it('VM hides answers and attempted hand/knowledge cards cannot be retried', () => {
    const enc = data.beatsById.get('n_manydoors_ch1')!.encounter!;
    const answer = enc.rounds[1].responses[0].accepts[0];
    const snap = injectAt(8, 'night', (s) => {
      s.run.hand = ['protagonist', answer, 'equip_polaroid', 'madness#1'];
      s.run.madness_clock['madness#1'] = 2;
      s.meta.knowledge.k_not_today = true;
      s.run.active_encounter = {
        beat_id: 'n_manydoors_ch1', stage: 'round', round_id: enc.rounds[1].id,
        blocked_slots: enc.per_round_slot_cost, attempted_card_ids: ['k_not_today'],
        visited_round_ids: enc.rounds.slice(0, 2).map((r) => r.id),
      };
    });
    const game = createGame(data, snap);
    expectRejectsWithoutChange(game, () => game.respondToEncounter('item_old_paper'), 'not_held');
    expectRejectsWithoutChange(game, () => game.respondToEncounter('unknown'), 'unknown_card');
    expectRejectsWithoutChange(game, () => game.respondToEncounter('madness#1'), 'madness_blocked');
    expectRejectsWithoutChange(game, () => game.escapeEncounter(['madness#1']), 'not_discardable');
    expectRejectsWithoutChange(game, () => game.discardInEncounter('madness#1'), 'not_discardable');
    expect(game.respondToEncounter(answer).ok).toBe(true);
    const view = game.encounterView();
    if (view.stage !== 'round') throw new Error('Expected round stage');
    expect(Object.keys(view).sort()).toEqual([
      'stage', 'beat_id', 'round_id', 'demand', 'blocked_slots', 'capacity', 'available_slots',
      'can_escape', 'escape_cost', 'allow_discard', 'candidates', 'attempted_card_ids',
    ].sort());
    for (const candidate of view.candidates) {
      expect(Object.keys(candidate).sort()).toEqual([
        'card_id', 'base_id', 'source', 'name', 'submittable', 'disabled_reason', 'discardable',
      ].sort());
    }
    for (const id of [answer, 'k_not_today']) {
      expect(view.candidates.find((c) => c.card_id === id)).toMatchObject({
        submittable: false, disabled_reason: 'already_attempted',
      });
      expectRejectsWithoutChange(game, () => game.respondToEncounter(id), 'already_attempted');
    }
  });

  it.each(['victory', 'failure', 'escape'] as const)('%s exit applies cumulative effects once', (outcome) => {
    const localData = { ...structuredClone(data), beatsById: new Map(data.beatsById) };
    const beat = localData.beatsById.get('n_manydoors_ch1')!;
    const enc = beat.encounter!;
    localData.beatsById.set(beat.id, {
      ...beat, encounter: { ...enc, [`on_${outcome}`]: {
        ...enc[`on_${outcome}`], relation: { npc: 'ajie', delta: 1 },
      } },
    });
    const snap = injectAt(8, 'night', (s) => {
      s.run.hand = ['protagonist', 'item_gradphoto', 'inf_health_disappearance'];
      s.run.active_encounter = {
        beat_id: beat.id, stage: 'round', round_id: enc.rounds.at(-1)!.id,
        blocked_slots: enc.per_round_slot_cost, attempted_card_ids: [],
        visited_round_ids: enc.rounds.map((r) => r.id),
      };
    });
    const before = snap.run.relations.ajie ?? 0;
    const game = createGame(localData, snap);
    const result = outcome === 'escape' ? game.escapeEncounter(['item_gradphoto'])
      : game.respondToEncounter(outcome === 'victory' ? 'item_gradphoto' : 'inf_health_disappearance');
    expect(result.ok).toBe(true);
    expect(game.getSnapshot().run.relations.ajie).toBe(before + 1);
    expect(game.encounterView()).toEqual({});
    expectRejectsWithoutChange(game, () => game.respondToEncounter('protagonist'), 'no_active_encounter');
    expectRejectsWithoutChange(game, () => game.escapeEncounter(['item_gradphoto']), 'no_active_encounter');
  });

  it('bad exit effects preserve payment; ending suppresses after_finish advance', () => {
    const localData = { ...structuredClone(data), beatsById: new Map(data.beatsById) };
    const d8 = localData.beatsById.get('n_manydoors_ch1')!;
    localData.beatsById.set(d8.id, { ...d8, encounter: {
      ...d8.encounter!, on_escape: { gain: ['unknown'] },
    } });
    const snap = injectAt(8, 'night', (s) => {
      s.run.hand = ['protagonist', 'item_gradphoto'];
      s.run.active_encounter = { beat_id: d8.id, stage: 'round',
        round_id: d8.encounter!.rounds[0].id, blocked_slots: 1,
        attempted_card_ids: [], visited_round_ids: [d8.encounter!.rounds[0].id] };
    });
    const game = createGame(localData, snap);
    expectRejectsWithoutChange(game, () => game.escapeEncounter(['item_gradphoto']), 'data_conflict');
    const missingEncounter = structuredClone(snap);
    missingEncounter.run.active_encounter.beat_id = 'unknown';
    const corruptedGame = createGame(data, missingEncounter);
    expectRejectsWithoutChange(corruptedGame,
      () => corruptedGame.discardInEncounter('item_gradphoto'), 'data_conflict');
    const d45 = localData.beatsById.get('d45_encounter')!;
    localData.beatsById.set(d45.id, { ...d45, encounter: {
      ...d45.encounter!, on_victory: { ending: 'ending_inventory_be' },
    } });
    const finalGame = createGame(localData, injectAt(45, 'morning', (s) => { s.run.flags.final_day = true; }));
    expect(finalGame.advancePhase().ok).toBe(true);
    expect(finalGame.acknowledgeEncounterIntro().ok).toBe(true);
    expect(finalGame.respondToEncounter('protagonist').ok).toBe(true);
    expect(finalGame.getSnapshot().flow.mode).toBe('ending');
    expect(finalGame.getSnapshot().run.phase).toBe('afternoon');
  });

  it('intro and round block narrative mutations and visits', () => {
    const game = createGame(data, injectAt(8, 'evening', (s) => {
      s.run.hand = ['protagonist', 'item_gradphoto', 'equip_polaroid'];
    }));
    expect(game.advancePhase().ok).toBe(true);
    expect(game.playNightFixed().ok).toBe(true);
    for (const stage of ['intro', 'round']) {
      expect(game.encounterView().stage).toBe(stage);
      expectRejectsWithoutChange(game, () => game.playBeat('n_manydoors_ch1'), 'encounter_active');
      expectRejectsWithoutChange(game, () => game.playEvening(), 'encounter_active');
      expectRejectsWithoutChange(game, () => game.playNightFixed(), 'encounter_active');
      const before = game.serialize();
      game.markDayLocationVisited('temple');
      expect(game.serialize()).toEqual(before);
      if (stage === 'intro') expect(game.acknowledgeEncounterIntro().ok).toBe(true);
    }
  });
});
