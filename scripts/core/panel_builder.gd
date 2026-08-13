class_name PanelBuilder
extends RefCounted

## 地點面板 view model 計算器（純函式，規格書第四、五節）。
## build / available_locations 是 map_list、location_panel、走查腳本的共用入口。

enum TriState { HIDDEN = 0, LOCKED = 1, OPEN = 2, RESOLVED = 3 }

## 資料沒寫 reject_reason 時的通用理由。三態的硬規則要求灰掉一定要附理由（企劃書第十七節），
## 所以這裡不能留空字串——但資料端該補的仍然要補，lint 2 會抓。
const _REASON_FALLBACK := "（條件不足）"


## 當前天╱時段可到的白天地點 id 列表。
## 過濾條件：layer(day/both) + chapter ≤ 當前章 + phases 含當前時段。
## map_list 只渲染這份結果，自己不過濾。
static func available_locations(gs: Node, data: Node) -> Array[String]:
	var result: Array[String] = []
	var loader: DataLoader = data.get("loader") as DataLoader
	if loader == null:
		return result

	var current_chapter: int = gs.call("chapter")
	var current_phase: String = str(gs.get("phase"))

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
##                      "slots": [ { "slot": Dictionary, "tri": TriState, "reason": String } ] } ] }
## HIDDEN 的 beat 不進回傳陣列（等同不存在）。
static func build(location_id: String, gs: Node, data: Node) -> Dictionary:
	var loader: DataLoader = data.get("loader") as DataLoader
	if loader == null:
		return { "beats": [] }

	var current_day: int = int(gs.get("day"))
	var current_phase: String = str(gs.get("phase"))
	var placed_raw: Variant = gs.get("slots_placed")
	var placed: Dictionary = placed_raw as Dictionary if placed_raw is Dictionary else {}

	var beats_result: Array = []

	for b in loader.beats:
		if str(b.get("location", "")) != location_id:
			continue
		# 無 when 的 beat 是夜間章節變體，不進白天面板
		if not b.has("when"):
			continue
		var w: Dictionary = b.get("when", {}) as Dictionary
		if int(w.get("day", -1)) != current_day or str(w.get("phase", "")) != current_phase:
			continue

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
			var slot_key: String = str(b.get("id", "")) + "::" + str(s.get("id", ""))

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
				})

		# beat 級 requires 語意相同：成立前整個 beat 呈灰卡狀態＋理由，內部槽不可互動
		# （規格書第五節）——beat LOCKED 時，槽的三態一律降為 LOCKED，理由沿用 beat 的。
		if beat_tri == TriState.LOCKED:
			for slot_view: Dictionary in slots_result:
				slot_view["tri"] = TriState.LOCKED
				slot_view["reason"] = beat_reason

		beats_result.append({
			"beat": b,
			"tri": beat_tri,
			"reason": beat_reason,
			"slots": slots_result,
		})

	return { "beats": beats_result }
