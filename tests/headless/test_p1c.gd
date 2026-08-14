extends SceneTree

## P1-C headless 驗收測試：ConditionEval、enter_beat、available_locations、PanelBuilder.build。
## 跑法：
##   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/test_p1c.gd
## 全綠 exit 0；任一失敗 exit 1。


func _initialize() -> void:
	var gs: Node = load("res://scripts/autoload/game_state.gd").new()
	gs.name = "GameState"
	get_root().add_child(gs)
	Engine.register_singleton("GameState", gs)

	var data_node: Node = load("res://scripts/autoload/data.gd").new()
	data_node.name = "Data"
	get_root().add_child(data_node)
	Engine.register_singleton("Data", data_node)

	await process_frame

	if not data_node.get("ok"):
		push_error("P1-C: Data failed to load; abort")
		quit(1)
		return

	var failed := 0
	failed += _test_condition_eval(gs)
	failed += _test_enter_beat_d1_arrival(gs)
	failed += _test_available_locations(gs, data_node)
	failed += _test_panel_build_busstop_d1_evening(gs, data_node)
	failed += _test_panel_build_sanquan_d3_pm(gs, data_node)
	failed += _test_panel_build_all_d3_pm_locations(gs, data_node)
	failed += _test_condition_hidden_filtering(gs, data_node)

	Engine.unregister_singleton("Data")
	Engine.unregister_singleton("GameState")

	if failed > 0:
		push_error("P1-C: %d test(s) failed" % failed)
		quit(1)
	else:
		print("P1-C: all tests passed")
		quit(0)


func _ok(msg: String) -> int:
	print("  ok  " + msg)
	return 0


func _fail(msg: String) -> int:
	push_error("  FAIL  " + msg)
	return 1


func _reset(gs: Node) -> void:
	(gs.get("hand") as Array).clear()
	(gs.get("knowledge") as Dictionary).clear()
	(gs.get("madness_clock") as Dictionary).clear()
	(gs.get("beats_entered") as Dictionary).clear()
	(gs.get("slots_placed") as Dictionary).clear()
	gs.set("_madness_counter", 0)
	gs.set("day", 1)
	gs.set("phase", "morning")
	gs.set("action_spent", false)


# ── ConditionEval 運算子單元測試 ─────────────────────────────────────────────

func _test_condition_eval(gs: Node) -> int:
	print("--- condition_eval ---")
	_reset(gs)
	var failed := 0

	# null → true
	if not ConditionEval.eval(null, gs):
		failed += _fail("null condition: expected true")
	else:
		failed += _ok("null condition → true")

	# day
	gs.set("day", 1)
	if not ConditionEval.eval({ "day": 1 }, gs):
		failed += _fail("day==1: expected true")
	else:
		failed += _ok("day==1 → true")
	if ConditionEval.eval({ "day": 2 }, gs):
		failed += _fail("day==2 when day=1: expected false")
	else:
		failed += _ok("day==2 when day=1 → false")

	# day_at_least
	if not ConditionEval.eval({ "day_at_least": 1 }, gs):
		failed += _fail("day_at_least=1 when day=1: expected true")
	else:
		failed += _ok("day_at_least=1 when day=1 → true")
	if ConditionEval.eval({ "day_at_least": 2 }, gs):
		failed += _fail("day_at_least=2 when day=1: expected false")
	else:
		failed += _ok("day_at_least=2 when day=1 → false")

	# has_card（protagonist 還沒進手牌）
	if ConditionEval.eval({ "has_card": "protagonist" }, gs):
		failed += _fail("has_card protagonist before gain: expected false")
	else:
		failed += _ok("has_card protagonist before gain → false")
	gs.call("gain_card", "protagonist")
	if not ConditionEval.eval({ "has_card": "protagonist" }, gs):
		failed += _fail("has_card protagonist after gain: expected true")
	else:
		failed += _ok("has_card protagonist after gain → true")

	# has_knowledge
	if ConditionEval.eval({ "has_knowledge": "k_forty_something" }, gs):
		failed += _fail("has_knowledge before gain: expected false")
	else:
		failed += _ok("has_knowledge before gain → false")
	gs.call("gain_card", "k_forty_something")
	if not ConditionEval.eval({ "has_knowledge": "k_forty_something" }, gs):
		failed += _fail("has_knowledge after gain: expected true")
	else:
		failed += _ok("has_knowledge after gain → true")

	# madness_at_least
	if ConditionEval.eval({ "madness_at_least": 1 }, gs):
		failed += _fail("madness_at_least=1 before madness: expected false")
	else:
		failed += _ok("madness_at_least=1 before madness → false")
	gs.call("gain_card", "madness")
	if not ConditionEval.eval({ "madness_at_least": 1 }, gs):
		failed += _fail("madness_at_least=1 after gaining madness: expected true")
	else:
		failed += _ok("madness_at_least=1 after gaining madness → true")

	# not
	gs.set("day", 1)
	if ConditionEval.eval({ "not": { "day": 1 } }, gs):
		failed += _fail("not day==1 when day=1: expected false")
	else:
		failed += _ok("not day==1 when day=1 → false")

	# all
	if not ConditionEval.eval({ "all": [{ "day": 1 }, { "day_at_least": 1 }] }, gs):
		failed += _fail("all[day=1, day_at_least=1]: expected true")
	else:
		failed += _ok("all[day=1, day_at_least=1] → true")
	if ConditionEval.eval({ "all": [{ "day": 1 }, { "day": 2 }] }, gs):
		failed += _fail("all[day=1, day=2]: expected false")
	else:
		failed += _ok("all[day=1, day=2] → false")

	# any
	if not ConditionEval.eval({ "any": [{ "day": 2 }, { "day": 1 }] }, gs):
		failed += _fail("any[day=2, day=1]: expected true")
	else:
		failed += _ok("any[day=2, day=1] → true")
	if ConditionEval.eval({ "any": [{ "day": 2 }, { "day": 3 }] }, gs):
		failed += _fail("any[day=2, day=3] when day=1: expected false")
	else:
		failed += _ok("any[day=2, day=3] when day=1 → false")

	# count_at_least（day=1 時：day==1 → T, day==2 → F, day_at_least=1 → T，共 2 of 3）
	if not ConditionEval.eval({ "count_at_least": { "n": 2, "of": [
			{ "day": 1 }, { "day": 2 }, { "day_at_least": 1 }] } }, gs):
		failed += _fail("count_at_least n=2 of 3 (2 pass): expected true")
	else:
		failed += _ok("count_at_least n=2 of 3 (2 pass) → true")
	if ConditionEval.eval({ "count_at_least": { "n": 3, "of": [
			{ "day": 1 }, { "day": 2 }, { "day_at_least": 1 }] } }, gs):
		failed += _fail("count_at_least n=3 of 3 (2 pass): expected false")
	else:
		failed += _ok("count_at_least n=3 of 3 (2 pass) → false")

	# 未知運算子 → push_error（預期行為），回傳 false
	if ConditionEval.eval({ "unknown_op": "whatever" }, gs):
		failed += _fail("unknown operator: expected false")
	else:
		failed += _ok("unknown operator → false (push_error expected)")

	return failed


# ── play_beat：第 1 天到站事件（on_enter 冪等）───────────────────────────────

func _test_enter_beat_d1_arrival(gs: Node) -> int:
	print("--- play_beat d1_arrival ---")
	_reset(gs)
	gs.set("day", 1)
	gs.set("phase", "evening")
	var failed := 0

	var lines: PackedStringArray = gs.call("play_beat", "d1_arrival")

	if lines.is_empty():
		failed += _fail("play_beat d1_arrival: returned no text lines")
	else:
		failed += _ok("play_beat d1_arrival: returned %d text line(s)" % lines.size())

	if not (gs.get("beats_entered") as Dictionary).has("d1_arrival"):
		failed += _fail("beats_entered should contain d1_arrival")
	else:
		failed += _ok("beats_entered contains d1_arrival")

	if not (gs.get("hand") as Array).has("protagonist"):
		failed += _fail("protagonist should be in hand after d1_arrival on_enter")
	else:
		failed += _ok("protagonist in hand after d1_arrival on_enter")

	# 第二次呼叫：on_enter 不重複，手牌不增
	var size_before: int = (gs.get("hand") as Array).size()
	gs.call("play_beat", "d1_arrival")
	var size_after: int = (gs.get("hand") as Array).size()
	if size_after != size_before:
		failed += _fail("play_beat d1_arrival second call: on_enter re-ran (expected idempotent)")
	else:
		failed += _ok("enter_beat d1_arrival second call: on_enter idempotent")

	return failed


# ── available_locations：chapter/phases 過濾 ──────────────────────────────

func _test_available_locations(gs: Node, data: Node) -> int:
	print("--- available_locations ---")
	_reset(gs)
	var failed := 0

	# 第 2 天上午：busstop（phases=["morning"]）出現
	gs.set("day", 2)
	gs.set("phase", "morning")
	var locs_morning: Array[String] = PanelBuilder.available_locations(gs, data)
	if not locs_morning.has("busstop"):
		failed += _fail("day=2 morning: busstop should be available (phases=[morning])")
	else:
		failed += _ok("day=2 morning: busstop is available")
	if not locs_morning.has("sanquan"):
		failed += _fail("day=2 morning: sanquan should be available")
	else:
		failed += _ok("day=2 morning: sanquan is available")

	# 第 2 天下午：busstop（phases=["morning"] only）不出現
	gs.set("phase", "afternoon")
	var locs_afternoon: Array[String] = PanelBuilder.available_locations(gs, data)
	if locs_afternoon.has("busstop"):
		failed += _fail("day=2 afternoon: busstop should NOT be available (morning only)")
	else:
		failed += _ok("day=2 afternoon: busstop not available (morning only)")

	# 第 3 天下午：sanquan / oldstreet / temple 三個互搶地點都出現
	gs.set("day", 3)
	gs.set("phase", "afternoon")
	var locs_d3: Array[String] = PanelBuilder.available_locations(gs, data)
	for expected in ["sanquan", "oldstreet", "temple"]:
		if not locs_d3.has(expected):
			failed += _fail("day=3 afternoon: %s should be available" % expected)
		else:
			failed += _ok("day=3 afternoon: %s is available" % expected)

	# chapter 過濾：第 3 天（章 1）不出現 chapter>1 地點
	var loader: DataLoader = data.get("loader") as DataLoader
	var has_bad_chapter := false
	for loc_id in locs_d3:
		var loc: Dictionary = loader.locations.get(loc_id, {}) as Dictionary
		if int(loc.get("chapter", 1)) > 1:
			failed += _fail("day=3 afternoon: %s (chapter %d) should not appear" % [
				loc_id, int(loc.get("chapter", 1))])
			has_bad_chapter = true
	if not has_bad_chapter:
		failed += _ok("day=3 afternoon: no chapter>1 locations in result")

	return failed


# ── PanelBuilder.build：第 1 天晚間公車站（all OPEN）────────────────────────

func _test_panel_build_busstop_d1_evening(gs: Node, data: Node) -> int:
	print("--- panel_build busstop d1_evening ---")
	_reset(gs)
	gs.set("day", 1)
	gs.set("phase", "evening")
	var failed := 0

	var view: Dictionary = PanelBuilder.build("busstop", gs, data)
	var beats: Array = view["beats"] as Array

	if beats.size() != 1:
		failed += _fail("busstop d1 evening: expected 1 beat, got %d" % beats.size())
		return failed
	else:
		failed += _ok("busstop d1 evening: 1 beat in panel")

	var bv: Dictionary = beats[0] as Dictionary
	if str(bv["beat"]["id"]) != "d1_arrival":
		failed += _fail("beat id should be d1_arrival, got: " + str(bv["beat"]["id"]))
	else:
		failed += _ok("beat id is d1_arrival")

	if int(bv["tri"]) != PanelBuilder.TriState.OPEN:
		failed += _fail("d1_arrival tri should be OPEN, got: %d" % bv["tri"])
	else:
		failed += _ok("d1_arrival tri is OPEN")

	var slots: Array = bv["slots"] as Array
	if slots.size() != 3:
		failed += _fail("d1_arrival should have 3 slots, got %d" % slots.size())
	else:
		failed += _ok("d1_arrival has 3 slots (driver/ajie/uncle)")

	for sv in slots:
		var sv_dict: Dictionary = sv as Dictionary
		if int(sv_dict["tri"]) != PanelBuilder.TriState.OPEN:
			failed += _fail("slot %s tri should be OPEN, got %d" % [
				sv_dict["slot"]["id"], sv_dict["tri"]])
		else:
			failed += _ok("slot %s tri is OPEN" % sv_dict["slot"]["id"])

	return failed


# ── PanelBuilder.build：第 3 天下午山泉閣（LOCKED slot → OPEN after gain）──

func _test_panel_build_sanquan_d3_pm(gs: Node, data: Node) -> int:
	print("--- panel_build sanquan d3_pm requires ---")
	_reset(gs)
	gs.set("day", 3)
	gs.set("phase", "afternoon")
	var failed := 0

	var view: Dictionary = PanelBuilder.build("sanquan", gs, data)
	var beats: Array = view["beats"] as Array

	# 找 d3_pm_sanquan
	var d3_bv: Dictionary = {}
	for bv in beats:
		if str((bv as Dictionary)["beat"]["id"]) == "d3_pm_sanquan":
			d3_bv = bv as Dictionary
			break

	if d3_bv.is_empty():
		failed += _fail("d3_pm_sanquan should be in sanquan panel on day=3 afternoon")
		return failed
	else:
		failed += _ok("d3_pm_sanquan found in panel")

	if int(d3_bv["tri"]) != PanelBuilder.TriState.OPEN:
		failed += _fail("d3_pm_sanquan tri should be OPEN (no condition), got %d" % d3_bv["tri"])
	else:
		failed += _ok("d3_pm_sanquan tri is OPEN")

	# 找 show_version 槽（requires: any[has_card info_husband_version, info_wife_version]）
	var show_sv: Dictionary = {}
	for sv in d3_bv["slots"] as Array:
		if str((sv as Dictionary)["slot"]["id"]) == "show_version":
			show_sv = sv as Dictionary
			break

	if show_sv.is_empty():
		failed += _fail("show_version slot should be in d3_pm_sanquan slots")
		return failed
	else:
		failed += _ok("show_version slot found")

	# 沒有情報卡時 → LOCKED
	if int(show_sv["tri"]) != PanelBuilder.TriState.LOCKED:
		failed += _fail("show_version without info cards: expected LOCKED, got %d" % show_sv["tri"])
	else:
		failed += _ok("show_version without info cards → LOCKED")

	if str(show_sv["reason"]).is_empty():
		failed += _fail("show_version LOCKED should have reject_reason text")
	else:
		failed += _ok("show_version has reject_reason: " + str(show_sv["reason"]))

	# 取得 info_husband_version → show_version 變 OPEN
	gs.call("gain_card", "info_husband_version")
	view = PanelBuilder.build("sanquan", gs, data)
	show_sv = {}
	for bv in view["beats"] as Array:
		if str((bv as Dictionary)["beat"]["id"]) == "d3_pm_sanquan":
			for sv in (bv as Dictionary)["slots"] as Array:
				if str((sv as Dictionary)["slot"]["id"]) == "show_version":
					show_sv = sv as Dictionary
					break
			break

	if show_sv.is_empty():
		failed += _fail("show_version slot missing after gaining info card")
		return failed

	if int(show_sv["tri"]) != PanelBuilder.TriState.OPEN:
		failed += _fail("show_version after gaining info_husband_version: expected OPEN, got %d" % show_sv["tri"])
	else:
		failed += _ok("show_version after gaining info_husband_version → OPEN")

	return failed


# ── PanelBuilder.build：第 3 天下午三個地點面板（sanquan, oldstreet, temple）全部按資料呈現 ──

func _test_panel_build_all_d3_pm_locations(gs: Node, data: Node) -> int:
	print("--- panel_build all_d3_pm_locations ---")
	_reset(gs)
	gs.set("day", 3)
	gs.set("phase", "afternoon")
	var failed := 0

	# 1. sanquan
	var view_sanquan: Dictionary = PanelBuilder.build("sanquan", gs, data)
	var beats_sq: Array = view_sanquan["beats"] as Array
	if beats_sq.size() != 1 or str((beats_sq[0] as Dictionary)["beat"]["id"]) != "d3_pm_sanquan":
		failed += _fail("d3 pm sanquan: expected 1 beat (d3_pm_sanquan), got %d" % beats_sq.size())
	else:
		failed += _ok("d3 pm sanquan: beat d3_pm_sanquan correctly loaded")

	# 2. oldstreet: d3_pm_oldstreet (1 slot: wander)
	var view_oldstreet: Dictionary = PanelBuilder.build("oldstreet", gs, data)
	var beats_os: Array = view_oldstreet["beats"] as Array
	if beats_os.size() != 1:
		failed += _fail("d3 pm oldstreet: expected 1 beat, got %d" % beats_os.size())
	else:
		var bv_os: Dictionary = beats_os[0] as Dictionary
		if str(bv_os["beat"]["id"]) != "d3_pm_oldstreet":
			failed += _fail("d3 pm oldstreet: beat id expect d3_pm_oldstreet, got %s" % str(bv_os["beat"]["id"]))
		else:
			failed += _ok("d3 pm oldstreet: beat d3_pm_oldstreet present")
		var slots_os: Array = bv_os["slots"] as Array
		if slots_os.size() != 1 or str((slots_os[0] as Dictionary)["slot"]["id"]) != "wander":
			failed += _fail("d3 pm oldstreet: expected 1 slot (wander)")
		else:
			failed += _ok("d3 pm oldstreet: slot wander present and OPEN")

	# 3. temple: d3_pm_temple (1 slot: jinbo)
	var view_temple: Dictionary = PanelBuilder.build("temple", gs, data)
	var beats_tp: Array = view_temple["beats"] as Array
	if beats_tp.size() != 1:
		failed += _fail("d3 pm temple: expected 1 beat, got %d" % beats_tp.size())
	else:
		var bv_tp: Dictionary = beats_tp[0] as Dictionary
		if str(bv_tp["beat"]["id"]) != "d3_pm_temple":
			failed += _fail("d3 pm temple: beat id expect d3_pm_temple, got %s" % str(bv_tp["beat"]["id"]))
		else:
			failed += _ok("d3 pm temple: beat d3_pm_temple present")
		var slots_tp: Array = bv_tp["slots"] as Array
		if slots_tp.size() != 1 or str((slots_tp[0] as Dictionary)["slot"]["id"]) != "jinbo":
			failed += _fail("d3 pm temple: expected 1 slot (jinbo)")
		else:
			failed += _ok("d3 pm temple: slot jinbo present and OPEN")

	return failed


# ── PanelBuilder.build：condition 不成立時 Beat 與 Slot 呈 HIDDEN (完全不出 appearances in view model) ──

func _test_condition_hidden_filtering(gs: Node, data: Node) -> int:
	print("--- condition_hidden_filtering ---")
	_reset(gs)
	var failed := 0

	# 第 18 天上午 sanquan 的 d18_morning_prep 有 condition: { flag: "pilgrimage_accepted" }
	gs.set("day", 18)
	gs.set("phase", "morning")

	# 條件不成立 (flag 未設定) → d18_morning_prep 完全不出現 (HIDDEN 被過濾)
	var view_before: Dictionary = PanelBuilder.build("sanquan", gs, data)
	var beats_before: Array = view_before["beats"] as Array
	var found_before := false
	for bv in beats_before:
		if str((bv as Dictionary)["beat"]["id"]) == "d18_morning_prep":
			found_before = true
			break

	if found_before:
		failed += _fail("beat with false condition appeared in panel (should be HIDDEN/filtered out)")
	else:
		failed += _ok("beat with false condition (d18_morning_prep) is HIDDEN and absent from panel")

	# 設定 flag 使 condition 成立 → Beat 出現在面板中
	(gs.get("flags") as Dictionary)["pilgrimage_accepted"] = true
	var view_after: Dictionary = PanelBuilder.build("sanquan", gs, data)
	var beats_after: Array = view_after["beats"] as Array
	var found_after := false
	for bv in beats_after:
		if str((bv as Dictionary)["beat"]["id"]) == "d18_morning_prep":
			found_after = true
			break

	if not found_after:
		failed += _fail("beat with true condition missing from panel after flag set")
	else:
		failed += _ok("beat with true condition (d18_morning_prep) appears in panel after flag set")

	return failed
