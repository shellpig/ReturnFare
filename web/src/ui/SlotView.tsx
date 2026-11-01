import { TriState, type SlotView as SlotViewModel } from '../core/panel';
import { strings } from './strings';

export function SlotView({
  slot,
  onSelectSlot,
  onPreviewSlot,
  onChooseSlot,
}: {
  slot: SlotViewModel;
  onSelectSlot?: () => void;
  onPreviewSlot?: () => void;
  onChooseSlot?: () => void;
}) {
  const acceptTypesText =
    slot.acceptTypes.length > 0
      ? strings.slotTypes(slot.acceptTypes.join(strings.slotTypesDelimiter))
      : '';

  const canDirectChoose =
    slot.tri === TriState.OPEN && slot.isChoice && !slot.choiceRequiresCard;

  const canPlace =
    slot.tri === TriState.OPEN && slot.accepts.length > 0 && !slot.delegation;

  const canInteractive = canPlace || canDirectChoose;

  function handleContextMenu(e: React.MouseEvent) {
    e.preventDefault();
    if (onPreviewSlot) {
      onPreviewSlot();
    }
  }

  function handleClick() {
    if (canDirectChoose && !canPlace && onChooseSlot) {
      onChooseSlot();
    } else if (canPlace && !canDirectChoose && onSelectSlot) {
      onSelectSlot();
    }
  }

  return (
    <div
      className={`slot-item ${
        slot.tri === TriState.LOCKED
          ? 'slot-locked'
          : slot.tri === TriState.RESOLVED
            ? 'slot-resolved'
            : 'slot-open'
      } ${canInteractive ? 'slot-interactive' : ''}`}
      data-testid={`slot-${slot.id}`}
      onClick={handleClick}
      onContextMenu={handleContextMenu}
    >
      <div className="slot-header">
        {slot.occupant && !slot.label.includes(slot.occupant.name) && (
          <span className="slot-occupant">{slot.occupant.name}</span>
        )}
        <span className="slot-label">{slot.label}</span>
        {acceptTypesText && (
          <span className="slot-accept-types">{acceptTypesText}</span>
        )}
      </div>
      {slot.delegation?.preview && (
        <p className="slot-delegation-preview">{slot.delegation.preview}</p>
      )}
      {slot.delegation?.tendency && (
        <p className="slot-delegation-tendency">{slot.delegation.tendency}</p>
      )}
      {slot.tri === TriState.LOCKED && slot.reason && (
        <p className="reason slot-reason">{slot.reason}</p>
      )}
      {(canDirectChoose || canPlace) && (
        <div className="slot-actions">
          {canDirectChoose && (
            <button
              type="button"
              className="slot-choose-btn"
              data-testid={`choose-btn-${slot.id}`}
              onClick={(e) => {
                e.stopPropagation();
                if (onChooseSlot) onChooseSlot();
              }}
            >
              {strings.choose}
            </button>
          )}
          {canPlace && (
            <button
              type="button"
              className="slot-place-btn"
              data-testid={`place-btn-${slot.id}`}
              onClick={(e) => {
                e.stopPropagation();
                if (onSelectSlot) onSelectSlot();
              }}
            >
              {strings.placeCard}
            </button>
          )}
        </div>
      )}
    </div>
  );
}
