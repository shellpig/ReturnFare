class_name EffectApply
extends RefCounted

## on_place / on_enter 效果鍵結算（規格書第十四節）。
## 結算順序固定：text 呈現 → lose → gain → switch → switch_progress → relation → madness → flag。
## lose 先於 gain，讓「升級知識卡」不會瞬間超格。
## 回傳 UI 要播的文字行；不含 text 鍵時回傳空陣列。

const KNOWN_KEYS := [
	"text", "gain", "lose", "switch", "switch_progress", "relation", "madness", "flag",
]

## gain / lose 的陣列元素有兩種形態：
##   "card_id"                                → 無條件執行（既有形態，仍是預設寫法）
##   { "card": "card_id", "if": <condition> } → `if` 成立才執行；語彙沿用 ConditionEval，不另立
## 用途見 `data/SCHEMA.md > on_place 效果 > 帶條件的卡片項目`。
const CARD_ENTRY_KEYS := ["card", "if"]

static func apply(effect: Variant, gs: Node) -> PackedStringArray:
	var lines := PackedStringArray()
	if not effect is Dictionary:
		return lines
	var e := effect as Dictionary

	var text: Variant = e.get("text")
	if text is String and not (text as String).is_empty():
		lines.append(text as String)

	for entry: Variant in e.get("lose", []) as Array:
		if _entry_passes(entry, gs):
			gs.call("lose_card", _entry_card_id(entry))

	for entry: Variant in e.get("gain", []) as Array:
		if _entry_passes(entry, gs):
			gs.call("gain_card", _entry_card_id(entry))

	if e.has("switch"):
		gs.call("open_switch", str(e["switch"]))

	if e.has("switch_progress"):
		var sp: Dictionary = e["switch_progress"] as Dictionary
		for switch_id: String in sp.keys():
			gs.call("add_switch_progress", switch_id, int(sp[switch_id]))

	if e.has("relation"):
		var r: Dictionary = e["relation"] as Dictionary
		gs.call("add_relation", str(r.get("npc", "")), int(r.get("delta", 0)))

	if e.has("madness"):
		for i in range(int(e["madness"])):
			gs.call("gain_card", "madness")

	if e.has("flag"):
		var f: Dictionary = e["flag"] as Dictionary
		for flag_name: String in f.keys():
			gs.call("set_flag", flag_name, true if f[flag_name] else false)

	return lines


## 卡片項目的 id：字串形態直接回傳，物件形態取 `card`。
static func _entry_card_id(entry: Variant) -> String:
	if entry is Dictionary:
		return str((entry as Dictionary).get("card", ""))
	return str(entry)


## 卡片項目的守衛：字串形態恆成立；物件形態求值 `if`（缺 `if` 亦恆成立，同 ConditionEval 契約）。
## 逐項求值而非整塊求值——同一個效果塊裡其他鍵（例如 flag）不受影響。
static func _entry_passes(entry: Variant, gs: Node) -> bool:
	if not entry is Dictionary:
		return true
	return ConditionEval.eval((entry as Dictionary).get("if"), gs)
