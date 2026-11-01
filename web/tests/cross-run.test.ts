/**
 * ReturnFare Web — W6-E2-2 跨輪與重新開局整合測試。
 */

import { beforeAll, describe, expect, it } from 'vitest';
import {
  ENDING_REFUSE_BOARDING,
  ENDING_REPLACED,
  RETURNED_KNOWLEDGE_CARD,
  startEndingOnDraft,
} from '../src/core/ending';
import { MADNESS_CAP_ENDING_ID, madnessCardCount } from '../src/core/madness';
import {
  createEmptyRunState,
  createInitialSnapshot,
  initializeRun,
} from '../src/core/run-initialization';
import { createGame } from '../src/core/state';
import type {
  DeepReadonly,
  EndingHistoryRecord,
  Game,
  GameSnapshot,
} from '../src/core/state-types';
import { loadGameDataNode } from '../src/data/load-node';
import type { GameData } from '../src/data/types';

const ENDING_MADNESS_BE = MADNESS_CAP_ENDING_ID;
const ENDING_INVENTORY_BE = 'ending_inventory_be';

describe('W6-E2-2 cross-run & reset integration tests', () => {
  let data: GameData;

  beforeAll(async () => {
    data = await loadGameDataNode();

    // 驗證測試所用之全部真實 ID 均存在於資料型錄中，絕無捏造
    expect(data.cardsById.has('protagonist')).toBe(true);
    expect(data.cardsById.has('info_ahong_traces')).toBe(true);
    expect(data.cardsById.has('item_family_album')).toBe(true);
    expect(data.cardsById.has('k_town_covers')).toBe(true);
    expect(data.cardsById.has('k_not_today')).toBe(true);
    expect(data.cardsById.has(RETURNED_KNOWLEDGE_CARD)).toBe(true);
    expect(data.locationsById.has('n_corridor')).toBe(true);
    expect(data.locationsById.has('n_ahong_1')).toBe(true);
    expect(data.locationsById.has('bathhouse')).toBe(true);
    expect(data.locationsById.has('oldstreet')).toBe(true);
    expect(data.beatsById.has('n_corridor_ch1')).toBe(true);
    expect(data.beatsById.has('d1_morning_departure')).toBe(true);
    expect(data.beatsById.has('d45_then')).toBe(true);
    expect(data.beatsById.has('d45_encounter')).toBe(true);
  });

  /** 依 endingView 頁數上限翻完全部頁面直到 ready_to_complete。 */
  function playThroughEnding(game: Game): void {
    const pageCount = game.endingView().page_count;
    expect(pageCount).toBeGreaterThan(0);
    const maxSteps = pageCount * 2 + 2;
    for (let step = 0; step < maxSteps; step += 1) {
      const view = game.endingView();
      if (view.can_complete) return;
      if (!view.page_revealed) {
        const rev = game.revealEndingPage();
        expect(rev.ok).toBe(true);
      } else if (!view.is_last_page) {
        const adv = game.advanceEndingPage();
        expect(adv.ok).toBe(true);
      } else {
        break;
      }
    }
    expect(game.endingView().can_complete).toBe(true);
  }

  /** 建立縮短至可信 D45 evening 的快照，嚴格延續傳入的 meta。 */
  function createD45EveningGame(previousGame: Game, proxyNpc: string): Game {
    const prevSnap = previousGame.getSnapshot();
    expect(prevSnap.run.opening_choice_id).toBeTruthy();
    const d45Snap: GameSnapshot = {
      flow: {
        mode: 'run',
        active_ending: null,
      },
      run: {
        ...createEmptyRunState(),
        day: 45,
        phase: 'evening',
        hand: ['protagonist'],
        flags: {
          final_day: true,
          invited_none: true,
        },
        choices: {
          'd29_pm_invitation::invitation': 'invite_none',
        },
        slots_placed: {
          'd29_pm_invitation::invite_none': true,
        },
        selected_festival_proxy_npc: proxyNpc,
        opening_choice_id: prevSnap.run.opening_choice_id,
        knowledge_at_start: { ...prevSnap.meta.knowledge },
      },
      meta: structuredClone(prevSnap.meta as GameSnapshot['meta']),
    };
    return createGame(data, d45Snap);
  }

  interface MetaContract {
    runNumber: number;
    historyLength: number;
    latestEndingId: string;
    expectedKnowledge: readonly string[];
    expectedNightSeen: readonly string[];
    expectedNightOnceSeen: readonly string[];
    expectedDayVisited: readonly string[];
    delegationTutorialSeen: boolean;
    expectedPersistentItems: readonly string[];
  }

  /** 集中斷言 completeEnding 收尾後的 meta 留存、run 重置與重複結算原子拒絕。 */
  function assertCloseOutAndMeta(
    game: Game,
    priorHistory: readonly DeepReadonly<EndingHistoryRecord>[],
    contract: MetaContract,
  ): readonly DeepReadonly<EndingHistoryRecord>[] {
    const snap = game.getSnapshot();
    // 1. flow 狀態回歸開局
    expect(snap.flow.mode).toBe('opening');
    expect(snap.flow.active_ending).toBeNull();

    // 2. run 狀態完整清空為乾淨初值
    expect(snap.run).toEqual(createEmptyRunState());

    // 3. meta 輪數與旗標遞增／保留
    expect(snap.meta.run_number).toBe(contract.runNumber);
    expect(snap.meta.delegation_tutorial_seen).toBe(contract.delegationTutorialSeen);

    // 4. 知識、到訪與持久項精確比對
    for (const k of contract.expectedKnowledge) {
      expect(snap.meta.knowledge[k]).toBe(true);
    }
    for (const loc of contract.expectedNightSeen) {
      expect(snap.meta.night_locations_seen[loc]).toBe(true);
    }
    for (const beat of contract.expectedNightOnceSeen) {
      expect(snap.meta.night_once_beats_seen[beat]).toBe(true);
    }
    for (const loc of contract.expectedDayVisited) {
      expect(snap.meta.day_locations_visited[loc]).toBe(true);
    }
    for (const item of contract.expectedPersistentItems) {
      expect(snap.meta.loop_persistent_item_ids[item]).toBe(true);
    }

    // 5. 歷史記錄：嚴格保留原有前綴，且恰好追加一筆新記錄
    expect(snap.meta.ending_history).toHaveLength(contract.historyLength);
    for (let i = 0; i < priorHistory.length; i += 1) {
      expect(snap.meta.ending_history[i]).toEqual(priorHistory[i]);
    }
    const latest = snap.meta.ending_history[snap.meta.ending_history.length - 1];
    expect(latest.ending_id).toBe(contract.latestEndingId);
    expect(latest.run_number).toBe(contract.runNumber - 1);

    // 6. 重複呼叫 completeEnding 必須拒絕，且序列化位元組完全一致（0 副作用）
    const beforeDup = JSON.stringify(game.serialize());
    const dupRes = game.completeEnding();
    expect(dupRes.ok).toBe(false);
    expect(dupRes.reason_code).toBe('not_ending');
    expect(JSON.stringify(game.serialize())).toBe(beforeDup);

    return snap.meta.ending_history;
  }

  it('連續跨輪矩陣：同一份延續 meta 歷經 BE -> 正常長版 -> 不上車 -> 重見正常短版', () => {
    const cap = Number(data.tuning.madness_cap);
    const countdown = Number(data.tuning.madness_countdown_days);
    expect(cap).toBeGreaterThan(0);
    expect(countdown).toBeGreaterThan(0);
    const initialMadnessCount = cap - 1;

    // ── 1. Run 1: 發狂 BE（從可信 Day 6 Night 經真實 enterNightLocation 撞 cap 觸發） ──
    const run1Init = createInitialSnapshot();
    // 預先填充非空 meta 欄位以供整輪保留比對
    run1Init.meta.knowledge['k_town_covers'] = true;
    run1Init.meta.night_locations_seen['n_corridor'] = true;
    run1Init.meta.night_once_beats_seen['n_corridor_ch1'] = true;
    run1Init.meta.day_locations_visited['bathhouse'] = true;
    run1Init.meta.day_locations_visited['oldstreet'] = true;
    run1Init.meta.delegation_tutorial_seen = true;
    run1Init.meta.run_number = 1;
    run1Init.meta.ending_history = [];

    // 動態建構初始發狂卡清單與計時器，卡片實例數嚴格為 cap - 1
    const hand: string[] = ['protagonist', 'info_ahong_traces'];
    const madnessClock: Record<string, number> = {};
    for (let i = 1; i <= initialMadnessCount; i += 1) {
      const cardId = `madness#${i}`;
      hand.push(cardId);
      madnessClock[cardId] = countdown;
    }

    // 填充待重置之 dirty run 欄位（覆蓋 beats_entered, switches, switch_progress, forced_pending 等）
    run1Init.flow.mode = 'run';
    run1Init.run = {
      ...run1Init.run,
      day: 6,
      phase: 'night',
      opening_choice_id: 'take_family_album',
      hand,
      madness_clock: madnessClock,
      _madness_counter: initialMadnessCount,
      beats_entered: { d1_morning_departure: true },
      switches: { s1: true },
      switch_progress: { s1: 2 },
      forced_pending: ['madness#1'],
      flags: { test_flag: true },
      choices: { 'd29_pm_invitation::invitation': 'invite_none' },
      slots_placed: { 'd29_pm_invitation::invite_none': true },
      relations: { ajie: 3 },
      npc_action_counts: { ajie: 2 },
      action_spent: true,
      actions_spent_ahead: 1,
      indulgence_count: 2,
      madness_cards_cleared: 1,
      delegates_used_today: { ahong: true },
      pending_delegation_reports: [
        { due_day: 7, beat_id: 'd07_am_farm', slot_id: 'work', person_id: 'ahong' },
      ],
      knowledge_at_start: { ...run1Init.meta.knowledge },
    };

    const game = createGame(data, run1Init);
    expect(madnessCardCount(game.getSnapshot())).toBe(initialMadnessCount);

    // 透過正式夜間生命週期 API 進入收費地點 n_ahong_1 (earliest: 6, madness_cost: 1)
    const enterRes = game.enterNightLocation('n_ahong_1');
    expect(enterRes.ok).toBe(true);

    // 斷言由 madness_cap 觸發 ending_madness_be，手牌發狂卡實例恰達 cap
    const run1Ending = game.getSnapshot().flow.active_ending;
    expect(run1Ending?.source_id).toBe('madness_cap');
    expect(run1Ending?.ending_id).toBe(ENDING_MADNESS_BE);
    expect(madnessCardCount(game.getSnapshot())).toBe(cap);
    expect(game.getSnapshot().flow.mode).toBe('ending');

    // BE 排除複製品後日談頁面：僅含自身線性頁面，不含 variant_groups 或 lookup_fragments
    for (const ref of run1Ending!.page_refs) {
      expect(ref.startsWith('ending_madness_be/')).toBe(true);
      expect(ref.includes('variant_groups')).toBe(false);
      expect(ref.includes('lookup_fragments')).toBe(false);
    }
    expect(game.endingView().can_skip).toBe(false);

    // 未播完嘗試結算必須原子拒絕，且序列化完全一致
    const beforePremature = JSON.stringify(game.serialize());
    const prematureComplete = game.completeEnding();
    expect(prematureComplete.ok).toBe(false);
    expect(prematureComplete.reason_code).toBe('not_ready');
    expect(JSON.stringify(game.serialize())).toBe(beforePremature);

    playThroughEnding(game);

    const complete1 = game.completeEnding();
    expect(complete1.ok).toBe(true);

    // 斷言 Run 1 結算後的 Run 清空與 Meta 保留（獲得跨輪卡 k_i_returned）
    let historyAcc = assertCloseOutAndMeta(game, [], {
      runNumber: 2,
      historyLength: 1,
      latestEndingId: ENDING_MADNESS_BE,
      expectedKnowledge: ['k_town_covers', RETURNED_KNOWLEDGE_CARD],
      expectedNightSeen: ['n_corridor', 'n_ahong_1'],
      expectedNightOnceSeen: ['n_corridor_ch1'],
      expectedDayVisited: ['bathhouse', 'oldstreet'],
      delegationTutorialSeen: true,
      expectedPersistentItems: [],
    });

    const rec1 = historyAcc[0];
    expect(rec1.run_number).toBe(1);
    expect(rec1.opening_choice_id).toBe('take_family_album');
    expect(rec1.ended_day).toBe(6);
    expect(rec1.ended_phase).toBe('night');
    expect(rec1.partner_variant).toBeNull();
    expect(rec1.livelihood_variant).toBeNull();
    expect(rec1.inn_appearance_variant).toBeNull();
    expect(rec1.festival_proxy_npc).toBeNull();

    // 在開局畫面中，因尚未看過 ending_replaced，「不上車」維持鎖定
    const openingView1 = game.openingView();
    const refuseOpt1 = openingView1.find((o) => o.id === 'refuse_boarding');
    expect(refuseOpt1?.available).toBe(false);

    // ── 2. Run 2: 正常長版結局（選相簿開局，縮短至 D45 evening，走 coda 離場） ──
    const chooseAlbumRes = game.chooseOpening('take_family_album');
    expect(chooseAlbumRes.ok).toBe(true);
    expect(game.getSnapshot().flow.mode).toBe('run');
    expect(game.getSnapshot().run.hand[0]).toBe('protagonist');

    const game2 = createD45EveningGame(game, 'ajie');

    // 播放 coda 事件 d45_then，觸發 on_enter 獲得真實知識卡 k_not_today
    const playCodaRes = game2.playBeat('d45_then');
    expect(playCodaRes.ok).toBe(true);
    expect(game2.getSnapshot().run.flags.loop1_end).toBe(true);
    expect(game2.hasKnowledge('k_not_today')).toBe(true);

    // 未選 coda 選項時離場門檻阻擋推進
    expect(game2.getPhaseView().can_advance).toBe(false);
    expect(game2.advancePhase().ok).toBe(false);

    // 選擇 empty_handed 路線結算 coda
    expect(game2.choose('d45_then', 'd45_coda', 'empty_handed').ok).toBe(true);
    expect(game2.getPhaseView().can_advance).toBe(true);

    // 推進時段進入 ending_replaced
    expect(game2.advancePhase().ok).toBe(true);
    expect(game2.getSnapshot().flow.mode).toBe('ending');

    const run2Ending = game2.getSnapshot().flow.active_ending;
    expect(run2Ending?.ending_id).toBe(ENDING_REPLACED);
    expect(game2.hasSeenEnding(ENDING_REPLACED)).toBe(false);

    // 首見正常結局：不可跳過，嘗試 skipSeenEnding 必須拒絕且序列化完全一致
    expect(game2.endingView().can_skip).toBe(false);
    const beforeSkip = JSON.stringify(game2.serialize());
    const skipFail = game2.skipSeenEnding();
    expect(skipFail.ok).toBe(false);
    expect(skipFail.reason_code).toBe('ending_not_seen');
    expect(JSON.stringify(game2.serialize())).toBe(beforeSkip);

    // 驗證首見包含完整替換後日談（first_seen prefix 與 suffix 片段）
    expect(run2Ending!.page_refs[0]).toBe('ending_replaced/first_seen/prefix_pages/replacement');
    expect(run2Ending!.page_refs).toContain('ending_replaced/first_seen/suffix_pages/long_return');

    playThroughEnding(game2);

    expect(game2.completeEnding().ok).toBe(true);

    // 斷言 Run 2 結算後的 Run 清空與 Meta 保留（追加知識卡 k_not_today）
    historyAcc = assertCloseOutAndMeta(game2, historyAcc, {
      runNumber: 3,
      historyLength: 2,
      latestEndingId: ENDING_REPLACED,
      expectedKnowledge: ['k_town_covers', RETURNED_KNOWLEDGE_CARD, 'k_not_today'],
      expectedNightSeen: ['n_corridor', 'n_ahong_1'],
      expectedNightOnceSeen: ['n_corridor_ch1'],
      expectedDayVisited: ['bathhouse', 'oldstreet'],
      delegationTutorialSeen: true,
      expectedPersistentItems: [],
    });

    const rec2 = historyAcc[1];
    expect(rec2.run_number).toBe(2);
    expect(rec2.opening_choice_id).toBe('take_family_album');
    expect(rec2.ended_day).toBe(45);
    expect(rec2.ended_phase).toBe('evening');
    expect(rec2.partner_variant).toBe('none');
    expect(rec2.livelihood_variant).toBe('none_low');
    expect(rec2.inn_appearance_variant).toBe('none');
    expect(rec2.festival_proxy_npc).toBe('ajie');
    expect(rec2.knowledge_gained_this_run).toContain('k_not_today');

    // ── 3. Run 3: 不上車（refuse_boarding：因已看過 ending_replaced 而解鎖） ──
    const openingView2 = game2.openingView();
    const refuseOpt2 = openingView2.find((o) => o.id === 'refuse_boarding');
    expect(refuseOpt2?.available).toBe(true);

    // 選擇不上車：直接進結局，絕不初始化小鎮 run
    expect(game2.chooseOpening('refuse_boarding').ok).toBe(true);
    expect(game2.getSnapshot().flow.mode).toBe('ending');
    expect(game2.getSnapshot().run.hand).toEqual([]);
    expect(game2.getSnapshot().run.day).toBe(1);

    const run3Ending = game2.getSnapshot().flow.active_ending;
    expect(run3Ending?.ending_id).toBe(ENDING_REFUSE_BOARDING);

    for (const ref of run3Ending!.page_refs) {
      expect(ref.startsWith('ending_refuse_boarding/')).toBe(true);
      expect(ref.includes('variant_groups')).toBe(false);
      expect(ref.includes('lookup_fragments')).toBe(false);
    }

    playThroughEnding(game2);
    expect(game2.completeEnding().ok).toBe(true);

    // 斷言 Run 3 結算後的 Run 清空與 Meta 保留
    historyAcc = assertCloseOutAndMeta(game2, historyAcc, {
      runNumber: 4,
      historyLength: 3,
      latestEndingId: ENDING_REFUSE_BOARDING,
      expectedKnowledge: ['k_town_covers', RETURNED_KNOWLEDGE_CARD, 'k_not_today'],
      expectedNightSeen: ['n_corridor', 'n_ahong_1'],
      expectedNightOnceSeen: ['n_corridor_ch1'],
      expectedDayVisited: ['bathhouse', 'oldstreet'],
      delegationTutorialSeen: true,
      expectedPersistentItems: [],
    });

    const rec3 = historyAcc[2];
    expect(rec3.run_number).toBe(3);
    expect(rec3.opening_choice_id).toBe('refuse_boarding');
    expect(rec3.ended_day).toBeNull();
    expect(rec3.ended_phase).toBeNull();
    expect(rec3.partner_variant).toBeNull();
    expect(rec3.livelihood_variant).toBeNull();
    expect(rec3.inn_appearance_variant).toBeNull();
    expect(rec3.festival_proxy_npc).toBeNull();

    // ── 4. Run 4: 重見正常短版結局（電話開局，縮短至 D45 evening，驗證跳過至摘要） ──
    expect(game2.chooseOpening('return_missed_call').ok).toBe(true);

    const game4 = createD45EveningGame(game2, 'awei');
    game4.playBeat('d45_then');
    game4.choose('d45_then', 'd45_coda', 'empty_handed');

    expect(game4.advancePhase().ok).toBe(true);
    expect(game4.getSnapshot().flow.mode).toBe('ending');

    const run4Ending = game4.getSnapshot().flow.active_ending;
    expect(run4Ending?.ending_id).toBe(ENDING_REPLACED);
    expect(game4.hasSeenEnding(ENDING_REPLACED)).toBe(true);

    // 重見正常結局：提供跳過至 short_return
    expect(game4.endingView().can_skip).toBe(true);
    expect(game4.skipSeenEnding().ok).toBe(true);

    const skippedView = game4.endingView();
    expect(skippedView.page_revealed).toBe(true);
    expect(skippedView.is_last_page).toBe(true);
    expect(skippedView.can_complete).toBe(true);
    expect(run4Ending?.page_refs[skippedView.page_index]).toContain('short_return');

    expect(game4.completeEnding().ok).toBe(true);

    // 斷言 Run 4 結算後的 Run 清空與 Meta 保留
    historyAcc = assertCloseOutAndMeta(game4, historyAcc, {
      runNumber: 5,
      historyLength: 4,
      latestEndingId: ENDING_REPLACED,
      expectedKnowledge: ['k_town_covers', RETURNED_KNOWLEDGE_CARD, 'k_not_today'],
      expectedNightSeen: ['n_corridor', 'n_ahong_1'],
      expectedNightOnceSeen: ['n_corridor_ch1'],
      expectedDayVisited: ['bathhouse', 'oldstreet'],
      delegationTutorialSeen: true,
      expectedPersistentItems: [],
    });

    const rec4 = historyAcc[3];
    expect(rec4.run_number).toBe(4);
    expect(rec4.opening_choice_id).toBe('return_missed_call');
    expect(rec4.festival_proxy_npc).toBe('awei');
  });

  it('庫存 BE 規則層驗證與全量資料效果掃描：確認正式資料刻意無入口，且規則層結算合法', () => {
    // 1. 全量掃描正式資料所有型別效果位置（on_enter, on_place, on_place_by_level, encounter 各階段, choice.on_select），確認無 ending: ending_inventory_be
    function containsEnding(effect: unknown, target: string): boolean {
      if (!effect) return false;
      if (Array.isArray(effect)) {
        return effect.some((e) => containsEnding(e, target));
      }
      if (typeof effect === 'object' && effect !== null) {
        return (effect as Record<string, unknown>).ending === target;
      }
      return false;
    }

    for (const b of data.beats) {
      expect(containsEnding(b.on_enter, ENDING_INVENTORY_BE)).toBe(false);
      for (const slot of b.slots ?? []) {
        expect(containsEnding(slot.on_place, ENDING_INVENTORY_BE)).toBe(false);
        expect(containsEnding(slot.on_place_by_level?.light, ENDING_INVENTORY_BE)).toBe(false);
        expect(containsEnding(slot.on_place_by_level?.normal, ENDING_INVENTORY_BE)).toBe(false);
        expect(containsEnding(slot.on_place_by_level?.heavy, ENDING_INVENTORY_BE)).toBe(false);
      }
      if (b.encounter) {
        expect(containsEnding(b.encounter.on_victory, ENDING_INVENTORY_BE)).toBe(false);
        expect(containsEnding(b.encounter.on_failure, ENDING_INVENTORY_BE)).toBe(false);
        expect(containsEnding(b.encounter.on_escape, ENDING_INVENTORY_BE)).toBe(false);
        for (const round of b.encounter.rounds) {
          for (const resp of round.responses) {
            expect(containsEnding(resp.on_resolve, ENDING_INVENTORY_BE)).toBe(false);
          }
          expect(containsEnding(round.fallback.on_resolve, ENDING_INVENTORY_BE)).toBe(false);
        }
      }
    }
    for (const choice of data.openingChoices) {
      expect(containsEnding(choice.on_select, ENDING_INVENTORY_BE)).toBe(false);
      expect(choice.ending === ENDING_INVENTORY_BE).toBe(false);
    }

    // 2. 獨立收尾測試：使用完全真實的卡片與知識 ID，包含未結算之 active_encounter 進行重置測試
    const base = createInitialSnapshot();
    base.flow.mode = 'run';
    base.run.day = 15;
    base.run.phase = 'afternoon';
    base.run.opening_choice_id = 'take_family_album';
    base.run.hand = ['protagonist', 'info_ahong_traces'];
    base.run.active_encounter = { stage: 'intro', beat_id: 'd45_encounter' };
    base.run.flags = { loop1_end: true };
    base.meta.knowledge['k_town_covers'] = true;

    const started = startEndingOnDraft(
      base,
      ENDING_INVENTORY_BE,
      'ending_effect',
      data,
      { fromMode: 'run' },
    );
    expect(started.ok).toBe(true);

    const game = createGame(data, base);
    playThroughEnding(game);

    expect(game.completeEnding().ok).toBe(true);

    const snap = game.getSnapshot();
    expect(snap.flow.mode).toBe('opening');
    expect(snap.meta.ending_history).toHaveLength(1);
    const rec = snap.meta.ending_history[0];
    expect(rec.ending_id).toBe(ENDING_INVENTORY_BE);
    expect(rec.ended_day).toBe(15);
    expect(rec.ended_phase).toBe('afternoon');
    expect(rec.partner_variant).toBeNull();
    expect(rec.livelihood_variant).toBeNull();
    expect(rec.inn_appearance_variant).toBeNull();
    expect(rec.festival_proxy_npc).toBeNull();
    expect(snap.meta.knowledge[RETURNED_KNOWLEDGE_CARD]).toBe(true);
    expect(snap.meta.knowledge['k_town_covers']).toBe(true);
    expect(snap.run).toEqual(createEmptyRunState());
    expect(snap.run.active_encounter).toEqual({});
  });

  it('D45 coda -> ending -> complete -> opening -> chooseOpening -> D1 端到端生命週期流轉（完全未修改正式資料）', () => {
    const base = createInitialSnapshot();
    base.flow.mode = 'run';
    base.run = {
      ...base.run,
      day: 45,
      phase: 'evening',
      hand: ['protagonist'],
      flags: { final_day: true, invited_none: true },
      choices: { 'd29_pm_invitation::invitation': 'invite_none' },
      slots_placed: { 'd29_pm_invitation::invite_none': true },
      selected_festival_proxy_npc: 'ajie',
      opening_choice_id: 'take_family_album',
    };

    const game = createGame(data, base);

    // 1. 播放 coda 並結算
    game.playBeat('d45_then');
    game.choose('d45_then', 'd45_coda', 'empty_handed');

    // 2. 推進進入結局
    expect(game.advancePhase().ok).toBe(true);
    expect(game.getSnapshot().flow.mode).toBe('ending');

    // 3. 翻頁並結算
    playThroughEnding(game);
    expect(game.completeEnding().ok).toBe(true);
    expect(game.getSnapshot().flow.mode).toBe('opening');

    // 4. 開局重新選擇相簿
    const chooseRes = game.chooseOpening('take_family_album');
    expect(chooseRes.ok).toBe(true);
    expect(chooseRes.lines.length).toBeGreaterThan(0);

    // 5. 成功重入 D1 morning
    const snapD1 = game.getSnapshot();
    expect(snapD1.flow.mode).toBe('run');
    expect(snapD1.run.day).toBe(1);
    expect(snapD1.run.phase).toBe('morning');
    expect(snapD1.run.hand[0]).toBe('protagonist');
    expect(snapD1.run.hand).toContain('item_family_album');
    expect(snapD1.run.opening_choice_id).toBe('take_family_album');
    expect(snapD1.run.beats_entered['d1_morning_departure']).toBe(true);

    // 6. 推進至 D1 afternoon
    const advD1 = game.advancePhase();
    expect(advD1.ok).toBe(true);
    expect(advD1.phase_advanced).toBe(true);
    expect(game.getSnapshot().run.day).toBe(1);
    expect(game.getSnapshot().run.phase).toBe('afternoon');
  });

  it('[Fixture Scope: 隔離跨輪物品生命週期] 驗證 loop_persistent_item_ids 在開輪恢復、結算保留與全輪清空契約', () => {
    // 建立合成夾具：將真實卡片 item_family_album 標記為跨輪物品
    const snap = createInitialSnapshot();
    snap.meta.loop_persistent_item_ids['item_family_album'] = true;
    snap.meta.run_number = 2;

    // 1. 開輪初始化時自動將 loop_persistent_item_ids 恢復至手牌
    const initialized = initializeRun(snap, data);
    expect(initialized.run.hand).toContain('protagonist');
    expect(initialized.run.hand).toContain('item_family_album');

    // 2. 模擬一輪中持有更多卡片後進入結局並結算
    initialized.flow.mode = 'run';
    initialized.run.day = 10;
    initialized.run.phase = 'morning';
    initialized.run.opening_choice_id = 'take_family_album';
    initialized.run.hand.push('info_ahong_traces');

    const started = startEndingOnDraft(
      initialized,
      ENDING_INVENTORY_BE,
      'ending_effect',
      data,
      { fromMode: 'run' },
    );
    expect(started.ok).toBe(true);

    const fixtureGame = createGame(data, initialized);
    playThroughEnding(fixtureGame);
    expect(fixtureGame.completeEnding().ok).toBe(true);

    // 3. 結算後 run 狀態清空，meta.loop_persistent_item_ids 完整保留
    const snapAfter = fixtureGame.getSnapshot();
    expect(snapAfter.run).toEqual(createEmptyRunState());
    expect(snapAfter.meta.loop_persistent_item_ids['item_family_album']).toBe(true);
    expect(snapAfter.meta.run_number).toBe(3);
  });
});
