import { describe, expect, it } from 'vitest';
import { loadGameDataNode } from '../src/data/load-node';
import type { Beat, Effect, GameData, Phase } from '../src/data/types';
import { planEffects } from '../src/core/effect';
import {
  MADNESS_CAP_ENDING_ID,
  MADNESS_CAP_SOURCE_ID,
  madnessCardCount,
  tickMadnessOnDraft,
} from '../src/core/madness';
import { createInitialSnapshot } from '../src/core/run-initialization';
import { createGame } from '../src/core/state';
import type { GameSnapshot } from '../src/core/state-types';
import { createRunForTrace } from '../src/core/trace-entry';

describe('W6-A madness clock, cap and vision', async () => {
  const data = await loadGameDataNode();
  const countdown = data.tuning.madness_countdown_days;
  const cap = data.tuning.madness_cap;

  /** 注入起點：正式 run 初始化為底，只改日期／時段（不是從開局自然走到）。 */
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

  function addMadness(snap: GameSnapshot, ids: Record<string, number>): void {
    for (const [id, days] of Object.entries(ids)) {
      snap.run.hand.push(id);
      snap.run.madness_clock[id] = days;
      snap.run._madness_counter = Math.max(
        snap.run._madness_counter,
        Number(id.split('#')[1]),
      );
    }
  }

  /** 在正式資料上加隔離 fixture beat（不寫回 data/，每個案例各自建立）。 */
  function withBeats(extra: Beat[]): GameData {
    const beats = [...data.beats, ...extra];
    return { ...data, beats, beatsById: new Map(beats.map((b) => [b.id, b])) };
  }

  const fixtureBeat = (id: string, on_enter: Effect): Beat => ({
    id,
    location: 'sanquan',
    when: { day: 10, phase: 'morning' },
    text: `fixture ${id}`,
    slots: [],
    on_enter,
  });

  it('每日只在進 morning 時 tick；當夜發的卡不倒數；各走各的鐘', () => {
    const game = createGame(
      data,
      injectAt(10, 'morning', (s) => addMadness(s, { 'madness#1': 5, 'madness#2': 3 })),
    );
    const clock = () => game.getSnapshot().run.madness_clock;
    expect(game.advancePhase().phase_advanced).toBe(true); // -> afternoon
    expect(game.advancePhase().phase_advanced).toBe(true); // -> evening
    expect(game.advancePhase().phase_advanced).toBe(true); // -> night
    expect(game.getSnapshot().run.phase).toBe('night');
    expect(clock()).toEqual({ 'madness#1': 5, 'madness#2': 3 }); // 白天與入夜都不倒數

    // 當夜才發的新卡：滿值，直到次日 morning 才與其他卡一起 −1
    expect(game.enterNightLocation('n_ahong_1').ok).toBe(true);
    expect(clock()).toEqual({ 'madness#1': 5, 'madness#2': 3, 'madness#3': countdown });
    expect(game.advancePhase().phase_advanced).toBe(true);
    expect(game.getSnapshot().run.phase).toBe('morning');
    expect(clock()).toEqual({
      'madness#1': 4,
      'madness#2': 2,
      'madness#3': countdown - 1,
    });
  });

  it('歸零 clamp 且不重複歸零；已處理過的 0 不會被再次入列', () => {
    const draft = createInitialSnapshot();
    draft.run.madness_clock = { a: 1, b: 2, c: 0 };
    expect(tickMadnessOnDraft(draft)).toEqual(['a']);
    expect(draft.run.madness_clock).toEqual({ a: 0, b: 1, c: 0 });
    expect(tickMadnessOnDraft(draft)).toEqual(['b']); // 只有剛歸零者回報
    expect(tickMadnessOnDraft(draft)).toEqual([]); // 之後 clamp 在 0，不重複回報
    expect(draft.run.madness_clock).toEqual({ a: 0, b: 0, c: 0 });

    // 走 Game：一張已是 0 且債已清（forced_pending 空）的卡，換日不再入列 forced，推進照常
    const game = createGame(
      data,
      injectAt(10, 'night', (s) => {
        s.run.night_location_chosen = 'n_exit';
        addMadness(s, { 'madness#1': 0 });
      }),
    );
    expect(game.advancePhase().phase_advanced).toBe(true);
    const now = game.getSnapshot();
    expect(now.run.madness_clock).toEqual({ 'madness#1': 0 });
    expect(now.run.forced_pending).toEqual([]);
  });

  it('剛歸零在換日 morning 自動結算強制縱慾（W6-B）', () => {
    const snap = injectAt(10, 'night', (s) => {
      s.run.night_location_chosen = 'n_exit';
      addMadness(s, { 'madness#1': 1 });
    });
    const game = createGame(data, snap);
    expect(game.getPhaseView().can_advance).toBe(true);
    const res = game.advancePhase();
    expect(res.ok).toBe(true);
    expect(res.phase_advanced).toBe(true);
    const after = game.getSnapshot();
    expect(after.run.day).toBe(11);
    expect(after.run.phase).toBe('morning');
    expect(after.run.action_spent).toBe(true);
    expect(after.run.forced_pending).toEqual([]);
    expect(after.run.hand.includes('madness#1')).toBe(false);
    expect(after.run.madness_clock['madness#1']).toBeUndefined();
    expect(after.run.madness_cards_cleared).toBe(1);
    expect(after.run.flags.binge_eaten).toBe(true); // exit_sanquan x_binge flag
    // 還沒到歸零（剩 2 天）則照常推進並倒數
    const ok = createGame(
      data,
      injectAt(10, 'night', (s) => {
        s.run.night_location_chosen = 'n_exit';
        addMadness(s, { 'madness#1': 2 });
      }),
    );
    expect(ok.advancePhase().phase_advanced).toBe(true);
    expect(ok.getSnapshot().run.madness_clock).toEqual({ 'madness#1': 1 });
  });

  it('cap 依手牌發狂卡實例數判斷；達 cap 只提出 madness_cap 請求，不達不提', () => {
    const runState = (hand: string[], clock: Record<string, number> = {}) => {
      const s = createInitialSnapshot();
      s.flow.mode = 'run';
      s.run.hand = ['protagonist', ...hand];
      s.run.madness_clock = clock;
      return s;
    };
    const instances = (n: number) => Array.from({ length: n }, (_, i) => `madness#${i + 1}`);
    const clockFor = (n: number) => Object.fromEntries(instances(n).map((id) => [id, countdown]));

    expect(madnessCardCount(runState(instances(3)))).toBe(3);
    const reach = planEffects([{ madness: 1 }], runState(instances(cap - 1), clockFor(cap - 1)), data);
    expect(reach.ok).toBe(true);
    expect(reach.endingRequest).toEqual({
      ending_id: MADNESS_CAP_ENDING_ID,
      source_id: MADNESS_CAP_SOURCE_ID,
    });
    // 直接 gain 發狂卡走同一個 primitive 與同一個 cap
    const viaGain = planEffects([{ gain: ['madness'] }], runState(instances(cap - 1), clockFor(cap - 1)), data);
    expect(viaGain.endingRequest?.source_id).toBe('madness_cap');
    // 少一張不提
    const short = planEffects([{ madness: 1 }], runState(instances(cap - 2), clockFor(cap - 2)), data);
    expect(short.endingRequest).toBeNull();
    // 只看手牌實例：時鐘鍵再多（視野門檻用）、手牌沒有就不算
    const staleClock = planEffects([{ madness: 1 }], runState([], clockFor(cap + 3)), data);
    expect(staleClock.ok).toBe(true);
    expect(staleClock.endingRequest).toBeNull();
    expect(MADNESS_CAP_ENDING_ID).toBe('ending_madness_be');
  });

  it('批次效果先完整 preflight，最後只派一個 ending request；與明示 ending 不同則整筆 data_conflict', () => {
    const state = createInitialSnapshot();
    state.flow.mode = 'run';
    state.run.hand = ['protagonist'];
    const original = JSON.stringify(state);

    // 多個區塊各自把數量推過 cap：只回一個請求，且之後的 lose 不會撤回已撞上的 cap
    const batch = planEffects(
      [{ madness: cap }, { gain: ['madness'] }, { lose: ['madness#1'] }, { madness: 2 }],
      state,
      data,
    );
    expect(batch.ok).toBe(true);
    expect(batch.endingRequest).toEqual({
      ending_id: MADNESS_CAP_ENDING_ID,
      source_id: MADNESS_CAP_SOURCE_ID,
    });
    expect(JSON.stringify(state)).toBe(original);

    // 同時明示另一個結局：兩個不同請求，整筆 data_conflict，零洩漏
    const conflict = planEffects(
      [{ text: '不該外洩', madness: cap }, { ending: 'ending_inventory_be' }],
      state,
      data,
    );
    expect(conflict.ok).toBe(false);
    expect(conflict.reason_code).toBe('data_conflict');
    expect(conflict.lines).toEqual([]);
    expect(conflict.endingRequest).toBeNull();
    expect(JSON.stringify(conflict.nextState)).toBe(original);

    // 走 Game 的完整交易：一個 beat 的 on_enter 一次發超過 cap 張，仍只啟動一次結局，而且所有卡都在手
    const fixtureData = withBeats([
      fixtureBeat('test_cap_batch', { madness: cap + 2 }),
      fixtureBeat('test_cap_conflict', { madness: cap, ending: 'ending_inventory_be' }),
    ]);
    const game = createGame(fixtureData, injectAt(10, 'morning'));
    const historyBefore = game.getSnapshot().meta.ending_history.length;
    expect(game.playBeat('test_cap_batch').ok).toBe(true);
    const now = game.getSnapshot();
    expect(now.flow.mode).toBe('ending');
    expect(now.flow.active_ending?.source_id).toBe('madness_cap');
    expect(now.run.hand.filter((c) => c.startsWith('madness#')).length).toBe(cap + 2);
    expect(now.run.beats_entered.test_cap_batch).toBe(true);
    expect(now.meta.ending_history.length).toBe(historyBefore);
    expect(game.playBeat('test_cap_batch').reason_code).toBe('not_run');

    const conflictGame = createGame(fixtureData, injectAt(10, 'morning'));
    const conflictBefore = JSON.stringify(conflictGame.serialize());
    const conflictRes = conflictGame.playBeat('test_cap_conflict');
    expect(conflictRes.ok).toBe(false);
    expect(conflictRes.reason_code).toBe('data_conflict');
    expect(JSON.stringify(conflictGame.serialize())).toBe(conflictBefore);
  });

  it('所有發狂來源共用同一個發卡 primitive：實例 id 連號、倒數與 madness_clock 一致', () => {
    const fixtureData = withBeats([
      fixtureBeat('test_madness_effect', { madness: 1 }),
      fixtureBeat('test_madness_gain', { gain: ['madness'] }),
    ]);
    const game = createGame(fixtureData, injectAt(6, 'night'));
    expect(game.enterNightLocation('n_ahong_1').ok).toBe(true); // 夜間標記收費
    expect(game.playBeat('test_madness_effect').ok).toBe(true); // madness 效果
    expect(game.playBeat('test_madness_gain').ok).toBe(true); // 直接 gain
    const snap = game.getSnapshot();
    expect(snap.run.hand).toEqual(['protagonist', 'madness#1', 'madness#2', 'madness#3']);
    expect(snap.run.madness_clock).toEqual({
      'madness#1': countdown,
      'madness#2': countdown,
      'madness#3': countdown,
    });
    expect(snap.run._madness_counter).toBe(3);
    expect(game.handView().map((c) => c.countdown)).toEqual([undefined, countdown, countdown, countdown]);
  });

  it('視野條件：D23 旅館夜的外溢內容隨發狂卡張數出現／消失（不顯示，不是灰掉）', () => {
    const threshold = data.tuning.madness_vision_threshold;
    expect(JSON.stringify(data.beatsById.get('d23_night_bleed')!.condition)).toContain(
      `"madness_at_least":${threshold}`,
    );
    const fixtureData = withBeats([
      fixtureBeat('test_gain_cards', { madness: threshold }),
      fixtureBeat('test_clear_one', { lose: ['madness#1'] }),
    ]);
    const game = createGame(fixtureData, injectAt(23, 'night'));
    const primary = () => game.resolvedNightContent('sanquan').primary?.id ?? null;
    const panelBeats = () => game.buildPanel('sanquan').beats.map((b) => b.id);
    expect(primary()).toBeNull();
    expect(panelBeats()).not.toContain('d23_night_bleed');

    expect(game.playBeat('test_gain_cards').ok).toBe(true);
    expect(primary()).toBe('d23_night_bleed'); // 剛好達門檻即出現且是 OPEN
    expect(game.buildPanel('sanquan').beats.find((b) => b.id === 'd23_night_bleed')?.tri).toBe(2);

    expect(game.playBeat('test_clear_one').ok).toBe(true); // 清掉一張，低於門檻又消失
    expect(game.getSnapshot().run.madness_cards_cleared).toBe(1);
    expect(primary()).toBeNull();
    expect(panelBeats()).not.toContain('d23_night_bleed');
  });
});
