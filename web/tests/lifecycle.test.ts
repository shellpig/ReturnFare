/**
 * ReturnFare Web — W6-E2-1 生命週期與出口規則整合測試。
 *
 * 覆蓋驗收規格：
 * 1. 正式 D29 invitation choice：
 *    - 明示不邀、開面板未選、完全未進面板皆從同一 default_if_unresolved 槽（invite_none）凍結代付者；
 *    - 邀請阿婕／阿薇固定值；
 *    - 最高投入（highest_eligible）、同分按 npcs.json 來源陣列順序、全零 fallback；
 *    - 凍結後追加投入不重算，D31／D39 條件與正常結局快照維持凍結值；
 *    - 覆寫（含相同 id）、非候選 NPC、非法 fallback／mode 皆原子拒絕，serialize 逐字一致。
 * 2. 正式 D45 終局生命週期：
 *    - 從可信 D44 night 推進，auto_enter final_day 成立，無需開啟 morning 面板；
 *    - 推進進入 D45 afternoon 固定遭遇（d45_encounter）；
 *    - 正常回應後以 after_finish: advance_phase 自動推進至 D45 evening；
 *    - d45_then coda 提供持名冊比對（compare_registry）與空手（empty_handed）兩條合法路徑；
 *    - 未結算 coda 時 phase_exit 門檻拒絕離場（phase_requirements_incomplete）；
 *    - 結算 coda 後 advancePhase 啟動 ending_replaced（source: d45_coda），phase_advanced: false，ended_day=45, ended_phase=evening；
 *    - 缺少凍結代付者時原子拒絕（data_conflict），包含逾期預設記帳整筆復原；
 *    - getPhaseView().can_advance 查詢純粹，與實際 advance 結果一致。
 */

import { describe, expect, it } from 'vitest';
import { loadGameDataNode } from '../src/data/load-node';
import type { Phase } from '../src/data/types';
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
    it('三種不邀路徑（明示不邀、開面板未選、完全未進面板）經同一 default 槽凍結同值', () => {
      // 1. 明示不邀：主動呼叫 choose('d29_pm_invitation', 'invitation', 'invite_none')
      const snap1 = injectTrustedSnapshot(29, 'afternoon');
      const game1 = createGame(data, snap1);
      const res1 = game1.choose('d29_pm_invitation', 'invitation', 'invite_none');
      expect(res1.ok).toBe(true);
      expect(game1.getSnapshot().run.selected_festival_proxy_npc).toBe('ajie');
      expect(game1.getSnapshot().run.choices['d29_pm_invitation::invitation']).toBe('invite_none');
      expect(game1.getSnapshot().run.slots_placed['d29_pm_invitation::invite_none']).toBe(true);
      expect(game1.getSnapshot().run.flags.invited_none).toBe(true);

      // 2. 開面板未選：查詢 sanquan 面板後直接 advancePhase()
      const snap2 = injectTrustedSnapshot(29, 'afternoon');
      const game2 = createGame(data, snap2);
      const panelView = game2.buildPanel('sanquan');
      expect(panelView).not.toBeNull();
      const adv2 = game2.advancePhase();
      expect(adv2.ok).toBe(true);
      expect(adv2.phase_advanced).toBe(true);
      expect(game2.getSnapshot().run.selected_festival_proxy_npc).toBe('ajie');
      expect(game2.getSnapshot().run.choices['d29_pm_invitation::invitation']).toBe('invite_none');
      expect(game2.getSnapshot().run.slots_placed['d29_pm_invitation::invite_none']).toBe(true);
      expect(game2.getSnapshot().run.flags.invited_none).toBe(true);

      // 3. 完全未進面板：直接 advancePhase()
      const snap3 = injectTrustedSnapshot(29, 'afternoon');
      const game3 = createGame(data, snap3);
      const adv3 = game3.advancePhase();
      expect(adv3.ok).toBe(true);
      expect(adv3.phase_advanced).toBe(true);
      expect(game3.getSnapshot().run.selected_festival_proxy_npc).toBe('ajie');
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

    it('邀阿婕與阿薇固定值凍結正確 id 並套用旗標', () => {
      // 邀阿婕
      const snapAjie = injectTrustedSnapshot(29, 'afternoon', (s) => {
        s.run.hand.push('npc_ajie');
      });
      const gameAjie = createGame(data, snapAjie);
      const resAjie = gameAjie.choose('d29_pm_invitation', 'invitation', 'invite_ajie', 'npc_ajie');
      expect(resAjie.ok).toBe(true);
      expect(gameAjie.getSnapshot().run.selected_festival_proxy_npc).toBe('ajie');
      expect(gameAjie.getSnapshot().run.flags.invited_ajie).toBe(true);

      // 邀阿薇（門檻：relation_at_least 恩人，對應數值 >= 40）
      const snapAwei = injectTrustedSnapshot(29, 'afternoon', (s) => {
        s.run.hand.push('npc_awei');
        s.run.relations.awei = 40;
      });
      const gameAwei = createGame(data, snapAwei);
      const resAwei = gameAwei.choose('d29_pm_invitation', 'invitation', 'invite_awei', 'npc_awei');
      expect(resAwei.ok).toBe(true);
      expect(gameAwei.getSnapshot().run.selected_festival_proxy_npc).toBe('awei');
      expect(gameAwei.getSnapshot().run.flags.invited_awei).toBe(true);
    });

    it('最高投入結算：全零 fallback、高者勝、同分取 npcs.json 來源陣列序、非候選 NPC 忽略', () => {
      // 1. 全零 fallback -> 'ajie'
      const plan0 = planEffects(
        [{ festival_proxy: { mode: 'highest_eligible', fallback: 'ajie' } }],
        injectTrustedSnapshot(29, 'afternoon'),
        data,
      );
      expect(plan0.ok).toBe(true);
      expect(plan0.nextState.run.selected_festival_proxy_npc).toBe('ajie');

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

    it('非法值與重複凍結原子拒絕（serialize 逐字一致）', () => {
      const snap = injectTrustedSnapshot(29, 'afternoon');
      const originalSerialized = JSON.stringify(snap);

      // 1. 已凍結後再次套用（包含相同 id）皆以 data_conflict 拒絕
      const frozenSnap = injectTrustedSnapshot(29, 'afternoon', (s) => {
        s.run.selected_festival_proxy_npc = 'ajie';
      });
      const frozenSerialized = JSON.stringify(frozenSnap);

      // 再次凍結相同 id -> data_conflict
      const planDupSame = planEffects(
        [{ festival_proxy: { mode: 'fixed', npc: 'ajie' } }],
        frozenSnap,
        data,
      );
      expect(planDupSame.ok).toBe(false);
      expect(planDupSame.reason_code).toBe('data_conflict');
      expect(JSON.stringify(planDupSame.nextState)).toBe(frozenSerialized);

      // 再次凍結不同 id -> data_conflict
      const planDupDiff = planEffects(
        [{ festival_proxy: { mode: 'fixed', npc: 'awei' } }],
        frozenSnap,
        data,
      );
      expect(planDupDiff.ok).toBe(false);
      expect(planDupDiff.reason_code).toBe('data_conflict');
      expect(JSON.stringify(planDupDiff.nextState)).toBe(frozenSerialized);

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

    it('D29 凍結後追加投入不重算：D31、D39 與 ending 快照維持凍結值', () => {
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
      afterSnap.run.day = 31;
      afterSnap.run.phase = 'morning';

      // D31 condition: festival_proxy_is ajie 成立，awei 不成立
      expect(evalCondition({ festival_proxy_is: 'ajie' }, afterSnap, data)).toBe(true);
      expect(evalCondition({ festival_proxy_is: 'awei' }, afterSnap, data)).toBe(false);

      // D39
      afterSnap.run.day = 39;
      expect(evalCondition({ festival_proxy_is: 'ajie' }, afterSnap, data)).toBe(true);
      expect(evalCondition({ festival_proxy_is: 'awei' }, afterSnap, data)).toBe(false);
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

      // 4. 未結算 coda 時 phase_exit 門檻阻擋離場
      expect(game.getPhaseView().can_advance).toBe(false);
      const beforeCoda = JSON.stringify(game.serialize());
      const advNoCoda = game.advancePhase();
      expect(advNoCoda.ok).toBe(false);
      expect(advNoCoda.reason_code).toBe('phase_requirements_incomplete');
      expect(JSON.stringify(game.serialize())).toBe(beforeCoda);

      // 5. 走 empty_handed 路線結算 coda
      const chooseCoda = game.choose('d45_then', 'd45_coda', 'empty_handed');
      expect(chooseCoda.ok).toBe(true);
      expect(game.getSnapshot().run.choices['d45_then::d45_coda']).toBe('empty_handed');

      // 門檻已滿足，can_advance 為 true
      expect(game.getPhaseView().can_advance).toBe(true);

      // 6. advancePhase 啟動 ending_replaced 結局
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

    it('持名冊路線（compare_registry）：比對升級知識卡並進入 ending_replaced', () => {
      const snapD45Eve = injectTrustedSnapshot(45, 'evening', (s) => {
        s.run.flags.final_day = true;
        s.run.selected_festival_proxy_npc = 'awei';
        s.run.hand.push('info_registry');
      });
      const game = createGame(data, snapD45Eve);

      // 結算 compare_registry
      const chooseRes = game.choose(
        'd45_then',
        'd45_coda',
        'compare_registry',
        'info_registry',
      );
      expect(chooseRes.ok).toBe(true);

      // 比對效果：獲得升級卡 k_already_on_list，失去 k_not_today
      expect(game.hasKnowledge('k_already_on_list')).toBe(true);
      expect(game.hasKnowledge('k_not_today')).toBe(false);

      // 推進進入 ending_replaced
      const advRes = game.advancePhase();
      expect(advRes.ok).toBe(true);
      expect(advRes.phase_advanced).toBe(false);
      expect(game.getSnapshot().flow.mode).toBe('ending');
      expect(game.getSnapshot().flow.active_ending?.festival_proxy_npc).toBe('awei');
    });

    it('D45 結局時缺少凍結代付者：原子拒絕（data_conflict），逾期預設記帳整筆復原', () => {
      const snapMissingProxy = injectTrustedSnapshot(45, 'evening', (s) => {
        s.run.flags.final_day = true;
        s.run.selected_festival_proxy_npc = null; // 缺少凍結代付者
        s.run.choices['d45_then::d45_coda'] = 'empty_handed';
        s.run.slots_placed['d45_then::empty_handed'] = true;
      });
      const game = createGame(data, snapMissingProxy);
      const beforeJson = JSON.stringify(game.serialize());

      expect(game.getPhaseView().can_advance).toBe(false);
      const advRes = game.advancePhase();
      expect(advRes.ok).toBe(false);
      expect(advRes.reason_code).toBe('data_conflict');
      expect(JSON.stringify(game.serialize())).toBe(beforeJson);
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
