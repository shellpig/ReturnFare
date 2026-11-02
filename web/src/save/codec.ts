/**
 * ReturnFare Web — 存檔序列化與嚴格解碼驗證（W7-B1）。
 *
 * 提供純函式：
 * - encodeSave(snapshot, savedAt): string
 * - decodeSave(text, data): SaveDecodeResult
 *
 * 嚴格驗證 unknown 輸入的所有欄位型別、數值範圍、mode/active 關聯、
 * 卡片與發狂時鐘一致性、beat/slot/group 引用、ending/history 規約。
 * 成功時回傳完全未竄改的可信 GameSnapshot；失敗時回傳具體錯誤代碼與訊息。
 */

import { cardBaseId, LAST_DAY, PHASES, phasesForDay } from '../core/facts';
import {
  HISTORY_RECORD_KEYS,
  parseEndingResultFields,
  parseEndingSnapshot,
} from '../core/ending';
import type {
  ActiveEndingSnapshot,
  GameSnapshot,
} from '../core/state-types';
import type { GameData } from '../data/types';
import {
  SAVE_FORMAT,
  SAVE_VERSION,
  type SaveDecodeResult,
  type SaveEnvelope,
} from './types';

function isPlainObject(val: unknown): val is Record<string, unknown> {
  return typeof val === 'object' && val !== null && !Array.isArray(val);
}

function hasOwn(obj: object, key: string): boolean {
  return Object.prototype.hasOwnProperty.call(obj, key);
}

function isStrictInt(val: unknown): val is number {
  return typeof val === 'number' && Number.isInteger(val) && Number.isFinite(val);
}

/** 序列化 GameSnapshot 為標準 SaveEnvelope JSON 字串。 */
export function encodeSave(snapshot: GameSnapshot, savedAt: string): string {
  const envelope: SaveEnvelope = {
    format: SAVE_FORMAT,
    version: SAVE_VERSION,
    saved_at: savedAt,
    state: snapshot,
  };
  return JSON.stringify(envelope, null, 2);
}

/**
 * 完整解碼並驗證存檔字串。
 *
 * 若成功，回傳驗證過之可信 GameSnapshot 與 envelope；
 * 若失敗，回傳對應的 SaveDecodeResult 失敗物件（零狀態副作用）。
 */
export function decodeSave(text: string, data: GameData): SaveDecodeResult {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch (err) {
    return {
      ok: false,
      reason_code: 'invalid_json',
      error: `JSON 解析失敗: ${(err as Error).message}`,
    };
  }

  if (!isPlainObject(parsed)) {
    return {
      ok: false,
      reason_code: 'invalid_envelope',
      error: '存檔頂層必須為物件',
    };
  }

  if (parsed.format !== SAVE_FORMAT) {
    return {
      ok: false,
      reason_code: 'invalid_envelope',
      error: `不支援的存檔格式: ${String(parsed.format)}`,
    };
  }

  if (!isStrictInt(parsed.version)) {
    return {
      ok: false,
      reason_code: 'unsupported_version',
      error: '存檔版本號必須為整數',
    };
  }
  if (parsed.version !== SAVE_VERSION) {
    return {
      ok: false,
      reason_code: 'unsupported_version',
      error: `不支援的存檔版本號: ${parsed.version}`,
    };
  }

  // 版本確認後才檢查欄位數，較新版本多出的欄位才會回報 unsupported_version
  const envelopeKeys = Object.keys(parsed);
  if (
    envelopeKeys.length !== 4 ||
    !hasOwn(parsed, 'format') ||
    !hasOwn(parsed, 'version') ||
    !hasOwn(parsed, 'saved_at') ||
    !hasOwn(parsed, 'state')
  ) {
    return {
      ok: false,
      reason_code: 'invalid_envelope',
      error: '存檔 envelope 欄位不完整或含有未知欄位',
    };
  }

  const ISO_UTC_REGEX = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$/;
  if (
    typeof parsed.saved_at !== 'string' ||
    !ISO_UTC_REGEX.test(parsed.saved_at) ||
    Number.isNaN(Date.parse(parsed.saved_at)) ||
    new Date(parsed.saved_at).toISOString().slice(0, 19) !== parsed.saved_at.slice(0, 19)
  ) {
    return {
      ok: false,
      reason_code: 'invalid_envelope',
      error: 'saved_at 必須為合法的 UTC ISO 8601 時間字串 (結尾為 Z)',
    };
  }

  const stateValidation = validateSnapshot(parsed.state, data);
  if (!stateValidation.ok) {
    return {
      ok: false,
      reason_code: 'invalid_save_shape',
      error: stateValidation.error,
    };
  }

  return {
    ok: true,
    state: parsed.state as unknown as GameSnapshot,
    envelope: parsed as unknown as SaveEnvelope,
  };
}

interface ValidationSuccess {
  readonly ok: true;
}

interface ValidationFailure {
  readonly ok: false;
  readonly error: string;
}

type ValidationResult = ValidationSuccess | ValidationFailure;

function valid(): ValidationSuccess {
  return { ok: true };
}

function fail(error: string): ValidationFailure {
  return { ok: false, error };
}

/** 完整嚴格驗證 GameSnapshot 內部每一欄位。 */
function validateSnapshot(stateRaw: unknown, data: GameData): ValidationResult {
  if (!isPlainObject(stateRaw)) {
    return fail('state 必須為物件');
  }

  const topKeys = Object.keys(stateRaw);
  if (
    topKeys.length !== 3 ||
    !hasOwn(stateRaw, 'flow') ||
    !hasOwn(stateRaw, 'run') ||
    !hasOwn(stateRaw, 'meta')
  ) {
    return fail('state 必須精確包含 flow、run、meta 三個區塊');
  }

  const flowResult = validateFlow(stateRaw.flow, data);
  if (!flowResult.ok) return flowResult;

  const metaResult = validateMeta(stateRaw.meta, data);
  if (!metaResult.ok) return metaResult;

  const runResult = validateRun(stateRaw.run, stateRaw.flow as { mode: string }, data);
  if (!runResult.ok) return runResult;

  return valid();
}

function validateFlow(flowRaw: unknown, data: GameData): ValidationResult {
  if (!isPlainObject(flowRaw)) return fail('flow 必須為物件');
  const keys = Object.keys(flowRaw);
  if (keys.length !== 2 || !hasOwn(flowRaw, 'mode') || !hasOwn(flowRaw, 'active_ending')) {
    return fail('flow 必須精確包含 mode 與 active_ending');
  }

  const mode = flowRaw.mode;
  if (mode !== 'opening' && mode !== 'run' && mode !== 'ending') {
    return fail(`未知的 flow.mode: ${String(mode)}`);
  }

  const activeEnding = flowRaw.active_ending;
  if (mode === 'ending') {
    if (activeEnding === null || typeof activeEnding !== 'object') {
      return fail('flow.mode 為 ending 時 active_ending 不得為 null');
    }
    const parsedEnding: ActiveEndingSnapshot | null = parseEndingSnapshot(activeEnding, data);
    if (parsedEnding === null) {
      return fail('active_ending 快照不合法');
    }
  } else {
    if (activeEnding !== null) {
      return fail(`flow.mode 為 ${mode} 時 active_ending 必須為 null`);
    }
  }

  return valid();
}

function validateMeta(metaRaw: unknown, data: GameData): ValidationResult {
  if (!isPlainObject(metaRaw)) return fail('meta 必須為物件');

  const expectedKeys = [
    'knowledge',
    'night_locations_seen',
    'night_once_beats_seen',
    'day_locations_visited',
    'delegation_tutorial_seen',
    'run_number',
    'ending_history',
    'loop_persistent_item_ids',
  ];

  const actualKeys = Object.keys(metaRaw);
  if (actualKeys.length !== expectedKeys.length) {
    return fail('meta 欄位數量不符');
  }
  for (const k of expectedKeys) {
    if (!hasOwn(metaRaw, k)) {
      return fail(`meta 缺少必要欄位: ${k}`);
    }
  }

  if (!isStrictInt(metaRaw.run_number) || metaRaw.run_number < 1) {
    return fail('meta.run_number 必須為 >= 1 的整數');
  }

  if (typeof metaRaw.delegation_tutorial_seen !== 'boolean') {
    return fail('meta.delegation_tutorial_seen 必須為布林值');
  }

  // loop_persistent_item_ids
  if (!isPlainObject(metaRaw.loop_persistent_item_ids)) {
    return fail('meta.loop_persistent_item_ids 必須為物件');
  }
  for (const cardId of Object.keys(metaRaw.loop_persistent_item_ids)) {
    if (metaRaw.loop_persistent_item_ids[cardId] !== true) {
      return fail(`meta.loop_persistent_item_ids['${cardId}'] 值必須為 true`);
    }
    const card = data.cardsById.get(cardId);
    if (!card || card.loop_persistent !== true) {
      return fail(`meta.loop_persistent_item_ids 引用了非跨輪保留卡片: '${cardId}'`);
    }
  }

  // day_locations_visited
  if (!isPlainObject(metaRaw.day_locations_visited)) {
    return fail('meta.day_locations_visited 必須為物件');
  }
  for (const locId of Object.keys(metaRaw.day_locations_visited)) {
    if (metaRaw.day_locations_visited[locId] !== true) {
      return fail(`meta.day_locations_visited['${locId}'] 值必須為 true`);
    }
    const loc = data.locationsById.get(locId);
    if (!loc || loc.layer !== 'day') {
      return fail(`meta.day_locations_visited 引用了非白天地點: '${locId}'`);
    }
  }

  // night_locations_seen
  if (!isPlainObject(metaRaw.night_locations_seen)) {
    return fail('meta.night_locations_seen 必須為物件');
  }
  for (const locId of Object.keys(metaRaw.night_locations_seen)) {
    if (metaRaw.night_locations_seen[locId] !== true) {
      return fail(`meta.night_locations_seen['${locId}'] 值必須為 true`);
    }
    const loc = data.locationsById.get(locId);
    if (!loc || loc.layer !== 'night') {
      return fail(`meta.night_locations_seen 引用了非夜間地點: '${locId}'`);
    }
  }

  // night_once_beats_seen
  if (!isPlainObject(metaRaw.night_once_beats_seen)) {
    return fail('meta.night_once_beats_seen 必須為物件');
  }
  for (const beatId of Object.keys(metaRaw.night_once_beats_seen)) {
    if (metaRaw.night_once_beats_seen[beatId] !== true) {
      return fail(`meta.night_once_beats_seen['${beatId}'] 值必須為 true`);
    }
    const beat = data.beatsById.get(beatId);
    if (!beat) {
      return fail(`meta.night_once_beats_seen 引用了不存在的 beat: '${beatId}'`);
    }
    if (beat.meta_once !== true) {
      return fail(`meta.night_once_beats_seen 引用了非 meta_once 的 beat: '${beatId}'`);
    }
  }

  // knowledge
  if (!isPlainObject(metaRaw.knowledge)) {
    return fail('meta.knowledge 必須為物件');
  }
  for (const cardId of Object.keys(metaRaw.knowledge)) {
    if (metaRaw.knowledge[cardId] !== true) {
      return fail(`meta.knowledge['${cardId}'] 值必須為 true`);
    }
    const card = data.cardsById.get(cardId);
    if (!card || card.type !== 'knowledge' || card.slotless !== true) {
      return fail(`meta.knowledge 含有非知識卡或非無槽卡項目: '${cardId}'`);
    }
  }

  // ending_history
  if (!Array.isArray(metaRaw.ending_history)) {
    return fail('meta.ending_history 必須為陣列');
  }
  for (let i = 0; i < metaRaw.ending_history.length; i += 1) {
    const entry = metaRaw.ending_history[i];
    if (!isPlainObject(entry)) {
      return fail(`meta.ending_history[${i}] 必須為物件`);
    }
    const entryKeys = Object.keys(entry);
    if (entryKeys.length !== HISTORY_RECORD_KEYS.length) {
      return fail(`meta.ending_history[${i}] 欄位數量不符`);
    }
    for (const key of HISTORY_RECORD_KEYS) {
      if (!hasOwn(entry, key)) {
        return fail(`meta.ending_history[${i}] 缺少欄位: ${key}`);
      }
    }
    const parsed = parseEndingResultFields(entry, data);
    if (parsed === null) {
      return fail(`meta.ending_history[${i}] 結果欄位驗證失敗`);
    }
  }

  return valid();
}

function validateRun(
  runRaw: unknown,
  flow: { mode: string },
  data: GameData,
): ValidationResult {
  if (!isPlainObject(runRaw)) return fail('run 必須為物件');

  const expectedKeys = [
    'day',
    'phase',
    'opening_choice_id',
    'knowledge_at_start',
    'selected_festival_proxy_npc',
    'action_spent',
    'actions_spent_ahead',
    'hand',
    'madness_clock',
    '_madness_counter',
    'beats_entered',
    'slots_placed',
    'choices',
    'flags',
    'switches',
    'switch_progress',
    'relations',
    'npc_action_counts',
    'night_location_chosen',
    'night_sleep_pending',
    'indulgence_count',
    'madness_cards_cleared',
    'forced_pending',
    'delegates_used_today',
    'pending_delegation_reports',
    'active_encounter',
  ];

  const actualKeys = Object.keys(runRaw);
  if (actualKeys.length !== expectedKeys.length) {
    return fail(`run 欄位數量不符 (期望 ${expectedKeys.length} 欄，實際 ${actualKeys.length} 欄)`);
  }
  for (const k of expectedKeys) {
    if (!hasOwn(runRaw, k)) {
      return fail(`run 缺少必要欄位: ${k}`);
    }
  }

  // day & phase
  if (!isStrictInt(runRaw.day) || runRaw.day < 1 || runRaw.day > LAST_DAY) {
    return fail(`run.day 必須為 1 至 ${LAST_DAY} 的整數`);
  }
  const legalPhases = phasesForDay(runRaw.day);
  if (
    typeof runRaw.phase !== 'string' ||
    !(legalPhases as readonly string[]).includes(runRaw.phase)
  ) {
    return fail(`run.phase 必須為該日合法時段 (第 ${runRaw.day} 天可選: ${legalPhases.join(', ')}): '${String(runRaw.phase)}'`);
  }

  // opening_choice_id
  if (runRaw.opening_choice_id !== null) {
    if (
      typeof runRaw.opening_choice_id !== 'string' ||
      !data.openingChoicesById.has(runRaw.opening_choice_id)
    ) {
      return fail(`run.opening_choice_id 引用了不存在的開局選項: '${String(runRaw.opening_choice_id)}'`);
    }
  }

  // knowledge_at_start
  if (!isPlainObject(runRaw.knowledge_at_start)) {
    return fail('run.knowledge_at_start 必須為物件');
  }
  for (const cid of Object.keys(runRaw.knowledge_at_start)) {
    if (runRaw.knowledge_at_start[cid] !== true) {
      return fail(`run.knowledge_at_start['${cid}'] 值必須為 true`);
    }
    const card = data.cardsById.get(cid);
    if (!card || card.type !== 'knowledge' || card.slotless !== true) {
      return fail(`run.knowledge_at_start 含有非知識卡或非無槽卡: '${cid}'`);
    }
  }

  // selected_festival_proxy_npc
  if (runRaw.selected_festival_proxy_npc !== null) {
    const proxy = runRaw.selected_festival_proxy_npc;
    if (
      typeof proxy !== 'string' ||
      data.npcsById.get(proxy)?.festival_proxy_eligible !== true
    ) {
      return fail(`run.selected_festival_proxy_npc 非合法慶典代付候選 NPC: '${String(proxy)}'`);
    }
  }

  // action_spent & actions_spent_ahead
  if (typeof runRaw.action_spent !== 'boolean') {
    return fail('run.action_spent 必須為布林值');
  }
  if (!isStrictInt(runRaw.actions_spent_ahead) || runRaw.actions_spent_ahead < 0) {
    return fail('run.actions_spent_ahead 必須為 >= 0 的整數');
  }

  // _madness_counter
  if (!isStrictInt(runRaw._madness_counter) || runRaw._madness_counter < 0) {
    return fail('run._madness_counter 必須為 >= 0 的整數');
  }

  // hand & madness_clock
  if (!Array.isArray(runRaw.hand)) {
    return fail('run.hand 必須為陣列');
  }
  if (!isPlainObject(runRaw.madness_clock)) {
    return fail('run.madness_clock 必須為物件');
  }

  const handCards = new Set<string>();
  const madnessInstancesInHand = new Set<string>();
  const madnessCountdownCap = Number(data.tuning.madness_countdown_days);

  for (let i = 0; i < runRaw.hand.length; i += 1) {
    const item = runRaw.hand[i];
    if (typeof item !== 'string' || item.length === 0) {
      return fail(`run.hand[${i}] 必須為非空字串`);
    }
    if (handCards.has(item)) {
      return fail(`run.hand 含有重複卡片項目: '${item}'`);
    }
    handCards.add(item);

    const baseId = cardBaseId(item);
    if (baseId === 'madness') {
      const match = /^madness#(\d+)$/.exec(item);
      if (!match) {
        return fail(`run.hand 中的發狂卡實例 ID 格式錯誤: '${item}'`);
      }
      const instanceNum = Number.parseInt(match[1], 10);
      if (instanceNum < 1 || instanceNum > runRaw._madness_counter) {
        return fail(`run.hand 中的發狂卡序號 ${instanceNum} 超過 _madness_counter (${runRaw._madness_counter})`);
      }
      madnessInstancesInHand.add(item);

      if (!hasOwn(runRaw.madness_clock, item)) {
        return fail(`run.hand 中的發狂卡 '${item}' 缺少對應之 madness_clock 記錄`);
      }
      const countdown = runRaw.madness_clock[item];
      if (!isStrictInt(countdown) || countdown < 0 || countdown > madnessCountdownCap) {
        return fail(`run.madness_clock['${item}'] 倒數數值不合法 (${String(countdown)})`);
      }
    } else {
      const card = data.cardsById.get(item);
      if (!card) {
        return fail(`run.hand 引用了不存在的卡片: '${item}'`);
      }
      if (card.slotless === true) {
        return fail(`run.hand 不得包含無槽知識卡: '${item}'`);
      }
    }
  }

  // madness_clock 內的所有 key 必須都在手牌中
  const clockKeys = Object.keys(runRaw.madness_clock);
  if (clockKeys.length !== madnessInstancesInHand.size) {
    return fail('run.madness_clock 含有不在手牌中的多餘發狂卡項目');
  }
  for (const k of clockKeys) {
    if (!madnessInstancesInHand.has(k)) {
      return fail(`run.madness_clock 項目 '${k}' 不在手牌中`);
    }
  }

  // beats_entered
  if (!isPlainObject(runRaw.beats_entered)) {
    return fail('run.beats_entered 必須為物件');
  }
  for (const bid of Object.keys(runRaw.beats_entered)) {
    if (runRaw.beats_entered[bid] !== true) {
      return fail(`run.beats_entered['${bid}'] 值必須為 true`);
    }
    if (!data.beatsById.has(bid)) {
      return fail(`run.beats_entered 引用了不存在的 beat: '${bid}'`);
    }
  }

  // slots_placed
  if (!isPlainObject(runRaw.slots_placed)) {
    return fail('run.slots_placed 必須為物件');
  }
  for (const slotKey of Object.keys(runRaw.slots_placed)) {
    if (runRaw.slots_placed[slotKey] !== true) {
      return fail(`run.slots_placed['${slotKey}'] 值必須為 true`);
    }
    const parts = slotKey.split('::');
    if (parts.length !== 2) {
      return fail(`run.slots_placed 格式錯誤 (應為 beatId::slotId): '${slotKey}'`);
    }
    const [bid, sid] = parts;
    const beat = data.beatsById.get(bid);
    if (!beat) {
      return fail(`run.slots_placed 引用了不存在的 beat: '${bid}'`);
    }
    const hasSlot = (beat.slots ?? []).some((s) => s.id === sid);
    if (!hasSlot) {
      return fail(`run.slots_placed 引用了 beat '${bid}' 中不存在的 slot: '${sid}'`);
    }
  }

  // choices
  if (!isPlainObject(runRaw.choices)) {
    return fail('run.choices 必須為物件');
  }
  const choicesMap = runRaw.choices as Record<string, unknown>;
  const slotsPlacedMap = runRaw.slots_placed as Record<string, unknown>;

  for (const choiceKey of Object.keys(choicesMap)) {
    const slotId: unknown = choicesMap[choiceKey];
    if (typeof slotId !== 'string') {
      return fail(`run.choices['${choiceKey}'] 值必須為字串 slotId`);
    }
    const parts = choiceKey.split('::');
    if (parts.length !== 2) {
      return fail(`run.choices 鍵格式錯誤 (應為 beatId::groupId): '${choiceKey}'`);
    }
    const [bid, gid] = parts;
    const beat = data.beatsById.get(bid);
    if (!beat) {
      return fail(`run.choices 引用了不存在的 beat: '${bid}'`);
    }
    const targetSlot = (beat.slots ?? []).find((s) => s.id === slotId);
    if (!targetSlot) {
      return fail(`run.choices 引用了 beat '${bid}' 中不存在的 slot '${slotId}'`);
    }
    if (targetSlot.choice_group !== gid) {
      return fail(`run.choices slot '${slotId}' 的 choice_group (${targetSlot.choice_group}) 與鍵 '${gid}' 不一致`);
    }

    // 選擇的槽位必須同步記入 slots_placed
    const selectedSlotKey = `${bid}::${slotId}`;
    if (slotsPlacedMap[selectedSlotKey] !== true) {
      return fail(`run.choices 選取的槽位 '${selectedSlotKey}' 未同步記入 slots_placed`);
    }

    // 同一 choice_group 下的其他槽位不得存在於 slots_placed
    for (const otherSlot of beat.slots ?? []) {
      if (otherSlot.choice_group === gid && otherSlot.id !== slotId) {
        const conflictSlotKey = `${bid}::${otherSlot.id}`;
        if (slotsPlacedMap[conflictSlotKey] === true) {
          return fail(`run.slots_placed 包含了與 choices 互斥的同組槽位: '${conflictSlotKey}'`);
        }
      }
    }
  }

  // 反向：slots_placed 中帶有 choice_group 的槽位必須在 choices 中有對應紀錄且指向自身
  for (const slotKey of Object.keys(slotsPlacedMap)) {
    const [bid, sid] = slotKey.split('::');
    const beat = data.beatsById.get(bid)!;
    const slot = (beat.slots ?? []).find((s) => s.id === sid);
    if (slot && typeof slot.choice_group === 'string' && slot.choice_group.length > 0) {
      const choiceKey = `${bid}::${slot.choice_group}`;
      if (!hasOwn(choicesMap, choiceKey) || choicesMap[choiceKey] !== sid) {
        return fail(`run.slots_placed 中的 choice_group 槽位 '${slotKey}' 與 choices 紀錄不一致`);
      }
    }
  }

  // flags & switches
  if (!isPlainObject(runRaw.flags)) return fail('run.flags 必須為物件');
  for (const fid of Object.keys(runRaw.flags)) {
    if (typeof runRaw.flags[fid] !== 'boolean') {
      return fail(`run.flags['${fid}'] 值必須為布林值`);
    }
  }

  if (!isPlainObject(runRaw.switches)) return fail('run.switches 必須為物件');
  for (const sid of Object.keys(runRaw.switches)) {
    if (typeof runRaw.switches[sid] !== 'boolean') {
      return fail(`run.switches['${sid}'] 值必須為布林值`);
    }
  }

  // switch_progress
  if (!isPlainObject(runRaw.switch_progress)) return fail('run.switch_progress 必須為物件');
  for (const spid of Object.keys(runRaw.switch_progress)) {
    const val = runRaw.switch_progress[spid];
    if (!isStrictInt(val)) {
      return fail(`run.switch_progress['${spid}'] 值必須為整數`);
    }
  }

  // relations
  if (!isPlainObject(runRaw.relations)) return fail('run.relations 必須為物件');
  for (const nid of Object.keys(runRaw.relations)) {
    if (!data.npcsById.has(nid)) {
      return fail(`run.relations 引用了不存在的 NPC: '${nid}'`);
    }
    const val = runRaw.relations[nid];
    if (!isStrictInt(val)) {
      return fail(`run.relations['${nid}'] 值必須為整數`);
    }
  }

  // npc_action_counts
  if (!isPlainObject(runRaw.npc_action_counts)) return fail('run.npc_action_counts 必須為物件');
  for (const nid of Object.keys(runRaw.npc_action_counts)) {
    if (!data.npcsById.has(nid)) {
      return fail(`run.npc_action_counts 引用了不存在的 NPC: '${nid}'`);
    }
    const val = runRaw.npc_action_counts[nid];
    if (!isStrictInt(val) || val < 0) {
      return fail(`run.npc_action_counts['${nid}'] 必須為 >= 0 的整數`);
    }
  }

  // night_location_chosen & night_sleep_pending
  if (typeof runRaw.night_location_chosen !== 'string') {
    return fail('run.night_location_chosen 必須為字串');
  }
  if (runRaw.night_location_chosen.length > 0) {
    const loc = data.locationsById.get(runRaw.night_location_chosen);
    if (!loc || loc.layer !== 'night') {
      return fail(`run.night_location_chosen 引用了非夜間地點: '${runRaw.night_location_chosen}'`);
    }
  }
  if (typeof runRaw.night_sleep_pending !== 'boolean') {
    return fail('run.night_sleep_pending 必須為布林值');
  }

  // counts
  if (!isStrictInt(runRaw.indulgence_count) || runRaw.indulgence_count < 0) {
    return fail('run.indulgence_count 必須為 >= 0 的整數');
  }
  if (!isStrictInt(runRaw.madness_cards_cleared) || runRaw.madness_cards_cleared < 0) {
    return fail('run.madness_cards_cleared 必須為 >= 0 的整數');
  }

  // forced_pending
  if (!Array.isArray(runRaw.forced_pending)) {
    return fail('run.forced_pending 必須為陣列');
  }
  const pendingDebts = new Set<string>();
  for (let i = 0; i < runRaw.forced_pending.length; i += 1) {
    const item = runRaw.forced_pending[i];
    if (typeof item !== 'string' || item.length === 0) {
      return fail(`run.forced_pending[${i}] 必須為非空字串`);
    }
    const match = /^madness#(\d+)$/.exec(item);
    if (!match) {
      return fail(`run.forced_pending[${i}] 必須為合法發狂卡實例 ID (如 madness#N): '${item}'`);
    }
    const instNum = Number.parseInt(match[1], 10);
    if (instNum < 1 || instNum > runRaw._madness_counter) {
      return fail(`run.forced_pending[${i}] 序號 ${instNum} 超過 _madness_counter (${runRaw._madness_counter})`);
    }
    if (pendingDebts.has(item)) {
      return fail(`run.forced_pending 含有重複項目: '${item}'`);
    }
    pendingDebts.add(item);

    // 若該發狂卡仍在手牌中，其倒數時計必須為 0 (已歸零才入列)
    if (runRaw.hand.includes(item)) {
      if (runRaw.madness_clock[item] !== 0) {
        return fail(`run.forced_pending 中的持有中發狂卡 '${item}' 其 madness_clock 必須為 0`);
      }
    }
  }

  // delegates_used_today
  if (!isPlainObject(runRaw.delegates_used_today)) {
    return fail('run.delegates_used_today 必須為物件');
  }
  for (const cid of Object.keys(runRaw.delegates_used_today)) {
    if (runRaw.delegates_used_today[cid] !== true) {
      return fail(`run.delegates_used_today['${cid}'] 值必須為 true`);
    }
    const card = data.cardsById.get(cid);
    if (!card || card.type !== 'person') {
      return fail(`run.delegates_used_today 引用了非人物卡: '${cid}'`);
    }
  }

  // pending_delegation_reports
  if (!Array.isArray(runRaw.pending_delegation_reports)) {
    return fail('run.pending_delegation_reports 必須為陣列');
  }
  const pendingReportPointers = new Set<string>();
  for (let i = 0; i < runRaw.pending_delegation_reports.length; i += 1) {
    const rep = runRaw.pending_delegation_reports[i];
    if (!isPlainObject(rep)) {
      return fail(`run.pending_delegation_reports[${i}] 必須為物件`);
    }
    const repKeys = Object.keys(rep);
    if (
      repKeys.length !== 4 ||
      !hasOwn(rep, 'due_day') ||
      !hasOwn(rep, 'beat_id') ||
      !hasOwn(rep, 'slot_id') ||
      !hasOwn(rep, 'person_id')
    ) {
      return fail(`run.pending_delegation_reports[${i}] 欄位不完整`);
    }
    if (!isStrictInt(rep.due_day) || rep.due_day < 1 || rep.due_day > LAST_DAY) {
      return fail(`run.pending_delegation_reports[${i}].due_day 必須為 1 至 ${LAST_DAY} 的整數`);
    }
    if (typeof rep.beat_id !== 'string' || !data.beatsById.has(rep.beat_id)) {
      return fail(`run.pending_delegation_reports[${i}].beat_id 引用了不存在的 beat: '${String(rep.beat_id)}'`);
    }
    const beat = data.beatsById.get(rep.beat_id)!;
    if (typeof rep.slot_id !== 'string') {
      return fail(`run.pending_delegation_reports[${i}].slot_id 必須為字串`);
    }
    const slot = (beat.slots ?? []).find((s) => s.id === rep.slot_id);
    if (!slot) {
      return fail(`run.pending_delegation_reports[${i}].slot_id 引用了不存在的 slot: '${rep.slot_id}'`);
    }

    const del = slot.delegation;
    if (
      !del ||
      del.result_timing !== 'next_morning' ||
      !del.report ||
      typeof del.report !== 'object' ||
      Array.isArray(del.report) ||
      Object.keys(del.report).length === 0
    ) {
      return fail(`run.pending_delegation_reports[${i}] 槽位 '${rep.slot_id}' 非合法的 next_morning 委託槽`);
    }

    if (typeof rep.person_id !== 'string') {
      return fail(`run.pending_delegation_reports[${i}].person_id 必須為字串`);
    }
    const personCard = data.cardsById.get(rep.person_id);
    if (!personCard || personCard.type !== 'person') {
      return fail(`run.pending_delegation_reports[${i}].person_id 引用了非人物卡: '${rep.person_id}'`);
    }
    const accepts = slot.accepts ?? [];
    if (!accepts.includes(rep.person_id) && !accepts.includes(cardBaseId(rep.person_id))) {
      return fail(`run.pending_delegation_reports[${i}] 委託槽 '${rep.slot_id}' 不接受人物卡 '${rep.person_id}'`);
    }

    const actionPointer = `${rep.beat_id}::${rep.slot_id}`;
    if (pendingReportPointers.has(actionPointer)) {
      return fail(`run.pending_delegation_reports 重複了相同的委託行動: '${actionPointer}'`);
    }
    pendingReportPointers.add(actionPointer);
  }

  // active_encounter
  if (!isPlainObject(runRaw.active_encounter)) {
    return fail('run.active_encounter 必須為物件');
  }
  const encKeys = Object.keys(runRaw.active_encounter);
  if (flow.mode !== 'run') {
    if (encKeys.length > 0) {
      return fail(`flow.mode 為 ${flow.mode} 時 active_encounter 必須為空物件`);
    }
  } else if (encKeys.length > 0) {
    const requiredEncKeys = [
      'beat_id',
      'stage',
      'round_id',
      'blocked_slots',
      'attempted_card_ids',
      'visited_round_ids',
    ];
    if (encKeys.length !== requiredEncKeys.length) {
      return fail(`run.active_encounter 欄位數量不符 (期望 ${requiredEncKeys.length} 欄，實際 ${encKeys.length} 欄)`);
    }
    for (const ek of requiredEncKeys) {
      if (!hasOwn(runRaw.active_encounter, ek)) {
        return fail(`run.active_encounter 缺少必要欄位: '${ek}'`);
      }
    }
    const enc = runRaw.active_encounter;
    if (typeof enc.beat_id !== 'string' || !data.beatsById.has(enc.beat_id)) {
      return fail(`run.active_encounter.beat_id 引用了不存在的 beat: '${String(enc.beat_id)}'`);
    }
    const beat = data.beatsById.get(enc.beat_id)!;
    if (!beat.encounter) {
      return fail(`run.active_encounter beat '${enc.beat_id}' 無遭遇定義`);
    }
    if (enc.stage !== 'intro' && enc.stage !== 'round') {
      return fail(`run.active_encounter.stage 必須為 intro 或 round: '${String(enc.stage)}'`);
    }
    if (typeof enc.round_id !== 'string') {
      return fail('run.active_encounter.round_id 必須為字串');
    }
    if (!isStrictInt(enc.blocked_slots) || enc.blocked_slots < 0) {
      return fail('run.active_encounter.blocked_slots 必須為 >= 0 的整數');
    }
    if (!Array.isArray(enc.attempted_card_ids)) {
      return fail('run.active_encounter.attempted_card_ids 必須為陣列');
    }
    if (!Array.isArray(enc.visited_round_ids)) {
      return fail('run.active_encounter.visited_round_ids 必須為陣列');
    }

    if (enc.stage === 'intro') {
      if (enc.round_id !== '') {
        return fail(`run.active_encounter intro 階段 round_id 必須為空字串: '${enc.round_id}'`);
      }
      if (enc.blocked_slots !== 0) {
        return fail(`run.active_encounter intro 階段 blocked_slots 必須為 0: ${enc.blocked_slots}`);
      }
      if (enc.visited_round_ids.length !== 0) {
        return fail('run.active_encounter intro 階段 visited_round_ids 必須為空陣列');
      }
      if (enc.attempted_card_ids.length !== 0) {
        return fail('run.active_encounter intro 階段 attempted_card_ids 必須為空陣列');
      }
    } else {
      const hasRound = beat.encounter.rounds.some((r) => r.id === enc.round_id);
      if (!hasRound) {
        return fail(`run.active_encounter.round_id 引用了不存在的回合: '${enc.round_id}'`);
      }

      const visitedSet = new Set<string>();
      for (let i = 0; i < enc.visited_round_ids.length; i += 1) {
        const rid = enc.visited_round_ids[i];
        if (
          typeof rid !== 'string' ||
          !beat.encounter.rounds.some((r) => r.id === rid)
        ) {
          return fail(`run.active_encounter.visited_round_ids[${i}] 引用了不存在的回合: '${String(rid)}'`);
        }
        if (visitedSet.has(rid)) {
          return fail(`run.active_encounter.visited_round_ids 含有重複回合: '${rid}'`);
        }
        visitedSet.add(rid);
      }
      if (!visitedSet.has(enc.round_id)) {
        return fail(`run.active_encounter.visited_round_ids 必須包含當前回合 '${enc.round_id}'`);
      }

      const attemptedSet = new Set<string>();
      for (let i = 0; i < enc.attempted_card_ids.length; i += 1) {
        const cid = enc.attempted_card_ids[i];
        if (typeof cid !== 'string' || !data.cardsById.has(cid)) {
          return fail(`run.active_encounter.attempted_card_ids[${i}] 引用了無效卡片: '${String(cid)}'`);
        }
        if (cid !== cardBaseId(cid)) {
          return fail(`run.active_encounter.attempted_card_ids[${i}] 必須為正規 base ID: '${cid}'`);
        }
        const card = data.cardsById.get(cid)!;
        if (card.type === 'madness') {
          return fail(`run.active_encounter.attempted_card_ids[${i}] 不得包含發狂卡: '${cid}'`);
        }
        if (attemptedSet.has(cid)) {
          return fail(`run.active_encounter.attempted_card_ids 含有重複項目: '${cid}'`);
        }
        attemptedSet.add(cid);
      }
    }
  }

  return valid();
}
