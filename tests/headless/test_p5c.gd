extends SceneTree

## P5-C 四類結局與組合後日談測試（實作規格書 P5-C、測試指南 P5-C）。
## 涵蓋：4×3 生計開關帶矩陣與 s1～s6 獨立邊界測試（P5C-V6）、
## 伴侶／生計／修繕優先序、客觀敘事與「她先死」完整後日談（P5C-V5）、
## uninvited_proxy 查表與防篡改、首見長版 vs 重見短版分支、
## 兩種 BE 的後日談隔離與獨立首見計算、不上車外地人生快照與生命週期、
## 四類結局逐頁 ready_to_complete 門檻與動作原子性、
## Resolver 壞資料 data_conflict 防禦、
## Deserialize variant 與 page ref 一致性驗證（P5C-V7）、
## 全 432 組全排列結構版文字走查（864 次求值）。
## 跑法：Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/test_p5c.gd

const PlaythroughGreedy := preload("res://tests/headless/playthrough_greedy.gd")

var _failed := 0


func _initialize() -> void:
	var data_node: Node = PlaythroughGreedy.setup_data(self)
	var gs: Node = PlaythroughGreedy.setup_game_state(self, data_node)
	await process_frame

	if not bool(data_node.get("ok")):
		push_error("P5-C: Data 載入失敗，中止")
		quit(1)
		return

	print("=== P5-C 四類結局與組合後日談測試 ===")
	_test_1_partner_variants(gs, data_node)
	_test_2_livelihood_switch_matrix(gs, data_node)
	_test_3_switch_matrix_independent_boundaries(gs, data_node)
	_test_4_inn_appearance_variants(gs, data_node)
	_test_5_uninvited_proxy_lookup(gs, data_node)
	_test_6_first_seen_vs_repeat_and_chronology(gs, data_node)
	_test_7_be_endings_independence(gs, data_node)
	_test_8_refuse_boarding_ending(gs, data_node)
	_test_9_lifecycle_ready_to_complete_all_four(gs, data_node)
	_test_10_resolver_bad_data_defense(gs, data_node)
	_test_11_deserialize_variant_validation(gs, data_node)
	_test_12_structural_text_walkthrough(gs, data_node)

	if _failed > 0:
		push_error("test_p5c: %d 個斷言失敗" % _failed)
		quit(1)
	else:
		print("\n=== P5-C 全部測試通過 ===")
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


func _fresh_run(gs: Node, day: int = 45, phase: String = "evening") -> void:
	# P5-D：fresh state 是 opening，本檔驗的是 run 層規則。
	gs.set("flow_mode", "run")
	(gs.get("active_ending") as Dictionary).clear()
	PlaythroughGreedy.start_fresh_run(gs)
	gs.set("day", day)
	gs.set("phase", phase)
	gs.set("ending_history", [] as Array[Dictionary])
	gs.set("run_number", 1)
	(gs.get("knowledge") as Dictionary).clear()
	(gs.get("knowledge_at_start") as Dictionary).clear()
	(gs.get("night_locations_seen") as Dictionary).clear()
	(gs.get("flags") as Dictionary).clear()
	(gs.get("relations") as Dictionary).clear()
	(gs.get("npc_action_counts") as Dictionary).clear()
	(gs.get("switches") as Dictionary).clear()
	(gs.get("switch_progress") as Dictionary).clear()
	gs.set("selected_festival_proxy_npc", "")
	gs.set("opening_choice_id", "")


func _force_opening_mode(gs: Node) -> void:
	var state: Dictionary = gs.call("serialize")
	(state["flow"] as Dictionary)["mode"] = "opening"
	var res: Dictionary = gs.call("deserialize", state)
	if not bool(res.get("ok", false)):
		_fail("_force_opening_mode: deserialize 失敗")


func _refs_contain(refs: Array, needle: String) -> bool:
	for r: Variant in refs:
		if needle in str(r):
			return true
	return false


func _set_switches(gs: Node, count: int) -> void:
	var sw: Dictionary = gs.get("switches") as Dictionary
	sw.clear()
	var sp: Dictionary = gs.get("switch_progress") as Dictionary
	sp.clear()

	# 6 switches: s1, s2, s3, s4, s5, s6 (target 3)
	if count >= 1:
		sw["s1"] = true
	if count >= 2:
		sw["s2"] = true
	if count >= 3:
		sw["s3"] = true
	if count >= 4:
		sw["s4"] = true
	if count >= 5:
		sw["s5"] = true
	if count >= 6:
		sp["s6"] = 3


# ── 1. 伴侶 variants 涵蓋與關係獨立性 ─────────────────────────────────────────

func _test_1_partner_variants(gs: Node, data_node: Node) -> void:
	print("\n--- 1. 伴侶 variants 覆蓋與關係獨立性 ---")
	var loader: DataLoader = data_node.get("loader") as DataLoader

	# (a) invited_ajie -> partner_variant: "ajie"
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["invited_ajie"] = true
	var res_ajie := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(bool(res_ajie.get("ok", false)), "邀阿婕 resolve 成功")
	_check(str((res_ajie.get("variants") as Dictionary).get("partner_variant", "")) == "ajie", "伴侶為 ajie")
	var refs_ajie: Array = res_ajie.get("page_refs", []) as Array
	_check(_refs_contain(refs_ajie, "partner_ajie_long"), "包含 partner_ajie_long 頁面")
	_check(not _refs_contain(refs_ajie, "partner_awei_long") and not _refs_contain(refs_ajie, "partner_none_long"), "不包含其他伴侶頁面")

	# (b) invited_awei -> partner_variant: "awei"
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "awei")
	(gs.get("flags") as Dictionary)["invited_awei"] = true
	var res_awei := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(bool(res_awei.get("ok", false)), "邀阿薇 resolve 成功")
	_check(str((res_awei.get("variants") as Dictionary).get("partner_variant", "")) == "awei", "伴侶為 awei")
	var refs_awei: Array = res_awei.get("page_refs", []) as Array
	_check(_refs_contain(refs_awei, "partner_awei_long"), "包含 partner_awei_long 頁面")
	_check(not _refs_contain(refs_awei, "partner_ajie_long") and not _refs_contain(refs_awei, "partner_none_long"), "不包含其他伴侶頁面")

	# (c) 無邀請 (invited_none 或未邀) -> fallback partner_variant: "none"
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "acai")
	(gs.get("flags") as Dictionary)["invited_none"] = true
	var res_none := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(bool(res_none.get("ok", false)), "無邀請 resolve 成功")
	_check(str((res_none.get("variants") as Dictionary).get("partner_variant", "")) == "none", "伴侶為 fallback none")
	var refs_none: Array = res_none.get("page_refs", []) as Array
	_check(_refs_contain(refs_none, "partner_none_long"), "包含 partner_none_long 頁面")

	# (d) 關係完成度獨立性：只改 relations 不改 flags，伴侶仍為 none
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "acai")
	(gs.get("relations") as Dictionary)["ajie"] = 100
	(gs.get("relations") as Dictionary)["awei"] = 100
	var res_rel := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(bool(res_rel.get("ok", false)), "高關係值但無 choice 旗標 resolve 成功")
	_check(str((res_rel.get("variants") as Dictionary).get("partner_variant", "")) == "none",
		"只改 relation 不改 D29 choice 時伴侶仍為 none（resolver 不偷看關係度）")


# ── 2. 生計 4×3 開關帶矩陣、優先序與合成防禦 (P5C-V1) ─────────────────────────

func _test_2_livelihood_switch_matrix(gs: Node, data_node: Node) -> void:
	print("\n--- 2. 生計 4×3 開關帶矩陣、優先序與合成防禦 ---")
	var loader: DataLoader = data_node.get("loader") as DataLoader

	# 12 格人生矩陣測試：4 routes × 3 bands (high: 4-6, mid: 2-3, low: 0-1)
	var matrix_cases := [
		# 1. 答應叔叔 (accepted_inn)
		{ "route": "accepted_inn", "switches": 6, "expected": "uncle_high", "ref": "livelihood_uncle_high_long" },
		{ "route": "accepted_inn", "switches": 4, "expected": "uncle_high", "ref": "livelihood_uncle_high_long" },
		{ "route": "accepted_inn", "switches": 3, "expected": "uncle_mid", "ref": "livelihood_uncle_mid_long" },
		{ "route": "accepted_inn", "switches": 2, "expected": "uncle_mid", "ref": "livelihood_uncle_mid_long" },
		{ "route": "accepted_inn", "switches": 1, "expected": "uncle_low", "ref": "livelihood_uncle_low_long" },
		{ "route": "accepted_inn", "switches": 0, "expected": "uncle_low", "ref": "livelihood_uncle_low_long" },

		# 2. 前老闆 (accepted_outside_job)
		{ "route": "accepted_outside_job", "switches": 6, "expected": "boss_high", "ref": "livelihood_boss_high_long" },
		{ "route": "accepted_outside_job", "switches": 4, "expected": "boss_high", "ref": "livelihood_boss_high_long" },
		{ "route": "accepted_outside_job", "switches": 3, "expected": "boss_mid", "ref": "livelihood_boss_mid_long" },
		{ "route": "accepted_outside_job", "switches": 2, "expected": "boss_mid", "ref": "livelihood_boss_mid_long" },
		{ "route": "accepted_outside_job", "switches": 1, "expected": "boss_low", "ref": "livelihood_boss_low_long" },
		{ "route": "accepted_outside_job", "switches": 0, "expected": "boss_low", "ref": "livelihood_boss_low_long" },

		# 3. 周先生 (accepted_job)
		{ "route": "accepted_job", "switches": 6, "expected": "zhou_high", "ref": "livelihood_zhou_high_long" },
		{ "route": "accepted_job", "switches": 4, "expected": "zhou_high", "ref": "livelihood_zhou_high_long" },
		{ "route": "accepted_job", "switches": 3, "expected": "zhou_mid", "ref": "livelihood_zhou_mid_long" },
		{ "route": "accepted_job", "switches": 2, "expected": "zhou_mid", "ref": "livelihood_zhou_mid_long" },
		{ "route": "accepted_job", "switches": 1, "expected": "zhou_low", "ref": "livelihood_zhou_low_long" },
		{ "route": "accepted_job", "switches": 0, "expected": "zhou_low", "ref": "livelihood_zhou_low_long" },

		# 4. 皆無 (none)
		{ "route": "none", "switches": 6, "expected": "none_high", "ref": "livelihood_none_high_long" },
		{ "route": "none", "switches": 4, "expected": "none_high", "ref": "livelihood_none_high_long" },
		{ "route": "none", "switches": 3, "expected": "none_mid", "ref": "livelihood_none_mid_long" },
		{ "route": "none", "switches": 2, "expected": "none_mid", "ref": "livelihood_none_mid_long" },
		{ "route": "none", "switches": 1, "expected": "none_low", "ref": "livelihood_none_low_long" },
		{ "route": "none", "switches": 0, "expected": "none_low", "ref": "livelihood_none_low_long" },
	]

	for mc in matrix_cases:
		_fresh_run(gs)
		gs.set("selected_festival_proxy_npc", "ajie")
		if str(mc["route"]) != "none":
			(gs.get("flags") as Dictionary)[str(mc["route"])] = true
		_set_switches(gs, int(mc["switches"]))

		var res := EndingResolver.resolve("ending_replaced", gs, loader)
		var actual_var := str((res.get("variants") as Dictionary).get("livelihood_variant", ""))
		_check(actual_var == str(mc["expected"]),
			"生計矩陣 [%s + %d 開關] → variant: %s" % [str(mc["route"]), int(mc["switches"]), actual_var])
		_check(_refs_contain(res.get("page_refs", []) as Array, str(mc["ref"])),
			"包含頁面 %s" % str(mc["ref"]))

	# 優先序與開關帶組合：三旗標同時成立，開關為 3 (mid band) -> 依序只取 uncle_mid
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["accepted_inn"] = true
	(gs.get("flags") as Dictionary)["accepted_outside_job"] = true
	(gs.get("flags") as Dictionary)["accepted_job"] = true
	_set_switches(gs, 3)
	var res_multi := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(str((res_multi.get("variants") as Dictionary).get("livelihood_variant", "")) == "uncle_mid",
		"三旗標同時成立且開關=3 時依序取 uncle_mid")
	var refs_multi: Array = res_multi.get("page_refs", []) as Array
	_check(_refs_contain(refs_multi, "livelihood_uncle_mid_long"), "優先取 uncle_mid 頁面")
	_check(not _refs_contain(refs_multi, "boss") and not _refs_contain(refs_multi, "zhou"), "不包含 boss 或 zhou 頁面")

	# 合成防禦：無叔叔但雙 D43 旗標成立，開關為 5 (high band) -> 依序取 boss_high
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["accepted_outside_job"] = true
	(gs.get("flags") as Dictionary)["accepted_job"] = true
	_set_switches(gs, 5)
	var res_dual := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(str((res_dual.get("variants") as Dictionary).get("livelihood_variant", "")) == "boss_high",
		"無叔叔雙 D43 且開關=5 時只取前老闆 high (boss_high)")
	var refs_dual: Array = res_dual.get("page_refs", []) as Array
	_check(_refs_contain(refs_dual, "livelihood_boss_high_long"), "只有前老闆 high 入頁")
	_check(not _refs_contain(refs_dual, "zhou"), "周先生頁面未入頁（不拼裝互斥人生）")


# ── 3. 六開關矩陣獨立 s1～s6 邊界與結構守門 (P5C-V6) ───────────────────────────

func _test_3_switch_matrix_independent_boundaries(gs: Node, data_node: Node) -> void:
	print("\n--- 3. 六開關矩陣獨立 s1～s6 邊界與結構守門 ---")
	var loader: DataLoader = data_node.get("loader") as DataLoader

	var all_switches := ["s1", "s2", "s3", "s4", "s5", "s6"]

	# 為 s1～s6 每一條開關建立獨立的 3→4 邊界測試
	for tested_sw in all_switches:
		_fresh_run(gs)
		gs.set("selected_festival_proxy_npc", "ajie")
		(gs.get("flags") as Dictionary)["accepted_inn"] = true

		# 挑選其餘 5 個中的 3 個開關作為基準 (此時恰為 3 開關 -> mid band)
		var other_switches := []
		for sw in all_switches:
			if sw != tested_sw:
				other_switches.append(sw)
		var base_3 := [other_switches[0], other_switches[1], other_switches[2]]

		for sw_name in base_3:
			if str(sw_name) == "s6":
				(gs.get("switch_progress") as Dictionary)["s6"] = 3
			else:
				(gs.get("switches") as Dictionary)[str(sw_name)] = true

		# (a) 僅 3 個其他開關：未達 4 門檻 -> uncle_mid
		var res_mid := EndingResolver.resolve("ending_replaced", gs, loader)
		_check(str((res_mid.get("variants") as Dictionary).get("livelihood_variant", "")) == "uncle_mid",
			"開關邊界 [%s 缺] (base: %s) → uncle_mid" % [tested_sw, str(base_3)])

		# (b) 加入被測開關：達到 4 門檻 -> uncle_high
		if tested_sw == "s6":
			(gs.get("switch_progress") as Dictionary)["s6"] = 3
		else:
			(gs.get("switches") as Dictionary)[tested_sw] = true

		var res_high := EndingResolver.resolve("ending_replaced", gs, loader)
		_check(str((res_high.get("variants") as Dictionary).get("livelihood_variant", "")) == "uncle_high",
			"開關邊界 [%s 命中] (3+1=4 開關) → uncle_high" % tested_sw)
		_check(_refs_contain(res_high.get("page_refs", []) as Array, "livelihood_uncle_high_long"),
			"包含 livelihood_uncle_high_long")

	# (c) 結構斷言：驗證 endings.json 中 4 條 high 生計規則的 of[] 恰好且精確包含 6 條條件
	var end_rep: Dictionary = loader.endings_by_id["ending_replaced"] as Dictionary
	var vgs: Array = end_rep.get("variant_groups", []) as Array
	var livelihood_group := vgs[0] as Dictionary
	var rules: Array = livelihood_group.get("rules", []) as Array
	var high_rules := ["uncle_high", "boss_high", "zhou_high", "none_high"]

	for hr_id in high_rules:
		var hr_dict: Dictionary = {}
		for r in rules:
			if str((r as Dictionary).get("id", "")) == hr_id:
				hr_dict = r as Dictionary
				break
		_check(not hr_dict.is_empty(), "找到 high rule: %s" % hr_id)
		var when_dict: Dictionary = hr_dict.get("when", {}) as Dictionary
		var all_arr: Array = when_dict.get("all", []) as Array
		var count_cond: Dictionary = {}
		if hr_id == "none_high":
			count_cond = when_dict.get("count_at_least", {}) as Dictionary
		else:
			for item in all_arr:
				if (item as Dictionary).has("count_at_least"):
					count_cond = (item as Dictionary).get("count_at_least", {}) as Dictionary
					break

		_check(int(count_cond.get("n", 0)) == 4, "%s 門檻 n == 4" % hr_id)
		var of_arr: Array = count_cond.get("of", []) as Array
		_check(of_arr.size() == 6, "%s of[] 恰有 6 條條件" % hr_id)
		var seen_sws := {}
		for cond_item in of_arr:
			var cdict := cond_item as Dictionary
			if cdict.has("switch"):
				seen_sws[str(cdict["switch"])] = true
			elif cdict.has("switch_progress_at_least"):
				var sp_dict := cdict["switch_progress_at_least"] as Dictionary
				if str(sp_dict.get("switch", "")) == "s6" and int(sp_dict.get("n", 0)) == 3:
					seen_sws["s6"] = true
		_check(seen_sws.has("s1") and seen_sws.has("s2") and seen_sws.has("s3") and seen_sws.has("s4") and seen_sws.has("s5") and seen_sws.has("s6"),
			"%s of[] 精確覆蓋 s1～s6 全開關條件" % hr_id)


# ── 4. 旅館修繕 variants 涵蓋與排他 ───────────────────────────────────────────

func _test_4_inn_appearance_variants(gs: Node, data_node: Node) -> void:
	print("\n--- 4. 旅館修繕 variants 覆蓋與互斥人生隔離 ---")
	var loader: DataLoader = data_node.get("loader") as DataLoader

	# (a) repaired_sign -> sign
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["repaired_sign"] = true
	var res_sign := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(str((res_sign.get("variants") as Dictionary).get("inn_appearance_variant", "")) == "sign", "旅館外觀為 sign")
	_check(_refs_contain(res_sign.get("page_refs", []) as Array, "inn_sign_long"), "包含 inn_sign_long")

	# (b) repaired_pipes -> pipes
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["repaired_pipes"] = true
	var res_pipes := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(str((res_pipes.get("variants") as Dictionary).get("inn_appearance_variant", "")) == "pipes", "旅館外觀為 pipes")
	_check(_refs_contain(res_pipes.get("page_refs", []) as Array, "inn_pipes_long"), "包含 inn_pipes_long")

	# (c) repaired_windows -> windows
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["repaired_windows"] = true
	var res_win := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(str((res_win.get("variants") as Dictionary).get("inn_appearance_variant", "")) == "windows", "旅館外觀為 windows")
	_check(_refs_contain(res_win.get("page_refs", []) as Array, "inn_windows_long"), "包含 inn_windows_long")

	# (d) 無修繕 -> none
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	var res_none := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(str((res_none.get("variants") as Dictionary).get("inn_appearance_variant", "")) == "none", "旅館外觀為 fallback none")
	_check(_refs_contain(res_none.get("page_refs", []) as Array, "inn_none_long"), "包含 inn_none_long")

	# (e) 多修繕同時成立時按資料順序只取第一項 (sign)
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["repaired_sign"] = true
	(gs.get("flags") as Dictionary)["repaired_pipes"] = true
	(gs.get("flags") as Dictionary)["repaired_windows"] = true
	var res_multi := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(str((res_multi.get("variants") as Dictionary).get("inn_appearance_variant", "")) == "sign", "多修繕旗標同時成立時依序取 sign")
	var refs_multi: Array = res_multi.get("page_refs", []) as Array
	_check(_refs_contain(refs_multi, "inn_sign_long"), "只有 sign 頁面入頁")
	_check(not _refs_contain(refs_multi, "inn_pipes_long") and not _refs_contain(refs_multi, "inn_windows_long"), "互斥修繕不拼在一起")


# ── 5. uninvited_proxy 查表與防篡改 ──────────────────────────────────────────

func _test_5_uninvited_proxy_lookup(gs: Node, data_node: Node) -> void:
	print("\n--- 5. uninvited_proxy 查表與後續動作計數防篡改 ---")
	var loader: DataLoader = data_node.get("loader") as DataLoader

	# (a) partner: none + proxy: acai -> proxy_acai_long
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "acai")
	var res_acai := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(bool(res_acai.get("ok", false)), "proxy acai resolve 成功")
	var refs_acai: Array = res_acai.get("page_refs", []) as Array
	_check(_refs_contain(refs_acai, "proxy_acai_long"), "包含 proxy_acai_long 頁面")

	# (b) partner: none + proxy: ajie -> proxy_ajie_long
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	var res_ajie := EndingResolver.resolve("ending_replaced", gs, loader)
	var refs_ajie: Array = res_ajie.get("page_refs", []) as Array
	_check(_refs_contain(refs_ajie, "proxy_ajie_long"), "包含 proxy_ajie_long 頁面")

	# (c) partner: none + proxy: awei -> proxy_awei_long
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "awei")
	var res_awei := EndingResolver.resolve("ending_replaced", gs, loader)
	var refs_awei: Array = res_awei.get("page_refs", []) as Array
	_check(_refs_contain(refs_awei, "proxy_awei_long"), "包含 proxy_awei_long 頁面")

	# 三個首見 proxy 頁都要明確把死亡主詞切回走出山泉閣的人，不能接在 NPC 主詞上。
	for long_case in [
		{ "npc": "阿財", "refs": refs_acai },
		{ "npc": "阿婕", "refs": refs_ajie },
		{ "npc": "阿薇", "refs": refs_awei },
	]:
		var long_ref := str((long_case["refs"] as Array)[4])
		var long_page := EndingResolver.resolve_ref(long_ref, loader)
		var long_beats: Array = long_page.get("narrative_beats", []) as Array
		_check(long_beats.has("switch_subject_to_protagonist"),
			"%s 首見 proxy 頁明確切回後日談主體 (K-208)" % str(long_case["npc"]))
		_check(long_beats.has("died_early_forties") and long_beats.has("died_of_cancer") and long_beats.has("died_rapidly"),
			"%s 首見 proxy 頁由走出山泉閣的人病逝 (K-208)" % str(long_case["npc"]))

	# 重見短版同樣逐一守住主詞，避免把「四十出頭病逝」接到 proxy NPC。
	for repeat_case in [
		{ "id": "acai", "npc": "阿財" },
		{ "id": "ajie", "npc": "阿婕" },
		{ "id": "awei", "npc": "阿薇" },
	]:
		_fresh_run(gs)
		gs.set("selected_festival_proxy_npc", str(repeat_case["id"]))
		(gs.get("ending_history") as Array[Dictionary]).append({ "ending_id": "ending_replaced", "run_number": 1 })
		var repeat_res := EndingResolver.resolve("ending_replaced", gs, loader)
		var repeat_refs: Array = repeat_res.get("page_refs", []) as Array
		var repeat_ref := str(repeat_refs[4])
		var repeat_page := EndingResolver.resolve_ref(repeat_ref, loader)
		var repeat_beats: Array = repeat_page.get("narrative_beats", []) as Array
		_check(repeat_beats.has("protagonist_dies_early_forties"),
			"%s 重見 proxy 頁明確由走出山泉閣的人病逝 (K-208)" % str(repeat_case["npc"]))

	# (d) D29 凍結後改動 npc_action_counts：結局 festival_proxy_npc 仍為凍結 id
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "acai")
	(gs.get("npc_action_counts") as Dictionary)["ajie"] = 999
	(gs.get("npc_action_counts") as Dictionary)["awei"] = 888
	var res_tamper := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(_refs_contain(res_tamper.get("page_refs", []) as Array, "proxy_acai_long"),
		"改動 npc_action_counts 後結局仍讀凍結的 acai 片段（不重算投入）")
	_check(not _refs_contain(res_tamper.get("page_refs", []) as Array, "proxy_ajie_long"), "未受竄改的 ajie 影響")

	# (e) 邀阿婕／阿薇時，uninvited_proxy fragment 不啟用
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "acai")
	(gs.get("flags") as Dictionary)["invited_ajie"] = true
	var res_invited := EndingResolver.resolve("ending_replaced", gs, loader)
	var refs_inv: Array = res_invited.get("page_refs", []) as Array
	_check(_refs_contain(refs_inv, "partner_ajie_long"), "邀阿婕時有 partner_ajie_long")
	_check(not _refs_contain(refs_inv, "proxy_acai_long") and not _refs_contain(refs_inv, "proxy_ajie_long"),
		"邀阿婕時 uninvited_proxy 查表片段不啟用")


# ── 6. 首見長版 vs 重見短版分支、時間軸順序與「她先死」承重 (P5C-V5) ─────────────

func _test_6_first_seen_vs_repeat_and_chronology(gs: Node, data_node: Node) -> void:
	print("\n--- 6. 首見長版 vs 重見短版分支、時間軸順序與「她先死」承重 ---")
	var loader: DataLoader = data_node.get("loader") as DataLoader

	# (a) 邀阿婕首見長版：prefix (走出山泉閣) -> 生計 -> 旅館修繕 -> 伴侶(婚姻/二十年/她先/然後是他) -> suffix(庇佑回歸)
	_fresh_run(gs)
	gs.set("run_number", 1)
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["invited_ajie"] = true
	(gs.get("flags") as Dictionary)["accepted_inn"] = true
	(gs.get("flags") as Dictionary)["repaired_sign"] = true
	_set_switches(gs, 6)

	var res_ajie := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(str(res_ajie.get("branch", "")) == "first_seen", "初次正常結局為 first_seen")
	var refs_ajie: Array = res_ajie.get("page_refs", []) as Array
	_check(refs_ajie.size() == 5, "邀阿婕首見長版恰 5 頁 (page_count=%d)" % refs_ajie.size())

	# 第 1 頁：prefix 可觀察畫面
	var p0 := EndingResolver.resolve_ref(str(refs_ajie[0]), loader)
	var beats0: Array = p0.get("narrative_beats", []) as Array
	_check(beats0.has("observable_exit_sanquan"), "首見 prefix 呈現可觀察畫面")
	_check(not beats0.has("reveals_replacement_truth"), "首見 prefix 不過早揭露替換真相 (K-200)")

	# 第 2 頁：生計
	_check("livelihood" in str(refs_ajie[1]), "第 2 頁為生計落地")

	# 第 3 頁：旅館
	_check("inn_appearance" in str(refs_ajie[2]), "第 3 頁為旅館修繕")

	# 第 4 頁：伴侶（婚姻 → 二十年 → 她先癌逝 → 主角同病死亡）
	_check("partner" in str(refs_ajie[3]), "第 4 頁為伴侶婚姻與死亡順序")
	var p3_ajie := EndingResolver.resolve_ref(str(refs_ajie[3]), loader)
	var beats3_ajie: Array = p3_ajie.get("narrative_beats", []) as Array
	_check(beats3_ajie.has("marriage") and beats3_ajie.has("no_children"), "伴侶頁包含婚姻與無小孩")
	_check(beats3_ajie.has("twenty_years") and beats3_ajie.has("died_early_forties"), "伴侶頁包含二十年與四十出頭時間軸")
	_check(beats3_ajie.has("spouse_dies_first") and beats3_ajie.has("died_of_cancer") and beats3_ajie.has("died_rapidly"), "伴侶頁包含「她先」與癌症 (K-203)")
	_check(beats3_ajie.has("protagonist_same_illness") and beats3_ajie.has("died_rapidly"), "伴侶頁包含主角同病死亡（承重線索 K-203）")

	# 第 5 頁：suffix 黑畫面與庇佑發動
	_check("long_return" in str(refs_ajie[4]), "第 5 頁為庇佑回歸")
	var p4 := EndingResolver.resolve_ref(str(refs_ajie[4]), loader)
	var beats4: Array = p4.get("narrative_beats", []) as Array
	_check(beats4.has("black_screen") and beats4.has("blessing_reactivated"), "suffix 呈現黑畫面與庇佑回歸")

	# (b) 邀阿薇首見長版：同樣包含「她先」與同病死亡
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "awei")
	(gs.get("flags") as Dictionary)["invited_awei"] = true
	(gs.get("flags") as Dictionary)["accepted_inn"] = true
	(gs.get("flags") as Dictionary)["repaired_sign"] = true
	_set_switches(gs, 6)

	var res_awei := EndingResolver.resolve("ending_replaced", gs, loader)
	var refs_awei: Array = res_awei.get("page_refs", []) as Array
	var p3_awei := EndingResolver.resolve_ref(str(refs_awei[3]), loader)
	var beats3_awei: Array = p3_awei.get("narrative_beats", []) as Array
	_check(beats3_awei.has("spouse_dies_first") and beats3_awei.has("protagonist_same_illness"),
		"阿薇長版包含婚姻、她先走與主角同病死亡 (K-203)")

	# (c) 不邀首見長版：先獨身二十年，再播 proxy 回顧與四十出頭癌逝，最後庇佑回歸（不誤播「她先」）
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "acai")
	(gs.get("flags") as Dictionary)["invited_none"] = true
	(gs.get("flags") as Dictionary)["accepted_inn"] = true
	(gs.get("flags") as Dictionary)["repaired_sign"] = true
	_set_switches(gs, 6)

	var res_none := EndingResolver.resolve("ending_replaced", gs, loader)
	var refs_none: Array = res_none.get("page_refs", []) as Array
	_check(refs_none.size() == 6, "不邀首見長版（含 proxy 照片）恰 6 頁 (page_count=%d)" % refs_none.size())
	
	# 第 4 頁：伴侶頁只有獨身二十年，不提前播死亡
	var p3_none := EndingResolver.resolve_ref(str(refs_none[3]), loader)
	var beats3_none: Array = p3_none.get("narrative_beats", []) as Array
	_check(beats3_none.has("no_marriage") and beats3_none.has("single_twenty_years"), "無伴侶長版伴侶頁包含獨身二十年")
	_check(not beats3_none.has("died_of_cancer") and not beats3_none.has("died_early_forties"), "無伴侶伴侶頁不提前播癌症早死（留待 proxy 回顧之後 K-206）")
	_check(not beats3_none.has("spouse_dies_first") and not beats3_none.has("protagonist_same_illness"), "無伴侶伴侶頁不得誤播「她先」或「然後是他」")
	
	# 第 5 頁：proxy 回顧＋四十出頭癌症早死（時間軸：照片回顧 → 癌症早死）
	_check("proxy_acai_long" in str(refs_none[4]), "第 5 頁為代付者阿財照片")
	var p4_none := EndingResolver.resolve_ref(str(refs_none[4]), loader)
	var beats4_none: Array = p4_none.get("narrative_beats", []) as Array
	_check(beats4_none.has("proxy_reminisce") and beats4_none.has("died_early_forties") and beats4_none.has("died_of_cancer") and beats4_none.has("died_rapidly"),
		"proxy 頁面呈現多年後回顧與四十出頭癌症早死 (K-206)")
	
	# 第 6 頁：黑畫面與庇佑回歸
	_check("long_return" in str(refs_none[5]), "第 6 頁為庇佑回歸")
	var p5_none := EndingResolver.resolve_ref(str(refs_none[5]), loader)
	var beats5_none: Array = p5_none.get("narrative_beats", []) as Array
	_check(beats5_none.has("black_screen") and beats5_none.has("blessing_reactivated"), "第 6 頁呈現黑畫面與庇佑回歸")

	# (d) history 只有 BE 結局 -> 正常結局仍為 first_seen
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("ending_history") as Array[Dictionary]).append({ "ending_id": "ending_madness_be", "run_number": 1 })
	(gs.get("ending_history") as Array[Dictionary]).append({ "ending_id": "ending_inventory_be", "run_number": 2 })
	var res_be_hist := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(str(res_be_hist.get("branch", "")) == "first_seen", "只有 BE history 時正常結局仍為 first_seen")

	# (e) history 已有 ending_replaced -> 重見短版
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["invited_ajie"] = true
	(gs.get("flags") as Dictionary)["accepted_inn"] = true
	(gs.get("flags") as Dictionary)["repaired_sign"] = true
	_set_switches(gs, 6)
	(gs.get("ending_history") as Array[Dictionary]).append({ "ending_id": "ending_replaced", "run_number": 1 })
	var res_repeat := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(str(res_repeat.get("branch", "")) == "repeat", "history 已有 ending_replaced 時為 repeat")
	var refs_rep: Array = res_repeat.get("page_refs", []) as Array
	_check(_refs_contain(refs_rep, "again_replaced") and _refs_contain(refs_rep, "short_return"), "重見包含短版 prefix/suffix")
	_check(_refs_contain(refs_rep, "partner_ajie_short"), "重見包含 partner_ajie_short")
	_check(_refs_contain(refs_rep, "livelihood_uncle_high_short"), "重見包含 livelihood_uncle_high_short")
	_check(_refs_contain(refs_rep, "inn_sign_short"), "重見包含 inn_sign_short")
	var p_rep_ajie := EndingResolver.resolve_ref(str(refs_rep[3]), loader)
	var beats_rep_ajie: Array = p_rep_ajie.get("narrative_beats", []) as Array
	_check(beats_rep_ajie.has("spouse_dies_first") and beats_rep_ajie.has("protagonist_same_illness"), "重見短版亦保留她先離世與同病線索 (K-203)")
	_check(EndingResolver.skip_target("ending_replaced", loader) == "short_return", "正常結局 skip_to 指向 short_return")


# ── 7. 兩種 BE 結局獨立性 ────────────────────────────────────────────────────

func _test_7_be_endings_independence(gs: Node, data_node: Node) -> void:
	print("\n--- 7. 兩種 BE 結局隔離與獨立首見計算 ---")
	var loader: DataLoader = data_node.get("loader") as DataLoader

	# (a) ending_madness_be
	_fresh_run(gs, 20, "morning")
	var res_mad_first := EndingResolver.resolve("ending_madness_be", gs, loader)
	_check(bool(res_mad_first.get("ok", false)), "madness BE 首見 resolve 成功")
	var refs_mad_first: Array = res_mad_first.get("page_refs", []) as Array
	_check(refs_mad_first.size() == 1 and str(refs_mad_first[0]).ends_with("/madness_lost"), "madness BE 首見恰 1 頁 (madness_lost)")
	_check(not _refs_contain(refs_mad_first, "replacement") and not _refs_contain(refs_mad_first, "partner_"), "madness BE 不含替換後日談 refs")

	# (b) ending_inventory_be
	_fresh_run(gs, 20, "morning")
	var res_inv_first := EndingResolver.resolve("ending_inventory_be", gs, loader)
	_check(bool(res_inv_first.get("ok", false)), "inventory BE 首見 resolve 成功")
	var refs_inv_first: Array = res_inv_first.get("page_refs", []) as Array
	_check(refs_inv_first.size() == 1 and str(refs_inv_first[0]).ends_with("/inventory_confined"), "inventory BE 首見恰 1 頁 (inventory_confined)")
	_check(not _refs_contain(refs_inv_first, "replacement") and not _refs_contain(refs_inv_first, "partner_"), "inventory BE 不含替換後日談 refs")

	# (c) 獨立首見／重見計算
	_fresh_run(gs)
	(gs.get("ending_history") as Array[Dictionary]).append({ "ending_id": "ending_madness_be", "run_number": 1 })
	_check(bool(gs.call("has_seen_ending", "ending_madness_be")), "has_seen_ending(madness_be) 為 true")
	_check(not bool(gs.call("has_seen_ending", "ending_inventory_be")), "has_seen_ending(inventory_be) 為 false")

	var res_mad_rep := EndingResolver.resolve("ending_madness_be", gs, loader)
	_check(str(res_mad_rep.get("branch", "")) == "repeat", "madness BE 為 repeat")
	var refs_mad_rep: Array = res_mad_rep.get("page_refs", []) as Array
	_check(refs_mad_rep.size() == 1 and str(refs_mad_rep[0]).ends_with("/madness_summary"), "madness BE 重見為 summary 頁")

	var res_inv_still_first := EndingResolver.resolve("ending_inventory_be", gs, loader)
	_check(str(res_inv_still_first.get("branch", "")) == "first_seen", "inventory BE 仍為 first_seen（狀態彼此獨立）")


# ── 8. 不上車 ending_refuse_boarding ──────────────────────────────────────────

func _test_8_refuse_boarding_ending(gs: Node, data_node: Node) -> void:
	print("\n--- 8. 不上車外地人生與快照規格 ---")
	var loader: DataLoader = data_node.get("loader") as DataLoader

	# (a) opening mode 下啟動 ending_refuse_boarding
	_fresh_run(gs)
	_force_opening_mode(gs)
	var start_res: Dictionary = gs.call("_start_ending_from_opening", "refuse_boarding")
	_check(bool(start_res.get("ok", false)), "_start_ending_from_opening 成功")
	_check(str(gs.get("flow_mode")) == "ending", "啟動後進入 ending mode")

	var snapshot: Dictionary = gs.get("active_ending") as Dictionary
	_check(str(snapshot.get("ending_id", "")) == "ending_refuse_boarding", "快照 ending_id 為 ending_refuse_boarding")
	_check(str(snapshot.get("source_id", "")) == "opening_choice", "快照 source_id 為 opening_choice")
	_check(str(snapshot.get("opening_choice_id", "")) == "refuse_boarding", "快照 opening_choice_id 為 refuse_boarding")
	_check(snapshot.get("ended_day") == null, "不上車快照 ended_day 為 null")
	_check(snapshot.get("ended_phase") == null, "不上車快照 ended_phase 為 null")
	_check(snapshot.get("partner_variant") == null, "不上車快照 partner_variant 為 null")
	_check(snapshot.get("livelihood_variant") == null, "不上車快照 livelihood_variant 為 null")
	_check(snapshot.get("inn_appearance_variant") == null, "不上車快照 inn_appearance_variant 為 null")
	_check(snapshot.get("festival_proxy_npc") == null, "不上車快照 festival_proxy_npc 為 null")
	_check((snapshot.get("knowledge_gained_this_run", []) as Array).is_empty(), "不上車快照 knowledge_gained_this_run 為空陣列")

	# (b) 內容順序涵蓋外地生活、癌症早死與庇佑回歸
	var refs: Array = snapshot.get("page_refs", []) as Array
	_check(refs.size() == 2, "不上車首見恰 2 頁 (page_count=%d)" % refs.size())
	var page0 := EndingResolver.resolve_ref(str(refs[0]), loader)
	var page1 := EndingResolver.resolve_ref(str(refs[1]), loader)
	var beats_page0: Array = page0.get("narrative_beats", []) as Array
	var beats_page1: Array = page1.get("narrative_beats", []) as Array
	_check(bool(page0.get("ok", false)) and beats_page0.has("outside_ordinary_life"), "第 1 頁描述外地普通生活")
	_check(bool(page1.get("ok", false)) and beats_page1.has("died_early_forties") and beats_page1.has("died_of_cancer") and beats_page1.has("blessing_reactivated"), "第 2 頁描述四十出頭癌症早死與庇佑回歸")

	# (c) 重見不上車為摘要短篇
	_fresh_run(gs)
	_force_opening_mode(gs)
	(gs.get("ending_history") as Array[Dictionary]).append({ "ending_id": "ending_refuse_boarding", "run_number": 1 })
	var rep_start: Dictionary = gs.call("_start_ending_from_opening", "refuse_boarding")
	_check(bool(rep_start.get("ok", false)), "重見不上車啟動成功")
	var rep_snap: Dictionary = gs.get("active_ending") as Dictionary
	var rep_refs: Array = rep_snap.get("page_refs", []) as Array
	_check(rep_refs.size() == 1, "重見不上車恰 1 頁")
	var rep_p0 := EndingResolver.resolve_ref(str(rep_refs[0]), loader)
	var beats_rep_p0: Array = rep_p0.get("narrative_beats", []) as Array
	_check(bool(rep_p0.get("ok", false)) and beats_rep_p0.has("refuse_boarding_summary"), "重見不上車播摘要文字")
	_check(EndingResolver.skip_target("ending_refuse_boarding", loader) == "complete", "不上車 skip_to 指向 complete")


# ── 9. 四類結局逐頁 ready_to_complete 門檻與動作原子性 (P5C-V3) ───────────────

func _test_9_lifecycle_ready_to_complete_all_four(gs: Node, data_node: Node) -> void:
	print("\n--- 9. 四類結局逐頁 ready_to_complete 門檻與動作原子性 ---")

	# (a) 三類 run 結局在末頁揭露前 ready_to_complete 恆為 false
	var run_cases := [
		{ "id": "ending_replaced", "source": "d45_coda", "proxy": "ajie" },
		{ "id": "ending_madness_be", "source": "madness_cap", "proxy": "" },
		{ "id": "ending_inventory_be", "source": "ending_effect", "proxy": "" },
	]
	for c in run_cases:
		_fresh_run(gs, 45, "evening")
		if not str(c["proxy"]).is_empty():
			gs.set("selected_festival_proxy_npc", str(c["proxy"]))
		var sres: Dictionary = gs.call("start_ending", str(c["id"]), str(c["source"]))
		_check(bool(sres.get("ok", false)), "啟動 %s 成功" % str(c["id"]))

		var view: Dictionary = gs.call("ending_view")
		var total_pages := int(view.get("page_count", 0))
		_check(not bool(view.get("can_complete", true)), "%s 初始 can_complete 為 false" % str(c["id"]))

		for i in range(total_pages):
			var rev: Dictionary = gs.call("reveal_ending_page")
			_check(bool(rev.get("ok", false)), "%s 揭露第 %d 頁成功" % [str(c["id"]), i])
			var cur_view: Dictionary = gs.call("ending_view")
			if i < total_pages - 1:
				_check(not bool(cur_view.get("can_complete", true)), "%s 非末頁 (第 %d 頁) can_complete 仍為 false" % [str(c["id"]), i])
				var adv: Dictionary = gs.call("advance_ending_page")
				_check(bool(adv.get("ok", false)), "%s 翻到第 %d 頁成功" % [str(c["id"]), i + 1])
			else:
				_check(bool(cur_view.get("can_complete", false)), "%s 末頁揭露後 can_complete 變為 true" % str(c["id"]))

	# (b) 不上車結局 (ending_refuse_boarding) 首見 2 頁逐頁門檻
	_fresh_run(gs)
	_force_opening_mode(gs)
	var rb_start: Dictionary = gs.call("_start_ending_from_opening", "refuse_boarding")
	_check(bool(rb_start.get("ok", false)), "首見不上車啟動成功")
	var rb_view0: Dictionary = gs.call("ending_view")
	_check(int(rb_view0.get("page_count", 0)) == 2, "不上車首見為 2 頁")
	_check(not bool(rb_view0.get("can_complete", true)), "不上車初始 can_complete 為 false")

	# 揭露第 0 頁
	var rb_rev0: Dictionary = gs.call("reveal_ending_page")
	_check(bool(rb_rev0.get("ok", false)), "不上車揭露第 0 頁成功")
	var rb_view_rev0: Dictionary = gs.call("ending_view")
	_check(not bool(rb_view_rev0.get("can_complete", true)), "不上車第 0 頁 (非末頁) 揭露後 can_complete 仍為 false")

	# 翻到第 1 頁（末頁）
	var rb_adv0: Dictionary = gs.call("advance_ending_page")
	_check(bool(rb_adv0.get("ok", false)), "不上車翻到第 1 頁成功")
	var rb_view_adv0: Dictionary = gs.call("ending_view")
	_check(not bool(rb_view_adv0.get("can_complete", true)), "不上車第 1 頁未揭露前 can_complete 仍為 false")

	# 揭露第 1 頁（末頁）
	var rb_rev1: Dictionary = gs.call("reveal_ending_page")
	_check(bool(rb_rev1.get("ok", false)), "不上車揭露第 1 頁成功")
	var rb_view_rev1: Dictionary = gs.call("ending_view")
	_check(bool(rb_view_rev1.get("can_complete", false)), "不上車末頁揭露後 can_complete 變為 true")

	# (c) 重見不上車 skip_seen_ending 後直接 ready
	_fresh_run(gs)
	_force_opening_mode(gs)
	(gs.get("ending_history") as Array[Dictionary]).append({ "ending_id": "ending_refuse_boarding", "run_number": 1 })
	gs.call("_start_ending_from_opening", "refuse_boarding")
	var rb_rep_view: Dictionary = gs.call("ending_view")
	_check(bool(rb_rep_view.get("can_skip", false)), "重見不上車 can_skip 為 true")
	var rb_skip_res: Dictionary = gs.call("skip_seen_ending")
	_check(bool(rb_skip_res.get("ok", false)), "不上車 skip_seen_ending 成功")
	var rb_after_skip: Dictionary = gs.call("ending_view")
	_check(bool(rb_after_skip.get("can_complete", false)), "不上車跳過後直接進入 can_complete")

	# (d) 重見正常結局 skip_seen_ending 後直接進入 ready
	_fresh_run(gs, 45, "evening")
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("ending_history") as Array[Dictionary]).append({ "ending_id": "ending_replaced", "run_number": 1 })
	gs.call("start_ending", "ending_replaced", "d45_coda")
	var before_skip: Dictionary = gs.call("ending_view")
	_check(bool(before_skip.get("can_skip", false)), "重見結局 can_skip 為 true")
	var skip_res: Dictionary = gs.call("skip_seen_ending")
	_check(bool(skip_res.get("ok", false)), "skip_seen_ending 成功")
	var after_skip: Dictionary = gs.call("ending_view")
	_check(bool(after_skip.get("can_complete", false)), "跳過後直接進入 can_complete")

	# (e) 重複 start_ending 被擋，且不產生第二份快照
	var snap_before := JSON.stringify(gs.get("active_ending"))
	var dup_res: Dictionary = gs.call("start_ending", "ending_replaced", "d45_coda")
	_check(str(dup_res.get("reason_code", "")) == "not_run", "ending mode 重複呼叫 start_ending 回 not_run")
	_check(JSON.stringify(gs.get("active_ending")) == snap_before, "重複呼叫不產生第二份快照，active_ending 零變化")


# ── 10. Resolver 壞資料 data_conflict 防禦 (P5C-V4) ───────────────────────────

func _test_10_resolver_bad_data_defense(gs: Node, data_node: Node) -> void:
	print("\n--- 10. Resolver 壞資料 data_conflict 防禦 ---")
	var base_loader: DataLoader = data_node.get("loader") as DataLoader

	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")

	# (a) 刪除 prefix_pages
	var bad_l1 := DataLoader.new()
	bad_l1.endings_by_id = base_loader.endings_by_id.duplicate(true)
	var e1: Dictionary = (bad_l1.endings_by_id["ending_replaced"] as Dictionary).duplicate(true)
	var fs1: Dictionary = (e1["first_seen"] as Dictionary).duplicate(true)
	fs1.erase("prefix_pages")
	e1["first_seen"] = fs1
	bad_l1.endings_by_id["ending_replaced"] = e1
	var r1 := EndingResolver.resolve("ending_replaced", gs, bad_l1)
	_check(not bool(r1.get("ok", false)) and str(r1.get("reason_code", "")) == "data_conflict",
		"缺少 prefix_pages 回 data_conflict")

	# (b) 刪除 suffix_pages
	var bad_l2 := DataLoader.new()
	bad_l2.endings_by_id = base_loader.endings_by_id.duplicate(true)
	var e2: Dictionary = (bad_l2.endings_by_id["ending_replaced"] as Dictionary).duplicate(true)
	var fs2: Dictionary = (e2["first_seen"] as Dictionary).duplicate(true)
	fs2.erase("suffix_pages")
	e2["first_seen"] = fs2
	bad_l2.endings_by_id["ending_replaced"] = e2
	var r2 := EndingResolver.resolve("ending_replaced", gs, bad_l2)
	_check(not bool(r2.get("ok", false)) and str(r2.get("reason_code", "")) == "data_conflict",
		"缺少 suffix_pages 回 data_conflict")

	# (c) 刪除 variant rule 的 first_seen_pages 欄位
	var bad_l3 := DataLoader.new()
	bad_l3.endings_by_id = base_loader.endings_by_id.duplicate(true)
	var e3: Dictionary = (bad_l3.endings_by_id["ending_replaced"] as Dictionary).duplicate(true)
	var vgs3: Array = (e3["variant_groups"] as Array).duplicate(true)
	var vg0: Dictionary = (vgs3[0] as Dictionary).duplicate(true)
	var rules0: Array = (vg0["rules"] as Array).duplicate(true)
	var r0_0: Dictionary = (rules0[0] as Dictionary).duplicate(true)
	r0_0.erase("first_seen_pages")
	rules0[0] = r0_0
	vg0["rules"] = rules0
	vgs3[0] = vg0
	e3["variant_groups"] = vgs3
	bad_l3.endings_by_id["ending_replaced"] = e3
	(gs.get("flags") as Dictionary)["accepted_inn"] = true
	_set_switches(gs, 6)
	var r3 := EndingResolver.resolve("ending_replaced", gs, bad_l3)
	_check(not bool(r3.get("ok", false)) and str(r3.get("reason_code", "")) == "data_conflict",
		"rule 缺少 first_seen_pages 欄位回 data_conflict")

	# (d) 建立多個 fallback: true
	var bad_l4 := DataLoader.new()
	bad_l4.endings_by_id = base_loader.endings_by_id.duplicate(true)
	var e4: Dictionary = (bad_l4.endings_by_id["ending_replaced"] as Dictionary).duplicate(true)
	var vgs4: Array = (e4["variant_groups"] as Array).duplicate(true)
	var vg_inn: Dictionary = (vgs4[1] as Dictionary).duplicate(true)
	var r_inn: Array = (vg_inn["rules"] as Array).duplicate(true)
	# 把 sign 也改成 fallback
	var r_sign: Dictionary = (r_inn[0] as Dictionary).duplicate(true)
	r_sign["fallback"] = true
	r_sign.erase("when")
	r_inn[0] = r_sign
	vg_inn["rules"] = r_inn
	vgs4[1] = vg_inn
	e4["variant_groups"] = vgs4
	bad_l4.endings_by_id["ending_replaced"] = e4
	var r4 := EndingResolver.resolve("ending_replaced", gs, bad_l4)
	_check(not bool(r4.get("ok", false)) and str(r4.get("reason_code", "")) == "data_conflict",
		"多個 fallback: true 回 data_conflict")

	# (e) 0 個 fallback
	var bad_l5 := DataLoader.new()
	bad_l5.endings_by_id = base_loader.endings_by_id.duplicate(true)
	var e5: Dictionary = (bad_l5.endings_by_id["ending_replaced"] as Dictionary).duplicate(true)
	var vgs5: Array = (e5["variant_groups"] as Array).duplicate(true)
	var vg_p: Dictionary = (vgs5[2] as Dictionary).duplicate(true)
	var r_p: Array = (vg_p["rules"] as Array).duplicate(true)
	r_p[-1].erase("fallback")
	r_p[-1]["when"] = { "flag": "no_flag" }
	vg_p["rules"] = r_p
	vgs5[2] = vg_p
	e5["variant_groups"] = vgs5
	bad_l5.endings_by_id["ending_replaced"] = e5
	var r5 := EndingResolver.resolve("ending_replaced", gs, bad_l5)
	_check(not bool(r5.get("ok", false)) and str(r5.get("reason_code", "")) == "data_conflict",
		"0 個 fallback 回 data_conflict")


# ── 11. Deserialize Variant 集合與 Page Ref 一致性驗證 (P5C-V7) ───────────────

func _test_11_deserialize_variant_validation(gs: Node, _data_node: Node) -> void:
	print("\n--- 11. Deserialize Variant 集合與 Page Ref 一致性驗證 ---")

	# 取得基準合法的 composite ending 快照
	_fresh_run(gs, 45, "evening")
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["invited_ajie"] = true
	(gs.get("flags") as Dictionary)["accepted_inn"] = true
	(gs.get("flags") as Dictionary)["repaired_sign"] = true
	_set_switches(gs, 6)
	gs.call("start_ending", "ending_replaced", "d45_coda")
	gs.call("reveal_ending_page")

	var good_save: Dictionary = gs.call("serialize")
	var baseline_text := _state_text(gs)
	var roundtrip_res: Dictionary = gs.call("deserialize", JSON.parse_string(baseline_text) as Dictionary)
	_check(bool(roundtrip_res.get("ok", false)), "基準 composite 快照 deserialize 成功")
	_check(_state_text(gs) == baseline_text, "基準快照往返序列化字串完全相同")

	# (a) 未知 livelihood_variant (例如舊版 "uncle" 或任意非 12 格字串) -> invalid_save_shape
	var bad_var_cases := [
		["livelihood_variant: uncle (舊版未帶開關帶)", "livelihood_variant", "uncle"],
		["livelihood_variant: nonexistent", "livelihood_variant", "nonexistent"],
		["partner_variant: nonexistent", "partner_variant", "nonexistent"],
		["inn_appearance_variant: nonexistent", "inn_appearance_variant", "nonexistent"],
	]
	for bvc in bad_var_cases:
		var label: String = bvc[0]
		var field: String = bvc[1]
		var val: String = bvc[2]
		var broken: Dictionary = JSON.parse_string(baseline_text) as Dictionary
		((broken["flow"] as Dictionary)["active_ending"] as Dictionary)[field] = val
		var before := _state_text(gs)
		var res: Dictionary = gs.call("deserialize", broken)
		_check(not bool(res.get("ok", true)) and str(res.get("reason_code", "")) == "invalid_save_shape",
			"壞 variant「%s」→ invalid_save_shape" % label)
		_check(_state_text(gs) == before, "壞 variant 拒絕後狀態零變化")

	# (b) variant 與 page_refs 矛盾 (快照標 livelihood_variant=uncle_low，但 refs 包含 uncle_high)
	var broken_ref_mismatch: Dictionary = JSON.parse_string(baseline_text) as Dictionary
	((broken_ref_mismatch["flow"] as Dictionary)["active_ending"] as Dictionary)["livelihood_variant"] = "uncle_low"
	var before_mismatch := _state_text(gs)
	var res_mismatch: Dictionary = gs.call("deserialize", broken_ref_mismatch)
	_check(not bool(res_mismatch.get("ok", true)) and str(res_mismatch.get("reason_code", "")) == "invalid_save_shape",
		"variant 與 page_refs 矛盾 → invalid_save_shape")
	_check(_state_text(gs) == before_mismatch, "矛盾快照拒絕後狀態零變化")

	# (c) linear ending 偽帶 variant 欄位 -> invalid_save_shape
	_fresh_run(gs, 20, "morning")
	gs.call("start_ending", "ending_madness_be", "madness_cap")
	var madness_save: Dictionary = gs.call("serialize")
	var madness_text := _state_text(gs)
	var broken_linear: Dictionary = JSON.parse_string(madness_text) as Dictionary
	((broken_linear["flow"] as Dictionary)["active_ending"] as Dictionary)["partner_variant"] = "ajie"
	var before_linear := _state_text(gs)
	var res_linear: Dictionary = gs.call("deserialize", broken_linear)
	_check(not bool(res_linear.get("ok", true)) and str(res_linear.get("reason_code", "")) == "invalid_save_shape",
		"linear ending 偽帶 partner_variant → invalid_save_shape")
	_check(_state_text(gs) == before_linear, "linear 偽帶 variant 拒絕後狀態零變化")

	# (d) lookup ref 的 NPC 與 festival_proxy_npc 矛盾（快照標 proxy=ajie，但 refs 包含 proxy_acai_long）
	_fresh_run(gs, 45, "evening")
	gs.set("selected_festival_proxy_npc", "acai")
	(gs.get("flags") as Dictionary)["invited_none"] = true
	gs.call("start_ending", "ending_replaced", "d45_coda")
	var uninvited_base_text := _state_text(gs)
	var broken_proxy_mismatch: Dictionary = JSON.parse_string(uninvited_base_text) as Dictionary
	((broken_proxy_mismatch["flow"] as Dictionary)["active_ending"] as Dictionary)["festival_proxy_npc"] = "ajie"
	var before_proxy_mismatch := _state_text(gs)
	var res_proxy_mismatch: Dictionary = gs.call("deserialize", broken_proxy_mismatch)
	_check(not bool(res_proxy_mismatch.get("ok", true)) and str(res_proxy_mismatch.get("reason_code", "")) == "invalid_save_shape",
		"lookup ref 與 festival_proxy_npc 矛盾 → invalid_save_shape")
	_check(_state_text(gs) == before_proxy_mismatch, "proxy 矛盾快照拒絕後狀態零變化")

	# (e) lookup ref 的 when_group 與 partner_variant 矛盾（快照標 partner=ajie，但 refs 包含 uninvited proxy）
	var broken_when_mismatch: Dictionary = JSON.parse_string(uninvited_base_text) as Dictionary
	((broken_when_mismatch["flow"] as Dictionary)["active_ending"] as Dictionary)["partner_variant"] = "ajie"
	var before_when_mismatch := _state_text(gs)
	var res_when_mismatch: Dictionary = gs.call("deserialize", broken_when_mismatch)
	_check(not bool(res_when_mismatch.get("ok", true)) and str(res_when_mismatch.get("reason_code", "")) == "invalid_save_shape",
		"lookup ref 與 partner_variant (when_group) 矛盾 → invalid_save_shape")
	_check(_state_text(gs) == before_when_mismatch, "when_group 矛盾快照拒絕後狀態零變化")


# ── 12. 全 432 組排列與全結局結構版文字走查 ────────────────────────────────────

func _test_12_structural_text_walkthrough(gs: Node, data_node: Node) -> void:
	print("\n--- 12. 全 432 組 normal composite 與全結局結構版文字走查 ---")
	var loader: DataLoader = data_node.get("loader") as DataLoader

	var partners := ["invited_ajie", "invited_awei", "invited_none"]
	var livelihood_routes := [
		{ "flag": "accepted_inn", "sw": 6 },
		{ "flag": "accepted_inn", "sw": 3 },
		{ "flag": "accepted_inn", "sw": 0 },
		{ "flag": "accepted_outside_job", "sw": 6 },
		{ "flag": "accepted_outside_job", "sw": 3 },
		{ "flag": "accepted_outside_job", "sw": 0 },
		{ "flag": "accepted_job", "sw": 6 },
		{ "flag": "accepted_job", "sw": 3 },
		{ "flag": "accepted_job", "sw": 0 },
		{ "flag": "none", "sw": 6 },
		{ "flag": "none", "sw": 3 },
		{ "flag": "none", "sw": 0 },
	]
	var inn_repairs := ["repaired_sign", "repaired_pipes", "repaired_windows", "none"]
	var proxy_npcs := ["ajie", "awei", "acai"]

	var total_combos := 0
	for p in partners:
		for l in livelihood_routes:
			for r in inn_repairs:
				for prx in proxy_npcs:
					total_combos += 1
					_fresh_run(gs)
					gs.set("selected_festival_proxy_npc", prx)
					if p != "invited_none":
						(gs.get("flags") as Dictionary)[p] = true
					if str(l["flag"]) != "none":
						(gs.get("flags") as Dictionary)[str(l["flag"])] = true
					_set_switches(gs, int(l["sw"]))
					if r != "none":
						(gs.get("flags") as Dictionary)[r] = true

					# 驗證首見 (long)
					var res_long := EndingResolver.resolve("ending_replaced", gs, loader)
					_check_walkthrough_result(res_long, "combo_long_%d" % total_combos, loader)

					# 驗證重見 (short)
					(gs.get("ending_history") as Array[Dictionary]).append({ "ending_id": "ending_replaced", "run_number": 1 })
					var res_short := EndingResolver.resolve("ending_replaced", gs, loader)
					_check_walkthrough_result(res_short, "combo_short_%d" % total_combos, loader)

	_ok("432 組組合（12 生計 × 4 修繕 × 3 伴侶 × 3 proxy × 首見／重見共 864 次求值）全部無缺頁、無重頁、無空白頁")

	# 走查 linear 結局 (madness, inventory, refuse_boarding)
	for lid in ["ending_madness_be", "ending_inventory_be", "ending_refuse_boarding"]:
		_fresh_run(gs)
		var l_first := EndingResolver.resolve(lid, gs, loader)
		_check_walkthrough_result(l_first, "%s_first" % lid, loader)

		(gs.get("ending_history") as Array[Dictionary]).append({ "ending_id": lid, "run_number": 1 })
		var l_rep := EndingResolver.resolve(lid, gs, loader)
		_check_walkthrough_result(l_rep, "%s_repeat" % lid, loader)

	_ok("三類 linear 結局首見與重見全部走查通過")


func _check_walkthrough_result(res: Dictionary, label: String, loader: DataLoader) -> void:
	if not bool(res.get("ok", false)):
		_fail("%s: resolve 失敗: %s" % [label, str(res.get("reason_code", ""))])
		return
	var refs: Array = res.get("page_refs", []) as Array
	if refs.is_empty():
		_fail("%s: page_refs 為空" % label)
		return

	var seen_pages: Dictionary = {}
	for ref_val: Variant in refs:
		var ref_str := str(ref_val)
		if seen_pages.has(ref_str):
			_fail("%s: 發現重複頁面 ref: %s" % [label, ref_str])
		seen_pages[ref_str] = true

		var page := EndingResolver.resolve_ref(ref_str, loader)
		if not bool(page.get("ok", false)):
			_fail("%s: resolve_ref 失敗: %s" % [label, ref_str])
		var text := str(page.get("text", "")).strip_edges()
		if text.is_empty():
			_fail("%s: 頁面文字為空: %s" % [label, ref_str])
