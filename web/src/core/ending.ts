/**
 * ReturnFare Web — 結局底座（W6-E1）。
 *
 * 對齊 Godot：
 * - scripts/core/ending_resolver.gd：variant／lookup 片段選擇與 stable page ref 組裝、解析
 * - scripts/autoload/game_state.gd：_build_ending_plan／ending_view／reveal／advance／skip／
 *   complete_ending／_build_history_record／_parse_ending_*
 *
 * 純 TS：不依賴 React／DOM。依 endings 資料的有序 rules／lookup 選片段，不寫任何具名分支。
 * 這裡的轉換函式都在傳入狀態的複本上運作；Game（state.ts）負責提交與通知。
 */

import type { Condition, GameData, Phase } from '../data/types';
import { gainCard } from './cards';
import {
  ConditionError,
  UnsupportedConditionError,
  evalCondition,
  hasSeenEnding,
} from './condition';
import { LAST_DAY, PHASES } from './facts';
import { cloneSnapshot, createEmptyRunState } from './run-initialization';
import type {
  ActiveEndingSnapshot,
  DeepReadonly,
  EndingHistoryRecord,
  GameSnapshot,
  ReasonCode,
} from './state-types';

export const BRANCH_FIRST = 'first_seen';
export const BRANCH_REPEAT = 'repeat';
export const SKIP_COMPLETE = 'complete';

export const ENDING_REPLACED = 'ending_replaced';
export const ENDING_REFUSE_BOARDING = 'ending_refuse_boarding';

/** 結局結算時發給玩家的跨輪知識卡（game_state.gd RETURNED_KNOWLEDGE_CARD）。 */
export const RETURNED_KNOWLEDGE_CARD = 'k_i_returned';

/** 封閉的 source ↔ ending 配對（game_state.gd ENDING_SOURCE_PAIRS）。 */
export const ENDING_SOURCE_PAIRS: Readonly<Record<string, string>> = {
  madness_cap: 'ending_madness_be',
  ending_effect: 'ending_inventory_be',
  d45_coda: 'ending_replaced',
  opening_choice: 'ending_refuse_boarding',
};

/** run 生命週期只認這三個來源；opening_choice 專屬開局入口（RUN_ENDING_SOURCES）。 */
export const RUN_ENDING_SOURCES: readonly string[] = [
  'madness_cap',
  'ending_effect',
  'd45_coda',
];

/** 三個 variant 欄位；欄名去掉 `_variant` 就是 endings.json 的 variant group id。 */
export const ENDING_VARIANT_KEYS = [
  'partner_variant',
  'livelihood_variant',
  'inn_appearance_variant',
] as const;

/** history record 的封閉欄位集合（HISTORY_RECORD_KEYS）。 */
export const HISTORY_RECORD_KEYS = [
  'run_number',
  'ending_id',
  'opening_choice_id',
  'ended_day',
  'ended_phase',
  'partner_variant',
  'livelihood_variant',
  'inn_appearance_variant',
  'festival_proxy_npc',
  'knowledge_gained_this_run',
] as const;

/** active_ending 快照的固定欄位（ENDING_SNAPSHOT_KEYS）；缺一不可。 */
export const ENDING_SNAPSHOT_KEYS = [
  'ending_id',
  'source_id',
  'run_number',
  'opening_choice_id',
  'ended_day',
  'ended_phase',
  'partner_variant',
  'livelihood_variant',
  'inn_appearance_variant',
  'festival_proxy_npc',
  'knowledge_gained_this_run',
  'page_refs',
  'page_index',
  'page_revealed',
  'ready_to_complete',
] as const;

type Raw = Record<string, unknown>;

function isRaw(val: unknown): val is Raw {
  return typeof val === 'object' && val !== null && !Array.isArray(val);
}

function hasOwn(obj: object, key: string): boolean {
  return Object.prototype.hasOwnProperty.call(obj, key);
}

function str(val: unknown): string {
  return typeof val === 'string' ? val : '';
}

// ── Resolver ────────────────────────────────────────────────────────────────

/** `source_field` → 凍結欄位。P5 封閉值只有一組。 */
const SOURCE_FIELD_READERS: Readonly<
  Record<string, (state: DeepReadonly<GameSnapshot>) => string>
> = {
  festival_proxy_npc: (state) => state.run.selected_festival_proxy_npc ?? '',
};

export type EndingResolution =
  | {
      readonly ok: true;
      readonly branch: typeof BRANCH_FIRST | typeof BRANCH_REPEAT;
      /** 鍵是資料上的 `history_field`；linear ending 為空物件。 */
      readonly variants: Readonly<Record<string, string>>;
      readonly page_refs: readonly string[];
    }
  | {
      readonly ok: false;
      readonly reason_code: 'unknown_ending' | 'data_conflict';
    };

const RESOLVE_CONFLICT = { ok: false, reason_code: 'data_conflict' } as const;

function variantPageKey(isFirstSeen: boolean): string {
  return isFirstSeen ? 'first_seen_pages' : 'repeat_pages';
}

/** 把 pages 陣列串成 ref 附加到 refs。空陣列合法；非陣列或壞 page 回 false。 */
function appendPages(refs: string[], pagesRaw: unknown, prefix: string): boolean {
  if (!Array.isArray(pagesRaw)) {
    return false;
  }
  for (const pageRaw of pagesRaw) {
    if (!isRaw(pageRaw)) {
      return false;
    }
    const pageId = str(pageRaw.id);
    const text = str(pageRaw.text);
    if (pageId.length === 0 || text.trim().length === 0) {
      return false;
    }
    refs.push(prefix + pageId);
  }
  return true;
}

/**
 * 依資料順序取第一個 when 成立的 rule；都不成立才用 fallback。
 * 嚴格要求恰有一個 fallback 且形狀合法；違反回 null（＝ data_conflict）。
 */
function pickRule(
  rulesRaw: unknown,
  state: DeepReadonly<GameSnapshot>,
  data: GameData,
): Raw | null {
  if (!Array.isArray(rulesRaw) || rulesRaw.length === 0) {
    return null;
  }
  let fallback: Raw | null = null;
  let fallbackCount = 0;
  let matched: Raw | null = null;
  for (const ruleRaw of rulesRaw) {
    if (!isRaw(ruleRaw)) {
      return null;
    }
    if (ruleRaw.fallback === true) {
      fallbackCount += 1;
      if (hasOwn(ruleRaw, 'when')) {
        return null;
      }
      fallback = ruleRaw;
    } else {
      if (!hasOwn(ruleRaw, 'when')) {
        return null;
      }
      if (matched === null && evalCondition(ruleRaw.when as Condition, state, data)) {
        matched = ruleRaw;
      }
    }
  }
  if (fallbackCount !== 1) {
    return null;
  }
  return matched ?? fallback;
}

function findEntry(entriesRaw: unknown, value: string): Raw | null {
  if (!Array.isArray(entriesRaw)) {
    return null;
  }
  for (const entry of entriesRaw) {
    if (isRaw(entry) && str(entry.value) === value) {
      return entry;
    }
  }
  return null;
}

function findById(listRaw: unknown, id: string): Raw | null {
  if (!Array.isArray(listRaw)) {
    return null;
  }
  for (const item of listRaw) {
    if (isRaw(item) && str(item.id) === id) {
      return item;
    }
  }
  return null;
}

function resolveOrThrow(
  endingId: string,
  state: DeepReadonly<GameSnapshot>,
  data: GameData,
): EndingResolution {
  const endingRaw = data.endingsById.get(endingId) as unknown;
  if (!isRaw(endingRaw)) {
    return { ok: false, reason_code: 'unknown_ending' };
  }
  const ending = endingRaw;

  const isFirstSeen = !hasSeenEnding(state, endingId);
  const branch = isFirstSeen ? BRANCH_FIRST : BRANCH_REPEAT;
  const branchData = ending[branch];
  if (!isRaw(branchData)) {
    return RESOLVE_CONFLICT;
  }

  const refs: string[] = [];
  const variants: Record<string, string> = {};
  const kind = str(ending.kind);

  if (kind === 'linear') {
    if (!appendPages(refs, branchData.pages, `${endingId}/${branch}/pages/`)) {
      return RESOLVE_CONFLICT;
    }
  } else if (kind === 'composite') {
    if (
      !appendPages(refs, branchData.prefix_pages, `${endingId}/${branch}/prefix_pages/`)
    ) {
      return RESOLVE_CONFLICT;
    }

    const chosenByGroup = new Map<string, string>();
    if (!Array.isArray(ending.variant_groups)) {
      return RESOLVE_CONFLICT;
    }
    for (const vgRaw of ending.variant_groups) {
      if (!isRaw(vgRaw)) {
        return RESOLVE_CONFLICT;
      }
      const groupId = str(vgRaw.id);
      const historyField = str(vgRaw.history_field);
      if (groupId.length === 0 || historyField.length === 0) {
        return RESOLVE_CONFLICT;
      }
      const rule = pickRule(vgRaw.rules, state, data);
      if (rule === null) {
        return RESOLVE_CONFLICT;
      }
      const ruleId = str(rule.id);
      if (ruleId.length === 0) {
        return RESOLVE_CONFLICT;
      }
      variants[historyField] = ruleId;
      chosenByGroup.set(groupId, ruleId);
      if (
        !appendPages(
          refs,
          rule[variantPageKey(isFirstSeen)],
          `${endingId}/${branch}/variant_groups/${groupId}/${ruleId}/`,
        )
      ) {
        return RESOLVE_CONFLICT;
      }
    }

    if (Array.isArray(ending.lookup_fragments)) {
      for (const lfRaw of ending.lookup_fragments) {
        if (!isRaw(lfRaw)) {
          return RESOLVE_CONFLICT;
        }
        const lfId = str(lfRaw.id);
        const whenGroup = lfRaw.when_group;
        if (lfId.length === 0 || !isRaw(whenGroup)) {
          return RESOLVE_CONFLICT;
        }
        const wgGroup = str(whenGroup.group);
        const wgVariant = str(whenGroup.variant);
        const chosen = chosenByGroup.get(wgGroup);
        if (chosen === undefined) {
          return RESOLVE_CONFLICT;
        }
        if (chosen !== wgVariant) {
          continue;
        }
        const readSource = hasOwn(SOURCE_FIELD_READERS, str(lfRaw.source_field))
          ? SOURCE_FIELD_READERS[str(lfRaw.source_field)]
          : undefined;
        if (readSource === undefined) {
          return RESOLVE_CONFLICT;
        }
        const lookupValue = readSource(state);
        if (lookupValue.length === 0) {
          return RESOLVE_CONFLICT;
        }
        const entry = findEntry(lfRaw.entries, lookupValue);
        if (entry === null) {
          return RESOLVE_CONFLICT;
        }
        if (
          !appendPages(
            refs,
            entry[variantPageKey(isFirstSeen)],
            `${endingId}/${branch}/lookup_fragments/${lfId}/${lookupValue}/`,
          )
        ) {
          return RESOLVE_CONFLICT;
        }
      }
    }

    if (
      !appendPages(refs, branchData.suffix_pages, `${endingId}/${branch}/suffix_pages/`)
    ) {
      return RESOLVE_CONFLICT;
    }
  } else {
    return RESOLVE_CONFLICT;
  }

  if (refs.length === 0) {
    return RESOLVE_CONFLICT;
  }
  return { ok: true, branch, variants, page_refs: refs };
}

/**
 * 求出本次結局的 variant、lookup 片段與有序 page refs。
 * 失敗只回 unknown_ending 或 data_conflict，不自行猜測缺漏的資料。
 */
export function resolveEnding(
  endingId: string,
  state: DeepReadonly<GameSnapshot>,
  data: GameData,
): EndingResolution {
  try {
    return resolveOrThrow(endingId, state, data);
  } catch (err) {
    if (err instanceof ConditionError || err instanceof UnsupportedConditionError) {
      return RESOLVE_CONFLICT;
    }
    throw err;
  }
}

export type PageResolution =
  | { readonly ok: true; readonly text: string; readonly page_id: string }
  | { readonly ok: false };

const PAGE_MISS = { ok: false } as const;

function findPage(pagesRaw: unknown, pageId: string): PageResolution {
  if (!Array.isArray(pagesRaw)) {
    return PAGE_MISS;
  }
  for (const pageRaw of pagesRaw) {
    if (!isRaw(pageRaw) || str(pageRaw.id) !== pageId) {
      continue;
    }
    const text = str(pageRaw.text);
    if (text.trim().length === 0) {
      return PAGE_MISS;
    }
    return { ok: true, text, page_id: pageId };
  }
  return PAGE_MISS;
}

/** 解析 page ref 回玩家可見文字。ref 失效一律回 ok:false，不得當成空白頁跳過。 */
export function resolveRef(ref: string, data: GameData): PageResolution {
  if (ref.length === 0) {
    return PAGE_MISS;
  }
  const parts = ref.split('/');
  if (parts.length < 4) {
    return PAGE_MISS;
  }
  const endingRaw = data.endingsById.get(parts[0]) as unknown;
  if (!isRaw(endingRaw)) {
    return PAGE_MISS;
  }
  const branch = parts[1];
  if (branch !== BRANCH_FIRST && branch !== BRANCH_REPEAT) {
    return PAGE_MISS;
  }
  const branchData = endingRaw[branch];
  if (!isRaw(branchData)) {
    return PAGE_MISS;
  }
  const container = parts[2];
  const pageKey = variantPageKey(branch === BRANCH_FIRST);

  if (container === 'pages' || container === 'prefix_pages' || container === 'suffix_pages') {
    return parts.length === 4 ? findPage(branchData[container], parts[3]) : PAGE_MISS;
  }
  if (container === 'variant_groups') {
    if (parts.length !== 6) {
      return PAGE_MISS;
    }
    const group = findById(endingRaw.variant_groups, parts[3]);
    const rule = group === null ? null : findById(group.rules, parts[4]);
    return rule === null ? PAGE_MISS : findPage(rule[pageKey], parts[5]);
  }
  if (container === 'lookup_fragments') {
    if (parts.length !== 6) {
      return PAGE_MISS;
    }
    const fragment = findById(endingRaw.lookup_fragments, parts[3]);
    const entry = fragment === null ? null : findEntry(fragment.entries, parts[4]);
    return entry === null ? PAGE_MISS : findPage(entry[pageKey], parts[5]);
  }
  return PAGE_MISS;
}

/** 重見時資料明示的跳過落點：repeat page id 或字面值 "complete"；找不到回空字串。 */
export function skipTarget(endingId: string, data: GameData): string {
  const endingRaw = data.endingsById.get(endingId) as unknown;
  if (!isRaw(endingRaw) || !isRaw(endingRaw[BRANCH_REPEAT])) {
    return '';
  }
  return str((endingRaw[BRANCH_REPEAT] as Raw).skip_to);
}

/** ref 的最後一段就是 page id（page id 本身不得含斜線，由 lint 保證）。 */
export function pageIdOf(ref: string): string {
  const parts = ref.split('/');
  return parts[parts.length - 1];
}

// ── 結果欄位的逐欄驗證（active snapshot 與 history record 共用）────────────────

function isNullOrFilledString(val: unknown): val is string | null {
  return val === null || (typeof val === 'string' && val.length > 0);
}

function isStrictInt(val: unknown): val is number {
  return typeof val === 'number' && Number.isInteger(val);
}

function isFestivalCandidate(npcId: string, data: GameData): boolean {
  return data.npcsById.get(npcId)?.festival_proxy_eligible === true;
}

/** 資料中宣告 `ending` 指向 endingId 的開局選項 id；找不到回空字串。 */
function openingChoiceForEnding(endingId: string, data: GameData): string {
  for (const choice of data.openingChoices) {
    if (choice.ending === endingId) {
      return choice.id;
    }
  }
  return '';
}

/** 某個 ending 的 variant group id → 合法 rule id 集合。 */
function variantRulesByGroup(endingRaw: Raw): Map<string, Set<string>> {
  const out = new Map<string, Set<string>>();
  if (!Array.isArray(endingRaw.variant_groups)) {
    return out;
  }
  for (const group of endingRaw.variant_groups) {
    if (!isRaw(group)) {
      continue;
    }
    const rules = new Set<string>();
    if (Array.isArray(group.rules)) {
      for (const rule of group.rules) {
        if (isRaw(rule)) {
          rules.add(str(rule.id));
        }
      }
    }
    out.set(str(group.id), rules);
  }
  return out;
}

function cardCatalogOrder(cardId: string, data: GameData): number {
  return data.cards.findIndex((card) => card.id === cardId);
}

/**
 * 十欄結果的逐欄驗證（HISTORY_RECORD_KEYS）。任一不合法回 null。
 * 含 ending 專屬 nullable 矩陣：泛用 nullable 過關不代表這個 ending 收得起這組值。
 */
export function parseEndingResultFields(
  rawInput: unknown,
  data: GameData,
): EndingHistoryRecord | null {
  if (!isRaw(rawInput)) {
    return null;
  }
  const raw = rawInput;
  const endingId = raw.ending_id;
  if (typeof endingId !== 'string' || !data.endingsById.has(endingId)) {
    return null;
  }
  const runNo = raw.run_number;
  if (!isStrictInt(runNo) || runNo < 1) {
    return null;
  }
  if (!isNullOrFilledString(raw.opening_choice_id)) {
    return null;
  }
  for (const key of [...ENDING_VARIANT_KEYS, 'festival_proxy_npc'] as const) {
    if (!isNullOrFilledString(raw[key])) {
      return null;
    }
  }

  const endingRaw = data.endingsById.get(endingId) as unknown as Raw;
  const isRefuse = endingId === ENDING_REFUSE_BOARDING;

  const openingRef = raw.opening_choice_id as string | null;
  if (openingRef !== null && !data.openingChoicesById.has(openingRef)) {
    return null;
  }
  if (isRefuse && openingRef !== openingChoiceForEnding(endingId, data)) {
    return null;
  }

  // variant 欄有值 ⇔ 這個 ending 真的有同名 variant group，且值必須是該 group 宣告的合法 rule id。
  const validRules = variantRulesByGroup(endingRaw);
  for (const variantKey of ENDING_VARIANT_KEYS) {
    const groupId = variantKey.slice(0, -'_variant'.length);
    const val = raw[variantKey];
    const rules = validRules.get(groupId);
    if (rules !== undefined) {
      if (typeof val !== 'string' || !rules.has(val)) {
        return null;
      }
    } else if (val !== null) {
      return null;
    }
  }

  // 代付者：正常結局必須是已凍結的正式候選；不上車一律 null；BE 有值就得是候選。
  const proxy = raw.festival_proxy_npc as string | null;
  if (isRefuse) {
    if (proxy !== null) {
      return null;
    }
  } else if (endingId === ENDING_REPLACED) {
    if (proxy === null || !isFestivalCandidate(proxy, data)) {
      return null;
    }
  } else if (proxy !== null && !isFestivalCandidate(proxy, data)) {
    return null;
  }

  const endedDay = raw.ended_day;
  const endedPhase = raw.ended_phase;
  if ((endedDay === null) !== (endedPhase === null)) {
    return null;
  }
  // 不上車沒有 run，因此沒有結束日；其餘三個結局一定結束在某個時段。
  if (isRefuse !== (endedDay === null)) {
    return null;
  }
  if (endedDay !== null) {
    if (!isStrictInt(endedDay) || endedDay < 1 || endedDay > LAST_DAY) {
      return null;
    }
    if (typeof endedPhase !== 'string' || !(PHASES as readonly string[]).includes(endedPhase)) {
      return null;
    }
  }

  // 當輪知識：必須真的是知識卡、不重複，且依 cards.json 順序排列；不上車一律空。
  if (!Array.isArray(raw.knowledge_gained_this_run)) {
    return null;
  }
  const gained: string[] = [];
  let lastOrder = -1;
  for (const item of raw.knowledge_gained_this_run) {
    if (typeof item !== 'string' || item.length === 0 || gained.includes(item)) {
      return null;
    }
    const order = cardCatalogOrder(item, data);
    if (order < 0 || order <= lastOrder) {
      return null;
    }
    const card = data.cards[order];
    if (card.slotless !== true || card.type !== 'knowledge') {
      return null;
    }
    lastOrder = order;
    gained.push(item);
  }
  if (isRefuse && gained.length > 0) {
    return null;
  }

  return {
    run_number: runNo,
    ending_id: endingId,
    opening_choice_id: openingRef,
    ended_day: endedDay,
    ended_phase: endedPhase as Phase | null,
    partner_variant: raw.partner_variant as string | null,
    livelihood_variant: raw.livelihood_variant as string | null,
    inn_appearance_variant: raw.inn_appearance_variant as string | null,
    festival_proxy_npc: proxy,
    knowledge_gained_this_run: gained,
  };
}

/** active_ending 快照的逐欄驗證。缺欄、多欄、錯型別、失效 page ref 或越界 index 一律回 null。 */
export function parseEndingSnapshot(
  rawInput: unknown,
  data: GameData,
): ActiveEndingSnapshot | null {
  if (!isRaw(rawInput)) {
    return null;
  }
  const raw = rawInput;
  if (Object.keys(raw).length !== ENDING_SNAPSHOT_KEYS.length) {
    return null;
  }
  for (const key of ENDING_SNAPSHOT_KEYS) {
    if (!hasOwn(raw, key)) {
      return null;
    }
  }

  const result = parseEndingResultFields(raw, data);
  if (result === null) {
    return null;
  }
  const sourceId = raw.source_id;
  if (
    typeof sourceId !== 'string' ||
    !hasOwn(ENDING_SOURCE_PAIRS, sourceId) ||
    ENDING_SOURCE_PAIRS[sourceId] !== result.ending_id
  ) {
    return null;
  }

  const endingRaw = data.endingsById.get(result.ending_id) as unknown as Raw;
  if (!Array.isArray(raw.page_refs)) {
    return null;
  }
  const refs: string[] = [];
  let branchSeen = '';
  for (const item of raw.page_refs) {
    if (typeof item !== 'string' || !resolveRef(item, data).ok) {
      return null;
    }
    // 可解析不等於屬於這一次結局：ref 必須指向本 ending，且全部同一個 branch。
    const parts = item.split('/');
    if (parts[0] !== result.ending_id) {
      return null;
    }
    if (branchSeen.length === 0) {
      branchSeen = parts[1];
    } else if (parts[1] !== branchSeen) {
      return null;
    }
    // variant_groups 的 page ref rule id 必須與 snapshot 欄位完全一致。
    if (parts.length >= 5 && parts[2] === 'variant_groups') {
      if (str(raw[`${parts[3]}_variant`]) !== parts[4]) {
        return null;
      }
    }
    // lookup_fragments 的 lookup value 必須與 snapshot 欄位及 when_group 完全一致。
    if (parts.length >= 5 && parts[2] === 'lookup_fragments') {
      const fragment = findById(endingRaw.lookup_fragments, parts[3]);
      if (fragment === null) {
        return null;
      }
      const whenGroup = isRaw(fragment.when_group) ? fragment.when_group : {};
      const wgGroup = str(whenGroup.group);
      if (wgGroup.length > 0 && str(raw[`${wgGroup}_variant`]) !== str(whenGroup.variant)) {
        return null;
      }
      const sourceField = str(fragment.source_field);
      if (sourceField.length > 0 && str(raw[sourceField]) !== parts[4]) {
        return null;
      }
    }
    refs.push(item);
  }
  if (refs.length === 0) {
    return null;
  }

  const index = raw.page_index;
  if (!isStrictInt(index) || index < 0 || index >= refs.length) {
    return null;
  }
  if (typeof raw.page_revealed !== 'boolean' || typeof raw.ready_to_complete !== 'boolean') {
    return null;
  }
  // ready 只由「揭露末頁」或「跳到末頁」產生，兩者都同時把頁碼停在末頁並標記已揭露。
  const atLast = index === refs.length - 1;
  if (raw.ready_to_complete !== (atLast && raw.page_revealed)) {
    return null;
  }

  return {
    ending_id: result.ending_id,
    source_id: sourceId,
    run_number: result.run_number,
    opening_choice_id: result.opening_choice_id,
    ended_day: result.ended_day,
    ended_phase: result.ended_phase,
    partner_variant: result.partner_variant,
    livelihood_variant: result.livelihood_variant,
    inn_appearance_variant: result.inn_appearance_variant,
    festival_proxy_npc: result.festival_proxy_npc,
    knowledge_gained_this_run: result.knowledge_gained_this_run,
    page_refs: refs,
    page_index: index,
    page_revealed: raw.page_revealed,
    ready_to_complete: raw.ready_to_complete,
  };
}

/** 由 active snapshot 建 history record 並驗完所有引用；只複製封閉十欄。不合法回 null。 */
export function buildHistoryRecord(
  snapshot: DeepReadonly<ActiveEndingSnapshot>,
  data: GameData,
): EndingHistoryRecord | null {
  const parsed = parseEndingSnapshot(snapshot, data);
  if (parsed === null) {
    return null;
  }
  const record: Raw = {};
  for (const key of HISTORY_RECORD_KEYS) {
    record[key] = parsed[key];
  }
  return record as unknown as EndingHistoryRecord;
}

// ── 結局啟動 ────────────────────────────────────────────────────────────────

export type EndingPlan =
  | { readonly ok: true; readonly snapshot: ActiveEndingSnapshot }
  | {
      readonly ok: false;
      readonly reason_code: ReasonCode;
      readonly reason_text: string;
    };

function planReject(reason_code: ReasonCode, reason_text = ''): EndingPlan {
  return { ok: false, reason_code, reason_text };
}

/** 本輪新增的知識卡，依 cards.json 資料順序輸出，確保快照可逐字比較。 */
function knowledgeGainedSinceStart(
  state: DeepReadonly<GameSnapshot>,
  data: GameData,
): string[] {
  const gained: string[] = [];
  for (const card of data.cards) {
    if (
      state.meta.knowledge[card.id] === true &&
      state.run.knowledge_at_start[card.id] !== true
    ) {
      gained.push(card.id);
    }
  }
  return gained;
}

/**
 * 純函式：依 `state` 的當下狀態建結局快照，不寫任何狀態。
 * `state` 可以是真狀態，也可以是已套完效果與記帳的 draft（因此快照看得到剛完成的動作）。
 * `allowOpeningSource` 只有開局入口給 true。檢查順序同 Godot _build_ending_plan。
 */
export function buildEndingPlan(
  endingId: string,
  sourceId: string,
  state: DeepReadonly<GameSnapshot>,
  data: GameData,
  allowOpeningSource = false,
): EndingPlan {
  if (!data.endingsById.has(endingId)) {
    return planReject('unknown_ending');
  }
  if (!hasOwn(ENDING_SOURCE_PAIRS, sourceId) || ENDING_SOURCE_PAIRS[sourceId] !== endingId) {
    return planReject('invalid_ending_source');
  }
  // 配對正確不代表這條入口收得起：run 生命週期只認 RUN_ENDING_SOURCES。
  if (!allowOpeningSource && !RUN_ENDING_SOURCES.includes(sourceId)) {
    return planReject('invalid_ending_source', `來源不屬於 run 生命週期：${sourceId}`);
  }

  const frozenProxy = state.run.selected_festival_proxy_npc ?? '';
  if (endingId === ENDING_REPLACED) {
    // 結局當下不得重算投入：代付者必須已在 D29 凍結，且必須是正式候選。
    if (frozenProxy.length === 0 || !isFestivalCandidate(frozenProxy, data)) {
      return planReject('data_conflict', '慶典代付者尚未凍結');
    }
  }

  const resolved = resolveEnding(endingId, state, data);
  if (!resolved.ok) {
    return planReject(resolved.reason_code);
  }
  for (const ref of resolved.page_refs) {
    if (!resolveRef(ref, data).ok) {
      return planReject('data_conflict', `page ref 無法解析：${ref}`);
    }
  }

  const isRefuse = endingId === ENDING_REFUSE_BOARDING;
  const variants = resolved.variants;
  const snapshot: ActiveEndingSnapshot = {
    ending_id: endingId,
    source_id: sourceId,
    run_number: state.meta.run_number,
    opening_choice_id: isRefuse
      ? openingChoiceForEnding(endingId, data)
      : (state.run.opening_choice_id ?? null),
    ended_day: isRefuse ? null : state.run.day,
    ended_phase: isRefuse ? null : state.run.phase,
    partner_variant: variants.partner_variant ?? null,
    livelihood_variant: variants.livelihood_variant ?? null,
    inn_appearance_variant: variants.inn_appearance_variant ?? null,
    // 正常結局用凍結值；兩種 BE 有凍結就複製，不上車一律 null。
    festival_proxy_npc: isRefuse || frozenProxy.length === 0 ? null : frozenProxy,
    knowledge_gained_this_run: isRefuse ? [] : knowledgeGainedSinceStart(state, data),
    page_refs: [...resolved.page_refs],
    page_index: 0,
    page_revealed: false,
    ready_to_complete: false,
  };
  return { ok: true, snapshot };
}

export interface StartEndingOptions {
  /** run 來源要求 'run'，開局不上車要求 'opening'。 */
  readonly fromMode: 'run' | 'opening';
}

export type EndingStart =
  | { readonly ok: true }
  | {
      readonly ok: false;
      readonly reason_code: ReasonCode;
      readonly reason_text: string;
    };

/**
 * 在 draft 上啟動結局：mode → 無 active ending → plan；成功才寫 active_ending 並切 mode。
 * 失敗不動 draft。對齊 start_ending／_start_ending_from_opening 的檢查順序。
 */
export function startEndingOnDraft(
  draft: GameSnapshot,
  endingId: string,
  sourceId: string,
  data: GameData,
  options: StartEndingOptions,
): EndingStart {
  if (draft.flow.mode !== options.fromMode) {
    return options.fromMode === 'run'
      ? { ok: false, reason_code: 'not_run', reason_text: '目前不在單輪進行中' }
      : { ok: false, reason_code: 'not_opening', reason_text: '目前不在開局中' };
  }
  if (draft.flow.active_ending !== null) {
    return { ok: false, reason_code: 'ending_active', reason_text: '已有進行中的結局' };
  }
  const plan = buildEndingPlan(endingId, sourceId, draft, data, options.fromMode === 'opening');
  if (!plan.ok) {
    return plan;
  }
  draft.flow.mode = 'ending';
  draft.flow.active_ending = plan.snapshot;
  return { ok: true };
}

// ── 檢視與頁面轉換 ──────────────────────────────────────────────────────────

/** 結局畫面的唯一查詢投影：只含當頁文字與進度，不含其他頁、condition 或 ending id。 */
export interface EndingView {
  readonly page_text: string;
  readonly page_index: number;
  /** 非結局模式為 0。 */
  readonly page_count: number;
  readonly page_revealed: boolean;
  readonly is_last_page: boolean;
  readonly can_skip: boolean;
  readonly can_complete: boolean;
}

export function endingView(
  state: DeepReadonly<GameSnapshot>,
  data: GameData,
): EndingView {
  const active = state.flow.active_ending;
  if (state.flow.mode !== 'ending' || active === null) {
    return {
      page_text: '',
      page_index: 0,
      page_count: 0,
      page_revealed: false,
      is_last_page: false,
      can_skip: false,
      can_complete: false,
    };
  }
  const idx = active.page_index;
  const count = active.page_refs.length;
  let pageText = '';
  if (idx >= 0 && idx < count) {
    const page = resolveRef(active.page_refs[idx], data);
    if (page.ok) {
      pageText = page.text;
    }
  }
  return {
    page_text: pageText,
    page_index: idx,
    page_count: count,
    page_revealed: active.page_revealed,
    is_last_page: idx === count - 1,
    can_skip: hasSeenEnding(state, active.ending_id) && !active.ready_to_complete,
    can_complete: active.ready_to_complete,
  };
}

export type EndingStep =
  | { readonly ok: true; readonly nextState: GameSnapshot }
  | {
      readonly ok: false;
      readonly reason_code: ReasonCode;
      readonly reason_text: string;
    };

function stepReject(reason_code: ReasonCode, reason_text: string): EndingStep {
  return { ok: false, reason_code, reason_text };
}

type StageGate =
  | { readonly ok: true; readonly active: DeepReadonly<ActiveEndingSnapshot> }
  | { readonly ok: false; readonly step: EndingStep };

/** 三個 page mutation 的共用前置：mode ending → active 存在 → 尚未 ready。 */
function endingStageGate(state: DeepReadonly<GameSnapshot>): StageGate {
  if (state.flow.mode !== 'ending') {
    return { ok: false, step: stepReject('not_ending', '目前不在結局中') };
  }
  const active = state.flow.active_ending;
  if (active === null) {
    return { ok: false, step: stepReject('no_active_ending', '沒有進行中的結局') };
  }
  if (active.ready_to_complete) {
    return { ok: false, step: stepReject('wrong_ending_stage', '結局已可結算') };
  }
  return { ok: true, active };
}

function pageRefPlayable(
  active: DeepReadonly<ActiveEndingSnapshot>,
  idx: number,
  data: GameData,
): boolean {
  if (idx < 0 || idx >= active.page_refs.length) {
    return false;
  }
  return resolveRef(active.page_refs[idx], data).ok;
}

/** 以 patch 覆寫 active 的複本；回傳整份新狀態。 */
function withActivePatch(
  state: DeepReadonly<GameSnapshot>,
  active: DeepReadonly<ActiveEndingSnapshot>,
  patch: Partial<ActiveEndingSnapshot>,
): EndingStep {
  const nextState = cloneSnapshot(state as GameSnapshot);
  nextState.flow.active_ending = {
    ...structuredClone(active as ActiveEndingSnapshot),
    ...patch,
  };
  return { ok: true, nextState };
}

/** 逐字補完當頁；揭露末頁時同一步把 ready_to_complete 設為 true。 */
export function revealEndingPage(
  state: DeepReadonly<GameSnapshot>,
  data: GameData,
): EndingStep {
  const gate = endingStageGate(state);
  if (!gate.ok) {
    return gate.step;
  }
  const active = gate.active;
  if (active.page_revealed) {
    return stepReject('already_revealed', '本頁已完整顯示');
  }
  if (!pageRefPlayable(active, active.page_index, data)) {
    return stepReject('data_conflict', '結局頁面資料異常');
  }
  return withActivePatch(state, active, {
    page_revealed: true,
    ready_to_complete: active.page_index === active.page_refs.length - 1,
  });
}

/** 翻頁：只接受「已揭露且非末頁」。 */
export function advanceEndingPage(
  state: DeepReadonly<GameSnapshot>,
  data: GameData,
): EndingStep {
  const gate = endingStageGate(state);
  if (!gate.ok) {
    return gate.step;
  }
  const active = gate.active;
  if (!active.page_revealed) {
    return stepReject('page_not_revealed', '本頁尚未完整顯示');
  }
  if (active.page_index >= active.page_refs.length - 1) {
    return stepReject('last_page', '已是最後一頁');
  }
  if (!pageRefPlayable(active, active.page_index + 1, data)) {
    return stepReject('data_conflict', '結局頁面資料異常');
  }
  return withActivePatch(state, active, {
    page_index: active.page_index + 1,
    page_revealed: false,
  });
}

/** 重見同一 ending id 才提供的整段跳過；落點由資料的 `repeat.skip_to` 指定。不寫 history。 */
export function skipSeenEnding(
  state: DeepReadonly<GameSnapshot>,
  data: GameData,
): EndingStep {
  const gate = endingStageGate(state);
  if (!gate.ok) {
    return gate.step;
  }
  const active = gate.active;
  if (!hasSeenEnding(state, active.ending_id)) {
    return stepReject('ending_not_seen', '這個結局還沒看過，不能跳過');
  }
  const target = skipTarget(active.ending_id, data);
  if (target.length === 0) {
    return stepReject('data_conflict', '結局缺少跳過落點');
  }
  const lastIndex = active.page_refs.length - 1;
  let targetIndex = lastIndex;
  if (target !== SKIP_COMPLETE) {
    targetIndex = active.page_refs.findIndex((ref) => pageIdOf(ref) === target);
    if (targetIndex < 0) {
      return stepReject('data_conflict', '跳過落點不在本次結局頁面內');
    }
  }
  if (!pageRefPlayable(active, targetIndex, data)) {
    return stepReject('data_conflict', '結局頁面資料異常');
  }
  return withActivePatch(state, active, {
    page_index: targetIndex,
    page_revealed: true,
    ready_to_complete: targetIndex === lastIndex,
  });
}

/**
 * 正式的輪結束結算：任何結局都只從這裡回到開局。固定順序為
 * 驗 mode／active／ready → 建好並驗完 history record → append → 取得「我回來過」→
 * run_number + 1 → 清 run（與開局初始化共用 createEmptyRunState）→ 清 active → mode opening。
 * meta 其餘欄位（知識、夜間 seen、白天 visited、教學、persistent set）一律保留。
 */
export function completeEnding(
  state: DeepReadonly<GameSnapshot>,
  data: GameData,
): EndingStep {
  if (state.flow.mode !== 'ending') {
    return stepReject('not_ending', '目前不在結局中');
  }
  const active = state.flow.active_ending;
  if (active === null) {
    return stepReject('no_active_ending', '沒有進行中的結局');
  }
  if (!active.ready_to_complete) {
    return stepReject('not_ready', '結局尚未播完');
  }
  const record = buildHistoryRecord(active, data);
  if (record === null) {
    return stepReject('data_conflict', '結局結果不合法，無法寫入歷輪摘要');
  }

  const nextState = cloneSnapshot(state as GameSnapshot);
  nextState.meta.ending_history.push(record);
  // history 的 knowledge_gained_this_run 取自凍結快照，因此不含這一步才發的知識卡。
  const returned = gainCard(nextState, RETURNED_KNOWLEDGE_CARD, data);
  if (!returned.ok) {
    return stepReject('data_conflict', `缺少跨輪知識卡：${RETURNED_KNOWLEDGE_CARD}`);
  }
  nextState.meta.run_number += 1;
  nextState.run = createEmptyRunState();
  nextState.flow.active_ending = null;
  nextState.flow.mode = 'opening';
  return { ok: true, nextState };
}
