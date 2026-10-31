/**
 * ReturnFare Web — Build-time 資料完整性驗證（W2-B）。
 *
 * 移植 scripts/data_loader.gd（verify_references 與 Lint 1～22）與
 * scripts/autoload/data.gd（REQUIRED_TUNING_KEYS 與 ACTION_PHASES 一致性）的檢查聯集。
 *
 * - load_all 階段的七類重複 id 與 beat.when (day + day_from) 互斥已由 W2-A loadGameData 在建索引前攔截。
 * - error 擋 build，warning 不擋 build（保留 DataFacts 豁免名單，不擅自升降嚴重度）。
 * - 純函式，不依賴 React、DOM 或檔案系統 I/O。
 */

import {
  ACTION_PHASES,
  BY_DESIGN_CHOICE_ONLY_BEATS,
  PHASES,
  beatMatchesTime,
  chapterForDay,
  isEmptyPhaseByDesign,
  isNarrationOnlyPhase,
  isPendingCardRefByDesign,
} from '../core/facts';
import type { Beat, GameData, Phase } from './types';
import {
  CARD_TYPE_IDS,
  EXPECTED_ENDING_IDS,
  EXPECTED_OPENING_CHOICE_IDS,
  INDULGENCE_LEVEL_KEYS,
  LEGAL_NARRATIVE_BEAT_TAGS,
  LEGAL_REJECT_REASON_TAGS,
  REQUIRED_TUNING_KEYS,
  isCardEntryKey,
  isConditionOperator,
  isEffectKey,
} from './vocabulary';

export interface Diagnostic {
  readonly ruleId: string;
  readonly source: string;
  readonly message: string;
}

export interface ValidationReport {
  readonly errors: Diagnostic[];
  readonly warnings: Diagnostic[];
  readonly executedRules: string[];
}

export type LintGroup =
  | 'structure_refs_tuning'
  | 'vocabulary_card_types'
  | 'day_supply_free_slot_echo'
  | 'indulgence'
  | 'night'
  | 'delegation_encounter'
  | 'opening_ending_loop';

export interface RuleOutput {
  readonly errors: Diagnostic[];
  readonly warnings?: Diagnostic[];
}

export interface LintRuleEntry {
  readonly id: string;
  readonly group: LintGroup;
  readonly run: (data: GameData) => RuleOutput;
}

type JsonObject = Record<string, unknown>;

const REQUIRED_DEFAULT_GROUPS: Readonly<Record<string, string>> = {
  d29_pm_invitation: 'invitation',
};

const REQUIRED_CARD_GROUPS: Readonly<Record<string, string>> = {
  d43_pm_zhou: 'leaving',
};

function isPlainObject(value: unknown): value is JsonObject {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isWholeNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && Math.floor(value) === value;
}

function makeDiag(ruleId: string, source: string, message: string): Diagnostic {
  return { ruleId, source, message };
}

function beatsAt(data: GameData, day: number, phase: Phase): Beat[] {
  return data.beats.filter((b) => beatMatchesTime(b.when, day, phase));
}

function mapsEqual(a: unknown, b: unknown): boolean {
  const objA = isPlainObject(a) ? a : {};
  const objB = isPlainObject(b) ? b : {};
  const keysA = Object.keys(objA);
  const keysB = Object.keys(objB);
  if (keysA.length !== keysB.length) {
    return false;
  }
  for (const k of keysA) {
    if (objA[k] !== objB[k]) {
      return false;
    }
  }
  return true;
}

function candidateTuning(tuning: unknown, dotPath: string): unknown {
  let node: unknown = tuning;
  for (const part of dotPath.split('.')) {
    if (isPlainObject(node) && part in node && node[part] !== null && node[part] !== undefined) {
      node = node[part];
    } else {
      return null;
    }
  }
  return node;
}

/* ------------------------------------------------------------------ */
/* 共用條件与效果語彙檢查                                              */
/* ------------------------------------------------------------------ */

function lintRequiredConditionSubNode(
  node: unknown,
  bid: string,
  where: string,
  ruleId: string,
  out: Diagnostic[],
): void {
  if (node === null || node === undefined) {
    out.push(makeDiag(ruleId, bid, `${bid} [${where}]：condition 子條件不得為 null 或省略`));
    return;
  }
  lintConditionNode(node, bid, where, ruleId, out);
}

function lintConditionNode(
  node: unknown,
  bid: string,
  where: string,
  ruleId: string,
  out: Diagnostic[],
): void {
  if (node === null || node === undefined) {
    return;
  }
  if (!isPlainObject(node)) {
    out.push(makeDiag(ruleId, bid, `${bid} [${where}]：condition 不是 Dictionary`));
    return;
  }
  const keys = Object.keys(node);
  if (keys.length === 0) {
    out.push(makeDiag(ruleId, bid, `${bid} [${where}]：condition 是空的 Dictionary（非 null）`));
    return;
  }
  if (keys.length > 1) {
    out.push(
      makeDiag(
        ruleId,
        bid,
        `${bid} [${where}]：condition 包含多個運算子鍵（應使用 all）→ ${JSON.stringify(keys)}`,
      ),
    );
  }
  for (const k of keys) {
    if (!isConditionOperator(k)) {
      out.push(makeDiag(ruleId, bid, `${bid} [${where}]：未知 condition 運算子 → ${k}`));
      continue;
    }
    if (k === 'not') {
      lintRequiredConditionSubNode(node[k], bid, `${where}.not`, ruleId, out);
    } else if (k === 'all' || k === 'any') {
      const subArr = node[k];
      if (!Array.isArray(subArr) || subArr.length === 0) {
        out.push(makeDiag(ruleId, bid, `${bid} [${where}.${k}]：${k} 必須為非空 Array`));
      } else {
        for (let i = 0; i < subArr.length; i += 1) {
          lintRequiredConditionSubNode(subArr[i], bid, `${where}.${k}[${i}]`, ruleId, out);
        }
      }
    } else if (k === 'count_at_least') {
      const ca = node[k];
      if (!isPlainObject(ca)) {
        out.push(
          makeDiag(
            ruleId,
            bid,
            `${bid} [${where}.count_at_least]：count_at_least 必須為 Dictionary`,
          ),
        );
      } else {
        if (!isWholeNumber(ca.n) || ca.n < 1) {
          out.push(
            makeDiag(
              ruleId,
              bid,
              `${bid} [${where}.count_at_least]：count_at_least.n 必須為正整數`,
            ),
          );
        }
        if (!Array.isArray(ca.of) || ca.of.length === 0) {
          out.push(
            makeDiag(
              ruleId,
              bid,
              `${bid} [${where}.count_at_least]：count_at_least.of 必須為非空 Array`,
            ),
          );
        } else {
          for (let i = 0; i < ca.of.length; i += 1) {
            lintRequiredConditionSubNode(
              ca.of[i],
              bid,
              `${where}.count_at_least.of[${i}]`,
              ruleId,
              out,
            );
          }
        }
      }
    }
  }
}

function lintCardEntriesNode(
  node: unknown,
  bid: string,
  where: string,
  ruleId: string,
  out: Diagnostic[],
): void {
  if (!Array.isArray(node)) {
    out.push(makeDiag(ruleId, bid, `${bid} [${where}]：應為陣列`));
    return;
  }
  for (const entry of node) {
    if (typeof entry === 'string') {
      continue;
    }
    if (!isPlainObject(entry)) {
      out.push(
        makeDiag(ruleId, bid, `${bid} [${where}]：卡片項目必須是字串或 { card, if } 物件`),
      );
      continue;
    }
    for (const k of Object.keys(entry)) {
      if (!isCardEntryKey(k)) {
        out.push(makeDiag(ruleId, bid, `${bid} [${where}]：卡片項目未知鍵 → ${k}`));
      }
    }
    if (typeof entry.card !== 'string' || entry.card.length === 0) {
      out.push(makeDiag(ruleId, bid, `${bid} [${where}]：卡片項目缺少 card`));
    }
    if ('if' in entry && entry.if !== undefined) {
      lintConditionNode(entry.if, bid, `${where}.if`, ruleId, out);
    }
  }
}

function lintEffectNode(
  node: unknown,
  bid: string,
  where: string,
  ruleId: string,
  out: Diagnostic[],
): void {
  if (node === null || node === undefined) {
    return;
  }
  if (!isPlainObject(node)) {
    out.push(makeDiag(ruleId, bid, `${bid} [${where}]：效果不是 Dictionary`));
    return;
  }
  for (const k of Object.keys(node)) {
    if (!isEffectKey(k)) {
      out.push(makeDiag(ruleId, bid, `${bid} [${where}]：未知效果鍵 → ${k}`));
      continue;
    }
    if (k === 'gain' || k === 'lose') {
      lintCardEntriesNode(node[k], bid, `${where}.${k}`, ruleId, out);
    }
  }
}

/* ------------------------------------------------------------------ */
/* 群組一：基本結構、引用、tuning                                       */
/* ------------------------------------------------------------------ */

function checkCardRefs(
  data: GameData,
  node: unknown,
  bid: string,
  where: string,
  ruleId: string,
  problems: Diagnostic[],
): void {
  if (isPlainObject(node)) {
    for (const [k, v] of Object.entries(node)) {
      switch (k) {
        case 'gain':
        case 'lose': {
          if (Array.isArray(v)) {
            for (const c of v) {
              if (isPlainObject(c)) {
                const entryCard = String(c.card ?? '');
                if (!data.cardsById.has(entryCard)) {
                  problems.push(
                    makeDiag(
                      ruleId,
                      bid,
                      `${bid} [${where}]：${k} 引用不存在的卡 → ${entryCard}`,
                    ),
                  );
                }
                checkCardRefs(data, c.if, bid, where, ruleId, problems);
              } else if (!data.cardsById.has(String(c))) {
                problems.push(
                  makeDiag(
                    ruleId,
                    bid,
                    `${bid} [${where}]：${k} 引用不存在的卡 → ${String(c)}`,
                  ),
                );
              }
            }
          }
          break;
        }
        case 'has_card':
        case 'has_knowledge': {
          const cid = String(v);
          if (!data.cardsById.has(cid) && !isPendingCardRefByDesign(cid)) {
            problems.push(makeDiag(ruleId, bid, `${bid} [${where}]：${k} 不存在 → ${cid}`));
          }
          break;
        }
        case 'night_seen': {
          const locId = String(v);
          const loc = data.locationsById.get(locId);
          if (!loc) {
            problems.push(
              makeDiag(ruleId, bid, `${bid} [${where}]：${k} 引用不存在的地點 → ${locId}`),
            );
          } else if (loc.layer !== 'night') {
            problems.push(
              makeDiag(ruleId, bid, `${bid} [${where}]：${k} 引用的地點不是夜間地點 → ${locId}`),
            );
          }
          break;
        }
        case 'opening_choice': {
          const ocKey = String(v);
          if (!data.openingChoicesById.has(ocKey)) {
            problems.push(
              makeDiag(ruleId, bid, `${bid} [${where}]：${k} 引用不存在的選項 → ${ocKey}`),
            );
          }
          break;
        }
        case 'ending_seen':
        case 'ending': {
          const endKey = String(v);
          if (!data.endingsById.has(endKey)) {
            problems.push(
              makeDiag(ruleId, bid, `${bid} [${where}]：${k} 引用不存在的 ending → ${endKey}`),
            );
          }
          break;
        }
        case 'festival_proxy_is': {
          const npcKey = String(v);
          const npc = data.npcsById.get(npcKey);
          if (!npc) {
            problems.push(
              makeDiag(ruleId, bid, `${bid} [${where}]：${k} 引用不存在的 NPC → ${npcKey}`),
            );
          } else if (npc.festival_proxy_eligible !== true) {
            problems.push(
              makeDiag(
                ruleId,
                bid,
                `${bid} [${where}]：${k} 引用非 festival_proxy_eligible NPC → ${npcKey}`,
              ),
            );
          }
          break;
        }
        case 'festival_proxy': {
          if (isPlainObject(v)) {
            const fpMode = String(v.mode ?? '');
            if (fpMode === 'fixed') {
              const fpNpc = String(v.npc ?? '');
              const npc = data.npcsById.get(fpNpc);
              if (!npc) {
                problems.push(
                  makeDiag(
                    ruleId,
                    bid,
                    `${bid} [${where}]：${k} fixed 引用不存在的 NPC → ${fpNpc}`,
                  ),
                );
              } else if (npc.festival_proxy_eligible !== true) {
                problems.push(
                  makeDiag(
                    ruleId,
                    bid,
                    `${bid} [${where}]：${k} fixed 引用非 festival_proxy_eligible NPC → ${fpNpc}`,
                  ),
                );
              }
            } else if (fpMode === 'highest_eligible') {
              const fpFb = String(v.fallback ?? '');
              const npc = data.npcsById.get(fpFb);
              if (!npc) {
                problems.push(
                  makeDiag(
                    ruleId,
                    bid,
                    `${bid} [${where}]：${k} fallback 引用不存在的 NPC → ${fpFb}`,
                  ),
                );
              } else if (npc.festival_proxy_eligible !== true) {
                problems.push(
                  makeDiag(
                    ruleId,
                    bid,
                    `${bid} [${where}]：${k} fallback 引用非 festival_proxy_eligible NPC → ${fpFb}`,
                  ),
                );
              }
            } else {
              problems.push(
                makeDiag(ruleId, bid, `${bid} [${where}]：${k} 未知 mode → ${fpMode}`),
              );
            }
          }
          break;
        }
        default: {
          checkCardRefs(data, v, bid, where, ruleId, problems);
          break;
        }
      }
    }
  } else if (Array.isArray(node)) {
    for (const item of node) {
      checkCardRefs(data, item, bid, where, ruleId, problems);
    }
  }
}

export function verify_references(data: GameData): RuleOutput {
  const ruleId = 'verify_references';
  const errors: Diagnostic[] = [];

  for (const loc of data.locations) {
    const lid = loc.id;
    const counterpart = loc.day_counterpart;
    if (counterpart !== undefined && counterpart !== null) {
      const cpLoc = data.locationsById.get(counterpart);
      if (!cpLoc) {
        errors.push(makeDiag(ruleId, lid, `${lid}：day_counterpart 不存在 → ${counterpart}`));
      } else if (cpLoc.layer !== 'day') {
        errors.push(
          makeDiag(ruleId, lid, `${lid}：day_counterpart 不是白天地點 → ${counterpart}`),
        );
      } else if (!mapsEqual(cpLoc.map, loc.map)) {
        errors.push(
          makeDiag(ruleId, lid, `${lid}：座標與 day_counterpart ${counterpart} 不一致`),
        );
      }
    }
  }

  for (const loc of data.locations) {
    if ('requires' in loc && loc.requires !== undefined) {
      checkCardRefs(data, loc.requires, loc.id, 'location.requires', ruleId, errors);
    }
  }

  for (const npc of data.npcs) {
    const nid = npc.id;
    if (npc.card !== undefined && npc.card !== null && !data.cardsById.has(String(npc.card))) {
      errors.push(makeDiag(ruleId, nid, `NPC ${nid}：card 不存在 → ${String(npc.card)}`));
    }
    for (const at of npc.at ?? []) {
      const atLoc = String(at.location ?? '');
      const loc = data.locationsById.get(atLoc);
      if (!loc) {
        errors.push(makeDiag(ruleId, nid, `NPC ${nid}：at.location 不存在 → ${atLoc}`));
        continue;
      }
      const openPhases = loc.phases ?? [];
      for (const p of at.phases ?? []) {
        if (!openPhases.includes(p)) {
          errors.push(makeDiag(ruleId, nid, `NPC ${nid}：${atLoc} 沒有 ${String(p)} 這個時段`));
        }
      }
    }
  }

  for (const oc of data.openingChoices) {
    const ocid = String(oc.id ?? '?');
    checkCardRefs(data, oc.on_select, ocid, 'opening_choice.on_select', ruleId, errors);
    checkCardRefs(data, oc.requires, ocid, 'opening_choice.requires', ruleId, errors);
    if ('ending' in oc && oc.ending !== undefined) {
      const ocEid = String(oc.ending ?? '');
      if (!data.endingsById.has(ocEid)) {
        errors.push(
          makeDiag(ruleId, ocid, `${ocid} [opening_choice]：ending 引用不存在的 ending → ${ocEid}`),
        );
      }
    }
  }

  for (const end of data.endings) {
    const endEid = String(end.id ?? '?');
    checkCardRefs(data, end, endEid, 'ending', ruleId, errors);
  }

  for (const b of data.beats) {
    const bid = String(b.id);
    const locId = String(b.location ?? '');
    if (!data.locationsById.has(locId)) {
      errors.push(makeDiag(ruleId, bid, `${bid}：location 不存在 → ${locId}`));
    }

    for (const key of ['condition', 'requires', 'on_enter', 'echo'] as const) {
      checkCardRefs(data, b[key], bid, key, ruleId, errors);
    }

    checkCardRefs(data, b.encounter, bid, 'encounter', ruleId, errors);

    if (isPlainObject(b.phase_exit)) {
      const ped = b.phase_exit;
      const bSlotIds = new Set<string>();
      const bGroupIds = new Set<string>();
      for (const s of b.slots ?? []) {
        bSlotIds.add(String(s.id ?? ''));
        if ('choice_group' in s && s.choice_group !== undefined) {
          bGroupIds.add(String(s.choice_group ?? ''));
        }
      }
      if (Array.isArray(ped.required_slots)) {
        for (const rs of ped.required_slots) {
          const rsStr = String(rs);
          if (!bSlotIds.has(rsStr)) {
            errors.push(
              makeDiag(
                ruleId,
                bid,
                `${bid} [phase_exit]：required_slots 引用不存在的槽 → ${rsStr}`,
              ),
            );
          }
        }
      }
      if (Array.isArray(ped.required_choice_groups)) {
        for (const rg of ped.required_choice_groups) {
          const rgStr = String(rg);
          if (!bGroupIds.has(rgStr)) {
            errors.push(
              makeDiag(
                ruleId,
                bid,
                `${bid} [phase_exit]：required_choice_groups 引用不存在的 choice group → ${rgStr}`,
              ),
            );
          }
        }
      }
      if ('ending' in ped && ped.ending !== undefined) {
        const peEnd = String(ped.ending ?? '');
        if (!data.endingsById.has(peEnd)) {
          errors.push(
            makeDiag(ruleId, bid, `${bid} [phase_exit]：ending 不存在 → ${peEnd}`),
          );
        }
      }
    }

    for (const s of b.slots ?? []) {
      const where = `slot:${String(s.id ?? '?')}`;
      checkCardRefs(data, s.requires, bid, where, ruleId, errors);
      checkCardRefs(data, s.on_place, bid, where, ruleId, errors);
      checkCardRefs(data, s.delegation, bid, `${where}.delegation`, ruleId, errors);
      if (isPlainObject(s.on_place_by_level)) {
        for (const lvl of Object.values(s.on_place_by_level)) {
          checkCardRefs(data, lvl, bid, `${where}.on_place_by_level`, ruleId, errors);
        }
      }
      for (const a of s.accepts ?? []) {
        const aStr = String(a);
        if (
          !data.cardsById.has(aStr) &&
          !CARD_TYPE_IDS.includes(aStr as (typeof CARD_TYPE_IDS)[number])
        ) {
          errors.push(
            makeDiag(ruleId, bid, `${bid} [${where}]：accepts 既不是卡也不是 type → ${aStr}`),
          );
        }
      }
    }
  }

  return { errors };
}

export function validate_tuning_and_action_phases(data: GameData): RuleOutput {
  const ruleId = 'Data.REQUIRED_TUNING_KEYS';
  const errors: Diagnostic[] = [];

  for (const key of REQUIRED_TUNING_KEYS) {
    if (candidateTuning(data.tuning, key) === null) {
      errors.push(makeDiag(ruleId, 'tuning.json', `tuning.json 缺少必要鍵：${key}`));
    }
  }

  const ppd = (data.tuning as unknown as JsonObject)?.phases_per_day;
  const expectedCount = ACTION_PHASES.length;
  if (ppd !== expectedCount) {
    errors.push(
      makeDiag(
        ruleId,
        'tuning.json',
        `tuning.phases_per_day=${String(ppd)} ≠ ACTION_PHASES count=${expectedCount}`,
      ),
    );
  }

  return { errors };
}

/* ------------------------------------------------------------------ */
/* 群組二：語彙與卡型                                                   */
/* ------------------------------------------------------------------ */

export function lint_vocabulary(data: GameData): RuleOutput {
  const ruleId = 'lint_vocabulary';
  const errors: Diagnostic[] = [];

  for (const b of data.beats) {
    const bid = String(b.id ?? '?');
    lintConditionNode(b.condition, bid, 'beat.condition', ruleId, errors);
    lintConditionNode(b.requires, bid, 'beat.requires', ruleId, errors);
    lintEffectNode(b.on_enter, bid, 'beat.on_enter', ruleId, errors);
    if (isPlainObject(b.echo)) {
      lintConditionNode(b.echo.condition, bid, 'echo.condition', ruleId, errors);
    }
    for (const s of b.slots ?? []) {
      const where = `slot:${String(s.id ?? '?')}`;
      lintConditionNode(s.condition, bid, `${where}.condition`, ruleId, errors);
      lintConditionNode(s.requires, bid, `${where}.requires`, ruleId, errors);
      lintEffectNode(s.on_place, bid, `${where}.on_place`, ruleId, errors);
    }
  }

  return { errors };
}

export function lint_card_types(data: GameData): RuleOutput {
  const ruleId = 'lint_card_types';
  const errors: Diagnostic[] = [];

  for (const card of data.cards) {
    const cid = card.id;
    const typeId = String(card.type ?? '');
    if (!data.cardTypesById.has(typeId)) {
      errors.push(
        makeDiag(ruleId, cid, `卡片 ${cid}：type 未在 card_types.json 定義 → ${typeId}`),
      );
    }
    const rawCard = card as unknown as JsonObject;
    if (!('discardable' in rawCard) || rawCard.discardable === undefined) {
      errors.push(makeDiag(ruleId, cid, `卡片 ${cid}：缺少必填欄位 discardable`));
    } else if (typeof rawCard.discardable !== 'boolean') {
      errors.push(
        makeDiag(ruleId, cid, `卡片 ${cid}：discardable 必須是 boolean（實際型別錯誤）`),
      );
    }
  }

  for (const ct of data.cardTypes) {
    const typeId = String(ct.id ?? '');
    if (!CARD_TYPE_IDS.includes(typeId as (typeof CARD_TYPE_IDS)[number])) {
      errors.push(makeDiag(ruleId, typeId, `card_types.json：未知型別 id → ${typeId}`));
    }
  }

  return { errors };
}

export function lint_missing_reject_reason(data: GameData): RuleOutput {
  const ruleId = 'lint_missing_reject_reason';
  const warnings: Diagnostic[] = [];

  for (const b of data.beats) {
    const bid = String(b.id ?? '?');
    if ('requires' in b && b.requires !== undefined && String(b.reject_reason ?? '').length === 0) {
      warnings.push(makeDiag(ruleId, bid, `${bid} [beat]：有 requires 但沒有 reject_reason`));
    }
    for (const s of b.slots ?? []) {
      if (
        'requires' in s &&
        s.requires !== undefined &&
        String(s.reject_reason ?? '').length === 0
      ) {
        warnings.push(
          makeDiag(
            ruleId,
            bid,
            `${bid} [slot:${String(s.id ?? '?')}]：有 requires 但沒有 reject_reason`,
          ),
        );
      }
    }
  }

  return { errors: [], warnings };
}

/* ------------------------------------------------------------------ */
/* 群組三：白天供需、免費槽、殘響                                        */
/* ------------------------------------------------------------------ */

export function lint_free_slot_rules(data: GameData): RuleOutput {
  const ruleId = 'lint_free_slot_rules';
  const errors: Diagnostic[] = [];
  const warnings: Diagnostic[] = [];

  for (const b of data.beats) {
    const bid = String(b.id ?? '?');
    for (const s of b.slots ?? []) {
      const cg = s.choice_group;
      const isChoice = cg !== undefined && cg !== null && String(cg).length > 0;
      const accepts = Array.isArray(s.accepts) ? s.accepts : [];
      const requiresCard = Boolean(s.choice_requires_card);
      if (isChoice && accepts.includes('protagonist') && !requiresCard) {
        errors.push(
          makeDiag(
            ruleId,
            bid,
            `${bid} [slot:${String(s.id ?? '?')}]：choice 槽的 accepts 不得包含 protagonist`,
          ),
        );
      }
    }
  }

  const panelsMap = new Map<string, Beat[]>();
  for (const b of data.beats) {
    if (!isPlainObject(b.when)) {
      continue;
    }
    const phaseStr = String(b.when.phase ?? '');
    if (phaseStr !== 'morning' && phaseStr !== 'afternoon') {
      continue;
    }
    const dayNum = typeof b.when.day === 'number' ? Math.trunc(b.when.day) : -1;
    const locId = String(b.location ?? '');
    if (locId.length === 0) {
      continue;
    }
    const pkey = `第 ${dayNum} 天 ${phaseStr}・${locId}`;
    const list = panelsMap.get(pkey) ?? [];
    list.push(b);
    panelsMap.set(pkey, list);
  }

  for (const [pkey, pbeats] of panelsMap.entries()) {
    let allFixed = true;
    let hasProtagSlot = false;
    const beatIds: string[] = [];

    for (const b of pbeats) {
      beatIds.push(String(b.id ?? '?'));
      if (!Boolean(b.fixed)) {
        allFixed = false;
      }
      for (const s of b.slots ?? []) {
        const accepts = Array.isArray(s.accepts) ? s.accepts : [];
        if (accepts.includes('protagonist')) {
          hasProtagSlot = true;
          break;
        }
      }
    }

    if (allFixed) {
      continue;
    }

    if (!hasProtagSlot) {
      const allExempt = beatIds.every((bid) => BY_DESIGN_CHOICE_ONLY_BEATS.includes(bid));
      const joinedIds = beatIds.join(', ');
      if (allExempt) {
        warnings.push(
          makeDiag(
            ruleId,
            joinedIds,
            `${joinedIds} (${pkey})：面板僅有免費槽（已列入 DataFacts 豁免名單）`,
          ),
        );
      } else {
        errors.push(
          makeDiag(
            ruleId,
            joinedIds,
            `${joinedIds} (${pkey})：非 fixed 面板無任何主角卡槽，違反 SCHEMA 同面板規約`,
          ),
        );
      }
    }
  }

  return { errors, warnings };
}

/** 同源別名（契約明定只登錄一次於 registry）。 */
export const lint_choice_rules = lint_free_slot_rules;

export function lint_action_phases(data: GameData): RuleOutput {
  const ruleId = 'lint_action_phases';
  const errors: Diagnostic[] = [];

  for (let d = 1; d <= 45; d += 1) {
    for (const p of ACTION_PHASES) {
      if (isEmptyPhaseByDesign(d, p)) {
        continue;
      }
      if (beatsAt(data, d, p).length === 0) {
        errors.push(makeDiag(ruleId, `day:${d}:${p}`, `第 ${d} 天 ${p}：沒有任何 beat`));
      }
    }
  }

  for (const b of data.beats) {
    if (!isPlainObject(b.when)) {
      continue;
    }
    const pVal = b.when.phase;
    const phasesToCheck: string[] = [];
    if (Array.isArray(pVal)) {
      for (const pItem of pVal) {
        phasesToCheck.push(String(pItem));
      }
    } else if (typeof pVal === 'string') {
      phasesToCheck.push(pVal);
    }

    const locId = String(b.location ?? '');
    const loc = data.locationsById.get(locId);
    const locPhases = Array.isArray(loc?.phases) ? loc.phases.map(String) : [];
    const beatDay = typeof b.when.day === 'number' ? Math.trunc(b.when.day) : -1;
    const bid = String(b.id ?? '');

    for (const phaseStr of phasesToCheck) {
      if (phaseStr === 'morning' || phaseStr === 'afternoon') {
        if (isNarrationOnlyPhase(beatDay, phaseStr)) {
          continue;
        }
        if (!locPhases.includes(phaseStr)) {
          errors.push(
            makeDiag(
              ruleId,
              bid,
              `${bid}：beat 時段為 ${phaseStr}，但所屬地點 ${locId} 的 phases 僅有 ${JSON.stringify(locPhases)}`,
            ),
          );
        }
      }
    }
  }

  return { errors };
}

export function lint_echoes(data: GameData): RuleOutput {
  const ruleId = 'lint_echoes';
  const errors: Diagnostic[] = [];
  const seenEchoTexts = new Map<string, string>();

  for (const b of data.beats) {
    const bid = String(b.id ?? '?');
    const echoRaw = (b as unknown as JsonObject).echo;
    if (echoRaw === null || echoRaw === undefined) {
      continue;
    }
    if (!isPlainObject(echoRaw)) {
      errors.push(makeDiag(ruleId, bid, `${bid}：echo 不是 Dictionary`));
      continue;
    }
    if (
      !('day' in echoRaw) ||
      typeof echoRaw.day !== 'number' ||
      !Number.isFinite(echoRaw.day) ||
      Math.trunc(echoRaw.day) <= 0
    ) {
      errors.push(makeDiag(ruleId, bid, `${bid}：echo 缺少有效的 day 欄位`));
      continue;
    }

    const echoDay = Math.trunc(echoRaw.day);
    if (isPlainObject(b.when)) {
      const beatDay = typeof b.when.day === 'number' ? Math.trunc(b.when.day) : -1;
      if (beatDay > 0 && echoDay <= beatDay) {
        errors.push(
          makeDiag(ruleId, bid, `${bid}：echo.day（${echoDay}）必須大於 beat.when.day（${beatDay}）`),
        );
      }
    }

    const text = String(echoRaw.text ?? '').trim();
    if (text.length === 0) {
      errors.push(makeDiag(ruleId, bid, `${bid}：echo.text 為空`));
    } else if (seenEchoTexts.has(text)) {
      errors.push(
        makeDiag(ruleId, bid, `${bid}：echo.text 與 ${seenEchoTexts.get(text)} 重複`),
      );
    } else {
      seenEchoTexts.set(text, bid);
    }
  }

  return { errors };
}

/* ------------------------------------------------------------------ */
/* 群組四：縱慾                                                        */
/* ------------------------------------------------------------------ */

function isUnconditionalOrMadnessOnly(cond: unknown): boolean {
  if (cond === null || cond === undefined) {
    return true;
  }
  if (!isPlainObject(cond)) {
    return false;
  }
  const keys = Object.keys(cond);
  if (keys.length === 0) {
    return true;
  }
  if (keys.length === 1 && 'madness_at_least' in cond) {
    return true;
  }
  return false;
}

function hasNonEmptyObject(val: unknown): boolean {
  if (val === null || val === undefined) {
    return false;
  }
  if (isPlainObject(val) && Object.keys(val).length === 0) {
    return false;
  }
  return true;
}

export function lint_indulgence_integrity(data: GameData): RuleOutput {
  const ruleId = 'lint_indulgence_integrity';
  const errors: Diagnostic[] = [];

  for (let d = 1; d <= 45; d += 1) {
    for (const p of ACTION_PHASES) {
      let hasUnconditionalExit = false;
      for (const b of beatsAt(data, d, p)) {
        if (hasNonEmptyObject(b.requires)) {
          continue;
        }
        if (!isUnconditionalOrMadnessOnly(b.condition)) {
          continue;
        }
        for (const s of b.slots ?? []) {
          const accepts = Array.isArray(s.accepts) ? s.accepts : [];
          if (!accepts.includes('madness')) {
            continue;
          }
          const ind = isPlainObject(s.indulgence) ? s.indulgence : {};
          if (ind.auto === false) {
            continue;
          }
          if (hasNonEmptyObject(s.requires)) {
            continue;
          }
          if (!isUnconditionalOrMadnessOnly(s.condition)) {
            continue;
          }
          hasUnconditionalExit = true;
          break;
        }
        if (hasUnconditionalExit) {
          break;
        }
      }
      if (!hasUnconditionalExit) {
        errors.push(
          makeDiag(ruleId, `day:${d}:${p}`, `第 ${d} 天 ${p}：無任何無條件自動縱慾出口`),
        );
      }
    }
  }

  return { errors };
}

export function lint_indulgence_exits(data: GameData): RuleOutput {
  const ruleId = 'lint_indulgence_exits';
  const errors: Diagnostic[] = [];
  let nonAutoCount = 0;

  for (const b of data.beats) {
    const bid = String(b.id ?? '?');
    for (const s of b.slots ?? []) {
      const sid = String(s.id ?? '?');
      const where = `${bid} [slot:${sid}]`;
      const accepts = Array.isArray(s.accepts) ? s.accepts : [];
      if (!accepts.includes('madness')) {
        continue;
      }

      const indVal = (s as unknown as JsonObject).indulgence;
      if (!isPlainObject(indVal)) {
        errors.push(
          makeDiag(ruleId, bid, `${where}：accepts 含 madness 但缺少有效的 indulgence 物件`),
        );
        continue;
      }

      const autoVal = indVal.auto;
      let isAuto = true;
      if (autoVal !== null && autoVal !== undefined) {
        if (typeof autoVal !== 'boolean') {
          errors.push(makeDiag(ruleId, bid, `${where}：indulgence.auto 必須是布林值`));
        } else {
          isAuto = autoVal;
        }
      }

      if (!isAuto) {
        nonAutoCount += 1;
      }

      if (isAuto) {
        if (!isWholeNumber(indVal.weight)) {
          errors.push(makeDiag(ruleId, bid, `${where}：indulgence.weight 必須是整數`));
        }
      }

      const rawSlot = s as unknown as JsonObject;
      if ('on_place_by_level' in rawSlot && rawSlot.on_place_by_level !== undefined) {
        const byLvlVal = rawSlot.on_place_by_level;
        if (!isPlainObject(byLvlVal)) {
          errors.push(makeDiag(ruleId, bid, `${where}：on_place_by_level 必須是 Dictionary`));
        } else {
          for (const [lvlKey, lvlEffect] of Object.entries(byLvlVal)) {
            if (!INDULGENCE_LEVEL_KEYS.includes(lvlKey as (typeof INDULGENCE_LEVEL_KEYS)[number])) {
              errors.push(
                makeDiag(ruleId, bid, `${where}：on_place_by_level 未知強度鍵 → ${lvlKey}`),
              );
            } else {
              lintEffectNode(
                lvlEffect,
                bid,
                `${where}.on_place_by_level.${lvlKey}`,
                ruleId,
                errors,
              );
            }
          }
        }
      }
    }
  }

  if (nonAutoCount > 1) {
    errors.push(
      makeDiag(
        ruleId,
        'beats',
        `全作 indulgence.auto 為 false 的槽至多 1 個，實際有 ${nonAutoCount} 個`,
      ),
    );
  }

  return { errors };
}

/* ------------------------------------------------------------------ */
/* 群組五：夜間                                                        */
/* ------------------------------------------------------------------ */

export function lint_night_reachability(data: GameData): RuleOutput {
  const ruleId = 'lint_night_reachability';
  const errors: Diagnostic[] = [];

  for (const b of data.beats) {
    const bid = String(b.id ?? '?');
    const locId = String(b.location ?? '');
    const loc = data.locationsById.get(locId);
    const isFixed = Boolean(b.fixed);
    let isNight = false;

    if (isPlainObject(b.when) && String(b.when.phase ?? '') === 'night') {
      isNight = true;
      const nightDay = typeof b.when.day === 'number' ? Math.trunc(b.when.day) : -1;
      const earliest = typeof loc?.earliest_night === 'number' ? Math.trunc(loc.earliest_night) : 1;
      if (nightDay < earliest) {
        errors.push(
          makeDiag(
            ruleId,
            bid,
            `${bid}：定日夜 beat 日期（${nightDay}）早於地點 ${locId} 的 earliest_night（${earliest}）`,
          ),
        );
      }
    }

    const hasChapter = 'chapter' in b && b.chapter !== undefined;
    const hasWhen = 'when' in b && b.when !== undefined;
    if (isNight || hasChapter || (!hasWhen && String(loc?.layer ?? '') === 'night')) {
      if (!isFixed) {
        const layer = String(loc?.layer ?? '');
        if (layer !== 'night' && locId !== 'sanquan') {
          errors.push(
            makeDiag(
              ruleId,
              bid,
              `${bid}：非 fixed 夜間 beat 掛在非夜間地點且非 sanquan（${locId}）`,
            ),
          );
        }
      }
    }
  }

  return { errors };
}

export function lint_night_alignment(data: GameData): RuleOutput {
  const ruleId = 'lint_night_alignment';
  const errors: Diagnostic[] = [];
  const counterpartToCard = new Map<string, string>();
  const cardToCounterparts = new Map<string, string[]>();

  for (const loc of data.locations) {
    if (loc.layer !== 'night') {
      continue;
    }
    const lid = loc.id;
    const cpVal = loc.day_counterpart;
    const revealVal = loc.night_reveal;

    if (cpVal !== null && cpVal !== undefined) {
      const cp = String(cpVal);
      if (typeof revealVal !== 'string' || revealVal.length === 0) {
        errors.push(
          makeDiag(ruleId, lid, `${lid}：有 day_counterpart（${cp}）但缺少有效的 night_reveal`),
        );
        continue;
      }

      const cardId = revealVal;
      const cdef = data.cardsById.get(cardId);
      if (!cdef) {
        errors.push(makeDiag(ruleId, lid, `${lid}：night_reveal 卡片不存在：${cardId}`));
      } else {
        const ctype = String(cdef.type ?? '');
        const slotless = Boolean(cdef.slotless);
        if (ctype !== 'knowledge') {
          errors.push(
            makeDiag(
              ruleId,
              lid,
              `${lid}：night_reveal 卡片 ${cardId} 型別不是 knowledge（實際為 ${ctype}）`,
            ),
          );
        }
        if (!slotless) {
          errors.push(
            makeDiag(ruleId, lid, `${lid}：night_reveal 卡片 ${cardId} slotless 必須為 true`),
          );
        }
      }

      if (counterpartToCard.has(cp)) {
        if (counterpartToCard.get(cp) !== cardId) {
          errors.push(
            makeDiag(
              ruleId,
              lid,
              `${lid}：day_counterpart ${cp} 指向多個不同的 night_reveal（${counterpartToCard.get(cp)} vs ${cardId}）`,
            ),
          );
        }
      } else {
        counterpartToCard.set(cp, cardId);
      }

      const cpList = cardToCounterparts.get(cardId) ?? [];
      if (!cpList.includes(cp)) {
        cpList.push(cp);
        cardToCounterparts.set(cardId, cpList);
        if (cpList.length > 1) {
          errors.push(
            makeDiag(
              ruleId,
              lid,
              `不同 day_counterpart（${cpList.join(' 與 ')}）共用了同一張對位卡 ${cardId}`,
            ),
          );
        }
      }
    } else if (revealVal !== null && revealVal !== undefined) {
      errors.push(
        makeDiag(
          ruleId,
          lid,
          `${lid}：day_counterpart 為 null，但 night_reveal 不為 null（實際為 ${String(revealVal)}）`,
        ),
      );
    }
  }

  return { errors };
}

export function lint_night_locations(data: GameData): RuleOutput {
  const ruleId = 'lint_night_locations';
  const errors: Diagnostic[] = [];

  for (const loc of data.locations) {
    if (loc.layer !== 'night') {
      continue;
    }
    const lid = loc.id;
    const rawLoc = loc as unknown as JsonObject;
    const earliestVal = rawLoc.earliest_night;
    if (!isWholeNumber(earliestVal) || earliestVal < 1 || earliestVal > 45) {
      errors.push(makeDiag(ruleId, lid, `${lid}：缺少有效的 earliest_night（1-45 整數）`));
    }

    const chVal = rawLoc.chapter;
    if (!isWholeNumber(chVal) || chVal < 1 || chVal > 3) {
      errors.push(makeDiag(ruleId, lid, `${lid}：缺少有效的 chapter（1-3 整數）`));
    }

    if (typeof earliestVal === 'number' && typeof chVal === 'number') {
      const earliest = Math.trunc(earliestVal);
      const ch = Math.trunc(chVal);
      const expectedCh = chapterForDay(earliest);
      if (ch !== expectedCh) {
        errors.push(
          makeDiag(
            ruleId,
            lid,
            `${lid}：chapter（${ch}）與 earliest_night（${earliest} 所屬章節 ${expectedCh}）不一致`,
          ),
        );
      }
    }

    const isTeaser = Boolean(rawLoc.teaser_only);
    if (isTeaser) {
      const reasonVal = rawLoc.reject_reason;
      if (typeof reasonVal !== 'string' || reasonVal.trim().length === 0) {
        errors.push(makeDiag(ruleId, lid, `${lid}：teaser_only 地點缺少有效的 reject_reason`));
      }
      if (rawLoc.madness_cost !== null && rawLoc.madness_cost !== undefined) {
        errors.push(
          makeDiag(
            ruleId,
            lid,
            `${lid}：teaser_only 地點的 madness_cost 必須為 null 或省略（實際為 ${String(rawLoc.madness_cost)}）`,
          ),
        );
      }
      if (rawLoc.day_counterpart !== null && rawLoc.day_counterpart !== undefined) {
        errors.push(
          makeDiag(
            ruleId,
            lid,
            `${lid}：teaser_only 地點的 day_counterpart 必須為 null 或省略（實際為 ${String(rawLoc.day_counterpart)}）`,
          ),
        );
      }
      if (rawLoc.night_reveal !== null && rawLoc.night_reveal !== undefined) {
        errors.push(
          makeDiag(
            ruleId,
            lid,
            `${lid}：teaser_only 地點的 night_reveal 必須為 null 或省略（實際為 ${String(rawLoc.night_reveal)}）`,
          ),
        );
      }
    } else {
      if (!('madness_cost' in rawLoc)) {
        errors.push(makeDiag(ruleId, lid, `${lid}：缺少 madness_cost 欄位`));
      } else {
        const costVal = rawLoc.madness_cost;
        if (!isWholeNumber(costVal) || costVal < 0) {
          errors.push(
            makeDiag(
              ruleId,
              lid,
              `${lid}：madness_cost 必須為 >= 0 之整數（實際為 ${String(costVal)}）`,
            ),
          );
        }
      }
    }

    if ('requires' in rawLoc && rawLoc.requires !== null && rawLoc.requires !== undefined) {
      const reqReasonVal = rawLoc.reject_reason;
      if (typeof reqReasonVal !== 'string' || reqReasonVal.trim().length === 0) {
        errors.push(makeDiag(ruleId, lid, `${lid}：帶 requires 的夜間地點缺少有效的 reject_reason`));
      }
      const tagVal = rawLoc.reject_reason_tag;
      if (typeof tagVal !== 'string' || tagVal.trim().length === 0) {
        errors.push(
          makeDiag(ruleId, lid, `${lid}：帶 requires 的夜間地點缺少有效的 reject_reason_tag`),
        );
      } else if (
        !LEGAL_REJECT_REASON_TAGS.includes(
          tagVal.trim() as (typeof LEGAL_REJECT_REASON_TAGS)[number],
        )
      ) {
        errors.push(
          makeDiag(
            ruleId,
            lid,
            `${lid}：reject_reason_tag「${tagVal}」不在封閉字彙（${LEGAL_REJECT_REASON_TAGS.join(', ')}）內`,
          ),
        );
      }
    }
  }

  return { errors };
}

function scanLegacyFlags(
  node: unknown,
  bid: string,
  where: string,
  ruleId: string,
  problems: Diagnostic[],
): void {
  if (isPlainObject(node)) {
    for (const [k, v] of Object.entries(node)) {
      if (k.includes('opened_n_')) {
        problems.push(makeDiag(ruleId, bid, `${bid} [${where}]：包含舊夜間旗標鍵 → ${k}`));
      }
      if (typeof v === 'string' && v.includes('opened_n_')) {
        problems.push(makeDiag(ruleId, bid, `${bid} [${where}.${k}]：包含舊夜間旗標值 → ${v}`));
      } else {
        scanLegacyFlags(v, bid, `${where}.${k}`, ruleId, problems);
      }
    }
  } else if (Array.isArray(node)) {
    for (let i = 0; i < node.length; i += 1) {
      const item = node[i];
      if (typeof item === 'string' && item.includes('opened_n_')) {
        problems.push(
          makeDiag(ruleId, bid, `${bid} [${where}[${i}]]：包含舊夜間旗標值 → ${item}`),
        );
      } else {
        scanLegacyFlags(item, bid, `${where}[${i}]`, ruleId, problems);
      }
    }
  }
}

export function lint_legacy_night_flags(data: GameData): RuleOutput {
  const ruleId = 'lint_legacy_night_flags';
  const errors: Diagnostic[] = [];

  for (const loc of data.locations) {
    scanLegacyFlags(loc, loc.id, `location:${loc.id}`, ruleId, errors);
  }
  for (const b of data.beats) {
    const bid = String(b.id ?? '?');
    scanLegacyFlags(b, bid, `beat:${bid}`, ruleId, errors);
  }

  return { errors };
}

export function lint_night_once(data: GameData): RuleOutput {
  const ruleId = 'lint_night_once';
  const errors: Diagnostic[] = [];
  const nightFixedByDay = new Map<number, string>();

  for (const b of data.beats) {
    const bid = String(b.id ?? '');
    const rawBeat = b as unknown as JsonObject;
    const isFixed = Boolean(rawBeat.fixed);
    let isExactNight = false;
    let beatDay = -1;

    if (isPlainObject(rawBeat.when)) {
      const wd = rawBeat.when;
      const pVal = wd.phase;
      let isNightPhase = false;
      if (typeof pVal === 'string') {
        isNightPhase = pVal === 'night';
      } else if (Array.isArray(pVal)) {
        isNightPhase = pVal.includes('night');
      }
      if (
        isNightPhase &&
        'day' in wd &&
        wd.day !== undefined &&
        !('day_from' in wd && wd.day_from !== undefined) &&
        !('day_to' in wd && wd.day_to !== undefined)
      ) {
        isExactNight = true;
        beatDay = typeof wd.day === 'number' ? Math.trunc(wd.day) : -1;
      }
    }

    const encRaw = rawBeat.encounter;
    const repeatRaw = isPlainObject(encRaw) ? encRaw.repeat_each_run : false;
    const isRepeat = typeof repeatRaw === 'boolean' && repeatRaw;

    if ('meta_once' in rawBeat && rawBeat.meta_once !== undefined) {
      const moVal = rawBeat.meta_once;
      if (moVal !== true) {
        errors.push(makeDiag(ruleId, bid, `${bid}：meta_once 欄位值必須為 boolean true`));
      }
      if (!isFixed) {
        errors.push(makeDiag(ruleId, bid, `${bid}：meta_once 只能用於 fixed: true 的 beat`));
      }
      if (!isExactNight) {
        errors.push(
          makeDiag(ruleId, bid, `${bid}：meta_once 只能用於具有 exact night when 的 beat`),
        );
      }
      if (isRepeat) {
        errors.push(
          makeDiag(ruleId, bid, `${bid}：encounter.repeat_each_run 與 meta_once 不得同時存在`),
        );
      }
    }

    const locId = String(rawBeat.location ?? '');
    const loc = data.locationsById.get(locId);
    const isNightLayer = loc?.layer === 'night';

    if (isFixed && isExactNight && isNightLayer) {
      if (rawBeat.meta_once !== true && !isRepeat) {
        errors.push(
          makeDiag(
            ruleId,
            bid,
            `${bid}：night-layer 地點 (${locId}) 的 fixed night beat 必須標記 meta_once: true（或為 repeat_each_run 遭遇）`,
          ),
        );
      }

      if (beatDay > 0) {
        if (nightFixedByDay.has(beatDay)) {
          const prevBid = nightFixedByDay.get(beatDay)!;
          errors.push(
            makeDiag(
              ruleId,
              bid,
              `第 ${beatDay} 夜存在多個 night-layer fixed beat：${prevBid} 與 ${bid}（同一夜至多一個）`,
            ),
          );
        } else {
          nightFixedByDay.set(beatDay, bid);
        }
      }
    }
  }

  return { errors };
}

export function lint_night_location_descs(data: GameData): RuleOutput {
  const ruleId = 'lint_night_location_descs';
  const errors: Diagnostic[] = [];

  for (const loc of data.locations) {
    if (loc.layer !== 'night') {
      continue;
    }
    const lid = loc.id;
    const desc = String(loc.desc ?? '').trim();
    if (desc.length === 0) {
      errors.push(makeDiag(ruleId, lid, `${lid}：night desc 為空`));
      continue;
    }

    const cpVal = loc.day_counterpart;
    if (cpVal !== null && cpVal !== undefined && String(cpVal).length > 0) {
      const cpId = String(cpVal);
      const cpLoc = data.locationsById.get(cpId);
      const cpName = String(cpLoc?.name ?? '').trim();
      if (cpName.length > 0) {
        const candidateNames: string[] = [cpName];
        for (const delimiter of ['／', '＋', '/']) {
          if (cpName.includes(delimiter)) {
            for (const part of cpName.split(delimiter)) {
              const p = part.trim();
              if (p.length >= 2 && !candidateNames.includes(p)) {
                candidateNames.push(p);
              }
            }
          }
        }
        for (const checkName of candidateNames) {
          if (desc.includes(checkName)) {
            errors.push(
              makeDiag(ruleId, lid, `${lid}：night desc 包含 day_counterpart 名稱「${checkName}」`),
            );
            break;
          }
        }
      }
    }
  }

  return { errors };
}

/* ------------------------------------------------------------------ */
/* 群組六：委託、遭遇                                                   */
/* ------------------------------------------------------------------ */

function beatLatestDay(b: Beat): number {
  if (!isPlainObject(b.when)) {
    return 45;
  }
  if (typeof b.when.day === 'number') {
    return Math.trunc(b.when.day);
  }
  if (typeof b.when.day_to === 'number') {
    return Math.trunc(b.when.day_to);
  }
  return 45;
}

export function lint_delegations(data: GameData): RuleOutput {
  const ruleId = 'lint_delegations';
  const errors: Diagnostic[] = [];

  for (const b of data.beats) {
    const bid = String(b.id ?? '');
    const groupHasProtag = new Set<string>();

    for (const s0 of b.slots ?? []) {
      const acc0 = Array.isArray(s0.accepts) ? s0.accepts : [];
      const cg0 = String(s0.choice_group ?? '');
      if (cg0.length > 0 && acc0.includes('protagonist')) {
        groupHasProtag.add(cg0);
      }
    }

    for (const s of b.slots ?? []) {
      const rawSlot = s as unknown as JsonObject;
      if (!('delegation' in rawSlot) || rawSlot.delegation === undefined) {
        continue;
      }
      const sid = String(rawSlot.id ?? '?');
      const where = `${bid} [slot:${sid}]`;
      const deleg = rawSlot.delegation;
      if (!isPlainObject(deleg)) {
        errors.push(makeDiag(ruleId, bid, `${where}：delegation 不是 Dictionary`));
        continue;
      }

      const acc = Array.isArray(rawSlot.accepts) ? rawSlot.accepts : [];
      if (acc.length !== 1 || typeof acc[0] !== 'string') {
        errors.push(
          makeDiag(ruleId, bid, `${where}：委託槽 accepts 必須恰好一個明確 person card id`),
        );
      } else {
        const pid = acc[0];
        if (pid === 'person') {
          errors.push(makeDiag(ruleId, bid, `${where}：委託槽 accepts 不可用型別泛稱 person`));
        } else {
          const card = data.cardsById.get(pid);
          if (!card) {
            errors.push(
              makeDiag(ruleId, bid, `${where}：委託槽 accepts 引用不存在的卡 -> ${pid}`),
            );
          } else if (String(card.type ?? '') !== 'person') {
            errors.push(
              makeDiag(ruleId, bid, `${where}：委託槽 accepts 的卡 ${pid} 型別不是 person`),
            );
          }
        }
      }

      const cg = String(rawSlot.choice_group ?? '');
      if (cg.length === 0) {
        errors.push(makeDiag(ruleId, bid, `${where}：委託槽必須有非空 choice_group`));
      } else if (!groupHasProtag.has(cg)) {
        errors.push(
          makeDiag(ruleId, bid, `${where}：委託槽的 choice_group ${cg} 缺親自處理（protagonist）槽`),
        );
      }

      const timing = String(deleg.result_timing ?? '');
      if (timing !== 'immediate' && timing !== 'next_morning') {
        errors.push(makeDiag(ruleId, bid, `${where}：result_timing 非法 -> ${timing}`));
      }
      const hasReport = 'report' in deleg && deleg.report !== undefined;
      if (timing === 'next_morning') {
        if (!hasReport) {
          errors.push(makeDiag(ruleId, bid, `${where}：next_morning 委託必須有 report`));
        } else if (
          !isPlainObject(deleg.report) ||
          String(deleg.report.text ?? '').length === 0
        ) {
          errors.push(makeDiag(ruleId, bid, `${where}：report 必須是含 text 的 Dictionary`));
        } else {
          lintEffectNode(deleg.report, bid, `${where}.report`, ruleId, errors);
        }
        const latest = beatLatestDay(b);
        if (latest >= 45) {
          errors.push(
            makeDiag(
              ruleId,
              bid,
              `${where}：next_morning 委託最晚成立日 ${latest} 會落到第 45 天之後`,
            ),
          );
        }
      } else if (timing === 'immediate' && hasReport) {
        errors.push(makeDiag(ruleId, bid, `${where}：immediate 委託不得有 report`));
      }

      if (String(deleg.preview ?? '').length === 0) {
        errors.push(makeDiag(ruleId, bid, `${where}：delegation 缺 preview`));
      }
      if (String(deleg.tendency ?? '').length === 0) {
        errors.push(makeDiag(ruleId, bid, `${where}：delegation 缺 tendency`));
      }
      if (
        'requires' in rawSlot &&
        rawSlot.requires !== undefined &&
        String(rawSlot.reject_reason ?? '').length === 0
      ) {
        errors.push(makeDiag(ruleId, bid, `${where}：委託槽有 requires 但缺 reject_reason`));
      }
    }
  }

  return { errors };
}

function lintNextRound(
  nr: unknown,
  roundIds: ReadonlySet<string>,
  bid: string,
  where: string,
  ruleId: string,
  problems: Diagnostic[],
): void {
  if (nr === null) {
    return;
  }
  if (typeof nr !== 'string' || !roundIds.has(nr)) {
    problems.push(
      makeDiag(ruleId, bid, `${where}：next_round 引用不存在的 round -> ${String(nr)}`),
    );
  }
}

function dfsCycleCheck(
  rid: string,
  roundById: ReadonlyMap<string, JsonObject>,
  visited: Set<string>,
  recStack: Set<string>,
): boolean {
  if (recStack.has(rid)) {
    return true;
  }
  if (visited.has(rid)) {
    return false;
  }
  visited.add(rid);
  recStack.add(rid);

  const r = roundById.get(rid);
  if (r) {
    if (Array.isArray(r.responses)) {
      for (const respVv of r.responses) {
        if (isPlainObject(respVv)) {
          const nr = respVv.next_round;
          if (nr !== null && nr !== undefined && roundById.has(String(nr))) {
            if (dfsCycleCheck(String(nr), roundById, visited, recStack)) {
              return true;
            }
          }
        }
      }
    }
    if (isPlainObject(r.fallback)) {
      const fnr = r.fallback.next_round;
      if (fnr !== null && fnr !== undefined && roundById.has(String(fnr))) {
        if (dfsCycleCheck(String(fnr), roundById, visited, recStack)) {
          return true;
        }
      }
    }
  }

  recStack.delete(rid);
  return false;
}

function roundGraphHasCycle(roundById: ReadonlyMap<string, JsonObject>): boolean {
  const visited = new Set<string>();
  const recStack = new Set<string>();
  for (const rid of roundById.keys()) {
    if (dfsCycleCheck(rid, roundById, visited, recStack)) {
      return true;
    }
  }
  return false;
}

function roundCanReachNull(
  rid: string,
  roundById: ReadonlyMap<string, JsonObject>,
  visiting: Set<string>,
): boolean {
  const r = roundById.get(rid);
  if (!r || visiting.has(rid)) {
    return false;
  }
  visiting.add(rid);

  if (Array.isArray(r.responses)) {
    for (const respVv of r.responses) {
      if (!isPlainObject(respVv) || !('next_round' in respVv)) {
        continue;
      }
      const nr = respVv.next_round;
      if (nr === null) {
        return true;
      }
      if (roundCanReachNull(String(nr), roundById, visiting)) {
        return true;
      }
    }
  }
  if (isPlainObject(r.fallback) && 'next_round' in r.fallback) {
    const fnr = r.fallback.next_round;
    if (fnr === null) {
      return true;
    }
    if (roundCanReachNull(String(fnr), roundById, visiting)) {
      return true;
    }
  }

  return false;
}

export function lint_encounters(data: GameData): RuleOutput {
  const ruleId = 'lint_encounters';
  const errors: Diagnostic[] = [];

  for (const b of data.beats) {
    const rawBeat = b as unknown as JsonObject;
    if (!('encounter' in rawBeat) || rawBeat.encounter === undefined) {
      continue;
    }
    const bid = String(rawBeat.id ?? '');
    const encV = rawBeat.encounter;
    if (!isPlainObject(encV)) {
      errors.push(makeDiag(ruleId, bid, `${bid} [encounter]：encounter 不是 Dictionary`));
      continue;
    }
    const enc = encV;
    const where = `${bid} [encounter]`;

    const prsc = enc.per_round_slot_cost;
    if (!isWholeNumber(prsc) || prsc < 0) {
      errors.push(makeDiag(ruleId, bid, `${where}：per_round_slot_cost 必須為非負整數`));
    }
    if (!('escape_cost' in enc)) {
      errors.push(makeDiag(ruleId, bid, `${where}：escape_cost 必填（null 或非負整數）`));
    } else {
      const ec = enc.escape_cost;
      if (ec !== null && (!isWholeNumber(ec) || ec < 0)) {
        errors.push(makeDiag(ruleId, bid, `${where}：escape_cost 必須為 null 或非負整數`));
      }
    }
    if ('allow_discard' in enc && enc.allow_discard !== undefined && typeof enc.allow_discard !== 'boolean') {
      errors.push(makeDiag(ruleId, bid, `${where}：allow_discard 必須是 boolean`));
    }
    if (
      'repeat_each_run' in enc &&
      enc.repeat_each_run !== undefined &&
      typeof enc.repeat_each_run !== 'boolean'
    ) {
      errors.push(makeDiag(ruleId, bid, `${where}：repeat_each_run 必須是 boolean`));
    }
    if (
      'charge_first_visit' in enc &&
      enc.charge_first_visit !== undefined &&
      typeof enc.charge_first_visit !== 'boolean'
    ) {
      errors.push(makeDiag(ruleId, bid, `${where}：charge_first_visit 必須是 boolean`));
    }
    const af = String(enc.after_finish ?? '');
    if (af !== 'stay' && af !== 'advance_phase') {
      errors.push(
        makeDiag(ruleId, bid, `${where}：after_finish 必須是 stay 或 advance_phase -> ${af}`),
      );
    }
    for (const exitKey of ['on_victory', 'on_failure', 'on_escape'] as const) {
      if (!isPlainObject(enc[exitKey])) {
        errors.push(makeDiag(ruleId, bid, `${where}：缺少或型別錯誤的 ${exitKey}`));
      } else {
        lintEffectNode(enc[exitKey], bid, `${where}.${exitKey}`, ruleId, errors);
      }
    }

    const roundsV = enc.rounds;
    if (!Array.isArray(roundsV) || roundsV.length === 0) {
      errors.push(makeDiag(ruleId, bid, `${where}：rounds 必須是非空陣列`));
      continue;
    }

    const roundIds = new Set<string>();
    const roundById = new Map<string, JsonObject>();
    for (const rV of roundsV) {
      if (!isPlainObject(rV)) {
        errors.push(makeDiag(ruleId, bid, `${where}：round 不是 Dictionary`));
        continue;
      }
      const rid = String(rV.id ?? '');
      if (rid.length === 0) {
        errors.push(makeDiag(ruleId, bid, `${where}：round 缺 id`));
        continue;
      }
      if (roundIds.has(rid)) {
        errors.push(makeDiag(ruleId, bid, `${where}：round id 重複 -> ${rid}`));
      }
      roundIds.add(rid);
      roundById.set(rid, rV);
    }

    for (const [ridK, r] of roundById.entries()) {
      const rwhere = `${where} round:${ridK}`;
      if (String(r.demand ?? '').length === 0) {
        errors.push(makeDiag(ruleId, bid, `${rwhere}：round 缺 demand`));
      }
      const respV = r.responses;
      if (!Array.isArray(respV) || respV.length === 0) {
        errors.push(makeDiag(ruleId, bid, `${rwhere}：responses 必須非空`));
      } else {
        const seenAccepts = new Map<string, string>();
        const seenRespIds = new Set<string>();
        for (const respVv of respV) {
          if (!isPlainObject(respVv)) {
            errors.push(makeDiag(ruleId, bid, `${rwhere}：response 不是 Dictionary`));
            continue;
          }
          const resp = respVv;
          const respid = String(resp.id ?? '?');
          if (!('id' in resp) || String(resp.id ?? '').length === 0) {
            errors.push(makeDiag(ruleId, bid, `${rwhere}：response 缺 id`));
          } else if (seenRespIds.has(respid)) {
            errors.push(makeDiag(ruleId, bid, `${rwhere}：response id 重複 -> ${respid}`));
          } else {
            seenRespIds.add(respid);
          }

          const accs = resp.accepts;
          if (!Array.isArray(accs) || accs.length === 0) {
            errors.push(
              makeDiag(ruleId, bid, `${rwhere} response:${respid}：accepts 必須非空`),
            );
          } else {
            for (const cV of accs) {
              const cid = String(cV);
              if (!data.cardsById.has(cid)) {
                errors.push(
                  makeDiag(
                    ruleId,
                    bid,
                    `${rwhere} response:${respid}：accepts 引用不存在的卡 -> ${cid}`,
                  ),
                );
              }
              if (seenAccepts.has(cid)) {
                errors.push(
                  makeDiag(
                    ruleId,
                    bid,
                    `${rwhere} response:${respid}：accepts 卡 ${cid} 與同 round 其他 response 重疊`,
                  ),
                );
              } else {
                seenAccepts.set(cid, respid);
              }
            }
          }

          if (typeof resp.consume_card !== 'boolean') {
            errors.push(
              makeDiag(ruleId, bid, `${rwhere} response:${respid}：consume_card 必填 boolean`),
            );
          } else if (resp.consume_card && Array.isArray(resp.accepts)) {
            for (const cV2 of resp.accepts) {
              const cid2 = String(cV2);
              const card2 = data.cardsById.get(cid2);
              if (card2 && !Boolean(card2.discardable)) {
                errors.push(
                  makeDiag(
                    ruleId,
                    bid,
                    `${rwhere} response:${respid}：consume_card:true 不可消耗不可丟棄卡 ${cid2}（禁止通用事件永久失去人物）`,
                  ),
                );
              }
            }
          }

          if (!isPlainObject(resp.on_resolve)) {
            errors.push(makeDiag(ruleId, bid, `${rwhere} response:${respid}：缺 on_resolve`));
          } else {
            lintEffectNode(
              resp.on_resolve,
              bid,
              `${rwhere} response:${respid}.on_resolve`,
              ruleId,
              errors,
            );
          }

          if (!('next_round' in resp)) {
            errors.push(
              makeDiag(
                ruleId,
                bid,
                `${rwhere} response:${respid}：缺 next_round（必須明示 id 或 null）`,
              ),
            );
          } else {
            lintNextRound(
              resp.next_round,
              roundIds,
              bid,
              `${rwhere} response:${respid}`,
              ruleId,
              errors,
            );
          }
        }
      }

      const fbV = r.fallback;
      if (!isPlainObject(fbV)) {
        errors.push(makeDiag(ruleId, bid, `${rwhere}：缺 fallback`));
      } else {
        const fb = fbV;
        if (
          'requires_discardable' in fb &&
          fb.requires_discardable !== undefined &&
          typeof fb.requires_discardable !== 'boolean'
        ) {
          errors.push(
            makeDiag(ruleId, bid, `${rwhere} fallback：requires_discardable 必須是 boolean`),
          );
        }
        if (!isPlainObject(fb.on_resolve)) {
          errors.push(makeDiag(ruleId, bid, `${rwhere} fallback：缺 on_resolve`));
        } else {
          lintEffectNode(fb.on_resolve, bid, `${rwhere} fallback.on_resolve`, ruleId, errors);
        }
        if (!('next_round' in fb)) {
          errors.push(
            makeDiag(ruleId, bid, `${rwhere} fallback：缺 next_round（必須明示 id 或 null）`),
          );
        } else {
          lintNextRound(fb.next_round, roundIds, bid, `${rwhere} fallback`, ruleId, errors);
        }
      }
    }

    if (roundById.size > 0 && isPlainObject(roundsV[0])) {
      const firstId = String(roundsV[0].id ?? '');
      const reachable = new Set<string>();
      const stack: string[] = [firstId];
      while (stack.length > 0) {
        const cur = stack.pop()!;
        if (reachable.has(cur) || !roundById.has(cur)) {
          continue;
        }
        reachable.add(cur);
        const cr = roundById.get(cur)!;
        if (Array.isArray(cr.responses)) {
          for (const respVv of cr.responses) {
            if (!isPlainObject(respVv)) {
              continue;
            }
            const nr = respVv.next_round;
            if (nr !== null && nr !== undefined) {
              stack.push(String(nr));
            }
          }
        }
        if (isPlainObject(cr.fallback)) {
          const fnr = cr.fallback.next_round;
          if (fnr !== null && fnr !== undefined) {
            stack.push(String(fnr));
          }
        }
      }

      for (const rid2 of roundIds) {
        if (!reachable.has(rid2)) {
          errors.push(makeDiag(ruleId, bid, `${where}：round ${rid2} 不可從第一回合到達`));
        }
      }
      for (const rid3 of roundById.keys()) {
        if (!roundCanReachNull(rid3, roundById, new Set<string>())) {
          errors.push(
            makeDiag(ruleId, bid, `${where}：round ${rid3} 無法抵達任何結束出口（無出口 cycle）`),
          );
        }
      }
      if (roundGraphHasCycle(roundById)) {
        errors.push(
          makeDiag(ruleId, bid, `${where}：round graph 不得存在任何 cycle（必須為 DAG）`),
        );
      }
    }

    const isFixed = Boolean(rawBeat.fixed);
    const wd: JsonObject = isPlainObject(rawBeat.when) ? rawBeat.when : {};
    const hasExactDay =
      'day' in wd &&
      wd.day !== undefined &&
      !('day_from' in wd && wd.day_from !== undefined) &&
      !('day_to' in wd && wd.day_to !== undefined) &&
      isWholeNumber(wd.day);

    if (enc.repeat_each_run === true) {
      if (!isFixed || !hasExactDay) {
        errors.push(
          makeDiag(
            ruleId,
            bid,
            `${where}：repeat_each_run 只可用於有明確整數 when.day 的 fixed encounter`,
          ),
        );
      }
    }
    if (enc.charge_first_visit === true) {
      const phaseOk = String(wd.phase ?? '') === 'night';
      const locId = String(rawBeat.location ?? '');
      const loc = data.locationsById.get(locId);
      const layerNight = loc?.layer === 'night';
      if (!isFixed) {
        errors.push(makeDiag(ruleId, bid, `${where}：charge_first_visit 要求 beat 為 fixed`));
      }
      if (!hasExactDay) {
        errors.push(
          makeDiag(ruleId, bid, `${where}：charge_first_visit 要求明確整數 when.day`),
        );
      }
      if (!phaseOk) {
        errors.push(
          makeDiag(ruleId, bid, `${where}：charge_first_visit 要求 when.phase == night`),
        );
      }
      if (!layerNight) {
        errors.push(
          makeDiag(
            ruleId,
            bid,
            `${where}：charge_first_visit 要求所掛 location layer == night`,
          ),
        );
      }
    }
  }

  return { errors };
}

/* ------------------------------------------------------------------ */
/* 群組七：開局、結局、跨輪                                             */
/* ------------------------------------------------------------------ */

function lintPageList(
  pages: unknown,
  eid: string,
  where: string,
  pageIds: Set<string>,
  ruleId: string,
  problems: Diagnostic[],
): void {
  if (!Array.isArray(pages)) {
    problems.push(makeDiag(ruleId, eid, `${eid} [${where}]：頁面列表必須為 Array`));
    return;
  }
  for (const p of pages) {
    if (!isPlainObject(p)) {
      problems.push(makeDiag(ruleId, eid, `${eid} [${where}]：page 必須為 Dictionary`));
      continue;
    }
    const pid = String(p.id ?? '');
    const text = String(p.text ?? '');
    if (pid.length === 0) {
      problems.push(makeDiag(ruleId, eid, `${eid} [${where}]：page id 不得為空`));
    } else if (pid.includes('/')) {
      problems.push(
        makeDiag(ruleId, eid, `${eid} [${where}]：page id 不得包含斜線 → ${pid}`),
      );
    } else if (pageIds.has(pid)) {
      problems.push(makeDiag(ruleId, eid, `${eid} [${where}]：page id 全域重複 → ${pid}`));
    }
    pageIds.add(pid);

    if (text.trim().length === 0) {
      problems.push(makeDiag(ruleId, eid, `${eid} [${where}.${pid}]：page text 不得為空`));
    }
    for (const forbidden of EXPECTED_ENDING_IDS) {
      if (text.includes(forbidden)) {
        problems.push(
          makeDiag(
            ruleId,
            eid,
            `${eid} [${where}.${pid}]：玩家文字直接包含內部 ending id → ${forbidden}`,
          ),
        );
      }
    }

    if ('narrative_beats' in p && p.narrative_beats !== undefined) {
      const nb = p.narrative_beats;
      if (!Array.isArray(nb)) {
        problems.push(
          makeDiag(ruleId, eid, `${eid} [${where}.${pid}]：narrative_beats 必須為 Array`),
        );
      } else {
        const seenTags = new Set<string>();
        for (const tagV of nb) {
          if (typeof tagV !== 'string') {
            problems.push(
              makeDiag(
                ruleId,
                eid,
                `${eid} [${where}.${pid}]：narrative_beats 元素必須為 String`,
              ),
            );
            continue;
          }
          if (
            !LEGAL_NARRATIVE_BEAT_TAGS.includes(
              tagV as (typeof LEGAL_NARRATIVE_BEAT_TAGS)[number],
            )
          ) {
            problems.push(
              makeDiag(
                ruleId,
                eid,
                `${eid} [${where}.${pid}]：未知 narrative_beat tag → ${tagV}`,
              ),
            );
          }
          if (seenTags.has(tagV)) {
            problems.push(
              makeDiag(
                ruleId,
                eid,
                `${eid} [${where}.${pid}]：重複的 narrative_beat tag → ${tagV}`,
              ),
            );
          }
          seenTags.add(tagV);
        }
      }
    }
  }
}

function lintCompositePaths(
  end: JsonObject,
  eid: string,
  ruleId: string,
  problems: Diagnostic[],
): void {
  const fs = isPlainObject(end.first_seen) ? end.first_seen : {};
  const rep = isPlainObject(end.repeat) ? end.repeat : {};
  const fsPrefixCount = Array.isArray(fs.prefix_pages) ? fs.prefix_pages.length : 0;
  const fsSuffixCount = Array.isArray(fs.suffix_pages) ? fs.suffix_pages.length : 0;
  const repPrefixCount = Array.isArray(rep.prefix_pages) ? rep.prefix_pages.length : 0;
  const repSuffixCount = Array.isArray(rep.suffix_pages) ? rep.suffix_pages.length : 0;

  const vgroups = Array.isArray(end.variant_groups) ? end.variant_groups : [];
  if (vgroups.length === 0) {
    return;
  }

  let combos: JsonObject[][] = [[]];
  for (const vg of vgroups) {
    if (!isPlainObject(vg)) {
      continue;
    }
    const rules = Array.isArray(vg.rules) ? vg.rules : [];
    const nextCombos: JsonObject[][] = [];
    for (const combo of combos) {
      for (const r of rules) {
        if (isPlainObject(r)) {
          nextCombos.push([...combo, r]);
        }
      }
    }
    combos = nextCombos;
  }

  for (const combo of combos) {
    let fsRulesPageCount = 0;
    let repRulesPageCount = 0;
    const comboIds: string[] = [];
    for (const rd of combo) {
      comboIds.push(String(rd.id ?? ''));
      fsRulesPageCount += Array.isArray(rd.first_seen_pages) ? rd.first_seen_pages.length : 0;
      repRulesPageCount += Array.isArray(rd.repeat_pages) ? rd.repeat_pages.length : 0;
    }
    const totalFs = fsPrefixCount + fsRulesPageCount + fsSuffixCount;
    const totalRep = repPrefixCount + repRulesPageCount + repSuffixCount;

    if (totalFs < 1) {
      problems.push(
        makeDiag(
          ruleId,
          eid,
          `${eid}：組裝路徑 ${JSON.stringify(comboIds)} 缺少首見頁面（總頁數為 0）`,
        ),
      );
    }
    if (totalRep < 1) {
      problems.push(
        makeDiag(
          ruleId,
          eid,
          `${eid}：組裝路徑 ${JSON.stringify(comboIds)} 缺少重播頁面（總頁數為 0）`,
        ),
      );
    }
  }
}

function checkSingleEndingEffect(
  node: unknown,
  bid: string,
  where: string,
  ruleId: string,
  problems: Diagnostic[],
): void {
  if (isPlainObject(node)) {
    if ('ending' in node && node.ending !== undefined) {
      const endVal = String(node.ending);
      if (endVal !== 'ending_inventory_be') {
        problems.push(
          makeDiag(
            ruleId,
            bid,
            `${bid} [${where}]：beat ending 效果只能引用 ending_inventory_be（實際為 ${endVal}）`,
          ),
        );
      }
      if ('madness' in node && node.madness !== undefined) {
        problems.push(
          makeDiag(
            ruleId,
            bid,
            `${bid} [${where}]：同一效果塊不得同時有 madness 與 ending（會形成雙 ending request）`,
          ),
        );
      }
    }
    for (const [k, v] of Object.entries(node)) {
      if (k === 'phase_exit') {
        continue;
      }
      checkSingleEndingEffect(v, bid, `${where}.${k}`, ruleId, problems);
    }
  } else if (Array.isArray(node)) {
    for (const v of node) {
      checkSingleEndingEffect(v, bid, where, ruleId, problems);
    }
  }
}

export function lint_endings(data: GameData): RuleOutput {
  const ruleId = 'lint_endings';
  const errors: Diagnostic[] = [];
  const seenIds: string[] = [];

  for (const end of data.endings) {
    const eid = String(end.id ?? '');
    seenIds.push(eid);
    if (!EXPECTED_ENDING_IDS.includes(eid as (typeof EXPECTED_ENDING_IDS)[number])) {
      errors.push(makeDiag(ruleId, 'endings.json', `endings.json：非預期的 ending id → ${eid}`));
    }
  }

  for (const expId of EXPECTED_ENDING_IDS) {
    if (!seenIds.includes(expId)) {
      errors.push(makeDiag(ruleId, 'endings.json', `endings.json：缺少必填 ending id → ${expId}`));
    }
  }

  if (data.endings.length !== 4) {
    errors.push(
      makeDiag(
        ruleId,
        'endings.json',
        `endings.json：預期恰 4 筆 ending，實際為 ${data.endings.length} 筆`,
      ),
    );
  }

  for (const endItem of data.endings) {
    const end = endItem as unknown as JsonObject;
    const eid = String(end.id ?? '');
    const kind = String(end.kind ?? '');
    const pageIds = new Set<string>();
    const repeatPageIds = new Set<string>();

    if (eid === 'ending_replaced') {
      if (kind !== 'composite') {
        errors.push(
          makeDiag(ruleId, eid, `${eid}：kind 必須為 composite（實際為 ${kind}）`),
        );
      }

      if (!isPlainObject(end.first_seen)) {
        errors.push(makeDiag(ruleId, eid, `${eid}：缺少 first_seen 字典`));
      } else {
        lintPageList(
          end.first_seen.prefix_pages,
          eid,
          'first_seen.prefix_pages',
          pageIds,
          ruleId,
          errors,
        );
        lintPageList(
          end.first_seen.suffix_pages,
          eid,
          'first_seen.suffix_pages',
          pageIds,
          ruleId,
          errors,
        );
      }

      if (!isPlainObject(end.repeat)) {
        errors.push(makeDiag(ruleId, eid, `${eid}：缺少 repeat 字典`));
      } else {
        lintPageList(
          end.repeat.prefix_pages,
          eid,
          'repeat.prefix_pages',
          pageIds,
          ruleId,
          errors,
        );
        lintPageList(
          end.repeat.suffix_pages,
          eid,
          'repeat.suffix_pages',
          pageIds,
          ruleId,
          errors,
        );
        if (Array.isArray(end.repeat.prefix_pages)) {
          for (const p of end.repeat.prefix_pages) {
            if (isPlainObject(p)) {
              repeatPageIds.add(String(p.id ?? ''));
            }
          }
        }
        if (Array.isArray(end.repeat.suffix_pages)) {
          for (const p of end.repeat.suffix_pages) {
            if (isPlainObject(p)) {
              repeatPageIds.add(String(p.id ?? ''));
            }
          }
        }
      }

      const vgMap = new Map<string, JsonObject>();
      const vgRuleMap = new Map<string, Map<string, JsonObject>>();
      if (!Array.isArray(end.variant_groups)) {
        errors.push(makeDiag(ruleId, eid, `${eid}：variant_groups 必須是 Array`));
      } else {
        const expectedVgs = ['livelihood', 'inn_appearance', 'partner'];
        const actualVgs: string[] = [];
        const histFields = new Set<string>();
        for (const vg of end.variant_groups) {
          if (!isPlainObject(vg)) {
            errors.push(makeDiag(ruleId, eid, `${eid}：variant_group 元素必須是 Dictionary`));
            continue;
          }
          const vgid = String(vg.id ?? '');
          actualVgs.push(vgid);
          vgMap.set(vgid, vg);
          const ruleMap = new Map<string, JsonObject>();
          vgRuleMap.set(vgid, ruleMap);

          const hf = String(vg.history_field ?? '');
          if (hf.length === 0) {
            errors.push(makeDiag(ruleId, eid, `${eid} [${vgid}]：缺少 history_field`));
          } else if (histFields.has(hf)) {
            errors.push(
              makeDiag(ruleId, eid, `${eid} [${vgid}]：history_field 重複 → ${hf}`),
            );
          }
          histFields.add(hf);

          if (!Array.isArray(vg.rules) || vg.rules.length === 0) {
            errors.push(makeDiag(ruleId, eid, `${eid} [${vgid}]：rules 必須為非空 Array`));
          } else {
            const ruleIds = new Set<string>();
            let fallbackCount = 0;
            for (const r of vg.rules) {
              if (!isPlainObject(r)) {
                errors.push(makeDiag(ruleId, eid, `${eid} [${vgid}]：rule 必須為 Dictionary`));
                continue;
              }
              const rid = String(r.id ?? '');
              if (rid.length === 0) {
                errors.push(makeDiag(ruleId, eid, `${eid} [${vgid}]：rule id 不得為空`));
              } else if (ruleIds.has(rid)) {
                errors.push(makeDiag(ruleId, eid, `${eid} [${vgid}]：rule id 重複 → ${rid}`));
              }
              ruleIds.add(rid);
              ruleMap.set(rid, r);

              if (Array.isArray(r.repeat_pages)) {
                for (const p of r.repeat_pages) {
                  if (isPlainObject(p)) {
                    repeatPageIds.add(String(p.id ?? ''));
                  }
                }
              }

              const isFb = r.fallback === true;
              if (isFb) {
                fallbackCount += 1;
                if ('when' in r && r.when !== undefined) {
                  errors.push(
                    makeDiag(
                      ruleId,
                      eid,
                      `${eid} [${vgid}.${rid}]：fallback rule 不得同時包含 when`,
                    ),
                  );
                }
              } else if (!('when' in r) || r.when === undefined) {
                errors.push(
                  makeDiag(ruleId, eid, `${eid} [${vgid}.${rid}]：非 fallback rule 必須包含 when`),
                );
              } else {
                lintConditionNode(r.when, eid, `${vgid}.${rid}.when`, ruleId, errors);
              }

              lintPageList(
                r.first_seen_pages,
                eid,
                `${vgid}.${rid}.first_seen_pages`,
                pageIds,
                ruleId,
                errors,
              );
              lintPageList(
                r.repeat_pages,
                eid,
                `${vgid}.${rid}.repeat_pages`,
                pageIds,
                ruleId,
                errors,
              );
            }
            if (fallbackCount !== 1) {
              errors.push(
                makeDiag(
                  ruleId,
                  eid,
                  `${eid} [${vgid}]：rules 必須恰有一個 fallback（實際為 ${fallbackCount} 個）`,
                ),
              );
            }
          }
        }
        if (JSON.stringify(actualVgs) !== JSON.stringify(expectedVgs)) {
          errors.push(
            makeDiag(
              ruleId,
              eid,
              `${eid}：variant_groups 順序或項目不符預期（預期 ${JSON.stringify(expectedVgs)}，實際 ${JSON.stringify(actualVgs)}）`,
            ),
          );
        }
      }

      if (isPlainObject(end.repeat)) {
        const skipTo = String(end.repeat.skip_to ?? '');
        if (skipTo.length === 0) {
          errors.push(makeDiag(ruleId, eid, `${eid}：repeat 缺少 skip_to`));
        } else if (skipTo !== 'complete' && !repeatPageIds.has(skipTo)) {
          errors.push(
            makeDiag(
              ruleId,
              eid,
              `${eid}：repeat.skip_to 指向不存在的 repeat page id 或非 'complete' → ${skipTo}`,
            ),
          );
        }
      }

      if (!Array.isArray(end.lookup_fragments)) {
        errors.push(makeDiag(ruleId, eid, `${eid}：lookup_fragments 必須是 Array`));
      } else {
        for (const lf of end.lookup_fragments) {
          if (!isPlainObject(lf)) {
            errors.push(makeDiag(ruleId, eid, `${eid}：lookup_fragment 元素必須是 Dictionary`));
            continue;
          }
          const lfid = String(lf.id ?? '');
          if (!isPlainObject(lf.when_group)) {
            errors.push(makeDiag(ruleId, eid, `${eid} [${lfid}]：缺少 when_group 字典`));
          } else {
            const grpName = String(lf.when_group.group ?? '');
            const varName = String(lf.when_group.variant ?? '');
            if (!vgMap.has(grpName)) {
              errors.push(
                makeDiag(
                  ruleId,
                  eid,
                  `${eid} [${lfid}]：when_group.group 指向不存在的 variant_group → ${grpName}`,
                ),
              );
            } else if (!vgRuleMap.get(grpName)?.has(varName)) {
              errors.push(
                makeDiag(
                  ruleId,
                  eid,
                  `${eid} [${lfid}]：when_group.variant 指向不存在的 rule id → ${varName} (在 group ${grpName} 中)`,
                ),
              );
            }
          }
          const srcField = String(lf.source_field ?? '');
          if (srcField !== 'festival_proxy_npc') {
            errors.push(
              makeDiag(ruleId, eid, `${eid} [${lfid}]：未知 source_field → ${srcField}`),
            );
          }
          if (!Array.isArray(lf.entries)) {
            errors.push(makeDiag(ruleId, eid, `${eid} [${lfid}]：entries 必須為 Array`));
          } else {
            for (const entry of lf.entries) {
              if (!isPlainObject(entry)) {
                errors.push(makeDiag(ruleId, eid, `${eid} [${lfid}]：entry 必須是 Dictionary`));
                continue;
              }
              const npcVal = String(entry.value ?? '');
              const npc = data.npcsById.get(npcVal);
              if (!npc) {
                errors.push(
                  makeDiag(
                    ruleId,
                    eid,
                    `${eid} [${lfid}]：entries.value 引用不存在的 NPC → ${npcVal}`,
                  ),
                );
              } else if (npc.festival_proxy_eligible !== true) {
                errors.push(
                  makeDiag(
                    ruleId,
                    eid,
                    `${eid} [${lfid}]：entries.value 引用非 festival_proxy_eligible NPC → ${npcVal}`,
                  ),
                );
              }
              lintPageList(
                entry.first_seen_pages,
                eid,
                `${lfid}.${npcVal}.first_seen_pages`,
                pageIds,
                ruleId,
                errors,
              );
              lintPageList(
                entry.repeat_pages,
                eid,
                `${lfid}.${npcVal}.repeat_pages`,
                pageIds,
                ruleId,
                errors,
              );
            }
          }
        }
      }

      lintCompositePaths(end, eid, ruleId, errors);
    } else if (kind === 'linear') {
      if (!isPlainObject(end.first_seen)) {
        errors.push(makeDiag(ruleId, eid, `${eid}：缺少 first_seen`));
      } else if (!Array.isArray(end.first_seen.pages) || end.first_seen.pages.length === 0) {
        errors.push(makeDiag(ruleId, eid, `${eid}：first_seen.pages 必須為非空 Array`));
      } else {
        lintPageList(end.first_seen.pages, eid, 'first_seen.pages', pageIds, ruleId, errors);
      }

      if (!isPlainObject(end.repeat)) {
        errors.push(makeDiag(ruleId, eid, `${eid}：缺少 repeat`));
      } else {
        if (!Array.isArray(end.repeat.pages) || end.repeat.pages.length === 0) {
          errors.push(makeDiag(ruleId, eid, `${eid}：repeat.pages 必須為非空 Array`));
        } else {
          lintPageList(end.repeat.pages, eid, 'repeat.pages', pageIds, ruleId, errors);
          for (const p of end.repeat.pages) {
            if (isPlainObject(p)) {
              repeatPageIds.add(String(p.id ?? ''));
            }
          }
        }
        const skipTo = String(end.repeat.skip_to ?? '');
        if (skipTo.length === 0) {
          errors.push(makeDiag(ruleId, eid, `${eid}：repeat 缺少 skip_to`));
        } else if (skipTo !== 'complete' && !repeatPageIds.has(skipTo)) {
          errors.push(
            makeDiag(
              ruleId,
              eid,
              `${eid}：repeat.skip_to 指向不存在的 repeat page id 或非 'complete' → ${skipTo}`,
            ),
          );
        }
      }
    } else {
      errors.push(makeDiag(ruleId, eid, `${eid}：未知 kind → ${kind}`));
    }
  }

  for (const b of data.beats) {
    const rawBeat = b as unknown as JsonObject;
    const bid = String(rawBeat.id ?? '?');
    const pe = rawBeat.phase_exit;
    if (pe !== null && pe !== undefined) {
      if (!isPlainObject(pe)) {
        errors.push(makeDiag(ruleId, bid, `${bid}：phase_exit 必須為 Dictionary`));
      } else {
        if (rawBeat.fixed !== true) {
          errors.push(makeDiag(ruleId, bid, `${bid}：phase_exit 只能掛在 fixed:true 的 beat`));
        }
        const w = rawBeat.when;
        if (
          !isPlainObject(w) ||
          !('day' in w) ||
          w.day === undefined ||
          !('phase' in w) ||
          w.phase === undefined
        ) {
          errors.push(
            makeDiag(
              ruleId,
              bid,
              `${bid}：phase_exit 所在的 beat 必須有明確整數 day 與合法 phase`,
            ),
          );
        }
        const bSlotIds = new Set<string>();
        const bGroupIds = new Set<string>();
        for (const s of b.slots ?? []) {
          bSlotIds.add(String(s.id ?? ''));
          if ('choice_group' in s && s.choice_group !== undefined) {
            bGroupIds.add(String(s.choice_group ?? ''));
          }
        }

        const reqSlots = pe.required_slots;
        const reqGroups = pe.required_choice_groups;
        const hasSlots = Array.isArray(reqSlots) && reqSlots.length > 0;
        const hasGroups = Array.isArray(reqGroups) && reqGroups.length > 0;

        if (!hasSlots && !hasGroups) {
          errors.push(
            makeDiag(
              ruleId,
              bid,
              `${bid} [phase_exit]：required_slots 與 required_choice_groups 至少一個必須是非空 Array`,
            ),
          );
        }
        if (reqSlots !== null && reqSlots !== undefined && !Array.isArray(reqSlots)) {
          errors.push(makeDiag(ruleId, bid, `${bid} [phase_exit]：required_slots 必須為 Array`));
        }
        if (reqGroups !== null && reqGroups !== undefined && !Array.isArray(reqGroups)) {
          errors.push(
            makeDiag(ruleId, bid, `${bid} [phase_exit]：required_choice_groups 必須為 Array`),
          );
        }

        if (hasSlots) {
          const seenRs = new Set<string>();
          for (const rs of reqSlots) {
            const rsStr = String(rs);
            if (seenRs.has(rsStr)) {
              errors.push(
                makeDiag(
                  ruleId,
                  bid,
                  `${bid} [phase_exit]：required_slots 包含重複 slot id → ${rsStr}`,
                ),
              );
            }
            seenRs.add(rsStr);
            if (!bSlotIds.has(rsStr)) {
              errors.push(
                makeDiag(
                  ruleId,
                  bid,
                  `${bid} [phase_exit]：required_slots 引用父 beat 不存在的 slot id → ${rsStr}`,
                ),
              );
            }
          }
        }

        if (hasGroups) {
          const seenRg = new Set<string>();
          for (const rg of reqGroups) {
            const rgStr = String(rg);
            if (seenRg.has(rgStr)) {
              errors.push(
                makeDiag(
                  ruleId,
                  bid,
                  `${bid} [phase_exit]：required_choice_groups 包含重複 group id → ${rgStr}`,
                ),
              );
            }
            seenRg.add(rgStr);
            if (!bGroupIds.has(rgStr)) {
              errors.push(
                makeDiag(
                  ruleId,
                  bid,
                  `${bid} [phase_exit]：required_choice_groups 引用父 beat 不存在的 choice group → ${rgStr}`,
                ),
              );
            } else {
              const groupSlots = (b.slots ?? []).filter(
                (s) => String(s.choice_group ?? '') === rgStr,
              );
              let hasUnconditional = false;
              let reqCardId = '';
              let notCardId = '';
              for (const s of groupSlots) {
                const sCond = s.condition as unknown;
                const sReq = s.requires as unknown;
                const sCrc = Boolean(s.choice_requires_card);
                if (
                  (sCond === null || sCond === undefined) &&
                  (sReq === null || sReq === undefined) &&
                  !sCrc
                ) {
                  hasUnconditional = true;
                }
                if (sCrc && Array.isArray(s.accepts) && s.accepts.length > 0) {
                  reqCardId = String(s.accepts[0]);
                }
                if (isPlainObject(sCond) && 'has_card' in sCond) {
                  reqCardId = String(sCond.has_card);
                }
                if (isPlainObject(sCond) && isPlainObject(sCond.not) && 'has_card' in sCond.not) {
                  notCardId = String(sCond.not.has_card);
                }
              }
              const isComplementary = reqCardId.length > 0 && reqCardId === notCardId;
              if (!hasUnconditional && !isComplementary) {
                errors.push(
                  makeDiag(
                    ruleId,
                    bid,
                    `${bid} [phase_exit]：required_choice_groups 引用之 group '${rgStr}' 無無條件槽且未具可驗證之互補條件保證`,
                  ),
                );
              }
            }
          }
        }

        const hasEnding = 'ending' in pe && pe.ending !== undefined;
        const hasSource = 'source' in pe && pe.source !== undefined;
        if (hasEnding !== hasSource) {
          errors.push(
            makeDiag(
              ruleId,
              bid,
              `${bid} [phase_exit]：ending 與 source 必須同時存在或同時省略`,
            ),
          );
        } else if (hasEnding) {
          const peEnding = String(pe.ending ?? '');
          const peSource = String(pe.source ?? '');
          if (peEnding !== 'ending_replaced' || peSource !== 'd45_coda') {
            errors.push(
              makeDiag(
                ruleId,
                bid,
                `${bid} [phase_exit]：不合法的 ending/source 配對 → ${peEnding} / ${peSource}`,
              ),
            );
          }
        }
      }
    }

    checkSingleEndingEffect(rawBeat, bid, 'beat', ruleId, errors);
  }

  return { errors };
}

export function lint_opening_and_defaults(data: GameData): RuleOutput {
  const ruleId = 'lint_opening_and_defaults';
  const errors: Diagnostic[] = [];
  const actualOrder: string[] = [];

  const screenRaw = data.openingScreen as unknown as JsonObject;
  for (const field of ['title', 'prompt'] as const) {
    const val = screenRaw?.[field];
    if (typeof val !== 'string' || val.trim().length === 0) {
      errors.push(
        makeDiag(
          ruleId,
          'opening_choices.json',
          `opening_choices.json [screen.${field}]：必須為非空字串`,
        ),
      );
    }
  }

  for (const oc of data.openingChoices) {
    const rawOc = oc as unknown as JsonObject;
    const ocid = String(rawOc.id ?? '');
    actualOrder.push(ocid);

    if (String(rawOc.label ?? '').trim().length === 0) {
      errors.push(makeDiag(ruleId, ocid, `opening_choices [${ocid}]：label 不得為空`));
    }
    if (String(rawOc.preview ?? '').trim().length === 0) {
      errors.push(makeDiag(ruleId, ocid, `opening_choices [${ocid}]：preview 不得為空`));
    }
    if (String(rawOc.confirm_text ?? '').trim().length === 0) {
      errors.push(makeDiag(ruleId, ocid, `opening_choices [${ocid}]：confirm_text 不得為空`));
    }

    const hasOnSelect = 'on_select' in rawOc && rawOc.on_select !== undefined;
    const hasEnding = 'ending' in rawOc && rawOc.ending !== undefined;
    if (hasOnSelect && hasEnding) {
      errors.push(
        makeDiag(ruleId, ocid, `opening_choices [${ocid}]：不得同時包含 on_select 與 ending`),
      );
    } else if (!hasOnSelect && !hasEnding) {
      errors.push(
        makeDiag(ruleId, ocid, `opening_choices [${ocid}]：必須在 on_select 與 ending 中恰有一個`),
      );
    }

    if (hasOnSelect) {
      if (!isPlainObject(rawOc.on_select)) {
        errors.push(
          makeDiag(ruleId, ocid, `opening_choices [${ocid}]：on_select 必須為 Dictionary`),
        );
      } else if ('ending' in rawOc.on_select && rawOc.on_select.ending !== undefined) {
        errors.push(
          makeDiag(ruleId, ocid, `opening_choices [${ocid}]：on_select 不得內藏 ending`),
        );
      }
    }

    if (hasEnding) {
      const endVal = String(rawOc.ending ?? '');
      if (endVal !== 'ending_refuse_boarding') {
        errors.push(
          makeDiag(
            ruleId,
            ocid,
            `opening_choices [${ocid}]：ending 只能引用 ending_refuse_boarding（實際為 ${endVal}）`,
          ),
        );
      }
      if (!('requires' in rawOc) || rawOc.requires === undefined) {
        errors.push(
          makeDiag(ruleId, ocid, `opening_choices [${ocid}]：不上車必須包含 requires 門檻`),
        );
      } else {
        if (
          !isPlainObject(rawOc.requires) ||
          String(rawOc.requires.ending_seen ?? '') !== 'ending_replaced'
        ) {
          errors.push(
            makeDiag(
              ruleId,
              ocid,
              `opening_choices [${ocid}]：不上車門檻必須為 ending_seen: ending_replaced`,
            ),
          );
        }
        if (String(rawOc.reject_reason ?? '').trim().length === 0) {
          errors.push(
            makeDiag(
              ruleId,
              ocid,
              `opening_choices [${ocid}]：有 requires 時必須提供非空 reject_reason`,
            ),
          );
        }
      }
    }
  }

  if (JSON.stringify(actualOrder) !== JSON.stringify(EXPECTED_OPENING_CHOICE_IDS)) {
    errors.push(
      makeDiag(
        ruleId,
        'opening_choices.json',
        `opening_choices.json：順序或項目不符預期（預期 ${JSON.stringify(EXPECTED_OPENING_CHOICE_IDS)}，實際 ${JSON.stringify(actualOrder)}）`,
      ),
    );
  }

  for (const b of data.beats) {
    const rawBeat = b as unknown as JsonObject;
    const bid = String(rawBeat.id ?? '?');
    const isFixed = rawBeat.fixed === true;
    const groupsDefaults = new Map<string, number>();
    const groupsSlots = new Map<string, JsonObject[]>();

    for (const s of b.slots ?? []) {
      const sd = s as unknown as JsonObject;
      const sid = String(sd.id ?? '?');
      const cg = String(sd.choice_group ?? '');
      if (cg.length > 0) {
        const list = groupsSlots.get(cg) ?? [];
        list.push(sd);
        groupsSlots.set(cg, list);
      }
      const hasDefault = sd.default_if_unresolved === true;
      const reqCard = sd.choice_requires_card;

      if (hasDefault) {
        if (cg.length === 0) {
          errors.push(
            makeDiag(ruleId, bid, `${bid} [${sid}]：default_if_unresolved 只能用於 choice_group 槽`),
          );
        } else {
          groupsDefaults.set(cg, (groupsDefaults.get(cg) ?? 0) + 1);
        }
        if (!isFixed) {
          errors.push(
            makeDiag(
              ruleId,
              bid,
              `${bid} [${sid}]：default_if_unresolved 所在父 beat 必須為 fixed:true`,
            ),
          );
        }
        if (Array.isArray(sd.accepts) && sd.accepts.length > 0) {
          errors.push(
            makeDiag(ruleId, bid, `${bid} [${sid}]：default 槽不得收卡（accepts 必須為空）`),
          );
        }
        if (reqCard === true) {
          errors.push(
            makeDiag(
              ruleId,
              bid,
              `${bid} [${sid}]：default 槽不得同時設 choice_requires_card:true`,
            ),
          );
        }
      }

      if (reqCard !== null && reqCard !== undefined) {
        if (typeof reqCard !== 'boolean') {
          errors.push(
            makeDiag(ruleId, bid, `${bid} [${sid}]：choice_requires_card 必須為 boolean`),
          );
        } else if (reqCard === true) {
          if (cg.length === 0) {
            errors.push(
              makeDiag(ruleId, bid, `${bid} [${sid}]：choice_requires_card 只能用於 choice_group 槽`),
            );
          }
          if (!Array.isArray(sd.accepts) || sd.accepts.length === 0) {
            errors.push(
              makeDiag(
                ruleId,
                bid,
                `${bid} [${sid}]：choice_requires_card:true 必須有非空 accepts`,
              ),
            );
          }
        }
      }
    }

    for (const [cgName, count] of groupsDefaults.entries()) {
      if (count > 1) {
        errors.push(
          makeDiag(
            ruleId,
            bid,
            `${bid}：choice_group '${cgName}' 包含多個 default_if_unresolved 槽（${count} 個）`,
          ),
        );
      }
    }

    const needDefaultCg = REQUIRED_DEFAULT_GROUPS[bid];
    if (needDefaultCg) {
      if ((groupsDefaults.get(needDefaultCg) ?? 0) === 0) {
        errors.push(
          makeDiag(
            ruleId,
            bid,
            `${bid}：choice_group '${needDefaultCg}' 必須有一個 default_if_unresolved 槽`,
          ),
        );
      } else {
        for (const dsd of groupsSlots.get(needDefaultCg) ?? []) {
          if (dsd.default_if_unresolved !== true) {
            continue;
          }
          for (const blocker of ['condition', 'requires', 'delegation'] as const) {
            if (blocker in dsd && dsd[blocker] !== undefined) {
              errors.push(
                makeDiag(
                  ruleId,
                  bid,
                  `${bid} [${String(dsd.id ?? '?')}]：default 槽不得有 ${blocker}，否則無法由無卡 choose() 結算`,
                ),
              );
            }
          }
        }
      }
    }

    const needCardCg = REQUIRED_CARD_GROUPS[bid];
    if (needCardCg) {
      const cardSlots = groupsSlots.get(needCardCg) ?? [];
      if (cardSlots.length !== 2) {
        errors.push(
          makeDiag(
            ruleId,
            bid,
            `${bid}：choice_group '${needCardCg}' 必須恰有兩個工作槽（實際 ${cardSlots.length} 個）`,
          ),
        );
      }
      for (const csd of cardSlots) {
        const csid = String(csd.id ?? '?');
        if (csd.choice_requires_card !== true) {
          errors.push(
            makeDiag(
              ruleId,
              bid,
              `${bid} [${csid}]：choice_group '${needCardCg}' 的槽必須設 choice_requires_card:true`,
            ),
          );
        }
        const cAccepts = csd.accepts;
        const acceptsOnlyProtagonist =
          Array.isArray(cAccepts) && cAccepts.length === 1 && String(cAccepts[0]) === 'protagonist';
        if (!acceptsOnlyProtagonist) {
          errors.push(
            makeDiag(
              ruleId,
              bid,
              `${bid} [${csid}]：choice_group '${needCardCg}' 的槽 accepts 只能收 protagonist（實際 ${JSON.stringify(cAccepts)}）`,
            ),
          );
        }
      }
    }
  }

  return { errors };
}

function checkPermanentLose(
  node: unknown,
  bid: string,
  where: string,
  data: GameData,
  ruleId: string,
  problems: Diagnostic[],
): void {
  if (isPlainObject(node)) {
    if (Array.isArray(node.lose)) {
      for (const entry of node.lose) {
        if (isPlainObject(entry) && entry.permanent === true) {
          const cid = String(entry.card ?? '');
          const card = data.cardsById.get(cid);
          if (!card || card.loop_persistent !== true) {
            problems.push(
              makeDiag(
                ruleId,
                bid,
                `${bid} [${where}]：lose 的 permanent:true 指向非 loop_persistent 卡 → ${cid}`,
              ),
            );
          }
        }
      }
    }
    for (const [k, v] of Object.entries(node)) {
      checkPermanentLose(v, bid, `${where}.${k}`, data, ruleId, problems);
    }
  } else if (Array.isArray(node)) {
    for (const v of node) {
      checkPermanentLose(v, bid, where, data, ruleId, problems);
    }
  }
}

function condMatchesProxyIs(cond: unknown, npcId: string): boolean {
  if (!isPlainObject(cond)) {
    return false;
  }
  if ('festival_proxy_is' in cond && String(cond.festival_proxy_is) === npcId) {
    return true;
  }
  if (Array.isArray(cond.all)) {
    for (const sub of cond.all) {
      if (condMatchesProxyIs(sub, npcId)) {
        return true;
      }
    }
  }
  if (Array.isArray(cond.any)) {
    for (const sub of cond.any) {
      if (condMatchesProxyIs(sub, npcId)) {
        return true;
      }
    }
  }
  return false;
}

export function lint_loop_and_festival(data: GameData): RuleOutput {
  const ruleId = 'lint_loop_and_festival';
  const errors: Diagnostic[] = [];

  let totalPersistentSlots = 0;
  for (const card of data.cards) {
    const rawCard = card as unknown as JsonObject;
    const cid = card.id;
    if (!('loop_persistent' in rawCard) || rawCard.loop_persistent === undefined) {
      errors.push(makeDiag(ruleId, cid, `卡片 ${cid}：缺少必填欄位 loop_persistent`));
    } else if (typeof rawCard.loop_persistent !== 'boolean') {
      errors.push(makeDiag(ruleId, cid, `卡片 ${cid}：loop_persistent 必須是 boolean`));
    } else if (rawCard.loop_persistent === true) {
      const ctype = String(card.type ?? '');
      if (card.slotless === true || ctype === 'protagonist' || ctype === 'madness') {
        errors.push(
          makeDiag(
            ruleId,
            cid,
            `卡片 ${cid}：loop_persistent:true 只能用於 slotless:false、非 protagonist、非 madness 的卡`,
          ),
        );
      }
      totalPersistentSlots += 1;
    }
  }

  const handSize = typeof data.tuning?.hand_size === 'number' ? Math.trunc(data.tuning.hand_size) : 6;
  if (totalPersistentSlots + 1 > handSize) {
    errors.push(
      makeDiag(
        ruleId,
        'cards.json',
        `跨輪保留卡片佔格上限超載（${totalPersistentSlots} + 1 > hand_size ${handSize}）`,
      ),
    );
  }

  for (const b of data.beats) {
    const bid = String(b.id ?? '?');
    checkPermanentLose(b, bid, 'beat', data, ruleId, errors);
  }

  const eligibleNpcs: string[] = [];
  for (const npc of data.npcs) {
    const rawNpc = npc as unknown as JsonObject;
    const nid = npc.id;
    if (!('festival_proxy_eligible' in rawNpc) || rawNpc.festival_proxy_eligible === undefined) {
      errors.push(makeDiag(ruleId, nid, `NPC ${nid}：缺少必填欄位 festival_proxy_eligible`));
    } else if (typeof rawNpc.festival_proxy_eligible !== 'boolean') {
      errors.push(makeDiag(ruleId, nid, `NPC ${nid}：festival_proxy_eligible 必須是 boolean`));
    } else if (rawNpc.festival_proxy_eligible === true) {
      eligibleNpcs.push(nid);
    }
  }

  for (const enpc of eligibleNpcs) {
    let hasAttention = false;
    for (const b of data.beats) {
      for (const s of b.slots ?? []) {
        if (String(s.attention_npc ?? '') === enpc) {
          hasAttention = true;
          break;
        }
      }
      if (hasAttention) {
        break;
      }
    }
    if (!hasAttention) {
      errors.push(
        makeDiag(
          ruleId,
          enpc,
          `NPC ${enpc} (festival_proxy_eligible:true)：未被任何 slot 的 attention_npc 引用`,
        ),
      );
    }

    const endRep = data.endingsById.get('ending_replaced') as unknown as JsonObject | undefined;
    let hasFragEntry = false;
    if (endRep && Array.isArray(endRep.lookup_fragments)) {
      for (const lf of endRep.lookup_fragments) {
        if (isPlainObject(lf) && lf.id === 'uninvited_proxy' && Array.isArray(lf.entries)) {
          for (const entry of lf.entries) {
            if (isPlainObject(entry) && String(entry.value ?? '') === enpc) {
              hasFragEntry = true;
              break;
            }
          }
        }
      }
    }
    if (!hasFragEntry) {
      errors.push(
        makeDiag(
          ruleId,
          enpc,
          `NPC ${enpc} (festival_proxy_eligible:true)：在 endings.json 的 uninvited_proxy 缺少對應 fragment`,
        ),
      );
    }

    let d31Found = false;
    let d39Found = false;
    for (const b of data.beats) {
      if (!isPlainObject(b.when)) {
        continue;
      }
      const dayNum = typeof b.when.day === 'number' ? Math.trunc(b.when.day) : 0;
      if (dayNum === 31 && condMatchesProxyIs(b.condition, enpc)) {
        d31Found = true;
      }
      if (dayNum === 39 && condMatchesProxyIs(b.condition, enpc)) {
        d39Found = true;
      }
    }
    if (!d31Found) {
      errors.push(
        makeDiag(
          ruleId,
          enpc,
          `NPC ${enpc} (festival_proxy_eligible:true)：缺少第 31 天 festival_proxy_is 內容`,
        ),
      );
    }
    if (!d39Found) {
      errors.push(
        makeDiag(
          ruleId,
          enpc,
          `NPC ${enpc} (festival_proxy_eligible:true)：缺少第 39 天 festival_proxy_is 內容`,
        ),
      );
    }
  }

  const d29Beat = data.beatsById.get('d29_pm_invitation');
  if (d29Beat) {
    for (const s of d29Beat.slots ?? []) {
      if (s.default_if_unresolved === true && isPlainObject(s.on_place)) {
        const fp = s.on_place.festival_proxy;
        if (isPlainObject(fp)) {
          const fb = String(fp.fallback ?? '');
          if (!eligibleNpcs.includes(fb)) {
            errors.push(
              makeDiag(
                ruleId,
                'd29_pm_invitation',
                `D29 default 槽的 festival_proxy fallback '${fb}' 不是合法候選 NPC`,
              ),
            );
          }
        }
      }
    }
  }

  return { errors };
}

function phaseOrderOf(beat: Beat): number {
  const when = (beat as unknown as JsonObject).when;
  if (!isPlainObject(when) || !('day' in when) || !('phase' in when)) {
    return -1;
  }
  const phaseIdx = PHASES.indexOf(String(when.phase) as Phase);
  if (phaseIdx < 0 || typeof when.day !== 'number' || !Number.isFinite(when.day)) {
    return -1;
  }
  return Math.trunc(when.day) * PHASES.length + phaseIdx;
}

function collectConditionFlags(cond: unknown, out: string[]): void {
  if (!isPlainObject(cond)) {
    return;
  }
  if ('flag' in cond && cond.flag !== undefined) {
    const name = String(cond.flag);
    if (!out.includes(name)) {
      out.push(name);
    }
  }
  for (const key of ['all', 'any'] as const) {
    if (Array.isArray(cond[key])) {
      for (const sub of cond[key] as unknown[]) {
        collectConditionFlags(sub, out);
      }
    }
  }
}

export function lint_phase_lifecycle(data: GameData): RuleOutput {
  const ruleId = 'lint_phase_lifecycle';
  const errors: Diagnostic[] = [];
  const autoFlagOrder = new Map<string, number>();

  for (const beat of data.beats) {
    const rawBeat = beat as unknown as JsonObject;
    const bid = String(rawBeat.id ?? '');
    if (!('auto_enter' in rawBeat) || rawBeat.auto_enter === undefined) {
      continue;
    }
    if (typeof rawBeat.auto_enter !== 'boolean') {
      errors.push(makeDiag(ruleId, bid, `beat ${bid}：auto_enter 必須是 boolean`));
      continue;
    }
    if (rawBeat.auto_enter !== true) {
      continue;
    }
    if (rawBeat.fixed !== true) {
      errors.push(
        makeDiag(ruleId, bid, `beat ${bid}：auto_enter:true 只能用於 fixed:true 的 beat`),
      );
      continue;
    }

    const order = phaseOrderOf(beat);
    if (order < 0) {
      errors.push(
        makeDiag(ruleId, bid, `beat ${bid}：auto_enter:true 需要明確的 when.day 與 when.phase`),
      );
      continue;
    }

    if (!isPlainObject(rawBeat.on_enter) || !isPlainObject(rawBeat.on_enter.flag)) {
      continue;
    }
    for (const [flagName, flagVal] of Object.entries(rawBeat.on_enter.flag)) {
      if (flagVal !== true) {
        continue;
      }
      const prev = autoFlagOrder.get(flagName);
      if (prev === undefined || order < prev) {
        autoFlagOrder.set(flagName, order);
      }
    }
  }

  for (const beat of data.beats) {
    const rawBeat = beat as unknown as JsonObject;
    if (!('phase_exit' in rawBeat) || rawBeat.phase_exit === undefined) {
      continue;
    }
    const bid = String(rawBeat.id ?? '');
    const order = phaseOrderOf(beat);
    if (order < 0) {
      errors.push(
        makeDiag(ruleId, bid, `beat ${bid}：帶 phase_exit 需要明確的 when.day 與 when.phase`),
      );
      continue;
    }
    const needed: string[] = [];
    collectConditionFlags(rawBeat.condition, needed);
    for (const flagName of needed) {
      const flagOrd = autoFlagOrder.get(flagName);
      if (flagOrd === undefined) {
        errors.push(
          makeDiag(
            ruleId,
            bid,
            `beat ${bid} [phase_exit]：condition 依賴的旗標 ${flagName} 沒有任何 auto_enter beat 寫入，玩家可能繞過整條生命週期`,
          ),
        );
      } else if (flagOrd >= order) {
        errors.push(
          makeDiag(
            ruleId,
            bid,
            `beat ${bid} [phase_exit]：condition 依賴的旗標 ${flagName} 只由同時段或更晚的 auto_enter beat 寫入`,
          ),
        );
      }
    }
  }

  return { errors };
}

/* ------------------------------------------------------------------ */
/* Registry 與 validateData 主入口                                     */
/* ------------------------------------------------------------------ */

export const LINT_REGISTRY: readonly LintRuleEntry[] = [
  // 1. 基本結構、引用、tuning
  { id: 'verify_references', group: 'structure_refs_tuning', run: verify_references },
  {
    id: 'Data.REQUIRED_TUNING_KEYS',
    group: 'structure_refs_tuning',
    run: validate_tuning_and_action_phases,
  },
  // 2. 語彙與卡型
  { id: 'lint_vocabulary', group: 'vocabulary_card_types', run: lint_vocabulary },
  { id: 'lint_card_types', group: 'vocabulary_card_types', run: lint_card_types },
  {
    id: 'lint_missing_reject_reason',
    group: 'vocabulary_card_types',
    run: lint_missing_reject_reason,
  },
  // 3. 白天供需、免費槽、殘響（lint_choice_rules / lint_free_slot_rules 同源只登錄一次）
  { id: 'lint_free_slot_rules', group: 'day_supply_free_slot_echo', run: lint_free_slot_rules },
  { id: 'lint_action_phases', group: 'day_supply_free_slot_echo', run: lint_action_phases },
  { id: 'lint_echoes', group: 'day_supply_free_slot_echo', run: lint_echoes },
  // 4. 縱慾
  { id: 'lint_indulgence_integrity', group: 'indulgence', run: lint_indulgence_integrity },
  { id: 'lint_indulgence_exits', group: 'indulgence', run: lint_indulgence_exits },
  // 5. 夜間
  { id: 'lint_night_reachability', group: 'night', run: lint_night_reachability },
  { id: 'lint_night_alignment', group: 'night', run: lint_night_alignment },
  { id: 'lint_night_locations', group: 'night', run: lint_night_locations },
  { id: 'lint_legacy_night_flags', group: 'night', run: lint_legacy_night_flags },
  { id: 'lint_night_once', group: 'night', run: lint_night_once },
  { id: 'lint_night_location_descs', group: 'night', run: lint_night_location_descs },
  // 6. 委託、遭遇
  { id: 'lint_delegations', group: 'delegation_encounter', run: lint_delegations },
  { id: 'lint_encounters', group: 'delegation_encounter', run: lint_encounters },
  // 7. 開局、結局、跨輪
  { id: 'lint_endings', group: 'opening_ending_loop', run: lint_endings },
  {
    id: 'lint_opening_and_defaults',
    group: 'opening_ending_loop',
    run: lint_opening_and_defaults,
  },
  { id: 'lint_loop_and_festival', group: 'opening_ending_loop', run: lint_loop_and_festival },
  { id: 'lint_phase_lifecycle', group: 'opening_ending_loop', run: lint_phase_lifecycle },
];

export function validateData(data: GameData): ValidationReport {
  const errors: Diagnostic[] = [];
  const warnings: Diagnostic[] = [];
  const executedRules: string[] = [];

  for (const rule of LINT_REGISTRY) {
    executedRules.push(rule.id);
    const out = rule.run(data);
    errors.push(...out.errors);
    if (out.warnings) {
      warnings.push(...out.warnings);
    }
  }

  return {
    errors,
    warnings,
    executedRules,
  };
}
