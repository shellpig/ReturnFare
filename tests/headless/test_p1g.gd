extends SceneTree

## P1-G 規則層與兩階段面板回歸測試。
## 跑法：Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/test_p1g.gd

const PanelBuilder := preload("res://scripts/core/panel_builder.gd")

func _initialize() -> void:
	await process_frame
	var data_node: Node = get_root().get_node("Data")
	var gs: Node = get_root().get_node("GameState")
	if not data_node.get("ok"):
		push_error("P1-G: Data failed to load")
		quit(1)
		return

	var failed := 0
	failed += _test_three_rule_entries(gs, data_node)
	failed += await _test_two_stage_location_panel(gs)
	failed += _test_type_preview_and_fallback(gs, data_node)
	failed += _test_choice_only_action_prompt(gs)

	if failed > 0:
		push_error("P1-G: %d test(s) failed" % failed)
		quit(1)
	else:
		print("P1-G: all tests passed")
		quit(0)


func _test_three_rule_entries(gs: Node, data_node: Node) -> int:
	print("--- P1-G rule entries: build_panel / play_beat / preview_slot ---")
	_reset_gs(gs)
	gs.set("day", 1)
	gs.set("phase", "evening")
	var before: Dictionary = gs.serialize()
	var view: Dictionary = gs.build_panel("busstop")
	var after: Dictionary = gs.serialize()
	var failed := 0
	if before != after:
		failed += _fail("build_panel changed GameState")
	else:
		failed += _ok("build_panel is side-effect free")
	if gs.has_method("open_panel"):
		failed += _fail("open_panel should be removed")
	else:
		failed += _ok("open_panel removed")

	var lines: PackedStringArray = gs.play_beat("d1_arrival")
	if not lines.is_empty() and (gs.get("beats_entered") as Dictionary).has("d1_arrival"):
		failed += _ok("play_beat settles and returns d1_arrival lines")
	else:
		failed += _fail("play_beat did not settle d1_arrival")

	var preview: Dictionary = gs.preview_slot("d1_arrival", "driver")
	if preview.has("cards") and preview.has("reason"):
		failed += _ok("preview_slot returns cards/reason shape")
	else:
		failed += _fail("preview_slot response shape is incomplete: %s" % str(preview))
	return failed


func _test_two_stage_location_panel(gs: Node) -> int:
	print("--- P1-G two-stage UI: beats first, slots after演出 ---")
	_reset_gs(gs)
	gs.set("day", 32)
	gs.set("phase", "morning")
	var scene: PackedScene = load("res://scenes/ui/location_panel.tscn")
	var panel: Node = scene.instantiate()
	get_root().add_child(panel)
	await process_frame
	panel.call("show_location", "temple")
	await process_frame

	var failed := 0
	var beat_container: Node = panel.find_child("BeatContainer", true, false)
	if _has_slot_marker(beat_container):
		failed += _fail("slots were rendered during beat演出")
	else:
		failed += _ok("slots are absent during beat演出")

	if not (gs.get("beats_entered") as Dictionary).is_empty():
		failed += _fail("entering location should NOT play any beat immediately (side-effect free)")
	else:
		failed += _ok("entering location does not change state before player advances")

	var advance_btn: Button = panel.get_node("AdvanceBeatButton")
	if not advance_btn.visible:
		failed += _fail("演出佇列 did not expose advance button")
	else:
		failed += _ok("演出佇列 waits for player advance")

	panel.call("_on_advance_beat_pressed")
	await process_frame
	if (gs.get("beats_entered") as Dictionary).size() != 1:
		failed += _fail("first advance should play the first beat")
	else:
		failed += _ok("first advance plays the first beat")

	var guard := 0
	while advance_btn.visible and guard < 12:
		panel.call("_on_advance_beat_pressed")
		await process_frame
		guard += 1
	if advance_btn.visible:
		failed += _fail("演出佇列 did not finish")
	else:
		failed += _ok("normal stage reached only after all beats演出")

	var title: Label = panel.get_node("LocationTitle")
	var data_node: Node = get_root().get_node("Data")
	var exp_temple_name := str((data_node.get("loader").locations.get("temple", {}) as Dictionary).get("name", ""))
	assert(not exp_temple_name.is_empty(), "fixture 前提：temple 有 name")
	if title.text == exp_temple_name:
		failed += _ok("missing desc fallback still displays location name")
	else:
		failed += _fail("location name fallback mismatch: %s (expected: %s)" % [title.text, exp_temple_name])
	panel.queue_free()
	return failed


func _test_type_preview_and_fallback(gs: Node, data_node: Node) -> int:
	print("--- P1-G slot type labels and preview consistency ---")
	_reset_gs(gs)
	gs.set("day", 22)
	gs.set("phase", "afternoon")
	gs.call("set_flag", "acai_obs_knee", true)
	gs.call("gain_card", "equip_polaroid")
	var view: Dictionary = gs.build_panel("sanquan")
	var beat_view := _find_beat(view, "d22_pm_sandbags")
	var slot_view := _find_slot(beat_view, "obs_walk")
	var failed := 0
	var types: PackedStringArray = slot_view.get("accept_types", PackedStringArray())
	if types == PackedStringArray(["裝備卡", "情報卡"]):
		failed += _ok("obs_walk type label is 裝備卡、情報卡")
	else:
		failed += _fail("obs_walk type label mismatch: %s" % str(types))

	var before: Dictionary = gs.serialize()
	var preview: Dictionary = gs.preview_slot("d22_pm_sandbags", "obs_walk")
	var after: Dictionary = gs.serialize()
	if before == after and (preview.get("cards", []) as Array).has("equip_polaroid"):
		failed += _ok("preview lists legal card without changing state")
	else:
		failed += _fail("preview changed state or omitted legal card: %s" % str(preview))

	var locked_preview: Dictionary = gs.preview_slot("d22_pm_sandbags", "obs_hands")
	if (locked_preview.get("cards", []) as Array).is_empty() and not str(locked_preview.get("reason", "")).is_empty():
		failed += _ok("locked slot preview is empty with a reason")
	else:
		failed += _fail("locked slot preview mismatch: %s" % str(locked_preview))
	return failed


func _test_choice_only_action_prompt(gs: Node) -> int:
	print("--- P1-G action prompt counts unresolved choice_group slots ---")
	var cases: Array[Dictionary] = [
		{
			"label": "第 35 天下午",
			"day": 35,
			"phase": "afternoon",
			"location": "clinic",
			"beat": "d35_pm_answer",
			"slot": "accept",
			"card": "",
			"flag": "inheritance_offered",
		},
		{
			"label": "第 40 天上午",
			"day": 40,
			"phase": "morning",
			"location": "sanquan",
			"beat": "d40_tell_someone",
			"slot": "tell_her",
			"card": "info_something_off",
			"flag": "",
		},
		{
			"label": "第 43 天下午",
			"day": 43,
			"phase": "afternoon",
			"location": "sanquan",
			"beat": "d43_conclusion",
			"slot": "theory_exchange",
			"cards": ["info_something_off", "info_acai_walk", "info_jinghe_pool"],
			"flag": "",
		},
	]

	var failed := 0
	for test_case: Dictionary in cases:
		_reset_gs(gs)
		gs.set("day", int(test_case.get("day", -1)))
		gs.set("phase", str(test_case.get("phase", "")))
		var flag_id := str(test_case.get("flag", ""))
		if not flag_id.is_empty():
			gs.call("set_flag", flag_id, true)
		var cards: Array = test_case.get("cards", []) as Array
		var card_id := str(test_case.get("card", ""))
		if not card_id.is_empty():
			cards.append(card_id)
		for card_to_gain: Variant in cards:
			gs.call("gain_card", str(card_to_gain))
		var beat_id := str(test_case.get("beat", ""))
		var slot_id := str(test_case.get("slot", ""))
		gs.play_beat(beat_id)

		var view: Dictionary = gs.build_panel(str(test_case.get("location", "")))
		var beat_view := _find_beat(view, beat_id)
		var slot_view := _find_slot(beat_view, slot_id)
		var slot_is_open := int(slot_view.get("tri", -1)) == PanelBuilder.TriState.OPEN
		var slot_is_choice := bool(slot_view.get("is_choice", false))
		if not slot_is_open or not slot_is_choice:
			failed += _fail("%s choice slot is not OPEN: %s" % [str(test_case.get("label", "")), str(slot_view)])
			continue
		if not (gs.placeable_cards(beat_id, slot_id)).is_empty():
			failed += _fail("%s unexpectedly has a legal card placement" % str(test_case.get("label", "")))
			continue
		if gs.has_any_legal_action():
			failed += _ok("%s remains actionable through direct choice" % str(test_case.get("label", "")))
		else:
			failed += _fail("%s was reported as having no action" % str(test_case.get("label", "")))

		if str(test_case.get("beat", "")) == "d40_tell_someone":
			var choice_result: Dictionary = gs.choose("d40_tell_someone", "d40_tell", "tell_her", "")
			if not choice_result.get("ok", false):
				failed += _fail("第 40 天上午 direct choice failed: %s" % str(choice_result))
			elif gs.has_any_legal_action():
				failed += _fail("第 40 天上午 remained actionable after choice resolved")
			else:
				failed += _ok("第 40 天上午 is no longer actionable after choice resolved")
	return failed


func _has_slot_marker(container: Node) -> bool:
	for child in container.get_children():
		if child is Label:
			var text: String = (child as Label).text
			if text.contains("[空槽]") or text.contains("[灰]") or text.contains("[已放]") or text.contains("[出席]"):
				return true
	return false


func _find_beat(view: Dictionary, beat_id: String) -> Dictionary:
	for entry: Dictionary in view.get("beats", []) as Array:
		if str((entry["beat"] as Dictionary).get("id", "")) == beat_id:
			return entry
	return {}


func _find_slot(beat_view: Dictionary, slot_id: String) -> Dictionary:
	for entry: Dictionary in beat_view.get("slots", []) as Array:
		if str((entry["slot"] as Dictionary).get("id", "")) == slot_id:
			return entry
	return {}


func _reset_gs(gs: Node) -> void:
	# P5-D：fresh state 是 opening，本檔驗的是 run 層規則。
	gs.set("flow_mode", "run")
	(gs.get("active_ending") as Dictionary).clear()
	(gs.get("hand") as Array).clear()
	(gs.get("knowledge") as Dictionary).clear()
	(gs.get("madness_clock") as Dictionary).clear()
	(gs.get("beats_entered") as Dictionary).clear()
	(gs.get("slots_placed") as Dictionary).clear()
	(gs.get("choices") as Dictionary).clear()
	(gs.get("flags") as Dictionary).clear()
	(gs.get("switches") as Dictionary).clear()
	(gs.get("switch_progress") as Dictionary).clear()
	(gs.get("relations") as Dictionary).clear()
	(gs.get("npc_action_counts") as Dictionary).clear()
	gs.set("_madness_counter", 0)
	gs.set("day", 1)
	gs.set("phase", "morning")
	gs.set("action_spent", false)


func _ok(message: String) -> int:
	print("  ok  " + message)
	return 0


func _fail(message: String) -> int:
	push_error("  FAIL  " + message)
	return 1
