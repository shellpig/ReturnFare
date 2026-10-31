import { useState } from 'react';
import type { Game } from '../core/state-types';
import { useGame } from './use-game';
import { OpeningPanel } from './OpeningPanel';
import { NarrationPanel } from './NarrationPanel';
export function GameShell({ game }: { game: Game }) {
  const snapshot = useGame(game);
  const [index, setIndex] = useState(0);
  const [error, setError] = useState('');
  if (snapshot.flow.mode === 'opening') return <OpeningPanel game={game} />;
  const view = game.getPhaseView();
  function advance() {
    const result = game.advancePhase();
    if (!result.ok) { setError(result.reason_text); return; }
    setIndex(0); setError('');
    const phase = game.getPhaseView().phase;
    const performance = phase === 'evening' ? game.playEvening() : phase === 'night' ? game.playNightFixed() : null;
    if (performance && !performance.ok) setError(performance.reason_text);
  }
  return <NarrationPanel view={view} index={index} error={error}
    onContinue={() => setIndex(current => Math.min(current + 1, view.lines.length))} onAdvance={advance} />;
}
