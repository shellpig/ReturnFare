class_name DataFacts
extends RefCounted

## 專案資料靜態事實與名單（B-03、K-16）

## 刻意設計為完全無任何 beat 的行動時段名單（verify_data 與走查腳本共用，B-03）
const BY_DESIGN_EMPTY_PHASES: Array[Dictionary] = [
	{ "day": 32, "phase": "afternoon" },
]

## 純演出時段：有 fixed auto_enter beat、但玩家不選地點也不放卡的行動時段。
## 第 1 天上午與下午主角還在路上，鎮上的地點一個都還沒抵達，因此地圖不出清單
## （PanelBuilder.available_locations() 直接回空），lint 5 的地點時段支援檢查也跳過
## ——這類 beat 的 location 只是歸屬標籤，玩家不從地圖進入。
const NARRATION_ONLY_PHASES: Array[Dictionary] = [
	{ "day": 1, "phase": "morning" },
	{ "day": 1, "phase": "afternoon" },
]

## 有 beat 但僅有 choice 槽、無主角卡槽的行動時段（K-16，走查腳本豁免名單）
const BY_DESIGN_CHOICE_ONLY_PHASES: Array[Dictionary] = [
	{ "day": 35, "phase": "afternoon" },
	{ "day": 40, "phase": "morning" },
	{ "day": 43, "phase": "afternoon" },
]

## 違反 SCHEMA 同面板規約但已接受豁免的免費槽 beat 名單（K-16、K-27，lint 3 豁免名單）
## 前三個是 choice 槽；d43_morning_ask_paper 是比對槽——lint 3 目前只查 choice 槽，
## 要等 K-27 把判斷放寬成「不收 protagonist 的槽」之後才看得到它。
const BY_DESIGN_CHOICE_ONLY_BEATS: PackedStringArray = [
	"d35_pm_answer",
	"d40_tell_someone",
	"d43_conclusion",
	"d43_morning_ask_paper",
]

## 待決 22 卡片清單尚未建立、但已知在 requires 佔位使出口恆為 LOCKED 的卡片 id 名單（奢侈出口錢卡）
const BY_DESIGN_PENDING_CARD_REFS: PackedStringArray = [
	"card_money",
]

## 章節起始天數（第 1、2、3 章）
const CHAPTER_START_DAYS: Array[int] = [1, 16, 33]


## 根據天數計算所屬章節（1-3）
static func chapter_for_day(day: int) -> int:
	for i in range(CHAPTER_START_DAYS.size() - 1, -1, -1):
		if day >= CHAPTER_START_DAYS[i]:
			return i + 1
	return 1


## 檢查給定的 (day, phase) 是否為刻意留空的行動時段
static func is_empty_phase_by_design(day: int, phase: String) -> bool:
	for p in BY_DESIGN_EMPTY_PHASES:
		if int(p.get("day", -1)) == day and str(p.get("phase", "")) == phase:
			return true
	return false


## 檢查給定的 (day, phase) 是否為純演出時段（無地圖、無行動格）
static func is_narration_only_phase(day: int, phase: String) -> bool:
	for p in NARRATION_ONLY_PHASES:
		if int(p.get("day", -1)) == day and str(p.get("phase", "")) == phase:
			return true
	return false


## 檢查給定的 (day, phase) 是否為只有 choice 槽的行動時段
static func is_choice_only_phase_by_design(day: int, phase: String) -> bool:
	for p in BY_DESIGN_CHOICE_ONLY_PHASES:
		if int(p.get("day", -1)) == day and str(p.get("phase", "")) == phase:
			return true
	return false


## 檢查給定的 card_id 是否為已知待決尚未建檔的引用卡片
static func is_pending_card_ref_by_design(card_id: String) -> bool:
	return BY_DESIGN_PENDING_CARD_REFS.has(card_id)



## 檢查 beat 在給定的天數、時段是否成立（僅負責有 when beat 的日期／時段判準，P3-C）。
static func beat_matches_time(beat: Dictionary, day: int, phase: String) -> bool:
	var w: Variant = beat.get("when")
	if not w is Dictionary:
		return false
	var wd := w as Dictionary
	if wd.has("day") and wd.has("day_from"):
		return false

	# 日期比對
	if wd.has("day"):
		if int(wd.get("day", -1)) != day:
			return false
	elif wd.has("day_from") or wd.has("day_to"):
		var from_d := int(wd.get("day_from", 1))
		var to_d := int(wd.get("day_to", 45))
		if day < from_d or day > to_d:
			return false
	else:
		return false

	# 時段比對
	var p_val: Variant = wd.get("phase")
	if p_val is Array:
		if not (p_val as Array).has(phase):
			return false
	elif p_val is String:
		if str(p_val) != phase:
			return false
	else:
		return false

	return true


## 取得卡片 base id（去除實例後綴如 #1、#2，K-137）
static func card_base_id(id: String) -> String:
	var hash_idx := id.rfind("#")
	if hash_idx >= 0:
		return id.substr(0, hash_idx)
	return id
