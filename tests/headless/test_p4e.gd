extends SceneTree

const PlaythroughGreedy := preload("res://tests/headless/playthrough_greedy.gd")

func _initialize() -> void:
	var data_node: Node = PlaythroughGreedy.setup_data(self)
	var gs: Node = PlaythroughGreedy.setup_game_state(self, data_node)
	
	await process_frame
	
	if not bool(data_node.get("ok")):
		push_error("P4-E: Data failed to load; abort")
		quit(1)
		return
		
	var failed: int = 0
	print("\n=== P4-E 遭遇 UI 與規則整合測試 ===")
	
	failed += _test_1_view_safety_and_non_leakage(gs, data_node)
	failed += _test_2_d8_lifecycle(gs, data_node)
	failed += _test_3_candidate_disabled_states(gs, data_node)
	failed += _test_4_charge_first_visit_real_end_run(gs, data_node)
	failed += _test_5_three_round_paths(gs, data_node)
	failed += _test_6_d8_escape(gs, data_node)
	failed += _test_7_d8_discard(gs, data_node)
	failed += _test_8_d45_no_escape_no_discard_rejection_codes(gs, data_node)
	failed += _test_9_d45_response_paths_and_cards_retained(gs, data_node)
	failed += _test_10_d45_after_finish(gs, data_node)
	failed += _test_11_serialization_roundtrip(gs, data_node)
	failed += _test_12_d8_night_actions_blocked_and_protagonist_not_consumed(gs, data_node)
	failed += _test_13_d8_zero_discardable_direct_failure(gs, data_node)
	failed += _test_14_d8_knowledge_overwrites_round_1(gs, data_node)
	failed += _test_15_d8_win_lose_return_to_night_end(gs, data_node)
	
	if failed > 0:
		push_error("\nP4-E: %d assertion(s) failed\n" % failed)
		quit(1)
	else:
		print("\nP4-E: all tests passed\n")
		quit(0)

func _ok(msg: String) -> int:
	print("  [OK] %s" % msg)
	return 0

func _err(msg: String) -> int:
	push_error("  [FAIL] %s" % msg)
	return 1

func _reset_gs(gs: Node) -> void:
	gs.end_run("test_reset")
	gs.day = 1
	gs.phase = "morning"
	gs.hand.clear()
	gs.hand.append("protagonist")
	gs.knowledge.clear()
	gs.flags.clear()
	gs.active_encounter.clear()
	gs.night_locations_seen.clear()

func _setup_gs_for_d8(gs: Node, setup_hand: bool = true) -> void:
	_reset_gs(gs)
	gs.day = 8
	gs.phase = "night"
	if setup_hand:
		gs.gain_card("equip_polaroid") # discardable
		gs.gain_card("info_chunama_pause") # knowledge (slotless)
		gs.gain_card("routine_debt") # item (not discardable, but accepted)
	gs.play_night_fixed()

func _setup_gs_for_d45(gs: Node) -> void:
	_reset_gs(gs)
	gs.day = 45
	gs.phase = "morning"
	gs.flags["final_day"] = true
	gs.advance_phase() # to afternoon, triggers D45 encounter

func _test_1_view_safety_and_non_leakage(gs: Node, _data_node: Node) -> int:
	var failed: int = 0
	_setup_gs_for_d8(gs)
	gs.acknowledge_encounter_intro()
	
	var view: Dictionary = gs.encounter_view()
	if str(view.get("stage", "")) != "round":
		failed += _err("View stage should be 'round'")
	
	if view.has("accepts"):
		failed += _err("View should NOT leak 'accepts' array")
	if view.has("next_round"):
		failed += _err("View should NOT leak 'next_round' information")
		
	var required_keys := ["demand", "candidates", "blocked_slots", "available_slots", "capacity", "can_escape", "allow_discard", "stage"]
	for k in required_keys:
		if not view.has(k):
			failed += _err("View is missing required key '%s'" % k)
			
	var candidates: Array = view.get("candidates", [])
	for c in candidates:
		if c is Dictionary and (c as Dictionary).has("accepts"):
			failed += _err("Candidate should NOT leak 'accepts' information")
			
	if failed == 0:
		failed += _ok("View model safety and non-leakage verified")
	return failed

func _test_2_d8_lifecycle(gs: Node, _data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)
	gs.day = 8
	gs.phase = "night"
	gs.gain_card("equip_polaroid") # legal move for R1
	gs.play_night_fixed()
	
	var view1: Dictionary = gs.encounter_view()
	if str(view1.get("stage", "")) != "intro":
		failed += _err("D8 encounter should start in 'intro' stage")
	
	gs.acknowledge_encounter_intro()
	
	var view2: Dictionary = gs.encounter_view()
	if str(view2.get("stage", "")) != "round":
		failed += _err("D8 encounter should transition to 'round' stage")
	
	if not "那個名字什麼時候開始是你的？" in str(view2.get("demand", "")):
		failed += _err("Demand does not match first round of D8 encounter")
		
	if failed == 0:
		failed += _ok("D8 intro -> acknowledge -> round lifecycle verified")
	return failed

func _test_3_candidate_disabled_states(gs: Node, _data_node: Node) -> int:
	var failed: int = 0
	_setup_gs_for_d8(gs, true)
	gs.gain_card("madness")
	gs.knowledge["k_not_today"] = true
	gs.acknowledge_encounter_intro()
	
	var view: Dictionary = gs.encounter_view()
	var madness_found := false
	for c in view.get("candidates", []):
		if c.get("base_id", "") == "madness":
			madness_found = true
			if str(c.get("disabled_reason", "")) != "madness_blocked":
				failed += _err("Madness card disabled_reason should be 'madness_blocked'")
			if c.get("submittable", true):
				failed += _err("Madness card should not be submittable")
	
	if not madness_found:
		failed += _err("Madness card not found in candidates")
		
	# Submit k_not_today in R1 (consume_card: false), advances to R2
	var _res = gs.respond_to_encounter("k_not_today")
	
	view = gs.encounter_view()
	var k_found := false
	for c in view.get("candidates", []):
		if c.get("base_id", "") == "k_not_today":
			k_found = true
			if str(c.get("disabled_reason", "")) != "already_attempted":
				failed += _err("Attempted card disabled_reason should be 'already_attempted', got '%s'" % c.get("disabled_reason"))
			if c.get("submittable", true):
				failed += _err("Attempted card should not be submittable")
				
	if not k_found:
		failed += _err("Attempted card not found in candidates")
		
	if failed == 0:
		failed += _ok("Candidate disabled states (madness_blocked, already_attempted) verified")
	return failed

func _test_4_charge_first_visit_real_end_run(gs: Node, _data_node: Node) -> int:
	var failed: int = 0
	# 第一輪：走真實流程進 D8，收費 1 點瘋狂值並寫入 night_locations_seen
	_reset_gs(gs)
	gs.day = 8
	gs.phase = "night"
	
	var initial_madness = int(gs.get("_madness_counter"))
	gs.play_night_fixed()
	var madness_after_first = int(gs.get("_madness_counter"))
	
	if madness_after_first - initial_madness != 1:
		failed += _err("First visit should charge madness cost")
		
	# 走真實 end_run() 跨輪，不手動注入 seen
	gs.end_run("truth")
	if not gs.night_locations_seen.has("n_manydoors"):
		failed += _err("night_locations_seen should persist across end_run in meta")
		
	# 第二輪：推進至 D8 夜間，驗證 play_night_fixed() 不再重收費
	gs.day = 8
	gs.phase = "night"
	var madness_before_second = int(gs.get("_madness_counter"))
	gs.play_night_fixed()
	var madness_after_second = int(gs.get("_madness_counter"))
	
	if madness_after_second != madness_before_second:
		failed += _err("Second run D8 visit should NOT charge madness cost via real end_run")
		
	if failed == 0:
		failed += _ok("D8 charge_first_visit via real end_run verified")
	return failed

func _test_5_three_round_paths(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	# Victory Path
	_setup_gs_for_d8(gs, true)
	gs.acknowledge_encounter_intro()
	
	# R1: equip_polaroid (fallback, next_round: who_remembers)
	gs.respond_to_encounter("equip_polaroid")
	
	var r2_view = gs.encounter_view()
	if not "誰記得你" in str(r2_view.get("demand", "")):
		failed += _err("Did not reach R2 'who_remembers'")
		
	# R2: info_chunama_pause (accepts, next_round: what_remains)
	gs.respond_to_encounter("info_chunama_pause")
	
	var r3_view = gs.encounter_view()
	if not "那你留下什麼" in str(r3_view.get("demand", "")):
		failed += _err("Did not reach R3 'what_remains'")
		
	# R3: routine_debt (accepts, next_round: null -> victory)
	gs.respond_to_encounter("routine_debt")
	
	if not gs.active_encounter.is_empty():
		failed += _err("Encounter should be ended after R3 victory")
	if not gs.flags.get("d8_encounter_victory", false):
		failed += _err("d8_encounter_victory flag should be set")
		
	# Failure Path (Capacity limit upon entry into round)
	var orig_cards: Dictionary = data_node.loader.cards.duplicate(true)
	_setup_gs_for_d8(gs, false) # hand has protagonist + 1 madness = 2 cards.
	var max_hand: int = int(data_node.tuning("hand_size", 14))
	while gs.hand.size() < max_hand - 2:
		var dummy_id = "dummy_%d" % gs.hand.size()
		data_node.loader.cards[dummy_id] = { "id": dummy_id, "type": "item", "discardable": false }
		gs.hand.append(dummy_id)
	# Add one discardable card:
	data_node.loader.cards["dummy_disc"] = { "id": "dummy_disc", "type": "item", "discardable": true }
	gs.hand.append("dummy_disc") # hand.size() = 13 (12 non-discardable + 1 discardable)
	
	gs.acknowledge_encounter_intro() # enters R1 (cost 1 slot). hand (13) + blocked (1) = 14 = capacity limit -> failure
	
	# Cleanly restore loader cards immediately (實作守則 7)
	data_node.loader.cards = orig_cards
	
	if not gs.active_encounter.is_empty():
		failed += _err("Encounter should fail due to overload capacity upon entering R1")
	if not gs.flags.get("d8_encounter_failure", false):
		failed += _err("d8_encounter_failure flag should be set")
		
	if failed == 0:
		failed += _ok("D8 three-round paths (victory and capacity failure) verified")
	return failed

func _test_6_d8_escape(gs: Node, _data_node: Node) -> int:
	var failed: int = 0
	_setup_gs_for_d8(gs, true)
	gs.acknowledge_encounter_intro()
	
	var view = gs.encounter_view()
	if not view.get("can_escape", false):
		failed += _err("D8 should allow escape")
		
	var esc_cards: Array[String] = ["equip_polaroid"]
	var req = gs.escape_encounter(esc_cards)
	if not bool(req.get("ok", false)):
		failed += _err("Escape should succeed")
		
	if not gs.active_encounter.is_empty():
		failed += _err("Active encounter should be cleared after escape")
		
	if not gs.flags.get("d8_encounter_escaped", false):
		failed += _err("d8_encounter_escaped flag should be set")
		
	if failed == 0:
		failed += _ok("D8 escape verified")
	return failed

func _test_7_d8_discard(gs: Node, _data_node: Node) -> int:
	var failed: int = 0
	_setup_gs_for_d8(gs, true)
	gs.acknowledge_encounter_intro()
	
	var view = gs.encounter_view()
	if not view.get("allow_discard", false):
		failed += _err("D8 should allow discard")
		
	var req = gs.discard_in_encounter("equip_polaroid")
	if not bool(req.get("ok", false)):
		failed += _err("Discard should succeed")
		
	if gs.has_card("equip_polaroid"):
		failed += _err("Card should be removed from hand after discard")
		
	if failed == 0:
		failed += _ok("D8 discard verified")
	return failed

func _test_8_d45_no_escape_no_discard_rejection_codes(gs: Node, _data_node: Node) -> int:
	var failed: int = 0
	_setup_gs_for_d45(gs)
	gs.acknowledge_encounter_intro()
	
	var view = gs.encounter_view()
	if view.get("can_escape", true):
		failed += _err("D45 should NOT allow escape in view")
	if view.get("allow_discard", true):
		failed += _err("D45 should NOT allow discard in view")
		
	# Direct calls must return exact rejection codes with zero state mutation
	var snap_before := JSON.stringify(gs.serialize())
	
	var empty_esc: Array[String] = []
	var esc_res = gs.escape_encounter(empty_esc)
	if bool(esc_res.get("ok", true)) or str(esc_res.get("reason_code", "")) != "cannot_escape":
		failed += _err("Direct escape_encounter on D45 should return reason_code 'cannot_escape', got '%s'" % esc_res.get("reason_code"))
		
	var disc_res = gs.discard_in_encounter("protagonist")
	if bool(disc_res.get("ok", true)) or str(disc_res.get("reason_code", "")) != "discard_disabled":
		failed += _err("Direct discard_in_encounter on D45 should return reason_code 'discard_disabled', got '%s'" % disc_res.get("reason_code"))
		
	var snap_after := JSON.stringify(gs.serialize())
	if snap_after != snap_before:
		failed += _err("State mutated after rejected escape/discard calls on D45")
		
	if failed == 0:
		failed += _ok("D45 no escape, no discard, and exact rejection codes verified")
	return failed

func _test_9_d45_response_paths_and_cards_retained(gs: Node, _data_node: Node) -> int:
	var failed: int = 0
	# Path 1: Submit protagonist (protagonist must be retained in hand and not consumed)
	_setup_gs_for_d45(gs)
	gs.acknowledge_encounter_intro()
	var req1 = gs.respond_to_encounter("protagonist")
	if not bool(req1.get("ok", false)):
		failed += _err("Submitting protagonist should succeed")
	if not "這個名字已經登記" in "".join(req1.get("lines", [])):
		failed += _err("Did not get correct resolution text for protagonist")
	if not gs.has_card("protagonist") or not gs.hand.has("protagonist"):
		failed += _err("Protagonist card should be retained in hand after D45 encounter")
	
	# Path 2: Submit inf_health_disappearance
	_setup_gs_for_d45(gs)
	gs.gain_card("inf_health_disappearance")
	gs.acknowledge_encounter_intro()
	var req2 = gs.respond_to_encounter("inf_health_disappearance")
	if not bool(req2.get("ok", false)):
		failed += _err("Submitting inf_health_disappearance should succeed")
		
	if gs.has_knowledge("inf_health_disappearance"):
		failed += _err("Should lose inf_health_disappearance")
	if not gs.has_knowledge("k_health_from_disappearance"):
		failed += _err("Should gain k_health_from_disappearance")

	# Path 3: Full 14-card hand on D45 must succeed and not fail capacity (F2 fix / K-168)
	_setup_gs_for_d45(gs)
	var fill_cards: Array[String] = [
		"routine_debt", "equip_polaroid", "item_gradphoto", "item_old_paper",
		"doc_prescription", "info_ajie_saw_parents", "info_uncle_treated_20y", "info_acai_box",
		"info_husband_version", "info_wife_version", "info_ahong_private", "info_ajie_class",
		"info_chunama_pause"
	]
	for cid in fill_cards:
		if gs.hand.size() < 14:
			gs.gain_card(cid)
	gs.acknowledge_encounter_intro()
	var req3 = gs.respond_to_encounter("protagonist")
	if not bool(req3.get("ok", false)):
		failed += _err("D45 with full 14-card hand should NOT fail capacity (per_round_slot_cost is 0)")
		
	if failed == 0:
		failed += _ok("D45 response paths, card retention, and 14-card full hand capacity verified")
	return failed

func _test_10_d45_after_finish(gs: Node, _data_node: Node) -> int:
	var failed: int = 0
	_setup_gs_for_d45(gs)
	gs.acknowledge_encounter_intro()
	gs.respond_to_encounter("protagonist")
	
	if gs.phase != "evening":
		failed += _err("Phase should auto-advance to 'evening' after D45 encounter finishes, got '%s'" % gs.phase)
		
	if failed == 0:
		failed += _ok("D45 after_finish phase advance verified")
	return failed

func _test_11_serialization_roundtrip(gs: Node, _data_node: Node) -> int:
	var failed: int = 0
	_setup_gs_for_d8(gs, true)
	gs.acknowledge_encounter_intro()
	
	var view_before = gs.encounter_view()
	var saved_state = gs.serialize()
	
	_reset_gs(gs)
	gs.deserialize(saved_state)
	
	var view_after = gs.encounter_view()
	
	if str(view_before) != str(view_after):
		failed += _err("Encounter view after deserialize does not match before")
		
	if failed == 0:
		failed += _ok("Serialization/deserialization roundtrip verified")
	return failed

func _test_12_d8_night_actions_blocked_and_protagonist_not_consumed(gs: Node, _data_node: Node) -> int:
	var failed: int = 0
	_setup_gs_for_d8(gs, true)
	
	# 1. During intro: sleep_night(), enter_night_location(), advance_phase() are blocked
	var snap_before := JSON.stringify(gs.serialize())
	
	var sleep_lines: PackedStringArray = gs.sleep_night()
	if not sleep_lines.is_empty():
		failed += _err("sleep_night during encounter intro should return empty lines")
	if JSON.stringify(gs.serialize()) != snap_before:
		failed += _err("State mutated after sleep_night during intro")
		
	var enter_res = gs.enter_night_location("sanquan")
	if bool(enter_res.get("ok", true)) or str(enter_res.get("reason_code", "")) != "encounter_active":
		failed += _err("enter_night_location during intro should be rejected with 'encounter_active', got '%s'" % enter_res.get("reason_code"))
		
	var adv_intro_res = gs.advance_phase()
	if bool(adv_intro_res.get("ok", true)) or str(adv_intro_res.get("reason_code", "")) != "encounter_active":
		failed += _err("advance_phase during encounter intro should be rejected with 'encounter_active', got '%s'" % adv_intro_res.get("reason_code"))
		
	var rna_intro_res = gs.resolve_night_advance()
	if bool(rna_intro_res.get("advance", true)) or str(rna_intro_res.get("reason_code", "")) != "encounter_active":
		failed += _err("resolve_night_advance during intro should return encounter_active")
		
	var snap_after := JSON.stringify(gs.serialize())
	if snap_after != snap_before:
		failed += _err("State mutated after rejected actions in intro")
		
	# 2. Transition to round: sleep_night() and advance_phase() are still blocked
	gs.acknowledge_encounter_intro()
	var snap_before_round := JSON.stringify(gs.serialize())
	var sleep_lines_r: PackedStringArray = gs.sleep_night()
	if not sleep_lines_r.is_empty():
		failed += _err("sleep_night during encounter round should return empty lines")
	if JSON.stringify(gs.serialize()) != snap_before_round:
		failed += _err("State mutated after sleep_night during round")
		
	var adv_round_res = gs.advance_phase()
	if bool(adv_round_res.get("ok", true)) or str(adv_round_res.get("reason_code", "")) != "encounter_active":
		failed += _err("advance_phase during encounter round should be rejected with 'encounter_active', got '%s'" % adv_round_res.get("reason_code"))

	# 2b. K-166 可證偽對照測試：D24 颱風夜在有可播定日 sleep 內容時，若有活躍遭遇，sleep_night 仍被阻斷
	var gs_control: Node = (load("res://scripts/autoload/game_state.gd") as GDScript).new()
	gs_control.name = "GSControlK166"
	gs_control.set("Data", _data_node)
	get_root().add_child(gs_control)
	_reset_gs(gs_control)
	gs_control.day = 24
	gs_control.phase = "night"
	gs_control.flags["boundary_bleeding"] = true
	gs_control.flags["hold_d24am"] = true
	# 正常無遭遇時，D24 睡覺有內容
	var d24_normal_lines: PackedStringArray = gs_control.sleep_night()
	if d24_normal_lines.is_empty():
		failed += _err("K-166 control: D24 normal sleep should have bleed lines")
	# 注入遭遇後，D24 睡覺必須被阻斷回空且狀態不變
	_reset_gs(gs_control)
	gs_control.day = 24
	gs_control.phase = "night"
	gs_control.flags["boundary_bleeding"] = true
	gs_control.flags["hold_d24am"] = true
	gs_control.active_encounter = { "stage": "round", "beat_id": "mock_enc" }
	var snap_d24_before := JSON.stringify(gs_control.serialize())
	var d24_blocked_lines: PackedStringArray = gs_control.sleep_night()
	if not d24_blocked_lines.is_empty():
		failed += _err("K-166: sleep_night with active encounter on D24 should return empty lines")
	if JSON.stringify(gs_control.serialize()) != snap_d24_before:
		failed += _err("K-166: sleep_night with active encounter on D24 should not mutate state")
	gs_control.queue_free()
		
	# 3. In R1, trying protagonist (not discardable, not in R1 response) is rejected with card_not_submittable
	var pro_res = gs.respond_to_encounter("protagonist")
	if bool(pro_res.get("ok", true)) or str(pro_res.get("reason_code", "")) != "card_not_submittable":
		failed += _err("protagonist submission in D8 R1 should be rejected with 'card_not_submittable', got '%s'" % pro_res.get("reason_code"))
	if not gs.has_card("protagonist") or not gs.hand.has("protagonist"):
		failed += _err("protagonist must not be consumed on rejection in R1")
		
	# 4. In R1 fallback via equip_polaroid, protagonist remains in hand untouched
	var disc_res = gs.respond_to_encounter("equip_polaroid")
	if not bool(disc_res.get("ok", false)):
		failed += _err("Fallback response with equip_polaroid should succeed")
	if not gs.has_card("protagonist") or not gs.hand.has("protagonist"):
		failed += _err("protagonist must not be consumed in R1 fallback")
		
	if failed == 0:
		failed += _ok("D8 night actions blocked and protagonist not consumed verified")
	return failed

func _test_13_d8_zero_discardable_direct_failure(gs: Node, _data_node: Node) -> int:
	var failed: int = 0
	# Setup D8 with 0 discardable cards and 0 response matches:
	# Hand only has protagonist (discardable: false), hand size = 2 (with 1 madness), capacity is 14
	_reset_gs(gs)
	gs.day = 8
	gs.phase = "night"
	gs.play_night_fixed() # hand: [protagonist, madness#1]
	
	# Hand has 2 cards, available slots = 14 - 2 - 1 = 11 > 0 (NOT capacity overload).
	# But has_legal_moves is false because madness is blocked and protagonist is not discardable.
	var ack_res = gs.acknowledge_encounter_intro()
	if not bool(ack_res.get("ok", false)):
		failed += _err("acknowledge_encounter_intro should succeed")
		
	if not gs.active_encounter.is_empty():
		failed += _err("Encounter should immediately settle as failure due to zero legal moves")
	if not gs.flags.get("d8_encounter_failure", false):
		failed += _err("d8_encounter_failure flag should be set for zero legal moves")
	if gs.flags.get("d8_encounter_victory", false):
		failed += _err("d8_encounter_victory should not be set")
		
	if failed == 0:
		failed += _ok("D8 zero discardable cards direct failure (non-capacity failure) verified")
	return failed

func _test_14_d8_knowledge_overwrites_round_1(gs: Node, _data_node: Node) -> int:
	var failed: int = 0
	_setup_gs_for_d8(gs, true) # hand has equip_polaroid, info_chunama_pause, routine_debt
	# Gain k_not_today (a valid response for R1 name_since_when)
	gs.gain_card("k_not_today")
	gs.acknowledge_encounter_intro()
	
	var r1_view = gs.encounter_view()
	var cand_k_found := false
	for c in r1_view.get("candidates", []):
		if str(c.get("base_id", "")) == "k_not_today":
			cand_k_found = true
			if not bool(c.get("submittable", false)):
				failed += _err("k_not_today should be submittable in R1")
	if not cand_k_found:
		failed += _err("k_not_today not found in R1 candidates")
		
	# Submit k_not_today: direct correct answer, releases cost, advances to R2
	var res = gs.respond_to_encounter("k_not_today")
	if not bool(res.get("ok", false)):
		failed += _err("Submitting k_not_today in R1 should succeed")
		
	var r2_view = gs.encounter_view()
	if not "誰記得你" in str(r2_view.get("demand", "")):
		failed += _err("Submitting k_not_today should advance directly to R2 'who_remembers'")
		
	# equip_polaroid should NOT have been consumed (knowledge answer preserved discardable hand card)
	if not gs.has_card("equip_polaroid"):
		failed += _err("equip_polaroid should remain in hand when answering with knowledge")
		
	if failed == 0:
		failed += _ok("D8 knowledge overwriting R1 question verified")
	return failed

func _test_15_d8_win_lose_return_to_night_end(gs: Node, _data_node: Node) -> int:
	var failed: int = 0
	# 1. Victory settlement -> remains in Day 8 Night -> advance to Day 9 Morning
	_setup_gs_for_d8(gs, true)
	gs.acknowledge_encounter_intro()
	gs.respond_to_encounter("equip_polaroid")
	gs.respond_to_encounter("info_chunama_pause")
	gs.respond_to_encounter("routine_debt")
	
	if gs.day != 8 or gs.phase != "night":
		failed += _err("After victory, game should remain in Day 8 Night")
	if not gs.active_encounter.is_empty():
		failed += _err("Active encounter should be empty after victory")
		
	var adv_win_res: Dictionary = gs.resolve_night_advance()
	if not bool(adv_win_res.get("advance", false)):
		adv_win_res = gs.resolve_night_advance()
	if not bool(adv_win_res.get("advance", false)):
		failed += _err("resolve_night_advance after D8 victory should return advance: true")
	gs.advance_phase()
	if gs.day != 9 or gs.phase != "morning":
		failed += _err("Night advance after D8 victory should advance to Day 9 Morning, got D%d %s" % [gs.day, gs.phase])
		
	# 2. Failure settlement -> remains in Day 8 Night -> advance to Day 9 Morning
	_reset_gs(gs)
	gs.day = 8
	gs.phase = "night"
	gs.play_night_fixed()
	gs.acknowledge_encounter_intro() # zero discardable -> failure
	
	if gs.day != 8 or gs.phase != "night":
		failed += _err("After failure, game should remain in Day 8 Night")
	if not gs.active_encounter.is_empty():
		failed += _err("Active encounter should be empty after failure")
		
	var adv_fail_res: Dictionary = gs.resolve_night_advance()
	if not bool(adv_fail_res.get("advance", false)):
		adv_fail_res = gs.resolve_night_advance()
	if not bool(adv_fail_res.get("advance", false)):
		failed += _err("resolve_night_advance after D8 failure should return advance: true")
	gs.advance_phase()
	if gs.day != 9 or gs.phase != "morning":
		failed += _err("Night advance after D8 failure should advance to Day 9 Morning, got D%d %s" % [gs.day, gs.phase])
		
	if failed == 0:
		failed += _ok("D8 victory and failure return to night end advance verified")
	return failed
