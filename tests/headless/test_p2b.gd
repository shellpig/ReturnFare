extends SceneTree

## P2-B headless 驗收測試：縱慾出口、主動縱慾、泡湯特例、強度等級追加效果、三態可見性、when 解析、Lint 4 & 10。
## 跑法：
##   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/test_p2b.gd
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
		push_error("P2-B: Data failed to load; abort")
		quit(1)
		return

	var failed := 0
	failed += _test_exit_slots_visibility(gs, data_node)
	failed += _test_active_indulgence_smash(gs, data_node)
	failed += _test_soak_morning_vs_afternoon(gs, data_node)
	failed += _test_indulgence_rejection_paths(gs, data_node)
	failed += _test_indulgence_level_escalation(gs, data_node)
	failed += _test_when_day_from_parsing(data_node)
	failed += _test_conflicting_when_fixture()
	failed += _test_lint_4_and_10(data_node)
	failed += _test_serialize_roundtrip_p2b(gs)
	failed += _test_end_run_resets_p2b(gs)

	Engine.unregister_singleton("Data")
	Engine.unregister_singleton("GameState")

	if failed > 0:
		push_error("P2-B: %d test(s) failed" % failed)
		quit(1)
	else:
		print("P2-B: all tests passed")
		quit(0)


func _ok(msg: String) -> int:
	print("  ok  " + msg)
	return 0


func _fail(msg: String) -> int:
	push_error("  FAIL  " + msg)
	return 1


# ── 1. 出口槽三態與可見性 ──────────────────────────────────────────────────

func _test_exit_slots_visibility(gs: Node, data: Node) -> int:
	var failed := 0
	gs.call("end_run")

	# 手上 0 張發狂卡時：山泉閣、老街、靜和園均無出口槽（HIDDEN，不進入 view model）
	for loc_id in ["sanquan", "oldstreet", "jinghe"]:
		var view: Dictionary = PanelBuilder.build(loc_id, gs, data)
		for bv in view.get("beats", []):
			for sv in bv.get("slots", []):
				var s: Dictionary = sv.get("slot", {})
				if (s.get("accepts", []) as Array).has("madness"):
					failed += _fail("0 張發狂卡時 %s 不應出現出口槽 %s" % [loc_id, str(s.get("id"))])

	if failed == 0:
		failed += _ok("0 張發狂卡時所有出口槽完全隱藏 (HIDDEN)")

	# 手上有 1 張發狂卡時：
	gs.call("gain_card", "madness") # madness#1

	# D1 上午逛山泉閣：砸東西、食慾、泡湯出現，暴力對人（D16前）與性慾（未達疑似）隱藏
	gs.set("day", 1)
	gs.set("phase", "morning")
	var sq_view: Dictionary = PanelBuilder.build("sanquan", gs, data)
	var sq_slots := _collect_slot_ids(sq_view)
	if not sq_slots.has("x_smash") or not sq_slots.has("x_binge") or not sq_slots.has("x_soak"):
		failed += _fail("1 張發狂卡時山泉閣應出現 x_smash, x_binge, x_soak；實際：%s" % str(sq_slots))
	else:
		failed += _ok("1 張發狂卡時山泉閣砸東西、食慾、泡湯槽正常出現")

	if sq_slots.has("x_violence"):
		failed += _fail("第 1 天山泉閣不應出現 x_violence（應擋在 D16 之後）")
	else:
		failed += _ok("第 1 天 x_violence 保持隱藏（D16 門檻）")

	if sq_slots.has("x_lust_ajie"):
		failed += _fail("未達疑似關係時 x_lust_ajie 不應出現")
	else:
		failed += _ok("未達疑似關係時 x_lust_ajie 保持隱藏")

	# D16 起逛山泉閣：暴力對人出現
	gs.set("day", 16)
	var sq_d16_view: Dictionary = PanelBuilder.build("sanquan", gs, data)
	var sq_d16_slots := _collect_slot_ids(sq_d16_view)
	if sq_d16_slots.has("x_violence"):
		failed += _ok("第 16 天山泉閣暴力對人槽正常出現")
	else:
		failed += _fail("第 16 天山泉閣應出現 x_violence")

	# 與阿婕達疑似後：x_lust_ajie 出現
	gs.call("add_relation", "ajie", 5) # 達疑似
	var sq_rel_view: Dictionary = PanelBuilder.build("sanquan", gs, data)
	var sq_rel_slots := _collect_slot_ids(sq_rel_view)
	if sq_rel_slots.has("x_lust_ajie"):
		failed += _ok("阿婕達疑似關係後 x_lust_ajie 正常出現")
	else:
		failed += _fail("阿婕達疑似後山泉閣應出現 x_lust_ajie")

	# 老街奢侈出口：恆呈 LOCKED 且附理由
	var os_view: Dictionary = PanelBuilder.build("oldstreet", gs, data)
	var splurge_slot := _find_slot_view(os_view, "x_splurge")
	if splurge_slot.is_empty():
		failed += _fail("老街應包含 x_splurge")
	else:
		if int(splurge_slot.get("tri", -1)) == PanelBuilder.TriState.LOCKED and not str(splurge_slot.get("reason", "")).is_empty():
			failed += _ok("老街奢侈出口呈 LOCKED 並附理由：%s" % str(splurge_slot.get("reason")))
		else:
			failed += _fail("老街奢侈出口應呈 LOCKED")

	# 槽型別標示檢查：出口槽顯示「發狂卡」
	var smash_slot := _find_slot_view(sq_view, "x_smash")
	var accept_types: PackedStringArray = smash_slot.get("accept_types", PackedStringArray())
	if accept_types.has("發狂卡"):
		failed += _ok("出口槽顯示型別標示為「發狂卡」")
	else:
		failed += _fail("出口槽 accept_types 應含「發狂卡」；實際：%s" % str(accept_types))

	return failed


# ── 2. 主動縱慾成功路徑（砸東西）────────────────────────────────────────────

func _test_active_indulgence_smash(gs: Node, data: Node) -> int:
	var failed := 0
	gs.call("end_run")
	gs.set("day", 2)
	gs.set("phase", "morning")
	gs.call("gain_card", "madness") # madness#1

	var init_count: int = int(gs.get("indulgence_count"))
	var result: Dictionary = gs.call("try_place", "madness#1", "exit_sanquan", "x_smash")
	if not result.get("ok", false):
		failed += _fail("放發狂卡進 x_smash 失敗：%s" % str(result))
		return failed

	# 斷言：卡片消失、消耗行動格、indulgence_count +1、套 on_place 旗標
	if gs.call("has_card", "madness#1"):
		failed += _fail("放卡縱慾後 madness#1 應從手牌消失")
	else:
		failed += _ok("放卡縱慾後 madness#1 已從手牌移除")

	if not bool(gs.get("action_spent")):
		failed += _fail("放卡縱慾後 action_spent 應為 true")
	else:
		failed += _ok("放卡縱慾後該時段行動格已消耗 (action_spent = true)")

	var new_count: int = int(gs.get("indulgence_count"))
	if new_count != init_count + 1:
		failed += _fail("indulgence_count 應 +1；實際：%d" % new_count)
	else:
		failed += _ok("indulgence_count 正確累計為 1")

	var flags: Dictionary = gs.get("flags")
	if not flags.get("inn_damaged", false):
		failed += _fail("on_place 效果 inn_damaged 未生效")
	else:
		failed += _ok("on_place flag (inn_damaged) 正確生效")

	# 同一時段不能再放主角卡（以 D2 afternoon d2_pm_work 驗證）
	gs.set("phase", "afternoon")
	gs.set("action_spent", true)
	var protag_res: Dictionary = gs.call("try_place", "protagonist", "d2_pm_work", "work")
	if protag_res.get("ok", true) or str(protag_res.get("reason_code", "")) != "action_spent":
		failed += _fail("行動格已消耗時放主角卡應被拒絕 (action_spent)；實際：%s" % str(protag_res))
	else:
		failed += _ok("縱慾消耗行動格後，同一時段無法再放主角卡")

	# 同一時段再縱慾一次應被行動格擋下（不是被「槽已放過」擋下）
	gs.call("gain_card", "madness") # madness#2
	var same_phase_res: Dictionary = gs.call("indulge", "exit_sanquan", "x_smash", "madness#2")
	if same_phase_res.get("ok", true) or str(same_phase_res.get("reason_code", "")) != "action_spent":
		failed += _fail("同一時段重複縱慾應被 action_spent 擋下；實際：%s" % str(same_phase_res))
	else:
		failed += _ok("同一時段無法再縱慾一次（行動格已用）")

	# 換到下一個行動時段：同一個出口槽必須可以再用（K-54）。
	# 出口 beat 的 when 是 day_from 1 → day_to 45，若寫進 slots_placed 就會變成一輪只能用一次。
	gs.set("action_spent", false)
	var reuse_res: Dictionary = gs.call("indulge", "exit_sanquan", "x_smash", "madness#2")
	if not reuse_res.get("ok", false):
		failed += _fail("換一個行動時段後同一出口槽應可再用；實際：%s" % str(reuse_res))
	elif int(gs.get("indulgence_count")) != init_count + 2:
		failed += _fail("重複使用同一出口後 indulgence_count 應為 %d；實際：%d" % [
			init_count + 2, int(gs.get("indulgence_count"))
		])
	elif (gs.get("slots_placed") as Dictionary).has("exit_sanquan::x_smash"):
		failed += _fail("縱慾不得寫入 slots_placed（會讓常駐出口 beat 一輪只能用一次）")
	else:
		failed += _ok("同一出口槽跨時段可重複使用，且未寫入 slots_placed (K-54)")

	# 跨日同樣成立：第 3 天再用一次同一個出口
	gs.set("day", 3)
	gs.set("phase", "morning")
	gs.set("action_spent", false)
	gs.call("gain_card", "madness") # madness#3
	var next_day_res: Dictionary = gs.call("indulge", "exit_sanquan", "x_smash", "madness#3")
	if not next_day_res.get("ok", false):
		failed += _fail("跨日後同一出口槽應可再用；實際：%s" % str(next_day_res))
	else:
		failed += _ok("同一出口槽跨日可重複使用")

	return failed


# ── 3. 泡湯特例 ─────────────────────────────────────────────────────────────

func _test_soak_morning_vs_afternoon(gs: Node, data: Node) -> int:
	var failed := 0
	gs.call("end_run")
	gs.set("day", 5)
	gs.set("phase", "morning")
	gs.call("gain_card", "madness") # madness#1
	gs.call("gain_card", "madness") # madness#2

	# 上午發動泡湯：消耗當日 2 格行動格，時段維持 morning，清掉指定的一張
	var soak_res: Dictionary = gs.call("indulge", "exit_sanquan", "x_soak", "madness#1")
	if not soak_res.get("ok", false):
		failed += _fail("上午發動泡湯失敗：%s" % str(soak_res))
	else:
		if str(gs.get("phase")) != "morning":
			failed += _fail("泡湯不應跳時段，當前時段應維持 morning；實際：%s" % str(gs.get("phase")))
		else:
			failed += _ok("上午泡湯時段維持 morning（不跳時段）")

		if not bool(gs.get("action_spent")):
			failed += _fail("上午泡湯後 morning 的 action_spent 應為 true")
		else:
			failed += _ok("上午泡湯後 morning action_spent = true")

		if gs.call("has_card", "madness#1"):
			failed += _fail("madness#1 應被清除")
		elif not gs.call("has_card", "madness#2"):
			failed += _fail("madness#2 應保留在手上（只清 1 張）")
		else:
			failed += _ok("泡湯依 tuning.soak_cards_cleared 只清除玩家指定之 1 張發狂卡，其餘保留")

		# 推進至 afternoon：下午行動格應自動呈現已消耗 (action_spent = true)
		gs.call("advance_phase")
		if str(gs.get("phase")) != "afternoon":
			failed += _fail("推進後時段應為 afternoon；實際：%s" % str(gs.get("phase")))
		elif not bool(gs.get("action_spent")):
			failed += _fail("泡湯吃 2 格後，下午時段 action_spent 應自動為 true")
		else:
			failed += _ok("推進至 afternoon 後，下午行動格已預先扣除 (action_spent = true)")

		# 推進至 evening
		gs.call("advance_phase")
		if str(gs.get("phase")) != "evening":
			failed += _fail("推進後時段應為 evening；實際：%s" % str(gs.get("phase")))
		else:
			failed += _ok("再次推進正常進入 evening")

	# 下午點泡湯：三態呈 LOCKED 且理由為只能在上午發動
	gs.call("end_run")
	gs.set("day", 5)
	gs.set("phase", "afternoon")
	gs.call("gain_card", "madness") # madness#1
	var sq_pm_view: Dictionary = PanelBuilder.build("sanquan", gs, data)
	var soak_slot_pm := _find_slot_view(sq_pm_view, "x_soak")
	if int(soak_slot_pm.get("tri", -1)) != PanelBuilder.TriState.LOCKED:
		failed += _fail("下午泡湯槽應呈 LOCKED；實際：%d" % int(soak_slot_pm.get("tri", -1)))
	else:
		failed += _ok("下午泡湯槽呈 LOCKED（理由：%s）" % str(soak_slot_pm.get("reason")))

	var pm_indulge_res: Dictionary = gs.call("indulge", "exit_sanquan", "x_soak", "madness#1")
	if pm_indulge_res.get("ok", true) or str(pm_indulge_res.get("reason_code", "")) != "locked":
		failed += _fail("下午呼叫 indulge 泡湯應被拒絕 (locked)；實際：%s" % str(pm_indulge_res))
	else:
		failed += _ok("下午呼叫 indulge 泡湯被正確拒絕且 GameState 零變化")

	# 上午行動格已用時（格數不足）：
	gs.call("end_run")
	gs.set("day", 5)
	gs.set("phase", "morning")
	gs.set("action_spent", true)
	gs.call("gain_card", "madness")
	var sq_spent_view: Dictionary = PanelBuilder.build("sanquan", gs, data)
	var soak_spent_slot := _find_slot_view(sq_spent_view, "x_soak")
	if int(soak_spent_slot.get("tri", -1)) != PanelBuilder.TriState.LOCKED:
		failed += _fail("上午已消耗行動格時泡湯應呈 LOCKED")
	else:
		failed += _ok("上午格數不足時泡湯呈 LOCKED（理由：%s）" % str(soak_spent_slot.get("reason")))

	var spent_soak_res: Dictionary = gs.call("indulge", "exit_sanquan", "x_soak", "madness#1")
	if spent_soak_res.get("ok", true):
		failed += _fail("格數不足時泡湯應被拒絕")
	else:
		failed += _ok("格數不足時呼叫泡湯被正確拒絕")

	return failed


# ── 4. 拒絕路徑零變化 ───────────────────────────────────────────────────────

func _test_indulgence_rejection_paths(gs: Node, data: Node) -> int:
	var failed := 0
	gs.call("end_run")
	gs.set("day", 2)
	gs.set("phase", "morning")
	gs.call("gain_card", "madness") # madness#1

	var before_state: Dictionary = gs.call("serialize")

	# 1. 卡不在手上
	var r1: Dictionary = gs.call("indulge", "exit_sanquan", "x_smash", "madness#999")
	if r1.get("ok", true) or str(r1.get("reason_code", "")) != "not_held":
		failed += _fail("未持有的卡應回傳 not_held")
	else:
		failed += _ok("未持有的卡 indulge 拒絕 (not_held)")

	# 2. 非發狂卡放出口槽
	var r2: Dictionary = gs.call("try_place", "protagonist", "exit_sanquan", "x_smash")
	if r2.get("ok", true) or str(r2.get("reason_code", "")) != "not_accepted":
		failed += _fail("非發狂卡放出口槽應回傳 not_accepted；實際：%s" % str(r2))
	else:
		failed += _ok("非發狂卡放出口槽拒絕 (not_accepted)")

	# 3. 非縱慾槽呼叫 indulge
	var r3: Dictionary = gs.call("indulge", "d2_pm_work", "work", "madness#1")
	if r3.get("ok", true) or str(r3.get("reason_code", "")) != "not_accepted":
		failed += _fail("非縱慾槽呼叫 indulge 應回傳 not_accepted")
	else:
		failed += _ok("非縱慾槽呼叫 indulge 拒絕 (not_accepted)")

	# 斷言：拒絕路徑下 GameState 零變化
	var after_state: Dictionary = gs.call("serialize")
	if before_state != after_state:
		failed += _fail("拒絕路徑下 GameState 發生了變化")
	else:
		failed += _ok("所有拒絕路徑皆保證 GameState 零變化")

	return failed


# ── 5. 強度等級與追加效果 ───────────────────────────────────────────────────

func _test_indulgence_level_escalation(gs: Node, data: Node) -> int:
	var failed := 0
	var tuning: Dictionary = data.loader.tuning

	# 查表驗證：1 -> light, 2..7 -> normal, 8 -> heavy
	if Indulgence.level_for(1, tuning) != "light":
		failed += _fail("第 1 次縱慾應為 light")
	if Indulgence.level_for(2, tuning) != "normal" or Indulgence.level_for(7, tuning) != "normal":
		failed += _fail("第 2~7 次縱慾應為 normal")
	if Indulgence.level_for(8, tuning) != "heavy":
		failed += _fail("第 8 次縱慾應為 heavy")
	failed += _ok("Indulgence.level_for 強度級查表正確 (1=light, 2~7=normal, 8=heavy)")

	# 實測追加效果套用：
	gs.call("end_run")
	gs.set("day", 17)
	gs.set("phase", "morning")
	gs.call("gain_card", "madness") # madness#1

	# 第 1 次（light）：套 on_place 與 light 追加文字
	var r_light: Dictionary = gs.call("indulge", "exit_sanquan", "x_violence", "madness#1")
	if not r_light.get("ok", false):
		failed += _fail("第 1 次暴力縱慾失敗：%s" % str(r_light))
	else:
		var lines: PackedStringArray = r_light.get("lines", PackedStringArray())
		var has_light_text := false
		for line in lines:
			if "突如其來的暴力" in line:
				has_light_text = true
		if has_light_text:
			failed += _ok("第 1 次縱慾套用 light 追加效果文字")
		else:
			failed += _fail("第 1 次縱慾未套用 light 追加文字；實際：%s" % str(lines))

	return failed


# ── 6. When 常駐日期範圍解析 ───────────────────────────────────────────────

func _test_when_day_from_parsing(data: Node) -> int:
	var failed := 0
	var loader: DataLoader = data.loader

	var d1_beats := loader.beats_at(1, "morning")
	var d23_beats := loader.beats_at(23, "morning")
	var d45_beats := loader.beats_at(45, "afternoon")
	var evening_beats := loader.beats_at(1, "evening")

	var has_d1 := false
	for b in d1_beats:
		if str(b.get("id")) == "exit_sanquan": has_d1 = true
	var has_d23 := false
	for b in d23_beats:
		if str(b.get("id")) == "exit_sanquan": has_d23 = true
	var has_d45 := false
	for b in d45_beats:
		if str(b.get("id")) == "exit_sanquan": has_d45 = true
	var has_eve := false
	for b in evening_beats:
		if str(b.get("id")) == "exit_sanquan": has_eve = true

	if has_d1 and has_d23 and has_d45 and not has_eve:
		failed += _ok("when.day_from/day_to 與 phase 陣列在 D1, D23, D45 上午/下午均成立，在 evening 不成立")
	else:
		failed += _fail("when.day_from 解析結果不符：d1=%s, d23=%s, d45=%s, eve=%s" % [
			str(has_d1), str(has_d23), str(has_d45), str(has_eve)
		])

	return failed


# ── 7. Conflicting When Fixture ─────────────────────────────────────────────

func _test_conflicting_when_fixture() -> int:
	var failed := 0
	var broken_loader := DataLoader.new("res://tests/fixtures/broken/conflicting_when/")
	var ok := broken_loader.load_all()
	if ok:
		failed += _fail("同時包含 day 與 day_from 的 fixture 載入應回傳 false")
	else:
		var has_err := false
		for e in broken_loader.errors:
			if "when 同時包含 day 與 day_from" in e:
				has_err = true
		if has_err:
			failed += _ok("conflicting_when fixture 正確觸發載入錯誤")
		else:
			failed += _fail("未找到預期的 when 衝突錯誤訊息；實際：%s" % str(broken_loader.errors))

	return failed


# ── 8. Lint 4 與 Lint 10 驗證 ───────────────────────────────────────────────

func _test_lint_4_and_10(data: Node) -> int:
	var failed := 0
	var loader: DataLoader = data.loader

	var lint4_errs := DataLoader.lint_indulgence_integrity(loader)
	if not lint4_errs.is_empty():
		failed += _fail("Lint 4 (縱慾完整性) 失敗：%s" % str(lint4_errs))
	else:
		failed += _ok("Lint 4 (縱慾完整性) 通過：1-45 天均有保底縱慾出口")

	var lint10_errs := DataLoader.lint_indulgence_exits(loader.beats)
	if not lint10_errs.is_empty():
		failed += _fail("Lint 10 (縱慾出口資料完整性) 失敗：%s" % str(lint10_errs))
	else:
		failed += _ok("Lint 10 (縱慾出口資料完整性) 通過")

	return failed


# ── 9. 序列化往返 ──────────────────────────────────────────────────────────

func _test_serialize_roundtrip_p2b(gs: Node) -> int:
	var failed := 0
	gs.call("end_run")
	gs.set("day", 10)
	gs.set("phase", "morning")
	gs.set("indulgence_count", 4)
	gs.set("action_spent", true)
	(gs.get("slots_placed") as Dictionary)["exit_sanquan::x_smash"] = true

	var d: Dictionary = gs.call("serialize")

	var gs2: Node = load("res://scripts/autoload/game_state.gd").new()
	gs2.name = "GameState2"
	get_root().add_child(gs2)
	gs2.call("deserialize", d)

	if int(gs2.get("indulgence_count")) != 4:
		failed += _fail("deserialize 後 indulgence_count 不符")
	elif not (gs2.get("slots_placed") as Dictionary).has("exit_sanquan::x_smash"):
		failed += _fail("deserialize 後 slots_placed 不符")
	else:
		failed += _ok("序列化往返完整保留 P2-B 狀態 (indulgence_count, slots_placed)")

	gs2.queue_free()
	return failed


# ── 10. end_run 重置 ───────────────────────────────────────────────────────

func _test_end_run_resets_p2b(gs: Node) -> int:
	var failed := 0
	gs.set("indulgence_count", 5)
	(gs.get("slots_placed") as Dictionary)["exit_sanquan::x_smash"] = true

	gs.call("end_run")

	if int(gs.get("indulgence_count")) != 0:
		failed += _fail("end_run 後 indulgence_count 未重置為 0")
	elif not (gs.get("slots_placed") as Dictionary).is_empty():
		failed += _fail("end_run 後 slots_placed 未清空")
	else:
		failed += _ok("end_run 正確重置 indulgence_count 與 slots_placed")

	return failed


# ── 輔助工具 ───────────────────────────────────────────────────────────────

func _collect_slot_ids(view: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for bv in view.get("beats", []):
		for sv in bv.get("slots", []):
			var s: Dictionary = sv.get("slot", {})
			result.append(str(s.get("id", "")))
	return result


func _find_slot_view(view: Dictionary, slot_id: String) -> Dictionary:
	for bv in view.get("beats", []):
		for sv in bv.get("slots", []):
			var s: Dictionary = sv.get("slot", {})
			if str(s.get("id", "")) == slot_id:
				return sv
	return {}
