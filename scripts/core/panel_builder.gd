class_name PanelBuilder
extends RefCounted

## 地點面板 view model 計算器（純函式，規格書第四、五、九節）。
## build / available_locations 是 map_list、location_panel、走查腳本的共用入口。

enum TriState { HIDDEN = 0, LOCKED = 1, OPEN = 2, RESOLVED = 3 }

## 資料沒寫 reject_reason 時的通用理由。三態的硬規則要求灰掉一定要附理由（企劃書第十七節），
## 所以這裡不能留空字串——但資料端該補的仍然要補，lint 2 會抓。
const _REASON_FALLBACK := "（條件不足）"
const _REASON_NIGHT_LOCKED_STUB := "（夜間標記尚未開放）"


## 當前天╱時段可到的地點 id 列表。
## 白天：layer(day/both) + chapter ≤ 當前章 + phases 含當前時段。
## 夜間：layer(night) + earliest_night ≤ 當前天。
## map_list 只渲染這份結果，自己不過濾。
static func available_locations(gs: Node, data: Node) -> Array[String]:
	var result: Array[String] = []
	var loader: DataLoader = data.get("loader") as DataLoader
	if loader == null:
		return result

	var current_chapter: int = gs.call("chapter")
	var current_phase: String = str(gs.get("phase"))
	var current_day: int = int(gs.get("day"))

	if current_phase == "night":
		var chosen_loc: String = str(gs.get("night_location_chosen"))
		if not chosen_loc.is_empty():
			if loader.locations.has(chosen_loc):
				result.append(chosen_loc)
			return result

		for loc_id: String in loader.locations:
			var loc: Dictionary = loader.locations[loc_id] as Dictionary
			if str(loc.get("layer", "")) != "night":
				continue
			var earliest: int = int(loc.get("earliest_night", 999))
			if earliest <= current_day:
				result.append(loc_id)
		return result

	for loc_id: String in loader.locations:
		var loc: Dictionary = loader.locations[loc_id] as Dictionary
		var layer: String = str(loc.get("layer", ""))
		if layer != "day" and layer != "both":
			continue
		if int(loc.get("chapter", 1)) > current_chapter:
			continue
		var phases: Array = loc.get("phases", []) as Array
		if not phases.has(current_phase):
			continue
		result.append(loc_id)

	return result


## 計算一個地點面板的 view model。
## 回傳：{ "beats": [ { "beat": Dictionary, "tri": TriState, "reason": String,
##                      "slots": [ { "slot": Dictionary, "tri": TriState, "reason": String, "is_choice": bool } ] } ] }
## HIDDEN 的 beat 不進回傳陣列（等同不存在）。
static func build(location_id: String, gs: Node, data: Node) -> Dictionary:
	var loader: DataLoader = data.get("loader") as DataLoader
	if loader == null:
		return { "location": {}, "beats": [] }

	var current_day: int = int(gs.get("day"))
	var current_phase: String = str(gs.get("phase"))
	var current_chapter: int = int(gs.call("chapter"))
	var placed_raw: Variant = gs.get("slots_placed")
	var placed: Dictionary = placed_raw as Dictionary if placed_raw is Dictionary else {}
	var choices_raw: Variant = gs.get("choices")
	var choices: Dictionary = choices_raw as Dictionary if choices_raw is Dictionary else {}

	var candidate_beats: Array[Dictionary] = []

	if current_phase != "night":
		# 白天 / 傍晚：直接取當天該時段掛在該地點的所有 beat（K-14）
		for b in loader.beats_at(current_day, current_phase):
			if str(b.get("location", "")) == location_id:
				candidate_beats.append(b)
	else:
		# 夜間四步解析（規格書第九節）：
		var loc: Dictionary = loader.locations.get(location_id, {}) as Dictionary
		var madness_cost: int = int(loc.get("madness_cost", 0))

		if madness_cost > 0:
			# 收費地點在 P1 呈灰鎖定附 stub 理由
			return {
				"location": loc,
				"beats": [
					{
						"beat": {
							"id": location_id + "_locked",
							"title": str(loc.get("name", location_id)),
							"text": "",
						},
						"tri": TriState.LOCKED,
						"reason": _REASON_NIGHT_LOCKED_STUB,
						"slots": [],
					}
				]
			}

		# 免費地點：
		# 1. 主內容：定日優先於章節變體
		var primary_beat: Dictionary = {}
		for b in loader.beats:
			if str(b.get("location", "")) != location_id:
				continue
			var w: Variant = b.get("when")
			if w is Dictionary:
				var wd := w as Dictionary
				if int(wd.get("day", -1)) == current_day and str(wd.get("phase", "")) == "night":
					primary_beat = b
					break

		if primary_beat.is_empty():
			# 找章節變體：no when, has chapter, chapter <= current_chapter (取最大 chapter)
			var best_ch := -1
			for b in loader.beats:
				if str(b.get("location", "")) != location_id:
					continue
				if b.has("when"):
					continue
				if b.has("chapter"):
					var ch := int(b.get("chapter", 1))
					if ch <= current_chapter and ch > best_ch:
						best_ch = ch
						primary_beat = b

		if not primary_beat.is_empty():
			candidate_beats.append(primary_beat)

		# 2. 附加 beat 並列：no when, no chapter, location == location_id
		for b in loader.beats:
			if str(b.get("location", "")) != location_id:
				continue
			if not b.has("when") and not b.has("chapter"):
				candidate_beats.append(b)

	var beats_result: Array = []

	for b in candidate_beats:
		var beat_tri: int
		var beat_reason: String = ""

		if not ConditionEval.eval(b.get("condition"), gs):
			beat_tri = TriState.HIDDEN
		elif not ConditionEval.eval(b.get("requires"), gs):
			beat_tri = TriState.LOCKED
			beat_reason = str(b.get("reject_reason", _REASON_FALLBACK))
		else:
			beat_tri = TriState.OPEN

		if beat_tri == TriState.HIDDEN:
			continue

		var slots_result: Array = []
		for s in b.get("slots", []) as Array:
			var slot_tri: int
			var slot_reason: String = ""
			var beat_id: String = str(b.get("id", ""))
			var slot_id: String = str(s.get("id", ""))
			var slot_key: String = beat_id + "::" + slot_id
			var choice_group: Variant = s.get("choice_group")
			var is_choice := choice_group != null and not str(choice_group).is_empty()
			var group_key := beat_id + "::" + str(choice_group) if is_choice else ""

			# choice_group 已選定：整組只渲染被選的那個，狀態為 RESOLVED（P1-E 契約）
			if is_choice and choices.has(group_key):
				var chosen_slot_id: String = str(choices[group_key])
				if slot_id != chosen_slot_id:
					continue
				else:
					slot_tri = TriState.RESOLVED
			else:
				if not ConditionEval.eval(s.get("condition"), gs):
					slot_tri = TriState.HIDDEN
				elif placed.has(slot_key):
					slot_tri = TriState.RESOLVED
				elif not ConditionEval.eval(s.get("requires"), gs):
					slot_tri = TriState.LOCKED
					slot_reason = str(s.get("reject_reason", _REASON_FALLBACK))
				else:
					slot_tri = TriState.OPEN

			if slot_tri != TriState.HIDDEN:
				slots_result.append({
					"slot": s,
					"tri": slot_tri,
					"reason": slot_reason,
					"is_choice": is_choice, # K-19
					"accept_types": _accept_types(s, loader, data),
				})

		# beat 級 requires 語意相同：成立前整個 beat 呈灰卡狀態＋理由，內部槽不可互動
		# （規格書第五節）——beat LOCKED 時，槽的三態降為 LOCKED，理由沿用 beat 的。
		# 但已放過的槽（RESOLVED）維持 RESOLVED（已知問題 K-12）。
		if beat_tri == TriState.LOCKED:
			for slot_view: Dictionary in slots_result:
				if int(slot_view.get("tri", -1)) != TriState.RESOLVED:
					slot_view["tri"] = TriState.LOCKED
					slot_view["reason"] = beat_reason

		beats_result.append({
			"beat": b,
			"tri": beat_tri,
			"reason": beat_reason,
			"slots": slots_result,
		})

	return {
		"location": loader.locations.get(location_id, {}),
		"beats": beats_result,
	}


## 把槽的 accepts 換成去重、保序的顯示型別名稱。
## 具體卡 id 只反查 type，絕不把卡名暴露在槽標籤上。
static func _accept_types(slot: Dictionary, loader: DataLoader, data: Node) -> PackedStringArray:
	var result := PackedStringArray()
	var seen: Dictionary = {}
	for accepted: Variant in slot.get("accepts", []) as Array:
		var accepted_id := str(accepted)
		var type_id := accepted_id
		if loader.cards.has(accepted_id):
			type_id = str((loader.cards[accepted_id] as Dictionary).get("type", ""))
		if type_id.is_empty() or seen.has(type_id):
			continue
		seen[type_id] = true
		var display_name := str(data.call("card_type_name", type_id))
		if display_name.is_empty():
			display_name = type_id
		result.append(display_name)
	return result
