import { TriState, type PanelView } from '../core/panel';
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

export function LocationPanel({
  panel,
  isPlaying,
  beatTitle,
  beatLines,
  onAdvanceBeat,
  onBack,
}: {
  panel: PanelView;
  isPlaying: boolean;
  beatTitle: string;
  beatLines: readonly string[];
  onAdvanceBeat: () => void;
  onBack: () => void;
}) {
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
                      <SlotView key={slot.id} slot={slot} />
                    ))}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </section>
  );
}
