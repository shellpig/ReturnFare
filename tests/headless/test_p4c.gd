extends SceneTree

## P4-C headless 驗收測試：
## 1. 委託槽 view model 欄位（result_timing／preview／tendency／task_title／delegation_state）
## 2. 未取得候選完全不進面板；持有後在原位置出現
## 3. 今日已受託時 view model 正確反映（獨立於 choice_group 是否已永久結算）
## 4. 委託教學信號：零到一張 person card 才發、不寫 meta、mark_ 後才算看過、跨輪保留
## 5. D17～19 處方委託三條人物路線 data-driven 結果（阿婕／阿珠／阿財）
## 6. 阿婕信任破壞後候選隱藏

const DataLoader := preload("res://scripts/data_loader.gd")
const PanelBuilder := preload("res://scripts/core/panel_builder.gd")
const PlaythroughGreedy := preload("res://tests/headless/playthrough_greedy.gd")

func _initialize() -> void:
	var data_node: Node = PlaythroughGreedy.setup_data(self)
	var gs: Node = PlaythroughGreedy.setup_game_state(self, data_node)

	await process_frame

	if not bool(data_node.get("ok")):
		push_error("P4-C: Data failed to load; abort")
		quit(1)
		return

	var failed: int = 0
	print("\n=== P4-C 委託 UI 與首個案例測試套件 ===")

	failed += _test_view_model_fields(gs, data_node)
	failed += _test_candidate_visibility(gs, data_node)
	failed += _test_delegated_today_view(gs, data_node)
	failed += _test_tutorial_lifecycle(gs, data_node)
	failed += _test_ajie_route(gs, data_node)
	failed += _test_azhu_route_next_morning(gs, data_node)
	failed += _test_acai_route_subjective(gs, data_node)
	failed += _test_ajie_trust_broken_hides_candidate(gs, data_node)
	failed += _test_ajie_trust_repair_reacquire(gs, data_node)
	failed += _test_prescription_d18_d19(gs, data_node)
	failed += _test_prescription_no_repeat_subsequent_day(gs, data_node)
	failed += _test_candidate_stable_ordering(gs, data_node)
	failed += _test_azhu_acai_acquisition_gates(gs, data_node)

	if failed > 0:
		push_error("\nP4-C: %d assertion(s) failed\n" % failed)
		quit(1)
	else:
		print("\nP4-C: all tests passed\n")
		quit(0)


func _ok(msg: String) -> int:
	print("  ok  " + msg)
	return 0


func _fail(msg: String) -> int:
	push_error("  FAIL  " + msg)
	return 1


func _reset_gs(gs: Node) -> void:
	gs.call("end_run")
	var hand: Array = gs.get("hand") as Array
	hand.clear()
	hand.append("protagonist")
	(gs.get("delegates_used_today") as Dictionary).clear()
	(gs.get("pending_delegation_reports") as Array).clear()
	(gs.get("choices") as Dictionary).clear()
	(gs.get("slots_placed") as Dictionary).clear()
	(gs.get("flags") as Dictionary).clear()
	(gs.get("relations") as Dictionary).clear()
	(gs.get("npc_action_counts") as Dictionary).clear()
	(gs.get("knowledge") as Dictionary).clear()
	gs.set("night_locations_seen", {})
	gs.set("delegation_tutorial_seen", false)
	gs.set("day", 17)
	gs.set("phase", "afternoon")
	gs.set("action_spent", false)


func _find_slot_view(panel: Dictionary, beat_id: String, slot_id: String) -> Dictionary:
	for beat_view: Dictionary in panel.get("beats", []) as Array:
		if str((beat_view["beat"] as Dictionary).get("id", "")) != beat_id:
			continue
		for slot_view: Dictionary in beat_view.get("slots", []) as Array:
			if str((slot_view["slot"] as Dictionary).get("id", "")) == slot_id:
				return slot_view
	return {}


# ─── 1. 委託槽 view model 欄位 ───
func _test_view_model_fields(gs: Node, data_node: Node) -> int:
	print("\n--- 1. 委託槽 view model 欄位 ---")
	var failed: int = 0
	_reset_gs(gs)

	var hand: Array = gs.get("hand") as Array
	hand.append("npc_ajie")

	var panel: Dictionary = gs.call("build_panel", "sanquan")
	var ajie_view := _find_slot_view(panel, "d17_19_prescription", "ask_ajie")
	if ajie_view.is_empty():
		failed += _fail("找不到 ask_ajie 的 slot view（持有 npc_ajie 時應出現）")
	else:
		var deleg: Dictionary = ajie_view.get("delegation", {}) as Dictionary
		if str(deleg.get("result_timing", "")) == "immediate" \
			and not str(deleg.get("preview", "")).is_empty() \
			and not str(deleg.get("tendency", "")).is_empty() \
			and str(deleg.get("task_title", "")) == "叔叔的舊藥單" \
			and str(deleg.get("delegation_state", "")) == "available":
			_ok("ask_ajie view model 含 result_timing/preview/tendency/task_title，delegation_state=available")
		else:
			failed += _fail("ask_ajie view model 欄位不符：%s" % str(deleg))

	var self_view := _find_slot_view(panel, "d17_19_prescription", "find_self")
	if self_view.is_empty():
		failed += _fail("找不到 find_self 的 slot view")
	else:
		var self_deleg: Dictionary = self_view.get("delegation", {}) as Dictionary
		if self_deleg.is_empty():
			_ok("find_self（非委託槽）的 delegation view model 為空字典")
		else:
			failed += _fail("find_self 不應帶 delegation 欄位：%s" % str(self_deleg))

	return failed


# ─── 2. 未取得候選完全不進面板；持有後在原位置出現 ───
func _test_candidate_visibility(gs: Node, data_node: Node) -> int:
	print("\n--- 2. 未取得候選完全不進面板；持有後在原位置出現 ---")
	var failed: int = 0
	_reset_gs(gs)

	var panel_empty: Dictionary = gs.call("build_panel", "sanquan")
	var has_any_candidate := false
	for sid in ["ask_ajie", "ask_azhu", "ask_acai"]:
		if not _find_slot_view(panel_empty, "d17_19_prescription", sid).is_empty():
			has_any_candidate = true
	var self_present := not _find_slot_view(panel_empty, "d17_19_prescription", "find_self").is_empty()

	if not has_any_candidate and self_present:
		_ok("零人物卡時三個委託候選完全不出現，親自處理槽仍在")
	else:
		failed += _fail("零人物卡時候選可見性不符：has_any_candidate=%s self_present=%s" % [str(has_any_candidate), str(self_present)])

	var hand: Array = gs.get("hand") as Array
	hand.append("npc_acai")
	var panel_acai: Dictionary = gs.call("build_panel", "sanquan")
	var acai_present := not _find_slot_view(panel_acai, "d17_19_prescription", "ask_acai").is_empty()
	var ajie_still_absent := _find_slot_view(panel_acai, "d17_19_prescription", "ask_ajie").is_empty()
	if acai_present and ajie_still_absent:
		_ok("取得阿財後 ask_acai 在資料原位置出現，未取得的 ask_ajie 仍不出現")
	else:
		failed += _fail("取得單一人物卡後候選可見性不符：acai_present=%s ajie_still_absent=%s" % [str(acai_present), str(ajie_still_absent)])

	return failed


# ─── 3. 今日已受託時 view model 正確反映（獨立於 choice_group 是否永久結算）───
func _test_delegated_today_view(gs: Node, data_node: Node) -> int:
	print("\n--- 3. 今日已受託時 view model 正確反映 ---")
	var failed: int = 0
	_reset_gs(gs)

	var loader: DataLoader = data_node.get("loader") as DataLoader
	# 兩個各自獨立 choice_group 的委託槽，同接受 npc_ajie；委託其中一個之後，
	# 另一個槽本身未被 choice_group／slots_placed 鎖住，純靠 delegation_state 呈現「今日已受託」。
	var beat_a: Dictionary = {
		"id": "test_p4c_today_a",
		"location": "clinic",
		"when": { "day_from": 17, "day_to": 19, "phase": ["afternoon"] },
		"slots": [
			{
				"id": "slot_a",
				"accepts": ["npc_ajie"],
				"choice_group": "grp_today_a",
				"delegation": { "result_timing": "immediate", "preview": "p", "tendency": "t" },
				"on_place": { "text": "a done" }
			}
		]
	}
	var beat_b: Dictionary = {
		"id": "test_p4c_today_b",
		"location": "clinic",
		"when": { "day_from": 17, "day_to": 19, "phase": ["afternoon"] },
		"slots": [
			{
				"id": "slot_b",
				"accepts": ["npc_ajie"],
				"choice_group": "grp_today_b",
				"delegation": { "result_timing": "immediate", "preview": "p", "tendency": "t" },
				"on_place": { "text": "b done" }
			}
		]
	}
	loader.beats_by_id["test_p4c_today_a"] = beat_a
	loader.beats_by_id["test_p4c_today_b"] = beat_b
	# build_panel() 走 loader.beats_at()，該函式掃 loader.beats 陣列（不是 beats_by_id），
	# 兩處都要注入合成 beat 才能被面板 view model 看見（真正的放置／委託仍走 beats_by_id）。
	loader.beats.append(beat_a)
	loader.beats.append(beat_b)

	var hand: Array = gs.get("hand") as Array
	hand.append("npc_ajie")

	var panel_before: Dictionary = gs.call("build_panel", "clinic")
	var before_view := _find_slot_view(panel_before, "test_p4c_today_b", "slot_b")
	var before_state: String = str((before_view.get("delegation", {}) as Dictionary).get("delegation_state", ""))

	gs.call("delegate", "test_p4c_today_a", "slot_a", "npc_ajie")

	var panel_after: Dictionary = gs.call("build_panel", "clinic")
	var after_view := _find_slot_view(panel_after, "test_p4c_today_b", "slot_b")
	var after_tri: int = int(after_view.get("tri", -1))
	var after_state: String = str((after_view.get("delegation", {}) as Dictionary).get("delegation_state", ""))

	if before_state == "available" and after_tri == PanelBuilder.TriState.OPEN and after_state == "delegated_today":
		_ok("委託阿婕前 slot_b delegation_state=available；委託後該槽仍 OPEN 但 delegation_state=delegated_today（未被 choice_group 鎖住，純靠此欄位呈現鎖定）")
	else:
		failed += _fail("delegation_state 反映不符：before=%s after_tri=%d after_state=%s" % [before_state, after_tri, after_state])

	return failed


# ─── 4. 委託教學信號生命週期 ───
func _test_tutorial_lifecycle(gs: Node, data_node: Node) -> int:
	print("\n--- 4. 委託教學信號生命週期 ---")
	var failed: int = 0
	_reset_gs(gs)

	var signal_count := { "n": 0 }
	var handler := func(): signal_count["n"] += 1
	gs.connect("delegation_tutorial_available", handler)

	# (a) 零到一張 person card：發出信號，但不寫 meta
	gs.call("gain_card", "npc_ajie", false)
	if int(signal_count["n"]) == 1 and not bool(gs.get("delegation_tutorial_seen")):
		_ok("首次取得 person card 發出 delegation_tutorial_available，且不自動寫 delegation_tutorial_seen")
	else:
		failed += _fail("首次取得信號行為不符：count=%d seen=%s" % [int(signal_count["n"]), str(gs.get("delegation_tutorial_seen"))])

	# (b) 已持有一張後再取得第二張 person card：不再發信號
	gs.call("gain_card", "npc_azhu", false)
	if int(signal_count["n"]) == 1:
		_ok("第二張 person card 不再重複發出教學信號")
	else:
		failed += _fail("第二張 person card 不該重複發信號：count=%d" % int(signal_count["n"]))

	# (c) mark_delegation_tutorial_seen() 後才算看過
	gs.call("mark_delegation_tutorial_seen")
	if bool(gs.get("delegation_tutorial_seen")):
		_ok("mark_delegation_tutorial_seen() 後 delegation_tutorial_seen 為 true")
	else:
		failed += _fail("mark_delegation_tutorial_seen() 未生效")

	# (d) 序列化往返保留
	var s_data: Dictionary = gs.call("serialize")
	gs.set("delegation_tutorial_seen", false)
	gs.call("deserialize", s_data)
	if bool(gs.get("delegation_tutorial_seen")):
		_ok("delegation_tutorial_seen 序列化往返保留")
	else:
		failed += _fail("delegation_tutorial_seen 序列化往返遺失")

	# (e) end_run() 不清空（meta 層，跨輪保留）
	gs.call("end_run")
	if bool(gs.get("delegation_tutorial_seen")):
		_ok("end_run() 後 delegation_tutorial_seen 仍保留（meta 層跨輪不重置）")
	else:
		failed += _fail("end_run() 錯誤清空了 delegation_tutorial_seen")

	gs.disconnect("delegation_tutorial_available", handler)
	return failed


# ─── 5a. D17～19 阿婕路線（immediate，帶額外資訊）───
func _test_ajie_route(gs: Node, data_node: Node) -> int:
	print("\n--- 5a. 阿婕路線（immediate）---")
	var failed: int = 0
	_reset_gs(gs)

	var hand: Array = gs.get("hand") as Array
	hand.append("npc_ajie")

	var r: Dictionary = gs.call("delegate", "d17_19_prescription", "ask_ajie", "npc_ajie")
	var got_doc: bool = bool(gs.call("has_card", "doc_prescription"))
	var got_info: bool = bool(gs.call("has_card", "info_ajie_saw_parents"))
	var still_held: bool = bool(gs.call("has_card", "npc_ajie"))

	if bool(r.get("ok", false)) and got_doc and got_info and still_held:
		_ok("委託阿婕：immediate 取得 doc_prescription 與 info_ajie_saw_parents，人物卡仍在手牌")
	else:
		failed += _fail("阿婕路線結果不符：ok=%s doc=%s info=%s held=%s" % [str(r.get("ok")), str(got_doc), str(got_info), str(still_held)])

	return failed


# ─── 5b. D17～19 阿珠路線（next_morning）───
func _test_azhu_route_next_morning(gs: Node, data_node: Node) -> int:
	print("\n--- 5b. 阿珠路線（next_morning）---")
	var failed: int = 0
	_reset_gs(gs)

	var hand: Array = gs.get("hand") as Array
	hand.append("npc_azhu")

	var r: Dictionary = gs.call("delegate", "d17_19_prescription", "ask_azhu", "npc_azhu")
	var got_doc_immediately: bool = bool(gs.call("has_card", "doc_prescription"))
	var pending: Array = gs.get("pending_delegation_reports") as Array

	if bool(r.get("ok", false)) and not got_doc_immediately and pending.size() == 1:
		_ok("委託阿珠：派出當下不取得 doc_prescription，排入 pending（隔日上午回報）")
	else:
		failed += _fail("阿珠派出當下不符：ok=%s got_doc_immediately=%s pending=%d" % [str(r.get("ok")), str(got_doc_immediately), pending.size()])

	# 推進至隔日上午
	gs.call("advance_phase") # evening
	gs.call("advance_phase") # night
	gs.call("advance_phase") # morning (Day 18)

	var got_doc_after: bool = bool(gs.call("has_card", "doc_prescription"))
	var got_uncle_info: bool = bool(gs.call("has_card", "info_uncle_treated_20y"))
	var rep_lines: PackedStringArray = gs.get("last_delegation_report_lines")

	if got_doc_after and got_uncle_info and not rep_lines.is_empty():
		_ok("隔日上午回報結算：取得 doc_prescription 與 info_uncle_treated_20y，回報文字進 last_delegation_report_lines")
	else:
		failed += _fail("阿珠隔日回報結算不符：doc=%s uncle_info=%s lines=%s" % [str(got_doc_after), str(got_uncle_info), str(rep_lines)])

	return failed


# ─── 5c. D17～19 阿財路線（immediate，回報主觀不含 doc_prescription）───
func _test_acai_route_subjective(gs: Node, data_node: Node) -> int:
	print("\n--- 5c. 阿財路線（回報主觀，不給 doc_prescription）---")
	var failed: int = 0
	_reset_gs(gs)

	var hand: Array = gs.get("hand") as Array
	hand.append("npc_acai")

	var r: Dictionary = gs.call("delegate", "d17_19_prescription", "ask_acai", "npc_acai")
	var got_doc: bool = bool(gs.call("has_card", "doc_prescription"))
	var got_box_info: bool = bool(gs.call("has_card", "info_acai_box"))

	if bool(r.get("ok", false)) and not got_doc and got_box_info:
		_ok("委託阿財：取得 info_acai_box，但不取得 doc_prescription（漏掉重要文件而不自知）")
	else:
		failed += _fail("阿財路線結果不符：ok=%s doc=%s box_info=%s" % [str(r.get("ok")), str(got_doc), str(got_box_info)])

	return failed


# ─── 6. 阿婕信任破壞後候選隱藏 ───
func _test_ajie_trust_broken_hides_candidate(gs: Node, data_node: Node) -> int:
	print("\n--- 6. 阿婕信任破壞後候選隱藏 ---")
	var failed: int = 0
	_reset_gs(gs)

	# 信任破壞的資料唯一真值是 ajie_trust_broken；破壞時若持有人物卡會同時 lose_card，
	# 因此手牌本就不會有 npc_ajie。這裡直接模擬該不變式。
	var flags: Dictionary = gs.get("flags") as Dictionary
	flags["ajie_trust_broken"] = true

	var panel: Dictionary = gs.call("build_panel", "sanquan")
	var ajie_view := _find_slot_view(panel, "d17_19_prescription", "ask_ajie")
	if ajie_view.is_empty():
		_ok("ajie_trust_broken=true 且未持有 npc_ajie 時，ask_ajie 候選不出現")
	else:
		failed += _fail("信任破壞後 ask_ajie 候選仍出現")

	return failed


# ─── 7. 阿婕信任修復後重新取得候選（真實放卡＋D17 on_enter 接線）───
func _test_ajie_trust_repair_reacquire(gs: Node, data_node: Node) -> int:
	print("\n--- 7. 阿婕信任修復後重新取得候選（真實放卡＋D17 on_enter）---")
	var failed: int = 0
	_reset_gs(gs)

	# (a) 破壞信任：D17 下午候選隱藏（破壞時人物卡本就不在手，不變式同 test 6）
	var flags: Dictionary = gs.get("flags") as Dictionary
	flags["ajie_trust_broken"] = true
	gs.set("day", 17)
	gs.set("phase", "afternoon")
	var panel_broken: Dictionary = gs.call("build_panel", "sanquan")
	var hidden_when_broken := _find_slot_view(panel_broken, "d17_19_prescription", "ask_ajie").is_empty()

	# (b) 真實修復：D16 下午把主角卡放進 repair_ajie_trust 槽，走 try_place 規則層
	#     （不直接 EffectApply；驗真實放卡入口清 ajie_trust_broken）
	gs.set("day", 16)
	gs.set("phase", "afternoon")
	gs.set("action_spent", false)
	var repair_res: Dictionary = gs.call("try_place", "protagonist", "d16_pm_sanquan", "repair_ajie_trust")
	var repaired := bool(repair_res.get("ok", false)) and not bool(flags.get("ajie_trust_broken", true))

	# (c) 真實 D17 on_enter：play_beat 觸發 d17_morning_phone，條件 gain 重新取得 npc_ajie
	#     （不直接 gain_card；驗 on_enter 接線的 has_card 條件 gain）
	gs.set("day", 17)
	gs.set("phase", "morning")
	gs.call("play_beat", "d17_morning_phone")
	var reacquired := bool(gs.call("has_card", "npc_ajie"))

	# (d) D17 下午候選回原位且可再委託
	gs.set("phase", "afternoon")
	var panel_repaired: Dictionary = gs.call("build_panel", "sanquan")
	var ajie_view := _find_slot_view(panel_repaired, "d17_19_prescription", "ask_ajie")
	var reappeared := not ajie_view.is_empty()
	var delegable := reappeared and str((ajie_view.get("delegation", {}) as Dictionary).get("delegation_state", "")) == "available"

	if hidden_when_broken and repaired and reacquired and reappeared and delegable:
		_ok("信任破壞→候選隱藏；D16 真實放卡修復＋D17 on_enter 條件 gain 重取 npc_ajie 後，ask_ajie 候選回原位且 delegation_state=available 可再委託")
	else:
		failed += _fail("修復重取不符：hidden=%s repaired=%s(ok=%s) reacquired=%s reappeared=%s delegable=%s" % [str(hidden_when_broken), str(repaired), str(repair_res.get("ok")), str(reacquired), str(reappeared), str(delegable)])

	return failed


# ─── 11. 阿珠只由 D9 揭露路線、阿財只由 D17-19 共事取得 ───
func _test_azhu_acai_acquisition_gates(gs: Node, data_node: Node) -> int:
	print("\n--- 11. 阿珠只由 D9 揭露、阿財只由 D17-19 共事取得 ---")
	var failed: int = 0

	# 阿珠：D17 on_enter 僅在 azhu_shared_abnormal_medicine（D9 揭露路線寫入）成立時 gain npc_azhu
	_reset_gs(gs)
	gs.set("day", 17)
	gs.set("phase", "morning")
	gs.call("play_beat", "d17_morning_phone")
	var azhu_without_flag := bool(gs.call("has_card", "npc_azhu"))

	_reset_gs(gs)
	(gs.get("flags") as Dictionary)["azhu_shared_abnormal_medicine"] = true
	gs.set("day", 17)
	gs.set("phase", "morning")
	gs.call("play_beat", "d17_morning_phone")
	var azhu_with_flag := bool(gs.call("has_card", "npc_azhu"))

	if not azhu_without_flag and azhu_with_flag:
		_ok("阿珠：無 azhu_shared_abnormal_medicine（D9 揭露）時 D17 on_enter 不取得；旗標成立才取得")
	else:
		failed += _fail("阿珠取得閘門不符：without_flag=%s with_flag=%s" % [str(azhu_without_flag), str(azhu_with_flag)])

	# 阿財：唯有真的在 D17-19「跟阿財做事」放主角卡才取得 npc_acai（條件 gain，走 try_place）
	_reset_gs(gs)
	gs.set("day", 17)
	gs.set("phase", "afternoon")
	gs.set("action_spent", false)
	var acai_before := bool(gs.call("has_card", "npc_acai"))
	var work_res: Dictionary = gs.call("try_place", "protagonist", "d17_pm_acai_intro", "work")
	var acai_after := bool(gs.call("has_card", "npc_acai"))

	if not acai_before and bool(work_res.get("ok", false)) and acai_after:
		_ok("阿財：D17-19『跟阿財做事』真實放卡後才取得 npc_acai（條件 gain）")
	else:
		failed += _fail("阿財取得閘門不符：before=%s work_ok=%s after=%s" % [str(acai_before), str(work_res.get("ok")), str(acai_after)])

	return failed


# ─── 8. D18、D19 仍能完成處方 ───
func _test_prescription_d18_d19(gs: Node, data_node: Node) -> int:
	print("\n--- 8. D18、D19 仍能完成處方 ---")
	var failed: int = 0

	# 處方 beat 窗口 day_from:17 day_to:19；驗第 18／19 天各仍可委託完成，不只 D17。
	for d: int in [18, 19]:
		_reset_gs(gs)
		gs.set("day", d)
		var hand: Array = gs.get("hand") as Array
		hand.append("npc_ajie")
		var r: Dictionary = gs.call("delegate", "d17_19_prescription", "ask_ajie", "npc_ajie")
		var got_doc: bool = bool(gs.call("has_card", "doc_prescription"))
		if bool(r.get("ok", false)) and got_doc:
			_ok("第 %d 天委託阿婕完成處方，取得 doc_prescription" % d)
		else:
			failed += _fail("第 %d 天處方無法完成：ok=%s doc=%s reason=%s" % [d, str(r.get("ok")), str(got_doc), str(r.get("reason_code"))])

	return failed


# ─── 9. 任一路線完成後，後續日不再重開 ───
func _test_prescription_no_repeat_subsequent_day(gs: Node, data_node: Node) -> int:
	print("\n--- 9. 處方任一路線完成後，後續日不再重開 ---")
	var failed: int = 0
	_reset_gs(gs)
	var hand: Array = gs.get("hand") as Array
	hand.append("npc_ajie")
	var r17: Dictionary = gs.call("delegate", "d17_19_prescription", "ask_ajie", "npc_ajie")

	# 進入次日：choices／slots_placed 屬 run 層，不隨換日清；delegates_used_today 每日重置。
	# 因此若再次嘗試被擋，原因必為 choice_group 已結算（already_resolved），而非今日已受託。
	gs.set("day", 18)
	(gs.get("delegates_used_today") as Dictionary).clear()

	var panel_d18: Dictionary = gs.call("build_panel", "sanquan")
	var self_view := _find_slot_view(panel_d18, "d17_19_prescription", "find_self")
	var self_not_open := self_view.is_empty() or int(self_view.get("tri", -1)) != PanelBuilder.TriState.OPEN
	var ajie_view := _find_slot_view(panel_d18, "d17_19_prescription", "ask_ajie")
	var no_open_ajie_candidate := ajie_view.is_empty() or int(ajie_view.get("tri", -1)) != PanelBuilder.TriState.OPEN

	var retry: Dictionary = gs.call("delegate", "d17_19_prescription", "ask_ajie", "npc_ajie")
	var rejected_resolved := not bool(retry.get("ok", true)) and str(retry.get("reason_code", "")) == "already_resolved"

	if bool(r17.get("ok", false)) and self_not_open and no_open_ajie_candidate and rejected_resolved:
		_ok("D17 委託完成後，D18 處方 choice_group 維持結算：find_self 非 OPEN、無 OPEN 委託候選、再委託回 already_resolved")
	else:
		failed += _fail("跨日不重複不符：r17=%s self_not_open=%s no_open_ajie=%s retry_ok=%s reason=%s" % [str(r17.get("ok")), str(self_not_open), str(no_open_ajie_candidate), str(retry.get("ok")), str(retry.get("reason_code"))])

	return failed


# ─── 10. 候選排序照資料、不因狀態（取得順序）變化跳動 ───
func _test_candidate_stable_ordering(gs: Node, data_node: Node) -> int:
	print("\n--- 10. 候選排序照資料、不因狀態變化跳動 ---")
	var failed: int = 0
	_reset_gs(gs)
	var hand: Array = gs.get("hand") as Array

	# 只持有阿財：候選＝[find_self, ask_acai]（阿婕／阿珠靠 has_card 隱藏）
	hand.append("npc_acai")
	var order_acai := _prescription_slot_order(gs)

	# 再取得阿婕：新候選 ask_ajie 應插回資料位（find_self 與 ask_acai 之間），非接尾端
	hand.append("npc_ajie")
	var order_ajie := _prescription_slot_order(gs)

	# 再取得阿珠：ask_azhu 亦插回資料位
	hand.append("npc_azhu")
	var order_all := _prescription_slot_order(gs)

	var ok_acai := order_acai == PackedStringArray(["find_self", "ask_acai"])
	var ok_ajie := order_ajie == PackedStringArray(["find_self", "ask_ajie", "ask_acai"])
	var ok_all := order_all == PackedStringArray(["find_self", "ask_ajie", "ask_azhu", "ask_acai"])

	if ok_acai and ok_ajie and ok_all:
		_ok("候選永遠照資料槽序：新出現的候選插回資料位置，不因取得順序改變排序")
	else:
		failed += _fail("排序不穩定：acai=%s ajie=%s all=%s" % [str(order_acai), str(order_ajie), str(order_all)])

	return failed


func _prescription_slot_order(gs: Node) -> PackedStringArray:
	var panel: Dictionary = gs.call("build_panel", "sanquan")
	var order := PackedStringArray()
	for beat_view: Dictionary in panel.get("beats", []) as Array:
		if str((beat_view["beat"] as Dictionary).get("id", "")) != "d17_19_prescription":
			continue
		for slot_view: Dictionary in beat_view.get("slots", []) as Array:
			order.append(str((slot_view["slot"] as Dictionary).get("id", "")))
	return order
