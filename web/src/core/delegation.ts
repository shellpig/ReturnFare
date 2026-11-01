/**
 * ReturnFare Web — 委託系統核心型別與受託狀態查詢（W6-C）。
 *
 * 對齊 Godot scripts/autoload/game_state.gd 的 delegation_status()。
 */

import { cardBaseId } from './facts';
import { hasCard } from './cards';
import type { DeepReadonly, GameSnapshot } from './state-types';

export interface DelegationStatus {
  readonly held: boolean;
  readonly delegated_today: boolean;
  readonly available: boolean;
  readonly has_pending_report: boolean;
}

/**
 * 查詢人物卡當前受託狀態（對齊 Godot delegation_status）。
 * 純查詢，無副作用。
 */
export function calcDelegationStatus(
  state: DeepReadonly<GameSnapshot> | GameSnapshot,
  personCardId: string,
): DelegationStatus {
  const baseId = cardBaseId(personCardId);
  const isHeld = hasCard(state, personCardId);
  const usedToday = Boolean(state.run.delegates_used_today[baseId]);
  let hasPending = false;
  for (let i = 0; i < state.run.pending_delegation_reports.length; i += 1) {
    if (state.run.pending_delegation_reports[i].person_id === baseId) {
      hasPending = true;
      break;
    }
  }
  return {
    held: isHeld,
    delegated_today: usedToday,
    available: isHeld && !usedToday,
    has_pending_report: hasPending,
  };
}
