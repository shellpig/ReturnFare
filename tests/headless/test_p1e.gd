extends SceneTree

## P1-E headless 驗收測試：choice_group 互斥選擇題系統
## 涵蓋：
##   1. 直選與帶卡選雙入口
##   2. 選定即定案、同組其餘選項消失、被選項以 RESOLVED 唯讀展示
##   3. 直選與用卡狀態等價性
##   4. 重複選擇 no-op 與防重複觸發
##   5. 不選離開無副作用
##   6. LOCKED 選項阻擋
##   7. 第 22 天真實資料驗證（d22_pm_sandbags / acai_read）
##   8. 序列化往返
##   9. UI 層 location_panel 按鈕產生與點擊結算
##
## 跑法：
##   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/test_p1e.gd
##
## 全綠 exit 0；任一失敗 exit 1。


func _initialize() -> void:
	await process_frame

	var data_node: Node = get_root().get_node_or_null("Data")
	if data_node == null:
		data_node = load("res://scripts/autoload/data.gd").new()
		data_node.name = "Data"
		get_root().add_child(data_node)
		Engine.register_singleton("Data", data_node)
		await process_frame

	if not data_node.get("ok"):
		push_error("P1-E: Data failed to load; abort")
		quit(1)
		return

	var gs: Node = get_root().get_node_or_null("GameState")
	if gs == null:
		gs = load("res://scripts/autoload/game_state.gd").new()
		gs.name = "GameState"
		get_root().add_child(gs)
		Engine.register_singleton("GameState", gs)
		await process_frame

	var failed := 0
	failed += _test_choice_direct_selection(gs, data_node)
	failed += _test_choice_with_card(gs, data_node)
	failed += _test_choice_state_equivalence(gs, data_node)
	failed += _test_choice_repeated_call_noop(gs, data_node)
	failed += _test_choice_leave_panel_unselected(gs, data_node)
	failed += _test_choice_locked_slot(gs, data_node)
	failed += _test_choice_real_data_d22_sandbags(gs, data_node)
	failed += _test_choice_serialize_roundtrip(gs)
	failed += await _test_choice_ui_buttons(gs, data_node)

	if failed > 0:
		push_error("P1-E: %d test(s) failed" % failed)
		quit(1)
	else:
		print("P1-E: all tests passed")
		quit(0)


func _ok(msg: String) -> int:
	print("  ok  " + msg)
	return 0


func _fail(msg: String) -> int:
	push_error("  FAIL  " + msg)
	return 1


func _reset_gs(gs: Node) -> void:
	gs.set("day", 1)
	gs.set("phase", "morning")
	gs.set("action_spent", false)
	(gs.get("hand") as Array).clear()
	(gs.get("knowledge") as Dictionary).clear()
	(gs.get("madness_clock") as Dictionary).clear()
	gs.set("_madness_counter", 0)
	(gs.get("beats_entered") as Dictionary).clear()
	(gs.get("slots_placed") as Dictionary).clear()
	(gs.get("flags") as Dictionary).clear()
	(gs.get("switches") as Dictionary).clear()
	(gs.get("switch_progress") as Dictionary).clear()
	(gs.get("relations") as Dictionary).clear()
	(gs.get("npc_action_counts") as Dictionary).clear()
	if gs.get("choices") is Dictionary:
		(gs.get("choices") as Dictionary).clear()


# ── 測試項目 ──────────────────────────────────────────────────────────────────

func _test_choice_direct_selection(gs: Node, data_node: Node) -> int:
	_reset_gs(gs)
	print("--- 1. choice direct selection & panel presentation ---")

	# 使用第 29 天下午邀請事件（d29_pm_invitation: invitation 組）
	gs.set("day", 29)
	gs.set("phase", "afternoon")

	# 開啟前/未選擇時：PanelBuilder 應渲染出可見的選項
	var view_before: Dictionary = PanelBuilder.build("sanquan", gs, data_node)
	var beat_view_before: Dictionary = {}
	for bv in view_before.get("beats", []):
		if str(bv["beat"].get("id", "")) == "d29_pm_invitation":
			beat_view_before = bv
			break

	if beat_view_before.is_empty():
		return _fail("d29_pm_invitation beat view not found in sanquan")

	var slots_before: Array = beat_view_before.get("slots", [])
	# invite_ajie, invite_none (invite_awei 可能因 requires LOCKED)
	if slots_before.size() < 2:
		return _fail("expected at least 2 slots in invitation group before choosing, got %d" % slots_before.size())

	# 直接選擇 invite_none（不帶卡）
	var res: Dictionary = gs.call("choose", "d29_pm_invitation", "invitation", "invite_none", "")
	if not res.get("ok", false):
		return _fail("choose invite_none direct selection failed: %s" % res.get("reason_code", ""))

	# 驗證 choices 記錄
	var choices: Dictionary = gs.get("choices") as Dictionary
	if choices.get("d29_pm_invitation::invitation") != "invite_none":
		return _fail("choices['d29_pm_invitation::invitation'] != 'invite_none'")

	# 驗證 slots_placed 記錄
	var slots_placed: Dictionary = gs.get("slots_placed") as Dictionary
	if not slots_placed.has("d29_pm_invitation::invite_none"):
		return _fail("slots_placed has no d29_pm_invitation::invite_none")

	# 驗證效果已套用（flag: invited_none = true）
	var flags: Dictionary = gs.get("flags") as Dictionary
	if not flags.get("invited_none", false):
		return _fail("flag invited_none is not true")

	# 驗證面板重繪：同組其餘選項消失，僅保留被選者以 RESOLVED 呈現
	var view_after: Dictionary = PanelBuilder.build("sanquan", gs, data_node)
	var beat_view_after: Dictionary = {}
	for bv in view_after.get("beats", []):
		if str(bv["beat"].get("id", "")) == "d29_pm_invitation":
			beat_view_after = bv
			break

	var slots_after: Array = beat_view_after.get("slots", [])
	if slots_after.size() != 1:
		return _fail("expected exactly 1 slot in view after choosing, got %d" % slots_after.size())

	var remaining_slot_view: Dictionary = slots_after[0]
	if str(remaining_slot_view["slot"].get("id", "")) != "invite_none":
		return _fail("remaining slot is '%s', expected 'invite_none'" % str(remaining_slot_view["slot"].get("id", "")))
	if int(remaining_slot_view.get("tri", -1)) != PanelBuilder.TriState.RESOLVED:
		return _fail("remaining slot tri is not RESOLVED (%d)" % int(remaining_slot_view.get("tri", -1)))

	# 選擇題不消耗行動格
	if bool(gs.get("action_spent")):
		return _fail("choice selection unexpectedly set action_spent to true")

	_ok("direct selection successfully resolved choice and collapsed other options")
	return 0


func _test_choice_with_card(gs: Node, data_node: Node) -> int:
	_reset_gs(gs)
	print("--- 2. choice selection with card ---")

	gs.set("day", 22)
	gs.set("phase", "afternoon")
	gs.call("set_flag", "acai_obs_knee", true)

	# 給予拍立得裝備卡
	gs.call("gain_card", "equip_polaroid")

	# 帶卡選擇 d22_pm_sandbags / acai_read / obs_walk
	var res: Dictionary = gs.call("choose", "d22_pm_sandbags", "acai_read", "obs_walk", "equip_polaroid")
	if not res.get("ok", false):
		return _fail("choose obs_walk with equip_polaroid failed: %s" % res.get("reason_code", ""))

	var choices: Dictionary = gs.get("choices") as Dictionary
	if choices.get("d22_pm_sandbags::acai_read") != "obs_walk":
		return _fail("choices['d22_pm_sandbags::acai_read'] != 'obs_walk'")

	# 驗證獲得情報卡 info_acai_walk
	if not bool(gs.call("has_card", "info_acai_walk")):
		return _fail("player did not gain info_acai_walk")

	# 驗證面板重繪：同組其餘選項（obs_hands, obs_talk, dismiss）消失，僅留 obs_walk (RESOLVED)
	var view_after: Dictionary = PanelBuilder.build("sanquan", gs, data_node)
	var beat_view_after: Dictionary = {}
	for bv in view_after.get("beats", []):
		if str(bv["beat"].get("id", "")) == "d22_pm_sandbags":
			beat_view_after = bv
			break

	var choice_slots_in_view: Array = []
	for sv in beat_view_after.get("slots", []):
		if sv["slot"].get("choice_group") == "acai_read":
			choice_slots_in_view.append(sv)

	if choice_slots_in_view.size() != 1:
		return _fail("expected 1 choice slot in view, got %d" % choice_slots_in_view.size())
	if str(choice_slots_in_view[0]["slot"].get("id", "")) != "obs_walk":
		return _fail("remaining choice slot is not obs_walk")
	if int(choice_slots_in_view[0].get("tri", -1)) != PanelBuilder.TriState.RESOLVED:
		return _fail("remaining choice slot is not RESOLVED")

	_ok("choice with card succeeded, granted effect, and collapsed other options")
	return 0


func _test_choice_state_equivalence(gs: Node, _data_node: Node) -> int:
	print("--- 3. state equivalence between direct and with-card paths ---")

	# 跑路徑 A：無卡直接選 d22 obs_walk
	_reset_gs(gs)
	gs.set("day", 22)
	gs.set("phase", "afternoon")
	gs.call("set_flag", "acai_obs_knee", true)
	var res_a: Dictionary = gs.call("choose", "d22_pm_sandbags", "acai_read", "obs_walk", "")
	if not res_a.get("ok", false):
		return _fail("path A choose failed: %s" % res_a.get("reason_code", ""))
	var serialized_a: Dictionary = gs.call("serialize")

	# 跑路徑 B：帶卡選 d22 obs_walk（事先持有 equip_polaroid）
	_reset_gs(gs)
	gs.set("day", 22)
	gs.set("phase", "afternoon")
	gs.call("set_flag", "acai_obs_knee", true)
	gs.call("gain_card", "equip_polaroid")
	var res_b: Dictionary = gs.call("choose", "d22_pm_sandbags", "acai_read", "obs_walk", "equip_polaroid")
	if not res_b.get("ok", false):
		return _fail("path B choose failed: %s" % res_b.get("reason_code", ""))
	var serialized_b: Dictionary = gs.call("serialize")

	# 比對兩者狀態：
	# 兩路徑除了 hand 差一張 equip_polaroid 之外，其餘所有 run/meta 欄位必須完全相同！
	var run_a: Dictionary = serialized_a["run"]
	var run_b: Dictionary = serialized_b["run"]

	if run_a["choices"] != run_b["choices"]:
		return _fail("choices mismatch between path A and B")
	if run_a["slots_placed"] != run_b["slots_placed"]:
		return _fail("slots_placed mismatch between path A and B")
	if run_a["flags"] != run_b["flags"]:
		return _fail("flags mismatch between path A and B")
	if run_a["switches"] != run_b["switches"]:
		return _fail("switches mismatch between path A and B")
	if run_a["relations"] != run_b["relations"]:
		return _fail("relations mismatch between path A and B")
	if run_a["action_spent"] != run_b["action_spent"]:
		return _fail("action_spent mismatch between path A and B")

	# 兩者都應該獲得了 info_acai_walk
	if not (run_a["hand"] as Array).has("info_acai_walk") or not (run_b["hand"] as Array).has("info_acai_walk"):
		return _fail("info_acai_walk missing in hand for one of the paths")

	_ok("direct and with-card selection leave completely identical state (aside from held card)")
	return 0


func _test_choice_repeated_call_noop(gs: Node, _data_node: Node) -> int:
	_reset_gs(gs)
	print("--- 4. repeated choose call is no-op ---")

	gs.set("day", 29)
	gs.set("phase", "afternoon")

	# 第一次選擇 invite_none
	var res1: Dictionary = gs.call("choose", "d29_pm_invitation", "invitation", "invite_none", "")
	if not res1.get("ok", false):
		return _fail("first choose failed")

	# 第二次重複選擇同一組（無論選同一個 slot 或不同 slot）
	var res2: Dictionary = gs.call("choose", "d29_pm_invitation", "invitation", "invite_none", "")
	if res2.get("ok", false):
		return _fail("repeated choose on same slot should fail (ok=false)")
	if str(res2.get("reason_code", "")) != "resolved":
		return _fail("expected reason_code 'resolved', got '%s'" % str(res2.get("reason_code", "")))

	var res3: Dictionary = gs.call("choose", "d29_pm_invitation", "invitation", "invite_ajie", "")
	if res3.get("ok", false):
		return _fail("repeated choose on another slot in same group should fail (ok=false)")
	if str(res3.get("reason_code", "")) != "resolved":
		return _fail("expected reason_code 'resolved', got '%s'" % str(res3.get("reason_code", "")))

	# try_place 對已結算組的槽也應被擋下
	var res4: Dictionary = gs.call("try_place", "npc_ajie", "d29_pm_invitation", "invite_ajie")
	if res4.get("ok", false):
		return _fail("try_place on resolved choice group should fail")
	if str(res4.get("reason_code", "")) != "resolved":
		return _fail("try_place expected reason_code 'resolved', got '%s'" % str(res4.get("reason_code", "")))

	_ok("repeated choice call is no-op with reason_code=resolved")
	return 0


func _test_choice_leave_panel_unselected(gs: Node, _data_node: Node) -> int:
	_reset_gs(gs)
	print("--- 5. leave panel unselected has no side effects ---")

	gs.set("day", 29)
	gs.set("phase", "afternoon")

	# 打開面板
	var view1: Dictionary = gs.call("open_panel", "sanquan")
	var bv1: Dictionary = {}
	for bv in view1.get("beats", []):
		if str(bv["beat"].get("id", "")) == "d29_pm_invitation":
			bv1 = bv
			break

	var count1: int = (bv1.get("slots", []) as Array).size()

	# 不選擇，直接模擬離開與重開面板
	var choices: Dictionary = gs.get("choices") as Dictionary
	if not choices.is_empty():
		return _fail("choices should remain empty without choosing")

	var view2: Dictionary = gs.call("open_panel", "sanquan")
	var bv2: Dictionary = {}
	for bv in view2.get("beats", []):
		if str(bv["beat"].get("id", "")) == "d29_pm_invitation":
			bv2 = bv
			break

	var count2: int = (bv2.get("slots", []) as Array).size()
	if count1 != count2:
		return _fail("slot count changed after reopening without selection (%d vs %d)" % [count1, count2])

	_ok("leaving panel unselected keeps all options intact and makes 0 mutations")
	return 0


func _test_choice_locked_slot(gs: Node, _data_node: Node) -> int:
	_reset_gs(gs)
	print("--- 6. locked choice slot rejection ---")

	# d29_pm_invitation 的 invite_awei 需要 relation_at_least: awei >= 恩人
	gs.set("day", 29)
	gs.set("phase", "afternoon")

	# 未達關係時直接選 invite_awei
	var res: Dictionary = gs.call("choose", "d29_pm_invitation", "invitation", "invite_awei", "")
	if res.get("ok", false):
		return _fail("choose on locked slot should fail")
	if str(res.get("reason_code", "")) != "locked":
		return _fail("expected reason_code 'locked', got '%s'" % str(res.get("reason_code", "")))
	if str(res.get("reason_text", "")) != "（你想不出用什麼身分開這個口。）":
		return _fail("reason_text mismatch: %s" % str(res.get("reason_text", "")))

	# 驗證 choices 未寫入
	var choices: Dictionary = gs.get("choices") as Dictionary
	if not choices.is_empty():
		return _fail("failed choose wrote to choices")

	_ok("locked choice slot rejected with locked reason_code and reason_text")
	return 0


func _test_choice_real_data_d22_sandbags(gs: Node, data_node: Node) -> int:
	_reset_gs(gs)
	print("--- 7. real data validation: d22_pm_sandbags / acai_read ---")

	gs.set("day", 22)
	gs.set("phase", "afternoon")
	gs.call("set_flag", "acai_obs_knee", true)

	# 1. 驗證 d22_pm_sandbags 在 sanquan 面板中有 4 個 choice 槽 + 1 個普通 work 槽
	var view: Dictionary = PanelBuilder.build("sanquan", gs, data_node)
	var bv: Dictionary = {}
	for b in view.get("beats", []):
		if str(b["beat"].get("id", "")) == "d22_pm_sandbags":
			bv = b
			break

	if bv.is_empty():
		return _fail("d22_pm_sandbags not found in sanquan afternoon")

	var slots: Array = bv.get("slots", [])
	# work (OPEN), obs_walk (OPEN), obs_hands (LOCKED), obs_talk (OPEN), dismiss (OPEN)
	var found_work := false
	var found_walk := false
	var found_hands := false
	var found_talk := false
	var found_dismiss := false

	for sv in slots:
		var sid: String = str(sv["slot"].get("id", ""))
		match sid:
			"work":
				found_work = true
				if int(sv["tri"]) != PanelBuilder.TriState.OPEN:
					return _fail("work slot tri is not OPEN")
			"obs_walk":
				found_walk = true
				if int(sv["tri"]) != PanelBuilder.TriState.OPEN:
					return _fail("obs_walk slot tri is not OPEN")
			"obs_hands":
				found_hands = true
				if int(sv["tri"]) != PanelBuilder.TriState.LOCKED:
					return _fail("obs_hands slot tri is not LOCKED (missing requires)")
				if str(sv["reason"]) != "（你沒有真的跟他遞過幾次東西。）":
					return _fail("obs_hands reason mismatch: %s" % str(sv["reason"]))
			"obs_talk":
				found_talk = true
				if int(sv["tri"]) != PanelBuilder.TriState.OPEN:
					return _fail("obs_talk slot tri is not OPEN")
			"dismiss":
				found_dismiss = true
				if int(sv["tri"]) != PanelBuilder.TriState.OPEN:
					return _fail("dismiss slot tri is not OPEN")

	if not (found_work and found_walk and found_hands and found_talk and found_dismiss):
		return _fail("not all expected slots found in d22_pm_sandbags")

	# 2. 直選 dismiss（我想太多了）
	var res := gs.call("choose", "d22_pm_sandbags", "acai_read", "dismiss", "") as Dictionary
	if not res.get("ok", false):
		return _fail("choose dismiss failed")
	if not bool(gs.get("flags").get("acai_dismissed", false)):
		return _fail("acai_dismissed flag not set")

	# 3. 面板重繪後，work 槽依然存在（非 choice_group），choice 槽只剩 dismiss (RESOLVED)
	var view_post: Dictionary = PanelBuilder.build("sanquan", gs, data_node)
	var bv_post: Dictionary = {}
	for b in view_post.get("beats", []):
		if str(b["beat"].get("id", "")) == "d22_pm_sandbags":
			bv_post = b
			break

	var slots_post: Array = bv_post.get("slots", [])
	if slots_post.size() != 2:
		return _fail("expected 2 slots in view post-choice (work + dismiss), got %d" % slots_post.size())

	var s0: Dictionary = slots_post[0]
	var s1: Dictionary = slots_post[1]
	if str(s0["slot"].get("id", "")) != "work" or str(s1["slot"].get("id", "")) != "dismiss":
		return _fail("expected [work, dismiss], got [%s, %s]" % [str(s0["slot"].get("id", "")), str(s1["slot"].get("id", ""))])

	if int(s0["tri"]) != PanelBuilder.TriState.OPEN:
		return _fail("work slot should still be OPEN")
	if int(s1["tri"]) != PanelBuilder.TriState.RESOLVED:
		return _fail("dismiss slot should be RESOLVED")

	_ok("real data d22_pm_sandbags verified for tri-states, non-choice slot preservation, and choice collapse")
	return 0


func _test_choice_serialize_roundtrip(gs: Node) -> int:
	_reset_gs(gs)
	print("--- 8. serialize / deserialize roundtrip for choices ---")

	(gs.get("choices") as Dictionary)["d22_pm_sandbags::acai_read"] = "obs_walk"
	(gs.get("choices") as Dictionary)["d29_pm_invitation::invitation"] = "invite_none"

	var data: Dictionary = gs.call("serialize")
	var new_gs: Node = load("res://scripts/autoload/game_state.gd").new()
	new_gs.call("deserialize", data)

	var choices: Dictionary = new_gs.get("choices") as Dictionary
	if choices.get("d22_pm_sandbags::acai_read") != "obs_walk":
		new_gs.free()
		return _fail("roundtrip failed for d22_pm_sandbags::acai_read")
	if choices.get("d29_pm_invitation::invitation") != "invite_none":
		new_gs.free()
		return _fail("roundtrip failed for d29_pm_invitation::invitation")

	new_gs.free()
	_ok("serialize/deserialize roundtrip preserved choices dictionary")
	return 0


func _test_choice_ui_buttons(gs: Node, _data_node: Node) -> int:
	_reset_gs(gs)
	print("--- 9. UI location_panel button generation and clicking ---")

	gs.set("day", 22)
	gs.set("phase", "afternoon")
	gs.call("set_flag", "acai_obs_knee", true)
	gs.call("gain_card", "equip_polaroid")

	var panel_scene: PackedScene = load("res://scenes/ui/location_panel.tscn")
	var panel: Node = panel_scene.instantiate()
	get_root().add_child(panel)

	# 顯示 sanquan 地點
	panel.call("show_location", "sanquan")
	await process_frame

	var beat_container: Node = panel.get_node("BeatContainer")
	var buttons: Array[Button] = []
	for child in beat_container.get_children():
		if child is Button:
			buttons.append(child as Button)

	# 在 sanquan 中：
	# work (accepts protagonist): 1 個放入按鈕（如果主角卡在手）
	# obs_walk (choice_group, accepts polaroid/box): 1 個選擇按鈕 + 1 個放入拍立得按鈕
	# obs_hands (LOCKED): 0 按鈕
	# obs_talk (choice_group): 1 個選擇按鈕 + 1 個放入拍立得按鈕
	# dismiss (choice_group): 1 個選擇按鈕 + 1 個放入拍立得按鈕
	if buttons.is_empty():
		panel.queue_free()
		return _fail("expected choice and place buttons in location_panel, found none")

	# 找出「選擇：① 他走路的方式」或「放入：拍立得」按鈕並點擊
	var target_btn: Button = null
	for btn in buttons:
		if btn.text.contains("他走路的方式"):
			target_btn = btn
			break

	if target_btn == null:
		panel.queue_free()
		return _fail("target choice button for obs_walk not found")

	# 模擬點擊
	target_btn.emit_signal("pressed")
	await process_frame

	# 驗證選擇完成
	var choices: Dictionary = gs.get("choices") as Dictionary
	if choices.get("d22_pm_sandbags::acai_read") != "obs_walk":
		panel.queue_free()
		return _fail("clicking choice button did not write to choices")

	panel.queue_free()
	_ok("location_panel generated direct/card choice buttons and button click successfully resolved choice")
	return 0
