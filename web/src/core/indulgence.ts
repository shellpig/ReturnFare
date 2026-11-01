/**
 * ReturnFare Web — 縱慾純計算與查表邏輯（W6-B，對齊 Godot scripts/core/indulgence.gd）。
 */

import type { GameData, Tuning } from '../data/types';
import { evalCondition } from './condition';
import type { DeepReadonly, GameSnapshot } from './state-types';

export type IndulgenceLevel = 'light' | 'normal' | 'heavy';

export interface IndulgenceExitTarget {
  readonly beatId: string;
  readonly slotId: string;
}

/**
 * 依據累計縱慾次數 n（主動＋強制合計）查表決定強度級（規格書第八節、P2-C）。
 * n <= forced_light_count -> "light"
 * n <= forced_normal_until -> "normal"
 * 否則 -> "heavy"
 */
export function levelFor(count: number, tuning: Tuning): IndulgenceLevel {
  const lightCount = tuning.indulgence.forced_light_count;
  const normalUntil = tuning.indulgence.forced_normal_until;
  if (count <= lightCount) {
    return 'light';
  }
  if (count <= normalUntil) {
    return 'normal';
  }
  return 'heavy';
}

/**
 * 挑選強制縱慾出口（規格書第八節、P2-C、開發設計方針 P2-C）。
 * 掃描全部 accepts 含 madness 的槽，過濾掉 auto == false，
 * 求值 condition 與 requires，取 indulgence.weight 最大者；同分取資料載入順序第一個。
 * 不看地點可達性、不看 when——強制縱慾是主角自己動手，不是玩家走過去。
 * 刻意不檢查 slots_placed（K-54，出口可重複使用）。
 * 池空時回傳 null（資料錯誤，由 Lint 4 預先防禦）。
 */
export function pickExit(
  state: DeepReadonly<GameSnapshot> | GameSnapshot,
  data: GameData,
): IndulgenceExitTarget | null {
  let bestExit: IndulgenceExitTarget | null = null;
  let maxWeight = -Infinity;

  for (let i = 0; i < data.beats.length; i += 1) {
    const beat = data.beats[i];
    // 求值 beat 級條件與前置門檻（不檢查 when 與地點可達性）
    if (!evalCondition(beat.condition, state as GameSnapshot, data)) {
      continue;
    }
    if (!evalCondition(beat.requires, state as GameSnapshot, data)) {
      continue;
    }

    const slots = beat.slots ?? [];
    for (let j = 0; j < slots.length; j += 1) {
      const slot = slots[j];
      const accepts = slot.accepts ?? [];
      if (!accepts.includes('madness')) {
        continue;
      }

      const ind = slot.indulgence;
      if (!ind || typeof ind !== 'object') {
        continue;
      }

      // 過濾 auto == false（如泡湯 x_soak 永不入自動挑選池）
      if (ind.auto === false) {
        continue;
      }

      // 求值 slot 級條件與前置門檻
      if (!evalCondition(slot.condition, state as GameSnapshot, data)) {
        continue;
      }
      if (!evalCondition(slot.requires, state as GameSnapshot, data)) {
        continue;
      }

      const weight = ind.weight ?? 0;

      // 嚴格大於：同分時維持資料載入順序第一個
      if (weight > maxWeight) {
        maxWeight = weight;
        bestExit = {
          beatId: beat.id,
          slotId: slot.id,
        };
      }
    }
  }

  return bestExit;
}
