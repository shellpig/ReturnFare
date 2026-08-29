extends SceneTree

## P3-C headless 驗收測試：
## 1. night_beat_candidates 候選收集與章節優先序、白天 beat 排除、addon 順序
## 2. resolved_night_content 條件 fallback、定日覆蓋、requires LOCKED 保持、sleep 跳過
## 3. D31 聚會 saw_n_gathering_intro 常態與特殊內容切換及跨輪重置
## 4. 規則層無分散 when 掃描檢驗 (_is_beat_time_valid 分流)
## 5. 零內容地點回傳 empty_result 且不產生假 beat
## 6. D1、D2、D15 meta-once 雙輪重演與 D14 先行到訪測試
## 7. D24 d24_night_laozeng 每輪重演與文字不重複播放
## 8. D3 n3_map_opens 環境引導跨輪測試
## 9. Lint 14 四種負向 fixture 驗證
## 10. advance_phase() 夜間三態與文字停拍驗證（P5-D 起 resolve_night_advance 退場）

const DataLoader := preload("res://scripts/data_loader.gd")
const ConditionEval := preload("res://scripts/core/condition_eval.gd")
const PanelBuilder := preload("res://scripts/core/panel_builder.gd")
const DataFacts := preload("res://scripts/core/data_facts.gd")
const PlaythroughGreedy := preload("res://tests/headless/playthrough_greedy.gd")

func _initialize() -> void:
	var data_node: Node = PlaythroughGreedy.setup_data(self)
	var gs: Node = PlaythroughGreedy.setup_game_state(self, data_node)

	await process_frame

	if not data_node.get("ok"):
		push_error("P3-C: Data failed to load; abort")
		quit(1)
		return

	var failed := 0
	failed += _test_candidate_priority_and_filtering(gs, data_node)
	failed += _test_resolved_night_content(gs, data_node)
	failed += _test_gathering_intro_and_d31(gs, data_node)
	failed += _test_no_duplicate_when_scanning(gs, data_node)
	failed += _test_empty_result_and_no_fake_beats(gs, data_node)
	failed += _test_dual_run_d1_d2_d15(gs, data_node)
	failed += _test_dual_run_d24_laozeng(gs, data_node)
	failed += _test_dual_run_d3_n3_map_opens(gs, data_node)
	failed += _test_lint_night_once_negative_fixtures(data_node)
	failed += _test_forced_night_visit_rejection_and_abort(gs, data_node)
	failed += _test_resolve_night_advance(gs, data_node)
	failed += await _test_main_scene_advance_hint(self, gs, data_node)

	if failed > 0:
		push_error("\nP3-C: %d assertion(s) failed" % failed)
		quit(1)
	else:
		print("\nP3-C: all tests passed")
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


# ── 1. night_beat_candidates 候選收集與章節優先序 ─────────────────────────────

func _test_candidate_priority_and_filtering(_gs: Node, _data_node: Node) -> int:
	print("--- 1. night_beat_candidates priority, daytime exclusion, range exclusion & addon order ---")
	var failed := 0

	# 建立合成 DataLoader 隔離測試
	var test_loader := DataLoader.new()
	test_loader.locations = {
		"loc_syn": { "id": "loc_syn", "layer": "night", "earliest_night": 1 }
	}
	test_loader.beats = [
		{ "id": "syn_addon_1", "location": "loc_syn" },
		{ "id": "syn_ch1", "location": "loc_syn", "chapter": 1 },
		{ "id": "syn_dated_night", "location": "loc_syn", "when": { "day": 10, "phase": "night" } },
		{ "id": "syn_daytime_morning", "location": "loc_syn", "when": { "day": 10, "phase": "morning" } },
		{ "id": "syn_range_night", "location": "loc_syn", "when": { "day_from": 5, "day_to": 15, "phase": "night" } },
		{ "id": "syn_ch3", "location": "loc_syn", "chapter": 3 },
		{ "id": "syn_addon_2", "location": "loc_syn" },
		{ "id": "syn_ch2", "location": "loc_syn", "chapter": 2 },
	]

	# 第三章第 10 天呼叫
	var cand_ch3: Dictionary = test_loader.night_beat_candidates(10, "loc_syn", 3)
	var prim_ch3: Array = cand_ch3.get("primaries", []) as Array
	var addon_ch3: Array = cand_ch3.get("addons", []) as Array

	var prim_ids_ch3 := PackedStringArray()
	for p: Dictionary in prim_ch3:
		prim_ids_ch3.append(str(p.get("id", "")))
	var addon_ids_ch3 := PackedStringArray()
	for a: Dictionary in addon_ch3:
		addon_ids_ch3.append(str(a.get("id", "")))

	if prim_ids_ch3 == PackedStringArray(["syn_dated_night", "syn_ch3", "syn_ch2", "syn_ch1"]):
		failed += _ok("第 3 章 primaries 優先序正確: 定日 > ch3 > ch2 > ch1")
	else:
		failed += _fail("第 3 章 primaries 優先序錯誤: %s" % str(prim_ids_ch3))

	if not prim_ids_ch3.has("syn_daytime_morning"):
		failed += _ok("同地點白天 beat 未混入 night primaries")
	else:
		failed += _fail("同地點白天 beat 錯誤混入 night primaries")

	if not prim_ids_ch3.has("syn_range_night") and not addon_ids_ch3.has("syn_range_night"):
		failed += _ok("夜間候選正確排除區間 (day_from/day_to) beat")
	else:
		failed += _fail("夜間候選錯誤收錄了區間 beat")

	if addon_ids_ch3 == PackedStringArray(["syn_addon_1", "syn_addon_2"]):
		failed += _ok("addons 保持資料原始順序")
	else:
		failed += _fail("addons 順序錯誤: %s" % str(addon_ids_ch3))

	# 第二章第 10 天呼叫（ch3 不應入列）
	var cand_ch2: Dictionary = test_loader.night_beat_candidates(10, "loc_syn", 2)
	var prim_ids_ch2 := PackedStringArray()
	for p: Dictionary in cand_ch2.get("primaries", []) as Array:
		prim_ids_ch2.append(str(p.get("id", "")))
	if prim_ids_ch2 == PackedStringArray(["syn_dated_night", "syn_ch2", "syn_ch1"]):
		failed += _ok("第 2 章 primaries 正確排除 ch3: 定日 > ch2 > ch1")
	else:
		failed += _fail("第 2 章 primaries 錯誤: %s" % str(prim_ids_ch2))

	# 第一章第 11 天呼叫（定日不符，僅剩 ch1）
	var cand_ch1_d11: Dictionary = test_loader.night_beat_candidates(11, "loc_syn", 1)
	var prim_ids_ch1_d11 := PackedStringArray()
	for p: Dictionary in cand_ch1_d11.get("primaries", []) as Array:
		prim_ids_ch1_d11.append(str(p.get("id", "")))
	if prim_ids_ch1_d11 == PackedStringArray(["syn_ch1"]):
		failed += _ok("非定日天數正確排除定日 beat，僅取當前章以下變體")
	else:
		failed += _fail("非定日天數 primaries 錯誤: %s" % str(prim_ids_ch1_d11))

	return failed


# ── 2. resolved_night_content 狀態求值與 fallback / requires ────────────────

func _test_resolved_night_content(gs: Node, data_node: Node) -> int:
	print("--- 2. resolved_night_content condition fallback, requires LOCKED & sleep skip ---")
	var failed := 0
	var loader: DataLoader = data_node.get("loader") as DataLoader

	# 動態注入合成 beats 進行求值測試
	var original_beats: Array[Dictionary] = loader.beats.duplicate()
	loader.beats.append_array([
		{
			"id": "test_dated_cond",
			"location": "loc_eval",
			"when": { "day": 20, "phase": "night" },
			"condition": { "flag": "eval_flag_on" },
			"slots": []
		},
		{
			"id": "test_ch2_var",
			"location": "loc_eval",
			"chapter": 2,
			"slots": []
		},
		{
			"id": "test_dated_req_locked",
			"location": "sanquan",
			"when": { "day": 20, "phase": "night" },
			"condition": { "flag": "eval_flag_on" },
			"requires": { "flag": "unmet_req_flag" },
			"reject_reason": "（需要未達成的門檻）",
			"slots": []
		},
		{
			"id": "test_addon_active",
			"location": "loc_eval",
			"condition": { "flag": "eval_flag_on" },
			"slots": []
		},
		{
			"id": "test_addon_inactive",
			"location": "loc_eval",
			"condition": { "flag": "eval_addon_false" },
			"slots": []
		}
	])

	# Case 1: condition 為 false 時退回章節變體（第 20 天為第 2 章）
	_reset_gs(gs)
	gs.set("day", 20)
	gs.set("phase", "night")
	var res1: Dictionary = gs.call("resolved_night_content", "loc_eval")
	if str(res1.get("primary", {}).get("id", "")) == "test_ch2_var":
		failed += _ok("exact dated condition=false 時成功退回章節變體 (test_ch2_var)")
	else:
		failed += _fail("condition=false 退回失敗: %s" % str(res1))

	# Case 2: condition 為 true 時覆蓋章節變體
	gs.call("set_flag", "eval_flag_on", true)
	var res2: Dictionary = gs.call("resolved_night_content", "loc_eval")
	if str(res2.get("primary", {}).get("id", "")) == "test_dated_cond":
		failed += _ok("exact dated condition=true 時成功覆蓋章節變體 (test_dated_cond)")
	else:
		failed += _fail("condition=true 覆蓋失敗: %s" % str(res2))

	# Case 3: addons 依 condition 過濾
	var addons: Array = res2.get("addons", []) as Array
	if addons.size() == 1 and str(addons[0].get("id", "")) == "test_addon_active":
		failed += _ok("addons 依 condition 正確過濾且保留成立者")
	else:
		failed += _fail("addons 過濾失敗: %s" % str(addons))

	# Case 4: primary requires=false 仍選中且呈 LOCKED，sleep_night 跳過不播放
	var res_sq: Dictionary = gs.call("resolved_night_content", "sanquan")
	if str(res_sq.get("primary", {}).get("id", "")) == "test_dated_req_locked":
		failed += _ok("requires=false 時 primary 仍被選中不退回")
	else:
		failed += _fail("requires=false primary 選擇錯誤: %s" % str(res_sq))

	var panel_view: Dictionary = PanelBuilder.build("sanquan", gs, data_node)
	var beats_view: Array = panel_view.get("beats", []) as Array
	if beats_view.size() > 0 and int(beats_view[0].get("tri", -1)) == PanelBuilder.TriState.LOCKED:
		failed += _ok("PanelBuilder.build 對 requires=false 產生 LOCKED 狀態")
	else:
		failed += _fail("PanelBuilder.build 未正確產出 LOCKED")

	var sleep_lines: PackedStringArray = gs.call("sleep_night")
	if sleep_lines.is_empty():
		failed += _ok("sleep_night 遇 requires=false 正確跳過不播放")
	else:
		failed += _fail("sleep_night 錯誤播放了 requires=false 的內容: %s" % str(sleep_lines))

	# 還原 loader.beats
	loader.beats = original_beats
	return failed


# ── 3. D31 聚會 saw_n_gathering_intro 狀態切換 ──────────────────────────────

func _test_gathering_intro_and_d31(gs: Node, _data_node: Node) -> int:
	print("--- 3. D31 gathering intro vs special content and loop reset ---")
	var failed := 0

	_reset_gs(gs)
	gs.set("day", 31)
	gs.set("phase", "night")

	# 1. 尚未看過常態聚會（saw_n_gathering_intro == false）時，解析為常態變體 n_gathering_ch2
	var res_before: Dictionary = gs.call("resolved_night_content", "n_gathering")
	if str(res_before.get("primary", {}).get("id", "")) == "n_gathering_ch2":
		failed += _ok("首次進入聚會解析為常態內容 n_gathering_ch2，不播 n_gathering_d31")
	else:
		failed += _fail("首次進入未取 n_gathering_ch2: %s" % str(res_before))

	# 模擬進入 n_gathering_ch2 執行 on_enter，寫入 saw_n_gathering_intro: true
	gs.call("play_beat", "n_gathering_ch2")
	if bool((gs.get("flags") as Dictionary).get("saw_n_gathering_intro", false)):
		failed += _ok("n_gathering_ch2 on_enter 成功寫入 saw_n_gathering_intro: true")
	else:
		failed += _fail("saw_n_gathering_intro 未寫入")

	# 2. 本輪已看過常態內容後，第 31 夜解析為特殊內容 n_gathering_d31
	var res_after: Dictionary = gs.call("resolved_night_content", "n_gathering")
	if str(res_after.get("primary", {}).get("id", "")) == "n_gathering_d31":
		failed += _ok("本輪已看過常態聚會後，第 31 夜成功解析為 n_gathering_d31 特殊內容")
	else:
		failed += _fail("已看過常態內容後第 31 夜未取 n_gathering_d31: %s" % str(res_after))

	# 3. 跨輪重置：run_reset 後 meta night_locations_seen 保留，但 run flag 清空，不得直接播特殊內容
	PlaythroughGreedy.start_fresh_run(gs)
	gs.set("day", 31)
	gs.set("phase", "night")
	var res_loop2: Dictionary = gs.call("resolved_night_content", "n_gathering")
	if str(res_loop2.get("primary", {}).get("id", "")) == "n_gathering_ch2":
		failed += _ok("第二輪未在新一輪看過常態聚會前，第 31 夜仍解析為常態內容")
	else:
		failed += _fail("第二輪未先看常態內容卻錯誤播了特殊內容: %s" % str(res_loop2))

	return failed


# ── 4. 規則層無分散 when 掃描檢驗 ──────────────────────────────────────────

func _test_no_duplicate_when_scanning(gs: Node, _data_node: Node) -> int:
	print("--- 4. Code structure check: no duplicate night when scanning ---")
	var failed := 0

	_reset_gs(gs)
	gs.set("day", 10)
	gs.set("phase", "night")

	# 驗證 _is_beat_time_valid 分流
	var night_valid_primary := { "id": "n_ahong_1_ch1", "location": "n_ahong_1" }
	if gs.call("_is_beat_time_valid", night_valid_primary):
		failed += _ok("_is_beat_time_valid 夜間 non-fixed 透過 resolved_night_content 判準通過")
	else:
		failed += _fail("_is_beat_time_valid 夜間有效 beat 判定失敗")

	var night_invalid_beat := { "id": "n_ahong_1_ch3", "location": "n_ahong_1", "chapter": 3 }
	if not gs.call("_is_beat_time_valid", night_invalid_beat):
		failed += _ok("_is_beat_time_valid 夜間未被 resolved 選中之變體判定為 false")
	else:
		failed += _fail("_is_beat_time_valid 錯誤放行未選中之變體")

	return failed


# ── 5. 零內容地點回傳 empty_result 且付費地點回傳真實 beat id ──────────────

func _test_empty_result_and_no_fake_beats(gs: Node, data_node: Node) -> int:
	print("--- 5. empty_result and real beat ids in night panel (no fake beats) ---")
	var failed := 0
	var loader: DataLoader = data_node.get("loader") as DataLoader

	_reset_gs(gs)
	gs.set("day", 10)
	gs.set("phase", "night")

	# 1. 斷言收費夜間地點 build_panel 回傳真實 beat id（非 fake）
	var paid_locs := ["n_ahong_1", "n_source"]
	for ploc in paid_locs:
		var panel_view: Dictionary = PanelBuilder.build(ploc, gs, data_node)
		var beats_arr: Array = panel_view.get("beats", []) as Array
		if beats_arr.is_empty():
			failed += _fail("收費地點 %s build_panel 未回傳 beats" % ploc)
			continue
		for bv: Dictionary in beats_arr:
			var beat_dict: Dictionary = bv.get("beat", {}) as Dictionary
			var bid: String = str(beat_dict.get("id", ""))
			if not loader.beats_by_id.has(bid):
				failed += _fail("收費地點 %s 回傳了不存在於 beats 資料庫的假 id: %s" % [ploc, bid])
			elif bid.ends_with("_locked"):
				failed += _fail("收費地點 %s 回傳了帶有 _locked 假後綴的 id: %s" % [ploc, bid])
			else:
				failed += _ok("收費地點 %s 回傳真實 beat id: %s" % [ploc, bid])

	# 2. 測試合法但無內容的地點（例如給定一個無 beat 的地點）
	var original_locations := loader.locations.duplicate()
	loader.locations["n_empty_test"] = { "id": "n_empty_test", "layer": "night", "earliest_night": 1 }
	var panel_empty: Dictionary = PanelBuilder.build("n_empty_test", gs, data_node)
	if bool(panel_empty.get("empty_result", false)) and (panel_empty.get("beats", []) as Array).is_empty():
		failed += _ok("夜間無 beat 地點回傳 empty_result: true 且 beats 為空陣列")
	else:
		failed += _fail("empty_result 產出失敗: %s" % str(panel_empty))

	var entered_before := (gs.get("beats_entered") as Dictionary).duplicate()
	gs.call("enter_night_location", "n_empty_test")
	var entered_after := (gs.get("beats_entered") as Dictionary).duplicate()
	if entered_before == entered_after:
		failed += _ok("進入零內容地點不製造假 beat id 且 beats_entered 不新增鍵")
	else:
		failed += _fail("進入零內容地點造成 beats_entered 變異")

	loader.locations = original_locations
	return failed


# ── 6. D1、D2、D15 meta-once 雙輪重演與 D14 先行到訪 ────────────────────────

func _test_dual_run_d1_d2_d15(gs: Node, _data_node: Node) -> int:
	print("--- 6. D1, D2, D15 meta-once dual run & D14 prior active visit ---")
	var failed := 0

	_reset_gs(gs)

	# --- 第一輪 D1 night ---
	gs.set("day", 1)
	gs.set("phase", "night")
	gs.set("night_location_chosen", "")
	var d1_lines: PackedStringArray = gs.call("play_night_fixed")
	if d1_lines.size() > 0 and d1_lines[0].contains("一條走廊"):
		failed += _ok("第一輪 D1 night play_night_fixed 播放 n_corridor_ch1")
	else:
		failed += _fail("第一輪 D1 night 播放失敗: %s" % str(d1_lines))

	if bool((gs.get("night_once_beats_seen") as Dictionary).get("n_corridor_ch1", false)):
		failed += _ok("n_corridor_ch1 寫入 meta night_once_beats_seen")
	else:
		failed += _fail("n_corridor_ch1 未寫入 night_once_beats_seen")

	if str(gs.get("night_location_chosen")) == "n_corridor":
		failed += _ok("D1 fixed 強制到訪記錄 night_location_chosen: n_corridor")
	else:
		failed += _fail("D1 fixed 未記錄 chosen")

	if bool((gs.get("night_locations_seen") as Dictionary).get("n_corridor", false)):
		failed += _ok("D1 fixed 強制到訪記錄 meta seen: n_corridor")
	else:
		failed += _fail("D1 fixed 未記錄 seen")

	# --- 第一輪 D2 night ---
	gs.set("day", 2)
	gs.set("phase", "night")
	gs.set("night_location_chosen", "")
	var d2_lines: PackedStringArray = gs.call("play_night_fixed")
	if d2_lines.size() > 0 and d2_lines[0].contains("同一條走廊"):
		failed += _ok("第一輪 D2 night play_night_fixed 播放 n_exit_ch1")
	else:
		failed += _fail("第一輪 D2 night 播放失敗: %s" % str(d2_lines))
	if bool((gs.get("night_once_beats_seen") as Dictionary).get("n_exit_ch1", false)):
		failed += _ok("n_exit_ch1 寫入 meta night_once_beats_seen")
	else:
		failed += _fail("n_exit_ch1 未寫入 night_once_beats_seen")

	# --- 第一輪 D14 主動先行到訪 n_plaza ---
	gs.set("day", 14)
	gs.set("phase", "night")
	gs.set("night_location_chosen", "")
	var enter_res: Dictionary = gs.call("enter_night_location", "n_plaza")
	if bool(enter_res.get("ok", false)):
		failed += _ok("D14 主動進入收費地點 n_plaza 成功")
	else:
		failed += _fail("D14 進入 n_plaza 失敗: %s" % str(enter_res))

	# --- 第一輪 D15 night fixed 到訪 ---
	gs.set("day", 15)
	gs.set("phase", "night")
	gs.set("night_location_chosen", "")
	var d15_lines: PackedStringArray = gs.call("play_night_fixed")
	if d15_lines.size() > 0 and d15_lines[0].contains("人群裡有一個背影"):
		failed += _ok("第一輪 D15 fixed 在已主動到訪後仍播一次 n15_everyone")
	else:
		failed += _fail("第一輪 D15 播放失敗: %s" % str(d15_lines))
	if bool((gs.get("night_once_beats_seen") as Dictionary).get("n15_everyone", false)):
		failed += _ok("n15_everyone 寫入 meta night_once_beats_seen")
	else:
		failed += _fail("n15_everyone 未寫入 night_once_beats_seen")

	# --- 第二輪跨輪重演 ---
	PlaythroughGreedy.start_fresh_run(gs)
	gs.set("day", 1)
	gs.set("phase", "night")
	gs.set("night_location_chosen", "")
	var loop2_d1_lines: PackedStringArray = gs.call("play_night_fixed")
	if loop2_d1_lines.is_empty():
		failed += _ok("第二輪 D1 night 不再強制播放 n_corridor_ch1")
	else:
		failed += _fail("第二輪 D1 night 錯誤重播: %s" % str(loop2_d1_lines))
	if str(gs.get("night_location_chosen")).is_empty():
		failed += _ok("第二輪 D1 night 未強制設定 chosen，地點清單保持可用")
	else:
		failed += _fail("第二輪 D1 night 錯誤鎖定 chosen")

	gs.set("day", 2)
	gs.set("night_location_chosen", "")
	var loop2_d2_lines: PackedStringArray = gs.call("play_night_fixed")
	if loop2_d2_lines.is_empty():
		failed += _ok("第二輪 D2 night 不再強制播放 n_exit_ch1")
	else:
		failed += _fail("第二輪 D2 night 錯誤重播: %s" % str(loop2_d2_lines))

	gs.set("day", 15)
	gs.set("night_location_chosen", "")
	var loop2_d15_lines: PackedStringArray = gs.call("play_night_fixed")
	if loop2_d15_lines.is_empty():
		failed += _ok("第二輪 D15 night 不再強制播放 n15_everyone")
	else:
		failed += _fail("第二輪 D15 night 錯誤重播: %s" % str(loop2_d15_lines))

	return failed


# ── 7. D24 d24_night_laozeng 每輪重演與不重複播放 ───────────────────────────

func _test_dual_run_d24_laozeng(gs: Node, _data_node: Node) -> int:
	print("--- 7. D24 d24_night_laozeng repeat per run and no same-night duplicate ---")
	var failed := 0

	_reset_gs(gs)

	# 第一輪 D24
	gs.set("day", 24)
	gs.set("phase", "night")
	var d24_lines1: PackedStringArray = gs.call("play_night_fixed")
	if d24_lines1.size() > 0 and d24_lines1[0].contains("巡查點名"):
		failed += _ok("第一輪 D24 night play_night_fixed 播放 d24_night_laozeng")
	else:
		failed += _fail("第一輪 D24 播放失敗: %s" % str(d24_lines1))

	if bool((gs.get("flags") as Dictionary).get("laozeng_patrol_d24", false)):
		failed += _ok("d24_night_laozeng 成功寫入 run flag: laozeng_patrol_d24")
	else:
		failed += _fail("laozeng_patrol_d24 未寫入")

	if str(gs.get("night_location_chosen")).is_empty():
		failed += _ok("d24_night_laozeng 掛在 sanquan，不佔用 night_location_chosen")
	else:
		failed += _fail("d24_night_laozeng 錯誤佔用了 night_location_chosen")

	# 同一夜再次呼叫（例如 _route_view 重建）不重複播放
	var d24_rebuild_lines: PackedStringArray = gs.call("play_night_fixed")
	if d24_rebuild_lines.is_empty():
		failed += _ok("同夜重建 route 不重複播放 d24_night_laozeng")
	else:
		failed += _fail("同夜重建錯誤重播了文字: %s" % str(d24_rebuild_lines))

	# 第二輪 D24
	PlaythroughGreedy.start_fresh_run(gs)
	gs.set("day", 24)
	gs.set("phase", "night")
	var d24_lines2: PackedStringArray = gs.call("play_night_fixed")
	if d24_lines2.size() > 0 and d24_lines2[0].contains("巡查點名"):
		failed += _ok("第二輪 D24 night 正確再次播放 d24_night_laozeng（每輪 fixed）")
	else:
		failed += _fail("第二輪 D24 未重播: %s" % str(d24_lines2))

	return failed


# ── 8. D3 n3_map_opens 環境引導跨輪測試 ────────────────────────────────────

func _test_dual_run_d3_n3_map_opens(gs: Node, _data_node: Node) -> int:
	print("--- 8. D3 n3_map_opens environmental guidance dual run ---")
	var failed := 0

	_reset_gs(gs)

	# 第一輪 D3
	gs.set("day", 3)
	gs.set("phase", "night")
	var d3_lines1: PackedStringArray = gs.call("play_night_fixed")
	if d3_lines1.size() > 0 and d3_lines1[0].contains("三個沒有名字的標記出現"):
		failed += _ok("第一輪 D3 night play_night_fixed 播放 n3_map_opens 環境引導")
	else:
		failed += _fail("第一輪 D3 播放失敗: %s" % str(d3_lines1))

	if bool((gs.get("night_once_beats_seen") as Dictionary).get("n3_map_opens", false)):
		failed += _ok("n3_map_opens 寫入 meta night_once_beats_seen")
	else:
		failed += _fail("n3_map_opens 未寫入 night_once_beats_seen")

	if str(gs.get("night_location_chosen")).is_empty():
		failed += _ok("n3_map_opens 掛在 sanquan，不佔用 night_location_chosen")
	else:
		failed += _fail("n3_map_opens 錯誤佔用了 night_location_chosen")

	# 第二輪 D3
	PlaythroughGreedy.start_fresh_run(gs)
	gs.set("day", 3)
	gs.set("phase", "night")
	var d3_lines2: PackedStringArray = gs.call("play_night_fixed")
	if d3_lines2.is_empty():
		failed += _ok("第二輪 D3 night 不再播放 n3_map_opens，夜間清單直接可用")
	else:
		failed += _fail("第二輪 D3 錯誤重播: %s" % str(d3_lines2))

	return failed


# ── 9. Lint 14 七種負向 fixture 驗證 ────────────────────────────────────────

func _test_lint_night_once_negative_fixtures(_data_node: Node) -> int:
	print("--- 9. Lint 14 negative fixtures (string & array phase) ---")
	var failed := 0

	# 負向 fixture 1: 非 night fixed 使用 meta_once
	var loader1 := DataLoader.new()
	loader1.locations = { "sanquan": { "id": "sanquan", "layer": "both" } }
	loader1.beats = [
		{ "id": "b_bad_morning_meta", "location": "sanquan", "fixed": true, "meta_once": true, "when": { "day": 1, "phase": "morning" } }
	]
	var errs1 := DataLoader.lint_night_once(loader1)
	if errs1.size() > 0 and errs1[0].contains("具有 exact night when"):
		failed += _ok("負向 fixture 1: 非 night fixed 標記 meta_once 被成功攔截")
	else:
		failed += _fail("負向 fixture 1 未攔截: %s" % str(errs1))

	# 負向 fixture 2: night-layer fixed 缺 meta_once (字串 phase)
	var loader2 := DataLoader.new()
	loader2.locations = { "n_corridor": { "id": "n_corridor", "layer": "night" } }
	loader2.beats = [
		{ "id": "n_corridor_ch1", "location": "n_corridor", "fixed": true, "when": { "day": 1, "phase": "night" } }
	]
	var errs2 := DataLoader.lint_night_once(loader2)
	if errs2.size() > 0 and errs2[0].contains("必須標記 meta_once: true"):
		failed += _ok("負向 fixture 2: night-layer fixed 缺 meta_once 被成功攔截")
	else:
		failed += _fail("負向 fixture 2 未攔截: %s" % str(errs2))

	# 負向 fixture 3: meta_once beat 缺 exact night when
	var loader3 := DataLoader.new()
	loader3.locations = { "sanquan": { "id": "sanquan", "layer": "both" } }
	loader3.beats = [
		{ "id": "b_no_when_meta", "location": "sanquan", "fixed": true, "meta_once": true }
	]
	var errs3 := DataLoader.lint_night_once(loader3)
	if errs3.size() > 0 and errs3[0].contains("具有 exact night when"):
		failed += _ok("負向 fixture 3: meta_once 缺 exact night when 被成功攔截")
	else:
		failed += _fail("負向 fixture 3 未攔截: %s" % str(errs3))

	# 負向 fixture 4: 同一個 when.day 掛兩個不同 night-layer 地點的 fixed
	var loader4 := DataLoader.new()
	loader4.locations = {
		"n_corridor": { "id": "n_corridor", "layer": "night" },
		"n_exit": { "id": "n_exit", "layer": "night" }
	}
	loader4.beats = [
		{ "id": "n_corridor_ch1", "location": "n_corridor", "fixed": true, "meta_once": true, "when": { "day": 1, "phase": "night" } },
		{ "id": "n_exit_ch1", "location": "n_exit", "fixed": true, "meta_once": true, "when": { "day": 1, "phase": "night" } }
	]
	var errs4 := DataLoader.lint_night_once(loader4)
	if errs4.size() > 0 and errs4[0].contains("存在多個 night-layer fixed beat"):
		failed += _ok("負向 fixture 4: 同一夜存在多個 night-layer fixed beat 被成功攔截")
	else:
		failed += _fail("負向 fixture 4 未攔截: %s" % str(errs4))

	# 負向 fixture 5: 陣列 phase 的 night-layer fixed 缺 meta_once
	var loader5 := DataLoader.new()
	loader5.locations = { "n_corridor": { "id": "n_corridor", "layer": "night" } }
	loader5.beats = [
		{ "id": "n_corridor_arr_phase", "location": "n_corridor", "fixed": true, "when": { "day": 1, "phase": ["evening", "night"] } }
	]
	var errs5 := DataLoader.lint_night_once(loader5)
	if errs5.size() > 0 and errs5[0].contains("必須標記 meta_once: true"):
		failed += _ok("負向 fixture 5: 陣列 phase night-layer fixed 缺 meta_once 成功攔截")
	else:
		failed += _fail("負向 fixture 5 未攔截: %s" % str(errs5))

	# 負向 fixture 6: 陣列 phase 不包含 night 的 fixed 標記 meta_once
	var loader6 := DataLoader.new()
	loader6.locations = { "sanquan": { "id": "sanquan", "layer": "both" } }
	loader6.beats = [
		{ "id": "b_arr_no_night_meta", "location": "sanquan", "fixed": true, "meta_once": true, "when": { "day": 1, "phase": ["morning", "afternoon"] } }
	]
	var errs6 := DataLoader.lint_night_once(loader6)
	if errs6.size() > 0 and errs6[0].contains("具有 exact night when"):
		failed += _ok("負向 fixture 6: 陣列 phase 未含 night 標記 meta_once 成功攔截")
	else:
		failed += _fail("負向 fixture 6 未攔截: %s" % str(errs6))

	# 負向 fixture 7: 陣列 phase 與字串 phase 在同一夜衝突
	var loader7 := DataLoader.new()
	loader7.locations = {
		"n_corridor": { "id": "n_corridor", "layer": "night" },
		"n_exit": { "id": "n_exit", "layer": "night" }
	}
	loader7.beats = [
		{ "id": "n_corridor_ch1", "location": "n_corridor", "fixed": true, "meta_once": true, "when": { "day": 1, "phase": ["night"] } },
		{ "id": "n_exit_ch1", "location": "n_exit", "fixed": true, "meta_once": true, "when": { "day": 1, "phase": "night" } }
	]
	var errs7 := DataLoader.lint_night_once(loader7)
	if errs7.size() > 0 and errs7[0].contains("存在多個 night-layer fixed beat"):
		failed += _ok("負向 fixture 7: 陣列 phase 與字串 phase 同夜衝突成功攔截")
	else:
		failed += _fail("負向 fixture 7 未攔截: %s" % str(errs7))

	return failed


# ── 10. _record_forced_night_visit 防線與 play_night_fixed 失敗阻斷 ─────────

func _test_forced_night_visit_rejection_and_abort(gs: Node, _data_node: Node) -> int:
	print("--- 10. _record_forced_night_visit defense & play_night_fixed abort (K-90, already_slept) ---")
	var failed := 0

	# Case 1: 當夜已選地點時，play_night_fixed 必須阻斷執行，不播 beat 且不燒掉 meta_once
	_reset_gs(gs)
	gs.set("day", 1)
	gs.set("phase", "night")
	gs.set("night_location_chosen", "n_source")
	gs.set("night_once_beats_seen", {})

	var lines_blocked: PackedStringArray = gs.call("play_night_fixed")
	if lines_blocked.is_empty():
		failed += _ok("chosen 已佔用時 play_night_fixed 成功阻斷執行並回傳空行 (K-90)")
	else:
		failed += _fail("chosen 已佔用時 play_night_fixed 錯誤執行了內容: %s" % str(lines_blocked))

	if not (gs.get("night_once_beats_seen") as Dictionary).has("n_corridor_ch1"):
		failed += _ok("阻斷後 meta night_once_beats_seen 未被提前寫入/永久燒掉")
	else:
		failed += _fail("阻斷後 meta night_once_beats_seen 錯誤寫入了 n_corridor_ch1")

	if str(gs.get("night_location_chosen")) == "n_source":
		failed += _ok("阻斷後 night_location_chosen 保持原值 'n_source'")
	else:
		failed += _fail("阻斷後 night_location_chosen 遭污染: %s" % str(gs.get("night_location_chosen")))

	# Case 2: 當夜已進入睡眠 pending 時，play_night_fixed 同樣阻斷 (already_slept)
	_reset_gs(gs)
	gs.set("day", 1)
	gs.set("phase", "night")
	gs.set("night_location_chosen", "")
	gs.set("night_sleep_pending", true)
	gs.set("night_once_beats_seen", {})

	var lines_sleep_blocked: PackedStringArray = gs.call("play_night_fixed")
	if lines_sleep_blocked.is_empty():
		failed += _ok("sleep_pending 為真時 play_night_fixed 成功阻斷執行")
	else:
		failed += _fail("sleep_pending 為真時 play_night_fixed 錯誤執行: %s" % str(lines_sleep_blocked))

	if not (gs.get("night_once_beats_seen") as Dictionary).has("n_corridor_ch1"):
		failed += _ok("sleep_pending 阻斷後 meta night_once_beats_seen 未被寫入")
	else:
		failed += _fail("sleep_pending 阻斷後 meta 遭錯誤寫入")

	# Case 3: helper 直接呼叫傳回值驗證
	_reset_gs(gs)
	var ok_clean: bool = gs.call("_record_forced_night_visit", "n_corridor")
	if ok_clean and str(gs.get("night_location_chosen")) == "n_corridor":
		failed += _ok("乾淨狀態下 _record_forced_night_visit 回傳 true 並成功寫入 chosen")
	else:
		failed += _fail("乾淨狀態下 _record_forced_night_visit 寫入失敗")

	var ok_repeat: bool = gs.call("_record_forced_night_visit", "n_exit")
	if not ok_repeat and str(gs.get("night_location_chosen")) == "n_corridor":
		failed += _ok("重複呼叫時 _record_forced_night_visit 回傳 false 並拒絕覆蓋")
	else:
		failed += _fail("重複呼叫時 _record_forced_night_visit 覆蓋成功")

	return failed


# ── 11. 夜間停拍與推進（P5-D 起由 advance_phase() 吸收）─────────────────────

func _test_resolve_night_advance(gs: Node, _data_node: Node) -> int:
	print("--- 11. advance_phase() night staging: pending 停拍 and chosen bypass ---")
	var failed := 0

	# Case A: 未選地點按「推進」，有睡眠內容時先播、停在原時段；再按一次才換日
	_reset_gs(gs)
	gs.set("day", 24)
	gs.set("phase", "night")
	gs.call("set_flag", "boundary_bleeding", true)
	gs.call("gain_card", "madness")
	gs.call("gain_card", "madness")
	gs.call("gain_card", "madness") # 3 cards -> triggers d24_night_bleed

	var adv_step1: Dictionary = gs.call("advance_phase")
	if bool(adv_step1.get("ok", false)) and not bool(adv_step1.get("phase_advanced", true)) \
			and (adv_step1.get("lines", PackedStringArray()) as PackedStringArray).size() > 0:
		failed += _ok("有睡眠內容時第 1 次推進成功但 phase_advanced 為 false，並附帶文字行")
	else:
		failed += _fail("第 1 步未如預期停拍: %s" % str(adv_step1))

	if bool(gs.get("night_sleep_pending")) and int(gs.get("day")) == 24 and str(gs.get("phase")) == "night":
		failed += _ok("第 1 步成功設定 night_sleep_pending: true 且停在原時段")
	else:
		failed += _fail("night_sleep_pending 或時段狀態異常")

	var adv_step2: Dictionary = gs.call("advance_phase")
	if bool(adv_step2.get("phase_advanced", false)) and int(gs.get("day")) == 25:
		failed += _ok("第 2 步 pending 清除後真正換日")
	else:
		failed += _fail("第 2 步未換日: %s" % str(adv_step2))

	if not bool(gs.get("night_sleep_pending")):
		failed += _ok("第 2 步成功清除 night_sleep_pending")
	else:
		failed += _fail("night_sleep_pending 未被清除")

	# Case B: 無睡眠內容時一次就換日
	_reset_gs(gs)
	gs.set("day", 10)
	gs.set("phase", "night")
	var adv_direct: Dictionary = gs.call("advance_phase")
	if bool(adv_direct.get("phase_advanced", false)) and (adv_direct.get("lines", PackedStringArray()) as PackedStringArray).is_empty():
		failed += _ok("無睡眠內容時第 1 次推進就換日，且不回傳文字行")
	else:
		failed += _fail("無睡眠內容時未直接換日: %s" % str(adv_direct))

	# Case C: 已到訪地點後，不解析睡眠內容，直接換日
	_reset_gs(gs)
	gs.set("day", 24)
	gs.set("phase", "night")
	gs.call("set_flag", "boundary_bleeding", true)
	gs.call("gain_card", "madness")
	gs.call("gain_card", "madness")
	gs.call("gain_card", "madness")
	gs.set("night_location_chosen", "n_source")
	var adv_chosen: Dictionary = gs.call("advance_phase")
	if bool(adv_chosen.get("phase_advanced", false)) and (adv_chosen.get("lines", PackedStringArray()) as PackedStringArray).is_empty():
		failed += _ok("已到訪地點後絕不播放 sleep beat，直接換日")
	else:
		failed += _fail("已到訪地點後錯誤觸發了 sleep: %s" % str(adv_chosen))

	return failed


# ── 12. _refresh_advance_hint 夜間按鈕三態真畫面斷言 ────────────────────────

func _test_main_scene_advance_hint(tree: SceneTree, gs: Node, _data_node: Node) -> int:
	print("--- 12. main.gd _refresh_advance_hint three night button states ---")
	var failed := 0

	var main_scene: Node = load("res://scenes/main.tscn").instantiate()
	tree.get_root().add_child(main_scene)
	await tree.process_frame

	var advance_btn: Button = main_scene.get_node_or_null("AdvanceButton") as Button
	if advance_btn == null:
		failed += _fail("AdvanceButton 不存在")
		main_scene.queue_free()
		return failed

	# 1. 夜間未選地點、無 pending -> 按鈕為「直接睡」
	_reset_gs(gs)
	main_scene.set("_is_showing_ending", false)
	gs.set("day", 10)
	gs.set("phase", "night")
	main_scene.call("_refresh_status")
	if advance_btn.text == "直接睡":
		failed += _ok("夜間初始狀態按鈕文字為『直接睡』")
	else:
		failed += _fail("夜間初始按鈕文字不符: 預期『直接睡』, 實際『%s』" % advance_btn.text)

	# 2. 觸發睡眠內容停拍 -> 按鈕變為「進入隔天」
	_reset_gs(gs)
	main_scene.set("_is_showing_ending", false)
	gs.set("day", 24)
	gs.set("phase", "night")
	gs.call("set_flag", "boundary_bleeding", true)
	gs.call("gain_card", "madness")
	gs.call("gain_card", "madness")
	gs.call("gain_card", "madness")
	main_scene.call("_refresh_status")
	# 第 1 次點擊推進按鈕：觸發停拍
	main_scene.call("_on_advance_pressed")
	if bool(gs.get("night_sleep_pending")):
		failed += _ok("點擊『直接睡』後成功進入 pending 停拍")
	else:
		failed += _fail("點擊『直接睡』後未進入 pending")
	if advance_btn.text == "進入隔天":
		failed += _ok("睡眠停拍期間按鈕文字變為『進入隔天』(K-68, K-69)")
	else:
		failed += _fail("睡眠停拍期間按鈕文字不符: 預期『進入隔天』, 實際『%s』" % advance_btn.text)

	# 第 2 次點擊推進按鈕：換日進入隔天 morning
	main_scene.call("_on_advance_pressed")
	if int(gs.get("day")) == 25 and str(gs.get("phase")) == "morning":
		failed += _ok("點擊『進入隔天』後推進至第 25 天 morning")
	else:
		failed += _fail("點擊『進入隔天』未推進: day=%s, phase=%s" % [str(gs.get("day")), str(gs.get("phase"))])

	# 3. 夜間選定地點後 -> 按鈕變為「結束今晚」
	_reset_gs(gs)
	main_scene.set("_is_showing_ending", false)
	gs.set("day", 10)
	gs.set("phase", "night")
	gs.set("night_location_chosen", "n_landmark")
	main_scene.call("_refresh_status")
	if advance_btn.text == "結束今晚":
		failed += _ok("夜間選定地點後按鈕文字為『結束今晚』")
	else:
		failed += _fail("夜間選定地點後按鈕文字不符: 預期『結束今晚』, 實際『%s』" % advance_btn.text)

	main_scene.queue_free()
	return failed
