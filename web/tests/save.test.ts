/**
 * ReturnFare Web — 存檔序列化、反序列化驗證與儲存配接器測試（W7-B1 Review Correction）。
 */

import { beforeAll, describe, expect, it } from 'vitest';
import { cardBaseId } from '../src/core/facts';
import {
  createEmptyRunState,
  createInitialSnapshot,
} from '../src/core/run-initialization';
import { createGame } from '../src/core/state';
import type { Game, GameSnapshot } from '../src/core/state-types';
import { loadGameDataNode } from '../src/data/load-node';
import type { GameData } from '../src/data/types';
import { decodeSave, encodeSave } from '../src/save/codec';
import {
  createMemoryStorageDriver,
  createSaveStorage,
  getDefaultStorageDriver,
} from '../src/save/storage';
import { createSaveController } from '../src/save/controller';
import {
  SAVE_FORMAT,
  SAVE_STORAGE_KEYS,
  SAVE_VERSION,
  type StorageDriver,
} from '../src/save/types';

function replacedHistoryRecord(): GameSnapshot['meta']['ending_history'][number] {
  return {
    run_number: 1,
    ending_id: 'ending_replaced',
    opening_choice_id: 'take_family_album',
    ended_day: 45,
    ended_phase: 'evening',
    partner_variant: 'none',
    livelihood_variant: 'none_low',
    inn_appearance_variant: 'none',
    festival_proxy_npc: 'ajie',
    knowledge_gained_this_run: [],
  };
}

describe('W7-B1 save codec & storage adapter', () => {
  let data: GameData;

  beforeAll(async () => {
    data = await loadGameDataNode();
  });

  describe('1. 完整真實狀態 roundtrip (opening, run, active encounter, ending)', () => {
    it('1.1 opening 狀態 (開局前) exact roundtrip', () => {
      const game = createGame(data);
      const snap = game.getSnapshot() as GameSnapshot;
      expect(snap.flow.mode).toBe('opening');

      const savedAt = '2026-11-02T12:00:00.000Z';
      const encoded = encodeSave(snap, savedAt);
      const decoded = decodeSave(encoded, data);

      expect(decoded.ok).toBe(true);
      if (!decoded.ok) return;

      expect(decoded.envelope.format).toBe(SAVE_FORMAT);
      expect(decoded.envelope.version).toBe(SAVE_VERSION);
      expect(decoded.envelope.saved_at).toBe(savedAt);
      expect(decoded.state).toEqual(snap);
    });

    it('1.2 run 狀態 (選擇相簿開局並推進) exact roundtrip', () => {
      const game = createGame(data);
      const choiceRes = game.chooseOpening('take_family_album');
      expect(choiceRes.ok).toBe(true);

      const snap = game.getSnapshot() as GameSnapshot;
      expect(snap.flow.mode).toBe('run');
      expect(snap.run.opening_choice_id).toBe('take_family_album');
      expect(snap.run.hand).toContain('protagonist');
      expect(snap.run.hand).toContain('item_family_album');

      const savedAt = '2026-11-02T12:05:30.000Z';
      const encoded = encodeSave(snap, savedAt);
      const decoded = decodeSave(encoded, data);

      expect(decoded.ok).toBe(true);
      if (!decoded.ok) return;

      expect(decoded.state).toEqual(snap);
    });

    it('1.3 active encounter 狀態 (D8 night 固定遭遇 round 階段) exact roundtrip', () => {
      // 建立在 D8 evening 狀態並推進到 night 觸發遭遇
      const baseSnap = createInitialSnapshot();
      baseSnap.flow.mode = 'run';
      baseSnap.run.day = 8;
      baseSnap.run.phase = 'evening';
      baseSnap.run.opening_choice_id = 'take_family_album';
      baseSnap.run.hand = ['protagonist', 'item_gradphoto', 'item_family_album'];
      baseSnap.meta.knowledge = { k_not_today: true };

      const game = createGame(data, baseSnap);
      const advNight = game.advancePhase();
      expect(advNight.ok).toBe(true);
      expect(game.getSnapshot().run.phase).toBe('night');

      const fixedRes = game.playNightFixed();
      expect(fixedRes.ok).toBe(true);
      expect(game.getSnapshot().run.active_encounter.stage).toBe('intro');

      const ackRes = game.acknowledgeEncounterIntro();
      expect(ackRes.ok).toBe(true);
      expect(game.getSnapshot().run.active_encounter.stage).toBe('round');

      const snap = game.getSnapshot() as GameSnapshot;
      expect(snap.run.active_encounter.round_id).toBe('name_since_when');
      expect(snap.run.active_encounter.visited_round_ids).toContain('name_since_when');

      const savedAt = '2026-11-02T12:10:00.000Z';
      const encoded = encodeSave(snap, savedAt);
      const decoded = decodeSave(encoded, data);

      expect(decoded.ok).toBe(true);
      if (!decoded.ok) return;

      expect(decoded.state).toEqual(snap);
    });

    it('1.4 ending 狀態 (不上車結局進行中) exact roundtrip', () => {
      // 具備 ending_replaced 歷史的 opening 狀態，使 refuse_boarding 解鎖
      const initSnap = createInitialSnapshot();
      initSnap.meta.run_number = 2;
      initSnap.meta.ending_history.push(replacedHistoryRecord());

      const game = createGame(data, initSnap);
      const refuseRes = game.chooseOpening('refuse_boarding');
      expect(refuseRes.ok).toBe(true);

      const snap = game.getSnapshot() as GameSnapshot;
      expect(snap.flow.mode).toBe('ending');
      expect(snap.flow.active_ending?.ending_id).toBe('ending_refuse_boarding');

      const savedAt = '2026-11-02T12:15:00.000Z';
      const encoded = encodeSave(snap, savedAt);
      const decoded = decodeSave(encoded, data);

      expect(decoded.ok).toBe(true);
      if (!decoded.ok) return;

      expect(decoded.state).toEqual(snap);
    });
  });

  describe('2. 載入狀態之後續生命週期等價性 (formal delegation & madness tick)', () => {
    it('2.1 loaded pending report: 正式 D17 委託流程、存讀並於 D18 morning 結算回報恰好一次', () => {
      // 依 delegation.test.ts 方式在 D17 morning 透過 playBeat('d17_morning_phone') 取得 npc_azhu
      const snap = createInitialSnapshot();
      snap.flow.mode = 'run';
      snap.run.day = 17;
      snap.run.phase = 'morning';
      snap.run.opening_choice_id = 'take_family_album';
      snap.run.hand = ['protagonist', 'item_family_album'];
      snap.run.flags.azhu_shared_abnormal_medicine = true;

      const morningGame = createGame(data, snap);
      expect(morningGame.playBeat('d17_morning_phone').ok).toBe(true);
      expect(morningGame.hasCard('npc_azhu')).toBe(true);

      // 推進到 afternoon 執行委託
      expect(morningGame.advancePhase().ok).toBe(true);
      expect(morningGame.getSnapshot().run.phase).toBe('afternoon');

      const delRes = morningGame.delegate('d17_19_prescription', 'ask_azhu', 'npc_azhu');
      expect(delRes.ok).toBe(true);
      expect(morningGame.getSnapshot().run.pending_delegation_reports).toHaveLength(1);

      // 推進到 evening 並完成晚飯演出
      expect(morningGame.advancePhase().ok).toBe(true);
      expect(morningGame.playEvening().ok).toBe(true);

      // 推進到 night 並完成固定演出
      expect(morningGame.advancePhase().ok).toBe(true);
      expect(morningGame.getSnapshot().run.phase).toBe('night');
      expect(morningGame.playNightFixed().ok).toBe(true);

      // 在 D17 night 存檔
      const savedText = encodeSave(morningGame.getSnapshot() as GameSnapshot, '2026-11-02T12:20:00.000Z');
      const decodeRes = decodeSave(savedText, data);
      expect(decodeRes.ok).toBe(true);
      if (!decodeRes.ok) return;

      // 載入存檔建立 loadedGame
      const loadedGame = createGame(data, decodeRes.state);

      // 原實例與載入實例分別推進進 D18 morning
      const origMorningAdv = morningGame.advancePhase();
      expect(origMorningAdv.ok).toBe(true);

      const loadedMorningAdv = loadedGame.advancePhase();
      expect(loadedMorningAdv.ok).toBe(true);

      // 驗證回報文字與獎勵道具恰好獲得一次
      const reportText = data.beatsById.get('d17_19_prescription')!.slots!
        .find(slot => slot.id === 'ask_azhu')!.delegation!.report!.text;
      expect(loadedGame.getPhaseView().delegation_report_lines.filter(line => line === reportText)).toHaveLength(1);
      expect(morningGame.getPhaseView().delegation_report_lines).toEqual(loadedGame.getPhaseView().delegation_report_lines);
      expect(loadedGame.hasCard('doc_prescription')).toBe(true);
      expect(loadedGame.hasCard('info_uncle_treated_20y')).toBe(true);
      expect(loadedGame.getSnapshot().run.pending_delegation_reports).toHaveLength(0);

      // 兩者狀態完全一致
      expect(loadedGame.getSnapshot()).toEqual(morningGame.getSnapshot());

      // 後續推進不會再次觸發回報
      const nextAdv = loadedGame.advancePhase();
      expect(nextAdv.ok).toBe(true);
      expect(loadedGame.getPhaseView().delegation_report_lines).toHaveLength(0);
    });

    it('2.2 loaded madness: 發狂卡進 morning 倒數扣減與未中斷實例完全一致', () => {
      // 建立手牌有 1 張倒數 2 天發狂卡的 D2 evening 狀態
      const snap = createInitialSnapshot();
      snap.flow.mode = 'run';
      snap.run.day = 2;
      snap.run.phase = 'evening';
      snap.run.opening_choice_id = 'take_family_album';
      snap.run._madness_counter = 1;
      snap.run.hand = ['protagonist', 'madness#1'];
      snap.run.madness_clock = { 'madness#1': 2 };

      const origGame = createGame(data, snap);
      // D2 evening -> night
      expect(origGame.advancePhase().ok).toBe(true);

      // 存檔並載入
      const savedText = encodeSave(origGame.getSnapshot() as GameSnapshot, '2026-11-02T12:25:00.000Z');
      const decodeRes = decodeSave(savedText, data);
      expect(decodeRes.ok).toBe(true);
      if (!decodeRes.ok) return;

      const loadedGame = createGame(data, decodeRes.state);

      // 推進進 D3 morning（發狂時鐘 tick：2 -> 1）
      const origMorning = origGame.advancePhase();
      expect(origMorning.ok).toBe(true);

      const loadedMorning = loadedGame.advancePhase();
      expect(loadedMorning.ok).toBe(true);

      expect(loadedGame.getSnapshot().run.madness_clock['madness#1']).toBe(1);
      expect(origGame.getSnapshot().run.madness_clock['madness#1']).toBe(1);

      // 兩者狀態完全一致
      expect(loadedGame.getSnapshot()).toEqual(origGame.getSnapshot());
    });
  });

  describe('3. 代表性反例拒絕 (Malformed, Version, Envelope, References)', () => {
    it('3.1 壞 JSON 拒絕 (invalid_json)', () => {
      const res = decodeSave('{ broken json ', data);
      expect(res.ok).toBe(false);
      if (res.ok) return;
      expect(res.reason_code).toBe('invalid_json');
    });

    it('3.2 新版或不支援版本拒絕 (unsupported_version)', () => {
      const validText = encodeSave(createInitialSnapshot(), '2026-11-02T12:00:00.000Z');
      const v2Obj = JSON.parse(validText);
      v2Obj.version = 2;

      const res = decodeSave(JSON.stringify(v2Obj), data);
      expect(res.ok).toBe(false);
      if (res.ok) return;
      expect(res.reason_code).toBe('unsupported_version');
    });

    it('3.2b 版本 2 且多一個未知欄位仍回報 unsupported_version (先檢版本再檢欄位數)', () => {
      const v2Obj = JSON.parse(encodeSave(createInitialSnapshot(), '2026-11-02T12:00:00.000Z'));
      v2Obj.version = 2;
      v2Obj.extra_future_field = true;

      const res = decodeSave(JSON.stringify(v2Obj), data);
      expect(res.ok).toBe(false);
      if (res.ok) return;
      expect(res.reason_code).toBe('unsupported_version');
    });

    it('3.3 錯誤 envelope 格式拒絕 (invalid_envelope)', () => {
      const validText = encodeSave(createInitialSnapshot(), '2026-11-02T12:00:00.000Z');
      const obj = JSON.parse(validText);
      obj.format = 'other-game';

      const res = decodeSave(JSON.stringify(obj), data);
      expect(res.ok).toBe(false);
      if (res.ok) return;
      expect(res.reason_code).toBe('invalid_envelope');
    });

    it('3.4 非嚴格 UTC ISO 時間戳記拒絕 (如 2026 年或無 Z 標記)', () => {
      const validText = encodeSave(createInitialSnapshot(), '2026-11-02T12:00:00.000Z');
      const obj = JSON.parse(validText);
      obj.saved_at = '2026';

      const res = decodeSave(JSON.stringify(obj), data);
      expect(res.ok).toBe(false);
      if (res.ok) return;
      expect(res.reason_code).toBe('invalid_envelope');
      expect(res.error).toContain('UTC ISO 8601');
    });

    it('3.5 不正當 history nullable 矩陣拒絕 (refuse ending 帶 ended_day)', () => {
      const snap = createInitialSnapshot();
      snap.meta.ending_history.push({
        run_number: 1,
        ending_id: 'ending_refuse_boarding',
        opening_choice_id: 'refuse_boarding',
        ended_day: 10, // 不上車 ending 必須為 null
        ended_phase: 'morning',
        partner_variant: null,
        livelihood_variant: null,
        inn_appearance_variant: null,
        festival_proxy_npc: null,
        knowledge_gained_this_run: [],
      });

      const res = decodeSave(encodeSave(snap, '2026-11-02T12:00:00.000Z'), data);
      expect(res.ok).toBe(false);
      if (res.ok) return;
      expect(res.reason_code).toBe('invalid_save_shape');
      expect(res.error).toContain('ending_history');
    });

    it('3.6 flow.mode 與 active_ending 關聯衝突拒絕', () => {
      const snap = createInitialSnapshot();
      snap.flow.mode = 'run';
      // run 模式下 active_ending 必須為 null
      (snap.flow as { active_ending: unknown }).active_ending = { ending_id: 'ending_refuse_boarding' };

      const res = decodeSave(encodeSave(snap, '2026-11-02T12:00:00.000Z'), data);
      expect(res.ok).toBe(false);
      if (res.ok) return;
      expect(res.reason_code).toBe('invalid_save_shape');
    });

    it('3.7 結局包含不存在的損毀 page_refs 拒絕', () => {
      const initSnap = createInitialSnapshot();
      initSnap.meta.run_number = 2;
      initSnap.meta.ending_history.push(replacedHistoryRecord());

      const game = createGame(data, initSnap);
      expect(game.chooseOpening('refuse_boarding').ok).toBe(true);
      const snap = JSON.parse(JSON.stringify(game.getSnapshot())) as GameSnapshot;

      // 注入損毀 page ref
      (snap.flow.active_ending as { page_refs: string[] }).page_refs = [
        'ending_refuse_boarding/first_seen/pages/non_existent_page_12345',
      ];

      const res = decodeSave(encodeSave(snap, '2026-11-02T12:00:00.000Z'), data);
      expect(res.ok).toBe(false);
      if (res.ok) return;
      expect(res.reason_code).toBe('invalid_save_shape');
      expect(res.error).toContain('active_ending 快照不合法');
    });

    it('3.8 手牌含有不存在之卡片拒絕', () => {
      const snap = createInitialSnapshot();
      snap.run.hand.push('totally_fake_card_id');

      const res = decodeSave(encodeSave(snap, '2026-11-02T12:00:00.000Z'), data);
      expect(res.ok).toBe(false);
      if (res.ok) return;
      expect(res.reason_code).toBe('invalid_save_shape');
      expect(res.error).toContain('totally_fake_card_id');
    });

    it('3.9 發狂時鐘與手牌不一致拒絕 (手牌有卡但 clock 缺漏)', () => {
      const snap = createInitialSnapshot();
      snap.run._madness_counter = 1;
      snap.run.hand.push('madness#1');
      // 故意不加 madness_clock

      const res = decodeSave(encodeSave(snap, '2026-11-02T12:00:00.000Z'), data);
      expect(res.ok).toBe(false);
      if (res.ok) return;
      expect(res.reason_code).toBe('invalid_save_shape');
      expect(res.error).toContain('madness_clock');
    });

    it('3.10 forced_pending 包含非發狂卡或未知債務拒絕', () => {
      const snap = createInitialSnapshot();
      snap.run.forced_pending = ['fake_card'];

      const res = decodeSave(encodeSave(snap, '2026-11-02T12:00:00.000Z'), data);
      expect(res.ok).toBe(false);
      if (res.ok) return;
      expect(res.reason_code).toBe('invalid_save_shape');
      expect(res.error).toContain('forced_pending');
    });

    it('3.11 第 45 天夜間 (D45 night) 拒絕 (第 45 天僅有 3 時段)', () => {
      const snap = createInitialSnapshot();
      snap.run.day = 45;
      snap.run.phase = 'night';

      const res = decodeSave(encodeSave(snap, '2026-11-02T12:00:00.000Z'), data);
      expect(res.ok).toBe(false);
      if (res.ok) return;
      expect(res.reason_code).toBe('invalid_save_shape');
      expect(res.error).toContain('run.phase');
    });

    it('3.12 遭遇 intro 階段 round_id 或佔格不為空拒絕', () => {
      const snap = createInitialSnapshot();
      snap.flow.mode = 'run';
      snap.run.active_encounter = {
        beat_id: 'n_manydoors_ch1',
        stage: 'intro',
        round_id: 'name_since_when', // intro 必須為空字串
        blocked_slots: 0,
        attempted_card_ids: [],
        visited_round_ids: [],
      };

      const res = decodeSave(encodeSave(snap, '2026-11-02T12:00:00.000Z'), data);
      expect(res.ok).toBe(false);
      if (res.ok) return;
      expect(res.reason_code).toBe('invalid_save_shape');
      expect(res.error).toContain('intro 階段 round_id 必須為空字串');
    });

    it('3.13 遭遇 round 階段 visited_round_ids 未包含當前回合拒絕', () => {
      const snap = createInitialSnapshot();
      snap.flow.mode = 'run';
      snap.run.active_encounter = {
        beat_id: 'n_manydoors_ch1',
        stage: 'round',
        round_id: 'name_since_when',
        blocked_slots: 1,
        attempted_card_ids: [],
        visited_round_ids: [], // 必須包含 name_since_when
      };

      const res = decodeSave(encodeSave(snap, '2026-11-02T12:00:00.000Z'), data);
      expect(res.ok).toBe(false);
      if (res.ok) return;
      expect(res.reason_code).toBe('invalid_save_shape');
      expect(res.error).toContain('visited_round_ids 必須包含當前回合');
    });

    it('3.14 pending_delegation_reports 引用非委託槽位拒絕', () => {
      const snap = createInitialSnapshot();
      snap.flow.mode = 'run';
      snap.run.day = 17;
      snap.run.phase = 'evening';
      snap.run.pending_delegation_reports = [
        {
          due_day: 18,
          beat_id: 'd17_19_prescription',
          slot_id: 'find_self', // 非委託槽
          person_id: 'npc_azhu',
        },
      ];

      const res = decodeSave(encodeSave(snap, '2026-11-02T12:00:00.000Z'), data);
      expect(res.ok).toBe(false);
      if (res.ok) return;
      expect(res.reason_code).toBe('invalid_save_shape');
      expect(res.error).toContain('非合法的 next_morning 委託槽');
    });

    it('3.15 choice 與 slots_placed 衝突拒絕 (同 choice_group 下多槽被放置)', () => {
      const snap = createInitialSnapshot();
      snap.flow.mode = 'run';
      snap.run.choices['d17_19_prescription::prescription_route'] = 'ask_azhu';
      snap.run.slots_placed['d17_19_prescription::ask_azhu'] = true;
      // 刻意注入互斥槽位
      snap.run.slots_placed['d17_19_prescription::find_self'] = true;

      const res = decodeSave(encodeSave(snap, '2026-11-02T12:00:00.000Z'), data);
      expect(res.ok).toBe(false);
      if (res.ok) return;
      expect(res.reason_code).toBe('invalid_save_shape');
      expect(res.error).toContain('互斥的同組槽位');
    });

    it('3.16 night_once_beats_seen 引用非 meta_once 的 beat 拒絕', () => {
      const snap = createInitialSnapshot();
      // d1_morning_phone 是白天 beat，不是 meta_once
      snap.meta.night_once_beats_seen['d1_morning_phone'] = true;

      const res = decodeSave(encodeSave(snap, '2026-11-02T12:00:00.000Z'), data);
      expect(res.ok).toBe(false);
      if (res.ok) return;
      expect(res.reason_code).toBe('invalid_save_shape');
      expect(res.error).toContain('非 meta_once 的 beat');
    });
  });

  describe('4. Storage 配接器 (安全保護、槽位隔離與例外不破壞現有狀態)', () => {
    it('4.1 正常存讀與 peek 摘要', () => {
      const driver = createMemoryStorageDriver();
      const storage = createSaveStorage({ driver, clock: () => '2026-11-02T12:00:00.000Z' });

      expect(storage.hasSave('auto')).toBe(false);
      expect(storage.hasSave('manual')).toBe(false);

      const snap = createInitialSnapshot();
      const saveRes = storage.save('auto', snap);
      expect(saveRes.ok).toBe(true);
      expect(storage.hasSave('auto')).toBe(true);
      expect(storage.hasSave('manual')).toBe(false);

      const peekRes = storage.peek('auto');
      expect(peekRes.exists).toBe(true);
      expect(peekRes.saved_at).toBe('2026-11-02T12:00:00.000Z');
      expect(peekRes.flow_mode).toBe('opening');

      const loadRes = storage.load('auto', data);
      expect(loadRes.ok).toBe(true);
      if (!loadRes.ok) return;
      expect(loadRes.state).toEqual(snap);
    });

    it('4.2 槽位含有空字串或損毀內容時視為存在且 load 回傳 decode_error (非 empty_slot)', () => {
      const driver = createMemoryStorageDriver({
        [SAVE_STORAGE_KEYS.auto]: '',
        [SAVE_STORAGE_KEYS.manual]: '   ',
      });
      const storage = createSaveStorage({ driver });

      // hasSave 必須為 true，以防未經確認即覆寫
      expect(storage.hasSave('auto')).toBe(true);
      expect(storage.hasSave('manual')).toBe(true);

      // load 必須為 decode_error，不可回傳 empty_slot
      const loadAuto = storage.load('auto', data);
      expect(loadAuto.ok).toBe(false);
      if (loadAuto.ok) return;
      expect(loadAuto.reason).toBe('decode_error');

      const loadManual = storage.load('manual', data);
      expect(loadManual.ok).toBe(false);
      if (loadManual.ok) return;
      expect(loadManual.reason).toBe('decode_error');
    });

    it('4.3 讀取例外時 hasSave 安全返回 true (防止誤判無檔案而覆寫)', () => {
      const failingDriver: StorageDriver = {
        getItem: () => {
          throw new Error('SecurityError: localStorage inaccessible');
        },
        setItem: () => {},
      };
      const storage = createSaveStorage({ driver: failingDriver });
      expect(storage.hasSave('auto')).toBe(true);
      expect(storage.peek('auto').exists).toBe(true);

      const loadRes = storage.load('auto', data);
      expect(loadRes.ok).toBe(false);
      if (loadRes.ok) return;
      expect(loadRes.reason).toBe('read_error');
    });

    it('4.4 寫入失敗時保留原有存檔且不更動記憶體遊戲', () => {
      const snapOld = createInitialSnapshot();
      snapOld.meta.run_number = 1;

      const initialKey = SAVE_STORAGE_KEYS.manual;
      const initialContent = encodeSave(snapOld, '2026-11-01T10:00:00.000Z');

      let shouldFail = false;
      const failingDriver: StorageDriver = {
        getItem: (k: string) => (k === initialKey ? initialContent : null),
        setItem: (_k: string, _v: string) => {
          if (shouldFail) {
            throw new Error('QuotaExceededError: storage full');
          }
        },
      };

      const storage = createSaveStorage({ driver: failingDriver });
      shouldFail = true;

      const snapNew = createInitialSnapshot();
      snapNew.meta.run_number = 2;

      // 嘗試寫入，應安全回傳失敗物件而非拋錯
      const writeRes = storage.save('manual', snapNew);
      expect(writeRes.ok).toBe(false);
      if (!writeRes.ok) {
        expect(writeRes.error).toContain('QuotaExceededError');
      }

      // 讀取該槽位，舊檔案應依然完整存在
      shouldFail = false;
      const loadRes = storage.load('manual', data);
      expect(loadRes.ok).toBe(true);
      if (!loadRes.ok) return;
      expect(loadRes.state.meta.run_number).toBe(1);
    });

    it('4.5 壞檔解碼失敗時不刪除原檔', () => {
      const driver = createMemoryStorageDriver({
        [SAVE_STORAGE_KEYS.auto]: '{ malformed save json',
      });
      const storage = createSaveStorage({ driver });

      const loadRes = storage.load('auto', data);
      expect(loadRes.ok).toBe(false);
      if (loadRes.ok) return;
      expect(loadRes.reason).toBe('decode_error');

      // 原檔未被刪除或清空
      expect(driver.getItem(SAVE_STORAGE_KEYS.auto)).toBe('{ malformed save json');
    });

    it('4.6 Node 環境下無 window 時 getDefaultStorageDriver 安全回傳 null', () => {
      const driver = getDefaultStorageDriver();
      // 在 Node headless 環境中 window 為 undefined
      expect(driver).toBeNull();
    });
  });

  describe('5. W7-B2 SaveController & autosave lifecycle', () => {
    it('5.1 no mount overwrite: 啟動掛載不覆寫現有自動存檔', () => {
      // 模擬先前遊玩留在 localStorage 的自動存檔
      const gameOld = createGame(data);
      gameOld.chooseOpening('take_family_album');
      const snapOld = gameOld.getSnapshot() as GameSnapshot;
      expect(snapOld.flow.mode).toBe('run');

      const initialAutoText = encodeSave(snapOld, '2026-11-01T12:00:00.000Z');
      const driver = createMemoryStorageDriver({
        [SAVE_STORAGE_KEYS.auto]: initialAutoText,
      });
      const storage = createSaveStorage({ driver });

      // 新 session 開場，建立 fresh opening game 與 controller
      const freshGame = createGame(data);
      expect(freshGame.getSnapshot().flow.mode).toBe('opening');

      const controller = createSaveController({
        data,
        initialGame: freshGame,
        storage,
      });

      // 驗證：雖然 controller 已建立並訂閱 freshGame，但未發生實質遊戲提交，不得覆寫既有存檔
      expect(driver.getItem(SAVE_STORAGE_KEYS.auto)).toBe(initialAutoText);
      expect(controller.hasAutoSave()).toBe(true);

      const peek = controller.peekAutoSave();
      expect(peek.saved_at).toBe('2026-11-01T12:00:00.000Z');
      expect(peek.flow_mode).toBe('run');

      controller.unsubscribe();
    });

    it('5.2 no reject-preview writes: 預覽卡槽與被拒絕的操作不寫檔', () => {
      const driver = createMemoryStorageDriver();
      const storage = createSaveStorage({ driver });
      const game = createGame(data);

      const controller = createSaveController({
        data,
        initialGame: game,
        storage,
      });

      // 尚未提交任何操作，auto 應為空
      expect(storage.hasSave('auto')).toBe(false);

      // 呼叫純查詢 / 預覽 API
      game.previewSlot('d1_arrival', 'talk_elder');
      game.placeableCards('d1_arrival', 'talk_elder');
      game.hasAnyLegalAction();
      game.hasUnseenContent();

      // 嘗試非法操作（在 opening 模式直接推進時段）
      const rejected = game.advancePhase();
      expect(rejected.ok).toBe(false);

      // 驗證：查詢與拒絕操作完全零寫入副作用
      expect(storage.hasSave('auto')).toBe(false);
      expect(driver.getItem(SAVE_STORAGE_KEYS.auto)).toBeNull();

      controller.unsubscribe();
    });

    it('5.3 autosave on committed mutation: 成功提交的遊戲指令自動寫入 auto 槽位', () => {
      const driver = createMemoryStorageDriver();
      const storage = createSaveStorage({ driver });
      const game = createGame(data);

      const controller = createSaveController({
        data,
        initialGame: game,
        storage,
      });

      expect(storage.hasSave('auto')).toBe(false);

      // 1. 提交開局選擇
      const res1 = game.chooseOpening('take_family_album');
      expect(res1.ok).toBe(true);

      // 驗證：已成功自動存入 auto
      expect(storage.hasSave('auto')).toBe(true);
      const auto1 = storage.load('auto', data);
      expect(auto1.ok).toBe(true);
      if (!auto1.ok) return;
      expect(auto1.state.flow.mode).toBe('run');
      expect(auto1.state.run.day).toBe(1);
      expect(auto1.state.run.phase).toBe('morning');

      // 2. 推進時段
      const res2 = game.advancePhase();
      expect(res2.ok).toBe(true);

      const auto2 = storage.load('auto', data);
      expect(auto2.ok).toBe(true);
      if (!auto2.ok) return;
      expect(auto2.state.run.phase).toBe('afternoon');

      controller.unsubscribe();
    });

    it('5.3b autosave suspended: 暫停時連續命令 auto 原字串逐字不變，resume 後才寫入目前進度', () => {
      // 模擬部署回退後遇到的新版（不支援版本）自動檔
      const unsupportedAuto = JSON.stringify({
        format: SAVE_FORMAT,
        version: SAVE_VERSION + 1,
        saved_at: '2026-11-01T12:00:00.000Z',
        state: {},
      });
      const driver = createMemoryStorageDriver({ [SAVE_STORAGE_KEYS.auto]: unsupportedAuto });
      const storage = createSaveStorage({ driver });
      const game = createGame(data);
      const controller = createSaveController({
        data,
        initialGame: game,
        storage,
        autosaveSuspended: true,
      });
      expect(controller.isAutosaveSuspended()).toBe(true);

      expect(game.chooseOpening('take_family_album').ok).toBe(true);
      expect(driver.getItem(SAVE_STORAGE_KEYS.auto)).toBe(unsupportedAuto);
      expect(game.advancePhase().ok).toBe(true);
      expect(driver.getItem(SAVE_STORAGE_KEYS.auto)).toBe(unsupportedAuto);

      // 明示覆蓋：恢復並立即寫入目前已提交快照
      const res = controller.resumeAutosave();
      expect(res.ok).toBe(true);
      expect(controller.isAutosaveSuspended()).toBe(false);
      const afterResume = storage.load('auto', data);
      expect(afterResume.ok).toBe(true);
      if (!afterResume.ok) return;
      expect(afterResume.state).toEqual(game.getSnapshot());

      // 恢復後的後續命令照常寫入
      expect(game.advancePhase().ok).toBe(true);
      const afterNext = storage.load('auto', data);
      expect(afterNext.ok).toBe(true);
      if (!afterNext.ok) return;
      expect(afterNext.state.run.phase).toBe(game.getSnapshot().run.phase);

      controller.unsubscribe();
    });

    it('5.3c autosave suspended: applySnapshot（讀取／匯入／繼續）視同取代，恢復 autosave', () => {
      const unsupportedAuto = '{"format":"returnfare-web","version":99}';
      const driver = createMemoryStorageDriver({ [SAVE_STORAGE_KEYS.auto]: unsupportedAuto });
      const storage = createSaveStorage({ driver });
      const controller = createSaveController({
        data,
        initialGame: createGame(data),
        storage,
        autosaveSuspended: true,
      });
      const other = createGame(data);
      other.chooseOpening('take_family_album');
      const { game: loaded } = controller.applySnapshot(other.getSnapshot() as GameSnapshot, true);
      expect(controller.isAutosaveSuspended()).toBe(false);
      expect(storage.load('auto', data).ok).toBe(true);
      expect(loaded.advancePhase().ok).toBe(true);
      const after = storage.load('auto', data);
      expect(after.ok).toBe(true);
      if (!after.ok) return;
      expect(after.state.run.phase).toBe('afternoon');
      controller.unsubscribe();
    });

    it('5.4 unsubscribe on replacement: 替換 Game 時舊實例取消訂閱，不再觸發寫入', () => {
      const driver = createMemoryStorageDriver();
      const storage = createSaveStorage({ driver });
      const game1 = createGame(data);

      const controller = createSaveController({
        data,
        initialGame: game1,
        storage,
      });

      game1.chooseOpening('take_family_album');
      const snap1 = storage.load('auto', data);
      expect(snap1.ok).toBe(true);
      if (!snap1.ok) return;
      expect(snap1.state.run.opening_choice_id).toBe('take_family_album');

      // 替換為 game2 (例如開新局使用 return_missed_call)
      const game2 = createGame(data);
      controller.setGame(game2);

      // 此時若操作舊的 game1，不應污染 controller 或 storage
      game1.advancePhase();

      // 操作 game2 則正常 autosave
      const resChoose = game2.chooseOpening('return_missed_call');
      expect(resChoose.ok).toBe(true);

      const snap2 = storage.load('auto', data);
      expect(snap2.ok).toBe(true);
      if (!snap2.ok) return;
      expect(snap2.state.run.opening_choice_id).toBe('return_missed_call');

      controller.unsubscribe();
    });

    it('5.5 storage failure handling: 儲存失敗時觸發錯誤回呼，記憶體遊戲維持可遊玩', () => {
      let failWrite = false;
      let capturedError = '';
      const failingDriver: StorageDriver = {
        getItem: () => null,
        setItem: () => {
          if (failWrite) {
            throw new Error('QuotaExceededError: disk full');
          }
        },
      };

      const storage = createSaveStorage({ driver: failingDriver });
      const game = createGame(data);

      const controller = createSaveController({
        data,
        initialGame: game,
        storage,
        onStorageError: (err) => {
          capturedError = err;
        },
      });

      failWrite = true;

      // 執行提交指令
      const res = game.chooseOpening('take_family_album');
      expect(res.ok).toBe(true);

      // 驗證：錯誤回報已被捕捉
      expect(capturedError).toContain('QuotaExceededError');

      // 驗證：記憶體遊戲完全正常運行，狀態正確更新
      expect(game.getSnapshot().flow.mode).toBe('run');
      expect(game.hasCard('item_family_album')).toBe(true);

      controller.unsubscribe();
    });

    it('5.6 export leaves live game and slots byte-for-byte identical', () => {
      const driver = createMemoryStorageDriver();
      const storage = createSaveStorage({ driver });
      const game = createGame(data);

      const controller = createSaveController({
        data,
        initialGame: game,
        storage,
      });

      game.chooseOpening('take_family_album');
      controller.saveManual();

      const autoBefore = driver.getItem(SAVE_STORAGE_KEYS.auto);
      const manualBefore = driver.getItem(SAVE_STORAGE_KEYS.manual);
      const liveSnapshotBefore = JSON.stringify(game.getSnapshot());

      // 執行匯出
      const exportedJson = controller.exportJson();
      expect(typeof exportedJson).toBe('string');

      // 驗證匯出字串可解碼且與 live 快照一致
      const decoded = controller.decodeImport(exportedJson);
      expect(decoded.ok).toBe(true);
      if (!decoded.ok) return;
      expect(JSON.stringify(decoded.state)).toBe(liveSnapshotBefore);

      // 驗證：本機 auto 與 manual 槽位完全未變動
      expect(driver.getItem(SAVE_STORAGE_KEYS.auto)).toBe(autoBefore);
      expect(driver.getItem(SAVE_STORAGE_KEYS.manual)).toBe(manualBefore);

      // 驗證：live 遊戲狀態完全未變動
      expect(JSON.stringify(game.getSnapshot())).toBe(liveSnapshotBefore);

      controller.unsubscribe();
    });

    it('5.7 cancel import / bad JSON / newer version preserves live game and both slots', () => {
      const driver = createMemoryStorageDriver();
      const storage = createSaveStorage({ driver });
      const game = createGame(data);

      const controller = createSaveController({
        data,
        initialGame: game,
        storage,
      });

      game.chooseOpening('take_family_album');
      controller.saveManual();

      const autoBefore = driver.getItem(SAVE_STORAGE_KEYS.auto);
      const manualBefore = driver.getItem(SAVE_STORAGE_KEYS.manual);
      const liveSnapshotBefore = JSON.stringify(game.getSnapshot());

      // 1. 損毀 JSON
      const resBad = controller.decodeImport('not a json string {{{');
      expect(resBad.ok).toBe(false);
      if (resBad.ok) return;
      expect(resBad.reason_code).toBe('invalid_json');

      // 2. 不支援的較新版本 (version: 999)
      const resNewer = controller.decodeImport(
        JSON.stringify({
          format: 'returnfare-web',
          version: 999,
          saved_at: '2099-01-01T00:00:00.000Z',
          state: game.getSnapshot(),
        }),
      );
      expect(resNewer.ok).toBe(false);
      if (resNewer.ok) return;
      expect(resNewer.reason_code).toBe('unsupported_version');

      // 驗證：槽位與目前遊戲未受任何破壞
      expect(driver.getItem(SAVE_STORAGE_KEYS.auto)).toBe(autoBefore);
      expect(driver.getItem(SAVE_STORAGE_KEYS.manual)).toBe(manualBefore);
      expect(JSON.stringify(game.getSnapshot())).toBe(liveSnapshotBefore);

      controller.unsubscribe();
    });

    it('5.8 applySnapshot on import replaces game, updates auto slot, leaves manual slot untouched', () => {
      const driver = createMemoryStorageDriver();
      const storage = createSaveStorage({ driver });
      const game = createGame(data);

      const controller = createSaveController({
        data,
        initialGame: game,
        storage,
      });

      // 初始為 album 路線並手動存檔
      game.chooseOpening('take_family_album');
      controller.saveManual();
      const manualBefore = driver.getItem(SAVE_STORAGE_KEYS.manual);

      // 準備另一份 phone 路線快照模擬匯入
      const anotherGame = createGame(data);
      const resOther = anotherGame.chooseOpening('return_missed_call');
      expect(resOther.ok).toBe(true);
      const importSnap = anotherGame.getSnapshot() as GameSnapshot;

      // 套用匯入
      const { game: newGame, autoWriteOk } = controller.applySnapshot(importSnap, true);
      expect(autoWriteOk).toBe(true);
      expect(newGame.getSnapshot().run.opening_choice_id).toBe('return_missed_call');

      // 驗證：auto 槽位已更新為匯入之快照
      const autoAfter = storage.load('auto', data);
      expect(autoAfter.ok).toBe(true);
      if (!autoAfter.ok) return;
      expect(autoAfter.state.run.opening_choice_id).toBe('return_missed_call');

      // 驗證：manual 槽位完全不受影響
      expect(driver.getItem(SAVE_STORAGE_KEYS.manual)).toBe(manualBefore);

      controller.unsubscribe();
    });

    it('5.9 D1 formal roundtrip & current fixed/auto_enter narration restoration', () => {
      // 1. 開局選擇相簿路線
      const game = createGame(data);
      const res = game.chooseOpening('take_family_album');
      expect(res.ok).toBe(true);

      const origView = game.getPhaseView();
      expect(origView.narration_only).toBe(true);
      expect(origView.lines.length).toBeGreaterThan(0);
      expect(origView.lines[0]).toContain('出城的時候還在下雨');

      // 取得快照並序列化 roundtrip
      const snap = game.serialize();
      const encoded = encodeSave(snap, '2026-11-02T12:00:00.000Z');
      const decoded = decodeSave(encoded, data);
      expect(decoded.ok).toBe(true);
      if (!decoded.ok) return;

      // 重建遊戲實例
      const restored = createGame(data, decoded.state);

      // 斷言：在查詢 getPhaseView() 前，狀態與原始快照完全一致
      expect(restored.serialize()).toEqual(snap);

      // 斷言：還原後之 PhaseView 成功投影出出城文本，非空陣列！
      const restoredView = restored.getPhaseView();
      expect(restoredView.narration_only).toBe(true);
      expect(restoredView.lines).toEqual(origView.lines);

      // 斷言：在查詢 getPhaseView() 後，狀態依然嚴格無任何副作用或變動
      expect(restored.serialize()).toEqual(snap);

      // 斷言：持有卡片張數維持 2（主角 + 相簿），未發生二次發卡
      expect(restored.getSnapshot().run.hand.length).toBe(2);
      expect(restored.hasCard('item_family_album')).toBe(true);
    });

    it('5.10 Evening, Night fixed & Sleep stage narration restoration without side-effects', () => {
      const game = createGame(data);
      game.chooseOpening('take_family_album');

      // 推進至 D1 evening
      game.advancePhase(); // -> afternoon
      game.advancePhase(); // -> evening
      game.playEvening();

      const eveningView = game.getPhaseView();
      expect(eveningView.lines.length).toBeGreaterThan(0);

      // 還原 evening
      const eveningSnap = game.serialize();
      const restoredEvening = createGame(data, eveningSnap);
      expect(restoredEvening.serialize()).toEqual(eveningSnap);
      expect(restoredEvening.getPhaseView().lines).toEqual(eveningView.lines);
      expect(restoredEvening.serialize()).toEqual(eveningSnap);

      // 推進至 D1 night
      game.advancePhase(); // -> night
      game.playNightFixed();
      const nightView = game.getPhaseView();
      expect(nightView.lines.length).toBeGreaterThan(0);

      // 還原 night fixed
      const nightSnap = game.serialize();
      const restoredNight = createGame(data, nightSnap);
      expect(restoredNight.serialize()).toEqual(nightSnap);
      expect(restoredNight.getPhaseView().lines).toEqual(nightView.lines);
      expect(restoredNight.serialize()).toEqual(nightSnap);

      // 測試夜間就寢停拍階段（以具有 sanquan 睡覺劇情的 D23 night 為例）
      const d23Snap = game.serialize();
      d23Snap.run.day = 23;
      d23Snap.run.phase = 'night';
      d23Snap.run.night_location_chosen = '';
      d23Snap.run.night_sleep_pending = false;
      d23Snap.run.flags.typhoon_secured = true;
      const sleepGame = createGame(data, d23Snap);

      const advanceRes = sleepGame.advancePhase();
      expect(advanceRes.ok).toBe(true);
      expect(advanceRes.phase_advanced).toBe(false);
      expect(sleepGame.getSnapshot().run.night_sleep_pending).toBe(true);

      const sleepView = sleepGame.getPhaseView();
      expect(sleepView.lines.length).toBeGreaterThan(0);

      // 還原 sleep stage
      const sleepSnap = sleepGame.serialize();
      const restoredSleep = createGame(data, sleepSnap);
      expect(restoredSleep.serialize()).toEqual(sleepSnap);
      expect(restoredSleep.getPhaseView().lines).toEqual(sleepView.lines);
      expect(restoredSleep.serialize()).toEqual(sleepSnap);
    });

    it('5.11 manual save -> advance -> manual load -> reopen -> continue resumes loaded state', () => {
      const driver = createMemoryStorageDriver();
      const storage = createSaveStorage({ driver });
      const game = createGame(data);

      const controller = createSaveController({
        data,
        initialGame: game,
        storage,
      });

      // 1. 開局並推進到下午
      game.chooseOpening('take_family_album');
      game.advancePhase(); // -> afternoon
      expect(game.getSnapshot().run.phase).toBe('afternoon');

      // 2. 在下午進行手動存檔
      const saveRes = controller.saveManual();
      expect(saveRes.ok).toBe(true);
      const manualBefore = driver.getItem(SAVE_STORAGE_KEYS.manual);

      // 3. 繼續推進到傍晚（放棄的未來）
      game.advancePhase(); // -> evening
      expect(game.getSnapshot().run.phase).toBe('evening');
      // auto 槽位目前記錄著傍晚
      expect(storage.load('auto', data).ok).toBe(true);
      if (storage.load('auto', data).ok) {
        expect((storage.load('auto', data) as any).state.run.phase).toBe('evening');
      }

      // 4. 執行手動讀取（確認讀取）
      const loadRes = controller.loadManualSave();
      expect(loadRes.ok).toBe(true);
      if (!loadRes.ok) return;

      // applySnapshot(..., updateAuto: true) 同步更新 auto 槽位為已還原的下午狀態
      const { game: restoredGame, autoWriteOk } = controller.applySnapshot(loadRes.state, true);
      expect(autoWriteOk).toBe(true);
      expect(restoredGame.getSnapshot().run.phase).toBe('afternoon');

      // 驗證：auto 槽位已回退至下午，不再是傍晚！
      const autoAfterLoad = storage.load('auto', data);
      expect(autoAfterLoad.ok).toBe(true);
      if (!autoAfterLoad.ok) return;
      expect(autoAfterLoad.state.run.phase).toBe('afternoon');

      // 驗證：手動槽位維持原樣
      expect(driver.getItem(SAVE_STORAGE_KEYS.manual)).toBe(manualBefore);

      // 5. 模擬重開頁面：讀取 auto 槽位
      const continueLoad = storage.load('auto', data);
      expect(continueLoad.ok).toBe(true);
      if (!continueLoad.ok) return;
      expect(continueLoad.state.run.phase).toBe('afternoon');

      controller.unsubscribe();
    });
  });
});
