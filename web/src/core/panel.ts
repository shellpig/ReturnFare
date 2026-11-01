/**
 * ReturnFare Web — 地點面板與卡槽三態評估器（W4-B）。
 *
 * 對齊 Godot scripts/core/panel_builder.gd、scripts/autoload/game_state.gd
 * （available_locations / remaining_actions_today）與 scenes/ui/map_list.gd。
 * 所有查詢均為零副作用純函式，不修改 run.* 或 meta.*。
 */

import type { GameData } from '../data/types';
import { strings } from '../ui/strings';
import { evalCondition } from './condition';
import { beatsAt, chapterForDay, isNarrationOnlyPhase } from './facts';
import { nightBeatList, nightLocationSummary, resolveNightBeats } from './night';
import type { DeepReadonly, GameSnapshot } from './state-types';

export const TriState = {
  HIDDEN: 0,
  LOCKED: 1,
  OPEN: 2,
  RESOLVED: 3,
} as const;

export type TriState = (typeof TriState)[keyof typeof TriState];

export interface MapLocationView {
  id: string;
  name: string;
  enabled: boolean;
  map?: { x: number; y: number };
}

export interface PanelView {
  location: { id: string; name: string; desc: string };
  beats: readonly BeatView[];
  /** 夜間合法地點沒有任何可顯示的 beat：UI 顯示通用空結果，不是假 beat。 */
  empty_result: boolean;
}

export interface BeatView {
  id: string;
  title: string;
  text: string;
  tri: TriState;
  reason: string;
  slots: readonly SlotView[];
}

export interface SlotView {
  id: string;
  label: string;
  occupant: { id: string; name: string } | null;
  accepts: readonly string[];
  acceptTypes: readonly string[];
  tri: TriState;
  reason: string;
  isChoice: boolean;
  choiceGroup: string;
  choiceRequiresCard: boolean;
  delegation?: {
    resultTiming: 'immediate' | 'next_morning';
    preview?: string;
    tendency?: string;
  };
}

const OCCUPANT_TO_NPC_ID: Readonly<Record<string, string>> = {
  npc_aqin: 'aqinbo',
  npc_chen: 'drchen',
  npc_chunama: 'chun_ama',
  npc_driver: 'bus_driver',
  npc_longstay: 'mr_xu',
  npc_student: 'grad_student',
  npc_wu: 'wu_chairman',
};

const AMBIENT_OCCUPANT_NAMES: Readonly<Record<string, string>> = {
  npc_awei_grandma: '她阿嬤',
  npc_couple: '中年夫妻',
  npc_husband: '那位先生',
  npc_zhao: '趙先生',
};

function resolveOccupant(
  occId: string,
  state: DeepReadonly<GameSnapshot> | Readonly<GameSnapshot>,
  data: GameData,
): { id: string; name: string } {
  const strippedId = occId.replace(/^npc_/, '');
  const mappedNpcId = OCCUPANT_TO_NPC_ID[occId] ?? strippedId;
  const npc =
    data.npcsById.get(occId) ??
    data.npcsById.get(mappedNpcId) ??
    data.npcs.find((n) => n.card === occId);

  if (npc) {
    if (
      typeof npc.locked_name === 'string' &&
      npc.locked_name.length > 0 &&
      npc.reveal !== null &&
      npc.reveal !== undefined &&
      !evalCondition(npc.reveal, state as GameSnapshot, data)
    ) {
      return { id: occId, name: npc.locked_name };
    }
    return { id: occId, name: npc.name };
  }

  const card = data.cardsById.get(occId);
  if (card) {
    return { id: occId, name: card.name };
  }

  return {
    id: occId,
    name: AMBIENT_OCCUPANT_NAMES[occId] ?? occId,
  };
}

/**
 * 計算當日剩餘可用行動格數（對應 Godot GameState.remaining_actions_today()）。
 */
export function remainingActionsToday(
  state: DeepReadonly<GameSnapshot> | Readonly<GameSnapshot>,
): number {
  if (state.run.phase === 'morning') {
    const cur = state.run.action_spent ? 0 : 1;
    const pm = state.run.actions_spent_ahead > 0 ? 0 : 1;
    return cur + pm;
  }
  if (state.run.phase === 'afternoon') {
    return state.run.action_spent ? 0 : 1;
  }
  return 0;
}

/**
 * 夜間清單：一般 row 看 earliest_night ≤ 當天，teaser 看 chapter ≤ 當章；
 * earliest_night 由早至晚、同夜照資料順序（穩定排序，狀態改變不跳位）。
 * 當夜已選或已睡也不從清單移除，location requires 不成立也保留（對應 PanelBuilder.available_locations）。
 */
function availableNightLocations(
  state: DeepReadonly<GameSnapshot> | Readonly<GameSnapshot>,
  data: GameData,
): readonly string[] {
  const curChapter = chapterForDay(state.run.day);
  const visible: { id: string; earliest: number; index: number }[] = [];
  data.locations.forEach((loc, index) => {
    if (loc.layer !== 'night') {
      return;
    }
    const earliest = loc.earliest_night ?? 999;
    const isVisible =
      loc.teaser_only === true
        ? (loc.chapter ?? 1) <= curChapter
        : earliest <= state.run.day;
    if (isVisible) {
      visible.push({ id: loc.id, earliest, index });
    }
  });
  visible.sort((a, b) => a.earliest - b.earliest || a.index - b.index);
  return visible.map((v) => v.id);
}

/**
 * 回傳目前時段開放的地點 ID 清單：白天依 data.locations 定義順序，夜間見 availableNightLocations。
 * 對應 Godot GameState.available_locations()。
 */
export function availableLocations(
  state: DeepReadonly<GameSnapshot> | Readonly<GameSnapshot>,
  data: GameData,
): readonly string[] {
  if (state.run.phase === 'night') {
    return availableNightLocations(state, data);
  }
  if (isNarrationOnlyPhase(state.run.day, state.run.phase)) {
    return [];
  }

  const curChapter = chapterForDay(state.run.day);
  const curPhase = state.run.phase;
  const out: string[] = [];

  for (let i = 0; i < data.locations.length; i += 1) {
    const loc = data.locations[i];
    if (loc.layer !== 'day' && loc.layer !== 'both') {
      continue;
    }
    if ((loc.chapter ?? 1) > curChapter) {
      continue;
    }
    if (!(loc.phases ?? []).includes(curPhase)) {
      continue;
    }
    out.push(loc.id);
  }

  return out;
}

/**
 * 將 slot.accepts 轉成顯示用的卡型名稱陣列（對應 Godot PanelBuilder._resolve_accept_types）。
 * 若為具體卡 ID 則先查其 card.type，去重保序後查 cardTypesById.get(typeId)?.name。
 */
export function resolveAcceptTypes(
  accepts: readonly string[],
  data: GameData,
): readonly string[] {
  const typeIds: string[] = [];
  for (let i = 0; i < accepts.length; i += 1) {
    const acceptedId = String(accepts[i]);
    const card = data.cardsById.get(acceptedId);
    const typeId = card ? card.type : acceptedId;
    if (typeId.length > 0 && !typeIds.includes(typeId)) {
      typeIds.push(typeId);
    }
  }
  return typeIds.map((typeId) => data.cardTypesById.get(typeId)?.name ?? typeId);
}

/**
 * 建立指定地點的面板 View Model（對應 Godot PanelBuilder.build_panel）。
 * 純查詢，絕不寫入 beats_entered、day_locations_visited 或任何其他狀態。
 */
export function buildPanel(
  locationId: string,
  state: DeepReadonly<GameSnapshot> | Readonly<GameSnapshot>,
  data: GameData,
): PanelView {
  const loc = data.locationsById.get(locationId);
  const locationInfo = {
    id: locationId,
    name: loc?.name ?? locationId,
    desc: loc?.desc ?? '',
  };

  // 夜間只讀唯一有狀態解析入口（K-30）；其餘時段直接取當時段掛在該地點的 beat。
  const candidateBeats =
    state.run.phase !== 'night'
      ? beatsAt(data.beats, state.run.day, state.run.phase).filter(
          (b) => b.location === locationId,
        )
      : nightBeatList(resolveNightBeats(state, locationId, data));

  const beatsResult: BeatView[] = [];

  for (let i = 0; i < candidateBeats.length; i += 1) {
    const b = candidateBeats[i];

    // 1. beat.condition 不過 -> HIDDEN（完全省略）
    if (!evalCondition(b.condition, state as GameSnapshot, data)) {
      continue;
    }

    // 2. beat.requires 不過 -> LOCKED，否則 OPEN
    let beatTri: TriState = TriState.OPEN;
    let beatReason = '';
    if (!evalCondition(b.requires, state as GameSnapshot, data)) {
      beatTri = TriState.LOCKED;
      beatReason =
        typeof b.reject_reason === 'string' && b.reject_reason.length > 0
          ? b.reject_reason
          : strings.reasonFallback;
    }

    const slotsResult: SlotView[] = [];
    const rawSlots = b.slots ?? [];

    for (let s = 0; s < rawSlots.length; s += 1) {
      const slot = rawSlots[s];
      const slotId = slot.id;
      const slotKey = `${b.id}::${slotId}`;
      const choiceGroup =
        typeof slot.choice_group === 'string' ? slot.choice_group : '';
      const isChoice = choiceGroup.length > 0;
      const groupKey = isChoice ? `${b.id}::${choiceGroup}` : '';

      let slotTri: TriState = TriState.OPEN;
      let slotReason = '';

      // 先檢查所屬 choice_group 是否已結算（對齊 panel_builder.gd:74–82）
      if (
        isChoice &&
        Object.prototype.hasOwnProperty.call(state.run.choices, groupKey)
      ) {
        const chosenSlotId = state.run.choices[groupKey];
        if (slotId !== chosenSlotId) {
          // 同組未選項目收起
          continue;
        }
        slotTri = TriState.RESOLVED;
      } else {
        // slot.condition 不過 -> HIDDEN
        if (!evalCondition(slot.condition, state as GameSnapshot, data)) {
          continue;
        }

        if (state.run.slots_placed[slotKey] === true) {
          slotTri = TriState.RESOLVED;
        } else if (!evalCondition(slot.requires, state as GameSnapshot, data)) {
          slotTri = TriState.LOCKED;
          slotReason =
            typeof slot.reject_reason === 'string' &&
            slot.reject_reason.length > 0
              ? slot.reject_reason
              : strings.reasonFallback;
        } else if (slot.indulgence?.soak === true) {
          if (state.run.phase !== 'morning') {
            slotTri = TriState.LOCKED;
            slotReason = strings.soakMorningOnly;
          } else {
            const cost = data.tuning.indulgence.soak_phase_cost;
            if (remainingActionsToday(state) < cost) {
              slotTri = TriState.LOCKED;
              slotReason = strings.soakInsufficientActions;
            } else {
              slotTri = TriState.OPEN;
            }
          }
        } else {
          slotTri = TriState.OPEN;
        }
      }

      // beat 為 LOCKED 時，底下未 RESOLVED 的卡槽一併降為 LOCKED 並繼承 beatReason
      if (beatTri === TriState.LOCKED && slotTri !== TriState.RESOLVED) {
        slotTri = TriState.LOCKED;
        slotReason = beatReason;
      }

      let occupant: { id: string; name: string } | null = null;
      if (typeof slot.occupant === 'string' && slot.occupant.length > 0) {
        occupant = resolveOccupant(slot.occupant, state, data);
      }

      const accepts = [...(slot.accepts ?? [])];
      const acceptTypes = resolveAcceptTypes(accepts, data);

      const slotView: SlotView = {
        id: slotId,
        label: typeof slot.label === 'string' && slot.label.length > 0 ? slot.label : slotId,
        occupant,
        accepts,
        acceptTypes,
        tri: slotTri,
        reason: slotReason,
        isChoice,
        choiceGroup,
        choiceRequiresCard: slot.choice_requires_card === true,
        ...(slot.delegation
          ? {
              delegation: {
                resultTiming: slot.delegation.result_timing,
                ...(slot.delegation.preview !== undefined
                  ? { preview: slot.delegation.preview }
                  : {}),
                ...(slot.delegation.tendency !== undefined
                  ? { tendency: slot.delegation.tendency }
                  : {}),
              },
            }
          : {}),
      };

      slotsResult.push(slotView);
    }

    beatsResult.push({
      id: b.id,
      title: typeof b.title === 'string' ? b.title : '',
      text: typeof b.text === 'string' ? b.text : '',
      tri: beatTri,
      reason: beatReason,
      slots: slotsResult,
    });
  }

  return {
    location: locationInfo,
    beats: beatsResult,
    empty_result: state.run.phase === 'night' && beatsResult.length === 0,
  };
}

/**
 * 回傳目前時段地圖的地點顯示清單（對應 Godot scenes/ui/map_list.gd:26–43）。
 * 白天：有可見 beat 或曾到訪才啟用；夜間：名稱＋狀態文字，所有 row 皆可點開詳情（不啟用與否看詳情的進入鈕）。
 * 純查詢，絕不寫入 day_locations_visited。
 */
export function mapView(
  state: DeepReadonly<GameSnapshot> | Readonly<GameSnapshot>,
  data: GameData,
): readonly MapLocationView[] {
  const locIds = availableLocations(state, data);
  if (state.run.phase === 'night') {
    return locIds.map((locId) => {
      const summary = nightLocationSummary(state, locId, data);
      const loc = data.locationsById.get(locId);
      return {
        id: locId,
        name: strings.nightListEntry(summary.display_name, summary.status_text),
        enabled: true,
        ...(loc?.map ? { map: { x: loc.map.x, y: loc.map.y } } : {}),
      };
    });
  }
  return locIds.map((locId) => {
    const loc = data.locationsById.get(locId);
    const panel = buildPanel(locId, state, data);
    const hasVisibleBeat = panel.beats.length > 0;
    const visitedBefore = state.meta.day_locations_visited[locId] === true;
    return {
      id: locId,
      name: loc?.name ?? locId,
      enabled: hasVisibleBeat || visitedBefore,
      ...(loc?.map ? { map: { x: loc.map.x, y: loc.map.y } } : {}),
    };
  });
}
