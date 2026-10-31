import { useEffect, useRef } from 'react';
import type { CardView } from '../core/state-types';
import { strings } from './strings';

export interface CardDetailProps {
  readonly card?: CardView | null;
  readonly knowledgeList?: readonly CardView[] | null;
  readonly onClose: () => void;
}

export function CardDetail({ card, knowledgeList, onClose }: CardDetailProps) {
  const dialogRef = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    const el = dialogRef.current;
    if (el && !el.open) {
      el.showModal();
    }
  }, []);

  function handleCancel(e: React.SyntheticEvent) {
    e.preventDefault();
    onClose();
  }

  const isKnowledgeMode = Array.isArray(knowledgeList);
  const title = isKnowledgeMode ? strings.knowledgeListTitle : strings.cardDetailTitle;

  return (
    <dialog
      ref={dialogRef}
      className="card-detail-dialog"
      onCancel={handleCancel}
      aria-labelledby="card-dialog-title"
    >
      <h2 id="card-dialog-title">{title}</h2>
      {isKnowledgeMode ? (
        <div className="knowledge-detail-content">
          {knowledgeList.length === 0 ? (
            <p className="empty-knowledge story">{strings.emptyKnowledge}</p>
          ) : (
            <div className="knowledge-list">
              {knowledgeList.map((item) => (
                <div
                  key={item.instanceId}
                  className="knowledge-item"
                  data-testid={`knowledge-item-${item.instanceId}`}
                >
                  <h3 className="knowledge-name">{item.name}</h3>
                  <p className="knowledge-text story">{item.text}</p>
                </div>
              ))}
            </div>
          )}
        </div>
      ) : card ? (
        <div className="card-detail-content">
          <h3 className="card-detail-name">
            {card.countdown !== undefined
              ? strings.cardCountdown(card.name, card.countdown)
              : card.name}
          </h3>
          <p className="card-detail-text story">{card.text}</p>
        </div>
      ) : null}
      <div className="dialog-actions">
        <button type="button" onClick={onClose} autoFocus>
          {strings.close}
        </button>
      </div>
    </dialog>
  );
}
