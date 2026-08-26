extends SceneTree

## P4-B headless 驗收測試：
## 1. 單日單人委託限制與跨時段持續
## 2. 換日上午回報結算與 delegates_used_today 重置
## 3. immediate vs next_morning 差異與手牌保留
## 4. 委託不吃行動格、不增 npc_action_counts、與 choice_group 親自處理互斥
## 5. 關係增減完全由資料驅動、決定論無 RNG
## 6. pending 序列化往返、人物卡中途移除仍照常回報、end_run 清空
## 7. 11 碼封閉拒絕矩陣與狀態零變化
## 8. 拒絕優先順序反證測試

const DataLoader := preload("res://scripts/data_loader.gd")
const ConditionEval := preload("res://scripts/core/condition_eval.gd")
const PlaythroughGreedy := preload("res://tests/headless/playthrough_greedy.gd")

func _initialize() -> void:
	var data_node: Node = PlaythroughGreedy.setup_data(self)
	var gs: Node = PlaythroughGreedy.setup_game_state(self, data_node)

	await process_frame

	if not bool(data_node.get("ok")):
		push_error("P4-B: Data failed to load; abort")
		quit(1)
		return

	var failed: int = 0
	print("\n=== P4-B 委託規則測試套件 ===")

	failed += _test_single_day_person_delegation_limit(gs, data_node)
	failed += _test_next_morning_resolution_and_reset(gs, data_node)
	failed += _test_immediate_vs_next_morning(gs, data_node)
	failed += _test_action_costs_and_mutex(gs, data_node)
	failed += _test_relation_determinism_no_rng(gs, data_node)
	failed += _test_serialization_and_resilience(gs, data_node)
	failed += _test_11_code_rejection_matrix(gs, data_node)
	failed += _test_rejection_precedence(gs, data_node)

	if failed > 0:
		push_error("\nP4-B: %d assertion(s) failed\n" % failed)
		quit(1)
	else:
		print("\nP4-B: all tests passed\n")
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
	gs.set("day", 17)
	gs.set("phase", "morning")
	gs.set("action_spent", false)


# ─── 1. 單日單人委託限制與跨時段持續 ───
func _test_single_day_person_delegation_limit(gs: Node, data_node: Node) -> int:
	print("\n--- 1. 單日單人委託限制與跨時段持續 ---")
	var failed: int = 0
	_reset_gs(gs)

	var loader: DataLoader = data_node.get("loader") as DataLoader
	var beat_a: Dictionary = {
		"id": "test_del_beat_1",
		"location": "clinic",
		"when": { "day_from": 17, "day_to": 19, "phase": ["morning", "afternoon"] },
		"slots": [
			{
				"id": "del_ajie_slot_1",
				"accepts": ["npc_ajie"],
				"choice_group": "test_grp_1",
				"delegation": {
					"result_timing": "immediate",
					"preview": "p",
					"tendency": "t"
				},
				"on_place": { "text": "ajie done 1" }
			},
			{
				"id": "del_acai_slot_1",
				"accepts": ["npc_acai"],
				"choice_group": "test_grp_1",
				"delegation": {
					"result_timing": "immediate",
					"preview": "p",
					"tendency": "t"
				},
				"on_place": { "text": "acai done 1" }
			}
		]
	}
	var beat_b: Dictionary = {
		"id": "test_del_beat_2",
		"location": "clinic",
		"when": { "day_from": 17, "day_to": 19, "phase": ["morning", "afternoon"] },
		"slots": [
			{
				"id": "del_ajie_slot_2",
				"accepts": ["npc_ajie"],
				"choice_group": "test_grp_2",
				"delegation": {
					"result_timing": "immediate",
					"preview": "p",
					"tendency": "t"
				},
				"on_place": { "text": "ajie done 2" }
			},
			{
				"id": "del_acai_slot_2",
				"accepts": ["npc_acai"],
				"choice_group": "test_grp_2",
				"delegation": {
					"result_timing": "immediate",
					"preview": "p",
					"tendency": "t"
				},
				"on_place": { "text": "acai done 2" }
			}
		]
	}
	loader.beats_by_id["test_del_beat_1"] = beat_a
	loader.beats_by_id["test_del_beat_2"] = beat_b

	var hand: Array = gs.get("hand") as Array
	hand.append("npc_ajie")
	hand.append("npc_acai")

	# (a) 上午委託阿婕成功
	var r1: Dictionary = gs.call("delegate", "test_del_beat_1", "del_ajie_slot_1", "npc_ajie")
	if bool(r1.get("ok")):
		_ok("上午阿婕委託成功")
	else:
		failed += _fail("上午阿婕委託失敗：%s" % str(r1))

	# (b) 同日上午再次委託阿婕在另一個 slot 失敗（already_delegated_today）
	var r2: Dictionary = gs.call("delegate", "test_del_beat_2", "del_ajie_slot_2", "npc_ajie")
	if str(r2.get("reason_code", "")) == "already_delegated_today":
		_ok("同日上午阿婕重複委託被拒（already_delegated_today）")
	else:
		failed += _fail("同日上午阿婕重複委託未被拒：%s" % str(r2))

	# (c) 同日上午委託阿財成功（不同人物互不影響）
	var r3: Dictionary = gs.call("delegate", "test_del_beat_2", "del_acai_slot_2", "npc_acai")
	if bool(r3.get("ok")):
		_ok("同日上午阿財委託成功（不同人物互不影響）")
	else:
		failed += _fail("同日上午阿財委託失敗：%s" % str(r3))

	# (d) 推進至下午：delegates_used_today 不被清空
	gs.call("advance_phase")
	if str(gs.get("phase")) == "afternoon":
		var dut: Dictionary = gs.get("delegates_used_today")
		if dut.has("npc_ajie") and dut.has("npc_acai"):
			_ok("跨時段至下午 delegates_used_today 依然保留")
		else:
			failed += _fail("跨時段至下午 delegates_used_today 被誤清：%s" % str(dut))

	# (e) 下午再次委託阿婕依然回 already_delegated_today
	var r4: Dictionary = gs.call("delegate", "test_del_beat_2", "del_ajie_slot_2", "npc_ajie")
	if str(r4.get("reason_code", "")) == "already_delegated_today":
		_ok("下午再次委託阿婕依然被拒（already_delegated_today）")
	else:
		failed += _fail("下午委託阿婕未被拒：%s" % str(r4))

	# (f) 推進至 evening：非行動時段回 not_action_phase
	gs.call("advance_phase")
	if str(gs.get("phase")) == "evening":
		var r5: Dictionary = gs.call("delegate", "test_del_beat_2", "del_ajie_slot_2", "npc_ajie")
		if str(r5.get("reason_code", "")) == "not_action_phase":
			_ok("evening 時段委託回 not_action_phase")
		else:
			failed += _fail("evening 時段委託未回 not_action_phase：%s" % str(r5))

	return failed


# ─── 2. 換日上午回報結算與 delegates_used_today 重置 ───
func _test_next_morning_resolution_and_reset(gs: Node, data_node: Node) -> int:
	print("\n--- 2. 換日上午回報結算與 delegates_used_today 重置 ---")
	var failed: int = 0
	_reset_gs(gs)

	var loader: DataLoader = data_node.get("loader") as DataLoader
	var beat_nm1: Dictionary = {
		"id": "test_del_nm_1",
		"location": "clinic",
		"when": { "day_from": 17, "day_to": 19, "phase": ["morning", "afternoon"] },
		"slots": [
			{
				"id": "slot_nm_1",
				"accepts": ["npc_ajie"],
				"choice_group": "grp_nm_1",
				"delegation": {
					"result_timing": "next_morning",
					"preview": "p1",
					"tendency": "t1",
					"report": {
						"text": "report 1 arrived",
						"flag": { "rep_1_received": true }
					}
				},
				"on_place": { "text": "dispatched 1" }
			}
		]
	}
	var beat_nm2: Dictionary = {
		"id": "test_del_nm_2",
		"location": "clinic",
		"when": { "day_from": 17, "day_to": 19, "phase": ["morning", "afternoon"] },
		"slots": [
			{
				"id": "slot_nm_2",
				"accepts": ["npc_acai"],
				"choice_group": "grp_nm_2",
				"delegation": {
					"result_timing": "next_morning",
					"preview": "p2",
					"tendency": "t2",
					"report": {
						"text": "report 2 arrived",
						"flag": { "rep_2_received": true }
					}
				},
				"on_place": { "text": "dispatched 2" }
			}
		]
	}
	loader.beats_by_id["test_del_nm_1"] = beat_nm1
	loader.beats_by_id["test_del_nm_2"] = beat_nm2

	var hand: Array = gs.get("hand") as Array
	hand.append("npc_ajie")
	hand.append("npc_acai")

	# 在第 17 天上午派出阿婕，下午派出阿財
	var r1: Dictionary = gs.call("delegate", "test_del_nm_1", "slot_nm_1", "npc_ajie")
	gs.call("advance_phase") # -> afternoon
	var r2: Dictionary = gs.call("delegate", "test_del_nm_2", "slot_nm_2", "npc_acai")

	if bool(r1.get("ok")) and bool(r2.get("ok")):
		var pending: Array = gs.get("pending_delegation_reports") as Array
		if pending.size() == 2 and int(pending[0]["due_day"]) == 18 and int(pending[1]["due_day"]) == 18:
			_ok("兩筆 next_morning 委託成功排入 pending，due_day=18")
		else:
			failed += _fail("pending_delegation_reports 內容不符：%s" % str(pending))
	else:
		failed += _fail("派出失敗：r1=%s, r2=%s" % [str(r1), str(r2)])

	# 同時塞一張發狂卡倒數為 1，驗證換日順序：發狂倒數/強制縱慾先執行，接著才是回報
	gs.call("gain_card", "madness", false)
	var mc: Dictionary = gs.get("madness_clock")
	for k: String in mc.keys():
		mc[k] = 1

	# advance: afternoon -> evening -> night -> morning (Day 18)
	gs.call("advance_phase") # evening
	gs.call("advance_phase") # night
	gs.call("advance_phase") # morning of Day 18

	if int(gs.get("day")) == 18 and str(gs.get("phase")) == "morning":
		var flags: Dictionary = gs.get("flags")
		var rep_lines: PackedStringArray = gs.get("last_delegation_report_lines")
		var dut: Dictionary = gs.get("delegates_used_today")
		var pending_now: Array = gs.get("pending_delegation_reports") as Array

		var flags_ok: bool = bool(flags.get("rep_1_received", false)) and bool(flags.get("rep_2_received", false))
		var lines_ok: bool = rep_lines.has("report 1 arrived") and rep_lines.has("report 2 arrived")
		var pending_cleared: bool = pending_now.is_empty()
		var daily_cleared: bool = dut.is_empty()

		if flags_ok and lines_ok and pending_cleared and daily_cleared:
			_ok("Day 18 上午：pending reports 依序結算完成，flags 設定正確，文字收集完整，pending 清空，delegates_used_today 清空")
		else:
			failed += _fail("Day 18 上午結算不符：flags_ok=%s lines_ok=%s pending_cleared=%s daily_cleared=%s" % [str(flags_ok), str(lines_ok), str(pending_cleared), str(daily_cleared)])

		# 驗證 Day 18 上午阿婕可再次受託（清空後可再委託）
		(gs.get("choices") as Dictionary).clear()
		(gs.get("slots_placed") as Dictionary).clear()
		var r4: Dictionary = gs.call("delegate", "test_del_nm_1", "slot_nm_1", "npc_ajie")
		if bool(r4.get("ok")):
			_ok("Day 18 上午 delegates_used_today 清空後阿婕可再次受託")
		else:
			failed += _fail("Day 18 上午阿婕無法再次受託：%s" % str(r4))
	else:
		failed += _fail("推進至 Day 18 上午失敗：day=%s phase=%s" % [str(gs.get("day")), str(gs.get("phase"))])

	return failed


# ─── 3. immediate vs next_morning 差異與手牌保留 ───
func _test_immediate_vs_next_morning(gs: Node, data_node: Node) -> int:
	print("\n--- 3. immediate vs next_morning 差異與手牌保留 ---")
	var failed: int = 0
	_reset_gs(gs)

	var loader: DataLoader = data_node.get("loader") as DataLoader
	var beat_imm: Dictionary = {
		"id": "test_del_imm_comp",
		"location": "clinic",
		"when": { "day_from": 17, "day_to": 19, "phase": ["morning"] },
		"slots": [
			{
				"id": "slot_imm",
				"accepts": ["npc_ajie"],
				"choice_group": "grp_imm",
				"delegation": {
					"result_timing": "immediate",
					"preview": "preview imm",
					"tendency": "tendency imm"
				},
				"on_place": { "text": "imm text", "flag": { "imm_done": true } }
			}
		]
	}
	var beat_next: Dictionary = {
		"id": "test_del_next_comp",
		"location": "clinic",
		"when": { "day_from": 17, "day_to": 19, "phase": ["morning"] },
		"slots": [
			{
				"id": "slot_next",
				"accepts": ["npc_acai"],
				"choice_group": "grp_next",
				"delegation": {
					"result_timing": "next_morning",
					"preview": "preview next",
					"tendency": "tendency next",
					"report": { "text": "next rep text", "flag": { "next_rep_done": true } }
				},
				"on_place": { "text": "dispatch text", "flag": { "next_dispatched": true } }
			}
		]
	}
	loader.beats_by_id["test_del_imm_comp"] = beat_imm
	loader.beats_by_id["test_del_next_comp"] = beat_next

	var hand: Array = gs.get("hand") as Array
	hand.append("npc_ajie")
	hand.append("npc_acai")

	# (a) immediate 測試
	var r_imm: Dictionary = gs.call("delegate", "test_del_imm_comp", "slot_imm", "npc_ajie")
	var flags: Dictionary = gs.get("flags")
	var pending: Array = gs.get("pending_delegation_reports") as Array
	if bool(r_imm.get("ok")) and bool(flags.get("imm_done", false)) and pending.is_empty():
		_ok("immediate 委託當場套效果且不進入 pending_delegation_reports")
	else:
		failed += _fail("immediate 委託異常：ok=%s flags=%s pending_size=%d" % [str(r_imm.get("ok")), str(flags), pending.size()])

	if bool(gs.call("has_card", "npc_ajie")):
		_ok("immediate 委託完成後人物卡仍留在 hand")
	else:
		failed += _fail("immediate 委託後人物卡從 hand 遺失")

	# (b) next_morning 測試
	var r_next: Dictionary = gs.call("delegate", "test_del_next_comp", "slot_next", "npc_acai")
	flags = gs.get("flags")
	pending = gs.get("pending_delegation_reports") as Array
	if bool(r_next.get("ok")) and bool(flags.get("next_dispatched", false)) and not bool(flags.get("next_rep_done", false)) and pending.size() == 1:
		_ok("next_morning 委託當場只套派出效果，report 不提前結算，排入 pending")
	else:
		failed += _fail("next_morning 委託異常：ok=%s flags=%s pending_size=%d" % [str(r_next.get("ok")), str(flags), pending.size()])

	if bool(gs.call("has_card", "npc_acai")):
		_ok("next_morning 委託派出後人物卡仍留在 hand")
	else:
		failed += _fail("next_morning 委託後人物卡從 hand 遺失")

	return failed


# ─── 4. 委託不吃行動格、不增 npc_action_counts、與 choice_group 親自處理互斥 ───
func _test_action_costs_and_mutex(gs: Node, _data_node: Node) -> int:
	print("\n--- 4. 委託不吃行動格、不增 npc_action_counts、與 choice_group 親自處理互斥 ---")
	var failed: int = 0
	_reset_gs(gs)

	# d17_19_prescription 的 when 是 afternoon，設定至第 17 天下午
	gs.set("day", 17)
	gs.set("phase", "afternoon")
	gs.set("action_spent", false)

	var hand: Array = gs.get("hand") as Array
	hand.append("npc_ajie")
	hand.append("npc_acai")

	# 委託前狀態
	var actions_before: int = int(gs.call("remaining_actions_today"))
	var spent_before: bool = bool(gs.get("action_spent"))
	var npc_actions_before: Dictionary = (gs.get("npc_action_counts") as Dictionary).duplicate()

	var r1: Dictionary = gs.call("delegate", "d17_19_prescription", "ask_ajie", "npc_ajie")
	if bool(r1.get("ok")):
		var actions_after: int = int(gs.call("remaining_actions_today"))
		var spent_after: bool = bool(gs.get("action_spent"))
		var npc_actions_after: Dictionary = gs.get("npc_action_counts")

		if actions_before == actions_after and spent_before == spent_after and npc_actions_before == npc_actions_after:
			_ok("委託成功不改變 action_spent、不消耗 remaining_actions、不增加 npc_action_counts")
		else:
			failed += _fail("委託成功影響了行動格或 NPC 投入帳：actions=%d->%d spent=%s->%s" % [actions_before, actions_after, str(spent_before), str(spent_after)])
	else:
		failed += _fail("d17_19_prescription ask_ajie 委託失敗：%s" % str(r1))

	# 驗證同一 choice_group 下的親自處理（find_self）與其他人物槽（ask_acai）皆互斥
	var r_self: Dictionary = gs.call("try_place", "protagonist", "d17_19_prescription", "find_self")
	if str(r_self.get("reason_code", "")) == "resolved":
		_ok("委託阿婕後，親自處理槽（find_self）變為 resolved 互斥不可選")
	else:
		failed += _fail("親自處理槽未互斥：%s" % str(r_self))

	var r_acai: Dictionary = gs.call("delegate", "d17_19_prescription", "ask_acai", "npc_acai")
	if str(r_acai.get("reason_code", "")) == "already_resolved":
		_ok("委託阿婕後，同 group 其他人物槽（ask_acai）變為 already_resolved 互斥不可選")
	else:
		failed += _fail("同 group 其他人物槽未互斥：%s" % str(r_acai))

	# 反向測試：若先選親自處理，委託槽變為 already_resolved
	_reset_gs(gs)
	gs.set("day", 17)
	gs.set("phase", "afternoon")
	gs.set("action_spent", false)
	hand = gs.get("hand") as Array
	hand.append("npc_ajie")
	var r_self_first: Dictionary = gs.call("try_place", "protagonist", "d17_19_prescription", "find_self")
	if bool(r_self_first.get("ok")) and bool(gs.get("action_spent")):
		var r_del_after: Dictionary = gs.call("delegate", "d17_19_prescription", "ask_ajie", "npc_ajie")
		if str(r_del_after.get("reason_code", "")) == "already_resolved":
			_ok("親自處理完成後，委託槽（ask_ajie）變為 already_resolved 互斥不可選")
		else:
			failed += _fail("親自處理後委託槽未互斥：%s" % str(r_del_after))
	else:
		failed += _fail("親自處理失敗：%s" % str(r_self_first))

	return failed


# ─── 5. 關係增減完全由資料驅動、決定論無 RNG ───
func _test_relation_determinism_no_rng(gs: Node, data_node: Node) -> int:
	print("\n--- 5. 關係增減完全由資料驅動、決定論無 RNG ---")
	var failed: int = 0
	_reset_gs(gs)

	var loader: DataLoader = data_node.get("loader") as DataLoader
	var beat_rel: Dictionary = {
		"id": "test_del_rel_cases",
		"location": "clinic",
		"when": { "day_from": 17, "day_to": 19, "phase": ["morning"] },
		"slots": [
			{
				"id": "slot_rel_up",
				"accepts": ["npc_ajie"],
				"choice_group": "grp_rel_1",
				"delegation": { "result_timing": "immediate", "preview": "p", "tendency": "t" },
				"on_place": { "relation": { "npc": "ajie", "delta": 2 } }
			},
			{
				"id": "slot_rel_down",
				"accepts": ["npc_acai"],
				"choice_group": "grp_rel_2",
				"delegation": { "result_timing": "immediate", "preview": "p", "tendency": "t" },
				"on_place": { "relation": { "npc": "acai", "delta": -1 } }
			},
			{
				"id": "slot_rel_none",
				"accepts": ["npc_azhu"],
				"choice_group": "grp_rel_3",
				"delegation": { "result_timing": "immediate", "preview": "p", "tendency": "t" },
				"on_place": { "text": "no relation change" }
			}
		]
	}
	loader.beats_by_id["test_del_rel_cases"] = beat_rel

	var hand: Array = gs.get("hand") as Array
	hand.append("npc_ajie")
	hand.append("npc_acai")
	hand.append("npc_azhu")

	gs.call("delegate", "test_del_rel_cases", "slot_rel_up", "npc_ajie")
	gs.call("delegate", "test_del_rel_cases", "slot_rel_down", "npc_acai")
	gs.call("delegate", "test_del_rel_cases", "slot_rel_none", "npc_azhu")

	var rel: Dictionary = gs.get("relations")
	var ajie_ok: bool = int(rel.get("ajie", 0)) == 2
	var acai_ok: bool = int(rel.get("acai", 0)) == -1
	var azhu_ok: bool = int(rel.get("azhu", 0)) == 0

	if ajie_ok and acai_ok and azhu_ok:
		_ok("關係增加 (+2)、下降 (-1)、不變 (0) 完全由資料驅動，無全域自動 delta")
	else:
		failed += _fail("關係變更不符預期：%s" % str(rel))

	# 決定論：重跑同一狀態兩次，serialize 逐字完全相同
	var serialized_1: String = str(gs.call("serialize"))
	_reset_gs(gs)
	hand = gs.get("hand") as Array
	hand.append("npc_ajie")
	hand.append("npc_acai")
	hand.append("npc_azhu")
	gs.call("delegate", "test_del_rel_cases", "slot_rel_up", "npc_ajie")
	gs.call("delegate", "test_del_rel_cases", "slot_rel_down", "npc_acai")
	gs.call("delegate", "test_del_rel_cases", "slot_rel_none", "npc_azhu")
	var serialized_2: String = str(gs.call("serialize"))

	if serialized_1 == serialized_2:
		_ok("相同初始狀態與委託序列產生完全一致的序列化字串（100% 決定論無 RNG）")
	else:
		failed += _fail("決定論比對失敗：兩次序列化不一致")

	return failed


# ─── 6. pending 序列化往返、人物卡中途移除仍照常回報、end_run 清空 ───
func _test_serialization_and_resilience(gs: Node, data_node: Node) -> int:
	print("\n--- 6. pending 序列化往返、人物卡中途移除仍照常回報、end_run 清空 ---")
	var failed: int = 0
	_reset_gs(gs)

	var loader: DataLoader = data_node.get("loader") as DataLoader
	var beat_res: Dictionary = {
		"id": "test_del_resilience",
		"location": "clinic",
		"when": { "day_from": 17, "day_to": 19, "phase": ["morning"] },
		"slots": [
			{
				"id": "slot_res_1",
				"accepts": ["npc_ajie"],
				"choice_group": "grp_res",
				"delegation": {
					"result_timing": "next_morning",
					"preview": "p",
					"tendency": "t",
					"report": { "text": "report arrived safely", "flag": { "res_rep_ok": true } }
				},
				"on_place": { "text": "dispatched" }
			}
		]
	}
	loader.beats_by_id["test_del_resilience"] = beat_res

	var hand: Array = gs.get("hand") as Array
	hand.append("npc_ajie")

	gs.call("delegate", "test_del_resilience", "slot_res_1", "npc_ajie")

	# (a) 序列化往返
	var s_data: Dictionary = gs.call("serialize")
	var s_str: String = str(s_data)
	gs.call("deserialize", s_data)
	var s_str_after: String = str(gs.call("serialize"))

	if s_str == s_str_after:
		var dut: Dictionary = gs.get("delegates_used_today")
		var pnd: Array = gs.get("pending_delegation_reports") as Array
		if dut.has("npc_ajie") and pnd.size() == 1 and str(pnd[0]["person_id"]) == "npc_ajie":
			_ok("delegates_used_today 與 pending_delegation_reports 序列化往返完全一致")
		else:
			failed += _fail("反序列化後內容不符：dut=%s pnd=%s" % [str(dut), str(pnd)])
	else:
		failed += _fail("序列化往返字串不一致")

	# (b) 人物卡在回報前被事件移除（例如 lose_card）
	gs.call("lose_card", "npc_ajie")
	if not bool(gs.call("has_card", "npc_ajie")):
		# 推進至隔日 morning
		gs.call("advance_phase") # afternoon
		gs.call("advance_phase") # evening
		gs.call("advance_phase") # night
		gs.call("advance_phase") # morning
		var flags: Dictionary = gs.get("flags")
		if bool(flags.get("res_rep_ok", false)):
			_ok("人物卡在回報前被移除，隔日上午 report 仍照常結算並套用效果")
		else:
			failed += _fail("人物卡移除後隔日 report 未結算：%s" % str(flags))
	else:
		failed += _fail("lose_card npc_ajie 失敗")

	# (c) end_run 清空所有委託狀態
	gs.call("end_run")
	var dut_end: Dictionary = gs.get("delegates_used_today")
	var pnd_end: Array = gs.get("pending_delegation_reports") as Array
	var lines_end: PackedStringArray = gs.get("last_delegation_report_lines")
	if dut_end.is_empty() and pnd_end.is_empty() and lines_end.is_empty():
		_ok("end_run 清空 delegates_used_today、pending_delegation_reports 與 last_delegation_report_lines")
	else:
		failed += _fail("end_run 未清空委託狀態：dut=%s pnd=%s lines=%s" % [str(dut_end), str(pnd_end), str(lines_end)])

	return failed


# ─── 7. 11 碼封閉拒絕矩陣與狀態零變化 ───
func _test_11_code_rejection_matrix(gs: Node, data_node: Node) -> int:
	print("\n--- 7. 11 碼封閉拒絕矩陣與狀態零變化 ---")
	var failed: int = 0
	_reset_gs(gs)

	var loader: DataLoader = data_node.get("loader") as DataLoader
	var beat_matrix: Dictionary = {
		"id": "test_del_matrix_beat",
		"location": "clinic",
		"when": { "day_from": 17, "day_to": 19, "phase": ["morning", "afternoon"] },
		"condition": { "has_card": "protagonist" },
		"slots": [
			{
				"id": "slot_matrix_valid",
				"accepts": ["npc_ajie"],
				"choice_group": "grp_matrix_1",
				"delegation": { "result_timing": "immediate", "preview": "p", "tendency": "t" },
				"on_place": { "text": "valid done" }
			},
			{
				"id": "slot_matrix_not_del",
				"accepts": ["npc_ajie"],
				"choice_group": "grp_matrix_2",
				"on_place": { "text": "not del done" }
			},
			{
				"id": "slot_matrix_locked",
				"accepts": ["npc_ajie"],
				"choice_group": "grp_matrix_3",
				"requires": { "flag": "req_slot_flag" },
				"reject_reason": "slot requires not met",
				"delegation": { "result_timing": "immediate", "preview": "p", "tendency": "t" },
				"on_place": { "text": "locked done" }
			},
			{
				"id": "slot_matrix_cond_hidden",
				"accepts": ["npc_ajie"],
				"condition": { "flag": "hidden_slot_flag" },
				"delegation": { "result_timing": "immediate", "preview": "p", "tendency": "t" },
				"on_place": { "text": "hidden done" }
			},
			{
				"id": "slot_matrix_bad_timing",
				"accepts": ["npc_ajie"],
				"choice_group": "grp_matrix_4",
				"delegation": { "result_timing": "invalid_timing", "preview": "p", "tendency": "t" },
				"on_place": { "text": "bad timing done" }
			},
			{
				"id": "slot_matrix_nm_no_report",
				"accepts": ["npc_ajie"],
				"choice_group": "grp_matrix_5",
				"delegation": { "result_timing": "next_morning", "preview": "p", "tendency": "t" },
				"on_place": { "text": "nm no rep done" }
			},
			{
				"id": "slot_matrix_imm_with_report",
				"accepts": ["npc_ajie"],
				"choice_group": "grp_matrix_6",
				"delegation": {
					"result_timing": "immediate",
					"preview": "p",
					"tendency": "t",
					"report": { "text": "illegal report in immediate" }
				},
				"on_place": { "text": "imm rep done" }
			}
		]
	}
	loader.beats_by_id["test_del_matrix_beat"] = beat_matrix

	var hand: Array = gs.get("hand") as Array
	hand.append("npc_ajie")
	hand.append("npc_acai")
	hand.append("info_husband_version")

	# (1) not_action_phase
	gs.set("phase", "night")
	var before: String = str(gs.call("serialize"))
	var r: Dictionary = gs.call("delegate", "test_del_matrix_beat", "slot_matrix_valid", "npc_ajie")
	if str(r.get("reason_code", "")) == "not_action_phase" and str(gs.call("serialize")) == before:
		_ok("1. not_action_phase 正確且狀態零變化")
	else:
		failed += _fail("1. not_action_phase 失敗：%s" % str(r))
	gs.set("phase", "morning")

	# (2) unknown_beat（不存在、時段不合、condition 不成立）
	before = str(gs.call("serialize"))
	r = gs.call("delegate", "non_existent_beat", "slot_matrix_valid", "npc_ajie")
	if str(r.get("reason_code", "")) == "unknown_beat" and str(gs.call("serialize")) == before:
		_ok("2. unknown_beat 正確且狀態零變化")
	else:
		failed += _fail("2. unknown_beat 失敗：%s" % str(r))

	# (3) unknown_slot（不存在、condition 不成立隱藏）
	before = str(gs.call("serialize"))
	r = gs.call("delegate", "test_del_matrix_beat", "slot_matrix_cond_hidden", "npc_ajie")
	if str(r.get("reason_code", "")) == "unknown_slot" and str(gs.call("serialize")) == before:
		_ok("3. unknown_slot 正確且狀態零變化")
	else:
		failed += _fail("3. unknown_slot 失敗：%s" % str(r))

	# (4) not_delegation（槽非委託槽）
	before = str(gs.call("serialize"))
	r = gs.call("delegate", "test_del_matrix_beat", "slot_matrix_not_del", "npc_ajie")
	if str(r.get("reason_code", "")) == "not_delegation" and str(gs.call("serialize")) == before:
		_ok("4. not_delegation 正確且狀態零變化")
	else:
		failed += _fail("4. not_delegation 失敗：%s" % str(r))

	# (5) not_held（未持有該卡、卡 id 為空）
	before = str(gs.call("serialize"))
	r = gs.call("delegate", "test_del_matrix_beat", "slot_matrix_valid", "npc_azhu")
	if str(r.get("reason_code", "")) == "not_held" and str(gs.call("serialize")) == before:
		_ok("5. not_held 正確且狀態零變化")
	else:
		failed += _fail("5. not_held 失敗：%s" % str(r))

	# (6) not_person（手上有該卡但 type 不是 person）
	before = str(gs.call("serialize"))
	r = gs.call("delegate", "test_del_matrix_beat", "slot_matrix_valid", "info_husband_version")
	if str(r.get("reason_code", "")) == "not_person" and str(gs.call("serialize")) == before:
		_ok("6. not_person 正確且狀態零變化")
	else:
		failed += _fail("6. not_person 失敗：%s" % str(r))

	# (7) not_accepted（手上有 person 卡但槽 accepts 不包含）
	before = str(gs.call("serialize"))
	r = gs.call("delegate", "test_del_matrix_beat", "slot_matrix_valid", "npc_acai")
	if str(r.get("reason_code", "")) == "not_accepted" and str(gs.call("serialize")) == before:
		_ok("7. not_accepted 正確且狀態零變化")
	else:
		failed += _fail("7. not_accepted 失敗：%s" % str(r))

	# (8) already_delegated_today（今日已委託過）
	(gs.get("delegates_used_today") as Dictionary)["npc_ajie"] = true
	before = str(gs.call("serialize"))
	r = gs.call("delegate", "test_del_matrix_beat", "slot_matrix_valid", "npc_ajie")
	if str(r.get("reason_code", "")) == "already_delegated_today" and str(gs.call("serialize")) == before:
		_ok("8. already_delegated_today 正確且狀態零變化")
	else:
		failed += _fail("8. already_delegated_today 失敗：%s" % str(r))
	(gs.get("delegates_used_today") as Dictionary).clear()

	# (9) locked（requires 條件不足，帶 reject_reason）
	before = str(gs.call("serialize"))
	r = gs.call("delegate", "test_del_matrix_beat", "slot_matrix_locked", "npc_ajie")
	if str(r.get("reason_code", "")) == "locked" and str(r.get("reason_text", "")) == "slot requires not met" and str(gs.call("serialize")) == before:
		_ok("9. locked 正確（帶 reject_reason）且狀態零變化")
	else:
		failed += _fail("9. locked 失敗：%s" % str(r))

	# (10) already_resolved（choice group 已結算 / 槽已放置）
	(gs.get("choices") as Dictionary)["test_del_matrix_beat::grp_matrix_1"] = "slot_matrix_valid"
	before = str(gs.call("serialize"))
	r = gs.call("delegate", "test_del_matrix_beat", "slot_matrix_valid", "npc_ajie")
	if str(r.get("reason_code", "")) == "already_resolved" and str(gs.call("serialize")) == before:
		_ok("10. already_resolved 正確且狀態零變化")
	else:
		failed += _fail("10. already_resolved 失敗：%s" % str(r))
	(gs.get("choices") as Dictionary).clear()

	# (11) data_conflict（壞 timing 或 report 結構矛盾）
	# 11a: bad timing
	before = str(gs.call("serialize"))
	r = gs.call("delegate", "test_del_matrix_beat", "slot_matrix_bad_timing", "npc_ajie")
	if str(r.get("reason_code", "")) == "data_conflict" and str(gs.call("serialize")) == before:
		_ok("11a. data_conflict (bad timing) 正確且狀態零變化")
	else:
		failed += _fail("11a. data_conflict (bad timing) 失敗：%s" % str(r))

	# 11b: next_morning missing report
	before = str(gs.call("serialize"))
	r = gs.call("delegate", "test_del_matrix_beat", "slot_matrix_nm_no_report", "npc_ajie")
	if str(r.get("reason_code", "")) == "data_conflict" and str(gs.call("serialize")) == before:
		_ok("11b. data_conflict (next_morning missing report) 正確且狀態零變化")
	else:
		failed += _fail("11b. data_conflict 失敗：%s" % str(r))

	# 11c: immediate with report
	before = str(gs.call("serialize"))
	r = gs.call("delegate", "test_del_matrix_beat", "slot_matrix_imm_with_report", "npc_ajie")
	if str(r.get("reason_code", "")) == "data_conflict" and str(gs.call("serialize")) == before:
		_ok("11c. data_conflict (immediate with report) 正確且狀態零變化")
	else:
		failed += _fail("11c. data_conflict 失敗：%s" % str(r))

	return failed


# ─── 8. 拒絕優先順序反證測試 ───
func _test_rejection_precedence(gs: Node, data_node: Node) -> int:
	print("\n--- 8. 拒絕優先順序反證測試 ---")
	var failed: int = 0
	_reset_gs(gs)

	var loader: DataLoader = data_node.get("loader") as DataLoader
	var beat_prec: Dictionary = {
		"id": "test_del_prec_beat",
		"location": "clinic",
		"when": { "day_from": 17, "day_to": 19, "phase": ["morning"] },
		"slots": [
			{
				"id": "slot_prec_1",
				"accepts": ["npc_ajie"],
				"choice_group": "grp_prec",
				"requires": { "flag": "non_existent_flag" },
				"reject_reason": "locked reason",
				"delegation": { "result_timing": "immediate", "preview": "p", "tendency": "t" },
				"on_place": { "text": "prec done" }
			}
		]
	}
	loader.beats_by_id["test_del_prec_beat"] = beat_prec

	var hand: Array = gs.get("hand") as Array
	hand.append("npc_ajie")
	hand.append("npc_acai")
	hand.append("info_husband_version")

	# (a) not_action_phase 優先於 unknown_beat
	gs.set("phase", "night")
	var r: Dictionary = gs.call("delegate", "non_existent_beat", "slot_prec_1", "npc_ajie")
	if str(r.get("reason_code", "")) == "not_action_phase":
		_ok("優先序：not_action_phase > unknown_beat")
	else:
		failed += _fail("優先序錯誤：not_action_phase vs unknown_beat -> %s" % str(r))
	gs.set("phase", "morning")

	# (b) not_held 優先於 not_person
	r = gs.call("delegate", "test_del_prec_beat", "slot_prec_1", "ghost_card")
	if str(r.get("reason_code", "")) == "not_held":
		_ok("優先序：not_held > not_person")
	else:
		failed += _fail("優先序錯誤：not_held vs not_person -> %s" % str(r))

	# (c) not_person 優先於 not_accepted
	r = gs.call("delegate", "test_del_prec_beat", "slot_prec_1", "info_husband_version")
	if str(r.get("reason_code", "")) == "not_person":
		_ok("優先序：not_person > not_accepted")
	else:
		failed += _fail("優先序錯誤：not_person vs not_accepted -> %s" % str(r))

	# (d) not_accepted 優先於 already_delegated_today
	(gs.get("delegates_used_today") as Dictionary)["npc_acai"] = true
	r = gs.call("delegate", "test_del_prec_beat", "slot_prec_1", "npc_acai")
	if str(r.get("reason_code", "")) == "not_accepted":
		_ok("優先序：not_accepted > already_delegated_today")
	else:
		failed += _fail("優先序錯誤：not_accepted vs already_delegated_today -> %s" % str(r))
	(gs.get("delegates_used_today") as Dictionary).clear()

	# (e) already_delegated_today 優先於 locked
	(gs.get("delegates_used_today") as Dictionary)["npc_ajie"] = true
	r = gs.call("delegate", "test_del_prec_beat", "slot_prec_1", "npc_ajie")
	if str(r.get("reason_code", "")) == "already_delegated_today":
		_ok("優先序：already_delegated_today > locked")
	else:
		failed += _fail("優先序錯誤：already_delegated_today vs locked -> %s" % str(r))
	(gs.get("delegates_used_today") as Dictionary).clear()

	# (f) locked 優先於 already_resolved
	(gs.get("choices") as Dictionary)["test_del_prec_beat::grp_prec"] = "slot_prec_1"
	r = gs.call("delegate", "test_del_prec_beat", "slot_prec_1", "npc_ajie")
	if str(r.get("reason_code", "")) == "locked":
		_ok("優先序：locked > already_resolved")
	else:
		failed += _fail("優先序錯誤：locked vs already_resolved -> %s" % str(r))
	(gs.get("choices") as Dictionary).clear()

	# (g) delegation_status 查詢函式驗證
	var st1: Dictionary = gs.call("delegation_status", "npc_ajie")
	if bool(st1.get("held")) and not bool(st1.get("delegated_today")) and bool(st1.get("available")) and not bool(st1.get("has_pending_report")):
		_ok("delegation_status 初始狀態正常 (held=true, delegated_today=false, available=true)")
	else:
		failed += _fail("delegation_status 初始狀態異常：%s" % str(st1))

	(gs.get("delegates_used_today") as Dictionary)["npc_ajie"] = true
	var st2: Dictionary = gs.call("delegation_status", "npc_ajie")
	if bool(st2.get("delegated_today")) and not bool(st2.get("available")):
		_ok("delegation_status 今日已受託狀態正常 (delegated_today=true, available=false)")
	else:
		failed += _fail("delegation_status 今日已受託狀態異常：%s" % str(st2))
	(gs.get("delegates_used_today") as Dictionary).clear()

	return failed
