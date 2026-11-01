import { useEffect, useState } from 'react';
import { TriState } from '../core/panel';
import type { Game } from '../core/state-types';
import { EncounterPanel } from './EncounterPanel';
import { EndingPanel } from './EndingPanel';
import { HandPanel } from './HandPanel';
import { LocationPanel } from './LocationPanel';
import { MapPanel } from './MapPanel';
import { ModalDialog } from './ModalDialog';
import { NightDetails } from './NightDetails';
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
  actionResultLines: readonly string[];
}

export function GameShell({ game }: { game: Game }) {
  const snapshot = useGame(game);
  const [index, setIndex] = useState(0);
  const [error, setError] = useState('');
  const [activeLocation, setActiveLocation] =
    useState<ActiveLocationState | null>(null);
  // 夜間地點詳情（唯讀）；進入前不改任何狀態。
  const [nightDetailId, setNightDetailId] = useState<string | null>(null);
  // 遭遇歷程文字與結束後的結果文字（W6-D）。
  const [encounterActionLines, setEncounterActionLines] = useState<readonly string[]>([]);
  const [encounterResultLines, setEncounterResultLines] = useState<readonly string[]>([]);

  // 離開 run（進結局或回開局）時清掉上一輪的面板、演出進度與錯誤，避免殘留到下一輪。
  useEffect(() => {
    if (snapshot.flow.mode !== 'run') {
      setActiveLocation(null);
      setNightDetailId(null);
      setIndex(0);
      setError('');
      setEncounterActionLines([]);
      setEncounterResultLines([]);
    }
  }, [snapshot.flow.mode]);

  if (snapshot.flow.mode === 'opening') {
    return <OpeningPanel game={game} />;
  }
  if (snapshot.flow.mode === 'ending') {
    return <EndingPanel game={game} />;
  }

  const view = game.getPhaseView();

  function advance() {
    const result = game.advancePhase();
    if (!result.ok) {
      setError(result.reason_text);
      return;
    }
    setActiveLocation(null);
    setNightDetailId(null);
    setIndex(0);
    setError('');
    setEncounterActionLines([]);
    setEncounterResultLines([]);
    // 夜間睡覺停拍沒有換時段：睡覺文字已是這個時段要讀的演出，不再重播入夜 fixed。
    if (!result.phase_advanced) {
      return;
    }
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

  function openLocation(locationId: string, entryLines: readonly string[] = []) {
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
        actionResultLines: entryLines,
      });
    } else {
      setActiveLocation({
        locationId,
        isPlaying: false,
        playedBeatIds: [],
        beatTitle: '',
        beatLines: [],
        actionResultLines: entryLines,
      });
    }
  }

  function enterNightLocation(locationId: string) {
    const result = game.enterNightLocation(locationId);
    if (!result.ok) {
      setError(
        result.reason_text ||
          strings.reasonCodes[result.reason_code] ||
          strings.reasonFallback,
      );
      return;
    }
    setNightDetailId(null);
    // 撞發狂上限已進結局：不再開原地點面板，畫面交給結局流程。
    if (game.getSnapshot().flow.mode !== 'run') {
      return;
    }
    openLocation(locationId, result.lines);
  }

  function confirmAlignment(dayLocationId: string) {
    const result = game.confirmNightAlignment(dayLocationId);
    if (!result.ok) {
      setError(
        result.reason_text ||
          strings.reasonCodes[result.reason_code] ||
          strings.reasonFallback,
      );
      return;
    }
    setError('');
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
        ...activeLocation,
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

  function handleActionResult(result: {
    ok: boolean;
    reason_code: string;
    reason_text: string;
    lines: readonly string[];
  }) {
    if (result.ok) {
      setError('');
      setActiveLocation((current) =>
        current
          ? {
              ...current,
              actionResultLines: result.lines,
            }
          : null,
      );
    } else {
      setError(
        strings.placeFailed(
          result.reason_text ||
            strings.reasonCodes[result.reason_code] ||
            result.reason_code,
        ),
      );
    }
  }

  function handlePlaceCard(cardId: string, beatId: string, slotId: string) {
    handleActionResult(game.tryPlace(cardId, beatId, slotId));
  }

  function handleChooseSlot(
    beatId: string,
    groupId: string,
    slotId: string,
    cardId?: string,
  ) {
    handleActionResult(game.choose(beatId, groupId, slotId, cardId));
  }

  function handleDelegate(
    beatId: string,
    slotId: string,
    personCardId: string,
  ) {
    handleActionResult(game.delegate(beatId, slotId, personCardId));
  }

  function handleEncounterMutation(result: {
    ok: boolean;
    reason_code: string;
    reason_text: string;
    lines: readonly string[];
  }) {
    if (!result.ok) {
      setError(
        result.reason_text ||
          strings.reasonCodes[result.reason_code] ||
          result.reason_code,
      );
      return;
    }
    setError('');
    const curEnc = game.encounterView();
    if (!('stage' in curEnc)) {
      setEncounterResultLines(result.lines);
      setEncounterActionLines([]);
    } else {
      setEncounterActionLines(result.lines);
    }
  }

  function handleAckIntro() {
    handleEncounterMutation(game.acknowledgeEncounterIntro());
  }

  function handleRespondEncounter(cardId: string) {
    handleEncounterMutation(game.respondToEncounter(cardId));
  }

  function handleDiscardEncounter(cardId: string) {
    handleEncounterMutation(game.discardInEncounter(cardId));
  }

  function handleEscapeEncounter(cardIds: readonly string[]) {
    handleEncounterMutation(game.escapeEncounter(cardIds));
  }

  let advanceText: string = strings.advance;
  if (view.phase === 'morning' || view.phase === 'afternoon') {
    const hasAction = game.hasAnyLegalAction();
    const hasUnseen = game.hasUnseenContent();
    if (hasAction) {
      advanceText = strings.advance;
    } else if (hasUnseen) {
      advanceText = strings.advanceUnseen;
    } else {
      advanceText = strings.advanceHint;
    }
  }

  // 夜間主按鈕三態沿 scenes/main.gd：直接睡／結束今晚／進入隔天（由規則層的 night_advance 衍生）。
  if (view.night_advance === 'sleep') {
    advanceText = strings.advanceSleep;
  } else if (view.night_advance === 'end_night') {
    advanceText = strings.advanceEndNight;
  } else if (view.night_advance === 'next_day') {
    advanceText = strings.advanceNextDay;
  }

  const delegationTutorial = view.delegation_tutorial_available && (
    <ModalDialog
      className="delegation-tutorial-dialog"
      labelledBy="delegation-tutorial-title"
      onClose={() => game.markDelegationTutorialSeen()}
    >
      <h3 id="delegation-tutorial-title">{strings.delegationTutorialTitle}</h3>
      <p className="story tutorial-text">{strings.delegationTutorialText}</p>
      <div className="dialog-actions">
        <button
          type="button"
          data-testid="dialog-confirm-delegation-tutorial"
          onClick={() => game.markDelegationTutorialSeen()}
          autoFocus
        >
          {strings.confirm}
        </button>
      </div>
    </ModalDialog>
  );

  const encounterView = game.encounterView();
  if ('stage' in encounterView) {
    return (
      <section className="encounter-shell">
        <header>
          {strings.status(view.day, strings.phases[view.phase], view.chapter)}
        </header>
        <EncounterPanel
          game={game}
          introLines={view.lines}
          lastActionLines={encounterActionLines}
          onAckIntro={handleAckIntro}
          onRespond={handleRespondEncounter}
          onDiscard={handleDiscardEncounter}
          onEscape={handleEscapeEncounter}
        />
        {error && (
          <p role="alert" className="reason">
            {error}
          </p>
        )}
        <HandPanel game={game} />
        {delegationTutorial}
      </section>
    );
  }

  if (view.narration_only || index < view.lines.length) {
    return (
      <section className="narration-shell">
        {encounterResultLines.length > 0 && (
          <div className="encounter-result-banner" data-testid="encounter-result">
            {encounterResultLines.map((line, idx) => (
              <p key={idx} className="story encounter-result-line">
                {line}
              </p>
            ))}
          </div>
        )}
        {view.forced_lines.length > 0 && (
          <div className="forced-narrative-banner" data-testid="forced-narrative">
            {view.forced_lines.map((line, idx) => (
              <p key={idx} className="story forced-line">
                {line}
              </p>
            ))}
          </div>
        )}
        {view.delegation_report_lines.length > 0 && (
          <div className="delegation-report-banner" data-testid="delegation-report">
            {view.delegation_report_lines.map((line, idx) => (
              <p key={idx} className="story delegation-report-line" aria-live="polite">
                {line}
              </p>
            ))}
          </div>
        )}
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
        {delegationTutorial}
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
          game={game}
          panel={game.buildPanel(activeLocation.locationId)}
          isPlaying={activeLocation.isPlaying}
          beatTitle={activeLocation.beatTitle}
          beatLines={activeLocation.beatLines}
          actionResultLines={activeLocation.actionResultLines}
          onAdvanceBeat={advanceBeatInLocation}
          onBack={() => setActiveLocation(null)}
          onPlaceCard={handlePlaceCard}
          onChooseSlot={handleChooseSlot}
          onConfirmAlignment={confirmAlignment}
          onDelegate={handleDelegate}
        />
      ) : nightDetailId ? (
        <NightDetails
          locationId={nightDetailId}
          summary={game.nightLocationSummary(nightDetailId)}
          onEnter={enterNightLocation}
          onBack={() => setNightDetailId(null)}
        />
      ) : (
        <>
          {encounterResultLines.length > 0 && (
            <div className="encounter-result-banner" data-testid="encounter-result">
              {encounterResultLines.map((line, idx) => (
                <p key={idx} className="story encounter-result-line">
                  {line}
                </p>
              ))}
            </div>
          )}
          {view.forced_lines.length > 0 && (
            <div className="forced-narrative-banner" data-testid="forced-narrative">
              {view.forced_lines.map((line, idx) => (
                <p key={idx} className="story forced-line">
                  {line}
                </p>
              ))}
            </div>
          )}
          {view.delegation_report_lines.length > 0 && (
            <div className="delegation-report-banner" data-testid="delegation-report">
              {view.delegation_report_lines.map((line, idx) => (
                <p key={idx} className="story delegation-report-line" aria-live="polite">
                  {line}
                </p>
              ))}
            </div>
          )}
          <MapPanel
            locations={game.mapView()}
            onSelectLocation={view.phase === 'night' ? setNightDetailId : openLocation}
          />
        </>
      )}
      {error && (
        <p role="alert" className="reason">
          {error}
        </p>
      )}
      <div className="phase-actions">
        {!activeLocation && view.phase_exit !== null && !view.phase_exit.satisfied && (
          <button
            type="button"
            data-testid="phase-exit-open"
            onClick={() => openLocation(view.phase_exit!.location_id)}
          >
            {strings.continue}
          </button>
        )}
        <button
          type="button"
          disabled={!view.can_advance}
          onClick={advance}
        >
          {advanceText}
        </button>
      </div>
      <HandPanel game={game} />
      {delegationTutorial}
    </section>
  );
}
