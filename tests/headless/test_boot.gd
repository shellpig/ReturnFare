extends SceneTree

## Boot 測試：正式啟動路徑走不走得通。
## 跑法：
##   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/test_boot.gd
## 全綠 exit 0；任一失敗 exit 1。
##
## **本檔刻意不呼叫 Engine.register_singleton()。** 其他測試都自己組裝 GameState 與 Data
## 再註冊成 Engine singleton，走的是注入路徑；正式遊戲走的是 project.godot 的 autoload 路徑。
## 兩條路組裝方式不同，而只有前者被驗過——2026-08-13 就因此漏掉一個「遊戲開不起來」的 bug
## （data.gd 用 Engine.get_singleton 找 autoload，永遠拿到 null，Data.ok 恆為 false）。
## 這一檔補的就是那個盲區：autoload 起得來嗎、main.tscn 進得到正常分支嗎。
##
## 加測試時請注意：**任何在這裡手動註冊 singleton 的行為都會讓本檔失去意義。**


func _initialize() -> void:
	await process_frame

	var failed := 0
	failed += _test_autoloads_present()
	failed += _test_data_ok()
	failed += await _test_main_scene_enters_normal_branch()

	if failed > 0:
		push_error("boot: %d test(s) failed" % failed)
		quit(1)
	else:
		print("boot: all tests passed")
		quit(0)


func _ok(msg: String) -> int:
	print("  ok  " + msg)
	return 0


func _fail(msg: String) -> int:
	push_error("  FAIL  " + msg)
	return 1


# ── autoload 真的掛在 /root 底下 ────────────────────────────────────────────

func _test_autoloads_present() -> int:
	print("--- autoloads ---")
	var failed := 0

	for name in ["GameState", "Data"]:
		if get_root().get_node_or_null(NodePath(name)) == null:
			failed += _fail("/root/%s 不存在（project.godot 的 autoload 沒掛上）" % name)
		else:
			failed += _ok("/root/%s 存在" % name)

	# autoload 不是 Engine singleton——這是 data.gd 當初踩到的前提，釘住它。
	if Engine.has_singleton("GameState"):
		failed += _fail("Engine.has_singleton(GameState) 為真：前提變了，_find_game_state() 要重看")
	else:
		failed += _ok("autoload 不是 Engine singleton（前提成立）")

	return failed


# ── Data.ok：正式啟動路徑的總開關 ──────────────────────────────────────────

func _test_data_ok() -> int:
	print("--- Data.ok ---")
	var failed := 0

	var data_node: Node = get_root().get_node_or_null("Data")
	if data_node == null:
		return _fail("/root/Data 不存在，後續全部略過")

	if not data_node.get("ok"):
		failed += _fail("Data.ok 為 false：正式啟動路徑走不通，遊戲會停在錯誤畫面")
	else:
		failed += _ok("Data.ok 為 true")

	return failed


# ── main.tscn 走到正常分支，不是錯誤分支 ───────────────────────────────────

func _test_main_scene_enters_normal_branch() -> int:
	print("--- main.tscn ---")
	var failed := 0

	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		return _fail("main.tscn 載不進來")

	var main: Node = scene.instantiate()
	get_root().add_child(main)
	await process_frame

	# main.gd 的錯誤分支會寫 ErrorLabel 並把 StatusLabel／AdvanceButton 藏起來，
	# 而且在接任何 signal 之前就 return。用這三件事分辨走了哪一條。
	var error_label: Label = main.get_node_or_null("ErrorLabel")
	var status_label: Label = main.get_node_or_null("StatusLabel")
	var advance_btn: Button = main.get_node_or_null("AdvanceButton")

	if error_label == null or status_label == null or advance_btn == null:
		failed += _fail("main.tscn 少了 ErrorLabel／StatusLabel／AdvanceButton 其中之一")
		main.queue_free()
		return failed

	if not error_label.text.is_empty():
		failed += _fail("ErrorLabel 有字，走的是錯誤分支：" + error_label.text)
	else:
		failed += _ok("ErrorLabel 是空的")

	if not status_label.visible:
		failed += _fail("StatusLabel 被藏起來，走的是錯誤分支")
	else:
		failed += _ok("StatusLabel 可見")

	if not advance_btn.visible:
		failed += _fail("AdvanceButton 被藏起來，走的是錯誤分支")
	else:
		failed += _ok("AdvanceButton 可見")

	# _refresh_status() 只在正常分支跑。不能只驗「有字」——main.tscn 本身帶佔位字，
	# 壞掉時那條斷言照樣過。驗開場狀態的實際內容才分得出來。
	if not status_label.text.begins_with("第 1 天"):
		failed += _fail("StatusLabel 不是開場狀態，_refresh_status() 沒跑到：「%s」" % status_label.text)
	else:
		failed += _ok("StatusLabel 是 _refresh_status() 寫的：「%s」" % status_label.text)

	# 驗證 FlowText 節點在 main.tscn 存在 (K-28)
	var flow_text: FlowText = main.get_node_or_null("ContentView/FlowText")
	if flow_text == null:
		failed += _fail("ContentView/FlowText 不存在")
	else:
		failed += _ok("ContentView/FlowText 存在")

	# 驗證 Day 1 night fixed 演出 (n_corridor_ch1) 在 FlowText 顯示
	var gs: Node = get_root().get_node("GameState")
	gs.set("day", 1)
	gs.set("phase", "night")
	main.call("_route_view")
	if not flow_text.visible or flow_text.get_lines().is_empty():
		failed += _fail("Day 1 night fixed 文字未能寫入 FlowText")
	else:
		failed += _ok("Day 1 night fixed (n_corridor_ch1) 成功渲染進 FlowText")

	# 驗證 Day 24 night fixed 演出 (d24_night_laozeng) 在 FlowText 顯示
	gs.set("day", 24)
	gs.set("phase", "night")
	main.call("_route_view")
	if not flow_text.visible or flow_text.get_lines().is_empty():
		failed += _fail("Day 24 night fixed 文字未能寫入 FlowText")
	else:
		failed += _ok("Day 24 night fixed (d24_night_laozeng) 成功渲染進 FlowText")

	# 驗證夜間開啟地點面板時 FlowText 被隱藏，關閉面板後恢復顯示
	var map_list: Node = main.get_node_or_null("ContentView/MapList")
	var loc_panel: Node = main.get_node_or_null("ContentView/LocationPanel")
	gs.set("day", 1)
	gs.set("phase", "night")
	main.call("_route_view")
	if not flow_text.visible:
		failed += _fail("Day 1 night route_view FlowText 未顯示")
	main.call("_on_location_selected", "n_corridor_1")
	if flow_text.visible:
		failed += _fail("開啟地點面板時 FlowText 未被隱藏（疊字 bug）")
	elif not loc_panel.visible:
		failed += _fail("開啟地點面板時 LocationPanel 未顯示")
	else:
		failed += _ok("開啟地點面板時 FlowText 正確隱藏、LocationPanel 顯示")

	main.call("_on_panel_closed")
	if not flow_text.visible or not map_list.visible:
		failed += _fail("關閉地點面板後 FlowText 或 MapList 未恢復顯示")
	elif loc_panel.visible:
		failed += _fail("關閉地點面板後 LocationPanel 未隱藏")
	else:
		failed += _ok("關閉地點面板後 FlowText 與 MapList 正確恢復顯示且無重疊")

	# 驗證 K-40: FlowText 為 ScrollContainer 具備 clip_contents，且夜間不蓋住 MapList。
	# **比的是實際矩形，不是 offset。** 只比 offset 會漏掉錨點落差——FlowText 曾經帶
	# anchors_preset = 15（anchor_bottom = 1.0），offset_bottom = 120 的實際意思是
	# 「父節點底邊再往下 120」，兩個數字比得過，但整張地圖被蓋住、地點按鈕全部點不到。
	gs.set("day", 1)
	gs.set("phase", "night")
	main.call("_route_view")
	await process_frame
	if not (flow_text is ScrollContainer):
		failed += _fail("FlowText 根節點不是 ScrollContainer (K-40)")
	elif not flow_text.clip_contents:
		failed += _fail("FlowText 未開啟 clip_contents (K-40)")
	else:
		var flow_rect: Rect2 = flow_text.get_global_rect()
		var map_rect: Rect2 = (map_list as Control).get_global_rect()
		if flow_rect.intersects(map_rect):
			failed += _fail("FlowText 實際矩形 %s 與 MapList %s 重疊，會蓋掉地點按鈕 (K-40)"
				% [str(flow_rect), str(map_rect)])
		else:
			failed += _ok("FlowText 是 ScrollContainer、開啟 clip_contents，實際矩形與 MapList 不重疊 (K-40)")

	# 驗證 [出席] 行印的是槽上 authored 的 label，沒有把 occupant 的卡 id 漏到畫面上。
	# occupant 是**卡 id**（`npc_ajie`），122 個 occupant 槽只有 4 個查得到卡片，
	# 任何「拿 occupant 去查名字」的寫法都會在其餘 18 個身上退回印出原始 id。
	gs.set("day", 2)
	gs.set("phase", "morning")
	main.call("_on_location_selected", "sanquan")
	await process_frame
	# P1-G：先把演出佇列逐一播放完，常態階段才建立 occupant 槽。
	var beat_advance_btn: Button = loc_panel.get_node("AdvanceBeatButton")
	while beat_advance_btn.visible:
		loc_panel.call("_on_advance_beat_pressed")
		await process_frame
	var occupant_lines := PackedStringArray()
	var beat_container: Node = loc_panel.find_child("BeatContainer", true, false)
	for child in beat_container.get_children():
		var lbl := child as Label
		if lbl != null and lbl.text.contains("[出席]"):
			occupant_lines.append(lbl.text)
	if occupant_lines.is_empty():
		failed += _fail("第 2 天上午山泉閣面板沒有任何 [出席] 行，斷言前提不成立")
	else:
		var leaked := PackedStringArray()
		for line in occupant_lines:
			if line.contains("npc_"):
				leaked.append(line)
		if not leaked.is_empty():
			failed += _fail("[出席] 把原始卡 id 漏到畫面上：%s" % ", ".join(leaked))
		else:
			failed += _ok("[出席] 印的是 label，沒有漏卡 id（%d 行）：%s"
				% [occupant_lines.size(), ", ".join(occupant_lines)])
	main.call("_on_panel_closed")

	# 驗證 run_ended 結局 stub 在 FlowText 顯示且保持可見
	main.call("_on_run_ended", "ending_default")
	if not flow_text.visible or not flow_text.get_text().contains("[結局 stub]"):
		failed += _fail("結局 stub 未能寫入 FlowText")
	else:
		failed += _ok("結局 stub 成功寫入 FlowText 且保持可見")

	main.queue_free()
	return failed
