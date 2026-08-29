extends SceneTree

## 45 天貪心走查測試腳本（P1-F 驗收、K-36 走查入口共用）。
## 策略：每個行動時段將主角卡放進第一個可放的 OPEN 槽，晚間結算，夜間直接睡。
## 走完 45 天結局 coda 並驗證回到第 1 天 morning。
## 跑法：
##   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/playthrough_greedy.gd
## 全通 exit 0；任一異常 exit 1。

const PanelBuilder := preload("res://scripts/core/panel_builder.gd")
const DataFacts := preload("res://scripts/core/data_facts.gd")


func _initialize() -> void:
	await process_frame

	var data_node := setup_data(self)
	var gs := setup_game_state(self, data_node)

	var res := run_greedy_walk(gs, data_node, true)
	var failed := 0

	# ── 驗收夜間收費標記與發狂卡統計 ──
	var expected_paid_markers := 0
	var expected_total_madness_cost := 0
	var expected_paid_ids: Array[String] = []
	for loc_id_key: String in data_node.loader.locations.keys():
		var loc: Dictionary = data_node.loader.locations[loc_id_key] as Dictionary
		if str(loc.get("layer", "")) == "night":
			var cost_val: Variant = loc.get("madness_cost")
			if cost_val != null and int(cost_val) > 0:
				expected_paid_markers += 1
				expected_total_madness_cost += int(cost_val)
				expected_paid_ids.append(loc_id_key)

	var seen_locations: Dictionary = res.get("final_night_markers", {}) as Dictionary
	var opened_count := 0
	for loc_id in seen_locations.keys():
		var loc: Dictionary = data_node.loader.locations.get(loc_id, {}) as Dictionary
		if int(loc.get("madness_cost", 0)) > 0:
			opened_count += 1
	var madness_gained: int = int(res.get("final_madness_count", 0))
	var madness_in_hand: int = (res.get("final_madness_cards", []) as Array).size()
	var madness_cleared: int = int(res.get("final_madness_cards_cleared", 0))

	print("=== 夜間收費標記與發狂卡統計 ===")
	print("  全作收費標記總數（locations.json）: %d" % expected_paid_markers)
	print("  一輪實際開啟收費標記數:             %d" % opened_count)
	print("  全作收費標記 madness_cost 總和:      %d" % expected_total_madness_cost)
	print("  一輪累計發放發狂卡張數:             %d" % madness_gained)
	print("  一輪累計消除發狂卡張數:             %d" % madness_cleared)
	print("  重置前手牌持有發狂卡張數:           %d" % madness_in_hand)

	if opened_count != expected_paid_markers:
		push_error("FAIL: 開啟的夜間收費標記數 (%d) 與全作收費標記總數 (%d) 不符" % [opened_count, expected_paid_markers])
		failed += 1
	else:
		print("  ok  一輪結束時開到的收費標記數與全作收費標記總數完全相符 (%d/%d)" % [opened_count, expected_paid_markers])

	if madness_gained != expected_total_madness_cost:
		push_error("FAIL: 累計發放發狂卡張數 (%d) 與收費標記 madness_cost 總和 (%d) 不符" % [madness_gained, expected_total_madness_cost])
		failed += 1
	else:
		print("  ok  累計發放發狂卡張數與收費標記 madness_cost 總和完全相符 (%d 張)" % madness_gained)

	if madness_in_hand + madness_cleared != expected_total_madness_cost:
		push_error("FAIL: 重置前手牌持有 (%d) + 消除張數 (%d) 與預期總張數 (%d) 不符" % [madness_in_hand, madness_cleared, expected_total_madness_cost])
		failed += 1
	else:
		print("  ok  重置前手牌持有與消除張數總和與預期總張數完全相符 (%d + %d = %d 張)" % [madness_in_hand, madness_cleared, expected_total_madness_cost])

	# ── 驗收迴圈重置狀態 ──
	print("\n=== 45 天走查完畢，驗收重置狀態 ===")

	var sync_errors: Array = res.get("errors", []) as Array
	if not sync_errors.is_empty():
		for err in sync_errors:
			push_error("FAIL: %s" % str(err))
			failed += 1
	else:
		print("  ok  全 45 天時間軸同步無異常 (K-148)")

	if int(res.get("illegal_phases", 0)) > 0:
		push_error("FAIL: 存在 %d 個未放置且未列入合法原因之行動格 (K-25)" % int(res.get("illegal_phases", 0)))
		failed += 1
	else:
		print("  ok  全 90 個行動時段均已完成合法性分類與驗證 (K-25)")

	if int(res.get("ending_started_count", 0)) != 1:
		push_error("FAIL: ending_started 發射次數不為 1（實際為 %d）" % int(res.get("ending_started_count", 0)))
		failed += 1
	else:
		print("  ok  ending_started 恰好發射 1 次 (ending_id: %s)" % str(res.get("last_ending_id", "")))

	if str(gs.get("flow_mode")) != "opening":
		push_error("FAIL: 結局結算後未回到 opening (實際: %s)" % str(gs.get("flow_mode")))
		failed += 1
	else:
		print("  ok  結局結算後停在 opening（下一輪要明示選一個開局選項才開始）")

	if int(gs.get("run_number")) != 2 or (gs.get("ending_history") as Array).size() != 1:
		push_error("FAIL: 結算後輪數／歷輪摘要不正確 (run_number=%d, history=%d)"
			% [int(gs.get("run_number")), (gs.get("ending_history") as Array).size()])
		failed += 1
	else:
		print("  ok  結算後 run_number 加一且歷輪摘要恰一筆")

	if not bool(gs.call("has_knowledge", "k_i_returned")):
		push_error("FAIL: 結算後未取得「我回來過」")
		failed += 1
	else:
		print("  ok  結算後取得「我回來過」")

	var hand: Array = gs.get("hand") as Array
	if not hand.is_empty():
		push_error("FAIL: opening 期間手牌不為空 (實際: %s)" % str(hand))
		failed += 1
	else:
		print("  ok  opening 期間手牌為空（主角卡由 choose_opening() 發）")

	var open_res: Dictionary = gs.call("choose_opening", "take_family_album")
	var hand_after: Array = gs.get("hand") as Array
	if not bool(open_res.get("ok", false)) or hand_after.size() != 2 or hand_after[0] != "protagonist" or hand_after[1] != "item_family_album":
		push_error("FAIL: 第二輪 choose_opening(take_family_album) 未建立正確手牌 (實際: %s)" % str(hand_after))
		failed += 1
	else:
		print("  ok  第二輪由相簿開局，手牌為 [protagonist, item_family_album] 且回到第 1 天 morning")

	var knowledge: Dictionary = gs.get("knowledge") as Dictionary
	# P5-B／B1：D45 coda 是一個 choice group，比對與空手兩條路都能收尾。
	# 走查不再強迫第 13 天去拿名冊，因此驗的是「保留下來的那張，對得上本輪真的走的那條路」。
	var coda_path := str(res.get("coda_path", ""))
	var expected_knowledge := "k_already_on_list" if coda_path == "compare_registry" else "k_not_today"
	if coda_path.is_empty():
		push_error("FAIL: D45 coda 選擇組未結算")
		failed += 1
	elif not knowledge.has(expected_knowledge):
		push_error("FAIL: 重置後知識卡 %s 未保留（coda 路徑：%s）" % [expected_knowledge, coda_path])
		failed += 1
	else:
		print("  ok  重置後 meta 層知識卡已完整保留 (%d 張知識卡，coda 路徑：%s)" % [knowledge.size(), coda_path])

	var flags: Dictionary = gs.get("flags") as Dictionary
	var switches: Dictionary = gs.get("switches") as Dictionary
	var relations: Dictionary = gs.get("relations") as Dictionary
	var slots_placed: Dictionary = gs.get("slots_placed") as Dictionary
	var choices: Dictionary = gs.get("choices") as Dictionary
	var beats_entered: Dictionary = gs.get("beats_entered") as Dictionary

	if not flags.is_empty() or not switches.is_empty() or not relations.is_empty() or not slots_placed.is_empty() or not choices.is_empty() or not beats_entered.is_empty():
		push_error("FAIL: 重置後 run 層狀態未清空")
		failed += 1
	else:
		print("  ok  重置後 run 層狀態（flags, switches, relations, slots_placed, choices, beats_entered）全部清空")

	if failed > 0 or not bool(res.get("ok", false)):
		push_error("playthrough_greedy: %d assertion(s) failed" % failed)
		quit(1)
	else:
		print("=== 45 天貪心走查測試全部通過 (總行動數: %d) ===" % int(res.get("actions_taken", 0)))
		quit(0)


## 推進到真的換了時段為止。夜間第一次推進可能只把「直接睡」的文字停拍下來
## （phase_advanced 為 false），此時要再按一次才會進隔天——這正是玩家看到的節奏。
## 進了結局或被規則層拒絕時不重試。
static func advance_until_phase_changes(gs: Node) -> Dictionary:
	var res: Dictionary = gs.call("advance_phase")
	if bool(res.get("ok", false)) and not bool(res.get("phase_advanced", false)) and str(gs.get("flow_mode")) == "run":
		res = gs.call("advance_phase")
	return res


## 執行 45 天貪心走查（K-36：供 test_p1f 與本腳本共用）
static func run_greedy_walk(gs: Node, data_node: Node, verbose: bool = false) -> Dictionary:
	# P5-D：fresh boot 停在 opening。走查驗的是 45 天的內容，不是開局選項本身，
	# 因此用測試 helper 起一輪乾淨的 run（開局選項的正式路徑由 test_p5d 驗）。
	if str(gs.get("flow_mode")) != "run":
		start_fresh_run(gs)
	var ending_started_box := [0]
	var last_ending_box := [""]
	var coda_path_box := [""]
	var final_night_markers_box := [{}]
	var final_madness_count_box := [0]
	var final_madness_cards_box := [[]]
	var final_indulgence_count_box := [0]
	var final_madness_cards_cleared_box := [0]
	var cb := func():
		ending_started_box[0] += 1
		last_ending_box[0] = str((gs.get("active_ending") as Dictionary).get("ending_id", ""))
		final_night_markers_box[0] = (gs.get("night_locations_seen") as Dictionary).duplicate()
		final_madness_count_box[0] = int(gs.get("_madness_counter"))
		var mcards: Array = []
		for card in (gs.get("hand") as Array):
			if str(card).begins_with("madness"):
				mcards.append(card)
		final_madness_cards_box[0] = mcards
		final_indulgence_count_box[0] = int(gs.get("indulgence_count"))
		final_madness_cards_cleared_box[0] = int(gs.get("madness_cards_cleared"))

	gs.ending_started.connect(cb)

	if verbose:
		print("=== 開始 45 天貪心走查 ===")

	var day_counter := 0
	var actions_taken := 0
	var illegal_phases := 0

	var stats := {
		"placed": 0,
		"forced_indulgence": 0,
		"all_fixed": 0,
		"condition_locked": 0,
		"requires_locked": 0,
		"slot_requires_locked": 0,
		"empty_by_design": 0,
		"choice_only_by_design": 0,
		"compare_only": 0,
		"illegal": 0,
	}

	var errors: Array[String] = []
	var last_ind_count := int(gs.get("indulgence_count"))

	for d in range(1, 46):
		day_counter = d

		# 1. Morning
		if int(gs.get("day")) != d or str(gs.get("phase")) != "morning":
			var err_m := "時間同步錯誤 (morning): 預期第 %d 天 morning, 實際第 %d 天 %s" % [d, int(gs.get("day")), str(gs.get("phase"))]
			errors.append(err_m)
			if verbose:
				push_error(err_m)
		var forced_m := (int(gs.get("indulgence_count")) > last_ind_count)
		last_ind_count = int(gs.get("indulgence_count"))
		var res_m := execute_action_phase(gs, data_node, d, "morning", forced_m)
		var cat_m: String = str(res_m.get("category", "illegal"))
		if stats.has(cat_m):
			stats[cat_m] += 1
		else:
			stats["illegal"] += 1
		if not res_m.get("ok", false):
			illegal_phases += 1
		if res_m.get("placed", false):
			actions_taken += 1
		last_ind_count = int(gs.get("indulgence_count"))
		gs.advance_phase()

		# 2. Afternoon
		if int(gs.get("day")) != d or str(gs.get("phase")) != "afternoon":
			var err_a := "時間同步錯誤 (afternoon): 預期第 %d 天 afternoon, 實際第 %d 天 %s" % [d, int(gs.get("day")), str(gs.get("phase"))]
			errors.append(err_a)
			if verbose:
				push_error(err_a)
		var forced_a := (int(gs.get("indulgence_count")) > last_ind_count)
		last_ind_count = int(gs.get("indulgence_count"))
		var res_a := execute_action_phase(gs, data_node, d, "afternoon", forced_a)
		var cat_a: String = str(res_a.get("category", "illegal"))
		if stats.has(cat_a):
			stats[cat_a] += 1
		else:
			stats["illegal"] += 1
		if not res_a.get("ok", false):
			illegal_phases += 1
		if res_a.get("placed", false):
			actions_taken += 1
		last_ind_count = int(gs.get("indulgence_count"))
		if str(gs.get("phase")) == "afternoon":
			var adv_a: Dictionary = gs.advance_phase()
			if not adv_a.get("ok", false):
				illegal_phases += 1

		if verbose:
			print("  第 %2d 天 | morning: %-32s | afternoon: %-32s" % [
				d,
				str(res_m.get("summary", "")),
				str(res_a.get("summary", ""))
			])

		# 3. Evening
		if int(gs.get("day")) != d or str(gs.get("phase")) != "evening":
			var err_e := "時間同步錯誤 (evening): 預期第 %d 天 evening, 實際第 %d 天 %s" % [d, int(gs.get("day")), str(gs.get("phase"))]
			errors.append(err_e)
			if verbose:
				push_error(err_e)
		execute_evening_phase(gs, data_node, d)
		if d == 45:
			coda_path_box[0] = str((gs.get("choices") as Dictionary).get("d45_then::d45_coda", ""))
		last_ind_count = int(gs.get("indulgence_count"))
		gs.advance_phase()

		# 第 45 天 evening 推進：coda 門檻完成後由規則層啟動 ending_replaced，不進第 45 夜。
		if d == 45:
			break

		# 4. Night
		if int(gs.get("day")) != d or str(gs.get("phase")) != "night":
			var err_n := "時間同步錯誤 (night): 預期第 %d 天 night, 實際第 %d 天 %s" % [d, int(gs.get("day")), str(gs.get("phase"))]
			errors.append(err_n)
			if verbose:
				push_error(err_n)
		execute_night_phase(gs, data_node, d)
		last_ind_count = int(gs.get("indulgence_count"))
		advance_until_phase_changes(gs)

	gs.ending_started.disconnect(cb)

	# P5-D：走查走到 D45 後由規則層進 ending，逐頁播完再以正式的 complete_ending() 收尾，
	# 完成後停在 opening——不自己跳回第 1 天，也不再有 legacy end_run() 這條路。
	var ending_pages := 0
	if str(gs.get("flow_mode")) == "ending":
		var page_cap := 200
		while str(gs.get("flow_mode")) == "ending" and page_cap > 0:
			page_cap -= 1
			var view: Dictionary = gs.call("ending_view")
			if bool(view.get("can_complete", false)):
				gs.call("complete_ending")
				break
			if not bool(view.get("page_revealed", false)):
				gs.call("reveal_ending_page")
			else:
				gs.call("advance_ending_page")
				ending_pages += 1

	if verbose:
		print("\n=== 45 天行動時段統計表（共 90 時段）===")
		print("  成功放置主角卡:          %2d 格" % stats["placed"])
		print("  強制縱慾消耗時段:        %2d 格" % stats["forced_indulgence"])
		print("  全 fixed 敘事時段:       %2d 格" % stats["all_fixed"])
		print("  條件分支未解鎖 (HIDDEN): %2d 格" % stats["condition_locked"])
		print("  前置門檻未達成 (LOCKED): %2d 格 (beat: %d, slot: %d)" % [
			stats["requires_locked"] + stats["slot_requires_locked"],
			stats["requires_locked"],
			stats["slot_requires_locked"]
		])
		print("  刻意留空時段 (名單內):     %2d 格" % stats["empty_by_design"])
		print("  純選擇題時段 (豁免名單):   %2d 格" % stats["choice_only_by_design"])
		print("  純比對槽時段:             %2d 格" % stats["compare_only"])
		if stats["illegal"] > 0:
			print("  異常/非法空時段:          %2d 格" % stats["illegal"])
		print("=========================================\n")

	var is_walk_ok: bool = (errors.is_empty() and illegal_phases == 0 and int(ending_started_box[0]) == 1 and str(gs.get("flow_mode")) == "opening")

	return {
		"ok": is_walk_ok,
		"errors": errors,
		"actions_taken": actions_taken,
		"illegal_phases": illegal_phases,
		"stats": stats,
		"ending_started_count": ending_started_box[0],
		"ending_pages_turned": ending_pages,
		"last_ending_id": last_ending_box[0],
		"final_night_markers": final_night_markers_box[0],
		"final_madness_count": final_madness_count_box[0],
		"final_madness_cards": final_madness_cards_box[0],
		"final_indulgence_count": final_indulgence_count_box[0],
		"final_madness_cards_cleared": final_madness_cards_cleared_box[0],
		"coda_path": coda_path_box[0],
	}


## 自動完整結算遭遇（多回合遍歷、正解/錯答/逃離/丟棄，K-142）
static func solve_active_encounter_if_any(gs: Node) -> void:
	var safety_cap := 25
	while not (gs.get("active_encounter") as Dictionary).is_empty() and safety_cap > 0:
		safety_cap -= 1
		var enc_state: Dictionary = gs.get("active_encounter") as Dictionary
		var stage := str(enc_state.get("stage", ""))
		if stage == "intro":
			var ack_res: Dictionary = gs.acknowledge_encounter_intro()
			if not ack_res.get("ok", false):
				break
			continue
		elif stage == "round":
			var view: Dictionary = gs.encounter_view()
			var candidates: Array = view.get("candidates", []) as Array
			var responded := false
			for cand in candidates:
				if not cand is Dictionary:
					continue
				var c_dict := cand as Dictionary
				if bool(c_dict.get("submittable", false)):
					var cid := str(c_dict.get("card_id", ""))
					var res: Dictionary = gs.respond_to_encounter(cid)
					if res.get("ok", false):
						responded = true
						break
			if responded:
				continue

			# 無法回應時嘗試逃離
			if bool(view.get("can_escape", false)):
				var esc_cost: int = int(view.get("escape_cost", 0))
				var disc_cards: Array[String] = []
				for cand in candidates:
					var c_dict := cand as Dictionary
					if str(c_dict.get("source", "")) == "hand" and bool(c_dict.get("discardable", false)):
						disc_cards.append(str(c_dict.get("card_id", "")))
						if disc_cards.size() == esc_cost:
							break
				if disc_cards.size() == esc_cost:
					var esc_res: Dictionary = gs.escape_encounter(disc_cards)
					if esc_res.get("ok", false):
						break

			# 無法逃離時嘗試主動丟棄
			if bool(view.get("allow_discard", false)):
				var discarded := false
				for cand in candidates:
					var c_dict := cand as Dictionary
					if str(c_dict.get("source", "")) == "hand" and bool(c_dict.get("discardable", false)):
						var d_res: Dictionary = gs.discard_in_encounter(str(c_dict.get("card_id", "")))
						if d_res.get("ok", false):
							discarded = true
							break
				if discarded:
					continue
			break


static func execute_action_phase(gs: Node, data_node: Node, day: int, phase: String, forced_indulged: bool = false) -> Dictionary:
	# 遭遇處理（P4-D、K-142）：若當前時段已有活躍遭遇（如 D45 afternoon），先進行遭遇結算
	if not (gs.get("active_encounter") as Dictionary).is_empty():
		solve_active_encounter_if_any(gs)
		return { "ok": true, "placed": false, "category": "all_fixed", "detail": "遭遇結算", "summary": "[all_fixed] 遭遇結算" }

	var locs := PanelBuilder.available_locations(gs, data_node)
	var placed := false
	var placed_info := ""

	# 依地點順序演出所有成立 beat；UI 與走查共用 play_beat()。
	# 每演出一個重新求值，讓 on_enter 解鎖的後續 beat 也能進佇列。
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

	# 貪心尋找第一個可放主角卡的 OPEN 槽
	for loc_id in locs:
		var view: Dictionary = gs.build_panel(loc_id)
		for bv: Dictionary in view.get("beats", []) as Array:
			var bid: String = str(bv["beat"].get("id", ""))
			if int(bv.get("tri", -1)) != PanelBuilder.TriState.OPEN:
				continue
			for sv: Dictionary in bv.get("slots", []) as Array:
				if int(sv.get("tri", -1)) != PanelBuilder.TriState.OPEN:
					continue
				var slot: Dictionary = sv["slot"] as Dictionary
				var sid: String = str(slot.get("id", ""))
				var accepts: Array = slot.get("accepts", []) as Array
				if accepts.has("protagonist"):
					var res: Dictionary = gs.try_place("protagonist", bid, sid)
					if res.get("ok", false):
						placed = true
						placed_info = "%s::%s" % [bid, sid]
						break
			if placed:
				break
		if placed:
			break

	if placed:
		return {
			"ok": true,
			"placed": true,
			"category": "placed",
			"detail": placed_info,
			"summary": "放置 [%s]" % placed_info
		}

	# 放不下主角卡時，進行合法性診斷與分類（K-25 / K-60）
	var diag := diagnose_unplaced_phase(data_node, day, phase, gs, forced_indulged)
	var ok: bool = bool(diag.get("ok", false))
	var cat: String = str(diag.get("category", "illegal"))
	var detail: String = str(diag.get("detail", ""))

	if not ok:
		push_error("FAIL: 第 %d 天 %s 未放置主角卡且為非法狀態：%s" % [day, phase, detail])

	return {
		"ok": ok,
		"placed": false,
		"category": cat,
		"detail": detail,
		"summary": "[%s] %s" % [cat, detail]
	}


## 診斷未放卡時段的合法性（K-25 / K-60：從規則層事實推導縱慾吃格、全 fixed 時段、比對名單與條件/門檻限制）
static func diagnose_unplaced_phase(data_node: Node, day: int, phase: String, gs: Node, forced_indulged: bool = false) -> Dictionary:
	var loader: DataLoader = data_node.get("loader") as DataLoader
	var beats: Array[Dictionary] = loader.beats_at(day, phase)

	# 0. 強制縱慾已消耗該時段行動格（P2-C / K-60：規則層比對該時段進場時是否發生強制縱慾結算）
	if bool(gs.get("action_spent")) and forced_indulged:
		return { "ok": true, "category": "forced_indulgence", "detail": "行動格已由強制縱慾消耗" }

	# 1. 刻意留空
	if DataFacts.is_empty_phase_by_design(day, phase):
		return { "ok": true, "category": "empty_by_design", "detail": "刻意留空時段" }

	# 2. 刻意 choice-only
	if DataFacts.is_choice_only_phase_by_design(day, phase):
		return { "ok": true, "category": "choice_only_by_design", "detail": "純選擇題時段（已豁免）" }

	# 3. 檢查非法空時段（K-25 缺口 2：完全無 beat 且不在留空名單中）
	if beats.is_empty():
		return { "ok": false, "category": "illegal", "detail": "異常：該時段無任何 beat 且未列入刻意留空名單" }

	# 4. 該時段所有 beat 均為 fixed（全 fixed 敘事時段，不吃行動格）
	var all_fixed := true
	for b in beats:
		if not b.get("fixed", false):
			all_fixed = false
			break
	if all_fixed:
		var beat_ids: PackedStringArray = []
		for b in beats:
			beat_ids.append(str(b.get("id", "")))
		return { "ok": true, "category": "all_fixed", "detail": "全 fixed (%s)" % ", ".join(beat_ids) }

	# 5. 條件分支未解鎖（HIDDEN）或前置門檻未達成（LOCKED）
	var active_beats: Array[Dictionary] = []
	var locked_reasons: PackedStringArray = []
	for b in beats:
		if not ConditionEval.eval(b.get("condition"), gs):
			continue
		if not ConditionEval.eval(b.get("requires"), gs):
			locked_reasons.append("%s (beat requires LOCKED)" % str(b.get("id", "")))
			continue
		active_beats.append(b)

	if active_beats.is_empty():
		if not locked_reasons.is_empty():
			return { "ok": true, "category": "requires_locked", "detail": "門檻未達: %s" % ", ".join(locked_reasons) }
		var all_cond_beats: PackedStringArray = []
		for b in beats:
			all_cond_beats.append(str(b.get("id", "")))
		return { "ok": true, "category": "condition_locked", "detail": "條件未解鎖: %s" % ", ".join(all_cond_beats) }

	# 6. 檢查 active_beats 的槽：是否所有可放主角卡的槽都處於 requires LOCKED，或僅有純比對槽
	var has_open_protag_slot := false
	var has_only_non_protag_slots := true
	for b in active_beats:
		for s: Dictionary in b.get("slots", []) as Array:
			var accepts: Array = s.get("accepts", []) as Array
			if accepts.has("protagonist"):
				has_only_non_protag_slots = false
				if ConditionEval.eval(s.get("requires"), gs):
					has_open_protag_slot = true
					break

	if has_only_non_protag_slots:
		return { "ok": true, "category": "compare_only", "detail": "純比對槽時段" }

	if not has_open_protag_slot:
		return { "ok": true, "category": "slot_requires_locked", "detail": "主角卡槽門檻未達 (slot requires LOCKED)" }

	return { "ok": false, "category": "illegal", "detail": "異常：有 active beat 且有 OPEN 主角卡槽卻未能放置" }


static func execute_evening_phase(gs: Node, _data_node: Node, day: int) -> void:
	# 統一走 GameState.play_evening() 結算 fixed beat 與殘響（K-26）
	gs.play_evening()

	# 第 45 天 evening 的 coda 選擇組：持名冊就比對，沒有就空手收尾。
	# 兩條路都能結算同一個 choice group，因此錯過第 13 天的名冊不會卡死這一輪。
	if day == 45:
		if gs.has_card("info_registry"):
			gs.try_place("info_registry", "d45_then", "compare_registry")
		else:
			gs.choose("d45_then", "d45_coda", "empty_handed")


static func execute_night_phase(gs: Node, data_node: Node, _day: int, open_markers: bool = true) -> void:
	# 1. 統一走 GameState.play_night_fixed() 結算入夜 fixed beat（K-26、K-126）
	gs.play_night_fixed()
	solve_active_encounter_if_any(gs)

	if not open_markers:
		return

	# 2. 貪心開夜間標記：若當夜有可用的夜間地點，優先開未開啟的收費標記
	var locs: Array[String] = PanelBuilder.available_locations(gs, data_node)
	var chosen_loc := ""
	var loader: DataLoader = data_node.get("loader") as DataLoader
	if loader != null:
		for loc_id in locs:
			var summary: Dictionary = PanelBuilder.location_summary(loc_id, gs, data_node)
			if not bool(summary.get("can_enter", false)):
				continue
			var loc: Dictionary = loader.locations.get(loc_id, {}) as Dictionary
			if int(loc.get("madness_cost", 0)) > 0 and not (gs.get("night_locations_seen") as Dictionary).has(loc_id):
				chosen_loc = loc_id
				break
	if chosen_loc.is_empty():
		for loc_id in locs:
			var summary: Dictionary = PanelBuilder.location_summary(loc_id, gs, data_node)
			if bool(summary.get("can_enter", false)):
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

	# 3. 夜間收尾由 advance_phase() 的夜間停拍吸收；走查不另開第二個推進入口（P5-D）。


## 測試專用：把狀態重設成「剛開始一輪」的初態（第 1 天 morning、手上只有主角卡）。
## 正式路徑是 `complete_ending()` → `choose_opening()`；P1～P4 的既有測試只需要一個乾淨的
## run，因此直接借 GameState 的 run 初始化 helper，不在測試側另寫一份重置邏輯。
static func start_fresh_run(gs: Node) -> void:
	gs.set("flow_mode", "run")
	(gs.get("active_ending") as Dictionary).clear()
	gs.call("_apply_run_initialization", gs)


static func setup_data(tree: SceneTree) -> Node:
	var data_node: Node = tree.get_root().get_node_or_null("Data")
	if data_node == null:
		data_node = load("res://scripts/autoload/data.gd").new()
		data_node.name = "Data"
		tree.get_root().add_child(data_node)
		Engine.register_singleton("Data", data_node)
	return data_node


## 測試用 GameState 工廠。P5-D 起 fresh state 是 opening（正式啟動路徑），而 P1～P4 的
## 既有案例要的是一輪乾淨的 run；autoload 也可能已經把 GameState 掛在 /root 底下，
## 因此正規化的判準是「本 process 還沒起過」，不是「這次有沒有建立節點」。
## opening 的正式路徑由 `test_boot` 與 `test_p5d` 驗。
static var _test_run_started := false


static func setup_game_state(tree: SceneTree, data_node: Node) -> Node:
	var gs: Node = tree.get_root().get_node_or_null("GameState")
	if gs == null:
		gs = load("res://scripts/autoload/game_state.gd").new()
		gs.name = "GameState"
		gs.set("Data", data_node)
		tree.get_root().add_child(gs)
		Engine.register_singleton("GameState", gs)
	# 每個 process 只正規化一次：重複呼叫拿到同一個 node，不會把測試中途的狀態洗掉。
	# 資料還沒 ready（autoload 的 _ready 尚未跑）時先不動，交給下一次呼叫，
	# 避免發不出主角卡卻留下一個看起來已經起好的 run。
	if not _test_run_started and data_node != null and data_node.get("loader") != null:
		_test_run_started = true
		start_fresh_run(gs)
	return gs
