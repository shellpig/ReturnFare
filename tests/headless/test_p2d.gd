extends SceneTree

## P2-D headless 驗收測試：視野門檻與發瘋 BE（madness_at_least 真資料求值與顯隱、madness_cap 即時 BE、收尾狀態重置、批次發卡單次結束、正式資料第一輪不觸發 BE）。
## 跑法：
##   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/test_p2d.gd
## 全綠 exit 0；任一失敗 exit 1。

const ConditionEval := preload("res://scripts/core/condition_eval.gd")
const PanelBuilder := preload("res://scripts/core/panel_builder.gd")
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
		push_error("P2-D: Data failed to load; abort")
		quit(1)
		return

	var failed := 0
	failed += _test_vision_threshold_visibility(gs, data_node)
	failed += _test_madness_cap_triggers_be(gs, data_node)
	failed += await _test_be_flow_text_display()
	failed += _test_state_reset_after_be(gs, data_node)
	failed += _test_single_run_ended_emission_on_batch_gain(gs, data_node)
	failed += _test_real_data_cap_unreached_in_run1(gs, data_node)

	if data_created:
		Engine.unregister_singleton("Data")
	if gs_created:
		Engine.unregister_singleton("GameState")

	if failed > 0:
		push_error("P2-D: %d test(s) failed" % failed)
		quit(1)
	else:
		print("P2-D: all tests passed")
		quit(0)


func _ok(msg: String) -> int:
	print("  ok  " + msg)
	return 0


func _fail(msg: String) -> int:
	push_error("  FAIL  " + msg)
	return 1


# ── 1. 視野門檻顯隱測試（madness_at_least） ─────────────────────────────────────

func _test_vision_threshold_visibility(gs: Node, data_node: Node) -> int:
	print("--- 1. vision threshold visibility (madness_at_least) ---")
	var failed := 0
	gs.call("end_run")

	# 合成測試用 beat，掛 condition: { "madness_at_least": 3 }
	var test_beat_id := "test_beat_vision_threshold"
	var test_slot_id := "test_slot_vision"
	var test_beat: Dictionary = {
		"id": test_beat_id,
		"when": { "day": 8, "phase": "morning" },
		"location": "sanquan_lobby",
		"title": "深層幻視",
		"condition": { "madness_at_least": 3 },
		"slots": [
			{
				"id": test_slot_id,
				"name": "窺視",
				"accepts": ["protagonist"],
				"on_place": { "text": "你看見了不該看見的景象。" }
			}
		]
	}

	var loader: DataLoader = data_node.get("loader")
	loader.beats.append(test_beat)
	loader.beats_by_id[test_beat_id] = test_beat

	gs.set("day", 8)
	gs.set("phase", "morning")

	# (a) 手牌 0 張發狂卡：求值 false、PanelBuilder 視圖中該 beat 不出現（HIDDEN）
	if ConditionEval.eval(test_beat["condition"], gs):
		failed += _fail("0 張發狂卡時 madness_at_least: 3 應為 false")
	else:
		failed += _ok("0 張發狂卡時 madness_at_least: 3 為 false")

	var panel_0: Dictionary = PanelBuilder.build("sanquan_lobby", gs, data_node)
	var beats_0: Array = panel_0.get("beats", []) as Array
	var found_0 := false
	for item: Dictionary in beats_0:
		var b: Dictionary = item.get("beat", {}) as Dictionary
		if b.get("id") == test_beat_id:
			found_0 = true
			break
	if not found_0:
		failed += _ok("0 張發狂卡時掛門檻的 beat 不在面板中（HIDDEN）")
	else:
		failed += _fail("0 張發狂卡時掛門檻的 beat 不應出現於面板中")

	# (b) 手牌獲得 2 張發狂卡：求值仍為 false
	gs.call("gain_card", "madness")
	gs.call("gain_card", "madness")
	if ConditionEval.eval(test_beat["condition"], gs):
		failed += _fail("2 張發狂卡時 madness_at_least: 3 應為 false")
	else:
		failed += _ok("2 張發狂卡時 madness_at_least: 3 為 false")

	var panel_2: Dictionary = PanelBuilder.build("sanquan_lobby", gs, data_node)
	var beats_2: Array = panel_2.get("beats", []) as Array
	var found_2 := false
	for item: Dictionary in beats_2:
		var b: Dictionary = item.get("beat", {}) as Dictionary
		if b.get("id") == test_beat_id:
			found_2 = true
			break
	if not found_2:
		failed += _ok("2 張發狂卡時掛門檻的 beat 依然不出現（HIDDEN，不是灰掉）")
	else:
		failed += _fail("2 張發狂卡時掛門檻的 beat 不應出現")

	# (c) 手牌獲得第 3 張發狂卡（達到門檻 3）：求值 true、面板出現該 beat 且狀態為 OPEN
	gs.call("gain_card", "madness")
	if not ConditionEval.eval(test_beat["condition"], gs):
		failed += _fail("3 張發狂卡時 madness_at_least: 3 應為 true")
	else:
		failed += _ok("3 張發狂卡時 madness_at_least: 3 為 true")

	var panel_3: Dictionary = PanelBuilder.build("sanquan_lobby", gs, data_node)
	var beats_3: Array = panel_3.get("beats", []) as Array
	var found_beat_item: Dictionary = {}
	for item: Dictionary in beats_3:
		var b: Dictionary = item.get("beat", {}) as Dictionary
		if b.get("id") == test_beat_id:
			found_beat_item = item
			break
	if not found_beat_item.is_empty() and int(found_beat_item.get("tri", -1)) == PanelBuilder.TriState.OPEN:
		failed += _ok("3 張發狂卡時掛門檻的 beat 正確出現且為 OPEN")
	else:
		failed += _fail("3 張發狂卡時掛門檻的 beat 未出現或狀態非 OPEN (beat=%s)" % str(found_beat_item))

	# (d) 清掉一張發狂卡（降回 2 張）：求值再次變為 false、面板重新隱藏該 beat
	gs.call("lose_card", "madness#1")
	if ConditionEval.eval(test_beat["condition"], gs):
		failed += _fail("清掉 1 張降至 2 張後 madness_at_least: 3 應為 false")
	else:
		failed += _ok("清掉 1 張降至 2 張後 madness_at_least: 3 恢復為 false")

	var panel_after_lose: Dictionary = PanelBuilder.build("sanquan_lobby", gs, data_node)
	var beats_after: Array = panel_after_lose.get("beats", []) as Array
	var found_after := false
	for item: Dictionary in beats_after:
		var b: Dictionary = item.get("beat", {}) as Dictionary
		if b.get("id") == test_beat_id:
			found_after = true
			break
	if not found_after:
		failed += _ok("降至 2 張後掛門檻的 beat 再次消失（動態求值）")
	else:
		failed += _fail("降至 2 張後掛門檻的 beat 應再次隱藏")

	# 清理合成資料
	loader.beats.erase(test_beat)
	loader.beats_by_id.erase(test_beat_id)

	# (e) 真資料驗證（K-64）：ch2_nights.json 颱風夜 d23_night_bleed (madness_at_least: 3)
	gs.call("end_run")
	gs.set("day", 23)
	gs.set("phase", "night")
	var d23_beat: Dictionary = loader.beats_by_id.get("d23_night_bleed", {})
	if d23_beat.is_empty():
		failed += _fail("真資料未找到 d23_night_bleed")
	else:
		if ConditionEval.eval(d23_beat.get("condition"), gs):
			failed += _fail("0 張發狂卡且未防颱時 d23_night_bleed 應為 false")
		else:
			failed += _ok("0 張發狂卡時真資料 d23_night_bleed 為 false")

		gs.call("gain_card", "madness")
		gs.call("gain_card", "madness")
		if ConditionEval.eval(d23_beat.get("condition"), gs):
			failed += _fail("2 張發狂卡時真資料 d23_night_bleed 應為 false")
		else:
			failed += _ok("2 張發狂卡時真資料 d23_night_bleed 仍為 false")

		gs.call("gain_card", "madness")
		if not ConditionEval.eval(d23_beat.get("condition"), gs):
			failed += _fail("3 張發狂卡時真資料 d23_night_bleed 應為 true")
		else:
			failed += _ok("3 張發狂卡時真資料 d23_night_bleed 成功解鎖為 true (K-64)")

		gs.call("lose_card", "madness#1")
		if ConditionEval.eval(d23_beat.get("condition"), gs):
			failed += _fail("降至 2 張後真資料 d23_night_bleed 應恢復為 false")
		else:
			failed += _ok("降至 2 張後真資料 d23_night_bleed 重新關閉為 false")

	# (f) 真資料驗證（K-64）：ch2_nights.json d24_night_bleed (boundary_bleeding + madness_at_least: 3)
	gs.call("end_run")
	gs.set("day", 24)
	gs.set("phase", "night")
	gs.call("set_flag", "boundary_bleeding", true)
	var d24_beat: Dictionary = loader.beats_by_id.get("d24_night_bleed", {})
	if d24_beat.is_empty():
		failed += _fail("真資料未找到 d24_night_bleed")
	else:
		gs.call("gain_card", "madness")
		gs.call("gain_card", "madness")
		if ConditionEval.eval(d24_beat.get("condition"), gs):
			failed += _fail("2 張發狂卡時真資料 d24_night_bleed 應為 false")
		else:
			failed += _ok("2 張發狂卡時真資料 d24_night_bleed 仍為 false")

		gs.call("gain_card", "madness")
		if not ConditionEval.eval(d24_beat.get("condition"), gs):
			failed += _fail("3 張發狂卡時真資料 d24_night_bleed 應為 true")
		else:
			failed += _ok("3 張發狂卡時真資料 d24_night_bleed 成功解鎖為 true (K-64)")

	# (g) 真資料驗證（K-64）：indulgence_exits.json exit_sanquan (madness_at_least: 1)
	gs.call("end_run")
	gs.set("day", 1)
	gs.set("phase", "morning")
	var exit_beat: Dictionary = loader.beats_by_id.get("exit_sanquan", {})
	if exit_beat.is_empty():
		failed += _fail("真資料未找到 exit_sanquan")
	else:
		if ConditionEval.eval(exit_beat.get("condition"), gs):
			failed += _fail("0 張發狂卡時 exit_sanquan 應為 false")
		else:
			failed += _ok("0 張發狂卡時 exit_sanquan condition 為 false")

		gs.call("gain_card", "madness")
		if not ConditionEval.eval(exit_beat.get("condition"), gs):
			failed += _fail("1 張發狂卡時 exit_sanquan 應為 true")
		else:
			failed += _ok("1 張發狂卡時 exit_sanquan condition 成功解鎖為 true (K-64)")

	return failed


# ── 2. madness_cap 觸發發瘋 BE ──────────────────────────────────────────────

func _test_madness_cap_triggers_be(gs: Node, data_node: Node) -> int:
	print("--- 2. madness_cap triggers madness BE immediately ---")
	var failed := 0
	gs.call("end_run")

	var loader: DataLoader = data_node.get("loader")
	var orig_cap = loader.tuning["madness_cap"]
	loader.tuning["madness_cap"] = 2

	var endings_received: Array[String] = []
	var on_run_ended := func(eid: String) -> void:
		endings_received.append(eid)
	gs.connect("run_ended", on_run_ended)

	# 拿第 1 張卡：未達 cap (1/2)
	gs.call("gain_card", "madness")
	if endings_received.is_empty():
		failed += _ok("持有 1/2 張發狂卡時未觸發 BE")
	else:
		failed += _fail("持有 1/2 張發狂卡時不應觸發 BE")

	# 拿第 2 張卡：達到 cap (2/2) -> 即刻觸發 ending_madness_be
	gs.call("gain_card", "madness")
	if endings_received.size() == 1 and endings_received[0] == "ending_madness_be":
		failed += _ok("達到 cap 2 時立即觸發 ending_madness_be")
	else:
		failed += _fail("達到 cap 2 時未正確觸發 BE (received=%s)" % str(endings_received))

	gs.disconnect("run_ended", on_run_ended)
	loader.tuning["madness_cap"] = orig_cap
	return failed


# ── 3. 發瘋 BE 演出文字展示 ──────────────────────────────────────────────────

func _test_be_flow_text_display() -> int:
	print("--- 3. madness BE display branches in main scene (K-67) ---")
	var failed := 0

	var gs: Node = get_root().get_node_or_null("GameState")
	var data_node: Node = get_root().get_node_or_null("Data")
	var loader: DataLoader = data_node.get("loader")
	var orig_cap = loader.tuning["madness_cap"]

	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var main: Control = main_scene.instantiate()
	get_root().add_child(main)
	await process_frame

	# 觸發一般結局（透過 GameState 發射 run_ended）
	gs.call("end_run", "ending_default")
	await process_frame
	var flow_text: FlowText = main.get_node("ContentView/FlowText")
	var text_default := flow_text.get_text() if flow_text.has_method("get_text") else ""
	if text_default.is_empty() and flow_text.has_node("ScrollContainer/TextLabel"):
		text_default = (flow_text.get_node("ScrollContainer/TextLabel") as RichTextLabel).text

	if "[結局 stub]" in text_default:
		failed += _ok("一般結局訊號發射後顯示 [結局 stub]")
	else:
		failed += _fail("一般結局未顯示 [結局 stub] (text=%s)" % text_default)

	# 透過真實規則層入口發卡衝破 cap 觸發發瘋 BE（K-67：驗證 GameState.run_ended 訊號接線）
	loader.tuning["madness_cap"] = 2
	gs.call("gain_card", "madness")
	gs.call("gain_card", "madness")
	await process_frame

	var text_be := flow_text.get_text() if flow_text.has_method("get_text") else ""
	if text_be.is_empty() and flow_text.has_node("ScrollContainer/TextLabel"):
		text_be = (flow_text.get_node("ScrollContainer/TextLabel") as RichTextLabel).text

	if "[發瘋 BE]" in text_be and not ("[結局 stub]" in text_be):
		failed += _ok("真實發卡達 cap 觸發發瘋 BE，經由訊號接線顯示 [發瘋 BE] 且不播一般結局骨架 (K-67)")
	else:
		failed += _fail("發瘋 BE 文本展示錯誤 (text=%s)" % text_be)

	loader.tuning["madness_cap"] = orig_cap
	main.queue_free()
	await process_frame
	return failed


# ── 4. 發瘋 BE 後回到第 1 天 morning 與狀態重置 ─────────────────────────────

func _test_state_reset_after_be(gs: Node, data_node: Node) -> int:
	print("--- 4. state reset after madness BE ---")
	var failed := 0
	gs.call("end_run")

	# 設置一些 run 層與 meta 層狀態
	gs.set("day", 15)
	gs.set("phase", "afternoon")
	gs.call("gain_card", "k_forty_something") # 知識卡（meta 層）
	gs.call("set_flag", "test_flag", true)
	gs.call("open_switch", "sw_test")
	gs.call("add_relation", "npc_ahong", 2)

	var loader: DataLoader = data_node.get("loader")
	var orig_cap = loader.tuning["madness_cap"]
	loader.tuning["madness_cap"] = 2

	# 獲得 2 張發狂卡以觸發 BE
	gs.call("gain_card", "madness")
	gs.call("gain_card", "madness")

	var cur_day: int = gs.get("day")
	var cur_phase: String = gs.get("phase")
	var hand: Array = gs.get("hand")
	var knowledge: Dictionary = gs.get("knowledge")
	var flags: Dictionary = gs.get("flags")
	var switches: Dictionary = gs.get("switches")
	var relations: Dictionary = gs.get("relations")
	var clock: Dictionary = gs.get("madness_clock")

	# P5-B：撞 cap 改為啟動 ending_madness_be，run 當下不清空；正式結算在 P5-D。
	if cur_day == 15 and cur_phase == "afternoon":
		failed += _ok("BE 啟動後 day／phase 不動")
	else:
		failed += _fail("BE 啟動後時間不應改變 (day=%d, phase=%s)" % [cur_day, cur_phase])

	if str(gs.get("flow_mode")) == "ending" and str((gs.get("active_ending") as Dictionary).get("ending_id", "")) == "ending_madness_be":
		failed += _ok("BE 啟動後進入 ending mode 且 ending_id 為 ending_madness_be")
	else:
		failed += _fail("BE 啟動後 flow 狀態異常 (mode=%s)" % str(gs.get("flow_mode")))

	if hand.size() == 3 and not clock.is_empty():
		failed += _ok("BE 啟動後 run 尚未清空（手牌與發狂錶保留給結局快照）")
	else:
		failed += _fail("BE 啟動後 run 不應被清空 (hand=%s)" % str(hand))

	# legacy end_run 收尾（P5-D 由 complete_ending() 取代）後才做跨輪重置驗收
	gs.call("end_run", "ending_madness_be")
	var hand_reset: Array = gs.get("hand")
	var knowledge_reset: Dictionary = gs.get("knowledge")
	var flags_reset: Dictionary = gs.get("flags")
	var switches_reset: Dictionary = gs.get("switches")
	var relations_reset: Dictionary = gs.get("relations")
	var clock_reset: Dictionary = gs.get("madness_clock")

	if int(gs.get("day")) == 1 and str(gs.get("phase")) == "morning":
		failed += _ok("legacy end_run 後回到第 1 天 morning")
	else:
		failed += _fail("legacy end_run 後時間未重置為 D1 morning (day=%d, phase=%s)" % [int(gs.get("day")), str(gs.get("phase"))])

	if hand_reset == ["protagonist"]:
		failed += _ok("重置後手牌只剩主角卡")
	else:
		failed += _fail("重置後手牌未正確重置 (hand=%s)" % str(hand_reset))

	if knowledge_reset.has("k_forty_something"):
		failed += _ok("重置後知識卡跨輪完整保留")
	else:
		failed += _fail("重置後知識卡丟失 (knowledge=%s)" % str(knowledge_reset))

	if flags_reset.is_empty() and switches_reset.is_empty() and relations_reset.is_empty() and clock_reset.is_empty():
		failed += _ok("重置後 flags / switches / relations / madness_clock 等 run 層狀態已清空")
	else:
		failed += _fail("重置後 run 層狀態未完全清空")

	if str(gs.get("flow_mode")) == "run" and (gs.get("active_ending") as Dictionary).is_empty():
		failed += _ok("重置後 flow 回到 run 且 active_ending 為 null")
	else:
		failed += _fail("重置後 flow 層未歸位 (mode=%s)" % str(gs.get("flow_mode")))

	loader.tuning["madness_cap"] = orig_cap
	return failed


# ── 5. 批次發卡衝破 cap 時 run_ended 恰好發射一次且無重置污染 ────────────────

func _test_single_run_ended_emission_on_batch_gain(gs: Node, data_node: Node) -> int:
	print("--- 5. batch gain over cap emits run_ended exactly once ---")
	var failed := 0
	gs.call("end_run")

	var loader: DataLoader = data_node.get("loader")
	var orig_cap = loader.tuning["madness_cap"]
	loader.tuning["madness_cap"] = 2

	# 設置一個 madness_cost = 3 的夜間收費地點
	var test_loc_id := "test_loc_heavy_cost"
	var test_loc: Dictionary = {
		"id": test_loc_id,
		"name": "測試收費標記",
		"layer": "night",
		"time": "night",
		"earliest_night": 1,
		"madness_cost": 3
	}
	loader.locations[test_loc_id] = test_loc

	var emitted_endings: Array[String] = []
	var on_run_ended := func(eid: String) -> void:
		emitted_endings.append(eid)
	gs.connect("run_ended", on_run_ended)

	# 手上原本有 1 張發狂卡
	gs.call("gain_card", "madness")
	gs.set("phase", "night")

	# 一次開 cost=3 的標記（總共衝到 4 張，超過 cap 2）
	gs.call("enter_night_location", test_loc_id)

	if emitted_endings.size() == 1 and emitted_endings == ["ending_madness_be"]:
		failed += _ok("一次發多張衝破 cap 時，run_ended 恰好發射 1 次")
	else:
		failed += _fail("run_ended 發射次數不符 (count=%d, endings=%s)" % [emitted_endings.size(), str(emitted_endings)])

	# P5-B：批次發卡衝破 cap 只啟動一次結局，四張卡都留在快照所描述的這一輪。
	var hand_after: Array = gs.get("hand")
	var clock_after: Dictionary = gs.get("madness_clock")
	if hand_after.size() == 5 and clock_after.size() == 4 and str(gs.get("flow_mode")) == "ending":
		failed += _ok("批次發卡後四張發狂卡都留在本輪，且只啟動一次結局")
	else:
		failed += _fail("批次發卡後狀態異常 (hand=%s, clock=%s, mode=%s)" % [str(hand_after), str(clock_after), str(gs.get("flow_mode"))])

	gs.call("end_run", "ending_madness_be")
	var hand_reset: Array = gs.get("hand")
	if hand_reset == ["protagonist"] and (gs.get("madness_clock") as Dictionary).is_empty():
		failed += _ok("legacy end_run 後手牌為乾淨的 ['protagonist']，後續發卡未污染新一輪")
	else:
		failed += _fail("重置後手牌受後續發卡污染 (hand=%s)" % str(hand_reset))

	gs.disconnect("run_ended", on_run_ended)
	loader.locations.erase(test_loc_id)
	loader.tuning["madness_cap"] = orig_cap
	return failed


# ── 6. 正式資料上第一輪碰不到 BE（K-63）────────────────────────────────────

func _test_real_data_cap_unreached_in_run1(gs: Node, data_node: Node) -> int:
	print("--- 6. real data 45-day playthrough never reaches madness BE (K-63) ---")
	var failed := 0
	gs.call("end_run")

	var res: Dictionary = PlaythroughGreedy.run_greedy_walk(gs, data_node, false)
	if not bool(res.get("ok", false)):
		failed += _fail("45 天貪心走查執行失敗")
	else:
		failed += _ok("45 天貪心走查在正式資料上成功走完")

	var last_ending: String = str(res.get("last_ending_id", ""))
	# P5-B：D45 coda 門檻完成後啟動的是正常替換結局，不再是 P1 的 ending_default stub。
	if last_ending == "ending_replaced" and last_ending != "ending_madness_be":
		failed += _ok("45 天走查結局為 ending_replaced，未觸發 ending_madness_be (K-63)")
	else:
		failed += _fail("走查結局異常 (last_ending_id=%s)" % last_ending)

	var run_ended_cnt: int = int(res.get("run_ended_count", 0))
	if run_ended_cnt == 1:
		failed += _ok("走查全程 run_ended 恰好發射 1 次")
	else:
		failed += _fail("走查全程 run_ended 發射次數不符 (實際: %d)" % run_ended_cnt)

	var final_madness: int = (res.get("final_madness_cards", []) as Array).size()
	var cap: int = int(data_node.call("tuning", "madness_cap"))
	if final_madness < cap:
		failed += _ok("重置前持有發狂卡數 (%d) 低於 tuning.madness_cap (%d)" % [final_madness, cap])
	else:
		failed += _fail("重置前持有發狂卡數 (%d) 達到或超過 cap (%d)" % [final_madness, cap])

	return failed
