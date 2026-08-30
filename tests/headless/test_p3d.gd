extends SceneTree

## P3-D headless 驗收測試：夜間地點清單與詳情 UI view model、穩定排序、狀態文字、門檻理由、風險警告、teaser 與無內容地點。

const PlaythroughGreedy := preload("res://tests/headless/playthrough_greedy.gd")
const ConditionEval := preload("res://scripts/core/condition_eval.gd")

func _initialize() -> void:
	var data_node: Node = PlaythroughGreedy.setup_data(self)
	var gs: Node = PlaythroughGreedy.setup_game_state(self, data_node)

	await process_frame

	if not data_node.get("ok"):
		push_error("P3-D: Data failed to load; abort")
		quit(1)
		return

	var failed := 0
	print("\n=== P3-D Headless Test Suite ===")

	failed += _test_stable_order_and_seen_knowledge_invariance(gs, data_node)
	failed += _test_status_text_and_display_name_rules(gs, data_node)
	failed += _test_teaser_only_chapter_gating_and_reason(gs, data_node)
	failed += _test_gating_and_closed_reject_matrix(gs, data_node)
	failed += _test_risk_warning_near_cap_and_seen_cleared(gs, data_node)
	failed += _test_empty_result_location_summary_and_entry(gs, data_node)
	failed += _test_state_immutability_on_summary_calls(gs, data_node)

	if failed == 0:
		print("\nP3-D: all tests passed\n")
		quit(0)
	else:
		printerr("\nP3-D: %d test(s) failed\n" % failed)
		quit(1)


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


func _ok(msg: String) -> int:
	print("  ok  %s" % msg)
	return 0


func _fail(msg: String) -> int:
	printerr("  FAIL  %s" % msg)
	return 1


# ── 1. 清單穩定排序與狀態改變不跳位 ──────────────────────────────────────────

func _test_stable_order_and_seen_knowledge_invariance(gs: Node, data_node: Node) -> int:
	print("--- 1. Stable order by earliest_night + data order, immutable under state changes ---")
	var failed := 0
	_reset_gs(gs)

	gs.set("day", 14)
	gs.set("phase", "night")

	var initial_locs: Array[String] = PanelBuilder.available_locations(gs, data_node)
	if initial_locs.is_empty():
		return failed + _fail("D14 night available_locations 為空")

	# 驗證 earliest_night 升序
	var prev_earliest := -1
	for loc_id in initial_locs:
		var loc: Dictionary = data_node.loader.locations[loc_id] as Dictionary
		var earliest := int(loc.get("earliest_night", 999))
		if earliest < prev_earliest:
			failed += _fail("地點 %s earliest_night (%d) 小於前一地點 (%d)，排序未升序" % [loc_id, earliest, prev_earliest])
		prev_earliest = earliest
	if failed == 0:
		failed += _ok("D14 可見地點按 earliest_night 嚴格升序")

	# 依序改 seen 與 knowledge
	var seen_dict: Dictionary = gs.get("night_locations_seen") as Dictionary
	seen_dict["n_ahong_1"] = true
	seen_dict["n_landmark"] = true
	(gs.get("knowledge") as Dictionary)["k_ahong_story"] = true

	var after_state_locs: Array[String] = PanelBuilder.available_locations(gs, data_node)
	if after_state_locs == initial_locs:
		failed += _ok("改動 seen 與 knowledge 後，available_locations 清單順序與項目逐字不變")
	else:
		failed += _fail("改動 seen/knowledge 後 available_locations 發生跳位或項目漂移")

	# 選擇地點後，available_locations 仍保留全部當前可見 row
	gs.set("night_location_chosen", "n_ahong_1")
	var after_chosen_locs: Array[String] = PanelBuilder.available_locations(gs, data_node)
	if after_chosen_locs == initial_locs:
		failed += _ok("選定地點後，available_locations 仍保留全部開放 row 與原排序（不收縮）")
	else:
		failed += _fail("選定地點後 available_locations 收縮或排序異常: %s" % str(after_chosen_locs))

	return failed


# ── 2. 四種狀態文字與顯示名稱（一對一／多對一對位） ──────────────────────────

func _test_status_text_and_display_name_rules(gs: Node, data_node: Node) -> int:
	print("--- 2. Status texts and display names (1-to-1 & multi-to-1) ---")
	var failed := 0
	_reset_gs(gs)

	gs.set("day", 14)
	gs.set("phase", "night")

	var exp_n_exit_name := str((data_node.loader.locations.get("n_exit", {}) as Dictionary).get("name", ""))
	var exp_n_landmark_name := str((data_node.loader.locations.get("n_landmark", {}) as Dictionary).get("name", ""))
	var exp_sanquan_name := str((data_node.loader.locations.get("sanquan", {}) as Dictionary).get("name", ""))
	var exp_jinghe_back_name := str((data_node.loader.locations.get("jinghe_back", {}) as Dictionary).get("name", ""))
	var exp_n_corridor_name := str((data_node.loader.locations.get("n_corridor", {}) as Dictionary).get("name", ""))
	assert(not exp_n_exit_name.is_empty(), "fixture 前提：n_exit 有 name")
	assert(not exp_n_landmark_name.is_empty(), "fixture 前提：n_landmark 有 name")
	assert(not exp_sanquan_name.is_empty(), "fixture 前提：sanquan 有 name")
	assert(not exp_jinghe_back_name.is_empty(), "fixture 前提：jinghe_back 有 name")
	assert(not exp_n_corridor_name.is_empty(), "fixture 前提：n_corridor 有 name")

	# 1. 未到訪可對位 row (n_exit -> day_counterpart: sanquan, 引子名: 石階外的鎮)
	var s_unseen_cp := PanelBuilder.location_summary("n_exit", gs, data_node)
	if str(s_unseen_cp.get("status_text")) == "[尚未到訪]" and str(s_unseen_cp.get("display_name")) == exp_n_exit_name:
		failed += _ok("未到訪可對位 row 顯示引子名與 [尚未到訪]")
	else:
		failed += _fail("未到訪可對位 row 狀態文字異常: %s" % str(s_unseen_cp))

	# 2. 未到訪夜間限定 row (n_landmark -> day_counterpart: null, 引子名: 地標)
	var s_unseen_no_cp := PanelBuilder.location_summary("n_landmark", gs, data_node)
	if str(s_unseen_no_cp.get("status_text")) == "[尚未到訪]" and str(s_unseen_no_cp.get("display_name")) == exp_n_landmark_name:
		failed += _ok("未到訪夜間限定 row 顯示引子名與 [尚未到訪]")
	else:
		failed += _fail("未到訪夜間限定 row 狀態文字異常: %s" % str(s_unseen_no_cp))

	# 3. 已到訪、未對位 (n_exit seen, knowledge 缺 k_night_sanquan)
	(gs.get("night_locations_seen") as Dictionary)["n_exit"] = true
	var s_seen_unaligned := PanelBuilder.location_summary("n_exit", gs, data_node)
	if str(s_seen_unaligned.get("status_text")) == "[已到訪，尚未對位]" and str(s_seen_unaligned.get("display_name")) == exp_n_exit_name:
		failed += _ok("已到訪未對位 row 顯示 [已到訪，尚未對位] 且維持引子名")
	else:
		failed += _fail("已到訪未對位 row 狀態文字異常: %s" % str(s_seen_unaligned))

	# 4. 已到訪夜間限定 row (n_landmark seen, day_counterpart == null)
	(gs.get("night_locations_seen") as Dictionary)["n_landmark"] = true
	var s_seen_night_only := PanelBuilder.location_summary("n_landmark", gs, data_node)
	if str(s_seen_night_only.get("status_text")) == "[已到訪]" and str(s_seen_night_only.get("display_name")) == exp_n_landmark_name:
		failed += _ok("已到訪夜間限定 row 顯示 [已到訪]（無尚未對位）")
	else:
		failed += _fail("已到訪夜間限定 row 狀態文字異常: %s" % str(s_seen_night_only))

	# 5. 已對位一對一 row (n_exit -> sanquan, 僅一筆 night row 指向 sanquan)
	(gs.get("knowledge") as Dictionary)["k_night_sanquan"] = true
	var s_aligned_1to1 := PanelBuilder.location_summary("n_exit", gs, data_node)
	if str(s_aligned_1to1.get("status_text")) == "[已對位]" and str(s_aligned_1to1.get("display_name")) == exp_sanquan_name:
		failed += _ok("已對位一對一 row 顯示白天地點名『山泉閣』與 [已對位]")
	else:
		failed += _fail("已對位一對一 row 狀態文字或名稱異常: %s" % str(s_aligned_1to1))

	# 6. 已對位多對一 row (n_corridor 與 n_steam_below 都指向 jinghe_back)
	(gs.get("night_locations_seen") as Dictionary)["n_corridor"] = true
	(gs.get("knowledge") as Dictionary)["k_night_jinghe_back"] = true
	var s_aligned_multi := PanelBuilder.location_summary("n_corridor", gs, data_node)
	var expected_multi_name := "%s・%s" % [exp_jinghe_back_name, exp_n_corridor_name]
	if str(s_aligned_multi.get("status_text")) == "[已對位]" and str(s_aligned_multi.get("display_name")) == expected_multi_name:
		failed += _ok("已對位多對一 row 顯示『白天地點名・夜間引子名』與 [已對位]")
	else:
		failed += _fail("已對位多對一 row 狀態文字或名稱異常: %s" % str(s_aligned_multi))

	return failed


# ── 3. Teaser-only 章節出現與理由 ──────────────────────────────────────────

func _test_teaser_only_chapter_gating_and_reason(gs: Node, data_node: Node) -> int:
	print("--- 3. Teaser-only chapter visibility, lock and reject reason ---")
	var failed := 0
	_reset_gs(gs)

	# Chapter 1 (Day 10 night): teaser-only 不應在 available_locations 出現
	gs.set("day", 10)
	gs.set("phase", "night")
	var ch1_locs: Array[String] = PanelBuilder.available_locations(gs, data_node)
	if not ch1_locs.has("n_corridor_end"):
		failed += _ok("第 1 章 n_corridor_end 不在 available_locations 出現")
	else:
		failed += _fail("第 1 章 n_corridor_end 錯誤出現於 available_locations")

	# Chapter 2 (Day 20 night): teaser-only 仍不出現
	gs.set("day", 20)
	var ch2_locs: Array[String] = PanelBuilder.available_locations(gs, data_node)
	if not ch2_locs.has("n_corridor_end"):
		failed += _ok("第 2 章 n_corridor_end 不在 available_locations 出現")
	else:
		failed += _fail("第 2 章 n_corridor_end 錯誤出現於 available_locations")

	# Chapter 3 (Day 33 night): teaser-only 正確出現
	gs.set("day", 33)
	var ch3_locs: Array[String] = PanelBuilder.available_locations(gs, data_node)
	if ch3_locs.has("n_corridor_end"):
		failed += _ok("第 3 章 n_corridor_end 正確出現於 available_locations")
	else:
		failed += _fail("第 3 章 n_corridor_end 未出現在 available_locations")

	var exp_n_corridor_end_reason := str((data_node.loader.locations.get("n_corridor_end", {}) as Dictionary).get("reject_reason", ""))
	assert(not exp_n_corridor_end_reason.is_empty(), "fixture 前提：n_corridor_end 有 reject_reason")

	var summary: Dictionary = PanelBuilder.location_summary("n_corridor_end", gs, data_node)
	if bool(summary.get("teaser_only", false)) and not bool(summary.get("can_enter", true)) and str(summary.get("reason_code", "")) == "teaser" and str(summary.get("reason_text", "")) == exp_n_corridor_end_reason and str(summary.get("status_text", "")) == "[尚未到訪]":
		failed += _ok("teaser-only 詳情顯示 [尚未到訪]、can_enter=false、reason_code=teaser、reason_text 等於資料定義")
	else:
		failed += _fail("teaser-only summary 內容異常: %s" % str(summary))

	return failed


# ── 4. 門檻與八碼拒絕矩陣 ──────────────────────────────────────────────────

func _test_gating_and_closed_reject_matrix(gs: Node, data_node: Node) -> int:
	print("--- 4. Location requires gate and closed reject reason matrix ---")
	var failed := 0
	_reset_gs(gs)

	gs.set("day", 14)
	gs.set("phase", "night")

	var exp_n_ahong_2_reason := str((data_node.loader.locations.get("n_ahong_2", {}) as Dictionary).get("reject_reason", ""))
	assert(not exp_n_ahong_2_reason.is_empty(), "fixture 前提：n_ahong_2 有 reject_reason")

	# 1. locked: n_ahong_2 缺少 info_ahong_traces
	var s_locked := PanelBuilder.location_summary("n_ahong_2", gs, data_node)
	if not bool(s_locked.get("can_enter", true)) and str(s_locked.get("reason_code", "")) == "locked" and str(s_locked.get("reason_text", "")) == exp_n_ahong_2_reason:
		failed += _ok("requires 不成立的地點 (n_ahong_2) can_enter=false、reason_code=locked、帶具體理由")
	else:
		failed += _fail("locked 地點 summary 異常: %s" % str(s_locked))

	# 2. too_early: 在 D5 查詢 D6 開放的 n_ahong_1
	gs.set("day", 5)
	var s_early := PanelBuilder.location_summary("n_ahong_1", gs, data_node)
	if not bool(s_early.get("can_enter", true)) and str(s_early.get("reason_code", "")) == "too_early":
		failed += _ok("未達 earliest_night 地點 can_enter=false、reason_code=too_early")
	else:
		failed += _fail("too_early 地點 summary 異常: %s" % str(s_early))

	# 3. not_night: 白天查詢
	gs.set("day", 14)
	gs.set("phase", "morning")
	var s_not_night := PanelBuilder.location_summary("n_ahong_1", gs, data_node)
	if not bool(s_not_night.get("can_enter", true)) and str(s_not_night.get("reason_code", "")) == "not_night":
		failed += _ok("非夜間時段 can_enter=false、reason_code=not_night")
	else:
		failed += _fail("not_night summary 異常: %s" % str(s_not_night))

	# 4. not_night_layer: 傳入白天地點 sanquan
	gs.set("phase", "night")
	var s_not_night_layer := PanelBuilder.location_summary("sanquan", gs, data_node)
	if not bool(s_not_night_layer.get("can_enter", true)) and str(s_not_night_layer.get("reason_code", "")) == "not_night_layer":
		failed += _ok("非夜間圖層地點 can_enter=false、reason_code=not_night_layer")
	else:
		failed += _fail("not_night_layer summary 異常: %s" % str(s_not_night_layer))

	# 5. already_chosen: 當夜已選定地點
	gs.set("night_location_chosen", "n_landmark")
	var s_chosen_self := PanelBuilder.location_summary("n_landmark", gs, data_node)
	var s_chosen_other := PanelBuilder.location_summary("n_ahong_1", gs, data_node)
	if not bool(s_chosen_self.get("can_enter", true)) and str(s_chosen_self.get("reason_code", "")) == "already_chosen" and not bool(s_chosen_other.get("can_enter", true)) and str(s_chosen_other.get("reason_code", "")) == "already_chosen":
		failed += _ok("當夜已選定地點後所有地點 can_enter=false、reason_code=already_chosen")
	else:
		failed += _fail("already_chosen summary 異常: self=%s, other=%s" % [str(s_chosen_self), str(s_chosen_other)])

	# 6. already_slept: 睡眠停拍期間
	gs.set("night_location_chosen", "")
	gs.set("night_sleep_pending", true)
	var s_slept := PanelBuilder.location_summary("n_landmark", gs, data_node)
	if not bool(s_slept.get("can_enter", true)) and str(s_slept.get("reason_code", "")) == "already_slept":
		failed += _ok("睡眠停拍期間 (sleep_pending) 所有地點 can_enter=false、reason_code=already_slept")
	else:
		failed += _fail("already_slept summary 異常: %s" % str(s_slept))

	return failed


# ── 5. 風險警告（首次 marker cost 達 cap） ───────────────────────────────────

func _test_risk_warning_near_cap_and_seen_cleared(gs: Node, data_node: Node) -> int:
	print("--- 5. Risk warning near cap and cleared after seen ---")
	var failed := 0
	_reset_gs(gs)

	gs.set("day", 14)
	gs.set("phase", "night")

	# 給玩家 6 張發狂卡（madness_cap 為 7），n_plaza cost 為 1 -> 首次進場會達 cap
	var hand: Array = gs.get("hand") as Array
	for i in range(6):
		hand.append("madness#%d" % (i + 1))

	var summary_warn: Dictionary = PanelBuilder.location_summary("n_plaza", gs, data_node)
	if str(summary_warn.get("warning", "")) == "再往前，你可能回不來。":
		failed += _ok("首次進場會達 cap 時 summary 顯示風險警告『再往前，你可能回不來。』且無洩漏數字")
	else:
		failed += _fail("接近 cap 時風險警告異常: %s" % str(summary_warn))

	# 免費地點 (n_landmark cost 0) 不會觸發 BE，不應有 warning
	var summary_free: Dictionary = PanelBuilder.location_summary("n_landmark", gs, data_node)
	if str(summary_free.get("warning", "")).is_empty():
		failed += _ok("免費地點 (cost 0) 不觸發 BE，無風險警告")
	else:
		failed += _fail("免費地點錯誤顯示風險警告: %s" % str(summary_free))

	# 到訪後 (seen)，再次進入不再收費，警告消失
	(gs.get("night_locations_seen") as Dictionary)["n_plaza"] = true
	var summary_seen: Dictionary = PanelBuilder.location_summary("n_plaza", gs, data_node)
	if str(summary_seen.get("warning", "")).is_empty():
		failed += _ok("已到訪地點不再收費，風險警告消失")
	else:
		failed += _fail("已到訪地點仍殘留風險警告: %s" % str(summary_seen))

	return failed


# ── 6. 零內容地點 summary 與進入 ──────────────────────────────────────────

func _test_empty_result_location_summary_and_entry(gs: Node, data_node: Node) -> int:
	print("--- 6. Empty result location summary and valid entry ---")
	var failed := 0
	_reset_gs(gs)

	gs.set("day", 14)
	gs.set("phase", "night")

	# n_source 在 D14 沒有 beat (empty_result: true)
	var summary := PanelBuilder.location_summary("n_source", gs, data_node)
	if bool(summary.get("can_enter", false)):
		failed += _ok("無 beat 地點 (n_source) can_enter 為 true")
	else:
		failed += _fail("無 beat 地點 can_enter 不得為 false: %s" % str(summary))

	# 進入無 beat 地點
	var res: Dictionary = gs.call("enter_night_location", "n_source") as Dictionary
	if bool(res.get("ok", false)) and str(gs.get("night_location_chosen")) == "n_source":
		failed += _ok("無 beat 地點成功進入並設為 night_location_chosen")
	else:
		failed += _fail("進入無 beat 地點失敗: %s" % str(res))

	return failed


# ── 7. 呼叫 summary 狀態零變化（純 view model 驗證） ────────────────────────

func _test_state_immutability_on_summary_calls(gs: Node, data_node: Node) -> int:
	print("--- 7. Immutability of GameState under summary calls ---")
	var failed := 0
	_reset_gs(gs)

	gs.set("day", 14)
	gs.set("phase", "night")

	var state_before: String = JSON.stringify(gs.call("serialize"))

	for loc_id in data_node.loader.locations:
		var _s1 := PanelBuilder.location_summary(loc_id, gs, data_node)
		var _s2 := PanelBuilder.available_locations(gs, data_node)

	var state_after: String = JSON.stringify(gs.call("serialize"))
	if state_before == state_after:
		failed += _ok("連續呼叫所有地點 location_summary 與 available_locations，serialize 逐字零變化")
	else:
		failed += _fail("呼叫 summary 導致 GameState 發生副作用變化")

	return failed
