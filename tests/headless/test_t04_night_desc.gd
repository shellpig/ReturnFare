extends SceneTree

## T-04 驗證：夜間地點簡介、UI 詳情面板串接、無劇透 Lint 與套語密度
## 包含 28 個 night row desc、三狀態顯示契約、fallback 退路與變異檢驗。

const PlaythroughGreedy := preload("res://tests/headless/playthrough_greedy.gd")
const PanelBuilder := preload("res://scripts/core/panel_builder.gd")

const STOCK_PHRASES: Array[String] = [
	# 膨脹形容詞 (20)
	"細膩", "精緻", "深刻", "雋永", "震撼", "極致", "絕美", "唯美", "璀璨", "耀眼",
	"動人", "驚豔", "扣人心弦", "刻骨銘心", "淋漓盡致", "恰到好處", "無可取代", "分毫不差", "無邊無際", "無聲無息",
	# 小說套語 (17)
	"空氣彷彿凝結", "時間彷彿靜止", "心頭一緊", "喉頭一哽", "鼻頭一酸", "眼眶泛紅", "嘴角勾起", "幾不可聞",
	"緩緩開口", "輕聲說道", "深吸一口氣", "瞳孔微縮", "指尖顫抖", "目光交會", "意味深長", "若有似無", "不易察查", "不易察覺",
	# 標誌性副詞與片語 (18)
	"說不出的", "道不盡的", "難以言喻", "莫名的", "空氣中瀰漫", "內心深處", "宛如", "彷彿",
	"猛然", "悄然", "驟然", "轟然", "溘然", "黯然", "毅然", "決然", "赫然", "儼然",
	# 宏大名詞 (13)
	"浩瀚", "瑰寶", "殿堂", "盛宴", "樂章", "史詩", "篇章", "里程碑", "縮影", "光輝", "靈魂深處", "印記",
	# 濾鏡詞 (4)
	"感覺到", "意識到", "注意到", "不禁",
	# 四字成語堆疊 (16)
	"白駒過隙", "蒸蒸日上", "有聲有色", "風雨飄搖", "撒手人寰", "長相廝守", "結為連理", "結髮為伴",
	"平淡相守", "苦心經營", "舉手投足", "溘然長逝", "急劇惡化", "來勢洶洶", "彈指而過", "悄然而逝"
]

const NIGHT_LOCATIONS_28: Array[String] = [
	"n_corridor", "n_exit", "n_queue", "n_litwindow", "n_watersound",
	"n_ahong_1", "n_woodtags", "n_source", "n_manydoors", "n_music",
	"n_lockedhouse", "n_ahong_2", "n_nodoor", "n_landmark", "n_plaza",
	"n_ahong_3", "n_litcorridor", "n_higher", "n_ahong_4", "n_emptyspot",
	"n_gathering", "n_ahong_5", "n_steam_below", "n_ahong_6", "n_emptyspot_2",
	"n_behind_temple", "n_ahong_7", "n_corridor_end"
]


func _initialize() -> void:
	await process_frame
	var data_node: Node = get_root().get_node_or_null("Data")
	var gs: Node = get_root().get_node_or_null("GameState")
	if data_node == null:
		data_node = PlaythroughGreedy.setup_data(self)
		await process_frame
	if gs == null:
		gs = PlaythroughGreedy.setup_game_state(self, data_node)

	if not bool(data_node.get("ok")):
		push_error("T-04: Data 載入失敗")
		quit(1)
		return

	var failed := 0
	failed += _test_group1_night_locations_desc_presence(gs, data_node)
	failed += await _test_group2_desc_missing_fallback(gs, data_node)
	failed += _test_group3_counterpart_spoiler_lint(data_node)
	failed += _test_group4_stock_phrase_density(data_node)
	failed += await _test_group5_ui_three_states_desc_consistency(gs, data_node)

	if failed > 0:
		print("\n=== T-04 測試失敗，共有 %d 項錯誤 ===" % failed)
		quit(1)
	else:
		print("\n=== T-04 全部測試通過（Exit Code 0）===")
		quit(0)


func _ok(msg: String) -> int:
	print("  [OK] %s" % msg)
	return 0


func _fail(msg: String) -> int:
	print("  [FAIL] %s" % msg)
	return 1


func _reset_gs(gs: Node) -> void:
	gs.set("day", 1)
	gs.set("phase", "night")
	gs.set("hand", [])
	gs.set("madness", 0)
	gs.set("knowledge", {})
	gs.set("flags", {})
	gs.set("night_locations_seen", {})
	gs.set("day_locations_visited", {})
	gs.set("night_chosen_location", "")
	gs.set("night_sleep_pending", false)


# ── Group 1: 28 個夜間地點 desc 完整性與 location_summary ──
func _test_group1_night_locations_desc_presence(gs: Node, data_node: Node) -> int:
	print("--- Group 1: 28 night locations desc presence ---")
	var failed := 0
	_reset_gs(gs)
	var loader: DataLoader = data_node.get("loader") as DataLoader

	var count := 0
	for lid in NIGHT_LOCATIONS_28:
		if not loader.locations.has(lid):
			failed += _fail("缺少夜間地點: %s" % lid)
			continue
		var loc: Dictionary = loader.locations[lid] as Dictionary
		var desc: String = str(loc.get("desc", "")).strip_edges()
		if desc.is_empty():
			failed += _fail("%s 的 desc 為空" % lid)
		elif desc.length() < 30 or desc.length() > 60:
			failed += _fail("%s 的 desc 字數（%d 字）不在 30-60 字規格內: %s" % [lid, desc.length(), desc])
		else:
			count += 1

		var summary: Dictionary = PanelBuilder.location_summary(lid, gs, data_node)
		var sum_desc: String = str(summary.get("desc", ""))
		if sum_desc != desc:
			failed += _fail("%s location_summary 回傳的 desc 不符" % lid)

	if count == 28:
		failed += _ok("28 個夜間地點 desc 全部非空、字數均在 30-60 字內且 location_summary 正確透傳")
	return failed


# ── Group 2: 缺欄位退路測試（無 desc 的 mock night row）──
func _test_group2_desc_missing_fallback(gs: Node, data_node: Node) -> int:
	print("--- Group 2: missing desc fallback ---")
	var failed := 0
	_reset_gs(gs)
	var loader: DataLoader = data_node.get("loader") as DataLoader

	var mock_lid := "mock_night_no_desc"
	loader.locations[mock_lid] = {
		"id": mock_lid,
		"name": "無簡介夜間測試點",
		"layer": "night",
		"chapter": 1,
		"earliest_night": 1,
		"madness_cost": 0,
		"day_counterpart": null,
		"night_reveal": null,
		"map": { "x": 50, "y": 50 }
	}

	# 1. location_summary 回傳 desc 為空字串
	var summary: Dictionary = PanelBuilder.location_summary(mock_lid, gs, data_node)
	if str(summary.get("desc", "")).is_empty():
		failed += _ok("mock 地點缺少 desc 欄位時，location_summary 回傳 desc 為空字串")
	else:
		failed += _fail("mock 地點缺少 desc 欄位但 location_summary 回傳非空: %s" % str(summary.get("desc")))

	# 2. UI 渲染不崩潰且不生成 night_desc 節點
	var loc_scene: PackedScene = load("res://scenes/ui/location_panel.tscn")
	var panel: Node = loc_scene.instantiate()
	get_root().add_child(panel)
	await process_frame

	panel.call("show_night_details", mock_lid)
	await process_frame

	var beat_container: Node = panel.find_child("BeatContainer", true, false)
	var has_desc_node := false
	var has_status_node := false
	for child in beat_container.get_children():
		if child is Label:
			var qaid := str(child.get_meta("qa_id", ""))
			if qaid.begins_with("night_desc::"):
				has_desc_node = true
			elif qaid.begins_with("night_status::"):
				has_status_node = true

	if has_status_node and not has_desc_node:
		failed += _ok("地點缺少 desc 時，show_night_details 正確渲染 status 但隱藏/不生成 desc 標籤且不崩潰")
	else:
		failed += _fail("缺少 desc 渲染異常: has_status=%s, has_desc=%s" % [has_status_node, has_desc_node])

	loader.locations.erase(mock_lid)
	panel.queue_free()
	await process_frame
	return failed


# ── Group 3: 新增 Lint 22 無劇透與對位地點名稱檢查 ──
func _test_group3_counterpart_spoiler_lint(data_node: Node) -> int:
	print("--- Group 3: counterpart spoiler lint ---")
	var failed := 0
	var loader: DataLoader = data_node.get("loader") as DataLoader

	# 1. 正式資料 0 錯誤
	var errs := DataLoader.lint_night_location_descs(loader)
	if errs.is_empty():
		failed += _ok("正式資料通過 Lint 22，12 個對位地點 desc 無任何 day_counterpart 劇透名稱")
	else:
		failed += _fail("Lint 22 發現錯誤: %s" % str(errs))

	# 2. 變異測試：注入劇透名稱時 Lint 轉紅
	var orig_n_exit: Dictionary = (loader.locations["n_exit"] as Dictionary).duplicate(true)
	loader.locations["n_exit"]["desc"] = "站在山泉閣的石階頂端向下望去，底下的街道空無一人。"
	var mut_errs := DataLoader.lint_night_location_descs(loader)
	loader.locations["n_exit"] = orig_n_exit

	var mutation_caught := false
	for e in mut_errs:
		if e.contains("n_exit") and e.contains("山泉閣"):
			mutation_caught = true
			break
	if mutation_caught:
		failed += _ok("變異測試成功：將對位地點名塞入 desc 時，Lint 22 確實轉紅報錯")
	else:
		failed += _fail("變異測試失敗：Lint 22 未抓到注入的劇透名稱")

	return failed


# ── Group 4: 88 詞完整套語清單密度檢驗 ──
func _test_group4_stock_phrase_density(data_node: Node) -> int:
	print("--- Group 4: stock phrase density scan ---")
	var failed := 0
	var loader: DataLoader = data_node.get("loader") as DataLoader

	var total_chars := 0
	var hit_count := 0
	var hit_details: Array[String] = []

	for lid in NIGHT_LOCATIONS_28:
		var loc: Dictionary = loader.locations.get(lid, {}) as Dictionary
		var desc: String = str(loc.get("desc", ""))
		total_chars += desc.length()
		for phrase in STOCK_PHRASES:
			if desc.contains(phrase):
				hit_count += 1
				hit_details.append("%s 命中『%s』" % [lid, phrase])

	var density := 0.0
	if total_chars > 0:
		density = (float(hit_count) / float(total_chars)) * 1000.0

	print("  28 夜間地點 desc 總字數: %d 字，套語命中: %d 筆，密度: %.2f / 千字" % [
		total_chars, hit_count, density
	])

	if hit_count == 0 and density <= 1.5:
		failed += _ok("28 個夜間地點 desc 套語密度為 0.00 / 千字（標準 ≤ 1.5）")
	elif density <= 1.5:
		failed += _ok("28 個夜間地點 desc 套語密度符合標準 (%.2f <= 1.5): %s" % [density, str(hit_details)])
	else:
		failed += _fail("28 個夜間地點 desc 套語密度超標 (%.2f > 1.5): %s" % [density, str(hit_details)])

	return failed


# ── Group 5: UI 三狀態（未到訪／已到訪未對位／已對位）desc 一致性 ──
func _test_group5_ui_three_states_desc_consistency(gs: Node, data_node: Node) -> int:
	print("--- Group 5: UI three states desc consistency ---")
	var failed := 0
	_reset_gs(gs)
	var loader: DataLoader = data_node.get("loader") as DataLoader
	var expected_desc: String = str((loader.locations.get("n_exit", {}) as Dictionary).get("desc", ""))

	var loc_scene: PackedScene = load("res://scenes/ui/location_panel.tscn")
	var panel: Node = loc_scene.instantiate()
	get_root().add_child(panel)
	await process_frame

	# 1. 狀態一：尚未到訪
	panel.call("show_night_details", "n_exit")
	await process_frame
	var title_lbl: Label = panel.get_node("LocationTitle") as Label
	var found_desc_1 := ""
	for child in (panel.find_child("BeatContainer", true, false) as Node).get_children():
		if child is Label and str(child.get_meta("qa_id", "")) == "night_desc::n_exit":
			found_desc_1 = (child as Label).text
			break

	if title_lbl.text == "石階外的鎮" and found_desc_1 == expected_desc:
		failed += _ok("狀態一 [尚未到訪] 正確顯示引子名與 desc")
	else:
		failed += _fail("狀態一顯示異常: title='%s', desc='%s'" % [title_lbl.text, found_desc_1])

	# 2. 狀態二：已到訪未對位
	var seen_dict: Dictionary = gs.get("night_locations_seen") as Dictionary
	seen_dict["n_exit"] = true
	panel.call("show_night_details", "n_exit")
	await process_frame

	var found_desc_2 := ""
	for child in (panel.find_child("BeatContainer", true, false) as Node).get_children():
		if child is Label and str(child.get_meta("qa_id", "")) == "night_desc::n_exit":
			found_desc_2 = (child as Label).text
			break

	if title_lbl.text == "石階外的鎮" and found_desc_2 == expected_desc:
		failed += _ok("狀態二 [已到訪，尚未對位] 正確顯示引子名與同一段 desc")
	else:
		failed += _fail("狀態二顯示異常: title='%s', desc='%s'" % [title_lbl.text, found_desc_2])

	# 3. 狀態三：已對位
	var know_dict: Dictionary = gs.get("knowledge") as Dictionary
	know_dict["k_night_sanquan"] = true
	panel.call("show_night_details", "n_exit")
	await process_frame

	var found_desc_3 := ""
	for child in (panel.find_child("BeatContainer", true, false) as Node).get_children():
		if child is Label and str(child.get_meta("qa_id", "")) == "night_desc::n_exit":
			found_desc_3 = (child as Label).text
			break

	if title_lbl.text == "山泉閣" and found_desc_3 == expected_desc:
		failed += _ok("狀態三 [已對位] display_name 變成白天地點名『山泉閣』且顯示同一段 desc")
	else:
		failed += _fail("狀態三顯示異常: title='%s', desc='%s'" % [title_lbl.text, found_desc_3])

	panel.queue_free()
	await process_frame
	return failed
