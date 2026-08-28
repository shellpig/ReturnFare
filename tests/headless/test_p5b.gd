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
	var sources: Array = pairs.keys()
	var endings: Array = pairs.values()

	for source: String in sources:
		for ending: String in endings:
			_fresh_run(gs, 45, "evening")
			gs.set("selected_festival_proxy_npc", "ajie")
			var before := _state_text(gs)
			var res: Dictionary = gs.call("start_ending", ending, source)
			if str(pairs[source]) == ending:
				_check(bool(res.get("ok", false)), "合法配對 %s → %s 成功" % [source, ending])
			else:
				_check(_reject_code(res) == "invalid_ending_source", "錯配 %s → %s 精確回 invalid_ending_source" % [source, ending])
				_check(_state_text(gs) == before, "錯配 %s → %s 拒絕後零變化" % [source, ending])

	_fresh_run(gs, 45, "evening")
	_check(_reject_code(gs.call("start_ending", "ending_replaced", "some_unknown_source")) == "invalid_ending_source",
		"未知 source → invalid_ending_source")
	_check(_reject_code(gs.call("start_ending", "ending_nonexistent", "d45_coda")) == "unknown_ending",
		"未知 ending → unknown_ending")


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
