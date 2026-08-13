extends Node

## GameState autoload: 全部 runtime 狀態的唯一容器（規格書第一節）。
## P1-A 範圍：時間群與序列化骨架。其餘群先立空欄位，各 Phase 再填。

const CHAPTER_START_DAYS := [1, 16, 33]
const LAST_DAY := 45
const PHASES := ["morning", "afternoon", "evening", "night"]
const ACTION_PHASES := ["morning", "afternoon"]

# --- 時間群（run 層）---
var day: int = 1
var phase: String = "morning"

# --- 其他群（各 Phase 填入；已在此立位讓序列化結構穩定）---
var action_spent: bool = false        # P1-D 才有人寫，P1-A 只進序列化

signal phase_changed(day: int, phase: String)
signal day_changed(day: int)
signal chapter_changed(chapter: int)
signal run_ended(ending_id: String)


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


func serialize() -> Dictionary:
	return {
		"run": {
			"day": day,
			"phase": phase,
			"action_spent": action_spent,
		},
		"meta": {}
	}


func deserialize(d: Dictionary) -> void:
	var run: Dictionary = d.get("run", {})
	day = run.get("day", 1)
	phase = run.get("phase", "morning")
	action_spent = run.get("action_spent", false)
