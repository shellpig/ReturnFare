class_name PanelBuilder
extends RefCounted

## 地點面板 view model 計算器（純函式，規格書第四、五、九節）。
## build / available_locations 是 map_list、location_panel、走查腳本的共用入口。

enum TriState { HIDDEN = 0, LOCKED = 1, OPEN = 2, RESOLVED = 3 }

## 資料沒寫 reject_reason 時的通用理由。三態的硬規則要求灰掉一定要附理由（企劃書第十七節），
## 所以這裡不能留空字串——但資料端該補的仍然要補，lint 2 會抓。
const _REASON_FALLBACK := "（條件不足）"


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
		var candidates: Array[Dictionary] = []
		var original_index: int = 0
		for loc_id: String in loader.locations:
			var loc: Dictionary = loader.locations[loc_id] as Dictionary
			if str(loc.get("layer", "")) != "night":
				original_index += 1
				continue
			var is_teaser: bool = bool(loc.get("teaser_only", false))
			var earliest: int = int(loc.get("earliest_night", 999))
			var chapter: int = int(loc.get("chapter", 1))
			var is_visible: bool = false
			if is_teaser:
				is_visible = (chapter <= current_chapter)
			else:
				is_visible = (earliest <= current_day)

			if is_visible:
				candidates.append({
					"id": loc_id,
					"earliest": earliest,
					"index": original_index,
				})
			original_index += 1

		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["earliest"]) != int(b["earliest"]):
				return int(a["earliest"]) < int(b["earliest"])
			return int(a["index"]) < int(b["index"])
		)

		for c in candidates:
			result.append(str(c["id"]))
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


## 計算夜間地點的 summary view model（規格書第九節、開發設計方針 P3-D）。
## 回傳：{
##   "display_name": String,
##   "status_text": String,
##   "can_enter": bool,
##   "reason_code": String,
##   "reason_text": String,
##   "warning": String,
##   "teaser_only": bool
## }
static func location_summary(location_id: String, gs: Node, data: Node) -> Dictionary:
	var loader: DataLoader = data.get("loader") as DataLoader if data != null else null
	if loader == null or not loader.locations.has(location_id):
		return {
			"display_name": location_id,
			"status_text": "",
			"can_enter": false,
			"reason_code": "unknown_location",
			"reason_text": "",
			"warning": "",
			"teaser_only": false,
		}

	var loc: Dictionary = loader.locations[location_id] as Dictionary
	var layer: String = str(loc.get("layer", ""))
	var is_teaser: bool = bool(loc.get("teaser_only", false))
	var day_counterpart: Variant = loc.get("day_counterpart")
	var night_reveal: Variant = loc.get("night_reveal")

	var seen_dict: Dictionary = gs.get("night_locations_seen") as Dictionary if gs != null and gs.get("night_locations_seen") is Dictionary else {}
	var is_seen: bool = seen_dict.has(location_id)

	var knowledge_dict: Dictionary = gs.get("knowledge") as Dictionary if gs != null and gs.get("knowledge") is Dictionary else {}
	var has_reveal_knowledge: bool = (night_reveal != null and not str(night_reveal).is_empty() and knowledge_dict.has(str(night_reveal)))
	var is_aligned: bool = (is_seen and has_reveal_knowledge)

	# 1. display_name 計算
	var display_name: String = str(loc.get("name", location_id))
	if day_counterpart != null and not str(day_counterpart).is_empty() and is_aligned:
		var day_loc_id := str(day_counterpart)
		var day_loc_name := day_loc_id
		if loader.locations.has(day_loc_id):
			day_loc_name = str((loader.locations[day_loc_id] as Dictionary).get("name", day_loc_id))

		# 檢查是一對一或多對一
		var counterpart_count := 0
		for other_id: String in loader.locations:
			var other_loc: Dictionary = loader.locations[other_id] as Dictionary
			if str(other_loc.get("layer", "")) == "night" and str(other_loc.get("day_counterpart", "")) == day_loc_id:
				counterpart_count += 1

		if counterpart_count > 1:
			display_name = "%s・%s" % [day_loc_name, str(loc.get("name", location_id))]
		else:
			display_name = day_loc_name

	# 2. status_text 計算
	var status_text: String = "[尚未到訪]"
	if is_teaser:
		status_text = "[尚未到訪]"
	elif not is_seen:
		status_text = "[尚未到訪]"
	else:
		if day_counterpart != null and not str(day_counterpart).is_empty():
			if is_aligned:
				status_text = "[已對位]"
			else:
				status_text = "[已到訪，尚未對位]"
		else:
			status_text = "[已到訪]"

	# 3. can_enter, reason_code, reason_text 計算 (依 GameState.enter_night_location 封閉八碼矩陣)
	var can_enter: bool = false
	var reason_code: String = ""
	var reason_text: String = ""

	var current_phase: String = str(gs.get("phase")) if gs != null else ""
	var current_day: int = int(gs.get("day")) if gs != null else 1
	var chosen_loc: String = str(gs.get("night_location_chosen")) if gs != null else ""
	var sleep_pending: bool = bool(gs.get("night_sleep_pending")) if gs != null else false

	if current_phase != "night":
		reason_code = "not_night"
	elif layer != "night":
		reason_code = "not_night_layer"
	elif is_teaser:
		reason_code = "teaser"
		reason_text = str(loc.get("reject_reason", ""))
	elif current_day < int(loc.get("earliest_night", 1)):
		reason_code = "too_early"
	elif loc.has("requires") and not ConditionEval.eval(loc["requires"], gs):
		reason_code = "locked"
		reason_text = str(loc.get("reject_reason", _REASON_FALLBACK))
	elif not chosen_loc.is_empty():
		reason_code = "already_chosen"
	elif sleep_pending:
		reason_code = "already_slept"
	else:
		can_enter = true

	# 4. warning 計算
	var warning: String = ""
	if gs != null and gs.has_method("would_night_entry_end_run") and bool(gs.call("would_night_entry_end_run", location_id)):
		warning = "再往前，你可能回不來。"

	return {
		"display_name": display_name,
		"status_text": status_text,
		"can_enter": can_enter,
		"reason_code": reason_code,
		"reason_text": reason_text,
		"warning": warning,
		"teaser_only": is_teaser,
	}


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
		# 夜間：唯一有狀態求值入口（P3-C，K-30）
		var resolved: Dictionary = gs.call("resolved_night_content", location_id)
		var p: Dictionary = resolved.get("primary", {})
		if not p.is_empty():
			candidate_beats.append(p)
		for addon in resolved.get("addons", []) as Array:
			if addon is Dictionary and not (addon as Dictionary).is_empty():
				candidate_beats.append(addon as Dictionary)

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
					var ind_val: Variant = s.get("indulgence")
					var is_soak := false
					if ind_val is Dictionary:
						is_soak = bool((ind_val as Dictionary).get("soak", false))

					if is_soak:
						var soak_cost := 2
						if data != null and data.has_method("tuning"):
							soak_cost = int(data.tuning("indulgence.soak_phase_cost", 2))
						var rem_actions: int = int(gs.call("remaining_actions_today")) if gs.has_method("remaining_actions_today") else (2 if (current_phase == "morning" and not bool(gs.get("action_spent"))) else (1 if (current_phase == "afternoon" and not bool(gs.get("action_spent"))) else 0))
						if rem_actions < soak_cost:
							slot_tri = TriState.LOCKED
							slot_reason = "（只能在上午發動）" if current_phase != "morning" else "（格數不足）"
						else:
							slot_tri = TriState.OPEN
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

	var is_empty_result := (current_phase == "night" and beats_result.is_empty())
	return {
		"location": loader.locations.get(location_id, {}),
		"beats": beats_result,
		"empty_result": is_empty_result,
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
