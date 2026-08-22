extends SceneTree

## P3-B headless 驗收測試：
## 進入夜間地點原子入口 enter_night_location（八碼拒絕矩陣、狀態零變化、順序優先序）、
## 首次收費與重進不收、跨輪 meta 保留、撞 cap BE 仍記 seen、would_night_entry_end_run 預判、
## _record_forced_night_visit、night_seen condition 求值、Lint 13 舊旗標退場檢查。

const DataLoader := preload("res://scripts/data_loader.gd")
const ConditionEval := preload("res://scripts/core/condition_eval.gd")
const PlaythroughGreedy := preload("res://tests/headless/playthrough_greedy.gd")

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
		push_error("P3-B: Data failed to load; abort")
		quit(1)
		return

	var failed := 0
	failed += _test_rejection_matrix(gs, data_node)
	failed += _test_too_early_precedence(gs, data_node)
	failed += _test_entry_cost_and_idempotency(gs, data_node)
	failed += _test_meta_persistence_and_serialization(gs, data_node)
	failed += _test_cap_be_seen_retention(gs, data_node)
	failed += _test_would_night_entry_end_run(gs, data_node)
	failed += _test_record_forced_night_visit(gs, data_node)
	failed += _test_night_seen_condition(gs, data_node)
	failed += _test_lint_legacy_night_flags(data_node)

	Engine.unregister_singleton("Data")
	Engine.unregister_singleton("GameState")

	if failed > 0:
		push_error("\nP3-B: %d assertion(s) failed" % failed)
		quit(1)
	else:
		print("\nP3-B: all tests passed")
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
	gs.set("night_location_chosen", "")
	gs.set("night_sleep_pending", false)


# ── 1. 八碼拒絕矩陣與狀態零變化 ─────────────────────────────────────────────

func _test_rejection_matrix(gs: Node, _data_node: Node) -> int:
	print("--- 1. 8-code rejection matrix & zero-state mutation ---")
	var failed := 0

	# 1.1 not_night
	_reset_gs(gs)
	gs.set("day", 6)
	gs.set("phase", "morning")
	var snap_before := (gs.call("serialize") as Dictionary).duplicate(true)
	var res1: Dictionary = gs.call("enter_night_location", "n_ahong_1")
	var snap_after := (gs.call("serialize") as Dictionary).duplicate(true)
	if not bool(res1.get("ok", true)) and str(res1.get("reason_code", "")) == "not_night":
		failed += _ok("1. not_night: 非夜間時段拒絕成功")
	else:
		failed += _fail("1. not_night 失敗: %s" % str(res1))
	if snap_before == snap_after:
		failed += _ok("1. not_night: 拒絕後狀態零變化")
	else:
		failed += _fail("1. not_night 造成狀態變異")

	# 1.2 unknown_location
	_reset_gs(gs)
	gs.set("day", 6)
	gs.set("phase", "night")
	snap_before = (gs.call("serialize") as Dictionary).duplicate(true)
	var res2: Dictionary = gs.call("enter_night_location", "n_nonexistent_loc")
	snap_after = (gs.call("serialize") as Dictionary).duplicate(true)
	if not bool(res2.get("ok", true)) and str(res2.get("reason_code", "")) == "unknown_location":
		failed += _ok("2. unknown_location: 未知地點拒絕成功")
	else:
		failed += _fail("2. unknown_location 失敗: %s" % str(res2))
	if snap_before == snap_after:
		failed += _ok("2. unknown_location: 拒絕後狀態零變化")
	else:
		failed += _fail("2. unknown_location 造成狀態變異")

	# 1.3 not_night_layer
	_reset_gs(gs)
	gs.set("day", 6)
	gs.set("phase", "night")
	snap_before = (gs.call("serialize") as Dictionary).duplicate(true)
	var res3: Dictionary = gs.call("enter_night_location", "temple")
	snap_after = (gs.call("serialize") as Dictionary).duplicate(true)
	if not bool(res3.get("ok", true)) and str(res3.get("reason_code", "")) == "not_night_layer":
		failed += _ok("3. not_night_layer: 白天地點於夜間拒絕成功")
	else:
		failed += _fail("3. not_night_layer 失敗: %s" % str(res3))
	if snap_before == snap_after:
		failed += _ok("3. not_night_layer: 拒絕後狀態零變化")
	else:
		failed += _fail("3. not_night_layer 造成狀態變異")

	# 1.4 teaser
	_reset_gs(gs)
	gs.set("day", 45)
	gs.set("phase", "night")
	snap_before = (gs.call("serialize") as Dictionary).duplicate(true)
	var res4: Dictionary = gs.call("enter_night_location", "n_corridor_end")
	snap_after = (gs.call("serialize") as Dictionary).duplicate(true)
	if not bool(res4.get("ok", true)) and str(res4.get("reason_code", "")) == "teaser":
		failed += _ok("4. teaser: teaser_only 地點拒絕成功")
	else:
		failed += _fail("4. teaser 失敗: %s" % str(res4))
	if snap_before == snap_after:
		failed += _ok("4. teaser: 拒絕後狀態零變化")
	else:
		failed += _fail("4. teaser 造成狀態變異")

	# 1.5 too_early
	_reset_gs(gs)
	gs.set("day", 6)
	gs.set("phase", "night")
	snap_before = (gs.call("serialize") as Dictionary).duplicate(true)
	var res5: Dictionary = gs.call("enter_night_location", "n_ahong_2") # earliest_night: 11
	snap_after = (gs.call("serialize") as Dictionary).duplicate(true)
	if not bool(res5.get("ok", true)) and str(res5.get("reason_code", "")) == "too_early":
		failed += _ok("5. too_early: 未達 earliest_night 地點拒絕成功")
	else:
		failed += _fail("5. too_early 失敗: %s" % str(res5))
	if snap_before == snap_after:
		failed += _ok("5. too_early: 拒絕後狀態零變化")
	else:
		failed += _fail("5. too_early 造成狀態變異")

	# 1.6 locked
	_reset_gs(gs)
	gs.set("day", 11)
	gs.set("phase", "night")
	# 未見過 n_ahong_1
	snap_before = (gs.call("serialize") as Dictionary).duplicate(true)
	var res6: Dictionary = gs.call("enter_night_location", "n_ahong_2")
	snap_after = (gs.call("serialize") as Dictionary).duplicate(true)
	if not bool(res6.get("ok", true)) and str(res6.get("reason_code", "")) == "locked" and str(res6.get("reason_text", "")) == "你還沒跟完上一段痕跡。":
		failed += _ok("6. locked: 門檻未達成拒絕成功並附 reject_reason")
	else:
		failed += _fail("6. locked 失敗: %s" % str(res6))
	if snap_before == snap_after:
		failed += _ok("6. locked: 拒絕後狀態零變化")
	else:
		failed += _fail("6. locked 造成狀態變異")

	# 1.7 already_chosen
	_reset_gs(gs)
	gs.set("day", 6)
	gs.set("phase", "night")
	var entry_ok: Dictionary = gs.call("enter_night_location", "n_ahong_1")
	if not bool(entry_ok.get("ok", false)):
		return failed + _fail("進入 n_ahong_1 失敗")
	snap_before = (gs.call("serialize") as Dictionary).duplicate(true)
	var res7: Dictionary = gs.call("enter_night_location", "n_woodtags")
	snap_after = (gs.call("serialize") as Dictionary).duplicate(true)
	if not bool(res7.get("ok", true)) and str(res7.get("reason_code", "")) == "already_chosen":
		failed += _ok("7. already_chosen: 當夜已選地點後拒絕進入第二個地點")
	else:
		failed += _fail("7. already_chosen 失敗: %s" % str(res7))
	if snap_before == snap_after:
		failed += _ok("7. already_chosen: 拒絕後狀態零變化")
	else:
		failed += _fail("7. already_chosen 造成狀態變異")

	# 1.8 already_slept
	_reset_gs(gs)
	gs.set("day", 6)
	gs.set("phase", "night")
	gs.set("night_sleep_pending", true)
	snap_before = (gs.call("serialize") as Dictionary).duplicate(true)
	var res8: Dictionary = gs.call("enter_night_location", "n_ahong_1")
	snap_after = (gs.call("serialize") as Dictionary).duplicate(true)
	if not bool(res8.get("ok", true)) and str(res8.get("reason_code", "")) == "already_slept":
		failed += _ok("8. already_slept: 當夜已就寢後拒絕進入地點")
	else:
		failed += _fail("8. already_slept 失敗: %s" % str(res8))
	if snap_before == snap_after:
		failed += _ok("8. already_slept: 拒絕後狀態零變化")
	else:
		failed += _fail("8. already_slept 造成狀態變異")

	return failed


# ── 2. too_early vs locked 順序優先序 ────────────────────────────────────────

func _test_too_early_precedence(gs: Node, _data_node: Node) -> int:
	print("--- 2. too_early vs locked precedence ---")
	var failed := 0
	_reset_gs(gs)

	# 第 6 夜：n_ahong_2（earliest_night: 11，requires: night_seen: n_ahong_1）
	# 此時既未到 earliest_night (too_early)，也未滿足 requires (locked)
	gs.set("day", 6)
	gs.set("phase", "night")

	var res: Dictionary = gs.call("enter_night_location", "n_ahong_2")
	if str(res.get("reason_code", "")) == "too_early":
		failed += _ok("同時符合 too_early 與 locked 時，依順序優先回傳 too_early")
	else:
		failed += _fail("too_early vs locked 優先序不符 (實際: %s)" % str(res))

	return failed


# ── 3. 首次收費、重進不收與免費地點 ──────────────────────────────────────────

func _test_entry_cost_and_idempotency(gs: Node, _data_node: Node) -> int:
	print("--- 3. cost deduction, idempotency & free locations ---")
	var failed := 0
	_reset_gs(gs)

	gs.set("day", 6)
	gs.set("phase", "night")

	# 首次進入收費地點 n_ahong_1 (madness_cost: 1)
	var res1: Dictionary = gs.call("enter_night_location", "n_ahong_1")
	var lines1: PackedStringArray = res1.get("lines", PackedStringArray())
	var hand1: Array = gs.get("hand")
	var chosen1: String = str(gs.get("night_location_chosen"))
	var seen1: Dictionary = gs.get("night_locations_seen")

	if bool(res1.get("ok", false)) and lines1.size() > 0 and lines1[0].contains("發狂卡") and hand1.has("madness#1") and chosen1 == "n_ahong_1" and bool(seen1.get("n_ahong_1", false)):
		failed += _ok("首次進入收費地點回傳文字、發放發狂卡、記錄 chosen 與 meta seen")
	else:
		failed += _fail("首次進入收費地點狀態異常: res=%s, hand=%s, chosen=%s, seen=%s" % [str(res1), str(hand1), chosen1, str(seen1)])

	# 跨日到第 7 夜再次進入 n_ahong_1 (重進)
	gs.call("advance_phase") # D7 morning
	gs.call("advance_phase") # D7 afternoon
	gs.call("advance_phase") # D7 evening
	gs.call("advance_phase") # D7 night

	var res2: Dictionary = gs.call("enter_night_location", "n_ahong_1")
	var lines2: PackedStringArray = res2.get("lines", PackedStringArray())
	var hand2: Array = gs.get("hand")
	var chosen2: String = str(gs.get("night_location_chosen"))

	if bool(res2.get("ok", false)) and lines2.is_empty() and hand2.size() == hand1.size() and chosen2 == "n_ahong_1":
		failed += _ok("再次進入已 seen 收費地點回傳 ok:true、空文字行且不重複扣費/發卡")
	else:
		failed += _fail("重複進入收費地點狀態異常: res=%s, lines=%s, hand=%s, chosen=%s" % [str(res2), str(lines2), str(hand2), chosen2])

	# 免費地點 n_woodtags (madness_cost: 0)
	_reset_gs(gs)
	gs.set("day", 6)
	gs.set("phase", "night")

	var res_free: Dictionary = gs.call("enter_night_location", "n_woodtags")
	var lines_free: PackedStringArray = res_free.get("lines", PackedStringArray())
	var hand_free: Array = gs.get("hand")
	var seen_free: Dictionary = gs.get("night_locations_seen")

	if bool(res_free.get("ok", false)) and lines_free.is_empty() and hand_free == ["protagonist"] and bool(seen_free.get("n_woodtags", false)):
		failed += _ok("進入免費地點不發卡、回傳空文字行、記錄 meta seen 且成功進入")
	else:
		failed += _fail("免費地點進入狀態異常: res=%s, lines=%s, hand=%s, seen=%s" % [str(res_free), str(lines_free), str(hand_free), str(seen_free)])

	return failed


# ── 4. 跨輪保留與序列化往返 ──────────────────────────────────────────────────

func _test_meta_persistence_and_serialization(gs: Node, _data_node: Node) -> int:
	print("--- 4. meta persistence across end_run & serialization roundtrip ---")
	var failed := 0
	_reset_gs(gs)

	gs.set("day", 14)
	gs.set("phase", "night")
	gs.call("enter_night_location", "n_ahong_1")

	# end_run 重置 run 層但保留 meta
	gs.call("end_run")

	var seen_after: Dictionary = gs.get("night_locations_seen")
	var chosen_after: String = str(gs.get("night_location_chosen"))
	var slept_after: bool = bool(gs.get("night_sleep_pending"))

	if bool(seen_after.get("n_ahong_1", false)) and chosen_after.is_empty() and not slept_after:
		failed += _ok("end_run 後 meta night_locations_seen 保留，run 層 chosen 與 sleep_pending 清空")
	else:
		failed += _fail("end_run meta/run 分離異常 (seen=%s, chosen=%s, slept=%s)" % [str(seen_after), chosen_after, str(slept_after)])

	# 序列化往返
	gs.set("day", 8)
	gs.set("phase", "night")
	gs.set("night_locations_seen", { "n_ahong_1": true, "n_source": true })
	gs.set("night_once_beats_seen", { "beat_test_once": true })
	gs.set("night_location_chosen", "n_source")
	gs.set("night_sleep_pending", true)

	var saved: Dictionary = gs.call("serialize")

	_reset_gs(gs)
	gs.call("deserialize", saved)

	var res_seen: Dictionary = gs.get("night_locations_seen")
	var res_once: Dictionary = gs.get("night_once_beats_seen")
	var res_chosen: String = str(gs.get("night_location_chosen"))
	var res_slept: bool = bool(gs.get("night_sleep_pending"))

	if res_seen.has("n_ahong_1") and res_seen.has("n_source") and res_once.has("beat_test_once") and res_chosen == "n_source" and res_slept:
		failed += _ok("serialize / deserialize 完整還原 meta (seen/once) 與 run (chosen/sleep_pending)")
	else:
		failed += _fail("序列化還原異常: seen=%s, once=%s, chosen=%s, slept=%s" % [str(res_seen), str(res_once), res_chosen, str(res_slept)])

	return failed


# ── 5. 撞 Cap BE 仍記 seen ──────────────────────────────────────────────────

func _test_cap_be_seen_retention(gs: Node, _data_node: Node) -> int:
	print("--- 5. cap BE retains seen location in meta ---")
	var failed := 0
	_reset_gs(gs)

	# 手上塞滿 6 張發狂卡（tuning madness_cap = 7）
	for i in range(6):
		gs.call("gain_card", "madness")
	gs.set("day", 7)
	gs.set("phase", "night")

	var emitted_endings: Array[String] = []
	var on_run_ended := func(eid: String) -> void:
		emitted_endings.append(eid)
	gs.connect("run_ended", on_run_ended)

	# 進入 cost=1 的收費地點 n_source -> 湊齊 7 張觸發 ending_madness_be
	var res: Dictionary = gs.call("enter_night_location", "n_source")

	var day_after: int = int(gs.get("day"))
	var phase_after: String = str(gs.get("phase"))
	var seen_after: Dictionary = gs.get("night_locations_seen")

	if emitted_endings == ["ending_madness_be"] and day_after == 1 and phase_after == "morning" and bool(seen_after.get("n_source", false)):
		failed += _ok("進入地點撞 cap 觸發發瘋 BE，回到第 1 天 morning 且 meta night_locations_seen 仍記錄 n_source")
	else:
		failed += _fail("撞 cap BE 狀態異常: endings=%s, day=%d, phase=%s, seen=%s" % [str(emitted_endings), day_after, phase_after, str(seen_after)])

	# BE 發生時不回傳 marker 文字行
	if (res.get("lines", PackedStringArray()) as PackedStringArray).is_empty():
		failed += _ok("撞 cap 結束本輪時不回傳 marker 提示文字行")
	else:
		failed += _fail("撞 cap 時不應回傳提示文字 (lines: %s)" % str(res.get("lines")))

	gs.disconnect("run_ended", on_run_ended)
	return failed


# ── 6. would_night_entry_end_run 預判 ────────────────────────────────────────

func _test_would_night_entry_end_run(gs: Node, _data_node: Node) -> int:
	print("--- 6. would_night_entry_end_run query ---")
	var failed := 0
	_reset_gs(gs)

	# 0 張發狂卡時進入 n_ahong_1 (cost 1) 不會 BE
	gs.set("day", 6)
	gs.set("phase", "night")
	if not bool(gs.call("would_night_entry_end_run", "n_ahong_1")):
		failed += _ok("0 張發狂卡時預判進入 n_ahong_1 不會 BE (false)")
	else:
		failed += _fail("0 張發狂卡時預判錯誤")

	# 手上 6 張發狂卡時預判進入 n_ahong_1 (cost 1) 會 BE
	for i in range(6):
		gs.call("gain_card", "madness")
	if bool(gs.call("would_night_entry_end_run", "n_ahong_1")):
		failed += _ok("6 張發狂卡時預判進入未到訪 n_ahong_1 會觸發 BE (true)")
	else:
		failed += _fail("6 張發狂卡時預判錯誤")

	# 若該地點已經 seen，再次進入 cost 為 0，不會 BE
	gs.set("night_locations_seen", { "n_ahong_1": true })
	if not bool(gs.call("would_night_entry_end_run", "n_ahong_1")):
		failed += _ok("已到訪地點再次進入 cost 為 0，預判不會 BE (false)")
	else:
		failed += _fail("已到訪地點預判錯誤")

	# 免費地點預判不會 BE
	if not bool(gs.call("would_night_entry_end_run", "n_woodtags")):
		failed += _ok("免費地點預判不會 BE (false)")
	else:
		failed += _fail("免費地點預判錯誤")

	return failed


# ── 7. _record_forced_night_visit 私有 helper ────────────────────────────────

func _test_record_forced_night_visit(gs: Node, _data_node: Node) -> int:
	print("--- 7. _record_forced_night_visit helper ---")
	var failed := 0
	_reset_gs(gs)

	gs.set("day", 1)
	gs.set("phase", "night")

	gs.call("_record_forced_night_visit", "n_corridor")

	var chosen: String = str(gs.get("night_location_chosen"))
	var seen: Dictionary = gs.get("night_locations_seen")
	var hand: Array = gs.get("hand")

	if chosen == "n_corridor" and bool(seen.get("n_corridor", false)) and hand == ["protagonist"]:
		failed += _ok("_record_forced_night_visit 成功寫入 chosen 與 seen，且跳過收費發卡")
	else:
		failed += _fail("_record_forced_night_visit 狀態異常 (chosen=%s, seen=%s, hand=%s)" % [chosen, str(seen), str(hand)])

	return failed


# ── 8. night_seen Condition 求值 ────────────────────────────────────────────

func _test_night_seen_condition(gs: Node, _data_node: Node) -> int:
	print("--- 8. night_seen condition evaluation ---")
	var failed := 0
	_reset_gs(gs)

	var cond: Dictionary = { "night_seen": "n_ahong_1" }
	if not ConditionEval.eval(cond, gs):
		failed += _ok("未到訪 n_ahong_1 時 night_seen 條件求值為 false")
	else:
		failed += _fail("未到訪時 night_seen 應為 false")

	gs.set("night_locations_seen", { "n_ahong_1": true })
	if ConditionEval.eval(cond, gs):
		failed += _ok("到訪 n_ahong_1 後 night_seen 條件求值為 true")
	else:
		failed += _fail("到訪後 night_seen 應為 true")

	return failed


# ── 9. Lint 13 舊夜間旗標退場檢查 ───────────────────────────────────────────

func _test_lint_legacy_night_flags(data_node: Node) -> int:
	print("--- 9. Lint 13 legacy night flags check ---")
	var failed := 0

	# 9.1 正向：正式資料庫零錯誤
	var clean_errs: PackedStringArray = DataLoader.lint_legacy_night_flags(data_node.loader)
	if clean_errs.is_empty():
		failed += _ok("正式資料庫通過 Lint 13 舊旗標檢查（0 錯誤）")
	else:
		failed += _fail("正式資料庫含有舊夜間旗標: %s" % str(clean_errs))

	# 9.2 負向：含 opened_n_ 的 key 或 value 被攔截
	var mock_loader := DataLoader.new()
	mock_loader.locations = {
		"test_loc": {
			"id": "test_loc",
			"requires": { "flag": "opened_n_bad_flag" }
		}
	}
	mock_loader.beats = [
		{
			"id": "test_beat",
			"on_enter": { "flag": { "opened_n_other": true } }
		}
	]

	var bad_errs: PackedStringArray = DataLoader.lint_legacy_night_flags(mock_loader)
	if bad_errs.size() == 2:
		failed += _ok("負向 fixture: location 與 beat 中的 opened_n_* 均被 Lint 13 成功攔截（2 筆錯誤）")
	else:
		failed += _fail("負向 fixture 攔截數量不符 (實際 %d 筆: %s)" % [bad_errs.size(), str(bad_errs)])

	return failed
