extends SceneTree

## P1-F 驗收測試：45 天全程走通與迴圈 stub。
## 跑法：
##   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/test_p1f.gd
## 全綠 exit 0；任一失敗 exit 1。

const ConditionEval := preload("res://scripts/core/condition_eval.gd")
const EffectApply := preload("res://scripts/core/effect_apply.gd")
const PanelBuilder := preload("res://scripts/core/panel_builder.gd")
const DataFacts := preload("res://scripts/core/data_facts.gd")
const PlaythroughGreedy := preload("res://tests/headless/playthrough_greedy.gd")


func _initialize() -> void:
	await process_frame

	var data_node := _setup_data()
	var gs := _setup_game_state(data_node)

	var failed := 0
	failed += _test_evening_echo_missed_vs_attended(gs, data_node)
	failed += _test_chapter1_three_echoes(gs, data_node)
	failed += _test_evening_execution_order_d27(gs, data_node)
	failed += _test_night_resolution_and_free_locations(gs, data_node)
	failed += _test_night_sleep_resolution(gs, data_node)
	failed += _test_night_protagonist_placement_no_action_cost(gs, data_node)
	failed += _test_day45_ending_coda_and_loop_reset(gs, data_node)
	failed += _test_run_ended_emitted_exactly_once(gs, data_node)
	failed += _test_second_loop_arrival_gain_idempotent(gs, data_node)
	failed += _test_greedy_playthrough_45_days(gs, data_node)

	if failed > 0:
		push_error("P1-F: %d test(s) failed" % failed)
		quit(1)
	else:
		print("\nP1-F: all tests passed")
		quit(0)


func _ok(msg: String) -> int:
	print("  ok  " + msg)
	return 0


func _fail(msg: String) -> int:
	push_error("  FAIL  " + msg)
	return 1


func _setup_data() -> Node:
	var data_node: Node = get_root().get_node_or_null("Data")
	if data_node == null:
		data_node = load("res://scripts/autoload/data.gd").new()
		data_node.name = "Data"
		get_root().add_child(data_node)
		Engine.register_singleton("Data", data_node)
	return data_node


func _setup_game_state(data_node: Node) -> Node:
	var gs: Node = get_root().get_node_or_null("GameState")
	if gs == null:
		gs = load("res://scripts/autoload/game_state.gd").new()
		gs.name = "GameState"
		gs.set("Data", data_node)
		get_root().add_child(gs)
		Engine.register_singleton("GameState", gs)
	return gs


func _reset_gs(gs: Node) -> void:
	gs.set("day", 1)
	gs.set("phase", "morning")
	gs.set("action_spent", false)
	(gs.get("hand") as Array).clear()
	(gs.get("hand") as Array).append("protagonist")
	(gs.get("knowledge") as Dictionary).clear()
	(gs.get("flags") as Dictionary).clear()
	(gs.get("switches") as Dictionary).clear()
	(gs.get("switch_progress") as Dictionary).clear()
	(gs.get("relations") as Dictionary).clear()
	(gs.get("slots_placed") as Dictionary).clear()
	(gs.get("choices") as Dictionary).clear()
	(gs.get("beats_entered") as Dictionary).clear()
	(gs.get("npc_action_counts") as Dictionary).clear()
	(gs.get("madness_clock") as Dictionary).clear()
	gs.set("_madness_counter", 0)


# ── 1. 錯過的 beat 的 echo 在正確的天播出 ────────────────────────────────────

func _test_evening_echo_missed_vs_attended(gs: Node, _data_node: Node) -> int:
	print("--- 1. evening echo missed vs attended (d3_pm_sanquan -> d5 evening) ---")
	var failed := 0

	# 狀況 A：錯過第 3 天下午阿宏（沒放 help_ahong 槽）
	_reset_gs(gs)
	gs.set("day", 3)
	gs.set("phase", "afternoon")
	# 不放卡，直接推到第 5 天 evening
	gs.set("day", 5)
	gs.set("phase", "evening")
	var echoes_missed: PackedStringArray = gs.play_evening()
	var found_missed := false
	for l in echoes_missed:
		if l.contains("旁邊有人提起第 3 天下午發生過的一件小事"):
			found_missed = true
			break
	if found_missed:
		failed += _ok("錯過第 3 天阿宏：第 5 天 evening 成功播出殘響 (via GameState.play_evening)")
	else:
		failed += _fail("錯過第 3 天阿宏：第 5 天 evening 未播出殘響（演出輸出: %s）" % str(echoes_missed))

	# 狀況 B：到場第 3 天下午阿宏（放置 help_ahong 槽）
	_reset_gs(gs)
	gs.set("day", 3)
	gs.set("phase", "afternoon")
	var place_res: Dictionary = gs.try_place("protagonist", "d3_pm_sanquan", "help_ahong")
	if not place_res.get("ok", false):
		failed += _fail("放置 d3_pm_sanquan::help_ahong 失敗: %s" % str(place_res))
	gs.set("day", 5)
	gs.set("phase", "evening")
	var echoes_attended: PackedStringArray = gs.play_evening()
	var found_attended := false
	for l in echoes_attended:
		if l.contains("旁邊有人提起第 3 天下午發生過的一件小事"):
			found_attended = true
			break
	if not found_attended:
		failed += _ok("到場第 3 天阿宏：第 5 天 evening 不播出該殘響（條件成立未觸發）")
	else:
		failed += _fail("到場第 3 天阿宏：第 5 天 evening 仍錯誤播出了殘響")

	return failed


# ── 2. 第一章三次殘響全數播出 ────────────────────────────────────────────────

func _test_chapter1_three_echoes(gs: Node, _data_node: Node) -> int:
	print("--- 2. chapter 1 three echoes (d5, d8, d13) ---")
	var failed := 0

	# 1. 第 5 天殘響 (d3_pm_sanquan.echo)
	_reset_gs(gs)
	gs.set("day", 5)
	gs.set("phase", "evening")
	var d5_lines: PackedStringArray = gs.play_evening()
	var d5_found := false
	for l in d5_lines:
		if l.contains("第 3 天下午"):
			d5_found = true
			break
	if d5_found:
		failed += _ok("第 5 天殘響播出成功 (via GameState.play_evening)")
	else:
		failed += _fail("第 5 天殘響未播出 (輸出: %s)" % str(d5_lines))

	# 2. 第 8 天 evening 殘響 (d8_echo_bathhouse - fixed beat)
	_reset_gs(gs)
	gs.set("day", 8)
	gs.set("phase", "evening")
	var d8_lines: PackedStringArray = gs.play_evening()
	var d8_found := false
	for l in d8_lines:
		if l.contains("浴場"):
			d8_found = true
			break
	if d8_found:
		failed += _ok("第 8 天 evening 浴場殘響 (fixed beat) 播出成功 (via GameState.play_evening)")
	else:
		failed += _fail("第 8 天 evening 浴場殘響未正確播出 (輸出: %s)" % str(d8_lines))

	# 3. 第 13 天殘響 (d12_pm_awei.echo)
	_reset_gs(gs)
	gs.set("day", 13)
	gs.set("phase", "evening")
	var d13_lines: PackedStringArray = gs.play_evening()
	var d13_found := false
	for l in d13_lines:
		if l.contains("阿薇那天一個人搬到天黑"):
			d13_found = true
			break
	if d13_found:
		failed += _ok("第 13 天殘響 (阿薇搬東西) 播出成功 (via GameState.play_evening)")
	else:
		failed += _fail("第 13 天殘響未播出 (輸出: %s)" % str(d13_lines))

	return failed


# ── 3. 同一天多個 evening fixed beat 依陣列順序結算 ─────────────────────────

func _test_evening_execution_order_d27(gs: Node, data_node: Node) -> int:
	print("--- 3. evening execution order d27 ---")
	var failed := 0
	var loader: DataLoader = data_node.get("loader") as DataLoader

	_reset_gs(gs)
	gs.set("day", 27)
	gs.set("phase", "evening")
	gs.set_flag("awei_sheltering", true)
	gs.set_flag("dodger_chen", true)

	var d27_beats := loader.beats_at(27, "evening")
	var beat_ids: PackedStringArray = []
	for b in d27_beats:
		if b.get("fixed", false):
			beat_ids.append(str(b.get("id", "")))

	if beat_ids.size() < 2:
		return failed + _fail("第 27 天 evening fixed beats 數量少於 2 (實際: %s)" % str(beat_ids))

	var first_idx := beat_ids.find("d27_evening_awei_confirm")
	var second_idx := beat_ids.find("d27_evening_cover_knowledge")

	if first_idx >= 0 and second_idx >= 0 and first_idx < second_idx:
		failed += _ok("第 27 天 evening 陣列順序正確：d27_evening_awei_confirm 先於 d27_evening_cover_knowledge")
	else:
		failed += _fail("第 27 天 evening 陣列順序錯誤: %s" % str(beat_ids))

	# 依序結算：透過 GameState.play_evening() 統一結算
	gs.play_evening()

	if gs.has_knowledge("k_town_covers"):
		failed += _ok("依序結算後 d27_evening_cover_knowledge 成功獲得知識卡 k_town_covers")
	else:
		failed += _fail("依序結算後未獲得 k_town_covers，順序或條件可能有問題")

	return failed


# ── 4. 夜間地圖免費地點可進與三態解析 ────────────────────────────────────────

func _test_night_resolution_and_free_locations(gs: Node, data_node: Node) -> int:
	print("--- 4. night resolution and free locations ---")
	var failed := 0

	_reset_gs(gs)
	gs.set("day", 1)
	gs.set("phase", "night")

	# 第 1 夜走廊自動強制播出（fixed beat）
	var loader: DataLoader = data_node.get("loader") as DataLoader
	var n1_beats := loader.beats_at(1, "night")
	var n1_corridor_found := false
	for b in n1_beats:
		if b.get("id") == "n_corridor_ch1" and b.get("fixed", false):
			var lines: PackedStringArray = gs.play_beat("n_corridor_ch1")
			if lines.size() > 0:
				n1_corridor_found = true
				break
	if n1_corridor_found:
		failed += _ok("第 1 夜走廊 n_corridor_ch1 自動強制播出")
	else:
		failed += _fail("第 1 夜走廊未強制播出")

	# 第 10 夜起免費地點解析與收費地點呈灰
	_reset_gs(gs)
	gs.set("day", 10)
	gs.set("phase", "night")

	var night_locs := PanelBuilder.available_locations(gs, data_node)
	if night_locs.is_empty():
		return failed + _fail("第 10 夜 available_locations 為空")

	# 免費地點（madness_cost == 0）
	var view_free := PanelBuilder.build("n_landmark", gs, data_node)
	var beats_free: Array = view_free.get("beats", []) as Array
	if beats_free.size() >= 1:
		failed += _ok("第 10 夜免費地點 n_landmark view model 包含主內容與附加 beat (共 %d 個 beat)" % beats_free.size())
	else:
		failed += _fail("第 10 夜免費地點 n_landmark view model 為空")

	# 收費地點（madness_cost > 0）在 P3 已真值化，回傳真實 beat（如 n_ahong_1_ch1）
	var view_paid := PanelBuilder.build("n_ahong_1", gs, data_node)
	var beats_paid: Array = view_paid.get("beats", []) as Array
	if beats_paid.size() == 1 and int(beats_paid[0].get("tri")) == PanelBuilder.TriState.OPEN:
		var bid: String = str(beats_paid[0].get("beat", {}).get("id", ""))
		if bid == "n_ahong_1_ch1":
			failed += _ok("第 10 夜收費地點 n_ahong_1 解析出真實 beat (n_ahong_1_ch1, OPEN)")
		else:
			failed += _fail("收費地點 beat id 不符: %s" % bid)
	else:
		failed += _fail("收費地點狀態未正確解析出 OPEN beat (beats: %s)" % str(beats_paid))

	return failed


# ── 5. 直接睡＝解析旅館當夜定日 beat ─────────────────────────────────────────

func _test_night_sleep_resolution(gs: Node, data_node: Node) -> int:
	print("--- 5. night sleep resolution ---")
	var failed := 0

	_reset_gs(gs)
	gs.set("day", 24)
	gs.set("phase", "night")

	# 1. 第 24 夜 fixed beat (d24_night_laozeng) 入夜強制播
	var loader: DataLoader = data_node.get("loader") as DataLoader
	var n24_beats := loader.beats_at(24, "night")
	var fixed_entered := false
	for b in n24_beats:
		if b.get("id") == "d24_night_laozeng" and b.get("fixed", false):
			var lines: PackedStringArray = gs.play_beat("d24_night_laozeng")
			if lines.size() > 0:
				fixed_entered = true
				break
	if fixed_entered:
		failed += _ok("第 24 夜 fixed beat 入夜強制播成功")
	else:
		failed += _fail("第 24 夜 fixed beat 未能入夜強制播")

	# 2. 颱風夜條件成立時睡覺播 bleed beat (d24_night_bleed)
	gs.set_flag("boundary_bleeding", true)
	gs.set_flag("hold_d24am", true)

	var sleep_lines: PackedStringArray = gs.sleep_night()
	if sleep_lines.size() > 0 and sleep_lines[0].contains("二樓有人在走"):
		failed += _ok("直接睡：成功解析旅館當夜定日 beat (d24_night_bleed)")
	else:
		failed += _fail("直接睡：未能解析出 d24_night_bleed (輸出: %s)" % str(sleep_lines))

	if gs.flags.get("awei_heard_it", false):
		failed += _ok("d24_night_bleed 之 on_enter 成功設定 flag awei_heard_it")
	else:
		failed += _fail("d24_night_bleed 未能觸發 on_enter flag")

	return failed


# ── 6. 夜間放主角卡不消耗行動格 ──────────────────────────────────────────────

func _test_night_protagonist_placement_no_action_cost(gs: Node, data_node: Node) -> int:
	print("--- 6. night protagonist placement no action cost ---")
	var failed := 0

	_reset_gs(gs)
	gs.set("day", 10)
	gs.set("phase", "night")

	var res: Dictionary = gs.try_place("protagonist", "n_take_something", "leave")
	if res.get("ok", false):
		if not gs.action_spent:
			failed += _ok("夜間放置主角卡結算成功且 action_spent 仍為 false")
		else:
			failed += _fail("夜間放置主角卡錯誤地消耗了 action_spent")
	else:
		failed += _fail("夜間放置主角卡失敗: %s" % str(res))

	return failed


# ── 7. 第 45 天 evening 結局 coda 與迴圈重置 ──────────────────────────────────

func _test_day45_ending_coda_and_loop_reset(gs: Node, data_node: Node) -> int:
	print("--- 7. day 45 ending coda and loop reset ---")
	var failed := 0

	_reset_gs(gs)
	gs.set("day", 45)
	gs.set("phase", "evening")
	gs.set_flag("final_day", true)

	# 1. d45_then 播出
	var lines: PackedStringArray = gs.play_beat("d45_then")
	if lines.size() > 0 and lines[0].contains("是他自己"):
		failed += _ok("第 45 天 evening d45_then 成功播出")
	else:
		failed += _fail("第 45 天 evening d45_then 播出失敗 (輸出: %s)" % str(lines))

	# on_enter 發 k_not_today
	if gs.has_knowledge("k_not_today"):
		failed += _ok("d45_then on_enter 成功給予知識卡 k_not_today")
	else:
		failed += _fail("d45_then 未給予 k_not_today")

	# 2. 比對槽放入情報卡完成知識升級且不吃格
	gs.gain_card("info_registry")
	var compare_res: Dictionary = gs.try_place("info_registry", "d45_then", "compare_registry")
	if compare_res.get("ok", false):
		if gs.has_knowledge("k_already_on_list") and not gs.has_knowledge("k_not_today"):
			failed += _ok("比對槽放置成功：k_not_today 升級為 k_already_on_list")
		else:
			failed += _fail("比對槽升級效果不正確")
		if not gs.action_spent:
			failed += _ok("比對槽放置不消耗行動格")
		else:
			failed += _fail("比對槽錯誤消耗了行動格")
	else:
		failed += _fail("比對槽放置失敗: %s" % str(compare_res))

	# 3. advance_phase 推進觸發 end_run
	gs.advance_phase()
	if int(gs.get("day")) == 1 and str(gs.get("phase")) == "morning":
		failed += _ok("coda 推進後回到第 1 天 morning")
	else:
		failed += _fail("coda 推進後未回到第 1 天 morning")

	if gs.has_knowledge("k_already_on_list"):
		failed += _ok("重置後 meta 層知識卡完整保留")
	else:
		failed += _fail("重置後 meta 層知識卡丟失")

	var hand: Array = gs.get("hand") as Array
	if hand.size() == 1 and hand[0] == "protagonist":
		failed += _ok("重置後手牌只剩主角卡")
	else:
		failed += _fail("重置後手牌狀態異常: %s" % str(hand))

	var flags: Dictionary = gs.get("flags") as Dictionary
	if flags.is_empty():
		failed += _ok("重置後 flags 清空")
	else:
		failed += _fail("重置後 flags 未清空")

	# 4. 第二輪重播 d45_then：升級是單向的，不得把舊版發回來。
	#    beats_entered 每輪清空，所以 on_enter 會再結算一次；而 knowledge 跨輪保留，
	#    k_already_on_list 還在手上 → 守衛必須擋掉 k_not_today 的重發。
	gs.set("day", 45)
	gs.set("phase", "evening")
	gs.play_beat("d45_then")

	if not gs.has_knowledge("k_not_today"):
		failed += _ok("第二輪重播 d45_then 不重發已升級的 k_not_today")
	else:
		failed += _fail("第二輪重播 d45_then 把 k_not_today 發回來了（升級應為單向）")

	if gs.has_knowledge("k_already_on_list"):
		failed += _ok("第二輪重播後升級版 k_already_on_list 仍在")
	else:
		failed += _fail("第二輪重播後升級版 k_already_on_list 遺失")

	var flags_loop2: Dictionary = gs.get("flags") as Dictionary
	if flags_loop2.get("loop1_end", false):
		failed += _ok("守衛只擋卡片項目，同一個 on_enter 的 flag 照常寫入")
	else:
		failed += _fail("守衛誤擋了整個 on_enter：loop1_end 未寫入")

	return failed


# ── 8. run_ended 一輪恰好發射一次 ────────────────────────────────────────────

func _test_run_ended_emitted_exactly_once(gs: Node, data_node: Node) -> int:
	print("--- 8. run_ended emitted exactly once ---")
	var failed := 0

	_reset_gs(gs)
	gs.set("day", 45)
	gs.set("phase", "evening")

	var emit_box := [0]
	var cb := func(_eid: String): emit_box[0] += 1
	gs.run_ended.connect(cb)

	# 第一次推進：觸發 end_run
	gs.advance_phase()
	if emit_box[0] == 1:
		failed += _ok("第 45 天 evening 推進：run_ended 成功發射 1 次")
	else:
		failed += _fail("第一次推進 run_ended 發射次數不為 1 (實際: %d)" % emit_box[0])

	# 連按幾次推進：天數由第 1 天往下走，不重發 run_ended
	gs.advance_phase() # day 1 afternoon
	gs.advance_phase() # day 1 evening
	gs.advance_phase() # day 1 night
	gs.advance_phase() # day 2 morning

	if emit_box[0] == 1:
		failed += _ok("連續推進 4 次後 run_ended 計數仍為 1（無無窮迴圈）")
	else:
		failed += _fail("連續推進後 run_ended 被重複發射 (實際: %d 次)" % emit_box[0])

	if int(gs.get("day")) == 2 and str(gs.get("phase")) == "morning":
		failed += _ok("時間推進正常進行至第 2 天 morning")
	else:
		failed += _fail("時間推進異常: 第 %d 天 %s" % [int(gs.get("day")), str(gs.get("phase"))])

	gs.run_ended.disconnect(cb)
	return failed


# ── 9. 第二輪重看到站事件主角卡仍恰好一張（gain 冪等）───────────────────────

func _test_second_loop_arrival_gain_idempotent(gs: Node, data_node: Node) -> int:
	print("--- 9. second loop arrival gain idempotent ---")
	var failed := 0

	_reset_gs(gs)
	# 初始手牌為主角卡
	var hand: Array = gs.get("hand") as Array
	if hand.size() != 1 or hand[0] != "protagonist":
		return failed + _fail("初始手牌未含主角卡")

	# 模擬第 1 天到站事件 gain protagonist
	gs.gain_card("protagonist")
	if hand.size() == 1 and hand[0] == "protagonist":
		failed += _ok("gain_card('protagonist') 具冪等性，手牌仍恰好 1 張主角卡")
	else:
		failed += _fail("gain_card('protagonist') 重複發卡，手牌: %s" % str(hand))

	return failed


# ── 10. 45 天貪心走查腳本（共用 PlaythroughGreedy，K-36）────────────────────

func _test_greedy_playthrough_45_days(gs: Node, data_node: Node) -> int:
	print("--- 10. 45-day greedy playthrough (via PlaythroughGreedy) ---")
	var failed := 0

	_reset_gs(gs)
	var res: Dictionary = PlaythroughGreedy.run_greedy_walk(gs, data_node, false)

	var sync_errors: Array = res.get("errors", []) as Array
	if not sync_errors.is_empty():
		for err in sync_errors:
			failed += _fail("貪心走查時間同步異常 (K-148): %s" % str(err))
	else:
		failed += _ok("全 45 天時間軸同步無異常 (K-148)")

	if int(res.get("illegal_phases", 0)) > 0:
		failed += _fail("存在 %d 個未放置且未列入合法原因之行動格 (K-25)" % int(res.get("illegal_phases", 0)))
	else:
		failed += _ok("全 90 個行動時段均已完成合法性分類與驗證 (K-25)")

	if int(res.get("run_ended_count", 0)) == 1:
		failed += _ok("45 天走查結束且 run_ended 恰好發射 1 次 (K-36)")
	else:
		failed += _fail("45 天走查 run_ended 發射次數不為 1 (實際: %d)" % int(res.get("run_ended_count", 0)))

	if int(gs.get("day")) == 1 and str(gs.get("phase")) == "morning":
		failed += _ok("45 天走查後成功回到第 1 天 morning")
	else:
		failed += _fail("45 天走查後未回到第 1 天 morning")

	return failed
