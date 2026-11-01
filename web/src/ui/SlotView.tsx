import { TriState, type SlotView as SlotViewModel } from '../core/panel';
import { strings } from './strings';

export function SlotView({
  slot,
  onSelectSlot,
  onPreviewSlot,
}: {
  slot: SlotViewModel;
  onSelectSlot?: () => void;
  onPreviewSlot?: () => void;
}) {
  const acceptTypesText =
    slot.acceptTypes.length > 0
      ? strings.slotTypes(slot.acceptTypes.join(strings.slotTypesDelimiter))
      : '';

  const canPlace =
    slot.tri === TriState.OPEN &&
    slot.accepts.length > 0 &&
    !slot.isChoice &&
    !slot.delegation;

  function handleContextMenu(e: React.MouseEvent) {
    e.preventDefault();
    if (onPreviewSlot) {
      onPreviewSlot();
    }
  }

  function handleClick() {
    if (canPlace && onSelectSlot) {
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
      } ${canPlace ? 'slot-interactive' : ''}`}
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
      {canPlace && (
        <div className="slot-actions">
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
        </div>
      )}
    </div>
  );
}
