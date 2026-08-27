extends SceneTree

## P3-F headless 驗收測試：
## 1. 28-row 動態夜間地點狀態矩陣與資料衍生斷言（含 K-34 門檻鎖定與 K-35 零合成 beat）
## 2. 第一輪重演：路徑效率策略（D14 n_ahong_3，D15 fixed n_plaza 免費，全輪 13 marker cost）
## 3. 第一輪重演：最大壓力策略（D14 主動 n_plaza，D15 fixed 已見，D16+ n_ahong_3，全輪 14 marker cost）
## 4. 第二輪跨輪五路徑抽樣與終身首次收費驗證（seen paid, unseen paid, seen free, fixed once, shared counterpart）
## 5. 跨輪決定論測試：同第一輪終態載入兩次，相同第二輪操作序列產生逐字相同 serialize 與時間軸

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

	if not data_node.get("ok"):
		push_error("P3-F: Data failed to load; abort")
		quit(1)
		return

	var failed := 0
	print("\n=== P3-F Headless Test Suite ===")

	failed += _test_28_row_matrix_and_derivations(gs, data_node)
	failed += _test_first_round_path_efficiency_13(gs, data_node)
	failed += _test_first_round_max_pressure_14(gs, data_node)
	failed += _test_second_round_replay_and_five_paths(gs, data_node)
	failed += _test_determinism_across_two_runs(gs, data_node)

	if failed > 0:
		push_error("\nP3-F: %d assertion(s) failed\n" % failed)
		quit(1)
	else:
		print("\nP3-F: all tests passed\n")
		quit(0)


func _ok(msg: String) -> int:
	print("  ok  " + msg)
	return 0


func _fail(msg: String) -> int:
	push_error("  FAIL  " + msg)
	return 1


static func _reset_gs(gs: Node) -> void:
	gs.call("end_run")
	gs.set("night_locations_seen", {})
	gs.set("night_once_beats_seen", {})
	gs.set("knowledge", {})
	gs.set("night_location_chosen", "")
	gs.set("night_sleep_pending", false)
	gs.set("day", 1)
	gs.set("phase", "morning")


# ── 1. 28-row 動態狀態矩陣與資料衍生斷言 ─────────────────────────────────────

func _test_28_row_matrix_and_derivations(gs: Node, data_node: Node) -> int:
	print("--- 1. 28-row dynamic night location matrix & derivations ---")
	var failed := 0
	_reset_gs(gs)

	var loader: DataLoader = data_node.get("loader") as DataLoader
	var night_locs: Array[Dictionary] = []
	var alignable_rows: Array[Dictionary] = []
	var night_only_rows: Array[Dictionary] = []
	var paid_rows: Array[Dictionary] = []
	var free_rows: Array[Dictionary] = []
	var teaser_rows: Array[Dictionary] = []
	var gated_rows: Array[Dictionary] = []
	var unique_reveals: Dictionary = {}

	for loc_id: String in loader.locations:
		var loc: Dictionary = loader.locations[loc_id] as Dictionary
		if str(loc.get("layer", "")) != "night":
			continue
		night_locs.append(loc)

		var day_cp: Variant = loc.get("day_counterpart")
		var is_teaser: bool = bool(loc.get("teaser_only", false))
		var cost_val: Variant = loc.get("madness_cost")
		var cost: int = int(cost_val) if (cost_val is int or cost_val is float) else 0

		if is_teaser:
			teaser_rows.append(loc)
		elif cost > 0:
			paid_rows.append(loc)
		else:
			free_rows.append(loc)

		if day_cp != null and not str(day_cp).is_empty():
			alignable_rows.append(loc)
			var rev: Variant = loc.get("night_reveal")
			if rev != null and not str(rev).is_empty():
				unique_reveals[str(rev)] = true
		else:
			night_only_rows.append(loc)

		if loc.has("requires"):
			gated_rows.append(loc)

	# 斷言分類總數
	if night_locs.size() == 28:
		failed += _ok("夜間地點總數動態計算恰為 28 個")
	else:
		failed += _fail("夜間地點總數異常: 預期 28, 實際 %d" % night_locs.size())

	if alignable_rows.size() == 12:
		failed += _ok("可對位 row (alignable) 動態計算恰為 12 個")
	else:
		failed += _fail("可對位 row 總數異常: 預期 12, 實際 %d" % alignable_rows.size())

	if night_only_rows.size() == 16:
		failed += _ok("夜間限定 row (night-only) 動態計算恰為 16 個")
	else:
		failed += _fail("夜間限定 row 總數異常: 預期 16, 實際 %d" % night_only_rows.size())

	if paid_rows.size() == 14:
		failed += _ok("收費 row (paid) 動態計算恰為 14 個")
	else:
		failed += _fail("收費 row 總數異常: 預期 14, 實際 %d" % paid_rows.size())

	if free_rows.size() == 13 and teaser_rows.size() == 1:
		failed += _ok("免費 row 恰為 13 個、teaser row 恰為 1 個 (n_corridor_end)")
	else:
		failed += _fail("免費/teaser 總數異常: free=%d, teaser=%d" % [free_rows.size(), teaser_rows.size()])

	if gated_rows.size() == 6:
		failed += _ok("帶門檻 row (gated requires) 動態計算恰為 6 個 (阿宏鏈)")
	else:
		failed += _fail("帶門檻 row 總數異常: 預期 6, 實際 %d" % gated_rows.size())

	# 斷言對位卡片完整性 (10 張 knowledge)
	if unique_reveals.size() == 10:
		failed += _ok("可對位 row 衍生之 reveal knowledge 卡片恰為 10 張")
	else:
		failed += _fail("reveal knowledge 總數異常: 預期 10, 實際 %d" % unique_reveals.size())

	var cards_valid := true
	for cid in unique_reveals.keys():
		if not loader.cards.has(cid):
			cards_valid = false
			failed += _fail("reveal card %s 不存在於 cards.json" % cid)
		else:
			var card_obj: Dictionary = loader.cards[cid] as Dictionary
			if str(card_obj.get("type", "")) != "knowledge":
				cards_valid = false
				failed += _fail("reveal card %s 型別不為 knowledge: %s" % [cid, str(card_obj.get("type", ""))])
	if cards_valid:
		failed += _ok("10 張 reveal 知識卡皆存在於 cards.json 且型別均為 knowledge")

	# 斷言 K-35：所有 28 個夜間地點呼叫 PanelBuilder.build() 不存在任何未定義的假 beat ID
	var fake_beats_found := 0
	for loc_obj in night_locs:
		var lid := str(loc_obj.get("id", ""))
		var panel: Dictionary = PanelBuilder.build(lid, gs, data_node)
		for bv: Dictionary in panel.get("beats", []) as Array:
			var b_data: Dictionary = bv.get("beat", {}) as Dictionary
			var bid := str(b_data.get("id", ""))
			if bid.is_empty() or not loader.beats_by_id.has(bid):
				fake_beats_found += 1
				failed += _fail("地點 %s 於 build() 回傳未知/合成 beat id: %s (K-35)" % [lid, bid])
	if fake_beats_found == 0:
		failed += _ok("全 28 個夜間地點 build() 無任何資料不存在的假 beat id (K-35 結案證據)")

	# 斷言 K-34：gated requires 門檻未達成時 location_summary 正確標記 locked 與理由
	var gated_locked_ok := true
	gs.set("phase", "night")
	for loc_obj in gated_rows:
		var lid := str(loc_obj.get("id", ""))
		var earliest := int(loc_obj.get("earliest_night", 1))
		gs.set("day", earliest)
		var summary: Dictionary = PanelBuilder.location_summary(lid, gs, data_node)
		if bool(summary.get("can_enter", true)):
			gated_locked_ok = false
			failed += _fail("未達成門檻地點 %s can_enter 應為 false" % lid)
		if str(summary.get("reason_code", "")) != "locked":
			gated_locked_ok = false
			failed += _fail("未達成門檻地點 %s reason_code 異常: %s" % [lid, str(summary.get("reason_code", ""))])
		if str(summary.get("status_text", "")) != "[尚未到訪]":
			gated_locked_ok = false
			failed += _fail("未到訪之帶門檻地點 %s status_text 異常: %s" % [lid, str(summary.get("status_text", ""))])
		if str(summary.get("reason_text", "")).is_empty():
			gated_locked_ok = false
			failed += _fail("未達成門檻地點 %s reason_text 不得為空" % lid)
	if gated_locked_ok:
		failed += _ok("帶門檻地點於前置條件不足時正確阻斷進入 (K-34 結案證據)")

	return failed


# ── 核心第一輪走查重演器 ───────────────────────────────────────────────────

static func _run_first_round_sim(gs: Node, data_node: Node, strategy_type: String) -> Dictionary:
	_reset_gs(gs)

	var final_markers_box := [{}]
	var final_madness_cards_box := [[]]
	var endings_received: Array[String] = []
	var final_madness_cleared_box := [0]

	var on_run_ended := func(eid: String) -> void:
		endings_received.append(eid)
		final_markers_box[0] = (gs.get("night_locations_seen") as Dictionary).duplicate()
		var mcards: Array = []
		for card in (gs.get("hand") as Array):
			if str(card).begins_with("madness"):
				mcards.append(card)
		final_madness_cards_box[0] = mcards
		final_madness_cleared_box[0] = int(gs.get("madness_cards_cleared"))

	gs.connect("run_ended", on_run_ended)

	var loader: DataLoader = data_node.get("loader") as DataLoader
	var last_ind_count := int(gs.get("indulgence_count"))
	var events_timeline: Array[Dictionary] = []
	var paid_entered_count := 0

	for d in range(1, 46):
		# ── 1. Morning ──
		assert(int(gs.get("day")) == d and str(gs.get("phase")) == "morning")
		var cur_ind_count := int(gs.get("indulgence_count"))
		var forced_m := (cur_ind_count > last_ind_count)
		if forced_m:
			var lvl := Indulgence.level_for(cur_ind_count, loader.tuning)
			events_timeline.append({
				"day": d,
				"phase": "morning",
				"action": "forced_indulgence",
				"level": lvl,
			})
		last_ind_count = cur_ind_count

		PlaythroughGreedy.execute_action_phase(gs, data_node, d, "morning", forced_m)
		last_ind_count = int(gs.get("indulgence_count"))
		gs.advance_phase()

		# ── 2. Afternoon ──
		assert(int(gs.get("day")) == d and str(gs.get("phase")) == "afternoon")
		cur_ind_count = int(gs.get("indulgence_count"))
		var forced_a := (cur_ind_count > last_ind_count)
		if forced_a:
			var lvl := Indulgence.level_for(cur_ind_count, loader.tuning)
			events_timeline.append({
				"day": d,
				"phase": "afternoon",
				"action": "forced_indulgence",
				"level": lvl,
			})
		last_ind_count = cur_ind_count

		PlaythroughGreedy.execute_action_phase(gs, data_node, d, "afternoon", forced_a)
		last_ind_count = int(gs.get("indulgence_count"))
		if str(gs.get("phase")) == "afternoon":
			gs.advance_phase()

		# ── 3. Evening ──
		assert(int(gs.get("day")) == d and str(gs.get("phase")) == "evening")
		PlaythroughGreedy.execute_evening_phase(gs, data_node, d)
		last_ind_count = int(gs.get("indulgence_count"))
		gs.advance_phase()

		if d == 45:
			break

		# ── 4. Night ──
		assert(int(gs.get("day")) == d and str(gs.get("phase")) == "night")
		# P4-A：D8 起夜間 fixed 遭遇（charge_first_visit）於 play_night_fixed 強制到訪時收費，
		# 不走顯式 enter_night_location，故在此以 _madness_counter 差額補進 paid_entered_count。
		var madness_before_fixed: int = int(gs.get("_madness_counter"))
		gs.play_night_fixed()
		paid_entered_count += int(gs.get("_madness_counter")) - madness_before_fixed
		PlaythroughGreedy.solve_active_encounter_if_any(gs)

		var locs := PanelBuilder.available_locations(gs, data_node)
		var chosen_loc := ""

		if strategy_type == "path_efficiency_13":
			if d == 14:
				var sum_ah3 := PanelBuilder.location_summary("n_ahong_3", gs, data_node)
				if bool(sum_ah3.get("can_enter", false)):
					chosen_loc = "n_ahong_3"
			if chosen_loc.is_empty():
				for lid in locs:
					var summary := PanelBuilder.location_summary(lid, gs, data_node)
					if not bool(summary.get("can_enter", false)):
						continue
					var loc_data := loader.locations.get(lid, {}) as Dictionary
					if int(loc_data.get("madness_cost", 0)) > 0 and not (gs.get("night_locations_seen") as Dictionary).has(lid):
						chosen_loc = lid
						break
			if chosen_loc.is_empty():
				for lid in locs:
					var summary := PanelBuilder.location_summary(lid, gs, data_node)
					if bool(summary.get("can_enter", false)):
						chosen_loc = lid
						break

		elif strategy_type == "max_pressure_14":
			if d == 14:
				var sum_plz := PanelBuilder.location_summary("n_plaza", gs, data_node)
				if bool(sum_plz.get("can_enter", false)):
					chosen_loc = "n_plaza"
			if chosen_loc.is_empty():
				for lid in locs:
					var summary := PanelBuilder.location_summary(lid, gs, data_node)
					if not bool(summary.get("can_enter", false)):
						continue
					var loc_data := loader.locations.get(lid, {}) as Dictionary
					if int(loc_data.get("madness_cost", 0)) > 0 and not (gs.get("night_locations_seen") as Dictionary).has(lid):
						chosen_loc = lid
						break
			if chosen_loc.is_empty():
				for lid in locs:
					var summary := PanelBuilder.location_summary(lid, gs, data_node)
					if bool(summary.get("can_enter", false)):
						chosen_loc = lid
						break

		if not chosen_loc.is_empty():
			var loc_dict: Dictionary = loader.locations.get(chosen_loc, {}) as Dictionary
			var cost_val: int = int(loc_dict.get("madness_cost", 0))
			var is_first: bool = not (gs.get("night_locations_seen") as Dictionary).has(chosen_loc)

			var entry_res: Dictionary = gs.enter_night_location(chosen_loc)
			if entry_res.get("ok", false):
				if cost_val > 0 and is_first:
					paid_entered_count += cost_val
				var view: Dictionary = gs.build_panel(chosen_loc)
				for bv: Dictionary in view.get("beats", []) as Array:
					if int(bv.get("tri", -1)) == PanelBuilder.TriState.OPEN:
						var bid := str((bv["beat"] as Dictionary).get("id", ""))
						if not bid.is_empty():
							gs.play_beat(bid)
				events_timeline.append({
					"day": d,
					"phase": "night",
					"action": "enter_night_location",
					"loc": chosen_loc,
				})

		gs.sleep_night()
		last_ind_count = int(gs.get("indulgence_count"))
		gs.advance_phase()

	gs.disconnect("run_ended", on_run_ended)

	return {
		"strategy": strategy_type,
		"endings": endings_received,
		"final_night_markers": final_markers_box[0],
		"final_madness_cards": final_madness_cards_box[0],
		"paid_entered_count": paid_entered_count,
		"final_madness_cleared": final_madness_cleared_box[0],
		"events_timeline": events_timeline,
		"final_state": gs.call("serialize"),
	}


# ── 2. 第一輪重演：路徑效率策略（13 Marker Cost）───────────────────────────

func _test_first_round_path_efficiency_13(gs: Node, data_node: Node) -> int:
	print("--- 2. First round replay: Path efficiency (13 marker cost) ---")
	var failed := 0
	_reset_gs(gs)

	var res := _run_first_round_sim(gs, data_node, "path_efficiency_13")

	# 驗證收費標記數與發放發狂卡
	var paid_cost: int = int(res.get("paid_entered_count", 0))
	if paid_cost == 13:
		failed += _ok("路徑效率策略 (D14 n_ahong_3 + D15 fixed n_plaza 免費) 累計收取 13 marker cost")
	else:
		failed += _fail("路徑效率策略 marker cost 不為 13: 實際 %d" % paid_cost)

	var cleared: int = int(res.get("final_madness_cleared", 0))
	if cleared == 11:
		failed += _ok("強制縱慾累計消除 11 張發狂卡")
	else:
		failed += _fail("強制縱慾消除張數異常: 預期 11, 實際 %d" % cleared)

	var in_hand: int = (res.get("final_madness_cards", []) as Array).size()
	if in_hand == 2:
		failed += _ok("重置前手牌持有 2 張發狂卡 (13 供給 = 11 消除 + 2 留存)")
	else:
		failed += _fail("重置前手牌發狂卡異常: 預期 2, 實際 %d" % in_hand)

	var endings: Array = res.get("endings", []) as Array
	if endings.size() == 1 and endings[0] == "ending_default":
		failed += _ok("順利走完 45 天並觸發 ending_default，未觸發發瘋 BE")
	else:
		failed += _fail("結局異常: %s" % str(endings))

	var seen_markers: Dictionary = res.get("final_night_markers", {}) as Dictionary
	var loader: DataLoader = data_node.get("loader") as DataLoader
	var paid_seen_count := 0
	for lid in seen_markers.keys():
		var ldata: Dictionary = loader.locations.get(lid, {}) as Dictionary
		if int(ldata.get("madness_cost", 0)) > 0:
			paid_seen_count += 1
	if paid_seen_count == 14:
		failed += _ok("一輪結束時 14 個收費地點全部被記錄為 seen (含 D15 fixed 到訪之 n_plaza)")
	else:
		failed += _fail("收費地點 seen 總數異常: 預期 14, 實際 %d" % paid_seen_count)

	return failed


# ── 3. 第一輪重演：最大壓力策略（14 Marker Cost）───────────────────────────

func _test_first_round_max_pressure_14(gs: Node, data_node: Node) -> int:
	print("--- 3. First round replay: Max pressure (14 marker cost) ---")
	var failed := 0
	_reset_gs(gs)

	var res := _run_first_round_sim(gs, data_node, "max_pressure_14")

	var paid_cost: int = int(res.get("paid_entered_count", 0))
	if paid_cost == 14:
		failed += _ok("最大壓力策略 (D14 主動走 n_plaza) 累計收取 14 marker cost")
	else:
		failed += _fail("最大壓力策略 marker cost 不為 14: 實際 %d" % paid_cost)

	var cleared: int = int(res.get("final_madness_cleared", 0))
	if cleared == 12:
		failed += _ok("強制縱慾累計消除 12 張發狂卡")
	else:
		failed += _fail("強制縱慾消除張數異常: 預期 12, 實際 %d" % cleared)

	var in_hand: int = (res.get("final_madness_cards", []) as Array).size()
	if in_hand == 2:
		failed += _ok("重置前手牌持有 2 張發狂卡 (14 供給 = 12 消除 + 2 留存)")
	else:
		failed += _fail("重置前手牌發狂卡異常: 預期 2, 實際 %d" % in_hand)

	var endings: Array = res.get("endings", []) as Array
	if endings.size() == 1 and endings[0] == "ending_default":
		failed += _ok("順利走完 45 天並觸發 ending_default，未觸發發瘋 BE")
	else:
		failed += _fail("結局異常: %s" % str(endings))

	return failed


# ── 4. 第二輪跨輪五路徑抽樣與終身首次收費驗證 ─────────────────────────────

func _test_second_round_replay_and_five_paths(gs: Node, data_node: Node) -> int:
	print("--- 4. Second round replay & five sample paths (lifetime first-visit fee) ---")
	var failed := 0
	_reset_gs(gs)

	# 先以路徑效率策略跑完第一輪
	_run_first_round_sim(gs, data_node, "path_efficiency_13")

	# 驗證第 1 輪真實 end_run() 後的狀態
	if int(gs.get("day")) == 1 and str(gs.get("phase")) == "morning":
		failed += _ok("第 1 輪結束後時間正確重置至第 1 天 morning")
	else:
		failed += _fail("重置後時間異常: 第 %d 天 %s" % [int(gs.get("day")), str(gs.get("phase"))])

	var hand: Array = gs.get("hand") as Array
	if hand.size() == 1 and hand[0] == "protagonist":
		failed += _ok("重置後手牌只剩主角卡 [protagonist]")
	else:
		failed += _fail("重置後手牌異常: %s" % str(hand))

	var meta_seen: Dictionary = gs.get("night_locations_seen") as Dictionary
	if not meta_seen.is_empty():
		failed += _ok("meta 層 night_locations_seen 在跨輪重置後完整保留 (%d 個地點)" % meta_seen.size())
	else:
		failed += _fail("meta 層 night_locations_seen 跨輪遺失")

	var meta_once: Dictionary = gs.get("night_once_beats_seen") as Dictionary
	if not meta_once.is_empty():
		failed += _ok("meta 層 night_once_beats_seen 在跨輪重置後完整保留 (%d 個 beat)" % meta_once.size())
	else:
		failed += _fail("meta 層 night_once_beats_seen 跨輪遺失")

	# 抽樣 5 條路徑：
	# Path 1: 已見收費地點 (Seen Paid) -> 第二輪進入不收 marker cost、不發發狂卡
	gs.set("day", 10)
	gs.set("phase", "night")
	var hand_size_before := (gs.get("hand") as Array).size()
	var res_seen_paid: Dictionary = gs.enter_night_location("n_ahong_1")
	var hand_size_after := (gs.get("hand") as Array).size()
	if bool(res_seen_paid.get("ok", false)) and hand_size_after == hand_size_before and (res_seen_paid.get("lines") as PackedStringArray).is_empty():
		failed += _ok("Path 1 (Seen Paid): 進入第 1 輪已到訪之收費地點 n_ahong_1 不收 marker cost、不發發狂卡 (終身首次收費)")
	else:
		failed += _fail("Path 1 (Seen Paid) 失敗: res=%s, hand_before=%d, hand_after=%d" % [str(res_seen_paid), hand_size_before, hand_size_after])

	# Path 2: 未見收費地點 (Unseen Paid) -> 首次進入收費發卡並記入 seen
	gs.set("night_location_chosen", "")
	gs.set("day", 20)
	(gs.get("night_locations_seen") as Dictionary).erase("n_higher")
	var hand_before_unseen := (gs.get("hand") as Array).size()
	var res_unseen_paid: Dictionary = gs.enter_night_location("n_higher")
	var hand_after_unseen := (gs.get("hand") as Array).size()
	if bool(res_unseen_paid.get("ok", false)) and hand_after_unseen == hand_before_unseen + 1 and (gs.get("night_locations_seen") as Dictionary).has("n_higher"):
		failed += _ok("Path 2 (Unseen Paid): 第 2 輪首次進入未見收費地點 n_higher 正常收取 marker cost 並發放發狂卡")
	else:
		failed += _fail("Path 2 (Unseen Paid) 失敗: res=%s, hand_before=%d, hand_after=%d" % [str(res_unseen_paid), hand_before_unseen, hand_after_unseen])

	# Path 3: 已見免費地點 (Seen Free) -> 0 代價進入
	gs.set("night_location_chosen", "")
	var hand_before_free := (gs.get("hand") as Array).size()
	var res_seen_free: Dictionary = gs.enter_night_location("n_landmark")
	var hand_after_free := (gs.get("hand") as Array).size()
	if bool(res_seen_free.get("ok", false)) and hand_after_free == hand_before_free:
		failed += _ok("Path 3 (Seen Free): 進入免費地點 n_landmark 正常進入且 0 代價")
	else:
		failed += _fail("Path 3 (Seen Free) 失敗: res=%s" % str(res_seen_free))

	# Path 4: 一次性 fixed (D1/D2/D15) 不重播，重播型 fixed (D24) 正常重播
	gs.set("night_location_chosen", "")
	gs.set("night_sleep_pending", false)
	# 測試 D1 fixed 不重播
	gs.set("day", 1)
	gs.set("phase", "night")
	gs.play_night_fixed()
	if str(gs.get("night_location_chosen")) != "n_corridor":
		failed += _ok("Path 4a (Fixed Once): 第 2 輪 D1 入夜不重播 d1_night_fixed (meta_once)")
	else:
		failed += _fail("Path 4a (Fixed Once): D1 誤重播了 d1_night_fixed")

	# 測試 D15 fixed 不重播
	gs.set("night_location_chosen", "")
	gs.set("day", 15)
	gs.set("phase", "night")
	gs.play_night_fixed()
	if str(gs.get("night_location_chosen")) != "n_plaza":
		failed += _ok("Path 4b (Fixed Once): 第 2 輪 D15 入夜不重播 d15_night_corridor (meta_once)")
	else:
		failed += _fail("Path 4b (Fixed Once): D15 誤重播了 d15_night_corridor")

	# 測試 D24 play_night_fixed 重播
	gs.set("night_location_chosen", "")
	gs.set("day", 24)
	gs.set("phase", "night")
	(gs.get("flags") as Dictionary).clear()
	var d24_lines: PackedStringArray = gs.play_night_fixed()
	if (gs.get("flags") as Dictionary).get("laozeng_patrol_d24", false) and not d24_lines.is_empty():
		failed += _ok("Path 4c (Repeatable): 第 2 輪 D24 play_night_fixed 正常重播老曾巡邏定日 beat (每輪重播)")
	else:
		failed += _fail("Path 4c (Repeatable): D24 play_night_fixed 未能正確重播: lines=%s" % str(d24_lines))

	# Path 5: Shared Counterpart Auto-alignment
	# 第 1 輪已持有 k_night_temple，n_woodtags 已見，n_music 尚未到訪
	gs.gain_card("k_night_temple", true)
	var seen_dict: Dictionary = gs.get("night_locations_seen") as Dictionary
	seen_dict["n_woodtags"] = true
	seen_dict.erase("n_music")

	var loader: DataLoader = data_node.get("loader") as DataLoader
	var temple_day_name := str((loader.locations.get("temple", {}) as Dictionary).get("name", "temple"))
	var exp_woodtags_name := "%s・數木牌的屋子" % temple_day_name
	var exp_music_name := "%s・有音樂的地方" % temple_day_name

	var summary_woodtags: Dictionary = PanelBuilder.location_summary("n_woodtags", gs, data_node)
	var summary_music_before: Dictionary = PanelBuilder.location_summary("n_music", gs, data_node)

	if str(summary_woodtags.get("status_text", "")) == "[已對位]" and str(summary_woodtags.get("display_name", "")) == exp_woodtags_name:
		failed += _ok("Path 5a (Auto Alignment): 第 2 輪已見之 n_woodtags 自動衍生 [已對位] 與『%s』" % exp_woodtags_name)
	else:
		failed += _fail("Path 5a summary 異常: %s" % str(summary_woodtags))

	if str(summary_music_before.get("status_text", "")) == "[尚未到訪]" and str(summary_music_before.get("display_name", "")) == "有音樂的地方":
		failed += _ok("Path 5b (Unseen Counterpart): 第 2 輪未見之 n_music 仍為 [尚未到訪] 與『有音樂的地方』")
	else:
		failed += _fail("Path 5b summary_before 異常: %s" % str(summary_music_before))

	# 第 2 輪日後到訪 n_music
	gs.set("day", 10)
	gs.set("phase", "night")
	gs.set("night_location_chosen", "")
	gs.enter_night_location("n_music")
	var summary_music_after: Dictionary = PanelBuilder.location_summary("n_music", gs, data_node)
	if str(summary_music_after.get("status_text", "")) == "[已對位]" and str(summary_music_after.get("display_name", "")) == exp_music_name:
		failed += _ok("Path 5c (Subsequent Visit): 第 2 輪到訪 n_music 後自動顯示 [已對位] 與『%s』且無二次確認" % exp_music_name)
	else:
		failed += _fail("Path 5c summary_after 異常: %s" % str(summary_music_after))

	gs.set("phase", "morning")
	var offer_temple: Dictionary = PanelBuilder.alignment_offer("temple", gs, data_node)
	if not bool(offer_temple.get("available", true)):
		failed += _ok("Path 5d (No Repeat Offer): 白天 temple 對位 offer 為 false (已持有知識，不重複發起)")
	else:
		failed += _fail("Path 5d offer 異常: %s" % str(offer_temple))

	return failed


# ── 5. 跨輪決定論測試 ───────────────────────────────────────────────────────

func _test_determinism_across_two_runs(gs: Node, data_node: Node) -> int:
	print("--- 5. Determinism test across two runs from same serialized checkpoint ---")
	var failed := 0
	_reset_gs(gs)

	# 跑完第一輪並取得存檔
	var res1 := _run_first_round_sim(gs, data_node, "path_efficiency_13")
	var checkpoint_state: Dictionary = res1.get("final_state", {}) as Dictionary

	# 建立兩個獨立的 GameState 實例進行第二輪走查
	var gs_a: Node = (load("res://scripts/autoload/game_state.gd") as GDScript).new()
	gs_a.name = "GameState_A"
	gs_a.set("Data", data_node)
	get_root().add_child(gs_a)
	gs_a.deserialize(checkpoint_state)

	var gs_b: Node = (load("res://scripts/autoload/game_state.gd") as GDScript).new()
	gs_b.name = "GameState_B"
	gs_b.set("Data", data_node)
	get_root().add_child(gs_b)
	gs_b.deserialize(checkpoint_state)

	# 兩邊執行完全相同的第二輪操作序列（前 10 天）
	var timeline_a: Array[Dictionary] = []
	var timeline_b: Array[Dictionary] = []

	for d in range(1, 11):
		# Morning
		PlaythroughGreedy.execute_action_phase(gs_a, data_node, d, "morning", false)
		gs_a.advance_phase()
		timeline_a.append({ "day": d, "phase": "morning", "action_spent": bool(gs_a.get("action_spent")) })

		PlaythroughGreedy.execute_action_phase(gs_b, data_node, d, "morning", false)
		gs_b.advance_phase()
		timeline_b.append({ "day": d, "phase": "morning", "action_spent": bool(gs_b.get("action_spent")) })

		# Afternoon
		PlaythroughGreedy.execute_action_phase(gs_a, data_node, d, "afternoon", false)
		gs_a.advance_phase()

		PlaythroughGreedy.execute_action_phase(gs_b, data_node, d, "afternoon", false)
		gs_b.advance_phase()

		# Evening
		PlaythroughGreedy.execute_evening_phase(gs_a, data_node, d)
		gs_a.advance_phase()

		PlaythroughGreedy.execute_evening_phase(gs_b, data_node, d)
		gs_b.advance_phase()

		# Night
		gs_a.play_night_fixed()
		gs_a.sleep_night()
		gs_a.advance_phase()

		gs_b.play_night_fixed()
		gs_b.sleep_night()
		gs_b.advance_phase()

	var state_a: Dictionary = gs_a.serialize()
	var state_b: Dictionary = gs_b.serialize()

	if JSON.stringify(state_a) == JSON.stringify(state_b):
		failed += _ok("同存檔重載兩次並執行相同操作序列，最終 serialize() 逐字完全相同")
	else:
		failed += _fail("決定論 serialize() 比對失敗:\n  A: %s\n  B: %s" % [JSON.stringify(state_a), JSON.stringify(state_b)])

	if JSON.stringify(timeline_a) == JSON.stringify(timeline_b):
		failed += _ok("兩次執行過程記錄之事件時間軸逐項完全相同")
	else:
		failed += _fail("時間軸比對失敗")

	gs_a.queue_free()
	gs_b.queue_free()

	return failed
