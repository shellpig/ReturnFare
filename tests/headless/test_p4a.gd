extends SceneTree

const PlaythroughGreedy := preload("res://tests/headless/playthrough_greedy.gd")

## P4-A 資料與 SCHEMA 真值化測試（實作規格書 P4-A、測試指南 P4-A）。
## 正向：載入正式資料，驗 lint 15/16 全綠、每張卡有 boolean discardable，並動態數出
##       委託槽數、encounter beat 數、D8/D45 契約值（不預填完整表）。
## 負向：以 in-memory loader 建每個錯誤類別的最小反例，逐條驗對應 lint 抓到。
## 跑法：Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/test_p4a.gd

var _failed := 0


func _initialize() -> void:
	await process_frame
	print("=== P4-A 資料與 SCHEMA 真值化測試 ===")
	_test_positive_real_data()
	_test_lint9_discardable_negative()
	_test_lint15_negative()
	_test_lint16_negative()
	_test_lint14_repeat_exception()
	_test_runtime_gate()
	_test_nb1_d8_be_regression()

	if _failed > 0:
		push_error("test_p4a: %d 個斷言失敗" % _failed)
		quit(1)
	else:
		print("\n=== P4-A 全部測試通過 ===")
		quit(0)


func _ok(msg: String) -> void:
	print("  ok  " + msg)


func _fail(msg: String) -> void:
	push_error("  FAIL  " + msg)
	_failed += 1


## 建一個只填 beats/cards/locations 的 in-memory loader（不 load_all）。
func _make_loader(beats: Array, cards: Dictionary, locations: Dictionary) -> DataLoader:
	var loader := DataLoader.new()
	loader.cards = cards
	loader.locations = locations
	loader.beats.clear()
	for b in beats:
		loader.beats.append(b as Dictionary)
	return loader


func _errs_contain(errs: PackedStringArray, needle: String) -> bool:
	for e in errs:
		if needle in e:
			return true
	return false


## 共用最小卡片集
func _base_cards() -> Dictionary:
	return {
		"protagonist": { "id": "protagonist", "type": "protagonist", "discardable": false },
		"npc_x": { "id": "npc_x", "type": "person", "discardable": false },
		"npc_y": { "id": "npc_y", "type": "person", "discardable": false },
		"info_x": { "id": "info_x", "type": "info", "discardable": true },
		"know_x": { "id": "know_x", "type": "knowledge", "discardable": false },
	}


func _base_locs() -> Dictionary:
	return {
		"day_loc": { "id": "day_loc", "layer": "day", "madness_cost": 0 },
		"night_loc": { "id": "night_loc", "layer": "night", "madness_cost": 1 },
	}


# ─────────────────────────── 正向：正式資料 ───────────────────────────
func _test_positive_real_data() -> void:
	print("\n--- 1. 正向：正式資料 lint 15/16 全綠、動態數 ---")
	var loader := DataLoader.new()
	var ok := loader.load_all()
	if not ok:
		_fail("正式資料載入失敗")
		return
	var ref_probs := loader.verify_references()
	if ref_probs.size() > 0:
		_fail("正式資料引用檢查非空：%d" % ref_probs.size())

	# 每張卡都有 boolean discardable（lint 9）
	var ct_errs := DataLoader.lint_card_types(loader)
	if ct_errs.size() == 0:
		_ok("lint 9：正式資料全部卡片皆有合法 type 與 boolean discardable")
	else:
		_fail("lint 9 正式資料非空：%s" % str(ct_errs))
	var missing_disc := 0
	for cid: String in loader.cards:
		var c: Dictionary = loader.cards[cid]
		if not (c.get("discardable") is bool):
			missing_disc += 1
	if missing_disc == 0:
		_ok("全部 %d 張卡皆有 boolean discardable（動態數）" % loader.cards.size())
	else:
		_fail("有 %d 張卡缺 boolean discardable" % missing_disc)

	# lint 15
	var d_errs := DataLoader.lint_delegations(loader)
	if d_errs.size() == 0:
		_ok("lint 15：正式資料委託全綠")
	else:
		_fail("lint 15 正式資料非空：%s" % str(d_errs))

	# lint 16
	var e_errs := DataLoader.lint_encounters(loader)
	if e_errs.size() == 0:
		_ok("lint 16：正式資料遭遇全綠")
	else:
		_fail("lint 16 正式資料非空：%s" % str(e_errs))

	# 動態數：委託槽（有 delegation 的槽）
	var deleg_slots := 0
	var deleg_beats := {}
	var enc_beats: Array[String] = []
	for b in loader.beats:
		for s in b.get("slots", []) as Array:
			if (s as Dictionary).has("delegation"):
				deleg_slots += 1
				deleg_beats[str(b.get("id", ""))] = true
		if b.has("encounter"):
			enc_beats.append(str(b.get("id", "")))
	_ok("動態數：委託槽 %d 個（分佈於 beat %s）" % [deleg_slots, str(deleg_beats.keys())])
	_ok("動態數：encounter beat %d 個 → %s" % [enc_beats.size(), str(enc_beats)])

	# D8 契約值
	var d8: Dictionary = loader.beats_by_id.get("n_manydoors_ch1", {})
	var d8_enc: Dictionary = d8.get("encounter", {}) as Dictionary
	if bool(d8_enc.get("repeat_each_run", false)) and bool(d8_enc.get("charge_first_visit", false)) \
			and bool(d8_enc.get("allow_discard", false)) and int(d8_enc.get("escape_cost", -1)) == 1 \
			and str(d8_enc.get("after_finish", "")) == "stay" and not d8.has("meta_once") \
			and (d8_enc.get("rounds", []) as Array).size() == 3:
		_ok("D8 契約：repeat+charge+allow_discard、escape_cost 1、after_finish stay、非 meta_once、三回合")
	else:
		_fail("D8 契約值不符：%s" % str(d8_enc))
	# D8 三回合 fallback 都 requires_discardable
	var d8_fb_all := true
	for r in d8_enc.get("rounds", []) as Array:
		if not bool((r as Dictionary).get("fallback", {}).get("requires_discardable", false)):
			d8_fb_all = false
	if d8_fb_all:
		_ok("D8 三回合 fallback 全設 requires_discardable")
	else:
		_fail("D8 有 fallback 未設 requires_discardable")

	# D45 契約值
	var d45: Dictionary = loader.beats_by_id.get("d45_encounter", {})
	var d45_enc: Dictionary = d45.get("encounter", {}) as Dictionary
	if d45_enc.get("escape_cost") == null and bool(d45_enc.get("allow_discard", true)) == false \
			and str(d45_enc.get("after_finish", "")) == "advance_phase" \
			and (d45_enc.get("rounds", []) as Array).size() == 1:
		_ok("D45 契約：escape_cost null、allow_discard false、after_finish advance_phase、一回合")
	else:
		_fail("D45 契約值不符：%s" % str(d45_enc))

	# D17 不再自動發三張人物卡
	var d17: Dictionary = loader.beats_by_id.get("d17_morning_phone", {})
	var d17_gain: Array = (d17.get("on_enter", {}) as Dictionary).get("gain", []) as Array
	var auto_person := false
	for g in d17_gain:
		if g is String and str(loader.cards.get(g, {}).get("type", "")) == "person":
			auto_person = true
	if not auto_person:
		_ok("D17 on_enter 無無條件人物卡發放（不再自動發三張）")
	else:
		_fail("D17 on_enter 仍無條件發人物卡：%s" % str(d17_gain))


# ─────────────────────────── lint 9 discardable 負向 ───────────────────────────
func _test_lint9_discardable_negative() -> void:
	print("\n--- 1b. lint 9 discardable 缺欄/錯型別負向 ---")
	var ct := {
		"info": { "id": "info" }, "person": { "id": "person" },
		"protagonist": { "id": "protagonist" }, "knowledge": { "id": "knowledge" },
	}
	# 缺欄
	var loader1 := DataLoader.new()
	loader1.card_types = ct
	loader1.cards = { "c1": { "id": "c1", "type": "info" } }
	if _errs_contain(DataLoader.lint_card_types(loader1), "缺少必填欄位 discardable"):
		_ok("缺 discardable 欄位被抓")
	else:
		_fail("缺 discardable 未被抓")
	# 錯型別
	var loader2 := DataLoader.new()
	loader2.card_types = ct
	loader2.cards = { "c2": { "id": "c2", "type": "info", "discardable": "yes" } }
	if _errs_contain(DataLoader.lint_card_types(loader2), "discardable 必須是 boolean"):
		_ok("discardable 錯型別被抓")
	else:
		_fail("discardable 錯型別未被抓")


# ─────────────────────────── lint 15 負向 ───────────────────────────
func _test_lint15_negative() -> void:
	print("\n--- 2. lint 15 委託負向 fixture ---")
	var locs := _base_locs()
	var cards := _base_cards()

	# 基底：一個合法的委託 beat（含親自處理槽），各案例只壞一處
	var deleg_slot := func(overrides: Dictionary) -> Dictionary:
		var s := {
			"id": "ask", "accepts": ["npc_x"], "choice_group": "grp",
			"condition": { "has_card": "npc_x" },
			"delegation": {
				"result_timing": "immediate",
				"preview": "去問問。", "tendency": "還行。",
			},
		}
		for k in overrides.keys():
			s[k] = overrides[k]
		return s

	var make := func(slot: Dictionary, when: Dictionary = {"day": 20, "phase": "afternoon"}) -> Array:
		var protag_slot := { "id": "self", "accepts": ["protagonist"], "choice_group": "grp", "choice_requires_card": true }
		return [{ "id": "b_test", "location": "day_loc", "when": when, "slots": [protag_slot, slot] }]

	# 泛型 person
	var s1 : Dictionary = deleg_slot.call({ "accepts": ["person"] })
	var l1 := DataLoader.lint_delegations(_make_loader(make.call(s1), cards, locs))
	if _errs_contain(l1, "型別泛稱"):
		_ok("泛型 person accepts 被抓")
	else:
		_fail("泛型 person 未被抓：%s" % str(l1))

	# 非人物卡
	var s2 : Dictionary = deleg_slot.call({ "accepts": ["info_x"], "condition": { "has_card": "info_x" } })
	var l2 := DataLoader.lint_delegations(_make_loader(make.call(s2), cards, locs))
	if _errs_contain(l2, "型別不是 person"):
		_ok("非人物卡 accepts 被抓")
	else:
		_fail("非人物卡未被抓：%s" % str(l2))

	# 引用不存在
	var s3 : Dictionary = deleg_slot.call({ "accepts": ["npc_ghost"], "condition": { "has_card": "npc_x" } })
	var l3 := DataLoader.lint_delegations(_make_loader(make.call(s3), cards, locs))
	if _errs_contain(l3, "引用不存在"):
		_ok("引用不存在的人物卡被抓")
	else:
		_fail("引用不存在未被抓：%s" % str(l3))

	# 缺 choice_group
	var s4 : Dictionary = deleg_slot.call({ "choice_group": "" })
	var l4 := DataLoader.lint_delegations(_make_loader(make.call(s4), cards, locs))
	if _errs_contain(l4, "非空 choice_group"):
		_ok("缺 choice_group 被抓")
	else:
		_fail("缺 choice_group 未被抓：%s" % str(l4))

	# timing 非法
	var s5 : Dictionary = deleg_slot.call({ "delegation": { "result_timing": "in_3_days", "preview": "x", "tendency": "y" } })
	var l5 := DataLoader.lint_delegations(_make_loader(make.call(s5), cards, locs))
	if _errs_contain(l5, "result_timing 非法"):
		_ok("timing 非法被抓")
	else:
		_fail("timing 非法未被抓：%s" % str(l5))

	# next_morning 缺 report
	var s6 : Dictionary = deleg_slot.call({ "delegation": { "result_timing": "next_morning", "preview": "x", "tendency": "y" } })
	var l6 := DataLoader.lint_delegations(_make_loader(make.call(s6), cards, locs))
	if _errs_contain(l6, "next_morning 委託必須有 report"):
		_ok("next_morning 缺 report 被抓")
	else:
		_fail("next_morning 缺 report 未被抓：%s" % str(l6))

	# immediate 多 report
	var s7 : Dictionary = deleg_slot.call({ "delegation": { "result_timing": "immediate", "preview": "x", "tendency": "y", "report": { "text": "r" } } })
	var l7 := DataLoader.lint_delegations(_make_loader(make.call(s7), cards, locs))
	if _errs_contain(l7, "immediate 委託不得有 report"):
		_ok("immediate 多 report 被抓")
	else:
		_fail("immediate 多 report 未被抓：%s" % str(l7))

	# next_morning 落到第 45 天
	var s8 : Dictionary = deleg_slot.call({ "delegation": { "result_timing": "next_morning", "preview": "x", "tendency": "y", "report": { "text": "r" } } })
	var l8 := DataLoader.lint_delegations(_make_loader(make.call(s8, { "day": 45, "phase": "afternoon" }), cards, locs))
	if _errs_contain(l8, "落到第 45 天之後"):
		_ok("next_morning 可成立於 D45 被抓")
	else:
		_fail("next_morning 落 D45 未被抓：%s" % str(l8))

	# 鎖定條件缺 reject_reason
	var s9 : Dictionary = deleg_slot.call({ "requires": { "flag": "some_gate" } })
	var l9 := DataLoader.lint_delegations(_make_loader(make.call(s9), cards, locs))
	if _errs_contain(l9, "requires 但缺 reject_reason"):
		_ok("鎖定條件缺 reject_reason 被抓")
	else:
		_fail("缺 reject_reason 未被抓：%s" % str(l9))

	# report 未知效果鍵（封閉語彙）
	var s11: Dictionary = deleg_slot.call({ "delegation": { "result_timing": "next_morning", "preview": "x", "tendency": "y", "report": { "text": "r", "teleport": "z" } } })
	var l11 := DataLoader.lint_delegations(_make_loader(make.call(s11), cards, locs))
	if _errs_contain(l11, "未知效果鍵"):
		_ok("report 未知效果鍵被抓")
	else:
		_fail("report 未知效果鍵未被抓：%s" % str(l11))

	# report 引用不存在卡（verify_references 遞迴 delegation）
	var s12: Dictionary = deleg_slot.call({ "delegation": { "result_timing": "next_morning", "preview": "x", "tendency": "y", "report": { "text": "r", "gain": ["ghost_card"] } } })
	var vr12 := _make_loader(make.call(s12), cards, locs).verify_references()
	if _errs_contain(vr12, "引用不存在的卡"):
		_ok("report.gain 壞引用被 verify_references 抓")
	else:
		_fail("report.gain 壞引用未被抓：%s" % str(vr12))

	# choice_group 缺親自處理槽
	var lone := [{ "id": "b_lone", "location": "day_loc", "when": { "day": 20, "phase": "afternoon" },
		"slots": [deleg_slot.call({})] }]
	var l10 := DataLoader.lint_delegations(_make_loader(lone, cards, locs))
	if _errs_contain(l10, "缺親自處理"):
		_ok("choice_group 缺親自處理槽被抓")
	else:
		_fail("缺親自處理槽未被抓：%s" % str(l10))


# ─────────────────────────── lint 16 負向 ───────────────────────────
func _test_lint16_negative() -> void:
	print("\n--- 3. lint 16 遭遇負向 fixture ---")
	var locs := _base_locs()
	var cards := _base_cards()

	# 合法基底 encounter（單回合勝利出口）
	var base_enc := func() -> Dictionary:
		return {
			"per_round_slot_cost": 1, "escape_cost": 1, "allow_discard": true, "after_finish": "stay",
			"rounds": [
				{ "id": "r1", "demand": "d", "responses": [
					{ "id": "a", "accepts": ["info_x"], "consume_card": false, "next_round": null, "on_resolve": { "text": "t" } }
				], "fallback": { "next_round": null, "on_resolve": { "text": "f" } } }
			],
			"on_victory": { "text": "v" }, "on_failure": { "text": "l" }, "on_escape": { "text": "e" },
		}
	var make_enc := func(enc: Dictionary, extra: Dictionary = {}) -> Array:
		var b := { "id": "enc_b", "location": "night_loc", "fixed": true,
			"when": { "day": 10, "phase": "night" }, "slots": [], "encounter": enc }
		for k in extra.keys():
			b[k] = extra[k]
		return [b]

	# 零回合
	var e1: Dictionary = base_enc.call(); e1["rounds"] = []
	if _errs_contain(DataLoader.lint_encounters(_make_loader(make_enc.call(e1), cards, locs)), "rounds 必須是非空陣列"):
		_ok("零回合被抓")
	else:
		_fail("零回合未被抓")

	# 重複 round id
	var e2: Dictionary = base_enc.call()
	e2["rounds"] = [e2["rounds"][0], { "id": "r1", "demand": "d2", "responses": [
		{ "id": "b", "accepts": ["know_x"], "consume_card": false, "next_round": null, "on_resolve": { "text": "t" } }
	], "fallback": { "next_round": null, "on_resolve": { "text": "f" } } }]
	if _errs_contain(DataLoader.lint_encounters(_make_loader(make_enc.call(e2), cards, locs)), "round id 重複"):
		_ok("重複 round id 被抓")
	else:
		_fail("重複 round id 未被抓")

	# 懸空 next_round
	var e3: Dictionary = base_enc.call()
	e3["rounds"][0]["responses"][0]["next_round"] = "ghost"
	if _errs_contain(DataLoader.lint_encounters(_make_loader(make_enc.call(e3), cards, locs)), "next_round 引用不存在"):
		_ok("懸空 next_round 被抓")
	else:
		_fail("懸空 next_round 未被抓")

	# 不可達 round + 無出口 cycle：r2 自環且不可達
	var e4: Dictionary = base_enc.call()
	e4["rounds"].append({ "id": "r2", "demand": "d", "responses": [
		{ "id": "c", "accepts": ["know_x"], "consume_card": false, "next_round": "r2", "on_resolve": { "text": "t" } }
	], "fallback": { "next_round": "r2", "on_resolve": { "text": "f" } } })
	var l4 := DataLoader.lint_encounters(_make_loader(make_enc.call(e4), cards, locs))
	if _errs_contain(l4, "不可從第一回合到達"):
		_ok("不可達 round 被抓")
	else:
		_fail("不可達 round 未被抓：%s" % str(l4))
	if _errs_contain(l4, "無法抵達任何結束出口"):
		_ok("無出口 cycle 被抓")
	else:
		_fail("無出口 cycle 未被抓：%s" % str(l4))

	# 接受集合空
	var e5: Dictionary = base_enc.call()
	e5["rounds"][0]["responses"][0]["accepts"] = []
	if _errs_contain(DataLoader.lint_encounters(_make_loader(make_enc.call(e5), cards, locs)), "accepts 必須非空"):
		_ok("接受集合空被抓")
	else:
		_fail("接受集合空未被抓")

	# 接受集合重疊
	var e6: Dictionary = base_enc.call()
	e6["rounds"][0]["responses"] = [
		{ "id": "a", "accepts": ["info_x"], "consume_card": false, "next_round": null, "on_resolve": { "text": "t" } },
		{ "id": "b", "accepts": ["info_x"], "consume_card": false, "next_round": null, "on_resolve": { "text": "t" } },
	]
	if _errs_contain(DataLoader.lint_encounters(_make_loader(make_enc.call(e6), cards, locs)), "與同 round 其他 response 重疊"):
		_ok("接受集合重疊被抓")
	else:
		_fail("接受集合重疊未被抓")

	# 壞引用
	var e7: Dictionary = base_enc.call()
	e7["rounds"][0]["responses"][0]["accepts"] = ["ghost_card"]
	if _errs_contain(DataLoader.lint_encounters(_make_loader(make_enc.call(e7), cards, locs)), "引用不存在的卡"):
		_ok("accepts 壞引用被抓")
	else:
		_fail("accepts 壞引用未被抓")

	# allow_discard 錯型別
	var e8: Dictionary = base_enc.call(); e8["allow_discard"] = "yes"
	if _errs_contain(DataLoader.lint_encounters(_make_loader(make_enc.call(e8), cards, locs)), "allow_discard 必須是 boolean"):
		_ok("allow_discard 錯型別被抓")
	else:
		_fail("allow_discard 錯型別未被抓")

	# requires_discardable 錯型別
	var e9: Dictionary = base_enc.call()
	e9["rounds"][0]["fallback"]["requires_discardable"] = 1
	if _errs_contain(DataLoader.lint_encounters(_make_loader(make_enc.call(e9), cards, locs)), "requires_discardable 必須是 boolean"):
		_ok("requires_discardable 錯型別被抓")
	else:
		_fail("requires_discardable 錯型別未被抓")

	# after_finish 非法
	var e10: Dictionary = base_enc.call(); e10["after_finish"] = "loop"
	if _errs_contain(DataLoader.lint_encounters(_make_loader(make_enc.call(e10), cards, locs)), "after_finish 必須是"):
		_ok("after_finish 非法被抓")
	else:
		_fail("after_finish 非法未被抓")

	# 遭遇效果偷讀非封閉鍵（on_resolve 用未知效果鍵）
	var e_key: Dictionary = base_enc.call()
	e_key["rounds"][0]["responses"][0]["on_resolve"] = { "text": "t", "teleport": "somewhere" }
	if _errs_contain(DataLoader.lint_encounters(_make_loader(make_enc.call(e_key), cards, locs)), "未知效果鍵"):
		_ok("遭遇 on_resolve 未知效果鍵被抓（封閉效果鍵）")
	else:
		_fail("遭遇 on_resolve 未知效果鍵未被抓")

	# 非法永久人物消耗：consume_card true 消耗不可丟棄人物卡
	var e11: Dictionary = base_enc.call()
	e11["rounds"][0]["responses"][0]["accepts"] = ["npc_x"]
	e11["rounds"][0]["responses"][0]["consume_card"] = true
	if _errs_contain(DataLoader.lint_encounters(_make_loader(make_enc.call(e11), cards, locs)), "不可消耗不可丟棄卡"):
		_ok("非法永久人物消耗被抓")
	else:
		_fail("非法永久人物消耗未被抓")

	# repeat 用在無明確 when.day 的 beat
	var e12: Dictionary = base_enc.call(); e12["repeat_each_run"] = true
	var l12 := DataLoader.lint_encounters(_make_loader(make_enc.call(e12, { "when": { "day_from": 10, "day_to": 12, "phase": "night" } }), cards, locs))
	if _errs_contain(l12, "repeat_each_run 只可用於"):
		_ok("repeat 用在無明確 when.day 被抓")
	else:
		_fail("repeat 無明確 when.day 未被抓：%s" % str(l12))

	# charge_first_visit 四聯合條件各自反例
	# (a) 非 fixed
	var ea: Dictionary = base_enc.call(); ea["charge_first_visit"] = true
	if _errs_contain(DataLoader.lint_encounters(_make_loader(make_enc.call(ea, { "fixed": false }), cards, locs)), "charge_first_visit 要求 beat 為 fixed"):
		_ok("charge_first_visit 非 fixed 被抓")
	else:
		_fail("charge_first_visit 非 fixed 未被抓")
	# (b) 非整數 when.day
	var eb: Dictionary = base_enc.call(); eb["charge_first_visit"] = true
	if _errs_contain(DataLoader.lint_encounters(_make_loader(make_enc.call(eb, { "when": { "day_from": 8, "day_to": 9, "phase": "night" } }), cards, locs)), "charge_first_visit 要求明確整數 when.day"):
		_ok("charge_first_visit 缺整數 when.day 被抓")
	else:
		_fail("charge_first_visit 缺整數 when.day 未被抓")
	# (c) when.phase 非 night
	var ec: Dictionary = base_enc.call(); ec["charge_first_visit"] = true
	if _errs_contain(DataLoader.lint_encounters(_make_loader(make_enc.call(ec, { "when": { "day": 10, "phase": "afternoon" } }), cards, locs)), "charge_first_visit 要求 when.phase == night"):
		_ok("charge_first_visit when.phase 非 night 被抓")
	else:
		_fail("charge_first_visit when.phase 非 night 未被抓")
	# (d) 非 night-layer location
	var ed: Dictionary = base_enc.call(); ed["charge_first_visit"] = true
	if _errs_contain(DataLoader.lint_encounters(_make_loader(make_enc.call(ed, { "location": "day_loc" }), cards, locs)), "location layer == night"):
		_ok("charge_first_visit 非 night-layer location 被抓")
	else:
		_fail("charge_first_visit 非 night-layer location 未被抓")

	# 小數 per_round_slot_cost（1.5 不得被 int() 截斷後接受）
	var ef1: Dictionary = base_enc.call(); ef1["per_round_slot_cost"] = 1.5
	if _errs_contain(DataLoader.lint_encounters(_make_loader(make_enc.call(ef1), cards, locs)), "per_round_slot_cost 必須為正整數"):
		_ok("小數 per_round_slot_cost 被抓")
	else:
		_fail("小數 per_round_slot_cost 未被抓")

	# 小數 escape_cost
	var ef2: Dictionary = base_enc.call(); ef2["escape_cost"] = 1.5
	if _errs_contain(DataLoader.lint_encounters(_make_loader(make_enc.call(ef2), cards, locs)), "escape_cost 必須為 null 或非負整數"):
		_ok("小數 escape_cost 被抓")
	else:
		_fail("小數 escape_cost 未被抓")

	# 小數 when.day（8.5）＋ repeat → 不算明確整數 day
	var ef3: Dictionary = base_enc.call(); ef3["repeat_each_run"] = true
	if _errs_contain(DataLoader.lint_encounters(_make_loader(make_enc.call(ef3, { "when": { "day": 8.5, "phase": "night" } }), cards, locs)), "repeat_each_run 只可用於"):
		_ok("小數 when.day 不被視為明確整數 day（repeat 被抓）")
	else:
		_fail("小數 when.day 仍被當明確整數 day")

	# 錯型別 boolean：repeat_each_run
	var ef4: Dictionary = base_enc.call(); ef4["repeat_each_run"] = "yes"
	if _errs_contain(DataLoader.lint_encounters(_make_loader(make_enc.call(ef4), cards, locs)), "repeat_each_run 必須是 boolean"):
		_ok("repeat_each_run 錯型別被抓")
	else:
		_fail("repeat_each_run 錯型別未被抓")

	# 錯型別 boolean：charge_first_visit
	var ef5: Dictionary = base_enc.call(); ef5["charge_first_visit"] = 1
	if _errs_contain(DataLoader.lint_encounters(_make_loader(make_enc.call(ef5), cards, locs)), "charge_first_visit 必須是 boolean"):
		_ok("charge_first_visit 錯型別被抓")
	else:
		_fail("charge_first_visit 錯型別未被抓")

	# response 缺 id
	var ef6: Dictionary = base_enc.call()
	ef6["rounds"][0]["responses"][0].erase("id")
	if _errs_contain(DataLoader.lint_encounters(_make_loader(make_enc.call(ef6), cards, locs)), "response 缺 id"):
		_ok("response 缺 id 被抓")
	else:
		_fail("response 缺 id 未被抓")

	# response id 重複
	var ef7: Dictionary = base_enc.call()
	ef7["rounds"][0]["responses"] = [
		{ "id": "dup", "accepts": ["info_x"], "consume_card": false, "next_round": null, "on_resolve": { "text": "t" } },
		{ "id": "dup", "accepts": ["know_x"], "consume_card": false, "next_round": null, "on_resolve": { "text": "t" } },
	]
	if _errs_contain(DataLoader.lint_encounters(_make_loader(make_enc.call(ef7), cards, locs)), "response id 重複"):
		_ok("response id 重複被抓")
	else:
		_fail("response id 重複未被抓")

	# 巢狀效果引用不存在卡：on_resolve.gain（verify_references 遞迴 encounter）
	var ef8: Dictionary = base_enc.call()
	ef8["rounds"][0]["responses"][0]["on_resolve"] = { "text": "t", "gain": ["ghost_card"] }
	if _errs_contain(_make_loader(make_enc.call(ef8), cards, locs).verify_references(), "引用不存在的卡"):
		_ok("encounter on_resolve.gain 壞引用被 verify_references 抓")
	else:
		_fail("encounter on_resolve.gain 壞引用未被抓")

	# round 缺 demand
	var ed1: Dictionary = base_enc.call(); ed1["rounds"][0].erase("demand")
	if _errs_contain(DataLoader.lint_encounters(_make_loader(make_enc.call(ed1), cards, locs)), "round 缺 demand"):
		_ok("round 缺 demand 被抓")
	else:
		_fail("round 缺 demand 未被抓")

	# response 缺 next_round 鍵（不得被 .get() 當成明示 null）
	var ed2: Dictionary = base_enc.call(); ed2["rounds"][0]["responses"][0].erase("next_round")
	if _errs_contain(DataLoader.lint_encounters(_make_loader(make_enc.call(ed2), cards, locs)), "response:a：缺 next_round"):
		_ok("response 缺 next_round 鍵被抓")
	else:
		_fail("response 缺 next_round 鍵未被抓")

	# fallback 缺 next_round 鍵
	var ed3: Dictionary = base_enc.call(); ed3["rounds"][0]["fallback"].erase("next_round")
	if _errs_contain(DataLoader.lint_encounters(_make_loader(make_enc.call(ed3), cards, locs)), "fallback：缺 next_round"):
		_ok("fallback 缺 next_round 鍵被抓")
	else:
		_fail("fallback 缺 next_round 鍵未被抓")

	# malformed 第一 round（非 Dictionary）＋第二筆合法 round：round_by_id 非空，
	# 逼 traversal 真的走到 `rounds[0] is Dictionary` 守衛（拿掉守衛會在 cast 崩）。
	var ed4: Dictionary = base_enc.call()
	ed4["rounds"] = ["not_a_dict", { "id": "r_ok", "demand": "d", "responses": [
		{ "id": "a", "accepts": ["info_x"], "consume_card": false, "next_round": null, "on_resolve": { "text": "t" } }
	], "fallback": { "next_round": null, "on_resolve": { "text": "f" } } }]
	var l_ed4 := DataLoader.lint_encounters(_make_loader(make_enc.call(ed4), cards, locs))
	if _errs_contain(l_ed4, "round 不是 Dictionary"):
		_ok("malformed round 記錯且未 crash（traversal 防呆）")
	else:
		_fail("malformed round 未被抓：%s" % str(l_ed4))

	# malformed response（round 合法但 response 非 Dictionary）不 crash
	var ed5: Dictionary = base_enc.call()
	ed5["rounds"][0]["responses"] = ["bad", { "id": "g", "accepts": ["info_x"], "consume_card": false, "next_round": null, "on_resolve": { "text": "t" } }]
	var l_ed5 := DataLoader.lint_encounters(_make_loader(make_enc.call(ed5), cards, locs))
	if _errs_contain(l_ed5, "response 不是 Dictionary"):
		_ok("malformed response 記錯且未 crash（reachability/can_reach_null 防呆）")
	else:
		_fail("malformed response 未被抓：%s" % str(l_ed5))

	# malformed fallback（round 合法但 fallback 非 Dictionary）不 crash：
	# rounds[0] 合法讓 traversal 啟動，走到 fallback 的 `is Dictionary` 守衛（拿掉會 cast 崩）。
	var ed6: Dictionary = base_enc.call(); ed6["rounds"][0]["fallback"] = "not_a_dict"
	var l_ed6 := DataLoader.lint_encounters(_make_loader(make_enc.call(ed6), cards, locs))
	if _errs_contain(l_ed6, "缺 fallback"):
		_ok("malformed fallback 記錯且未 crash（traversal fallback 防呆）")
	else:
		_fail("malformed fallback 未被抓：%s" % str(l_ed6))

	# round graph 存在 cycle 必須被 lint 抓出（K-146 DAG 規則）
	var ed_cycle: Dictionary = base_enc.call()
	ed_cycle["rounds"] = [
		{
			"id": "r1", "demand": "d1",
			"responses": [{ "id": "resp1", "accepts": ["info_x"], "consume_card": false, "next_round": "r2", "on_resolve": { "text": "t1" } }],
			"fallback": { "next_round": "r2", "on_resolve": { "text": "f1" } }
		},
		{
			"id": "r2", "demand": "d2",
			"responses": [{ "id": "resp2", "accepts": ["info_x"], "consume_card": false, "next_round": "r1", "on_resolve": { "text": "t2" } }],
			"fallback": { "next_round": null, "on_resolve": { "text": "f2" } }
		}
	]
	var l_cycle := DataLoader.lint_encounters(_make_loader(make_enc.call(ed_cycle), cards, locs))
	if _errs_contain(l_cycle, "round graph 不得存在任何 cycle"):
		_ok("round graph cycle 正確被 lint 阻擋（K-146 DAG 契約）")
	else:
		_fail("round graph cycle 未被抓：%s" % str(l_cycle))

	# 邊界：合法 D8 型（repeat+charge，night-layer）不報錯
	var e_ok: Dictionary = base_enc.call(); e_ok["repeat_each_run"] = true; e_ok["charge_first_visit"] = true
	if DataLoader.lint_encounters(_make_loader(make_enc.call(e_ok), cards, locs)).size() == 0:
		_ok("邊界：repeat+charge 的 night-layer fixed dated encounter 合法（無誤報）")
	else:
		_fail("邊界：合法 repeat+charge 遭遇被誤報")


# ─────────────────────────── lint 14 repeat 例外 ───────────────────────────
func _test_lint14_repeat_exception() -> void:
	print("\n--- 4. lint 14 repeat_each_run 例外回歸 ---")
	var locs := _base_locs()
	var cards := _base_cards()

	# (1) repeat 遭遇可不 meta_once（night-layer fixed dated）
	var b_repeat := [{ "id": "b_rep", "location": "night_loc", "fixed": true,
		"when": { "day": 8, "phase": "night" }, "slots": [],
		"encounter": { "per_round_slot_cost": 1, "repeat_each_run": true } }]
	if DataLoader.lint_night_once(_make_loader(b_repeat, cards, locs)).size() == 0:
		_ok("repeat_each_run 的 night-layer fixed beat 可不 meta_once")
	else:
		_fail("repeat_each_run 例外未生效：%s" % str(DataLoader.lint_night_once(_make_loader(b_repeat, cards, locs))))

	# (2) 非遭遇 night-layer fixed 缺 meta_once → 報錯
	var b_plain := [{ "id": "b_plain", "location": "night_loc", "fixed": true,
		"when": { "day": 9, "phase": "night" }, "slots": [] }]
	if _errs_contain(DataLoader.lint_night_once(_make_loader(b_plain, cards, locs)), "必須標記 meta_once"):
		_ok("非遭遇 night fixed 缺 meta_once 仍報錯")
	else:
		_fail("非遭遇 night fixed 缺 meta_once 未報錯")

	# (3) repeat + meta_once 同時 → 報錯
	var b_both := [{ "id": "b_both", "location": "night_loc", "fixed": true, "meta_once": true,
		"when": { "day": 8, "phase": "night" }, "slots": [],
		"encounter": { "per_round_slot_cost": 1, "repeat_each_run": true } }]
	if _errs_contain(DataLoader.lint_night_once(_make_loader(b_both, cards, locs)), "不得同時存在"):
		_ok("repeat_each_run 與 meta_once 同時出現報錯")
	else:
		_fail("repeat + meta_once 同時未報錯")


# ─────────────── 5. runtime gate / delegate 轉導 + choice_requires_card ───────────────
func _test_runtime_gate() -> void:
	print("\n--- 5. runtime gate / delegate 轉導 + choice_requires_card 硬成本 ---")
	var data_node := PlaythroughGreedy.setup_data(self)
	var gs := PlaythroughGreedy.setup_game_state(self, data_node)
	if data_node == null or gs == null or not bool(data_node.get("ok")):
		_fail("GameState/Data 未就緒，跳過 runtime gate 測試")
		return

	# 進 D17 下午、備妥人物卡與主角卡、清掉可能殘留的選擇/放置
	gs.set("day", 17)
	gs.set("phase", "afternoon")
	gs.set("action_spent", false)
	(gs.get("choices") as Dictionary).clear()
	(gs.get("slots_placed") as Dictionary).clear()
	var hand: Array = gs.get("hand") as Array
	hand.clear()
	hand.append("protagonist")
	hand.append("npc_ajie")

	var before := str(gs.call("serialize"))

	# 1. find_self 無卡直呼 choose → card_required，零變化
	var r2: Dictionary = gs.call("choose", "d17_19_prescription", "prescription_route", "find_self", "")
	if str(r2.get("reason_code", "")) == "card_required" and str(gs.call("serialize")) == before:
		_ok("choice_requires_card 槽無卡直呼回 card_required（零變化）")
	else:
		_fail("無卡 choose 未回 card_required：%s" % str(r2))

	# 2. 親自處理槽提交 protagonist → ok 且消耗行動格
	var r3: Dictionary = gs.call("try_place", "protagonist", "d17_19_prescription", "find_self")
	if bool(r3.get("ok", false)) and bool(gs.get("action_spent")):
		_ok("親自處理槽提交 protagonist 成功並消耗行動格")
	else:
		_fail("親自處理槽未消耗行動格：ok=%s action_spent=%s" % [str(r3.get("ok")), str(gs.get("action_spent"))])

	# 3. 在乾淨狀態下測試委託槽走 try_place 轉導至 delegate() 成功且不消耗主角行動
	(gs.get("choices") as Dictionary).clear()
	(gs.get("slots_placed") as Dictionary).clear()
	gs.set("action_spent", false)
	var r1: Dictionary = gs.call("try_place", "npc_ajie", "d17_19_prescription", "ask_ajie")
	if bool(r1.get("ok", false)) and not bool(gs.get("action_spent")):
		_ok("委託槽走 try_place 成功轉導至 delegate() 且不消耗行動格")
	else:
		_fail("委託槽轉導 delegate 失敗：%s" % str(r1))


# ─── 6. NB1 regression：D8 charge_first_visit 撞發狂上限，重置後不寫入 D8 beat ───
func _test_nb1_d8_be_regression() -> void:
	print("\n--- 6. NB1：D8 首次收費撞發狂上限，重置後不寫入 D8 beat ---")
	var data_node := PlaythroughGreedy.setup_data(self)
	var gs := PlaythroughGreedy.setup_game_state(self, data_node)
	if data_node == null or gs == null or not bool(data_node.get("ok")):
		_fail("GameState/Data 未就緒，跳過 NB1 regression")
		return

	var cap: int = int(data_node.call("tuning", "madness_cap", 7))
	# 乾淨重置本輪與 meta seen（讓 D8 是終身首次），排到第 8 夜
	gs.call("end_run")
	(gs.get("night_locations_seen") as Dictionary).clear()
	(gs.get("night_once_beats_seen") as Dictionary).clear()
	(gs.get("beats_entered") as Dictionary).clear()
	gs.set("day", 8)
	gs.set("phase", "night")
	# 先塞 cap-1 張發狂卡；D8 首次收費 +1 剛好撞上限
	for _i in range(cap - 1):
		gs.call("gain_card", "madness", false)

	var ended := [0]
	var cb := func(_eid: String): ended[0] += 1
	gs.connect("run_ended", cb)
	gs.call("play_night_fixed")
	gs.disconnect("run_ended", cb)

	var be_fired: bool = ended[0] == 1
	var was_reset: bool = int(gs.get("day")) == 1 and str(gs.get("phase")) == "morning"
	var d8_not_written: bool = not (gs.get("beats_entered") as Dictionary).has("n_manydoors_ch1")
	if be_fired and was_reset and d8_not_written:
		_ok("D8 首次收費撞上限 → 恰觸發一次 BE、重置回第 1 天、且未把 n_manydoors_ch1 寫進新輪 beats_entered")
	else:
		_fail("NB1 regression：be_fired=%s reset=%s d8_not_written=%s" % [str(be_fired), str(was_reset), str(d8_not_written)])
