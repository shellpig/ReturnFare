extends SceneTree

## P4-F headless 驗收測試：
## 1. D17～19 處方委託四種人物狀態覆蓋（零人物卡、阿婕、阿珠、阿財，涵蓋親自做、immediate、next_morning 與每日人物限制）
## 2. D8／D45 遭遇 Response Matrix 動態資料衍生測試（正解、錯答/fallback、逃離、丟棄、不可丟棄卡、推論卡特殊轉化、無合法解直接 failure）
## 3. 跨輪重置與第二輪持久化驗證（Meta 層保留、Run 層清空、D8 遭遇重演且不重收首次到訪費用、委託重置）
## 4. 跨輪決定論測試：同存檔重載兩次走相同第二輪操作序列，最終 serialize() 逐字完全相同

const DataLoader := preload("res://scripts/data_loader.gd")
const ConditionEval := preload("res://scripts/core/condition_eval.gd")
const PanelBuilder := preload("res://scripts/core/panel_builder.gd")
const DataFacts := preload("res://scripts/core/data_facts.gd")
const PlaythroughGreedy := preload("res://tests/headless/playthrough_greedy.gd")
const Indulgence := preload("res://scripts/core/indulgence.gd")


func _initialize() -> void:
	var data_node: Node = PlaythroughGreedy.setup_data(self)
	var gs: Node = PlaythroughGreedy.setup_game_state(self, data_node)

	await process_frame

	if not bool(data_node.get("ok")):
		push_error("P4-F: Data failed to load; abort")
		quit(1)
		return

	var failed := 0
	print("\n=== P4-F 全流程與跨輪整合測試 ===")

	failed += _test_d17_19_four_character_states(gs, data_node)
	failed += _test_encounter_matrix_derivation(gs, data_node)
	failed += _test_end_run_cleanup_and_second_run_persistence(gs, data_node)
	failed += _test_cross_run_determinism(gs, data_node)

	if failed > 0:
		push_error("\nP4-F: %d assertion(s) failed\n" % failed)
		quit(1)
	else:
		print("\nP4-F: all tests passed\n")
		quit(0)


func _ok(msg: String) -> int:
	print("  [OK] " + msg)
	return 0


func _fail(msg: String) -> int:
	push_error("  [FAIL] " + msg)
	return 1


static func _reset_gs(gs: Node) -> void:
	gs.call("end_run")
	gs.set("night_locations_seen", {})
	gs.set("night_once_beats_seen", {})
	gs.set("knowledge", {})
	gs.set("delegation_tutorial_seen", false)
	gs.set("night_location_chosen", "")
	gs.set("night_sleep_pending", false)
	gs.set("day", 1)
	gs.set("phase", "morning")


# ── 1. D17～19 處方委託四種人物狀態覆蓋 ──────────────────────────────────────

func _test_d17_19_four_character_states(gs: Node, data_node: Node) -> int:
	print("--- 1. D17-19 Prescription Delegation (4 character states) ---")
	var failed := 0

	# ── 狀態 1: 零人物卡（只有主角卡）──
	_reset_gs(gs)
	gs.set("day", 17)
	gs.set("phase", "afternoon")

	var panel_s1: Dictionary = gs.build_panel("sanquan")
	var pres_bv_s1: Dictionary = {}
	for bv: Dictionary in panel_s1.get("beats", []) as Array:
		if str((bv.get("beat", {}) as Dictionary).get("id", "")) == "d17_19_prescription":
			pres_bv_s1 = bv
			break

	if pres_bv_s1.is_empty():
		failed += _fail("狀態 1: D17 下午山泉閣未找到 d17_19_prescription beat")
	else:
		var slots_s1: Array = pres_bv_s1.get("slots", []) as Array
		var open_slots_s1: Array[String] = []
		for sv: Dictionary in slots_s1:
			if int(sv.get("tri", -1)) == PanelBuilder.TriState.OPEN:
				open_slots_s1.append(str((sv.get("slot", {}) as Dictionary).get("id", "")))

		if open_slots_s1.size() == 1 and open_slots_s1[0] == "find_self":
			failed += _ok("狀態 1 (零人物卡): 僅有親自處理槽 find_self 為 OPEN，其餘委託候選隱藏 (condition.has_card)")
		else:
			failed += _fail("狀態 1: OPEN 槽不符合預期: %s" % str(open_slots_s1))

		# 放置 find_self：消耗主角行動格、取得 doc_prescription、choice_group 結算
		var res_place: Dictionary = gs.try_place("protagonist", "d17_19_prescription", "find_self")
		if bool(res_place.get("ok", false)) and bool(gs.get("action_spent")) and gs.has_card("doc_prescription"):
			failed += _ok("狀態 1: 親自處理成功放置，消耗主角行動格且獲得 doc_prescription")
		else:
			failed += _fail("狀態 1 親自處理放置失敗: %s" % str(res_place))

		# choice_group prescription_route 互斥：同組委託槽已結算
		gs.gain_card("npc_ajie")
		var del_rej: Dictionary = gs.delegate("d17_19_prescription", "ask_ajie", "npc_ajie")
		if not bool(del_rej.get("ok", true)) and str(del_rej.get("reason_code", "")) == "already_resolved":
			failed += _ok("狀態 1: 處方路線互斥生效，已結算後委託回傳 already_resolved")
		else:
			failed += _fail("狀態 1: 處方路線互斥失敗: %s" % str(del_rej))

	# ── 狀態 2: 持有 npc_ajie（即時回報）──
	_reset_gs(gs)
	gs.gain_card("npc_ajie")
	gs.set("day", 17)
	gs.set("phase", "afternoon")

	var panel_s2: Dictionary = gs.build_panel("sanquan")
	var pres_bv_s2: Dictionary = {}
	for bv: Dictionary in panel_s2.get("beats", []) as Array:
		if str((bv.get("beat", {}) as Dictionary).get("id", "")) == "d17_19_prescription":
			pres_bv_s2 = bv
			break

	if pres_bv_s2.is_empty():
		failed += _fail("狀態 2: D17 下午未找到 d17_19_prescription beat")
	else:
		# 委託阿婕：immediate 回報
		var res_ajie: Dictionary = gs.delegate("d17_19_prescription", "ask_ajie", "npc_ajie")
		if bool(res_ajie.get("ok", false)):
			var action_spent_val: bool = bool(gs.get("action_spent"))
			var has_pres: bool = gs.has_card("doc_prescription")
			var has_info: bool = gs.has_card("info_ajie_saw_parents")
			var has_ajie_card: bool = gs.has_card("npc_ajie")
			if not action_spent_val and has_pres and has_info and has_ajie_card:
				failed += _ok("狀態 2 (阿婕 immediate): 不耗主角行動格，人物卡保留在手牌，獲得 doc_prescription 與 info_ajie_saw_parents")
			else:
				failed += _fail("狀態 2 委託阿婕效果異常: action_spent=%s, pres=%s, info=%s, ajie=%s" % [action_spent_val, has_pres, has_info, has_ajie_card])
		else:
			failed += _fail("狀態 2 委託阿婕失敗: %s" % str(res_ajie))

		# 驗證人物每日一次限制：今日已受託
		var status_ajie: Dictionary = gs.delegation_status("npc_ajie")
		if bool(status_ajie.get("delegated_today", false)):
			failed += _ok("狀態 2: delegation_status 正確回報 delegated_today=true")
		else:
			failed += _fail("狀態 2: delegation_status 未記錄今日已受託")

	# ── 狀態 3: 持有 npc_azhu（隔日上午回報）──
	_reset_gs(gs)
	gs.gain_card("npc_azhu")
	gs.set("day", 17)
	gs.set("phase", "afternoon")

	var res_azhu: Dictionary = gs.delegate("d17_19_prescription", "ask_azhu", "npc_azhu")
	if bool(res_azhu.get("ok", false)):
		var has_pres_immediate: bool = gs.has_card("doc_prescription")
		var pending_reports: Array = gs.get("pending_delegation_reports") as Array
		if not has_pres_immediate and pending_reports.size() == 1:
			failed += _ok("狀態 3 (阿珠 next_morning): 派出當下不發處方卡，正確排入 pending_delegation_reports")
		else:
			failed += _fail("狀態 3 當下效果異常: has_pres=%s, pending_count=%d" % [has_pres_immediate, pending_reports.size()])

		# 推進到 evening 再推進到第 18 天 morning
		gs.advance_phase() # to evening
		gs.play_evening()
		gs.advance_phase() # to night
		gs.sleep_night()
		gs.advance_phase() # to day 18 morning (觸發 _settle_pending_delegation_reports)

		var has_pres_morning: bool = gs.has_card("doc_prescription")
		var has_uncle_info: bool = gs.has_card("info_uncle_treated_20y")
		var report_lines: PackedStringArray = gs.get("last_delegation_report_lines") as PackedStringArray

		if has_pres_morning and has_uncle_info and report_lines.size() > 0:
			failed += _ok("狀態 3: 第 18 天上午順利結算回報，獲得 doc_prescription、info_uncle_treated_20y 並產生回報文字")
		else:
			failed += _fail("狀態 3 隔日上午回報結算失敗: pres=%s, info=%s, lines=%s" % [has_pres_morning, has_uncle_info, str(report_lines)])

		# 換日後 delegates_used_today 重置
		var status_azhu_d18: Dictionary = gs.delegation_status("npc_azhu")
		if not bool(status_azhu_d18.get("delegated_today", true)):
			failed += _ok("狀態 3: 進入隔日上午後 delegates_used_today 清空，人物恢復可用")
		else:
			failed += _fail("狀態 3: 換日後 delegates_used_today 未清空")
	else:
		failed += _fail("狀態 3 委託阿珠失敗: %s" % str(res_azhu))

	# ── 狀態 4: 持有 npc_acai（主觀回報，不給處方）──
	_reset_gs(gs)
	gs.gain_card("npc_acai")
	gs.set("day", 17)
	gs.set("phase", "afternoon")

	var res_acai: Dictionary = gs.delegate("d17_19_prescription", "ask_acai", "npc_acai")
	if bool(res_acai.get("ok", false)):
		var has_acai_box: bool = gs.has_card("info_acai_box")
		var has_pres_acai: bool = gs.has_card("doc_prescription")
		if has_acai_box and not has_pres_acai:
			failed += _ok("狀態 4 (阿財 subjective): 獲得 info_acai_box 且不給予 doc_prescription（主觀漏掉重要文件）")
		else:
			failed += _fail("狀態 4 效果異常: box=%s, pres=%s" % [has_acai_box, has_pres_acai])
	else:
		failed += _fail("狀態 4 委託阿財失敗: %s" % str(res_acai))

	# ── 驗證 D18、D19 持續窗與結算後關閉 ──
	# 若 D17 委託完成，D18 與 D19 不可再次結算
	(gs.get("delegates_used_today") as Dictionary).clear()
	gs.set("day", 18)
	gs.set("phase", "afternoon")
	var del_d18_rej: Dictionary = gs.delegate("d17_19_prescription", "ask_acai", "npc_acai")
	if not bool(del_d18_rej.get("ok", true)) and str(del_d18_rej.get("reason_code", "")) == "already_resolved":
		failed += _ok("D18 驗證: 處方 choice_group 保持已結算，不因換日重開 (already_resolved)")
	else:
		failed += _fail("D18 處方重開防護失敗: %s" % str(del_d18_rej))

	return failed


# ── 2. D8／D45 遭遇 Response Matrix 動態資料衍生測試 ────────────────────────

func _test_encounter_matrix_derivation(gs: Node, data_node: Node) -> int:
	print("--- 2. D8 & D45 Encounter Matrix Derivations ---")
	var failed := 0
	var loader: DataLoader = data_node.get("loader") as DataLoader

	# ── A. D8 遭遇（n_manydoors_ch1）──
	var d8_beat: Dictionary = loader.beats_by_id.get("n_manydoors_ch1", {}) as Dictionary
	if d8_beat.is_empty():
		return failed + _fail("D8 beat n_manydoors_ch1 不存在於資料中")

	var d8_enc: Dictionary = d8_beat.get("encounter", {}) as Dictionary
	var d8_rounds: Array = d8_enc.get("rounds", []) as Array
	if d8_rounds.size() != 3:
		return failed + _fail("D8 遭遇 rounds 數量不為 3 (實際: %d)" % d8_rounds.size())

	# 測試 D8 正解路徑（持有知識卡 k_not_today, info_chunama_pause, routine_debt）
	_reset_gs(gs)
	gs.gain_card("k_not_today")
	gs.gain_card("info_chunama_pause")
	gs.gain_card("routine_debt")
	gs.set("day", 8)
	gs.set("phase", "night")
	gs.play_night_fixed()
	gs.acknowledge_encounter_intro()

	# R1 正解
	var r1_res: Dictionary = gs.respond_to_encounter("k_not_today")
	if bool(r1_res.get("ok", false)) and str((gs.get("active_encounter") as Dictionary).get("round_id", "")) == "who_remembers":
		failed += _ok("D8 R1 正解 (k_not_today): 順利前進至 who_remembers，知識卡不被消耗")
	else:
		failed += _fail("D8 R1 正解失敗: %s" % str(r1_res))

	# R2 正解
	var r2_res: Dictionary = gs.respond_to_encounter("info_chunama_pause")
	if bool(r2_res.get("ok", false)) and str((gs.get("active_encounter") as Dictionary).get("round_id", "")) == "what_remains":
		failed += _ok("D8 R2 正解 (info_chunama_pause): 順利前進至 what_remains")
	else:
		failed += _fail("D8 R2 正解失敗: %s" % str(r2_res))

	# R3 正解 -> 結算勝利
	var r3_res: Dictionary = gs.respond_to_encounter("routine_debt")
	if bool(r3_res.get("ok", false)) and (gs.get("active_encounter") as Dictionary).is_empty():
		var is_victory: bool = bool((gs.get("flags") as Dictionary).get("d8_encounter_victory", false))
		if is_victory:
			failed += _ok("D8 R3 正解 (routine_debt): 遭遇順利結算勝利並寫入 d8_encounter_victory")
		else:
			failed += _fail("D8 勝利 flag 未正確寫入")
	else:
		failed += _fail("D8 R3 正解失敗: %s" % str(r3_res))

	# 測試 D8 Fallback 與可丟棄卡消耗
	_reset_gs(gs)
	gs.gain_card("equip_polaroid") # discardable: true
	gs.gain_card("item_gradphoto") # discardable: true
	gs.gain_card("info_husband_version") # discardable: true
	gs.set("day", 8)
	gs.set("phase", "night")
	gs.play_night_fixed()
	gs.acknowledge_encounter_intro()

	var fb1_res: Dictionary = gs.respond_to_encounter("equip_polaroid")
	if bool(fb1_res.get("ok", false)) and not gs.has_card("equip_polaroid"):
		failed += _ok("D8 R1 Fallback: 消耗可丟棄卡 equip_polaroid 並前進至 R2")
	else:
		failed += _fail("D8 R1 Fallback 失敗: %s" % str(fb1_res))

	# 測試 D8 逃離（Escape）
	var esc_pay: Array[String] = ["item_gradphoto"]
	var esc_res: Dictionary = gs.escape_encounter(esc_pay)
	if bool(esc_res.get("ok", false)) and (gs.get("active_encounter") as Dictionary).is_empty():
		var is_esc: bool = bool((gs.get("flags") as Dictionary).get("d8_encounter_escaped", false))
		if is_esc and not gs.has_card("item_gradphoto"):
			failed += _ok("D8 逃離成功: 支付代價 item_gradphoto，關閉遭遇並寫入 d8_encounter_escaped")
		else:
			failed += _fail("D8 逃離狀態異常: esc_flag=%s, has_card=%s" % [is_esc, gs.has_card("item_gradphoto")])
	else:
		failed += _fail("D8 逃離失敗: %s" % str(esc_res))

	# 測試 D8 零可丟棄卡直接 Failure（非容量超載）
	_reset_gs(gs)
	gs.set("day", 8)
	gs.set("phase", "night")
	gs.play_night_fixed()
	var ack_zero: Dictionary = gs.acknowledge_encounter_intro()
	if bool(ack_zero.get("ok", false)) and (gs.get("active_encounter") as Dictionary).is_empty():
		var is_fail: bool = bool((gs.get("flags") as Dictionary).get("d8_encounter_failure", false))
		if is_fail:
			failed += _ok("D8 零可丟棄卡直接 Failure: acknowledge 後立即結算 failure 並寫入 d8_encounter_failure")
		else:
			failed += _fail("D8 failure flag 未寫入")
	else:
		failed += _fail("D8 零可丟棄卡結算異常: %s" % str(ack_zero))

	# ── B. D45 遭遇（d45_encounter）──
	var d45_beat: Dictionary = loader.beats_by_id.get("d45_encounter", {}) as Dictionary
	if d45_beat.is_empty():
		return failed + _fail("D45 beat d45_encounter 不存在於資料中")

	var d45_enc: Dictionary = d45_beat.get("encounter", {}) as Dictionary
	var d45_rounds: Array = d45_enc.get("rounds", []) as Array
	if d45_rounds.is_empty():
		return failed + _fail("D45 遭遇 rounds 為空")

	var d45_r1: Dictionary = d45_rounds[0] as Dictionary
	var d45_responses: Array = d45_r1.get("responses", []) as Array

	# 驗證 D45 推論卡特殊轉化分支
	var transform_cases := [
		{ "input": "inf_health_disappearance", "output": "k_health_from_disappearance" },
		{ "input": "inf_jinghe_does_it", "output": "k_jinghe_not_entrance" },
		{ "input": "inf_hotspring_kills", "output": "k_not_side_effect" },
	]

	for tc in transform_cases:
		var in_card: String = tc["input"]
		var out_card: String = tc["output"]

		_reset_gs(gs)
		gs.gain_card(in_card)
		gs.set("day", 45)
		gs.set("phase", "morning")
		gs.set_flag("final_day", true)
		gs.advance_phase() # triggers d45_encounter intro
		gs.acknowledge_encounter_intro()

		var tc_res: Dictionary = gs.respond_to_encounter(in_card)
		if bool(tc_res.get("ok", false)):
			var lost_in: bool = not gs.has_card(in_card)
			var gained_out: bool = gs.has_knowledge(out_card)
			var phase_is_eve: bool = (str(gs.get("phase")) == "evening")
			if lost_in and gained_out and phase_is_eve:
				failed += _ok("D45 推論卡轉化 (%s -> %s): 失去推論卡、獲得對位知識且推進至 evening" % [in_card, out_card])
			else:
				failed += _fail("D45 轉化異常: lost_in=%s, gained_out=%s, phase=%s" % [lost_in, gained_out, str(gs.get("phase"))])
		else:
			failed += _fail("D45 回應 %s 失敗: %s" % [in_card, str(tc_res)])

	# 驗證 D45 人物卡與主角卡回應後卡片不丟失
	var retain_cases := ["protagonist", "npc_ajie", "npc_awei"]
	for rc in retain_cases:
		_reset_gs(gs)
		if rc != "protagonist":
			gs.gain_card(rc)
		gs.set("day", 45)
		gs.set("phase", "morning")
		gs.set_flag("final_day", true)
		gs.advance_phase()
		gs.acknowledge_encounter_intro()

		var rc_res: Dictionary = gs.respond_to_encounter(rc)
		if bool(rc_res.get("ok", false)) and gs.has_card(rc) and str(gs.get("phase")) == "evening":
			failed += _ok("D45 保留卡回應 (%s): 卡片仍在手牌未失去，且推進至 evening" % rc)
		else:
			failed += _fail("D45 保留卡回應 %s 失敗: res=%s, has_card=%s" % [rc, str(rc_res), gs.has_card(rc)])

	return failed


# ── 3. 跨輪重置與第二輪持久化驗證 ──────────────────────────────────────────

func _test_end_run_cleanup_and_second_run_persistence(gs: Node, data_node: Node) -> int:
	print("--- 3. Loop Reset & Second Loop Persistence ---")
	var failed := 0
	_reset_gs(gs)

	# 1. 模擬第 1 輪產生各層狀態
	gs.gain_card("k_not_today") # meta knowledge
	gs.gain_card("npc_ajie")
	gs.mark_delegation_tutorial_seen() # meta tutorial
	gs.set("day", 8)
	gs.set("phase", "night")
	gs.play_night_fixed() # triggers D8, records n_manydoors into seen, charges cost
	gs.acknowledge_encounter_intro()
	gs.respond_to_encounter("k_not_today")

	# 設定 Run-layer 狀態
	gs.set("day", 17)
	gs.set("phase", "afternoon")
	gs.delegate("d17_19_prescription", "ask_ajie", "npc_ajie")
	gs.set_flag("test_run_flag", true)

	var before_meta_seen: Dictionary = (gs.get("night_locations_seen") as Dictionary).duplicate()
	var before_knowledge: Dictionary = (gs.get("knowledge") as Dictionary).duplicate()
	var before_tutorial: bool = bool(gs.get("delegation_tutorial_seen"))

	# 執行真實 end_run()
	gs.call("end_run", "ending_default")

	# 2. 斷言 Meta 層完整保留
	if bool(gs.get("delegation_tutorial_seen")) == before_tutorial and before_tutorial == true:
		failed += _ok("Meta 保留: delegation_tutorial_seen 跨輪重置後保持 true")
	else:
		failed += _fail("Meta 遺失: delegation_tutorial_seen 跨輪重置後被清空")

	var after_knowledge: Dictionary = gs.get("knowledge") as Dictionary
	if after_knowledge.has("k_not_today"):
		failed += _ok("Meta 保留: knowledge 知識卡跨輪重置後保持完整 (%d 張)" % after_knowledge.size())
	else:
		failed += _fail("Meta 遺失: knowledge 跨輪重置後遺失")

	var after_meta_seen: Dictionary = gs.get("night_locations_seen") as Dictionary
	if after_meta_seen.has("n_manydoors"):
		failed += _ok("Meta 保留: night_locations_seen 跨輪重置後保持完整 (含 n_manydoors)")
	else:
		failed += _fail("Meta 遺失: night_locations_seen 跨輪重置後遺失")

	# 3. 斷言 Run 層完整重置
	var run_clean := true
	if int(gs.get("day")) != 1 or str(gs.get("phase")) != "morning":
		run_clean = false
		failed += _fail("Run 重置: 時間未重置至第 1 天 morning")
	if (gs.get("hand") as Array).size() != 1 or (gs.get("hand") as Array)[0] != "protagonist":
		run_clean = false
		failed += _fail("Run 重置: 手牌未重置至 [protagonist]")
	if not (gs.get("delegates_used_today") as Dictionary).is_empty():
		run_clean = false
		failed += _fail("Run 重置: delegates_used_today 未清空")
	if not (gs.get("pending_delegation_reports") as Array).is_empty():
		run_clean = false
		failed += _fail("Run 重置: pending_delegation_reports 未清空")
	if not (gs.get("active_encounter") as Dictionary).is_empty():
		run_clean = false
		failed += _fail("Run 重置: active_encounter 未清空")
	if not (gs.get("flags") as Dictionary).is_empty():
		run_clean = false
		failed += _fail("Run 重置: flags 未清空")

	if run_clean:
		failed += _ok("Run 重置: day/phase/hand/delegates/pending/encounter/flags 全部清空重置")

	# 4. 驗證第 2 輪 D8 遭遇重演且不重收首次地點費用 (charge_first_visit)
	gs.set("day", 8)
	gs.set("phase", "night")
	var hand_size_before_d8: int = (gs.get("hand") as Array).size()
	var madness_counter_before: int = int(gs.get("_madness_counter"))
	gs.play_night_fixed()

	var hand_size_after_d8: int = (gs.get("hand") as Array).size()
	var madness_counter_after: int = int(gs.get("_madness_counter"))
	var is_enc_active: bool = not (gs.get("active_encounter") as Dictionary).is_empty()

	if is_enc_active and hand_size_after_d8 == hand_size_before_d8 and madness_counter_after == madness_counter_before:
		failed += _ok("第 2 輪 D8 驗證: 遭遇正常啟動 (repeat_each_run) 且因已見不收取首次 marker cost (charge_first_visit)")
	else:
		failed += _fail("第 2 輪 D8 驗證異常: enc_active=%s, hand_delta=%d, madness_delta=%d" % [
			is_enc_active,
			hand_size_after_d8 - hand_size_before_d8,
			madness_counter_after - madness_counter_before
		])

	return failed


# ── 4. 跨輪決定論測試 ───────────────────────────────────────────────────────

func _test_cross_run_determinism(gs: Node, data_node: Node) -> int:
	print("--- 4. Cross-Run Determinism Test (P4-F) ---")
	var failed := 0
	_reset_gs(gs)

	# 走完第一輪並包含 P4 委託與遭遇決策
	gs.gain_card("npc_ajie")
	gs.mark_delegation_tutorial_seen()
	gs.set("day", 8)
	gs.set("phase", "night")
	gs.gain_card("equip_polaroid")
	gs.gain_card("item_gradphoto")
	gs.play_night_fixed()
	gs.acknowledge_encounter_intro()
	gs.respond_to_encounter("equip_polaroid")
	var esc_pay_cross: Array[String] = ["item_gradphoto"]
	gs.escape_encounter(esc_pay_cross)

	# 跑完第 1 輪重置
	gs.call("end_run", "ending_default")
	var checkpoint: Dictionary = gs.call("serialize")

	# 建立兩個獨立的 GameState 實例
	var gs_a: Node = (load("res://scripts/autoload/game_state.gd") as GDScript).new()
	gs_a.name = "GS_A_P4F"
	gs_a.set("Data", data_node)
	get_root().add_child(gs_a)
	gs_a.deserialize(checkpoint)

	var gs_b: Node = (load("res://scripts/autoload/game_state.gd") as GDScript).new()
	gs_b.name = "GS_B_P4F"
	gs_b.set("Data", data_node)
	get_root().add_child(gs_b)
	gs_b.deserialize(checkpoint)

	# 兩邊在第 2 輪執行完全相同的操作序列（包含 D8 遭遇與 D17 委託）
	var timeline_a: Array[Dictionary] = []
	var timeline_b: Array[Dictionary] = []

	for d in range(1, 20):
		# Morning
		var act_m_a := PlaythroughGreedy.execute_action_phase(gs_a, data_node, d, "morning", false)
		gs_a.advance_phase()
		var act_m_b := PlaythroughGreedy.execute_action_phase(gs_b, data_node, d, "morning", false)
		gs_b.advance_phase()
		timeline_a.append({ "day": d, "phase": "morning", "res": act_m_a.get("category") })
		timeline_b.append({ "day": d, "phase": "morning", "res": act_m_b.get("category") })

		# Afternoon (第 17 天委託阿婕)
		if d == 17:
			gs_a.gain_card("npc_ajie")
			gs_a.delegate("d17_19_prescription", "ask_ajie", "npc_ajie")
			gs_b.gain_card("npc_ajie")
			gs_b.delegate("d17_19_prescription", "ask_ajie", "npc_ajie")

		var act_a_a := PlaythroughGreedy.execute_action_phase(gs_a, data_node, d, "afternoon", false)
		if str(gs_a.get("phase")) == "afternoon":
			gs_a.advance_phase()
		var act_a_b := PlaythroughGreedy.execute_action_phase(gs_b, data_node, d, "afternoon", false)
		if str(gs_b.get("phase")) == "afternoon":
			gs_b.advance_phase()
		timeline_a.append({ "day": d, "phase": "afternoon", "res": act_a_a.get("category") })
		timeline_b.append({ "day": d, "phase": "afternoon", "res": act_a_b.get("category") })

		# Evening
		PlaythroughGreedy.execute_evening_phase(gs_a, data_node, d)
		gs_a.advance_phase()
		PlaythroughGreedy.execute_evening_phase(gs_b, data_node, d)
		gs_b.advance_phase()

		# Night
		gs_a.play_night_fixed()
		PlaythroughGreedy.solve_active_encounter_if_any(gs_a)
		gs_a.sleep_night()
		gs_a.advance_phase()

		gs_b.play_night_fixed()
		PlaythroughGreedy.solve_active_encounter_if_any(gs_b)
		gs_b.sleep_night()
		gs_b.advance_phase()

	var state_a: Dictionary = gs_a.serialize()
	var state_b: Dictionary = gs_b.serialize()

	if JSON.stringify(state_a) == JSON.stringify(state_b):
		failed += _ok("同存檔重載兩次並執行相同第二輪序列，serialize() 逐字完全相同")
	else:
		failed += _fail("決定論 serialize() 比對失敗:\n  A: %s\n  B: %s" % [JSON.stringify(state_a), JSON.stringify(state_b)])

	if JSON.stringify(timeline_a) == JSON.stringify(timeline_b):
		failed += _ok("兩次執行過程記錄之事件時間軸逐項完全相同")
	else:
		failed += _fail("時間軸比對失敗")

	gs_a.queue_free()
	gs_b.queue_free()

	return failed
