extends SceneTree

## P2-A headless 驗收測試：發狂卡的產生、獨立倒數、tick_madness、enter_night_location、一夜一個標記、序列化往返。
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
	failed += _test_failure_text_precedence()

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
	gs.set("night_locations_seen", {})
	gs.set("night_once_beats_seen", {})
	gs.set("knowledge", {})


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
	var res: Dictionary = gs.call("enter_night_location", "n_ahong_1")
	var lines: PackedStringArray = res.get("lines", PackedStringArray())
	var hand: Array = gs.get("hand")
	var clock: Dictionary = gs.get("madness_clock")
	var seen: Dictionary = gs.get("night_locations_seen")
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

	if not seen.has("n_ahong_1"):
		failed += _fail("night_locations_seen 未記錄 n_ahong_1")
	else:
		failed += _ok("night_locations_seen 記錄收費標記 n_ahong_1")

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
	gs.call("enter_night_location", "n_ahong_1")

	# 推進至第 7 天 morning
	gs.call("advance_phase")
	var d7_day: int = gs.get("day")
	var d7_phase: String = gs.get("phase")
	var clock: Dictionary = gs.get("madness_clock")
	if d7_day == 7 and d7_phase == "morning" and int(clock.get("madness#1", -1)) == 6:
		failed += _ok("第 7 天 morning: advance_phase 自動觸發 tick_madness，倒數變 6")
	else:
		failed += _fail("第 7 天 morning 倒數未變 6 (day=%d, phase=%s, clock=%s)" % [d7_day, d7_phase, str(clock)])

	# 逐日推進至第 12 天 morning (倒數變 1)
	for d in range(7, 12):
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

	var d12_val: int = int((gs.get("madness_clock") as Dictionary).get("madness#1", -1))
	if d12_val == 1:
		failed += _ok("第 12 天 morning: madness#1 倒數變 1")
	else:
		failed += _fail("第 12 天 morning 倒數未變 1 (val=%d)" % d12_val)

	# 說明：在 P2-A 單元驗證層，驗證 tick_madness() 自身的歸零回傳與 clamp 於 0 行為。
	# 在 P2-C 之後，若推進至第 13 天 morning，advance_phase 會自動觸發 _settle_forced_indulgence()
	# 將歸零的 madness#1 消除；完整的跨時段生命週期（歸零 -> 強制執行 -> 消卡吃格）由 test_p2c.gd 測試 1 驗收。
	# 驗證 tick_madness() 歸零行為
	var zeroed_list: Array[String] = gs.call("tick_madness")
	var zero_val: int = int((gs.get("madness_clock") as Dictionary).get("madness#1", -1))
	if zeroed_list == ["madness#1"] and zero_val == 0:
		failed += _ok("tick_madness 成功回傳歸零清單 ['madness#1'] 且 clock 值變為 0")
	else:
		failed += _fail("tick_madness 歸零行為不符 (zeroed=%s, val=%d)" % [str(zeroed_list), zero_val])

	# 再次呼叫 tick_madness：驗證 clamp 於 0 且不重複回傳歸零
	var zeroed_next: Array[String] = gs.call("tick_madness")
	var clamp_val: int = int((gs.get("madness_clock") as Dictionary).get("madness#1", -1))
	if zeroed_next.is_empty() and clamp_val == 0:
		failed += _ok("已歸零卡片倒數值 clamp 於 0 且次日不重複加入 zeroed 回傳隊列")
	else:
		failed += _fail("clamp 或重複加入 zeroed 異常 (zeroed=%s, val=%d)" % [str(zeroed_next), clamp_val])

	return failed


# ── 3. 各走各的鐘 (多張發狂卡獨立倒數) ───────────────────────────────────────

func _test_independent_clocks(gs: Node, _data_node: Node) -> int:
	print("--- 3. independent countdown clocks ---")
	var failed := 0
	_reset_gs(gs)

	# 第 6 夜開 n_ahong_1 -> madness#1 (7天)
	gs.set("day", 6)
	gs.set("phase", "night")
	gs.call("enter_night_location", "n_ahong_1")

	# 推進到第 7 天 night
	gs.call("advance_phase") # D7 morning (madness#1 變 6)
	gs.call("advance_phase") # D7 afternoon
	gs.call("advance_phase") # D7 evening
	gs.call("advance_phase") # D7 night

	# 第 7 夜開 n_source -> madness#2 (7天)
	gs.call("enter_night_location", "n_source")
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
	gs.call("enter_night_location", "n_ahong_1")

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
	var res1: Dictionary = gs.call("enter_night_location", "n_ahong_1")
	var lines1: PackedStringArray = res1.get("lines", PackedStringArray())

	var hand_count_1: int = (gs.get("hand") as Array).size()
	var clock_count_1: int = (gs.get("madness_clock") as Dictionary).size()

	# 推進至下一夜（D7 night）再次進入 n_ahong_1
	gs.call("advance_phase") # D7 morning
	gs.call("advance_phase") # D7 afternoon
	gs.call("advance_phase") # D7 evening
	gs.call("advance_phase") # D7 night

	var res2: Dictionary = gs.call("enter_night_location", "n_ahong_1")
	var lines2: PackedStringArray = res2.get("lines", PackedStringArray())
	var hand_count_2: int = (gs.get("hand") as Array).size()
	var clock_count_2: int = (gs.get("madness_clock") as Dictionary).size()

	if lines1.size() > 0 and lines2.is_empty() and hand_count_1 == hand_count_2 and clock_count_1 == clock_count_2 and bool(res2.get("ok", false)):
		failed += _ok("首次進收費標記回傳提示文字，次夜重複進入回傳空陣列且手牌張數不變")
	else:
		failed += _fail("重複進入收費地點斷言失敗 (res1=%s, res2=%s, hand1=%d, hand2=%d)" % [
			str(res1), str(res2), hand_count_1, hand_count_2
		])

	return failed


# ── 6. 免費地點不發卡但記入 night_locations_seen ─────────────────────────────

func _test_free_location_no_madness(gs: Node, data_node: Node) -> int:
	print("--- 6. free location (madness_cost == 0) does not grant madness but is recorded in seen ---")
	var failed := 0
	_reset_gs(gs)

	gs.set("day", 10)
	gs.set("phase", "night")
	var res: Dictionary = gs.call("enter_night_location", "n_landmark")
	var lines: PackedStringArray = res.get("lines", PackedStringArray())

	var hand: Array = gs.get("hand")
	var clock: Dictionary = gs.get("madness_clock")
	var seen: Dictionary = gs.get("night_locations_seen")
	var chosen: String = str(gs.get("night_location_chosen"))

	if lines.is_empty() and hand.size() == 1 and clock.is_empty() and seen.has("n_landmark") and chosen == "n_landmark" and bool(res.get("ok", false)):
		failed += _ok("進入免費地點 n_landmark 不發卡、記入 night_locations_seen，且設為當夜選定地點")
	else:
		failed += _fail("免費地點狀態異常 (lines=%s, hand=%s, clock=%s, seen=%s, chosen=%s)" % [
			str(lines), str(hand), str(clock), str(seen), chosen
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

	if lines.size() > 0 and hand.size() == 1 and clock.is_empty():
		failed += _ok("第 1 夜 fixed beat (走廊) 演出成功且不發卡")
	else:
		failed += _fail("第 1 夜 fixed beat 狀態異常 (lines=%d, hand=%s)" % [lines.size(), str(hand)])

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
	gs.set("night_locations_seen", { "n_ahong_1": true, "n_source": true })
	gs.set("night_location_chosen", "n_source")
	gs.set("night_sleep_pending", false)
	gs.set("indulgence_count", 3)
	gs.set("forced_pending", ["madness#1"] as Array[String])

	var saved: Dictionary = gs.call("serialize")

	# 重置
	_reset_gs(gs)

	# 讀回
	gs.call("deserialize", saved)

	var restored_clock: Dictionary = gs.get("madness_clock")
	var restored_counter: int = int(gs.get("_madness_counter"))
	var restored_seen: Dictionary = gs.get("night_locations_seen")
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

	if restored_seen.has("n_ahong_1") and restored_seen.has("n_source") and not restored_seen.has("n_landmark"):
		failed += _ok("序列化還原 night_locations_seen 收費集合正確")
	else:
		failed += _fail("night_locations_seen 還原錯誤: %s" % str(restored_seen))

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
	gs.set("night_locations_seen", { "n_ahong_1": true })
	gs.set("night_location_chosen", "n_ahong_1")
	gs.set("night_sleep_pending", true)
	gs.set("indulgence_count", 4)
	gs.set("forced_pending", ["madness#1"] as Array[String])

	gs.call("end_run")

	var clock: Dictionary = gs.get("madness_clock")
	var counter: int = int(gs.get("_madness_counter"))
	var seen: Dictionary = gs.get("night_locations_seen")
	var chosen: String = str(gs.get("night_location_chosen"))
	var slept: bool = bool(gs.get("night_sleep_pending"))
	var ind_cnt: int = int(gs.get("indulgence_count"))
	var pending: Array = gs.get("forced_pending")

	if clock.is_empty() and counter == 0 and seen.has("n_ahong_1") and chosen.is_empty() and not slept and ind_cnt == 0 and pending.is_empty():
		failed += _ok("end_run 成功清空 madness_clock, _madness_counter, night_location_chosen, night_sleep_pending, indulgence_count, forced_pending，且保留 meta night_locations_seen")
	else:
		failed += _fail("end_run 重置 P2 欄位異常 (clock=%s, counter=%d, seen=%s, chosen=%s, slept=%s, ind_cnt=%d, pending=%s)" % [
			str(clock), counter, str(seen), chosen, str(slept), ind_cnt, str(pending)
		])

	return failed


# ── 10. location_panel failure_text 理由三層優先序 (K-52) ─────────────────────

func _test_failure_text_precedence() -> int:
	print("--- 10. location_panel failure_text precedence (K-52) ---")
	var failed := 0
	var LocationPanelScript: GDScript = load("res://scenes/ui/location_panel.gd") as GDScript
	if LocationPanelScript == null:
		return _fail("無法載入 location_panel.gd")

	# Tier 1: reason_text 非空時優先勝出，不被 _REASON_CODE_TEXTS 覆蓋
	var res1: Dictionary = { "ok": false, "reason_code": "locked", "reason_text": "需要阿宏的工作筆記" }
	var text1: String = LocationPanelScript.failure_text(res1)
	if text1 == "需要阿宏的工作筆記":
		failed += _ok("Tier 1: reason_text 非空時優先採用資料 reject_reason ('需要阿宏的工作筆記')")
	else:
		failed += _fail("Tier 1 失敗: 預期 '需要阿宏的工作筆記'，實際 '%s'" % text1)

	# Tier 2: reason_text 為空時，查表 _REASON_CODE_TEXTS
	var res2: Dictionary = { "ok": false, "reason_code": "not_held", "reason_text": "" }
	var text2: String = LocationPanelScript.failure_text(res2)
	if text2 == "未持有此卡":
		failed += _ok("Tier 2: reason_text 為空時查表成功 ('未持有此卡')")
	else:
		failed += _fail("Tier 2 失敗: 預期 '未持有此卡'，實際 '%s'" % text2)

	var res2_locked: Dictionary = { "ok": false, "reason_code": "locked", "reason_text": "" }
	var text2_locked: String = LocationPanelScript.failure_text(res2_locked)
	if text2_locked == "條件不足":
		failed += _ok("Tier 2: locked 查表成功 ('條件不足')")
	else:
		failed += _fail("Tier 2 失敗: 預期 '條件不足'，實際 '%s'" % text2_locked)

	# Tier 3: reason_text 為空且 reason_code 未在表中，回傳原始 reason_code
	var res3: Dictionary = { "ok": false, "reason_code": "custom_eval_error", "reason_text": "" }
	var text3: String = LocationPanelScript.failure_text(res3)
	if text3 == "custom_eval_error":
		failed += _ok("Tier 3: 未知 reason_code 保留原始碼 ('custom_eval_error')，不為空字串")
	else:
		failed += _fail("Tier 3 失敗: 預期 'custom_eval_error'，實際 '%s'" % text3)

	# Edge: reason_code 與 reason_text 皆為空
	var res4: Dictionary = { "ok": false, "reason_code": "", "reason_text": "" }
	var text4: String = LocationPanelScript.failure_text(res4)
	if text4 == "":
		failed += _ok("Edge: 兩者皆為空時回傳空字串")
	else:
		failed += _fail("Edge 失敗: 預期 ''，實際 '%s'" % text4)

	return failed
