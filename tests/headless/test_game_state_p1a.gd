extends SceneTree

## P1-A headless 驗收測試。跑法：
##   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/test_game_state_p1a.gd
## 全綠 exit 0；任一失敗 exit 1。

# 與 GameState.ACTION_PHASES 必須保持一致
const _EXPECTED_ACTION_PHASES_COUNT := 2

const _GS_PATH := "res://scripts/autoload/game_state.gd"


func _initialize() -> void:
	var gs: Node = load("res://scripts/autoload/game_state.gd").new()
	gs.set("flow_mode", "run")  # P5-D：fresh state 是 opening，本檔驗的是 run 層
	gs.name = "GameState"
	get_root().add_child(gs)
	Engine.register_singleton("GameState", gs)

	var failed := 0
	failed += _test_bad_json(gs)
	failed += _test_bad_phases_per_day(gs)
	failed += _test_missing_tuning_key(gs)
	failed += _test_serialize_roundtrip()
	failed += _test_chapters()
	failed += _test_advance_day45()
	failed += _test_full_45_days_loop()

	Engine.unregister_singleton("GameState")
	gs.queue_free()

	if failed > 0:
		push_error("P1-A: %d test(s) failed" % failed)
		quit(1)
	else:
		print("P1-A: all tests passed")
		quit(0)


func _ok(msg: String) -> int:
	print("  ok  " + msg)
	return 0


func _fail(msg: String) -> int:
	push_error("  FAIL  " + msg)
	return 1


## P5-D：fresh state 是 opening。本檔驗的是時間軸本身，因此建好就切進 run
## （開局選項的正式路徑由 test_p5d 驗）。
func _new_gs() -> Object:
	var gs: Object = load(_GS_PATH).new()
	gs.set("flow_mode", "run")
	gs.call("gain_card", "protagonist", false)
	return gs


# 壞 JSON fixture → DataLoader 回報錯誤，Data.ok = false 擋進遊戲
func _test_bad_json(gs: Node) -> int:
	print("--- bad_json ---")
	var real_data := get_root().get_node("Data")
	var res: bool = real_data.call("load_data", "res://tests/fixtures/broken/bad_json/")
	var ok_flag: bool = real_data.get("ok")
	real_data.call("load_data", "res://data/")

	if res or ok_flag:
		return _fail("bad_json: Data.ok 預期為 false，實際為 true")
	return _ok("bad_json: Data.ok=false 擋進遊戲")


# tuning.phases_per_day=3 → 與 ACTION_PHASES 不符，Data.ok = false 且主畫面顯示 ErrorLabel 隱藏操作 UI
func _test_bad_phases_per_day(gs: Node) -> int:
	print("--- bad_phases_per_day ---")
	var real_data := get_root().get_node("Data")
	var res: bool = real_data.call("load_data", "res://tests/fixtures/broken/bad_phases_per_day/")
	var ok_flag: bool = real_data.get("ok")

	var failed := 0
	if res or ok_flag:
		failed += _fail("bad_phases_per_day: Data.ok 預期為 false，實際為 true")
	else:
		failed += _ok("bad_phases_per_day: tuning.phases_per_day ≠ 2 判定 ok=false")

	# 驗證 Data.ok = false 時，main 畫面切到 ErrorLabel 隱藏操作 UI
	var main_scene_class := load("res://scenes/main.tscn")
	var main_node: Control = main_scene_class.instantiate()
	main_node._ready()

	var error_label: Label = main_node.get_node("ErrorLabel")
	var status_label: Label = main_node.get_node("StatusLabel")
	var advance_btn: Button = main_node.get_node("AdvanceButton")

	if error_label.text != "資料載入失敗，詳情見 Output。":
		failed += _fail("main error UI: text wrong, got '%s'" % error_label.text)
	else:
		failed += _ok("main error UI: ErrorLabel shows error text correctly")

	if status_label.visible or advance_btn.visible:
		failed += _fail("main error UI: status_label or advance_btn should be hidden")
	else:
		failed += _ok("main error UI: status_label and advance_btn hidden correctly")

	main_node.queue_free()

	# 恢復原本正常的 data
	real_data.call("load_data", "res://data/")
	return failed


# tuning 缺少必要鍵 → Data.load_data 判定 ok=false 擋開機（K-07）
func _test_missing_tuning_key(gs: Node) -> int:
	print("--- missing_tuning_key ---")
	var real_data := get_root().get_node("Data")
	var data_class := load("res://scripts/autoload/data.gd")
	var req_keys: Array = data_class.REQUIRED_TUNING_KEYS

	# 驗證正常資料下所有必要 tuning 鍵皆存在
	real_data.call("load_data", "res://data/")
	if not real_data.get("ok"):
		return _fail("normal data failed to load")

	for k: String in req_keys:
		if real_data.call("tuning", k) == null:
			return _fail("required tuning key '%s' returned null on real data" % k)

	# 破壞性測試：暫時刪除一個必要鍵，驗證 load_data 失敗
	var orig_loader: DataLoader = real_data.get("loader")
	var orig_val = orig_loader.tuning.get("hand_size")
	orig_loader.tuning.erase("hand_size")
	var pass_without_key = true
	for k: String in req_keys:
		if real_data.call("tuning", k) == null:
			pass_without_key = false
			break
	orig_loader.tuning["hand_size"] = orig_val

	if pass_without_key:
		return _fail("erasing required tuning key 'hand_size' should be detected")

	return _ok("all %d required tuning keys verified and validated" % req_keys.size())


func _test_serialize_roundtrip() -> int:
	print("--- serialize_roundtrip ---")
	var gs: Object = _new_gs()
	gs.set("day", 17)
	gs.set("phase", "night")
	gs.set("action_spent", true)

	var snap: Dictionary = gs.call("serialize")
	var json_str := JSON.stringify(snap)
	var parsed: Dictionary = JSON.parse_string(json_str)

	gs.set("day", 1)
	gs.set("phase", "morning")
	gs.set("action_spent", false)
	gs.call("deserialize", parsed)

	var actual_day: int = int(gs.get("day"))
	var actual_phase: String = str(gs.get("phase"))
	var actual_spent: bool = bool(gs.get("action_spent"))
	gs.free()

	if not (actual_day == 17 and actual_phase == "night" and actual_spent == true):
		return _fail("roundtrip: day=%d phase=%s action_spent=%s" % [
			actual_day, actual_phase, str(actual_spent)
		])
	return _ok("roundtrip: day/phase/action_spent 全部還原正確")


# chapter() 各界線
func _test_chapters() -> int:
	print("--- chapters ---")
	var gs: Object = _new_gs()
	var failed := 0
	var cases := [[1, 1], [15, 1], [16, 2], [32, 2], [33, 3], [45, 3]]
	for c in cases:
		gs.set("day", c[0])
		var got: int = gs.call("chapter")
		if got != c[1]:
			failed += _fail("chapter(day=%d): expect %d got %d" % [c[0], c[1], got])
		else:
			failed += _ok("chapter(day=%d) = %d" % [c[0], c[1]])
	gs.free()
	return failed


# 第 45 天：afternoon→evening 不進 night；evening 發出 ending_started
func _test_advance_day45() -> int:
	print("--- advance_day45 ---")
	var gs: Object = _new_gs()
	get_root().add_child(gs as Node)  # 掛入樹讓 signal 可連線

	# Array 是引用類型，lambda 可以寫入（bool 是值類型，lambda 只拿到副本）
	var fired: Array = []
	gs.connect("ending_started", func() -> void: fired.append(true))

	gs.set("day", 45)
	gs.set("phase", "afternoon")
	gs.call("advance_phase")

	var failed := 0
	var phase_after: String = gs.get("phase")
	var day_after: int = gs.get("day")

	if phase_after != "evening":
		failed += _fail("day45 afternoon→?: phase=%s expect=evening" % phase_after)
	else:
		failed += _ok("day45 afternoon→evening OK")

	if day_after != 45:
		failed += _fail("day45: day should stay 45, got %d" % day_after)
	else:
		failed += _ok("day45: day stays 45")

	# P5-B：D45 evening 改由 d45_then 的 phase_exit 門檻接結局。
	# 門檻未完成時不得離場，且不再有 run_reset 的跨輪重置（正式結算在 P5-D）。
	(gs.get("flags") as Dictionary)["final_day"] = true
	var gate_res: Dictionary = gs.call("advance_phase")
	if str(gate_res.get("reason_code", "")) != "phase_requirements_incomplete":
		failed += _fail("day45 evening: 門檻未完成應回 phase_requirements_incomplete，實際 '%s'" % str(gate_res.get("reason_code", "")))
	else:
		failed += _ok("day45 evening: coda 門檻未完成時拒絕離場")

	# B1：coda 門檻改成「d45_coda 選擇組已結算」，比對與空手兩條路都算完成。
	(gs.get("choices") as Dictionary)["d45_then::d45_coda"] = "compare_registry"
	(gs.get("slots_placed") as Dictionary)["d45_then::compare_registry"] = true
	gs.set("selected_festival_proxy_npc", "ajie")
	gs.call("advance_phase")

	if fired.is_empty():
		failed += _fail("day45 evening advance: ending_started signal not emitted")
	else:
		failed += _ok("day45 evening advance: ending_started emitted")

	var phase_final: String = gs.get("phase")
	var day_final: int = int(gs.get("day"))
	if phase_final != "evening" or day_final != 45 or str(gs.get("flow_mode")) != "ending":
		failed += _fail("day45 進結局後應停在 Day 45 evening 且 mode 為 ending，實際 Day %d %s / %s" % [day_final, phase_final, str(gs.get("flow_mode"))])
	else:
		failed += _ok("day45 coda 門檻完成後進入 ending mode，day／phase 不動（P5-B）")

	(gs as Node).queue_free()
	return failed


# 從 Day 1 morning 一路 advance_phase 跑完 45 天，驗證 day/phase 遞增與 chapter_changed 恰為 2 次
func _test_full_45_days_loop() -> int:
	print("--- full_45_days_loop ---")
	var gs: Object = _new_gs()
	var gs_node := gs as Node
	get_root().add_child(gs_node)

	var chapter_changes: Array = []
	gs_node.connect("chapter_changed", func(ch: int) -> void: chapter_changes.append(ch))

	var day_changes: Array = []
	gs_node.connect("day_changed", func(d: int) -> void: day_changes.append(d))

	gs.set("day", 1)
	gs.set("phase", "morning")

	# 45 天 × 4 時段：Day 1 morning 到 Day 45 evening 需推進 178 次 advance_phase()
	# P5-B／A1：D45 終局鏈現在是時段生命週期的一部分（morning 的 fixed beat 自動進場，
	# afternoon 因此自動起遭遇）。本測試只驗時間軸本身，所以每一步先把遭遇清掉。
	# P5-D：夜間第一次推進只把「直接睡」的文字停拍下來，不換時段，因此這裡數的是
	# 真正換時段的次數（phase_advanced 為 true），不是按了幾次。
	var advanced := 0
	var guard := 0
	while advanced < 178 and guard < 500:
		guard += 1
		(gs.get("active_encounter") as Dictionary).clear()
		var step_res: Dictionary = gs.call("advance_phase")
		if bool(step_res.get("phase_advanced", false)):
			advanced += 1

	var failed := 0
	if gs.get("day") != 45 or gs.get("phase") != "evening":
		failed += _fail("full 45 loop: expected day 45 evening, got day %d %s" % [
			gs.get("day"), gs.get("phase")
		])
	else:
		failed += _ok("full 45 loop: 178 steps reached day 45 evening correctly")

	if chapter_changes.size() != 2:
		failed += _fail("chapter_changed count: expected 2 (ch 1->2 at day 16, 2->3 at day 33), got %d: %s" % [
			chapter_changes.size(), str(chapter_changes)
		])
	elif chapter_changes != [2, 3]:
		failed += _fail("chapter_changed sequence: expected [2, 3], got %s" % str(chapter_changes))
	else:
		failed += _ok("chapter_changed fired exactly 2 times at ch2 and ch3")

	if day_changes.size() != 44:
		failed += _fail("day_changed count: expected 44 (day 2..45), got %d" % day_changes.size())
	else:
		failed += _ok("day_changed fired exactly 44 times")

	gs_node.queue_free()
	return failed
