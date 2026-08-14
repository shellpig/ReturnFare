class_name EffectApply
extends RefCounted

## on_place / on_enter 效果鍵結算（規格書第十四節）。
## 結算順序固定：text 呈現 → lose → gain → switch → switch_progress → relation → madness → flag。
## lose 先於 gain，讓「升級知識卡」不會瞬間超格。
## 回傳 UI 要播的文字行；不含 text 鍵時回傳空陣列。

const KNOWN_KEYS := [
	"text", "gain", "lose", "switch", "switch_progress", "relation", "madness", "flag",
]

static func apply(effect: Variant, gs: Node) -> PackedStringArray:
	var lines := PackedStringArray()
	if not effect is Dictionary:
		return lines
	var e := effect as Dictionary

	var text: Variant = e.get("text")
	if text is String and not (text as String).is_empty():
		lines.append(text as String)

	for card_id: Variant in e.get("lose", []) as Array:
		gs.call("lose_card", str(card_id))

	for card_id: Variant in e.get("gain", []) as Array:
		gs.call("gain_card", str(card_id))

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
