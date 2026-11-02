import type { PhaseView } from '../core/state-types';
import { strings } from './strings';
import { useStoryText } from './use-story-text';
export function NarrationPanel({ view, index, error, canAdvanceDirect, advanceText, onContinue, onAdvance }: {
  view: PhaseView; index: number; error: string; canAdvanceDirect: boolean; advanceText: string;
  onContinue: () => void; onAdvance: () => void;
}) {
  const reading = index < view.lines.length - 1 || (index < view.lines.length && !canAdvanceDirect);
  const passage = view.lines[Math.min(index, view.lines.length - 1)];
  const story = useStoryText([passage ?? ''], `${view.day}:${view.phase}:${index}`);
  return <section className="narration" {...story.revealProps}>
    <header>{strings.status(view.day, strings.phases[view.phase], view.chapter)}</header>
    {passage !== undefined && <p className="story passage">{story.visibleLines[0]}</p>}
    {error && <p role="alert" className="reason">{error}</p>}
    {!story.typing && (reading ? <button onClick={onContinue}>{strings.continue}</button>
      : <button disabled={!view.can_advance} onClick={onAdvance}>{advanceText}</button>)}
  </section>;
}
