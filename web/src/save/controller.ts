/**
 * ReturnFare Web — 存檔控制器（W7-B2）。
 *
 * 職責：
 * - 集中管理 Game 實例的 autosave 訂閱生命週期（subscribe / unsubscribe）
 * - 比對序列化快照，確保只在成功提交的指令變更時觸發 autosave，拒絕／預覽／無狀態變更不寫檔
 * - 開局啟動不覆寫現有 auto-save（直到玩家做出實際遊戲提交或選擇載入）
 * - 封裝手動存檔、讀取、匯入與匯出之驗證與狀態替換
 * - 錯誤安全防護：Storage 例外回報給 UI，記憶體遊戲可繼續遊玩
 */

import type { Game, GameSnapshot } from '../core/state-types';
import type { GameData } from '../data/types';
import { createGame } from '../core/state';
import { decodeSave, encodeSave } from './codec';
import type {
  Clock,
  SaveDecodeResult,
  SaveLoadResult,
  SaveStorage,
  SaveSummary,
  SaveWriteResult,
} from './types';

export interface SaveControllerOptions {
  data: GameData;
  initialGame: Game;
  storage: SaveStorage;
  clock?: Clock;
  onStorageError?: (error: string) => void;
}

export interface SaveController {
  readonly storage: SaveStorage;
  readonly data: GameData;
  getGame(): Game;
  setGame(game: Game, baselineSnapshot?: GameSnapshot): void;
  subscribeToCurrentGame(): void;
  unsubscribe(): void;
  hasAutoSave(): boolean;
  peekAutoSave(): SaveSummary;
  loadAutoSave(): SaveLoadResult;
  hasManualSave(): boolean;
  peekManualSave(): SaveSummary;
  saveManual(): SaveWriteResult;
  loadManualSave(): SaveLoadResult;
  exportJson(): string;
  decodeImport(text: string): SaveDecodeResult;
  applySnapshot(
    snapshot: GameSnapshot,
    updateAuto?: boolean,
  ): { game: Game; autoWriteOk: boolean };
}

export function createSaveController(options: SaveControllerOptions): SaveController {
  const { data, storage } = options;
  const clock = options.clock ?? (() => new Date().toISOString());
  let currentGame: Game = options.initialGame;
  let unsubscribeFn: (() => void) | null = null;
  // 記錄前一次成功寫入或做為基線的快照 JSON 字串
  let lastSavedSnapshotJson: string = JSON.stringify(currentGame.getSnapshot());

  function unsubscribe(): void {
    if (unsubscribeFn) {
      unsubscribeFn();
      unsubscribeFn = null;
    }
  }

  function handleGameChange(): void {
    const currentSnap = currentGame.getSnapshot() as GameSnapshot;
    const currentJson = JSON.stringify(currentSnap);
    if (currentJson === lastSavedSnapshotJson) {
      // 快照未實質變更（例如無狀態副作用的查詢或拒絕）
      return;
    }
    const writeRes = storage.save('auto', currentSnap);
    if (writeRes.ok) {
      lastSavedSnapshotJson = currentJson;
    } else {
      options.onStorageError?.(writeRes.error);
    }
  }

  function subscribeToCurrentGame(): void {
    unsubscribe();
    unsubscribeFn = currentGame.subscribe(handleGameChange);
  }

  function setGame(game: Game, baselineSnapshot?: GameSnapshot): void {
    unsubscribe();
    currentGame = game;
    lastSavedSnapshotJson = JSON.stringify(baselineSnapshot ?? game.getSnapshot());
    subscribeToCurrentGame();
  }

  function hasAutoSave(): boolean {
    return storage.hasSave('auto');
  }

  function peekAutoSave(): SaveSummary {
    return storage.peek('auto');
  }

  function loadAutoSave(): SaveLoadResult {
    return storage.load('auto', data);
  }

  function hasManualSave(): boolean {
    return storage.hasSave('manual');
  }

  function peekManualSave(): SaveSummary {
    return storage.peek('manual');
  }

  function saveManual(): SaveWriteResult {
    const snap = currentGame.getSnapshot() as GameSnapshot;
    const res = storage.save('manual', snap);
    if (!res.ok) {
      options.onStorageError?.(res.error);
    }
    return res;
  }

  function loadManualSave(): SaveLoadResult {
    return storage.load('manual', data);
  }

  function exportJson(): string {
    const snap = currentGame.getSnapshot() as GameSnapshot;
    return encodeSave(snap, clock());
  }

  function decodeImport(text: string): SaveDecodeResult {
    return decodeSave(text, data);
  }

  function applySnapshot(
    snapshot: GameSnapshot,
    updateAuto = false,
  ): { game: Game; autoWriteOk: boolean } {
    const newGame = createGame(data, snapshot);
    let autoWriteOk = true;
    if (updateAuto) {
      // 手動讀取或匯入確認成功後，將新快照寫入 auto，manual 槽位不受影響
      const autoRes = storage.save('auto', snapshot);
      if (!autoRes.ok) {
        autoWriteOk = false;
        options.onStorageError?.(autoRes.error);
      }
    }
    setGame(newGame, snapshot);
    return { game: newGame, autoWriteOk };
  }

  // 初始連結訂閱
  subscribeToCurrentGame();

  return {
    storage,
    data,
    getGame: () => currentGame,
    setGame,
    subscribeToCurrentGame,
    unsubscribe,
    hasAutoSave,
    peekAutoSave,
    loadAutoSave,
    hasManualSave,
    peekManualSave,
    saveManual,
    loadManualSave,
    exportJson,
    decodeImport,
    applySnapshot,
  };
}
