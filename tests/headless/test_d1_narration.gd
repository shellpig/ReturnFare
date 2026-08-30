extends SceneTree

## 第 1 天上午／下午純演出時段測試。
## 涵蓋：開局落地即結算 D1 morning 的 auto_enter beat（不必等換時段）、
## 電話演出只在 `return_missed_call` 開局出現、D1 下午由 advance_phase() 結算、
## 純演出時段的地圖清單為空且 D2 上午恢復、
## 重複進場只重播文字不重複結算、`DataFacts` 名單與資料實況一致。
## 跑法：Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/test_d1_narration.gd

const PlaythroughGreedy := preload("res://tests/headless/playthrough_greedy.gd")
const PanelBuilder := preload("res://scripts/core/panel_builder.gd")
const DataFacts := preload("res://scripts/core/data_facts.gd")

var _failed := 0


func _initialize() -> void:
	var data_node: Node = PlaythroughGreedy.setup_data(self)
	await process_frame
	var gs: Node = PlaythroughGreedy.setup_game_state(self, data_node)

	if not bool(data_node.get("ok")):
		push_error("D1 演出：Data 載入失敗，中止")
		quit(1)
		return

	print("=== 第 1 天純演出時段測試 ===")
	_test_1_data_shape(data_node)
	_test_2_album_opening(gs, data_node)
	_test_3_phone_opening(gs, data_node)
	_test_4_map_empty_then_restored(gs, data_node)
	_test_5_afternoon_settles_on_advance(gs)
	_test_6_on_enter_settles_once(gs)

	if _failed > 0:
		push_error("test_d1_narration: %d 個斷言失敗" % _failed)
		quit(1)
	else:
		print("\n=== 第 1 天純演出時段測試全部通過 ===")
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


func _fresh_opening(gs: Node) -> void:
	gs.call("_reset_run_state")
	(gs.get("active_ending") as Dictionary).clear()
	gs.set("flow_mode", "opening")
	gs.set("run_number", 1)
	gs.set("ending_history", [] as Array[Dictionary])
	(gs.get("knowledge") as Dictionary).clear()


func _entered_ids(gs: Node) -> Array[String]:
	var out: Array[String] = []
	for k: String in (gs.get("beats_entered") as Dictionary).keys():
		out.append(k)
	out.sort()
	return out


func _beat_by_id(data_node: Node, beat_id: String) -> Dictionary:
	for b in data_node.loader.beats:
		if str(b.get("id", "")) == beat_id:
			return b
	return {}


# ── 1. 資料形狀 ──────────────────────────────────────────────────────────────

## 關掉地圖不可以順手關掉玩家該做的事。純演出時段允許常駐 beat 一起落在這裡
## （`indulgence_exits.json` 六個出口的 `day_from` 是 1，但它們 `madness_at_least:1`，
## 而第一張發狂卡最早第 3 夜才有，所以第 1 天不會成立），但**不得有任何收主角卡的槽**
## ——真有那種槽，玩家就會遇到「這個時段有東西要放卡，可是進不去」的死局。
func _test_1_data_shape(data_node: Node) -> void:
	print("\n[1] 純演出時段的資料形狀")
	_check(not DataFacts.NARRATION_ONLY_PHASES.is_empty(), "純演出名單非空（否則以下斷言全部恆真）")
	for entry in DataFacts.NARRATION_ONLY_PHASES:
		var d := int(entry.get("day", -1))
		var p := str(entry.get("phase", ""))
		var auto_count := 0
		var protagonist_slots: PackedStringArray = []
		for b in data_node.loader.beats_at(d, p):
			var bid := str(b.get("id", ""))
			if bool(b.get("fixed", false)) and bool(b.get("auto_enter", false)):
				auto_count += 1
				_check((b.get("slots", []) as Array).is_empty(), "%s 是演出，無任何槽" % bid)
				continue
			for s: Dictionary in (b.get("slots", []) as Array):
				if (s.get("accepts", []) as Array).has("protagonist"):
					protagonist_slots.append("%s.%s" % [bid, str(s.get("id", ""))])
		_check(auto_count > 0, "第 %d 天 %s 有 auto_enter 演出 beat（%d 個）" % [d, p, auto_count])
		_check(protagonist_slots.is_empty(),
			"第 %d 天 %s 沒有進不去的主角卡槽，實得 %s" % [d, p, str(protagonist_slots)])
		# 兩份名單不得重疊：一個時段不可能既「完全沒有 beat」又「有演出 beat」。
		_check(not DataFacts.is_empty_phase_by_design(d, p),
			"第 %d 天 %s 不在刻意留空名單（已經有內容了）" % [d, p])
		_check(DataFacts.is_narration_only_phase(d, p), "第 %d 天 %s 查得到純演出判定" % [d, p])


# ── 2. 相簿開局 ──────────────────────────────────────────────────────────────

func _test_2_album_opening(gs: Node, data_node: Node) -> void:
	print("\n[2] 相簿開局：D1 上午在落地當下就播完")
	_fresh_opening(gs)
	var res: Dictionary = gs.call("choose_opening", "take_family_album")
	_check(bool(res.get("ok", false)), "choose_opening(take_family_album) 成功")
	_check(int(gs.get("day")) == 1 and str(gs.get("phase")) == "morning", "落在第 1 天 morning")

	# 關鍵：不必等 advance_phase()，開局落地就要有演出文字。
	var lines: PackedStringArray = gs.get("last_auto_enter_lines")
	_check(lines.size() > 0, "落地即有進場演出文字（%d 行）" % lines.size())

	var expected: Array[String] = ["d1_morning_departure"]
	_check(_entered_ids(gs) == expected,
		"beats_entered 恰為 %s，實得 %s" % [str(expected), str(_entered_ids(gs))])

	# 電話那條的 condition 不成立，一個字都不該出現。
	var joined := "\n".join(lines)
	var phone_text := str(_beat_by_id(data_node, "d1_morning_phone").get("text", ""))
	_check(not phone_text.is_empty(), "d1_morning_phone 資料存在（否則下一條斷言恆真）")
	_check(not joined.contains(phone_text), "相簿開局不播電話演出")


# ── 3. 電話開局 ──────────────────────────────────────────────────────────────

func _test_3_phone_opening(gs: Node, data_node: Node) -> void:
	print("\n[3] 電話開局：多播一段電話，且順序在出城之前")
	_fresh_opening(gs)
	var res: Dictionary = gs.call("choose_opening", "return_missed_call")
	_check(bool(res.get("ok", false)), "choose_opening(return_missed_call) 成功")

	var expected: Array[String] = ["d1_morning_departure", "d1_morning_phone"]
	expected.sort()
	_check(_entered_ids(gs) == expected,
		"beats_entered 恰為 %s，實得 %s" % [str(expected), str(_entered_ids(gs))])

	var joined := "\n".join(gs.get("last_auto_enter_lines") as PackedStringArray)
	var phone_text := str(_beat_by_id(data_node, "d1_morning_phone").get("text", ""))
	var depart_text := str(_beat_by_id(data_node, "d1_morning_departure").get("text", ""))
	_check(joined.contains(phone_text), "電話開局播出電話演出")
	_check(joined.contains(depart_text), "電話開局同樣播出出城演出")
	_check(joined.find(phone_text) < joined.find(depart_text), "電話排在出城之前（資料陣列順序）")

	# 這段演出不取代 on_select：開局旗標仍照 opening_choices.json 寫入。
	_check(bool((gs.get("flags") as Dictionary).get("outside_job_waiting", false)),
		"outside_job_waiting 仍由 on_select 寫入")


# ── 4. 地圖 ──────────────────────────────────────────────────────────────────

func _test_4_map_empty_then_restored(gs: Node, data_node: Node) -> void:
	print("\n[4] 純演出時段無地圖，離開之後恢復")
	_fresh_opening(gs)
	gs.call("choose_opening", "take_family_album")

	_check(PanelBuilder.available_locations(gs, data_node).is_empty(), "D1 morning 地圖清單為空")
	gs.call("advance_phase")
	_check(str(gs.get("phase")) == "afternoon", "推進到 D1 afternoon")
	_check(PanelBuilder.available_locations(gs, data_node).is_empty(), "D1 afternoon 地圖清單為空")

	# D2 morning 是正常行動時段，地圖必須回來——否則上面兩條可能只是地圖整個壞了。
	gs.call("advance_phase")   # evening
	gs.call("advance_phase")   # night
	gs.call("advance_phase")   # D2 morning
	_check(int(gs.get("day")) == 2 and str(gs.get("phase")) == "morning", "推進到第 2 天 morning")
	_check(not PanelBuilder.available_locations(gs, data_node).is_empty(), "D2 morning 地圖清單恢復")


# ── 5. 下午 ──────────────────────────────────────────────────────────────────

func _test_5_afternoon_settles_on_advance(gs: Node) -> void:
	print("\n[5] D1 下午由 advance_phase() 結算")
	_fresh_opening(gs)
	gs.call("choose_opening", "take_family_album")
	var before := _entered_ids(gs)

	var res: Dictionary = gs.call("advance_phase")
	_check(bool(res.get("ok", false)) and bool(res.get("phase_advanced", false)), "advance_phase 進到下午")
	var lines: PackedStringArray = gs.get("last_auto_enter_lines")
	_check(lines.size() > 0, "下午有進場演出文字（%d 行）" % lines.size())
	_check(_entered_ids(gs).size() == before.size() + 1, "下午恰多結算一個 beat")
	_check(_entered_ids(gs).has("d1_pm_mountain_road"), "結算的是 d1_pm_mountain_road")

	# 上午那幾行不該還掛在 transient 上（換時段時 clear 過）。
	_check(not "\n".join(lines).contains("客運出城"), "換時段後不重播上午的文字")


# ── 6. 一次性 ────────────────────────────────────────────────────────────────

## `play_beat()` 的 on_enter 只結算一次。這幾個 beat 目前沒有 on_enter 效果，
## 但 beats_entered 的一次性仍必須成立，否則之後給它們加效果就會重複套。
func _test_6_on_enter_settles_once(gs: Node) -> void:
	print("\n[6] 重複進場不重複結算")
	_fresh_opening(gs)
	gs.call("choose_opening", "take_family_album")
	var first := _entered_ids(gs)

	var replay: PackedStringArray = gs.call("play_beat", "d1_morning_departure")
	_check(replay.size() > 0, "再次 play_beat 仍重播文字")
	_check(_entered_ids(gs) == first, "beats_entered 沒有變化")
