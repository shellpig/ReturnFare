import { useState } from 'react';
import { TriState } from '../core/panel';
import type { Game } from '../core/state-types';
import { HandPanel } from './HandPanel';
import { LocationPanel } from './LocationPanel';
import { MapPanel } from './MapPanel';
import { NarrationPanel } from './NarrationPanel';
import { OpeningPanel } from './OpeningPanel';
import { strings } from './strings';
import { useGame } from './use-game';

interface ActiveLocationState {
  locationId: string;
  isPlaying: boolean;
  playedBeatIds: string[];
  beatTitle: string;
  beatLines: readonly string[];
}

export function GameShell({ game }: { game: Game }) {
  const snapshot = useGame(game);
  const [index, setIndex] = useState(0);
  const [error, setError] = useState('');
  const [activeLocation, setActiveLocation] =
    useState<ActiveLocationState | null>(null);

  if (snapshot.flow.mode === 'opening') {
    return <OpeningPanel game={game} />;
  }

  const view = game.getPhaseView();

  function advance() {
    const result = game.advancePhase();
    if (!result.ok) {
      setError(result.reason_text);
      return;
    }
    setActiveLocation(null);
    setIndex(0);
    setError('');
    const phase = game.getPhaseView().phase;
    const performance =
      phase === 'evening'
        ? game.playEvening()
        : phase === 'night'
          ? game.playNightFixed()
          : null;
    if (performance && !performance.ok) {
      setError(performance.reason_text);
    }
  }

  function openLocation(locationId: string) {
    setError('');
    game.markDayLocationVisited(locationId);
    const panel = game.buildPanel(locationId);
    const firstOpen = panel.beats.find((b) => b.tri === TriState.OPEN);
    if (firstOpen) {
      const res = game.playBeat(firstOpen.id);
      if (!res.ok) {
        setError(res.reason_text);
        return;
      }
      setActiveLocation({
        locationId,
        isPlaying: true,
        playedBeatIds: [firstOpen.id],
        beatTitle: firstOpen.title || strings.noTitle,
        beatLines: res.lines,
      });
    } else {
      setActiveLocation({
        locationId,
        isPlaying: false,
        playedBeatIds: [],
        beatTitle: '',
        beatLines: [],
      });
    }
  }

  function advanceBeatInLocation() {
    if (!activeLocation) return;
    const freshPanel = game.buildPanel(activeLocation.locationId);
    const nextOpen = freshPanel.beats.find(
      (b) =>
        b.tri === TriState.OPEN && !activeLocation.playedBeatIds.includes(b.id),
    );
    if (nextOpen) {
      const res = game.playBeat(nextOpen.id);
      if (!res.ok) {
        setError(res.reason_text);
        return;
      }
      setActiveLocation({
        locationId: activeLocation.locationId,
        isPlaying: true,
        playedBeatIds: [...activeLocation.playedBeatIds, nextOpen.id],
        beatTitle: nextOpen.title || strings.noTitle,
        beatLines: res.lines,
      });
    } else {
      setActiveLocation({
        ...activeLocation,
        isPlaying: false,
      });
    }
  }

  if (view.narration_only || view.phase === 'night' || index < view.lines.length) {
    return (
      <section className="narration-shell">
        <NarrationPanel
          view={view}
          index={index}
          error={error}
          onContinue={() =>
            setIndex((current) => Math.min(current + 1, view.lines.length))
          }
          onAdvance={advance}
        />
        <HandPanel game={game} />
      </section>
    );
  }

  return (
    <section className="daytime-shell">
      <header>
        {strings.status(view.day, strings.phases[view.phase], view.chapter)}
      </header>
      {activeLocation ? (
        <LocationPanel
          panel={game.buildPanel(activeLocation.locationId)}
          isPlaying={activeLocation.isPlaying}
          beatTitle={activeLocation.beatTitle}
          beatLines={activeLocation.beatLines}
          onAdvanceBeat={advanceBeatInLocation}
          onBack={() => setActiveLocation(null)}
        />
      ) : (
        <MapPanel
          locations={game.mapView()}
          onSelectLocation={openLocation}
        />
      )}
      {error && (
        <p role="alert" className="reason">
          {error}
        </p>
      )}
      <div className="phase-actions">
        <button
          type="button"
          disabled={!view.can_advance}
          onClick={advance}
        >
          {strings.advance}
        </button>
      </div>
      <HandPanel game={game} />
    </section>
  );
}
