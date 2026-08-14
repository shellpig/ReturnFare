extends SceneTree

## 45 天貪心走查測試腳本（P1-F 驗收）。
## 策略：每個行動時段將主角卡放進第一個可放的 OPEN 槽，晚間結算，夜間直接睡。
## 走完 45 天結局 coda 並驗證回到第 1 天 morning。
## 跑法：
##   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/playthrough_greedy.gd
## 全通 exit 0；任一異常 exit 1。

const PanelBuilder := preload("res://scripts/core/panel_builder.gd")
const DataFacts := preload("res://scripts/core/data_facts.gd")

var _run_ended_count := 0
var _last_ending_id := ""


func _initialize() -> void:
	await process_frame

	var data_node := _setup_data()
	var gs := _setup_game_state(data_node)

	gs.run_ended.connect(_on_run_ended)

	print("=== 開始 45 天貪心走查 ===")

	var day_counter := 0
	var actions_taken := 0

	# 走查第 1 天至第 45 天
	for d in range(1, 46):
		day_counter = d

		# 1. Morning
		assert(int(gs.get("day")) == d and str(gs.get("phase")) == "morning", "時間同步錯誤 (morning)")
		actions_taken += _execute_action_phase(gs, data_node, d, "morning")
		gs.advance_phase()

		# 2. Afternoon
		assert(int(gs.get("day")) == d and str(gs.get("phase")) == "afternoon", "時間同步錯誤 (afternoon)")
		actions_taken += _execute_action_phase(gs, data_node, d, "afternoon")
		gs.advance_phase()

		# 3. Evening
		assert(int(gs.get("day")) == d and str(gs.get("phase")) == "evening", "時間同步錯誤 (evening)")
		_execute_evening_phase(gs, data_node, d)
		gs.advance_phase()

		# 第 45 天 evening 推進後已自動呼叫 end_run()，不進第 45 夜
		if d == 45:
			break

		# 4. Night
		assert(int(gs.get("day")) == d and str(gs.get("phase")) == "night", "時間同步錯誤 (night)")
		_execute_night_phase(gs, data_node, d)
		gs.advance_phase()

	# ── 驗收迴圈重置狀態 ──
	print("=== 45 天走查完畢，驗收重置狀態 ===")

	var failed := 0

	if _run_ended_count != 1:
		push_error("FAIL: run_ended 發射次數不為 1（實際為 %d）" % _run_ended_count)
		failed += 1
	else:
		print("  ok  run_ended 恰好發射 1 次 (ending_id: %s)" % _last_ending_id)

	if int(gs.get("day")) != 1 or str(gs.get("phase")) != "morning":
		push_error("FAIL: 迴圈重置後時間不為第 1 天 morning (實際: 第 %d 天 %s)" % [int(gs.get("day")), str(gs.get("phase"))])
		failed += 1
	else:
		print("  ok  重置後時間為第 1 天 morning")

	var hand: Array = gs.get("hand") as Array
	if hand.size() != 1 or hand[0] != "protagonist":
		push_error("FAIL: 重置後手牌不為 [protagonist] (實際: %s)" % str(hand))
		failed += 1
	else:
		print("  ok  重置後手牌只剩主角卡")

	var knowledge: Dictionary = gs.get("knowledge") as Dictionary
	if not knowledge.has("k_not_today"):
		push_error("FAIL: 重置後知識卡 k_not_today 未保留")
		failed += 1
	else:
		print("  ok  重置後 meta 層知識卡已完整保留 (%d 張知識卡)" % knowledge.size())

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

	if failed > 0:
		push_error("playthrough_greedy: %d assertion(s) failed" % failed)
		quit(1)
	else:
		print("=== 45 天貪心走查測試全部通過 (總行動數: %d) ===" % actions_taken)
		quit(0)


func _on_run_ended(ending_id: String) -> void:
	_run_ended_count += 1
	_last_ending_id = ending_id


func _execute_action_phase(gs: Node, data_node: Node, day: int, phase: String) -> int:
	var locs := PanelBuilder.available_locations(gs, data_node)
	var placed := false

	# 先打開所有可用地點（結算 fixed beat 之 on_enter）
	for loc_id in locs:
		gs.open_panel(loc_id)

	# 貪心尋找第一個可放主角卡的 OPEN 槽
	for loc_id in locs:
		var view: Dictionary = PanelBuilder.build(loc_id, gs, data_node)
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
						break
			if placed:
				break
		if placed:
			break

	return 1 if placed else 0


func _execute_evening_phase(gs: Node, data_node: Node, day: int) -> void:
	# 結算 evening fixed beats
	var loader: DataLoader = data_node.get("loader") as DataLoader
	for b in loader.beats_at(day, "evening"):
		if b.get("fixed", false):
			gs.enter_beat(str(b.get("id", "")))

	# 第 45 天 evening 特殊比對槽處理
	if day == 45:
		if gs.has_card("info_registry"):
			gs.try_place("info_registry", "d45_then", "compare_registry")


func _execute_night_phase(gs: Node, data_node: Node, day: int) -> void:
	# 入夜 fixed beat 自動結算
	var loader: DataLoader = data_node.get("loader") as DataLoader
	for b in loader.beats_at(day, "night"):
		if b.get("fixed", false):
			gs.enter_beat(str(b.get("id", "")))

	# 直接睡
	gs.sleep_night()


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
