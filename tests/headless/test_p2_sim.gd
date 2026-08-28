extends SceneTree

## P2-E headless 驗收測試：三種玩家 45 天重演（發狂卡機制模擬驗證）。
## 重演 A 深潛、B 典型、C 謹慎三種玩家，逐項對齊 subdocs/驗證/發狂卡機制模擬.md 與 實作規格書.md > P2-E。
## 走真的規則層入口（enter_night_location, indulge, advance_phase）。
## 跑法：
##   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/test_p2_sim.gd
## 全通 exit 0；任一不符 exit 1。

const PanelBuilder := preload("res://scripts/core/panel_builder.gd")
const Indulgence := preload("res://scripts/core/indulgence.gd")
const ConditionEval := preload("res://scripts/core/condition_eval.gd")
const PlaythroughGreedy := preload("res://tests/headless/playthrough_greedy.gd")


func _initialize() -> void:
	var gs: Node = get_root().get_node_or_null("GameState")
	var gs_created := false
	if gs == null:
		gs = load("res://scripts/autoload/game_state.gd").new()
		gs.name = "GameState"
		get_root().add_child(gs)
		Engine.register_singleton("GameState", gs)
		gs_created = true

	var data_node: Node = get_root().get_node_or_null("Data")
	var data_created := false
	if data_node == null:
		data_node = load("res://scripts/autoload/data.gd").new()
		data_node.name = "Data"
		get_root().add_child(data_node)
		Engine.register_singleton("Data", data_node)
		data_created = true

	await process_frame

	if not data_node.get("ok"):
		push_error("P2-E: Data failed to load; abort")
		quit(1)
		return

	var failed := 0

	print("=== P2-E headless 三種玩家重演測試 ===")

	# 1. 重演 A 深潛
	var res_a := _run_simulation(gs, data_node, "A_deep_dive")
	failed += _verify_player_a(res_a, data_node)

	# 2. 重演 B 典型
	var res_b := _run_simulation(gs, data_node, "B_typical")
	failed += _verify_player_b(res_b, data_node)

	# 3. 重演 C 謹慎
	var res_c := _run_simulation(gs, data_node, "C_cautious")
	failed += _verify_player_c(res_c, data_node)

	# 4. 決定論測試：同一個策略重跑兩次，產生的各項數據與狀態逐項完全相同
	failed += _test_determinism(gs, data_node)

	if data_created:
		Engine.unregister_singleton("Data")
	if gs_created:
		Engine.unregister_singleton("GameState")

	if failed > 0:
		push_error("\nP2-E: %d assertion(s) failed" % failed)
		quit(1)
	else:
		print("\nP2-E: all simulation tests passed successfully (exit 0)")
		quit(0)


func _ok(msg: String) -> int:
	print("  ok  " + msg)
	return 0


func _fail(msg: String) -> int:
	push_error("  FAIL  " + msg)
	return 1


# ── 核心模擬迴圈（共用，走真實規則層入口）───────────────────────────────────

static func _count_madness_in_hand(gs: Node) -> int:
	var count := 0
	for card in (gs.get("hand") as Array):
		if str(card).begins_with("madness"):
			count += 1
	return count


static func _run_simulation(gs: Node, data_node: Node, strategy_type: String) -> Dictionary:
	var final_markers_box := [{}]
	var final_madness_cards_box := [[]]
	var endings_received: Array[String] = []

	var on_run_ended := func(eid: String) -> void:
		endings_received.append(eid)
		final_markers_box[0] = (gs.get("night_locations_seen") as Dictionary).duplicate()
		var mcards: Array = []
		for card in (gs.get("hand") as Array):
			if str(card).begins_with("madness"):
				mcards.append(card)
		final_madness_cards_box[0] = mcards

	gs.connect("run_ended", on_run_ended)
	gs.call("end_run")
	gs.set("night_locations_seen", {})
	gs.set("night_once_beats_seen", {})
	gs.set("knowledge", {})

	var loader: DataLoader = data_node.get("loader")
	var daily_max_madness: Array[int] = [] # 1-indexed (index 0 unused, 1..45)
	daily_max_madness.resize(46)
	daily_max_madness.fill(0)

	var peak_madness := 0
	var peak_day := 0
	var forced_count_box := [0]
	var heavy_forced_count_box := [0]
	var active_count_box := [0]
	var actions_eaten_box := [0]
	var events_timeline: Array[Dictionary] = []
	var desync_errors: Array[String] = []
	var last_indulgence_count := int(gs.get("indulgence_count"))

	for d in range(1, 46):
		var d_max := _count_madness_in_hand(gs)

		# ── Morning ──
		if int(gs.get("day")) != d or str(gs.get("phase")) != "morning":
			desync_errors.append("Day %d morning desync: day=%d, phase=%s" % [d, int(gs.get("day")), str(gs.get("phase"))])
		# 檢查 morning 跨日是否自動觸發強制縱慾
		var cur_ind_count := int(gs.get("indulgence_count"))
		if cur_ind_count > last_indulgence_count:
			var lvl := Indulgence.level_for(cur_ind_count, loader.tuning)
			forced_count_box[0] += (cur_ind_count - last_indulgence_count)
			if lvl == "heavy":
				heavy_forced_count_box[0] += (cur_ind_count - last_indulgence_count)
			actions_eaten_box[0] += 1
			last_indulgence_count = cur_ind_count
			var hand_after := _count_madness_in_hand(gs)
			events_timeline.append({
				"day": d,
				"phase": "morning",
				"action": "forced_indulgence",
				"level": lvl,
				"hand_after": hand_after,
			})
			d_max = max(d_max, hand_after)

		d_max = max(d_max, _count_madness_in_hand(gs))

		# Morning 玩家行為
		_handle_action_phase(gs, data_node, d, "morning", strategy_type, events_timeline, func(active_add: int, eaten_add: int):
			active_count_box[0] += active_add
			actions_eaten_box[0] += eaten_add
		)
		last_indulgence_count = int(gs.get("indulgence_count"))
		d_max = max(d_max, _count_madness_in_hand(gs))
		PlaythroughGreedy.solve_active_encounter_if_any(gs)
		gs.advance_phase()

		# ── Afternoon ──
		if int(gs.get("day")) != d or str(gs.get("phase")) != "afternoon":
			desync_errors.append("Day %d afternoon desync: day=%d, phase=%s" % [d, int(gs.get("day")), str(gs.get("phase"))])
		cur_ind_count = int(gs.get("indulgence_count"))
		if cur_ind_count > last_indulgence_count:
			var lvl := Indulgence.level_for(cur_ind_count, loader.tuning)
			forced_count_box[0] += (cur_ind_count - last_indulgence_count)
			if lvl == "heavy":
				heavy_forced_count_box[0] += (cur_ind_count - last_indulgence_count)
			actions_eaten_box[0] += 1
			last_indulgence_count = cur_ind_count
			var hand_after := _count_madness_in_hand(gs)
			events_timeline.append({
				"day": d,
				"phase": "afternoon",
				"action": "forced_indulgence",
				"level": lvl,
				"hand_after": hand_after,
			})
			d_max = max(d_max, hand_after)

		d_max = max(d_max, _count_madness_in_hand(gs))

		# Afternoon 玩家行為
		_handle_action_phase(gs, data_node, d, "afternoon", strategy_type, events_timeline, func(active_add: int, eaten_add: int):
			active_count_box[0] += active_add
			actions_eaten_box[0] += eaten_add
		)
		last_indulgence_count = int(gs.get("indulgence_count"))
		d_max = max(d_max, _count_madness_in_hand(gs))
		PlaythroughGreedy.solve_active_encounter_if_any(gs)
		if str(gs.get("phase")) == "afternoon":
			gs.advance_phase()

		# ── Evening ──
		if int(gs.get("day")) != d or str(gs.get("phase")) != "evening":
			desync_errors.append("Day %d evening desync: day=%d, phase=%s" % [d, int(gs.get("day")), str(gs.get("phase"))])
		gs.play_evening()
		d_max = max(d_max, _count_madness_in_hand(gs))
		PlaythroughGreedy.solve_active_encounter_if_any(gs)
		gs.advance_phase()

		# 第 45 天 evening 推進後已呼叫 end_run，不進第 45 夜
		if d == 45:
			daily_max_madness[d] = d_max
			if d_max > peak_madness:
				peak_madness = d_max
				peak_day = d
			break

		# ── Night ──
		if int(gs.get("day")) != d or str(gs.get("phase")) != "night":
			desync_errors.append("Day %d night desync: day=%d, phase=%s" % [d, int(gs.get("day")), str(gs.get("phase"))])
		gs.play_night_fixed()
		PlaythroughGreedy.solve_active_encounter_if_any(gs)

		# 根據策略決定是否開啟夜間收費標記
		_handle_night_phase(gs, data_node, d, strategy_type, events_timeline)
		d_max = max(d_max, _count_madness_in_hand(gs))

		daily_max_madness[d] = d_max
		if d_max > peak_madness:
			peak_madness = d_max
			peak_day = d

		gs.sleep_night()
		gs.advance_phase()

	gs.disconnect("run_ended", on_run_ended)

	# P5-B：45 天走完不必然啟動結局（D45 coda 門檻要求先完成名冊比對），
	# 終局數字改為走查結束時直接取一次；run_ended 只用來確認中途有沒有 BE。
	final_markers_box[0] = (gs.get("night_locations_seen") as Dictionary).duplicate()
	var end_mcards: Array = []
	for card in (gs.get("hand") as Array):
		if str(card).begins_with("madness"):
			end_mcards.append(card)
	final_madness_cards_box[0] = end_mcards

	# 收集視野窗口（桌上 >= 3 張的天數）
	var vision_days: Array[int] = []
	for day_idx in range(1, 46):
		if daily_max_madness[day_idx] >= int(loader.tuning.get("madness_vision_threshold", 3)):
			vision_days.append(day_idx)

	var opened_paid_count := 0
	var opened_markers: Dictionary = final_markers_box[0] as Dictionary
	for loc_id in opened_markers.keys():
		var loc: Dictionary = loader.locations.get(loc_id, {}) as Dictionary
		if int(loc.get("madness_cost", 0)) > 0:
			opened_paid_count += 1

	return {
		"strategy": strategy_type,
		"peak_madness": peak_madness,
		"peak_day": peak_day,
		"endings": endings_received,
		"forced_count": forced_count_box[0],
		"heavy_forced_count": heavy_forced_count_box[0],
		"active_count": active_count_box[0],
		"actions_eaten": actions_eaten_box[0],
		"vision_days": vision_days,
		"paid_markers_opened": opened_paid_count,
		"events_timeline": events_timeline,
		"daily_max_madness": daily_max_madness,
		"desync_errors": desync_errors,
		"final_state": gs.call("serialize"),
	}


static func _handle_action_phase(gs: Node, data_node: Node, day: int, phase: String, strategy: String, timeline: Array[Dictionary], add_stats: Callable) -> void:
	# 先播放當前所有 OPEN beat
	_play_open_beats(gs, data_node)

	if strategy == "C_cautious":
		# C 謹慎策略：一有發狂卡就立即主動縱慾（消掉該卡並消耗行動格）
		var m_count := _count_madness_in_hand(gs)
		var spent := bool(gs.get("action_spent"))
		if m_count > 0 and not spent:
			# 挑選第一張發狂卡與可用出口
			var madness_card := ""
			for card in (gs.get("hand") as Array):
				if str(card).begins_with("madness"):
					madness_card = str(card)
					break
			if not madness_card.is_empty():
				var ind_res: Dictionary = gs.try_place(madness_card, "exit_sanquan", "x_smash")
				if ind_res.get("ok", false):
					add_stats.call(1, 1) # active_add=1, eaten_add=1
					timeline.append({
						"day": day,
						"phase": phase,
						"action": "active_indulgence",
						"slot": "exit_sanquan::x_smash",
						"hand_after": _count_madness_in_hand(gs),
					})
					return
				else:
					print("DEBUG C active indulgence failed at Day %d %s: res=%s" % [day, phase, str(ind_res)])

	# 若尚未消耗行動格，執行一般貪心主角卡放置
	if not bool(gs.get("action_spent")):
		var locs := PanelBuilder.available_locations(gs, data_node)
		for loc_id in locs:
			var view: Dictionary = gs.build_panel(loc_id)
			for bv: Dictionary in view.get("beats", []) as Array:
				if int(bv.get("tri", -1)) != PanelBuilder.TriState.OPEN:
					continue
				var bid: String = str(bv["beat"].get("id", ""))
				for sv: Dictionary in bv.get("slots", []) as Array:
					if int(sv.get("tri", -1)) != PanelBuilder.TriState.OPEN:
						continue
					var slot: Dictionary = sv["slot"] as Dictionary
					var sid: String = str(slot.get("id", ""))
					var accepts: Array = slot.get("accepts", []) as Array
					if accepts.has("protagonist"):
						var res: Dictionary = gs.try_place("protagonist", bid, sid)
						if res.get("ok", false):
							return


static func _handle_night_phase(gs: Node, data_node: Node, day: int, strategy: String, timeline: Array[Dictionary]) -> void:
	var madness_in_hand := _count_madness_in_hand(gs)
	var allow_open := false

	match strategy:
		"A_deep_dive":
			allow_open = true
		"B_typical":
			allow_open = (madness_in_hand < 3)
		"C_cautious":
			allow_open = (madness_in_hand < 2)

	if not allow_open:
		return

	var locs: Array[String] = PanelBuilder.available_locations(gs, data_node)
	var chosen_loc := ""
	var loader: DataLoader = data_node.get("loader") as DataLoader
	var opened_markers: Dictionary = gs.get("night_locations_seen") as Dictionary

	for loc_id in locs:
		var summary: Dictionary = PanelBuilder.location_summary(loc_id, gs, data_node)
		if not bool(summary.get("can_enter", false)):
			continue
		var loc: Dictionary = loader.locations.get(loc_id, {}) as Dictionary
		var cost_val: Variant = loc.get("madness_cost", 0)
		var cost: int = int(cost_val) if (cost_val is int or cost_val is float) else 0
		if cost > 0 and not opened_markers.has(loc_id):
			chosen_loc = loc_id
			break

	if not chosen_loc.is_empty():
		var entry_res: Dictionary = gs.enter_night_location(chosen_loc)
		if entry_res.get("ok", false):
			var view: Dictionary = gs.build_panel(chosen_loc)
			for bv: Dictionary in view.get("beats", []) as Array:
				if int(bv.get("tri", -1)) == PanelBuilder.TriState.OPEN:
					var bid := str((bv["beat"] as Dictionary).get("id", ""))
					if not bid.is_empty():
						gs.play_beat(bid)
			timeline.append({
				"day": day,
				"phase": "night",
				"action": "enter_night_location",
				"loc": chosen_loc,
				"hand_after": _count_madness_in_hand(gs),
			})


static func _play_open_beats(gs: Node, data_node: Node) -> void:
	var locs := PanelBuilder.available_locations(gs, data_node)
	var played_beats: Dictionary = {}
	var changed := true
	while changed:
		changed = false
		for loc_id in locs:
			var play_view: Dictionary = gs.build_panel(loc_id)
			for play_bv: Dictionary in play_view.get("beats", []) as Array:
				if int(play_bv.get("tri", -1)) != PanelBuilder.TriState.OPEN:
					continue
				var play_bid := str((play_bv["beat"] as Dictionary).get("id", ""))
				if played_beats.has(play_bid):
					continue
				gs.play_beat(play_bid)
				played_beats[play_bid] = true
				changed = true


# ── 2. A 深潛驗收斷言 ────────────────────────────────────────────────────────

func _verify_player_a(res: Dictionary, data_node: Node) -> int:
	print("\n--- 1. Player A (Deep Dive) verification ---")
	var failed := 0

	if res.is_empty():
		return _fail("A 模擬未跑完，回傳空結果")

	var desyncs: Array = res.get("desync_errors", []) as Array
	for err_msg in desyncs:
		failed += _fail(str(err_msg))

	# 1. 桌面峰值 4 (第 11 天)
	var peak: int = int(res["peak_madness"])
	var peak_day: int = int(res["peak_day"])
	if peak == 4 and peak_day == 11:
		failed += _ok("A 桌面峰值為 4（落在第 11 天）")
	else:
		failed += _fail("A 桌面峰值不符: 預期 4 (第 11 天), 實際 %d (第 %d 天)" % [peak, peak_day])

	# 2. 從未觸及 cap
	var endings: Array = res["endings"] as Array
	if not endings.has("ending_madness_be"):
		failed += _ok("A 從未觸及 cap 7（未觸發 ending_madness_be）")
	else:
		failed += _fail("A 異常觸發發瘋 BE: %s" % str(endings))

	# 3. 強制縱慾次數 12
	var forced: int = int(res["forced_count"])
	if forced == 12:
		failed += _ok("A 強制縱慾次數為 12 次")
	else:
		failed += _fail("A 強制縱慾次數不符: 預期 12, 實際 %d" % forced)

	# 4. 最重級強制縱慾 5 次
	var heavy: int = int(res["heavy_forced_count"])
	if heavy == 5:
		failed += _ok("A 其中最重級強制縱慾為 5 次（首次第 27 天）")
	else:
		failed += _fail("A 最重級強制縱慾次數不符: 預期 5, 實際 %d" % heavy)

	# 5. 主動縱慾次數 0
	var active: int = int(res["active_count"])
	if active == 0:
		failed += _ok("A 主動縱慾次數為 0 次")
	else:
		failed += _fail("A 主動縱慾次數不符: 預期 0, 實際 %d" % active)

	# 6. 吃掉行動格 12 / 90
	var eaten: int = int(res["actions_eaten"])
	if eaten == 12:
		failed += _ok("A 吃掉行動格為 12 / 90 格")
	else:
		failed += _fail("A 吃掉行動格數不符: 預期 12, 實際 %d" % eaten)

	# 7. 桌上 >= 3 張天數 18 / 45（P3-C: D15 固定造訪 n_plaza，開標記順延至 D16，D15 狂氣為 2）
	var vision_days: Array = res["vision_days"] as Array
	if vision_days.size() == 18:
		failed += _ok("A 桌上 >= 3 張天數為 18 / 45 天")
	else:
		failed += _fail("A 桌上 >= 3 張天數不符: 預期 18, 實際 %d (%s)" % [vision_days.size(), str(vision_days)])

	# 8. 開到收費標記 14 / 14
	var paid: int = int(res["paid_markers_opened"])
	if paid == 14:
		failed += _ok("A 開到的收費標記為 14 / 14 個")
	else:
		failed += _fail("A 開到的收費標記數不符: 預期 14, 實際 %d" % paid)

	# 視野窗口比對：主窗口 第 8–14 天 + 第 16-23 天 (15天) + 第二窗口 第 42–44 天 (3天)
	var expected_vision_a := [8, 9, 10, 11, 12, 13, 14, 16, 17, 18, 19, 20, 21, 22, 23, 42, 43, 44]
	if vision_days == expected_vision_a:
		failed += _ok("A 視野窗口完全相符（第 8–14, 16–23 天 ＋ 第 42–44 天）")
	else:
		failed += _fail("A 視野窗口不符: 預期 %s, 實際 %s" % [str(expected_vision_a), str(vision_days)])

	# 逐項時間軸比對（發狂卡機制模擬.md > 三 > A 深潛的逐項時間軸）
	var timeline: Array = res["events_timeline"] as Array
	failed += _verify_timeline_a(timeline)

	return failed


func _verify_timeline_a(timeline: Array) -> int:
	var failed := 0
	var expected_timeline := [
		{ "day": 6, "phase": "night", "action": "enter_night_location", "loc": "n_ahong_1", "hand_after": 1 },
		{ "day": 7, "phase": "night", "action": "enter_night_location", "loc": "n_source", "hand_after": 2 },
		{ "day": 11, "phase": "night", "action": "enter_night_location", "loc": "n_ahong_2", "hand_after": 4 },
		{ "day": 13, "phase": "morning", "action": "forced_indulgence", "level": "light", "hand_after": 3 },
		{ "day": 14, "phase": "morning", "action": "forced_indulgence", "level": "normal", "hand_after": 2 },
		{ "day": 14, "phase": "night", "action": "enter_night_location", "loc": "n_plaza", "hand_after": 3 },
		{ "day": 15, "phase": "morning", "action": "forced_indulgence", "level": "normal", "hand_after": 2 },
		{ "day": 16, "phase": "night", "action": "enter_night_location", "loc": "n_ahong_3", "hand_after": 3 },
		{ "day": 17, "phase": "night", "action": "enter_night_location", "loc": "n_litcorridor", "hand_after": 4 },
		{ "day": 18, "phase": "morning", "action": "forced_indulgence", "level": "normal", "hand_after": 3 },
		{ "day": 20, "phase": "night", "action": "enter_night_location", "loc": "n_higher", "hand_after": 4 },
		{ "day": 21, "phase": "morning", "action": "forced_indulgence", "level": "normal", "hand_after": 3 },
		{ "day": 21, "phase": "night", "action": "enter_night_location", "loc": "n_ahong_4", "hand_after": 4 },
		{ "day": 23, "phase": "morning", "action": "forced_indulgence", "level": "normal", "hand_after": 3 },
		{ "day": 24, "phase": "morning", "action": "forced_indulgence", "level": "normal", "hand_after": 2 },
		{ "day": 27, "phase": "morning", "action": "forced_indulgence", "level": "heavy", "hand_after": 1 },
		{ "day": 28, "phase": "morning", "action": "forced_indulgence", "level": "heavy", "hand_after": 0 },
		{ "day": 28, "phase": "night", "action": "enter_night_location", "loc": "n_ahong_5", "hand_after": 1 },
		{ "day": 35, "phase": "morning", "action": "forced_indulgence", "level": "heavy", "hand_after": 0 },
		{ "day": 37, "phase": "night", "action": "enter_night_location", "loc": "n_steam_below", "hand_after": 1 },
		{ "day": 38, "phase": "night", "action": "enter_night_location", "loc": "n_ahong_6", "hand_after": 2 },
		{ "day": 42, "phase": "night", "action": "enter_night_location", "loc": "n_behind_temple", "hand_after": 3 },
		{ "day": 43, "phase": "night", "action": "enter_night_location", "loc": "n_ahong_7", "hand_after": 4 },
		{ "day": 44, "phase": "morning", "action": "forced_indulgence", "level": "heavy", "hand_after": 3 },
		{ "day": 45, "phase": "morning", "action": "forced_indulgence", "level": "heavy", "hand_after": 2 },
	]

	if timeline.size() != expected_timeline.size():
		failed += _fail("A 時間軸事件總數不符: 預期 %d, 實際 %d" % [expected_timeline.size(), timeline.size()])
		return failed

	var match_all := true
	for i in range(expected_timeline.size()):
		var exp_ev: Dictionary = expected_timeline[i]
		var act_ev: Dictionary = timeline[i]
		for key in exp_ev.keys():
			if str(exp_ev[key]) != str(act_ev.get(key, "")):
				match_all = false
				failed += _fail("A 時間軸第 %d 項不符 [%s]: 預期 %s, 實際 %s (事件: %s)" % [
					i, key, str(exp_ev[key]), str(act_ev.get(key, "")), str(act_ev)
				])

	if match_all:
		failed += _ok("A 逐項時間軸 25 個事件完全相符（第 8 夜 n_manydoors 於 P4-A 起改為強制遭遇到訪：仍在 day 8 收 1 張發狂卡、視野窗口不變，但不再記為玩家選擇的 enter_night_location 事件。首次最重落在第 27 天，峰值落在第 11 天，重置前留 2 張）")

	return failed


# ── 3. B 典型驗收斷言 ────────────────────────────────────────────────────────

func _verify_player_b(res: Dictionary, data_node: Node) -> int:
	print("\n--- 2. Player B (Typical) verification ---")
	var failed := 0

	if res.is_empty():
		return _fail("B 模擬未跑完，回傳空結果")

	var desyncs: Array = res.get("desync_errors", []) as Array
	for err_msg in desyncs:
		failed += _fail(str(err_msg))

	# 1. 桌面峰值 3 (第 8 天)
	var peak: int = int(res["peak_madness"])
	var peak_day: int = int(res["peak_day"])
	if peak == 3 and peak_day == 8:
		failed += _ok("B 桌面峰值為 3（落在第 8 天）")
	else:
		failed += _fail("B 桌面峰值不符: 預期 3 (第 8 天), 實際 %d (第 %d 天)" % [peak, peak_day])

	# 2. 從未觸及 cap
	var endings: Array = res["endings"] as Array
	if not endings.has("ending_madness_be"):
		failed += _ok("B 從未觸及 cap 7（未觸發 ending_madness_be）")
	else:
		failed += _fail("B 異常觸發發瘋 BE: %s" % str(endings))

	# 3. 強制縱慾次數 12
	var forced: int = int(res["forced_count"])
	if forced == 12:
		failed += _ok("B 強制縱慾次數為 12 次")
	else:
		failed += _fail("B 強制縱慾次數不符: 預期 12, 實際 %d" % forced)

	# 4. 最重級強制縱慾 5 次
	var heavy: int = int(res["heavy_forced_count"])
	if heavy == 5:
		failed += _ok("B 其中最重級強制縱慾為 5 次")
	else:
		failed += _fail("B 最重級強制縱慾次數不符: 預期 5, 實際 %d" % heavy)

	# 5. 主動縱慾次數 0
	var active: int = int(res["active_count"])
	if active == 0:
		failed += _ok("B 主動縱慾次數為 0 次")
	else:
		failed += _fail("B 主動縱慾次數不符: 預期 0, 實際 %d" % active)

	# 6. 吃掉行動格 12 / 90
	var eaten: int = int(res["actions_eaten"])
	if eaten == 12:
		failed += _ok("B 吃掉行動格為 12 / 90 格")
	else:
		failed += _fail("B 吃掉行動格數不符: 預期 12, 實際 %d" % eaten)

	# 7. 桌上 >= 3 張天數 21 / 45（P3-C: D15 固定造訪 n_plaza，開標記順延至 D16，D15 狂氣為 2）
	var vision_days: Array = res["vision_days"] as Array
	if vision_days.size() == 21:
		failed += _ok("B 桌上 >= 3 張天數為 21 / 45 天")
	else:
		failed += _fail("B 桌上 >= 3 張天數不符: 預期 21, 實際 %d (%s)" % [vision_days.size(), str(vision_days)])

	# 8. 開到收費標記 14 / 14
	var paid: int = int(res["paid_markers_opened"])
	if paid == 14:
		failed += _ok("B 開到的收費標記為 14 / 14 個")
	else:
		failed += _fail("B 開到的收費標記數不符: 預期 14, 實際 %d" % paid)

	# 視野窗口比對：主窗口 第 8–14 天 + 第 16-26 天 (18天) + 第二窗口 第 42–44 天 (3天)
	var expected_vision_b := [8, 9, 10, 11, 12, 13, 14, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 42, 43, 44]
	if vision_days == expected_vision_b:
		failed += _ok("B 視野窗口完全相符（第 8–14, 16–26 天 ＋ 第 42–44 天）")
	else:
		failed += _fail("B 視野窗口不符: 預期 %s, 實際 %s" % [str(expected_vision_b), str(vision_days)])

	return failed


# ── 4. C 謹慎驗收斷言 ────────────────────────────────────────────────────────

func _verify_player_c(res: Dictionary, data_node: Node) -> int:
	print("\n--- 3. Player C (Cautious) verification ---")
	var failed := 0

	if res.is_empty():
		return _fail("C 模擬未跑完，回傳空結果")

	var desyncs: Array = res.get("desync_errors", []) as Array
	for err_msg in desyncs:
		failed += _fail(str(err_msg))

	# 1. 桌面峰值 1 (第 6 天)
	var peak: int = int(res["peak_madness"])
	var peak_day: int = int(res["peak_day"])
	if peak == 1 and peak_day == 6:
		failed += _ok("C 桌面峰值為 1（落在第 6 天）")
	else:
		failed += _fail("C 桌面峰值不符: 預期 1 (第 6 天), 實際 %d (第 %d 天)" % [peak, peak_day])

	# 2. 從未觸及 cap
	var endings: Array = res["endings"] as Array
	if not endings.has("ending_madness_be"):
		failed += _ok("C 從未觸及 cap 7（未觸發 ending_madness_be）")
	else:
		failed += _fail("C 異常觸發發瘋 BE: %s" % str(endings))

	# 3. 強制縱慾次數 0
	var forced: int = int(res["forced_count"])
	if forced == 0:
		failed += _ok("C 強制縱慾次數為 0 次")
	else:
		failed += _fail("C 強制縱慾次數不符: 預期 0, 實際 %d" % forced)

	# 4. 最重級強制縱慾 — (0 次)
	var heavy: int = int(res["heavy_forced_count"])
	if heavy == 0:
		failed += _ok("C 無最重級強制縱慾（0 次）")
	else:
		failed += _fail("C 最重級強制縱慾次數不符: 預期 0, 實際 %d" % heavy)

	# 5. 主動縱慾次數 14
	var active: int = int(res["active_count"])
	if active == 14:
		failed += _ok("C 主動縱慾次數為 14 次")
	else:
		failed += _fail("C 主動縱慾次數不符: 預期 14, 實際 %d" % active)

	# 6. 吃掉行動格 14 / 90
	var eaten: int = int(res["actions_eaten"])
	if eaten == 14:
		failed += _ok("C 吃掉行動格為 14 / 90 格")
	else:
		failed += _fail("C 吃掉行動格數不符: 預期 14, 實際 %d" % eaten)

	# 7. 桌上 >= 3 張天數 0 / 45
	var vision_days: Array = res["vision_days"] as Array
	if vision_days.is_empty():
		failed += _ok("C 桌上 >= 3 張天數為 0 / 45 天（無視野窗口）")
	else:
		failed += _fail("C 桌上 >= 3 張天數不符: 預期 0, 實際 %d (%s)" % [vision_days.size(), str(vision_days)])

	# 8. 開到收費標記 14 / 14
	var paid: int = int(res["paid_markers_opened"])
	if paid == 14:
		failed += _ok("C 開到的收費標記為 14 / 14 個")
	else:
		failed += _fail("C 開到的收費標記數不符: 預期 14, 實際 %d" % paid)

	return failed


# ── 5. 決定論測試 ────────────────────────────────────────────────────────────

func _test_determinism(gs: Node, data_node: Node) -> int:
	print("\n--- 4. Determinism verification across runs ---")
	var failed := 0

	var run1 := _run_simulation(gs, data_node, "A_deep_dive")
	var run2 := _run_simulation(gs, data_node, "A_deep_dive")

	if run1.is_empty() or run2.is_empty():
		return _fail("決定論測試：模擬未跑完，回傳空結果")

	var desyncs1: Array = run1.get("desync_errors", []) as Array
	for err_msg in desyncs1:
		failed += _fail("run1 desync: " + str(err_msg))

	var desyncs2: Array = run2.get("desync_errors", []) as Array
	for err_msg in desyncs2:
		failed += _fail("run2 desync: " + str(err_msg))

	var state1: Dictionary = run1["final_state"] as Dictionary
	var state2: Dictionary = run2["final_state"] as Dictionary

	var json1 := JSON.stringify(state1)
	var json2 := JSON.stringify(state2)

	if json1 == json2:
		failed += _ok("深潛玩家同存檔重跑兩次，最終序列化狀態逐字相同")
	else:
		failed += _fail("深潛玩家同存檔重跑兩次狀態分歧")

	var t1: Array = run1["events_timeline"] as Array
	var t2: Array = run2["events_timeline"] as Array
	if JSON.stringify(t1) == JSON.stringify(t2):
		failed += _ok("深潛玩家同存檔重跑兩次，時間軸與決策事件逐項相同")
	else:
		failed += _fail("深潛玩家同存檔重跑兩次時間軸分歧")

	return failed
