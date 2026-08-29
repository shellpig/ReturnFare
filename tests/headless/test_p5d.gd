extends SceneTree

## P5-D 開局、歷輪摘要與跨輪重置測試（實作規格書 P5-D、測試指南 P5-D）。
## 涵蓋：opening view 順序與鎖定、相簿／電話／不上車三條開局路徑、
## `complete_ending()` 的固定順序與 history 封閉欄位集合、跨輪重置逐欄稽核、
## `loop_persistent` 合成 fixture 的取得／恢復／永久失去、
## D29 逾期預設三路等價與慶典代付者凍結、`advance_phase()` 七步固定順序逐層反證、
## `choice_requires_card` 回歸與第二輪重入。
## 跑法：Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/test_p5d.gd

const PlaythroughGreedy := preload("res://tests/headless/playthrough_greedy.gd")

const OPENING_ORDER := ["take_family_album", "return_missed_call", "refuse_boarding"]
const HISTORY_KEYS := [
	"run_number", "ending_id", "opening_choice_id", "ended_day", "ended_phase",
	"partner_variant", "livelihood_variant", "inn_appearance_variant",
	"festival_proxy_npc", "knowledge_gained_this_run",
]

var _failed := 0


func _initialize() -> void:
	var data_node: Node = PlaythroughGreedy.setup_data(self)
	await process_frame
	var gs: Node = PlaythroughGreedy.setup_game_state(self, data_node)

	if not bool(data_node.get("ok")):
		push_error("P5-D: Data 載入失敗，中止")
		quit(1)
		return

	print("=== P5-D 開局、歷輪摘要與跨輪重置測試 ===")
	_test_1_opening_view_and_lock(gs)
	_test_2_opening_run_initialization(gs)
	_test_3_opening_idempotence_and_preview(gs)
	_test_4_complete_ending_history(gs, data_node)
	_test_5_knowledge_gained_freeze(gs)
	_test_6_refuse_boarding_unlock(gs)
	_test_7_refuse_boarding_lifecycle(gs)
	_test_8_cross_run_reset_audit(gs)
	_test_9_loop_persistent_fixture(gs, data_node)
	_test_10_d29_three_paths(gs, data_node)
	_test_11_d29_conflict_and_frozen_reads(gs, data_node)
	_test_12_advance_phase_order(gs, data_node)
	_test_13_advance_phase_success_shapes(gs)
	_test_14_card_required_regression(gs)
	_test_15_reject_matrix(gs)
	_test_16_second_run_reentry(gs)

	if _failed > 0:
		push_error("test_p5d: %d 個斷言失敗" % _failed)
		quit(1)
	else:
		print("\n=== P5-D 全部測試通過 ===")
		quit(0)


# ── 共用工具 ─────────────────────────────────────────────────────────────────

func _ok(msg: String) -> void:
	print("  ok  " + msg)


func _fail(msg: String) -> void:
	push_error("  FAIL  " + msg)
	_failed += 1


func _check(cond: bool, msg: String) -> void:
	if cond:
		_ok(msg)
	else:
		_fail(msg)


func _state_text(gs: Node) -> String:
	return JSON.stringify(gs.call("serialize"))


func _reject_code(res: Dictionary) -> String:
	if bool(res.get("ok", false)):
		return "<ok>"
	return str(res.get("reason_code", ""))


## 把整個 meta 層也洗乾淨，回到「第一次開機」的狀態。
func _fresh_opening(gs: Node) -> void:
	gs.call("_reset_run_state")
	(gs.get("active_ending") as Dictionary).clear()
	gs.set("flow_mode", "opening")
	gs.set("run_number", 1)
	gs.set("ending_history", [] as Array[Dictionary])
	(gs.get("knowledge") as Dictionary).clear()
	(gs.get("night_locations_seen") as Dictionary).clear()
	(gs.get("night_once_beats_seen") as Dictionary).clear()
	(gs.get("loop_persistent_item_ids") as Dictionary).clear()
	gs.set("delegation_tutorial_seen", false)


## 起一輪乾淨的 run 並排到指定時段（不經開局選項）。
func _fresh_run(gs: Node, day: int = 45, phase: String = "evening") -> void:
	_fresh_opening(gs)
	PlaythroughGreedy.start_fresh_run(gs)
	gs.set("day", day)
	gs.set("phase", phase)


## 逐頁播完當前結局後正式結算。回傳 complete_ending() 的結果。
func _play_out_and_complete(gs: Node) -> Dictionary:
	var guard := 200
	while guard > 0:
		guard -= 1
		var view: Dictionary = gs.call("ending_view")
		if view.is_empty():
			return { "ok": false, "reason_code": "no_active_ending" }
		if bool(view.get("can_complete", false)):
			return gs.call("complete_ending")
		if not bool(view.get("page_revealed", false)):
			gs.call("reveal_ending_page")
		else:
			gs.call("advance_ending_page")
	return { "ok": false, "reason_code": "page_guard_exhausted" }


func _find_slot(loader: DataLoader, beat_id: String, slot_id: String) -> Dictionary:
	var beat: Dictionary = loader.beats_by_id.get(beat_id, {}) as Dictionary
	for slot: Dictionary in beat.get("slots", []) as Array:
		if str(slot.get("id", "")) == slot_id:
			return slot
	return {}


# ── 1. opening view 順序、鎖定理由與直接確認 ─────────────────────────────────

func _test_1_opening_view_and_lock(gs: Node) -> void:
	print("\n--- 1. opening view 順序與鎖定 ---")
	_fresh_opening(gs)

	var view: Array = gs.call("opening_view")
	var ids: Array[String] = []
	for row: Dictionary in view:
		ids.append(str(row.get("id", "")))
	_check(ids == OPENING_ORDER,
		"opening view 永遠按相簿、電話、不上的資料順序（實際：%s）" % str(ids))

	_check(bool((view[0] as Dictionary).get("available", false)) and bool((view[1] as Dictionary).get("available", false)),
		"首輪相簿與電話皆可選")
	var refuse: Dictionary = view[2] as Dictionary
	_check(not bool(refuse.get("available", true)), "首輪不上車 available:false")
	_check(str(refuse.get("reason_text", "")) == "你還沒有理由放棄這趟路。", "鎖定理由取自資料且不劇透")

	for row: Dictionary in view:
		for leaked: String in ["requires", "on_select", "ending", "condition"]:
			_check(not (row as Dictionary).has(leaked), "opening view 不洩漏 %s（%s）" % [leaked, str(row.get("id", ""))])

	var before := _state_text(gs)
	var locked_res: Dictionary = gs.call("choose_opening", "refuse_boarding")
	_check(_reject_code(locked_res) == "opening_choice_locked", "直接確認 locked choice → opening_choice_locked")
	_check(_state_text(gs) == before, "locked 拒絕後序列化零變化")


# ── 2. 相簿／電話兩條開局的 run 初始化 ───────────────────────────────────────

func _test_2_opening_run_initialization(gs: Node) -> void:
	print("\n--- 2. 相簿／電話開局初始化 ---")

	_fresh_opening(gs)
	var album: Dictionary = gs.call("choose_opening", "take_family_album")
	_check(bool(album.get("ok", false)), "相簿開局成功")
	_check(str(gs.get("flow_mode")) == "run", "相簿開局後進入 run mode")
	var hand_album: Array = gs.get("hand") as Array
	_check(hand_album.size() == 2 and hand_album[0] == "protagonist" and hand_album[1] == "item_family_album",
		"相簿 run 的 hand index 0 為主角卡且含 item_family_album（實際：%s）" % str(hand_album))
	_check(str(gs.get("opening_choice_id")) == "take_family_album", "opening_choice_id 正確")
	_check(int(gs.get("day")) == 1 and str(gs.get("phase")) == "morning", "相簿 run 從 D1 morning 開始")
	_check(not bool((gs.get("flags") as Dictionary).get("outside_job_waiting", false)), "相簿 run 不寫 outside_job_waiting")

	_fresh_opening(gs)
	var phone: Dictionary = gs.call("choose_opening", "return_missed_call")
	_check(bool(phone.get("ok", false)), "電話開局成功")
	var hand_phone: Array = gs.get("hand") as Array
	_check(hand_phone.size() == 1 and hand_phone[0] == "protagonist",
		"電話 run 的 hand 只有主角卡，不含相簿（實際：%s）" % str(hand_phone))
	_check(bool((gs.get("flags") as Dictionary).get("outside_job_waiting", false)), "電話 run 寫入 outside_job_waiting")
	_check(str(gs.get("opening_choice_id")) == "return_missed_call", "opening_choice_id 正確")
	_check(int(gs.get("day")) == 1 and str(gs.get("phase")) == "morning", "電話 run 從 D1 morning 開始")


# ── 3. 預覽零變化與重複確認 ─────────────────────────────────────────────────

func _test_3_opening_idempotence_and_preview(gs: Node) -> void:
	print("\n--- 3. opening 預覽零變化與重複確認 ---")

	_fresh_opening(gs)
	var before := _state_text(gs)
	gs.call("opening_view")
	gs.call("opening_view")
	_check(_state_text(gs) == before, "opening_view 預覽／取消不呼叫任何 mutation")

	var first: Dictionary = gs.call("choose_opening", "take_family_album")
	_check(bool(first.get("ok", false)), "第一次確認相簿進 run")
	var after_first := _state_text(gs)
	var second: Dictionary = gs.call("choose_opening", "take_family_album")
	_check(_reject_code(second) == "not_opening", "同一 choice 第二次確認 → not_opening")
	_check(_state_text(gs) == after_first, "第二次確認零變化：不重複發卡、不重複套 flag")


# ── 4. 四類 ending 各完成一次：history 欄位、結算順序與冪等 ───────────────────

func _test_4_complete_ending_history(gs: Node, data_node: Node) -> void:
	print("\n--- 4. 四類 ending 完成一次的 history 與結算 ---")
	var loader: DataLoader = data_node.get("loader") as DataLoader

	var run_cases := [
		{ "id": "ending_replaced", "source": "d45_coda", "proxy": "ajie", "variants": true },
		{ "id": "ending_madness_be", "source": "madness_cap", "proxy": "", "variants": false },
		{ "id": "ending_inventory_be", "source": "ending_effect", "proxy": "", "variants": false },
	]

	for c: Dictionary in run_cases:
		var eid := str(c["id"])
		_fresh_opening(gs)
		gs.call("choose_opening", "take_family_album")
		gs.set("day", 45)
		gs.set("phase", "evening")
		if not str(c["proxy"]).is_empty():
			gs.set("selected_festival_proxy_npc", str(c["proxy"]))
		gs.call("gain_card", "k_forty_something")

		_check(bool((gs.call("start_ending", eid, str(c["source"])) as Dictionary).get("ok", false)),
			"%s 啟動成功" % eid)
		var res := _play_out_and_complete(gs)
		_check(bool(res.get("ok", false)), "%s 完成結算成功" % eid)

		var history: Array = gs.get("ending_history") as Array
		_check(history.size() == 1, "%s 完成後 history 恰 append 一筆" % eid)
		var record: Dictionary = history[0] as Dictionary
		var keys := record.keys()
		keys.sort()
		var expected := HISTORY_KEYS.duplicate()
		expected.sort()
		_check(keys == expected, "%s history 欄位集合精確（實際：%s）" % [eid, str(keys)])
		_check(str(record.get("ending_id", "")) == eid, "%s history ending_id 正確" % eid)
		_check(str(record.get("opening_choice_id", "")) == "take_family_album", "%s history 記下開局選項" % eid)
		_check(int(record.get("ended_day", 0)) == 45 and str(record.get("ended_phase", "")) == "evening",
			"%s history 記下結束時段" % eid)
		if bool(c["variants"]):
			for key: String in ["partner_variant", "livelihood_variant", "inn_appearance_variant"]:
				_check(record.get(key) != null, "%s history 的 %s 必填" % [eid, key])
			_check(str(record.get("festival_proxy_npc", "")) == "ajie", "%s history 記下凍結的代付者" % eid)
		else:
			for key: String in ["partner_variant", "livelihood_variant", "inn_appearance_variant"]:
				_check(record.get(key) == null, "%s history 的 %s 為 null" % [eid, key])

		_check(bool(gs.call("has_knowledge", "k_i_returned")), "%s 完成後取得「我回來過」" % eid)
		_check(not (record.get("knowledge_gained_this_run") as Array).has("k_i_returned"),
			"%s history 的當輪知識不含結算時才發的 k_i_returned" % eid)
		_check(int(gs.get("run_number")) == 2, "%s 完成後 run_number 恰加一" % eid)
		_check(str(gs.get("flow_mode")) == "opening", "%s 完成後回到 opening" % eid)
		_check((gs.get("active_ending") as Dictionary).is_empty(), "%s 完成後 active ending 已清空" % eid)
		_check((gs.get("hand") as Array).is_empty() and (gs.get("flags") as Dictionary).is_empty(),
			"%s 完成後 run 層全清" % eid)

		var after_complete := _state_text(gs)
		var retry: Dictionary = gs.call("complete_ending")
		_check(_reject_code(retry) == "not_ending", "%s 重試 complete → not_ending" % eid)
		_check((gs.get("ending_history") as Array).size() == 1, "%s 重試不多一筆 history" % eid)
		_check(_state_text(gs) == after_complete, "%s 重試後序列化零變化" % eid)

	# 不上車：唯一由 opening 私有入口啟動的 ending。
	_fresh_opening(gs)
	(gs.get("ending_history") as Array[Dictionary]).append(_replaced_history_stub())
	_check(bool((gs.call("choose_opening", "refuse_boarding") as Dictionary).get("ok", false)),
		"解鎖後不上車啟動成功")
	_check(bool(_play_out_and_complete(gs).get("ok", false)), "不上車完成結算成功")
	var rb_history: Array = gs.get("ending_history") as Array
	_check(rb_history.size() == 2, "不上車完成後 history 加一")
	var rb_record: Dictionary = rb_history[1] as Dictionary
	_check(str(rb_record.get("ending_id", "")) == "ending_refuse_boarding", "不上車 history ending_id 正確")
	_check(str(rb_record.get("opening_choice_id", "")) == "refuse_boarding", "不上車 history 的開局選項為 refuse_boarding")
	_check(rb_record.get("ended_day") == null and rb_record.get("ended_phase") == null, "不上車 history 的 day／phase 皆為 null")
	_check(rb_record.get("festival_proxy_npc") == null, "不上車 history 的代付者為 null")
	_check((rb_record.get("knowledge_gained_this_run") as Array).is_empty(), "不上車 history 的當輪知識為空")
	_check(loader != null, "loader 可用（保留供後續案例）")


func _replaced_history_stub() -> Dictionary:
	return {
		"run_number": 1, "ending_id": "ending_replaced", "opening_choice_id": "take_family_album",
		"ended_day": 45, "ended_phase": "evening",
		"partner_variant": "none", "livelihood_variant": "none_low", "inn_appearance_variant": "unrepaired",
		"festival_proxy_npc": "ajie", "knowledge_gained_this_run": [] as Array[String],
	}


# ── 5. knowledge_gained_this_run 的凍結範圍 ──────────────────────────────────

func _test_5_knowledge_gained_freeze(gs: Node) -> void:
	print("\n--- 5. 當輪新增知識的凍結範圍 ---")

	_fresh_opening(gs)
	gs.call("choose_opening", "take_family_album")
	gs.call("gain_card", "k_forty_something")   # 第一輪拿到
	gs.set("day", 45)
	gs.set("phase", "evening")
	gs.set("selected_festival_proxy_npc", "ajie")
	gs.call("start_ending", "ending_replaced", "d45_coda")
	_play_out_and_complete(gs)

	var first_gained: Array = ((gs.get("ending_history") as Array)[0] as Dictionary).get("knowledge_gained_this_run") as Array
	_check(first_gained.has("k_forty_something"), "第一輪的 history 含當輪新增的 k_forty_something")

	# 第二輪：上一輪知識已在 knowledge_at_start，不得再算成本輪新增。
	gs.call("choose_opening", "return_missed_call")
	gs.call("gain_card", "k_not_today")
	gs.set("day", 45)
	gs.set("phase", "evening")
	gs.set("selected_festival_proxy_npc", "awei")
	gs.call("start_ending", "ending_replaced", "d45_coda")
	_play_out_and_complete(gs)

	var second_gained: Array = ((gs.get("ending_history") as Array)[1] as Dictionary).get("knowledge_gained_this_run") as Array
	_check(second_gained.has("k_not_today"), "第二輪 history 含本輪新增的 k_not_today")
	_check(not second_gained.has("k_forty_something"), "第二輪 history 不含上一輪的知識")
	_check(not second_gained.has("k_i_returned"), "第二輪 history 不含第一輪結算發的 k_i_returned")


# ── 6. 不上車的解鎖條件只看 ending_replaced history ──────────────────────────

func _test_6_refuse_boarding_unlock(gs: Node) -> void:
	print("\n--- 6. 不上車解鎖條件 ---")

	var locked_cases := [
		{ "label": "只有 k_i_returned", "history": [] as Array[Dictionary], "knowledge": true, "run_number": 9 },
		{ "label": "只有發瘋 BE history", "history": [_history_stub("ending_madness_be")] as Array[Dictionary], "knowledge": false, "run_number": 2 },
		{ "label": "只有庫存 BE history", "history": [_history_stub("ending_inventory_be")] as Array[Dictionary], "knowledge": false, "run_number": 2 },
		{ "label": "高輪數但無正常結局", "history": [] as Array[Dictionary], "knowledge": false, "run_number": 42 },
	]
	for c: Dictionary in locked_cases:
		_fresh_opening(gs)
		gs.set("ending_history", c["history"])
		gs.set("run_number", int(c["run_number"]))
		if bool(c["knowledge"]):
			gs.call("gain_card", "k_i_returned")
		var view: Array = gs.call("opening_view")
		_check(not bool((view[2] as Dictionary).get("available", true)), "%s → 不上車仍鎖定" % str(c["label"]))
		_check(_reject_code(gs.call("choose_opening", "refuse_boarding")) == "opening_choice_locked",
			"%s → 確認不上車回 opening_choice_locked" % str(c["label"]))

	_fresh_opening(gs)
	(gs.get("ending_history") as Array[Dictionary]).append(_replaced_history_stub())
	var unlocked_view: Array = gs.call("opening_view")
	_check(bool((unlocked_view[2] as Dictionary).get("available", false)), "有 ending_replaced history → 不上車解鎖")
	_check(str((unlocked_view[2] as Dictionary).get("reason_text", "x")).is_empty(), "解鎖後不再顯示鎖定理由")


func _history_stub(ending_id: String) -> Dictionary:
	var record := _replaced_history_stub()
	record["ending_id"] = ending_id
	record["partner_variant"] = null
	record["livelihood_variant"] = null
	record["inn_appearance_variant"] = null
	return record


# ── 7. 不上車不建立 run ─────────────────────────────────────────────────────

func _test_7_refuse_boarding_lifecycle(gs: Node) -> void:
	print("\n--- 7. 不上車不建立 run ---")

	_fresh_opening(gs)
	(gs.get("ending_history") as Array[Dictionary]).append(_replaced_history_stub())
	var res: Dictionary = gs.call("choose_opening", "refuse_boarding")
	_check(bool(res.get("ok", false)), "解鎖後不上車直接進 ending")
	_check(str(gs.get("flow_mode")) == "ending", "不上車後 mode 為 ending")
	_check((gs.get("hand") as Array).is_empty(), "不上車不發主角卡")
	_check(str(gs.get("opening_choice_id")).is_empty(), "不上車不寫 run 的 opening_choice_id")
	_check(int(gs.get("day")) == 1 and str(gs.get("phase")) == "morning", "不上車不推進 day／phase")
	_check(str((gs.get("active_ending") as Dictionary).get("ending_id", "")) == "ending_refuse_boarding",
		"啟動的是 ending_refuse_boarding")

	_check(bool(_play_out_and_complete(gs).get("ok", false)), "不上車完成結算")
	_check((gs.get("ending_history") as Array).size() == 2, "不上車完成後 history 加一")
	_check(int(gs.get("run_number")) == 2, "不上車完成後 run_number 加一")
	_check(str(gs.get("flow_mode")) == "opening", "不上車完成後回 opening")


# ── 8. 跨輪重置逐欄稽核 ─────────────────────────────────────────────────────

func _test_8_cross_run_reset_audit(gs: Node) -> void:
	print("\n--- 8. 跨輪重置逐欄稽核 ---")

	_fresh_opening(gs)
	gs.call("choose_opening", "take_family_album")

	# 塞滿 P1～P4 的 run 層狀態
	gs.set("day", 45)
	gs.set("phase", "evening")
	gs.set("action_spent", true)
	gs.set("_actions_spent_ahead", 1)
	gs.call("gain_card", "madness", false)
	gs.call("gain_card", "info_registry")
	(gs.get("beats_entered") as Dictionary)["d1_arrival"] = true
	(gs.get("slots_placed") as Dictionary)["d45_then::compare_registry"] = true
	(gs.get("choices") as Dictionary)["d45_then::d45_coda"] = "compare_registry"
	(gs.get("flags") as Dictionary)["final_day"] = true
	(gs.get("switches") as Dictionary)["s1"] = true
	(gs.get("switch_progress") as Dictionary)["s6"] = 2
	(gs.get("relations") as Dictionary)["ajie"] = 5
	(gs.get("npc_action_counts") as Dictionary)["ajie"] = 3
	gs.set("night_location_chosen", "n_source")
	gs.set("night_sleep_pending", true)
	gs.set("indulgence_count", 4)
	gs.set("madness_cards_cleared", 2)
	(gs.get("forced_pending") as Array).append("madness#1")
	(gs.get("delegates_used_today") as Dictionary)["npc_ajie"] = true
	(gs.get("pending_delegation_reports") as Array).append({ "due_day": 46, "beat_id": "x", "slot_id": "y", "person_id": "npc_ajie" })
	gs.set("selected_festival_proxy_npc", "ajie")

	# meta 層先立起來，等一下要驗它們沒被清掉
	gs.call("gain_card", "k_forty_something")
	(gs.get("night_locations_seen") as Dictionary)["n_source"] = true
	(gs.get("night_once_beats_seen") as Dictionary)["n_manydoors_ch1"] = true
	gs.call("mark_delegation_tutorial_seen")

	gs.call("start_ending", "ending_replaced", "d45_coda")
	_check(bool(_play_out_and_complete(gs).get("ok", false)), "塞滿狀態後仍能完成結局")

	var run_state := gs.call("serialize").get("run", {}) as Dictionary
	_check(int(run_state.get("day", 0)) == 1 and str(run_state.get("phase", "")) == "morning", "重置後回到 D1 morning")
	_check(not bool(run_state.get("action_spent", true)) and int(run_state.get("actions_spent_ahead", 1)) == 0,
		"重置後行動格狀態歸零")
	_check((run_state.get("hand") as Array).is_empty(), "重置後普通手牌全清")
	_check((run_state.get("madness_clock") as Dictionary).is_empty() and int(run_state.get("_madness_counter", 1)) == 0,
		"重置後發狂錶與實例計數歸零")
	for key: String in ["beats_entered", "slots_placed", "choices", "flags", "switches", "switch_progress",
			"relations", "npc_action_counts", "delegates_used_today", "active_encounter", "knowledge_at_start"]:
		_check((run_state.get(key) as Dictionary).is_empty(), "重置後 %s 全清" % key)
	for key: String in ["forced_pending", "pending_delegation_reports"]:
		_check((run_state.get(key) as Array).is_empty(), "重置後 %s 全清" % key)
	_check(str(run_state.get("night_location_chosen", "x")).is_empty() and not bool(run_state.get("night_sleep_pending", true)),
		"重置後夜間暫態全清")
	_check(int(run_state.get("indulgence_count", 1)) == 0 and int(run_state.get("madness_cards_cleared", 1)) == 0,
		"重置後縱慾計數全清")
	_check(run_state.get("opening_choice_id") == null and run_state.get("selected_festival_proxy_npc") == null,
		"重置後開局選項與代付者回到 null")

	var meta_state := gs.call("serialize").get("meta", {}) as Dictionary
	_check((meta_state.get("knowledge") as Dictionary).has("k_forty_something"), "meta knowledge 保留")
	_check((meta_state.get("night_locations_seen") as Dictionary).has("n_source"), "meta night seen 保留")
	_check((meta_state.get("night_once_beats_seen") as Dictionary).has("n_manydoors_ch1"), "meta 夜間一次性 beat 保留")
	_check(bool(meta_state.get("delegation_tutorial_seen", false)), "meta 委託教學保留")
	_check((meta_state.get("ending_history") as Array).size() == 1, "meta 歷輪摘要保留")


# ── 9. loop_persistent 合成 fixture ─────────────────────────────────────────

func _test_9_loop_persistent_fixture(gs: Node, data_node: Node) -> void:
	print("\n--- 9. 跨輪魔法物品（合成 fixture）---")
	var loader: DataLoader = data_node.get("loader") as DataLoader

	var magic_id := "p5d_item_magic"
	var plain_id := "p5d_item_plain"
	loader.cards[magic_id] = {
		"id": magic_id, "name": "測試魔法物品", "type": "equipment",
		"slotless": false, "stashable": true, "discardable": true, "loop_persistent": true,
	}
	loader.cards[plain_id] = {
		"id": plain_id, "name": "測試普通物品", "type": "equipment",
		"slotless": false, "stashable": true, "discardable": true, "loop_persistent": false,
	}

	_fresh_opening(gs)
	gs.call("choose_opening", "take_family_album")
	gs.call("gain_card", magic_id)
	gs.call("gain_card", plain_id)
	_check((gs.get("loop_persistent_item_ids") as Dictionary).has(magic_id), "取得魔法物品當下就寫進 meta set")
	_check(not (gs.get("loop_persistent_item_ids") as Dictionary).has(plain_id), "普通物品不寫 meta set")

	_complete_replaced(gs, "ajie")
	_check((gs.get("loop_persistent_item_ids") as Dictionary).has(magic_id), "結算後 meta set 仍記得魔法物品")
	gs.call("choose_opening", "take_family_album")
	var hand_r2: Array = gs.get("hand") as Array
	_check(hand_r2.has(magic_id), "下一輪開局恢復魔法物品")
	_check(not hand_r2.has(plain_id), "普通物品不跨輪")
	_check(hand_r2[0] == "protagonist", "恢復後主角卡仍在 index 0")

	# 一般 lose 只令本輪消失，再下一輪照樣恢復。
	gs.call("lose_card", magic_id)
	_check(not (gs.get("hand") as Array).has(magic_id), "一般 lose 移出本輪手牌")
	_check((gs.get("loop_persistent_item_ids") as Dictionary).has(magic_id), "一般 lose 不動 meta set")
	_complete_replaced(gs, "ajie")
	gs.call("choose_opening", "take_family_album")
	_check((gs.get("hand") as Array).has(magic_id), "一般 lose 之後下一輪仍恢復")

	# permanent lose 走正式效果入口（beat 的 on_enter），不是測試自己呼叫 lose_card()。
	var perm_beat_id := "p5d_permanent_lose"
	var perm_beat := {
		"id": perm_beat_id,
		"location": "sanquan",
		"when": { "day": 1, "phase": "morning" },
		"title": "測試永久失去",
		"text": "測試用",
		"slots": [],
		"on_enter": { "lose": [{ "card": magic_id, "permanent": true }] },
	}
	loader.beats.append(perm_beat)
	loader.beats_by_id[perm_beat_id] = perm_beat
	gs.call("play_beat", perm_beat_id)
	loader.beats_by_id.erase(perm_beat_id)
	loader.beats.erase(perm_beat)

	_check(not (gs.get("hand") as Array).has(magic_id), "permanent lose 移出本輪手牌")
	_check(not (gs.get("loop_persistent_item_ids") as Dictionary).has(magic_id), "permanent lose 同步移除 meta set")
	_complete_replaced(gs, "ajie")
	gs.call("choose_opening", "take_family_album")
	_check(not (gs.get("hand") as Array).has(magic_id), "permanent lose 之後不再恢復")

	# 正式卡表不得有任何跨輪物品（第一輪不憑空帶入魔法物品）。
	loader.cards.erase(magic_id)
	loader.cards.erase(plain_id)
	var official_persistent := 0
	for cid: Variant in loader.cards.keys():
		if (loader.cards[cid] as Dictionary).get("loop_persistent", false) == true:
			official_persistent += 1
	_check(official_persistent == 0, "正式 cards catalog 的 loop_persistent:true 數量為 0（實際 %d）" % official_persistent)

	_fresh_opening(gs)


## 起一輪並以正常替換結局收尾（跨輪 fixture 共用）。
func _complete_replaced(gs: Node, proxy: String) -> void:
	gs.set("day", 45)
	gs.set("phase", "evening")
	gs.set("selected_festival_proxy_npc", proxy)
	gs.call("start_ending", "ending_replaced", "d45_coda")
	_play_out_and_complete(gs)


# ── 10. D29 逾期預設三路等價 ────────────────────────────────────────────────

func _test_10_d29_three_paths(gs: Node, data_node: Node) -> void:
	print("\n--- 10. D29 逾期預設三路等價 ---")
	var loader: DataLoader = data_node.get("loader") as DataLoader

	# (a) 明示不邀、(b) 進面板但未選、(c) 完全未進面板：三路結果必須相同。
	var explicit := _run_d29(gs, "explicit", { "ajie": 3, "awei": 1 })
	var entered := _run_d29(gs, "entered", { "ajie": 3, "awei": 1 })
	var never := _run_d29(gs, "never", { "ajie": 3, "awei": 1 })

	_check(explicit["choice"] == entered["choice"] and entered["choice"] == never["choice"],
		"三路都由同一個 invite_none 槽結算 choice group（%s）" % str(never["choice"]))
	_check(explicit["proxy"] == entered["proxy"] and entered["proxy"] == never["proxy"],
		"三路的慶典代付者相同（%s）" % str(never["proxy"]))
	_check(bool(explicit["invited_none"]) and bool(entered["invited_none"]) and bool(never["invited_none"]),
		"三路都套上 invite_none 的 on_place 效果")
	_check(not bool(never["beat_entered"]), "完全未進面板那條不寫 beats_entered、不套 beat on_enter")
	_check(str(never["proxy"]) == "ajie", "最大投入者為阿婕時代付者是阿婕")

	# 同分：按 npcs.json 的候選子序列（阿婕 → 阿薇 → 阿財）取第一個。
	var eligible: Array[String] = []
	for npc_id: Variant in loader.npcs.keys():
		if (loader.npcs[npc_id] as Dictionary).get("festival_proxy_eligible", false) == true:
			eligible.append(str(npc_id))
	var expected_eligible: Array[String] = ["ajie", "awei", "acai"]
	_check(eligible == expected_eligible,
		"正式候選子序列精確為阿婕 → 阿薇 → 阿財（實際：%s）" % str(eligible))

	var tie := _run_d29(gs, "never", { "ajie": 2, "awei": 2, "acai": 2 })
	_check(str(tie["proxy"]) == "ajie", "同分時按 NPC 資料順序取阿婕")
	var tie_late := _run_d29(gs, "never", { "awei": 2, "acai": 2 })
	_check(str(tie_late["proxy"]) == "awei", "阿婕沒有投入時同分取阿薇")

	var zero := _run_d29(gs, "never", {})
	_check(str(zero["proxy"]) == "ajie", "全部為 0 時使用資料 fallback（ajie）")

	var awei_top := _run_d29(gs, "never", { "ajie": 1, "awei": 5 })
	_check(str(awei_top["proxy"]) == "awei", "最大投入者為阿薇時代付者是阿薇")


## 走一次 D29 afternoon 的離場。`path` 為 explicit／entered／never。
## 回傳 { choice, proxy, invited_none, beat_entered }
func _run_d29(gs: Node, path: String, counts: Dictionary) -> Dictionary:
	_fresh_run(gs, 29, "afternoon")
	var nac: Dictionary = gs.get("npc_action_counts") as Dictionary
	for npc_id: Variant in counts.keys():
		nac[str(npc_id)] = int(counts[npc_id])

	match path:
		"explicit":
			gs.call("choose", "d29_pm_invitation", "invitation", "invite_none")
		"entered":
			gs.call("play_beat", "d29_pm_invitation")

	var adv: Dictionary = gs.call("advance_phase")
	_check(bool(adv.get("ok", false)), "D29 afternoon（%s）推進成功" % path)
	_check(str(gs.get("phase")) == "evening", "D29 afternoon（%s）離開到 evening" % path)
	return {
		"choice": str((gs.get("choices") as Dictionary).get("d29_pm_invitation::invitation", "")),
		"proxy": str(gs.get("selected_festival_proxy_npc")),
		"invited_none": bool((gs.get("flags") as Dictionary).get("invited_none", false)),
		"beat_entered": (gs.get("beats_entered") as Dictionary).has("d29_pm_invitation"),
	}


# ── 11. D29 預設失敗與凍結值的下游讀取 ──────────────────────────────────────

func _test_11_d29_conflict_and_frozen_reads(gs: Node, data_node: Node) -> void:
	print("\n--- 11. D29 預設衝突與凍結值下游讀取 ---")
	var loader: DataLoader = data_node.get("loader") as DataLoader
	var slot := _find_slot(loader, "d29_pm_invitation", "invite_none")
	_check(not slot.is_empty(), "找得到 invite_none 槽")
	var orig_proxy: Variant = (slot["on_place"] as Dictionary)["festival_proxy"]

	# 把 fallback 指向非候選 NPC：preflight 必須整批失敗。
	(slot["on_place"] as Dictionary)["festival_proxy"] = { "mode": "highest_eligible", "fallback": "uncle" }
	_fresh_run(gs, 29, "afternoon")
	var before := _state_text(gs)
	var conflict: Dictionary = gs.call("advance_phase")
	_check(_reject_code(conflict) == "unresolved_choice_conflict", "壞掉的逾期預設 → unresolved_choice_conflict")
	_check(int(gs.get("day")) == 29 and str(gs.get("phase")) == "afternoon", "拒絕後停在原 day／phase")
	_check(_state_text(gs) == before, "拒絕後完整序列化零變化")

	(slot["on_place"] as Dictionary)["festival_proxy"] = orig_proxy

	# 正常離場後 D31／D39／ending 讀的是同一個凍結 id。
	_fresh_run(gs, 29, "afternoon")
	(gs.get("npc_action_counts") as Dictionary)["awei"] = 4
	gs.call("advance_phase")
	var frozen := str(gs.get("selected_festival_proxy_npc"))
	_check(frozen == "awei", "離開 D29 afternoon 後代付者已凍結為 awei")

	gs.set("day", 31)
	gs.set("phase", "afternoon")
	_check(_visible_proxy_beat(gs, loader, 31) == "d31_proxy_awei", "D31 顯示的是凍結的那一位")
	gs.set("day", 39)
	gs.set("phase", "afternoon")
	_check(_visible_proxy_beat(gs, loader, 39) == "d39_proxy_awei", "D39 顯示的是凍結的那一位")

	gs.set("day", 45)
	gs.set("phase", "evening")
	gs.call("start_ending", "ending_replaced", "d45_coda")
	_check(str((gs.get("active_ending") as Dictionary).get("festival_proxy_npc", "")) == frozen,
		"ending 快照讀的是同一個凍結 id")


## 當下 day／phase 唯一條件成立的 festival_proxy_is beat id。
func _visible_proxy_beat(gs: Node, loader: DataLoader, day: int) -> String:
	var found := ""
	for b in loader.beats_at(day, "afternoon"):
		var cond: Variant = b.get("condition")
		if not (cond is Dictionary) or not (cond as Dictionary).has("festival_proxy_is"):
			continue
		if ConditionEval.eval(cond, gs):
			if not found.is_empty():
				return "<多個同時成立>"
			found = str(b.get("id", ""))
	return found


# ── 12. advance_phase() 七步固定順序逐層反證 ────────────────────────────────

func _test_12_advance_phase_order(gs: Node, data_node: Node) -> void:
	print("\n--- 12. advance_phase() 固定順序逐層反證 ---")
	var loader: DataLoader = data_node.get("loader") as DataLoader
	var slot := _find_slot(loader, "d29_pm_invitation", "invite_none")
	var orig_proxy: Variant = (slot["on_place"] as Dictionary)["festival_proxy"]
	var broken := { "mode": "highest_eligible", "fallback": "uncle" }

	# ① 非 run＋active encounter：先回 not_run
	_fresh_run(gs, 29, "afternoon")
	(slot["on_place"] as Dictionary)["festival_proxy"] = broken
	(gs.get("active_encounter") as Dictionary)["beat_id"] = "fake"
	gs.set("flow_mode", "opening")
	var r1: Dictionary = gs.call("advance_phase")
	_check(_reject_code(r1) == "not_run" and not bool(r1.get("phase_advanced", true)), "非 run＋遭遇＋壞 default → not_run")

	# ② active encounter＋壞 default：回 encounter_active
	gs.set("flow_mode", "run")
	var before2 := _state_text(gs)
	var r2: Dictionary = gs.call("advance_phase")
	_check(_reject_code(r2) == "encounter_active", "遭遇進行中＋壞 default → encounter_active")
	_check(_state_text(gs) == before2, "encounter_active 拒絕後零變化")
	(gs.get("active_encounter") as Dictionary).clear()

	# ③ 夜間有睡覺文字＋壞 default：先成功停拍，不換時段
	_fresh_run(gs, 24, "night")
	gs.call("set_flag", "boundary_bleeding", true)
	for _i in range(3):
		gs.call("gain_card", "madness", false)
	var r3: Dictionary = gs.call("advance_phase")
	_check(bool(r3.get("ok", false)) and not bool(r3.get("phase_advanced", true))
			and (r3.get("lines", PackedStringArray()) as PackedStringArray).size() > 0,
		"夜間停拍優先於逾期預設：成功、有文字、不換時段")
	_check(int(gs.get("day")) == 24 and str(gs.get("phase")) == "night", "停拍後停在原時段")

	# ④ 壞 default＋未完成 phase_exit：回 unresolved_choice_conflict
	_fresh_run(gs, 29, "afternoon")
	var r4: Dictionary = gs.call("advance_phase")
	_check(_reject_code(r4) == "unresolved_choice_conflict", "壞 default 先於 phase_exit 門檻 → unresolved_choice_conflict")
	(slot["on_place"] as Dictionary)["festival_proxy"] = orig_proxy

	# ⑤ 合法 default＋未完成 gate：回 phase_requirements_incomplete
	_fresh_run(gs, 45, "evening")
	gs.call("set_flag", "final_day", true)
	gs.set("selected_festival_proxy_npc", "ajie")
	var before5 := _state_text(gs)
	var r5: Dictionary = gs.call("advance_phase")
	_check(_reject_code(r5) == "phase_requirements_incomplete", "gate 未完成 → phase_requirements_incomplete")
	_check(_state_text(gs) == before5, "gate 拒絕後零變化")

	# ⑥ gate 完成但 ending 前置壞掉：回 data_conflict
	(gs.get("choices") as Dictionary)["d45_then::d45_coda"] = "empty_handed"
	(gs.get("slots_placed") as Dictionary)["d45_then::empty_handed"] = true
	gs.set("selected_festival_proxy_npc", "")
	var before6 := _state_text(gs)
	var r6: Dictionary = gs.call("advance_phase")
	_check(_reject_code(r6) == "data_conflict", "gate 完成但代付者未凍結 → data_conflict")
	_check(_state_text(gs) == before6, "data_conflict 拒絕後零變化")
	_check(str(gs.get("flow_mode")) == "run", "data_conflict 拒絕後仍在 run mode")

	for res: Dictionary in [r1, r2, r4, r5, r6]:
		_check(not bool(res.get("phase_advanced", true)) and (res.get("lines", PackedStringArray()) as PackedStringArray).is_empty(),
			"拒絕結果的 phase_advanced 為 false 且 lines 為空")


# ── 13. 成功路徑的 phase_advanced 形狀 ──────────────────────────────────────

func _test_13_advance_phase_success_shapes(gs: Node) -> void:
	print("\n--- 13. 成功推進的回傳形狀 ---")

	# 一般跨時段：phase_advanced 為 true
	_fresh_run(gs, 20, "morning")
	var normal: Dictionary = gs.call("advance_phase")
	_check(bool(normal.get("ok", false)) and bool(normal.get("phase_advanced", false)), "一般跨時段 phase_advanced:true")
	_check(str(gs.get("phase")) == "afternoon", "一般跨時段真的換了時段")

	# 進入新 phase 時由規則層自動建立當下 due fixed encounter（D45 afternoon）。
	_fresh_run(gs, 45, "morning")
	gs.call("set_flag", "final_day", true)
	gs.call("advance_phase")
	_check(str((gs.get("active_encounter") as Dictionary).get("beat_id", "")) == "d45_encounter",
		"進入 D45 afternoon 後自動建立 due fixed encounter")

	# 遭遇出口 after_finish:"advance_phase" 只走一次相同 transition。
	PlaythroughGreedy.solve_active_encounter_if_any(gs)
	_check(int(gs.get("day")) == 45 and str(gs.get("phase")) == "evening",
		"遭遇出口恰好推進一次到 D45 evening（實際：第 %d 天 %s）" % [int(gs.get("day")), str(gs.get("phase"))])

	# D45 evening 進 ending：成功但 phase_advanced 為 false、day／phase 不動。
	gs.call("play_evening")
	gs.set("selected_festival_proxy_npc", "ajie")
	gs.call("choose", "d45_then", "d45_coda", "empty_handed")
	var d45: Dictionary = gs.call("advance_phase")
	_check(bool(d45.get("ok", false)) and not bool(d45.get("phase_advanced", true)), "D45 進 ending 成功但 phase_advanced:false")
	_check(int(gs.get("day")) == 45 and str(gs.get("phase")) == "evening", "D45 進 ending 後 day／phase 不動")
	_check(str(gs.get("flow_mode")) == "ending", "D45 進 ending 後 mode 為 ending")

	# 夜間停拍：第一次 false、第二次才 true。
	_fresh_run(gs, 24, "night")
	gs.call("set_flag", "boundary_bleeding", true)
	for _i in range(3):
		gs.call("gain_card", "madness", false)
	var night1: Dictionary = gs.call("advance_phase")
	_check(bool(night1.get("ok", false)) and not bool(night1.get("phase_advanced", true)), "夜間第一次推進 phase_advanced:false")
	var night2: Dictionary = gs.call("advance_phase")
	_check(bool(night2.get("phase_advanced", false)) and int(gs.get("day")) == 25, "夜間第二次推進才換日")

	# resolve_night_advance() 已退場：規則層不得再有第二個推進入口。
	_check(not gs.has_method("resolve_night_advance"), "resolve_night_advance() 已從 GameState 退場")
	_check(not gs.has_method("end_run"), "end_run() 已從 GameState 退場")
	_check(not gs.has_signal("run_ended"), "run_ended 訊號已退場")


# ── 14. choice_requires_card 回歸 ───────────────────────────────────────────

func _test_14_card_required_regression(gs: Node) -> void:
	print("\n--- 14. choice_requires_card 回歸 ---")

	for slot_id: String in ["say_yes_boss", "say_yes"]:
		_fresh_run(gs, 43, "afternoon")
		var before := _state_text(gs)
		var res: Dictionary = gs.call("choose", "d43_pm_zhou", "leaving", slot_id)
		_check(_reject_code(res) == "card_required", "D43 %s 無卡直呼 → card_required" % slot_id)
		_check(_state_text(gs) == before, "D43 %s 拒絕後零變化" % slot_id)

	_fresh_run(gs, 43, "afternoon")
	gs.call("set_flag", "outside_job_waiting", true)   # say_yes_boss 的 condition
	var ok_res: Dictionary = gs.call("choose", "d43_pm_zhou", "leaving", "say_yes_boss", "protagonist")
	_check(bool(ok_res.get("ok", false)), "D43 提交主角卡才成立")
	_check(bool(gs.get("action_spent")), "D43 提交主角卡消耗下午行動格")

	# D22／D29 省略該欄，無卡 choice 仍成功。
	_fresh_run(gs, 29, "afternoon")
	_check(bool((gs.call("choose", "d29_pm_invitation", "invitation", "invite_none") as Dictionary).get("ok", false)),
		"D29 無卡 choice 回歸仍成功")


# ── 15. 拒絕矩陣 ────────────────────────────────────────────────────────────

func _test_15_reject_matrix(gs: Node) -> void:
	print("\n--- 15. opening／complete 拒絕矩陣 ---")

	# choose_opening
	_fresh_run(gs, 20, "morning")
	var before_run := _state_text(gs)
	_check(_reject_code(gs.call("choose_opening", "take_family_album")) == "not_opening", "run mode choose_opening → not_opening")
	_check(_state_text(gs) == before_run, "not_opening 拒絕後零變化")

	_fresh_opening(gs)
	var before_open := _state_text(gs)
	_check(_reject_code(gs.call("choose_opening", "no_such_choice")) == "unknown_opening_choice",
		"未知 choice → unknown_opening_choice")
	_check(_reject_code(gs.call("choose_opening", "refuse_boarding")) == "opening_choice_locked",
		"未解鎖 choice → opening_choice_locked")
	_check(_state_text(gs) == before_open, "opening 兩種拒絕後零變化")

	# complete_ending
	_check(_reject_code(gs.call("complete_ending")) == "not_ending", "opening mode complete_ending → not_ending")
	_fresh_run(gs, 45, "evening")
	_check(_reject_code(gs.call("complete_ending")) == "not_ending", "run mode complete_ending → not_ending")

	gs.set("selected_festival_proxy_npc", "ajie")
	gs.call("start_ending", "ending_replaced", "d45_coda")
	var before_ready := _state_text(gs)
	_check(_reject_code(gs.call("complete_ending")) == "not_ready", "未播完 complete_ending → not_ready")
	_check(_state_text(gs) == before_ready, "not_ready 拒絕後零變化")

	# ending mode 但 active 被清空（壞狀態）→ no_active_ending
	(gs.get("active_ending") as Dictionary).clear()
	_check(_reject_code(gs.call("complete_ending")) == "no_active_ending", "ending mode 無 active → no_active_ending")

	# ready 但 history record 引用不合法 → data_conflict，且 append 前就擋下
	_fresh_run(gs, 45, "evening")
	gs.set("selected_festival_proxy_npc", "ajie")
	gs.call("start_ending", "ending_replaced", "d45_coda")
	var guard := 200
	while guard > 0 and not bool((gs.call("ending_view") as Dictionary).get("can_complete", false)):
		guard -= 1
		if not bool((gs.call("ending_view") as Dictionary).get("page_revealed", false)):
			gs.call("reveal_ending_page")
		else:
			gs.call("advance_ending_page")
	(gs.get("active_ending") as Dictionary)["festival_proxy_npc"] = "uncle"
	var history_before: int = (gs.get("ending_history") as Array).size()
	_check(_reject_code(gs.call("complete_ending")) == "data_conflict", "history record 引用不合法 → data_conflict")
	_check((gs.get("ending_history") as Array).size() == history_before, "data_conflict 發生在 append 前")


# ── 16. 第二輪由 opening 重入 ───────────────────────────────────────────────

func _test_16_second_run_reentry(gs: Node) -> void:
	print("\n--- 16. 第二輪由 opening 重入 ---")

	_fresh_opening(gs)
	gs.call("choose_opening", "take_family_album")
	gs.call("gain_card", "k_forty_something")
	(gs.get("night_locations_seen") as Dictionary)["n_source"] = true
	gs.call("mark_delegation_tutorial_seen")
	_complete_replaced(gs, "ajie")

	var album2: Dictionary = gs.call("choose_opening", "take_family_album")
	_check(bool(album2.get("ok", false)), "第二輪可再選相簿")
	_check(int(gs.get("day")) == 1 and str(gs.get("phase")) == "morning", "第二輪重新進第 1 天 morning")
	_check(bool(gs.call("has_knowledge", "k_forty_something")), "第二輪保留 meta 知識")
	_check((gs.get("night_locations_seen") as Dictionary).has("n_source"), "第二輪保留夜間 seen")
	_check(bool(gs.get("delegation_tutorial_seen")), "第二輪保留教學狀態")
	_check((gs.get("ending_history") as Array).size() == 1, "第二輪保留歷輪摘要")
	_check(int(gs.get("run_number")) == 2, "第二輪的 run_number 為 2")

	_complete_replaced(gs, "awei")
	var phone2: Dictionary = gs.call("choose_opening", "return_missed_call")
	_check(bool(phone2.get("ok", false)), "第三輪可改選電話")
	_check(bool((gs.get("flags") as Dictionary).get("outside_job_waiting", false)), "第三輪電話開局旗標正確")
	_check(not (gs.get("hand") as Array).has("item_family_album"), "第三輪不殘留上一輪的相簿")
	_check(int(gs.get("run_number")) == 3, "第三輪的 run_number 為 3")
