import { useLayoutEffect, useRef, useState } from 'react';
import type { MapLocationView } from '../core/panel';
import { townMapLayout } from './town-map-layout';
import { ZoomableArt } from './ZoomableArt';

export function MapPanel({
  locations,
  onSelectLocation,
}: {
  locations: readonly MapLocationView[];
  onSelectLocation: (locationId: string) => void;
}) {
  const frame = useRef<HTMLDivElement>(null);
  const [highlighted, setHighlighted] = useState<string | null>(null);

  useLayoutEffect(() => {
    const element = frame.current;
    if (!element) return;
    function layoutLabels() {
      if (!element) return;
      const width = element.clientWidth;
      const height = element.clientHeight;
      if (!width || !height) return;
      const placed: { left: number; top: number; right: number; bottom: number }[] = [];
      const markers = [...element.querySelectorAll<HTMLElement>('.map-marker')];
      const dots = markers.map(marker => ({
        x: Number(marker.dataset.x) * width / 100,
        y: Number(marker.dataset.y) * height / 100,
      }));
      markers.forEach((marker, index) => {
        const label = marker.querySelector<HTMLElement>('.map-marker-name')!;
        const { x, y } = dots[index];
        const w = label.offsetWidth;
        const h = label.offsetHeight;
        let best = { left: 0, top: 0, score: Infinity };
        for (const gap of [12, 24, 40, 60, 84]) {
          for (const [dx, dy] of [[-w / 2, -h - gap], [gap, -h / 2], [-w - gap, -h / 2], [-w / 2, gap]]) {
            const left = Math.max(4, Math.min(width - w - 4, x + dx));
            const top = Math.max(4, Math.min(height - h - 4, y + dy));
            const right = left + w;
            const bottom = top + h;
            let score = Math.hypot(left - x - dx, top - y - dy);
            for (const box of placed) {
              score += Math.max(0, Math.min(right + 3, box.right) - Math.max(left - 3, box.left)) *
                Math.max(0, Math.min(bottom + 3, box.bottom) - Math.max(top - 3, box.top)) * 100;
            }
            for (const dot of dots) {
              if (dot.x > left - 7 && dot.x < right + 7 && dot.y > top - 7 && dot.y < bottom + 7) score += 10000;
            }
            if (score < best.score) best = { left, top, score };
          }
          if (best.score === 0) break;
        }
        placed.push({ left: best.left, top: best.top, right: best.left + w, bottom: best.top + h });
        label.style.left = `${best.left - x}px`;
        label.style.top = `${best.top - y}px`;
        const endX = Math.max(best.left, Math.min(best.left + w, x));
        const endY = Math.max(best.top, Math.min(best.top + h, y));
        const line = marker.querySelector<HTMLElement>('.map-marker-line')!;
        line.style.width = `${Math.hypot(endX - x, endY - y)}px`;
        line.style.transform = `rotate(${Math.atan2(endY - y, endX - x)}rad)`;
      });
    }
    const observer = new ResizeObserver(layoutLabels);
    observer.observe(element);
    let active = true;
    void document.fonts.ready.then(() => { if (active) layoutLabels(); });
    layoutLabels();
    return () => { active = false; observer.disconnect(); };
  }, [locations]);

  return (
    <section className="map-panel">
      <ZoomableArt className="map-art-frame" canvasRef={frame}>
        <img className="map-art" src="/art/map/town.webp" alt="" />
        <div className="map-markers">
          {locations.map(loc => {
            const position = townMapLayout[loc.id];
            if (!position) return null;
            return <div key={loc.id} className="map-marker" data-location={loc.id}
              data-x={position.x} data-y={position.y} data-enabled={loc.enabled}
              data-has-event={loc.hasEvent}
              data-highlighted={loc.enabled && highlighted === loc.id}
              onClick={() => { if (loc.enabled) onSelectLocation(loc.id); }}
              onMouseEnter={() => setHighlighted(loc.id)}
              onMouseLeave={() => setHighlighted(null)}
              onFocus={() => setHighlighted(loc.id)}
              onBlur={() => setHighlighted(null)}
              style={{ left: `${position.x}%`, top: `${position.y}%` }}>
              <span className="map-marker-line" aria-hidden="true" />
              <span className="map-marker-dot" aria-hidden="true" />
              <button type="button" className="map-marker-name" disabled={!loc.enabled}>{loc.name}</button>
            </div>;
          })}
        </div>
      </ZoomableArt>
    </section>
  );
}
