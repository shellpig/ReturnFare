/**
 * ReturnFare Web — 夜間規則輔助（W3-B 初期子集；W6-E1 補齊完整夜間流程）。
 *
 * 對齊 Godot scripts/autoload/game_state.gd 的 _record_forced_night_visit()
 * 與 scripts/data_loader.gd 的 night_beat_candidates()。
 */

import type { Beat, GameData } from '../data/types';
import { beatMatchesTime } from './facts';
import type { GameSnapshot } from './state-types';

/**
 * fixed 夜間到訪（playNightFixed 專用）：
 * 當 run.night_location_chosen 為空、未 night_sleep_pending、且地點存在於 data.locationsById 時，
 * 寫入 run.night_location_chosen 與 meta.night_locations_seen[locationId] = true，
 * 明確跳過一般夜間進場的 madness_cost，並回傳 true；否則回傳 false 且狀態零變化。
 */
export function recordForcedNightVisit(
  state: GameSnapshot,
  locationId: string,
  data: GameData,
): boolean {
  if (state.run.night_location_chosen !== '') {
    return false;
  }
  if (state.run.night_sleep_pending) {
    return false;
  }
  if (!data.locationsById.has(locationId)) {
    return false;
  }
  state.run.night_location_chosen = locationId;
  state.meta.night_locations_seen[locationId] = true;
  return true;
}

/**
 * 取得某地點在夜間的結構候選（對應 DataLoader.night_beat_candidates，純資料形狀選擇，不求值條件）。
 */
export function nightBeatCandidates(
  day: number,
  locationId: string,
  currentChapter: number,
  data: GameData,
): { primaries: Beat[]; addons: Beat[] } {
  const primaries: Beat[] = [];
  const addons: Beat[] = [];

  // 1. 定日夜間候選（同地點、non-fixed、exact when.day 且 beatMatchesTime(when, day, 'night') 成立）
  for (let i = 0; i < data.beats.length; i += 1) {
    const b = data.beats[i];
    if (b.location !== locationId) {
      continue;
    }
    if (b.fixed === true) {
      continue;
    }
    const w = b.when as { day?: number; day_from?: number; day_to?: number } | undefined;
    if (!w || typeof w !== 'object') {
      continue;
    }
    if (w.day === undefined || w.day_from !== undefined || w.day_to !== undefined) {
      continue;
    }
    if (beatMatchesTime(b.when, day, 'night')) {
      primaries.push(b);
    }
  }

  // 2. 章節變體（同地點、無 when、有 chapter <= currentChapter，chapter 由高至低排序，同章保留原序）
  for (let ch = currentChapter; ch >= 1; ch -= 1) {
    for (let i = 0; i < data.beats.length; i += 1) {
      const b = data.beats[i];
      if (b.location !== locationId) {
        continue;
      }
      if (b.when !== undefined) {
        continue;
      }
      if (b.chapter !== undefined && b.chapter === ch) {
        primaries.push(b);
      }
    }
  }

  // 3. 附加 beat（同地點、無 when、無 chapter，保留原序）
  for (let i = 0; i < data.beats.length; i += 1) {
    const b = data.beats[i];
    if (b.location !== locationId) {
      continue;
    }
    if (b.when === undefined && b.chapter === undefined) {
      addons.push(b);
    }
  }

  return { primaries, addons };
}
