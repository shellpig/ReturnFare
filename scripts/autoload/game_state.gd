extends Node

## GameState autoload: 全部 runtime 狀態的唯一容器（規格書第一節）。
## P1-A：時間群與序列化骨架。
## P1-B：手牌群（hand / knowledge / madness_clock）。
## P1-C：beat 事件群（beats_entered / slots_placed / enter_beat）。

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

# --- 其他群（各 Phase 填入）---
var action_spent: bool = false        # P1-D 才有人寫（run 層）

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
		madness_clock[inst] = Data.tuning("madness_countdown_days", 7)
		hand_changed.emit()
		return

	# 其餘卡：unique（已持有 = no-op，含知識集合）
	if has_card(id):
		return
	hand.append(id)
	hand_changed.emit()


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
## P1-C 最小效果結算：只處理 on_enter 的 text 與 gain；P1-D 換成正式 EffectApply。
## 回傳要播的文字行（PackedStringArray）。
func enter_beat(beat_id: String) -> PackedStringArray:
	var is_first := not beats_entered.has(beat_id)
	beats_entered[beat_id] = true

	var beat: Dictionary = Data.loader.beats_by_id.get(beat_id, {})
	if beat.is_empty():
		push_error("enter_beat: unknown beat id '%s'" % beat_id)
		return PackedStringArray()

	var lines := PackedStringArray()

	# beat 主文（每次呈現都顯示）
	var text: Variant = beat.get("text")
	if text is String and not (text as String).is_empty():
		lines.append(text as String)

	# on_enter 效果（只在第一次結算）
	if is_first:
		var on_enter: Variant = beat.get("on_enter")
		if on_enter is Dictionary:
			var et: Variant = (on_enter as Dictionary).get("text")
			if et is String and not (et as String).is_empty():
				lines.append(et as String)
			var gain: Variant = (on_enter as Dictionary).get("gain")
			if gain is Array:
				for card_id: Variant in gain as Array:
					gain_card(str(card_id))

	return lines


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
		},
		"meta": {
			"knowledge": knowledge.duplicate(),
		}
	}


func deserialize(d: Dictionary) -> void:
	var run: Dictionary = d.get("run", {})
	day = run.get("day", 1)
	phase = run.get("phase", "morning")
	action_spent = run.get("action_spent", false)
	hand = run.get("hand", []).duplicate()
	madness_clock = run.get("madness_clock", {}).duplicate()
	_madness_counter = run.get("_madness_counter", 0)
	beats_entered = run.get("beats_entered", {}).duplicate()
	slots_placed = run.get("slots_placed", {}).duplicate()

	var meta: Dictionary = d.get("meta", {})
	knowledge = meta.get("knowledge", {}).duplicate()


# ── 內部工具 ─────────────────────────────────────────────────────────────────

func _card_base_id(id: String) -> String:
	var hash_idx := id.rfind("#")
	if hash_idx >= 0:
		return id.substr(0, hash_idx)
	return id
