/**
 * ReturnFare Web — W6-E2-1 生命週期與出口規則整合測試。
 *
 * 覆蓋驗收規格：
 * 1. 正式 D29 invitation choice：
 *    - 明示不邀、開面板未選（真實 visited + playBeat + buildPanel）、完全未進面板皆從同一 default 槽（invite_none）凍結同值；
 *    - 皆採用非零最高候選（awei）驗證；
 *    - 邀請阿婕／阿薇固定值，使用 formal data.relationScale['恩人']；
 *    - 最高投入（highest_eligible）、全零 fallback 取非首位候選、同分按 npcs.json 來源陣列順序、非候選 NPC 忽略；
 *    - 凍結後追加投入不重算：驗證正式 D31／D39 beat.condition 及最終 D45 ending 快照皆維持原凍結值；
 *    - 遊戲層（Game.choose）與效果層覆寫（含相同 id）、非候選 NPC、非法 fallback／mode 皆原子拒絕，serialize 逐字一致；
 *    - 正向預設效果一次性驗證：加成關係值在多次 getPhaseView 預檢及 advance 推進中嚴格套用一次。
 * 2. 正式 D45 終局生命週期：
 *    - 從可信 D44 night 推進，auto_enter final_day 成立，無需開啟 morning 面板；
 *    - 推進進入 D45 afternoon 固定遭遇（d45_encounter），遭遇中推進阻擋；
 *    - 正常回應後以 after_finish: advance_phase 自動推進至 D45 evening；
 *    - 執行 formal coda on_enter，驗證 loop1_end 旗標與 k_not_today 成立；
 *    - d45_then coda 提供持名冊比對（compare_registry，實證失去 k_not_today 並獲得 k_already_on_list）與空手（empty_handed）兩條合法路徑；
 *    - 未結算 coda 時 phase_exit 門檻拒絕離場（phase_requirements_incomplete）；
 *    - 結算 coda 後 advancePhase 啟動 ending_replaced（source: d45_coda），phase_advanced: false，ended_day=45, ended_phase=evening；
 *    - 缺少凍結代付者時原子拒絕（data_conflict），包含待結算預設記帳與加成效果整筆復原；
 *    - 非法 phase_exit ending 或 source 皆對齊 Godot advance_phase 映射為 data_conflict，serialize 逐字一致；
 *    - getPhaseView().can_advance 查詢純粹無副作用，與實際 advance 結果一致。
 */

import { describe, expect, it } from 'vitest';
import { loadGameDataNode } from '../src/data/load-node';
import type { Beat, GameData, Phase } from '../src/data/types';
import type { GameSnapshot } from '../src/core/state-types';
import { createGame } from '../src/core/state';
import { createRunForTrace } from '../src/core/trace-entry';
import { planEffects } from '../src/core/effect';
import { evalCondition } from '../src/core/condition';

describe('W6-E2-1 lifecycle & exit rules', async () => {
  const data = await loadGameDataNode();

  /** 建立標明起點的可信快照（基於正式 createRunForTrace）。 */
  function injectTrustedSnapshot(
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

  describe('D29 invitation choice & festival_proxy', () => {
    it('三種不邀路徑（明示不邀、開面板未選、完全未進面板）經同一 default 槽凍結同值（非零最高候選 awei）', () => {
      // 三條路徑皆設置相同的非零最高候選投入：awei: 5, ajie: 2, acai: 1 -> 預期凍結 awei
      const setupCounts = (s: GameSnapshot) => {
        s.run.npc_action_counts.awei = 5;
        s.run.npc_action_counts.ajie = 2;
        s.run.npc_action_counts.acai = 1;
      };

      // 1. 明示不邀：主動呼叫 choose('d29_pm_invitation', 'invitation', 'invite_none')
      const snap1 = injectTrustedSnapshot(29, 'afternoon', setupCounts);
      const game1 = createGame(data, snap1);
      const res1 = game1.choose('d29_pm_invitation', 'invitation', 'invite_none');
      expect(res1.ok).toBe(true);
      expect(game1.getSnapshot().run.selected_festival_proxy_npc).toBe('awei');
      expect(game1.getSnapshot().run.choices['d29_pm_invitation::invitation']).toBe('invite_none');
      expect(game1.getSnapshot().run.slots_placed['d29_pm_invitation::invite_none']).toBe(true);
      expect(game1.getSnapshot().run.flags.invited_none).toBe(true);

      // 2. 開面板未選：像 GameShell 一樣 markDayLocationVisited + playBeat + buildPanel，然後不選直接 advancePhase()
      const snap2 = injectTrustedSnapshot(29, 'afternoon', setupCounts);
      const game2 = createGame(data, snap2);
      game2.markDayLocationVisited('sanquan');
      expect(game2.playBeat('d29_pm_invitation').ok).toBe(true);
      expect(game2.getSnapshot().run.beats_entered.d29_pm_invitation).toBe(true);
      const panelView = game2.buildPanel('sanquan');
      expect(panelView.beats.some((b) => b.id === 'd29_pm_invitation')).toBe(true);
      const adv2 = game2.advancePhase();
      expect(adv2.ok).toBe(true);
      expect(adv2.phase_advanced).toBe(true);
      expect(game2.getSnapshot().run.selected_festival_proxy_npc).toBe('awei');
      expect(game2.getSnapshot().run.choices['d29_pm_invitation::invitation']).toBe('invite_none');
      expect(game2.getSnapshot().run.slots_placed['d29_pm_invitation::invite_none']).toBe(true);
      expect(game2.getSnapshot().run.flags.invited_none).toBe(true);

      // 3. 完全未進面板：直接 advancePhase()
      const snap3 = injectTrustedSnapshot(29, 'afternoon', setupCounts);
      const game3 = createGame(data, snap3);
      const adv3 = game3.advancePhase();
      expect(adv3.ok).toBe(true);
      expect(adv3.phase_advanced).toBe(true);
      expect(game3.getSnapshot().run.selected_festival_proxy_npc).toBe('awei');
      expect(game3.getSnapshot().run.choices['d29_pm_invitation::invitation']).toBe('invite_none');
      expect(game3.getSnapshot().run.slots_placed['d29_pm_invitation::invite_none']).toBe(true);
      expect(game3.getSnapshot().run.flags.invited_none).toBe(true);

      // 三種路徑凍結的代付者完全一致
      expect(game1.getSnapshot().run.selected_festival_proxy_npc).toBe(
        game2.getSnapshot().run.selected_festival_proxy_npc,
      );
      expect(game2.getSnapshot().run.selected_festival_proxy_npc).toBe(
        game3.getSnapshot().run.selected_festival_proxy_npc,
      );
    });

    it('邀阿婕與阿薇固定值凍結正確 id 並套用旗標（使用 formal data.relationScale）', () => {
      // 邀阿婕
      const snapAjie = injectTrustedSnapshot(29, 'afternoon', (s) => {
        s.run.hand.push('npc_ajie');
      });
      const gameAjie = createGame(data, snapAjie);
      const resAjie = gameAjie.choose('d29_pm_invitation', 'invitation', 'invite_ajie', 'npc_ajie');
      expect(resAjie.ok).toBe(true);
      expect(gameAjie.getSnapshot().run.selected_festival_proxy_npc).toBe('ajie');
      expect(gameAjie.getSnapshot().run.flags.invited_ajie).toBe(true);

      // 邀阿薇（門檻：relation_at_least 恩人，取自 formal data.relationScale['恩人']）
      const benefactorThreshold = Number(data.relationScale['恩人']);
      expect(Number.isFinite(benefactorThreshold)).toBe(true);
      const snapAwei = injectTrustedSnapshot(29, 'afternoon', (s) => {
        s.run.hand.push('npc_awei');
        s.run.relations.awei = benefactorThreshold;
      });
      const gameAwei = createGame(data, snapAwei);
      const resAwei = gameAwei.choose('d29_pm_invitation', 'invitation', 'invite_awei', 'npc_awei');
      expect(resAwei.ok).toBe(true);
      expect(gameAwei.getSnapshot().run.selected_festival_proxy_npc).toBe('awei');
      expect(gameAwei.getSnapshot().run.flags.invited_awei).toBe(true);
    });

    it('最高投入結算：全零 fallback 取非首位候選、高者勝、同分取 npcs.json 來源陣列序、非候選 NPC 忽略', () => {
      // 1. 全零 fallback 取非首位候選（以 awei 為 fallback，區分 fallback 與恆選首位候選）
      const eligibleNpcs = data.npcs.filter((n) => n.festival_proxy_eligible).map((n) => n.id);
      expect(eligibleNpcs[0]).toBe('ajie');
      const nonFirstFallback = eligibleNpcs[1]; // 'awei'
      expect(nonFirstFallback).toBe('awei');

      const plan0 = planEffects(
        [{ festival_proxy: { mode: 'highest_eligible', fallback: nonFirstFallback } }],
        injectTrustedSnapshot(29, 'afternoon'),
        data,
      );
      expect(plan0.ok).toBe(true);
      expect(plan0.nextState.run.selected_festival_proxy_npc).toBe('awei');

      // 2. awei 明確最高 -> 'awei'
      const snapAweiHigh = injectTrustedSnapshot(29, 'afternoon', (s) => {
        s.run.npc_action_counts.awei = 5;
        s.run.npc_action_counts.ajie = 2;
        s.run.npc_action_counts.acai = 1;
      });
      const planAwei = planEffects(
        [{ festival_proxy: { mode: 'highest_eligible', fallback: 'ajie' } }],
        snapAweiHigh,
        data,
      );
      expect(planAwei.ok).toBe(true);
      expect(planAwei.nextState.run.selected_festival_proxy_npc).toBe('awei');

      // 3. acai 明確最高 -> 'acai'
      const snapAcaiHigh = injectTrustedSnapshot(29, 'afternoon', (s) => {
        s.run.npc_action_counts.acai = 10;
        s.run.npc_action_counts.ajie = 3;
        s.run.npc_action_counts.awei = 3;
      });
      const planAcai = planEffects(
        [{ festival_proxy: { mode: 'highest_eligible', fallback: 'ajie' } }],
        snapAcaiHigh,
        data,
      );
      expect(planAcai.ok).toBe(true);
      expect(planAcai.nextState.run.selected_festival_proxy_npc).toBe('acai');

      // 4. 同分取來源陣列順序（data.npcs 中 ajie 排在 awei 之前，awei 排在 acai 之前）
      // 4a. ajie 與 awei 同分 -> ajie
      const snapTie1 = injectTrustedSnapshot(29, 'afternoon', (s) => {
        s.run.npc_action_counts.ajie = 3;
        s.run.npc_action_counts.awei = 3;
        s.run.npc_action_counts.acai = 1;
      });
      const planTie1 = planEffects(
        [{ festival_proxy: { mode: 'highest_eligible', fallback: 'acai' } }],
        snapTie1,
        data,
      );
      expect(planTie1.ok).toBe(true);
      expect(planTie1.nextState.run.selected_festival_proxy_npc).toBe('ajie');

      // 4b. awei 與 acai 同分且高於 ajie -> awei
      const snapTie2 = injectTrustedSnapshot(29, 'afternoon', (s) => {
        s.run.npc_action_counts.ajie = 1;
        s.run.npc_action_counts.awei = 4;
        s.run.npc_action_counts.acai = 4;
      });
      const planTie2 = planEffects(
        [{ festival_proxy: { mode: 'highest_eligible', fallback: 'ajie' } }],
        snapTie2,
        data,
      );
      expect(planTie2.ok).toBe(true);
      expect(planTie2.nextState.run.selected_festival_proxy_npc).toBe('awei');

      // 5. 非候選 NPC（如 uncle）即使 count 極高也被忽略
      const snapUncleHigh = injectTrustedSnapshot(29, 'afternoon', (s) => {
        s.run.npc_action_counts.uncle = 999;
        s.run.npc_action_counts.awei = 2;
      });
      const planUncle = planEffects(
        [{ festival_proxy: { mode: 'highest_eligible', fallback: 'ajie' } }],
        snapUncleHigh,
        data,
      );
      expect(planUncle.ok).toBe(true);
      expect(planUncle.nextState.run.selected_festival_proxy_npc).toBe('awei');
    });

    it('非法值與重複凍結原子拒絕（效果層與 Game 層 serialize 逐字一致）', () => {
      const snap = injectTrustedSnapshot(29, 'afternoon');
      const originalSerialized = JSON.stringify(snap);

      // 1. 已凍結後再次套用（包含相同 id）皆以 data_conflict 拒絕
      const frozenSnap = injectTrustedSnapshot(29, 'afternoon', (s) => {
        s.run.selected_festival_proxy_npc = 'ajie';
      });
      const frozenSerialized = JSON.stringify(frozenSnap);

      // 效果層再次凍結相同 id -> data_conflict
      const planDupSame = planEffects(
        [{ festival_proxy: { mode: 'fixed', npc: 'ajie' } }],
        frozenSnap,
        data,
      );
      expect(planDupSame.ok).toBe(false);
      expect(planDupSame.reason_code).toBe('data_conflict');
      expect(JSON.stringify(planDupSame.nextState)).toBe(frozenSerialized);

      // 遊戲層再次呼叫 choose 進行不邀 -> data_conflict 且整筆 serialize 不變
      const gameFrozen = createGame(data, frozenSnap);
      const gameChooseDup = gameFrozen.choose('d29_pm_invitation', 'invitation', 'invite_none');
      expect(gameChooseDup.ok).toBe(false);
      expect(gameChooseDup.reason_code).toBe('data_conflict');
      expect(JSON.stringify(gameFrozen.serialize())).toBe(frozenSerialized);

      // 2. 非候選 NPC（fixed） -> data_conflict
      const planBadNpc = planEffects(
        [{ festival_proxy: { mode: 'fixed', npc: 'uncle' } }],
        snap,
        data,
      );
      expect(planBadNpc.ok).toBe(false);
      expect(planBadNpc.reason_code).toBe('data_conflict');
      expect(JSON.stringify(planBadNpc.nextState)).toBe(originalSerialized);

      // 3. 非候選 fallback（highest_eligible） -> data_conflict
      const planBadFb = planEffects(
        [{ festival_proxy: { mode: 'highest_eligible', fallback: 'uncle' } }],
        snap,
        data,
      );
      expect(planBadFb.ok).toBe(false);
      expect(planBadFb.reason_code).toBe('data_conflict');
      expect(JSON.stringify(planBadFb.nextState)).toBe(originalSerialized);

      // 4. 未知 mode -> data_conflict
      const planBadMode = planEffects(
        [{ festival_proxy: { mode: 'random' as unknown as 'fixed', npc: 'ajie' } }],
        snap,
        data,
      );
      expect(planBadMode.ok).toBe(false);
      expect(planBadMode.reason_code).toBe('data_conflict');
      expect(JSON.stringify(planBadMode.nextState)).toBe(originalSerialized);

      // 5. 非物件 festival_proxy -> data_conflict
      const planNotObj = planEffects(
        [{ festival_proxy: 'ajie' as unknown as { mode: 'fixed'; npc: string } }],
        snap,
        data,
      );
      expect(planNotObj.ok).toBe(false);
      expect(planNotObj.reason_code).toBe('data_conflict');
      expect(JSON.stringify(planNotObj.nextState)).toBe(originalSerialized);
    });

    it('正向預設效果一次性驗證：加成關係值在多次 getPhaseView 預檢及 advance 推進中嚴格套用一次', () => {
      // 建立隔離的 beats 複本：為 d29_pm_invitation 的 invite_none 槽追加 additive relation (+5)
      const isolatedBeats = data.beats.map((b) => {
        if (b.id !== 'd29_pm_invitation') return b;
        return {
          ...b,
          slots: (b.slots ?? []).map((s) => {
            if (s.id !== 'invite_none') return s;
            return {
              ...s,
              on_place: {
                ...s.on_place,
                relation: { npc: 'ajie', delta: 5 },
              },
            };
          }),
        };
      });
      const isolatedData: GameData = {
        ...data,
        beats: isolatedBeats,
        beatsById: new Map(isolatedBeats.map((b) => [b.id, b])),
      };

      const snap = injectTrustedSnapshot(29, 'afternoon', (s) => {
        s.run.relations.ajie = 10;
      });
      const game = createGame(isolatedData, snap);

      // 1. 多次查詢 getPhaseView().can_advance 不會提前或重複累加關係
      for (let i = 0; i < 3; i += 1) {
        expect(game.getPhaseView().can_advance).toBe(true);
        expect(game.getSnapshot().run.relations.ajie).toBe(10);
      }

      // 2. 推進時段，預設效果僅執行一次：10 + 5 = 15
      const adv = game.advancePhase();
      expect(adv.ok).toBe(true);
      expect(game.getSnapshot().run.relations.ajie).toBe(15);

      // 3. 推進後再次查詢 getPhaseView() 亦不增加
      expect(game.getPhaseView().day).toBe(29);
      expect(game.getSnapshot().run.relations.ajie).toBe(15);
    });

    it('D29 凍結後追加投入不重算：正式 D31／D39 beat.condition 與最終 ending 快照維持凍結值', () => {
      const snap = injectTrustedSnapshot(29, 'afternoon', (s) => {
        s.run.npc_action_counts.ajie = 1;
      });
      const game = createGame(data, snap);
      // D29 透過選擇凍結 ajie
      const chooseRes = game.choose('d29_pm_invitation', 'invitation', 'invite_none');
      expect(chooseRes.ok).toBe(true);
      expect(game.getSnapshot().run.selected_festival_proxy_npc).toBe('ajie');

      // 之後大幅增加 awei 投入
      const afterSnap = game.serialize();
      afterSnap.run.npc_action_counts.awei = 100;

      // 1. 正式 D31 beat 條件驗證（d31_proxy_ajie 成立，d31_proxy_awei 不成立）
      afterSnap.run.day = 31;
      afterSnap.run.phase = 'morning';
      const d31AjieCond = data.beatsById.get('d31_proxy_ajie')!.condition;
      const d31AweiCond = data.beatsById.get('d31_proxy_awei')!.condition;
      expect(evalCondition(d31AjieCond, afterSnap, data)).toBe(true);
      expect(evalCondition(d31AweiCond, afterSnap, data)).toBe(false);

      // 2. 正式 D39 beat 條件驗證（d39_proxy_ajie 成立，d39_proxy_awei 不成立）
      afterSnap.run.day = 39;
      const d39AjieCond = data.beatsById.get('d39_proxy_ajie')!.condition;
      const d39AweiCond = data.beatsById.get('d39_proxy_awei')!.condition;
      expect(evalCondition(d39AjieCond, afterSnap, data)).toBe(true);
      expect(evalCondition(d39AweiCond, afterSnap, data)).toBe(false);

      // 3. 推進至 D45 終局，驗證 active_ending.festival_proxy_npc 維持凍結之 ajie（而非後來投入較高的 awei）
      afterSnap.run.day = 45;
      afterSnap.run.phase = 'evening';
      afterSnap.run.flags.final_day = true;
      const gameD45 = createGame(data, afterSnap);
      gameD45.playBeat('d45_then');
      gameD45.choose('d45_then', 'd45_coda', 'empty_handed');
      const advEnding = gameD45.advancePhase();
      expect(advEnding.ok).toBe(true);
      expect(gameD45.getSnapshot().flow.mode).toBe('ending');
      expect(gameD45.getSnapshot().flow.active_ending?.festival_proxy_npc).toBe('ajie');
    });
  });

  describe('Formal D45 flow & ending_replaced', () => {
    it('正式 D44 night -> D45 morning final_day auto_enter -> afternoon encounter -> evening coda -> ending_replaced', () => {
      // 從正式 D44 night 起步
      const snapD44 = injectTrustedSnapshot(44, 'night', (s) => {
        // 先前 D29 已凍結代付者 ajie
        s.run.selected_festival_proxy_npc = 'ajie';
        s.run.night_location_chosen = 'n_exit';
      });
      const game = createGame(data, snapD44);

      // 1. D44 night 推進至 D45 morning
      const advToMorn = game.advancePhase();
      expect(advToMorn.ok).toBe(true);
      expect(advToMorn.phase_advanced).toBe(true);
      expect(game.getSnapshot().run.day).toBe(45);
      expect(game.getSnapshot().run.phase).toBe('morning');

      // 驗證 auto_enter 的 d45_morning_invitation 自動寫入 final_day 旗標，無需開啟 morning 面板
      expect(game.getSnapshot().run.flags.final_day).toBe(true);

      // 2. D45 morning 推進至 D45 afternoon
      const advToAft = game.advancePhase();
      expect(advToAft.ok).toBe(true);
      expect(advToAft.phase_advanced).toBe(true);
      expect(game.getSnapshot().run.day).toBe(45);
      expect(game.getSnapshot().run.phase).toBe('afternoon');

      // 驗證固定遭遇 d45_encounter 建立完成
      const enc = game.getSnapshot().run.active_encounter;
      expect(enc.beat_id).toBe('d45_encounter');
      expect(enc.stage).toBe('intro');

      // 遭遇中不可推進
      expect(game.getPhaseView().can_advance).toBe(false);
      const advBlocked = game.advancePhase();
      expect(advBlocked.ok).toBe(false);
      expect(advBlocked.reason_code).toBe('encounter_active');

      // 3. 正常回應遭遇（以主角卡回應）
      const ackRes = game.acknowledgeEncounterIntro();
      expect(ackRes.ok).toBe(true);
      const respRes = game.respondToEncounter('protagonist');
      expect(respRes.ok).toBe(true);

      // after_finish: advance_phase 自動推進至 D45 evening
      expect(game.getSnapshot().run.day).toBe(45);
      expect(game.getSnapshot().run.phase).toBe('evening');
      expect(Object.keys(game.getSnapshot().run.active_encounter).length).toBe(0);

      // 4. 執行 formal coda on_enter，驗證 loop1_end 旗標與 k_not_today 成立
      game.playBeat('d45_then');
      expect(game.getSnapshot().run.flags.loop1_end).toBe(true);
      expect(game.hasKnowledge('k_not_today')).toBe(true);

      // 5. 未結算 coda 時 phase_exit 門檻阻擋離場
      expect(game.getPhaseView().can_advance).toBe(false);
      expect(game.getPhaseView().phase_exit).toEqual({
        location_id: 'jinghe_back',
        satisfied: false,
      });
      const beforeCoda = JSON.stringify(game.serialize());
      const advNoCoda = game.advancePhase();
      expect(advNoCoda.ok).toBe(false);
      expect(advNoCoda.reason_code).toBe('phase_requirements_incomplete');
      expect(JSON.stringify(game.serialize())).toBe(beforeCoda);

      // 6. 走 empty_handed 路線結算 coda
      const chooseCoda = game.choose('d45_then', 'd45_coda', 'empty_handed');
      expect(chooseCoda.ok).toBe(true);
      expect(game.getSnapshot().run.choices['d45_then::d45_coda']).toBe('empty_handed');

      // 門檻已滿足，phase_exit.satisfied 為 true，can_advance 為 true
      expect(game.getPhaseView().phase_exit?.satisfied).toBe(true);
      expect(game.getPhaseView().can_advance).toBe(true);

      // 7. advancePhase 啟動 ending_replaced 結局
      const advEnding = game.advancePhase();
      expect(advEnding.ok).toBe(true);
      expect(advEnding.phase_advanced).toBe(false);

      const endingSnap = game.getSnapshot();
      expect(endingSnap.flow.mode).toBe('ending');
      expect(endingSnap.flow.active_ending).not.toBeNull();
      expect(endingSnap.flow.active_ending?.ending_id).toBe('ending_replaced');
      expect(endingSnap.flow.active_ending?.source_id).toBe('d45_coda');
      expect(endingSnap.flow.active_ending?.ended_day).toBe(45);
      expect(endingSnap.flow.active_ending?.ended_phase).toBe('evening');
      expect(endingSnap.flow.active_ending?.festival_proxy_npc).toBe('ajie');
    });

    it('持名冊路線（compare_registry）：實證先具備 k_not_today，比對後升級為 k_already_on_list 並失去 k_not_today', () => {
      const snapD45Eve = injectTrustedSnapshot(45, 'evening', (s) => {
        s.run.flags.final_day = true;
        s.run.selected_festival_proxy_npc = 'awei';
        s.run.hand.push('info_registry');
      });
      const game = createGame(data, snapD45Eve);

      // 1. 播放 coda beat，觸發 on_enter 獲得 k_not_today
      game.playBeat('d45_then');
      expect(game.hasKnowledge('k_not_today')).toBe(true);
      expect(game.hasKnowledge('k_already_on_list')).toBe(false);

      // 2. 結算 compare_registry
      const chooseRes = game.choose(
        'd45_then',
        'd45_coda',
        'compare_registry',
        'info_registry',
      );
      expect(chooseRes.ok).toBe(true);

      // 3. 比對效果：確實獲得升級卡 k_already_on_list，且失去原持有的 k_not_today
      expect(game.hasKnowledge('k_already_on_list')).toBe(true);
      expect(game.hasKnowledge('k_not_today')).toBe(false);

      // 4. 推進進入 ending_replaced
      const advRes = game.advancePhase();
      expect(advRes.ok).toBe(true);
      expect(advRes.phase_advanced).toBe(false);
      expect(game.getSnapshot().flow.mode).toBe('ending');
      expect(game.getSnapshot().flow.active_ending?.festival_proxy_npc).toBe('awei');
    });

    it('D45 結局時缺少凍結代付者：原子拒絕（data_conflict），附加待結算預設記帳與加成效果整筆復原', () => {
      // 建立隔離的 beats 複本：為 d45_then 追加一個待結算的無條件預設選擇槽（帶 flag 與加成 relation）
      const isolatedBeats = data.beats.map((b) => {
        if (b.id !== 'd45_then') return b;
        return {
          ...b,
          slots: [
            ...(b.slots ?? []),
            {
              id: 'test_default_slot',
              occupant: null,
              label: '測試未完成預設槽',
              accepts: [],
              choice_group: 'test_default_group',
              default_if_unresolved: true,
              on_place: {
                flag: { test_default_flag: true },
                relation: { npc: 'ajie', delta: 5 },
              },
            },
          ],
        };
      });
      const isolatedData: GameData = {
        ...data,
        beats: isolatedBeats,
        beatsById: new Map(isolatedBeats.map((b) => [b.id, b])),
      };

      const snapMissingProxy = injectTrustedSnapshot(45, 'evening', (s) => {
        s.run.flags.final_day = true;
        s.run.selected_festival_proxy_npc = null; // 缺少凍結代付者
        s.run.choices['d45_then::d45_coda'] = 'empty_handed';
        s.run.slots_placed['d45_then::empty_handed'] = true;
        s.run.relations.ajie = 10;
      });
      const game = createGame(isolatedData, snapMissingProxy);
      const beforeJson = JSON.stringify(game.serialize());

      expect(game.getPhaseView().can_advance).toBe(false);
      const advRes = game.advancePhase();
      expect(advRes.ok).toBe(false);
      expect(advRes.reason_code).toBe('data_conflict');

      // 驗證整筆狀態完全不變（包含預設 choice、預設 slot、flag 與加成 relation 全數未留下）
      expect(JSON.stringify(game.serialize())).toBe(beforeJson);
      expect(game.getSnapshot().run.choices['d45_then::test_default_group']).toBeUndefined();
      expect(game.getSnapshot().run.slots_placed['d45_then::test_default_slot']).toBeUndefined();
      expect(game.getSnapshot().run.flags.test_default_flag).toBeUndefined();
      expect(game.getSnapshot().run.relations.ajie).toBe(10);
    });

    it('非法 phase_exit ending 或 source 皆對齊 Godot advance_phase 映射為 data_conflict，serialize 逐字一致', () => {
      // 1. 未知結局 id（例如 nonexistent_ending）
      const badEndingBeats = data.beats.map((b) => {
        if (b.id !== 'd45_then') return b;
        return {
          ...b,
          phase_exit: {
            ...b.phase_exit,
            ending: 'nonexistent_ending',
          },
        };
      });
      const badEndingData: GameData = {
        ...data,
        beats: badEndingBeats,
        beatsById: new Map(badEndingBeats.map((b) => [b.id, b])),
      };

      const snapBadEnding = injectTrustedSnapshot(45, 'evening', (s) => {
        s.run.flags.final_day = true;
        s.run.selected_festival_proxy_npc = 'ajie';
        s.run.choices['d45_then::d45_coda'] = 'empty_handed';
        s.run.slots_placed['d45_then::empty_handed'] = true;
      });
      const gameBadEnding = createGame(badEndingData, snapBadEnding);
      const beforeBadEnding = JSON.stringify(gameBadEnding.serialize());
      const advBadEnding = gameBadEnding.advancePhase();
      expect(advBadEnding.ok).toBe(false);
      expect(advBadEnding.reason_code).toBe('data_conflict');
      expect(JSON.stringify(gameBadEnding.serialize())).toBe(beforeBadEnding);

      // 2. 非法 ending source（例如 invalid_source）
      const badSourceBeats = data.beats.map((b) => {
        if (b.id !== 'd45_then') return b;
        return {
          ...b,
          phase_exit: {
            ...b.phase_exit,
            source: 'invalid_source',
          },
        };
      });
      const badSourceData: GameData = {
        ...data,
        beats: badSourceBeats,
        beatsById: new Map(badSourceBeats.map((b) => [b.id, b])),
      };

      const snapBadSource = injectTrustedSnapshot(45, 'evening', (s) => {
        s.run.flags.final_day = true;
        s.run.selected_festival_proxy_npc = 'ajie';
        s.run.choices['d45_then::d45_coda'] = 'empty_handed';
        s.run.slots_placed['d45_then::empty_handed'] = true;
      });
      const gameBadSource = createGame(badSourceData, snapBadSource);
      const beforeBadSource = JSON.stringify(gameBadSource.serialize());
      const advBadSource = gameBadSource.advancePhase();
      expect(advBadSource.ok).toBe(false);
      expect(advBadSource.reason_code).toBe('data_conflict');
      expect(JSON.stringify(gameBadSource.serialize())).toBe(beforeBadSource);
    });

    it('getPhaseView().can_advance 查詢純粹無副作用，與 advancePhase 命令一致', () => {
      const snap = injectTrustedSnapshot(45, 'evening', (s) => {
        s.run.flags.final_day = true;
        s.run.selected_festival_proxy_npc = 'ajie';
      });
      const game = createGame(data, snap);
      const beforeJson = JSON.stringify(game.serialize());

      // 未選 coda：多次查詢 can_advance 皆為 false 且狀態零變化
      for (let i = 0; i < 5; i += 1) {
        expect(game.getPhaseView().can_advance).toBe(false);
      }
      expect(JSON.stringify(game.serialize())).toBe(beforeJson);

      // 選擇 coda
      game.choose('d45_then', 'd45_coda', 'empty_handed');
      const afterChoiceJson = JSON.stringify(game.serialize());

      // 已選 coda：多次查詢 can_advance 皆為 true 且狀態零變化
      for (let i = 0; i < 5; i += 1) {
        expect(game.getPhaseView().can_advance).toBe(true);
      }
      expect(JSON.stringify(game.serialize())).toBe(afterChoiceJson);

      // 執行推進確實成功
      const advRes = game.advancePhase();
      expect(advRes.ok).toBe(true);
      expect(advRes.phase_advanced).toBe(false);
      expect(game.getSnapshot().flow.mode).toBe('ending');
    });
  });
});
