import { useSyncExternalStore } from 'react';
import type { Game } from '../core/state-types';
export function useGame(game: Game) { return useSyncExternalStore(game.subscribe, game.getSnapshot, game.getSnapshot); }
