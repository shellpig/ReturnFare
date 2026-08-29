extends SceneTree

## P4-D 遭遇規則 headless 驗收測試：
## 1. 遭遇啟動與開場確認（start_encounter, stage intro, acknowledge_encounter_intro, stage round）
## 2. 遭遇自動啟動 hook 覆蓋（D45 下午 advance_phase 與 D8 入夜 play_night_fixed 自動建立 intro，K-126/K-127）
## 3. 遭遇進行中時段與各類放置／委託／縱慾／夜間操作阻擋（encounter_active）
## 4. 15 碼封閉拒絕矩陣（比對 serialize 零狀態變化，K-128）
## 5. 5 大遭遇入口固定拒絕順序優先驗證（雙條件交集衝突測試，K-131）
## 6. encounter_view 候選完整性、來源標記與答案不洩漏負向斷言（K-129）
## 7. 超載規則（is_overloaded 查詢、enter_night_location 阻擋、確認開場後立即結算 failure）
## 8. 佔格計算與扣除（進入回合加佔格、正解釋放本回合佔格、錯答保留佔格）
## 9. 主動丟棄卡片與逃離遭遇（allow_discard、cannot_escape 阻擋、扣卡結算）
## 10. 無合法解自動結算 failure 與容量上限失敗結算（手牌數＋佔格數 >= 容量）
## 11. 遭遇勝利與效果套用（累加型效果只套一次，K-140；不消耗 action、不開縱慾與備用區，K-141）
## 12. 遭遇結束推進（after_finish: "advance_phase" 推進時段、"stay" 停留原時段，K-130）
## 13. 回合循環偵測防禦（visited_round_ids 偵測 cycle 自動結算 failure，K-146）
## 14. 序列化往返與未存檔對照組逐字比對（K-139）
## 15. 故事線真實遭遇路徑驗證（D8 n_manydoors_ch1、D45 d45_encounter，K-138）
## 16. 夜間 fixed 迴圈於遭遇啟動後停播同夜後續 beat（與白天 hook 對齊）

const DataLoader := preload("res://scripts/data_loader.gd")
const ConditionEval := preload("res://scripts/core/condition_eval.gd")
const Encounter := preload("res://scripts/core/encounter.gd")
const DataFacts := preload("res://scripts/core/data_facts.gd")
const PlaythroughGreedy := preload("res://tests/headless/playthrough_greedy.gd")

func _initialize() -> void:
	var data_node: Node = PlaythroughGreedy.setup_data(self)
	var gs: Node = PlaythroughGreedy.setup_game_state(self, data_node)

	await process_frame

	if not bool(data_node.get("ok")):
		push_error("P4-D: Data failed to load; abort")
		quit(1)
		return

	var failed: int = 0
	print("\n=== P4-D 遭遇規則測試套件 ===")

	failed += _test_encounter_lifecycle_and_view(gs, data_node)
	failed += _test_phase_hook_autostart(gs, data_node)
	failed += _test_mutation_blocking_during_encounter(gs, data_node)
	failed += _test_15_code_rejection_matrix_zero_mutation(gs, data_node)
	failed += _test_rejection_priority_orders_all_endpoints(gs, data_node)
	failed += _test_view_model_completeness_and_non_leakage(gs, data_node)
	failed += _test_overload_and_penalty(gs, data_node)
	failed += _test_slot_blocking_and_release(gs, data_node)
	failed += _test_discard_and_escape(gs, data_node)
	failed += _test_no_legal_moves_and_capacity_failure(gs, data_node)
	failed += _test_victory_effects_and_action_immutability(gs, data_node)
	failed += _test_after_finish_stay_and_advance(gs, data_node)
	failed += _test_cycle_detection(gs, data_node)
	failed += _test_serialization_roundtrip_with_control(gs, data_node)
	failed += _test_storyline_encounters_contract(gs, data_node)
	failed += _test_night_fixed_stops_after_encounter(gs, data_node)

	if failed > 0:
		push_error("\nP4-D: %d assertion(s) failed\n" % failed)
		quit(1)
	else:
		print("\nP4-D: all tests passed\n")
		quit(0)


func _ok(msg: String) -> int:
	print("  [OK] %s" % msg)
	return 0


func _err(msg: String) -> int:
	push_error("  [FAIL] %s" % msg)
	return 1


## Helper: 建立乾淨測試環境
func _reset_gs(gs: Node) -> void:
	# P5-D：fresh state 是 opening，本檔驗的是 run 層規則。
	gs.set("flow_mode", "run")
	(gs.get("active_ending") as Dictionary).clear()
	PlaythroughGreedy.start_fresh_run(gs)
	gs.day = 1
	gs.phase = "morning"
	gs.hand.clear()
	gs.hand.append("protagonist")
	gs.knowledge.clear()
	# P5-B：knowledge_at_start 是 run_reset 當下的 knowledge 副本；這裡手動清 knowledge
	# 之後也要一起清，否則兩條對照路徑的開輪基準會不同（K-139 逐字比對）。
	(gs.get("knowledge_at_start") as Dictionary).clear()
	gs.flags.clear()
	gs.active_encounter.clear()


func _create_mock_encounter_beat(data_node: Node, beat_id: String, enc_data: Dictionary) -> void:
	var b: Dictionary = {
		"id": beat_id,
		"location": "sanquan",
		"when": { "day_from": 1, "day_to": 45, "phases": ["morning", "afternoon", "evening", "night"] },
		"encounter": enc_data
	}
	data_node.loader.beats_by_id[beat_id] = b


func _clean_mock_beat(data_node: Node, beat_id: String) -> void:
	if data_node != null and data_node.loader != null:
		data_node.loader.beats_by_id.erase(beat_id)


func _clean_mock_cards(data_node: Node, card_ids: Array) -> void:
	if data_node != null and data_node.loader != null:
		for cid in card_ids:
			data_node.loader.cards.erase(cid)


# ── 1. 遭遇啟動與開場確認 ───────────────────────────────────────────────────

func _test_encounter_lifecycle_and_view(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)

	data_node.loader.cards["k_fugu_cure"] = { "id": "k_fugu_cure", "type": "knowledge", "slotless": true, "discardable": false }

	var mock_enc: Dictionary = {
		"repeat_each_run": true,
		"charge_first_visit": false,
		"per_round_slot_cost": 1,
		"escape_cost": 1,
		"allow_discard": true,
		"after_finish": "stay",
		"rounds": [
			{
				"id": "r1",
				"demand": "第一回合需求",
				"responses": [
					{
						"accepts": ["k_fugu_cure"],
						"consume_card": false,
						"next_round": "r2",
						"on_resolve": { "flag": { "r1_cleared": true } }
					}
				],
				"fallback": {
					"prompt": "錯答提示",
					"requires_discardable": true,
					"next_round": null,
					"on_resolve": {}
				}
			},
			{
				"id": "r2",
				"demand": "第二回合需求",
				"responses": [
					{
						"accepts": ["k_fugu_cure"],
						"consume_card": false,
						"next_round": null,
						"on_resolve": {}
					}
				],
				"fallback": {
					"requires_discardable": false,
					"next_round": null
				}
			}
		],
		"on_victory": { "flag": { "enc_victory": true } },
		"on_failure": { "flag": { "enc_failed": true } }
	}
	_create_mock_encounter_beat(data_node, "mock_enc_lifecycle", mock_enc)

	# 啟動遭遇
	var res_start: Dictionary = gs.start_encounter("mock_enc_lifecycle")
	if not bool(res_start.get("ok", false)):
		failed += _err("start_encounter failed: %s" % str(res_start))
	elif str(gs.active_encounter.get("stage", "")) != "intro":
		failed += _err("active_encounter stage should be 'intro', got '%s'" % str(gs.active_encounter.get("stage", "")))
	elif int(gs.active_encounter.get("blocked_slots", -1)) != 0:
		failed += _err("blocked_slots should be 0 on intro, got %d" % int(gs.active_encounter.get("blocked_slots", -1)))
	else:
		failed += _ok("start_encounter correctly enters stage 'intro' with blocked_slots=0")

	# View model 檢查
	var view: Dictionary = gs.encounter_view()
	if str(view.get("stage", "")) != "intro":
		failed += _err("encounter_view stage should be 'intro'")
	elif int(view.get("blocked_slots", -1)) != 0:
		failed += _err("encounter_view blocked_slots should be 0")
	else:
		failed += _ok("encounter_view correctly reflects intro stage")

	# acknowledge intro 進入 round 1
	gs.knowledge["k_fugu_cure"] = true
	var res_ack: Dictionary = gs.acknowledge_encounter_intro()
	if not bool(res_ack.get("ok", false)):
		failed += _err("acknowledge_encounter_intro failed: %s" % str(res_ack))
	elif str(gs.active_encounter.get("stage", "")) != "round":
		failed += _err("active_encounter stage should be 'round', got '%s'" % str(gs.active_encounter.get("stage", "")))
	elif str(gs.active_encounter.get("round_id", "")) != "r1":
		failed += _err("round_id should be 'r1', got '%s'" % str(gs.active_encounter.get("round_id", "")))
	elif int(gs.active_encounter.get("blocked_slots", -1)) != 1:
		failed += _err("blocked_slots should be 1 after r1 entry, got %d" % int(gs.active_encounter.get("blocked_slots", -1)))
	else:
		failed += _ok("acknowledge_encounter_intro enters stage 'round' at r1 with blocked_slots=1")

	_clean_mock_beat(data_node, "mock_enc_lifecycle")
	_clean_mock_cards(data_node, ["k_fugu_cure"])
	return failed


# ── 2. 遭遇自動啟動 Hook 覆蓋（K-126/K-127）─────────────────────────────────

func _test_phase_hook_autostart(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)

	# 1. 白天定日遭遇：D45 上午 -> 下午，advance_phase 自動啟動 d45_encounter
	gs.day = 45
	gs.phase = "morning"
	gs.flags["final_day"] = true
	var adv_d45: Dictionary = gs.advance_phase()
	if not bool(adv_d45.get("ok", false)) or not bool(adv_d45.get("phase_advanced", false)):
		failed += _err("advance_phase to D45 afternoon failed: %s" % str(adv_d45))
	elif gs.phase != "afternoon":
		failed += _err("phase should be 'afternoon', got '%s'" % gs.phase)
	elif str(gs.active_encounter.get("beat_id", "")) != "d45_encounter":
		failed += _err("D45 afternoon should automatically start 'd45_encounter', got '%s'" % str(gs.active_encounter.get("beat_id", "")))
	elif str(gs.active_encounter.get("stage", "")) != "intro":
		failed += _err("auto-started d45_encounter should be in 'intro' stage")
	else:
		failed += _ok("advance_phase to D45 afternoon automatically starts d45_encounter intro (K-127)")

	# 2. 夜間定日遭遇：D8 傍晚 -> 夜間，play_night_fixed() 播文字、收費且自動啟動 n_manydoors_ch1 (K-126)
	_reset_gs(gs)
	gs.day = 8
	gs.phase = "evening"
	gs.advance_phase()
	if gs.phase != "night":
		failed += _err("phase should be 'night', got '%s'" % gs.phase)

	var madness_before := int(gs.get("_madness_counter"))
	var night_lines: PackedStringArray = gs.play_night_fixed()
	var madness_after := int(gs.get("_madness_counter"))

	if str(gs.active_encounter.get("beat_id", "")) != "n_manydoors_ch1":
		failed += _err("play_night_fixed on D8 should automatically start 'n_manydoors_ch1', got '%s'" % str(gs.active_encounter.get("beat_id", "")))
	elif str(gs.active_encounter.get("stage", "")) != "intro":
		failed += _err("auto-started n_manydoors_ch1 should be in 'intro' stage")
	elif madness_after - madness_before != 1:
		failed += _err("D8 night fixed should charge 1 madness card for first visit fee, got %d" % (madness_after - madness_before))
	elif not bool(gs.night_locations_seen.get("n_manydoors", false)):
		failed += _err("n_manydoors should be recorded into night_locations_seen")
	elif night_lines.is_empty():
		failed += _err("play_night_fixed should return beat text lines")
	else:
		failed += _ok("play_night_fixed on D8 correctly charges fee and automatically starts n_manydoors_ch1 encounter (K-126)")

	return failed


# ── 3. 遭遇進行中時段與各類操作阻擋 ──────────────────────────────────────────

func _test_mutation_blocking_during_encounter(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)

	var mock_enc: Dictionary = {
		"repeat_each_run": true,
		"per_round_slot_cost": 1,
		"escape_cost": null,
		"allow_discard": true,
		"after_finish": "stay",
		"rounds": [
			{
				"id": "r1",
				"demand": "需求",
				"responses": [{ "accepts": ["protagonist"], "next_round": null }],
				"fallback": { "requires_discardable": false, "next_round": null }
			}
		]
	}
	_create_mock_encounter_beat(data_node, "mock_enc_block", mock_enc)
	gs.start_encounter("mock_enc_block")

	# 1. advance_phase
	var res_adv: Dictionary = gs.advance_phase()
	if bool(res_adv.get("ok", true)) or str(res_adv.get("reason_code", "")) != "encounter_active" or bool(res_adv.get("phase_advanced", true)):
		failed += _err("advance_phase should be blocked with reason_code 'encounter_active'")
	else:
		failed += _ok("advance_phase is blocked during active encounter")

	# 2. try_place
	var res_place: Dictionary = gs.try_place("protagonist", "some_beat", "some_slot")
	if bool(res_place.get("ok", true)) or str(res_place.get("reason_code", "")) != "encounter_active":
		failed += _err("try_place should be blocked with reason_code 'encounter_active'")
	else:
		failed += _ok("try_place is blocked during active encounter")

	# 3. choose
	var res_choose: Dictionary = gs.choose("some_beat", "g1", "slot1", "protagonist")
	if bool(res_choose.get("ok", true)) or str(res_choose.get("reason_code", "")) != "encounter_active":
		failed += _err("choose should be blocked with reason_code 'encounter_active'")
	else:
		failed += _ok("choose is blocked during active encounter")

	# 4. delegate
	var res_del: Dictionary = gs.delegate("some_beat", "slot1", "protagonist")
	if bool(res_del.get("ok", true)) or str(res_del.get("reason_code", "")) != "encounter_active":
		failed += _err("delegate should be blocked with reason_code 'encounter_active'")
	else:
		failed += _ok("delegate is blocked during active encounter")

	# 5. indulge
	var res_ind: Dictionary = gs.indulge("some_beat", "slot1", "protagonist")
	if bool(res_ind.get("ok", true)) or str(res_ind.get("reason_code", "")) != "encounter_active":
		failed += _err("indulge should be blocked with reason_code 'encounter_active'")
	else:
		failed += _ok("indulge is blocked during active encounter")

	# 6. confirm_night_alignment
	var res_align: Dictionary = gs.confirm_night_alignment("sanquan")
	if bool(res_align.get("ok", true)) or str(res_align.get("reason_code", "")) != "encounter_active":
		failed += _err("confirm_night_alignment should be blocked with reason_code 'encounter_active'")
	else:
		failed += _ok("confirm_night_alignment is blocked during active encounter")

	# 7. enter_night_location
	gs.phase = "night"
	var res_night: Dictionary = gs.enter_night_location("sanquan_night")
	if bool(res_night.get("ok", true)) or str(res_night.get("reason_code", "")) != "encounter_active":
		failed += _err("enter_night_location should be blocked with reason_code 'encounter_active'")
	else:
		failed += _ok("enter_night_location is blocked during active encounter")

	# 8. 夜間推進（P5-D 起由 advance_phase() 吸收，沒有第二個入口）
	var res_night_adv: Dictionary = gs.advance_phase()
	if bool(res_night_adv.get("ok", true)) or str(res_night_adv.get("reason_code", "")) != "encounter_active":
		failed += _err("night advance_phase should be blocked with reason_code 'encounter_active'")
	else:
		failed += _ok("night advance_phase is blocked during active encounter")

	_clean_mock_beat(data_node, "mock_enc_block")
	return failed


# ── 4. 15 碼封閉拒絕矩陣驗證（比對 serialize 零變化，K-128）───────────────

func _test_15_code_rejection_matrix_zero_mutation(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)

	data_node.loader.cards["k_clue"] = { "id": "k_clue", "type": "knowledge", "slotless": true, "discardable": false }

	var mock_enc: Dictionary = {
		"repeat_each_run": true,
		"per_round_slot_cost": 1,
		"escape_cost": 1,
		"allow_discard": false,
		"after_finish": "stay",
		"rounds": [
			{
				"id": "r1",
				"demand": "需求",
				"responses": [{ "accepts": ["k_clue"], "next_round": null }],
				"fallback": { "requires_discardable": true, "next_round": null }
			}
		]
	}
	_create_mock_encounter_beat(data_node, "mock_enc_matrix", mock_enc)

	# Helper to test rejection and verify ZERO mutation
	var test_rej = func(endpoint_name: String, fn: Callable, expected_code: String) -> int:
		var ser_before: Dictionary = gs.serialize()
		var res: Dictionary = fn.call()
		if bool(res.get("ok", true)):
			return _err("%s should return ok:false" % endpoint_name)
		if str(res.get("reason_code", "")) != expected_code:
			return _err("%s expected '%s', got '%s'" % [endpoint_name, expected_code, str(res.get("reason_code", ""))])
		var ser_after: Dictionary = gs.serialize()
		if ser_before != ser_after:
			return _err("%s mutated state on rejection '%s' (K-128 violation)" % [endpoint_name, expected_code])
		return 0

	# 1. no_active_encounter across all 4 endpoints
	failed += test_rej.call("acknowledge_encounter_intro (inactive)", func(): return gs.acknowledge_encounter_intro(), "no_active_encounter")
	failed += test_rej.call("respond_to_encounter (inactive)", func(): return gs.respond_to_encounter("protagonist"), "no_active_encounter")
	failed += test_rej.call("discard_in_encounter (inactive)", func(): return gs.discard_in_encounter("protagonist"), "no_active_encounter")
	var esc_p: Array[String] = ["protagonist"]
	failed += test_rej.call("escape_encounter (inactive)", func(): return gs.escape_encounter(esc_p), "no_active_encounter")

	# 2. unknown_beat on start_encounter
	failed += test_rej.call("start_encounter (unknown beat)", func(): return gs.start_encounter("non_existent_beat_id"), "unknown_beat")

	# 3. data_conflict on start_encounter (corrupt encounter structure)
	var mock_bad_enc: Dictionary = { "per_round_slot_cost": 1, "after_finish": "stay" }
	_create_mock_encounter_beat(data_node, "mock_bad_enc", mock_bad_enc)
	failed += test_rej.call("start_encounter (bad rounds)", func(): return gs.start_encounter("mock_bad_enc"), "data_conflict")

	# Start valid encounter -> stage: "intro"
	gs.start_encounter("mock_enc_matrix")

	# 4. encounter_active on start_encounter
	failed += test_rej.call("start_encounter (active)", func(): return gs.start_encounter("mock_enc_matrix"), "encounter_active")

	# 5. wrong_stage during intro stage
	failed += test_rej.call("respond_to_encounter (in intro)", func(): return gs.respond_to_encounter("protagonist"), "wrong_stage")
	failed += test_rej.call("discard_in_encounter (in intro)", func(): return gs.discard_in_encounter("protagonist"), "wrong_stage")
	failed += test_rej.call("escape_encounter (in intro)", func(): return gs.escape_encounter(esc_p), "wrong_stage")

	# Acknowledge intro -> enter round 1
	gs.knowledge["k_clue"] = true
	gs.acknowledge_encounter_intro()

	# 6. wrong_stage (acknowledge during round stage)
	failed += test_rej.call("acknowledge_encounter_intro (in round)", func(): return gs.acknowledge_encounter_intro(), "wrong_stage")

	# 7. unknown_card
	mock_enc["allow_discard"] = true
	failed += test_rej.call("respond_to_encounter (unknown card)", func(): return gs.respond_to_encounter("totally_fake_card_id"), "unknown_card")
	failed += test_rej.call("discard_in_encounter (unknown card)", func(): return gs.discard_in_encounter("totally_fake_card_id"), "unknown_card")
	var esc_fake: Array[String] = ["totally_fake_card_id"]
	failed += test_rej.call("escape_encounter (unknown card)", func(): return gs.escape_encounter(esc_fake), "unknown_card")

	# 8. not_held
	failed += test_rej.call("respond_to_encounter (not held)", func(): return gs.respond_to_encounter("info_husband_version"), "not_held")
	failed += test_rej.call("discard_in_encounter (not held)", func(): return gs.discard_in_encounter("info_husband_version"), "not_held")
	var esc_unheld: Array[String] = ["info_husband_version"]
	failed += test_rej.call("escape_encounter (not held)", func(): return gs.escape_encounter(esc_unheld), "not_held")

	# 9. madness_blocked
	gs.gain_card("madness")
	var madness_inst: String = str(gs.hand[gs.hand.size() - 1])
	failed += test_rej.call("respond_to_encounter (madness)", func(): return gs.respond_to_encounter(madness_inst), "madness_blocked")

	# 10. card_not_submittable (fallback requires discardable, but protagonist is discardable: false)
	failed += test_rej.call("respond_to_encounter (not submittable)", func(): return gs.respond_to_encounter("protagonist"), "card_not_submittable")

	# 11. discard_disabled
	mock_enc["allow_discard"] = false
	failed += test_rej.call("discard_in_encounter (disabled)", func(): return gs.discard_in_encounter("protagonist"), "discard_disabled")

	# 12. not_discardable
	mock_enc["allow_discard"] = true
	failed += test_rej.call("discard_in_encounter (madness not discardable)", func(): return gs.discard_in_encounter(madness_inst), "not_discardable")
	failed += test_rej.call("discard_in_encounter (protagonist not discardable)", func(): return gs.discard_in_encounter("protagonist"), "not_discardable")
	var esc_mad: Array[String] = [madness_inst]
	var esc_prot: Array[String] = ["protagonist"]
	failed += test_rej.call("escape_encounter (madness not discardable)", func(): return gs.escape_encounter(esc_mad), "not_discardable")
	failed += test_rej.call("escape_encounter (protagonist not discardable)", func(): return gs.escape_encounter(esc_prot), "not_discardable")

	# 13. cannot_escape
	mock_enc["escape_cost"] = null
	failed += test_rej.call("escape_encounter (cannot escape)", func(): return gs.escape_encounter(esc_p), "cannot_escape")

	# 14. wrong_escape_count & duplicate_payment
	mock_enc["escape_cost"] = 2
	failed += test_rej.call("escape_encounter (wrong count)", func(): return gs.escape_encounter(esc_p), "wrong_escape_count")
	var esc_dup: Array[String] = ["protagonist", "protagonist"]
	failed += test_rej.call("escape_encounter (duplicate payment)", func(): return gs.escape_encounter(esc_dup), "duplicate_payment")

	# 15. already_attempted
	(gs.active_encounter["attempted_card_ids"] as Array).append("k_clue")
	failed += test_rej.call("respond_to_encounter (already attempted)", func(): return gs.respond_to_encounter("k_clue"), "already_attempted")

	_clean_mock_beat(data_node, "mock_enc_matrix")
	_clean_mock_beat(data_node, "mock_bad_enc")
	_clean_mock_cards(data_node, ["k_clue"])

	if failed == 0:
		failed += _ok("15-code rejection matrix with state zero-mutation serialize check verified (K-128)")
	return failed


# ── 5. 五大遭遇入口固定拒絕順序優先驗證（K-131）───────────────────────

func _test_rejection_priority_orders_all_endpoints(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)

	data_node.loader.cards["k_test_order"] = { "id": "k_test_order", "type": "knowledge", "slotless": true, "discardable": false }
	data_node.loader.cards["item_test_disc"] = { "id": "item_test_disc", "type": "item", "discardable": true }

	# ── Entry 1: start_encounter ──
	# encounter_active > unknown_beat (when encounter active and beat_id invalid)
	var enc_def: Dictionary = {
		"repeat_each_run": true, "per_round_slot_cost": 1, "escape_cost": null, "allow_discard": true, "after_finish": "stay",
		"rounds": [{ "id": "r1", "demand": "需求", "responses": [{ "accepts": ["k_test_order"], "next_round": null }], "fallback": { "requires_discardable": false, "next_round": null } }]
	}
	_create_mock_encounter_beat(data_node, "enc_prio_entry", enc_def)
	gs.start_encounter("enc_prio_entry")
	var r_start_prio: Dictionary = gs.start_encounter("non_existent_beat_id")
	if str(r_start_prio.get("reason_code", "")) != "encounter_active":
		failed += _err("start_encounter: encounter_active must take priority over unknown_beat")
	else:
		failed += _ok("start_encounter: encounter_active > unknown_beat verified")

	# ── Entry 2: acknowledge_encounter_intro ──
	_reset_gs(gs)
	# no_active_encounter > wrong_stage
	var r_ack_prio: Dictionary = gs.acknowledge_encounter_intro()
	if str(r_ack_prio.get("reason_code", "")) != "no_active_encounter":
		failed += _err("acknowledge: no_active_encounter must take priority over wrong_stage")
	else:
		failed += _ok("acknowledge_encounter_intro: no_active_encounter > wrong_stage verified")

	# ── Entry 3: respond_to_encounter ──
	gs.start_encounter("enc_prio_entry")
	gs.knowledge["k_test_order"] = true
	gs.acknowledge_encounter_intro() # enters round

	# madness_blocked > already_attempted
	gs.gain_card("madness")
	var m_inst: String = str(gs.hand[gs.hand.size() - 1])
	(gs.active_encounter["attempted_card_ids"] as Array).append("madness")
	var r_resp_mad_att: Dictionary = gs.respond_to_encounter(m_inst)
	if str(r_resp_mad_att.get("reason_code", "")) != "madness_blocked":
		failed += _err("respond_to_encounter: madness_blocked must take priority over already_attempted")
	else:
		failed += _ok("respond_to_encounter: madness_blocked > already_attempted verified")

	# already_attempted > card_not_submittable (K-131)
	enc_def["rounds"][0]["fallback"]["requires_discardable"] = true
	(gs.active_encounter["attempted_card_ids"] as Array).append("protagonist")
	var r_resp_att_sub: Dictionary = gs.respond_to_encounter("protagonist")
	if str(r_resp_att_sub.get("reason_code", "")) != "already_attempted":
		failed += _err("respond_to_encounter: already_attempted must take priority over card_not_submittable")
	else:
		failed += _ok("respond_to_encounter: already_attempted > card_not_submittable verified (K-131)")

	# ── Entry 4: discard_in_encounter ──
	enc_def["allow_discard"] = false
	# discard_disabled > unknown_card
	var r_disc_dis_unk: Dictionary = gs.discard_in_encounter("totally_fake_id")
	if str(r_disc_dis_unk.get("reason_code", "")) != "discard_disabled":
		failed += _err("discard_in_encounter: discard_disabled must take priority over unknown_card")
	else:
		failed += _ok("discard_in_encounter: discard_disabled > unknown_card verified")

	enc_def["allow_discard"] = true
	# unknown_card > not_held
	var r_disc_unk_held: Dictionary = gs.discard_in_encounter("totally_fake_id")
	if str(r_disc_unk_held.get("reason_code", "")) != "unknown_card":
		failed += _err("discard_in_encounter: unknown_card must take priority over not_held")
	else:
		failed += _ok("discard_in_encounter: unknown_card > not_held verified")

	data_node.loader.cards["item_test_nd"] = { "id": "item_test_nd", "type": "item", "discardable": false }

	# not_held > not_discardable
	var r_disc_held_nd: Dictionary = gs.discard_in_encounter("item_test_nd") # unheld non-discardable
	if str(r_disc_held_nd.get("reason_code", "")) != "not_held":
		failed += _err("discard_in_encounter: not_held must take priority over not_discardable")
	else:
		failed += _ok("discard_in_encounter: not_held > not_discardable verified")

	# ── Entry 5: escape_encounter ──
	enc_def["escape_cost"] = null
	# cannot_escape > wrong_escape_count
	var esc_p2: Array[String] = ["protagonist", "protagonist"]
	var r_esc_ce_cnt: Dictionary = gs.escape_encounter(esc_p2)
	if str(r_esc_ce_cnt.get("reason_code", "")) != "cannot_escape":
		failed += _err("escape_encounter: cannot_escape must take priority over wrong_escape_count")
	else:
		failed += _ok("escape_encounter: cannot_escape > wrong_escape_count verified")

	enc_def["escape_cost"] = 2
	# duplicate_payment > not_held (two identical unheld cards)
	var esc_dup_unheld: Array[String] = ["info_husband_version", "info_husband_version"]
	var r_esc_dup_held: Dictionary = gs.escape_encounter(esc_dup_unheld)
	if str(r_esc_dup_held.get("reason_code", "")) != "duplicate_payment":
		failed += _err("escape_encounter: duplicate_payment must take priority over not_held")
	else:
		failed += _ok("escape_encounter: duplicate_payment > not_held verified")

	# not_held > not_discardable (single unheld card when cost=1)
	enc_def["escape_cost"] = 1
	var esc_nd_unheld: Array[String] = ["item_test_nd"]
	var r_esc_held_nd: Dictionary = gs.escape_encounter(esc_nd_unheld)
	if str(r_esc_held_nd.get("reason_code", "")) != "not_held":
		failed += _err("escape_encounter: not_held must take priority over not_discardable")
	else:
		failed += _ok("escape_encounter: not_held > not_discardable verified")

	_clean_mock_beat(data_node, "enc_prio_entry")
	_clean_mock_cards(data_node, ["k_test_order", "item_test_disc", "item_test_nd"])
	return failed


# ── 6. encounter_view 候選完整性與答案不洩漏負向斷言（K-129）──────────────────

func _test_view_model_completeness_and_non_leakage(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)

	data_node.loader.cards["k_view_1"] = { "id": "k_view_1", "type": "knowledge", "name": "線索一", "slotless": true, "discardable": false }
	data_node.loader.cards["k_view_2"] = { "id": "k_view_2", "type": "knowledge", "name": "線索二", "slotless": true, "discardable": false }
	data_node.loader.cards["item_toy"] = { "id": "item_toy", "type": "item", "name": "玩具", "discardable": true }

	var enc_view_def: Dictionary = {
		"repeat_each_run": true, "per_round_slot_cost": 1, "escape_cost": 1, "allow_discard": true, "after_finish": "stay",
		"rounds": [
			{
				"id": "r1",
				"demand": "請出示線索一",
				"responses": [{ "accepts": ["k_view_1"], "consume_card": false, "next_round": "r2", "on_resolve": {} }],
				"fallback": { "requires_discardable": true, "next_round": null, "on_resolve": {} }
			},
			{
				"id": "r2",
				"demand": "請出示線索二",
				"responses": [{ "accepts": ["k_view_2"], "consume_card": false, "next_round": null, "on_resolve": {} }],
				"fallback": { "requires_discardable": false, "next_round": null, "on_resolve": {} }
			}
		],
		"on_victory": { "relation": { "npc": "ahong", "delta": 1 } }
	}
	_create_mock_encounter_beat(data_node, "mock_enc_view_test", enc_view_def)

	gs.knowledge["k_view_1"] = true
	gs.knowledge["k_view_2"] = true
	gs.hand.append("item_toy")

	gs.start_encounter("mock_enc_view_test")

	# 1. Intro 階段 key allowlist 驗證 (K-147)
	var intro_view: Dictionary = gs.encounter_view()
	var expected_intro_keys := ["stage", "beat_id", "blocked_slots", "capacity", "available_slots"]
	var intro_keys: Array = intro_view.keys()
	intro_keys.sort()
	var sorted_exp_intro := expected_intro_keys.duplicate()
	sorted_exp_intro.sort()
	if intro_keys != sorted_exp_intro:
		failed += _err("intro view keys do not match allowlist exactly: actual=%s, expected=%s (K-147)" % [str(intro_keys), str(sorted_exp_intro)])
	else:
		failed += _ok("intro view keys match allowlist exactly (K-147)")

	gs.acknowledge_encounter_intro()

	var view: Dictionary = gs.encounter_view()

	# 2. Round 階段 key allowlist 驗證 (K-147)
	var expected_round_keys := ["stage", "beat_id", "round_id", "demand", "blocked_slots", "capacity", "available_slots", "can_escape", "escape_cost", "allow_discard", "candidates", "attempted_card_ids"]
	var round_keys: Array = view.keys()
	round_keys.sort()
	var sorted_exp_round := expected_round_keys.duplicate()
	sorted_exp_round.sort()
	if round_keys != sorted_exp_round:
		failed += _err("round view keys do not match allowlist exactly: actual=%s, expected=%s (K-147)" % [str(round_keys), str(sorted_exp_round)])
	else:
		failed += _ok("round view keys match allowlist exactly (K-147)")

	# 正向驗證 view 欄位數值
	if str(view.get("stage", "")) != "round":
		failed += _err("view stage should be 'round'")
	if str(view.get("demand", "")) != "請出示線索一":
		failed += _err("view demand should be '請出示線索一', got '%s'" % str(view.get("demand", "")))
	if int(view.get("capacity", 0)) != 14:
		failed += _err("view capacity should be 14 (SSOT), got %d" % int(view.get("capacity", 0)))

	var candidates: Array = view.get("candidates", []) as Array
	# hand 含有 protagonist, item_toy; knowledge 含有 k_view_1, k_view_2 -> 共 4 張
	if candidates.size() != 4:
		failed += _err("view candidates size should be 4 (hand ∪ knowledge), got %d" % candidates.size())
	else:
		var found_sources: Dictionary = {}
		var expected_cand_keys := ["card_id", "base_id", "source", "name", "submittable", "disabled_reason", "discardable"]
		var sorted_exp_cand := expected_cand_keys.duplicate()
		sorted_exp_cand.sort()
		var cand_keys_ok := true
		for c in candidates:
			var c_dict := c as Dictionary
			found_sources[str(c_dict.get("source", ""))] = true
			var c_keys: Array = c_dict.keys()
			c_keys.sort()
			if c_keys != sorted_exp_cand:
				cand_keys_ok = false
				failed += _err("candidate view keys do not match allowlist exactly: actual=%s, expected=%s (K-147)" % [str(c_keys), str(sorted_exp_cand)])
				break
		if cand_keys_ok:
			if not found_sources.has("hand") or not found_sources.has("knowledge"):
				failed += _err("candidates must correctly distinguish 'hand' and 'knowledge' sources")
			else:
				failed += _ok("view candidates match allowlist and correctly distinguish 'hand' and 'knowledge' sources (K-129/K-147)")

	# 3. 負向：未到達的 r2 需求不能洩漏在 view 頂層
	if str(view.get("demand", "")).contains("線索二"):
		failed += _err("future round demand leaked in current round view (K-129)")
	else:
		failed += _ok("future round demand non-leakage negative assertion verified (K-129)")

	_clean_mock_beat(data_node, "mock_enc_view_test")
	_clean_mock_cards(data_node, ["k_view_1", "k_view_2", "item_toy"])
	return failed


# ── 7. 超載規則 ────────────────────────────────────────────────────────────

func _test_overload_and_penalty(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)

	data_node.loader.cards["k_clue"] = { "id": "k_clue", "type": "knowledge", "slotless": true, "discardable": false }
	var max_hand: int = int(data_node.tuning("hand_size", 14))

	# 1. is_overloaded 測試
	if gs.is_overloaded():
		failed += _err("is_overloaded should be false with 1 card")
	else:
		failed += _ok("is_overloaded false for hand <= %d" % max_hand)

	# 手牌填滿至 max_hand + 1 張（超載）
	var dummy_cards: Array[String] = []
	while gs.hand.size() <= max_hand:
		var dummy_id := "test_card_ov_%d" % gs.hand.size()
		data_node.loader.cards[dummy_id] = { "id": dummy_id, "type": "item", "discardable": false }
		dummy_cards.append(dummy_id)
		gs.hand.append(dummy_id)

	if not gs.is_overloaded():
		failed += _err("is_overloaded should be true with %d cards (hand_size=%d)" % [gs.hand.size(), max_hand])
	else:
		failed += _ok("is_overloaded true for hand > %d" % max_hand)

	# 2. 超載時進入夜間地點被阻擋（無遭遇時）
	gs.active_encounter.clear()
	gs.phase = "night"
	var res_loc_ov: Dictionary = gs.enter_night_location("sanquan_night")
	if str(res_loc_ov.get("reason_code", "")) != "overloaded":
		failed += _err("enter_night_location should return 'overloaded' when overloaded, got '%s'" % str(res_loc_ov))
	else:
		failed += _ok("enter_night_location correctly rejected with code 'overloaded'")

	# 3. 超載進入遭遇時，確認開場後立即走 failure 出口。
	# entered_round 是可觀測契約：明確超載分支回 false；若拿掉該分支、
	# 讓後續容量檢查代勞 failure，則會回 true，測試必須轉紅。
	gs.phase = "morning"
	var mock_enc: Dictionary = {
		"repeat_each_run": true,
		"per_round_slot_cost": 2,
		"escape_cost": null,
		"allow_discard": true,
		"after_finish": "stay",
		"rounds": [
			{
				"id": "r1",
				"demand": "需求",
				"responses": [{ "accepts": ["k_clue"], "next_round": null }],
				"fallback": { "requires_discardable": false, "next_round": null }
			}
		],
		"on_failure": { "switch_progress": { "overload_fail_count": 1 } }
	}
	_create_mock_encounter_beat(data_node, "mock_enc_ov", mock_enc)
	gs.switch_progress["overload_fail_count"] = 0
	gs.knowledge["k_clue"] = true

	# 斷言 1: start_encounter() 後仍停在 intro，尚未套 failure
	var start_res: Dictionary = gs.start_encounter("mock_enc_ov")
	if not bool(start_res.get("ok", false)) or str(gs.active_encounter.get("stage", "")) != "intro" or int(gs.switch_progress.get("overload_fail_count", 0)) != 0:
		failed += _err("start_encounter under overload should remain in intro stage with 0 failure effect")
	else:
		failed += _ok("start_encounter under overload stays in intro stage without premature failure")

	# 斷言 2 & 3: acknowledge 回 ok:true，且明示未進第一 round
	var res_ack_ov: Dictionary = gs.acknowledge_encounter_intro()
	if not bool(res_ack_ov.get("ok", false)) or bool(res_ack_ov.get("entered_round", true)):
		failed += _err("overloaded acknowledge should return ok:true and entered_round:false, got %s" % str(res_ack_ov))
	else:
		failed += _ok("overloaded acknowledge returns ok:true and entered_round:false")

	# 斷言 4 & 5 & 6: active encounter 已清空、可累加 failure 效果恰好套用一次、無殘留狀態
	if not gs.active_encounter.is_empty():
		failed += _err("active_encounter should be cleared immediately after overloaded failure settlement")
	elif int(gs.switch_progress.get("overload_fail_count", 0)) != 1:
		failed += _err("overloaded failure effect should apply exactly once (counter expected 1, got %d)" % int(gs.switch_progress.get("overload_fail_count", 0)))
	else:
		failed += _ok("overloaded acknowledge cleanly triggers failure effect exactly once without entering round or retaining active encounter")

	# 斷言 7: 非超載 acknowledge 仍只加第一 round 一次
	_clean_mock_cards(data_node, dummy_cards)
	while gs.hand.size() > 1:
		gs.hand.pop_back()
	if gs.is_overloaded():
		failed += _err("gs should not be overloaded after clearing dummy cards")

	gs.start_encounter("mock_enc_ov")
	var normal_ack: Dictionary = gs.acknowledge_encounter_intro()
	if not bool(normal_ack.get("ok", false)) or not bool(normal_ack.get("entered_round", false)) or str(gs.active_encounter.get("stage", "")) != "round" or int(gs.active_encounter.get("blocked_slots", 0)) != 2:
		failed += _err("normal non-overloaded acknowledge should return entered_round:true and enter round with exactly 1 round cost (blocked_slots=2, result=%s, state=%s)" % [str(normal_ack), str(gs.active_encounter)])
	else:
		failed += _ok("non-overloaded acknowledge enters round with single first-round cost")

	gs.active_encounter.clear()
	_clean_mock_beat(data_node, "mock_enc_ov")
	_clean_mock_cards(data_node, ["k_clue"])
	return failed


# ── 8. 佔格計算與扣除 ───────────────────────────────────────────────────────

func _test_slot_blocking_and_release(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)

	data_node.loader.cards["k_cure"] = { "id": "k_cure", "type": "knowledge", "slotless": true, "discardable": false }
	data_node.loader.cards["k_herb"] = { "id": "k_herb", "type": "knowledge", "slotless": true, "discardable": false }
	data_node.loader.cards["k_water"] = { "id": "k_water", "type": "knowledge", "slotless": true, "discardable": false }
	data_node.loader.cards["p_lan"] = { "id": "p_lan", "type": "person", "slotless": false, "discardable": false }

	var mock_enc: Dictionary = {
		"repeat_each_run": true,
		"per_round_slot_cost": 1,
		"escape_cost": null,
		"allow_discard": true,
		"after_finish": "stay",
		"rounds": [
			{
				"id": "r1",
				"demand": "需求1",
				"responses": [{ "accepts": ["k_cure"], "next_round": "r2" }],
				"fallback": { "requires_discardable": false, "next_round": "r2" }
			},
			{
				"id": "r2",
				"demand": "需求2",
				"responses": [{ "accepts": ["k_herb"], "next_round": "r3" }],
				"fallback": { "requires_discardable": false, "next_round": "r3" }
			},
			{
				"id": "r3",
				"demand": "需求3",
				"responses": [{ "accepts": ["k_water"], "next_round": null }],
				"fallback": { "requires_discardable": false, "next_round": null }
			}
		],
		"on_victory": { "flag": { "v_cleared": true } }
	}
	_create_mock_encounter_beat(data_node, "mock_enc_slots", mock_enc)
	gs.knowledge["k_cure"] = true
	gs.knowledge["k_water"] = true
	gs.hand.append("p_lan")

	gs.start_encounter("mock_enc_slots")
	gs.acknowledge_encounter_intro() # r1: blocked_slots = 1

	if int(gs.active_encounter.get("blocked_slots", 0)) != 1:
		failed += _err("r1 entry blocked_slots should be 1")

	# r1 正解 (k_cure) -> releases 1, enters r2 (+1) -> blocked_slots should be 1
	var r1_res: Dictionary = gs.respond_to_encounter("k_cure")
	if not bool(r1_res.get("ok", false)):
		failed += _err("r1 respond failed: %s" % str(r1_res))
	elif str(gs.active_encounter.get("round_id", "")) != "r2":
		failed += _err("should advance to r2")
	elif int(gs.active_encounter.get("blocked_slots", 0)) != 1:
		failed += _err("after r1 correct answer, blocked_slots should be 1, got %d" % int(gs.active_encounter.get("blocked_slots", 0)))
	else:
		failed += _ok("correct answer released round cost and added next round cost (blocked_slots=1)")

	# r2 錯答 (p_lan) -> retains 1, enters r3 (+1) -> blocked_slots should be 2
	var r2_res: Dictionary = gs.respond_to_encounter("p_lan")
	if not bool(r2_res.get("ok", false)):
		failed += _err("r2 respond failed: %s" % str(r2_res))
	elif str(gs.active_encounter.get("round_id", "")) != "r3":
		failed += _err("should advance to r3")
	elif int(gs.active_encounter.get("blocked_slots", 0)) != 2:
		failed += _err("after r2 fallback, blocked_slots should be 2, got %d" % int(gs.active_encounter.get("blocked_slots", 0)))
	else:
		failed += _ok("fallback retained round cost and added next round cost (blocked_slots=2)")

	_clean_mock_beat(data_node, "mock_enc_slots")
	_clean_mock_cards(data_node, ["k_cure", "k_herb", "k_water", "p_lan"])
	return failed


# ── 9. 主動丟棄與逃離遭遇 ───────────────────────────────────────────────────

func _test_discard_and_escape(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)

	data_node.loader.cards["k_cure"] = { "id": "k_cure", "type": "knowledge", "slotless": true, "discardable": false }
	data_node.loader.cards["item_leaf"] = { "id": "item_leaf", "type": "item", "discardable": true }
	data_node.loader.cards["item_stone"] = { "id": "item_stone", "type": "item", "discardable": true }

	gs.hand.append("item_leaf")
	gs.hand.append("item_stone")

	var mock_enc: Dictionary = {
		"repeat_each_run": true,
		"per_round_slot_cost": 1,
		"escape_cost": 1,
		"allow_discard": true,
		"after_finish": "stay",
		"rounds": [
			{
				"id": "r1",
				"demand": "需求",
				"responses": [{ "accepts": ["k_cure"], "next_round": null }],
				"fallback": { "requires_discardable": false, "next_round": null }
			}
		],
		"on_escape": { "flag": { "escaped_ok": true } }
	}
	_create_mock_encounter_beat(data_node, "mock_enc_disc_esc", mock_enc)
	gs.knowledge["k_cure"] = true

	gs.start_encounter("mock_enc_disc_esc")
	gs.acknowledge_encounter_intro()

	# 主動丟棄 item_leaf
	var res_disc: Dictionary = gs.discard_in_encounter("item_leaf")
	if not bool(res_disc.get("ok", false)):
		failed += _err("discard_in_encounter failed: %s" % str(res_disc))
	elif gs.has_card("item_leaf"):
		failed += _err("item_leaf should be lost after discard")
	elif int(gs.active_encounter.get("blocked_slots", 0)) != 1:
		failed += _err("blocked_slots should remain 1 after discard")
	elif str(gs.active_encounter.get("round_id", "")) != "r1":
		failed += _err("round_id should not advance on discard")
	else:
		failed += _ok("discard_in_encounter cleanly removed card without changing blocked_slots or round")

	# 逃離遭遇（支付 item_stone）
	var esc_payment: Array[String] = ["item_stone"]
	var res_esc: Dictionary = gs.escape_encounter(esc_payment)
	if not bool(res_esc.get("ok", false)):
		failed += _err("escape_encounter failed: %s" % str(res_esc))
	elif gs.has_card("item_stone"):
		failed += _err("item_stone should be lost after escape payment")
	elif not bool(gs.flags.get("escaped_ok", false)):
		failed += _err("on_escape effect should be applied")
	elif not gs.active_encounter.is_empty():
		failed += _err("active_encounter should be cleared after escape")
	else:
		failed += _ok("escape_encounter successfully paid cost, applied effect, and closed encounter")

	_clean_mock_beat(data_node, "mock_enc_disc_esc")
	_clean_mock_cards(data_node, ["k_cure", "item_leaf", "item_stone"])
	return failed


# ── 10. 無合法解自動結算 failure 與容量上限失敗 ─────────────────────────────

func _test_no_legal_moves_and_capacity_failure(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)

	data_node.loader.cards["k_clue"] = { "id": "k_clue", "type": "knowledge", "slotless": true, "discardable": false }

	# 1. 無合法動作自動結算 failure
	var mock_enc_no_legal: Dictionary = {
		"repeat_each_run": true, "per_round_slot_cost": 1, "escape_cost": null, "allow_discard": false, "after_finish": "stay",
		"rounds": [
			{
				"id": "r1", "demand": "需求",
				"responses": [{ "accepts": ["k_clue"], "next_round": null }],
				"fallback": { "requires_discardable": true, "next_round": null }
			}
		],
		"on_failure": { "flag": { "no_legal_failed": true } }
	}
	_create_mock_encounter_beat(data_node, "mock_enc_no_legal", mock_enc_no_legal)

	gs.start_encounter("mock_enc_no_legal")
	var res_ack_nl: Dictionary = gs.acknowledge_encounter_intro()

	if not bool(gs.flags.get("no_legal_failed", false)):
		failed += _err("acknowledge_encounter_intro should auto-fail when player has no legal moves")
	elif not gs.active_encounter.is_empty():
		failed += _err("active_encounter should be cleared after failure")
	else:
		failed += _ok("no legal moves triggers immediate auto-failure settlement")

	# 2. 容量上限失敗結算
	_reset_gs(gs)
	var max_hand: int = int(data_node.tuning("hand_size", 14))
	var dummy_cards: Array[String] = []
	while gs.hand.size() < max_hand - 1:
		var dummy_id := "test_c_cap_%d" % gs.hand.size()
		data_node.loader.cards[dummy_id] = { "id": dummy_id, "type": "item", "discardable": false }
		dummy_cards.append(dummy_id)
		gs.hand.append(dummy_id)

	var mock_enc_cap: Dictionary = {
		"repeat_each_run": true, "per_round_slot_cost": 2, "escape_cost": null, "allow_discard": true, "after_finish": "stay",
		"rounds": [
			{
				"id": "r1", "demand": "需求",
				"responses": [{ "accepts": ["k_clue"], "next_round": null }],
				"fallback": { "requires_discardable": false, "next_round": null }
			}
		],
		"on_failure": { "flag": { "cap_failed": true } }
	}
	_create_mock_encounter_beat(data_node, "mock_enc_cap", mock_enc_cap)
	gs.knowledge["k_clue"] = true

	gs.start_encounter("mock_enc_cap")
	var res_ack_cap: Dictionary = gs.acknowledge_encounter_intro()

	if not bool(gs.flags.get("cap_failed", false)):
		failed += _err("capacity exhaustion should trigger auto failure")
	elif not gs.active_encounter.is_empty():
		failed += _err("active_encounter should be cleared after capacity failure")
	else:
		failed += _ok("capacity exhaustion correctly triggers auto-failure")

	_clean_mock_beat(data_node, "mock_enc_no_legal")
	_clean_mock_beat(data_node, "mock_enc_cap")
	_clean_mock_cards(data_node, dummy_cards)
	_clean_mock_cards(data_node, ["k_clue"])
	return failed


# ── 11. 遭遇勝利效果套用與行動狀態不變性（K-140/K-141）───────────────────────

func _test_victory_effects_and_action_immutability(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)

	data_node.loader.cards["k_cure_v"] = { "id": "k_cure_v", "type": "knowledge", "slotless": true, "discardable": false }
	data_node.loader.cards["item_reward_leaf"] = { "id": "item_reward_leaf", "type": "item", "discardable": true }

	# 勝利給予累加型效果：relation delta +3 且 gain 一張 item_reward_leaf (K-140)
	var mock_enc_vic: Dictionary = {
		"repeat_each_run": true, "per_round_slot_cost": 1, "escape_cost": null, "allow_discard": true, "after_finish": "stay",
		"rounds": [
			{
				"id": "r1", "demand": "需求",
				"responses": [{ "accepts": ["k_cure_v"], "next_round": null }],
				"fallback": { "requires_discardable": false, "next_round": null }
			}
		],
		"on_victory": {
			"relation": { "npc": "ahong", "delta": 3 },
			"gain": ["item_reward_leaf"]
		}
	}
	_create_mock_encounter_beat(data_node, "mock_enc_vic", mock_enc_vic)
	gs.knowledge["k_cure_v"] = true
	gs.relations["ahong"] = 0

	# 記錄前置狀態（驗證遭遇不消耗 action_spent、不開縱慾與備用區，K-141）
	var action_before: bool = gs.action_spent
	var ind_before: int = gs.indulgence_count
	var forced_before_size: int = gs.forced_pending.size()

	gs.start_encounter("mock_enc_vic")
	gs.acknowledge_encounter_intro()

	var win_res: Dictionary = gs.respond_to_encounter("k_cure_v")
	if not bool(win_res.get("ok", false)):
		failed += _err("respond_to_encounter failed: %s" % str(win_res))
	elif int(gs.relations.get("ahong", 0)) != 3:
		failed += _err("relation delta should be exactly +3 (applied once), got %d (K-140)" % int(gs.relations.get("ahong", 0)))
	elif not gs.has_card("item_reward_leaf"):
		failed += _err("item_reward_leaf should be gained on victory")
	else:
		failed += _ok("encounter victory effect applied exactly once with cumulative assertions (K-140)")

	# 斷言行動格、縱慾、備用區零變化 (K-141)
	if gs.action_spent != action_before:
		failed += _err("encounter must not modify action_spent (K-141)")
	elif gs.indulgence_count != ind_before:
		failed += _err("encounter must not modify indulgence_count (K-141)")
	elif gs.forced_pending.size() != forced_before_size:
		failed += _err("encounter must not modify forced_pending (K-141)")
	else:
		failed += _ok("encounter lifecycle verified to not consume action or trigger indulgence/pending (K-141)")

	_clean_mock_beat(data_node, "mock_enc_vic")
	_clean_mock_cards(data_node, ["k_cure_v", "item_reward_leaf"])
	return failed


# ── 12. 遭遇結束推進（stay vs advance_phase，K-130）─────────────────────────

func _test_after_finish_stay_and_advance(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)

	data_node.loader.cards["k_sol"] = { "id": "k_sol", "type": "knowledge", "slotless": true, "discardable": false }

	# 1. after_finish: "advance_phase"
	var mock_enc_adv: Dictionary = {
		"repeat_each_run": true, "per_round_slot_cost": 1, "escape_cost": null, "allow_discard": true, "after_finish": "advance_phase",
		"rounds": [{ "id": "r1", "demand": "需求", "responses": [{ "accepts": ["k_sol"], "next_round": null }], "fallback": { "requires_discardable": false, "next_round": null } }],
		"on_victory": {}
	}
	_create_mock_encounter_beat(data_node, "mock_enc_adv", mock_enc_adv)
	gs.knowledge["k_sol"] = true
	gs.day = 10
	gs.phase = "morning"

	gs.start_encounter("mock_enc_adv")
	gs.acknowledge_encounter_intro()
	gs.respond_to_encounter("k_sol")

	if gs.day != 10 or gs.phase != "afternoon":
		failed += _err("after_finish: 'advance_phase' should advance phase from morning to afternoon on day 10, got day=%d, phase=%s" % [gs.day, gs.phase])
	else:
		failed += _ok("after_finish: 'advance_phase' correctly advanced phase to afternoon (K-130)")

	# 2. after_finish: "stay" (K-130)
	var mock_enc_stay: Dictionary = {
		"repeat_each_run": true, "per_round_slot_cost": 1, "escape_cost": null, "allow_discard": true, "after_finish": "stay",
		"rounds": [{ "id": "r1", "demand": "需求", "responses": [{ "accepts": ["k_sol"], "next_round": null }], "fallback": { "requires_discardable": false, "next_round": null } }],
		"on_victory": {}
	}
	_create_mock_encounter_beat(data_node, "mock_enc_stay", mock_enc_stay)
	gs.day = 20
	gs.phase = "afternoon"

	gs.start_encounter("mock_enc_stay")
	gs.acknowledge_encounter_intro()
	gs.respond_to_encounter("k_sol")

	if gs.day != 20 or gs.phase != "afternoon":
		failed += _err("after_finish: 'stay' should stay on day 20 afternoon, got day=%d, phase=%s (K-130)" % [gs.day, gs.phase])
	else:
		failed += _ok("after_finish: 'stay' correctly remained on current day and phase (K-130)")

	# 3. after_finish: "advance_phase" with ending_madness_be (K-133 regression: generation guard prevents advance on reset)
	var mock_enc_be: Dictionary = {
		"repeat_each_run": true, "per_round_slot_cost": 1, "escape_cost": null, "allow_discard": true, "after_finish": "advance_phase",
		"rounds": [{ "id": "r1", "demand": "需求", "responses": [{ "accepts": ["k_sol"], "next_round": null }], "fallback": { "requires_discardable": false, "next_round": null } }],
		"on_victory": { "gain": ["madness", "madness", "madness", "madness", "madness", "madness", "madness"] }
	}
	_create_mock_encounter_beat(data_node, "mock_enc_be", mock_enc_be)
	gs.day = 15
	gs.phase = "afternoon"
	gs.start_encounter("mock_enc_be")
	gs.acknowledge_encounter_intro()
	gs.respond_to_encounter("k_sol")

	# P5-B：撞 cap 改為啟動 ending_madness_be，出口守衛必須擋掉 after_finish 的額外推進，
	# day／phase 停在原地（不再有 run_reset 的重置）。
	if gs.day != 15 or gs.phase != "afternoon" or str(gs.get("flow_mode")) != "ending":
		failed += _err("K-133 regression: BE 啟動後不得再推進時段，got day=%d, phase=%s, mode=%s" % [gs.day, gs.phase, str(gs.get("flow_mode"))])
	else:
		failed += _ok("K-133 regression: 結局啟動後守衛正確阻止 after_finish 的 advance_phase (K-133)")
	PlaythroughGreedy.start_fresh_run(gs)

	_clean_mock_beat(data_node, "mock_enc_adv")
	_clean_mock_beat(data_node, "mock_enc_stay")
	_clean_mock_beat(data_node, "mock_enc_be")
	_clean_mock_cards(data_node, ["k_sol"])
	return failed


# ── 13. 回合循環偵測防禦（K-134）───────────────────────────────────────────

func _test_cycle_detection(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)

	data_node.loader.cards["k_cycle_a"] = { "id": "k_cycle_a", "type": "knowledge", "slotless": true, "discardable": false }
	data_node.loader.cards["k_cycle_b"] = { "id": "k_cycle_b", "type": "knowledge", "slotless": true, "discardable": false }

	# 定義帶有 cycle 的惡意遭遇：r1 -> r2 -> r1 (K-134)
	var mock_enc_cycle: Dictionary = {
		"repeat_each_run": true, "per_round_slot_cost": 1, "escape_cost": null, "allow_discard": true, "after_finish": "stay",
		"rounds": [
			{
				"id": "r1", "demand": "需求1",
				"responses": [{ "accepts": ["k_cycle_a"], "next_round": "r2" }],
				"fallback": { "requires_discardable": false, "next_round": "r2" }
			},
			{
				"id": "r2", "demand": "需求2",
				"responses": [{ "accepts": ["k_cycle_b"], "next_round": "r1" }], # 指回已訪問的 r1
				"fallback": { "requires_discardable": false, "next_round": "r1" }
			}
		],
		"on_failure": { "flag": { "cycle_caught": true } }
	}
	_create_mock_encounter_beat(data_node, "mock_enc_cycle", mock_enc_cycle)
	gs.knowledge["k_cycle_a"] = true
	gs.knowledge["k_cycle_b"] = true

	gs.start_encounter("mock_enc_cycle")
	gs.acknowledge_encounter_intro() # enters r1, visited=[r1]

	# r1 -> r2 (valid move)
	var res_r1: Dictionary = gs.respond_to_encounter("k_cycle_a")
	if not bool(res_r1.get("ok", false)) or str(gs.active_encounter.get("round_id", "")) != "r2":
		failed += _err("advance to r2 should succeed")

	# r2 -> r1 (cycle back to r1: caught by runtime guard, settled as failure with ok: true, K-146)
	var res_r2: Dictionary = gs.respond_to_encounter("k_cycle_b")
	if not bool(res_r2.get("ok", false)):
		failed += _err("re-entering visited round r1 should settle as failure with ok: true (K-146), got %s" % str(res_r2))
	elif not gs.active_encounter.is_empty():
		failed += _err("encounter should be closed after cycle failure")
	elif not bool(gs.flags.get("cycle_caught", false)):
		failed += _err("on_failure effect should be applied on cycle failure")
	else:
		failed += _ok("round graph cycle correctly detected and settled as failure with ok: true (K-146)")

	_clean_mock_beat(data_node, "mock_enc_cycle")
	_clean_mock_cards(data_node, ["k_cycle_a", "k_cycle_b"])
	return failed


# ── 14. 序列化往返與未存檔對照組逐字比對（K-139）───────────────────────────

func _test_serialization_roundtrip_with_control(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)

	data_node.loader.cards["k_ser_a"] = { "id": "k_ser_a", "type": "knowledge", "slotless": true, "discardable": false }
	data_node.loader.cards["k_ser_b"] = { "id": "k_ser_b", "type": "knowledge", "slotless": true, "discardable": false }
	data_node.loader.cards["item_ser_pay"] = { "id": "item_ser_pay", "type": "item", "discardable": true }

	var mock_enc_ser: Dictionary = {
		"repeat_each_run": true, "per_round_slot_cost": 1, "escape_cost": 1, "allow_discard": true, "after_finish": "stay",
		"rounds": [
			{
				"id": "r1", "demand": "需求1",
				"responses": [{ "accepts": ["k_ser_a"], "next_round": "r2" }],
				"fallback": { "requires_discardable": false, "next_round": "r2" }
			},
			{
				"id": "r2", "demand": "需求2",
				"responses": [{ "accepts": ["k_ser_b"], "next_round": null }],
				"fallback": { "requires_discardable": false, "next_round": null }
			}
		],
		"on_escape": { "flag": { "ser_escaped": true } }
	}
	_create_mock_encounter_beat(data_node, "mock_enc_ser_ctrl", mock_enc_ser)

	# ── 對照組 A（未存檔路徑）──
	_reset_gs(gs)
	gs.knowledge["k_ser_a"] = true
	gs.knowledge["k_ser_b"] = true
	gs.hand.append("item_ser_pay")

	gs.start_encounter("mock_enc_ser_ctrl")
	gs.acknowledge_encounter_intro()
	# 藉由真實 respond 產生 attempted 記錄
	gs.respond_to_encounter("protagonist") # fallback to r2
	var final_state_a: Dictionary = gs.serialize()

	# ── 實驗組 B（存檔→重置→讀檔路徑）──
	_reset_gs(gs)
	gs.knowledge["k_ser_a"] = true
	gs.knowledge["k_ser_b"] = true
	gs.hand.append("item_ser_pay")

	gs.start_encounter("mock_enc_ser_ctrl")
	gs.acknowledge_encounter_intro()
	gs.respond_to_encounter("protagonist") # fallback to r2

	var checkpoint: Dictionary = gs.serialize()
	_reset_gs(gs) # 徹底乾淨重置
	gs.deserialize(checkpoint)
	var final_state_b: Dictionary = gs.serialize()

	if final_state_a != final_state_b:
		failed += _err("deserialized state does not match unsaved control group (K-139)")
	else:
		failed += _ok("serialization roundtrip exactly matches unsaved control group (K-139)")

	_clean_mock_beat(data_node, "mock_enc_ser_ctrl")
	_clean_mock_cards(data_node, ["k_ser_a", "k_ser_b", "item_ser_pay"])
	return failed


# ── 15. 故事線真實遭遇路徑驗證（K-138）─────────────────────────────────────

func _test_storyline_encounters_contract(gs: Node, data_node: Node) -> int:
	var failed: int = 0

	# 1. D8: n_manydoors_ch1 完整生命週期與多回合推進
	_reset_gs(gs)
	var fugu_beat: Dictionary = data_node.loader.beats_by_id.get("n_manydoors_ch1", {}) as Dictionary
	if fugu_beat.is_empty():
		failed += _err("n_manydoors_ch1 beat missing from loader")
		return failed

	gs.knowledge["k_not_today"] = true
	gs.day = 8
	gs.phase = "night"
	var night_lines: PackedStringArray = gs.play_night_fixed()
	if str(gs.active_encounter.get("beat_id", "")) != "n_manydoors_ch1":
		failed += _err("n_manydoors_ch1 failed to start via play_night_fixed")

	var r_ack: Dictionary = gs.acknowledge_encounter_intro()
	if not bool(r_ack.get("ok", false)) or str(gs.active_encounter.get("round_id", "")) != "name_since_when":
		failed += _err("n_manydoors_ch1 acknowledge failed to enter round 1")
	else:
		failed += _ok("n_manydoors_ch1 correctly entered round 1 ('name_since_when')")

	# 2. D45: d45_encounter 完整生命週期
	_reset_gs(gs)
	gs.day = 45
	gs.phase = "morning"
	gs.flags["final_day"] = true
	gs.advance_phase()

	if str(gs.active_encounter.get("beat_id", "")) != "d45_encounter":
		failed += _err("d45_encounter failed to start on D45 afternoon")

	var r_ack_d45: Dictionary = gs.acknowledge_encounter_intro()
	if not bool(r_ack_d45.get("ok", false)) or str(gs.active_encounter.get("round_id", "")) != "final_demand":
		failed += _err("d45_encounter acknowledge failed to enter 'final_demand'")
	else:
		failed += _ok("d45_encounter correctly entered 'final_demand' on real data path")

	# 3. 完整走通 d45_encounter
	var res_d45_win: Dictionary = gs.respond_to_encounter("protagonist")
	if not bool(res_d45_win.get("ok", false)):
		failed += _err("d45_encounter protagonist respond failed: %s" % str(res_d45_win))
	elif not gs.active_encounter.is_empty():
		failed += _err("d45_encounter should be finished after protagonist response")
	else:
		failed += _ok("d45_encounter complete victory path verified on real data (K-138)")

	return failed


# ── 16. 夜間 fixed 迴圈於遭遇啟動後停播 ─────────────────────────────────────

## play_night_fixed() 啟動遭遇後必須 break，與 _check_fixed_encounter_for_current_phase()
## 的白天路徑一致。少了 break 時，同夜排在遭遇之後的 fixed beat 仍會被 play_beat()，
## 於是遭遇畫面已開、底下還附加下一段旁白。正式資料第 8 天夜間只有 n_manydoors_ch1
## 一個 fixed beat，所以這條要靠注入第二個 fixed beat 才觀測得到。
func _test_night_fixed_stops_after_encounter(gs: Node, data_node: Node) -> int:
	print("--- 16. 夜間遭遇啟動後停播同夜後續 fixed beat ---")
	var failed: int = 0
	var mock_id := "mock_night_after_encounter"
	var mock_text := "MOCK_LINE_AFTER_ENCOUNTER"
	var mock_beat: Dictionary = {
		"id": mock_id,
		"location": "sanquan",
		"fixed": true,
		"when": { "day": 8, "phase": "night" },
		"text": mock_text,
	}

	# 附加在 beats 陣列尾端，確保迭代順序排在真實的 n_manydoors_ch1 之後
	var beats_arr: Array = data_node.loader.beats
	beats_arr.append(mock_beat)
	data_node.loader.beats_by_id[mock_id] = mock_beat

	_reset_gs(gs)
	gs.day = 8
	gs.phase = "evening"
	gs.advance_phase()

	var night_lines: PackedStringArray = gs.play_night_fixed()
	var joined := "
".join(night_lines)

	if str(gs.active_encounter.get("beat_id", "")) != "n_manydoors_ch1":
		failed += _err("前置條件不成立：D8 入夜未自動啟動 n_manydoors_ch1，實際 '%s'" % str(gs.active_encounter.get("beat_id", "")))
	elif joined.contains(mock_text):
		failed += _err("遭遇啟動後仍播出同夜後續 fixed beat 的文字（play_night_fixed 缺 break）")
	elif bool(gs.beats_entered.get(mock_id, false)):
		failed += _err("遭遇啟動後仍把同夜後續 fixed beat 寫進 beats_entered（play_night_fixed 缺 break）")
	else:
		failed += _ok("play_night_fixed 啟動遭遇後停止播出同夜後續 fixed beat，與白天 hook 對齊")

	# 還原注入（fixture 隔離，守則 7）
	beats_arr.erase(mock_beat)
	_clean_mock_beat(data_node, mock_id)

	if data_node.loader.beats_by_id.has(mock_id) or beats_arr.has(mock_beat):
		failed += _err("mock beat 未完整還原，會污染後續測試")

	return failed
