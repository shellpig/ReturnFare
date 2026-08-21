extends SceneTree

## P3-A headless 驗收測試：夜間資料真值化。
## 跑法：
##   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/test_p3a.gd
## 全綠 exit 0；任一失敗 exit 1。

const DataFacts := preload("res://scripts/core/data_facts.gd")
const PanelBuilder := preload("res://scripts/core/panel_builder.gd")
const PlaythroughGreedy := preload("res://tests/headless/playthrough_greedy.gd")


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
		push_error("P3-A: Data failed to load; abort")
		quit(1)
		return

	var failed := 0
	failed += _test_true_data_alignment(data_node)
	failed += _test_knowledge_card_naming_and_text(data_node)
	failed += _test_night_names_review(data_node)
	failed += _test_ahong_reject_reasons(data_node)
	failed += _test_teaser_only_properties(data_node)
	failed += _test_negative_fixtures()
	failed += _test_baseline_checkpoint_replay(self, data_node)

	Engine.unregister_singleton("Data")
	Engine.unregister_singleton("GameState")

	if failed > 0:
		push_error("P3-A: %d test(s) failed" % failed)
		quit(1)
	else:
		print("P3-A: all tests passed")
		quit(0)


func _ok(msg: String) -> int:
	print("  ok  " + msg)
	return 0


func _fail(msg: String) -> int:
	push_error("  FAIL  " + msg)
	return 1


# ── 1. 真資料對位結構與型別斷言 ──────────────────────────────────────────────

func _test_true_data_alignment(data_node: Node) -> int:
	var failed := 0
	var loader: DataLoader = data_node.loader

	var distinct_cps: Dictionary = {}
	var reveal_rows_count := 0
	var night_only_count := 0

	for lid in loader.locations:
		var loc: Dictionary = loader.locations[lid]
		if str(loc.get("layer", "")) != "night":
			continue

		var cp: Variant = loc.get("day_counterpart")
		var reveal: Variant = loc.get("night_reveal")

		if cp != null:
			distinct_cps[str(cp)] = true
			reveal_rows_count += 1

			if reveal == null or not (reveal is String) or str(reveal).is_empty():
				failed += _fail("%s: day_counterpart 為 %s 但缺少 night_reveal" % [lid, str(cp)])
				continue

			var card_id := str(reveal)
			if not loader.cards.has(card_id):
				failed += _fail("%s: night_reveal 卡片 %s 不存在" % [lid, card_id])
			else:
				var cdef: Dictionary = loader.cards[card_id]
				if str(cdef.get("type", "")) != "knowledge":
					failed += _fail("%s: 對位卡 %s 型別不是 knowledge（實際為 %s）" % [lid, card_id, str(cdef.get("type"))])
				if not bool(cdef.get("slotless", false)):
					failed += _fail("%s: 對位卡 %s slotless 必須為 true" % [lid, card_id])
		else:
			night_only_count += 1
			if reveal != null:
				failed += _fail("%s: 夜間限定 row 的 night_reveal 必須為 null（實際為 %s）" % [lid, str(reveal)])

	if distinct_cps.size() != 10:
		failed += _fail("預期 10 個 distinct day_counterpart，實際 %d 個" % distinct_cps.size())
	if reveal_rows_count != 12:
		failed += _fail("預期 12 個可對位 night row，實際 %d 個" % reveal_rows_count)
	if night_only_count != 16:
		failed += _fail("預期 16 個夜間限定 row，實際 %d 個" % night_only_count)

	# 驗證 Lint 11 與 Lint 12 在真資料上為 0 錯誤
	var lint11_errs := DataLoader.lint_night_alignment(loader)
	if not lint11_errs.is_empty():
		failed += _fail("真資料 Lint 11 失敗: %s" % str(lint11_errs))

	var lint12_errs := DataLoader.lint_night_locations(loader)
	if not lint12_errs.is_empty():
		failed += _fail("真資料 Lint 12 失敗: %s" % str(lint12_errs))

	if failed == 0:
		failed += _ok("真資料對位完整性驗證通過（10 counterparts, 12 reveal rows, 16 night-only rows）")

	return failed


# ── 2. 對位知識卡名稱與文字規約 ──────────────────────────────────────────────

func _test_knowledge_card_naming_and_text(data_node: Node) -> int:
	var failed := 0
	var loader: DataLoader = data_node.loader

	# 收集所有夜間分區/引子名稱
	var night_location_names: Array[String] = []
	for lid in loader.locations:
		var loc: Dictionary = loader.locations[lid]
		if str(loc.get("layer", "")) == "night":
			night_location_names.append(str(loc.get("name", "")))

	for lid in loader.locations:
		var loc: Dictionary = loader.locations[lid]
		if str(loc.get("layer", "")) != "night":
			continue
		var cp: Variant = loc.get("day_counterpart")
		if cp == null:
			continue

		var reveal_id := str(loc.get("night_reveal", ""))
		var card: Dictionary = loader.cards.get(reveal_id, {}) as Dictionary
		var day_loc: Dictionary = loader.locations.get(str(cp), {}) as Dictionary
		var day_name := str(day_loc.get("name", ""))
		var card_name := str(card.get("name", ""))
		var card_text := str(card.get("text", ""))

		# 名稱必須包含對應白天地點名稱
		if not day_name in card_name:
			failed += _fail("對位卡 %s 名稱（%s）未包含白天地點名稱（%s）" % [reveal_id, card_name, day_name])

		# 文字不應洩漏其他夜間分區引子名稱（如很長的走廊、有蒸氣的樓下等特定夜點名）
		for n_name in ["很長的走廊", "有蒸氣的樓下", "數木牌的屋子", "有音樂的地方"]:
			if n_name in card_text:
				failed += _fail("對位卡 %s 文字（%s）劇透了未到訪夜間分區名（%s）" % [reveal_id, card_text, n_name])

	if failed == 0:
		failed += _ok("10 張對位卡名稱均包含白天地點名稱且文字無特定夜間分區劇透")

	return failed


# ── 3. 28 個夜間名稱審查 ──────────────────────────────────────────────────

func _test_night_names_review(data_node: Node) -> int:
	var failed := 0
	var loader: DataLoader = data_node.loader

	# n_ahong_2 不得再叫「血還是新的」
	var n_ahong_2_name := str((loader.locations.get("n_ahong_2", {}) as Dictionary).get("name", ""))
	if n_ahong_2_name != "有血跡的地方":
		failed += _fail("n_ahong_2 名稱應為「有血跡的地方」，實際為：%s" % n_ahong_2_name)

	var night_count := 0
	for lid in loader.locations:
		var loc: Dictionary = loader.locations[lid]
		if str(loc.get("layer", "")) != "night":
			continue
		night_count += 1
		var loc_name := str(loc.get("name", "")).strip_edges()
		if loc_name.is_empty():
			failed += _fail("夜間地點 %s 名稱不可為空" % lid)

	if night_count != 28:
		failed += _fail("夜間地點總數應為 28，實際 %d" % night_count)

	if failed == 0:
		failed += _ok("28 個夜間名稱審查通過（n_ahong_2 正確改名為引子名）")

	return failed


# ── 4. 阿宏鏈 6 個地點級門檻理由 ──────────────────────────────────────────

func _test_ahong_reject_reasons(data_node: Node) -> int:
	var failed := 0
	var loader: DataLoader = data_node.loader

	var ahong_expected_reasons := {
		"n_ahong_2": "你還沒跟完上一段痕跡。",
		"n_ahong_3": "你還沒跟完上一段痕跡。",
		"n_ahong_4": "你還沒跟完上一段痕跡。",
		"n_ahong_5": "你手上的路線知識還少了一段。",
		"n_ahong_6": "你手上的路線知識還少了一段。",
		"n_ahong_7": "三個對位點尚未連齊。",
	}

	for lid in ahong_expected_reasons.keys():
		var loc: Dictionary = loader.locations.get(lid, {}) as Dictionary
		var reason := str(loc.get("reject_reason", ""))
		var expected: String = ahong_expected_reasons[lid]
		if reason != expected:
			failed += _fail("%s reject_reason 不符：預期「%s」，實際「%s」" % [lid, expected, reason])

	if failed == 0:
		failed += _ok("阿宏鏈 6 個門檻地點均有正確具體的 reject_reason")

	return failed


# ── 5. n_corridor_end teaser_only 屬性 ─────────────────────────────────────

func _test_teaser_only_properties(data_node: Node) -> int:
	var failed := 0
	var loader: DataLoader = data_node.loader

	var loc: Dictionary = loader.locations.get("n_corridor_end", {}) as Dictionary
	if not bool(loc.get("teaser_only", false)):
		failed += _fail("n_corridor_end 必須標記 teaser_only: true")
	if loc.get("madness_cost") != null:
		failed += _fail("n_corridor_end madness_cost 必須為 null")
	if loc.get("day_counterpart") != null:
		failed += _fail("n_corridor_end day_counterpart 必須為 null")
	if loc.get("night_reveal") != null:
		failed += _fail("n_corridor_end night_reveal 必須為 null")
	if str(loc.get("reject_reason", "")).is_empty():
		failed += _fail("n_corridor_end 必須有非空的 reject_reason")
	if int(loc.get("chapter", -1)) != 3:
		failed += _fail("n_corridor_end chapter 必須為 3")

	if failed == 0:
		failed += _ok("n_corridor_end 正確配置為 teaser_only 且三欄為 null")

	return failed


# ── 6. 負向 Fixture 獨立測試 ───────────────────────────────────────────────

func _test_negative_fixtures() -> int:
	var failed := 0

	# 1. 同一 counterpart 指到兩張卡
	var l1 := DataLoader.new("res://tests/fixtures/broken/p3a_same_cp_two_cards/")
	if not l1.load_all():
		failed += _fail("fixture 1 讀取失敗: %s" % str(l1.errors))
	else:
		var errs1 := DataLoader.lint_night_alignment(l1)
		var matched1 := false
		for e in errs1:
			if "指向多個不同的 night_reveal" in e:
				matched1 = true
		if not matched1:
			failed += _fail("fixture 1 未觸發預期錯誤；實際報錯：%s" % str(errs1))
		else:
			failed += _ok("負向 fixture 1: 同一 counterpart 指到兩張卡被 Lint 11 成功攔截")

	# 2. 兩個不同 counterpart 指到同一張卡
	var l2 := DataLoader.new("res://tests/fixtures/broken/p3a_diff_cps_same_card/")
	if not l2.load_all():
		failed += _fail("fixture 2 讀取失敗: %s" % str(l2.errors))
	else:
		var errs2 := DataLoader.lint_night_alignment(l2)
		var matched2 := false
		for e in errs2:
			if "共用了同一張對位卡" in e:
				matched2 = true
		if not matched2:
			failed += _fail("fixture 2 未觸發預期錯誤；實際報錯：%s" % str(errs2))
		else:
			failed += _ok("負向 fixture 2: 不同 counterpart 共用同一張卡被 Lint 11 成功攔截")

	# 3. 對位卡非 knowledge / 非 slotless
	var l3 := DataLoader.new("res://tests/fixtures/broken/p3a_card_not_knowledge/")
	if not l3.load_all():
		failed += _fail("fixture 3 讀取失敗: %s" % str(l3.errors))
	else:
		var errs3 := DataLoader.lint_night_alignment(l3)
		var matched3 := false
		for e in errs3:
			if "型別不是 knowledge" in e or "slotless 必須為 true" in e:
				matched3 = true
		if not matched3:
			failed += _fail("fixture 3 未觸發預期錯誤；實際報錯：%s" % str(errs3))
		else:
			failed += _ok("負向 fixture 3: 對位卡非 knowledge/slotless 被 Lint 11 成功攔截")

	# 4. teaser 缺理由或帶價碼
	var l4 := DataLoader.new("res://tests/fixtures/broken/p3a_teaser_bad/")
	if not l4.load_all():
		failed += _fail("fixture 4 讀取失敗: %s" % str(l4.errors))
	else:
		var errs4 := DataLoader.lint_night_locations(l4)
		var matched4 := false
		for e in errs4:
			if "teaser_only" in e:
				matched4 = true
		if not matched4:
			failed += _fail("fixture 4 未觸發預期錯誤；實際報錯：%s" % str(errs4))
		else:
			failed += _ok("負向 fixture 4: teaser 帶價碼/缺理由被 Lint 12 成功攔截")

	# 5. chapter 與 earliest 不一致
	var l5 := DataLoader.new("res://tests/fixtures/broken/p3a_chapter_earliest_mismatch/")
	if not l5.load_all():
		failed += _fail("fixture 5 讀取失敗: %s" % str(l5.errors))
	else:
		var errs5 := DataLoader.lint_night_locations(l5)
		var matched5 := false
		for e in errs5:
			if "不一致" in e:
				matched5 = true
		if not matched5:
			failed += _fail("fixture 5 未觸發預期錯誤；實際報錯：%s" % str(errs5))
		else:
			failed += _ok("負向 fixture 5: chapter 與 earliest_night 不一致被 Lint 12 成功攔截")

	# 6. 一般 night row 缺 madness_cost 欄位（拼成 madness_costs）
	var l6 := DataLoader.new("res://tests/fixtures/broken/p3a_missing_field_or_misspelled/")
	if not l6.load_all():
		failed += _fail("fixture 6 讀取失敗: %s" % str(l6.errors))
	else:
		var errs6 := DataLoader.lint_night_locations(l6)
		var matched6 := false
		for e in errs6:
			if "缺少 madness_cost 欄位" in e:
				matched6 = true
		if not matched6:
			failed += _fail("fixture 6 未觸發預期錯誤；實際報錯：%s" % str(errs6))
		else:
			failed += _ok("負向 fixture 6: madness_cost 拼錯/缺少被 Lint 12 成功攔截")

	return failed


# ── 7. Baseline Checkpoint 重演比對 ────────────────────────────────────────

func _test_baseline_checkpoint_replay(tree: SceneTree, data_node: Node) -> int:
	var failed := 0

	var baseline_path := "res://_qa/p3a_baseline/p3a_night_baseline.json"
	var expected_path := "res://_qa/p3a_baseline/p3a_night_baseline.expected.json"

	var f_base_text := FileAccess.get_file_as_string(baseline_path)
	var f_exp_text := FileAccess.get_file_as_string(expected_path)

	if f_base_text.is_empty() or f_exp_text.is_empty():
		return _fail("讀不到 baseline 檔案：%s 或 %s" % [baseline_path, expected_path])

	var base_dict: Dictionary = JSON.parse_string(f_base_text)
	var expected_dict: Dictionary = JSON.parse_string(f_exp_text)

	# 1. 載入同一份狀態 JSON 比對 available_locations()
	var gs_avail: Node = PlaythroughGreedy.setup_game_state(tree, data_node)
	_reset_state(gs_avail)
	gs_avail.deserialize(base_dict)
	var actual_avail: Array[String] = PanelBuilder.available_locations(gs_avail, data_node)
	var expected_avail: Array = expected_dict.get("available_locations", []) as Array
	if Array(actual_avail) != expected_avail:
		failed += _fail("available_locations 不一致：\n  實際：%s\n  預期：%s" % [str(actual_avail), str(expected_avail)])

	# 2. 比對首次發卡
	var gs_grant: Node = PlaythroughGreedy.setup_game_state(tree, data_node)
	_reset_state(gs_grant)
	gs_grant.deserialize(base_dict)
	var exp_grant: Dictionary = expected_dict.get("first_card_grant", {}) as Dictionary
	var target_loc: String = str(exp_grant.get("target_location", "n_plaza"))
	var actual_lines: PackedStringArray = gs_grant.open_night_marker(target_loc)
	var actual_grant: Dictionary = {
		"target_location": target_loc,
		"lines": Array(actual_lines),
		"night_markers_opened": (gs_grant.get("night_markers_opened") as Dictionary).duplicate(true),
		"hand": (gs_grant.get("hand") as Array).duplicate(true),
		"madness_clock": (gs_grant.get("madness_clock") as Dictionary).duplicate(true),
	}
	var actual_grant_norm: Dictionary = JSON.parse_string(JSON.stringify(actual_grant))
	if actual_grant_norm != exp_grant:
		failed += _fail("首次發卡結果不一致：\n  實際：%s\n  預期：%s" % [str(actual_grant_norm), str(exp_grant)])

	# 3. 比對 fixed 流程
	var gs_fixed: Node = PlaythroughGreedy.setup_game_state(tree, data_node)
	_reset_state(gs_fixed)
	gs_fixed.deserialize(base_dict)
	gs_fixed.sleep_night()
	gs_fixed.advance_phase()
	PlaythroughGreedy.execute_action_phase(gs_fixed, data_node, 15, "morning")
	gs_fixed.advance_phase()
	PlaythroughGreedy.execute_action_phase(gs_fixed, data_node, 15, "afternoon")
	gs_fixed.advance_phase()
	PlaythroughGreedy.execute_evening_phase(gs_fixed, data_node, 15)
	gs_fixed.advance_phase()
	var actual_avail_d15: Array[String] = PanelBuilder.available_locations(gs_fixed, data_node)
	gs_fixed.play_night_fixed()
	var actual_beats_entered_d15: Array = (gs_fixed.get("beats_entered") as Dictionary).keys()
	actual_beats_entered_d15.sort()
	var actual_fixed: Dictionary = {
		"day": int(gs_fixed.get("day")),
		"phase": str(gs_fixed.get("phase")),
		"available_locations": Array(actual_avail_d15),
		"beats_entered": actual_beats_entered_d15,
	}
	var actual_fixed_norm: Dictionary = JSON.parse_string(JSON.stringify(actual_fixed))
	var exp_fixed: Dictionary = expected_dict.get("fixed_flow", {}) as Dictionary
	if actual_fixed_norm != exp_fixed:
		failed += _fail("fixed 流程結果不一致：\n  實際：%s\n  預期：%s" % [str(actual_fixed_norm), str(exp_fixed)])

	if failed == 0:
		failed += _ok("P3-A 變更後重演 baseline checkpoint 三項輸出與 expected 基準全等！")

	return failed


static func _reset_state(gs: Node) -> void:
	gs.set("day", 1)
	gs.set("phase", "morning")
	gs.set("hand", ["protagonist"])
	gs.set("beats_entered", {})
	gs.set("slots_placed", {})
	gs.set("choices", {})
	gs.set("flags", {})
	gs.set("switches", {})
	gs.set("switch_progress", {})
	gs.set("relations", {})
	gs.set("action_spent", false)
	gs.set("npc_action_counts", {})
	gs.set("knowledge", {})
	gs.set("madness_clock", {})
	gs.set("night_markers_opened", {})
	gs.set("night_location_chosen", "")
	gs.set("indulgence_count", 0)
	gs.set("madness_cards_cleared", 0)
	gs.set("forced_pending", [])
	gs.set("last_forced_lines", PackedStringArray())
