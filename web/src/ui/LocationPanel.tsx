import { useEffect, useRef, useState, type ReactNode } from 'react';
import { TriState, type PanelView, type SlotView as SlotViewModel } from '../core/panel';
import type { Game } from '../core/state-types';
import { SlotView } from './SlotView';
import { strings } from './strings';

const SCENE_ART_LOCATIONS = new Set([
  'bathhouse',
  'busstop',
  'clinic',
  'columbarium',
  'communitycenter',
  'jinghe',
  'oldhouse',
  'oldschool',
  'oldstreet',
  'police',
  'riverside',
  'sanquan',
  'temple',
]);

/** 與 CardDetail 相同以 showModal 開啟，Escape 走 onCancel 關閉。 */
function ModalDialog({
  className,
  labelledBy,
  onClose,
  children,
}: {
  className: string;
  labelledBy: string;
  onClose: () => void;
  children: ReactNode;
}) {
  const dialogRef = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    const el = dialogRef.current;
    if (el && !el.open) {
      el.showModal();
    }
  }, []);

  return (
    <dialog
      ref={dialogRef}
      className={className}
      onCancel={(e) => {
        e.preventDefault();
        onClose();
      }}
      aria-labelledby={labelledBy}
    >
      {children}
    </dialog>
  );
}

export function LocationPanel({
  game,
  panel,
  isPlaying,
  beatTitle,
  beatLines,
  actionResultLines,
  onAdvanceBeat,
  onBack,
  onPlaceCard,
  onChooseSlot,
}: {
  game: Game;
  panel: PanelView;
  isPlaying: boolean;
  beatTitle: string;
  beatLines: readonly string[];
  actionResultLines: readonly string[];
  onAdvanceBeat: () => void;
  onBack: () => void;
  onPlaceCard: (cardId: string, beatId: string, slotId: string) => void;
  onChooseSlot: (beatId: string, groupId: string, slotId: string) => void;
}) {
  const [pickerTarget, setPickerTarget] = useState<{
    beatId: string;
    slot: SlotViewModel;
  } | null>(null);
  const [previewTarget, setPreviewTarget] = useState<{
    beatId: string;
    slot: SlotViewModel;
  } | null>(null);

  const hasSceneArt = SCENE_ART_LOCATIONS.has(panel.location.id);

  return (
    <section className="location-panel">
      <div className="location-header">
        <h2>{panel.location.name}</h2>
        <button type="button" onClick={onBack}>
          {strings.backToMap}
        </button>
      </div>

      {hasSceneArt && (
        <div className="scene-art-frame">
          <img
            className="scene-art"
            src={`/art/scenes/${panel.location.id}.webp`}
            alt={panel.location.name}
          />
        </div>
      )}

      {isPlaying ? (
        <div className="beat-stage">
          <h3 className="beat-title">{beatTitle || strings.noTitle}</h3>
          <p className="story beat-text" aria-live="polite">
            {beatLines.join('\n\n')}
          </p>
          <button type="button" onClick={onAdvanceBeat}>
            {strings.continue}
          </button>
        </div>
      ) : (
        <div className="slots-stage">
          {actionResultLines && actionResultLines.length > 0 && (
            <div className="action-result-box" data-testid="action-result">
              {actionResultLines.map((line, idx) => (
                <p
                  key={idx}
                  className="story action-result-line"
                  aria-live="polite"
                >
                  {line}
                </p>
              ))}
            </div>
          )}
          {panel.location.desc && (
            <p className="story location-desc">{panel.location.desc}</p>
          )}
          <div className="beats-list">
            {panel.beats.map((beat) => {
              const visibleSlots = beat.slots.filter(
                (slot) =>
                  slot.tri !== TriState.HIDDEN &&
                  !(slot.tri === TriState.RESOLVED && !slot.isChoice),
              );
              const titleText =
                (beat.title || strings.noTitle) +
                (beat.tri === TriState.LOCKED && beat.reason
                  ? `  ${beat.reason}`
                  : '');

              return (
                <div key={beat.id} className="beat-group">
                  <h3 className="beat-group-title">{titleText}</h3>
                  <div className="slot-list">
                    {visibleSlots.map((slot) => (
                      <SlotView
                        key={slot.id}
                        slot={slot}
                        onSelectSlot={() =>
                          setPickerTarget({ beatId: beat.id, slot })
                        }
                        onPreviewSlot={() =>
                          setPreviewTarget({ beatId: beat.id, slot })
                        }
                        onChooseSlot={() =>
                          onChooseSlot(beat.id, slot.choiceGroup, slot.id)
                        }
                      />
                    ))}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {pickerTarget && (
        <ModalDialog
          className="card-picker-dialog"
          labelledBy="picker-dialog-title"
          onClose={() => setPickerTarget(null)}
        >
          <h3 id="picker-dialog-title">
            {strings.placeCard}：{pickerTarget.slot.label}
          </h3>
          {(() => {
            const candidates = game.placeableCards(
              pickerTarget.beatId,
              pickerTarget.slot.id,
            );
            if (candidates.length === 0) {
              return (
                <div className="picker-empty-content">
                  <p className="story empty-candidates">
                    {strings.noPlaceableCards}
                  </p>
                  <div className="dialog-actions">
                    <button
                      type="button"
                      onClick={() => setPickerTarget(null)}
                      autoFocus
                    >
                      {strings.close}
                    </button>
                  </div>
                </div>
              );
            }
            return (
              <div className="picker-candidates-content">
                <div className="candidate-list">
                  {candidates.map((cardId) => {
                    const card = game.cardView(cardId);
                    return (
                      <button
                        type="button"
                        key={cardId}
                        className="candidate-card-btn"
                        data-testid={`candidate-${cardId}`}
                        onClick={() => {
                          const bId = pickerTarget.beatId;
                          const sId = pickerTarget.slot.id;
                          setPickerTarget(null);
                          onPlaceCard(cardId, bId, sId);
                        }}
                      >
                        <span className="candidate-name">{card.name}</span>
                        {card.text && (
                          <span className="candidate-text story">
                            {card.text}
                          </span>
                        )}
                      </button>
                    );
                  })}
                </div>
                <div className="dialog-actions">
                  <button type="button" onClick={() => setPickerTarget(null)}>
                    {strings.cancel}
                  </button>
                </div>
              </div>
            );
          })()}
        </ModalDialog>
      )}

      {previewTarget && (
        <ModalDialog
          className="slot-preview-dialog"
          labelledBy="preview-dialog-title"
          onClose={() => setPreviewTarget(null)}
        >
          <h3 id="preview-dialog-title">
            {strings.preview}：{previewTarget.slot.label}
          </h3>
          {(() => {
            const preview = game.previewSlot(
              previewTarget.beatId,
              previewTarget.slot.id,
            );
            return (
              <div className="preview-content">
                {preview.cards.length > 0 ? (
                  <div className="preview-cards">
                    <p className="preview-heading">
                      {strings.placeableCardsTitle}
                    </p>
                    <ul className="preview-list">
                      {preview.cards.map((cardId) => (
                        <li key={cardId} className="preview-item">
                          {game.cardView(cardId).name}
                        </li>
                      ))}
                    </ul>
                  </div>
                ) : (
                  <div className="preview-empty">
                    <p className="story">{strings.noPlaceableCards}</p>
                    {preview.reason && (
                      <p className="reason preview-reason">
                        {strings.previewReason(
                          strings.reasonCodes[preview.reason] ?? preview.reason,
                        )}
                      </p>
                    )}
                  </div>
                )}
                <div className="dialog-actions">
                  <button
                    type="button"
                    onClick={() => setPreviewTarget(null)}
                    autoFocus
                  >
                    {strings.close}
                  </button>
                </div>
              </div>
            );
          })()}
        </ModalDialog>
      )}
    </section>
  );
}
