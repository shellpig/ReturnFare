class_name Encounter
extends RefCounted

## 遭遇系統純判斷與 Graph 處理（規格書第十三節、P4-D）。
## Encounter 不持有 runtime 狀態，所有狀態由 GameState.active_encounter 持有。

## 取得特定回合定義
static func get_round(encounter_data: Dictionary, round_id: String) -> Dictionary:
	for r in encounter_data.get("rounds", []) as Array:
		if r is Dictionary and str((r as Dictionary).get("id", "")) == round_id:
			return r as Dictionary
	return {}


## 取得第一回合 ID
static func get_first_round_id(encounter_data: Dictionary) -> String:
	var rounds: Array = encounter_data.get("rounds", []) as Array
	if not rounds.is_empty() and rounds[0] is Dictionary:
		return str((rounds[0] as Dictionary).get("id", ""))
	return ""


## 尋找命中之 response 分支（依資料順序搜尋）
static func find_matching_response(round_data: Dictionary, card_id: String, base_card_id: String) -> Dictionary:
	for resp in round_data.get("responses", []) as Array:
		if not resp is Dictionary:
			continue
		var r_dict := resp as Dictionary
		var accepts: Array = r_dict.get("accepts", []) as Array
		if accepts.has(card_id) or accepts.has(base_card_id):
			return r_dict
	return {}


## 檢查是否命中任一 response 分支
static func matches_any_response(round_data: Dictionary, card_id: String, base_card_id: String) -> bool:
	return not find_matching_response(round_data, card_id, base_card_id).is_empty()


## 檢查是否有任何合法動作（卡片提交、丟棄、逃離）
static func has_legal_moves(encounter_data: Dictionary, round_data: Dictionary, active_state: Dictionary, gs: Node, loader: DataLoader) -> bool:
	if gs == null or loader == null:
		return false

	var attempted: Array = active_state.get("attempted_card_ids", []) as Array
	var fallback: Dictionary = round_data.get("fallback", {}) as Dictionary
	var req_discardable: bool = bool(fallback.get("requires_discardable", false))

	# 1. 檢查 hand ∪ knowledge 是否有未嘗試的合法提交卡
	var hand: Array = gs.get("hand") as Array if "hand" in gs else []
	for cid_raw in hand:
		var cid := str(cid_raw)
		var base_id := _extract_base_id(cid)

		# 發狂卡不可提交
		if base_id == "madness":
			continue
		# 同一 base card 本場只能嘗試一次
		if attempted.has(base_id):
			continue

		# 命中 response 恆為合法提交
		if matches_any_response(round_data, cid, base_id):
			return true

		# 未命中 response，檢查 fallback 規則
		var card_def: Dictionary = loader.cards.get(base_id, {}) as Dictionary
		var is_discardable: bool = bool(card_def.get("discardable", false))
		if not req_discardable or is_discardable:
			return true

	var knowledge: Dictionary = gs.get("knowledge") as Dictionary if "knowledge" in gs else {}
	for kid_raw in knowledge.keys():
		var kid := str(kid_raw)
		var base_id := kid
		if attempted.has(base_id):
			continue
		if matches_any_response(round_data, kid, base_id):
			return true
		var card_def: Dictionary = loader.cards.get(base_id, {}) as Dictionary
		var is_discardable: bool = bool(card_def.get("discardable", false))
		if not req_discardable or is_discardable:
			return true

	# 2. 檢查是否可主動丟棄（allow_discard: true 且手上有至少一張可丟棄的非發狂卡）
	if bool(encounter_data.get("allow_discard", true)):
		for cid_raw in hand:
			var cid := str(cid_raw)
			var base_id := _extract_base_id(cid)
			if base_id == "madness":
				continue
			var card_def: Dictionary = loader.cards.get(base_id, {}) as Dictionary
			if bool(card_def.get("discardable", false)):
				return true

	# 3. 檢查是否可逃離
	var esc_cost_var: Variant = encounter_data.get("escape_cost")
	if esc_cost_var != null:
		var esc_cost := int(esc_cost_var)
		if esc_cost == 0:
			return true
		var discardable_count := 0
		for cid_raw in hand:
			var cid := str(cid_raw)
			var base_id := _extract_base_id(cid)
			if base_id == "madness":
				continue
			var card_def: Dictionary = loader.cards.get(base_id, {}) as Dictionary
			if bool(card_def.get("discardable", false)):
				discardable_count += 1
		if discardable_count >= esc_cost:
			return true

	return false


## 建立 View Model（供 UI 或測試走查，絕不外洩未到回合或 accepts 答案集合）
static func build_view(encounter_data: Dictionary, active_state: Dictionary, gs: Node, loader: DataLoader, tuning: Dictionary) -> Dictionary:
	if active_state.is_empty():
		return {}

	var stage := str(active_state.get("stage", "intro"))
	var beat_id := str(active_state.get("beat_id", ""))
	var blocked_slots := int(active_state.get("blocked_slots", 0))
	var hand_size := int(tuning.get("hand_size", 14))
	var hand: Array = gs.get("hand") as Array if (gs != null and "hand" in gs) else []
	var available_slots := hand_size - hand.size() - blocked_slots

	if stage == "intro":
		return {
			"stage": "intro",
			"beat_id": beat_id,
			"blocked_slots": blocked_slots,
			"capacity": hand_size,
			"available_slots": available_slots,
		}

	var round_id := str(active_state.get("round_id", ""))
	var round_data := get_round(encounter_data, round_id)
	var attempted: Array = active_state.get("attempted_card_ids", []) as Array
	var fallback: Dictionary = round_data.get("fallback", {}) as Dictionary
	var req_discardable: bool = bool(fallback.get("requires_discardable", false))

	var candidates: Array[Dictionary] = []

	# Hand 卡片
	for cid_raw in hand:
		var cid := str(cid_raw)
		var base_id := _extract_base_id(cid)
		var card_def: Dictionary = loader.cards.get(base_id, {}) as Dictionary if loader != null else {}
		var is_madness := (base_id == "madness")
		var is_attempted := attempted.has(base_id)
		var is_discardable := bool(card_def.get("discardable", false))
		var submittable := true
		var disabled_reason := ""

		if is_madness:
			submittable = false
			disabled_reason = "madness_blocked"
		elif is_attempted:
			submittable = false
			disabled_reason = "already_attempted"
		elif req_discardable:
			var matches_resp := matches_any_response(round_data, cid, base_id)
			if not matches_resp and not is_discardable:
				submittable = false
				disabled_reason = "card_not_submittable"

		candidates.append({
			"card_id": cid,
			"base_id": base_id,
			"source": "hand",
			"name": str(card_def.get("name", "")),
			"submittable": submittable,
			"disabled_reason": disabled_reason,
			"discardable": is_discardable,
		})

	# Knowledge 卡片
	var knowledge: Dictionary = gs.get("knowledge") as Dictionary if (gs != null and "knowledge" in gs) else {}
	for kid_raw in knowledge.keys():
		var kid := str(kid_raw)
		var base_id := kid
		var card_def: Dictionary = loader.cards.get(base_id, {}) as Dictionary if loader != null else {}
		var is_attempted := attempted.has(base_id)
		var is_discardable := bool(card_def.get("discardable", false))
		var submittable := true
		var disabled_reason := ""

		if is_attempted:
			submittable = false
			disabled_reason = "already_attempted"
		elif req_discardable:
			var matches_resp := matches_any_response(round_data, kid, base_id)
			if not matches_resp and not is_discardable:
				submittable = false
				disabled_reason = "card_not_submittable"

		candidates.append({
			"card_id": kid,
			"base_id": base_id,
			"source": "knowledge",
			"name": str(card_def.get("name", "")),
			"submittable": submittable,
			"disabled_reason": disabled_reason,
			"discardable": is_discardable,
		})

	var esc_cost_var: Variant = encounter_data.get("escape_cost")
	return {
		"stage": "round",
		"beat_id": beat_id,
		"round_id": round_id,
		"demand": str(round_data.get("demand", "")),
		"blocked_slots": blocked_slots,
		"capacity": hand_size,
		"available_slots": available_slots,
		"can_escape": (esc_cost_var != null),
		"escape_cost": esc_cost_var,
		"allow_discard": bool(encounter_data.get("allow_discard", true)),
		"candidates": candidates,
		"attempted_card_ids": attempted.duplicate(),
	}


static func _extract_base_id(id: String) -> String:
	return DataFacts.card_base_id(id)
