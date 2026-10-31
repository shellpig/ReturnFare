import type { MapLocationView } from '../core/panel';

export function MapPanel({
  locations,
  onSelectLocation,
}: {
  locations: readonly MapLocationView[];
  onSelectLocation: (locationId: string) => void;
}) {
  return (
    <section className="map-panel">
      <div className="map-art-frame">
        <img className="map-art" src="/art/map/town.webp" alt="" />
      </div>
      <div className="map-locations">
        {locations.map((loc) => (
          <button
            key={loc.id}
            type="button"
            disabled={!loc.enabled}
            onClick={() => onSelectLocation(loc.id)}
          >
            {loc.name}
          </button>
        ))}
      </div>
    </section>
  );
}
