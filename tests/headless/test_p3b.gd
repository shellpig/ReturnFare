extends SceneTree

## P3-B headless 驗收測試：
## 進入夜間地點原子入口 enter_night_location（八碼拒絕矩陣、狀態零變化、順序優先序）、
## 首次收費與重進不收、跨輪（第二輪）重進終身不收、撞 cap BE 仍記 seen、
## main.gd 真入口 BE 演出（不誤開舊面板）、would_night_entry_end_run 預判、
## _record_forced_night_visit、night_seen condition 求值、
## Lint 13 舊旗標退場檢查（含槽級獨立負向 fixture）、
## night_seen 引用檢查負向 fixture、阿宏鏈結構性斷言。

const DataLoader := preload("res://scripts/data_loader.gd")
const ConditionEval := preload("res://scripts/core/condition_eval.gd")
const PlaythroughGreedy := preload("res://tests/headless/playthrough_greedy.gd")

func _initialize() -> void:
	var data_node: Node = PlaythroughGreedy.setup_data(self)
	var gs: Node = PlaythroughGreedy.setup_game_state(self, data_node)

	await process_frame

	if not data_node.get("ok"):
		push_error("P3-B: Data failed to load; abort")
		quit(1)
		return

	var failed := 0
	failed += _test_rejection_matrix(gs, data_node)
	failed += _test_too_early_precedence(gs, data_node)
	failed += _test_entry_cost_and_idempotency(gs, data_node)
	failed += _test_meta_persistence_and_serialization(gs, data_node)
	failed += _test_cap_be_seen_retention(gs, data_node)
	failed += await _test_main_scene_cap_be_screen(self, gs, data_node)
	failed += _test_would_night_entry_end_run(gs, data_node)
	failed += _test_record_forced_night_visit(gs, data_node)
	failed += _test_night_seen_condition(gs, data_node)
	failed += _test_lint_legacy_night_flags(data_node)
	failed += _test_night_seen_reference_fixtures()
	failed += _test_ahong_chain_structure(data_node)

	if failed > 0:
		push_error("\nP3-B: %d assertion(s) failed" % failed)
		quit(1)
	else:
		print("\nP3-B: all tests passed")
		quit(0)


func _ok(msg: String) -> int:
	print("  ok  " + msg)
	return 0


func _fail(msg: String) -> int:
	push_error("  FAIL  " + msg)
	return 1


func _reset_gs(gs: Node) -> void:
	# P5-D：fresh state 是 opening，本檔驗的是 run 層規則。
	gs.set("flow_mode", "run")
	(gs.get("active_ending") as Dictionary).clear()
	PlaythroughGreedy.start_fresh_run(gs)
	gs.set("night_locations_seen", {})
	gs.set("night_once_beats_seen", {})
	gs.set("knowledge", {})
	gs.set("night_location_chosen", "")
	gs.set("night_sleep_pending", false)


# ── 1. 八碼拒絕矩陣與狀態零變化 ─────────────────────────────────────────────

func _test_rejection_matrix(gs: Node, _data_node: Node) -> int:
	print("--- 1. 8-code rejection matrix & zero-state mutation ---")
	var failed := 0

	# 1.1 not_night
	_reset_gs(gs)
	gs.set("day", 6)
	gs.set("phase", "morning")
	var snap_before := (gs.call("serialize") as Dictionary).duplicate(true)
	var res1: Dictionary = gs.call("enter_night_location", "n_ahong_1")
	var snap_after := (gs.call("serialize") as Dictionary).duplicate(true)
	if not bool(res1.get("ok", true)) and str(res1.get("reason_code", "")) == "not_night":
		failed += _ok("1. not_night: 非夜間時段拒絕成功")
	else:
		failed += _fail("1. not_night 失敗: %s" % str(res1))
	if snap_before == snap_after:
		failed += _ok("1. not_night: 拒絕後狀態零變化")
	else:
		failed += _fail("1. not_night 造成狀態變異")

	# 1.2 unknown_location
	_reset_gs(gs)
	gs.set("day", 6)
	gs.set("phase", "night")
	snap_before = (gs.call("serialize") as Dictionary).duplicate(true)
	var res2: Dictionary = gs.call("enter_night_location", "n_nonexistent_loc")
	snap_after = (gs.call("serialize") as Dictionary).duplicate(true)
	if not bool(res2.get("ok", true)) and str(res2.get("reason_code", "")) == "unknown_location":
		failed += _ok("2. unknown_location: 未知地點拒絕成功")
	else:
		failed += _fail("2. unknown_location 失敗: %s" % str(res2))
	if snap_before == snap_after:
		failed += _ok("2. unknown_location: 拒絕後狀態零變化")
	else:
		failed += _fail("2. unknown_location 造成狀態變異")

	# 1.3 not_night_layer
	_reset_gs(gs)
	gs.set("day", 6)
	gs.set("phase", "night")
	snap_before = (gs.call("serialize") as Dictionary).duplicate(true)
	var res3: Dictionary = gs.call("enter_night_location", "temple")
	snap_after = (gs.call("serialize") as Dictionary).duplicate(true)
	if not bool(res3.get("ok", true)) and str(res3.get("reason_code", "")) == "not_night_layer":
		failed += _ok("3. not_night_layer: 白天地點於夜間拒絕成功")
	else:
		failed += _fail("3. not_night_layer 失敗: %s" % str(res3))
	if snap_before == snap_after:
		failed += _ok("3. not_night_layer: 拒絕後狀態零變化")
	else:
		failed += _fail("3. not_night_layer 造成狀態變異")

	# 1.4 teaser
	_reset_gs(gs)
	gs.set("day", 45)
	gs.set("phase", "night")
	snap_before = (gs.call("serialize") as Dictionary).duplicate(true)
	var res4: Dictionary = gs.call("enter_night_location", "n_corridor_end")
	snap_after = (gs.call("serialize") as Dictionary).duplicate(true)
	if not bool(res4.get("ok", true)) and str(res4.get("reason_code", "")) == "teaser":
		failed += _ok("4. teaser: teaser_only 地點拒絕成功")
	else:
		failed += _fail("4. teaser 失敗: %s" % str(res4))
	if snap_before == snap_after:
		failed += _ok("4. teaser: 拒絕後狀態零變化")
	else:
		failed += _fail("4. teaser 造成狀態變異")

	# 1.5 too_early
	_reset_gs(gs)
	gs.set("day", 6)
	gs.set("phase", "night")
	snap_before = (gs.call("serialize") as Dictionary).duplicate(true)
	var res5: Dictionary = gs.call("enter_night_location", "n_ahong_2") # earliest_night: 11
	snap_after = (gs.call("serialize") as Dictionary).duplicate(true)
	if not bool(res5.get("ok", true)) and str(res5.get("reason_code", "")) == "too_early":
		failed += _ok("5. too_early: 未達 earliest_night 地點拒絕成功")
	else:
		failed += _fail("5. too_early 失敗: %s" % str(res5))
	if snap_before == snap_after:
		failed += _ok("5. too_early: 拒絕後狀態零變化")
	else:
		failed += _fail("5. too_early 造成狀態變異")

	# 1.6 locked
	_reset_gs(gs)
	gs.set("day", 11)
	gs.set("phase", "night")
	var exp_n_ahong_2_reason := str((_data_node.get("loader").locations.get("n_ahong_2", {}) as Dictionary).get("reject_reason", ""))
	assert(not exp_n_ahong_2_reason.is_empty(), "fixture 前提：n_ahong_2 有 reject_reason")
	# 未見過 n_ahong_1
	snap_before = (gs.call("serialize") as Dictionary).duplicate(true)
	var res6: Dictionary = gs.call("enter_night_location", "n_ahong_2")
	snap_after = (gs.call("serialize") as Dictionary).duplicate(true)
	if not bool(res6.get("ok", true)) and str(res6.get("reason_code", "")) == "locked" and str(res6.get("reason_text", "")) == exp_n_ahong_2_reason:
		failed += _ok("6. locked: 門檻未達成拒絕成功並附 reject_reason")
	else:
		failed += _fail("6. locked 失敗: %s" % str(res6))
	if snap_before == snap_after:
		failed += _ok("6. locked: 拒絕後狀態零變化")
	else:
		failed += _fail("6. locked 造成狀態變異")

	# 1.7 already_chosen
	_reset_gs(gs)
	gs.set("day", 6)
	gs.set("phase", "night")
	var entry_ok: Dictionary = gs.call("enter_night_location", "n_ahong_1")
	if not bool(entry_ok.get("ok", false)):
		return failed + _fail("進入 n_ahong_1 失敗")
	snap_before = (gs.call("serialize") as Dictionary).duplicate(true)
	var res7: Dictionary = gs.call("enter_night_location", "n_woodtags")
	snap_after = (gs.call("serialize") as Dictionary).duplicate(true)
	if not bool(res7.get("ok", true)) and str(res7.get("reason_code", "")) == "already_chosen":
		failed += _ok("7. already_chosen: 當夜已選地點後拒絕進入第二個地點")
	else:
		failed += _fail("7. already_chosen 失敗: %s" % str(res7))
	if snap_before == snap_after:
		failed += _ok("7. already_chosen: 拒絕後狀態零變化")
	else:
		failed += _fail("7. already_chosen 造成狀態變異")

	# 1.8 already_slept
	_reset_gs(gs)
	gs.set("day", 6)
	gs.set("phase", "night")
	gs.set("night_sleep_pending", true)
	snap_before = (gs.call("serialize") as Dictionary).duplicate(true)
	var res8: Dictionary = gs.call("enter_night_location", "n_ahong_1")
	snap_after = (gs.call("serialize") as Dictionary).duplicate(true)
	if not bool(res8.get("ok", true)) and str(res8.get("reason_code", "")) == "already_slept":
		failed += _ok("8. already_slept: 當夜已就寢後拒絕進入地點")
	else:
		failed += _fail("8. already_slept 失敗: %s" % str(res8))
	if snap_before == snap_after:
		failed += _ok("8. already_slept: 拒絕後狀態零變化")
	else:
		failed += _fail("8. already_slept 造成狀態變異")

	return failed


# ── 2. too_early vs locked 順序優先序 ────────────────────────────────────────

func _test_too_early_precedence(gs: Node, _data_node: Node) -> int:
	print("--- 2. too_early vs locked precedence ---")
	var failed := 0
	_reset_gs(gs)

	# 第 6 夜：n_ahong_2（earliest_night: 11，requires: night_seen: n_ahong_1）
	# 此時既未到 earliest_night (too_early)，也未滿足 requires (locked)
	gs.set("day", 6)
	gs.set("phase", "night")

	var res: Dictionary = gs.call("enter_night_location", "n_ahong_2")
	if str(res.get("reason_code", "")) == "too_early":
		failed += _ok("同時符合 too_early 與 locked 時，依順序優先回傳 too_early")
	else:
		failed += _fail("too_early vs locked 優先序不符 (實際: %s)" % str(res))

	return failed


# ── 3. 首次收費、重進不收與免費地點 ──────────────────────────────────────────

func _test_entry_cost_and_idempotency(gs: Node, _data_node: Node) -> int:
	print("--- 3. cost deduction, idempotency & free locations ---")
	var failed := 0
	_reset_gs(gs)

	gs.set("day", 6)
	gs.set("phase", "night")

	# 首次進入收費地點 n_ahong_1 (madness_cost: 1)
	var res1: Dictionary = gs.call("enter_night_location", "n_ahong_1")
	var lines1: PackedStringArray = res1.get("lines", PackedStringArray())
	var hand1: Array = gs.get("hand")
	var chosen1: String = str(gs.get("night_location_chosen"))
	var seen1: Dictionary = gs.get("night_locations_seen")

	if bool(res1.get("ok", false)) and lines1.size() > 0 and lines1[0].contains("發狂卡") and hand1.has("madness#1") and chosen1 == "n_ahong_1" and bool(seen1.get("n_ahong_1", false)):
		failed += _ok("首次進入收費地點回傳文字、發放發狂卡、記錄 chosen 與 meta seen")
	else:
		failed += _fail("首次進入收費地點狀態異常: res=%s, hand=%s, chosen=%s, seen=%s" % [str(res1), str(hand1), chosen1, str(seen1)])

	# 跨日到第 7 夜再次進入 n_ahong_1 (同輪重進)
	gs.call("advance_phase") # D7 morning
	gs.call("advance_phase") # D7 afternoon
	gs.call("advance_phase") # D7 evening
	gs.call("advance_phase") # D7 night

	var res2: Dictionary = gs.call("enter_night_location", "n_ahong_1")
	var lines2: PackedStringArray = res2.get("lines", PackedStringArray())
	var hand2: Array = gs.get("hand")
	var chosen2: String = str(gs.get("night_location_chosen"))

	if bool(res2.get("ok", false)) and lines2.is_empty() and hand2.size() == hand1.size() and chosen2 == "n_ahong_1":
		failed += _ok("再次進入已 seen 收費地點回傳 ok:true、空文字行且不重複扣費/發卡")
	else:
		failed += _fail("重複進入收費地點狀態異常: res=%s, lines=%s, hand=%s, chosen=%s" % [str(res2), str(lines2), str(hand2), chosen2])

	# 免費地點 n_woodtags (madness_cost: 0)
	_reset_gs(gs)
	gs.set("day", 6)
	gs.set("phase", "night")

	var res_free: Dictionary = gs.call("enter_night_location", "n_woodtags")
	var lines_free: PackedStringArray = res_free.get("lines", PackedStringArray())
	var hand_free: Array = gs.get("hand")
	var seen_free: Dictionary = gs.get("night_locations_seen")

	if bool(res_free.get("ok", false)) and lines_free.is_empty() and hand_free == ["protagonist"] and bool(seen_free.get("n_woodtags", false)):
		failed += _ok("進入免費地點不發卡、回傳空文字行、記錄 meta seen 且成功進入")
	else:
		failed += _fail("免費地點進入狀態異常: res=%s, lines=%s, hand=%s, seen=%s" % [str(res_free), str(lines_free), str(hand_free), str(seen_free)])

	return failed


# ── 4. 跨輪保留、第二輪重進不收費與序列化往返 ─────────────────────────────────

func _test_meta_persistence_and_serialization(gs: Node, _data_node: Node) -> int:
	print("--- 4. meta persistence across run_reset, Loop 2 re-entry & serialization ---")
	var failed := 0
	_reset_gs(gs)

	gs.set("day", 14)
	gs.set("phase", "night")
	gs.call("enter_night_location", "n_ahong_1")

	# run_reset 重置 run 層但保留 meta
	PlaythroughGreedy.start_fresh_run(gs)

	var seen_after: Dictionary = gs.get("night_locations_seen")
	var chosen_after: String = str(gs.get("night_location_chosen"))
	var slept_after: bool = bool(gs.get("night_sleep_pending"))

	if bool(seen_after.get("n_ahong_1", false)) and chosen_after.is_empty() and not slept_after:
		failed += _ok("run_reset 後 meta night_locations_seen 保留，run 層 chosen 與 sleep_pending 清空")
	else:
		failed += _fail("run_reset meta/run 分離異常 (seen=%s, chosen=%s, slept=%s)" % [str(seen_after), chosen_after, str(slept_after)])

	# 第二輪（跨輪）再次進入已 seen 收費地點（終身首次收費反證）：
	gs.set("day", 6)
	gs.set("phase", "night")
	var res_loop2: Dictionary = gs.call("enter_night_location", "n_ahong_1")
	var lines_loop2: PackedStringArray = res_loop2.get("lines", PackedStringArray())
	var hand_loop2: Array = gs.get("hand")
	if bool(res_loop2.get("ok", false)) and lines_loop2.is_empty() and hand_loop2 == ["protagonist"]:
		failed += _ok("第二輪（跨輪）再次進入已 seen 收費地點回傳 ok:true、空提示行且不收費發卡")
	else:
		failed += _fail("跨輪重進收費地點異常: res=%s, lines=%s, hand=%s" % [str(res_loop2), str(lines_loop2), str(hand_loop2)])

	# 序列化往返
	gs.set("day", 8)
	gs.set("phase", "night")
	gs.set("night_locations_seen", { "n_ahong_1": true, "n_source": true })
	gs.set("night_once_beats_seen", { "beat_test_once": true })
	gs.set("night_location_chosen", "n_source")
	gs.set("night_sleep_pending", true)

	var saved: Dictionary = gs.call("serialize")

	_reset_gs(gs)
	gs.call("deserialize", saved)

	var res_seen: Dictionary = gs.get("night_locations_seen")
	var res_once: Dictionary = gs.get("night_once_beats_seen")
	var res_chosen: String = str(gs.get("night_location_chosen"))
	var res_slept: bool = bool(gs.get("night_sleep_pending"))

	if res_seen.has("n_ahong_1") and res_seen.has("n_source") and res_once.has("beat_test_once") and res_chosen == "n_source" and res_slept:
		failed += _ok("serialize / deserialize 完整還原 meta (seen/once) 與 run (chosen/sleep_pending)")
	else:
		failed += _fail("序列化還原異常: seen=%s, once=%s, chosen=%s, slept=%s" % [str(res_seen), str(res_once), res_chosen, str(res_slept)])

	return failed


# ── 5. 撞 Cap BE 仍記 seen ──────────────────────────────────────────────────

func _test_cap_be_seen_retention(gs: Node, _data_node: Node) -> int:
	print("--- 5. cap BE retains seen location in meta ---")
	var failed := 0
	_reset_gs(gs)

	# 手上塞滿 6 張發狂卡（tuning madness_cap = 7）
	for i in range(6):
		gs.call("gain_card", "madness")
	gs.set("day", 7)
	gs.set("phase", "night")

	var emitted_endings: Array[String] = []
	var on_ending_started := func() -> void:
		emitted_endings.append(str((gs.get("active_ending") as Dictionary).get("ending_id", "")))
	gs.connect("ending_started", on_ending_started)

	# 進入 cost=1 的收費地點 n_source -> 湊齊 7 張觸發 ending_madness_be
	var res: Dictionary = gs.call("enter_night_location", "n_source")

	var day_after: int = int(gs.get("day"))
	var phase_after: String = str(gs.get("phase"))
	var seen_after: Dictionary = gs.get("night_locations_seen")

	# P5-B：撞 cap 改為啟動結局狀態機，day／phase 不動、run 不清；meta seen 一樣要留著。
	if emitted_endings == ["ending_madness_be"] and str(gs.get("flow_mode")) == "ending" \
			and day_after == 7 and phase_after == "night" and bool(seen_after.get("n_source", false)):
		failed += _ok("進入地點撞 cap 啟動發瘋 BE，停在原時段且 meta night_locations_seen 仍記錄 n_source")
	else:
		failed += _fail("撞 cap BE 狀態異常: endings=%s, mode=%s, day=%d, phase=%s, seen=%s" % [str(emitted_endings), str(gs.get("flow_mode")), day_after, phase_after, str(seen_after)])

	# BE 發生時不回傳 marker 文字行
	if (res.get("lines", PackedStringArray()) as PackedStringArray).is_empty():
		failed += _ok("撞 cap 結束本輪時不回傳 marker 提示文字行")
	else:
		failed += _fail("撞 cap 時不應回傳提示文字 (lines: %s)" % str(res.get("lines")))

	gs.disconnect("ending_started", on_ending_started)
	return failed


# ── 6. main.gd 真入口 BE 演出（不誤開舊面板） ────────────────────────────────

func _test_main_scene_cap_be_screen(tree: SceneTree, gs: Node, _data_node: Node) -> int:
	print("--- 6. main.gd real entry point triggers BE screen without opening old panel ---")
	var failed := 0
	_reset_gs(gs)

	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var main: Control = main_scene.instantiate() as Control
	tree.get_root().add_child(main)
	await tree.process_frame

	for i in range(6):
		gs.call("gain_card", "madness")
	gs.set("day", 6)
	gs.set("phase", "night")
	main.call("_refresh_status")
	main.call("_route_view")

	var map_list: Node = main.get_node("ContentView/MapList")
	var loc_panel: Node = main.get_node("ContentView/LocationPanel")
	var flow_text: Node = main.get_node("ContentView/FlowText")

	# P3-D 流程：點擊地點清單開啟詳情，再點擊進入按鈕觸發 cap BE
	main.call("_on_location_selected", "n_ahong_1")
	main.call("_on_night_entry_requested", "n_ahong_1")
	await tree.process_frame

	var ending_panel: Node = main.get_node("ContentView/EndingPanel")
	var is_ending: bool = str(gs.get("flow_mode")) == "ending" or ending_panel.visible
	var ending_flow: FlowText = ending_panel.find_child("EndingFlowText", true, false) as FlowText
	var ending_text := ending_flow.get_text() if ending_flow != null else ""
	var view_be: Dictionary = gs.call("ending_view")
	var page_text_be := str(view_be.get("page_text", ""))

	var exp_be_text := ""
	var data_node: Node = tree.get_root().get_node("Data")
	var madness_ending: Dictionary = data_node.loader.endings_by_id.get("ending_madness_be", {}) as Dictionary
	for p in (madness_ending.get("first_seen", {}) as Dictionary).get("pages", []):
		exp_be_text = str((p as Dictionary).get("text", "")).substr(0, 5)
		if not exp_be_text.is_empty():
			break
	assert(not exp_be_text.is_empty(), "fixture 前提：ending_madness_be 有 page text")

	if is_ending and ending_panel.visible and not loc_panel.visible and not map_list.visible and (ending_text.contains(exp_be_text) or page_text_be.contains(exp_be_text)):
		failed += _ok("main.gd 真入口點擊夜間地點觸發 BE：畫面切換至 EndingPanel 顯示發狂 BE 且未開啟 LocationPanel")
	else:
		failed += _fail("main.gd BE 畫面狀態異常: ending=%s, ending_vis=%s, panel_vis=%s" % [
			str(is_ending), str(ending_panel.visible), str(loc_panel.visible)
		])

	# P5-B：結局啟動後 run 不清空，推進按鈕也不得偷推時間（正式結局畫面在 P5-E）。
	main.call("_on_advance_pressed")
	await tree.process_frame

	var day_after: int = int(gs.get("day"))
	var phase_after: String = str(gs.get("phase"))
	var seen_after: bool = bool(gs.call("night_location_seen", "n_ahong_1"))
	if str(gs.get("flow_mode")) == "ending" and day_after == 6 and phase_after == "night" and seen_after:
		failed += _ok("BE 啟動後停在原時段，meta night_locations_seen 成功保留")
	else:
		failed += _fail("BE 後狀態異常: mode=%s, day=%d, phase=%s, seen=%s" % [str(gs.get("flow_mode")), day_after, phase_after, str(seen_after)])

	# legacy run_reset 收尾（P5-D 由 complete_ending() 取代）
	PlaythroughGreedy.start_fresh_run(gs)
	if int(gs.get("day")) == 1 and str(gs.get("phase")) == "morning" and bool(gs.call("night_location_seen", "n_ahong_1")):
		failed += _ok("legacy run_reset 後乾淨重啟至 D1 morning，且 meta night_locations_seen 成功保留")
	else:
		failed += _fail("legacy run_reset 後狀態異常: day=%d, phase=%s" % [int(gs.get("day")), str(gs.get("phase"))])

	main.queue_free()
	await tree.process_frame
	return failed


# ── 7. would_night_entry_end_run 預判 ────────────────────────────────────────

func _test_would_night_entry_end_run(gs: Node, _data_node: Node) -> int:
	print("--- 7. would_night_entry_end_run query ---")
	var failed := 0
	_reset_gs(gs)

	# 0 張發狂卡時進入 n_ahong_1 (cost 1) 不會 BE
	gs.set("day", 6)
	gs.set("phase", "night")
	if not bool(gs.call("would_night_entry_end_run", "n_ahong_1")):
		failed += _ok("0 張發狂卡時預判進入 n_ahong_1 不會 BE (false)")
	else:
		failed += _fail("0 張發狂卡時預判錯誤")

	# 手上 6 張發狂卡時預判進入 n_ahong_1 (cost 1) 會 BE
	for i in range(6):
		gs.call("gain_card", "madness")
	if bool(gs.call("would_night_entry_end_run", "n_ahong_1")):
		failed += _ok("6 張發狂卡時預判進入未到訪 n_ahong_1 會觸發 BE (true)")
	else:
		failed += _fail("6 張發狂卡時預判錯誤")

	# 若該地點已經 seen，再次進入 cost 為 0，不會 BE
	gs.set("night_locations_seen", { "n_ahong_1": true })
	if not bool(gs.call("would_night_entry_end_run", "n_ahong_1")):
		failed += _ok("已到訪地點再次進入 cost 為 0，預判不會 BE (false)")
	else:
		failed += _fail("已到訪地點預判錯誤")

	# 免費地點預判不會 BE
	if not bool(gs.call("would_night_entry_end_run", "n_woodtags")):
		failed += _ok("免費地點預判不會 BE (false)")
	else:
		failed += _fail("免費地點預判錯誤")

	return failed


# ── 8. _record_forced_night_visit 私有 helper ────────────────────────────────

func _test_record_forced_night_visit(gs: Node, _data_node: Node) -> int:
	print("--- 8. _record_forced_night_visit helper ---")
	var failed := 0
	_reset_gs(gs)

	gs.set("day", 1)
	gs.set("phase", "night")

	gs.call("_record_forced_night_visit", "n_corridor")

	var chosen: String = str(gs.get("night_location_chosen"))
	var seen: Dictionary = gs.get("night_locations_seen")
	var hand: Array = gs.get("hand")

	if chosen == "n_corridor" and bool(seen.get("n_corridor", false)) and hand == ["protagonist"]:
		failed += _ok("_record_forced_night_visit 成功寫入 chosen 與 seen，且跳過收費發卡")
	else:
		failed += _fail("_record_forced_night_visit 狀態異常 (chosen=%s, seen=%s, hand=%s)" % [chosen, str(seen), str(hand)])

	return failed


# ── 9. night_seen Condition 求值 ────────────────────────────────────────────

func _test_night_seen_condition(gs: Node, _data_node: Node) -> int:
	print("--- 9. night_seen condition evaluation ---")
	var failed := 0
	_reset_gs(gs)

	var cond: Dictionary = { "night_seen": "n_ahong_1" }
	if not ConditionEval.eval(cond, gs):
		failed += _ok("未到訪 n_ahong_1 時 night_seen 條件求值為 false")
	else:
		failed += _fail("未到訪時 night_seen 應為 false")

	gs.set("night_locations_seen", { "n_ahong_1": true })
	if ConditionEval.eval(cond, gs):
		failed += _ok("到訪 n_ahong_1 後 night_seen 條件求值為 true")
	else:
		failed += _fail("到訪後 night_seen 應為 true")

	return failed


# ── 10. Lint 13 舊夜間旗標退場檢查（含槽級獨立負向 fixture） ───────────────

func _test_lint_legacy_night_flags(data_node: Node) -> int:
	print("--- 10. Lint 13 legacy night flags check (including slot-level negative fixtures) ---")
	var failed := 0

	# 10.1 正向：正式資料庫零錯誤
	var clean_errs: PackedStringArray = DataLoader.lint_legacy_night_flags(data_node.loader)
	if clean_errs.is_empty():
		failed += _ok("正式資料庫通過 Lint 13 舊旗標檢查（0 錯誤）")
	else:
		failed += _fail("正式資料庫含有舊夜間旗標: %s" % str(clean_errs))

	# 10.2 負向：location 級
	var mock_loc := DataLoader.new()
	mock_loc.locations = {
		"loc_bad": { "id": "loc_bad", "requires": { "flag": "opened_n_loc_bad" } }
	}
	var errs_loc: PackedStringArray = DataLoader.lint_legacy_night_flags(mock_loc)
	if errs_loc.size() == 1 and errs_loc[0].contains("loc_bad"):
		failed += _ok("負向 fixture 1: location.requires 中的 opened_n_* 被成功攔截")
	else:
		failed += _fail("location.requires 舊旗標未正確攔截: %s" % str(errs_loc))

	# 10.3 負向：beat 級 on_enter
	var mock_beat := DataLoader.new()
	mock_beat.beats = [
		{ "id": "beat_bad", "on_enter": { "flag": { "opened_n_beat_bad": true } } }
	]
	var errs_beat: PackedStringArray = DataLoader.lint_legacy_night_flags(mock_beat)
	if errs_beat.size() == 1 and errs_beat[0].contains("beat_bad"):
		failed += _ok("負向 fixture 2: beat.on_enter 中的 opened_n_* 被成功攔截")
	else:
		failed += _fail("beat.on_enter 舊旗標未正確攔截: %s" % str(errs_beat))

	# 10.4 負向：slot 級 requires
	var mock_slot_req := DataLoader.new()
	mock_slot_req.beats = [
		{
			"id": "beat_slot_req",
			"slots": [
				{ "id": "s1", "requires": { "flag": "opened_n_slot_req" } }
			]
		}
	]
	var errs_slot_req: PackedStringArray = DataLoader.lint_legacy_night_flags(mock_slot_req)
	if errs_slot_req.size() == 1 and errs_slot_req[0].contains("beat_slot_req"):
		failed += _ok("負向 fixture 3: slot.requires 中的 opened_n_* 被成功攔截")
	else:
		failed += _fail("slot.requires 舊旗標未正確攔截: %s" % str(errs_slot_req))

	# 10.5 負向：slot 級 on_place
	var mock_slot_place := DataLoader.new()
	mock_slot_place.beats = [
		{
			"id": "beat_slot_place",
			"slots": [
				{ "id": "s2", "on_place": { "flag": { "opened_n_slot_place": true } } }
			]
		}
	]
	var errs_slot_place: PackedStringArray = DataLoader.lint_legacy_night_flags(mock_slot_place)
	if errs_slot_place.size() == 1 and errs_slot_place[0].contains("beat_slot_place"):
		failed += _ok("負向 fixture 4: slot.on_place 中的 opened_n_* 被成功攔截")
	else:
		failed += _fail("slot.on_place 舊旗標未正確攔截: %s" % str(errs_slot_place))

	# 10.6 負向：slot 級 condition
	var mock_slot_cond := DataLoader.new()
	mock_slot_cond.beats = [
		{
			"id": "beat_slot_cond",
			"slots": [
				{ "id": "s3", "condition": { "flag": "opened_n_slot_cond" } }
			]
		}
	]
	var errs_slot_cond: PackedStringArray = DataLoader.lint_legacy_night_flags(mock_slot_cond)
	if errs_slot_cond.size() == 1 and errs_slot_cond[0].contains("beat_slot_cond"):
		failed += _ok("負向 fixture 5: slot.condition 中的 opened_n_* 被成功攔截")
	else:
		failed += _fail("slot.condition 舊旗標未正確攔截: %s" % str(errs_slot_cond))

	return failed


# ── 11. night_seen 引用檢查負向 fixture ─────────────────────────────────────

func _test_night_seen_reference_fixtures() -> int:
	print("--- 11. night_seen reference validation negative fixtures ---")
	var failed := 0

	# 11.1 未知地點 id（在 location.requires 與 beat.requires）
	var mock_unknown := DataLoader.new()
	mock_unknown.cards = { "protagonist": { "id": "protagonist", "type": "character" } }
	mock_unknown.locations = {
		"loc_valid": { "id": "loc_valid", "layer": "night", "requires": { "night_seen": "nonexistent_loc_1" } }
	}
	mock_unknown.beats = [
		{
			"id": "beat_unknown",
			"location": "loc_valid",
			"requires": { "night_seen": "nonexistent_loc_2" }
		}
	]
	var errs_unknown: PackedStringArray = mock_unknown.verify_references()
	var has_loc_unknown := false
	var has_beat_unknown := false
	for e in errs_unknown:
		if e.contains("nonexistent_loc_1") and e.contains("引用不存在的地點"):
			has_loc_unknown = true
		if e.contains("nonexistent_loc_2") and e.contains("引用不存在的地點"):
			has_beat_unknown = true

	if has_loc_unknown and has_beat_unknown:
		failed += _ok("night_seen 引用不存在的地點 id 成功被 verify_references 攔截")
	else:
		failed += _fail("night_seen 未知地點負向攔截不符: %s" % str(errs_unknown))

	# 11.2 引用的地點不是夜間地點 (layer != "night")
	var mock_day_layer := DataLoader.new()
	mock_day_layer.cards = { "protagonist": { "id": "protagonist", "type": "character" } }
	mock_day_layer.locations = {
		"loc_day": { "id": "loc_day", "layer": "day" },
		"loc_night": { "id": "loc_night", "layer": "night", "requires": { "night_seen": "loc_day" } }
	}
	mock_day_layer.beats = [
		{
			"id": "beat_day_ref",
			"location": "loc_night",
			"requires": { "night_seen": "loc_day" }
		}
	]
	var errs_day_layer: PackedStringArray = mock_day_layer.verify_references()
	var has_day_loc_err := false
	var has_day_beat_err := false
	for e in errs_day_layer:
		if e.contains("loc_day") and e.contains("引用的地點不是夜間地點"):
			if e.contains("loc_night"):
				has_day_loc_err = true
			if e.contains("beat_day_ref"):
				has_day_beat_err = true

	if has_day_loc_err and has_day_beat_err:
		failed += _ok("night_seen 引用非夜間地點 (layer != 'night') 成功被 verify_references 攔截")
	else:
		failed += _fail("night_seen 白天地點負向攔截不符: %s" % str(errs_day_layer))

	return failed


# ── 12. 阿宏鏈結構性斷言 ───────────────────────────────────────────────────

func _test_ahong_chain_structure(data_node: Node) -> int:
	print("--- 12. Ahong chain structural assertions ---")
	var failed := 0
	var loader: DataLoader = data_node.loader

	# 1. n_ahong_1 (earliest 6, cost 1, no requires)
	var l1: Dictionary = loader.locations.get("n_ahong_1", {})
	if int(l1.get("madness_cost", 0)) == 1 and int(l1.get("earliest_night", 0)) == 6 and not l1.has("requires"):
		failed += _ok("n_ahong_1: cost 1, earliest 6, 無 requires")
	else:
		failed += _fail("n_ahong_1 結構不符: %s" % str(l1))

	# 2. n_ahong_2 requires { night_seen: n_ahong_1 } 且不含 flag
	var l2: Dictionary = loader.locations.get("n_ahong_2", {})
	if l2.get("requires") == { "night_seen": "n_ahong_1" }:
		failed += _ok("n_ahong_2: requires 為 { night_seen: n_ahong_1 } 且無 run flag")
	else:
		failed += _fail("n_ahong_2 requires 不符: %s" % str(l2.get("requires")))

	# 3. n_ahong_3 requires { night_seen: n_ahong_2 } 且不含 flag
	var l3: Dictionary = loader.locations.get("n_ahong_3", {})
	if l3.get("requires") == { "night_seen": "n_ahong_2" }:
		failed += _ok("n_ahong_3: requires 為 { night_seen: n_ahong_2 } 且無 run flag")
	else:
		failed += _fail("n_ahong_3 requires 不符: %s" % str(l3.get("requires")))

	# 4. n_ahong_4 requires { night_seen: n_ahong_3 } 且不含 flag
	var l4: Dictionary = loader.locations.get("n_ahong_4", {})
	if l4.get("requires") == { "night_seen": "n_ahong_3" }:
		failed += _ok("n_ahong_4: requires 為 { night_seen: n_ahong_3 } 且無 run flag")
	else:
		failed += _fail("n_ahong_4 requires 不符: %s" % str(l4.get("requires")))

	# 5. n_ahong_2_ch1 beat requires info_ahong_private 與 night_seen: n_ahong_1
	var b2: Dictionary = loader.beats_by_id.get("n_ahong_2_ch1", {})
	var b2_req: Dictionary = b2.get("requires", {})
	var b2_all: Array = b2_req.get("all", [])
	if b2_all.has({ "night_seen": "n_ahong_1" }) and b2_all.has({ "has_card": "info_ahong_private" }):
		failed += _ok("n_ahong_2_ch1: beat requires 包含 night_seen: n_ahong_1 與 has_card: info_ahong_private")
	else:
		failed += _fail("n_ahong_2_ch1 requires 不符: %s" % str(b2_req))

	# 6. n_ahong_4_ch2 gives k_ahong_point_1
	var b4: Dictionary = loader.beats_by_id.get("n_ahong_4_ch2", {})
	if (b4.get("on_enter", {}).get("gain", []) as Array).has("k_ahong_point_1"):
		failed += _ok("n_ahong_4_ch2: on_enter.gain 給予 k_ahong_point_1")
	else:
		failed += _fail("n_ahong_4_ch2 未給予 k_ahong_point_1: %s" % str(b4.get("on_enter")))

	# 7. n_ahong_5_ch2 gives k_ahong_point_2
	var b5: Dictionary = loader.beats_by_id.get("n_ahong_5_ch2", {})
	if (b5.get("on_enter", {}).get("gain", []) as Array).has("k_ahong_point_2"):
		failed += _ok("n_ahong_5_ch2: on_enter.gain 給予 k_ahong_point_2")
	else:
		failed += _fail("n_ahong_5_ch2 未給予 k_ahong_point_2: %s" % str(b5.get("on_enter")))

	# 8. n_ahong_6_ch3 gives k_ahong_point_3
	var b6: Dictionary = loader.beats_by_id.get("n_ahong_6_ch3", {})
	if (b6.get("on_enter", {}).get("gain", []) as Array).has("k_ahong_point_3"):
		failed += _ok("n_ahong_6_ch3: on_enter.gain 給予 k_ahong_point_3")
	else:
		failed += _fail("n_ahong_6_ch3 未給予 k_ahong_point_3: %s" % str(b6.get("on_enter")))

	# 9. n_ahong_5 requires k_ahong_point_1
	var l5: Dictionary = loader.locations.get("n_ahong_5", {})
	if l5.get("requires") == { "has_knowledge": "k_ahong_point_1" }:
		failed += _ok("n_ahong_5: requires 為 { has_knowledge: k_ahong_point_1 }")
	else:
		failed += _fail("n_ahong_5 requires 不符: %s" % str(l5.get("requires")))

	# 10. n_ahong_6 requires k_ahong_point_2
	var l6: Dictionary = loader.locations.get("n_ahong_6", {})
	if l6.get("requires") == { "has_knowledge": "k_ahong_point_2" }:
		failed += _ok("n_ahong_6: requires 為 { has_knowledge: k_ahong_point_2 }")
	else:
		failed += _fail("n_ahong_6 requires 不符: %s" % str(l6.get("requires")))

	# 11. n_ahong_7 requires k_ahong_point_1, 2, 3 (count_at_least 3 of 3)
	var l7: Dictionary = loader.locations.get("n_ahong_7", {})
	var l7_cnt: Dictionary = l7.get("requires", {}).get("count_at_least", {})
	var l7_of: Array = l7_cnt.get("of", [])
	if int(l7_cnt.get("n", 0)) == 3 and l7_of.has({ "has_knowledge": "k_ahong_point_1" }) and l7_of.has({ "has_knowledge": "k_ahong_point_2" }) and l7_of.has({ "has_knowledge": "k_ahong_point_3" }):
		failed += _ok("n_ahong_7: requires 為 count_at_least 包含三個對位點知識卡")
	else:
		failed += _fail("n_ahong_7 requires 不符: %s" % str(l7.get("requires")))

	# 12. 卡片定義完整性：k_ahong_point_* 為 slotless 知識卡，info_ahong_private 存在
	var c_priv: Dictionary = loader.cards.get("info_ahong_private", {})
	var c_k1: Dictionary = loader.cards.get("k_ahong_point_1", {})
	var c_k2: Dictionary = loader.cards.get("k_ahong_point_2", {})
	var c_k3: Dictionary = loader.cards.get("k_ahong_point_3", {})
	if not c_priv.is_empty() and bool(c_k1.get("slotless", false)) and bool(c_k2.get("slotless", false)) and bool(c_k3.get("slotless", false)):
		failed += _ok("info_ahong_private 存在且 k_ahong_point_1~3 均為 slotless 知識卡")
	else:
		failed += _fail("阿宏鏈卡片定義不符")

	return failed
