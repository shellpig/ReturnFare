/**
 * ReturnFare Web — 共用資料載入與索引（W2-A）。
 *
 * loadGameData(readText, manifest) 讀取全部正式 JSON，建立有序陣列與
 * 唯讀 ById 索引。讀檔／JSON／形狀／重複 id 失敗一律以相對檔名拋錯，
 * 不回傳部分資料也不以空資料回退。beat 時段 day 與 day_from 同時出現同樣失敗。
 * 跨表未知引用由 W2-B validateData() 攔截，不在此檢查。
 *
 * 兩個進入點（load-browser、load-node）各自注入 I/O，共用本檔的解析規則，
 * 不維護第二份讀取邏輯。
 */

import type {
  Beat,
  Card,
  CardType,
  DataFile,
  Ending,
  GameData,
  Location,
  Npc,
  OpeningChoice,
  ReadText,
  Tuning,
} from './types';

export type { ReadText, DataFile, GameData };

type JsonObject = Record<string, unknown>;

/* ------------------------------------------------------------------ */
/* 邊界解析                                                             */
/* ------------------------------------------------------------------ */

function readJsonFile(readText: ReadText, relPath: string): Promise<unknown> {
  return readText(relPath)
    .then((text) => {
      try {
        return JSON.parse(text);
      } catch {
        throw new Error(`${relPath}: JSON 解析失敗`);
      }
    })
    .catch((err) => {
      if (err instanceof Error && err.message.startsWith(relPath + ': ')) {
        throw err;
      }
      throw new Error(`${relPath}: 讀取失敗：${err instanceof Error ? err.message : String(err)}`);
    });
}

function asObject(value: unknown, file: string): JsonObject {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`${file}: 頂層必須是 JSON 物件`);
  }
  return value as JsonObject;
}

function requireArray(value: unknown, file: string, key: string): unknown[] {
  const obj = asObject(value, file);
  const arr = obj[key];
  if (!Array.isArray(arr)) {
    throw new Error(`${file}: 缺少必要陣列欄位 ${key}`);
  }
  return arr;
}

function requireStringId(entry: unknown, file: string): string {
  if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
    throw new Error(`${file}: 條目不是物件`);
  }
  const id = (entry as JsonObject).id;
  if (typeof id !== 'string' || id.length === 0) {
    throw new Error(`${file}: 條目缺少 id`);
  }
  return id;
}

/* ------------------------------------------------------------------ */
/* 開啟檔相容讀法：頂層物件 { screen, opening_choices[] } 或頂層陣列   */
/* ------------------------------------------------------------------ */

interface OpeningRaw {
  screen: unknown;
  openingChoices: unknown[];
}

function readOpeningRaw(value: unknown, file: string): OpeningRaw {
  if (Array.isArray(value)) {
    return { screen: {}, openingChoices: value };
  }
  const obj = asObject(value, file);
  const choices = obj.opening_choices;
  if (!Array.isArray(choices)) {
    throw new Error(`${file}: 缺少 opening_choices 陣列`);
  }
  return { screen: obj.screen ?? {}, openingChoices: choices };
}

interface EndingRawArray {
  endings: unknown[];
}

function readEndingsArray(value: unknown, file: string): unknown[] {
  if (Array.isArray(value)) {
    return value;
  }
  const obj = asObject(value, file);
  const endings = obj.endings;
  if (!Array.isArray(endings)) {
    throw new Error(`${file}: 缺少 endings 陣列`);
  }
  return endings;
}

/* ------------------------------------------------------------------ */
/* 載入                                                               */
/* ------------------------------------------------------------------ */

export async function loadGameData(
  readText: ReadText,
  manifest: readonly DataFile[],
): Promise<GameData> {
  const duplicateErrors: string[] = [];

  // 1. 調數值與關係表（物件，保留 _comment / _pending 等原始欄位）
  const tuningRaw = await readJsonFile(readText, 'tuning.json');
  const relationScaleRaw = await readJsonFile(readText, 'relation_scale.json');
  asObject(tuningRaw, 'tuning.json');
  asObject(relationScaleRaw, 'relation_scale.json');

  // 2. 卡片型別
  const cardTypesRaw = await readJsonFile(readText, 'card_types.json');
  const cardTypeEntries = requireArray(cardTypesRaw, 'card_types.json', 'card_types');
  const cardTypes: CardType[] = [];
  const cardTypeIds = new Set<string>();
  for (const entry of cardTypeEntries) {
    const id = requireStringId(entry, 'card_types.json');
    if (cardTypeIds.has(id)) {
      duplicateErrors.push(`card_types.json：卡片型別 id 重複：${id}`);
    } else {
      cardTypeIds.add(id);
      cardTypes.push(entry as CardType);
    }
  }

  // 3. 卡片
  const cardsRaw = await readJsonFile(readText, 'cards.json');
  const cardEntries = requireArray(cardsRaw, 'cards.json', 'cards');
  const cards: Card[] = [];
  const cardIds = new Set<string>();
  for (const entry of cardEntries) {
    const id = requireStringId(entry, 'cards.json');
    if (cardIds.has(id)) {
      duplicateErrors.push(`cards.json：卡片 id 重複：${id}`);
    } else {
      cardIds.add(id);
      cards.push(entry as Card);
    }
  }

  // 4. 地點（day 與 night 合併為一個有序 map，id 全域唯一）
  const locationsRaw = await readJsonFile(readText, 'locations.json');
  const locationEntries = requireArray(locationsRaw, 'locations.json', 'day')
    .concat(requireArray(locationsRaw, 'locations.json', 'night'));
  const locations: Location[] = [];
  const locationIds = new Set<string>();
  for (const entry of locationEntries) {
    const id = requireStringId(entry, 'locations.json');
    if (locationIds.has(id)) {
      duplicateErrors.push(`locations.json：地點 id 重複：${id}`);
    } else {
      locationIds.add(id);
      locations.push(entry as Location);
    }
  }

  // 5. NPC
  const npcsRaw = await readJsonFile(readText, 'npcs.json');
  const npcEntries = requireArray(npcsRaw, 'npcs.json', 'npcs');
  const npcs: Npc[] = [];
  const npcIds = new Set<string>();
  for (const entry of npcEntries) {
    const id = requireStringId(entry, 'npcs.json');
    if (npcIds.has(id)) {
      duplicateErrors.push(`npcs.json：NPC id 重複：${id}`);
    } else {
      npcIds.add(id);
      npcs.push(entry as Npc);
    }
  }

  // 6. Beats：manifest 中 beats/ 路徑依名稱排序，各檔 beats[] 串接、不重排
  const beatPaths = manifest
    .filter((f) => f.path.startsWith('beats/') && f.path.endsWith('.json'))
    .map((f) => f.path)
    .sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));

  type BeatWithSource = { beat: unknown; sourceFile: string };
  const beatSources: BeatWithSource[] = [];
  for (const beatPath of beatPaths) {
    const beatFileRaw = await readJsonFile(readText, beatPath);
    const beatEntries = requireArray(beatFileRaw, beatPath, 'beats');
    for (const entry of beatEntries) {
      beatSources.push({ beat: entry, sourceFile: beatPath });
    }
  }

  const beats: Beat[] = [];
  const beatIds = new Set<string>();
  for (const { beat, sourceFile } of beatSources) {
    const id = requireStringId(beat, sourceFile);
    if (beatIds.has(id)) {
      duplicateErrors.push(`${sourceFile}: beat id 重複：${id}`);
    } else {
      const when = (beat as JsonObject).when;
      if (
        when !== null &&
        typeof when === 'object' &&
        !Array.isArray(when) &&
        (when as JsonObject).day !== undefined &&
        (when as JsonObject).day_from !== undefined
      ) {
        duplicateErrors.push(
          `${sourceFile}: ${id}：when 同時包含 day 與 day_from`,
        );
      } else {
        beatIds.add(id);
        beats.push(beat as Beat);
      }
    }
  }

  // 7. 結局（頂層陣列，或 { endings[] } 相容讀法）
  const endingsRaw = await readJsonFile(readText, 'endings.json');
  const endingEntries = readEndingsArray(endingsRaw, 'endings.json');
  const endings: Ending[] = [];
  const endingIds = new Set<string>();
  for (const entry of endingEntries) {
    const id = requireStringId(entry, 'endings.json');
    if (endingIds.has(id)) {
      duplicateErrors.push(`endings.json：結局 id 重複：${id}`);
    } else {
      endingIds.add(id);
      endings.push(entry as Ending);
    }
  }

  // 8. 開局選項
  const openingRaw = await readJsonFile(readText, 'opening_choices.json');
  const { screen, openingChoices: openingChoiceEntries } = readOpeningRaw(
    openingRaw,
    'opening_choices.json',
  );
  const openingChoices: OpeningChoice[] = [];
  const openingChoiceIds = new Set<string>();
  for (const entry of openingChoiceEntries) {
    const id = requireStringId(entry, 'opening_choices.json');
    if (openingChoiceIds.has(id)) {
      duplicateErrors.push(`opening_choices.json：開局選項 id 重複：${id}`);
    } else {
      openingChoiceIds.add(id);
      openingChoices.push(entry as OpeningChoice);
    }
  }

  // 9. 建索引前攔截全部重複 id；失敗不回傳部分 GameData
  if (duplicateErrors.length > 0) {
    throw new Error(duplicateErrors.join('\n'));
  }

  const cardsById = new Map<string, Card>();
  for (const c of cards) cardsById.set(c.id, c);
  const locationsById = new Map<string, Location>();
  for (const l of locations) locationsById.set(l.id, l);
  const npcsById = new Map<string, Npc>();
  for (const n of npcs) npcsById.set(n.id, n);
  const beatsById = new Map<string, Beat>();
  for (const b of beats) beatsById.set(b.id, b);
  const endingsById = new Map<string, Ending>();
  for (const e of endings) endingsById.set(e.id, e);
  const openingChoicesById = new Map<string, OpeningChoice>();
  for (const oc of openingChoices) openingChoicesById.set(oc.id, oc);
  const cardTypesById = new Map<string, CardType>();
  for (const ct of cardTypes) cardTypesById.set(ct.id, ct);

  const openingScreen: unknown = screen ?? {};
  return {
    cards: Object.freeze(cards),
    locations: Object.freeze(locations),
    npcs: Object.freeze(npcs),
    beats: Object.freeze(beats),
    endings: Object.freeze(endings),
    openingChoices: Object.freeze(openingChoices),
    cardsById,
    locationsById,
    npcsById,
    beatsById,
    endingsById,
    openingChoicesById,
    tuning: tuningRaw as Tuning,
    relationScale: relationScaleRaw as unknown as { readonly [state: string]: number },
    cardTypes: Object.freeze(cardTypes),
    cardTypesById,
    openingScreen: openingScreen as { title: string; prompt: string; note?: string },
  };
}
