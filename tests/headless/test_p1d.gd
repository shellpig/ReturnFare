extends SceneTree

## P1-D headless 驗收測試：EffectApply、GameState.try_place、剩餘四個 condition 運算子
## （switch／switch_progress_at_least／flag／relation_at_least，另九個在 test_p1c.gd）、
## npc_action_counts 投入帳、語彙封閉性 lint。
## 跑法：
##   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/test_p1d.gd
## 全綠 exit 0；任一失敗 exit 1。


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
		push_error("P1-D: Data failed to load; abort")
		quit(1)
		return

	var failed := 0
	failed += _test_condition_switch_flag_relation(gs)
	failed += _test_effect_apply(gs)
	failed += _test_try_place_basic(gs)
	failed += _test_try_place_action_spent(gs)
	failed += _test_try_place_compare_free(gs)
	failed += _test_try_place_rejections(gs)
	failed += _test_attention_npc(gs, data_node)
	failed += _test_serialize_roundtrip(gs)
	failed += _test_lint_vocabulary()

	Engine.unregister_singleton("Data")
	Engine.unregister_singleton("GameState")

	if failed > 0:
		push_error("P1-D: %d test(s) failed" % failed)
		quit(1)
	else:
		print("P1-D: all tests passed")
		quit(0)


func _ok(msg: String) -> int:
	print("  ok  " + msg)
	return 0


func _fail(msg: String) -> int:
	push_error("  FAIL  " + msg)
	return 1


func _reset(gs: Node) -> void:
	(gs.get("hand") as Array).clear()
	(gs.get("knowledge") as Dictionary).clear()
	(gs.get("madness_clock") as Dictionary).clear()
	(gs.get("beats_entered") as Dictionary).clear()
	(gs.get("slots_placed") as Dictionary).clear()
	(gs.get("flags") as Dictionary).clear()
	(gs.get("switches") as Dictionary).clear()
	(gs.get("switch_progress") as Dictionary).clear()
	(gs.get("relations") as Dictionary).clear()
	(gs.get("npc_action_counts") as Dictionary).clear()
	gs.set("_madness_counter", 0)
	gs.set("day", 1)
	gs.set("phase", "morning")
	gs.set("action_spent", false)


# ── 剩餘四個 condition 運算子：switch／switch_progress_at_least／flag／relation_at_least ──

func _test_condition_switch_flag_relation(gs: Node) -> int:
	print("--- condition_eval: switch / switch_progress_at_least / flag / relation_at_least ---")
	_reset(gs)
	var failed := 0

	# switch
	if ConditionEval.eval({ "switch": "s_test" }, gs):
		failed += _fail("switch s_test before open: expected false")
	else:
		failed += _ok("switch s_test before open → false")
	gs.call("open_switch", "s_test")
	if not ConditionEval.eval({ "switch": "s_test" }, gs):
		failed += _fail("switch s_test after open: expected true")
	else:
		failed += _ok("switch s_test after open → true")

	# switch_progress_at_least
	gs.call("add_switch_progress", "s6", 1)
	gs.call("add_switch_progress", "s6", 2)
	if not ConditionEval.eval({ "switch_progress_at_least": { "switch": "s6", "n": 3 } }, gs):
		failed += _fail("switch_progress_at_least s6 n=3 (累計 3): expected true")
	else:
		failed += _ok("switch_progress_at_least s6 n=3 (累計 3) → true")
	if ConditionEval.eval({ "switch_progress_at_least": { "switch": "s6", "n": 4 } }, gs):
		failed += _fail("switch_progress_at_least s6 n=4 (累計 3): expected false")
	else:
		failed += _ok("switch_progress_at_least s6 n=4 (累計 3) → false")

	# flag（含明寫 false）
	gs.call("set_flag", "f_test", true)
	if not ConditionEval.eval({ "flag": "f_test" }, gs):
		failed += _fail("flag f_test after set true: expected true")
	else:
		failed += _ok("flag f_test after set true → true")
	gs.call("set_flag", "f_test", false)
	if ConditionEval.eval({ "flag": "f_test" }, gs):
		failed += _fail("flag f_test after set false: expected false")
	else:
		failed += _ok("flag f_test after set false → false")

	# relation_at_least（讀 data/relation_scale.json：疑似=1、恩人=3）
	gs.call("add_relation", "awei", 1)
	if not ConditionEval.eval({ "relation_at_least": { "npc": "awei", "state": "疑似" } }, gs):
		failed += _fail("relation_at_least awei 疑似 (relation=1): expected true")
	else:
		failed += _ok("relation_at_least awei 疑似 (relation=1) → true")
	if ConditionEval.eval({ "relation_at_least": { "npc": "awei", "state": "恩人" } }, gs):
		failed += _fail("relation_at_least awei 恩人 (relation=1): expected false")
	else:
		failed += _ok("relation_at_least awei 恩人 (relation=1) → false")
	gs.call("add_relation", "awei", 2)
	if not ConditionEval.eval({ "relation_at_least": { "npc": "awei", "state": "恩人" } }, gs):
		failed += _fail("relation_at_least awei 恩人 (relation=3): expected true")
	else:
		failed += _ok("relation_at_least awei 恩人 (relation=3) → true")

	return failed


# ── EffectApply：全部效果鍵各至少落一次帳 ────────────────────────────────────

func _test_effect_apply(gs: Node) -> int:
	print("--- effect_apply ---")
	_reset(gs)
	var failed := 0

	var effect := {
		"text": "測試效果文字",
		"gain": ["info_husband_version"],
		"switch": "s_fx_test",
		"switch_progress": { "s6": 2 },
		"relation": { "npc": "npc_fx_test", "delta": 3 },
		"madness": 2,
		"flag": { "fx_flag_a": true, "fx_flag_b": false },
	}
	var lines: PackedStringArray = EffectApply.apply(effect, gs)

	if not lines.has("測試效果文字"):
		failed += _fail("effect_apply: text line missing")
	else:
		failed += _ok("effect_apply: text line present")
	if not (gs.get("hand") as Array).has("info_husband_version"):
		failed += _fail("effect_apply: gain did not add card to hand")
	else:
		failed += _ok("effect_apply: gain added card to hand")
	if not (gs.get("switches") as Dictionary).get("s_fx_test", false):
		failed += _fail("effect_apply: switch not opened")
	else:
		failed += _ok("effect_apply: switch opened")
	if int((gs.get("switch_progress") as Dictionary).get("s6", 0)) != 2:
		failed += _fail("effect_apply: switch_progress wrong value")
	else:
		failed += _ok("effect_apply: switch_progress = 2")
	if int((gs.get("relations") as Dictionary).get("npc_fx_test", 0)) != 3:
		failed += _fail("effect_apply: relation delta not applied")
	else:
		failed += _ok("effect_apply: relation delta applied (+3)")
	var madness_count := 0
	for c: String in gs.get("hand") as Array:
		if c.begins_with("madness#"):
			madness_count += 1
	if madness_count != 2:
		failed += _fail("effect_apply: madness=2 should add 2 instances, got %d" % madness_count)
	else:
		failed += _ok("effect_apply: madness=2 added 2 instances")
	var flags: Dictionary = gs.get("flags")
	if flags.get("fx_flag_a", false) != true or flags.get("fx_flag_b", true) != false:
		failed += _fail("effect_apply: flag dict values wrong")
	else:
		failed += _ok("effect_apply: flag dict sets both true and false correctly")

	# lose：作用於知識集合
	gs.call("gain_card", "k_forty_something")
	EffectApply.apply({ "lose": ["k_forty_something"] }, gs)
	if (gs.get("knowledge") as Dictionary).has("k_forty_something"):
		failed += _fail("effect_apply: lose did not remove knowledge card")
	else:
		failed += _ok("effect_apply: lose removed knowledge card")

	return failed


# ── try_place：基本成功路徑（d2_pm_work，主角卡吃行動格、on_place 全效果落帳）──

func _test_try_place_basic(gs: Node) -> int:
	print("--- try_place: d2_pm_work basic success ---")
	_reset(gs)
	gs.call("gain_card", "protagonist")
	gs.set("day", 2)
	gs.set("phase", "afternoon")
	var failed := 0

	var result: Dictionary = gs.call("try_place", "protagonist", "d2_pm_work", "work")
	if not result.get("ok", false):
		failed += _fail("try_place d2_pm_work/work: expected ok, got reason_code=" + str(result.get("reason_code")))
		return failed
	failed += _ok("try_place d2_pm_work/work → ok")

	if not (gs.get("hand") as Array).has("info_husband_version") or not (gs.get("hand") as Array).has("info_wife_version"):
		failed += _fail("try_place: on_place gain (2 info cards) not applied")
	else:
		failed += _ok("try_place: on_place gain applied (2 info cards)")

	if not (gs.get("slots_placed") as Dictionary).has("d2_pm_work::work"):
		failed += _fail("try_place: slots_placed missing key")
	else:
		failed += _ok("try_place: slots_placed recorded")

	if not gs.get("action_spent"):
		failed += _fail("try_place: protagonist in action phase should consume action_spent")
	else:
		failed += _ok("try_place: action_spent = true")

	# 同一槽重放：resolved，GameState 零變化
	var hand_size_before: int = (gs.get("hand") as Array).size()
	var retry: Dictionary = gs.call("try_place", "protagonist", "d2_pm_work", "work")
	if retry.get("ok", false) or str(retry.get("reason_code")) != "resolved":
		failed += _fail("try_place retry on resolved slot: expected ok=false reason_code=resolved, got %s" % str(retry))
	else:
		failed += _ok("try_place retry on resolved slot → ok=false reason_code=resolved")
	if (gs.get("hand") as Array).size() != hand_size_before:
		failed += _fail("try_place retry on resolved slot: hand size changed (should be zero-change)")
	else:
		failed += _ok("try_place retry on resolved slot: hand unchanged")

	return failed


# ── try_place：同一時段第二次放主角卡 → action_spent 擋下 ──────────────────

func _test_try_place_action_spent(gs: Node) -> int:
	print("--- try_place: same-phase second protagonist blocked ---")
	_reset(gs)
	gs.call("gain_card", "protagonist")
	gs.set("day", 3)
	gs.set("phase", "afternoon")
	var failed := 0

	var first: Dictionary = gs.call("try_place", "protagonist", "d3_pm_sanquan", "soak")
	if not first.get("ok", false):
		failed += _fail("try_place d3_pm_sanquan/soak: expected ok, got " + str(first))
		return failed
	failed += _ok("try_place d3_pm_sanquan/soak → ok (first placement this phase)")

	var second: Dictionary = gs.call("try_place", "protagonist", "d3_pm_sanquan", "ledger")
	if second.get("ok", false) or str(second.get("reason_code")) != "action_spent":
		failed += _fail("try_place d3_pm_sanquan/ledger: expected ok=false reason_code=action_spent, got %s" % str(second))
	else:
		failed += _ok("try_place d3_pm_sanquan/ledger → ok=false reason_code=action_spent")

	if (gs.get("slots_placed") as Dictionary).has("d3_pm_sanquan::ledger"):
		failed += _fail("try_place: rejected placement should not write slots_placed")
	else:
		failed += _ok("try_place: rejected placement left slots_placed unchanged")
	if (gs.get("switches") as Dictionary).has("s1"):
		failed += _fail("try_place: rejected placement should not run on_place (switch s1 leaked)")
	else:
		failed += _ok("try_place: rejected placement did not run on_place")

	return failed


# ── try_place：比對槽（不收主角卡）不吃行動格 ──────────────────────────────

func _test_try_place_compare_free(gs: Node) -> int:
	print("--- try_place: compare slot does not consume action ---")
	_reset(gs)
	gs.call("gain_card", "protagonist")
	gs.call("gain_card", "info_husband_version")
	gs.set("day", 3)
	gs.set("phase", "afternoon")
	var failed := 0

	var cmp: Dictionary = gs.call("try_place", "info_husband_version", "d3_pm_sanquan", "show_version")
	if not cmp.get("ok", false):
		failed += _fail("try_place show_version (compare): expected ok, got " + str(cmp))
		return failed
	failed += _ok("try_place show_version (compare) → ok")

	if gs.get("action_spent"):
		failed += _fail("try_place: compare slot should not consume action_spent")
	else:
		failed += _ok("try_place: compare slot did not consume action_spent")

	# 免費槽用完，主角卡仍可放進同面板的行動格
	var later: Dictionary = gs.call("try_place", "protagonist", "d3_pm_sanquan", "ledger")
	if not later.get("ok", false):
		failed += _fail("try_place ledger after compare: expected ok, got " + str(later))
	else:
		failed += _ok("try_place ledger after compare → ok (compare did not spend the phase)")
	if not gs.get("action_spent"):
		failed += _fail("try_place: protagonist placement after compare should now consume action_spent")
	else:
		failed += _ok("try_place: action_spent = true after protagonist placement")

	return failed


# ── try_place：拒絕路徑（not_held／not_accepted／unknown_beat／unknown_slot）─

func _test_try_place_rejections(gs: Node) -> int:
	print("--- try_place: rejection paths ---")
	_reset(gs)
	gs.set("day", 3)
	gs.set("phase", "afternoon")
	var failed := 0

	# 未持有：registry 存在但未持有 → not_held，GameState 零變化
	var not_held: Dictionary = gs.call("try_place", "info_husband_version", "d3_pm_sanquan", "show_version")
	if not_held.get("ok", false) or str(not_held.get("reason_code")) != "not_held":
		failed += _fail("try_place unheld card: expected ok=false reason_code=not_held, got %s" % str(not_held))
	else:
		failed += _ok("try_place unheld card → ok=false reason_code=not_held")
	if not (gs.get("slots_placed") as Dictionary).is_empty():
		failed += _fail("try_place unheld card: slots_placed should stay empty")
	else:
		failed += _ok("try_place unheld card: slots_placed unchanged (empty)")

	# 空卡 id：try_place 傳入空字串 → not_held (K-17)
	var empty_card: Dictionary = gs.call("try_place", "", "d3_pm_sanquan", "show_version")
	if empty_card.get("ok", false) or str(empty_card.get("reason_code")) != "not_held":
		failed += _fail("try_place empty card id: expected ok=false reason_code=not_held, got %s" % str(empty_card))
	else:
		failed += _ok("try_place empty card id → ok=false reason_code=not_held (K-17)")

	# 不符 accepts：主角卡放進不收主角卡的比對槽（先持有 info 卡讓 requires 過，才單獨測 accepts）
	gs.call("gain_card", "protagonist")
	gs.call("gain_card", "info_husband_version")
	var not_accepted: Dictionary = gs.call("try_place", "protagonist", "d3_pm_sanquan", "show_version")
	if not_accepted.get("ok", false) or str(not_accepted.get("reason_code")) != "not_accepted":
		failed += _fail("try_place protagonist into compare slot: expected ok=false reason_code=not_accepted, got %s" % str(not_accepted))
	else:
		failed += _ok("try_place protagonist into compare slot → ok=false reason_code=not_accepted")

	# 不存在的槽／beat
	var unknown_slot: Dictionary = gs.call("try_place", "protagonist", "d3_pm_sanquan", "no_such_slot")
	if unknown_slot.get("ok", false) or str(unknown_slot.get("reason_code")) != "unknown_slot":
		failed += _fail("try_place unknown slot: expected reason_code=unknown_slot, got %s" % str(unknown_slot))
	else:
		failed += _ok("try_place unknown slot → reason_code=unknown_slot")

	var unknown_beat: Dictionary = gs.call("try_place", "protagonist", "no_such_beat", "x")
	if unknown_beat.get("ok", false) or str(unknown_beat.get("reason_code")) != "unknown_beat":
		failed += _fail("try_place unknown beat: expected reason_code=unknown_beat, got %s" % str(unknown_beat))
	else:
		failed += _ok("try_place unknown beat → reason_code=unknown_beat")

	return failed


# ── attention_npc 投入帳（規格書第十二節；資料尚無標註，用合成 beat 驗機制）──

func _test_attention_npc(gs: Node, data_node: Node) -> int:
	print("--- npc_action_counts (attention_npc) ---")
	_reset(gs)
	gs.call("gain_card", "protagonist")

	# GameState 內部一律讀裸全域 `Data`（見 game_state.gd 的 Data.loader.* 用法），
	# 而它固定綁在 project.godot 掛的那個 autoload 節點——不是本檔另外建立、註冊成
	# Engine singleton 的 data_node（那個是給 Data._ready() 自己找 GameState 用的獨立實例）。
	# 要合成 beat 讓 try_place 讀得到，得寫進 /root/Data 那一份 loader，不是 data_node 的。
	var real_data: Node = get_root().get_node("Data")
	var loader: DataLoader = real_data.get("loader") as DataLoader
	loader.beats_by_id["p1d_synthetic_attn_day"] = {
		"id": "p1d_synthetic_attn_day",
		"when": { "day": 5, "phase": "morning" },
		"slots": [
			{ "id": "s1", "accepts": ["protagonist"], "attention_npc": "npc_synth_test",
			  "on_place": { "text": "test" } },
		],
	}
	loader.beats_by_id["p1d_synthetic_attn_night"] = {
		"id": "p1d_synthetic_attn_night",
		"slots": [
			{ "id": "s1", "accepts": ["protagonist"], "attention_npc": "npc_synth_test",
			  "on_place": { "text": "test" } },
		],
	}

	var failed := 0

	gs.set("day", 5)
	gs.set("phase", "morning")
	var day_result: Dictionary = gs.call("try_place", "protagonist", "p1d_synthetic_attn_day", "s1")
	if not day_result.get("ok", false):
		failed += _fail("attention_npc day placement: expected ok, got " + str(day_result))
	else:
		failed += _ok("attention_npc day placement → ok")
	if int((gs.get("npc_action_counts") as Dictionary).get("npc_synth_test", 0)) != 1:
		failed += _fail("attention_npc: expected count 1 after one successful action-phase placement")
	else:
		failed += _ok("attention_npc: count = 1 after action-phase placement")

	# 重複嘗試（已 resolved）不計
	gs.call("try_place", "protagonist", "p1d_synthetic_attn_day", "s1")
	if int((gs.get("npc_action_counts") as Dictionary).get("npc_synth_test", 0)) != 1:
		failed += _fail("attention_npc: repeated placement on resolved slot should not double-count")
	else:
		failed += _ok("attention_npc: repeated placement on resolved slot did not double-count")

	# night 放置：不消耗行動格，也不計投入帳（action_spent 這裡已因白天那次放置為 true，
	# 驗的是「night 放置前後不變」，不是「一定是 false」）
	gs.set("phase", "night")
	var spent_before_night: bool = gs.get("action_spent")
	var night_result: Dictionary = gs.call("try_place", "protagonist", "p1d_synthetic_attn_night", "s1")
	if not night_result.get("ok", false):
		failed += _fail("attention_npc night placement: expected ok, got " + str(night_result))
	else:
		failed += _ok("attention_npc night placement → ok")
	if int((gs.get("npc_action_counts") as Dictionary).get("npc_synth_test", 0)) != 1:
		failed += _fail("attention_npc: night placement should not add to count (免費，不計)")
	else:
		failed += _ok("attention_npc: night placement did not add to count")
	if gs.get("action_spent") != spent_before_night:
		failed += _fail("attention_npc: night placement changed action_spent (should be untouched)")
	else:
		failed += _ok("attention_npc: night placement did not touch action_spent")

	loader.beats_by_id.erase("p1d_synthetic_attn_day")
	loader.beats_by_id.erase("p1d_synthetic_attn_night")

	return failed


# ── 序列化往返：P1-D 新增欄位（flags/switches/switch_progress/relations/npc_action_counts）──

func _test_serialize_roundtrip(gs: Node) -> int:
	print("--- serialize_roundtrip_p1d ---")
	_reset(gs)
	gs.call("gain_card", "protagonist")
	gs.call("set_flag", "rt_flag", true)
	gs.call("open_switch", "rt_switch")
	gs.call("add_switch_progress", "rt_prog", 4)
	gs.call("add_relation", "rt_npc", 2)
	gs.set("day", 3)
	gs.set("phase", "afternoon")
	gs.call("try_place", "protagonist", "d3_pm_sanquan", "soak")

	var snap: Dictionary = gs.call("serialize")
	var json_str := JSON.stringify(snap)
	var parsed: Dictionary = JSON.parse_string(json_str)

	_reset(gs)
	gs.call("deserialize", parsed)

	var failed := 0
	if not (gs.get("flags") as Dictionary).get("rt_flag", false):
		failed += _fail("roundtrip: flags lost")
	else:
		failed += _ok("roundtrip: flags preserved")
	if not (gs.get("switches") as Dictionary).get("rt_switch", false):
		failed += _fail("roundtrip: switches lost")
	else:
		failed += _ok("roundtrip: switches preserved")
	if int((gs.get("switch_progress") as Dictionary).get("rt_prog", 0)) != 4:
		failed += _fail("roundtrip: switch_progress lost")
	else:
		failed += _ok("roundtrip: switch_progress preserved")
	if int((gs.get("relations") as Dictionary).get("rt_npc", 0)) != 2:
		failed += _fail("roundtrip: relations lost")
	else:
		failed += _ok("roundtrip: relations preserved")
	if not (gs.get("slots_placed") as Dictionary).has("d3_pm_sanquan::soak"):
		failed += _fail("roundtrip: slots_placed lost")
	else:
		failed += _ok("roundtrip: slots_placed preserved")
	if not gs.get("action_spent"):
		failed += _fail("roundtrip: action_spent lost")
	else:
		failed += _ok("roundtrip: action_spent preserved")

	return failed


# ── 語彙封閉性 lint：未知鍵抓得到，且現行全部 252 個 beat 乾淨 ────────────────

func _test_lint_vocabulary() -> int:
	print("--- lint_vocabulary ---")
	var failed := 0

	var bad_condition: Array[Dictionary] = [{
		"id": "p1d_lint_bad_condition",
		"condition": { "bogus_operator": true },
		"slots": [],
	}]
	var problems1 := DataLoader.lint_vocabulary(bad_condition)
	if problems1.is_empty():
		failed += _fail("lint_vocabulary: unknown condition operator should be caught")
	else:
		failed += _ok("lint_vocabulary: unknown condition operator caught (%s)" % problems1[0])

	var multi_key_condition: Array[Dictionary] = [{
		"id": "p1d_lint_multi_key",
		"condition": { "day": 5, "flag": "x" },
		"slots": [],
	}]
	var problems_multi := DataLoader.lint_vocabulary(multi_key_condition)
	if problems_multi.is_empty():
		failed += _fail("lint_vocabulary: multi-key condition dictionary should be caught (should use 'all')")
	else:
		failed += _ok("lint_vocabulary: multi-key condition caught (%s)" % problems_multi[0])

	var bad_effect: Array[Dictionary] = [{
		"id": "p1d_lint_bad_effect",
		"slots": [
			{ "id": "s1", "on_place": { "bogus_effect_key": 1 } },
		],
	}]
	var problems2 := DataLoader.lint_vocabulary(bad_effect)
	if problems2.is_empty():
		failed += _fail("lint_vocabulary: unknown effect key should be caught")
	else:
		failed += _ok("lint_vocabulary: unknown effect key caught (%s)" % problems2[0])

	var good: Array[Dictionary] = [{
		"id": "p1d_lint_good",
		"condition": { "all": [{ "day_at_least": 1 }, { "not": { "flag": "x" } }] },
		"slots": [
			{ "id": "s1", "requires": { "count_at_least": { "n": 1, "of": [{ "has_card": "protagonist" }] } },
			  "reject_reason": "（測試）",
			  "on_place": { "text": "t", "gain": ["protagonist"], "flag": { "a": true } } },
		],
	}]
	var problems3 := DataLoader.lint_vocabulary(good)
	if not problems3.is_empty():
		failed += _fail("lint_vocabulary: well-formed beat flagged incorrectly: %s" % str(problems3))
	else:
		failed += _ok("lint_vocabulary: well-formed beat passes clean")

	# 迴歸：現行全部真實資料要是乾淨的（否則 Data.ok 早就是 false，遊戲開不了機）
	var real_loader := DataLoader.new()
	real_loader.load_all()
	var real_problems := DataLoader.lint_vocabulary(real_loader.beats)
	if not real_problems.is_empty():
		failed += _fail("lint_vocabulary: real data has %d vocabulary problem(s): %s" % [
			real_problems.size(), str(real_problems[0])])
	else:
		failed += _ok("lint_vocabulary: real data (252 beats) is clean")

	var missing_reasons := DataLoader.lint_missing_reject_reason(real_loader.beats)
	if not missing_reasons.is_empty():
		failed += _fail("lint_missing_reject_reason: real data has %d missing reject_reason(s): %s" % [
			missing_reasons.size(), str(missing_reasons[0])])
	else:
		failed += _ok("lint_missing_reject_reason: real data has 0 missing reject_reason warnings")

	# lint_choice_rules / lint_free_slot_rules: choice 槽接受 protagonist 必須報錯 (K-22)
	var bad_choice_beat: Array[Dictionary] = [{
		"id": "synthetic_bad_choice",
		"when": { "day": 10, "phase": "morning" },
		"location": "sanquan",
		"slots": [
			{ "id": "c1", "choice_group": "test_grp", "accepts": ["protagonist"] },
		],
	}]
	var choice_err_res := DataLoader.lint_choice_rules(bad_choice_beat)
	var choice_err_list: PackedStringArray = choice_err_res.get("errors", PackedStringArray())
	if choice_err_list.is_empty():
		failed += _fail("lint_choice_rules: choice slot accepting protagonist should be caught as error (K-22)")
	else:
		failed += _ok("lint_choice_rules: choice slot accepting protagonist caught as error (K-22)")

	# lint_free_slot_rules: 非 fixed 面板僅有免費槽且未列入豁免名單必須報錯 (K-27)
	var bad_free_panel_beat: Array[Dictionary] = [{
		"id": "synthetic_unexempted_free_beat",
		"when": { "day": 12, "phase": "morning" },
		"location": "temple",
		"slots": [
			{ "id": "compare_only", "accepts": ["info_registry"] },
		],
	}]
	var free_panel_err_res := DataLoader.lint_free_slot_rules(bad_free_panel_beat)
	var free_panel_err_list: PackedStringArray = free_panel_err_res.get("errors", PackedStringArray())
	if free_panel_err_list.is_empty():
		failed += _fail("lint_free_slot_rules: unexempted panel without protagonist slot should be caught as error (K-27)")
	else:
		failed += _ok("lint_free_slot_rules: unexempted panel without protagonist slot caught as error (K-27)")

	return failed
