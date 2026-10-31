import { TriState, type SlotView as SlotViewModel } from '../core/panel';
import { strings } from './strings';

export function SlotView({ slot }: { slot: SlotViewModel }) {
  const acceptTypesText =
    slot.acceptTypes.length > 0
      ? strings.slotTypes(slot.acceptTypes.join(strings.slotTypesDelimiter))
      : '';

  return (
    <div
      className={`slot-item ${
        slot.tri === TriState.LOCKED
          ? 'slot-locked'
          : slot.tri === TriState.RESOLVED
            ? 'slot-resolved'
            : 'slot-open'
      }`}
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
    </div>
  );
}
