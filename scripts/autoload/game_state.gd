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

	# 第 45 天特殊路徑：afternoon → evening（結局 coda）→ run_ended，不進 night
	if day == LAST_DAY and phase == "afternoon":
		phase = "evening"
		action_spent = false
		phase_changed.emit(day, phase)
		return

	if day == LAST_DAY and phase == "evening":
		run_ended.emit("stub")
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

## Beat 呈現的唯一入口（規格書第四節）。
## 一次性判定：beats_entered 記錄是否第一次。
## on_enter 效果走正式 EffectApply（規格書第十四節）。
## 回傳要播的文字行（PackedStringArray）。
func enter_beat(beat_id: String) -> PackedStringArray:
	var beat: Dictionary = Data.loader.beats_by_id.get(beat_id, {})
	if beat.is_empty():
		push_error("enter_beat: unknown beat id '%s'" % beat_id)
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


## 開啟地點面板的規則層入口（UI 與走查共用，規格書第四、五節）。
## 依序：
## 1. 找出該地點在當前 day 與 phase 符合條件的所有 beat
## 2. 若 beat 判斷為 OPEN（condition 與 requires 皆成立），呼叫 enter_beat() 結算 on_enter 並記錄 beats_entered
## 3. 在所有 on_enter 結算完成後，呼叫 PanelBuilder.build() 取得最新 view model 並回傳
func open_panel(location_id: String) -> Dictionary:
	var loader: DataLoader = Data.loader
	if loader == null:
		return { "beats": [] }

	var cur_day: int = day
	var cur_phase: String = phase
	var lines_by_beat: Dictionary = {}

	# 連鎖結算：處理可能由前面 on_enter 觸發後續 beat 變 OPEN 的情況
	var changed := true
	while changed:
		changed = false
		for b in loader.beats:
			if str(b.get("location", "")) != location_id:
				continue
			if not b.has("when"):
				continue
			var w: Dictionary = b.get("when", {}) as Dictionary
			if int(w.get("day", -1)) != cur_day or str(w.get("phase", "")) != cur_phase:
				continue
			var beat_id: String = str(b.get("id", ""))
			if beats_entered.has(beat_id):
				continue
			if ConditionEval.eval(b.get("condition"), self) and ConditionEval.eval(b.get("requires"), self):
				var res_lines := enter_beat(beat_id)
				lines_by_beat[beat_id] = res_lines
				changed = true
				break

	var view: Dictionary = PanelBuilder.build(location_id, self, Data)
	for bv: Dictionary in view.get("beats", []):
		var bid: String = str(bv["beat"].get("id", ""))
		if lines_by_beat.has(bid):
			bv["lines"] = lines_by_beat[bid]
		elif int(bv.get("tri", -1)) == PanelBuilder.TriState.OPEN:
			bv["lines"] = enter_beat(bid)
		else:
			bv["lines"] = PackedStringArray()

	return view


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


## 取得某個槽當前可放置的手牌或知識卡 id 列表（UI 專用查詢，規則層統一計算）。
## 沿用 try_place() 的第①③④步判斷（持有、accepts、action_spent）。
func placeable_cards(beat_id: String, slot_id: String) -> Array[String]:
	var result: Array[String] = []
	var beat: Dictionary = Data.loader.beats_by_id.get(beat_id, {})
	if beat.is_empty():
		return result

	var slot: Dictionary = {}
	for s: Dictionary in beat.get("slots", []) as Array:
		if str(s.get("id", "")) == slot_id:
			slot = s
			break
	if slot.is_empty():
		return result

	var slot_key := beat_id + "::" + slot_id
	if slots_placed.has(slot_key):
		return result

	var choice_group: Variant = slot.get("choice_group")
	if choice_group != null and not str(choice_group).is_empty():
		var group_key := beat_id + "::" + str(choice_group)
		if choices.has(group_key):
			return result

	var accepts: Array = slot.get("accepts", []) as Array
	var in_action_phase := ACTION_PHASES.has(phase)

	# 候選卡：hand + knowledge.keys()（保持 hand 原有順序，知識在後）
	var candidates: Array[String] = []
	for c_id in hand:
		candidates.append(c_id)
	for k_id in (knowledge as Dictionary).keys():
		candidates.append(str(k_id))

	for card_id in candidates:
		var base_id := _card_base_id(card_id)
		var card: Dictionary = Data.loader.cards.get(base_id, {})
		var card_type := str(card.get("type", ""))

		# ③ accepts
		if not (accepts.has(base_id) or accepts.has(card_type)):
			continue

		# ④ 行動格主角卡消耗檢查
		if card_type == "protagonist" and in_action_phase and action_spent:
			continue

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

	var slot: Dictionary = {}
	for s: Dictionary in beat.get("slots", []) as Array:
		if str(s.get("id", "")) == slot_id and str(s.get("choice_group", "")) == group_id:
			slot = s
			break
	if slot.is_empty():
		return { "ok": false, "reason_code": _REASON_UNKNOWN_SLOT, "reason_text": "", "lines": PackedStringArray() }

	# 三態必須 OPEN
	if not ConditionEval.eval(beat.get("condition"), self):
		return { "ok": false, "reason_code": _REASON_HIDDEN, "reason_text": "", "lines": PackedStringArray() }
	if not ConditionEval.eval(beat.get("requires"), self):
		var beat_reason := str(beat.get("reject_reason", _REASON_LOCKED_FALLBACK))
		return { "ok": false, "reason_code": _REASON_LOCKED, "reason_text": beat_reason, "lines": PackedStringArray() }
	if not ConditionEval.eval(slot.get("condition"), self):
		return { "ok": false, "reason_code": _REASON_HIDDEN, "reason_text": "", "lines": PackedStringArray() }
	var slot_key := beat_id + "::" + slot_id
	if slots_placed.has(slot_key):
		return { "ok": false, "reason_code": _REASON_RESOLVED, "reason_text": "", "lines": PackedStringArray() }
	if not ConditionEval.eval(slot.get("requires"), self):
		var slot_reason := str(slot.get("reject_reason", _REASON_LOCKED_FALLBACK))
		return { "ok": false, "reason_code": _REASON_LOCKED, "reason_text": slot_reason, "lines": PackedStringArray() }

	# 帶卡檢查（若傳入 card_id）
	if not card_id.is_empty():
		if not has_card(card_id):
			return { "ok": false, "reason_code": _REASON_NOT_HELD, "reason_text": "", "lines": PackedStringArray() }
		var base_id := _card_base_id(card_id)
		var card: Dictionary = Data.loader.cards.get(base_id, {})
		var accepts: Array = slot.get("accepts", []) as Array
		var card_type := str(card.get("type", ""))
		if not (accepts.has(base_id) or accepts.has(card_type)):
			return { "ok": false, "reason_code": _REASON_NOT_ACCEPTED, "reason_text": "", "lines": PackedStringArray() }

	# 效果結算（原子操作）
	var lines: PackedStringArray = EffectApply.apply(slot.get("on_place", {}), self)
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
	var beat: Dictionary = Data.loader.beats_by_id.get(beat_id, {})
	if beat.is_empty():
		return { "ok": false, "reason_code": _REASON_UNKNOWN_BEAT, "reason_text": "", "lines": PackedStringArray() }

	var slot: Dictionary = {}
	for s: Dictionary in beat.get("slots", []) as Array:
		if str(s.get("id", "")) == slot_id:
			slot = s
			break
	if slot.is_empty():
		return { "ok": false, "reason_code": _REASON_UNKNOWN_SLOT, "reason_text": "", "lines": PackedStringArray() }

	var choice_group: Variant = slot.get("choice_group")
	if choice_group != null and not str(choice_group).is_empty():
		return choose(beat_id, str(choice_group), slot_id, card_id)

	# ① 持有：傳入的卡此刻必須在手牌或知識集合（UI 是零規則顯示層，不能靠它擋非法卡 id）。
	if not has_card(card_id):
		return { "ok": false, "reason_code": _REASON_NOT_HELD, "reason_text": "", "lines": PackedStringArray() }

	var base_id := _card_base_id(card_id)
	var card: Dictionary = Data.loader.cards.get(base_id, {})
	var slot_key := beat_id + "::" + slot_id

	# ② 三態必須 OPEN（含一次性未放過）。beat 級 condition/requires 語意相同——
	# beat 不可互動時，內部槽一律不可放（規格書第五節），不能只靠 PanelBuilder 的 view model
	# 擋（UI 是零規則顯示層，規則層要能獨立擋下非法呼叫）。
	if not ConditionEval.eval(beat.get("condition"), self):
		return { "ok": false, "reason_code": _REASON_HIDDEN, "reason_text": "", "lines": PackedStringArray() }
	if not ConditionEval.eval(beat.get("requires"), self):
		var beat_reason := str(beat.get("reject_reason", _REASON_LOCKED_FALLBACK))
		return { "ok": false, "reason_code": _REASON_LOCKED, "reason_text": beat_reason, "lines": PackedStringArray() }
	if not ConditionEval.eval(slot.get("condition"), self):
		return { "ok": false, "reason_code": _REASON_HIDDEN, "reason_text": "", "lines": PackedStringArray() }
	if slots_placed.has(slot_key):
		return { "ok": false, "reason_code": _REASON_RESOLVED, "reason_text": "", "lines": PackedStringArray() }
	if not ConditionEval.eval(slot.get("requires"), self):
		var slot_reason := str(slot.get("reject_reason", _REASON_LOCKED_FALLBACK))
		return { "ok": false, "reason_code": _REASON_LOCKED, "reason_text": slot_reason, "lines": PackedStringArray() }

	# ③ accepts：型別名或卡 id。
	var accepts: Array = slot.get("accepts", []) as Array
	var card_type := str(card.get("type", ""))
	if not (accepts.has(base_id) or accepts.has(card_type)):
		return { "ok": false, "reason_code": _REASON_NOT_ACCEPTED, "reason_text": "", "lines": PackedStringArray() }

	# ④ 主角卡在行動格（morning/afternoon）時，同一時段不能放第二次。
	# night 時段放主角卡不消耗行動格（規格書第六節），所以不受這一步限制。
	var is_protagonist := card_type == "protagonist"
	var in_action_phase := ACTION_PHASES.has(phase)
	if is_protagonist and in_action_phase and action_spent:
		return { "ok": false, "reason_code": _REASON_ACTION_SPENT, "reason_text": "", "lines": PackedStringArray() }

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
