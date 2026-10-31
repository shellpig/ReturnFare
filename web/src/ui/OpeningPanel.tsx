import { useEffect, useRef, useState } from 'react';
import type { Game, OpeningOptionView } from '../core/state-types';
import { strings } from './strings';
export function OpeningPanel({ game }: { game: Game }) {
  const [selected, setSelected] = useState<OpeningOptionView | null>(null);
  const [error, setError] = useState('');
  const dialog = useRef<HTMLDialogElement>(null);
  const screen = game.openingScreenView();
  const choices = game.openingView();
  useEffect(() => { if (selected) dialog.current?.showModal(); }, [selected]);
  function close() { dialog.current?.close(); setSelected(null); }
  function confirm() {
    if (!selected) return;
    const result = game.chooseOpening(selected.id);
    if (!result.ok) { setError(result.reason_text); close(); }
  }
  return <section className="opening">
    <h1>{screen.title}</h1><p className="story">{screen.prompt}</p>
    <div className="choices">{choices.map(choice => <div key={choice.id}>
      <button disabled={!choice.available} onClick={() => { setError(''); setSelected(choice); }}>{choice.label}</button>
      {!choice.available && <p className="reason">{choice.reason_text}</p>}
    </div>)}</div>
    {error && <p role="alert" className="reason">{error}</p>}
    {selected && <dialog ref={dialog} onCancel={event => { event.preventDefault(); close(); }} aria-labelledby="choice-title">
      <h2 id="choice-title">{selected.label}</h2><p className="story">{selected.preview}</p>
      <p className="story">{selected.confirm_text}</p>
      <div className="dialog-actions"><button onClick={close} autoFocus>{strings.cancel}</button><button onClick={confirm}>{strings.confirm}</button></div>
    </dialog>}
  </section>;
}
