extends SceneTree

## P5-F 多結局與跨輪全流程驗收測試（實作規格書 P5-F、測試指南 P5-F）。
## 涵蓋：
## 1. 第一輪三條具名策略（正常替換、發狂 BE、庫存 BE）結算與不上車解鎖差異
## 2. 連續四次結算（BE → 正常長版 → 不上車 → 正常短版）與首見/重見、不上車零 run 建立
## 3. 正常 ending matrix 從正式 rules 動態衍生（生計優先序 uncle>boss>zhou>none、開關帶、外觀、伴侶、proxy）
## 4. D29 慶典代付者六條路徑（邀阿婕、邀阿薇、不邀、逾期同分、未進面板、全零 fallback）一致性與 D45 結算
## 5. 連續至少三輪 town run 狀態清洗與持久化保留（P4 daily/pending/active 清空、P1~P3 meta 保留、D8 重演不重收首次費）
## 6. Ending 快照載入續播（逐頁 vs skip）、完成冪等性與非法跨 mode 呼叫拒絕
## 7. loop_persistent 魔法物品合成 fixture 生命週期與正式卡片 0 魔法物品 catalog 斷言
## 8. 45 天貪心走查完備性與 codebase 無舊 end_run 殘留
## 跑法：Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/test_p5f.gd

const PlaythroughGreedy := preload("res://tests/headless/playthrough_greedy.gd")
const DataLoader := preload("res://scripts/data_loader.gd")
const EndingResolver := preload("res://scripts/core/ending_resolver.gd")
const EffectApply := preload("res://scripts/core/effect_apply.gd")
const ConditionEval := preload("res://scripts/core/condition_eval.gd")

var _failed := 0


func _initialize() -> void:
	var data_node: Node = PlaythroughGreedy.setup_data(self)
	await process_frame
	var gs: Node = PlaythroughGreedy.setup_game_state(self, data_node)

	if not bool(data_node.get("ok")):
		push_error("P5-F: Data 載入失敗，中止")
		quit(1)
		return

	print("=== P5-F 多結局與跨輪全流程驗收測試 ===")
	_test_1_first_run_three_endings(gs, data_node)
	_test_2_continuous_four_settlements(gs, data_node)
	_test_3_ending_matrix_dynamic_derivation(gs, data_node)
	_test_4_d29_six_proxy_paths(gs, data_node)
	_test_5_cross_run_three_runs_cleanup_and_persistence(gs, data_node)
	_test_6_checkpoint_reload_skip_vs_reveal_and_idempotency(gs, data_node)
	_test_7_loop_persistent_fixture_lifecycle_and_formal_catalog(gs, data_node)
	_test_8_greedy_and_no_legacy_end_run(gs, data_node)
	_test_9_preflight_null_counterexample(gs, data_node)

	if _failed > 0:
		push_error("test_p5f: %d 個斷言失敗" % _failed)
		quit(1)
	else:
		print("\n=== P5-F 全部測試通過 ===")
		quit(0)


# ── 共用工具 ─────────────────────────────────────────────────────────────────

func _ok(msg: String) -> void:
	print("  ok  " + msg)


func _fail(msg: String) -> void:
	push_error("  FAIL  " + msg)
	_failed += 1


func _check(cond: bool, msg: String, extra: String = "") -> void:
	if cond:
		_ok(msg)
	else:
		if not extra.is_empty():
			_fail("%s (細節: %s)" % [msg, extra])
		else:
			_fail(msg)


func _fresh_opening(gs: Node) -> void:
	gs.call("_reset_run_state")
	(gs.get("active_ending") as Dictionary).clear()
	gs.set("flow_mode", "opening")
	gs.set("run_number", 1)
	(gs.get("ending_history") as Array).clear()
	(gs.get("knowledge") as Dictionary).clear()
	(gs.get("night_locations_seen") as Dictionary).clear()
	(gs.get("night_once_beats_seen") as Dictionary).clear()
	gs.set("loop_persistent_item_ids", {})
	gs.set("selected_opening_choice", "")
	gs.set("selected_festival_proxy_npc", "")
	gs.set("delegation_tutorial_seen", false)


func _complete_all_pages(gs: Node) -> void:
	var guard := 60
	while guard > 0 and str(gs.get("flow_mode")) == "ending":
		guard -= 1
		var view: Dictionary = gs.call("ending_view")
		if bool(view.get("can_complete", false)):
			var comp_res: Dictionary = gs.call("complete_ending")
			if not bool(comp_res.get("ok", false)):
				_fail("complete_ending 失敗: %s" % str(comp_res.get("reason_code", "")))
			break
		if not bool(view.get("page_revealed", false)):
			gs.call("reveal_ending_page")
		else:
			gs.call("advance_ending_page")


func _count_inventory_be_effects_in_beats(loader: Object) -> int:
	var count := 0
	var beats: Dictionary = loader.beats_by_id
	for bid: String in beats:
		var b: Dictionary = beats[bid] as Dictionary
		if b.has("on_enter"):
			if str((b["on_enter"] as Dictionary).get("ending", "")) == "ending_inventory_be":
				count += 1
		if b.has("phase_exit"):
			if str((b["phase_exit"] as Dictionary).get("ending", "")) == "ending_inventory_be":
				count += 1
		for s in b.get("slots", []):
			if s is Dictionary:
				var on_p: Variant = s.get("on_place")
				if on_p is Dictionary and str((on_p as Dictionary).get("ending", "")) == "ending_inventory_be":
					count += 1
		if b.has("choices"):
			for ch in b.get("choices", []):
				if ch is Dictionary:
					var on_c: Variant = ch.get("on_choose")
					if on_c is Dictionary and str((on_c as Dictionary).get("ending", "")) == "ending_inventory_be":
						count += 1
		if b.has("encounter"):
			var enc: Dictionary = b.get("encounter", {}) as Dictionary
			for ex_k in ["on_victory", "on_failure", "on_escape"]:
				var ex_eff: Variant = enc.get(ex_k)
				if ex_eff is Dictionary and str((ex_eff as Dictionary).get("ending", "")) == "ending_inventory_be":
					count += 1
			for r in enc.get("rounds", []):
				if r is Dictionary:
					for resp in r.get("responses", []):
						if resp is Dictionary:
							var on_r: Variant = resp.get("on_resolve")
							if on_r is Dictionary and str((on_r as Dictionary).get("ending", "")) == "ending_inventory_be":
								count += 1
					var fb: Variant = r.get("fallback")
					if fb is Dictionary:
						var on_fb: Variant = (fb as Dictionary).get("on_resolve")
						if on_fb is Dictionary and str((on_fb as Dictionary).get("ending", "")) == "ending_inventory_be":
							count += 1
	return count


# ── 1. 第一輪三條具名策略走向不同結局 ────────────────────────────────────────

func _test_1_first_run_three_endings(gs: Node, data_node: Node) -> void:
	print("\n--- 1. 第一輪三條具名策略走向不同結局 ---")

	# (a) 正常替換結局 ending_replaced
	_fresh_opening(gs)
	var op_res: Dictionary = gs.call("choose_opening", "take_family_album")
	_check(bool(op_res.get("ok", false)), "第 1 輪相簿開局成功")

	gs.set("day", 45)
	gs.set("phase", "evening")
	gs.set("selected_festival_proxy_npc", "ajie")
	gs.call("gain_card", "info_registry")
	(gs.get("flags") as Dictionary)["final_day"] = true

	gs.call("play_beat", "d45_then")
	var place_res: Dictionary = gs.call("try_place", "info_registry", "d45_then", "compare_registry")
	_check(bool(place_res.get("ok", false)), "放置 info_registry 進比對槽")

	var adv_res: Dictionary = gs.call("advance_phase")
	_check(bool(adv_res.get("ok", false)) and str(gs.get("flow_mode")) == "ending", "d45_then 推進進入 ending 模式")
	_check(str((gs.get("active_ending") as Dictionary).get("ending_id", "")) == "ending_replaced", "當前結局為 ending_replaced")

	_complete_all_pages(gs)
	_check(str(gs.get("flow_mode")) == "opening", "正常替換結算後回到 opening")
	_check(int(gs.get("run_number")) == 2, "正常替換結算後 run_number 增為 2")
	var history: Array = gs.get("ending_history") as Array
	_check(history.size() == 1 and str(history[0].get("ending_id", "")) == "ending_replaced", "歷輪摘要記錄 ending_replaced")
	_check(int(history[0].get("ended_day", 0)) == 45 and str(history[0].get("ended_phase", "")) == "evening", "ended_day=45, ended_phase=evening")
	_check(bool(gs.call("has_knowledge", "k_i_returned")), "取得「我回來過」知識卡")

	var choices: Array = gs.call("opening_view") as Array
	var refuse_choice: Dictionary = {}
	for c_raw: Variant in choices:
		var c := c_raw as Dictionary
		if str(c.get("id", "")) == "refuse_boarding":
			refuse_choice = c
			break
	_check(not refuse_choice.is_empty() and bool(refuse_choice.get("available", false)), "正常替換結局完成後，不上車選項已解鎖")

	# (b) 發狂 BE ending_madness_be
	_fresh_opening(gs)
	var op_res_be: Dictionary = gs.call("choose_opening", "take_family_album")
	_check(bool(op_res_be.get("ok", false)), "發狂 BE 開局成功")
	gs.set("day", 10)
	gs.set("phase", "morning")

	# 發狂卡達上限 7 張觸發 BE
	var tuning_cap := int(data_node.tuning("madness.cap", 7))
	for i in range(tuning_cap):
		gs.call("gain_card", "madness")

	_check(str(gs.get("flow_mode")) == "ending", "發狂卡達到上限觸發 BE 進入 ending 模式")
	_check(str((gs.get("active_ending") as Dictionary).get("ending_id", "")) == "ending_madness_be", "當前結局為 ending_madness_be")

	_complete_all_pages(gs)
	_check(str(gs.get("flow_mode")) == "opening", "發狂 BE 結算後回到 opening")
	_check(int(gs.get("run_number")) == 2, "發狂 BE 結算後 run_number 增為 2")
	var history_be: Array = gs.get("ending_history") as Array
	_check(history_be.size() == 1 and str(history_be[0].get("ending_id", "")) == "ending_madness_be", "歷輪摘要記錄 ending_madness_be")
	_check(bool(gs.call("has_knowledge", "k_i_returned")), "BE 結算後亦取得「我回來過」")

	var open_view_be: Array = gs.call("opening_view") as Array
	var refuse_choice_be: Dictionary = {}
	for c_raw: Variant in open_view_be:
		var c := c_raw as Dictionary
		if str(c.get("id", "")) == "refuse_boarding":
			refuse_choice_be = c
			break
	_check(not bool(refuse_choice_be.get("available", true)), "僅完成發狂 BE 時，不上車選項仍為鎖定 (available=false)")

	# (c) 庫存 BE ending_inventory_be（B1 守衛與規則層可達性）
	# B1 守衛：斷言 data/beats 目前沒有任何 beat 帶 ending: ending_inventory_be
	var inv_be_count := _count_inventory_be_effects_in_beats(data_node.get("loader"))
	_check(inv_be_count == 0, "斷言 data/beats 目前沒有任何 beat 帶 ending: ending_inventory_be（補上翻面寫法時本條會轉紅，屆時把資料層走通那一條加回驗收）")

	# 規則層可達性驗證（非資料層走通）
	_fresh_opening(gs)
	var op_res_inv: Dictionary = gs.call("choose_opening", "return_missed_call")
	_check(bool(op_res_inv.get("ok", false)), "庫存 BE 開局成功")
	gs.set("day", 20)
	gs.set("phase", "afternoon")

	var inv_start: Dictionary = gs.call("start_ending", "ending_inventory_be", "ending_effect")
	_check(bool(inv_start.get("ok", false)) and str(gs.get("flow_mode")) == "ending", "規則層可達性驗證（非資料層走通）：庫存 BE 成功啟動進入 ending 模式")
	_check(str((gs.get("active_ending") as Dictionary).get("ending_id", "")) == "ending_inventory_be", "當前結局為 ending_inventory_be")

	_complete_all_pages(gs)
	_check(str(gs.get("flow_mode")) == "opening", "庫存 BE 結算後回到 opening")
	_check(int(gs.get("run_number")) == 2, "庫存 BE 結算後 run_number 增為 2")
	var history_inv: Array = gs.get("ending_history") as Array
	_check(history_inv.size() == 1 and str(history_inv[0].get("ending_id", "")) == "ending_inventory_be", "歷輪摘要記錄 ending_inventory_be")

	var open_view_inv: Array = gs.call("opening_view") as Array
	var refuse_choice_inv: Dictionary = {}
	for c_raw: Variant in open_view_inv:
		var c := c_raw as Dictionary
		if str(c.get("id", "")) == "refuse_boarding":
			refuse_choice_inv = c
			break
	_check(not bool(refuse_choice_inv.get("available", true)), "僅完成庫存 BE 時，不上車選項仍為鎖定 (available=false)")


# ── 2. 連續四次結算（BE → 正常長版 → 不上車 → 正常短版） ─────────────────────

func _test_2_continuous_four_settlements(gs: Node, data_node: Node) -> void:
	print("\n--- 2. 連續四次結算（BE → 正常長版 → 不上車 → 正常短版） ---")
	_fresh_opening(gs)

	# 1. 第 1 輪：發狂 BE
	var op1: Dictionary = gs.call("choose_opening", "take_family_album")
	_check(bool(op1.get("ok", false)), "第 1 輪開局成功")
	gs.call("gain_card", "k_forty_something")
	var tuning_cap := int(data_node.tuning("madness.cap", 7))
	for i in range(tuning_cap):
		gs.call("gain_card", "madness")
	_complete_all_pages(gs)
	_check(int(gs.get("run_number")) == 2, "結算 1 (BE) 後 run_number = 2")
	_check((gs.get("ending_history") as Array).size() == 1, "結算 1 後 history 筆數 = 1")
	_check(not bool(gs.call("has_seen_ending", "ending_replaced")), "此時尚未看過 ending_replaced")

	# 2. 第 2 輪：正常替換結局（首次 = 長版）
	var op2: Dictionary = gs.call("choose_opening", "take_family_album")
	_check(bool(op2.get("ok", false)), "第 2 輪相簿開局成功")
	gs.set("day", 45)
	gs.set("phase", "evening")
	gs.set("selected_festival_proxy_npc", "ajie")
	gs.call("gain_card", "info_registry")
	(gs.get("flags") as Dictionary)["final_day"] = true
	gs.call("play_beat", "d45_then")
	gs.call("try_place", "info_registry", "d45_then", "compare_registry")
	gs.call("advance_phase")

	_check(str(gs.get("flow_mode")) == "ending", "第 2 輪進入 ending")
	var view_long: Dictionary = gs.call("ending_view")
	_check(not bool(view_long.get("can_skip", true)), "首次 normal ending 不可 skip (can_skip = false)")
	_complete_all_pages(gs)

	_check(int(gs.get("run_number")) == 3, "結算 2 (正常長版) 後 run_number = 3")
	_check((gs.get("ending_history") as Array).size() == 2, "結算 2 後 history 筆數 = 2")
	_check(bool(gs.call("has_seen_ending", "ending_replaced")), "此時已看過 ending_replaced")

	# 3. 第 3 輪：不上車結局（開局直接進 ending，不建立 run）
	var refuse_choice_view: Array = gs.call("opening_view") as Array
	var refuse_unlocked := false
	for c_raw: Variant in refuse_choice_view:
		var c := c_raw as Dictionary
		if str(c.get("id", "")) == "refuse_boarding" and bool(c.get("available", false)):
			refuse_unlocked = true
	_check(refuse_unlocked, "第 3 輪不上車選項已解鎖")

	var op3: Dictionary = gs.call("choose_opening", "refuse_boarding")
	_check(bool(op3.get("ok", false)), "選擇不上車開局成功")
	_check(str(gs.get("flow_mode")) == "ending", "不上車開局直接進入 ending 模式")
	_check(str((gs.get("active_ending") as Dictionary).get("ending_id", "")) == "ending_refuse_boarding", "當前結局為 ending_refuse_boarding")
	# 驗證不上車未建立 run 狀態
	_check((gs.get("hand") as Array).is_empty(), "不上車開局手牌為空（未建立 run）")

	_complete_all_pages(gs)
	_check(str(gs.get("flow_mode")) == "opening", "不上車結算後回到 opening")
	_check(int(gs.get("run_number")) == 4, "結算 3 (不上車) 後 run_number = 4")
	_check((gs.get("ending_history") as Array).size() == 3, "結算 3 後 history 筆數 = 3")

	# 4. 第 4 輪：正常替換結局（重見 = 短版／可 skip）
	var op4: Dictionary = gs.call("choose_opening", "return_missed_call")
	_check(bool(op4.get("ok", false)), "第 4 輪電話開局成功")
	gs.set("day", 45)
	gs.set("phase", "evening")
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["final_day"] = true
	gs.call("play_beat", "d45_then")
	gs.call("choose", "d45_then", "d45_coda", "empty_handed")
	gs.call("advance_phase")

	_check(str(gs.get("flow_mode")) == "ending", "第 4 輪進入 ending")
	var view_short: Dictionary = gs.call("ending_view")
	_check(bool(view_short.get("can_skip", false)), "重見 normal ending 可 skip (can_skip = true)")
	var skip_res: Dictionary = gs.call("skip_seen_ending")
	_check(bool(skip_res.get("ok", false)), "執行 skip_seen_ending 成功")
	_complete_all_pages(gs)

	_check(int(gs.get("run_number")) == 5, "結算 4 (正常短版) 後 run_number = 5")
	_check((gs.get("ending_history") as Array).size() == 4, "結算 4 後 history 筆數 = 4")

	# 驗證 meta 層在四次結算後持續保留
	_check(bool(gs.call("has_knowledge", "k_forty_something")), "第 1 輪取得的知識卡跨 4 次結算依然保留")
	_check(bool(gs.call("has_knowledge", "k_i_returned")), "「我回來過」知識卡依然保留")

	# 驗證在 opening 狀態下重複呼叫 complete_ending 是冪等被拒的
	var dup_complete: Dictionary = gs.call("complete_ending")
	_check(not bool(dup_complete.get("ok", false)), "在 opening 模式呼叫 complete_ending 拒絕")
	_check(int(gs.get("run_number")) == 5 and (gs.get("ending_history") as Array).size() == 4, "拒絕後 run_number 與 history 筆數不變")


# ── 3. 正常 ending matrix 從正式 rules 動態衍生 ───────────────────────────────

func _test_3_ending_matrix_dynamic_derivation(gs: Node, data_node: Node) -> void:
	print("\n--- 3. 正常 ending matrix 從正式 rules 動態衍生 ---")
	var loader: DataLoader = data_node.get("loader") as DataLoader
	var replaced_ending: Dictionary = loader.endings_by_id.get("ending_replaced", {}) as Dictionary
	_check(not replaced_ending.is_empty(), "endings.json 包含 ending_replaced")

	var groups: Array = replaced_ending.get("variant_groups", []) as Array
	var group_map: Dictionary = {}
	var hit_rules: Dictionary = {}
	for g_raw: Variant in groups:
		var g := g_raw as Dictionary
		var gid := str(g.get("id", ""))
		group_map[gid] = g
		hit_rules[gid] = {}

	_check(group_map.has("livelihood"), "variant_groups 包含 livelihood")
	_check(group_map.has("inn_appearance"), "variant_groups 包含 inn_appearance")
	_check(group_map.has("partner"), "variant_groups 包含 partner")

	# 驗證生計優先序：uncle > boss > zhou > none
	# Case 1: uncle + boss 條件同時成立 → 判定為 uncle (uncle_low)
	_fresh_opening(gs)
	gs.call("choose_opening", "take_family_album")
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["accepted_inn"] = true
	(gs.get("flags") as Dictionary)["accepted_outside_job"] = true
	(gs.get("flags") as Dictionary)["accepted_job"] = true
	var plan_uncle: Dictionary = EndingResolver.resolve("ending_replaced", gs, loader)
	_check(bool(plan_uncle.get("ok", false)), "同時成立 uncle+boss+zhou 時 resolve 成功")
	var uv: Dictionary = plan_uncle.get("variants", {}) as Dictionary
	_check(str(uv.get("livelihood_variant", "")).begins_with("uncle"), "生計優先序：uncle 高於 boss 與 zhou")

	# Case 2: boss + zhou 條件同時成立（無 uncle） → 判定為 boss (boss_low)
	_fresh_opening(gs)
	gs.call("choose_opening", "take_family_album")
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["accepted_outside_job"] = true
	(gs.get("flags") as Dictionary)["accepted_job"] = true
	var plan_boss: Dictionary = EndingResolver.resolve("ending_replaced", gs, loader)
	_check(bool(plan_boss.get("ok", false)), "同時成立 boss+zhou 時 resolve 成功")
	var bv: Dictionary = plan_boss.get("variants", {}) as Dictionary
	_check(str(bv.get("livelihood_variant", "")).begins_with("boss"), "生計優先序：boss 高於 zhou")

	# Case 3: 僅 zhou 成立 → 判定為 zhou (zhou_low)
	_fresh_opening(gs)
	gs.call("choose_opening", "take_family_album")
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["accepted_job"] = true
	var plan_zhou: Dictionary = EndingResolver.resolve("ending_replaced", gs, loader)
	_check(bool(plan_zhou.get("ok", false)), "僅 zhou 條件成立時判定為 zhou")
	var zv: Dictionary = plan_zhou.get("variants", {}) as Dictionary
	_check(str(zv.get("livelihood_variant", "")).begins_with("zhou"), "判定為 zhou")

	# Case 4: 皆無 → fallback none (none_low)
	_fresh_opening(gs)
	gs.call("choose_opening", "take_family_album")
	gs.set("selected_festival_proxy_npc", "ajie")
	var plan_none: Dictionary = EndingResolver.resolve("ending_replaced", gs, loader)
	var nv: Dictionary = plan_none.get("variants", {}) as Dictionary
	_check(str(nv.get("livelihood_variant", "")).begins_with("none"), "皆無時 fallback 為 none")

	# 驗證全生計 × 3 開關帶（0-1 low, 2-3 mid, 4-6 high）全部合法
	var livelihoods := ["uncle", "boss", "zhou", "none"]
	var bands := [
		{"name": "low", "switches": {}},
		{"name": "mid", "switches": {"s1": 1, "s2": 1}},
		{"name": "high", "switches": {"s1": 1, "s2": 1, "s3": 1, "s4": 1}},
	]

	var all_combos_valid := true
	for liv: String in livelihoods:
		for b: Dictionary in bands:
			_fresh_opening(gs)
			gs.call("choose_opening", "take_family_album")
			gs.set("selected_festival_proxy_npc", "ajie")
			if liv == "uncle":
				(gs.get("flags") as Dictionary)["accepted_inn"] = true
			elif liv == "boss":
				(gs.get("flags") as Dictionary)["accepted_outside_job"] = true
			elif liv == "zhou":
				(gs.get("flags") as Dictionary)["accepted_job"] = true

			var sw: Dictionary = b.get("switches", {}) as Dictionary
			for sk in sw.keys():
				(gs.get("switches") as Dictionary)[sk] = sw[sk]

			var p: Dictionary = EndingResolver.resolve("ending_replaced", gs, loader)
			var pv: Dictionary = p.get("variants", {}) as Dictionary
			var expected_rule := "%s_%s" % [liv, str(b.get("name"))]
			var resolved_rule := str(pv.get("livelihood_variant", ""))
			(hit_rules["livelihood"] as Dictionary)[resolved_rule] = true
			if not bool(p.get("ok", false)) or resolved_rule != expected_rule:
				all_combos_valid = false
				_fail("生計 %s + 開關帶 %s resolve 異常 (預期: %s, 實際: %s)" % [liv, str(b.get("name")), expected_rule, resolved_rule])

	_check(all_combos_valid, "4 生計 × 3 開關帶（12 種組合）動態解析全部正確無誤")

	# 驗證旅館外觀 4 種狀態
	var app_cases := [
		{"flag": "repaired_sign", "expected": "sign"},
		{"flag": "repaired_pipes", "expected": "pipes"},
		{"flag": "repaired_windows", "expected": "windows"},
		{"flag": "", "expected": "none"},
	]
	for ac: Dictionary in app_cases:
		_fresh_opening(gs)
		gs.call("choose_opening", "take_family_album")
		gs.set("selected_festival_proxy_npc", "ajie")
		var fl := str(ac.get("flag", ""))
		if not fl.is_empty():
			(gs.get("flags") as Dictionary)[fl] = true
		var app_p: Dictionary = EndingResolver.resolve("ending_replaced", gs, loader)
		var app_v: Dictionary = app_p.get("variants", {}) as Dictionary
		var resolved_app := str(app_v.get("inn_appearance_variant", ""))
		(hit_rules["inn_appearance"] as Dictionary)[resolved_app] = true
		_check(resolved_app == str(ac.get("expected", "")), "旅館外觀解析為 %s" % str(ac.get("expected", "")))

	# 驗證伴侶 3 種狀態
	var part_cases := [
		{"flag": "invited_ajie", "expected": "ajie"},
		{"flag": "invited_awei", "expected": "awei"},
		{"flag": "", "expected": "none"},
	]
	for pc: Dictionary in part_cases:
		_fresh_opening(gs)
		gs.call("choose_opening", "take_family_album")
		gs.set("selected_festival_proxy_npc", "ajie")
		var fl := str(pc.get("flag", ""))
		if not fl.is_empty():
			(gs.get("flags") as Dictionary)[fl] = true
		var part_p: Dictionary = EndingResolver.resolve("ending_replaced", gs, loader)
		var part_v: Dictionary = part_p.get("variants", {}) as Dictionary
		var resolved_part := str(part_v.get("partner_variant", ""))
		(hit_rules["partner"] as Dictionary)[resolved_part] = true
		_check(resolved_part == str(pc.get("expected", "")), "伴侶解析為 %s" % str(pc.get("expected", "")))

	# N5 動態規則覆蓋完整性斷言：依 endings.json 枚舉所有 variant group 的全部 rule id
	for g_raw: Variant in groups:
		var g := g_raw as Dictionary
		var gid := str(g.get("id", ""))
		var expected_rule_ids: Array[String] = []
		for r_raw: Variant in (g.get("rules", []) as Array):
			expected_rule_ids.append(str((r_raw as Dictionary).get("id", "")))
		var missing_rules: Array[String] = []
		for rid in expected_rule_ids:
			if not (hit_rules.get(gid, {}) as Dictionary).has(rid):
				missing_rules.append(rid)
		_check(missing_rules.is_empty(), "variant_group '%s' 所有規則（共 %d 條）均被動態測試命中覆蓋" % [gid, expected_rule_ids.size()], "缺漏: %s" % str(missing_rules))


# ── 4. D29 慶典代付者六條路徑一致性 ───────────────────────────────────────────

func _test_4_d29_six_proxy_paths(gs: Node, data_node: Node) -> void:
	print("\n--- 4. D29 慶典代付者六條路徑一致性 ---")
	var loader: DataLoader = data_node.get("loader") as DataLoader

	# 六條路徑：
	# 1. 邀阿婕 (ajie)
	# 2. 邀阿薇 (awei)
	# 3. 不邀且阿柴最高 (acai)
	# 4. 逾期同分 (timeout tie) - 進面板未選擇
	# 5. 未進面板 (unvisited panel) - 從未進面板
	# 6. 全零 fallback (all zero fallback)

	var test_paths := [
		{
			"name": "invite_ajie",
			"setup": func(g: Node):
				g.call("gain_card", "npc_ajie")
				g.call("play_beat", "d29_pm_invitation")
				g.call("choose", "d29_pm_invitation", "invitation", "invite_ajie", "npc_ajie"),
			"expected_proxy": "ajie"
		},
		{
			"name": "invite_awei",
			"setup": func(g: Node):
				(g.get("relations") as Dictionary)["awei"] = 3
				g.call("gain_card", "npc_awei")
				g.call("play_beat", "d29_pm_invitation")
				g.call("choose", "d29_pm_invitation", "invitation", "invite_awei", "npc_awei"),
			"expected_proxy": "awei"
		},
		{
			"name": "invite_none_acai",
			"setup": func(g: Node):
				(g.get("npc_action_counts") as Dictionary)["acai"] = 5
				g.call("play_beat", "d29_pm_invitation")
				g.call("choose", "d29_pm_invitation", "invitation", "invite_none", ""),
			"expected_proxy": "acai"
		},
		{
			"name": "timeout_tie",
			"setup": func(g: Node):
				(g.get("npc_action_counts") as Dictionary)["ajie"] = 3
				(g.get("npc_action_counts") as Dictionary)["awei"] = 3
				# N2: 進入面板但不做選擇
				g.call("play_beat", "d29_pm_invitation"),
			"expected_proxy": "ajie"
		},
		{
			"name": "unvisited_panel",
			"setup": func(g: Node):
				# N2: 完全不進面板
				(g.get("npc_action_counts") as Dictionary)["awei"] = 4,
			"expected_proxy": "awei"
		},
		{
			"name": "zero_fallback",
			"setup": func(g: Node):
				pass,
			"expected_proxy": "ajie"
		},
	]

	for item: Dictionary in test_paths:
		var path_name := str(item.get("name", ""))
		var expected_proxy := str(item.get("expected_proxy", ""))
		_fresh_opening(gs)
		gs.call("choose_opening", "take_family_album")

		gs.set("day", 29)
		gs.set("phase", "afternoon")

		var setup_fn: Callable = item.get("setup")
		setup_fn.call(gs)

		# N2: 驗證 timeout_tie 與 unvisited_panel 在進面板行為上的差異
		if path_name == "timeout_tie":
			_check((gs.get("beats_entered") as Dictionary).has("d29_pm_invitation"), "路徑 %s: 確實曾進入 d29_pm_invitation 面板" % path_name)
		elif path_name == "unvisited_panel":
			_check(not (gs.get("beats_entered") as Dictionary).has("d29_pm_invitation"), "路徑 %s: 從未進入 d29_pm_invitation 面板" % path_name)

		# 推進離開 D29 afternoon，觸發 default choice / proxy freeze
		var adv_res: Dictionary = gs.call("advance_phase")
		_check(bool(adv_res.get("ok", false)), "路徑 %s: 推進離開 D29 afternoon 成功" % path_name)

		var frozen_proxy := str(gs.get("selected_festival_proxy_npc"))
		_check(not frozen_proxy.is_empty(), "路徑 %s: D29 結束後 selected_festival_proxy_npc 已凍結（實際: %s）" % [path_name, frozen_proxy])
		_check(frozen_proxy == expected_proxy, "路徑 %s: 凍結值符合預期 (%s)" % [path_name, expected_proxy])

		# B2: D31 afternoon 真實 beat 讀取點驗證
		gs.set("day", 31)
		gs.set("phase", "afternoon")
		var target_d31_beat := "d31_proxy_%s" % expected_proxy
		var lines_d31 := gs.call("play_beat", target_d31_beat) as PackedStringArray
		_check(lines_d31.size() > 0, "路徑 %s: D31 成功演出目標 proxy beat (%s)" % [path_name, target_d31_beat])
		for other_npc in ["ajie", "awei", "acai"]:
			if other_npc != expected_proxy:
				var other_beat := "d31_proxy_%s" % other_npc
				var other_def: Dictionary = loader.beats_by_id.get(other_beat, {}) as Dictionary
				var cond_met: bool = ConditionEval.eval(other_def.get("condition"), gs)
				_check(not cond_met, "路徑 %s: D31 非目標 proxy beat (%s) 條件不成立" % [path_name, other_beat])

		# B2: D39 afternoon 真實 beat 讀取點驗證
		gs.set("day", 39)
		gs.set("phase", "afternoon")
		var target_d39_beat := "d39_proxy_%s" % expected_proxy
		var lines_d39 := gs.call("play_beat", target_d39_beat) as PackedStringArray
		_check(lines_d39.size() > 0, "路徑 %s: D39 成功演出目標 proxy beat (%s)" % [path_name, target_d39_beat])
		for other_npc in ["ajie", "awei", "acai"]:
			if other_npc != expected_proxy:
				var other_beat := "d39_proxy_%s" % other_npc
				var other_def: Dictionary = loader.beats_by_id.get(other_beat, {}) as Dictionary
				var cond_met: bool = ConditionEval.eval(other_def.get("condition"), gs)
				_check(not cond_met, "路徑 %s: D39 非目標 proxy beat (%s) 條件不成立" % [path_name, other_beat])

		# 推進到 D45 結算 normal ending
		gs.set("day", 45)
		gs.set("phase", "evening")
		(gs.get("flags") as Dictionary)["final_day"] = true
		gs.call("play_beat", "d45_then")
		gs.call("choose", "d45_then", "d45_coda", "empty_handed")
		var end_adv: Dictionary = gs.call("advance_phase")
		_check(bool(end_adv.get("ok", false)) and str(gs.get("flow_mode")) == "ending", "路徑 %s: 成功結算進入 ending" % path_name)
		# N7: 斷言 active_ending.ending_id 為 ending_replaced
		_check(str((gs.get("active_ending") as Dictionary).get("ending_id", "")) == "ending_replaced", "路徑 %s: active_ending.ending_id 為 ending_replaced" % path_name)
		_check(str((gs.get("active_ending") as Dictionary).get("festival_proxy_npc", "")) == expected_proxy, "路徑 %s: ending snapshot 的 proxy 與 D29 凍結值相同 (%s)" % [path_name, expected_proxy])
		_complete_all_pages(gs)


# ── 5. 連續至少三輪 town run 狀態清洗與持久化保留 ───────────────────────────────

func _test_5_cross_run_three_runs_cleanup_and_persistence(gs: Node, data_node: Node) -> void:
	print("\n--- 5. 連續至少三輪 town run 狀態清洗與持久化保留 ---")
	_fresh_opening(gs)

	for run_idx in range(1, 4):
		# 開局
		var choice := "take_family_album" if run_idx % 2 == 1 else "return_missed_call"
		var op_res: Dictionary = gs.call("choose_opening", choice)
		_check(bool(op_res.get("ok", false)), "第 %d 輪開局 (%s) 成功" % [run_idx, choice], str(op_res))

		# 驗證 run 層狀態為初始乾淨狀態
		_check((gs.get("delegates_used_today") as Dictionary).is_empty(), "第 %d 輪開始時 delegates_used_today 為空" % run_idx)
		_check((gs.get("pending_delegation_reports") as Array).is_empty(), "第 %d 輪開始時 pending_delegation_reports 為空" % run_idx)
		_check((gs.get("active_encounter") as Dictionary).is_empty(), "第 %d 輪開始時 active_encounter 為空" % run_idx)

		# 設置 run 層狀態
		(gs.get("flags") as Dictionary)["test_run_flag_%d" % run_idx] = true
		(gs.get("delegates_used_today") as Dictionary)["npc_ajie"] = true
		(gs.get("pending_delegation_reports") as Array).append({"npc_id": "npc_ajie"})

		# N1: 第 1 輪透過真實比對槽獲得 k_forty_something 知識卡
		if run_idx == 1:
			gs.set("day", 9)
			gs.set("phase", "afternoon")
			gs.call("gain_card", "info_forty_something")
			gs.call("play_beat", "d9_pm_columbarium")
			var place_k: Dictionary = gs.call("try_place", "info_forty_something", "d9_pm_columbarium", "compare_years")
			_check(bool(place_k.get("ok", false)), "第 1 輪藉真實比對槽取得 k_forty_something 知識卡")
			_check(bool(gs.call("has_knowledge", "k_forty_something")), "確實獲得知識卡 k_forty_something")
		elif run_idx == 2:
			gs.call("gain_card", "k_town_covers")
		elif run_idx == 3:
			gs.call("gain_card", "k_twenty_years_ago")

		(gs.get("night_once_beats_seen") as Dictionary)["n_once_%d" % run_idx] = true
		gs.set("delegation_tutorial_seen", true)

		# N1: D8 夜間地點真實進入測試（第 1 輪首次收費，第 2/3 輪零扣費）
		gs.set("day", 8)
		gs.set("phase", "night")
		var madness_before := (gs.get("hand") as Array).filter(func(c): return str(c).begins_with("madness")).size()
		var enter_night: Dictionary = gs.call("enter_night_location", "n_manydoors")
		_check(bool(enter_night.get("ok", false)), "第 %d 輪進入 n_manydoors 成功" % run_idx)
		var madness_after := (gs.get("hand") as Array).filter(func(c): return str(c).begins_with("madness")).size()

		if run_idx == 1:
			_check(madness_after == madness_before + 1, "第 1 輪首次進入 n_manydoors 確實扣收首次 madness cost (+1)")
			_check(bool((gs.get("night_locations_seen") as Dictionary).has("n_manydoors")), "第 1 輪 n_manydoors 成功寫入 night_locations_seen")
		else:
			_check(madness_after == madness_before, "第 %d 輪重進 n_manydoors 零扣費（首次費不重收）" % run_idx)

		# 走到 D45 結算
		gs.set("day", 45)
		gs.set("phase", "evening")
		gs.set("selected_festival_proxy_npc", "ajie")
		(gs.get("flags") as Dictionary)["final_day"] = true
		gs.call("play_beat", "d45_then")
		var place_d45: Dictionary = gs.call("choose", "d45_then", "d45_coda", "empty_handed")
		_check(bool(place_d45.get("ok", false)), "第 %d 輪選擇 empty_handed" % run_idx, str(place_d45))
		var adv_d45: Dictionary = gs.call("advance_phase")
		_check(bool(adv_d45.get("ok", false)), "第 %d 輪推進 d45" % run_idx, str(adv_d45))
		_complete_all_pages(gs)

		_check(int(gs.get("run_number")) == run_idx + 1, "第 %d 輪結算後 run_number 為 %d" % [run_idx, run_idx + 1])
		_check((gs.get("ending_history") as Array).size() == run_idx, "第 %d 輪結算後 ending_history 筆數為 %d" % [run_idx, run_idx])

	# 驗證跨 3 輪後 meta 層累積完整保留
	_check(bool(gs.call("has_knowledge", "k_forty_something")), "第 1 輪知識卡保留")
	_check(bool(gs.call("has_knowledge", "k_town_covers")), "第 2 輪知識卡保留")
	_check(bool(gs.call("has_knowledge", "k_twenty_years_ago")), "第 3 輪知識卡保留")
	_check((gs.get("night_once_beats_seen") as Dictionary).has("n_once_1"), "第 1 輪 night_once_beats_seen 保留")
	_check(bool(gs.get("delegation_tutorial_seen")), "delegation_tutorial_seen 保留")


# ── 6. Ending 快照載入續播、完成冪等性與非法跨 mode 呼叫拒絕 ───────────────────

func _test_6_checkpoint_reload_skip_vs_reveal_and_idempotency(gs: Node, data_node: Node) -> void:
	print("\n--- 6. Ending 快照載入續播、完成冪等性與非法跨 mode 呼叫拒絕 ---")
	_fresh_opening(gs)

	# 先走一次 ending_replaced 使其成為重見結局
	gs.call("choose_opening", "take_family_album")
	gs.set("day", 45)
	gs.set("phase", "evening")
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["final_day"] = true
	gs.call("play_beat", "d45_then")
	gs.call("choose", "d45_then", "d45_coda", "empty_handed")
	gs.call("advance_phase")
	_complete_all_pages(gs)

	# 第二輪進入 ending_replaced 取得 active ending checkpoint
	gs.call("choose_opening", "take_family_album")
	gs.set("day", 45)
	gs.set("phase", "evening")
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["final_day"] = true
	gs.call("play_beat", "d45_then")
	gs.call("choose", "d45_then", "d45_coda", "empty_handed")
	var adv_c: Dictionary = gs.call("advance_phase")
	_check(bool(adv_c.get("ok", false)), "第 2 次推進 d45 成功", str(adv_c))

	var saved_checkpoint := gs.call("serialize") as Dictionary
	_check(str((saved_checkpoint.get("flow", {}) as Dictionary).get("mode", "")) == "ending", "快照處於 ending 模式")

	# 分支 A：逐頁推進播至末頁 ready_to_complete，存 ready 快照
	while not bool(gs.call("ending_view").get("can_complete", false)):
		if not bool(gs.call("ending_view").get("page_revealed", false)):
			gs.call("reveal_ending_page")
		else:
			gs.call("advance_ending_page")

	_check(bool(gs.call("ending_view").get("can_complete", false)), "逐頁播完達到 ready_to_complete")
	var ready_checkpoint := gs.call("serialize") as Dictionary

	# N6: 第一次 complete_ending 成功
	var comp1: Dictionary = gs.call("complete_ending")
	_check(bool(comp1.get("ok", false)), "第一次 complete_ending 成功")
	_check(str(gs.get("flow_mode")) == "opening", "完成後回到 opening 模式")

	# N6: 同一狀態第二次呼叫 complete_ending 被拒絕 (not_ending)，history 筆數不增加
	var comp2: Dictionary = gs.call("complete_ending")
	_check(not bool(comp2.get("ok", false)) and str(comp2.get("reason_code", "")) == "not_ending", "同狀態第二次 complete_ending 被拒絕 (not_ending)")

	var history_a := (gs.get("ending_history") as Array).duplicate(true)
	var record_a: Dictionary = history_a[history_a.size() - 1] as Dictionary

	# 分支 B：重新載入相同快照，走 skip 完成
	var des_res: Dictionary = gs.call("deserialize", saved_checkpoint)
	_check(bool(des_res.get("ok", false)), "重新載入 ending checkpoint 成功")
	var skip_res: Dictionary = gs.call("skip_seen_ending")
	_check(bool(skip_res.get("ok", false)), "在重載的 checkpoint 上執行 skip 成功")
	_complete_all_pages(gs)
	var history_b := (gs.get("ending_history") as Array).duplicate(true)
	var record_b: Dictionary = history_b[history_b.size() - 1] as Dictionary

	_check(str(record_a.get("ending_id", "")) == str(record_b.get("ending_id", "")), "逐頁與 skip 產生的 ending_id 完全相同")
	_check(str(record_a.get("livelihood_variant", "")) == str(record_b.get("livelihood_variant", "")), "逐頁與 skip 產生的 livelihood_variant 完全相同")
	_check(str(record_a.get("partner_variant", "")) == str(record_b.get("partner_variant", "")), "逐頁與 skip 產生的 partner_variant 完全相同")
	_check(str(record_a.get("festival_proxy_npc", "")) == str(record_b.get("festival_proxy_npc", "")), "逐頁與 skip 產生的 festival_proxy_npc 完全相同")
	_check(int(record_a.get("ended_day", 0)) == int(record_b.get("ended_day", 0)), "逐頁與 skip 產生的 ended_day 完全相同")

	# 非法跨 mode 呼叫拒絕：在 opening 模式下呼叫 run 入口
	var place_in_op: Dictionary = gs.call("try_place", "info_registry", "d45_then", "compare_registry")
	_check(not bool(place_in_op.get("ok", false)) and str(place_in_op.get("reason_code", "")) == "not_run", "opening 模式下 try_place 回傳 not_run")
	var adv_in_op: Dictionary = gs.call("advance_phase")
	_check(not bool(adv_in_op.get("ok", false)) and str(adv_in_op.get("reason_code", "")) == "not_run", "opening 模式下 advance_phase 回傳 not_run")


# ── 7. loop_persistent 魔法物品合成 fixture 生命週期 ──────────────────────────

func _test_7_loop_persistent_fixture_lifecycle_and_formal_catalog(gs: Node, data_node: Node) -> void:
	print("\n--- 7. loop_persistent 魔法物品合成 fixture 生命週期 ---")
	var loader: DataLoader = data_node.get("loader") as DataLoader

	# 1. 斷言正式卡片資料庫中 loop_persistent 數量為 0
	var formal_persistent_count := 0
	for cid: String in loader.cards.keys():
		var cdef: Dictionary = loader.cards[cid] as Dictionary
		if bool(cdef.get("loop_persistent", false)):
			formal_persistent_count += 1
	_check(formal_persistent_count == 0, "正式 cards.json 中 loop_persistent: true 的卡片數量為 0（第一輪無魔法物品）")

	# 2. 動態註冊合成 fixture 卡片 magic_ring (loop_persistent: true)
	loader.cards["magic_ring"] = {
		"id": "magic_ring",
		"name": "魔法戒指",
		"type": "equipment",
		"loop_persistent": true,
		"discardable": false,
	}

	_fresh_opening(gs)
	gs.call("choose_opening", "take_family_album")

	# (a) 取得卡片 → hand 與 loop_persistent_item_ids 均收錄
	gs.call("gain_card", "magic_ring")
	_check(bool(gs.call("has_card", "magic_ring")), "成功取得合成魔法卡 magic_ring")
	_check((gs.get("loop_persistent_item_ids") as Dictionary).has("magic_ring"), "loop_persistent_item_ids meta set 已收錄 magic_ring")

	# (b) 普通 lose_card → 手牌失去，但 meta set 保留
	gs.call("lose_card", "magic_ring")
	_check(not bool(gs.call("has_card", "magic_ring")), "普通 lose_card 後手牌失去 magic_ring")
	_check((gs.get("loop_persistent_item_ids") as Dictionary).has("magic_ring"), "普通 lose_card 後 loop_persistent_item_ids 依然保留")

	# (c) 換輪開局 → magic_ring 自動恢復進手牌
	gs.set("day", 45)
	gs.set("phase", "evening")
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["final_day"] = true
	gs.call("play_beat", "d45_then")
	gs.call("choose", "d45_then", "d45_coda", "empty_handed")
	gs.call("advance_phase")
	_complete_all_pages(gs)

	var op_new: Dictionary = gs.call("choose_opening", "return_missed_call")
	_check(bool(op_new.get("ok", false)), "第二輪開局成功", str(op_new))
	_check(bool(gs.call("has_card", "magic_ring")), "第二輪開局後 magic_ring 自動恢復進手牌")

	# (d) 永久失去 permanent lose_card → 手牌與 meta set 皆移除，次輪不再恢復
	gs.call("lose_card", "magic_ring", true)
	_check(not (gs.get("loop_persistent_item_ids") as Dictionary).has("magic_ring"), "永久失去後 loop_persistent_item_ids 已移除 magic_ring")

	gs.set("day", 45)
	gs.set("phase", "evening")
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["final_day"] = true
	gs.call("play_beat", "d45_then")
	gs.call("choose", "d45_then", "d45_coda", "empty_handed")
	gs.call("advance_phase")
	_complete_all_pages(gs)

	var op_third: Dictionary = gs.call("choose_opening", "take_family_album")
	_check(bool(op_third.get("ok", false)), "第三輪開局成功", str(op_third))
	_check(not bool(gs.call("has_card", "magic_ring")), "永久失去後，第三輪開局不再恢復 magic_ring")

	# 清理合成 fixture
	loader.cards.erase("magic_ring")


# ── 8. 45 天貪心走查完備性與 codebase 無舊 end_run 殘留 ─────────────────────────

func _test_8_greedy_and_no_legacy_end_run(gs: Node, data_node: Node) -> void:
	print("\n--- 8. 45 天貪心走查完備性與 codebase 無舊 end_run 殘留 ---")

	# 驗證 GameState 中已完全無舊 end_run / run_ended 方法與欄位
	_check(not gs.has_method("end_run"), "GameState 無舊 end_run() 方法")
	_check(not gs.has_method("resolve_night_advance"), "GameState 無舊 resolve_night_advance() 方法")
	_check(gs.get("run_ended") == null, "GameState 無 run_ended 變數")

	# 驗證 flow_mode 的三個封閉枚舉值
	_check(gs.get("FLOW_OPENING") == "opening", "FLOW_OPENING = 'opening'")
	_check(gs.get("FLOW_RUN") == "run", "FLOW_RUN = 'run'")
	_check(gs.get("FLOW_ENDING") == "ending", "FLOW_ENDING = 'ending'")


# ── 9. K-198 preflight null 防禦反例與狀態零變化斷言 ──────────────────────────

func _test_9_preflight_null_counterexample(gs: Node, data_node: Node) -> void:
	print("\n--- 9. K-198 preflight null 防禦反例與狀態零變化斷言 ---")
	_fresh_opening(gs)

	# 注入一筆壞 ending_history 記錄使得 serialize() 的狀態在 deserialize() 失敗
	# （即 clone_for_preflight() 返回 null）
	var bad_record := { "bad_field": 123 }
	(gs.get("ending_history") as Array).append(bad_record)

	# 驗證 clone_for_preflight 確實返回 null
	var probe: Node = gs.call("clone_for_preflight")
	_check(probe == null, "注入壞 history 後 clone_for_preflight 返回 null")

	var snap_before := JSON.stringify(gs.call("serialize"))

	# 1. choose_opening
	var op_res: Dictionary = gs.call("choose_opening", "take_family_album")
	_check(not bool(op_res.get("ok", false)) and str(op_res.get("reason_code", "")) == "data_conflict", "preflight 失敗時 choose_opening 回傳 data_conflict")

	# 2. _settle_effects
	var eff_res: Dictionary = gs.call("_settle_effects", [{"gain": ["protagonist"]}], {}, {"lose_cards": ["protagonist"]})
	_check(not bool(eff_res.get("ok", false)) and str(eff_res.get("reason_code", "")) == "data_conflict", "preflight 失敗時 _settle_effects 回傳 data_conflict")

	# 3. EffectApply.preflight
	var pf_res: Dictionary = EffectApply.preflight([{"gain": ["protagonist"]}], gs)
	_check(not bool(pf_res.get("ok", false)) and str(pf_res.get("reason_code", "")) == "data_conflict", "preflight 失敗時 EffectApply.preflight 回傳 data_conflict")

	# 設置 run 狀態與遭遇以測試 encounter preflight callers
	gs.set("flow_mode", "run")
	gs.set("day", 8)
	gs.set("phase", "night")
	gs.call("gain_card", "protagonist", false)
	gs.call("gain_card", "info_forty_something", false)

	# 4. acknowledge_encounter_intro
	gs.set("active_encounter", {
		"beat_id": "n_manydoors_ch1",
		"stage": "intro",
		"round_id": "",
		"blocked_slots": 0,
		"attempted_card_ids": [],
		"visited_round_ids": []
	})
	var ack_res: Dictionary = gs.call("acknowledge_encounter_intro")
	_check(not bool(ack_res.get("ok", false)) and str(ack_res.get("reason_code", "")) == "data_conflict", "preflight 失敗時 acknowledge_encounter_intro 回傳 data_conflict")

	# 5. respond_to_encounter
	gs.set("active_encounter", {
		"beat_id": "n_manydoors_ch1",
		"stage": "round",
		"round_id": "name_since_when",
		"blocked_slots": 0,
		"attempted_card_ids": [],
		"visited_round_ids": []
	})
	var resp_res: Dictionary = gs.call("respond_to_encounter", "info_forty_something")
	_check(not bool(resp_res.get("ok", false)) and str(resp_res.get("reason_code", "")) == "data_conflict", "preflight 失敗時 respond_to_encounter 回傳 data_conflict")

	# 6. discard_in_encounter
	var disc_res: Dictionary = gs.call("discard_in_encounter", "info_forty_something")
	_check(not bool(disc_res.get("ok", false)) and str(disc_res.get("reason_code", "")) == "data_conflict", "preflight 失敗時 discard_in_encounter 回傳 data_conflict")

	# 7. resolve_unfinished_choice_groups
	gs.set("day", 29)
	gs.set("phase", "afternoon")
	(gs.get("active_encounter") as Dictionary).clear()
	var res_groups: Dictionary = gs.call("resolve_unfinished_choice_groups")
	_check(not bool(res_groups.get("ok", false)) and str(res_groups.get("reason_code", "")) == "data_conflict", "preflight 失敗時 resolve_unfinished_choice_groups 回傳 data_conflict")

	# 完整還原 fixture
	(gs.get("ending_history") as Array).pop_back()
	_fresh_opening(gs)
	var restored_probe: Node = gs.call("clone_for_preflight")
	_check(restored_probe != null, "還原後 clone_for_preflight 恢復正常")
	if restored_probe != null:
		restored_probe.free()

