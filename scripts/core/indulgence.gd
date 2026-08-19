class_name Indulgence
extends RefCounted

## 縱慾相關純計算與查表邏輯（P2-B, P2-C）。

## 挑選強制縱慾出口（規格書第八節、P2-C、開發設計方針 P2-C）。
## 掃描全部 accepts 含 madness 的槽，過濾掉 auto == false，
## 求值 condition 與 requires，取 indulgence.weight 最大者；同分取資料載入順序第一個。
## 不看地點可達性、不看 when——強制縱慾是主角自己動手，不是玩家走過去。
## 刻意不檢查 slots_placed（K-54，出口可重複使用）。
## 池空時回傳空字典並 push_error（資料錯誤，由 Lint 4 預先防禦）。
## 回傳：{ "beat_id": String, "slot_id": String } 或 {}
static func pick_exit(gs: Node, data: Object) -> Dictionary:
	var loader: DataLoader = data as DataLoader if data is DataLoader else (data.get("loader") as DataLoader if data != null else null)
	if loader == null:
		push_error("Indulgence.pick_exit: DataLoader not found")
		return {}

	var best_exit: Dictionary = {}
	var max_weight: int = -999999

	for beat: Dictionary in loader.beats:
		# 求值 beat 級條件與前置門檻（不檢查 when 與地點可達性）
		if not ConditionEval.eval(beat.get("condition"), gs):
			continue
		if not ConditionEval.eval(beat.get("requires"), gs):
			continue

		var beat_id := str(beat.get("id", ""))
		var slots: Array = beat.get("slots", []) as Array

		for slot_val: Variant in slots:
			if not slot_val is Dictionary:
				continue
			var slot := slot_val as Dictionary
			var accepts: Array = slot.get("accepts", []) as Array
			if not accepts.has("madness"):
				continue

			var ind_val: Variant = slot.get("indulgence")
			if ind_val == null or not (ind_val is Dictionary):
				continue
			var ind := ind_val as Dictionary

			# 過濾 auto == false（如泡湯 x_soak 永不入自動挑選池）
			if ind.has("auto") and not bool(ind.get("auto", true)):
				continue

			# 求值 slot 級條件與前置門檻
			if not ConditionEval.eval(slot.get("condition"), gs):
				continue
			if not ConditionEval.eval(slot.get("requires"), gs):
				continue

			var weight := int(ind.get("weight", 0))
			var slot_id := str(slot.get("id", ""))

			# 嚴格大於：同分時維持資料載入順序第一個
			if weight > max_weight:
				max_weight = weight
				best_exit = {
					"beat_id": beat_id,
					"slot_id": slot_id,
				}

	if best_exit.is_empty():
		push_error("Indulgence.pick_exit: no valid indulgence exit found (data bug, Lint 4 violation)")
		return {}

	return best_exit


## 依據累計縱慾次數 n（主動＋強制合計）查表決定強度級（規格書第八節）。
## n <= forced_light_count (預設 1) -> "light"
## n <= forced_normal_until (預設 7) -> "normal"
## 否則 -> "heavy"
static func level_for(n: int, tuning: Dictionary) -> String:
	var ind: Dictionary = tuning.get("indulgence", {}) as Dictionary
	var light_count: int = int(ind.get("forced_light_count", 1))
	var normal_until: int = int(ind.get("forced_normal_until", 7))
	if n <= light_count:
		return "light"
	elif n <= normal_until:
		return "normal"
	else:
		return "heavy"

