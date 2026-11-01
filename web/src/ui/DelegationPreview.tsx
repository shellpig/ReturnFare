import { useState } from 'react';
import type { SlotView as SlotViewModel } from '../core/panel';
import type { Game } from '../core/state-types';
import { ModalDialog } from './ModalDialog';
import { strings } from './strings';

export function DelegationPreview({
  slot,
  game,
  onClose,
  onConfirm,
}: {
  slot: SlotViewModel;
  game: Game;
  onClose: () => void;
  onConfirm: (personCardId: string) => void;
}) {
  // Candidates: only acquired people appear, in original data ordering from slot.accepts
  const candidateList = slot.accepts
    .map((cardId) => {
      const status = game.delegationStatus(cardId);
      const card = game.cardView(cardId);
      return { cardId, status, card };
    })
    .filter((c) => c.status.held);

  // Default selection: first available candidate (if any)
  const firstAvailable = candidateList.find((c) => c.status.available);
  const [selectedCardId, setSelectedCardId] = useState<string>(
    firstAvailable?.cardId ?? '',
  );

  const del = slot.delegation;
  if (!del) return null;

  const timingText =
    del.resultTiming === 'immediate'
      ? strings.timingImmediate
      : strings.timingNextMorning;

  return (
    <ModalDialog
      className="delegation-preview-dialog"
      labelledBy="delegation-dialog-title"
      onClose={onClose}
    >
      <h3 id="delegation-dialog-title">{strings.delegationDialogTitle}</h3>
      <div className="delegation-preview-content">
        <p className="delegation-task" data-testid="delegation-task-title">
          {strings.delegationTask(del.taskTitle)}
        </p>
        {del.preview && (
          <p className="story delegation-preview-text" data-testid="delegation-preview">
            {del.preview}
          </p>
        )}
        <p className="delegation-timing" data-testid="delegation-timing">
          {timingText}
        </p>
        {del.tendency && (
          <p className="story delegation-tendency" data-testid="delegation-tendency">
            {strings.delegationTendency(del.tendency)}
          </p>
        )}

        <div className="delegation-candidates">
          {candidateList.map((c) => {
            const isUsed = c.status.delegated_today;
            const isSelected = selectedCardId === c.cardId;
            return (
              <button
                type="button"
                key={c.cardId}
                disabled={isUsed}
                className={`candidate-card-btn ${isSelected ? 'selected' : ''} ${isUsed ? 'locked' : ''}`}
                data-testid={isUsed ? `delegated_today-${c.cardId}` : `candidate-${c.cardId}`}
                onClick={() => {
                  if (!isUsed) setSelectedCardId(c.cardId);
                }}
              >
                <span className="candidate-name">{c.card.name}</span>
                {isUsed && (
                  <span className="candidate-status">
                    {strings.delegatedTodaySuffix}
                  </span>
                )}
              </button>
            );
          })}
        </div>

        <div className="dialog-actions">
          <button
            type="button"
            data-testid="dialog-cancel-delegation"
            onClick={onClose}
          >
            {strings.cancel}
          </button>
          <button
            type="button"
            data-testid="dialog-confirm-delegation"
            disabled={!selectedCardId}
            onClick={() => {
              if (selectedCardId) {
                onConfirm(selectedCardId);
              }
            }}
            autoFocus
          >
            {strings.confirm}
          </button>
        </div>
      </div>
    </ModalDialog>
  );
}
