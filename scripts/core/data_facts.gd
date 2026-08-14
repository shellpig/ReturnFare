class_name DataFacts
extends RefCounted

## 專案資料靜態事實與名單（B-03、K-16）

## 刻意設計為完全無任何 beat 的行動時段名單（verify_data 與走查腳本共用，B-03）
const BY_DESIGN_EMPTY_PHASES: Array[Dictionary] = [
	{ "day": 1, "phase": "morning" },
	{ "day": 1, "phase": "afternoon" },
	{ "day": 32, "phase": "afternoon" },
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


## 檢查給定的 (day, phase) 是否為刻意留空的行動時段
static func is_empty_phase_by_design(day: int, phase: String) -> bool:
	for p in BY_DESIGN_EMPTY_PHASES:
		if int(p.get("day", -1)) == day and str(p.get("phase", "")) == phase:
			return true
	return false


## 檢查給定的 (day, phase) 是否為只有 choice 槽的行動時段
static func is_choice_only_phase_by_design(day: int, phase: String) -> bool:
	for p in BY_DESIGN_CHOICE_ONLY_PHASES:
		if int(p.get("day", -1)) == day and str(p.get("phase", "")) == phase:
			return true
	return false
