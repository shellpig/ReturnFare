extends SceneTree

## T-03 驗證：白天地點空點問題、推進按鈕文案、進門立刻播放與地點簡介
## 包含 Step 1、Step 2、Step 3 全部驗收條目。

const PlaythroughGreedy := preload("res://tests/headless/playthrough_greedy.gd")
const PanelBuilder := preload("res://scripts/core/panel_builder.gd")

const STOCK_PHRASES: Array[String] = [
	# 膨脹形容詞 (20)
	"細膩", "精緻", "深刻", "雋永", "震撼", "極致", "絕美", "唯美", "璀璨", "耀眼",
	"動人", "驚豔", "扣人心弦", "刻骨銘心", "淋漓盡致", "恰到好處", "無可取代", "分毫不差", "無邊無際", "無聲無息",
	# 小說套語 (17)
	"空氣彷彿凝結", "時間彷彿靜止", "心頭一緊", "喉頭一哽", "鼻頭一酸", "眼眶泛紅", "嘴角勾起", "幾不可聞",
	"緩緩開口", "輕聲說道", "深吸一口氣", "瞳孔微縮", "指尖顫抖", "目光交會", "意味深長", "若有似無", "不易察覺",
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

const DAY_LOCATIONS_20: Array[String] = [
	"sanquan", "jinghe", "oldstreet", "temple", "clinic",
	"riverside", "columbarium", "oldschool", "bathhouse", "busstop",
	"communitycenter", "oldhouse", "police", "clinic_back", "registry_office",
	"upstream", "old_bathhouse", "jinghe_back", "oldhouse_room", "temple_back"
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
		push_error("T-03: Data 載入失敗")
		quit(1)
		return

	var failed := 0
	failed += await _test_group1_unseen_content_and_advance_hints(gs, data_node)
	failed += await _test_group2_show_location_immediate_playback(gs, data_node)
	failed += await _test_group3_daytime_button_enablement_matrix(gs, data_node)
	failed += _test_group4_day_locations_visited_meta_and_save_validation(gs, data_node)
	failed += _test_group5_d1_auto_enter_records_busstop(gs, data_node)
	failed += await _test_group6_day_locations_desc_and_fallback(gs, data_node)
	failed += _test_group7_stock_phrase_density(data_node)

	if failed > 0:
		push_error("=== T-03 TOTAL FAILED: %d ===" % failed)
		quit(1)
	else:
		print("\n=== T-03 ALL TESTS PASSED ===")
		quit(0)


func _ok(msg: String) -> int:
	print("  [OK] %s" % msg)
	return 0


func _fail(msg: String) -> int:
	push_error("  [FAIL] %s" % msg)
	return 1


func _reset_gs(gs: Node) -> void:
	gs.call("_reset_run_state")
	gs.set("day_locations_visited", {})
	gs.set("night_locations_seen", {})
	gs.set("night_once_beats_seen", {})
	gs.set("knowledge", {})
	gs.set("flow_mode", gs.FLOW_RUN)
	gs.set("active_ending", {})


# ── Group 1: has_unseen_content() 與推進按鈕三態 ────────────────────────────
func _test_group1_unseen_content_and_advance_hints(gs: Node, _data_node: Node) -> int:
	print("--- Group 1: has_unseen_content() & Advance hint strings ---")
	var failed := 0
	_reset_gs(gs)

	# 第 2 天上午：山泉閣有 d2_morning_intro（fixed beat，無玩家槽）
	gs.set("day", 2)
	gs.set("phase", "morning")
	gs.call("gain_card", "protagonist")

	# (1) 未進山泉閣前：has_any_legal_action 為 false，has_unseen_content 為 true
	var action1: bool = gs.has_any_legal_action()
	var unseen1: bool = gs.has_unseen_content()
	if not action1 and unseen1:
		failed += _ok("D2 morning 未進山泉閣：has_any_legal_action() == false, has_unseen_content() == true")
	else:
		failed += _fail("D2 morning 未進山泉閣狀態不符: action=%s, unseen=%s" % [action1, unseen1])

	# (2) 測試 main.gd 在此狀態下的按鈕文字
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var main_inst: Control = main_scene.instantiate()
	get_root().add_child(main_inst)
	await process_frame

	var adv_btn: Button = main_inst.get_node("AdvanceButton")
	main_inst.call("_refresh_advance_hint")
	if adv_btn.text == "推進時段（還有演出沒看）":
		failed += _ok("不可放卡但有演出沒看時，按鈕文字為「推進時段（還有演出沒看）」")
	else:
		failed += _fail("按鈕文字不符: '%s'" % adv_btn.text)

	# (3) 結算演出後：has_unseen_content 為 false
	gs.play_beat("d2_morning_intro")
	var unseen2: bool = gs.has_unseen_content()
	if not unseen2:
		failed += _ok("D2 morning 進入演出後：has_unseen_content() == false")
	else:
		failed += _fail("D2 morning 進入演出後 has_unseen_content 仍為 true")

	main_inst.call("_refresh_advance_hint")
	if adv_btn.text == "推進時段（目前無可做動作）":
		failed += _ok("不可放卡且無未看演出時，按鈕文字為「推進時段（目前無可做動作）」")
	else:
		failed += _fail("按鈕文字不符: '%s'" % adv_btn.text)

	# (4) 可放卡狀態（第 2 天下午）：按鈕文字為「推進時段」
	gs.set("day", 2)
	gs.set("phase", "afternoon")
	var action3: bool = gs.has_any_legal_action()
	main_inst.call("_refresh_advance_hint")
	if action3 and adv_btn.text == "推進時段":
		failed += _ok("可放卡時，按鈕文字為「推進時段」")
	else:
		failed += _fail("可放卡狀態按鈕文字不符: action=%s, text='%s'" % [action3, adv_btn.text])

	main_inst.queue_free()
	await process_frame
	return failed


# ── Group 2: show_location() 進門立刻呈現第一段 ──────────────────────────────
func _test_group2_show_location_immediate_playback(gs: Node, data_node: Node) -> int:
	print("--- Group 2: show_location() immediate playback ---")
	var failed := 0
	_reset_gs(gs)
	gs.set("day", 2)
	gs.set("phase", "morning")

	var loc_scene: PackedScene = load("res://scenes/ui/location_panel.tscn")
	var panel: Node = loc_scene.instantiate()
	get_root().add_child(panel)
	await process_frame

	# 呼叫 show_location("sanquan")，不呼叫任何 advance
	panel.call("show_location", "sanquan")
	await process_frame

	var entered: Dictionary = gs.get("beats_entered") as Dictionary
	if entered.has("d2_morning_intro"):
		failed += _ok("show_location('sanquan') 立即結算並記錄 d2_morning_intro")
	else:
		failed += _fail("show_location('sanquan') 未立即結算 d2_morning_intro")

	var loader: DataLoader = data_node.get("loader") as DataLoader
	var intro_beat: Dictionary = loader.beats_by_id.get("d2_morning_intro", {}) as Dictionary
	var intro_title: String = str(intro_beat.get("title", ""))
	var beat_container: Node = panel.find_child("BeatContainer", true, false)
	var title_found := false
	for child in beat_container.get_children():
		if child is Label:
			var txt: String = (child as Label).text
			if (not intro_title.is_empty() and txt.contains(intro_title)) or (intro_title.is_empty() and not txt.is_empty()):
				title_found = true
				break
	if title_found:
		failed += _ok("show_location('sanquan') 立即渲染了第一段 beat 標題/內容")
	else:
		failed += _fail("show_location('sanquan') 未立即渲染 beat 內容")

	panel.queue_free()
	await process_frame
	return failed


# ── Group 3: 白天地點按鈕四態矩陣 ──────────────────────────────────────────
func _test_group3_daytime_button_enablement_matrix(gs: Node, _data_node: Node) -> int:
	print("--- Group 3: Daytime button enablement 4-way matrix ---")
	var failed := 0
	_reset_gs(gs)

	# 測試場景：D2 morning
	# sanquan: 有 OPEN beat
	# oldschool: 沒 beat
	# temple: 沒 beat
	gs.set("day", 2)
	gs.set("phase", "morning")

	var map_scene: PackedScene = load("res://scenes/ui/map_list.tscn")
	var map_inst: Node = map_scene.instantiate()
	get_root().add_child(map_inst)
	await process_frame

	# 初始：sanquan (有 beat) -> enabled; temple (無 beat, 未去過) -> disabled
	map_inst.call("refresh")
	var container: GridContainer = map_inst.get_node("LocationsContainer")

	var sanquan_btn: Button = null
	var temple_btn: Button = null
	var oldschool_btn: Button = null
	for b: Button in container.get_children():
		var qid := str(b.get_meta("qa_id", ""))
		if qid == "location::sanquan":
			sanquan_btn = b
		elif qid == "location::temple":
			temple_btn = b
		elif qid == "location::oldschool":
			oldschool_btn = b

	# Case 1: 今天有 OPEN beat -> enabled
	if sanquan_btn != null and not sanquan_btn.disabled:
		failed += _ok("Case 1 (今天有 OPEN beat): sanquan 按鈕 enabled")
	else:
		failed += _fail("Case 1: sanquan 按鈕應為 enabled")

	# Case 4: 今天無 beat 且未去過 -> disabled, 但可見且掛 qa_id
	if temple_btn != null and temple_btn.disabled and str(temple_btn.get_meta("qa_id", "")) == "location::temple":
		failed += _ok("Case 4 (今天無 beat 且未去過): temple 按鈕 disabled，且保留 qa_id 與場景樹節點")
	else:
		failed += _fail("Case 4: temple 按鈕應為 disabled")

	# Case 3: 今天無 beat 但去過 (day_locations_visited) -> enabled
	var visited := gs.get("day_locations_visited") as Dictionary
	visited["temple"] = true
	map_inst.call("refresh")
	container = map_inst.get_node("LocationsContainer")
	for b: Button in container.get_children():
		if str(b.get_meta("qa_id", "")) == "location::temple":
			temple_btn = b
			break

	if temple_btn != null and not temple_btn.disabled:
		failed += _ok("Case 3 (今天無 beat 但曾去過): temple 按鈕 enabled")
	else:
		failed += _fail("Case 3: 曾去過的 temple 按鈕應為 enabled")

	# Case 2: 今天有 LOCKED beat (未去過) -> enabled
	_reset_gs(gs)
	gs.set("day", 19)
	gs.set("phase", "afternoon")
	# d19_pm_upstream 在 upstream 有 requires: has_knowledge(k_forty_something)，未持有時為 LOCKED
	map_inst.call("refresh")
	container = map_inst.get_node("LocationsContainer")
	var d19_upstream_btn: Button = null
	for b: Button in container.get_children():
		if str(b.get_meta("qa_id", "")) == "location::upstream":
			d19_upstream_btn = b
			break
	if d19_upstream_btn != null and not d19_upstream_btn.disabled:
		failed += _ok("Case 2 (今天有 LOCKED beat): upstream 按鈕 enabled（鉤子）")
	else:
		failed += _fail("Case 2: 含有 LOCKED beat 的地點應為 enabled")

	# Case 2 -> Case 3 體感延續（B4）：點進只有 LOCKED beat 的地點後，記錄已到訪，後續無 beat 時段維持 enabled
	var loc_scene: PackedScene = load("res://scenes/ui/location_panel.tscn")
	var panel: Node = loc_scene.instantiate()
	get_root().add_child(panel)
	await process_frame

	panel.call("show_location", "upstream")
	await process_frame

	var visited_after_upstream: Dictionary = gs.get("day_locations_visited") as Dictionary
	if visited_after_upstream.has("upstream") and visited_after_upstream["upstream"] == true:
		failed += _ok("B4: 進入只有 LOCKED beat 的地點（upstream）後，成功記錄到訪")
	else:
		failed += _fail("B4: 進入只有 LOCKED beat 的地點未記錄到訪")

	panel.queue_free()
	await process_frame

	# 驗證後續空時段（例如 D20 afternoon，upstream 無 beat）依然為 enabled
	gs.set("day", 20)
	gs.set("phase", "afternoon")
	map_inst.call("refresh")
	container = map_inst.get_node("LocationsContainer")
	var d20_upstream_btn: Button = null
	for b: Button in container.get_children():
		if str(b.get_meta("qa_id", "")) == "location::upstream":
			d20_upstream_btn = b
			break
	if d20_upstream_btn != null and not d20_upstream_btn.disabled:
		failed += _ok("B4: 曾進入過 LOCKED 地點後，後續空時段維持 enabled（不會再度變灰）")
	else:
		failed += _fail("B4: 曾進入過 LOCKED 地點後，後續空時段未維持 enabled")

	map_inst.queue_free()
	await process_frame
	return failed


# ── Group 4: day_locations_visited meta 序列化與形狀驗證 ──────────────────
func _test_group4_day_locations_visited_meta_and_save_validation(gs: Node, _data_node: Node) -> int:
	print("--- Group 4: day_locations_visited meta serialization & validation ---")
	var failed := 0
	_reset_gs(gs)

	# 1. 記錄地點
	gs.play_beat("d2_morning_intro")
	var visited: Dictionary = gs.get("day_locations_visited") as Dictionary
	if visited.has("sanquan") and visited["sanquan"] == true:
		failed += _ok("play_beat('d2_morning_intro') 自動記錄 sanquan 至 day_locations_visited")
	else:
		failed += _fail("play_beat 未記錄 sanquan: %s" % str(visited))

	# 2. _reset_run_state() 不清 meta
	gs.call("_reset_run_state")
	var visited_after_reset: Dictionary = gs.get("day_locations_visited") as Dictionary
	if visited_after_reset.has("sanquan"):
		failed += _ok("_reset_run_state() 保留 meta day_locations_visited")
	else:
		failed += _fail("_reset_run_state() 誤清了 day_locations_visited")

	# 3. serialize() -> deserialize() 往返
	var saved: Dictionary = gs.serialize()
	var meta_saved: Dictionary = saved.get("meta", {}) as Dictionary
	if (meta_saved.get("day_locations_visited", {}) as Dictionary).has("sanquan"):
		failed += _ok("serialize() 包含 meta.day_locations_visited")
	else:
		failed += _fail("serialize() 漏掉 meta.day_locations_visited")

	_reset_gs(gs)
	var load_res: Dictionary = gs.deserialize(saved)
	if bool(load_res.get("ok", false)) and (gs.get("day_locations_visited") as Dictionary).has("sanquan"):
		failed += _ok("deserialize() 正確還原 day_locations_visited")
	else:
		failed += _fail("deserialize() 還原失敗: %s" % str(load_res))

	# 4. 壞形狀拒絕：非 Dictionary
	var bad_saved1: Dictionary = saved.duplicate(true)
	bad_saved1["meta"]["day_locations_visited"] = ["sanquan"]
	var res1: Dictionary = gs.deserialize(bad_saved1)
	if not bool(res1.get("ok", false)) and str(res1.get("reason_code", "")) == "invalid_save_shape":
		failed += _ok("非 Dictionary 的 day_locations_visited 被 invalid_save_shape 拒絕")
	else:
		failed += _fail("非 Dictionary 形狀未被拒絕: %s" % str(res1))

	# 5. 壞形狀拒絕：值不是 true
	var bad_saved2: Dictionary = saved.duplicate(true)
	bad_saved2["meta"]["day_locations_visited"] = { "sanquan": false }
	var res2: Dictionary = gs.deserialize(bad_saved2)
	if not bool(res2.get("ok", false)) and str(res2.get("reason_code", "")) == "invalid_save_shape":
		failed += _ok("值非 true 的 day_locations_visited 被 invalid_save_shape 拒絕")
	else:
		failed += _fail("值非 true 未被拒絕: %s" % str(res2))

	# 6. 壞形狀拒絕：未知 location id
	var bad_saved3: Dictionary = saved.duplicate(true)
	bad_saved3["meta"]["day_locations_visited"] = { "fake_location_999": true }
	var res3: Dictionary = gs.deserialize(bad_saved3)
	if not bool(res3.get("ok", false)) and str(res3.get("reason_code", "")) == "invalid_save_shape":
		failed += _ok("未知 location id 的 day_locations_visited 被 invalid_save_shape 拒絕")
	else:
		failed += _fail("未知 location id 未被拒絕: %s" % str(res3))

	# 7. 壞形狀拒絕：非白天地點（夜間地點 id）（B1）
	var bad_saved4: Dictionary = saved.duplicate(true)
	bad_saved4["meta"]["day_locations_visited"] = { "n_corridor": true }
	var res4: Dictionary = gs.deserialize(bad_saved4)
	if not bool(res4.get("ok", false)) and str(res4.get("reason_code", "")) == "invalid_save_shape":
		failed += _ok("B1: 包含夜間地點 id 的 day_locations_visited 被 invalid_save_shape 拒絕")
	else:
		failed += _fail("B1: 包含夜間地點 id 未被拒絕: %s" % str(res4))

	# 8. 驗證 play_beat 播放夜間 beat 不會將夜間地點寫入 day_locations_visited（B1）
	gs.play_beat("n_corridor_ch1")
	var visited_after_night: Dictionary = gs.get("day_locations_visited") as Dictionary
	if not visited_after_night.has("n_corridor"):
		failed += _ok("B1: play_beat('n_corridor_ch1') 不會將夜間地點寫入 day_locations_visited")
	else:
		failed += _fail("B1: play_beat 誤將夜間地點寫入 day_locations_visited: %s" % str(visited_after_night))

	return failed


# ── Group 5: 第 1 天 auto_enter 自動解鎖 busstop ────────────────────────────
func _test_group5_d1_auto_enter_records_busstop(gs: Node, _data_node: Node) -> int:
	print("--- Group 5: D1 auto_enter records busstop in day_locations_visited ---")
	var failed := 0
	_reset_gs(gs)
	gs.set("flow_mode", gs.FLOW_OPENING)

	# 模擬開局選擇（D1 morning auto_enter 會播放 d1_morning_phone / d1_morning_departure）
	var choose_res: Dictionary = gs.choose_opening("take_family_album")
	if not bool(choose_res.get("ok", false)):
		return _fail("choose_opening 失敗: %s" % str(choose_res))

	var visited: Dictionary = gs.get("day_locations_visited") as Dictionary
	if visited.has("busstop") and visited["busstop"] == true:
		failed += _ok("D1 開局 auto_enter 演出後，busstop 成功被記錄至 day_locations_visited")
	else:
		failed += _fail("D1 開局後 busstop 未在 day_locations_visited 內: %s" % str(visited))

	return failed


# ── Group 6: 白天地點 desc 完整度與缺欄位 fallback ──────────────────────────
func _test_group6_day_locations_desc_and_fallback(gs: Node, data_node: Node) -> int:
	print("--- Group 6: Day locations desc completeness & fallback ---")
	var failed := 0
	_reset_gs(gs)

	var loader: DataLoader = data_node.get("loader") as DataLoader
	var missing_desc: Array[String] = []
	for lid: String in DAY_LOCATIONS_20:
		var loc: Dictionary = loader.locations.get(lid, {}) as Dictionary
		var desc: String = str(loc.get("desc", "")).strip_edges()
		if desc.is_empty():
			missing_desc.append(lid)

	if missing_desc.is_empty():
		failed += _ok("20 個白天地點全部具有非空 desc")
	else:
		failed += _fail("以下白天地點缺少 desc: %s" % str(missing_desc))

	# 驗證 build_panel 回傳的 location 包含 desc
	var panel_view: Dictionary = gs.build_panel("sanquan")
	var sanquan_desc := str((panel_view.get("location", {}) as Dictionary).get("desc", ""))
	if not sanquan_desc.is_empty():
		failed += _ok("build_panel('sanquan') 回傳之 view.location 包含非空 desc")
	else:
		failed += _fail("build_panel 回傳的 desc 為空")

	var loc_scene: PackedScene = load("res://scenes/ui/location_panel.tscn")
	var panel: Node = loc_scene.instantiate()
	get_root().add_child(panel)
	await process_frame

	# 1. 正常常態地點（有 desc，動態比對名稱與描述，不硬寫字面，解決 B5）
	gs.set("day", 2)
	gs.set("phase", "morning")
	var oldschool_loc: Dictionary = loader.locations.get("oldschool", {}) as Dictionary
	var expected_name: String = str(oldschool_loc.get("name", "oldschool"))
	var expected_desc: String = str(oldschool_loc.get("desc", ""))
	panel.call("show_location", "oldschool")
	await process_frame

	var title_lbl: Label = panel.get_node("LocationTitle")
	var desc_lbl: Label = panel.get_node("DescriptionLabel")
	if title_lbl.text == expected_name and desc_lbl.visible and desc_lbl.text == expected_desc:
		failed += _ok("無事件地點正確顯示動態標題與 desc 常駐簡介")
	else:
		failed += _fail("無事件地點渲染不符: title='%s', desc_visible=%s" % [title_lbl.text, desc_lbl.visible])

	# 2. 缺欄位退路測試（B2：模擬某個地點無 desc 或 desc 為空時，退回只顯示 name，DescriptionLabel 隱藏且不崩潰）
	var mock_loc_id := "mock_no_desc_location"
	loader.locations[mock_loc_id] = {
		"id": mock_loc_id,
		"name": "無簡介測試地點",
		"layer": "day",
		"phases": ["morning", "afternoon"],
		"chapter": 1
	}
	panel.call("show_location", mock_loc_id)
	await process_frame

	var mock_title_lbl: Label = panel.get_node("LocationTitle")
	var mock_desc_lbl: Label = panel.get_node("DescriptionLabel")
	if mock_title_lbl.text == "無簡介測試地點" and not mock_desc_lbl.visible and mock_desc_lbl.text.is_empty():
		failed += _ok("B2: 地點缺少 desc 欄位時，退回只顯示標題且 DescriptionLabel 隱藏不崩潰")
	else:
		failed += _fail("B2: 缺少 desc 地點渲染不符: title='%s', desc_visible=%s, desc_text='%s'" % [mock_title_lbl.text, mock_desc_lbl.visible, mock_desc_lbl.text])

	loader.locations.erase(mock_loc_id)
	panel.queue_free()
	await process_frame
	return failed


# ── Group 7: 新文案套語密度檢查 ─────────────────────────────────────────────
func _test_group7_stock_phrase_density(data_node: Node) -> int:
	print("--- Group 7: Stock phrase density on new day location desc ---")
	var failed := 0
	var loader: DataLoader = data_node.get("loader") as DataLoader

	var total_chars := 0
	var total_stock_hits := 0

	for lid: String in DAY_LOCATIONS_20:
		var loc: Dictionary = loader.locations.get(lid, {}) as Dictionary
		var desc: String = str(loc.get("desc", ""))
		total_chars += desc.length()
		for phrase: String in STOCK_PHRASES:
			var count := desc.count(phrase)
			if count > 0:
				total_stock_hits += count
				printerr("  [WARN] 地點 %s 的 desc 命中套語「%s」" % [lid, phrase])

	var density := (float(total_stock_hits) / float(total_chars)) * 1000.0 if total_chars > 0 else 0.0
	print("  總字數: %d, 套語命中: %d, 密度: %.2f / 千字" % [total_chars, total_stock_hits, density])

	if density <= 1.5:
		failed += _ok("20 個白天地點 desc 套語密度符合標準 (%.2f <= 1.5 / 千字)" % density)
	else:
		failed += _fail("套語密度超標: %.2f > 1.5 / 千字" % density)

	return failed
