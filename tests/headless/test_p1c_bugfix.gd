extends SceneTree

## P1-C 修 bug 回歸測試（2026-08-13 code review 找到的 A1／A2，兩條都在動 P1-D 之後補回）：
## A1：白天／固定面板要走 GameState.enter_beat()（beat 呈現的唯一入口，規格書第四節）——
##     結算 on_enter、寫入 beats_entered，不能只在 evening 演出流走這條。
## A2：beat 級 requires 不成立時，內部槽三態要一併降為 LOCKED（規格書第五節）——
##     PanelBuilder 的 view model 要降，GameState.try_place 的規則層也要獨立擋（不能只靠 UI）。
##
## 跑法：
##   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/test_p1c_bugfix.gd
##
## 本檔刻意不手動組裝 singleton，直接用 /root/GameState 與 /root/Data（project.godot 的
## autoload 路徑）——location_panel.gd 內部呼叫的就是這兩個裸全域，驗的要是遊戲實際會走的那條路。
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


# ── A1：show_location() 要透過 enter_beat() 呈現 beat ───────────────────────

func _test_a1_location_panel_calls_enter_beat() -> int:
	print("--- A1: location_panel.show_location() calls enter_beat ---")
	var failed := 0

	var gs: Node = get_root().get_node("GameState")
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
	if str(result.get("reason")) != beat_reason:
		failed += _fail("try_place rejection reason should match beat reason; got %s expected %s" % [
			str(result.get("reason")), beat_reason])
	else:
		failed += _ok("try_place rejection reason matches beat reason")
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


func _find_beat(view: Dictionary, beat_id: String) -> Dictionary:
	for entry in view.get("beats", []) as Array:
		if str((entry as Dictionary)["beat"]["id"]) == beat_id:
			return entry as Dictionary
	return {}
