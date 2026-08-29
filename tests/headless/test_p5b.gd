extends SceneTree

## P5-B 頂層流程與結局狀態機測試（實作規格書 P5-B、測試指南 P5-B）。
## 涵蓋：三種 mode 的跨 mode 封鎖、legacy checkpoint 遷移、start_ending 快照凍結、
## 逐頁 reveal／advance／skip、序列化往返與壞形狀、兩階段效果與 ending request 衝突、
## D45 phase_exit 端到端、source 配對矩陣與拒絕順序。
## 跑法：Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/test_p5b.gd

const PlaythroughGreedy := preload("res://tests/headless/playthrough_greedy.gd")

var _failed := 0


func _initialize() -> void:
	var data_node: Node = PlaythroughGreedy.setup_data(self)
	var gs: Node = PlaythroughGreedy.setup_game_state(self, data_node)
	await process_frame

	if not bool(data_node.get("ok")):
		push_error("P5-B: Data 載入失敗，中止")
		quit(1)
		return

	print("=== P5-B 頂層流程與結局狀態機測試 ===")
	_test_1_cross_mode_blocking(gs)
	_test_2_legacy_checkpoint_migration(gs)
	_test_3_snapshot_freeze(gs)
	_test_4_run_mutations_blocked_in_ending(gs)
	_test_5_page_typewriter(gs)
	_test_6_skip_requires_seen(gs)
	_test_7_serialization(gs)
	_test_8_two_phase_effects(gs, data_node)
	_test_9_source_matrix(gs)
	_test_10_rejection_order(gs)
	_test_11_action_atomicity(gs, data_node)
	_test_12_d45_lifecycle(gs)

	if _failed > 0:
		push_error("test_p5b: %d 個斷言失敗" % _failed)
		quit(1)
	else:
		print("\n=== P5-B 全部測試通過 ===")
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


## 完整序列化的逐字快照，用來驗「拒絕後零變化」。
func _state_text(gs: Node) -> String:
	return JSON.stringify(gs.call("serialize"))


## 乾淨的 run：清掉上一段測試的所有殘留，含 flow 層與 meta 歷輪。
func _fresh_run(gs: Node, day: int = 20, phase: String = "morning") -> void:
	gs.call("end_run", "test_reset")
	gs.set("day", day)
	gs.set("phase", phase)
	gs.set("ending_history", [] as Array[Dictionary])
	gs.set("run_number", 1)
	(gs.get("knowledge") as Dictionary).clear()
	(gs.get("knowledge_at_start") as Dictionary).clear()
	(gs.get("night_locations_seen") as Dictionary).clear()
	gs.set("selected_festival_proxy_npc", "")
	gs.set("opening_choice_id", "")


## 直接把 flow.mode 換成 opening（P5-B 尚無 choose_opening()，依方針用明示 fixture 建立）。
func _force_opening_mode(gs: Node) -> void:
	var state: Dictionary = gs.call("serialize")
	(state["flow"] as Dictionary)["mode"] = "opening"
	var res: Dictionary = gs.call("deserialize", state)
	if not bool(res.get("ok", false)):
		_fail("_force_opening_mode: deserialize 失敗")


func _reject_code(res: Dictionary) -> String:
	return str(res.get("reason_code", ""))


## 進入一個可播放的 ending_replaced（凍結代付者為阿婕）。
func _enter_replaced_ending(gs: Node) -> Dictionary:
	_fresh_run(gs, 45, "evening")
	gs.set("selected_festival_proxy_npc", "ajie")
	return gs.call("start_ending", "ending_replaced", "d45_coda")


# ── 1. 跨 mode 封鎖 ──────────────────────────────────────────────────────────

func _test_1_cross_mode_blocking(gs: Node) -> void:
	print("\n--- 1. 三種 mode 的跨 mode 封鎖 ---")

	# (a) run mode：ending 專用 mutation 全部 not_ending，且狀態零變化
	_fresh_run(gs)
	_check(str(gs.get("flow_mode")) == "run", "fresh boot 暫維持 legacy run mode")
	var before := _state_text(gs)
	_check(_reject_code(gs.call("reveal_ending_page")) == "not_ending", "run mode reveal_ending_page → not_ending")
	_check(_reject_code(gs.call("advance_ending_page")) == "not_ending", "run mode advance_ending_page → not_ending")
	_check(_reject_code(gs.call("skip_seen_ending")) == "not_ending", "run mode skip_seen_ending → not_ending")
	_check((gs.call("ending_view") as Dictionary).is_empty(), "run mode ending_view 回空字典")
	_check(_state_text(gs) == before, "run mode 拒絕三個 ending mutation 後序列化零變化")

	# (b) opening mode：run 與 ending mutation 都被擋
	_force_opening_mode(gs)
	_check(str(gs.get("flow_mode")) == "opening", "明示 fixture 建立 opening mode")
	var before_opening := _state_text(gs)
	_check(_reject_code(gs.call("advance_phase")) == "not_run", "opening mode advance_phase → not_run")
	_check(_reject_code(gs.call("try_place", "protagonist", "d20_am_clinic", "care")) == "not_run", "opening mode try_place → not_run")
	_check(_reject_code(gs.call("reveal_ending_page")) == "not_ending", "opening mode reveal_ending_page → not_ending")
	_check(_state_text(gs) == before_opening, "opening mode 拒絕後序列化零變化")

	# (c) ending mode：run mutation 全擋（詳細清單見第 4 組）
	var start_res := _enter_replaced_ending(gs)
	_check(bool(start_res.get("ok", false)), "start_ending(ending_replaced, d45_coda) 成功")
	_check(str(gs.get("flow_mode")) == "ending", "start_ending 後 mode 為 ending")
	_check(_reject_code(gs.call("advance_phase")) == "not_run", "ending mode advance_phase → not_run")


# ── 2. legacy checkpoint 遷移 ────────────────────────────────────────────────

func _test_2_legacy_checkpoint_migration(gs: Node) -> void:
	print("\n--- 2. 無 flow 的舊 checkpoint 遷移 ---")

	_fresh_run(gs, 30, "morning")
	gs.call("gain_card", "k_forty_something")
	var legacy: Dictionary = gs.call("serialize")
	legacy.erase("flow")
	(legacy["run"] as Dictionary).erase("opening_choice_id")
	(legacy["run"] as Dictionary).erase("selected_festival_proxy_npc")
	(legacy["run"] as Dictionary).erase("knowledge_at_start")
	(legacy["meta"] as Dictionary).erase("run_number")
	(legacy["meta"] as Dictionary).erase("ending_history")
	(legacy["meta"] as Dictionary).erase("loop_persistent_item_ids")

	var res: Dictionary = gs.call("deserialize", legacy)
	_check(bool(res.get("ok", false)), "舊 checkpoint 載入成功")
	_check(str(gs.get("flow_mode")) == "run", "無 flow 的舊 checkpoint 遷移為 run")
	_check((gs.get("active_ending") as Dictionary).is_empty(), "遷移後 active_ending 為 null")
	_check(str(gs.get("opening_choice_id")).is_empty(), "遷移後 opening_choice_id 為 null")
	_check(str(gs.get("selected_festival_proxy_npc")).is_empty(), "遷移後 selected_festival_proxy_npc 為 null")
	_check(int(gs.get("run_number")) == 1, "遷移後 run_number 補規格初值 1")

	var start_set: Dictionary = gs.get("knowledge_at_start") as Dictionary
	var now_set: Dictionary = gs.get("knowledge") as Dictionary
	_check(start_set.has("k_forty_something") and start_set.size() == now_set.size(),
		"knowledge_at_start 等於載入當下的 meta knowledge")

	# 立刻啟動結局：舊知識不得算成本輪新增
	gs.set("selected_festival_proxy_npc", "ajie")
	var start_res: Dictionary = gs.call("start_ending", "ending_replaced", "d45_coda")
	_check(bool(start_res.get("ok", false)), "遷移後可直接啟動結局")
	var snapshot: Dictionary = gs.get("active_ending") as Dictionary
	_check((snapshot.get("knowledge_gained_this_run", []) as Array).is_empty(),
		"舊 knowledge 不被算成 knowledge_gained_this_run")
	_check(snapshot.get("opening_choice_id") == null, "legacy run 的快照 opening_choice_id 為 null")


# ── 3. start_ending 一次凍結 ─────────────────────────────────────────────────

func _test_3_snapshot_freeze(gs: Node) -> void:
	print("\n--- 3. start_ending 快照凍結與前置檢查 ---")

	_fresh_run(gs, 45, "evening")
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["invited_ajie"] = true
	(gs.get("flags") as Dictionary)["accepted_inn"] = true
	(gs.get("flags") as Dictionary)["repaired_sign"] = true
	gs.call("gain_card", "k_forty_something")

	var res: Dictionary = gs.call("start_ending", "ending_replaced", "d45_coda")
	_check(bool(res.get("ok", false)), "正常結局啟動成功")

	var snapshot: Dictionary = gs.get("active_ending") as Dictionary
	_check(int(snapshot.get("ended_day", 0)) == 45 and str(snapshot.get("ended_phase", "")) == "evening",
		"快照凍結結束日與時段")
	_check(str(snapshot.get("partner_variant", "")) == "ajie", "快照凍結伴侶 variant＝ajie")
	_check(str(snapshot.get("livelihood_variant", "")) == "uncle", "快照凍結生計 variant＝uncle")
	_check(str(snapshot.get("inn_appearance_variant", "")) == "sign", "快照凍結旅館 variant＝sign")
	_check(str(snapshot.get("festival_proxy_npc", "")) == "ajie", "快照凍結慶典代付者")
	_check((snapshot.get("knowledge_gained_this_run", []) as Array).has("k_forty_something"),
		"快照凍結當輪新增知識")
	_check((snapshot.get("page_refs", []) as Array).size() > 0, "快照凍結 page refs")

	var first_text := str((gs.call("ending_view") as Dictionary).get("page_text", ""))

	# 故意改原 run dictionaries：ending view 仍讀快照，不重算
	(gs.get("flags") as Dictionary)["invited_ajie"] = false
	(gs.get("flags") as Dictionary)["invited_awei"] = true
	gs.set("selected_festival_proxy_npc", "acai")
	var snapshot_after: Dictionary = gs.get("active_ending") as Dictionary
	_check(str(snapshot_after.get("partner_variant", "")) == "ajie", "改 run flags 後快照 variant 不變")
	_check(str((gs.call("ending_view") as Dictionary).get("page_text", "")) == first_text,
		"改 run 狀態後 ending view 仍讀快照")

	# ending_view 不得洩漏內部欄位
	var view: Dictionary = gs.call("ending_view")
	var expected_keys := ["page_text", "page_index", "page_count", "page_revealed", "is_last_page", "can_skip", "can_complete"]
	var view_keys := view.keys()
	view_keys.sort()
	var want_keys := expected_keys.duplicate()
	want_keys.sort()
	_check(view_keys == want_keys, "ending_view 只回玩家可見欄位（不含 ending id／conditions）")

	# 代付者為空或非候選 → data_conflict 且零變化
	_fresh_run(gs, 45, "evening")
	var before_empty := _state_text(gs)
	var empty_res: Dictionary = gs.call("start_ending", "ending_replaced", "d45_coda")
	_check(_reject_code(empty_res) == "data_conflict", "代付者為空啟動正常結局 → data_conflict")
	_check(_state_text(gs) == before_empty, "代付者為空拒絕後序列化零變化")

	gs.set("selected_festival_proxy_npc", "azhu")
	var before_bad := _state_text(gs)
	var bad_res: Dictionary = gs.call("start_ending", "ending_replaced", "d45_coda")
	_check(_reject_code(bad_res) == "data_conflict", "代付者非正式候選 → data_conflict")
	_check(_state_text(gs) == before_bad, "代付者非候選拒絕後序列化零變化")

	# 代付者前置是 start_ending 自己的責任，不能只靠 resolver 的片段查表失敗來擋：
	# 伴侶命中阿婕時 uninvited_proxy fragment 不啟用，resolver 本身根本不需要代付者，
	# 這種路徑下空值／非候選仍然必須被前置檢查擋下。
	_fresh_run(gs, 45, "evening")
	(gs.get("flags") as Dictionary)["invited_ajie"] = true
	var before_no_frag := _state_text(gs)
	_check(_reject_code(gs.call("start_ending", "ending_replaced", "d45_coda")) == "data_conflict",
		"resolver 不需要代付片段時，空代付者仍被前置檢查擋下")
	_check(_state_text(gs) == before_no_frag, "該路徑拒絕後序列化零變化")

	gs.set("selected_festival_proxy_npc", "azhu")
	var before_bad_frag := _state_text(gs)
	_check(_reject_code(gs.call("start_ending", "ending_replaced", "d45_coda")) == "data_conflict",
		"resolver 不需要代付片段時，非候選代付者仍被前置檢查擋下")
	_check(_state_text(gs) == before_bad_frag, "該路徑拒絕後序列化零變化（非候選）")

	# 同一路徑換成合法候選就必須成功，證明上面兩條紅的是前置檢查而不是別的東西
	gs.set("selected_festival_proxy_npc", "awei")
	_check(bool((gs.call("start_ending", "ending_replaced", "d45_coda") as Dictionary).get("ok", false)),
		"同一路徑換成合法候選即可啟動")


# ── 4. ending mode 封鎖所有 run mutation ─────────────────────────────────────

func _test_4_run_mutations_blocked_in_ending(gs: Node) -> void:
	print("\n--- 4. ending mode 封鎖 run mutation ---")

	var start_res := _enter_replaced_ending(gs)
	_check(bool(start_res.get("ok", false)), "進入 ending mode")
	var before := _state_text(gs)

	var calls := {
		"advance_phase": gs.call("advance_phase"),
		"resolve_night_advance": gs.call("resolve_night_advance"),
		"enter_night_location": gs.call("enter_night_location", "n_source"),
		"try_place": gs.call("try_place", "protagonist", "d45_then", "compare_registry"),
		"choose": gs.call("choose", "d29_invitation", "invitation", "invite_none"),
		"delegate": gs.call("delegate", "d17_am_ask", "ask_ajie", "person_ajie"),
		"indulge": gs.call("indulge", "d20_pm_smash", "smash", "madness#1"),
		"start_encounter": gs.call("start_encounter", "d8_night"),
		"respond_to_encounter": gs.call("respond_to_encounter", "protagonist"),
		"confirm_night_alignment": gs.call("confirm_night_alignment", "jinghe_back"),
	}
	for name: String in calls.keys():
		_check(str((calls[name] as Dictionary).get("reason_code", "")) == "not_run", "ending mode %s → not_run" % name)

	_check((gs.call("sleep_night") as PackedStringArray).is_empty(), "ending mode sleep_night 不產生任何演出")
	_check((gs.call("play_evening") as PackedStringArray).is_empty(), "ending mode play_evening 不產生任何演出")
	_check((gs.call("play_night_fixed") as PackedStringArray).is_empty(), "ending mode play_night_fixed 不產生任何演出")
	_check((gs.call("play_beat", "d45_then") as PackedStringArray).is_empty(), "ending mode play_beat 不產生任何演出")

	_check(_state_text(gs) == before, "ending mode 全部 run mutation 拒絕後序列化逐字相同")


# ── 5. 逐字與翻頁 ────────────────────────────────────────────────────────────

func _test_5_page_typewriter(gs: Node) -> void:
	print("\n--- 5. reveal／advance 逐字與翻頁 ---")

	_enter_replaced_ending(gs)
	var view: Dictionary = gs.call("ending_view")
	_check(int(view.get("page_index", -1)) == 0 and not bool(view.get("page_revealed", true)),
		"進入結局時停在第 0 頁且尚未揭露")
	_check(int(view.get("page_count", 0)) >= 2, "正常結局首見至少兩頁（page_count=%d）" % int(view.get("page_count", 0)))

	_check(_reject_code(gs.call("advance_ending_page")) == "page_not_revealed", "未揭露就翻頁 → page_not_revealed")

	var before_reveal := _state_text(gs)
	var reveal_res: Dictionary = gs.call("reveal_ending_page")
	_check(bool(reveal_res.get("ok", false)), "reveal_ending_page 成功")
	var after_reveal: Dictionary = gs.get("active_ending") as Dictionary
	_check(int(after_reveal.get("page_index", -1)) == 0, "reveal 不動頁碼")
	_check(bool(after_reveal.get("page_revealed", false)), "reveal 只把當頁標為已揭露")
	_check(not bool(after_reveal.get("ready_to_complete", true)), "非末頁 reveal 不設 ready_to_complete")
	_check(before_reveal != _state_text(gs), "reveal 確實改變狀態")

	_check(_reject_code(gs.call("reveal_ending_page")) == "already_revealed", "第二次 reveal → already_revealed")

	var advance_res: Dictionary = gs.call("advance_ending_page")
	_check(bool(advance_res.get("ok", false)), "已揭露後可翻頁")
	var after_advance: Dictionary = gs.get("active_ending") as Dictionary
	_check(int(after_advance.get("page_index", -1)) == 1, "翻頁只加一頁")
	_check(not bool(after_advance.get("page_revealed", true)), "翻頁後新頁尚未揭露")

	# 走到末頁：揭露末頁同一步設 ready_to_complete
	var guard := 0
	while guard < 64:
		guard += 1
		var v: Dictionary = gs.call("ending_view")
		if bool(v.get("is_last_page", false)):
			break
		if not bool(v.get("page_revealed", false)):
			gs.call("reveal_ending_page")
		else:
			gs.call("advance_ending_page")
	gs.call("reveal_ending_page")
	var final_snapshot: Dictionary = gs.get("active_ending") as Dictionary
	_check(bool(final_snapshot.get("ready_to_complete", false)), "揭露末頁同一步設 ready_to_complete")
	_check(bool((gs.call("ending_view") as Dictionary).get("can_complete", false)), "ending_view can_complete 為 true")

	# last_page：合法形狀但尚未 ready（末頁已揭露、ready 仍為 false）時翻頁必須擋下
	var last_page_snapshot: Dictionary = gs.get("active_ending") as Dictionary
	last_page_snapshot["ready_to_complete"] = false
	_check(_reject_code(gs.call("advance_ending_page")) == "last_page", "末頁已揭露時翻頁 → last_page")
	last_page_snapshot["ready_to_complete"] = true

	# ready 之後三個 page mutation 都先回 wrong_ending_stage
	_check(_reject_code(gs.call("reveal_ending_page")) == "wrong_ending_stage", "ready 後 reveal → wrong_ending_stage")
	_check(_reject_code(gs.call("advance_ending_page")) == "wrong_ending_stage", "ready 後 advance → wrong_ending_stage")
	_check(_reject_code(gs.call("skip_seen_ending")) == "wrong_ending_stage", "ready 後 skip → wrong_ending_stage")


# ── 6. 跳過只在重見時開放 ────────────────────────────────────────────────────

func _test_6_skip_requires_seen(gs: Node) -> void:
	print("\n--- 6. skip_seen_ending 的首見／重見 ---")

	_enter_replaced_ending(gs)
	var before := _state_text(gs)
	_check(_reject_code(gs.call("skip_seen_ending")) == "ending_not_seen", "首見直呼 skip → ending_not_seen")
	_check(not bool((gs.call("ending_view") as Dictionary).get("can_skip", true)), "首見 ending_view can_skip 為 false")
	_check(_state_text(gs) == before, "首見 skip 拒絕後序列化零變化")

	# 造一筆別的 ending history：不同行 ending id 不互相解鎖
	_fresh_run(gs, 45, "evening")
	gs.set("ending_history", [{ "ending_id": "ending_madness_be" }] as Array[Dictionary])
	gs.set("selected_festival_proxy_npc", "ajie")
	gs.call("start_ending", "ending_replaced", "d45_coda")
	_check(_reject_code(gs.call("skip_seen_ending")) == "ending_not_seen", "只有別的 ending history 時仍不得跳過")

	# 同 id history → 重見，可跳到資料指定落點
	_fresh_run(gs, 45, "evening")
	gs.set("ending_history", [{ "ending_id": "ending_replaced" }] as Array[Dictionary])
	gs.set("selected_festival_proxy_npc", "ajie")
	gs.call("start_ending", "ending_replaced", "d45_coda")
	var repeat_refs: Array = (gs.get("active_ending") as Dictionary).get("page_refs", []) as Array
	_check(str(repeat_refs[0]).begins_with("ending_replaced/repeat/"), "重見改用 repeat 分支頁面")
	_check(bool((gs.call("ending_view") as Dictionary).get("can_skip", false)), "重見 ending_view can_skip 為 true")

	var skip_res: Dictionary = gs.call("skip_seen_ending")
	_check(bool(skip_res.get("ok", false)), "重見 skip 成功")
	var skipped: Dictionary = gs.get("active_ending") as Dictionary
	var target_ref := str((skipped.get("page_refs", []) as Array)[int(skipped.get("page_index", 0))])
	_check(target_ref.ends_with("short_return"), "skip 落在資料指定的 short_return（實際：%s）" % target_ref)
	_check(bool(skipped.get("page_revealed", false)) and bool(skipped.get("ready_to_complete", false)),
		"skip 到末頁後同時標記已揭露與可結算")
	_check((gs.get("ending_history") as Array).size() == 1, "skip 不寫 history")


# ── 7. 序列化往返與壞形狀 ────────────────────────────────────────────────────

func _test_7_serialization(gs: Node) -> void:
	print("\n--- 7. active ending 的序列化往返與壞形狀 ---")

	# (a) 三個階段各往返一次
	_enter_replaced_ending(gs)
	_roundtrip_case(gs, "未揭露首頁")

	gs.call("reveal_ending_page")
	gs.call("advance_ending_page")
	gs.call("reveal_ending_page")
	_roundtrip_case(gs, "已揭露中間頁")

	var guard := 0
	while guard < 64:
		guard += 1
		var v: Dictionary = gs.call("ending_view")
		if bool(v.get("is_last_page", false)) and bool(v.get("page_revealed", false)):
			break
		if not bool(v.get("page_revealed", false)):
			gs.call("reveal_ending_page")
		else:
			gs.call("advance_ending_page")
	_roundtrip_case(gs, "已揭露末頁")

	# (b) 壞形狀逐一拒絕，且載入前狀態零變化
	_enter_replaced_ending(gs)
	gs.call("reveal_ending_page")
	var good: Dictionary = gs.call("serialize")

	var bad_cases: Array = [
		["active_ending 錯型別", func(s: Dictionary) -> void: (s["flow"] as Dictionary)["active_ending"] = "ending"],
		["缺 page_refs 欄", func(s: Dictionary) -> void: ((s["flow"] as Dictionary)["active_ending"] as Dictionary).erase("page_refs")],
		["空字串代替 null", func(s: Dictionary) -> void: ((s["flow"] as Dictionary)["active_ending"] as Dictionary)["opening_choice_id"] = ""],
		["失效 page ref", func(s: Dictionary) -> void: ((s["flow"] as Dictionary)["active_ending"] as Dictionary)["page_refs"] = ["ending_replaced/first_seen/prefix_pages/no_such_page"]],
		["page_index 越界", func(s: Dictionary) -> void: ((s["flow"] as Dictionary)["active_ending"] as Dictionary)["page_index"] = 99],
		["run mode 帶 active", func(s: Dictionary) -> void: (s["flow"] as Dictionary)["mode"] = "run"],
		["ending mode 無 active", func(s: Dictionary) -> void:
			(s["flow"] as Dictionary)["active_ending"] = null],
		["未知 mode", func(s: Dictionary) -> void: (s["flow"] as Dictionary)["mode"] = "credits"],
		["source 與 ending 錯配", func(s: Dictionary) -> void: ((s["flow"] as Dictionary)["active_ending"] as Dictionary)["source_id"] = "madness_cap"],
		["page_revealed 錯型別", func(s: Dictionary) -> void: ((s["flow"] as Dictionary)["active_ending"] as Dictionary)["page_revealed"] = 1],
		["多出未定義欄位", func(s: Dictionary) -> void: ((s["flow"] as Dictionary)["active_ending"] as Dictionary)["extra"] = true],
	]

	for case_raw: Variant in bad_cases:
		var case_arr := case_raw as Array
		var label := str(case_arr[0])
		var mutate := case_arr[1] as Callable
		var broken: Dictionary = JSON.parse_string(JSON.stringify(good)) as Dictionary
		mutate.call(broken)
		var before := _state_text(gs)
		var res: Dictionary = gs.call("deserialize", broken)
		_check(not bool(res.get("ok", true)) and str(res.get("reason_code", "")) == "invalid_save_shape",
			"壞存檔「%s」→ invalid_save_shape" % label)
		_check(_state_text(gs) == before, "壞存檔「%s」拒絕後狀態零變化" % label)

	# (c) ending 專屬矩陣：泛用 nullable 過關、但這個 ending 收不起的組合。
	# 先證明基準快照本身合法，錯誤案例才不會是被別道檢查順手擋掉的假綠。
	_enter_replaced_ending(gs)
	gs.call("reveal_ending_page")
	var composite_good: Dictionary = gs.call("serialize")
	_check(bool((gs.call("deserialize", JSON.parse_string(JSON.stringify(composite_good)) as Dictionary) as Dictionary).get("ok", false)),
		"矩陣基準：合法 composite 快照可載入")

	var matrix_cases: Array = [
		["composite 的 partner_variant 為 null", func(s: Dictionary) -> void: _snap(s)["partner_variant"] = null],
		["composite 的 livelihood_variant 為 null", func(s: Dictionary) -> void: _snap(s)["livelihood_variant"] = null],
		["composite 的 inn_appearance_variant 為 null", func(s: Dictionary) -> void: _snap(s)["inn_appearance_variant"] = null],
		["composite 的代付者為 null", func(s: Dictionary) -> void: _snap(s)["festival_proxy_npc"] = null],
		["代付者不是正式候選", func(s: Dictionary) -> void: _snap(s)["festival_proxy_npc"] = "uncle"],
		["composite 沒有結束日", func(s: Dictionary) -> void:
			_snap(s)["ended_day"] = null
			_snap(s)["ended_phase"] = null],
		# 只換掉其中一個 ref，保持頁數、index、revealed、ready 全部不動，
		# 這樣轉紅的只會是「ref 歸屬」那道檢查，不是頁面進度一致性。
		["page ref 指向另一個 ending", func(s: Dictionary) -> void:
			var refs: Array = (_snap(s)["page_refs"] as Array).duplicate()
			refs[refs.size() - 1] = "ending_madness_be/first_seen/pages/madness_lost"
			_snap(s)["page_refs"] = refs],
		["page refs 混用 first_seen 與 repeat", func(s: Dictionary) -> void:
			var refs: Array = (_snap(s)["page_refs"] as Array).duplicate()
			refs.append("ending_replaced/repeat/suffix_pages/short_return")
			_snap(s)["page_refs"] = refs],
		["未到末頁卻 ready_to_complete", func(s: Dictionary) -> void: _snap(s)["ready_to_complete"] = true],
	]
	_reject_saves(gs, composite_good, matrix_cases)

	# 末頁已揭露卻沒有 ready：ready 與頁面進度必須一致，兩個方向都要擋。
	_enter_replaced_ending(gs)
	var guard_last := 0
	while guard_last < 64:
		guard_last += 1
		var v2: Dictionary = gs.call("ending_view")
		if bool(v2.get("is_last_page", false)) and bool(v2.get("page_revealed", false)):
			break
		if not bool(v2.get("page_revealed", false)):
			gs.call("reveal_ending_page")
		else:
			gs.call("advance_ending_page")
	var last_good: Dictionary = gs.call("serialize")
	_check(bool((gs.call("deserialize", JSON.parse_string(JSON.stringify(last_good)) as Dictionary) as Dictionary).get("ok", false)),
		"矩陣基準：末頁已揭露且 ready 的快照可載入")
	_reject_saves(gs, last_good, [
		["末頁已揭露卻 ready_to_complete 為 false", func(s: Dictionary) -> void: _snap(s)["ready_to_complete"] = false],
	])

	# (d) 不上車專屬矩陣。P5-B 的 run 入口不放行這個 ending，因此以手寫快照驗載入面。
	var refuse_good: Dictionary = JSON.parse_string(JSON.stringify(composite_good)) as Dictionary
	(refuse_good["flow"] as Dictionary)["active_ending"] = _refuse_snapshot()
	_check(bool((gs.call("deserialize", JSON.parse_string(JSON.stringify(refuse_good)) as Dictionary) as Dictionary).get("ok", false)),
		"矩陣基準：合法不上車快照可載入")
	_reject_saves(gs, refuse_good, [
		["不上車的 opening_choice_id 不是 refuse_boarding", func(s: Dictionary) -> void: _snap(s)["opening_choice_id"] = "take_family_album"],
		["不上車的 opening_choice_id 為 null", func(s: Dictionary) -> void: _snap(s)["opening_choice_id"] = null],
		["不上車帶結束日", func(s: Dictionary) -> void:
			_snap(s)["ended_day"] = 45
			_snap(s)["ended_phase"] = "evening"],
		["不上車帶代付者", func(s: Dictionary) -> void: _snap(s)["festival_proxy_npc"] = "ajie"],
		["linear ending 帶 partner_variant", func(s: Dictionary) -> void: _snap(s)["partner_variant"] = "ajie"],
	])

	_fresh_run(gs, 20, "morning")


## 壞存檔逐例：精確回 invalid_save_shape，且載入前後完整序列化零變化。
func _reject_saves(gs: Node, good: Dictionary, cases: Array) -> void:
	for case_raw: Variant in cases:
		var case_arr := case_raw as Array
		var label := str(case_arr[0])
		var broken: Dictionary = JSON.parse_string(JSON.stringify(good)) as Dictionary
		(case_arr[1] as Callable).call(broken)
		var before := _state_text(gs)
		var res: Dictionary = gs.call("deserialize", broken)
		_check(not bool(res.get("ok", true)) and str(res.get("reason_code", "")) == "invalid_save_shape",
			"壞存檔「%s」→ invalid_save_shape" % label)
		_check(_state_text(gs) == before, "壞存檔「%s」拒絕後狀態零變化" % label)


## 存檔裡的 active_ending 快照捷徑。
func _snap(save: Dictionary) -> Dictionary:
	return (save["flow"] as Dictionary)["active_ending"] as Dictionary


## 手寫的合法不上車快照（P5-B 沒有 opening 入口可以產生它）。
func _refuse_snapshot() -> Dictionary:
	return {
		"ending_id": "ending_refuse_boarding",
		"source_id": "opening_choice",
		"run_number": 1,
		"opening_choice_id": "refuse_boarding",
		"ended_day": null,
		"ended_phase": null,
		"partner_variant": null,
		"livelihood_variant": null,
		"inn_appearance_variant": null,
		"festival_proxy_npc": null,
		"knowledge_gained_this_run": [],
		"page_refs": [
			"ending_refuse_boarding/first_seen/pages/refuse_outside_life",
			"ending_refuse_boarding/first_seen/pages/refuse_early_death",
		],
		"page_index": 0,
		"page_revealed": false,
		"ready_to_complete": false,
	}


# ── 11. 完整玩家動作的原子性（四條先前繞過 preflight 的路徑）─────────────────

func _test_11_action_atomicity(gs: Node, data_node: Node) -> void:
	print("\n--- 11. 完整玩家動作的原子性 ---")

	var loader: DataLoader = data_node.get("loader") as DataLoader
	var orig_cap: Variant = loader.tuning["madness_cap"]
	loader.tuning["madness_cap"] = 2

	_atomicity_indulge(gs, loader)
	_atomicity_forced_indulge(gs, loader, data_node)
	_atomicity_delegation_report(gs, loader)
	_atomicity_encounter(gs, loader)
	_atomicity_encounter_capacity_order(gs, loader)

	loader.tuning["madness_cap"] = orig_cap


## (a) 主動縱慾：代價（行動格、發狂卡、次數）與效果必須同生同死。
func _atomicity_indulge(gs: Node, loader: DataLoader) -> void:
	var beat_id := "p5b_atomic_indulge"

	# 正向：效果只套一次，代價各扣一次。
	_fresh_run(gs, 20, "morning")
	gs.call("gain_card", "madness", false)
	var card_id := _first_madness(gs)
	_inject_indulgence_beat(loader, beat_id, 20, "morning", { "switch_progress": { "s6": 1 } })
	var ok_res: Dictionary = gs.call("indulge", beat_id, "slot", card_id)
	_check(bool(ok_res.get("ok", false)), "縱慾：合法效果結算成功")
	_check(int((gs.get("switch_progress") as Dictionary).get("s6", 0)) == 1, "縱慾：效果只套一次（可累加值為 1）")
	_check(int(gs.get("indulgence_count")) == 1, "縱慾：次數只加一次")
	_check(not bool(gs.call("has_card", card_id)), "縱慾：發狂卡只消一次")
	_check(bool(gs.get("action_spent")), "縱慾：行動格消一次")
	_remove_beat(loader, beat_id)

	# 反向：同一動作兩個不同 ending request → 代價一律不得落地。
	_fresh_run(gs, 20, "morning")
	gs.call("gain_card", "madness", false)
	gs.call("gain_card", "madness", false)
	var bad_card := _first_madness(gs)
	_inject_indulgence_beat(loader, beat_id, 20, "morning", {
		"madness": 1,
		"switch_progress": { "s6": 1 },
		"ending": "ending_inventory_be",
	})
	var before := _state_text(gs)
	var bad_res: Dictionary = gs.call("indulge", beat_id, "slot", bad_card)
	_check(_reject_code(bad_res) == "data_conflict", "縱慾：雙 ending request → data_conflict")
	_check(_state_text(gs) == before, "縱慾：拒絕後行動格、手牌、次數與效果全部零變化")
	_check(str(gs.get("flow_mode")) == "run", "縱慾：拒絕後仍在 run mode")
	_remove_beat(loader, beat_id)


## (b) 強制縱慾：結算失敗時債留在 forced_pending，行動格與手牌都不動。
func _atomicity_forced_indulge(gs: Node, loader: DataLoader, data_node: Node) -> void:
	_fresh_run(gs, 20, "morning")
	gs.call("gain_card", "madness", false)
	gs.call("gain_card", "madness", false)
	var debt_card := _first_madness(gs)
	var forced: Array = gs.get("forced_pending") as Array
	forced.clear()
	forced.append(debt_card)

	var exit_result: Dictionary = Indulgence.pick_exit(gs, data_node)
	_check(not exit_result.is_empty(), "強制縱慾：pick_exit 選到出口")
	var slot: Dictionary = _find_slot_in(loader, str(exit_result.get("beat_id", "")), str(exit_result.get("slot_id", "")))
	_check(not slot.is_empty(), "強制縱慾：出口槽存在")

	var orig_on_place: Variant = slot.get("on_place")
	slot["on_place"] = { "madness": 1, "ending": "ending_inventory_be" }
	var before := _state_text(gs)
	var lines: PackedStringArray = gs.call("_settle_forced_indulgence")
	_check(lines.is_empty(), "強制縱慾：結算失敗時不產生文字")
	_check(_state_text(gs) == before, "強制縱慾：失敗後行動格、手牌、次數與 forced_pending 全部零變化")
	_check((gs.get("forced_pending") as Array).has(debt_card), "強制縱慾：債仍留在 forced_pending（帳不豁免）")

	if orig_on_place == null:
		slot.erase("on_place")
	else:
		slot["on_place"] = orig_on_place
	forced.clear()


## (c) 延遲委託回報：結算失敗的那一筆原樣留在 pending，不得被吞掉。
func _atomicity_delegation_report(gs: Node, loader: DataLoader) -> void:
	var beat_id := "p5b_atomic_report"
	_fresh_run(gs, 20, "morning")
	gs.call("gain_card", "madness", false)
	gs.call("gain_card", "madness", false)

	_inject_delegation_beat(loader, beat_id, 20, "morning", {
		"madness": 1,
		"switch_progress": { "s6": 1 },
		"ending": "ending_inventory_be",
	})
	var report := { "beat_id": beat_id, "slot_id": "slot", "due_day": 20 }
	var pending: Array = gs.get("pending_delegation_reports") as Array
	pending.clear()
	pending.append(report)

	var before := _state_text(gs)
	gs.call("_settle_pending_delegation_reports")
	_check(_state_text(gs) == before, "延遲回報：結算失敗後完整序列化零變化")
	_check((gs.get("pending_delegation_reports") as Array).size() == 1, "延遲回報：失敗那筆仍留在 pending")
	_check(int((gs.get("switch_progress") as Dictionary).get("s6", 0)) == 0, "延遲回報：失敗時同塊效果一次都沒套")
	_remove_beat(loader, beat_id)

	# 正向對照：合法回報出列一次、效果套一次。
	_fresh_run(gs, 20, "morning")
	_inject_delegation_beat(loader, beat_id, 20, "morning", { "switch_progress": { "s6": 1 } })
	var good_report := { "beat_id": beat_id, "slot_id": "slot", "due_day": 20 }
	var pending2: Array = gs.get("pending_delegation_reports") as Array
	pending2.clear()
	pending2.append(good_report)
	gs.call("_settle_pending_delegation_reports")
	_check((gs.get("pending_delegation_reports") as Array).is_empty(), "延遲回報：成功那筆出列一次")
	_check(int((gs.get("switch_progress") as Dictionary).get("s6", 0)) == 1, "延遲回報：效果只套一次")
	_remove_beat(loader, beat_id)


## (d) 遭遇：response 的 on_resolve 與同一次出口效果必須合併成同一個 action plan。
func _atomicity_encounter(gs: Node, loader: DataLoader) -> void:
	var beat_id := "p5b_atomic_encounter"

	# 正向：on_resolve 與 on_victory 各套一次，遭遇結束。
	_fresh_run(gs, 20, "morning")
	gs.call("gain_card", "k_forty_something")
	_inject_encounter_beat(loader, beat_id,
		{ "switch_progress": { "s6": 1 } },
		{ "switch_progress": { "s6": 1 }, "flag": { "p5b_enc_victory": true } })
	_check(bool((gs.call("start_encounter", beat_id) as Dictionary).get("ok", false)), "遭遇：開場成功")
	gs.call("acknowledge_encounter_intro")
	var win_res: Dictionary = gs.call("respond_to_encounter", "k_forty_something")
	_check(bool(win_res.get("ok", false)), "遭遇：命中回應成功")
	_check(int((gs.get("switch_progress") as Dictionary).get("s6", 0)) == 2,
		"遭遇：on_resolve 與 on_victory 各套一次（可累加值為 2）")
	_check(bool((gs.get("flags") as Dictionary).get("p5b_enc_victory", false)), "遭遇：勝利出口 flag 落地")
	_check((gs.get("active_encounter") as Dictionary).is_empty(), "遭遇：出口後 active_encounter 清空")
	_remove_beat(loader, beat_id)

	# 反向：on_resolve 撞 cap 與 on_victory 的 inventory ending 是兩個不同 request，
	# 合併驗證後整個動作原子拒絕——不得扣卡、不得換回合、不得覆寫前一個結局。
	_fresh_run(gs, 20, "morning")
	gs.call("gain_card", "k_forty_something")
	gs.call("gain_card", "madness", false)
	_inject_encounter_beat(loader, beat_id,
		{ "madness": 1, "switch_progress": { "s6": 1 } },
		{ "ending": "ending_inventory_be" })
	gs.call("start_encounter", beat_id)
	gs.call("acknowledge_encounter_intro")
	var before := _state_text(gs)
	var conflict_res: Dictionary = gs.call("respond_to_encounter", "k_forty_something")
	_check(_reject_code(conflict_res) == "data_conflict", "遭遇：回應與出口的雙 ending request → data_conflict")
	_check(_state_text(gs) == before,
		"遭遇：拒絕後 attempted／blocked_slots／手牌／發狂與效果全部零變化")
	_check(str(gs.get("flow_mode")) == "run", "遭遇：拒絕後仍在 run mode")
	_remove_beat(loader, beat_id)
	_fresh_run(gs, 20, "morning")


# ── 12. D45 終局鏈：只按推進也走得完，兩條 coda 路都收得了尾 ──────────────────

func _test_12_d45_lifecycle(gs: Node) -> void:
	print("\n--- 12. D45 終局鏈（正式資料端到端）---")

	# (a) A1：D45 morning 不開任何地點、只按推進，終局鏈仍必須成立。
	_walk_into_day45(gs)
	_check(bool((gs.get("flags") as Dictionary).get("final_day", false)),
		"D45 morning：不開地點，final_day 仍由 auto_enter 自動寫入")
	_check((gs.get("beats_entered") as Dictionary).has("d45_morning_invitation"),
		"D45 morning：終局鏈的 fixed beat 自動進場")

	gs.call("advance_phase")
	_check(int(gs.get("day")) == 45 and str(gs.get("phase")) == "afternoon", "推進到 D45 afternoon")
	_check(str((gs.get("active_encounter") as Dictionary).get("beat_id", "")) == "d45_encounter",
		"D45 afternoon：終局遭遇自動開場，不必玩家先開山泉閣")

	PlaythroughGreedy.solve_active_encounter_if_any(gs)
	if str(gs.get("phase")) == "afternoon":
		gs.call("advance_phase")
	_check(int(gs.get("day")) == 45 and str(gs.get("phase")) == "evening", "遭遇結算後進入 D45 evening")

	# 門檻未結算時不得離場，更不得出現第 46 天。
	gs.call("play_evening")
	gs.set("selected_festival_proxy_npc", "ajie")
	var before_gate := _state_text(gs)
	var gate_res: Dictionary = gs.call("advance_phase")
	_check(_reject_code(gate_res) == "phase_requirements_incomplete",
		"D45 evening：coda 選擇組未結算 → phase_requirements_incomplete")
	_check(_state_text(gs) == before_gate, "D45 evening：門檻未過拒絕後序列化零變化")
	_check(int(gs.get("day")) == 45, "D45 evening：門檻未過時不會走到第 46 天")

	# (b) B1 未持名冊：空手槽一樣收得了尾，且什麼都不給。
	var knowledge_before: Dictionary = (gs.get("knowledge") as Dictionary).duplicate()
	var flags_before: Dictionary = (gs.get("flags") as Dictionary).duplicate()
	_check(not bool(gs.call("has_card", "info_registry")), "未持名冊：手上確實沒有 info_registry")
	var empty_res: Dictionary = gs.call("choose", "d45_then", "d45_coda", "empty_handed")
	_check(bool(empty_res.get("ok", false)), "未持名冊：空手槽可結算 d45_coda 選擇組")
	_check((gs.get("knowledge") as Dictionary) == knowledge_before, "空手槽不發任何知識卡")
	_check((gs.get("flags") as Dictionary) == flags_before, "空手槽不發任何旗標")
	_check(bool(gs.call("has_knowledge", "k_not_today")), "未持名冊：留著 k_not_today（沒有升級）")
	_check(not bool(gs.call("has_knowledge", "k_already_on_list")), "未持名冊：拿不到 k_already_on_list")

	var empty_adv: Dictionary = gs.call("advance_phase")
	_check(bool(empty_adv.get("ok", false)), "未持名冊：門檻完成後推進成功")
	_check(str(gs.get("flow_mode")) == "ending", "未持名冊：仍啟動結局")
	_check(str((gs.get("active_ending") as Dictionary).get("ending_id", "")) == "ending_replaced",
		"未持名冊：啟動的是 ending_replaced")
	_check(str((gs.get("active_ending") as Dictionary).get("source_id", "")) == "d45_coda",
		"未持名冊：source 為 d45_coda")
	_check(int(gs.get("day")) == 45 and str(gs.get("phase")) == "evening", "未持名冊：進結局後 day／phase 不動")

	# (c) B1 持名冊：同一個選擇組換另一條路，拿到升級知識卡。
	_walk_into_day45(gs)
	gs.call("advance_phase")
	PlaythroughGreedy.solve_active_encounter_if_any(gs)
	if str(gs.get("phase")) == "afternoon":
		gs.call("advance_phase")
	gs.call("play_evening")
	gs.set("selected_festival_proxy_npc", "ajie")
	gs.call("gain_card", "info_registry")
	var compare_res: Dictionary = gs.call("try_place", "info_registry", "d45_then", "compare_registry")
	_check(bool(compare_res.get("ok", false)), "持名冊：比對槽放置成功")
	_check(bool(gs.call("has_knowledge", "k_already_on_list")), "持名冊：升級成 k_already_on_list")
	_check(not bool(gs.call("has_knowledge", "k_not_today")), "持名冊：舊的 k_not_today 被換掉")
	_check(str((gs.get("choices") as Dictionary).get("d45_then::d45_coda", "")) == "compare_registry",
		"持名冊：比對槽同樣結算了 d45_coda 選擇組")

	var compare_adv: Dictionary = gs.call("advance_phase")
	_check(bool(compare_adv.get("ok", false)), "持名冊：門檻完成後推進成功")
	_check(str(gs.get("flow_mode")) == "ending", "持名冊：啟動結局")
	_check(int(gs.get("day")) == 45, "持名冊：進結局後仍停在第 45 天")

	# (d) 選擇組是互斥的：已走一條就不能再走另一條。
	gs.set("flow_mode", "run")
	(gs.get("active_ending") as Dictionary).clear()
	var second_res: Dictionary = gs.call("choose", "d45_then", "d45_coda", "empty_handed")
	_check(not bool(second_res.get("ok", true)), "d45_coda 選擇組結算後不得再選另一條")

	# 比對槽掛 choice_requires_card：沒有名冊時不得用「選擇」繞過放卡，
	# 否則會多出一條看起來像比對、實際上什麼都沒升級的第三條路。
	_walk_into_day45(gs)
	gs.call("advance_phase")
	PlaythroughGreedy.solve_active_encounter_if_any(gs)
	if str(gs.get("phase")) == "afternoon":
		gs.call("advance_phase")
	gs.call("play_evening")
	var bare_choose: Dictionary = gs.call("choose", "d45_then", "d45_coda", "compare_registry")
	_check(_reject_code(bare_choose) == "card_required", "未持名冊直呼比對槽 → card_required")
	_check(not (gs.get("choices") as Dictionary).has("d45_then::d45_coda"), "card_required 拒絕後選擇組仍未結算")

	# (e) 第二道防線：門檻整個不成立時（例如 final_day 沒寫進來），最後一天的
	# evening 仍然不得被越過。少了這道防線，時段機會把玩家送進第 46 天。
	_fresh_run(gs, 45, "evening")
	_check(not bool((gs.get("flags") as Dictionary).get("final_day", false)), "對照組：final_day 未成立")
	_check(not bool((gs.call("phase_exit_status") as Dictionary).get("has_gate", false)),
		"對照組：門檻 beat 因條件不成立而不存在")
	var no_gate_res: Dictionary = gs.call("advance_phase")
	_check(_reject_code(no_gate_res) == "phase_requirements_incomplete",
		"D45 evening 無門檻時仍拒絕離場")
	_check(int(gs.get("day")) == 45 and str(gs.get("phase")) == "evening", "D45 evening 無門檻時不會進第 46 天")

	_fresh_run(gs, 20, "morning")


## 從第 44 天 night 只按推進走進第 45 天 morning，全程不開任何地點。
func _walk_into_day45(gs: Node) -> void:
	_fresh_run(gs, 44, "night")
	gs.call("advance_phase")
	_check(int(gs.get("day")) == 45 and str(gs.get("phase")) == "morning",
		"只按推進即可從 D44 night 進到 D45 morning")


## (e) 容量與死局判定必須看得到 on_resolve 之後的手牌。
## 合併成單一 plan 之後，這個順序只存在於複本上，因此要有自己的斷言。
func _atomicity_encounter_capacity_order(gs: Node, loader: DataLoader) -> void:
	var beat_id := "p5b_atomic_capacity"
	var orig_cap: Variant = loader.tuning["madness_cap"]
	loader.tuning["madness_cap"] = 99

	_fresh_run(gs, 20, "morning")
	gs.call("gain_card", "info_registry")
	_inject_two_round_encounter(loader, beat_id, { "madness": 11 })
	gs.call("start_encounter", beat_id)
	gs.call("acknowledge_encounter_intro")
	var res: Dictionary = gs.call("respond_to_encounter", "info_registry")
	_check(bool(res.get("ok", false)), "容量順序：回應本身成功")
	_check(int((gs.get("hand") as Array).size()) == 13, "容量順序：on_resolve 真的把手牌撐到 13 張")
	_check((gs.get("active_encounter") as Dictionary).is_empty(),
		"容量順序：換回合時看的是 on_resolve 之後的手牌，因此直接走 failure 出口")
	_check(bool((gs.get("flags") as Dictionary).get("p5b_enc_failure", false)),
		"容量順序：落地的是 failure 出口效果")

	_remove_beat(loader, beat_id)
	loader.tuning["madness_cap"] = orig_cap


## 合成兩回合遭遇：第一回合命中後換到第二回合，途中會做容量判定。
func _inject_two_round_encounter(loader: DataLoader, beat_id: String, on_resolve: Dictionary) -> void:
	var beat := {
		"id": beat_id,
		"location": "jinghe_back",
		"title": "P5-B 合成兩回合遭遇",
		"encounter": {
			"per_round_slot_cost": 1,
			"escape_cost": 1,
			"allow_discard": true,
			"after_finish": "stay",
			"rounds": [
				{
					"id": "first_round",
					"demand": "合成提問一",
					"responses": [{
						"id": "answer", "accepts": ["info_registry"], "consume_card": false,
						"next_round": "second_round", "on_resolve": on_resolve,
					}],
					"fallback": { "requires_discardable": true, "next_round": "second_round", "on_resolve": {} },
				},
				{
					"id": "second_round",
					"demand": "合成提問二",
					"responses": [{
						"id": "answer2", "accepts": ["info_registry"], "consume_card": false,
						"next_round": null, "on_resolve": {},
					}],
					"fallback": { "requires_discardable": true, "next_round": null, "on_resolve": {} },
				},
			],
			"on_victory": { "flag": { "p5b_enc_victory": true } },
			"on_failure": { "flag": { "p5b_enc_failure": true } },
			"on_escape": { "flag": { "p5b_enc_escape": true } },
		},
	}
	loader.beats.append(beat)
	loader.beats_by_id[beat_id] = beat


## 手上第一張發狂卡的實例 id。
func _first_madness(gs: Node) -> String:
	for c: Variant in gs.get("hand") as Array:
		if str(c).begins_with("madness"):
			return str(c)
	return ""


func _find_slot_in(loader: DataLoader, beat_id: String, slot_id: String) -> Dictionary:
	var beat: Dictionary = loader.beats_by_id.get(beat_id, {}) as Dictionary
	for slot_raw: Variant in beat.get("slots", []) as Array:
		var slot := slot_raw as Dictionary
		if str(slot.get("id", "")) == slot_id:
			return slot
	return {}


## 合成一個縱慾出口 beat（收發狂卡、非泡湯）。
func _inject_indulgence_beat(loader: DataLoader, beat_id: String, day: int, phase: String, on_place: Dictionary) -> void:
	var beat := {
		"id": beat_id,
		"location": "jinghe_back",
		"when": { "day": day, "phase": phase },
		"title": "P5-B 合成縱慾出口",
		"slots": [{
			"id": "slot", "occupant": null, "label": "合成出口槽", "accepts": ["madness"],
			"indulgence": { "auto": false, "weight": 1 },
			"on_place": on_place,
		}],
	}
	loader.beats.append(beat)
	loader.beats_by_id[beat_id] = beat


## 合成一個隔日回報的委託 beat。
func _inject_delegation_beat(loader: DataLoader, beat_id: String, day: int, phase: String, report: Dictionary) -> void:
	var beat := {
		"id": beat_id,
		"location": "jinghe_back",
		"when": { "day": day, "phase": phase },
		"title": "P5-B 合成委託",
		"slots": [{
			"id": "slot", "occupant": null, "label": "合成委託槽", "accepts": ["person_ahong"],
			"delegation": { "result_timing": "next_morning", "report": report },
		}],
	}
	loader.beats.append(beat)
	loader.beats_by_id[beat_id] = beat


## 合成一個單回合遭遇 beat：命中 k_forty_something 直接走勝利出口。
func _inject_encounter_beat(loader: DataLoader, beat_id: String, on_resolve: Dictionary, on_victory: Dictionary) -> void:
	var beat := {
		"id": beat_id,
		"location": "jinghe_back",
		"title": "P5-B 合成遭遇",
		"encounter": {
			"per_round_slot_cost": 1,
			"escape_cost": 1,
			"allow_discard": true,
			"after_finish": "stay",
			"rounds": [{
				"id": "only_round",
				"demand": "合成提問",
				"responses": [{
					"id": "answer", "accepts": ["k_forty_something"], "consume_card": false,
					"next_round": null, "on_resolve": on_resolve,
				}],
				"fallback": { "requires_discardable": true, "next_round": null, "on_resolve": {} },
			}],
			"on_victory": on_victory,
			"on_failure": { "flag": { "p5b_enc_failure": true } },
			"on_escape": { "flag": { "p5b_enc_escape": true } },
		},
	}
	loader.beats.append(beat)
	loader.beats_by_id[beat_id] = beat


## 一次往返：page ref、index、revealed、ready 完全相等，且續播結果一致。
func _roundtrip_case(gs: Node, label: String) -> void:
	var before: Dictionary = gs.call("serialize")
	var view_before: Dictionary = gs.call("ending_view")
	var res: Dictionary = gs.call("deserialize", JSON.parse_string(JSON.stringify(before)) as Dictionary)
	_check(bool(res.get("ok", false)), "%s：往返載入成功" % label)
	_check(JSON.stringify(gs.call("serialize")) == JSON.stringify(before), "%s：往返後序列化逐字相同" % label)
	_check(JSON.stringify(gs.call("ending_view")) == JSON.stringify(view_before), "%s：往返後 ending view 完全相同" % label)


# ── 8. 兩階段效果、ending request 衝突與 D45 端到端 ─────────────────────────

func _test_8_two_phase_effects(gs: Node, data_node: Node) -> void:
	print("\n--- 8. 兩階段效果與 D45 phase_exit 端到端 ---")

	var loader: DataLoader = data_node.get("loader") as DataLoader
	var synthetic_id := "p5b_synthetic_beat"

	# (a) 其他效果 + 合法 inventory ending：效果只套一次，之後才進 ending
	_fresh_run(gs, 20, "morning")
	_inject_beat(loader, synthetic_id, 20, "morning", {
		"text": "合成槽",
		"flag": { "p5b_flag": true },
		"switch_progress": { "s6": 1 },
		"gain": ["k_forty_something"],
		"ending": "ending_inventory_be",
	})
	var place_res: Dictionary = gs.call("try_place", "protagonist", synthetic_id, "slot")
	_check(bool(place_res.get("ok", false)), "合法 ending 效果的放置成功")
	_check(bool((gs.get("flags") as Dictionary).get("p5b_flag", false)), "同一塊的 flag 有套用")
	_check(int((gs.get("switch_progress") as Dictionary).get("s6", 0)) == 1, "switch_progress 只累加一次")
	_check((gs.get("slots_placed") as Dictionary).has(synthetic_id + "::slot"), "槽只寫一次")
	_check(bool(gs.get("action_spent")), "主角卡消耗行動格一次")
	_check(str(gs.get("flow_mode")) == "ending", "效果 commit 後才進 ending mode")
	var inv_snapshot: Dictionary = gs.get("active_ending") as Dictionary
	_check(str(inv_snapshot.get("ending_id", "")) == "ending_inventory_be", "beat 效果啟動的是庫存 BE")
	_check(str(inv_snapshot.get("source_id", "")) == "ending_effect", "beat 效果的 source 固定為 ending_effect")
	_check((inv_snapshot.get("knowledge_gained_this_run", []) as Array).has("k_forty_something"),
		"快照看得到剛完成動作發的知識卡")
	_check(inv_snapshot.get("partner_variant") == null and inv_snapshot.get("festival_proxy_npc") == null,
		"BE 快照三個 variant 與未凍結代付者皆為 null")
	_remove_beat(loader, synthetic_id)

	# (b) madness 撞 cap＋同塊 flag：flag 留在本輪，結局為發狂 BE
	var orig_cap: Variant = loader.tuning["madness_cap"]
	loader.tuning["madness_cap"] = 2
	_fresh_run(gs, 20, "morning")
	gs.call("gain_card", "madness", false)
	_inject_beat(loader, synthetic_id, 20, "morning", {
		"madness": 1,
		"flag": { "p5b_cap_flag": true },
	})
	var cap_res: Dictionary = gs.call("try_place", "protagonist", synthetic_id, "slot")
	_check(bool(cap_res.get("ok", false)), "撞 cap 的放置本身成功")
	_check(bool((gs.get("flags") as Dictionary).get("p5b_cap_flag", false)), "撞 cap 時同塊 flag 仍留在本輪")
	_check(str(gs.get("flow_mode")) == "ending", "撞 cap 後進入 ending mode")
	_check(str((gs.get("active_ending") as Dictionary).get("ending_id", "")) == "ending_madness_be",
		"撞 cap 啟動發狂 BE")
	_check(str((gs.get("active_ending") as Dictionary).get("source_id", "")) == "madness_cap",
		"發狂 BE 的 source 為 madness_cap")
	_remove_beat(loader, synthetic_id)

	# (c) 同一 action 兩個不同 ending request → data_conflict，全部零變化
	_fresh_run(gs, 20, "morning")
	gs.call("gain_card", "madness", false)
	_inject_beat(loader, synthetic_id, 20, "morning", {
		"madness": 1,
		"flag": { "p5b_conflict_flag": true },
		"gain": ["k_forty_something"],
		"ending": "ending_inventory_be",
	})
	var before_conflict := _state_text(gs)
	var conflict_res: Dictionary = gs.call("try_place", "protagonist", synthetic_id, "slot")
	_check(_reject_code(conflict_res) == "data_conflict", "同一 action 兩個 ending request → data_conflict")
	_check(_state_text(gs) == before_conflict, "衝突拒絕後 madness／flag／hand／槽／行動格全部零變化")
	_check(str(gs.get("flow_mode")) == "run", "衝突拒絕後仍留在 run mode")
	_remove_beat(loader, synthetic_id)
	loader.tuning["madness_cap"] = orig_cap

	# (d) D45 phase_exit 端到端：required slot 完成前後
	_fresh_run(gs, 45, "afternoon")
	(gs.get("flags") as Dictionary)["final_day"] = true
	gs.set("selected_festival_proxy_npc", "ajie")
	gs.set("phase", "evening")
	gs.call("play_evening")
	var before_gate := _state_text(gs)
	var gate_res: Dictionary = gs.call("advance_phase")
	_check(_reject_code(gate_res) == "phase_requirements_incomplete", "required slot 未完成 → phase_requirements_incomplete")
	_check(not bool(gate_res.get("phase_advanced", true)), "門檻未過時 phase_advanced 為 false")
	_check(_state_text(gs) == before_gate, "門檻未過拒絕後序列化零變化")

	gs.call("gain_card", "info_registry")
	var coda_place: Dictionary = gs.call("try_place", "info_registry", "d45_then", "compare_registry")
	_check(bool(coda_place.get("ok", false)), "D45 比對槽放置成功")
	var advance_res: Dictionary = gs.call("advance_phase")
	_check(bool(advance_res.get("ok", false)), "門檻完成後推進成功")
	_check(not bool(advance_res.get("phase_advanced", true)), "D45 進結局不換時段（phase_advanced false）")
	_check(int(gs.get("day")) == 45 and str(gs.get("phase")) == "evening", "D45 啟動結局後 day／phase 不動")
	_check(str((gs.get("active_ending") as Dictionary).get("source_id", "")) == "d45_coda", "D45 結局 source 為 d45_coda")
	_check((gs.get("hand") as Array).size() > 0 and not (gs.get("slots_placed") as Dictionary).is_empty(),
		"進結局後 run 尚未被清空")


	# (e) lint 先擋正式資料形成雙 request；runtime preflight 只是第二道防線
	var clean_problems := DataLoader.lint_endings(loader)
	_check(clean_problems.is_empty(), "正式資料 lint 17 為 0 錯誤")
	_inject_beat(loader, synthetic_id, 20, "morning", { "madness": 1, "ending": "ending_inventory_be" })
	var dirty_problems := DataLoader.lint_endings(loader)
	var caught := false
	for problem: String in dirty_problems:
		if "雙 ending request" in problem:
			caught = true
			break
	_check(caught, "lint 17 抓到同一效果塊同時有 madness 與 ending 的雙 request 形狀")
	_remove_beat(loader, synthetic_id)
	_check(DataLoader.lint_endings(loader).is_empty(), "移除合成 beat 後 lint 17 回到 0 錯誤（fixture 完整還原）")


## 合成一個當下時段、只有一個主角卡槽的 beat（測試結束後必須移除）。
func _inject_beat(loader: DataLoader, beat_id: String, day: int, phase: String, on_place: Dictionary) -> void:
	var beat := {
		"id": beat_id,
		"location": "jinghe_back",
		"when": { "day": day, "phase": phase },
		"title": "P5-B 合成 beat",
		"slots": [
			{ "id": "slot", "occupant": null, "label": "合成槽", "accepts": ["protagonist"], "on_place": on_place },
		],
	}
	loader.beats.append(beat)
	loader.beats_by_id[beat_id] = beat


func _remove_beat(loader: DataLoader, beat_id: String) -> void:
	loader.beats_by_id.erase(beat_id)
	for i in range(loader.beats.size()):
		if str((loader.beats[i] as Dictionary).get("id", "")) == beat_id:
			loader.beats.remove_at(i)
			return


# ── 9. source ↔ ending 配對矩陣 ─────────────────────────────────────────────

func _test_9_source_matrix(gs: Node) -> void:
	print("\n--- 9. source ↔ ending 配對矩陣 ---")

	var pairs := {
		"madness_cap": "ending_madness_be",
		"ending_effect": "ending_inventory_be",
		"d45_coda": "ending_replaced",
		"opening_choice": "ending_refuse_boarding",
	}
	# 公開 start_ending() 只收前三個 run 來源；opening_choice → ending_refuse_boarding
	# 的成功路徑屬 P5-D 的私有 opening 入口，本階段只以資料層配對（lint 17）與下方
	# 的拒絕案例證明，不在 run 中放行。
	var run_sources := ["madness_cap", "ending_effect", "d45_coda"]
	var sources: Array = pairs.keys()
	var endings: Array = pairs.values()

	for source: String in sources:
		for ending: String in endings:
			_fresh_run(gs, 45, "evening")
			gs.set("selected_festival_proxy_npc", "ajie")
			var before := _state_text(gs)
			var res: Dictionary = gs.call("start_ending", ending, source)
			if str(pairs[source]) == ending and run_sources.has(source):
				_check(bool(res.get("ok", false)), "合法 run 配對 %s → %s 成功" % [source, ending])
			else:
				_check(_reject_code(res) == "invalid_ending_source", "%s → %s 精確回 invalid_ending_source" % [source, ending])
				_check(_state_text(gs) == before, "%s → %s 拒絕後零變化" % [source, ending])

	_fresh_run(gs, 45, "evening")
	_check(_reject_code(gs.call("start_ending", "ending_replaced", "some_unknown_source")) == "invalid_ending_source",
		"未知 source → invalid_ending_source")
	_check(_reject_code(gs.call("start_ending", "ending_nonexistent", "d45_coda")) == "unknown_ending",
		"未知 ending → unknown_ending")

	# 兩道 source 檢查必須可分辨：一道擋錯配，一道擋「配對正確但不是 run 來源」。
	# 只反轉後者時，下面四條會轉紅而上面 12 種錯配仍綠。
	_fresh_run(gs, 45, "evening")
	gs.set("selected_festival_proxy_npc", "ajie")
	gs.set("opening_choice_id", "refuse_boarding")
	var refuse_before := _state_text(gs)
	var refuse_res: Dictionary = gs.call("start_ending", "ending_refuse_boarding", "opening_choice")
	_check(_reject_code(refuse_res) == "invalid_ending_source",
		"run 中公開啟動不上車 → invalid_ending_source")
	_check(_state_text(gs) == refuse_before, "run 中公開啟動不上車：完整序列化零變化")
	_check(str(gs.get("flow_mode")) == "run", "run 中公開啟動不上車：mode 仍為 run")
	_check((gs.get("active_ending") as Dictionary).is_empty(), "run 中公開啟動不上車：active_ending 仍為空")

	# 第四組配對本身仍要留在封閉表裡，P5-D 的私有入口才有東西可用。
	var const_map: Dictionary = (gs.get_script() as Script).get_script_constant_map()
	var pairs_const: Dictionary = const_map.get("ENDING_SOURCE_PAIRS", {}) as Dictionary
	_check(str(pairs_const.get("opening_choice", "")) == "ending_refuse_boarding",
		"第四組配對仍在封閉表內（供 P5-D 私有入口）")
	var run_const: Array = const_map.get("RUN_ENDING_SOURCES", []) as Array
	_check(run_const.size() == 3 and not run_const.has("opening_choice"),
		"RUN_ENDING_SOURCES 恰為三個 run 來源")
	_fresh_run(gs, 45, "evening")


# ── 10. 拒絕順序（每組同時具有兩個錯誤）─────────────────────────────────────

func _test_10_rejection_order(gs: Node) -> void:
	print("\n--- 10. 固定拒絕順序 ---")

	# start_ending：非 run ＋ 未知 ending → mode gate 先發
	_enter_replaced_ending(gs)
	_check(_reject_code(gs.call("start_ending", "ending_nonexistent", "d45_coda")) == "not_run",
		"start_ending：not_run 先於 unknown_ending")

	# start_ending：已有 active ending ＋ 錯配 source（先把 mode 掰回 run 只留 active）
	var ending_state: Dictionary = gs.call("serialize")
	var run_with_active: Dictionary = JSON.parse_string(JSON.stringify(ending_state)) as Dictionary
	gs.set("flow_mode", "run")
	_check(_reject_code(gs.call("start_ending", "ending_madness_be", "d45_coda")) == "ending_active",
		"start_ending：ending_active 先於 invalid_ending_source")
	gs.call("deserialize", run_with_active)

	# reveal／advance：非 ending mode ＋ 其他錯 → not_ending 先發
	_fresh_run(gs, 20, "morning")
	_check(_reject_code(gs.call("reveal_ending_page")) == "not_ending", "reveal：not_ending 先於 already_revealed")
	_check(_reject_code(gs.call("advance_ending_page")) == "not_ending", "advance：not_ending 先於 page_not_revealed")
	_check(_reject_code(gs.call("skip_seen_ending")) == "not_ending", "skip：not_ending 先於 ending_not_seen")

	# ending mode 但 active 為空 → no_active_ending 先於各自的第二錯
	gs.set("flow_mode", "ending")
	(gs.get("active_ending") as Dictionary).clear()
	_check(_reject_code(gs.call("reveal_ending_page")) == "no_active_ending", "reveal：no_active_ending 先於 already_revealed")
	_check(_reject_code(gs.call("advance_ending_page")) == "no_active_ending", "advance：no_active_ending 先於 page_not_revealed")
	_check(_reject_code(gs.call("skip_seen_ending")) == "no_active_ending", "skip：no_active_ending 先於 ending_not_seen")
	gs.set("flow_mode", "run")

	# advance_ending_page：已在末頁但未揭露 → page_not_revealed 先於 last_page
	_enter_replaced_ending(gs)
	var snapshot: Dictionary = gs.get("active_ending") as Dictionary
	snapshot["page_index"] = (snapshot.get("page_refs", []) as Array).size() - 1
	snapshot["page_revealed"] = false
	_check(_reject_code(gs.call("advance_ending_page")) == "page_not_revealed",
		"advance：page_not_revealed 先於 last_page")

	# skip：首見 ＋ 已在末頁 → ending_not_seen（skip 不看頁碼）
	_check(_reject_code(gs.call("skip_seen_ending")) == "ending_not_seen", "skip：首見一律 ending_not_seen")

	_fresh_run(gs, 20, "morning")
