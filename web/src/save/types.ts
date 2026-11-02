/**
 * ReturnFare Web — 存檔系統核心型別（W7-B1）。
 *
 * 定義 localStorage / 檔案匯入匯出的 SaveEnvelope、SaveSlot、儲存鍵值與解碼結果型別。
 */

import type { GameSnapshot } from '../core/state-types';
import type { GameData } from '../data/types';

export const SAVE_FORMAT = 'returnfare-web';
export const SAVE_VERSION = 1;

export type SaveSlot = 'auto' | 'manual';

export const SAVE_STORAGE_KEYS: Readonly<Record<SaveSlot, string>> = {
  auto: 'returnfare.save.auto',
  manual: 'returnfare.save.manual',
};

/** 存檔 envelope 封閉形狀（四欄）。 */
export interface SaveEnvelope {
  format: typeof SAVE_FORMAT;
  version: typeof SAVE_VERSION;
  saved_at: string; // UTC ISO 8601 字串，供 UI 顯示，不進 GameSnapshot/trace
  state: GameSnapshot;
}

export type SaveDecodeErrorCode =
  | 'invalid_json'
  | 'unsupported_version'
  | 'invalid_envelope'
  | 'invalid_save_shape';

export type SaveDecodeResult =
  | {
      readonly ok: true;
      readonly state: GameSnapshot;
      readonly envelope: SaveEnvelope;
    }
  | {
      readonly ok: false;
      readonly reason_code: SaveDecodeErrorCode;
      readonly error: string;
    };

/** 可注入的鍵值儲存介面（抽象 window.localStorage）。 */
export interface StorageDriver {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
}

/** 注入時間來源，測試時可給定固定字串。 */
export type Clock = () => string;

export interface SaveStorageOptions {
  driver?: StorageDriver | null;
  clock?: Clock;
}

export type SaveWriteResult =
  | {
      readonly ok: true;
      readonly slot: SaveSlot;
      readonly saved_at: string;
    }
  | {
      readonly ok: false;
      readonly slot: SaveSlot;
      readonly error: string;
    };

export type SaveLoadResult =
  | {
      readonly ok: true;
      readonly slot: SaveSlot;
      readonly state: GameSnapshot;
      readonly envelope: SaveEnvelope;
    }
  | {
      readonly ok: false;
      readonly slot: SaveSlot;
      readonly reason: 'empty_slot' | 'storage_unavailable' | 'read_error' | 'decode_error';
      readonly decode_result?: SaveDecodeResult;
      readonly error: string;
    };

export interface SaveSummary {
  readonly slot: SaveSlot;
  readonly exists: boolean;
  readonly saved_at?: string;
  readonly version?: number;
  readonly day?: number;
  readonly phase?: string;
  readonly flow_mode?: string;
  readonly run_number?: number;
}

export interface SaveStorage {
  hasSave(slot: SaveSlot): boolean;
  peek(slot: SaveSlot): SaveSummary;
  loadRaw(slot: SaveSlot): string | null;
  save(slot: SaveSlot, snapshot: GameSnapshot): SaveWriteResult;
  load(slot: SaveSlot, data: GameData): SaveLoadResult;
}
