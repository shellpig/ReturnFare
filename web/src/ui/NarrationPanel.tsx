import type { PhaseView } from '../core/state-types';
import type { GameData } from '../data/types';
import { storyArtFor } from './story-art';
import { strings } from './strings';
import { useStoryText } from './use-story-text';
export function NarrationPanel({ view, data, index, error, canAdvanceDirect, advanceText, onContinue, onAdvance }: {
  view: PhaseView; data: GameData; index: number; error: string; canAdvanceDirect: boolean; advanceText: string;
  onContinue: () => void; onAdvance: () => void;
}) {
  const reading = index < view.lines.length - 1 || (index < view.lines.length && !canAdvanceDirect);
  const passage = view.lines[Math.min(index, view.lines.length - 1)];
  const story = useStoryText([passage ?? ''], `${view.day}:${view.phase}:${index}`);
  const art = storyArtFor(data, passage);
  return <section className="narration" {...story.revealProps}>
    <header>{strings.status(view.day, strings.phases[view.phase], view.chapter)}</header>
    {art && <div className="scene-art-frame"><img className="scene-art story-art" src={art} alt="" /></div>}
    {passage !== undefined && <p className="story passage">{story.visibleLines[0]}</p>}
    {error && <p role="alert" className="reason">{error}</p>}
    {!story.typing && (reading ? <button onClick={onContinue}>{strings.continue}</button>
      : <button disabled={!view.can_advance} onClick={onAdvance}>{advanceText}</button>)}
  </section>;
}
