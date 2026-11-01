/**
 * ReturnFare Web — 縱慾系統單元與規則層整合驗證（W6-B）。
 */

import { describe, expect, it } from 'vitest';
import { loadGameDataNode } from '../src/data/load-node';
import type { Beat, Effect, GameData, Phase, Slot } from '../src/data/types';
import { levelFor, pickExit } from '../src/core/indulgence';
import { TriState } from '../src/core/panel';
import { createGame } from '../src/core/state';
import type { GameSnapshot } from '../src/core/state-types';
import { createRunForTrace } from '../src/core/trace-entry';

describe('W6-B indulgence system (core & integration)', async () => {
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

  function addMadness(
    snap: GameSnapshot,
    cards: Record<string, number>,
  ): void {
    for (const [id, count] of Object.entries(cards)) {
      if (!snap.run.hand.includes(id)) {
        snap.run.hand.push(id);
      }
      snap.run.madness_clock[id] = count;
    }
  }

  describe('levelFor() and pickExit() pure functions', () => {
    it('levelFor: 邊界與強度級查表符合正式 tuning', () => {
      const { forced_light_count: light, forced_normal_until: normal } = data.tuning.indulgence;
      expect(levelFor(0, data.tuning)).toBe('light');
      expect(levelFor(light, data.tuning)).toBe('light');
      expect(levelFor(light + 1, data.tuning)).toBe('normal');
      expect(levelFor(normal, data.tuning)).toBe('normal');
      expect(levelFor(normal + 1, data.tuning)).toBe('heavy');

      // 自訂 tuning
      const customTuning = {
        forced_light_count: 3,
        forced_normal_until: 5,
        soak_phase_cost: 2,
        soak_cards_cleared: 1,
      };
      const custom = { ...data.tuning, indulgence: customTuning };
      expect(levelFor(3, custom)).toBe('light');
      expect(levelFor(4, custom)).toBe('normal');
      expect(levelFor(5, custom)).toBe('normal');
      expect(levelFor(6, custom)).toBe('heavy');
    });

    it('pickExit: 掃描條件成立最高權重，過濾 auto:false，同分保留載入順序', () => {
      const snap = injectAt(1, 'morning', (s) => {
        addMadness(s, { 'madness#1': 7 });
      });

      // 在 D1 morning，madness >= 1 成立。
      // exit_sanquan: x_smash(weight: 1), x_binge(weight: 2), x_soak(auto: false)
      // x_splurge 需要 card_money（未持有），x_violence 需要 day >= 16，x_lust 需要關係
      // 故 x_binge (weight 2) 嚴格大於 x_smash (weight 1)
      const exit = pickExit(snap, data);
      expect(exit).not.toBeNull();
      expect(exit?.beatId).toBe('exit_sanquan');
      expect(exit?.slotId).toBe('x_binge');

      // auto:false 即使權重更高亦不可入自動池
      const mockSlot: Slot = {
        id: 'mock_high_auto_false',
        accepts: ['madness'],
        indulgence: { weight: 9999, auto: false },
      };
      const mockBeat: Beat = {
        id: 'mock_exit_beat',
        location: 'sanquan',
        title: 'Mock',
        slots: [mockSlot],
      };
      const customData: GameData = {
        ...data,
        beats: [mockBeat, ...data.beats],
      };
      const exitWithMock = pickExit(snap, customData);
      // 依然是 x_binge，mock_high_auto_false 被 auto:false 排除
      expect(exitWithMock?.slotId).toBe('x_binge');

      // 同分時嚴格保留資料順序第一個
      const mockTie1: Slot = {
        id: 'tie_slot_1',
        accepts: ['madness'],
        indulgence: { weight: 20 },
      };
      const mockTie2: Slot = {
        id: 'tie_slot_2',
        accepts: ['madness'],
        indulgence: { weight: 20 },
      };
      const mockTieBeat: Beat = {
        id: 'mock_tie_beat',
        location: 'sanquan',
        title: 'Mock Tie',
        slots: [mockTie1, mockTie2],
      };
      const tieData: GameData = {
        ...data,
        beats: [mockTieBeat, ...data.beats],
      };
      const tieExit = pickExit(snap, tieData);
      expect(tieExit?.slotId).toBe('tie_slot_1');
    });

    it('pickExit: 忽略 when、地點可達性與 slots_placed（K-54 出口可重複使用）', () => {
      const snap = injectAt(10, 'night', (s) => {
        addMadness(s, { 'madness#1': 7 });
        // 刻意標記已放置過
        s.run.slots_placed['exit_sanquan::x_binge'] = true;
      });
      // 即使在 night 且 slots_placed 已有，pickExit 依舊可挑選 x_binge
      const exit = pickExit(snap, data);
      expect(exit?.slotId).toBe('x_binge');
    });
  });

  describe('Active indulgence via indulge() and tryPlace()', () => {
    it('official active exit removes selected madness#N, charges action, and increments count once', () => {
      const snap = injectAt(2, 'morning', (s) => {
        addMadness(s, { 'madness#1': 7, 'madness#2': 5 });
        s.run.action_spent = false;
        s.run.indulgence_count = 0;
      });
      const game = createGame(data, snap);

      // 主動在 exit_sanquan 的 x_smash 放置指定的 madness#2
      const res = game.tryPlace('madness#2', 'exit_sanquan', 'x_smash');
      expect(res.ok).toBe(true);
      expect(res.lines.length).toBeGreaterThan(0);

      const after = game.getSnapshot();
      // 正好移除所選的 madness#2，madness#1 仍在
      expect(after.run.hand.includes('madness#2')).toBe(false);
      expect(after.run.hand.includes('madness#1')).toBe(true);
      expect(after.run.madness_clock['madness#2']).toBeUndefined();
      expect(after.run.madness_clock['madness#1']).toBe(7);
      expect(after.run.madness_cards_cleared).toBe(1);

      // 當前行動格已用
      expect(after.run.action_spent).toBe(true);
      // 縱慾次數 +1
      expect(after.run.indulgence_count).toBe(1);
      // x_smash 的 on_place 旗標落地
      expect(after.run.flags.inn_damaged).toBe(true);
      // 出口槽刻意不記錄 slots_placed（可重複使用）
      expect(after.run.slots_placed['exit_sanquan::x_smash']).toBeUndefined();
    });

    it('exit reuse: 同一個出口槽隔天或不同時段可再次使用', () => {
      const snap = injectAt(2, 'morning', (s) => {
        addMadness(s, { 'madness#1': 7, 'madness#2': 5 });
      });
      const game = createGame(data, snap);
      const res1 = game.tryPlace('madness#1', 'exit_sanquan', 'x_smash');
      expect(res1.ok).toBe(true);

      // 推進到 afternoon（重設 action_spent）
      const adv = game.advancePhase();
      expect(adv.ok).toBe(true);
      expect(game.getSnapshot().run.phase).toBe('afternoon');
      expect(game.getSnapshot().run.action_spent).toBe(false);

      // 同一個 exit_sanquan::x_smash 可以再次放入 madness#2
      const res2 = game.tryPlace('madness#2', 'exit_sanquan', 'x_smash');
      expect(res2.ok).toBe(true);
      expect(game.getSnapshot().run.indulgence_count).toBe(2);
    });

    it('soak clears configured cards, reserves afternoon action ahead, and NEVER changes phase directly', () => {
      const snap = injectAt(3, 'morning', (s) => {
        addMadness(s, { 'madness#1': 7, 'madness#2': 4, 'madness#3': 5 });
        s.run.action_spent = false;
        s.run.actions_spent_ahead = 0;
      });
      const game = createGame(data, snap);

      // 泡湯特例
      const soakRes = game.tryPlace('madness#2', 'exit_sanquan', 'x_soak');
      expect(soakRes.ok).toBe(true);

      const after = game.getSnapshot();
      // 依然在 morning，絕不在此直接改變 phase
      expect(after.run.phase).toBe('morning');
      expect(after.run.action_spent).toBe(true);
      expect(after.run.actions_spent_ahead).toBe(data.tuning.indulgence.soak_phase_cost - 1);
      expect(after.run.indulgence_count).toBe(1);
      const cleared = Math.min(3, data.tuning.indulgence.soak_cards_cleared);
      const removed = ['madness#2', 'madness#1', 'madness#3'].slice(0, cleared);
      expect(after.run.madness_cards_cleared).toBe(cleared);
      expect(after.run.hand).toEqual(snap.run.hand.filter((id) => !removed.includes(id)));
      expect(after.run.hand).not.toContain('madness#2');

      // 推進到 afternoon
      const adv = game.advancePhase();
      expect(adv.ok).toBe(true);
      const pmState = game.getSnapshot();
      expect(pmState.run.phase).toBe('afternoon');
      // 下午行動格已被預先扣除
      expect(pmState.run.action_spent).toBe(true);
      expect(pmState.run.actions_spent_ahead).toBe(0);
    });

    it('soak restrictions: 只能在上午發動，且剩餘行動格必須足夠', () => {
      // 1. 下午發動泡湯：拒絕
      const pmSnap = injectAt(3, 'afternoon', (s) => {
        addMadness(s, { 'madness#1': 7 });
        s.run.action_spent = false;
      });
      const pmGame = createGame(data, pmSnap);
      const pmRes = pmGame.tryPlace('madness#1', 'exit_sanquan', 'x_soak');
      expect(pmRes.ok).toBe(false);
      expect(pmRes.reason_code).toBe('locked');
      expect(pmRes.reason_text).toContain('上午');

      // 2. 上午但行動格已用：拒絕
      const spentSnap = injectAt(3, 'morning', (s) => {
        addMadness(s, { 'madness#1': 7 });
        s.run.action_spent = true;
      });
      const spentGame = createGame(data, spentSnap);
      const spentRes = spentGame.tryPlace('madness#1', 'exit_sanquan', 'x_soak');
      expect(spentRes.ok).toBe(false);
      expect(spentRes.reason_code).toBe('locked');
      expect(spentRes.reason_text).toContain('格數不足');
    });

    it('direct Game.indulge() API adheres to same guards and preserves instance ID', () => {
      const snap = injectAt(2, 'morning', (s) => {
        addMadness(s, { 'madness#1': 7 });
      });
      const game = createGame(data, snap);
      const res = game.indulge('exit_sanquan', 'x_binge', 'madness#1');
      expect(res.ok).toBe(true);
      expect(game.getSnapshot().run.flags.binge_eaten).toBe(true);
    });

    it('soak remains morning-only when its configured cost is one and the fixture allows afternoon', () => {
      const original = data.beatsById.get('exit_sanquan')!;
      const soakBeat: Beat = {
        ...original,
        when: { day_from: 1, day_to: 45, phase: ['morning', 'afternoon'] },
      };
      const customData: GameData = {
        ...data,
        tuning: {
          ...data.tuning,
          indulgence: { ...data.tuning.indulgence, soak_phase_cost: 1 },
        },
        beats: data.beats.map((beat) => beat.id === soakBeat.id ? soakBeat : beat),
        beatsById: new Map([...data.beatsById, [soakBeat.id, soakBeat]]),
      };
      const game = createGame(customData, injectAt(3, 'afternoon', (s) => {
        addMadness(s, { 'madness#1': 4 });
      }));
      const before = JSON.stringify(game.serialize());
      expect(game.previewSlot('exit_sanquan', 'x_soak').cards).toEqual([]);
      expect(game.indulge('exit_sanquan', 'x_soak', 'madness#1')).toMatchObject({
        ok: false, reason_code: 'locked', lines: [],
      });
      expect(game.tryPlace('madness#1', 'exit_sanquan', 'x_soak').ok).toBe(false);
      expect(JSON.stringify(game.serialize())).toBe(before);
      expect(game.buildPanel('sanquan').beats.find((b) => b.id === 'exit_sanquan')!
        .slots.find((s) => s.id === 'x_soak')!.tri).toBe(TriState.LOCKED);
    });

    it('key rejects preserve serialized state byte-for-byte with zero side effects', () => {
      const snap = injectAt(2, 'morning', (s) => {
        addMadness(s, { 'madness#1': 7 });
      });
      const game = createGame(data, snap);
      const baselineJson = JSON.stringify(game.serialize());

      // 未持有的卡
      const r1 = game.indulge('exit_sanquan', 'x_smash', 'madness#999');
      expect(r1.ok).toBe(false);
      expect(r1.reason_code).toBe('not_held');
      expect(JSON.stringify(game.serialize())).toBe(baselineJson);

      // 非發狂卡
      const r2 = game.indulge('exit_sanquan', 'x_smash', 'protagonist');
      expect(r2.ok).toBe(false);
      expect(r2.reason_code).toBe('not_accepted');
      expect(JSON.stringify(game.serialize())).toBe(baselineJson);

      // 非縱慾槽
      const r3 = game.indulge('d2_pm_work', 'work', 'madness#1');
      expect(r3.ok).toBe(false);
      expect(r3.reason_code).toBe('not_accepted');
      expect(JSON.stringify(game.serialize())).toBe(baselineJson);

      // 未知 beat / slot
      const r4 = game.indulge('unknown_beat', 'unknown_slot', 'madness#1');
      expect(r4.ok).toBe(false);
      expect(r4.reason_code).toBe('unknown_beat');
      expect(JSON.stringify(game.serialize())).toBe(baselineJson);
    });
  });

  describe('Forced indulgence in advancePhase() lifecycle', () => {
    it('forced ending wins over target auto-enter and fixed encounter checks', () => {
      const exit: Beat = {
        id: 'test_forced_ending_exit',
        location: 'sanquan',
        slots: [{
          id: 'ending_exit', accepts: ['madness'], indulgence: { weight: 100 },
          on_place: { ending: 'ending_inventory_be' },
        }],
      };
      const encounter = data.beats.find((beat) => beat.fixed && beat.encounter)!;
      expect(encounter).toBeDefined();
      const target: Beat = {
        ...encounter, id: 'test_target_encounter',
        when: { day: 11, phase: 'morning' }, condition: undefined, requires: undefined,
      };
      const auto: Beat = {
        id: 'test_target_auto', location: 'sanquan', auto_enter: true, fixed: true,
        when: { day: 11, phase: 'morning' },
        on_enter: { flag: { unwanted_auto_effect: true } },
      };
      const beats = [...data.beats, exit, auto, target];
      const customData = { ...data, beats, beatsById: new Map(beats.map((b) => [b.id, b])) };
      const game = createGame(customData, injectAt(10, 'night', (s) => {
        s.run.night_location_chosen = 'n_exit';
        addMadness(s, { 'madness#1': 1 });
      }));
      expect(game.advancePhase()).toMatchObject({ ok: true, phase_advanced: true });
      expect(game.getSnapshot().flow.mode).toBe('ending');
      expect(game.getSnapshot().flow.active_ending?.ending_id).toBe('ending_inventory_be');
      expect(game.getSnapshot().run.flags.unwanted_auto_effect).toBeUndefined();
      expect(game.getSnapshot().run.indulgence_count).toBe(1);
      const before = JSON.stringify(game.serialize());
      expect(game.indulge(exit.id, 'ending_exit', 'madness#1').reason_code).toBe('not_run');
      expect(JSON.stringify(game.serialize())).toBe(before);
    });

    it('active and forced share the same level count and additive effects', () => {
      const game = createGame(data, injectAt(2, 'morning', (s) => {
        addMadness(s, { 'madness#1': 4, 'madness#2': 0 });
        s.run.forced_pending = ['madness#2'];
      }));
      expect(game.indulge('exit_sanquan', 'x_binge', 'madness#1').ok).toBe(true);
      expect(game.getSnapshot().run.indulgence_count).toBe(1);
      const beforeRelation = game.getSnapshot().run.relations.uncle ?? 0;
      expect(game.advancePhase().ok).toBe(true);
      expect(game.getSnapshot().run.indulgence_count).toBe(2);
      const normalDelta = data.beatsById.get('exit_sanquan')!.slots!
        .find((slot) => slot.id === 'x_binge')!.on_place_by_level!.normal!.relation!.delta;
      expect(game.getSnapshot().run.relations.uncle).toBe(beforeRelation + normalDelta);
    });
    it('morning tick triggers forced indulgence, charges action, and applies level-specific effect exactly once', () => {
      const snap = injectAt(10, 'night', (s) => {
        s.run.night_location_chosen = 'n_exit';
        addMadness(s, { 'madness#1': 1 }); // 倒數剩 1 天，進 morning 歸零
        s.run.relations.uncle = 0;
        s.run.indulgence_count = 1; // 已縱慾過 1 次，這次是第 2 次 -> level 為 'normal'
      });
      const game = createGame(data, snap);
      const beforeQueries = JSON.stringify(game.serialize());
      expect(game.getPhaseView().can_advance).toBe(true);
      expect(game.getPhaseView().can_advance).toBe(true);
      expect(JSON.stringify(game.serialize())).toBe(beforeQueries);

      const adv = game.advancePhase();
      expect(adv.ok).toBe(true);
      expect(adv.phase_advanced).toBe(true);

      const state = game.getSnapshot();
      expect(state.run.day).toBe(11);
      expect(state.run.phase).toBe('morning');
      // 強制縱慾自動結算了 x_binge（權重 2 最高）
      expect(state.run.hand.includes('madness#1')).toBe(false);
      expect(state.run.madness_clock['madness#1']).toBeUndefined();
      expect(state.run.forced_pending).toEqual([]);
      // 行動格被強制縱慾消耗
      expect(state.run.action_spent).toBe(true);
      // 縱慾次數由 1 變 2
      expect(state.run.indulgence_count).toBe(2);

      // x_binge 的 base on_place 效果（flag: binge_eaten）
      expect(state.run.flags.binge_eaten).toBe(true);
      // x_binge 的 on_place_by_level.normal 效果：uncle 關係 -1（數值計數斷言，非僅布林旗標）
      expect(state.run.relations.uncle).toBe(-1);

      // 強制文字獨立投影，供地圖保留顯示。
      const phaseView = game.getPhaseView();
      expect(phaseView.forced_lines.length).toBeGreaterThan(0);
      expect(phaseView.forced_lines.some((line) => line.includes('剩菜'))).toBe(true);
    });

    it('representative multiple debt across morning, afternoon, and next day', () => {
      // 3 張剛歸零的發狂卡
      const snap = injectAt(10, 'night', (s) => {
        s.run.night_location_chosen = 'n_exit';
        addMadness(s, {
          'madness#1': 1,
          'madness#2': 1,
          'madness#3': 1,
        });
      });
      const game = createGame(data, snap);

      // 1. night -> D11 morning：結算第 1 張
      const adv1 = game.advancePhase();
      expect(adv1.ok).toBe(true);
      expect(game.getSnapshot().run.phase).toBe('morning');
      expect(game.getSnapshot().run.action_spent).toBe(true);
      expect(game.getSnapshot().run.forced_pending).toEqual(['madness#2', 'madness#3']);
      expect(game.getSnapshot().run.hand.includes('madness#1')).toBe(false);
      expect(game.getSnapshot().run.indulgence_count).toBe(1);

      // 2. D11 morning -> afternoon：結算第 2 張
      const adv2 = game.advancePhase();
      expect(adv2.ok).toBe(true);
      expect(game.getSnapshot().run.phase).toBe('afternoon');
      expect(game.getSnapshot().run.action_spent).toBe(true);
      expect(game.getSnapshot().run.forced_pending).toEqual(['madness#3']);
      expect(game.getSnapshot().run.hand.includes('madness#2')).toBe(false);
      expect(game.getSnapshot().run.indulgence_count).toBe(2);

      // 3. D11 afternoon -> evening：非行動時段，第 3 張留存
      const adv3 = game.advancePhase();
      expect(adv3.ok).toBe(true);
      expect(game.getSnapshot().run.phase).toBe('evening');
      expect(game.getSnapshot().run.forced_pending).toEqual(['madness#3']);
      expect(game.getSnapshot().run.indulgence_count).toBe(2);

      // 4. D11 evening -> night
      const adv4 = game.advancePhase();
      expect(adv4.ok).toBe(true);
      expect(game.getSnapshot().run.phase).toBe('night');
      expect(game.getSnapshot().run.forced_pending).toEqual(['madness#3']);

      // 5. 進入夜間地點並推進至 D12 morning：結算第 3 張
      game.enterNightLocation('n_exit');
      const adv5 = game.advancePhase();
      expect(adv5.ok).toBe(true);
      expect(game.getSnapshot().run.day).toBe(12);
      expect(game.getSnapshot().run.phase).toBe('morning');
      expect(game.getSnapshot().run.action_spent).toBe(true);
      expect(game.getSnapshot().run.forced_pending).toEqual([]);
      expect(game.getSnapshot().run.hand.includes('madness#3')).toBe(false);
      expect(game.getSnapshot().run.indulgence_count).toBe(3);
    });

    it('skip stale queue heads already absent from hand per Godot contract', () => {
      const snap = injectAt(10, 'morning', (s) => {
        // 手上只有 madness#2，但 forced_pending 前面有一張早已不在手上的 madness#stale
        s.run.forced_pending = ['madness#stale', 'madness#2'];
        addMadness(s, { 'madness#2': 0 });
        s.run.action_spent = false;
      });
      const game = createGame(data, snap);
      // 推進到 afternoon 結算隊列
      const adv = game.advancePhase();
      expect(adv.ok).toBe(true);

      const state = game.getSnapshot();
      // madness#stale 被跳過，madness#2 成功結算
      expect(state.run.forced_pending).toEqual([]);
      expect(state.run.hand.includes('madness#2')).toBe(false);
      expect(state.run.action_spent).toBe(true);
      expect(state.run.indulgence_count).toBe(1);
    });

    it('one isolated invalid exit/effect fixture retains debt, card, and action without polluting catalog', () => {
      // 構造一個結算失敗的孤立 beat fixture
      const originalBeats = data.beats;
      const originalBeatsById = data.beatsById;

      const brokenSlot: Slot = {
        id: 'broken_slot',
        accepts: ['madness'],
        indulgence: { weight: 9999 },
        // 故意設置一個無法滿足條件或壞格式的效果，使其在 planEffects 失敗
        on_place: {
          text: 'must not leak from a failed transaction',
          relation: {
            npc: 'non_existent_npc',
            delta: 1,
          },
        },
      };
      const brokenBeat: Beat = {
        id: 'broken_exit_beat',
        location: 'sanquan',
        when: { day: 10, phase: 'morning' },
        title: 'Broken Exit',
        slots: [brokenSlot],
      };

      const mutableBeats = [...originalBeats, brokenBeat];
      const mutableBeatsById = new Map(originalBeatsById);
      mutableBeatsById.set('broken_exit_beat', brokenBeat);

      const brokenData: GameData = {
        ...data,
        beats: mutableBeats,
        beatsById: mutableBeatsById,
      };

      const active = createGame(brokenData, injectAt(10, 'morning', (s) => {
        addMadness(s, { 'madness#1': 4 });
      }));
      const beforeActive = JSON.stringify(active.serialize());
      expect(active.indulge(brokenBeat.id, brokenSlot.id, 'madness#1'))
        .toMatchObject({ ok: false, reason_code: 'data_conflict', lines: [] });
      expect(JSON.stringify(active.serialize())).toBe(beforeActive);

      const snap = injectAt(10, 'night', (s) => {
        s.run.night_location_chosen = 'n_exit';
        addMadness(s, { 'madness#1': 1 });
      });

      const game = createGame(brokenData, snap);
      const adv = game.advancePhase();
      expect(adv.ok).toBe(true);

      const after = game.getSnapshot();
      // 效果結算失敗，債留在 forced_pending，發狂卡不被扣除，行動格不被扣除
      expect(after.run.forced_pending).toEqual(['madness#1']);
      expect(after.run.hand.includes('madness#1')).toBe(true);
      expect(after.run.action_spent).toBe(false);
      expect(after.run.indulgence_count).toBe(0);
    });

    it('conditional effect observes that the requested madness cost has already been removed', () => {
      const snap = injectAt(2, 'morning', (s) => {
        addMadness(s, { 'madness#1': 7 });
        s.run.indulgence_count = 0;
      });

      // 若效果讀到扣卡前狀態，就會試圖移除主角卡並使整筆交易失敗。
      const originalBeats = data.beats;
      const originalBeatsById = data.beatsById;
      const testSlot: Slot = {
        id: 'test_post_cost_slot',
        accepts: ['madness'],
        indulgence: { weight: 1 },
        on_place: {
          flag: {
            cost_removed_before_effect: true,
          },
          lose: [
            {
              card: 'protagonist',
              if: {
                has_card: 'madness#1',
              },
            },
          ],
        },
      };
      const testBeat: Beat = {
        id: 'test_post_cost_beat',
        location: 'sanquan',
        title: 'Test',
        when: {
          day_from: 1,
          day_to: 45,
          phase: ['morning', 'afternoon'],
        },
        slots: [testSlot],
      };
      const testData: GameData = {
        ...data,
        beats: [testBeat, ...originalBeats],
        beatsById: new Map([['test_post_cost_beat', testBeat], ...originalBeatsById]),
      };

      const game = createGame(testData, snap);
      const res = game.indulge('test_post_cost_beat', 'test_post_cost_slot', 'madness#1');
      expect(res.ok).toBe(true);
      expect(game.getSnapshot().run.flags.cost_removed_before_effect).toBe(true);
      expect(game.getSnapshot().run.indulgence_count).toBe(1);
    });
  });
});
