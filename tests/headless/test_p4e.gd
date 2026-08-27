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
	print("\n=== P4-E 遭遇 UI 層次整合測試 ===")
	
	failed += _test_1_view_safety_and_non_leakage(gs, data_node)
	failed += _test_2_d8_lifecycle(gs, data_node)
	failed += _test_3_candidate_disabled_states(gs, data_node)
	failed += _test_4_charge_first_visit(gs, data_node)
	failed += _test_5_three_round_paths(gs, data_node)
	failed += _test_6_d8_escape(gs, data_node)
	failed += _test_7_d8_discard(gs, data_node)
	failed += _test_8_d45_no_escape_no_discard(gs, data_node)
	failed += _test_9_d45_response_paths(gs, data_node)
	failed += _test_10_d45_after_finish(gs, data_node)
	failed += _test_11_serialization_roundtrip(gs, data_node)
	
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

func _test_1_view_safety_and_non_leakage(gs: Node, data_node: Node) -> int:
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

func _test_2_d8_lifecycle(gs: Node, data_node: Node) -> int:
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

func _test_3_candidate_disabled_states(gs: Node, data_node: Node) -> int:
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

func _test_4_charge_first_visit(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)
	gs.day = 8
	gs.phase = "night"
	
	var initial_madness = int(gs.get("_madness_counter"))
	gs.play_night_fixed()
	var madness_after_first = int(gs.get("_madness_counter"))
	
	if madness_after_first - initial_madness != 1:
		failed += _err("First visit should charge madness cost")
		
	gs.end_run("test_reset")
	gs.day = 8
	gs.phase = "night"
	gs.night_locations_seen["n_manydoors"] = true
	var madness_before_second = int(gs.get("_madness_counter"))
	gs.play_night_fixed()
	var madness_after_second = int(gs.get("_madness_counter"))
	
	if madness_after_second != madness_before_second:
		failed += _err("Second visit should NOT charge madness cost")
		
	if failed == 0:
		failed += _ok("D8 charge_first_visit logic verified")
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
		failed += _ok("D8 three-round paths (victory and failure) verified")
	return failed

func _test_6_d8_escape(gs: Node, data_node: Node) -> int:
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

func _test_7_d8_discard(gs: Node, data_node: Node) -> int:
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

func _test_8_d45_no_escape_no_discard(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_setup_gs_for_d45(gs)
	gs.acknowledge_encounter_intro()
	
	var view = gs.encounter_view()
	if view.get("can_escape", true):
		failed += _err("D45 should NOT allow escape")
	if view.get("allow_discard", true):
		failed += _err("D45 should NOT allow discard")
		
	if failed == 0:
		failed += _ok("D45 no escape and no discard verified")
	return failed

func _test_9_d45_response_paths(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	# Path 1: Submit protagonist
	_setup_gs_for_d45(gs)
	gs.acknowledge_encounter_intro()
	var req1 = gs.respond_to_encounter("protagonist")
	if not bool(req1.get("ok", false)):
		failed += _err("Submitting protagonist should succeed")
	if not "這個名字已經登記" in "".join(req1.get("lines", [])):
		failed += _err("Did not get correct resolution text for protagonist")
	
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
		
	if failed == 0:
		failed += _ok("D45 response paths verified")
	return failed

func _test_10_d45_after_finish(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_setup_gs_for_d45(gs)
	gs.acknowledge_encounter_intro()
	gs.respond_to_encounter("protagonist")
	
	if gs.phase != "evening":
		failed += _err("Phase should auto-advance to 'evening' after D45 encounter finishes, got '%s'" % gs.phase)
		
	if failed == 0:
		failed += _ok("D45 after_finish phase advance verified")
	return failed

func _test_11_serialization_roundtrip(gs: Node, data_node: Node) -> int:
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
