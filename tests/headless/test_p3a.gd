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
	gs.set("flow_mode", "run")  # P5-D：fresh state 是 opening，本檔驗的是 run 層
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

	# 收集所有夜間分區/引子名稱（K-103：動態防護）
	var night_location_names: Array[String] = []
	for lid in loader.locations:
		var loc: Dictionary = loader.locations[lid]
		if str(loc.get("layer", "")) == "night":
			var n_name := str(loc.get("name", "")).strip_edges()
			if not n_name.is_empty():
				night_location_names.append(n_name)

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

		# 文字不應洩漏任何夜間分區引子名稱
		for n_name in night_location_names:
			if n_name in card_text:
				failed += _fail("對位卡 %s 文字（%s）洩漏了夜間分區名（%s）" % [reveal_id, card_text, n_name])

	if failed == 0:
		failed += _ok("10 張對位卡名稱均包含白天地點名稱且文字無夜間分區劇透（動態掃描 28 個夜間名稱）")

	return failed


# ── 3. 28 個夜間名稱審查 ──────────────────────────────────────────────────

func _test_night_names_review(data_node: Node) -> int:
	var failed := 0
	var loader: DataLoader = data_node.loader

	# n_ahong_2 不得再叫「血還是新的」
	var n_ahong_2_name := str((loader.locations.get("n_ahong_2", {}) as Dictionary).get("name", ""))
	if n_ahong_2_name.is_empty() or n_ahong_2_name == "血還是新的":
		failed += _fail("n_ahong_2 名稱不得為空且不得再叫「血還是新的」，實際為：%s" % n_ahong_2_name)

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
		failed += _ok("夜間地點總數為 28、名稱非空且 n_ahong_2 正確改名為引子名（K-104：其餘 27 個名稱與 primary beat 人工審查已落檔）")

	return failed


# ── 4. 阿宏鏈 6 個地點級門檻理由 ──────────────────────────────────────────

func _test_ahong_reject_reasons(data_node: Node) -> int:
	var failed := 0
	var loader: DataLoader = data_node.loader

	# 驗證 6 個帶 location requires 的阿宏 row 均有非空、非通用、語意對應的 reject_reason（K-109）
	var ahong_ids := ["n_ahong_2", "n_ahong_3", "n_ahong_4", "n_ahong_5", "n_ahong_6", "n_ahong_7"]
	var seen_reasons: Dictionary = {}

	for lid in ahong_ids:
		var loc: Dictionary = loader.locations.get(lid, {}) as Dictionary
		var reason := str(loc.get("reject_reason", "")).strip_edges()
		if reason.is_empty():
			failed += _fail("%s 缺少 reject_reason" % lid)
			continue
		if reason == "無法進入" or reason == "條件未達成" or reason == "未解鎖":
			failed += _fail("%s reject_reason 不得使用通用 fallback（實際為「%s」）" % [lid, reason])
		seen_reasons[lid] = reason

	# 語意對應斷言（非字串逐字拷貝，避免文案微調時假紅）
	# 2/3/4 指向上一段痕跡
	for lid in ["n_ahong_2", "n_ahong_3", "n_ahong_4"]:
		var r: String = str(seen_reasons.get(lid, ""))
		if not ("痕跡" in r or "上一段" in r):
			failed += _fail("%s reject_reason（%s）未指向上一段痕跡" % [lid, r])

	# 5 指向第一段路線知識
	var r5: String = str(seen_reasons.get("n_ahong_5", ""))
	var k1_name: String = str((loader.cards.get("k_ahong_point_1", {}) as Dictionary).get("name", ""))
	assert(not k1_name.is_empty(), "fixture 前提：k_ahong_point_1 有 name")
	if not ("路線" in r5 or "第一段" in r5 or k1_name in r5):
		failed += _fail("n_ahong_5 reject_reason（%s）未指向第一段路線知識" % r5)

	# 6 指向第二段路線知識，且與 5 不得完全相同
	var r6: String = str(seen_reasons.get("n_ahong_6", ""))
	var k2_name: String = str((loader.cards.get("k_ahong_point_2", {}) as Dictionary).get("name", ""))
	assert(not k2_name.is_empty(), "fixture 前提：k_ahong_point_2 有 name")
	if not ("路線" in r6 or "第二段" in r6 or k2_name in r6):
		failed += _fail("n_ahong_6 reject_reason（%s）未指向第二段路線知識" % r6)
	if r5 == r6:
		failed += _fail("n_ahong_5 與 n_ahong_6 要求不同知識卡，reject_reason 不應完全相同")

	# 7 指向三個對位點
	var r7: String = str(seen_reasons.get("n_ahong_7", ""))
	if not ("對位點" in r7 or "三個" in r7):
		failed += _fail("n_ahong_7 reject_reason（%s）未指向三個對位點" % r7)

	if failed == 0:
		failed += _ok("阿宏鏈 6 個門檻地點均有非空、彼此語意對應且指向各自要求之 reject_reason")

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

	# 7. teaser 地點單獨缺 earliest_night 或 chapter 被 Lint 12 攔截 (K-108)
	var l7 := DataLoader.new("res://tests/fixtures/broken/p3a_teaser_missing_time_column/")
	if not l7.load_all():
		failed += _fail("fixture 7 讀取失敗: %s" % str(l7.errors))
	else:
		var errs7 := DataLoader.lint_night_locations(l7)
		var has_no_earliest_err := false
		var has_no_chapter_err := false
		for e in errs7:
			if "n_teaser_no_earliest" in e and "缺少有效的 earliest_night" in e:
				has_no_earliest_err = true
			if "n_teaser_no_chapter" in e and "缺少有效的 chapter" in e:
				has_no_chapter_err = true
		if not has_no_earliest_err:
			failed += _fail("fixture 7: n_teaser_no_earliest 未報出缺少 earliest_night；實際報錯：%s" % str(errs7))
		if not has_no_chapter_err:
			failed += _fail("fixture 7: n_teaser_no_chapter 未報出缺少 chapter；實際報錯：%s" % str(errs7))
		if has_no_earliest_err and has_no_chapter_err:
			failed += _ok("負向 fixture 7: teaser 單獨缺 earliest_night 或 chapter 均被 Lint 12 成功攔截 (K-108)")

	# 8. 一般 night row 缺 earliest_night (K-110)
	var l8 := DataLoader.new("res://tests/fixtures/broken/p3a_missing_earliest_night/")
	if not l8.load_all():
		failed += _fail("fixture 8 讀取失敗: %s" % str(l8.errors))
	else:
		var errs8 := DataLoader.lint_night_locations(l8)
		var matched8 := false
		for e in errs8:
			if "缺少有效的 earliest_night" in e:
				matched8 = true
		if not matched8:
			failed += _fail("fixture 8 未觸發預期錯誤；實際報錯：%s" % str(errs8))
		else:
			failed += _ok("負向 fixture 8: 一般 night row 缺 earliest_night 被 Lint 12 成功攔截 (K-110)")

	# 9. 一般 night row 缺 chapter (K-110)
	var l9 := DataLoader.new("res://tests/fixtures/broken/p3a_missing_chapter/")
	if not l9.load_all():
		failed += _fail("fixture 9 讀取失敗: %s" % str(l9.errors))
	else:
		var errs9 := DataLoader.lint_night_locations(l9)
		var matched9 := false
		for e in errs9:
			if "缺少有效的 chapter" in e:
				matched9 = true
		if not matched9:
			failed += _fail("fixture 9 未觸發預期錯誤；實際報錯：%s" % str(errs9))
		else:
			failed += _ok("負向 fixture 9: 一般 night row 缺 chapter 被 Lint 12 成功攔截 (K-110)")

	# 10. 一般 night row madness_cost 為負值 (K-110)
	var l10 := DataLoader.new("res://tests/fixtures/broken/p3a_negative_madness_cost/")
	if not l10.load_all():
		failed += _fail("fixture 10 讀取失敗: %s" % str(l10.errors))
	else:
		var errs10 := DataLoader.lint_night_locations(l10)
		var matched10 := false
		for e in errs10:
			if "madness_cost 必須為 >= 0 之整數" in e:
				matched10 = true
		if not matched10:
			failed += _fail("fixture 10 未觸發預期錯誤；實際報錯：%s" % str(errs10))
		else:
			failed += _ok("負向 fixture 10: madness_cost 為負值被 Lint 12 成功攔截 (K-110)")

	# 11. 欄位型別錯誤 (K-110)
	# 兩個 row 各自只踩一道防線，因此刪掉型別／整數性檢查就一定會紅：
	#   n_string_chapter      chapter 寫成字串 "2"——範圍檢查攔不到（int("2") == 2 落在 1-3），只有型別檢查抓得到
	#   n_fractional_earliest earliest_night 寫成 15.5——範圍檢查攔不到（15 落在 1-45），只有整數性檢查抓得到
	# 用 "one" 那種寫不出數字的值不算數：int("one") == 0，會被範圍檢查順手攔下，型別檢查根本沒出手（K-113）。
	var l11 := DataLoader.new("res://tests/fixtures/broken/p3a_invalid_type_field/")
	if not l11.load_all():
		failed += _fail("fixture 11 讀取失敗: %s" % str(l11.errors))
	else:
		var errs11 := DataLoader.lint_night_locations(l11)
		var has_string_chapter_err := false
		var has_fractional_earliest_err := false
		for e in errs11:
			if "n_string_chapter" in e and "缺少有效的 chapter" in e:
				has_string_chapter_err = true
			if "n_fractional_earliest" in e and "缺少有效的 earliest_night" in e:
				has_fractional_earliest_err = true
		if not has_string_chapter_err:
			failed += _fail("fixture 11: chapter 寫成字串未被攔下；實際報錯：%s" % str(errs11))
		if not has_fractional_earliest_err:
			failed += _fail("fixture 11: earliest_night 寫成小數未被攔下；實際報錯：%s" % str(errs11))
		if has_string_chapter_err and has_fractional_earliest_err:
			failed += _ok("負向 fixture 11: 字串型別與小數值均被 Lint 12 成功攔截 (K-110／K-113)")

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
	var actual_res: Dictionary = gs_grant.enter_night_location(target_loc)
	var actual_lines: PackedStringArray = actual_res.get("lines", PackedStringArray())
	var actual_grant: Dictionary = {
		"target_location": target_loc,
		"lines": Array(actual_lines),
		"night_locations_seen": (gs_grant.get("night_locations_seen") as Dictionary).duplicate(true),
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
	gs.set("night_locations_seen", {})
	gs.set("night_once_beats_seen", {})
	gs.set("madness_clock", {})
	gs.set("night_location_chosen", "")
	gs.set("night_sleep_pending", false)
	gs.set("indulgence_count", 0)
	gs.set("madness_cards_cleared", 0)
	gs.set("forced_pending", [])
	gs.set("last_forced_lines", PackedStringArray())
