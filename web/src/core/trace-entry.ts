/**
 * ReturnFare Web — Trace 與測試專用無開局走查入口（W3-B）。
 *
 * 對齊 Godot tests/headless/playthrough_greedy.gd 的 _reset_to_clean_run()：
 * - 透過 initializeRun 建立 flow.mode = 'run'、無 opening_choice_id 的初態
 * - 不先播 D1 morning auto_enter（beats_entered 維持空物件）
 * - 嚴禁由 main.tsx、UI 元件或公開 barrel import，不得進入瀏覽器正式 bundle
 */

import type { GameData } from '../data/types';
import {
  createInitialSnapshot,
  initializeRun,
} from './run-initialization';
import { createGame } from './state';
import type { Game } from './state-types';

export function createRunForTrace(data: GameData): Game {
  const base = createInitialSnapshot();
  const initialized = initializeRun(base, data);
  initialized.flow.mode = 'run';
  initialized.flow.active_ending = null;
  initialized.run.opening_choice_id = null;
  return createGame(data, initialized);
}
