import { useEffect, useRef, useState } from 'react';
import { createGame } from '../core/state';
import type { Game } from '../core/state-types';
import type { GameData } from '../data/types';
import { loadGameDataBrowser } from '../data/load-browser';
import { createSaveController, type SaveController } from '../save/controller';
import { createSaveStorage } from '../save/storage';
import type { SaveStorage } from '../save/types';
import { finishBoot, setBootDataProgress, waitBootFonts } from './boot';
import { GameShell } from './GameShell';
import { strings } from './strings';

type LoadingState =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | {
      status: 'ready';
      game: Game;
      data: GameData;
      storage: SaveStorage;
      controller: SaveController;
      gameKey: number;
    };

export default function App() {
  const [state, setState] = useState<LoadingState>({ status: 'loading' });
  const [storageError, setStorageError] = useState<string>('');
  const activeRef = useRef(true);
  const controllerRef = useRef<SaveController | null>(null);

  useEffect(() => {
    activeRef.current = true;
    loadGameDataBrowser(setBootDataProgress)
      .then(async (data) => {
        await waitBootFonts();
        if (!activeRef.current) return;
        const storage = createSaveStorage();
        let initialError = '';
        const probe = storage.load('auto', data);
        if (!probe.ok && probe.reason !== 'empty_slot') {
          if (probe.reason === 'decode_error') {
            initialError = strings.autoSaveCorrupted(probe.error);
          } else if (probe.reason === 'storage_unavailable') {
            initialError = strings.storageUnavailable;
          } else if (probe.reason === 'read_error') {
            initialError = strings.autoSaveReadError(probe.error);
          }
        }
        if (initialError) {
          setStorageError(initialError);
        }

        const initialGame = createGame(data);
        const controller = createSaveController({
          data,
          initialGame,
          storage,
          onStorageError: (err) => {
            if (activeRef.current) {
              setStorageError(err);
            }
          },
        });
        controllerRef.current = controller;

        setState({
          status: 'ready',
          game: initialGame,
          data,
          storage,
          controller,
          gameKey: 0,
        });
      })
      .catch((error) => {
        if (activeRef.current) setState({ status: 'error', message: String(error) });
      })
      .finally(finishBoot);

    return () => {
      activeRef.current = false;
      controllerRef.current?.unsubscribe();
    };
  }, []);

  function handleReplaceGame(newGame: Game) {
    setState((prev) => {
      if (prev.status !== 'ready') return prev;
      return {
        ...prev,
        game: newGame,
        gameKey: prev.gameKey + 1,
      };
    });
  }

  return (
    <main className="app-shell">
      {state.status === 'ready' ? (
        <GameShell
          gameKey={state.gameKey}
          game={state.game}
          controller={state.controller}
          onReplaceGame={handleReplaceGame}
          storageError={storageError}
          onClearStorageError={() => setStorageError('')}
        />
      ) : state.status === 'error' ? (
        <p role="alert">{strings.dataError}：{state.message}</p>
      ) : (
        <p role="status">{strings.loading}</p>
      )}
    </main>
  );
}
