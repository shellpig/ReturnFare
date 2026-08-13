extends SceneTree

## P1-A headless 驗收測試。跑法：
##   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/test_game_state_p1a.gd
## 全綠 exit 0；任一失敗 exit 1。

# 與 GameState.ACTION_PHASES 必須保持一致
const _EXPECTED_ACTION_PHASES_COUNT := 2

const _GS_PATH := "res://scripts/autoload/game_state.gd"


func _initialize() -> void:
	var failed := 0
	failed += _test_bad_json()
	failed += _test_bad_phases_per_day()
	failed += _test_serialize_roundtrip()
	failed += _test_chapters()
	failed += _test_advance_day45()

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


func _new_gs() -> Object:
	return load(_GS_PATH).new()


# 壞 JSON fixture → DataLoader 回報錯誤
func _test_bad_json() -> int:
	print("--- bad_json ---")
	var loader := DataLoader.new("res://tests/fixtures/broken/bad_json/")
	loader.load_all()
	if loader.errors.is_empty():
		return _fail("bad_json: 預期有錯誤，卻得到 0 筆")
	return _ok("bad_json: 正確回報 %d 筆錯誤" % loader.errors.size())


# tuning.phases_per_day=3 → 與 ACTION_PHASES 不符
func _test_bad_phases_per_day() -> int:
	print("--- bad_phases_per_day ---")
	var loader := DataLoader.new("res://tests/fixtures/broken/bad_phases_per_day/")
	loader.load_all()
	var ppd: Variant = loader.tuning.get("phases_per_day")
	if ppd == null:
		return _fail("bad_phases_per_day: tuning.json 沒有 phases_per_day 鍵")
	if (ppd as int) == _EXPECTED_ACTION_PHASES_COUNT:
		return _fail("bad_phases_per_day: phases_per_day=%s 沒有觸發不符" % str(ppd))
	return _ok("bad_phases_per_day: phases_per_day=%s ≠ %d，可偵測" % [str(ppd), _EXPECTED_ACTION_PHASES_COUNT])


# GameState 序列化往返相等
func _test_serialize_roundtrip() -> int:
	print("--- serialize_roundtrip ---")
	var gs: Object = _new_gs()
	gs.set("day", 17)
	gs.set("phase", "night")
	gs.set("action_spent", true)

	var snap: Dictionary = gs.call("serialize")
	gs.set("day", 1)
	gs.set("phase", "morning")
	gs.set("action_spent", false)
	gs.call("deserialize", snap)

	var day_ok: bool = gs.get("day") == 17
	var phase_ok: bool = gs.get("phase") == "night"
	var spent_ok: bool = gs.get("action_spent") == true
	gs.free()

	if not (day_ok and phase_ok and spent_ok):
		return _fail("roundtrip: day=%s phase=%s action_spent=%s" % [
			str(gs.get("day")), str(gs.get("phase")), str(gs.get("action_spent"))
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


# 第 45 天：afternoon→evening 不進 night；evening 發出 run_ended
func _test_advance_day45() -> int:
	print("--- advance_day45 ---")
	var gs: Object = _new_gs()
	get_root().add_child(gs as Node)  # 掛入樹讓 signal 可連線

	# Array 是引用類型，lambda 可以寫入（bool 是值類型，lambda 只拿到副本）
	var fired: Array = []
	gs.connect("run_ended", func(_id: String) -> void: fired.append(true))

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

	gs.call("advance_phase")

	if fired.is_empty():
		failed += _fail("day45 evening advance: run_ended signal not emitted")
	else:
		failed += _ok("day45 evening advance: run_ended emitted")

	var phase_final: String = gs.get("phase")
	if phase_final != "evening":
		failed += _fail("day45 after run_ended: phase changed to %s (should stay evening)" % phase_final)
	else:
		failed += _ok("day45 after run_ended: phase stays evening (no night)")

	(gs as Node).queue_free()
	return failed
