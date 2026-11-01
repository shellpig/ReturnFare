import { describe, expect, it } from 'vitest';
import { loadGameDataNode } from '../src/data/load-node';
import type { GameData, Phase } from '../src/data/types';
import { TriState } from '../src/core/panel';
import { createGame } from '../src/core/state';
import type { Game, GameSnapshot } from '../src/core/state-types';
import { createRunForTrace } from '../src/core/trace-entry';
import { executeGreedyNightPhase } from './support/greedy';

const COUNTDOWN_KEY = 'madness_countdown_days';

describe('W6-A night locations, sleep and alignment', async () => {
  const data = await loadGameDataNode();
  const loc = (id: string) => data.locationsById.get(id)!;
  const countdown = data.tuning[COUNTDOWN_KEY];
  const cap = data.tuning.madness_cap;

  /**
   * 注入起點：以正式 run 初始化（主角卡、乾淨 run 層）為底，只改日期與時段。
   * 這不是從開局自然走到該時段；自然走查另見「greedy 夜間走查」。
   */
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

  /** 加 N 張已在倒數的發狂卡（直接寫入起點，供 cap 邊界案例使用）。 */
  function withMadnessCards(snap: GameSnapshot, count: number): void {
    for (let i = 1; i <= count; i += 1) {
      snap.run.hand.push(`madness#${i}`);
      snap.run.madness_clock[`madness#${i}`] = countdown;
    }
    snap.run._madness_counter = count;
  }

  function expectRejectsWithoutChange(
    game: Game,
    act: () => { ok: boolean; reason_code: string; reason_text?: string },
    code: string,
  ) {
    const before = JSON.stringify(game.serialize());
    const res = act();
    expect(res.ok).toBe(false);
    expect(res.reason_code).toBe(code);
    expect(JSON.stringify(game.serialize())).toBe(before);
    return res;
  }

  it('注入 D6 起點：n_ahong_1 進入 → 發卡 → advancePhase() 換日並第一次倒數', () => {
    const snap = injectAt(6, 'night');
    // 起點前置：尚未 seen／chosen／slept、未超載、無其他發狂卡與 forced 待辦、不會撞 cap
    expect(snap.meta.night_locations_seen).toEqual({});
    expect(snap.run.night_location_chosen).toBe('');
    expect(snap.run.night_sleep_pending).toBe(false);
    expect(snap.run.hand).toEqual(['protagonist']);
    expect(snap.run.madness_clock).toEqual({});
    expect(snap.run.forced_pending).toEqual([]);
    const cost = loc('n_ahong_1').madness_cost!;
    expect(cost).toBeGreaterThan(0);
    expect(cost).toBeLessThan(cap);

    const game = createGame(data, snap);
    // 開詳情（摘要＋解析＋面板）都是純查詢
    const beforeOpen = JSON.stringify(game.serialize());
    const summary = game.nightLocationSummary('n_ahong_1');
    expect(summary.can_enter).toBe(true);
    expect(summary.status_text).toBe('[尚未到訪]');
    expect(summary.warning).toBe('');
    expect(game.resolvedNightContent('n_ahong_1').primary?.id).toBe('n_ahong_1_ch1');
    game.buildPanel('n_ahong_1');
    expect(JSON.stringify(game.serialize())).toBe(beforeOpen);

    const res = game.enterNightLocation('n_ahong_1');
    expect(res.ok).toBe(true);
    expect(res.lines).toEqual([`推開了夜色深處的門。獲得 ${cost} 張發狂卡。`]);
    let now = game.getSnapshot();
    expect(now.run.night_location_chosen).toBe('n_ahong_1');
    expect(now.meta.night_locations_seen).toEqual({ n_ahong_1: true });
    expect(now.run.hand).toEqual(['protagonist', 'madness#1']);
    expect(now.run.madness_clock).toEqual({ 'madness#1': countdown });
    expect(game.handSlotsUsed()).toBe(2);

    // 進入後面板可播 OPEN beat，on_enter 發資訊卡（效果自己的帳）
    const panel = game.buildPanel('n_ahong_1');
    expect(panel.beats.map((b) => [b.id, b.tri])).toEqual([['n_ahong_1_ch1', TriState.OPEN]]);
    expect(game.playBeat('n_ahong_1_ch1').ok).toBe(true);
    expect(game.getSnapshot().run.hand).toContain('info_ahong_traces');

    // 當夜不倒數；advancePhase() 換日（已選地點不再睡一次）後 morning tick 一次
    expect(game.getPhaseView().night_advance).toBe('end_night');
    const adv = game.advancePhase();
    expect(adv.ok).toBe(true);
    expect(adv.phase_advanced).toBe(true);
    now = game.getSnapshot();
    expect(now.run.day).toBe(7);
    expect(now.run.phase).toBe('morning');
    expect(now.run.madness_clock).toEqual({ 'madness#1': countdown - 1 });
    expect(now.run.night_location_chosen).toBe('');
    expect(now.run.forced_pending).toEqual([]);
  });

  it('重訪已 seen 的收費 row 免費，但 beat 自己的效果仍照套；免費 row 也記到訪並用掉今晚', () => {
    const snap = injectAt(6, 'night', (s) => {
      s.meta.night_locations_seen.n_ahong_1 = true;
    });
    const game = createGame(data, snap);
    expect(game.nightLocationSummary('n_ahong_1').status_text).toBe('[已到訪]');
    const res = game.enterNightLocation('n_ahong_1');
    expect(res.ok).toBe(true);
    expect(res.lines).toEqual([]);
    expect(game.getSnapshot().run.hand).toEqual(['protagonist']);
    expect(game.getSnapshot().run.madness_clock).toEqual({});
    expect(game.getSnapshot().run.night_location_chosen).toBe('n_ahong_1');
    // 免費不等於 beat 沒有效果：on_enter 仍發一次資訊卡
    expect(game.playBeat('n_ahong_1_ch1').ok).toBe(true);
    expect(game.getSnapshot().run.hand).toEqual(['protagonist', 'info_ahong_traces']);

    // madness_cost 為 0 的 row：不發卡、記到訪、用掉今晚，且不產生「免費」文字
    const free = createGame(data, injectAt(6, 'night'));
    const freeRes = free.enterNightLocation('n_woodtags');
    expect(loc('n_woodtags').madness_cost).toBe(0);
    expect(freeRes.ok).toBe(true);
    expect(freeRes.lines).toEqual([]);
    expect(free.getSnapshot().meta.night_locations_seen.n_woodtags).toBe(true);
    expect(free.getSnapshot().run.night_location_chosen).toBe('n_woodtags');
    expect(free.getSnapshot().run.hand).toEqual(['protagonist']);
  });

  it('睡覺固定內容：停拍後不能再進地點，第二次推進才換日；已選地點則不再睡', () => {
    const sleepSnap = () =>
      injectAt(23, 'night', (s) => {
        s.run.flags.typhoon_secured = true;
      });
    const bleed = data.beatsById.get('d23_night_bleed')!;
    const game = createGame(data, sleepSnap());
    expect(game.resolvedNightContent('sanquan').primary?.id).toBe('d23_night_bleed');
    expect(game.getPhaseView().night_advance).toBe('sleep');

    const first = game.advancePhase();
    expect(first.ok).toBe(true);
    expect(first.phase_advanced).toBe(false);
    expect(first.lines).toEqual([bleed.text]);
    let now = game.getSnapshot();
    expect(now.run.phase).toBe('night');
    expect(now.run.night_sleep_pending).toBe(true);
    expect(now.run.beats_entered.d23_night_bleed).toBe(true);
    expect(now.run.flags.boundary_bleeding).toBe(true);
    expect(game.getPhaseView().night_advance).toBe('next_day');
    expect(game.getPhaseView().lines).toEqual([bleed.text]);

    // 睡覺停拍之後：進地點被拒（零變化），摘要也一致顯示不可進
    expectRejectsWithoutChange(game, () => game.enterNightLocation('n_emptyspot'), 'already_slept');
    expect(game.nightLocationSummary('n_emptyspot').can_enter).toBe(false);
    expect(game.nightLocationSummary('n_emptyspot').reason_code).toBe('already_slept');

    const second = game.advancePhase();
    expect(second.ok).toBe(true);
    expect(second.phase_advanced).toBe(true);
    now = game.getSnapshot();
    expect([now.run.day, now.run.phase]).toEqual([24, 'morning']);
    expect(now.run.night_sleep_pending).toBe(false);

    // 已選地點：直接換日，不再解析睡覺（旗標不會被睡覺內容寫入）
    const chosen = createGame(data, sleepSnap());
    expect(chosen.enterNightLocation('n_emptyspot').ok).toBe(true);
    const adv = chosen.advancePhase();
    expect(adv.phase_advanced).toBe(true);
    expect(adv.lines).toEqual([]);
    expect(chosen.getSnapshot().run.flags.boundary_bleeding).toBeUndefined();

    // 無睡覺內容：一次就換日
    const quiet = createGame(data, injectAt(5, 'night'));
    expect(quiet.advancePhase().phase_advanced).toBe(true);
    expect(quiet.getSnapshot().run.day).toBe(6);
  });

  it('teaser 一律拒絕：摘要顯示資料理由、不可進、零變化', () => {
    const game = createGame(data, injectAt(40, 'night'));
    expect(game.availableLocations()).toContain('n_corridor_end');
    const summary = game.nightLocationSummary('n_corridor_end');
    expect(summary.teaser_only).toBe(true);
    expect(summary.can_enter).toBe(false);
    expect(summary.reason_code).toBe('teaser');
    expect(summary.reason_text).toBe(loc('n_corridor_end').reject_reason);
    expect(summary.status_text).toBe('[尚未到訪]');
    expectRejectsWithoutChange(game, () => game.enterNightLocation('n_corridor_end'), 'teaser');
    // 第二章還看不到 teaser
    const early = createGame(data, injectAt(32, 'night'));
    expect(early.availableLocations()).not.toContain('n_corridor_end');
  });

  it('首訪撞發狂上限：到訪仍保留、啟動 madness_cap 結局，不再播原面板', () => {
    const snap = injectAt(6, 'night', (s) => withMadnessCards(s, cap - 1));
    const game = createGame(data, snap);
    // 風險警告是不帶數字的純 preflight，且不實際發卡
    const beforeSummary = JSON.stringify(game.serialize());
    expect(game.nightLocationSummary('n_ahong_1').warning).toBe('再往前，你可能回不來。');
    expect(game.nightLocationSummary('n_woodtags').warning).toBe('');
    expect(JSON.stringify(game.serialize())).toBe(beforeSummary);

    const res = game.enterNightLocation('n_ahong_1');
    expect(res.ok).toBe(true);
    expect(res.lines).toEqual([]); // 會結束本輪就不附「獲得發狂卡」提示
    const now = game.getSnapshot();
    expect(now.flow.mode).toBe('ending');
    expect(now.flow.active_ending?.source_id).toBe('madness_cap');
    expect(now.flow.active_ending?.ending_id).toBe('ending_madness_be');
    expect(now.meta.night_locations_seen.n_ahong_1).toBe(true);
    expect(now.run.night_location_chosen).toBe('n_ahong_1');
    expect(now.run.hand.filter((c) => c.startsWith('madness#')).length).toBe(cap);
    // 進 ending 後不能繼續播原面板
    expect(game.playBeat('n_ahong_1_ch1').reason_code).toBe('not_run');
    expect(game.endingView().page_count).toBeGreaterThan(0);
  });

  it('進入拒絕矩陣：每個封閉碼各有案例，檢查順序固定，拒絕前後 serialize 逐字一致', () => {
    const reject = (
      snap: GameSnapshot,
      locationId: string,
      code: string,
      text?: string,
    ) => {
      const game = createGame(data, snap);
      const res = expectRejectsWithoutChange(game, () => game.enterNightLocation(locationId), code);
      if (text !== undefined) {
        expect(res.reason_text).toBe(text);
      }
    };

    // 模式與時段
    reject(createRunForTrace(data).serialize(), 'n_corridor', 'not_night');
    const opening = createGame(data);
    expectRejectsWithoutChange(opening, () => opening.enterNightLocation('n_corridor'), 'not_run');
    reject(injectAt(6, 'afternoon'), 'n_ahong_1', 'not_night');
    reject(
      injectAt(6, 'night', (s) => {
        s.run.active_encounter = { stage: 'intro', beat_id: 'x' };
      }),
      'n_ahong_1',
      'encounter_active',
    );
    // 超載（hand_size 之上）
    reject(
      injectAt(6, 'night', (s) => {
        s.run.hand = ['protagonist', ...Array(data.tuning.hand_size).fill('info_ahong_traces')];
      }),
      'n_ahong_1',
      'overloaded',
    );
    // 地點與門檻
    reject(injectAt(6, 'night'), 'no_such_place', 'unknown_location');
    reject(injectAt(6, 'night'), 'sanquan', 'not_night_layer');
    reject(injectAt(40, 'night'), 'n_corridor_end', 'teaser');
    reject(injectAt(5, 'night'), 'n_ahong_1', 'too_early');
    // too_early 先於 locked：D10 的 n_ahong_2 同時「時候未到」與「前一段沒走」
    reject(injectAt(10, 'night'), 'n_ahong_2', 'too_early');
    reject(injectAt(12, 'night'), 'n_ahong_2', 'locked', loc('n_ahong_2').reject_reason);
    // locked 先於 already_chosen；already_chosen 先於 already_slept
    reject(
      injectAt(12, 'night', (s) => {
        s.run.night_location_chosen = 'n_exit';
      }),
      'n_ahong_2',
      'locked',
    );
    reject(
      injectAt(6, 'night', (s) => {
        s.run.night_location_chosen = 'n_exit';
        s.run.night_sleep_pending = true;
      }),
      'n_ahong_1',
      'already_chosen',
    );
    reject(
      injectAt(6, 'night', (s) => {
        s.run.night_sleep_pending = true;
      }),
      'n_ahong_1',
      'already_slept',
    );
  });

  it('摘要：狀態文字、不顯示價碼、每項 can_enter 與 enter 一致；開詳情不改狀態', () => {
    const game = createGame(
      data,
      injectAt(12, 'night', (s) => {
        s.meta.night_locations_seen.n_ahong_1 = true;
        s.meta.night_locations_seen.n_woodtags = true;
      }),
    );
    const before = JSON.stringify(game.serialize());
    const ids = game.availableLocations();
    // 穩定排序：earliest_night 由早至晚，同夜照資料順序，且 D12 不含更晚的 row
    const order = data.locations.filter((l) => l.layer === 'night' && !l.teaser_only && (l.earliest_night ?? 999) <= 12);
    const expected = order
      .map((l, i) => ({ id: l.id, e: l.earliest_night!, i }))
      .sort((a, b) => a.e - b.e || a.i - b.i)
      .map((x) => x.id);
    expect(ids).toEqual(expected);

    const statusOf = (id: string) => game.nightLocationSummary(id).status_text;
    expect(statusOf('n_ahong_1')).toBe('[已到訪]'); // dc null
    expect(statusOf('n_woodtags')).toBe('[已到訪，尚未對位]');
    expect(statusOf('n_music')).toBe('[尚未到訪]');
    const lockedSummary = game.nightLocationSummary('n_ahong_2');
    expect(lockedSummary.can_enter).toBe(true); // 前一段已 seen
    for (const id of ids) {
      const s = game.nightLocationSummary(id);
      expect(JSON.stringify(s)).not.toContain('免費');
      expect(s.desc).toBe((loc(id).desc ?? '').trim());
    }
    expect(JSON.stringify(game.serialize())).toBe(before);

    // 每一項 summary.can_enter 與實際進入規則一致
    for (const id of ids) {
      const fresh = createGame(data, JSON.parse(before) as GameSnapshot);
      const canEnter = fresh.nightLocationSummary(id).can_enter;
      expect(fresh.enterNightLocation(id).ok, id).toBe(canEnter);
    }
    // 門檻不成立仍在清單、進入灰掉並附資料理由
    const early = createGame(data, injectAt(12, 'night'));
    const gate = early.nightLocationSummary('n_ahong_2');
    expect(gate.can_enter).toBe(false);
    expect(gate.reason_code).toBe('locked');
    expect(gate.reason_text).toBe(loc('n_ahong_2').reject_reason);
    expect(early.availableLocations()).toContain('n_ahong_2');
    // 今夜已選之後清單與排序不變，所有進入鍵都灰掉
    const afterEnter = createGame(data, injectAt(12, 'night'));
    const listBefore = afterEnter.availableLocations();
    expect(afterEnter.enterNightLocation('n_woodtags').ok).toBe(true);
    expect(afterEnter.availableLocations()).toEqual(listBefore);
    for (const id of listBefore) {
      expect(afterEnter.nightLocationSummary(id).can_enter).toBe(false);
    }
    expect(afterEnter.nightLocationSummary('n_music').reason_code).toBe('already_chosen');
  });

  it('夜間內容解析：定日優先、condition 退回、最近章節、requires 保持 LOCKED、addons 保序、無內容不是假 beat', () => {
    const idOf = (day: number, location: string, tweak?: (s: GameSnapshot) => void) => {
      const g = createGame(data, injectAt(day, 'night', tweak));
      return g.resolvedNightContent(location);
    };
    // 當日定日（n_queue_d24）優先於章節變體；D23 沒有當章版本，向下取最近的第一章；D43 為第三章定日版本
    expect(idOf(24, 'n_queue').primary?.id).toBe('n_queue_d24');
    expect(idOf(23, 'n_queue').primary?.id).toBe('n_queue_ch1');
    expect(idOf(43, 'n_queue').primary?.id).toBe('n_queue_ch3');
    expect(idOf(44, 'n_queue').primary?.id).toBe('n_queue_ch1');
    // 定日候選 condition 不成立時退回章節變體，成立才取定日
    expect(idOf(31, 'n_gathering').primary?.id).toBe('n_gathering_ch2');
    expect(
      idOf(31, 'n_gathering', (s) => {
        s.run.flags.saw_n_gathering_intro = true;
      }).primary?.id,
    ).toBe('n_gathering_d31');
    expect(idOf(34, 'n_gathering').primary?.id).toBe('n_gathering_ch3');
    // 附加 beat：只在 condition 成立時並列，且 primary 在前、保序
    expect(idOf(9, 'n_landmark').addons).toEqual([]);
    const withAddon = createGame(data, injectAt(10, 'night'));
    expect(withAddon.resolvedNightContent('n_landmark').addons.map((b) => b.id)).toEqual(['n_take_something']);
    expect(withAddon.buildPanel('n_landmark').beats.map((b) => b.id)).toEqual(['n_landmark_ch1', 'n_take_something']);
    // requires 不成立仍是被選中的 LOCKED 內容，不退回下一個版本
    const locked = createGame(
      data,
      injectAt(12, 'night', (s) => {
        s.meta.night_locations_seen.n_ahong_1 = true;
      }),
    );
    expect(locked.resolvedNightContent('n_ahong_2').primary?.id).toBe('n_ahong_2_ch1');
    const lockedBeat = locked.buildPanel('n_ahong_2').beats[0];
    expect(lockedBeat.id).toBe('n_ahong_2_ch1');
    expect(lockedBeat.tri).toBe(TriState.LOCKED);
    // 沒有任何內容的合法地點：回通用空結果旗標，不產生假 beat，進入照常記到訪
    const empty = createGame(data, injectAt(5, 'night'));
    expect(empty.resolvedNightContent('n_exit')).toEqual({ primary: null, addons: [] });
    expect(empty.buildPanel('n_exit').empty_result).toBe(true);
    expect(empty.buildPanel('n_exit').beats).toEqual([]);
    expect(empty.enterNightLocation('n_exit').ok).toBe(true);
    expect(empty.getSnapshot().meta.night_locations_seen.n_exit).toBe(true);
    expect(empty.getSnapshot().run.beats_entered).toEqual({});
    // 睡覺、面板與合法性用同一份：夜間 non-fixed beat 只有被解析選中的才能在槽上被處理
    const takeOk = createGame(data, injectAt(10, 'night'));
    expect(takeOk.previewSlot('n_take_something', 'take')).toEqual({ cards: ['protagonist'], reason: '' });
    const takeEarly = createGame(data, injectAt(9, 'night'));
    expect(takeEarly.previewSlot('n_take_something', 'take')).toEqual({ cards: [], reason: 'hidden' });
    expect(takeEarly.tryPlace('protagonist', 'n_take_something', 'take').reason_code).toBe('hidden');
  });

  it('入夜 fixed 與 meta_once：D1 強制到訪、跨輪不重播且不佔名額、D3 引導與 D15 免收費、D24 旅館演出不用掉今晚', () => {
    // D1 強制到訪：免費、記 chosen／seen／once
    const d1 = createGame(data, injectAt(1, 'night'));
    const d1Lines = d1.playNightFixed().lines;
    expect(d1Lines).toEqual([data.beatsById.get('n_corridor_ch1')!.text]);
    expect(d1.getSnapshot().run.night_location_chosen).toBe('n_corridor');
    expect(d1.getSnapshot().meta.night_once_beats_seen).toEqual({ n_corridor_ch1: true });
    expect(d1.enterNightLocation('n_exit').reason_code).toBe('too_early');
    // 第二輪（meta 保留、run 清空）：不再強播、不佔今晚，可正常自選，且免費
    const again = createGame(
      data,
      injectAt(1, 'night', (s) => {
        s.meta.night_locations_seen.n_corridor = true;
        s.meta.night_once_beats_seen.n_corridor_ch1 = true;
      }),
    );
    expect(again.playNightFixed().lines).toEqual([]);
    expect(again.getSnapshot().run.night_location_chosen).toBe('');
    expect(again.enterNightLocation('n_corridor').ok).toBe(true);
    // D3 環境引導掛在 sanquan（白天地點）：播一次、不算到訪、不用掉今晚
    const d3 = createGame(data, injectAt(3, 'night'));
    expect(d3.playNightFixed().lines.length).toBeGreaterThan(0);
    expect(d3.getSnapshot().run.night_location_chosen).toBe('');
    expect(d3.getSnapshot().meta.night_locations_seen).toEqual({});
    expect(d3.getSnapshot().meta.night_once_beats_seen.n3_map_opens).toBe(true);
    expect(d3.nightLocationSummary('n_queue').can_enter).toBe(true);
    // D15 強制到訪付費 row：不收 marker cost，之後主動再進一樣免費
    const d15 = createGame(data, injectAt(15, 'night'));
    expect(loc('n_plaza').madness_cost).toBeGreaterThan(0);
    expect(d15.playNightFixed().ok).toBe(true);
    expect(d15.getSnapshot().run.night_location_chosen).toBe('n_plaza');
    expect(d15.getSnapshot().run.hand).toEqual(['protagonist']);
    expect(d15.getSnapshot().run.madness_clock).toEqual({});
    const d16 = createGame(
      data,
      injectAt(16, 'night', (s) => {
        s.meta.night_locations_seen.n_plaza = true;
      }),
    );
    expect(d16.enterNightLocation('n_plaza').lines).toEqual([]);
    expect(d16.getSnapshot().run.hand).toEqual(['protagonist']);
    // D24 旅館 fixed 不 meta_once、不是 night-layer：不用掉今晚，還能再選一個地點
    const d24 = createGame(data, injectAt(24, 'night'));
    expect(d24.playNightFixed().ok).toBe(true);
    expect(d24.getSnapshot().run.beats_entered.d24_night_laozeng).toBe(true);
    expect(d24.getSnapshot().run.night_location_chosen).toBe('');
    expect(d24.enterNightLocation('n_queue').ok).toBe(true);
  });

  it('D8 charge_first_visit：首次強制到訪先收費；遭遇本身仍原子拒絕（W6-D），撞 cap 則進 BE', () => {
    // 遭遇未接：整筆拒絕，連收費也不留下
    const d8 = createGame(data, injectAt(8, 'night'));
    const rejected = expectRejectsWithoutChange(d8, () => d8.playNightFixed(), 'not_implemented');
    expect(rejected.reason_text).toContain('W6-D');
    // 前一時段進 D8 night 同樣在 mutation 前原子拒絕（遭遇由 W6-D 負責）
    const eve = createGame(data, injectAt(8, 'evening'));
    expect(eve.getPhaseView().can_advance).toBe(false);
    expectRejectsWithoutChange(eve, () => eve.advancePhase(), 'not_implemented');
    // 首次收費撞 cap：進 madness_cap 結局，不播 beat，到訪保留
    const capped = createGame(
      data,
      injectAt(8, 'night', (s) => withMadnessCards(s, cap - 1)),
    );
    expect(capped.playNightFixed().ok).toBe(true);
    const snap = capped.getSnapshot();
    expect(snap.flow.mode).toBe('ending');
    expect(snap.flow.active_ending?.source_id).toBe('madness_cap');
    expect(snap.meta.night_locations_seen.n_manydoors).toBe(true);
    expect(snap.run.beats_entered.n_manydoors_ch1).toBeUndefined();
    expect(snap.meta.night_once_beats_seen).toEqual({});
  });

  it('機制守衛：日期不再是守衛，仍未接的系統在 mutation 前原子拒絕', () => {
    // D3 之後的一般推進（含夜間換日）直接通過
    const d10 = createGame(data, injectAt(10, 'morning'));
    expect(d10.advancePhase().phase_advanced).toBe(true);
    const d20Night = createGame(
      data,
      injectAt(20, 'night', (s) => {
        s.run.night_location_chosen = 'n_exit';
      }),
    );
    expect(d20Night.advancePhase().phase_advanced).toBe(true);
    expect(d20Night.getSnapshot().run.day).toBe(21);

    const guards: [string, GameSnapshot][] = [
      ['預扣行動格', injectAt(10, 'morning', (s) => { s.run.actions_spent_ahead = 1; })],
      ['強制縱慾待辦', injectAt(10, 'morning', (s) => { s.run.forced_pending = ['madness#1']; })],
      [
        '委託隔日回報',
        injectAt(10, 'night', (s) => {
          s.run.night_location_chosen = 'n_exit';
          s.run.pending_delegation_reports = [
            { due_day: 11, beat_id: 'b', slot_id: 's', person_id: 'p' },
          ];
        }),
      ],
      [
        'D45 結局收束（phase_exit ending，E2）',
        injectAt(45, 'evening', (s) => {
          s.run.flags.final_day = true;
          s.run.choices['d45_then::d45_coda'] = 'empty_handed';
          s.run.slots_placed['d45_then::empty_handed'] = true;
        }),
      ],
    ];
    for (const [label, snap] of guards) {
      const game = createGame(data, snap);
      const before = JSON.stringify(game.serialize());
      expect(game.getPhaseView().can_advance, label).toBe(false);
      const res = game.advancePhase();
      expect(res.ok, label).toBe(false);
      expect(res.reason_code, label).toBe('not_implemented');
      expect(JSON.stringify(game.serialize()), label).toBe(before);
    }
  });

  it('對位：正確白天地點免費確認、共用 knowledge、多對一顯示、不增加佔格、已對位狀態純衍生', () => {
    const temple = loc('temple');
    const woodtags = loc('n_woodtags');
    const seenWoodtags = () =>
      injectAt(9, 'afternoon', (s) => {
        s.meta.night_locations_seen.n_woodtags = true;
      });
    const game = createGame(data, seenWoodtags());
    expect(game.nightLocationSummary('n_woodtags').status_text).toBe('[已到訪，尚未對位]');
    expect(game.nightLocationSummary('n_music').status_text).toBe('[尚未到訪]');
    const offer = game.alignmentOffer('temple');
    expect(offer).toEqual({ available: true, knowledge_id: 'k_night_temple', night_ids: ['n_woodtags'] });
    // 錯誤地點沒有 offer；白天地圖不曝光夜間資訊
    expect(game.alignmentOffer('sanquan').available).toBe(false);
    expect(game.mapView().some((m) => m.name.includes('尚未到訪'))).toBe(false);

    const before = game.serialize();
    const res = game.confirmNightAlignment('temple');
    expect(res.ok).toBe(true);
    expect(res.knowledge_id).toBe('k_night_temple');
    expect(res.lines).toEqual([]);
    // 確認前後只差一張 knowledge：不吃卡、不吃行動格、不增加手牌佔格
    const expectedAfter = structuredClone(before);
    expectedAfter.meta.knowledge.k_night_temple = true;
    expect(game.serialize()).toEqual(expectedAfter);
    expect(game.handSlotsUsed()).toBe(1);
    expect(game.getSnapshot().run.action_spent).toBe(false);
    expect(game.knowledgeView().map((k) => k.baseId)).toEqual(['k_night_temple']);

    // 多對一：已到訪 row 顯示「白天名・夜間引子名」；未到訪 row 不被提前標成到訪
    const aligned = game.nightLocationSummary('n_woodtags');
    expect(aligned.status_text).toBe('[已對位]');
    expect(aligned.display_name).toBe(`${temple.name}・${woodtags.name}`);
    const sibling = game.nightLocationSummary('n_music');
    expect(sibling.status_text).toBe('[尚未到訪]');
    expect(sibling.display_name).toBe(loc('n_music').name);
    expect(game.alignmentOffer('temple')).toEqual({
      available: false,
      knowledge_id: 'k_night_temple',
      night_ids: ['n_woodtags'],
    });
    // 沒有另存「已對位」集合
    expect(JSON.stringify(game.serialize())).not.toMatch(/align|matched/i);

    // 之後第一次到訪 sibling 時，因知識已存在自動成為已對位（衍生，不需第二次確認）
    const later = createGame(data, (() => {
      const s = game.serialize();
      s.meta.night_locations_seen.n_music = true;
      return s;
    })());
    expect(later.nightLocationSummary('n_music').status_text).toBe('[已對位]');
    // 任一真值被拿掉，衍生狀態就不成立（證明沒有第三份狀態）
    const noKnowledge = game.serialize();
    delete noKnowledge.meta.knowledge.k_night_temple;
    expect(createGame(data, noKnowledge).nightLocationSummary('n_woodtags').status_text).toBe('[已到訪，尚未對位]');
    const noSeen = game.serialize();
    delete noSeen.meta.night_locations_seen.n_woodtags;
    const noSeenSummary = createGame(data, noSeen).nightLocationSummary('n_woodtags');
    expect(noSeenSummary.status_text).toBe('[尚未到訪]');
    expect(noSeenSummary.display_name).toBe(woodtags.name);

    // 一對一：只顯示白天地點名
    const one = createGame(
      data,
      injectAt(5, 'night', (s) => {
        s.meta.night_locations_seen.n_exit = true;
        s.meta.knowledge.k_night_sanquan = true;
      }),
    );
    expect(one.nightLocationSummary('n_exit').display_name).toBe(loc('sanquan').name);
  });

  it('對位拒絕：六個封閉碼各有案例且 offer 與 confirm 判準一致，拒絕零變化', () => {
    const base = (tweak?: (s: GameSnapshot) => void) =>
      injectAt(9, 'afternoon', (s) => {
        s.meta.night_locations_seen.n_woodtags = true;
        tweak?.(s);
      });
    const check = (
      label: string,
      game: Game,
      dayId: string,
      code: string,
    ) => {
      const offer = game.alignmentOffer(dayId);
      const res = expectRejectsWithoutChange(game, () => game.confirmNightAlignment(dayId), code);
      expect((res as { knowledge_id?: string }).knowledge_id, label).toBe('');
      expect(offer.available, label).toBe(false);
    };
    const opening = createGame(data);
    check('not_run', opening, 'temple', 'not_run');
    check('not_day_phase night', createGame(data, injectAt(9, 'night', (s) => { s.meta.night_locations_seen.n_woodtags = true; })), 'temple', 'not_day_phase');
    check('not_day_phase evening', createGame(data, injectAt(9, 'evening', (s) => { s.meta.night_locations_seen.n_woodtags = true; })), 'temple', 'not_day_phase');
    check('encounter_active', createGame(data, base((s) => { s.run.active_encounter = { stage: 'intro', beat_id: 'x' }; })), 'temple', 'encounter_active');
    check('unknown_location', createGame(data, base()), 'no_such_place', 'unknown_location');
    check('not_day_layer', createGame(data, base()), 'n_woodtags', 'not_day_layer');
    check('no_seen_row', createGame(data, injectAt(9, 'afternoon')), 'temple', 'no_seen_row');
    check('already_known', createGame(data, base((s) => { s.meta.knowledge.k_night_temple = true; })), 'temple', 'already_known');

    // data_conflict：同一白天地點已到訪的兩個 row 指向不同 night_reveal（隔離 fixture，不污染正式資料）
    const conflictLocations = data.locations.map((l) =>
      l.id === 'n_music' ? { ...l, night_reveal: 'k_night_sanquan' } : l,
    );
    const conflictData: GameData = {
      ...data,
      locations: conflictLocations,
      locationsById: new Map(conflictLocations.map((l) => [l.id, l])),
    };
    const conflictGame = createGame(
      conflictData,
      base((s) => {
        s.meta.night_locations_seen.n_music = true;
      }),
    );
    expect(conflictGame.alignmentOffer('temple').available).toBe(false);
    const conflictBefore = JSON.stringify(conflictGame.serialize());
    const conflictRes = conflictGame.confirmNightAlignment('temple');
    expect(conflictRes.reason_code).toBe('data_conflict');
    expect(JSON.stringify(conflictGame.serialize())).toBe(conflictBefore);

    // 兩個 row 皆已到訪且共用同一張 knowledge：只出一個 offer，一次確認讓兩 row 同時成為已對位
    const both = createGame(
      data,
      base((s) => {
        s.meta.night_locations_seen.n_music = true;
      }),
    );
    expect(both.alignmentOffer('temple').night_ids).toEqual(['n_woodtags', 'n_music']);
    expect(both.confirmNightAlignment('temple').ok).toBe(true);
    expect(both.nightLocationSummary('n_woodtags').status_text).toBe('[已對位]');
    expect(both.nightLocationSummary('n_music').status_text).toBe('[已對位]');
    expect(both.confirmNightAlignment('temple').reason_code).toBe('already_known');
  });

  it('greedy 夜間走查（自然從開局走到 D8 evening）：先 fixed 再查可進地點，未 seen 收費 row 優先，D8 night 前被遭遇守衛擋下', () => {
    const game = createRunForTrace(data);
    const log: string[] = [];
    for (let guard = 0; guard < 60; guard += 1) {
      const { day, phase } = game.getSnapshot().run;
      if (phase === 'evening') {
        expect(game.playEvening().ok).toBe(true);
      } else if (phase === 'night') {
        executeGreedyNightPhase(game, data);
        log.push(`D${day}:${game.getSnapshot().run.night_location_chosen}`);
      }
      let res = game.advancePhase();
      if (res.ok && !res.phase_advanced && game.getPhaseView().night_advance === 'next_day') {
        res = game.advancePhase();
      }
      if (!res.ok) {
        expect(res.reason_code).toBe('not_implemented');
        break;
      }
    }
    const snap = game.getSnapshot();
    expect([snap.run.day, snap.run.phase]).toEqual([8, 'evening']);
    // D1／D2 為 fixed 強制到訪；D3 引導不佔名額，之後逐夜依規則進入
    expect(log.slice(0, 3)).toEqual(['D1:n_corridor', 'D2:n_exit', 'D3:n_corridor']);
    // D6 起第一個未 seen 的收費 row（n_ahong_1）、D7 的 n_source 各發一張卡，倒數各走各的
    expect(log[5]).toBe('D6:n_ahong_1');
    expect(log[6]).toBe('D7:n_source');
    expect(snap.run.madness_clock).toEqual({
      'madness#1': countdown - 2,
      'madness#2': countdown - 1,
    });
  });
});
