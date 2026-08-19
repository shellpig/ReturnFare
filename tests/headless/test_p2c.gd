extends SceneTree

## P2-C headless 驗收測試：強制縱慾（倒數歸零自動執行、出口挑選演算法、同日多張與順延、強度曲線與共享計數、決定論、序列化往返）。
## 跑法：
##   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/test_p2c.gd
## 全綠 exit 0；任一失敗 exit 1。

const DataFacts := preload("res://scripts/core/data_facts.gd")
const Indulgence := preload("res://scripts/core/indulgence.gd")
const PanelBuilder := preload("res://scripts/core/panel_builder.gd")


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
		push_error("P2-C: Data failed to load; abort")
		quit(1)
		return

	var failed := 0
	failed += _test_single_card_forced_lifecycle(gs, data_node)
	failed += _test_first_time_is_light_with_warning_text(gs, data_node)
	failed += _test_same_day_two_cards_zero(gs, data_node)
	failed += _test_same_day_three_cards_zero_postponed(gs, data_node)
	failed += _test_pick_exit_algorithms(gs, data_node)
	failed += _test_soak_never_picked(gs, data_node)
	failed += _test_location_agnostic(gs, data_node)
	failed += _test_shared_indulgence_count(gs, data_node)
	failed += _test_determinism(gs, data_node)
	failed += _test_serialize_and_end_run_p2c(gs)

	Engine.unregister_singleton("Data")
	Engine.unregister_singleton("GameState")

	if failed > 0:
		push_error("P2-C: %d test(s) failed" % failed)
		quit(1)
	else:
		print("P2-C: all tests passed")
		quit(0)


func _ok(msg: String) -> int:
	print("  ok  " + msg)
	return 0


func _fail(msg: String) -> int:
	push_error("  FAIL  " + msg)
	return 1


# ── 1. 單張歸零生命週期（第 6 夜開標記 -> 第 13 天 morning 自動強制縱慾）─────────

func _test_single_card_forced_lifecycle(gs: Node, _data: Node) -> int:
	print("--- 1. single card forced indulgence lifecycle (D6 night -> D13 morning) ---")
	var failed := 0
	gs.call("end_run")

	gs.set("day", 6)
	gs.set("phase", "night")
	gs.call("open_night_marker", "n_ahong_1")

	var card_inst := "madness#1"
	if not gs.call("has_card", card_inst):
		return failed + _fail("D6 夜間開標記未能獲得 madness#1")

	# 推進 D7 ~ D12 (共 6 天)
	for d in range(7, 13):
		gs.call("advance_phase") # morning
		gs.call("advance_phase") # afternoon
		gs.call("advance_phase") # evening
		gs.call("advance_phase") # night

	# 推進至第 13 天 morning：此時 tick_madness 歸零，advance_phase 自動執行強制縱慾
	gs.call("advance_phase")

	var cur_day: int = gs.get("day")
	var cur_phase: String = gs.get("phase")
	var action_spent: bool = gs.get("action_spent")
	var has_card: bool = gs.call("has_card", card_inst)
	var in_clock: bool = (gs.get("madness_clock") as Dictionary).has(card_inst)
	var ind_count: int = gs.get("indulgence_count")
	var forced_lines: PackedStringArray = gs.get("last_forced_lines")

	if cur_day == 13 and cur_phase == "morning":
		failed += _ok("推進至第 13 天 morning")
	else:
		failed += _fail("時間不符 (day=%d, phase=%s)" % [cur_day, cur_phase])

	if action_spent:
		failed += _ok("第 13 天上午行動格已被強制縱慾吃掉 (action_spent = true)")
	else:
		failed += _fail("第 13 天上午行動格未被消耗")

	if not has_card and not in_clock:
		failed += _ok("歸零的發狂卡 madness#1 已被消除 (離開 hand 與 madness_clock)")
	else:
		failed += _fail("發狂卡未被消除 (has_card=%s, in_clock=%s)" % [has_card, in_clock])

	if ind_count == 1:
		failed += _ok("本輪縱慾計數正確累計為 1")
	else:
		failed += _fail("縱慾計數不符預期: %d" % ind_count)

	if forced_lines.size() > 0:
		failed += _ok("強制縱慾產生演出文字行 (%d 行)" % forced_lines.size())
	else:
		failed += _fail("強制縱慾未產生演出文字行")

	# 驗證玩家在該時段無法再放主角卡
	var try_res: Dictionary = gs.call("try_place", "protagonist", "d13_morning_rules", "listen")
	if not try_res.get("ok", false) and str(try_res.get("reason_code", "")) == "action_spent":
		failed += _ok("行動格已耗盡，玩家在該時段無法再放主角卡 (reason_code = action_spent)")
	else:
		failed += _fail("玩家在強制縱慾吃格後仍能放卡或理由不符: %s" % str(try_res))

	return failed


# ── 2. 第一次縱慾為輕度且附預告文字 ──────────────────────────────────────────

func _test_first_time_is_light_with_warning_text(gs: Node, data: Node) -> int:
	print("--- 2. first time indulgence is light with warning text ---")
	var failed := 0
	gs.call("end_run")

	var lvl1: String = Indulgence.level_for(1, data.get("loader").tuning)
	if lvl1 == "light":
		failed += _ok("Indulgence.level_for(1) 查表為 'light'")
	else:
		failed += _fail("Indulgence.level_for(1) 查表不為 'light' (實際: %s)" % lvl1)

	# 構造一張歸零卡觸發第 1 次強制縱慾
	gs.set("day", 1)
	gs.set("phase", "night")
	gs.call("gain_card", "madness") # madness#1
	(gs.get("madness_clock") as Dictionary)["madness#1"] = 1

	gs.call("advance_phase") # -> D2 morning

	var lines: PackedStringArray = gs.get("last_forced_lines")
	var has_light_warning := false
	for l in lines:
		if l.contains("開始") or l.contains("沒這麼容易") or l.contains("輕微"):
			has_light_warning = true
			break

	if has_light_warning:
		failed += _ok("第 1 次強制縱慾播出輕度預告文字 (例如「只是開始」/「沒這麼容易」)")
	else:
		failed += _fail("第 1 次強制縱慾未包含預期之輕度預告文字 (輸出: %s)" % str(lines))

	return failed


# ── 3. 同日兩張歸零：各吃一格（上午、下午各一次）─────────────────────────────

func _test_same_day_two_cards_zero(gs: Node, _data: Node) -> int:
	print("--- 3. two cards zeroing on the same day eat morning & afternoon ---")
	var failed := 0
	gs.call("end_run")

	# 模擬第 10 夜持有兩張剩餘 1 天的發狂卡
	gs.set("day", 10)
	gs.set("phase", "night")
	gs.call("gain_card", "madness") # madness#1
	gs.call("gain_card", "madness") # madness#2
	(gs.get("madness_clock") as Dictionary)["madness#1"] = 1
	(gs.get("madness_clock") as Dictionary)["madness#2"] = 1

	# 推進至第 11 天 morning：兩張同時歸零
	gs.call("advance_phase")

	var d11_m_spent: bool = gs.get("action_spent")
	var pending_m: Array = gs.get("forced_pending")
	var has_c1: bool = gs.call("has_card", "madness#1")
	var has_c2: bool = gs.call("has_card", "madness#2")
	var ind_count_m: int = gs.get("indulgence_count")

	if d11_m_spent and ind_count_m == 1 and not has_c1 and has_c2 and pending_m.size() == 1:
		failed += _ok("第 11 天 morning: 消耗上午行動格，消掉第 1 張卡，第 2 張卡留於 forced_pending")
	else:
		failed += _fail("第 11 天 morning 狀態不符 (spent=%s, ind=%d, has1=%s, has2=%s, pending=%s)" % [
			d11_m_spent, ind_count_m, has_c1, has_c2, str(pending_m)
		])

	# 推進至第 11 天 afternoon：自動消耗下午行動格並消除第 2 張卡
	gs.call("advance_phase")

	var d11_a_spent: bool = gs.get("action_spent")
	var pending_a: Array = gs.get("forced_pending")
	var has_c2_after: bool = gs.call("has_card", "madness#2")
	var ind_count_a: int = gs.get("indulgence_count")

	if d11_a_spent and ind_count_a == 2 and not has_c2_after and pending_a.is_empty():
		failed += _ok("第 11 天 afternoon: 消耗下午行動格，消掉第 2 張卡，forced_pending 清空")
	else:
		failed += _fail("第 11 天 afternoon 狀態不符 (spent=%s, ind=%d, has2=%s, pending=%s)" % [
			d11_a_spent, ind_count_a, has_c2_after, str(pending_a)
		])

	return failed


# ── 4. 同日三張歸零：吃滿當天兩格，第三張順延至次日上午 ───────────────────────

func _test_same_day_three_cards_zero_postponed(gs: Node, _data: Node) -> int:
	print("--- 4. three cards zeroing: eats two today, third postponed to next morning ---")
	var failed := 0
	gs.call("end_run")

	gs.set("day", 19)
	gs.set("phase", "night")
	gs.call("gain_card", "madness") # madness#1
	gs.call("gain_card", "madness") # madness#2
	gs.call("gain_card", "madness") # madness#3
	(gs.get("madness_clock") as Dictionary)["madness#1"] = 1
	(gs.get("madness_clock") as Dictionary)["madness#2"] = 1
	(gs.get("madness_clock") as Dictionary)["madness#3"] = 1

	# D20 morning
	gs.call("advance_phase")
	var d20_m_spent: bool = gs.get("action_spent")
	var ind_d20_m: int = gs.get("indulgence_count")

	# D20 afternoon
	gs.call("advance_phase")
	var d20_a_spent: bool = gs.get("action_spent")
	var ind_d20_a: int = gs.get("indulgence_count")
	var pending_d20_a: Array = gs.get("forced_pending")

	if d20_m_spent and d20_a_spent and ind_d20_m == 1 and ind_d20_a == 2 and pending_d20_a == ["madness#3"]:
		failed += _ok("第 20 天吃滿 morning 與 afternoon 兩格，madness#3 維持 pending 順延")
	else:
		failed += _fail("第 20 天消耗狀態不符 (m_spent=%s, a_spent=%s, ind_m=%d, ind_a=%d, pending=%s)" % [
			d20_m_spent, d20_a_spent, ind_d20_m, ind_d20_a, str(pending_d20_a)
		])

	# D20 evening
	gs.call("advance_phase")
	# D20 night
	gs.call("advance_phase")
	# D21 morning：順延的 madness#3 自動執行
	gs.call("advance_phase")

	var d21_m_spent: bool = gs.get("action_spent")
	var ind_d21_m: int = gs.get("indulgence_count")
	var has_c3: bool = gs.call("has_card", "madness#3")
	var pending_d21_m: Array = gs.get("forced_pending")

	if d21_m_spent and ind_d21_m == 3 and not has_c3 and pending_d21_m.is_empty():
		failed += _ok("第 21 天 morning: 順延之 madness#3 正確吃掉上午行動格並消除")
	else:
		failed += _fail("第 21 天 morning 順延結算不符 (spent=%s, ind=%d, has3=%s, pending=%s)" % [
			d21_m_spent, ind_d21_m, has_c3, str(pending_d21_m)
		])

	return failed


# ── 5. 出口挑選演算法（權重最大、條件匹配、載入順序決勝）────────────────────

func _test_pick_exit_algorithms(gs: Node, data: Node) -> int:
	print("--- 5. pick_exit algorithm (weights, conditions, tie-breaks) ---")
	var failed := 0
	gs.call("end_run")

	# 1. 第一章（D1-D15，無特殊關係）：食慾 (x_binge, weight 2) > 砸東西 (x_smash, weight 1)
	gs.set("day", 5)
	gs.call("gain_card", "madness")
	var exit_ch1: Dictionary = Indulgence.pick_exit(gs, data)
	if str(exit_ch1.get("slot_id", "")) == "x_binge":
		failed += _ok("第一章（D1-15 無特殊關係）挑中食慾 x_binge (weight 2 > 1)")
	else:
		failed += _fail("第一章挑選出口不符預期: %s" % str(exit_ch1))

	# 2. 第 16 天之後（無特殊關係）：暴力對人 (x_violence, weight 4) > 食慾 (weight 2)
	gs.set("day", 16)
	var exit_ch2: Dictionary = Indulgence.pick_exit(gs, data)
	if str(exit_ch2.get("slot_id", "")) == "x_violence":
		failed += _ok("第 16 天之後（無特殊關係）挑中暴力對人 x_violence (weight 4)")
	else:
		failed += _fail("第 16 天之後挑選出口不符預期: %s" % str(exit_ch2))

	# 3. 與阿婕達「疑似」關係：性慾（阿婕）(x_lust_ajie, weight 5) > 暴力 (weight 4)
	gs.call("add_relation", "ajie", 1) # scale: "疑似" = 1
	var exit_ajie: Dictionary = Indulgence.pick_exit(gs, data)
	if str(exit_ajie.get("slot_id", "")) == "x_lust_ajie":
		failed += _ok("與阿婕達「疑似」關係後挑中性慾（阿婕）x_lust_ajie (weight 5)")
	else:
		failed += _fail("阿婕疑似關係挑選出口不符預期: %s" % str(exit_ajie))

	# 4. 阿婕與阿薇同時達「疑似」關係（均 weight 5）：同分依資料載入順序決勝（x_lust_ajie 先於 x_lust_awei）
	gs.call("add_relation", "awei", 1)
	var exit_both: Dictionary = Indulgence.pick_exit(gs, data)
	if str(exit_both.get("slot_id", "")) == "x_lust_ajie":
		failed += _ok("阿婕與阿薇同為疑似 (同為 weight 5) 時，依資料順序決勝挑中先載入的 x_lust_ajie")
	else:
		failed += _fail("同分決勝不符載入順序: %s" % str(exit_both))

	return failed


# ── 6. auto == false 槽（泡湯等）永不入自動挑選池 ────────────────────────────

func _test_soak_never_picked(gs: Node, data: Node) -> int:
	print("--- 6. auto == false slots (e.g. soak) are never picked by pick_exit ---")
	var failed := 0
	gs.call("end_run")

	gs.set("day", 1)
	gs.call("gain_card", "madness")

	# 1. 注入一個 weight = 999 的 auto == false 槽
	# 若 pick_exit 沒有 auto == false 過濾，它會因為 999 > 2 而錯誤挑中該槽
	var loader: DataLoader = data.get("loader") as DataLoader
	var test_synthetic_beat := {
		"id": "test_synthetic_soak_beat",
		"location": "sanquan",
		"when": { "day_from": 1, "day_to": 45, "phase": ["morning", "afternoon"] },
		"title": "測試非自動槽",
		"text": "測試",
		"slots": [
			{
				"id": "test_heavy_non_auto_slot",
				"accepts": ["madness"],
				"label": "測試非自動高權重槽",
				"indulgence": {
					"auto": false,
					"weight": 999
				},
				"on_place": {}
			}
		]
	}
	(loader.beats as Array).append(test_synthetic_beat)
	loader.beats_by_id["test_synthetic_soak_beat"] = test_synthetic_beat

	var exit_with_high_weight_non_auto: Dictionary = Indulgence.pick_exit(gs, data)

	# 復原 loader
	(loader.beats as Array).erase(test_synthetic_beat)
	loader.beats_by_id.erase("test_synthetic_soak_beat")

	if str(exit_with_high_weight_non_auto.get("slot_id", "")) == "x_binge":
		failed += _ok("即使存在 weight=999 的 auto==false 槽，pick_exit 仍堅定過濾並挑中 x_binge")
	else:
		failed += _fail("auto==false 過濾器失效，挑中了: %s" % str(exit_with_high_weight_non_auto))

	# 2. 真實資料中 x_soak 永遠不被挑中
	var exit_real: Dictionary = Indulgence.pick_exit(gs, data)
	if str(exit_real.get("slot_id", "")) != "x_soak":
		failed += _ok("真實資料庫中 pick_exit 挑選結果不是泡湯 (%s)" % str(exit_real.get("slot_id", "")))
	else:
		failed += _fail("pick_exit 錯誤挑中了泡湯槽 x_soak")

	return failed


# ── 7. 強制縱慾照樣執行（時段與環境無關性）────────────────────────────────────

func _test_location_agnostic(gs: Node, data: Node) -> int:
	print("--- 7. forced indulgence executes end-to-end regardless of context ---")
	var failed := 0
	gs.call("end_run")

	# 1. pick_exit 跨時段（下午）挑選
	gs.set("day", 8)
	gs.set("phase", "afternoon")
	gs.call("gain_card", "madness")

	var exit: Dictionary = Indulgence.pick_exit(gs, data)
	if not exit.is_empty() and str(exit.get("beat_id", "")).begins_with("exit_"):
		failed += _ok("pick_exit 成功跨時段挑選出口，不依賴特定地點與 when 時段")
	else:
		failed += _fail("pick_exit 跨時段挑選失敗: %s" % str(exit))

	# 2. 完整執行 _settle_forced_indulgence()（驗證「照樣執行」真路徑）
	(gs.get("forced_pending") as Array).append("madness#1")
	gs.set("action_spent", false)

	var forced_lines: PackedStringArray = gs.call("_settle_forced_indulgence")
	var action_spent: bool = gs.get("action_spent")
	var has_m1: bool = gs.call("has_card", "madness#1")
	var ind_count: int = gs.get("indulgence_count")
	var m_cleared: int = gs.get("madness_cards_cleared")

	if forced_lines.size() > 0 and action_spent and not has_m1 and ind_count == 1 and m_cleared == 1:
		failed += _ok("_settle_forced_indulgence 成功完整執行（扣格、消卡、累計次數、累計消卡數均正確）")
	else:
		failed += _fail("_settle_forced_indulgence 執行不符 (spent=%s, has=%s, ind=%d, cleared=%d, lines=%d)" % [
			action_spent, has_m1, ind_count, m_cleared, forced_lines.size()
		])

	return failed


# ── 8. 主動縱慾與強制縱慾共享同一個計數與強度曲線 ─────────────────────────────

func _test_shared_indulgence_count(gs: Node, data: Node) -> int:
	print("--- 8. active and forced indulgence share count and escalation curve ---")
	var failed := 0
	gs.call("end_run")

	# 主動縱慾 3 次
	for i in range(3):
		gs.call("gain_card", "madness")
		gs.set("day", i + 1)
		gs.set("phase", "morning")
		gs.set("action_spent", false)
		var m_inst := "madness#" + str(i + 1)
		var ind_res: Dictionary = gs.call("indulge", "exit_sanquan", "x_smash", m_inst)
		if not ind_res.get("ok", false):
			return failed + _fail("主動縱慾第 %d 次失敗: %s" % [i + 1, str(ind_res)])

	var ind_count: int = gs.get("indulgence_count")
	var m_cleared_3: int = gs.get("madness_cards_cleared")
	if ind_count == 3 and m_cleared_3 == 3:
		failed += _ok("主動縱慾 3 次後 indulgence_count 為 3 且 madness_cards_cleared 為 3")
	else:
		failed += _fail("主動縱慾 3 次後計數不符: ind=%d, cleared=%d" % [ind_count, m_cleared_3])

	# 第 4 次為強制縱慾：強度級應為 normal（level_for(4)）
	gs.call("gain_card", "madness")
	(gs.get("madness_clock") as Dictionary)["madness#4"] = 1
	gs.set("day", 10)
	gs.set("phase", "night")

	# 推進至 D11 morning 觸發強制縱慾
	gs.call("advance_phase")

	var ind_count_after: int = gs.get("indulgence_count")
	var m_cleared_4: int = gs.get("madness_cards_cleared")
	var lvl4: String = Indulgence.level_for(4, data.get("loader").tuning)
	var uncle_rel: int = int((gs.get("relations") as Dictionary).get("uncle", 0))

	if ind_count_after == 4 and m_cleared_4 == 4 and lvl4 == "normal":
		failed += _ok("第 4 次（強制縱慾）正確接續為第 4 次縱慾，強度級為 normal，累計消卡數為 4")
	else:
		failed += _fail("強度級或計數接續錯誤 (count=%d, cleared=%d, lvl=%s)" % [ind_count_after, m_cleared_4, lvl4])

	# normal 等級對 uncle 關係產生 -1 代價
	if uncle_rel < 0:
		failed += _ok("強制縱慾正確套用 normal 等級追加代價 (uncle relation = %d)" % uncle_rel)
	else:
		failed += _fail("強制縱慾未套用 normal 等級追加代價 (uncle relation = %d)" % uncle_rel)

	return failed


# ── 9. 決定論（相同狀態重跑結果完全一致）──────────────────────────────────────

func _test_determinism(gs: Node, data: Node) -> int:
	print("--- 9. determinism in exit picking and execution ---")
	var failed := 0
	gs.call("end_run")

	gs.set("day", 20)
	gs.call("gain_card", "madness")
	gs.call("add_relation", "uncle", -1)

	var exit1: Dictionary = Indulgence.pick_exit(gs, data)
	var exit2: Dictionary = Indulgence.pick_exit(gs, data)

	if exit1 == exit2 and not exit1.is_empty():
		failed += _ok("同一狀態連續呼叫 pick_exit 回傳完全相同之出口 (%s::%s)" % [
			str(exit1.get("beat_id")), str(exit1.get("slot_id"))
		])
	else:
		failed += _fail("pick_exit 非決定論或結果為空 (exit1=%s, exit2=%s)" % [str(exit1), str(exit2)])

	return failed


# ── 10. 序列化與 end_run 重置 ────────────────────────────────────────────────

func _test_serialize_and_end_run_p2c(gs: Node) -> int:
	print("--- 10. serialize roundtrip and end_run resets P2-C fields ---")
	var failed := 0
	gs.call("end_run")

	gs.set("day", 15)
	gs.set("phase", "morning")
	gs.set("indulgence_count", 5)
	gs.set("madness_cards_cleared", 5)
	(gs.get("forced_pending") as Array).append("madness#2")
	(gs.get("forced_pending") as Array).append("madness#3")

	var s: Dictionary = gs.call("serialize")
	var run: Dictionary = s.get("run", {})

	if int(run.get("indulgence_count", 0)) == 5 and int(run.get("madness_cards_cleared", 0)) == 5 and (run.get("forced_pending", []) as Array) == ["madness#2", "madness#3"]:
		failed += _ok("serialize 正確收錄 indulgence_count, madness_cards_cleared 與 forced_pending")
	else:
		failed += _fail("serialize 遺失 P2-C 欄位: %s" % str(run))

	# 清空後 deserialize 還原
	gs.call("end_run")
	gs.call("deserialize", s)

	var restored_ind: int = gs.get("indulgence_count")
	var restored_cleared: int = gs.get("madness_cards_cleared")
	var restored_pending: Array = gs.get("forced_pending")

	if restored_ind == 5 and restored_cleared == 5 and restored_pending == ["madness#2", "madness#3"]:
		failed += _ok("deserialize 完整還原 indulgence_count, madness_cards_cleared 與 forced_pending")
	else:
		failed += _fail("deserialize 還原 P2-C 欄位失敗 (ind=%d, cleared=%d, pending=%s)" % [
			restored_ind, restored_cleared, str(restored_pending)
		])

	# end_run 重置
	gs.call("end_run")
	var reset_ind: int = gs.get("indulgence_count")
	var reset_cleared: int = gs.get("madness_cards_cleared")
	var reset_pending: Array = gs.get("forced_pending")
	var reset_lines: PackedStringArray = gs.get("last_forced_lines")

	if reset_ind == 0 and reset_cleared == 0 and reset_pending.is_empty() and reset_lines.is_empty():
		failed += _ok("end_run 成功重置 indulgence_count, madness_cards_cleared, forced_pending 與 last_forced_lines")
	else:
		failed += _fail("end_run 重置 P2-C 欄位失敗 (ind=%d, cleared=%d, pending=%s, lines=%s)" % [
			reset_ind, reset_cleared, str(reset_pending), str(reset_lines)
		])

	return failed
