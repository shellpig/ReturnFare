import { TriState, type SlotView as SlotViewModel } from '../core/panel';
import { strings } from './strings';

export function SlotView({
  slot,
  onSelectSlot,
  onPreviewSlot,
  onChooseSlot,
  onSelectDelegation,
}: {
  slot: SlotViewModel;
  onSelectSlot?: () => void;
  onPreviewSlot?: () => void;
  onChooseSlot?: () => void;
  onSelectDelegation?: () => void;
}) {
  const acceptTypesText =
    slot.acceptTypes.length > 0
      ? strings.slotTypes(slot.acceptTypes.join(strings.slotTypesDelimiter))
      : '';

  const isDelegation = Boolean(slot.delegation);
  const isDisplayOnly = slot.accepts.length === 0 && !slot.isChoice && !isDelegation;

  const canDirectChoose =
    slot.tri === TriState.OPEN &&
    slot.isChoice &&
    !slot.choiceRequiresCard &&
    !isDelegation;

  const canPlace =
    slot.tri === TriState.OPEN && slot.accepts.length > 0 && !isDelegation;

  const canDelegate =
    slot.tri === TriState.OPEN && isDelegation;

  const canInteractive = canPlace || canDirectChoose || canDelegate;

  function handleContextMenu(e: React.MouseEvent) {
    e.preventDefault();
    if (onPreviewSlot) {
      onPreviewSlot();
    }
  }

  function handleClick() {
    if (canDelegate && onSelectDelegation) {
      onSelectDelegation();
    } else if (canDirectChoose && !canPlace && onChooseSlot) {
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
      } ${canInteractive ? 'slot-interactive' : ''} ${isDisplayOnly ? 'slot-display' : ''}`}
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
      {(canDirectChoose || canPlace || canDelegate) && (
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
          {canDelegate && (
            <button
              type="button"
              className="slot-delegate-btn"
              data-testid={`delegate-btn-${slot.id}`}
              onClick={(e) => {
                e.stopPropagation();
                if (onSelectDelegation) onSelectDelegation();
              }}
            >
              {strings.delegate}
            </button>
          )}
        </div>
      )}
    </div>
  );
}
