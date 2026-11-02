import { useRef, useState, type ChangeEvent } from 'react';
import type { Game, GameSnapshot } from '../core/state-types';
import type { SaveController } from '../save/controller';
import { ModalDialog } from './ModalDialog';
import { strings } from './strings';
import { useGame } from './use-game';

export interface SavePanelProps {
  game: Game;
  controller: SaveController;
  onReplaceGame: (newGame: Game) => void;
  storageError?: string;
  onClearStorageError?: () => void;
}

// saved_at 存檔內容維持 UTC ISO，只在顯示時轉為本地時間；無法解析時退回原字串
const savedAtFormatter = new Intl.DateTimeFormat('zh-TW', {
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
});

function formatSavedAt(iso: string): string {
  const ms = Date.parse(iso);
  if (Number.isNaN(ms)) return iso;
  return savedAtFormatter.format(new Date(ms));
}

type ConfirmState =
  | { type: 'overwrite' }
  | { type: 'overwriteAuto' }
  | { type: 'load'; snapshot: GameSnapshot; savedAt: string }
  | { type: 'import'; snapshot: GameSnapshot; savedAt: string };

export function SavePanel({
  game,
  controller,
  onReplaceGame,
  storageError,
  onClearStorageError,
}: SavePanelProps) {
  const snapshot = useGame(game);
  const [localError, setLocalError] = useState('');
  const [status, setStatus] = useState('');
  const [confirmState, setConfirmState] = useState<ConfirmState | null>(null);
  // 成功替換遊戲後隱藏啟動橫幅（自動檔本身停在 opening 時，替換後仍會符合顯示條件）
  const [bannerDismissed, setBannerDismissed] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const error = localError || storageError || '';

  function clearErrors() {
    setLocalError('');
    onClearStorageError?.();
  }

  const autoSummary = controller.peekAutoSave();
  const manualSummary = controller.peekManualSave();
  // 只要手動槽位在 storage 中存在即可點擊讀取，交由驗證管線報出具體原因
  const hasManualSave = manualSummary.exists;

  function handleContinueAuto() {
    clearErrors();
    setStatus('');
    const loadRes = controller.loadAutoSave();
    if (!loadRes.ok) {
      setLocalError(strings.loadError(loadRes.error));
      return;
    }
    const { game: newGame } = controller.applySnapshot(loadRes.state, false);
    onReplaceGame(newGame);
    setBannerDismissed(true);
    setStatus(strings.continueSuccess);
  }

  function handleManualSaveClick() {
    clearErrors();
    setStatus('');
    if (controller.hasManualSave()) {
      setConfirmState({ type: 'overwrite' });
      return;
    }
    executeManualSave();
  }

  function executeManualSave() {
    const res = controller.saveManual();
    if (!res.ok) {
      setLocalError(strings.saveError(res.error));
      return;
    }
    setStatus(strings.saveSuccess);
  }

  function handleManualLoadClick() {
    clearErrors();
    setStatus('');
    if (!hasManualSave) {
      setLocalError(strings.noManualSave);
      return;
    }
    const loadRes = controller.loadManualSave();
    if (!loadRes.ok) {
      setLocalError(strings.loadError(loadRes.error));
      return;
    }
    setConfirmState({
      type: 'load',
      snapshot: loadRes.state,
      savedAt: loadRes.envelope.saved_at,
    });
  }

  function handleExportClick() {
    clearErrors();
    setStatus('');
    try {
      const json = controller.exportJson();
      const blob = new Blob([json], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      const timeStr = new Date().toISOString().replace(/[:.]/g, '-');
      a.href = url;
      a.download = `returnfare-save-${timeStr}.json`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      // 延後撤銷，避免部分瀏覽器（如 iOS Safari）在下載開始前 URL 已失效而取消下載
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch (err) {
      setLocalError(strings.saveError((err as Error).message));
    }
  }

  async function handleImportFileChange(e: ChangeEvent<HTMLInputElement>) {
    clearErrors();
    setStatus('');
    const file = e.target.files?.[0];
    if (!file) return;
    // 立即清空 input 值，允許使用者重新選取同名檔案
    e.target.value = '';

    let text: string;
    try {
      text = await file.text();
    } catch {
      setLocalError(strings.importFileReadError);
      return;
    }

    const decodeRes = controller.decodeImport(text);
    if (!decodeRes.ok) {
      setLocalError(strings.importError(`${decodeRes.error} (${decodeRes.reason_code})`));
      return;
    }

    setConfirmState({
      type: 'import',
      snapshot: decodeRes.state,
      savedAt: decodeRes.envelope.saved_at,
    });
  }

  function handleConfirmDialog() {
    if (!confirmState) return;
    clearErrors();
    if (confirmState.type === 'overwrite') {
      setConfirmState(null);
      executeManualSave();
    } else if (confirmState.type === 'overwriteAuto') {
      setConfirmState(null);
      // 恢復 autosave 並把目前已提交進度寫入 auto；寫入失敗由 controller 回報 onStorageError
      const res = controller.resumeAutosave();
      if (res.ok) {
        setStatus(strings.overwriteAutoSuccess);
      }
    } else if (confirmState.type === 'load') {
      const snap = confirmState.snapshot;
      setConfirmState(null);
      // 手動載入成功確認後，更新 auto 槽位為此快照，避免重新整理後繼續舊的未來進度
      const { game: newGame, autoWriteOk } = controller.applySnapshot(snap, true);
      onReplaceGame(newGame);
      setBannerDismissed(true);
      if (autoWriteOk) {
        setStatus(strings.loadSuccess);
      }
    } else if (confirmState.type === 'import') {
      const snap = confirmState.snapshot;
      setConfirmState(null);
      // 匯入成功確認後，更新 auto 槽位
      const { game: newGame, autoWriteOk } = controller.applySnapshot(snap, true);
      onReplaceGame(newGame);
      setBannerDismissed(true);
      if (autoWriteOk) {
        setStatus(strings.importSuccess);
      }
    }
  }

  // 判斷是否在開局狀態且偵測到先前自動存檔
  const showStartupContinue =
    !bannerDismissed &&
    snapshot.flow.mode === 'opening' &&
    autoSummary.exists &&
    Boolean(autoSummary.saved_at);
  const autosaveSuspended = controller.isAutosaveSuspended();

  const phaseName = autoSummary.phase ? (strings.phases[autoSummary.phase as keyof typeof strings.phases] ?? autoSummary.phase) : '';

  return (
    <aside className="save-panel" role="region" aria-label={strings.saveRegion}>
      {showStartupContinue && (
        <div className="save-continue-banner" data-testid="save-continue-banner">
          <span className="save-continue-info">
            {strings.autoSaveDetected(
              autoSummary.day ?? 1,
              phaseName,
              autoSummary.saved_at ? formatSavedAt(autoSummary.saved_at) : strings.saveNoSlot,
            )}
          </span>
          <button
            type="button"
            className="save-btn save-continue-btn"
            data-testid="continue-auto-btn"
            onClick={handleContinueAuto}
          >
            {strings.continueAuto}
          </button>
        </div>
      )}

      {autosaveSuspended && (
        <div className="save-continue-banner" data-testid="autosave-suspended-banner">
          <span className="save-continue-info">{strings.autosaveSuspendedNote}</span>
          <button
            type="button"
            className="save-btn"
            data-testid="overwrite-auto-btn"
            onClick={() => {
              clearErrors();
              setStatus('');
              setConfirmState({ type: 'overwriteAuto' });
            }}
          >
            {strings.overwriteAuto}
          </button>
        </div>
      )}

      <div className="save-toolbar">
        <span className="save-storage-hint">{strings.saveStorageLocal}</span>
        <div className="save-summary-row">
          <span className="save-slot-summary" data-testid="auto-slot-summary">
            {strings.saveAutoInfo(
              autoSummary.saved_at ? formatSavedAt(autoSummary.saved_at) : strings.saveNoSlot,
            )}
          </span>
          <span className="save-slot-summary" data-testid="manual-slot-summary">
            {strings.saveManualInfo(
              manualSummary.saved_at ? formatSavedAt(manualSummary.saved_at) : strings.saveNoSlot,
            )}
          </span>
        </div>
        <div className="save-actions">
          <button
            type="button"
            className="save-btn"
            data-testid="manual-save-btn"
            onClick={handleManualSaveClick}
          >
            {strings.save}
          </button>
          <button
            type="button"
            className="save-btn"
            data-testid="manual-load-btn"
            disabled={!hasManualSave}
            onClick={handleManualLoadClick}
          >
            {strings.load}
          </button>
          <button
            type="button"
            className="save-btn"
            data-testid="export-btn"
            onClick={handleExportClick}
          >
            {strings.exportSave}
          </button>
          <button
            type="button"
            className="save-btn"
            data-testid="import-btn"
            onClick={() => fileInputRef.current?.click()}
          >
            {strings.importSave}
          </button>
          <input
            ref={fileInputRef}
            type="file"
            accept=".json,application/json"
            className="save-file-input"
            aria-label={strings.importSave}
            data-testid="import-file-input"
            onChange={handleImportFileChange}
          />
        </div>
      </div>

      {error && (
        <p role="alert" className="reason save-error" data-testid="save-error">
          {error}
        </p>
      )}
      {status && (
        <p role="status" className="save-status" data-testid="save-status">
          {status}
        </p>
      )}

      {confirmState && (
        <ModalDialog
          className="save-modal"
          labelledBy="save-dialog-title"
          onClose={() => setConfirmState(null)}
        >
          <div
            className="save-modal-content"
            onKeyDown={(e) => {
              // 阻止按鍵冒泡至 window，避免觸發 EndingPanel 的翻頁與推進
              if ([' ', 'Enter', 'ArrowRight', 'ArrowDown'].includes(e.key)) {
                e.stopPropagation();
              }
            }}
          >
            <h2 id="save-dialog-title">
              {confirmState.type === 'overwrite'
                ? strings.saveConfirmOverwriteTitle
                : confirmState.type === 'overwriteAuto'
                  ? strings.overwriteAutoConfirmTitle
                  : confirmState.type === 'load'
                  ? strings.loadConfirmTitle
                  : strings.importConfirmTitle}
            </h2>
            <p className="story">
              {confirmState.type === 'overwrite'
                ? strings.saveConfirmOverwriteText(
                    manualSummary.saved_at ? formatSavedAt(manualSummary.saved_at) : '',
                  )
                : confirmState.type === 'overwriteAuto'
                  ? strings.overwriteAutoConfirmText
                  : confirmState.type === 'load'
                    ? strings.loadConfirmText(formatSavedAt(confirmState.savedAt))
                    : strings.importConfirmText(formatSavedAt(confirmState.savedAt))}
            </p>
            <div className="dialog-actions">
              <button
                type="button"
                autoFocus
                data-testid="save-dialog-cancel-btn"
                onClick={() => setConfirmState(null)}
              >
                {strings.cancel}
              </button>
              <button
                type="button"
                data-testid="save-dialog-confirm-btn"
                onClick={handleConfirmDialog}
              >
                {strings.confirm}
              </button>
            </div>
          </div>
        </ModalDialog>
      )}
    </aside>
  );
}
