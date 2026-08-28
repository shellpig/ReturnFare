class_name ConditionEval
extends RefCounted

## 封閉語彙條件求值器（規格書第十四節）。
## eval(null, gs) = true（缺欄視為恆成立）。
## 未知運算子 → push_error + return false。
## 無副作用，可重入。

const KNOWN_KEYS := [
	"day", "day_at_least", "has_card", "has_knowledge", "switch",
	"switch_progress_at_least", "flag", "relation_at_least", "madness_at_least",
	"count_at_least", "not", "all", "any", "night_seen",
	"opening_choice", "ending_seen", "festival_proxy_is",
]

static func eval(cond: Variant, gs: Node) -> bool:
	if cond == null:
		return true
	if not cond is Dictionary:
		push_error("ConditionEval: expected Dictionary or null, got type %d" % typeof(cond))
		return false
	var d := cond as Dictionary

	if d.has("day"):
		return int(gs.get("day")) == int(d["day"])
	if d.has("day_at_least"):
		return int(gs.get("day")) >= int(d["day_at_least"])
	if d.has("has_card"):
		return gs.call("has_card", str(d["has_card"]))
	if d.has("has_knowledge"):
		return gs.call("has_knowledge", str(d["has_knowledge"]))
	if d.has("night_seen"):
		return gs.call("night_location_seen", str(d["night_seen"]))
	if d.has("opening_choice"):
		var oc: Variant = gs.get("opening_choice_id") if (gs != null and "opening_choice_id" in gs) else ""
		return str(oc) == str(d["opening_choice"])
	if d.has("ending_seen"):
		if gs != null and gs.has_method("ending_seen"):
			return gs.call("ending_seen", str(d["ending_seen"]))
		var hist: Variant = gs.get("ending_history") if (gs != null and "ending_history" in gs) else []
		if hist is Array:
			for item in hist:
				if item is Dictionary and (item as Dictionary).get("ending_id") == str(d["ending_seen"]):
					return true
		return false
	if d.has("festival_proxy_is"):
		var fp: Variant = gs.get("selected_festival_proxy_npc") if (gs != null and "selected_festival_proxy_npc" in gs) else ""
		return str(fp) == str(d["festival_proxy_is"])
	if d.has("madness_at_least"):
		var mc: Variant = gs.get("madness_clock")
		var count: int = (mc as Dictionary).size() if mc is Dictionary else 0
		return count >= int(d["madness_at_least"])
	if d.has("switch"):
		var sw: Variant = gs.get("switches")
		return sw is Dictionary and (sw as Dictionary).get(str(d["switch"]), false)
	if d.has("switch_progress_at_least"):
		var sp: Dictionary = d["switch_progress_at_least"] as Dictionary
		var prog: Variant = gs.get("switch_progress")
		if not prog is Dictionary:
			return false
		return int((prog as Dictionary).get(str(sp.get("switch", "")), 0)) >= int(sp.get("n", 0))
	if d.has("flag"):
		var flags: Variant = gs.get("flags")
		return flags is Dictionary and (flags as Dictionary).get(str(d["flag"]), false)
	if d.has("relation_at_least"):
		var ra: Dictionary = d["relation_at_least"] as Dictionary
		return gs.call("relation_at_least", str(ra.get("npc", "")), str(ra.get("state", "")))
	if d.has("count_at_least"):
		var ca: Dictionary = d["count_at_least"] as Dictionary
		var n := int(ca.get("n", 0))
		var of_list: Array = ca.get("of", []) as Array
		var count := 0
		for sub: Variant in of_list:
			if eval(sub, gs):
				count += 1
		return count >= n
	if d.has("not"):
		return not eval(d["not"], gs)
	if d.has("all"):
		for sub: Variant in d["all"] as Array:
			if not eval(sub, gs):
				return false
		return true
	if d.has("any"):
		for sub: Variant in d["any"] as Array:
			if eval(sub, gs):
				return true
		return false

	push_error("ConditionEval: unknown operator in: " + JSON.stringify(d))
	return false
