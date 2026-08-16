extends SceneTree

## P2-A headless 驗收測試：發狂卡的產生、獨立倒數、tick_madness、open_night_marker、一夜一個標記、序列化往返。
## 跑法：
##   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/test_p2a.gd
## 全綠 exit 0；任一失敗 exit 1。

const LAST_DAY := 45
const PHASES := ["morning", "afternoon", "evening", "night"]


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
		push_error("P2-A: Data failed to load; abort")
		quit(1)
		return

	var failed := 0
	failed += _test_single_card_generation_night_marker(gs, data_node)
	failed += _test_daily_countdown_zeroing_and_clamp(gs, data_node)
	failed += _test_independent_clocks(gs, data_node)
	failed += _test_one_location_per_night(gs, data_node)
	failed += _test_reentry_idempotent(gs, data_node)
	failed += _test_free_location_no_madness(gs, data_node)
	failed += _test_fixed_night_beat_no_marker_no_madness(gs, data_node)
	failed += _test_serialize_roundtrip_p2a(gs)
	failed += _test_end_run_resets_p2a(gs)

	Engine.unregister_singleton("Data")
	Engine.unregister_singleton("GameState")

	if failed > 0:
		push_error("P2-A: %d test(s) failed" % failed)
		quit(1)
	else:
		print("P2-A: all tests passed")
		quit(0)


func _ok(msg: String) -> int:
	print("  ok  " + msg)
	return 0


func _fail(msg: String) -> int:
	push_error("  FAIL  " + msg)
	return 1


func _reset_gs(gs: Node) -> void:
	gs.call("end_run")


# ── 1. 第 6 夜進收費標記發卡、文字提示與當天不倒數 ───────────────────────────────

func _test_single_card_generation_night_marker(gs: Node, _data_node: Node) -> int:
	print("--- 1. single card generation on night marker (Day 6 night) ---")
	var failed := 0
	_reset_gs(gs)

	gs.set("day", 6)
	gs.set("phase", "night")

	var initial_used: int = gs.call("hand_slots_used")
	if initial_used != 1:
		failed += _fail("初始手牌佔格應為 1，實際為 %d" % initial_used)
	else:
		failed += _ok("初始手牌佔格為 1 (protagonist)")

	# 首次進入收費地點 n_ahong_1 (madness_cost == 1)
	var lines: PackedStringArray = gs.call("open_night_marker", "n_ahong_1")
	var hand: Array = gs.get("hand")
	var clock: Dictionary = gs.get("madness_clock")
	var opened: Dictionary = gs.get("night_markers_opened")
	var chosen: String = str(gs.get("night_location_chosen"))

	if lines.size() > 0 and lines[0].contains("發狂卡"):
		failed += _ok("進入收費夜間標記回傳說明文字行: %s" % lines[0])
	else:
		failed += _fail("進入收費夜間標記未回傳說明文字行 (lines=%s)" % str(lines))

	if hand.size() != 2 or not hand.has("madness#1"):
		failed += _fail("進入收費地點後手牌未增加 madness#1: %s" % str(hand))
	else:
		failed += _ok("進入收費地點手牌加入 madness#1")

	if int(clock.get("madness#1", -1)) != 7:
		failed += _fail("發狂卡初始倒數應為 7 天，實際為 %s" % str(clock.get("madness#1")))
	else:
		failed += _ok("發狂卡初始倒數為 7 天 (tuning.madness_countdown_days)")

	if not opened.has("n_ahong_1"):
		failed += _fail("night_markers_opened 未記錄 n_ahong_1")
	else:
		failed += _ok("night_markers_opened 記錄收費標記 n_ahong_1")

	if chosen != "n_ahong_1":
		failed += _fail("night_location_chosen 未設定為 n_ahong_1 (實際為 '%s')" % chosen)
	else:
		failed += _ok("night_location_chosen 記錄當夜選定地點 n_ahong_1")

	var used_after: int = gs.call("hand_slots_used")
	if used_after != 2:
		failed += _fail("發狂卡應佔手牌格，hand_slots_used 應為 2，實際為 %d" % used_after)
	else:
		failed += _ok("發狂卡佔手牌格 (hand_slots_used = 2)")

	# 當天不倒數：在 night 時段內 clock 維持 7
	if int(clock.get("madness#1", -1)) == 7:
		failed += _ok("產生當天 (night) 不倒數，剩餘天數維持 7")
	else:
		failed += _fail("產生當天不應倒數")

	return failed


# ── 2. 每天 morning 減 1，第 13 天 morning 歸零且次日不重複進隊列／不變負值 ───

func _test_daily_countdown_zeroing_and_clamp(gs: Node, _data_node: Node) -> int:
	print("--- 2. daily countdown, zeroing, clamp at 0, and non-duplicate zeroing ---")
	var failed := 0
	_reset_gs(gs)

	# 第 6 夜發卡
	gs.set("day", 6)
	gs.set("phase", "night")
	gs.call("open_night_marker", "n_ahong_1")

	# 推進至第 7 天 morning
	gs.call("advance_phase")
	var d7_day: int = gs.get("day")
	var d7_phase: String = gs.get("phase")
	var clock: Dictionary = gs.get("madness_clock")
	if d7_day == 7 and d7_phase == "morning" and int(clock.get("madness#1", -1)) == 6:
		failed += _ok("第 7 天 morning: advance_phase 自動觸發 tick_madness，倒數變 6")
	else:
		failed += _fail("第 7 天 morning 倒數未變 6 (day=%d, phase=%s, clock=%s)" % [d7_day, d7_phase, str(clock)])

	# 逐日推進至第 12 天 night
	for d in range(7, 13):
		gs.call("advance_phase") # -> afternoon
		gs.call("advance_phase") # -> evening
		gs.call("advance_phase") # -> night
		var expected_val := 7 - (d - 6)
		var cur_val: int = int((gs.get("madness_clock") as Dictionary).get("madness#1", -1))
		if cur_val != expected_val:
			failed += _fail("第 %d 天時倒數應為 %d，實際為 %d" % [d, expected_val, cur_val])
			break
		# 推進到次日 morning (d+1 morning)
		gs.call("advance_phase")

	var d13_day: int = gs.get("day")
	var d13_phase: String = gs.get("phase")
	var d13_val: int = int((gs.get("madness_clock") as Dictionary).get("madness#1", -1))

	if d13_day == 13 and d13_phase == "morning" and d13_val == 0:
		failed += _ok("第 13 天 morning: madness#1 正確歸零 (clock = 0)")
	else:
		failed += _fail("第 13 天 morning 未正確歸零 (day=%d, phase=%s, val=%d)" % [d13_day, d13_phase, d13_val])

	# 推進至第 14 天 morning：驗證不變負數且不再回傳歸零
	gs.call("advance_phase") # D13 afternoon
	gs.call("advance_phase") # D13 evening
	gs.call("advance_phase") # D13 night
	# 推進到 D14 morning (此時觸發 tick_madness)
	gs.call("advance_phase")

	var d14_day: int = gs.get("day")
	var d14_val: int = int((gs.get("madness_clock") as Dictionary).get("madness#1", -1))
	if d14_day == 14 and d14_val == 0:
		failed += _ok("第 14 天 morning: 倒數值 clamp 於 0，不變為負數 (val = 0)")
	else:
		failed += _fail("第 14 天 morning 倒數值非 0 (val=%d)" % d14_val)

	# 手動再呼叫一次 tick_madness 驗證回傳值為空
	var zeroed_next: Array[String] = gs.call("tick_madness")
	if zeroed_next.is_empty():
		failed += _ok("已歸零的卡片次日不重複加入 zeroed 回傳隊列")
	else:
		failed += _fail("已歸零卡片重複加入 zeroed: %s" % str(zeroed_next))

	return failed


# ── 3. 各走各的鐘 (多張發狂卡獨立倒數) ───────────────────────────────────────

func _test_independent_clocks(gs: Node, _data_node: Node) -> int:
	print("--- 3. independent countdown clocks ---")
	var failed := 0
	_reset_gs(gs)

	# 第 6 夜開 n_ahong_1 -> madness#1 (7天)
	gs.set("day", 6)
	gs.set("phase", "night")
	gs.call("open_night_marker", "n_ahong_1")

	# 推進到第 7 天 night
	gs.call("advance_phase") # D7 morning (madness#1 變 6)
	gs.call("advance_phase") # D7 afternoon
	gs.call("advance_phase") # D7 evening
	gs.call("advance_phase") # D7 night

	# 第 7 夜開 n_source -> madness#2 (7天)
	gs.call("open_night_marker", "n_source")
	var clock_d7: Dictionary = gs.get("madness_clock")
	if int(clock_d7.get("madness#1", -1)) == 6 and int(clock_d7.get("madness#2", -1)) == 7:
		failed += _ok("第 7 夜: madness#1 為 6 天，madness#2 為 7 天")
	else:
		failed += _fail("第 7 夜兩張卡狀態不符: %s" % str(clock_d7))

	# 推進到第 8 天 morning
	gs.call("advance_phase") # D8 morning (全體 -1)
	var clock_d8: Dictionary = gs.get("madness_clock")
	if int(clock_d8.get("madness#1", -1)) == 5 and int(clock_d8.get("madness#2", -1)) == 6:
		failed += _ok("第 8 天 morning: madness#1 為 5 天，madness#2 為 6 天 (各走各的鐘)")
	else:
		failed += _fail("第 8 天 morning 兩張卡倒數不符: %s" % str(clock_d8))

	return failed


# ── 4. 一夜一個標記 (選定後其他地點關閉，跨日重置) ───────────────────────────

func _test_one_location_per_night(gs: Node, data_node: Node) -> int:
	print("--- 4. one location per night restriction ---")
	var failed := 0
	_reset_gs(gs)

	gs.set("day", 6)
	gs.set("phase", "night")

	# 未選地點前：可看到多個開放地點
	var initial_locs: Array[String] = PanelBuilder.available_locations(gs, data_node)
	if initial_locs.size() > 1 and initial_locs.has("n_ahong_1") and initial_locs.has("n_woodtags"):
		failed += _ok("夜間選地點前，多個已開放夜間地點均在 available_locations 中 (共 %d 個)" % initial_locs.size())
	else:
		failed += _fail("夜間選地點前 available_locations 不符預期: %s" % str(initial_locs))

	# 選定 n_ahong_1
	gs.call("open_night_marker", "n_ahong_1")

	# 選定後：available_locations 僅回傳該選定地點
	var chosen_locs: Array[String] = PanelBuilder.available_locations(gs, data_node)
	if chosen_locs == ["n_ahong_1"]:
		failed += _ok("選定 n_ahong_1 後，available_locations 僅回傳 ['n_ahong_1']，其餘地點不可見/不可進")
	else:
		failed += _fail("選定地點後 available_locations 未正確過濾: %s" % str(chosen_locs))

	# 推進至次日 morning：night_location_chosen 自動重置
	gs.call("advance_phase")
	var morning_chosen: String = str(gs.get("night_location_chosen"))
	if morning_chosen.is_empty():
		failed += _ok("跨日推進至 morning 後，night_location_chosen 自動清空重置")
	else:
		failed += _fail("跨日後 night_location_chosen 未清空 (實際為 '%s')" % morning_chosen)

	return failed


# ── 5. 同一收費地點重複進入不重複發卡 ────────────────────────────────────────

func _test_reentry_idempotent(gs: Node, _data_node: Node) -> int:
	print("--- 5. reentry to opened night marker is idempotent ---")
	var failed := 0
	_reset_gs(gs)

	gs.set("day", 6)
	gs.set("phase", "night")
	var lines1: PackedStringArray = gs.call("open_night_marker", "n_ahong_1")

	var hand_count_1: int = (gs.get("hand") as Array).size()
	var clock_count_1: int = (gs.get("madness_clock") as Dictionary).size()

	# 再次呼叫 open_night_marker("n_ahong_1")
	var lines2: PackedStringArray = gs.call("open_night_marker", "n_ahong_1")
	var hand_count_2: int = (gs.get("hand") as Array).size()
	var clock_count_2: int = (gs.get("madness_clock") as Dictionary).size()

	if lines1.size() > 0 and lines2.is_empty() and hand_count_1 == hand_count_2 and clock_count_1 == clock_count_2:
		failed += _ok("首次進收費標記回傳提示文字，重複進入回傳空陣列且手牌張數不變")
	else:
		failed += _fail("重複進入收費地點斷言失敗 (lines1=%s, lines2=%s, hand1=%d, hand2=%d)" % [
			str(lines1), str(lines2), hand_count_1, hand_count_2
		])

	return failed


# ── 6. 免費地點不發卡且不記入 night_markers_opened ───────────────────────────

func _test_free_location_no_madness(gs: Node, data_node: Node) -> int:
	print("--- 6. free location (madness_cost == 0) does not grant madness or enter night_markers_opened ---")
	var failed := 0
	_reset_gs(gs)

	gs.set("day", 10)
	gs.set("phase", "night")
	var lines: PackedStringArray = gs.call("open_night_marker", "n_landmark")

	var hand: Array = gs.get("hand")
	var clock: Dictionary = gs.get("madness_clock")
	var opened: Dictionary = gs.get("night_markers_opened")
	var chosen: String = str(gs.get("night_location_chosen"))

	if lines.is_empty() and hand.size() == 1 and clock.is_empty() and not opened.has("n_landmark") and chosen == "n_landmark":
		failed += _ok("進入免費地點 n_landmark 不發卡、不記入 night_markers_opened，但設為當夜選定地點")
	else:
		failed += _fail("免費地點狀態異常 (lines=%s, hand=%s, clock=%s, opened=%s, chosen=%s)" % [
			str(lines), str(hand), str(clock), str(opened), chosen
		])

	var chosen_locs: Array[String] = PanelBuilder.available_locations(gs, data_node)
	if chosen_locs == ["n_landmark"]:
		failed += _ok("免費地點選定後當夜同樣套用一夜一個地點過濾")
	else:
		failed += _fail("免費地點選定後過濾異常: %s" % str(chosen_locs))

	return failed


# ── 7. fixed 定日夜 beat 不算開標記不發卡 ─────────────────────────────────────

func _test_fixed_night_beat_no_marker_no_madness(gs: Node, _data_node: Node) -> int:
	print("--- 7. fixed night beat does not count as marker ---")
	var failed := 0
	_reset_gs(gs)

	gs.set("day", 1)
	gs.set("phase", "night")

	var lines: PackedStringArray = gs.call("play_night_fixed")
	var hand: Array = gs.get("hand")
	var clock: Dictionary = gs.get("madness_clock")
	var opened: Dictionary = gs.get("night_markers_opened")

	if lines.size() > 0 and hand.size() == 1 and clock.is_empty() and opened.is_empty():
		failed += _ok("第 1 夜 fixed beat (走廊) 演出成功且不算開標記、不發卡")
	else:
		failed += _fail("第 1 夜 fixed beat 狀態異常 (lines=%d, hand=%s, opened=%s)" % [lines.size(), str(hand), str(opened)])

	return failed


# ── 8. 序列化往返 ────────────────────────────────────────────────────────────

func _test_serialize_roundtrip_p2a(gs: Node) -> int:
	print("--- 8. serialization roundtrip with P2-A fields ---")
	var failed := 0
	_reset_gs(gs)

	gs.set("day", 8)
	gs.set("phase", "night")
	gs.set("action_spent", true)

	var hand: Array[String] = ["protagonist", "madness#1", "madness#2"]
	gs.set("hand", hand)
	gs.set("madness_clock", { "madness#1": 5, "madness#2": 6 })
	gs.set("_madness_counter", 2)
	gs.set("night_markers_opened", { "n_ahong_1": true, "n_source": true })
	gs.set("night_location_chosen", "n_source")
	gs.set("indulgence_count", 3)
	gs.set("forced_pending", ["madness#1"] as Array[String])

	var saved: Dictionary = gs.call("serialize")

	# 重置
	_reset_gs(gs)

	# 讀回
	gs.call("deserialize", saved)

	var restored_clock: Dictionary = gs.get("madness_clock")
	var restored_counter: int = int(gs.get("_madness_counter"))
	var restored_opened: Dictionary = gs.get("night_markers_opened")
	var restored_chosen: String = str(gs.get("night_location_chosen"))
	var restored_ind_cnt: int = int(gs.get("indulgence_count"))
	var restored_pending: Array = gs.get("forced_pending")

	if int(restored_clock.get("madness#1", -1)) == 5 and int(restored_clock.get("madness#2", -1)) == 6:
		failed += _ok("序列化還原 madness_clock 錶值正確")
	else:
		failed += _fail("madness_clock 還原錯誤: %s" % str(restored_clock))

	if restored_counter == 2:
		failed += _ok("序列化還原 _madness_counter 正確 (2)")
	else:
		failed += _fail("_madness_counter 還原錯誤: %d" % restored_counter)

	if restored_opened.has("n_ahong_1") and restored_opened.has("n_source") and not restored_opened.has("n_landmark"):
		failed += _ok("序列化還原 night_markers_opened 收費集合正確")
	else:
		failed += _fail("night_markers_opened 還原錯誤: %s" % str(restored_opened))

	if restored_chosen == "n_source":
		failed += _ok("序列化還原 night_location_chosen 正確 ('n_source')")
	else:
		failed += _fail("night_location_chosen 還原錯誤: '%s'" % restored_chosen)

	if restored_ind_cnt == 3 and restored_pending == ["madness#1"]:
		failed += _ok("序列化還原 indulgence_count 與 forced_pending 正確")
	else:
		failed += _fail("P2 擴充欄位還原錯誤 (indulgence_count=%d, forced_pending=%s)" % [restored_ind_cnt, str(restored_pending)])

	return failed


# ── 9. end_run 完整重置 P2-A 欄位 ───────────────────────────────────────────

func _test_end_run_resets_p2a(gs: Node) -> int:
	print("--- 9. end_run resets P2-A state fields ---")
	var failed := 0

	gs.set("madness_clock", { "madness#1": 2 })
	gs.set("_madness_counter", 3)
	gs.set("night_markers_opened", { "n_ahong_1": true })
	gs.set("night_location_chosen", "n_ahong_1")
	gs.set("indulgence_count", 4)
	gs.set("forced_pending", ["madness#1"] as Array[String])

	gs.call("end_run")

	var clock: Dictionary = gs.get("madness_clock")
	var counter: int = int(gs.get("_madness_counter"))
	var opened: Dictionary = gs.get("night_markers_opened")
	var chosen: String = str(gs.get("night_location_chosen"))
	var ind_cnt: int = int(gs.get("indulgence_count"))
	var pending: Array = gs.get("forced_pending")

	if clock.is_empty() and counter == 0 and opened.is_empty() and chosen.is_empty() and ind_cnt == 0 and pending.is_empty():
		failed += _ok("end_run 成功清空 madness_clock, _madness_counter, night_markers_opened, night_location_chosen, indulgence_count, forced_pending")
	else:
		failed += _fail("end_run 未清空 P2 欄位 (clock=%s, counter=%d, opened=%s, chosen=%s, ind_cnt=%d, pending=%s)" % [
			str(clock), counter, str(opened), chosen, ind_cnt, str(pending)
		])

	return failed
