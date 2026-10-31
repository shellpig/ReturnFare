import type { PhaseView } from '../core/state-types';
import { strings } from './strings';
export function NarrationPanel({ view, index, error, onContinue, onAdvance }: {
  view: PhaseView; index: number; error: string; onContinue: () => void; onAdvance: () => void;
}) {
  const reading = index < view.lines.length;
  return <section className="narration">
    <header>{strings.status(view.day, strings.phases[view.phase], view.chapter)}</header>
    {reading && <p className="story passage" aria-live="polite">{view.lines[index]}</p>}
    {error && <p role="alert" className="reason">{error}</p>}
    {reading ? <button onClick={onContinue}>{strings.continue}</button>
      : <button disabled={!view.can_advance || Boolean(error)} onClick={onAdvance}>{strings.advance}</button>}
  </section>;
}
