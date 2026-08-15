class_name P1AFCases
extends RefCounted

## P1-A～P1-F 的 UI runner 案例。
##
## 這裡的案例只透過 QAStep 送真實輸入，狀態觀察一律從 GameState.serialize()
## 或畫面 dump 取得；不讀 Data loader，也不呼叫 GameState 的規則操作入口。

const CaseBaseClass := preload("res://tests/ui_sim/cases/case_base.gd")
const QAStepClass := preload("res://tests/ui_sim/qa_step.gd")
const QADiagnosticsClass := preload("res://tests/ui_sim/qa_diagnostics.gd")


static func get_all_cases() -> Array[CaseBase]:
	return [
		UiCase.new("p1af_01_boot", "新局啟動顯示第 1 天 morning 第一章", "", "", "p1af_01_boot", "", "boot"),
		UiCase.new("p1af_02_phase_cycle", "新局連續推進四個時段並進入次日", "", "", "p1af_02_phase_cycle", "", "phase_cycle"),
		UiCase.new("p1af_03_d15", "第 15 天推進後章節切換至第二章", "d15_night.json", "", "p1af_03_chapter_boundary", "", "chapter_d15"),
		UiCase.new("p1af_03_d32", "第 32 天推進後章節切換至第三章", "d32_night.json", "", "p1af_03_chapter_boundary", "", "chapter_d32"),
		UiCase.new("p1af_04_coda", "第 45 天 afternoon 推進至 evening 結局 coda", "d45_afternoon.json", "", "p1af_04_d45_coda", "", "coda_jump"),
		UiCase.new("p1af_05_hand_default", "新局手牌列顯示預設上限", "", "hand_size_default", "p1af_05_hand_capacity", "", "hand_capacity"),
		UiCase.new("p1af_05_hand_variant", "資料變體重啟後手牌上限反映", "", "hand_size_small", "p1af_05_hand_capacity", "", "hand_capacity"),
		UiCase.new("p1af_06_hand_knowledge_split", "知識列與手牌列分開顯示", "d10_night__knowledge.json", "", "p1af_06_hand_knowledge_split", "", "hand_knowledge"),
		UiCase.new("p1af_07_arrival", "新局第一天 evening 到站演出與主角卡", "", "", "p1af_07_arrival", "", "arrival"),
		UiCase.new("p1af_08_map_filter", "D2 morning 地圖只顯示當時段開放地點", "d2_morning.json", "", "p1af_08_map_filter", "", "map_filter"),
		UiCase.new("p1af_09_occupant_empty", "演出後 occupant 不可放卡、空槽可互動", "d2_morning.json", "", "p1af_09_occupant_empty", "", "occupant_empty"),
		UiCase.new("p1af_10_requires_locked", "requires 不成立的槽呈灰並顯示理由", "d3_afternoon__no_info.json", "", "p1af_10_requires_locked", "", "requires_locked"),
		UiCase.new("p1af_11_unlock_same_panel", "同一面板取得條件後槽位重新求值", "d9_afternoon.json", "", "p1af_11_unlock_same_panel", "", "unlock_same_panel"),
		UiCase.new("p1af_12_condition_hidden", "condition 不成立的 D32 分支不出現", "d32_morning__none.json", "", "p1af_12_condition_hidden", "", "condition_hidden"),
		UiCase.new("p1af_13_competing_beats", "D3 afternoon 三個競爭 beat 均可逐一演出", "d3_afternoon.json", "", "p1af_13_competing_beats", "", "competing_beats"),
		UiCase.new("p1af_14_place_effect", "D3 放主角卡後效果文字與狀態落帳", "d3_afternoon.json", "", "p1af_14_place_effect", "", "place_effect"),
		UiCase.new("p1af_15_action_spent", "行動格用掉後第二地點不能再放主角卡", "d3_afternoon.json", "", "p1af_15_action_spent", "", "action_spent"),
		UiCase.new("p1af_16_panel_rebuild", "放置後同面板立即重建控制項", "d3_afternoon.json", "", "p1af_16_panel_rebuild", "", "panel_rebuild"),
		UiCase.new("p1af_17_compare_free", "D9 比對槽放情報卡不消耗行動格", "d9_afternoon.json", "", "p1af_17_compare_free", "", "compare_free"),
		UiCase.new("p1af_18_incompatible_absent", "不符合 accepts 的卡沒有 place 控制項", "d22_afternoon.json", "", "p1af_18_incompatible_absent", "", "incompatible_absent"),
		UiCase.new("p1af_19_attention", "D22 attention_npc 投入帳成功加一", "d22_afternoon.json", "", "p1af_19_attention", "", "attention"),
		UiCase.new("p1af_20_choice_collapse", "choice 選定後同組其餘選項消失", "d22_afternoon.json", "", "p1af_20_choice_collapse", "", "choice_collapse"),
		UiCase.new("p1af_21_choice_resolved", "重開面板後 choice 唯讀且不可反悔", "d22_afternoon.json", "", "p1af_21_choice_resolved", "", "choice_resolved"),
		UiCase.new("p1af_22_choice_equiv_direct", "choice 直選路徑結果基準", "d22_afternoon__no_polaroid.json", "", "p1af_22_choice_equivalence", "p1af_22_choice_equivalence", "choice_direct"),
		UiCase.new("p1af_22_choice_equiv_card", "choice 帶卡路徑結果基準", "d22_afternoon__with_polaroid.json", "", "p1af_22_choice_equivalence", "p1af_22_choice_equivalence", "choice_card"),
		UiCase.new("p1af_23_choice_leave", "不選 choice 離開後狀態不變", "d22_afternoon__no_polaroid.json", "", "p1af_23_choice_leave", "", "choice_leave"),
		UiCase.new("p1af_24_choice_no_card", "無相關卡時可直接選 choice", "d22_afternoon__no_polaroid.json", "", "p1af_24_choice_no_card", "", "choice_no_card"),
		UiCase.new("p1af_25_choice_card", "持有相關卡時可放卡選 choice", "d22_afternoon__with_polaroid.json", "", "p1af_25_choice_card", "", "choice_card_path"),
		UiCase.new("p1af_26_echo_d5_attended", "D5 到場時不播殘響", "d5_evening__attended.json", "", "p1af_26_echo_d5", "", "echo_d5_attended"),
		UiCase.new("p1af_26_echo_d5_missed", "D5 錯過時播出殘響", "d5_evening__miss_sanquan.json", "", "p1af_26_echo_d5", "", "echo_d5_missed"),
		UiCase.new("p1af_27_echo_d8", "D8 evening 殘響播出", "d8_evening.json", "", "p1af_27_ch1_echoes", "", "echo_d8"),
		UiCase.new("p1af_27_echo_d13", "D13 evening 殘響播出", "d13_evening.json", "", "p1af_27_ch1_echoes", "", "echo_d13"),
		UiCase.new("p1af_27_echo_d5", "D5 evening 殘響入口可重跑", "d5_evening__miss_sanquan.json", "", "p1af_27_ch1_echoes", "", "echo_d5_repeat"),
		UiCase.new("p1af_28_d27_both", "D27 evening 固定 beat 依序結算且取得知識", "d27_evening__both.json", "", "p1af_28_d27_order", "", "d27_both"),
		UiCase.new("p1af_28_d27_partial", "D27 evening 缺一條前置時不取得知識", "d27_evening__partial.json", "", "p1af_28_d27_order", "", "d27_partial"),
		UiCase.new("p1af_29_night_resolution", "D10 night 地圖解析與免費標記", "d10_night.json", "", "p1af_29_night_resolution", "", "night_resolution"),
		UiCase.new("p1af_29_night_d1_fixed", "D1 night 固定演出優先於地圖", "", "", "p1af_29_night_resolution", "", "night_resolution_d1"),
		UiCase.new("p1af_30_sleep_d24", "D24 night 直接睡播定日 beat", "d24_night.json", "", "p1af_30_sleep_d24", "", "sleep_d24"),
		UiCase.new("p1af_31_night_place", "D10 night 放主角卡不耗行動格", "d10_night.json", "", "p1af_31_night_place", "", "night_place"),
		UiCase.new("p1af_32_coda_full", "D45 coda 真 beat、比對與跨輪重置", "d45_evening.json", "", "p1af_32_d45_coda_full", "", "coda_full"),
		UiCase.new("p1af_33_full_walk", "從新局以真實輸入走完 45 天並續走第二輪", "", "", "p1af_33_full_walk", "", "full_walk"),
	]


class UiCase extends CaseBaseClass:
	var mode := ""

	func _init(case_id: String, desc: String, req_state: String, req_data_root: String, req_contract: String, compare: String, run_mode: String) -> void:
		super._init(case_id, desc, req_state, req_data_root, req_contract, compare)
		mode = run_mode

	func run(tree: SceneTree, main_node: Control, run_dir: String) -> Dictionary:
		match mode:
			"boot":
				return _boot(tree)
			"phase_cycle":
				return await _phase_cycle(tree)
			"chapter_d15", "chapter_d32":
				return await _chapter_boundary(tree)
			"coda_jump":
				return await _coda_jump(tree)
			"hand_capacity":
				return _hand_capacity(tree)
			"hand_knowledge":
				return _hand_knowledge(tree)
			"arrival":
				return await _arrival(tree)
			"map_filter":
				return _map_filter(tree)
			"occupant_empty":
				return await _occupant_empty(tree)
			"requires_locked":
				return await _requires_locked(tree)
			"unlock_same_panel":
				return await _unlock_same_panel(tree)
			"condition_hidden":
				return await _condition_hidden(tree, main_node)
			"competing_beats":
				return await _competing_beats(tree)
			"place_effect":
				return await _place_effect(tree)
			"action_spent":
				return await _action_spent(tree)
			"panel_rebuild":
				return await _panel_rebuild(tree)
			"compare_free":
				return await _compare_free(tree)
			"incompatible_absent":
				return await _incompatible_absent(tree)
			"attention":
				return await _attention(tree)
			"choice_collapse":
				return await _choice_collapse(tree)
			"choice_resolved":
				return await _choice_resolved(tree)
			"choice_direct", "choice_no_card":
				return await _choice_path(tree, false)
			"choice_card", "choice_card_path":
				return await _choice_path(tree, true)
			"choice_leave":
				return await _choice_leave(tree)
			"echo_d5_attended", "echo_d5_missed", "echo_d5_repeat", "echo_d8", "echo_d13":
				return _echo(tree)
			"d27_both", "d27_partial":
				return _d27_order(tree)
			"night_resolution", "night_resolution_d1":
				if mode == "night_resolution_d1":
					return await _night_resolution_d1(tree)
				return await _night_resolution(tree, main_node)
			"sleep_d24":
				return await _sleep_d24(tree, main_node)
			"night_place":
				return await _night_place(tree)
			"coda_full":
				return await _coda_full(tree)
			"full_walk":
				return await _full_walk(tree)
			_:
				assert_true(false, "未知 UI 案例模式: %s" % mode)
		return { "ok": errors.is_empty(), "errors": errors }

	func _state(tree: SceneTree) -> Dictionary:
		return CaseBaseClass.get_game_state(tree).call("serialize") as Dictionary

	func _run(tree: SceneTree) -> Dictionary:
		return _state(tree).get("run", {}) as Dictionary

	func _texts(root: Node) -> Array[String]:
		var result: Array[String] = []
		for item: Dictionary in QADiagnosticsClass.dump_ui_tree(root):
			if bool(item.get("visible_in_tree", false)):
				var text := str(item.get("text", ""))
				if not text.is_empty():
					result.append(text)
		return result

	func _has_text(root: Node, needle: String) -> bool:
		for text in _texts(root):
			if text.contains(needle):
				return true
		return false

	func _visible_ids(tree: SceneTree, prefix: String) -> Array[String]:
		var result: Array[String] = []
		for ctrl in QAStepClass.find_controls_by_qa_id_prefix(tree.get_root(), prefix):
			if not ctrl.is_visible_in_tree() or not ctrl.has_meta("qa_id"):
				continue
			if ctrl is BaseButton and (ctrl as BaseButton).disabled:
				continue
			result.append(str(ctrl.get_meta("qa_id")))
		return result

	func _click(tree: SceneTree, qa_id: String, button_index: MouseButton = MOUSE_BUTTON_LEFT, expected_disabled: bool = false) -> Dictionary:
		var result := await QAStepClass.click(tree, qa_id, button_index, expected_disabled)
		assert_true(bool(result.get("ok", false)), "點擊 %s 失敗: %s" % [qa_id, str(result.get("error", ""))])
		return result

	func _enter(tree: SceneTree, location_id: String, drain: bool = true) -> void:
		await _click(tree, "location::" + location_id)
		if drain:
			var drained := await QAStepClass.drain_beats(tree)
			assert_true(bool(drained.get("ok", false)), "地點 %s 演出失敗: %s" % [location_id, str(drained.get("error", ""))])

	func _close(tree: SceneTree) -> void:
		if QAStepClass.has_visible_qa_id(tree.get_root(), "panel_back"):
			await _click(tree, "panel_back")

	func _advance(tree: SceneTree) -> void:
		await _click(tree, "phase_advance")

	func _boot(tree: SceneTree) -> Dictionary:
		var run := _run(tree)
		assert_eq(int(run.get("day", 0)), 1, "新局天數")
		assert_eq(str(run.get("phase", "")), "morning", "新局時段")
		assert_eq(str(QAStepClass.find_controls_by_name(tree.get_root(), "StatusLabel")[0].text), "第 1 天  morning  第 1 章", "狀態列")
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "hand_slots"), "手牌列")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "state": _state(tree) } }

	func _phase_cycle(tree: SceneTree) -> Dictionary:
		var expected := ["afternoon", "evening", "night", "morning"]
		for phase in expected:
			await _advance(tree)
			assert_eq(str(_run(tree).get("phase", "")), phase, "連續推進時段")
		assert_eq(int(_run(tree).get("day", 0)), 2, "連續推進後天數")
		return { "ok": errors.is_empty(), "errors": errors }

	func _chapter_boundary(tree: SceneTree) -> Dictionary:
		var before := _run(tree)
		assert_eq(int(before.get("day", 0)), 15 if mode == "chapter_d15" else 32, "章節邊界前天數")
		var expected_chapter := 2 if mode == "chapter_d15" else 3
		var chapter_status_count := 0
		var previous_chapter := 1 if mode == "chapter_d15" else 2
		for _step in range(4):
			await _advance(tree)
			var status_step := QAStepClass.find_controls_by_name(tree.get_root(), "StatusLabel")[0] as Label
			var current_chapter := expected_chapter if status_step.text.contains("第 %d 章" % expected_chapter) else previous_chapter
			if current_chapter != previous_chapter:
				chapter_status_count += 1
			previous_chapter = current_chapter
		var after := _run(tree)
		var expected_day := 16 if mode == "chapter_d15" else 33
		assert_eq(int(after.get("day", 0)), expected_day, "章節切換後天數")
		var status_after := QAStepClass.find_controls_by_name(tree.get_root(), "StatusLabel")[0] as Label
		assert_true(status_after.text.contains("第 %d 章" % expected_chapter), "章節狀態列")
		assert_eq(chapter_status_count, 1, "章節邊界只切換一次")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["chapter_changed_once"] } }

	func _coda_jump(tree: SceneTree) -> Dictionary:
		assert_eq(str(_run(tree).get("phase", "")), "afternoon", "D45 coda 起點")
		await _advance(tree)
		assert_eq(str(_run(tree).get("phase", "")), "evening", "D45 afternoon 後進 evening")
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "beat_advance"), "D45 coda 演出入口")
		var drained := await QAStepClass.drain_beats(tree)
		assert_true(bool(drained.get("ok", false)), "D45 coda 演出")
		return { "ok": errors.is_empty(), "errors": errors }

	func _hand_capacity(tree: SceneTree) -> Dictionary:
		var labels := QAStepClass.find_controls_by_qa_id(tree.get_root(), "hand_slots")
		assert_true(not labels.is_empty(), "手牌上限標籤")
		if not labels.is_empty():
			var expected := "14" if required_data_root == "hand_size_default" else "7"
			assert_true((labels[0] as Label).text.contains("/ " + expected), "資料變體手牌上限")
		return { "ok": errors.is_empty(), "errors": errors }

	func _hand_knowledge(tree: SceneTree) -> Dictionary:
		var run := _run(tree)
		var meta := _state(tree).get("meta", {}) as Dictionary
		var knowledge := meta.get("knowledge", {}) as Dictionary
		assert_true(not knowledge.is_empty(), "D9 狀態應有知識卡")
		var knowledge_label := QAStepClass.find_controls_by_qa_id(tree.get_root(), "knowledge_cards")[0] as Label
		var hand_label := QAStepClass.find_controls_by_qa_id(tree.get_root(), "hand_cards")[0] as Label
		for key in knowledge.keys():
			assert_true(knowledge_label.text.contains(str(key)), "知識列必須顯示完整鍵: %s" % str(key))
			assert_false(hand_label.text.contains(str(key)), "知識卡不得出現在手牌列: %s" % str(key))
		assert_true(run.has("hand"), "serialize 手牌欄位")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "hand": run.get("hand", []), "knowledge": knowledge, "evidence": ["knowledge_label_complete", "knowledge_not_in_hand"] } }

	func _arrival(tree: SceneTree) -> Dictionary:
		await _advance(tree)
		await _advance(tree)
		assert_eq(int(_run(tree).get("day", 0)), 1, "到站天數")
		assert_true(_has_text(tree.get_root(), "司機") or _has_text(tree.get_root(), "阿源叔"), "到站演出內容")
		assert_true((_run(tree).get("hand", []) as Array).has("protagonist"), "到站後主角卡")
		return { "ok": errors.is_empty(), "errors": errors }

	func _map_filter(tree: SceneTree) -> Dictionary:
		var ids := _visible_ids(tree, "location::")
		assert_true(ids.has("location::sanquan"), "D2 山泉閣可見")
		assert_false(ids.has("location::n_landmark"), "D2 夜間地點不可見")
		assert_false(ids.has("location::jinghe_back"), "D2 第三章地點不可見")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "locations": ids } }

	func _occupant_empty(tree: SceneTree) -> Dictionary:
		await _enter(tree, "sanquan")
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "slot::d2_morning_intro::ajie"), "occupant 槽")
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "slot::d2_morning_intro::couple"), "另一個 occupant 槽")
		assert_false(QAStepClass.has_visible_qa_id(tree.get_root(), "place::d2_morning_intro::ajie::"), "occupant 不建立放卡按鈕")
		var occupant_label := QAStepClass.find_controls_by_qa_id(tree.get_root(), "slot::d2_morning_intro::ajie")[0] as Label
		assert_true(occupant_label.text.contains("[出席]"), "occupant 必須以出席狀態呈現")
		await _close(tree)
		await _advance(tree)
		await _enter(tree, "sanquan")
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "place::d2_pm_work::work::protagonist"), "空槽必須有真實放卡入口")
		await _click(tree, "place::d2_pm_work::work::protagonist")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["occupant_no_place", "empty_slot_interactive"] } }

	func _requires_locked(tree: SceneTree) -> Dictionary:
		await _enter(tree, "sanquan")
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "slot::d3_pm_sanquan::show_version"), "requires 槽")
		var locked_label := QAStepClass.find_controls_by_qa_id(tree.get_root(), "slot::d3_pm_sanquan::show_version")[0] as Label
		assert_true(locked_label.text.contains("[灰]"), "requires 槽必須以灰色鎖定文字呈現")
		assert_false(QAStepClass.has_visible_qa_id(tree.get_root(), "place::d3_pm_sanquan::show_version::info_husband_version"), "鎖定槽不得放卡")
		var before := _state(tree)
		await _click(tree, "slot::d3_pm_sanquan::show_version")
		assert_eq(JSON.stringify(before), JSON.stringify(_state(tree)), "鎖定槽真實左鍵輸入不得改變狀態")
		await _click(tree, "preview::d3_pm_sanquan::show_version")
		assert_true(_has_text(tree.get_root(), "不知道他們兩個私下說了什麼") or _has_text(tree.get_root(), "目前沒有可放的卡"), "鎖定理由")
		await _click(tree, "dialog_confirm::preview")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["locked_visual", "locked_click_blocked", "locked_reason"] } }

	func _unlock_same_panel(tree: SceneTree) -> Dictionary:
		await _enter(tree, "columbarium")
		var locked_label := QAStepClass.find_controls_by_qa_id(tree.get_root(), "slot::d9_pm_columbarium::compare_years")[0] as Label
		assert_true(locked_label.text.contains("[灰]"), "比對槽起始為鎖定")
		assert_true(_visible_ids(tree, "place::d9_pm_columbarium::compare_years::").is_empty(), "比對槽起始不可放卡")
		await _click(tree, "place::d9_pm_columbarium::count::protagonist")
		var place_ids := _visible_ids(tree, "place::d9_pm_columbarium::compare_years::")
		assert_true(not place_ids.is_empty(), "取得前置後同面板立即顯示比對放卡入口")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["locked_before", "unlocked_same_panel"] } }

	func _condition_hidden(tree: SceneTree, main_node: Control) -> Dictionary:
		await _enter(tree, "temple")
		assert_true(not _has_text(main_node, "阿婕"), "無邀請分支不顯示阿婕內容")
		assert_true(not _has_text(main_node, "阿薇"), "無邀請分支不顯示阿薇內容")
		assert_true(_has_text(main_node, "她沒聽見") or _has_text(main_node, "一個人走"), "條件成立的 D32 分支")
		return { "ok": errors.is_empty(), "errors": errors }

	func _competing_beats(tree: SceneTree) -> Dictionary:
		var evidence: Array[String] = []
		for loc_id in ["sanquan", "oldstreet", "temple"]:
			await _enter(tree, loc_id)
			assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "panel_back"), "D3 %s 面板" % loc_id)
			var expected_text: String = str({
				"sanquan": "阿宏還在後面搬貨",
				"oldstreet": "麵攤在收桌子",
				"temple": "金伯在整理慶典用具",
			}.get(loc_id, ""))
			assert_true(_has_text(tree.get_root(), expected_text), "D3 %s 競爭 beat 內容" % loc_id)
			evidence.append(loc_id + "_beat")
			await _close(tree)
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": evidence } }

	func _place_effect(tree: SceneTree) -> Dictionary:
		var before := _run(tree)
		await _enter(tree, "sanquan")
		await _click(tree, "place::d3_pm_sanquan::help_ahong::protagonist")
		var after := _run(tree)
		assert_true((after.get("hand", []) as Array).has("protagonist"), "主角卡是常駐手牌卡")
		assert_true((after.get("flags", {}) as Dictionary).get("ahong_last_normal_contact", false), "on_place 旗標")
		var after_state := _state(tree)
		assert_true((after_state.get("meta", {}) as Dictionary).get("knowledge", {}).has("info_ahong_private") or (after.get("hand", []) as Array).has("info_ahong_private"), "on_place 知識效果")
		assert_true(_has_text(tree.get_root(), "搬到一半他講了一件小事"), "on_place 效果文字必須在 UI 顯示")
		assert_false(bool(before.get("action_spent", false)), "放置前 action 未用")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["effect_text_visible", "effect_state"] } }

	func _action_spent(tree: SceneTree) -> Dictionary:
		await _enter(tree, "sanquan")
		await _click(tree, "place::d3_pm_sanquan::help_ahong::protagonist")
		await _close(tree)
		await _enter(tree, "oldstreet")
		assert_true(_visible_ids(tree, "place::").is_empty(), "第二地點不得再出現主角放卡入口")
		return { "ok": errors.is_empty(), "errors": errors }

	func _panel_rebuild(tree: SceneTree) -> Dictionary:
		await _enter(tree, "sanquan")
		await _click(tree, "place::d3_pm_sanquan::help_ahong::protagonist")
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "slot::d3_pm_sanquan::help_ahong"), "放置後槽位仍在面板")
		assert_false(QAStepClass.has_visible_qa_id(tree.get_root(), "place::d3_pm_sanquan::help_ahong::protagonist"), "放置後舊放卡按鈕移除")
		assert_true(not _visible_ids(tree, "place::d3_pm_sanquan::show_version::").is_empty(), "放置後新條件成立的槽立即開放")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["old_place_removed", "new_slot_open"] } }

	func _compare_free(tree: SceneTree) -> Dictionary:
		await _enter(tree, "columbarium")
		assert_false((_state(tree).get("meta", {}) as Dictionary).get("knowledge", {}).has("k_forty_something"), "自然比較前不得預注入知識")
		await _click(tree, "place::d9_pm_columbarium::count::protagonist")
		var before := _run(tree)
		var compare_ids := _visible_ids(tree, "place::d9_pm_columbarium::compare_years::")
		assert_true(not compare_ids.is_empty(), "D9 比對情報卡入口")
		await _click(tree, compare_ids[0])
		var after := _run(tree)
		assert_eq(bool(after.get("action_spent", false)), bool(before.get("action_spent", false)), "比對槽不新增行動消耗")
		assert_true((_state(tree).get("meta", {}) as Dictionary).get("knowledge", {}).has("k_forty_something"), "比對後知識落帳")
		assert_eq(int(after.get("day", 0)), int(before.get("day", 0)), "比對不推進時間")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["knowledge_absent_before", "knowledge_gained", "compare_no_extra_action"] } }

	func _incompatible_absent(tree: SceneTree) -> Dictionary:
		await _enter(tree, "sanquan")
		var run := _run(tree)
		var hand := run.get("hand", []) as Array
		var visible_cards: Array[String] = []
		for qid in _visible_ids(tree, "place::d22_pm_sandbags::work::"):
			visible_cards.append(qid.get_slice("::", 3))
		for card_id in hand:
			if str(card_id) != "protagonist":
				assert_false(visible_cards.has(str(card_id)), "不相容卡不可建立 place 按鈕: %s" % str(card_id))
		return { "ok": errors.is_empty(), "errors": errors }

	func _attention(tree: SceneTree) -> Dictionary:
		await _enter(tree, "sanquan")
		var before := _run(tree).get("npc_action_counts", {}) as Dictionary
		await _click(tree, "place::d22_pm_sandbags::work::protagonist")
		var after := _run(tree).get("npc_action_counts", {}) as Dictionary
		assert_eq(int(after.get("acai", 0)), int(before.get("acai", 0)) + 1, "阿財投入帳恰加一")
		var free_before := int((_run(tree).get("npc_action_counts", {}) as Dictionary).get("acai", 0))
		await _click(tree, "choose::d22_pm_sandbags::acai_read::obs_walk")
		var free_after := int((_run(tree).get("npc_action_counts", {}) as Dictionary).get("acai", 0))
		assert_eq(free_after, free_before, "免費 choice 不得增加 attention 投入帳")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["attention_success", "attention_free_unchanged"] } }

	func _choice_collapse(tree: SceneTree) -> Dictionary:
		await _enter(tree, "sanquan")
		await _click(tree, "choose::d22_pm_sandbags::acai_read::obs_walk")
		assert_false(QAStepClass.has_visible_qa_id(tree.get_root(), "choose::d22_pm_sandbags::acai_read::obs_hands"), "choice 其餘選項消失")
		assert_false(QAStepClass.has_visible_qa_id(tree.get_root(), "choose::d22_pm_sandbags::acai_read::obs_talk"), "choice 其餘選項消失")
		return { "ok": errors.is_empty(), "errors": errors }

	func _choice_resolved(tree: SceneTree) -> Dictionary:
		await _enter(tree, "sanquan")
		await _click(tree, "choose::d22_pm_sandbags::acai_read::obs_walk")
		await _close(tree)
		await _enter(tree, "sanquan")
		var resolved_label := QAStepClass.find_controls_by_qa_id(tree.get_root(), "slot::d22_pm_sandbags::obs_walk")[0] as Label
		assert_true(resolved_label.text.contains("[已放]"), "已選 choice 必須渲染 resolved")
		assert_false(QAStepClass.has_visible_qa_id(tree.get_root(), "choose::d22_pm_sandbags::acai_read::obs_walk"), "已選 choice 不可再操作")
		var before := _state(tree)
		await _click(tree, "slot::d22_pm_sandbags::obs_walk")
		assert_eq(JSON.stringify(before), JSON.stringify(_state(tree)), "resolved 槽真實輸入不得反悔")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["resolved_render", "resolved_click_noop"] } }

	func _choice_path(tree: SceneTree, with_card: bool) -> Dictionary:
		await _enter(tree, "sanquan")
		var before := _state(tree)
		if with_card:
			var place_ids := _visible_ids(tree, "place::d22_pm_sandbags::obs_walk::")
			assert_true(not place_ids.is_empty(), "持卡 choice 的放卡入口")
			if not place_ids.is_empty():
				await _click(tree, place_ids[0])
		else:
			await _click(tree, "choose::d22_pm_sandbags::acai_read::obs_walk")
		var after := _state(tree)
		var after_run := after.get("run", {}) as Dictionary
		var comparable := {
			"choice": (after_run.get("choices", {}) as Dictionary).get("d22_pm_sandbags::acai_read", ""),
			"slot_placed": (after_run.get("slots_placed", {}) as Dictionary).get("d22_pm_sandbags::obs_walk", false),
			"knowledge": after.get("meta", {}).get("knowledge", {}).get("info_acai_walk", false),
		}
		if comparison_group == "p1af_22_choice_equivalence":
			return { "ok": errors.is_empty(), "errors": errors, "observations": {
				"choice_result_projection": comparable,
				"fixture_causality": {
					"with_card": with_card,
					"source_hand": before.get("run", {}).get("hand", []),
				},
				"evidence": ["case_ok"],
			} }
		assert_true((after.get("run", {}) as Dictionary).get("choices", {}).has("d22_pm_sandbags::acai_read"), "choice 結算")
		assert_false(JSON.stringify(before) == JSON.stringify(after), "choice 結算應改變狀態")
		return { "ok": errors.is_empty(), "errors": errors }

	func _choice_leave(tree: SceneTree) -> Dictionary:
		await _enter(tree, "sanquan")
		var before := _state(tree)
		await _close(tree)
		await _enter(tree, "sanquan")
		assert_eq(JSON.stringify(before), JSON.stringify(_state(tree)), "不選離開不得結算")
		return { "ok": errors.is_empty(), "errors": errors }

	func _echo(tree: SceneTree) -> Dictionary:
		var text_ok := false
		match mode:
			"echo_d5_attended":
				assert_false(_has_text(tree.get_root(), "旁邊有人提起"), "到場不播 D5 殘響")
				text_ok = true
			"echo_d5_missed", "echo_d5_repeat":
				assert_true(_has_text(tree.get_root(), "旁邊有人提起"), "錯過時播 D5 殘響")
				text_ok = true
			"echo_d8":
				assert_true(_has_text(tree.get_root(), "不管你今天去哪"), "D8 殘響文字")
				text_ok = true
			"echo_d13":
				assert_true(_has_text(tree.get_root(), "有人說阿薇那天"), "D13 殘響文字")
				text_ok = true
		assert_true(text_ok, "殘響案例已執行")
		return { "ok": errors.is_empty(), "errors": errors }

	func _d27_order(tree: SceneTree) -> Dictionary:
		var run := _run(tree)
		var flags := run.get("flags", {}) as Dictionary
		var knowledge := (_state(tree).get("meta", {}) as Dictionary).get("knowledge", {}) as Dictionary
		var texts := _texts(tree.get_root())
		var first_text_index := texts.find("這是你唯一能親眼確認的人。")
		var second_text_index := texts.find("有幾個人在閃躲，而你說不上來為什麼。")
		if mode == "d27_both":
			assert_true(first_text_index >= 0 and second_text_index > first_text_index, "D27 evening UI fixed beat 順序")
		else:
			assert_true(first_text_index >= 0, "D27 partial 第一個 fixed beat UI")
			assert_true(second_text_index < 0, "D27 partial 不應顯示第二個 fixed beat")
		assert_true(bool(flags.get("dodger_awei_cleared", false)), "D27 第一個 fixed beat 旗標")
		if mode == "d27_both":
			assert_true(knowledge.has("k_town_covers"), "D27 順序後取得知識")
		else:
			assert_false(knowledge.has("k_town_covers"), "D27 缺一條前置不取得知識")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["evening_ui_order", "evening_outcome"] } }

	func _night_resolution(tree: SceneTree, main_node: Control) -> Dictionary:
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "location::n_landmark"), "D10 夜間免費地點")
		await _enter(tree, "n_landmark")
		assert_true(_has_text(tree.get_root(), "夜鎮裡有一個特殊的東西"), "D10 免費地點可真實進入")
		await _close(tree)
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "location::n_ahong_1"), "D10 已到付費標記開放日")
		await _enter(tree, "n_ahong_1")
		assert_true(_has_text(tree.get_root(), "夜間標記尚未開放"), "付費夜間標記必須顯示鎖定 stub")
		await _close(tree)
		assert_true(not _has_text(main_node, "發狂卡"), "D10 night 不產生發狂卡")
		var hand := _run(tree).get("hand", []) as Array
		for card_id in hand:
			assert_false(str(card_id).begins_with("madness"), "夜間不應產生 madness 卡")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "locations": _visible_ids(tree, "location::"), "evidence": ["night_fixed_priority", "night_free_interaction", "night_paid_locked", "night_no_madness"] } }

	func _night_resolution_d1(tree: SceneTree) -> Dictionary:
		await _advance(tree)
		await _advance(tree)
		await _advance(tree)
		assert_eq(str(_run(tree).get("phase", "")), "night", "D1 夜間起點")
		assert_true(_has_text(tree.get_root(), "一條走廊，兩側都是門"), "D1 fixed night beat 優先演出")
		return { "ok": errors.is_empty(), "errors": errors }

	func _sleep_d24(tree: SceneTree, main_node: Control) -> Dictionary:
		assert_true(_has_text(main_node, "老曾") or (_run(tree).get("flags", {}) as Dictionary).get("laozeng_patrol_d24", false), "D24 night fixed beat")
		await _click(tree, "phase_advance")
		assert_eq(int(_run(tree).get("day", 0)), 25, "D24 night 真實睡眠輸入後到 D25")
		assert_eq(str(_run(tree).get("phase", "")), "morning", "D24 night 真實睡眠輸入後到 morning")
		assert_true((_run(tree).get("flags", {}) as Dictionary).get("laozeng_patrol_d24", false), "D24 睡眠解析落帳")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["sleep_input", "sleep_resolution"] } }

	func _night_place(tree: SceneTree) -> Dictionary:
		await _enter(tree, "n_landmark")
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "place::n_take_something::take::protagonist"), "夜間主角放卡入口")
		var before := _run(tree)
		await _click(tree, "place::n_take_something::take::protagonist")
		var after := _run(tree)
		assert_true(bool((after.get("flags", {}) as Dictionary).get("took_from_night", false)), "夜間放卡效果")
		assert_false(bool(after.get("action_spent", false)), "夜間放主角卡不耗行動")
		assert_eq(int(after.get("day", 0)), int(before.get("day", 0)), "夜間放卡不推進時間")
		return { "ok": errors.is_empty(), "errors": errors }

	func _coda_full(tree: SceneTree) -> Dictionary:
		assert_eq(str(_run(tree).get("phase", "")), "evening", "D45 coda 起點")
		var drained := await QAStepClass.drain_beats(tree)
		assert_true(bool(drained.get("ok", false)), "D45 真 beat 演出")
		var place_ids := _visible_ids(tree, "place::d45_then::compare_registry::")
		assert_true(not place_ids.is_empty(), "D45 比對槽")
		if not place_ids.is_empty():
			await _click(tree, place_ids[0])
		assert_true((_state(tree).get("meta", {}) as Dictionary).get("knowledge", {}).has("k_already_on_list"), "D45 知識升級")
		assert_false(bool(_run(tree).get("action_spent", false)), "D45 比對不耗行動")
		await _close(tree)
		await _advance(tree)
		assert_true(_has_text(tree.get_root(), "[結局 stub]"), "D45 結束後先顯示結局 stub")
		await _advance(tree)
		var after := _run(tree)
		assert_eq(int(after.get("day", 0)), 1, "D45 結束回到第一天")
		assert_eq(str(after.get("phase", "")), "morning", "D45 結束回到 morning")
		assert_eq(JSON.stringify(after.get("hand", [])), JSON.stringify(["protagonist"]), "跨輪手牌重置")
		assert_true((_state(tree).get("meta", {}) as Dictionary).get("knowledge", {}).has("k_already_on_list"), "跨輪保留知識")
		var run_fields: Array[String] = ["flags", "switches", "switch_progress", "relations", "slots_placed", "choices", "beats_entered"]
		for field in run_fields:
			assert_true((after.get(field, {}) as Dictionary).is_empty(), "跨輪欄位清空: %s" % field)
		assert_false(_has_text(tree.get_root(), "[結局 stub]"), "關閉結局 stub 後才進入新輪 UI")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["run_fields_cleared", "reset_ui_state"] } }

	func _full_walk(tree: SceneTree) -> Dictionary:
		var safety := 0
		var first_round_done := false
		var second_round_arrival := false
		while safety < 420:
			safety += 1
			var run := _run(tree)
			var day := int(run.get("day", 0))
			var phase := str(run.get("phase", ""))
			if not first_round_done and day == 1 and phase == "morning" and safety > 1:
				first_round_done = true
				assert_true((_state(tree).get("meta", {}) as Dictionary).get("knowledge", {}).has("k_already_on_list"), "第一輪升級知識跨輪保留")
				assert_eq(JSON.stringify(run.get("hand", [])), JSON.stringify(["protagonist"]), "第一輪結束手牌重置")
				for reset_field in ["flags", "switches", "switch_progress", "relations", "slots_placed", "choices", "beats_entered"]:
					assert_true((run.get(reset_field, {}) as Dictionary).is_empty(), "完整走查跨輪欄位清空: %s" % reset_field)
				if _has_text(tree.get_root(), "[結局 stub]"):
					await _advance(tree)
				continue

			if first_round_done and day == 1 and phase == "evening":
				assert_true(_has_text(tree.get_root(), "司機") or _has_text(tree.get_root(), "阿源叔"), "第二輪第一天 evening 到站演出")
				var protagonist_count := 0
				for card_id in run.get("hand", []) as Array:
					if str(card_id) == "protagonist":
						protagonist_count += 1
				assert_eq(protagonist_count, 1, "第二輪主角卡恰好一張")
				second_round_arrival = true
				break

			if phase == "evening" and day == 45:
				if QAStepClass.has_visible_qa_id(tree.get_root(), "beat_advance"):
					var coda_drain := await QAStepClass.drain_beats(tree)
					assert_true(bool(coda_drain.get("ok", false)), "完整走查 D45 coda 演出")
				var coda_places := _visible_ids(tree, "place::d45_then::compare_registry::")
				assert_true(not coda_places.is_empty(), "完整走查 D45 必須持有名冊情報卡")
				if coda_places.is_empty():
					return { "ok": false, "errors": errors }
				await _click(tree, coda_places[0])
				await _close(tree)
				await _advance(tree)
				continue

			if phase == "morning" or phase == "afternoon":
				if not bool(run.get("action_spent", false)):
					var locations := _visible_ids(tree, "location::")
					if day == 13 and phase == "afternoon" and locations.has("location::temple"):
						var prioritized: Array[String] = ["location::temple"]
						for location_qid in locations:
							if location_qid != "location::temple":
								prioritized.append(location_qid)
						locations = prioritized
					var acted := false
					for qid in locations:
						await _click(tree, qid)
						var drained := await QAStepClass.drain_beats(tree)
						assert_true(bool(drained.get("ok", false)), "完整走查演出: %s" % qid)
						var choices := _visible_ids(tree, "choose::")
						if not choices.is_empty():
							await _click(tree, choices[0])
						var places := _visible_ids(tree, "place::")
						if not places.is_empty():
							var preferred := places[0]
							var registry_place := "place::d13_pm_registry::read::protagonist"
							if day == 13 and phase == "afternoon" and places.has(registry_place):
								preferred = registry_place
							for place_id in places:
								if place_id.ends_with("::protagonist"):
									preferred = place_id
									break
							await _click(tree, preferred)
							acted = true
						await _close(tree)
						if acted or bool(_run(tree).get("action_spent", false)):
							break
						if QAStepClass.has_visible_qa_id(tree.get_root(), "panel_back"):
							await _close(tree)
				await _advance(tree)
				continue

			await _advance(tree)

		assert_true(first_round_done, "完整走查必須走完第一輪並回到第二輪")
		assert_true(second_round_arrival, "完整走查必須抵達第二輪第一天 evening")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "iterations": safety, "final_state": _state(tree), "evidence": ["full_walk_d45", "first_round_reset", "second_round_arrival", "second_round_protagonist_exactly_one"] } }
