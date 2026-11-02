import { useEffect, useState } from 'react';
import { createGame } from '../core/state';
import type { Game } from '../core/state-types';
import { loadGameDataBrowser } from '../data/load-browser';
import { finishBoot, setBootDataProgress, waitBootFonts } from './boot';
import { GameShell } from './GameShell';
import { strings } from './strings';
type Loading = { status: 'loading' } | { status: 'error'; message: string } | { status: 'ready'; game: Game };
export default function App() {
  const [state, setState] = useState<Loading>({ status: 'loading' });
  useEffect(() => {
    let active = true;
    loadGameDataBrowser(setBootDataProgress)
      .then(async data => { await waitBootFonts(); if (active) setState({ status: 'ready', game: createGame(data) }); })
      .catch(error => { if (active) setState({ status: 'error', message: String(error) }); })
      .finally(finishBoot);
    return () => { active = false; };
  }, []);
  return <main className="app-shell">{state.status === 'ready' ? <GameShell game={state.game} /> :
    state.status === 'error' ? <p role="alert">{strings.dataError}：{state.message}</p> : <p role="status">{strings.loading}</p>}</main>;
}
