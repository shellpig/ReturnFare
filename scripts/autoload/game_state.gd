extends Node

## GameState autoload: 全部 runtime 狀態的唯一容器（規格書第一節）。
## P1-A：時間群與序列化骨架。
## P1-B：手牌群（hand / knowledge / madness_clock）。
## P1-C：beat 事件群（beats_entered / slots_placed / enter_beat）。
## P1-D：旗標／開關／關係群、放置與效果結算（try_place）、行動格消耗。

const CHAPTER_START_DAYS := [1, 16, 33]
const LAST_DAY := 45
const PHASES := ["morning", "afternoon", "evening", "night"]
const ACTION_PHASES := ["morning", "afternoon"]

# --- 時間群（run 層）---
var day: int = 1
var phase: String = "morning"

# --- 手牌群 ---
var hand: Array[String] = []          # 佔格卡 id，有序；主角卡恆在 index 0（run 層）
var knowledge: Dictionary = {}        # id -> true（Set；slotless 卡；meta 層，不隨輪重置）
var madness_clock: Dictionary = {}    # 實例 id -> 剩餘天數（P1 只建結構，P2 才走錶；run 層）
var _madness_counter: int = 0         # 實例編號計數器（run 層）

# --- Beat 事件群（P1-C, run 層）---
var beats_entered: Dictionary = {}    # beat_id -> true（一次性 on_enter 追蹤）
var slots_placed: Dictionary = {}     # "beat_id::slot_id" -> true（P1-D 填入，P1-C 保留空結構）
var choices: Dictionary = {}          # "beat_id::group_id" -> slot_id（P1-E 互斥選擇記錄，run 層）

# --- 旗標／開關／關係群（P1-D, run 層）---
var flags: Dictionary = {}            # name -> bool
var switches: Dictionary = {}         # id -> true
var switch_progress: Dictionary = {}  # id -> int（累計型開關）
var relations: Dictionary = {}        # npc -> int（單軸整數暫行案，規格書第十二節）

# --- 其他群 ---
var action_spent: bool = false                 # 當前行動格是否已放過主角卡（run 層）
var npc_action_counts: Dictionary = {}         # npc_id -> 本輪投入的主角行動數（run 層，規格書第十二節）

signal phase_changed(day: int, phase: String)
signal day_changed(day: int)
signal chapter_changed(chapter: int)
signal run_ended(ending_id: String)
signal hand_changed
signal knowledge_changed


# ── 時段狀態機 ──────────────────────────────────────────────────────────────

func chapter() -> int:
	for i in range(CHAPTER_START_DAYS.size() - 1, -1, -1):
		if day >= CHAPTER_START_DAYS[i]:
			return i + 1
	return 1


func advance_phase() -> void:
	var prev_ch := chapter()

	# 第 45 天特殊路徑：afternoon → evening（結局 coda）→ end_run 回第 1 天 morning，不進 night
	if day == LAST_DAY and phase == "afternoon":
		phase = "evening"
		action_spent = false
		phase_changed.emit(day, phase)
		return

	if day == LAST_DAY and phase == "evening":
		end_run("ending_default")
		return

	# 一般推進
	var idx := PHASES.find(phase)
	if idx < PHASES.size() - 1:
		phase = PHASES[idx + 1]
	else:
		# night → 次日 morning
		day += 1
		phase = PHASES[0]
		day_changed.emit(day)

	action_spent = false
	phase_changed.emit(day, phase)

	var new_ch := chapter()
	if new_ch != prev_ch:
		chapter_changed.emit(new_ch)


## 輪結束結算與迴圈重置（規格書第十六節、P1-F、B-02）。
## 順序固定：發射 run_ended -> meta 層保留 -> run 層重置 -> 回第 1 天 morning。
func end_run(ending_id: String = "ending_default") -> void:
	run_ended.emit(ending_id)

	day = 1
	phase = PHASES[0]
	action_spent = false
	hand.clear()
	hand.append("protagonist")
	flags.clear()
	switches.clear()
	switch_progress.clear()
	relations.clear()
	slots_placed.clear()
	choices.clear()
	beats_entered.clear()
	npc_action_counts.clear()
	madness_clock.clear()
	_madness_counter = 0

	day_changed.emit(day)
	phase_changed.emit(day, phase)
	chapter_changed.emit(chapter())
	hand_changed.emit()


## 晚間演出規則層唯一入口（UI、走查腳本、測試共用，規格書第十一節、K-26）。
## 依序：
## 1. 依陣列順序結算當日 evening fixed beat 之 play_beat()
## 2. 掃描當日成立之殘響（echo.day == day）並收集文字
## 回傳全部要播放的文字行（PackedStringArray）。
func play_evening() -> PackedStringArray:
	var lines := PackedStringArray()
	if Data == null or Data.loader == null:
		return lines

	var cur_day: int = day

	# 1. 當日 evening fixed beats（依陣列順序，保證連鎖條件如 d27 正確生效）
	for b in Data.loader.beats_at(cur_day, "evening"):
		if not b.get("fixed", false):
			continue
		if ConditionEval.eval(b.get("condition"), self) and ConditionEval.eval(b.get("requires"), self):
			var beat_lines := play_beat(str(b.get("id", "")))
			lines.append_array(beat_lines)

	# 2. 當日殘響
	for b in Data.loader.beats:
		var echo_raw: Variant = b.get("echo")
		if not echo_raw is Dictionary:
			continue
		var echo := echo_raw as Dictionary
		if int(echo.get("day", -1)) != cur_day:
			continue
		if ConditionEval.eval(echo.get("condition"), self) and ConditionEval.eval(echo.get("requires"), self):
			var text: String = str(echo.get("text", "")).strip_edges()
			if not text.is_empty():
				lines.append(text)

	return lines


## 夜間定日 fixed beat 強制播之唯一入口（UI、走查共用，規格書第九節第 1 步、K-26）。
func play_night_fixed() -> PackedStringArray:
	var lines := PackedStringArray()
	if Data == null or Data.loader == null:
		return lines

	var cur_day: int = day
	for b in Data.loader.beats_at(cur_day, "night"):
		if not b.get("fixed", false):
			continue
		if ConditionEval.eval(b.get("condition"), self) and ConditionEval.eval(b.get("requires"), self):
			var beat_lines := play_beat(str(b.get("id", "")))
			lines.append_array(beat_lines)

	return lines


## 直接睡＝解析旅館（sanquan）的當夜定日 beat（規格書第九節、P1-F）。
func sleep_night() -> PackedStringArray:
	var cur_day: int = day
	for b in Data.loader.beats:
		if str(b.get("location", "")) != "sanquan":
			continue
		var w: Variant = b.get("when")
		if not w is Dictionary:
			continue
		var wd := w as Dictionary
		if int(wd.get("day", -1)) != cur_day or str(wd.get("phase", "")) != "night":
			continue
		if bool(b.get("fixed", false)):
			continue
		if ConditionEval.eval(b.get("condition"), self) and ConditionEval.eval(b.get("requires"), self):
			return play_beat(str(b.get("id", "")))
	return PackedStringArray()


## 檢查 beat 在當前天與時段是否屬於合法範圍（K-18）。
func _is_beat_time_valid(beat: Dictionary) -> bool:
	var cur_day: int = day
	var cur_phase: String = phase
	var cur_ch: int = chapter()
	if cur_phase != "night":
		var w: Variant = beat.get("when")
		if not w is Dictionary:
			return false
		var wd := w as Dictionary
		return int(wd.get("day", -1)) == cur_day and str(wd.get("phase", "")) == cur_phase
	else:
		# Night phase
		var w: Variant = beat.get("when")
		if w is Dictionary:
			var wd := w as Dictionary
			return int(wd.get("day", -1)) == cur_day and str(wd.get("phase", "")) == "night"
		var ch: Variant = beat.get("chapter")
		if ch != null:
			return int(ch) <= cur_ch
		# Additional night beat (no when, no chapter)
		return true


# ── 手牌操作 ────────────────────────────────────────────────────────────────

## 取得卡片（按型別分流：slotless → knowledge；madness → 新實例進 hand；其餘 unique）。
func gain_card(id: String) -> void:
	var card: Dictionary = Data.loader.cards.get(id, {})
	if card.is_empty():
		push_error("gain_card: unknown card id '%s'" % id)
		return

	if card.get("slotless", false):
		# knowledge 類：不佔格，進知識集合（冪等）
		if knowledge.has(id):
			return
		knowledge[id] = true
		knowledge_changed.emit()
		return

	if card.get("type", "") == "madness":
		# 唯一的多實例卡
		_madness_counter += 1
		var inst := id + "#" + str(_madness_counter)
		hand.append(inst)
		madness_clock[inst] = int(Data.tuning("madness_countdown_days"))
		_check_hand_overflow(id)
		hand_changed.emit()
		return

	# 其餘卡：unique（已持有 = no-op，含知識集合）
	if has_card(id):
		return
	hand.append(id)
	_check_hand_overflow(id)
	hand_changed.emit()


func _check_hand_overflow(card_id: String) -> void:
	var max_hand: int = int(Data.tuning("hand_size"))
	if hand.size() > max_hand:
		push_warning("gain_card: hand is full (%d/%d), card '%s' gained anyway" % [hand.size(), max_hand, card_id])


## 丟棄卡片（can作用於 hand 與 knowledge；丟主角卡 = push_error）。
func lose_card(id: String) -> void:
	var base_id := _card_base_id(id)
	var card: Dictionary = Data.loader.cards.get(base_id, {})
	if card.get("type", "") == "protagonist":
		push_error("lose_card: cannot lose protagonist card (data bug)")
		return

	var idx := hand.find(id)
	if idx >= 0:
		hand.remove_at(idx)
		if card.get("type", "") == "madness":
			madness_clock.erase(id)
		hand_changed.emit()
		return

	if knowledge.has(id):
		knowledge.erase(id)
		knowledge_changed.emit()
		return

	push_error("lose_card: card '%s' not found in hand or knowledge" % id)


## 持有檢查：hand ∪ knowledge（備用區不算）。
func has_card(id: String) -> bool:
	return hand.has(id) or knowledge.has(id)


func has_knowledge(id: String) -> bool:
	return knowledge.has(id)


## 手牌佔格數（hand 裡的每個元素都佔一格；knowledge 不算）。
func hand_slots_used() -> int:
	return hand.size()


# ── Beat 呈現 ───────────────────────────────────────────────────────────────

## Beat 演出的規則層入口（P1-G）。
## 一次性判定：beats_entered 記錄是否第一次。
## on_enter 效果走正式 EffectApply（規格書第十四節）。
## 回傳要播的文字行（PackedStringArray）。
func play_beat(beat_id: String) -> PackedStringArray:
	var beat: Dictionary = Data.loader.beats_by_id.get(beat_id, {})
	if beat.is_empty():
		push_error("play_beat: unknown beat id '%s'" % beat_id)
		return PackedStringArray()

	var is_first := not beats_entered.has(beat_id)
	beats_entered[beat_id] = true

	var lines := PackedStringArray()

	# beat 主文（每次呈現都顯示）
	var text: Variant = beat.get("text")
	if text is String and not (text as String).is_empty():
		lines.append(text as String)

	# on_enter 效果（只在第一次結算）
	if is_first:
		lines.append_array(EffectApply.apply(beat.get("on_enter"), self))

	return lines


## 面板求值的規則層入口（P1-G）。純計算，不結算 on_enter、不改 GameState。
func build_panel(location_id: String) -> Dictionary:
	return PanelBuilder.build(location_id, self, Data)


## 右鍵預覽的規則層入口（P1-G）。純查詢，不結算任何效果。
## 回傳 { "cards": Array[String], "reason": String }。
func preview_slot(beat_id: String, slot_id: String) -> Dictionary:
	var beat: Dictionary = Data.loader.beats_by_id.get(beat_id, {})
	if beat.is_empty():
		return { "cards": [], "reason": _REASON_UNKNOWN_BEAT }
	var slot: Dictionary = _find_slot(beat, slot_id)
	if slot.is_empty():
		return { "cards": [], "reason": _REASON_UNKNOWN_SLOT }

	var state_result := _check_slot_state(beat, slot)
	if not state_result.get("ok", false):
		return {
			"cards": [],
			"reason": _result_reason(state_result),
		}

	var cards_result := placeable_cards(beat_id, slot_id)
	if not cards_result.is_empty():
		return { "cards": cards_result, "reason": "" }

	# OPEN 槽沒有可用卡時仍維持唯讀空清單；若是 action_spent 等狀態，
	# 用同一個規則檢查取得理由，避免預覽與實放分岔。
	var candidates := _held_cards()
	for card_id: String in candidates:
		var check_result := _check_place(card_id, beat, slot)
		if not check_result.get("ok", false):
			var reason := _result_reason(check_result)
			if not reason.is_empty() and reason != _REASON_NOT_HELD:
				return { "cards": [], "reason": reason }
	return { "cards": [], "reason": "" }


# ── 放置與效果結算（P1-D）───────────────────────────────────────────────────

const _REASON_UNKNOWN_BEAT := "unknown_beat"
const _REASON_UNKNOWN_SLOT := "unknown_slot"
const _REASON_NOT_HELD := "not_held"
const _REASON_HIDDEN := "hidden"
const _REASON_LOCKED := "locked"
const _REASON_RESOLVED := "resolved"
const _REASON_NOT_ACCEPTED := "not_accepted"
const _REASON_ACTION_SPENT := "action_spent"
const _REASON_LOCKED_FALLBACK := "（條件不足）"


func set_flag(name: String, value: bool = true) -> void:
	flags[name] = value


func open_switch(id: String) -> void:
	switches[id] = true


func add_switch_progress(id: String, n: int) -> void:
	switch_progress[id] = int(switch_progress.get(id, 0)) + n


func add_relation(npc: String, delta: int) -> void:
	relations[npc] = int(relations.get(npc, 0)) + delta


## `relation_at_least` 求值：讀 `data/relation_scale.json`（規格書第十二節）。
func relation_at_least(npc: String, state: String) -> bool:
	var scale: Dictionary = Data.loader.relation_scale
	if not scale.has(state):
		push_error("relation_at_least: unknown state '%s' (data/relation_scale.json)" % state)
		return false
	return int(relations.get(npc, 0)) >= int(scale[state])


## 標記當前行動格已用（規格書第六節）。
func consume_action() -> void:
	action_spent = true


func _find_slot(beat: Dictionary, slot_id: String) -> Dictionary:
	for slot: Dictionary in beat.get("slots", []) as Array:
		if str(slot.get("id", "")) == slot_id:
			return slot
	return {}


func _held_cards() -> Array[String]:
	var result: Array[String] = []
	for card_id: String in hand:
		result.append(card_id)
	for knowledge_id: Variant in (knowledge as Dictionary).keys():
		result.append(str(knowledge_id))
	return result


## 只檢查槽當前三態與時間，不檢查傳入卡片。
## _check_place() 與 preview_slot() 共用這段，確保灰槽理由一致。
func _check_slot_state(beat: Dictionary, slot: Dictionary) -> Dictionary:
	var beat_id := str(beat.get("id", ""))
	var slot_id := str(slot.get("id", ""))
	if not _is_beat_time_valid(beat):
		return { "ok": false, "reason_code": _REASON_HIDDEN, "reason_text": "" }
	if not ConditionEval.eval(beat.get("condition"), self):
		return { "ok": false, "reason_code": _REASON_HIDDEN, "reason_text": "" }
	if not ConditionEval.eval(beat.get("requires"), self):
		return {
			"ok": false,
			"reason_code": _REASON_LOCKED,
			"reason_text": str(beat.get("reject_reason", _REASON_LOCKED_FALLBACK)),
		}
	if not ConditionEval.eval(slot.get("condition"), self):
		return { "ok": false, "reason_code": _REASON_HIDDEN, "reason_text": "" }
	var slot_key := beat_id + "::" + slot_id
	if slots_placed.has(slot_key):
		return { "ok": false, "reason_code": _REASON_RESOLVED, "reason_text": "" }
	var choice_group: String = str(slot.get("choice_group", ""))
	if not choice_group.is_empty() and choices.has(beat_id + "::" + choice_group):
		return { "ok": false, "reason_code": _REASON_RESOLVED, "reason_text": "" }
	if not ConditionEval.eval(slot.get("requires"), self):
		return {
			"ok": false,
			"reason_code": _REASON_LOCKED,
			"reason_text": str(slot.get("reject_reason", _REASON_LOCKED_FALLBACK)),
		}
	return { "ok": true, "reason_code": "", "reason_text": "" }


## 放置前共用判斷。try_place() 與 preview_slot() 必須走同一條規則。
func _check_place(card_id: String, beat: Dictionary, slot: Dictionary) -> Dictionary:
	if card_id.is_empty() or not has_card(card_id):
		return { "ok": false, "reason_code": _REASON_NOT_HELD, "reason_text": "" }
	var state_result := _check_slot_state(beat, slot)
	if not state_result.get("ok", false):
		return state_result

	var base_id := _card_base_id(card_id)
	var card: Dictionary = Data.loader.cards.get(base_id, {})
	var accepts: Array = slot.get("accepts", []) as Array
	var card_type := str(card.get("type", ""))
	if not (accepts.has(base_id) or accepts.has(card_type)):
		return { "ok": false, "reason_code": _REASON_NOT_ACCEPTED, "reason_text": "" }

	var is_protagonist := card_type == "protagonist"
	if is_protagonist and ACTION_PHASES.has(phase) and action_spent:
		return { "ok": false, "reason_code": _REASON_ACTION_SPENT, "reason_text": "" }
	return { "ok": true, "reason_code": "", "reason_text": "" }


func _result_reason(result: Dictionary) -> String:
	var reason_text := str(result.get("reason_text", ""))
	if not reason_text.is_empty():
		return reason_text
	return str(result.get("reason_code", ""))


## 當前時段是否仍有任一動作可做（合法卡放置或未結算選擇題）。純查詢，不推進時段。
func has_any_legal_action() -> bool:
	var locations := PanelBuilder.available_locations(self, Data)
	for location_id: String in locations:
		var view := build_panel(location_id)
		for beat_view: Dictionary in view.get("beats", []) as Array:
			if int(beat_view.get("tri", -1)) != PanelBuilder.TriState.OPEN:
				continue
			var beat_id := str((beat_view["beat"] as Dictionary).get("id", ""))
			for slot_view: Dictionary in beat_view.get("slots", []) as Array:
				if int(slot_view.get("tri", -1)) != PanelBuilder.TriState.OPEN:
					continue
				if bool(slot_view.get("is_choice", false)):
					return true
				var slot_id := str((slot_view["slot"] as Dictionary).get("id", ""))
				if not placeable_cards(beat_id, slot_id).is_empty():
					return true
	return false


## 取得某個槽當前可放置的手牌或知識卡 id 列表（UI 專用查詢，規則層統一計算）。
## 與 try_place() 共用 _check_place()，不在 UI 重複判斷。
func placeable_cards(beat_id: String, slot_id: String) -> Array[String]:
	var result: Array[String] = []
	var beat: Dictionary = Data.loader.beats_by_id.get(beat_id, {})
	if beat.is_empty():
		return result
	var slot := _find_slot(beat, slot_id)
	if slot.is_empty():
		return result
	for card_id: String in _held_cards():
		if _check_place(card_id, beat, slot).get("ok", false):
			result.append(card_id)

	return result


## 選擇題選定的唯一入口（UI 與 headless 走查共用，規格書 P1-E、開發設計方針 P1-E）。
## 原子操作：驗證未結算 → 三態 OPEN →（若帶卡）持有與 accepts 檢查 → on_place 結算 →
## 同步寫入 choices[beat_id::group_id] 與 slots_placed[beat_id::slot_id]。
## 不吃卡、不吃行動格（SCHEMA 規範）。
## 重複呼叫為 no-op，回傳 { ok: false, reason_code: "resolved" }。
## 回傳：{ "ok": bool, "reason_code": String, "reason_text": String, "lines": PackedStringArray }
func choose(beat_id: String, group_id: String, slot_id: String, card_id: String = "") -> Dictionary:
	var choice_key := beat_id + "::" + group_id
	if choices.has(choice_key):
		return { "ok": false, "reason_code": _REASON_RESOLVED, "reason_text": "", "lines": PackedStringArray() }

	var beat: Dictionary = Data.loader.beats_by_id.get(beat_id, {})
	if beat.is_empty():
		return { "ok": false, "reason_code": _REASON_UNKNOWN_BEAT, "reason_text": "", "lines": PackedStringArray() }

	var slot: Dictionary = _find_slot(beat, slot_id)
	if str(slot.get("choice_group", "")) != group_id:
		slot = {}
	if slot.is_empty():
		return { "ok": false, "reason_code": _REASON_UNKNOWN_SLOT, "reason_text": "", "lines": PackedStringArray() }

	var state_result := _check_slot_state(beat, slot)
	if not state_result.get("ok", false):
		return {
			"ok": false,
			"reason_code": str(state_result.get("reason_code", "")),
			"reason_text": str(state_result.get("reason_text", "")),
			"lines": PackedStringArray(),
		}

	# 帶卡檢查（若傳入 card_id）
	if not card_id.is_empty():
		var place_result := _check_place(card_id, beat, slot)
		if not place_result.get("ok", false):
			return {
				"ok": false,
				"reason_code": str(place_result.get("reason_code", "")),
				"reason_text": str(place_result.get("reason_text", "")),
				"lines": PackedStringArray(),
			}

	# 效果結算（原子操作）
	var lines: PackedStringArray = EffectApply.apply(slot.get("on_place", {}), self)
	var slot_key := beat_id + "::" + slot_id
	choices[choice_key] = slot_id
	slots_placed[slot_key] = true

	return { "ok": true, "reason_code": "", "reason_text": "", "lines": lines }


## 放卡的唯一入口（UI 與 headless 走查共用；UI 內不做任何判斷）。
## 放置合法性四步檢查，順序固定（規格書第六節）：
## ①持有 → ②三態 OPEN（beat 與槽兩級 condition/requires 都要過，含一次性未放過）→
## ③accepts → ④action_spent（僅行動格內的主角卡）。
## 若該槽帶 choice_group，直接轉導 choose() 保證規則層單一入口（P1-E）。
## 任一步不過 → { ok=false, reason_code, reason_text, lines=[] }，GameState 零變化。
## 回傳：{ "ok": bool, "reason_code": String, "reason_text": String, "lines": PackedStringArray }
func try_place(card_id: String, beat_id: String, slot_id: String) -> Dictionary:
	# K-17: 空卡 id 走 try_place 直接擋下，不轉導 choose
	if card_id.is_empty():
		return { "ok": false, "reason_code": _REASON_NOT_HELD, "reason_text": "", "lines": PackedStringArray() }

	var beat: Dictionary = Data.loader.beats_by_id.get(beat_id, {})
	if beat.is_empty():
		return { "ok": false, "reason_code": _REASON_UNKNOWN_BEAT, "reason_text": "", "lines": PackedStringArray() }

	var slot := _find_slot(beat, slot_id)
	if slot.is_empty():
		return { "ok": false, "reason_code": _REASON_UNKNOWN_SLOT, "reason_text": "", "lines": PackedStringArray() }

	var choice_group: Variant = slot.get("choice_group")
	if choice_group != null and not str(choice_group).is_empty():
		return choose(beat_id, str(choice_group), slot_id, card_id)

	var check_result := _check_place(card_id, beat, slot)
	if not check_result.get("ok", false):
		return {
			"ok": false,
			"reason_code": str(check_result.get("reason_code", "")),
			"reason_text": str(check_result.get("reason_text", "")),
			"lines": PackedStringArray(),
		}

	var base_id := _card_base_id(card_id)
	var card: Dictionary = Data.loader.cards.get(base_id, {})
	var slot_key := beat_id + "::" + slot_id
	var card_type := str(card.get("type", ""))
	var is_protagonist := card_type == "protagonist"
	var in_action_phase := ACTION_PHASES.has(phase)

	# 全過 → 效果結算（原子操作：全部套完才重求值）。
	var lines: PackedStringArray = EffectApply.apply(slot.get("on_place", {}), self)
	slots_placed[slot_key] = true

	if is_protagonist and in_action_phase:
		consume_action()
		var attn: Variant = slot.get("attention_npc")
		if attn != null:
			var npc_id := str(attn)
			npc_action_counts[npc_id] = int(npc_action_counts.get(npc_id, 0)) + 1

	return { "ok": true, "reason_code": "", "reason_text": "", "lines": lines }


# ── 序列化 ──────────────────────────────────────────────────────────────────

func serialize() -> Dictionary:
	return {
		"run": {
			"day": day,
			"phase": phase,
			"action_spent": action_spent,
			"hand": hand.duplicate(),
			"madness_clock": madness_clock.duplicate(),
			"_madness_counter": _madness_counter,
			"beats_entered": beats_entered.duplicate(),
			"slots_placed": slots_placed.duplicate(),
			"choices": choices.duplicate(),
			"flags": flags.duplicate(),
			"switches": switches.duplicate(),
			"switch_progress": switch_progress.duplicate(),
			"relations": relations.duplicate(),
			"npc_action_counts": npc_action_counts.duplicate(),
		},
		"meta": {
			"knowledge": knowledge.duplicate(),
		}
	}


func deserialize(d: Dictionary) -> void:
	var run: Dictionary = d.get("run", {})
	day = int(run.get("day", 1))
	phase = str(run.get("phase", "morning"))
	action_spent = bool(run.get("action_spent", false))
	hand.clear()
	for item in run.get("hand", []):
		hand.append(str(item))
	madness_clock = run.get("madness_clock", {}).duplicate()
	_madness_counter = run.get("_madness_counter", 0)
	beats_entered = run.get("beats_entered", {}).duplicate()
	slots_placed = run.get("slots_placed", {}).duplicate()
	choices = run.get("choices", {}).duplicate()
	flags = run.get("flags", {}).duplicate()
	switches = run.get("switches", {}).duplicate()
	switch_progress = run.get("switch_progress", {}).duplicate()
	relations = run.get("relations", {}).duplicate()
	npc_action_counts = run.get("npc_action_counts", {}).duplicate()

	var meta: Dictionary = d.get("meta", {})
	knowledge = meta.get("knowledge", {}).duplicate()


# ── 內部工具 ─────────────────────────────────────────────────────────────────

func _card_base_id(id: String) -> String:
	var hash_idx := id.rfind("#")
	if hash_idx >= 0:
		return id.substr(0, hash_idx)
	return id
