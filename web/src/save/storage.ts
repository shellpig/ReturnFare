/**
 * ReturnFare Web — 存檔儲存配接器（W7-B1）。
 *
 * 封裝對 localStorage / 注入式 StorageDriver 的存取與例外保護：
 * - 依固定鍵 returnfare.save.auto 與 returnfare.save.manual 存取
 * - 安全捕捉例外，儲存空間滿或停用時不 crash，保留現有遊戲與既有檔案
 * - 讀取存檔時絕不覆寫或刪除壞檔，且不直接變更 Game instance
 * - 提供 Node 測試可用的記憶體 storage driver 與時間來源注入
 */

import type { GameSnapshot } from '../core/state-types';
import type { GameData } from '../data/types';
import { decodeSave, encodeSave } from './codec';
import {
  SAVE_STORAGE_KEYS,
  type Clock,
  type SaveDecodeResult,
  type SaveLoadResult,
  type SaveSlot,
  type SaveStorage,
  type SaveStorageOptions,
  type SaveSummary,
  type SaveWriteResult,
  type StorageDriver,
} from './types';

/** 安全嘗試獲取 window.localStorage，阻擋無 window 或瀏覽器安全性例外。 */
export function getDefaultStorageDriver(): StorageDriver | null {
  try {
    if (typeof window !== 'undefined' && window.localStorage) {
      return {
        getItem: (k: string) => window.localStorage.getItem(k),
        setItem: (k: string, v: string) => window.localStorage.setItem(k, v),
      };
    }
  } catch {
    // 例如在安全性沙盒或禁用 cookies 的環境下存取 window.localStorage 會拋錯
  }
  return null;
}

/** 建立獨立的記憶體儲存配接器（供 Node 測試與無 storage 環境使用）。 */
export function createMemoryStorageDriver(
  initialEntries?: Record<string, string>,
): StorageDriver {
  const store = new Map<string, string>(Object.entries(initialEntries ?? {}));
  return {
    getItem: (key: string) => store.get(key) ?? null,
    setItem: (key: string, value: string) => {
      store.set(key, value);
    },
  };
}

const defaultClock: Clock = () => new Date().toISOString();

/**
 * 建立存檔管理器配接器實例。
 *
 * @param options 可注入 driver 與 clock；預設使用 window.localStorage 與系統時間
 */
export function createSaveStorage(options: SaveStorageOptions = {}): SaveStorage {
  const driver = options.driver !== undefined ? options.driver : getDefaultStorageDriver();
  const clock = options.clock ?? defaultClock;

  function hasSave(slot: SaveSlot): boolean {
    if (!driver) return false;
    try {
      const raw = driver.getItem(SAVE_STORAGE_KEYS[slot]);
      return raw !== null;
    } catch {
      // 讀取例外不可回傳 false 以免誤授權直接覆寫既有檔案
      return true;
    }
  }

  function loadRaw(slot: SaveSlot): string | null {
    if (!driver) return null;
    try {
      return driver.getItem(SAVE_STORAGE_KEYS[slot]);
    } catch {
      return null;
    }
  }

  function peek(slot: SaveSlot): SaveSummary {
    if (!driver) return { slot, exists: false };
    let raw: string | null = null;
    try {
      raw = driver.getItem(SAVE_STORAGE_KEYS[slot]);
    } catch {
      // 讀取例外不可回傳 exists: false 以免誤授權直接覆寫既有檔案
      return { slot, exists: true };
    }
    if (raw === null) {
      return { slot, exists: false };
    }
    try {
      const parsed = JSON.parse(raw);
      if (typeof parsed === 'object' && parsed !== null) {
        return {
          slot,
          exists: true,
          saved_at: typeof parsed.saved_at === 'string' ? parsed.saved_at : undefined,
          version: typeof parsed.version === 'number' ? parsed.version : undefined,
          day: typeof parsed.state?.run?.day === 'number' ? parsed.state.run.day : undefined,
          phase: typeof parsed.state?.run?.phase === 'string' ? parsed.state.run.phase : undefined,
          flow_mode: typeof parsed.state?.flow?.mode === 'string' ? parsed.state.flow.mode : undefined,
          run_number: typeof parsed.state?.meta?.run_number === 'number' ? parsed.state.meta.run_number : undefined,
        };
      }
    } catch {
      // 損毀內容仍標記為存在
    }
    return { slot, exists: true };
  }

  function save(slot: SaveSlot, snapshot: GameSnapshot): SaveWriteResult {
    if (!driver) {
      return {
        ok: false,
        slot,
        error: '儲存空間不可用 (未偵測到本機儲存配接器)',
      };
    }

    const savedAt = clock();
    let text: string;
    try {
      text = encodeSave(snapshot, savedAt);
    } catch (err) {
      return {
        ok: false,
        slot,
        error: `編碼存檔失敗: ${(err as Error).message}`,
      };
    }

    try {
      driver.setItem(SAVE_STORAGE_KEYS[slot], text);
      return {
        ok: true,
        slot,
        saved_at: savedAt,
      };
    } catch (err) {
      return {
        ok: false,
        slot,
        error: `寫入儲存空間失敗: ${(err as Error).message}`,
      };
    }
  }

  function load(slot: SaveSlot, data: GameData): SaveLoadResult {
    if (!driver) {
      return {
        ok: false,
        slot,
        reason: 'storage_unavailable',
        error: '儲存空間不可用 (未偵測到本機儲存配接器)',
      };
    }

    let raw: string | null = null;
    try {
      raw = driver.getItem(SAVE_STORAGE_KEYS[slot]);
    } catch (err) {
      return {
        ok: false,
        slot,
        reason: 'read_error',
        error: `讀取儲存空間失敗: ${(err as Error).message}`,
      };
    }

    if (raw === null) {
      return {
        ok: false,
        slot,
        reason: 'empty_slot',
        error: `槽位 '${slot}' 尚無存檔`,
      };
    }

    const decodeRes: SaveDecodeResult = decodeSave(raw, data);
    if (!decodeRes.ok) {
      return {
        ok: false,
        slot,
        reason: 'decode_error',
        decode_result: decodeRes,
        error: `存檔解析或驗證失敗: ${decodeRes.error} (${decodeRes.reason_code})`,
      };
    }

    return {
      ok: true,
      slot,
      state: decodeRes.state,
      envelope: decodeRes.envelope,
    };
  }

  return {
    hasSave,
    loadRaw,
    peek,
    save,
    load,
  };
}
