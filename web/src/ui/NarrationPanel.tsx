import type { PhaseView } from '../core/state-types';
import { strings } from './strings';
export function NarrationPanel({ view, index, error, onContinue, onAdvance }: {
  view: PhaseView; index: number; error: string; onContinue: () => void; onAdvance: () => void;
}) {
  const reading = index < view.lines.length;
  const passage = view.lines[Math.min(index, view.lines.length - 1)];
  return <section className="narration">
    <header>{strings.status(view.day, strings.phases[view.phase], view.chapter)}</header>
    {passage !== undefined && <p className="story passage" aria-live="polite">{passage}</p>}
    {error && <p role="alert" className="reason">{error}</p>}
    {reading ? <button onClick={onContinue}>{strings.continue}</button>
      : <button disabled={!view.can_advance} onClick={onAdvance}>{strings.advance}</button>}
  </section>;
}
