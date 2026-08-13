extends SceneTree

## P1-C / P1-D 修 bug 回歸測試（K-01～K-04）：
## A1：location_panel.show_location() 透過 GameState.open_panel() 呈現 beat 並結算 on_enter。
## A2：beat 級 requires 不成立時，內部槽三態要一併降為 LOCKED（規格書第五節）。
## A3 (K-01+K-02)：GameState.open_panel() 規則層獨立入口，先結算 on_enter 再求值（Day 23 上午山泉閣連鎖解鎖）。
## A4 (K-03+K-04)：GameState.placeable_cards() 規則層過濾＋try_place() reason_code/reason_text 分離。
##
## 跑法：
##   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/test_p1c_bugfix.gd
##
## 本檔直接用 /root/GameState 與 /root/Data（project.godot 的 autoload 路徑）。
## 全綠 exit 0；任一失敗 exit 1。


func _initialize() -> void:
	await process_frame

	var data_node: Node = get_root().get_node("Data")
	if not data_node.get("ok"):
		push_error("P1-C bugfix: Data failed to load; abort")
		quit(1)
		return

	var failed := 0
	failed += await _test_a1_location_panel_calls_enter_beat()
	failed += _test_a2_beat_requires_cascades_to_slots()
	failed += _test_a3_open_panel_rule_layer_and_intra_panel()
	failed += _test_a4_placeable_cards_and_try_place_reason_code()

	if failed > 0:
		push_error("P1-C bugfix: %d test(s) failed" % failed)
		quit(1)
	else:
		print("P1-C bugfix: all tests passed")
		quit(0)


func _ok(msg: String) -> int:
	print("  ok  " + msg)
	return 0


func _fail(msg: String) -> int:
	push_error("  FAIL  " + msg)
	return 1


func _reset_gs(gs: Node) -> void:
	(gs.get("hand") as Array).clear()
	(gs.get("knowledge") as Dictionary).clear()
	(gs.get("madness_clock") as Dictionary).clear()
	(gs.get("beats_entered") as Dictionary).clear()
	(gs.get("slots_placed") as Dictionary).clear()
	(gs.get("flags") as Dictionary).clear()
	(gs.get("switches") as Dictionary).clear()
	(gs.get("switch_progress") as Dictionary).clear()
	(gs.get("relations") as Dictionary).clear()
	(gs.get("npc_action_counts") as Dictionary).clear()
	gs.set("_madness_counter", 0)
	gs.set("day", 1)
	gs.set("phase", "morning")
	gs.set("action_spent", false)


# ── A1：show_location() 要透過 open_panel() 呈現 beat ───────────────────────

func _test_a1_location_panel_calls_enter_beat() -> int:
	print("--- A1: location_panel.show_location() calls open_panel / enter_beat ---")
	var failed := 0

	var gs: Node = get_root().get_node("GameState")
	_reset_gs(gs)
	gs.set("day", 1)
	gs.set("phase", "evening")

	var scene: PackedScene = load("res://scenes/ui/location_panel.tscn")
	var panel: Node = scene.instantiate()
	get_root().add_child(panel)
	await process_frame

	panel.call("show_location", "busstop")

	if not (gs.get("beats_entered") as Dictionary).has("d1_arrival"):
		failed += _fail("show_location(busstop) did not run enter_beat: beats_entered missing d1_arrival")
	else:
		failed += _ok("show_location(busstop) ran enter_beat: beats_entered has d1_arrival")

	if not (gs.get("hand") as Array).has("protagonist"):
		failed += _fail("show_location(busstop): d1_arrival.on_enter.gain(protagonist) did not run")
	else:
		failed += _ok("show_location(busstop): d1_arrival.on_enter.gain(protagonist) ran")

	panel.queue_free()
	return failed


# ── A2：beat 級 LOCKED 要傳導到槽（view model 與 try_place 都要擋）──────────

func _test_a2_beat_requires_cascades_to_slots() -> int:
	print("--- A2: beat-level LOCKED cascades to slot tri (d19_pm_upstream) ---")
	var failed := 0

	var gs: Node = get_root().get_node("GameState")
	var data_node: Node = get_root().get_node("Data")
	_reset_gs(gs)

	gs.call("gain_card", "protagonist")
	gs.set("day", 19)
	gs.set("phase", "afternoon")

	# 尚未持有 k_forty_something → d19_pm_upstream 的 requires 不成立 → beat LOCKED
	var view: Dictionary = PanelBuilder.build("upstream", gs, data_node)
	var bv: Dictionary = _find_beat(view, "d19_pm_upstream")
	if bv.is_empty():
		return _fail("d19_pm_upstream not found in upstream panel (day=19 afternoon)")

	if int(bv["tri"]) != PanelBuilder.TriState.LOCKED:
		failed += _fail("d19_pm_upstream beat tri: expected LOCKED, got %d" % int(bv["tri"]))
	else:
		failed += _ok("d19_pm_upstream beat tri is LOCKED (missing k_forty_something)")

	var beat_reason: String = str(bv["reason"])
	var slot_view: Dictionary = {}
	for sv in bv["slots"] as Array:
		if str((sv as Dictionary)["slot"]["id"]) == "look":
			slot_view = sv as Dictionary
			break
	if slot_view.is_empty():
		return _fail("look slot not found under d19_pm_upstream")

	if int(slot_view["tri"]) != PanelBuilder.TriState.LOCKED:
		failed += _fail("look slot tri: expected LOCKED (cascaded from beat), got %d" % int(slot_view["tri"]))
	else:
		failed += _ok("look slot tri is LOCKED (cascaded from beat-level requires)")
	if str(slot_view["reason"]) != beat_reason:
		failed += _fail("look slot reason should match beat reason; slot=%s beat=%s" % [
			str(slot_view["reason"]), beat_reason])
	else:
		failed += _ok("look slot reason matches beat reason")

	# 規則層要能獨立擋下：繞過 UI 直接呼叫 try_place，一樣不准放
	var result: Dictionary = gs.call("try_place", "protagonist", "d19_pm_upstream", "look")
	if result.get("ok", false):
		failed += _fail("try_place on beat-LOCKED slot should fail, got ok=true")
	else:
		failed += _ok("try_place on beat-LOCKED slot → ok=false (reason=%s)" % str(result.get("reason")))
	if str(result.get("reason_code")) != "locked":
		failed += _fail("try_place rejection reason_code should be 'locked', got %s" % str(result.get("reason_code")))
	else:
		failed += _ok("try_place rejection reason_code is 'locked'")
	if str(result.get("reason_text")) != beat_reason:
		failed += _fail("try_place rejection reason_text should match beat reason; got %s expected %s" % [
			str(result.get("reason_text")), beat_reason])
	else:
		failed += _ok("try_place rejection reason_text matches beat reason")
	if not (gs.get("slots_placed") as Dictionary).is_empty():
		failed += _fail("try_place on beat-LOCKED slot should leave slots_placed empty")
	else:
		failed += _ok("try_place on beat-LOCKED slot: slots_placed unchanged (empty)")

	# 補上 k_forty_something 之後：beat／槽都變 OPEN，try_place 成功
	gs.call("gain_card", "k_forty_something")
	view = PanelBuilder.build("upstream", gs, data_node)
	bv = _find_beat(view, "d19_pm_upstream")
	if int(bv.get("tri", -1)) != PanelBuilder.TriState.OPEN:
		failed += _fail("after gaining k_forty_something, d19_pm_upstream should be OPEN")
	else:
		failed += _ok("after gaining k_forty_something, d19_pm_upstream is OPEN")

	var result2: Dictionary = gs.call("try_place", "protagonist", "d19_pm_upstream", "look")
	if not result2.get("ok", false):
		failed += _fail("try_place after gaining k_forty_something should succeed, got %s" % str(result2))
	else:
		failed += _ok("try_place after gaining k_forty_something → ok")

	return failed


# ── A3 (K-01+K-02)：open_panel 規則層入口與同面板連鎖求值 ─────────────────────

func _test_a3_open_panel_rule_layer_and_intra_panel() -> int:
	print("--- A3: GameState.open_panel() rule layer & intra-panel on_enter (d23 AM sanquan) ---")
	var failed := 0

	var gs: Node = get_root().get_node("GameState")
	_reset_gs(gs)
	gs.call("gain_card", "protagonist")
	gs.set("day", 23)
	gs.set("phase", "morning")

	# 不 instantiate 任何 UI，直接呼叫 GameState.open_panel("sanquan")
	var view: Dictionary = gs.call("open_panel", "sanquan")

	# ① 驗證 d23_morning_awei_knocks 已被 enter_beat，flag awei_sheltering 已寫入
	if not (gs.get("beats_entered") as Dictionary).has("d23_morning_awei_knocks"):
		failed += _fail("open_panel(sanquan): beats_entered missing d23_morning_awei_knocks")
	else:
		failed += _ok("open_panel(sanquan): beats_entered has d23_morning_awei_knocks")

	if not bool((gs.get("flags") as Dictionary).get("awei_sheltering", false)):
		failed += _fail("open_panel(sanquan): on_enter flag awei_sheltering not set")
	else:
		failed += _ok("open_panel(sanquan): on_enter flag awei_sheltering = true")

	# ② 驗證依賴 awei_sheltering 的 d23_am_settle_grandma 在同一回傳的 view model 中已呈 OPEN
	var grandma_beat: Dictionary = _find_beat(view, "d23_am_settle_grandma")
	if grandma_beat.is_empty():
		failed += _fail("open_panel(sanquan): d23_am_settle_grandma missing from view (evaluated before on_enter?)")
	else:
		if int(grandma_beat.get("tri", -1)) != PanelBuilder.TriState.OPEN:
			failed += _fail("open_panel(sanquan): d23_am_settle_grandma tri expected OPEN, got %d" % int(grandma_beat.get("tri", -1)))
		else:
			failed += _ok("open_panel(sanquan): d23_am_settle_grandma is OPEN on first open")

	return failed


# ── A4 (K-03+K-04)：placeable_cards 過濾與 try_place 結構 ────────────────────

func _test_a4_placeable_cards_and_try_place_reason_code() -> int:
	print("--- A4: GameState.placeable_cards() & try_place reason_code/reason_text ---")
	var failed := 0

	var gs: Node = get_root().get_node("GameState")
	_reset_gs(gs)
	gs.call("gain_card", "protagonist")
	gs.call("gain_card", "info_husband_version")
	gs.set("day", 3)
	gs.set("phase", "afternoon")

	# d3_pm_sanquan 下有兩個槽：soak（收 protagonist）、show_version（收 info 類比對卡）
	# ① 尚未消耗行動格時，soak 槽的 placeable_cards 應含 protagonist
	var soak_cards: Array = gs.call("placeable_cards", "d3_pm_sanquan", "soak")
	if not soak_cards.has("protagonist"):
		failed += _fail("placeable_cards soak: expected protagonist in list, got %s" % str(soak_cards))
	else:
		failed += _ok("placeable_cards soak contains protagonist")

	# ② show_version 是比對槽，不收 protagonist，只收 info
	var show_cards: Array = gs.call("placeable_cards", "d3_pm_sanquan", "show_version")
	if show_cards.has("protagonist") or not show_cards.has("info_husband_version"):
		failed += _fail("placeable_cards show_version: expected [info_husband_version], got %s" % str(show_cards))
	else:
		failed += _ok("placeable_cards show_version correctly filters by accepts")

	# ③ 放入主角卡消耗行動格後，soak 的 placeable_cards 應過濾掉 protagonist
	var place_res: Dictionary = gs.call("try_place", "protagonist", "d3_pm_sanquan", "soak")
	if not place_res.get("ok", false):
		failed += _fail("try_place protagonist in soak failed: %s" % str(place_res))
		return failed
	failed += _ok("try_place protagonist in soak succeeded")

	# 同一格已放過 → placeable_cards 應為空
	var soak_after: Array = gs.call("placeable_cards", "d3_pm_sanquan", "soak")
	if not soak_after.is_empty():
		failed += _fail("placeable_cards on resolved slot should be empty, got %s" % str(soak_after))
	else:
		failed += _ok("placeable_cards on resolved slot is empty")

	# 行動格 ledger（收 protagonist）因為 action_spent=true，placeable_cards 不得列出 protagonist
	var ledger_cards: Array = gs.call("placeable_cards", "d3_pm_sanquan", "ledger")
	if ledger_cards.has("protagonist"):
		failed += _fail("placeable_cards ledger should NOT contain protagonist when action_spent=true, got %s" % str(ledger_cards))
	else:
		failed += _ok("placeable_cards ledger excludes protagonist when action_spent=true")

	# ④ try_place 拒絕原因格式檢查：
	# action_spent 失敗時 reason_code 為 "action_spent", reason_text 為 ""
	var spent_res: Dictionary = gs.call("try_place", "protagonist", "d3_pm_sanquan", "ledger")
	if str(spent_res.get("reason_code")) != "action_spent" or str(spent_res.get("reason_text")) != "":
		failed += _fail("try_place action_spent: expected reason_code='action_spent', reason_text='', got %s" % str(spent_res))
	else:
		failed += _ok("try_place action_spent returns reason_code='action_spent' and empty reason_text")

	return failed


func _find_beat(view: Dictionary, beat_id: String) -> Dictionary:
	for entry in view.get("beats", []) as Array:
		if str((entry as Dictionary)["beat"]["id"]) == beat_id:
			return entry as Dictionary
	return {}

