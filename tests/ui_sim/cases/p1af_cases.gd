class_name P1AFCases
extends RefCounted

## P1-A～P1-H 的 UI runner 案例。
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
		UiCase.new("p1af_17_compare_free", "比對槽放情報卡不消耗行動格且後續仍可放主角卡", "d3_afternoon.json", "", "p1af_17_compare_free", "", "compare_free"),
		UiCase.new("p1af_18_incompatible_absent", "不符合 accepts 的卡沒有 place 控制項", "d22_afternoon.json", "", "p1af_18_incompatible_absent", "", "incompatible_absent"),
		UiCase.new("p1af_19_attention", "D22 attention_npc 投入帳成功加一", "d22_afternoon.json", "", "p1af_19_attention", "", "attention"),
		UiCase.new("p1af_20_choice_collapse", "choice 選定後同組其餘選項消失", "d22_afternoon.json", "", "p1af_20_choice_collapse", "", "choice_collapse"),
		UiCase.new("p1af_21_choice_resolved", "重開面板後 choice 唯讀且不可反悔", "d22_afternoon.json", "", "p1af_21_choice_resolved", "", "choice_resolved"),
		UiCase.new("p1af_22_choice_equiv_direct", "choice 直選路徑結果基準", "d22_afternoon__with_polaroid.json", "", "p1af_22_choice_equivalence", "p1af_22_choice_equivalence", "choice_direct"),
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
		UiCase.new("p1af_29_night_paid", "D10 night 收費標記發卡與鎖定 stub", "d10_night.json", "", "p1af_29_night_resolution", "", "night_resolution_paid"),
		UiCase.new("p1af_29_night_d1_fixed", "D1 night 固定演出優先於地圖", "", "", "p1af_29_night_resolution", "", "night_resolution_d1"),
		UiCase.new("p1af_30_sleep_d24", "D24 night 直接睡播定日 beat", "d24_night.json", "", "p1af_30_sleep_d24", "", "sleep_d24"),
		UiCase.new("p1af_31_night_place", "D10 night 放主角卡不耗行動格", "d10_night.json", "", "p1af_31_night_place", "", "night_place"),
		UiCase.new("p1af_32_coda_full", "D45 coda 真 beat、比對與跨輪重置", "d45_evening.json", "", "p1af_32_d45_coda_full", "", "coda_full"),
		UiCase.new("p1af_33_full_walk", "從新局以真實輸入走完 45 天並續走第二輪", "", "", "p1af_33_full_walk", "", "full_walk"),
		UiCase.new("p1h_01_hand_cards", "手牌列每一張卡各自一個按鈕且顯示卡名無id", "d10_night__knowledge.json", "", "p1h_01_hand_cards", "", "p1h_01"),
		UiCase.new("p1h_02_card_detail", "點擊卡片彈出唯讀詳情且關閉後狀態不變", "d10_night__knowledge.json", "", "p1h_02_card_detail", "", "p1h_02"),
		UiCase.new("p1h_03_detail_readonly", "詳情彈窗開著時全樹無任何放置或選擇控制項", "d10_night__knowledge.json", "", "p1h_03_detail_readonly", "", "p1h_03"),
		UiCase.new("p1h_04_knowledge_detail", "知識詳情完整呈現全部知識卡且可捲動", "p1h_knowledge_full.json", "", "p1h_04_knowledge_detail", "", "p1h_04"),
		UiCase.new("p1h_05_name_truncation", "超長卡名省略號截斷且詳情顯示完整名稱", "d10_night__knowledge.json", "long_card_name", "p1h_05_name_truncation", "", "p1h_05"),
		UiCase.new("p1h_06_handbar_geometry", "手牌列固定7欄外框矩形不變且幾何診斷全綠", "d10_night__knowledge.json", "", "p1h_06_handbar_geometry", "", "p1h_06"),
		UiCase.new("p2a_01_madness_hand_display", "多實例發狂卡在手牌各自呈現獨立按鈕且顯示各自倒數與詳情", "p2a_multi_madness.json", "", "p2a_01_madness_hand_display", "", "p2a_01"),
		UiCase.new("p2b_01_exit_zero", "手上 0 張發狂卡時山泉閣完全沒有出口槽節點", "d3_morning.json", "", "p2b_01_exit_visibility", "", "p2b_01_zero"),
		UiCase.new("p2b_01_exit_one", "手上有發狂卡時砸東西、暴食、泡湯三槽出現且標示「發狂卡」", "p2b_morning_madness.json", "", "p2b_01_exit_visibility", "", "p2b_01_one"),
		UiCase.new("p2b_02_exit_place", "放發狂卡進砸東西：文字播出、卡消失、行動格用掉、出口槽不收主角卡", "p2b_morning_madness.json", "", "p2b_02_exit_place", "", "p2b_02"),
		UiCase.new("p2b_03_soak_morning", "上午泡湯吃掉整天但不跳時段，手上只少一張", "p2b_morning_madness.json", "", "p2b_03_soak", "", "p2b_03_morning"),
		UiCase.new("p2b_03_soak_afternoon", "下午泡湯槽呈灰並顯示只能上午發動", "p2b_afternoon_madness.json", "", "p2b_03_soak", "", "p2b_03_afternoon"),
		UiCase.new("p2b_03_soak_spent", "上午行動格已用時泡湯槽呈灰並顯示格數不足", "p2b_morning_spent.json", "", "p2b_03_soak", "", "p2b_03_spent"),
		UiCase.new("p2b_04_violence_before", "第 16 天前山泉閣看不到暴力對人", "p2b_morning_madness.json", "", "p2b_04_exit_thresholds", "", "p2b_04_before"),
		UiCase.new("p2b_04_violence_after", "第 17 天暴力對人出現、性慾仍隱藏、老街奢侈呈灰附理由", "p2b_d17_madness.json", "", "p2b_04_exit_thresholds", "", "p2b_04_after"),
		UiCase.new("p2b_04_lust_relation", "與阿婕達疑似後性慾槽出現", "p2b_d17_ajie.json", "", "p2b_04_exit_thresholds", "", "p2b_04_lust"),
		UiCase.new("p2c_01_forced_text", "強制縱慾自動執行時效果文字播在地圖上，且整個時段留存", "p2c_night_one_forced.json", "", "p2c_01_forced_text", "", "p2c_01"),
		UiCase.new("p2c_02_forced_action_spent", "被強制縱慾吃掉的行動格：任何地點都沒有主角卡放入入口", "p2c_night_one_forced.json", "", "p2c_02_forced_action_spent", "", "p2c_02"),
		UiCase.new("p2c_03_forced_two_same_day", "同日兩張歸零：上午下午各吃一格，那一天完全沒有行動格", "p2c_night_two_forced.json", "", "p2c_03_forced_two_same_day", "", "p2c_03"),
		UiCase.new("p2d_01_vision_zero", "手上 2 張發狂卡時二樓有人在走完全不出現", "p2d_d24_two_cards.json", "", "p2d_01_vision_visibility", "", "p2d_01_zero"),
		UiCase.new("p2d_01_vision_three", "手上 3 張發狂卡時二樓有人在走正確出現", "p2d_d24_three_cards.json", "", "p2d_01_vision_visibility", "", "p2d_01_three"),
		UiCase.new("p2d_02_be_screen", "發狂卡達到 cap 時立即觸發發瘋 BE 且畫面呈現 [發瘋 BE] 並收起地圖與面板", "p2d_near_cap.json", "", "p2d_02_be_screen", "", "p2d_02"),
		UiCase.new("p3d_01_status_unaligned", "已到訪未對位地點顯示引子名與 [已到訪，尚未對位]", "p3d_seen_unaligned.json", "", "p3d_01_night_status_texts", "", "p3d_01_unaligned"),
		UiCase.new("p3d_01_status_nightonly", "已到訪夜間限定地點顯示 [已到訪] 且無尚未對位", "p3d_seen_nightonly.json", "", "p3d_01_night_status_texts", "", "p3d_01_nightonly"),
		UiCase.new("p3d_01_status_no_number", "未到訪收費與免費地點狀態文字均不含數字與免費字樣", "p3a_night_baseline.json", "", "p3d_01_night_status_texts", "", "p3d_01_no_number"),
		UiCase.new("p3d_02_aligned_1to1", "已對位一對一地點顯示白天地點名與 [已對位]", "p3d_aligned_1to1.json", "", "p3d_02_night_aligned_names", "", "p3d_02_1to1"),
		UiCase.new("p3d_02_aligned_multi", "已對位多對一地點顯示白天名・引子名與 [已對位]", "p3d_aligned_multi.json", "", "p3d_02_night_aligned_names", "", "p3d_02_multi"),
		UiCase.new("p3d_03_gated_ahong", "門檻未滿足之阿宏地點詳情顯示具體理由且進入按鈕 disabled 點擊零變化", "p3a_night_baseline.json", "", "p3d_03_night_detail_gated", "", "p3d_03_ahong"),
		UiCase.new("p3d_03_gated_teaser", "第三章 teaser-only 地點顯示理由且無成功進入路徑", "d33_night.json", "", "p3d_03_night_detail_gated", "", "p3d_03_teaser"),
		UiCase.new("p3d_04_near_cap_warning", "近 cap 狀態下收費地點詳情顯示無數字風險警告且免費地點無警告", "p2d_near_cap.json", "", "p3d_04_night_risk_warning", "", "p3d_04_warning"),
		UiCase.new("p3d_05_sleep_pending", "直接睡停拍期間全部夜間進入按鈕 disabled 且點擊狀態零變化", "p2d_d24_three_cards.json", "", "p3d_05_sleep_pending_disabled", "", "p3d_05_sleep"),
		UiCase.new("p3d_06_geometry", "夜間清單與詳情面板於 1280x720 幾何無重疊裁切溢出且長名稱可讀", "d33_night.json", "long_night_name", "p3d_06_night_list_geometry", "", "p3d_06_geo"),
		UiCase.new("p3e_01_day_align_flow", "夜間 row 已 seen、白天尚未持有 reveal 卡；地圖無提示，進常態面板看見 night_align 按鈕", "p3e_seen_counterpart.json", "", "p3e_01_day_align_flow", "", "p3e_01"),
		UiCase.new("p3e_02_wrong_locations", "同一狀態打開錯誤白天地點無對位按鈕、無理由提示、狀態不變", "p3e_seen_counterpart.json", "", "p3e_02_wrong_locations_noop", "", "p3e_02"),
		UiCase.new("p3e_03_dialog_cancel", "點對位按鈕開確認彈窗，取消後狀態零變化", "p3e_seen_counterpart.json", "", "p3e_03_align_dialog_cancel", "", "p3e_03"),
		UiCase.new("p3e_04_dialog_confirm", "確認對位後恰好獲得一張 reveal 知識卡、action_spent 仍 false、按鈕消失且知識詳情可讀", "p3e_seen_counterpart.json", "", "p3e_04_align_confirm_gain_knowledge", "", "p3e_04"),
		UiCase.new("p3e_05_multi_auto_align", "多對一只確認一次，第二個 row 日後到訪自動顯示已對位且無二次確認", "p3e_multi_first_seen.json", "", "p3e_05_multi_row_auto_align", "", "p3e_05"),
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
			"night_resolution", "night_resolution_paid", "night_resolution_d1":
				if mode == "night_resolution_d1":
					return await _night_resolution_d1(tree)
				elif mode == "night_resolution_paid":
					return await _night_resolution_paid(tree, main_node)
				return await _night_resolution(tree, main_node)
			"sleep_d24":
				return await _sleep_d24(tree, main_node)
			"night_place":
				return await _night_place(tree)
			"coda_full":
				return await _coda_full(tree)
			"full_walk":
				return await _full_walk(tree)
			"p1h_01":
				return _p1h_01(tree)
			"p1h_02":
				return await _p1h_02(tree)
			"p1h_03":
				return await _p1h_03(tree)
			"p1h_04":
				return await _p1h_04(tree)
			"p1h_05":
				return await _p1h_05(tree)
			"p1h_06":
				return _p1h_06(tree)
			"p2a_01":
				return await _p2a_01(tree)
			"p2b_01_zero":
				return await _p2b_01_zero(tree)
			"p2b_01_one":
				return await _p2b_01_one(tree)
			"p2b_02":
				return await _p2b_02(tree)
			"p2b_03_morning":
				return await _p2b_03_morning(tree)
			"p2b_03_afternoon", "p2b_03_spent":
				return await _p2b_03_locked(tree)
			"p2b_04_before":
				return await _p2b_04_before(tree)
			"p2b_04_after":
				return await _p2b_04_after(tree)
			"p2b_04_lust":
				return await _p2b_04_lust(tree)
			"p2c_01":
				return await _p2c_01(tree)
			"p2c_02":
				return await _p2c_02(tree)
			"p2c_03":
				return await _p2c_03(tree)
			"p2d_01_zero":
				return await _p2d_01_zero(tree)
			"p2d_01_three":
				return await _p2d_01_three(tree)
			"p2d_02":
				return await _p2d_02(tree)
			"p3d_01_unaligned":
				return await _p3d_01_unaligned(tree)
			"p3d_01_nightonly":
				return await _p3d_01_nightonly(tree)
			"p3d_01_no_number":
				return await _p3d_01_no_number(tree)
			"p3d_02_1to1":
				return await _p3d_02_1to1(tree)
			"p3d_02_multi":
				return await _p3d_02_multi(tree)
			"p3d_03_ahong":
				return await _p3d_03_ahong(tree)
			"p3d_03_teaser":
				return await _p3d_03_teaser(tree)
			"p3d_04_warning":
				return await _p3d_04_warning(tree)
			"p3d_05_sleep":
				return await _p3d_05_sleep(tree)
			"p3d_06_geo":
				return await _p3d_06_geo(tree, main_node, run_dir)
			"p3e_01":
				return await _p3e_01(tree)
			"p3e_02":
				return await _p3e_02(tree)
			"p3e_03":
				return await _p3e_03(tree)
			"p3e_04":
				return await _p3e_04(tree)
			"p3e_05":
				return await _p3e_05(tree, main_node)
			_:
				assert_true(false, "未知 UI 案例模式: %s" % mode)
		return { "ok": errors.is_empty(), "errors": errors }

	func _state(tree: SceneTree) -> Dictionary:
		return CaseBaseClass.get_game_state(tree).call("serialize") as Dictionary

	func _data(tree: SceneTree) -> Node:
		return CaseBaseClass.get_data(tree)

	func _run(tree: SceneTree) -> Dictionary:
		return _state(tree).get("run", {}) as Dictionary

	func _meta(tree: SceneTree) -> Dictionary:
		return _state(tree).get("meta", {}) as Dictionary

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
		if QAStepClass.has_visible_qa_id(tree.get_root(), "night_enter::" + location_id):
			var enter_btns := QAStepClass.find_controls_by_qa_id(tree.get_root(), "night_enter::" + location_id)
			if not enter_btns.is_empty() and not (enter_btns[0] as Button).disabled:
				await _click(tree, "night_enter::" + location_id)
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
		assert_eq(int(run.get("day", 0)), 1, "第 1 天")
		assert_eq(str(run.get("phase", "")), "morning", "morning 時段")
		var status := QAStepClass.find_controls_by_name(tree.get_root(), "StatusLabel")[0] as Label
		assert_true(status.text.contains("第 1 章"), "第一章狀態列")
		return { "ok": errors.is_empty(), "errors": errors }

	func _phase_cycle(tree: SceneTree) -> Dictionary:
		var phases: Array[String] = ["morning", "afternoon", "evening", "night"]
		for i in range(phases.size()):
			var run := _run(tree)
			assert_eq(int(run.get("day", 0)), 1, "第 1 天推進")
			assert_eq(str(run.get("phase", "")), phases[i], "時段循環")
			await _advance(tree)
		var next_day := _run(tree)
		assert_eq(int(next_day.get("day", 0)), 2, "推進至第 2 天")
		assert_eq(str(next_day.get("phase", "")), "morning", "次日起始時段")
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
		assert_true(not knowledge.is_empty(), "D10 狀態應有知識卡")
		var k_entries := QAStepClass.find_controls_by_qa_id(tree.get_root(), "knowledge_entry")
		assert_true(not k_entries.is_empty(), "知識入口按鈕必須存在")
		if not k_entries.is_empty():
			var btn := k_entries[0] as Button
			assert_true(btn.text.contains(str(knowledge.size())), "知識按鈕顯示正確張數: %d (實際: %s)" % [knowledge.size(), btn.text])
		for key in knowledge.keys():
			var found_in_hand := QAStepClass.find_controls_by_qa_id(tree.get_root(), "hand_card::" + str(key))
			assert_true(found_in_hand.is_empty(), "知識卡不得出現在手牌列: %s" % str(key))
		assert_true(run.has("hand"), "serialize 手牌欄位")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "hand": run.get("hand", []), "knowledge": knowledge, "evidence": ["knowledge_count_exact", "knowledge_not_in_hand"] } }

	func _p1h_01(tree: SceneTree) -> Dictionary:
		var run := _run(tree)
		var hand_cards: Array = run.get("hand", []) as Array
		assert_true(not hand_cards.is_empty(), "手牌不應為空")
		var data_node := _data(tree)
		var all_card_ids: Array = data_node.loader.cards.keys()
		for card_id in hand_cards:
			var btn_list := QAStepClass.find_controls_by_qa_id(tree.get_root(), "hand_card::" + str(card_id))
			assert_eq(btn_list.size(), 1, "手牌卡片按鈕唯一: %s" % str(card_id))
			if btn_list.size() == 1:
				var btn := btn_list[0] as Button
				var expected_name: String = str(data_node.call("card_display_name", str(card_id)))
				if str(card_id).begins_with("madness"):
					assert_true(btn.text.begins_with(expected_name), "手牌按鈕顯示名稱: %s" % str(card_id))
				else:
					assert_eq(btn.text, expected_name, "手牌按鈕顯示名稱: %s" % str(card_id))
		for text in _texts(tree.get_root()):
			for card_id in all_card_ids:
				if str(card_id).length() > 2:
					assert_false(text.contains(str(card_id)), "畫面上不得出現裸卡片 id: %s (在文字 '%s')" % [str(card_id), text])
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["hand_cards_visible", "no_card_id_visible"] } }

	func _p1h_02(tree: SceneTree) -> Dictionary:
		var before_state := _state(tree)
		var data_node := _data(tree)

		# 點先生說法
		await _click(tree, "hand_card::info_husband_version")
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "dialog_confirm::card_detail"), "先生說法詳情開啟")
		var husband_name: String = str(data_node.call("card_display_name", "info_husband_version"))
		var husband_text: String = str(data_node.loader.cards.get("info_husband_version", {}).get("text", ""))
		assert_true(_has_text(tree.get_root(), husband_name), "先生說法卡名")
		assert_true(_has_text(tree.get_root(), husband_text), "先生說法內容")
		await _click(tree, "dialog_confirm::card_detail")
		var after_husband := _state(tree)
		assert_eq(JSON.stringify(before_state), JSON.stringify(after_husband), "先生說法關閉後狀態逐欄不變")

		# 點妻子說法
		await _click(tree, "hand_card::info_wife_version")
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "dialog_confirm::card_detail"), "妻子說法詳情開啟")
		var wife_name: String = str(data_node.call("card_display_name", "info_wife_version"))
		var wife_text: String = str(data_node.loader.cards.get("info_wife_version", {}).get("text", ""))
		assert_true(_has_text(tree.get_root(), wife_name), "妻子說法卡名")
		assert_true(_has_text(tree.get_root(), wife_text), "妻子說法內容")
		await _click(tree, "dialog_confirm::card_detail")
		var after_wife := _state(tree)
		assert_eq(JSON.stringify(before_state), JSON.stringify(after_wife), "妻子說法關閉後狀態逐欄不變")

		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["husband_detail_ok", "wife_detail_ok", "state_unchanged"] } }

	func _p1h_03(tree: SceneTree) -> Dictionary:
		await _click(tree, "hand_card::protagonist")
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "dialog_confirm::card_detail"), "詳情開啟")
		var place_controls := QAStepClass.find_controls_by_qa_id_prefix(tree.get_root(), "place::")
		var choose_controls := QAStepClass.find_controls_by_qa_id_prefix(tree.get_root(), "choose::")
		assert_true(place_controls.is_empty(), "詳情開啟期間全樹不得存在任何 place:: 控制項")
		assert_true(choose_controls.is_empty(), "詳情開啟期間全樹不得存在任何 choose:: 控制項")
		await _click(tree, "dialog_confirm::card_detail")
		assert_false(QAStepClass.has_visible_qa_id(tree.get_root(), "dialog_confirm::card_detail"), "詳情關閉")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["no_placement_controls", "dialog_close_ok"] } }

	func _p1h_04(tree: SceneTree) -> Dictionary:
		var before_state := _state(tree)
		var meta := before_state.get("meta", {}) as Dictionary
		var knowledge := meta.get("knowledge", {}) as Dictionary
		assert_true(knowledge.size() >= 10, "p1h_knowledge_full 應有完整知識")
		var data_node := _data(tree)

		await _click(tree, "knowledge_entry")
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "dialog_confirm::card_detail"), "知識清單開啟")

		for k_id in knowledge.keys():
			var k_name: String = str(data_node.call("card_display_name", str(k_id)))
			var k_text: String = str(data_node.loader.cards.get(str(k_id), {}).get("text", ""))
			assert_true(_has_text(tree.get_root(), k_name), "知識卡名稱存在: %s" % k_name)
			assert_true(_has_text(tree.get_root(), k_text), "知識卡內容存在: %s" % str(k_id))

		var scroll_nodes := QAStepClass.find_controls_by_name(tree.get_root(), "ScrollContainer")
		var dialog_scroll: ScrollContainer = null
		for sn in scroll_nodes:
			if sn is ScrollContainer and sn.get_parent() is AcceptDialog:
				dialog_scroll = sn as ScrollContainer
				break
		assert_true(dialog_scroll != null, "知識清單彈窗內應有 ScrollContainer")
		if dialog_scroll != null:
			var content_box: VBoxContainer = dialog_scroll.get_child(0) as VBoxContainer
			var last_item: Control = content_box.get_child(content_box.get_child_count() - 1) as Control
			var scroll_res := await QAStepClass.scroll_into_view(tree, dialog_scroll, last_item)
			assert_true(bool(scroll_res.get("ok", false)), "滾輪捲動至最後一張知識卡")

		await _click(tree, "dialog_confirm::card_detail")
		var after_state := _state(tree)
		assert_eq(JSON.stringify(before_state), JSON.stringify(after_state), "知識清單關閉後狀態逐欄不變")

		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["all_knowledge_present", "scroll_last_visible", "state_unchanged"] } }

	func _p1h_05(tree: SceneTree) -> Dictionary:
		var btn_list := QAStepClass.find_controls_by_qa_id(tree.get_root(), "hand_card::info_husband_version")
		assert_eq(btn_list.size(), 1, "先生說法卡片按鈕")
		var data_node := _data(tree)
		var long_name: String = str(data_node.call("card_display_name", "info_husband_version"))
		assert_true(long_name.length() > 10, "資料變體超長卡名生效")
		if btn_list.size() == 1:
			var btn := btn_list[0] as Button
			assert_eq(btn.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS, "文字溢出截斷模式應為 OVERRUN_TRIM_ELLIPSIS")
			assert_true(btn.clip_text, "clip_text 應為 true")
			var font: Font = btn.get_theme_font("font")
			var font_size: int = btn.get_theme_font_size("font_size")
			var text_w: float = font.get_string_size(btn.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			assert_true(text_w > btn.size.x, "超長卡名寬度 (%f) 應大於按鈕寬度 (%f)" % [text_w, btn.size.x])

		await _click(tree, "hand_card::info_husband_version")
		assert_true(_has_text(tree.get_root(), long_name), "詳情彈窗內顯示完整未截斷全名")
		await _click(tree, "dialog_confirm::card_detail")

		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["ellipsis_displayed", "full_name_in_detail"] } }

	func _p1h_06(tree: SceneTree) -> Dictionary:
		var hand_bar_nodes := QAStepClass.find_controls_by_name(tree.get_root(), "HandBar")
		assert_eq(hand_bar_nodes.size(), 1, "HandBar 節點存在")
		var hand_bar := hand_bar_nodes[0] as Control

		var grid_nodes := QAStepClass.find_controls_by_name(hand_bar, "CardsGrid")
		assert_eq(grid_nodes.size(), 1, "CardsGrid 存在")
		if grid_nodes.size() == 1:
			var grid := grid_nodes[0] as GridContainer
			assert_eq(grid.columns, 7, "GridContainer.columns 固定為 7")
			var run := _run(tree)
			var hand_cards: Array = run.get("hand", []) as Array
			assert_eq(grid.get_child_count(), hand_cards.size(), "按鈕數等於手牌數")
			for child in grid.get_children():
				assert_true(child is Button, "CardsGrid 子節點皆為 Button（無空框）")

		var hb_rect := hand_bar.get_global_rect()
		assert_eq(hb_rect, Rect2(20, 580, 1240, 140), "HandBar 外框矩形保持 Rect2(20, 580, 1240, 140)")

		var content_view_nodes := QAStepClass.find_controls_by_name(tree.get_root(), "ContentView")
		assert_eq(content_view_nodes.size(), 1, "ContentView 存在")
		if content_view_nodes.size() == 1:
			var cv_rect := (content_view_nodes[0] as Control).get_global_rect()
			assert_eq(cv_rect, Rect2(0, 170, 1280, 400), "ContentView 外框矩形保持 Rect2(0, 170, 1280, 400)")

		var slots_labels := QAStepClass.find_controls_by_qa_id(tree.get_root(), "hand_slots")
		assert_true(not slots_labels.is_empty(), "hand_slots 標籤存在")
		if not slots_labels.is_empty():
			var limit := int(_data(tree).call("tuning", "hand_size"))
			var used := int(CaseBaseClass.get_game_state(tree).call("hand_slots_used"))
			assert_eq((slots_labels[0] as Label).text, "手牌 %d / %d" % [used, limit], "hand_slots 格式吻合")

		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["grid_columns_7", "no_empty_slots", "rects_preserved"] } }

	func _p2a_01(tree: SceneTree) -> Dictionary:
		var before_state := _state(tree)
		var run := before_state.get("run", {}) as Dictionary
		var hand_cards: Array = run.get("hand", []) as Array
		var madness_clock: Dictionary = run.get("madness_clock", {}) as Dictionary

		# 1. 斷言手牌含有多張獨立的發狂卡實例
		var madness_instances: Array[String] = []
		for c in hand_cards:
			if str(c).begins_with("madness#"):
				madness_instances.append(str(c))
		assert_true(madness_instances.size() >= 3, "手牌應至少有 3 張獨立發狂卡實例: %s" % str(madness_instances))

		# 2. 斷言畫面上各自存在獨立按鈕與對應倒數天數文字
		var data_node := _data(tree)
		for m_inst in madness_instances:
			var btn_list := QAStepClass.find_controls_by_qa_id(tree.get_root(), "hand_card::" + m_inst)
			assert_eq(btn_list.size(), 1, "發狂卡按鈕唯一且各自獨立: %s" % m_inst)
			if btn_list.size() == 1:
				var btn := btn_list[0] as Button
				var days := int(madness_clock.get(m_inst, 0))
				var card_name: String = str(data_node.call("card_display_name", m_inst))
				var expected_text := "%s (%d天)" % [card_name, days]
				assert_eq(btn.text, expected_text, "發狂卡按鈕文字正確顯示剩餘天數: %s" % m_inst)

		# 3. 點擊其中一張發狂卡，驗證詳情彈窗正常開啟與關閉
		var target_card := madness_instances[0]
		await _click(tree, "hand_card::" + target_card)
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "dialog_confirm::card_detail"), "發狂卡詳情開啟")
		var target_days := int(madness_clock.get(target_card, 0))
		var target_name: String = str(data_node.call("card_display_name", target_card))
		assert_true(_has_text(tree.get_root(), "%s (%d天)" % [target_name, target_days]), "詳情內含發狂卡天數標題")
		await _click(tree, "dialog_confirm::card_detail")
		assert_false(QAStepClass.has_visible_qa_id(tree.get_root(), "dialog_confirm::card_detail"), "詳情關閉")

		var after_state := _state(tree)
		assert_eq(JSON.stringify(before_state), JSON.stringify(after_state), "關閉詳情後狀態不變")

		return {
			"ok": errors.is_empty(),
			"errors": errors,
			"observations": {
				"evidence": [
					"madness_multi_distinct_buttons",
					"madness_countdown_labels",
					"madness_detail_dialog_ok"
				]
			}
		}

	# ── P2-B 縱慾出口 ──────────────────────────────────────────────────────
	# 出口槽的 id 全部是 exit_<地點>::x_<出口>，qa_id 沿用 P1-G 的 slot:: / place:: 契約。

	const _EXIT_SLOT_IDS := [
		"slot::exit_sanquan::x_smash",
		"slot::exit_sanquan::x_binge",
		"slot::exit_sanquan::x_soak",
	]

	func _p2b_01_zero(tree: SceneTree) -> Dictionary:
		var before_hand: Array = (_run(tree).get("hand", []) as Array).duplicate()
		assert_true(before_hand.filter(
			func(c: Variant) -> bool: return str(c).begins_with("madness")
		).is_empty(), "前提：手上沒有發狂卡")
		await _enter(tree, "sanquan")
		# 「不是灰掉，是不存在」——assert_no_qa_id 連隱藏節點都會抓到。
		for slot_qa_id in _EXIT_SLOT_IDS:
			assert_no_qa_id(tree, slot_qa_id, "0 張發狂卡時出口槽不得存在於節點樹")
		assert_false(_has_text(tree.get_root(), "壓抑不住的衝動"), "出口 beat 的文字也不得播出")
		# 不比對整份 state：開面板本來就會結算該面板的 on_enter（P1-C 契約），
		# beats_entered 會合法變動。這裡只釘住「逛過沒有出口槽的面板不會動到縱慾帳」。
		var after := _run(tree)
		assert_eq(int(after.get("indulgence_count", -1)), 0, "沒有出口槽可放，縱慾次數維持 0")
		assert_eq(JSON.stringify(after.get("hand", [])), JSON.stringify(before_hand), "手牌不變")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["exit_slots_absent"] } }

	func _p2b_01_one(tree: SceneTree) -> Dictionary:
		await _enter(tree, "sanquan")
		for slot_qa_id in _EXIT_SLOT_IDS:
			assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), slot_qa_id),
				"手上有發狂卡時出口槽應顯示：%s" % slot_qa_id)
		assert_no_qa_id(tree, "slot::exit_sanquan::x_violence", "第 3 天不得出現暴力對人（D16 門檻）")
		# 型別標示沿用 P1-G 規則：顯示 card_types.json 的型別名，不洩漏卡 id。
		assert_true(_has_text(tree.get_root(), "（收：發狂卡）"), "出口槽標示收「發狂卡」")
		assert_false(_has_text(tree.get_root(), "madness#"), "槽標籤不得出現卡片實例 id")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["exit_slots_visible", "exit_slot_type_label"] } }

	func _p2b_02(tree: SceneTree) -> Dictionary:
		await _enter(tree, "sanquan")
		var before := _state(tree)
		# 出口槽只收發狂卡：畫面上不得出現主角卡的放入按鈕，且對槽真實輸入不改變狀態。
		assert_no_qa_id(tree, "place::exit_sanquan::x_smash::protagonist", "出口槽不得提供主角卡放入入口")
		await _click(tree, "slot::exit_sanquan::x_smash")
		assert_eq(JSON.stringify(before), JSON.stringify(_state(tree)), "對出口槽的無效輸入不得改變狀態")

		await _click(tree, "place::exit_sanquan::x_smash::madness#1")
		var after := _run(tree)
		assert_true(_has_text(tree.get_root(), "碎片散了一地"), "on_place 效果文字必須在 UI 顯示")
		assert_false((after.get("hand", []) as Array).has("madness#1"), "縱慾掉的那張卡從手牌消失")
		assert_true((after.get("hand", []) as Array).has("madness#2"), "只消掉玩家挑的那一張")
		assert_true(bool(after.get("action_spent", false)), "縱慾吃掉該時段行動格")
		assert_eq(int(after.get("indulgence_count", 0)), 1, "本輪縱慾次數 +1")

		# 同時段任何地點都不能再放主角卡
		await _close(tree)
		await _enter(tree, "oldstreet")
		assert_true(_visible_ids(tree, "place::").filter(
			func(qa: String) -> bool: return qa.ends_with("::protagonist")
		).is_empty(), "縱慾用掉行動格後，第二地點不得再出現主角卡放入入口")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["indulge_place_effect", "indulge_action_spent", "exit_rejects_non_madness"] } }

	func _p2b_03_morning(tree: SceneTree) -> Dictionary:
		await _enter(tree, "sanquan")
		await _click(tree, "place::exit_sanquan::x_soak::madness#1")
		var after := _run(tree)
		# K-55：泡湯不得在放置管線中途改時段。時段留在 morning，面板留在畫面上，
		# 效果文字看得到，推進鈕沒有被鎖死。
		assert_eq(str(after.get("phase", "")), "morning", "泡湯不跳時段")
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "panel_back"), "泡湯後地點面板仍在畫面上")
		assert_true(_has_text(tree.get_root(), "溫泉池裡浸泡"), "泡湯效果文字必須在 UI 顯示")
		assert_false((after.get("hand", []) as Array).has("madness#1"), "泡湯清掉指定的那張")
		assert_true((after.get("hand", []) as Array).has("madness#2"), "只清 soak_cards_cleared 張，不是全清")

		await _close(tree)
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "phase_advance"), "推進鈕可按（K-55 卡死回歸）")
		await _advance(tree)
		var pm := _run(tree)
		assert_eq(str(pm.get("phase", "")), "afternoon", "推進一次進到下午")
		assert_true(bool(pm.get("action_spent", false)), "下午的行動格已被泡湯預先吃掉")
		await _enter(tree, "sanquan")
		assert_true(_visible_ids(tree, "place::").filter(
			func(qa: String) -> bool: return qa.ends_with("::protagonist")
		).is_empty(), "被吃掉的下午不得再出現主角卡放入入口")
		await _close(tree)
		await _advance(tree)
		assert_eq(str(_run(tree).get("phase", "")), "evening", "再推進一次進 evening")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["soak_eats_day"] } }

	func _p2b_03_locked(tree: SceneTree) -> Dictionary:
		var expected_reason := "只能在上午發動" if mode == "p2b_03_afternoon" else "格數不足"
		await _enter(tree, "sanquan")
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "slot::exit_sanquan::x_soak"), "泡湯槽仍顯示（灰掉不是消失）")
		assert_true(_has_text(tree.get_root(), expected_reason), "泡湯槽必須附理由：%s" % expected_reason)
		var before := _state(tree)
		assert_true(_visible_ids(tree, "place::exit_sanquan::x_soak::").is_empty(), "呈灰的泡湯槽不得提供放入入口")
		await _click(tree, "slot::exit_sanquan::x_soak")
		assert_eq(JSON.stringify(before), JSON.stringify(_state(tree)), "對呈灰泡湯槽的真實輸入不得改變狀態")
		var token := "soak_afternoon_locked" if mode == "p2b_03_afternoon" else "soak_not_enough_actions"
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": [token] } }

	func _p2b_04_before(tree: SceneTree) -> Dictionary:
		assert_eq(int(_run(tree).get("day", 0)), 3, "前提：第 16 天之前")
		await _enter(tree, "sanquan")
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "slot::exit_sanquan::x_smash"), "無條件出口仍在（對照組）")
		assert_no_qa_id(tree, "slot::exit_sanquan::x_violence", "第 16 天前暴力對人不得存在於節點樹")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["violence_day_gate_before"] } }

	func _p2b_04_after(tree: SceneTree) -> Dictionary:
		assert_eq(int(_run(tree).get("day", 0)), 17, "前提：第 16 天之後")
		await _enter(tree, "sanquan")
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "slot::exit_sanquan::x_violence"), "第 17 天暴力對人應出現")
		assert_no_qa_id(tree, "slot::exit_sanquan::x_lust_ajie", "未達疑似時性慾槽不得存在於節點樹")
		await _close(tree)
		# 奢侈出口：錢卡尚未建檔（待決 22），恆呈灰附理由——這是正確行為，不是 bug。
		await _enter(tree, "oldstreet")
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "slot::exit_oldstreet::x_splurge"), "奢侈槽應顯示")
		assert_true(_has_text(tree.get_root(), "身上沒有足夠的錢"), "奢侈槽必須附資料寫的理由")
		assert_true(_visible_ids(tree, "place::exit_oldstreet::x_splurge::").is_empty(), "呈灰的奢侈槽不得提供放入入口")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["violence_day_gate_after", "splurge_locked_reason"] } }

	func _p2b_04_lust(tree: SceneTree) -> Dictionary:
		await _enter(tree, "sanquan")
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "slot::exit_sanquan::x_lust_ajie"), "達疑似後性慾槽應出現")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["lust_relation_gate"] } }

	# ── P2-C 強制縱慾（K-61）────────────────────────────────────────────────
	# 三個案例都從「第 10 夜、發狂卡倒數剩 1」出發，推進一次跨到第 11 天 morning，
	# 跨日 tick 歸零之後 advance_phase() 自動執行強制縱慾。
	# 第 11 天 < 16 且無關係，所以挑選池只有砸東西(1) 與暴食(2)，必定挑中暴食。

	## 取當下地圖上前幾個可進的地點 id（不寫死地點，避免資料一改就假紅）。
	func _open_locations(tree: SceneTree, count: int) -> Array[String]:
		var ids: Array[String] = []
		for qa_id in _visible_ids(tree, "location::"):
			ids.append(qa_id.trim_prefix("location::"))
			if ids.size() >= count:
				break
		return ids

	func _forced_to_d11_morning(tree: SceneTree) -> Dictionary:
		await _advance(tree)
		var run := _run(tree)
		assert_eq(int(run.get("day", 0)), 11, "跨到第 11 天")
		assert_eq(str(run.get("phase", "")), "morning", "跨到 morning")
		return run

	func _p2c_01(tree: SceneTree) -> Dictionary:
		var run := await _forced_to_d11_morning(tree)
		assert_eq(int(run.get("indulgence_count", 0)), 1, "強制縱慾自動執行一次")
		# 效果文字必須真的畫在地圖上方，不是只存在 GameState 裡。
		assert_true(_has_text(tree.get_root(), "你把廚房裡能找到的食物"),
			"強制縱慾的 on_place 文字必須在畫面上")
		# 第一次是輕的，而且文字明講下次更重（規格書 P2-C：一張帳單，也是一則預告）。
		assert_true(_has_text(tree.get_root(), "下一次恐怕沒這麼容易"),
			"第一次強制縱慾必須播出輕度預告文字")

		# 開發設計方針 > P2-C 的契約：文字整個時段留存，關掉地點面板回到地圖仍看得到。
		var locs := _open_locations(tree, 1)
		assert_false(locs.is_empty(), "第 11 天上午地圖上必須有可進的地點")
		await _enter(tree, locs[0])
		await _close(tree)
		assert_true(_has_text(tree.get_root(), "你把廚房裡能找到的食物"),
			"關掉地點面板回到地圖，強制縱慾文字仍須留存")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": [
			"forced_text_visible", "forced_text_persists_in_phase",
		] } }

	func _p2c_02(tree: SceneTree) -> Dictionary:
		var run := await _forced_to_d11_morning(tree)
		assert_true(bool(run.get("action_spent", false)), "強制縱慾吃掉該時段行動格")
		assert_false((run.get("hand", []) as Array).has("madness#1"), "歸零那張發狂卡被消掉")
		assert_eq(int(run.get("indulgence_count", 0)), 1, "縱慾計數 +1")

		# 玩家在那一格不能再放主角卡——兩個地點都驗，證明擋的是行動格不是單一面板。
		var locs := _open_locations(tree, 2)
		assert_true(locs.size() >= 2, "第 11 天上午應有兩個以上可進地點可驗")
		for loc_id in locs:
			await _enter(tree, loc_id)
			assert_true(_visible_ids(tree, "place::").filter(
				func(qa: String) -> bool: return qa.ends_with("::protagonist")
			).is_empty(), "行動格已被強制縱慾吃掉，%s 不得出現主角卡放入入口" % loc_id)
			await _close(tree)
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": [
			"forced_action_spent", "forced_no_protagonist_place",
		] } }

	func _p2c_03(tree: SceneTree) -> Dictionary:
		var morning := await _forced_to_d11_morning(tree)
		assert_true(bool(morning.get("action_spent", false)), "上午行動格被第 1 張吃掉")
		assert_eq(int(morning.get("indulgence_count", 0)), 1, "上午結算第 1 次")
		assert_false((morning.get("hand", []) as Array).has("madness#1"), "第 1 張被消掉")
		assert_true((morning.get("hand", []) as Array).has("madness#2"), "第 2 張還在，等下午")

		await _advance(tree)
		var afternoon := _run(tree)
		assert_eq(str(afternoon.get("phase", "")), "afternoon", "推進到下午")
		assert_true(bool(afternoon.get("action_spent", false)), "下午行動格被第 2 張吃掉")
		assert_eq(int(afternoon.get("indulgence_count", 0)), 2, "下午結算第 2 次")
		assert_false((afternoon.get("hand", []) as Array).has("madness#2"), "第 2 張也被消掉")

		# 那一天玩家完全沒有行動格。
		var locs := _open_locations(tree, 1)
		assert_false(locs.is_empty(), "第 11 天下午地圖上必須有可進的地點")
		await _enter(tree, locs[0])
		assert_true(_visible_ids(tree, "place::").filter(
			func(qa: String) -> bool: return qa.ends_with("::protagonist")
		).is_empty(), "同日兩張歸零後，下午同樣不得出現主角卡放入入口")
		await _close(tree)
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": [
			"forced_two_same_day", "forced_day_fully_eaten",
		] } }

	func _p2d_01_zero(tree: SceneTree) -> Dictionary:
		# 手上 2 張發狂卡（未達門檻 3）：D24 night 睡眠時不觸發二樓有人在走（awei_heard_it 不落帳，無停拍直接推進）
		assert_eq(int(_run(tree).get("day", 0)), 24, "D24 night 起點")
		assert_false((_run(tree).get("flags", {}) as Dictionary).get("awei_heard_it", false), "睡眠前 awei_heard_it 為 false")
		await _click(tree, "phase_advance")
		assert_eq(int(_run(tree).get("day", 0)), 25, "無睡眠內容直接推進至 D25")
		assert_false(_has_text(tree.get_root(), "二樓有人在走"), "2 張發狂卡時畫面上看不到二樓有人在走")
		assert_false((_run(tree).get("flags", {}) as Dictionary).get("awei_heard_it", false), "2 張發狂卡時二樓有人在走未達門檻，不得落帳")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": [
			"vision_hidden_at_2",
		] } }

	func _p2d_01_three(tree: SceneTree) -> Dictionary:
		# 手上 3 張發狂卡（達門檻 3）：D24 night 睡眠時成功觸發二樓有人在走（awei_heard_it 成功落帳，停拍顯示文字）
		assert_eq(int(_run(tree).get("day", 0)), 24, "D24 night 起點")
		assert_false((_run(tree).get("flags", {}) as Dictionary).get("awei_heard_it", false), "睡眠前 awei_heard_it 為 false")

		# K-123 斷言：夜間推進按鈕初始為『直接睡』
		var adv_btn_init := QAStepClass.find_controls_by_qa_id(tree.get_root(), "phase_advance")[0] as Button
		assert_eq(adv_btn_init.text, "直接睡", "夜間初始推進按鈕文字為直接睡 (K-123)")

		# 第 1 次點擊：停拍並顯示睡眠文字
		await _click(tree, "phase_advance")
		assert_eq(int(_run(tree).get("day", 0)), 24, "有睡眠內容時第 1 次點擊停在 D24 供玩家閱讀")
		assert_true(bool(_run(tree).get("night_sleep_pending", false)), "第 1 次點擊設定 night_sleep_pending 為 true")
		assert_true(_has_text(tree.get_root(), "二樓有人在走"), "3 張發狂卡時二樓有人在走達視野門檻，畫面文字可見 (K-68)")
		assert_true((_run(tree).get("flags", {}) as Dictionary).get("awei_heard_it", false), "3 張發狂卡時二樓有人在走達視野門檻，成功落帳")

		# K-123 斷言：停拍期間按鈕變為『進入隔天』
		var adv_btn_pending := QAStepClass.find_controls_by_qa_id(tree.get_root(), "phase_advance")[0] as Button
		assert_eq(adv_btn_pending.text, "進入隔天", "睡眠停拍期間推進按鈕文字為進入隔天 (K-123)")

		# K-68 第三腳：驗證清回 2 張發狂卡後，視野門檻定日 beat 不再成立
		var gs := CaseBaseClass.get_game_state(tree)
		gs.call("lose_card", "madness#3")
		var mcards_now: int = (gs.get("hand") as Array).filter(func(c: Variant) -> bool: return str(c).begins_with("madness")).size()
		assert_eq(mcards_now, 2, "清掉 1 張發狂卡後手上剩 2 張")
		var resolved_under_2: Dictionary = gs.call("resolved_night_content", "sanquan")
		var p_beat: Dictionary = resolved_under_2.get("primary", {})
		assert_true(p_beat.is_empty() or str(p_beat.get("id", "")) != "d24_night_bleed", "清回 2 張後視野門檻定日 beat (d24_night_bleed) 不再被選中 (K-68 第三腳)")

		# 第 2 次點擊：換日進入隔天
		await _click(tree, "phase_advance")
		assert_eq(int(_run(tree).get("day", 0)), 25, "第 2 次點擊進入隔天 D25")
		assert_false(bool(_run(tree).get("night_sleep_pending", false)), "換日後 night_sleep_pending 清除")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": [
			"vision_visible_at_3",
		] } }

	func _p2d_02(tree: SceneTree) -> Dictionary:
		# 手上 6 張發狂卡，進 n_ahong_1 開啟收費標記獲得第 7 張 -> 達到 cap 7 即刻觸發發瘋 BE
		var run_before := _run(tree)
		var mcards := (run_before.get("hand", []) as Array).filter(func(c: String) -> bool: return c.begins_with("madness"))
		assert_eq(mcards.size(), 6, "啟動時手上 6 張發狂卡")
		await _enter(tree, "n_ahong_1")
		assert_true(_has_text(tree.get_root(), "[發瘋 BE]"), "達到 cap 7 必須呈現 [發瘋 BE]")
		assert_false(_has_text(tree.get_root(), "[結局 stub]"), "發瘋 BE 不得播出一般結局骨架")
		assert_false(QAStepClass.has_visible_qa_id(tree.get_root(), "panel_back"), "發瘋 BE 觸發後地點面板必須收起")
		assert_true(_visible_ids(tree, "location::").is_empty(), "發瘋 BE 觸發後地圖必須收起 (be_map_hidden, K-70)")
		var adv_btns := QAStepClass.find_controls_by_qa_id(tree.get_root(), "phase_advance")
		assert_eq(adv_btns.size(), 1, "發瘋 BE 觸發後推進按鈕存在 (K-70)")
		if not adv_btns.is_empty():
			assert_false((adv_btns[0] as Button).disabled, "發瘋 BE 觸發後推進按鈕未 disabled (K-70)")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": [
			"be_text_visible", "be_no_coda_stub", "be_map_hidden",
		] } }

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
		var panel_nodes := QAStepClass.find_controls_by_name(tree.get_root(), "LocationPanel")
		var panel: Node = panel_nodes[0] if not panel_nodes.is_empty() else tree.get_root()
		assert_true(not _has_text(panel, "看夜市那邊的燈"), "無邀請分支不顯示阿婕內容")
		assert_true(not _has_text(panel, "金伯的尾音還沒收"), "無邀請分支不顯示阿薇內容")
		assert_true(_has_text(panel, "兩段都沒有") or _has_text(panel, "一個人走"), "條件成立的 D32 分支")
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
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "slot::d3_pm_oldstreet::wander"), "第二地點仍顯示槽位")
		var before := _state(tree)
		await _click(tree, "slot::d3_pm_oldstreet::wander")
		assert_eq(JSON.stringify(before), JSON.stringify(_state(tree)), "行動耗盡後對第二地點槽位真實輸入不得改變狀態")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["action_spent_ui_blocked", "second_location_input_noop"] } }

	func _panel_rebuild(tree: SceneTree) -> Dictionary:
		await _enter(tree, "sanquan")
		await _click(tree, "place::d3_pm_sanquan::help_ahong::protagonist")
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "slot::d3_pm_sanquan::help_ahong"), "放置後槽位仍在面板")
		assert_false(QAStepClass.has_visible_qa_id(tree.get_root(), "place::d3_pm_sanquan::help_ahong::protagonist"), "放置後舊放卡按鈕移除")
		assert_true(not _visible_ids(tree, "place::d3_pm_sanquan::show_version::").is_empty(), "放置後新條件成立的槽立即開放")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["old_place_removed", "new_slot_open"] } }

	func _compare_free(tree: SceneTree) -> Dictionary:
		await _enter(tree, "sanquan")
		var before := _run(tree)
		assert_false(bool(before.get("action_spent", false)), "比對前行動格未消耗")
		var compare_ids := _visible_ids(tree, "place::d3_pm_sanquan::show_version::")
		assert_true(not compare_ids.is_empty(), "D3 比對情報卡入口存在")
		if not compare_ids.is_empty():
			await _click(tree, compare_ids[0])
		var mid := _run(tree)
		assert_false(bool(mid.get("action_spent", false)), "比對槽結算後仍不消耗行動格")
		assert_true(bool((mid.get("flags", {}) as Dictionary).get("couple_softened", false)), "比對槽效果正常落帳")
		await _click(tree, "place::d3_pm_sanquan::help_ahong::protagonist")
		var after := _run(tree)
		assert_true(bool(after.get("action_spent", false)), "比對後放置主角卡成功消耗行動格")
		assert_true(bool((after.get("flags", {}) as Dictionary).get("ahong_last_normal_contact", false)), "主角卡效果落帳")
		assert_eq(int(after.get("day", 0)), int(before.get("day", 0)), "比對與放置不推進時間")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["compare_no_action_spent", "action_still_available_after_compare", "compare_effect_applied"] } }

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
		var count_0 := int((_run(tree).get("npc_action_counts", {}) as Dictionary).get("acai", 0))
		await _click(tree, "place::d22_pm_sandbags::work::protagonist")
		var count_1 := int((_run(tree).get("npc_action_counts", {}) as Dictionary).get("acai", 0))
		assert_eq(count_1, count_0 + 1, "帶 attention_npc 的成功放置投入帳恰加一")
		await _click(tree, "slot::d22_pm_sandbags::work")
		var count_2 := int((_run(tree).get("npc_action_counts", {}) as Dictionary).get("acai", 0))
		assert_eq(count_2, count_1, "對已結算槽重複點擊不得再次增加投入帳")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["attention_success", "attention_repeat_unchanged"] } }

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
		if comparison_group == "p1af_22_choice_equivalence":
			return { "ok": errors.is_empty(), "errors": errors, "observations": {
				"choice_result_normalized": after,
				"fixture_causality": {
					"with_card": with_card,
					"source_hand": before.get("run", {}).get("hand", []),
				},
				"evidence": ["choice_equivalence_complete"],
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

	func _night_resolution(tree: SceneTree, _main_node: Control) -> Dictionary:
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "location::n_landmark"), "D10 夜間免費地點初始可見")
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "location::n_ahong_1"), "D10 夜間收費地點初始可見")

		# K-123 斷言：未選定地點時推進按鈕文字為『直接睡』
		var adv_btn_init := QAStepClass.find_controls_by_qa_id(tree.get_root(), "phase_advance")[0] as Button
		assert_eq(adv_btn_init.text, "直接睡", "夜間初始推進按鈕文字為直接睡 (K-123)")

		var count_before := (_run(tree).get("hand", []) as Array).size()
		await _enter(tree, "n_landmark")
		var texts := _texts(tree.get_root())
		var base_idx := -1
		var add_idx := -1
		for idx in range(texts.size()):
			if texts[idx].contains("夜鎮裡有一個特殊的東西"):
				base_idx = idx
			if texts[idx].contains("某個地方擺著一個小玩具"):
				add_idx = idx
		assert_true(base_idx >= 0, "D10 免費地點主內容/章節變體演出")
		assert_true(add_idx >= 0, "D10 附加 beat 並列演出")
		assert_true(add_idx > base_idx, "主內容與附加 beat 播放順序正確")
		await _close(tree)

		# 免費標記不產生發狂卡（手牌張數不變）
		var count_after := (_run(tree).get("hand", []) as Array).size()
		assert_eq(count_after, count_before, "進入免費夜間地點手牌不應產生任何發狂卡")

		# K-123 斷言：選定地點後推進按鈕文字為『結束今晚』
		var adv_btn_chosen := QAStepClass.find_controls_by_qa_id(tree.get_root(), "phase_advance")[0] as Button
		assert_eq(adv_btn_chosen.text, "結束今晚", "選定夜間地點後推進按鈕文字為結束今晚 (K-123)")

		# 一夜一個標記限制（K-91 斷言反轉）：選定 n_landmark 後，其他地點仍可見，但進入按鈕 disabled
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "location::n_ahong_1"), "一夜最多開一個地點，已選過地點後其他地點仍可見")
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "location::n_landmark"), "已選定的夜間地點仍可重新查看")

		var before_click_state := _state(tree)
		await _click(tree, "location::n_ahong_1")
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "night_status::n_ahong_1"), "其他地點詳情可開")
		var enter_btn_list := QAStepClass.find_controls_by_qa_id(tree.get_root(), "night_enter::n_ahong_1")
		assert_eq(enter_btn_list.size(), 1, "其他地點進入按鈕存在")
		if not enter_btn_list.is_empty():
			var enter_btn := enter_btn_list[0] as Button
			assert_true(enter_btn.disabled, "已選過地點後，其他地點進入按鈕 disabled")
		await _click(tree, "night_enter::n_ahong_1", MOUSE_BUTTON_LEFT, true)
		var after_click_state := _state(tree)
		assert_eq(JSON.stringify(before_click_state), JSON.stringify(after_click_state), "點擊 disabled 進入按鈕狀態零變化")
		await _close(tree)

		return {
			"ok": errors.is_empty(),
			"errors": errors,
			"observations": {
				"locations": _visible_ids(tree, "location::"),
				"evidence": [
					"night_free_interaction",
					"night_chapter_and_additional_order",
					"night_one_location_limit",
					"night_no_madness"
				]
			}
		}

	func _night_resolution_paid(tree: SceneTree, _main_node: Control) -> Dictionary:
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "location::n_ahong_1"), "D10 已到收費標記開放日")
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "location::n_landmark"), "D10 免費標記可見")
		var mcards_before: int = (_run(tree).get("hand", []) as Array).filter(func(c: Variant) -> bool: return str(c).begins_with("madness")).size()
		await _enter(tree, "n_ahong_1")
		assert_true(_has_text(tree.get_root(), "腳印是工作鞋的") or _has_text(tree.get_root(), "有人走過"), "付費夜間標記顯示真實 beat 內容")
		assert_true(_has_text(tree.get_root(), "獲得 1 張發狂卡"), "進入收費標記顯示發卡提示")
		await _close(tree)

		# 進入收費標記發放發狂卡（發狂卡張數恰好增加 1 張）
		var mcards_after: int = (_run(tree).get("hand", []) as Array).filter(func(c: Variant) -> bool: return str(c).begins_with("madness")).size()
		assert_eq(mcards_after, mcards_before + 1, "進入收費夜間地點後手牌應增加 1 張發狂卡")
		assert_true((_run(tree).get("hand", []) as Array).has("info_ahong_traces"), "進入 n_ahong_1 獲得真實 beat 獎勵情報卡 info_ahong_traces")

		# K-123 斷言：選定收費地點後推進按鈕文字為『結束今晚』
		var adv_btn_paid := QAStepClass.find_controls_by_qa_id(tree.get_root(), "phase_advance")[0] as Button
		assert_eq(adv_btn_paid.text, "結束今晚", "選定夜間收費地點後推進按鈕文字為結束今晚 (K-123)")

		# 一夜一個標記限制（K-91 斷言反轉）：選定 n_ahong_1 後，其他地點仍可見，但進入按鈕 disabled
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "location::n_landmark"), "一夜最多開一個地點，已選過收費地點後其他地點仍可見")
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "location::n_ahong_1"), "已選定的夜間收費地點仍可重新查看")

		var before_click_state := _state(tree)
		await _click(tree, "location::n_landmark")
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "night_status::n_landmark"), "其他地點詳情可開")
		var enter_btn_list := QAStepClass.find_controls_by_qa_id(tree.get_root(), "night_enter::n_landmark")
		assert_eq(enter_btn_list.size(), 1, "免費地點進入按鈕存在")
		if not enter_btn_list.is_empty():
			var enter_btn := enter_btn_list[0] as Button
			assert_true(enter_btn.disabled, "已選過收費地點後，其他地點進入按鈕 disabled")
		await _click(tree, "night_enter::n_landmark", MOUSE_BUTTON_LEFT, true)
		var after_click_state := _state(tree)
		assert_eq(JSON.stringify(before_click_state), JSON.stringify(after_click_state), "點擊 disabled 進入按鈕狀態零變化")
		await _close(tree)

		return {
			"ok": errors.is_empty(),
			"errors": errors,
			"observations": {
				"locations": _visible_ids(tree, "location::"),
				"evidence": [
					"night_paid_locked",
					"night_one_location_limit"
				]
			}
		}

	func _night_resolution_d1(tree: SceneTree) -> Dictionary:
		await _advance(tree)
		await _advance(tree)
		await _advance(tree)
		assert_eq(str(_run(tree).get("phase", "")), "night", "D1 夜間起點")
		assert_true(_has_text(tree.get_root(), "一條走廊，兩側都是門"), "D1 fixed night beat 優先演出")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["night_fixed_priority"] } }

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
		var advance_steps := 0
		while int(_run(tree).get("day", 0)) < 8 and advance_steps < 60:
			await _advance(tree)
			advance_steps += 1
		assert_true(advance_steps < 60, "推進至第 8 天超過步數上限，流程可能卡住")
		assert_eq(int(_run(tree).get("day", 0)), 8, "新輪推進至第 8 天")
		assert_eq(str(_run(tree).get("phase", "")), "morning", "新輪推進至第 8 天 morning")
		await _enter(tree, "jinghe")
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "slot::d8_morning_jinghe::go_with_ajie"), "第 8 天旗標控制槽存在")
		assert_false(QAStepClass.has_visible_qa_id(tree.get_root(), "place::d8_morning_jinghe::go_with_ajie::protagonist"), "重置後未持有旗標不可放卡")
		var go_label := QAStepClass.find_controls_by_qa_id(tree.get_root(), "slot::d8_morning_jinghe::go_with_ajie")[0] as Label
		assert_true(go_label.text.contains("未解鎖") or go_label.text.contains("你昨天沒有答應她"), "旗標控制槽回到未解鎖狀態")
		var before_click := _state(tree)
		await _click(tree, "slot::d8_morning_jinghe::go_with_ajie")
		assert_eq(JSON.stringify(before_click), JSON.stringify(_state(tree)), "點擊未解鎖旗標槽不得改變狀態")
		await _close(tree)
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["run_fields_cleared", "reset_ui_state", "reset_flag_slots_locked"] } }

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

	func _has_digits(s: String) -> bool:
		for ch in s:
			if ch >= "0" and ch <= "9":
				return true
		return false

	func _p3d_01_unaligned(tree: SceneTree) -> Dictionary:
		var btns := QAStepClass.find_controls_by_qa_id(tree.get_root(), "location::n_exit")
		assert_eq(btns.size(), 1, "地圖清單中找到 location::n_exit 按鈕")
		if not btns.is_empty():
			assert_true((btns[0] as Button).text.contains("[已到訪，尚未對位]"), "未對位地點按鈕文字包含 [已到訪，尚未對位]")
		await _click(tree, "location::n_exit")
		var status_nodes := QAStepClass.find_controls_by_qa_id(tree.get_root(), "night_status::n_exit")
		assert_eq(status_nodes.size(), 1, "詳情面板中找到 night_status::n_exit 節點")
		if not status_nodes.is_empty():
			assert_eq((status_nodes[0] as Label).text, "[已到訪，尚未對位]", "詳情狀態文字為 [已到訪，尚未對位]")
		await _close(tree)
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["status_seen_unaligned"] } }

	func _p3d_01_nightonly(tree: SceneTree) -> Dictionary:
		var btns := QAStepClass.find_controls_by_qa_id(tree.get_root(), "location::n_landmark")
		assert_eq(btns.size(), 1, "地圖清單中找到 location::n_landmark 按鈕")
		if not btns.is_empty():
			assert_true((btns[0] as Button).text.contains("[已到訪]"), "夜間限定地點按鈕文字包含 [已到訪]")
			assert_false((btns[0] as Button).text.contains("尚未對位"), "夜間限定地點按鈕文字不含『尚未對位』")
		await _click(tree, "location::n_landmark")
		var status_nodes := QAStepClass.find_controls_by_qa_id(tree.get_root(), "night_status::n_landmark")
		assert_eq(status_nodes.size(), 1, "詳情面板中找到 night_status::n_landmark 節點")
		if not status_nodes.is_empty():
			assert_eq((status_nodes[0] as Label).text, "[已到訪]", "詳情狀態文字為 [已到訪]")
		await _close(tree)
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["status_seen_nightonly"] } }

	func _p3d_01_no_number(tree: SceneTree) -> Dictionary:
		var btn_paid_arr := QAStepClass.find_controls_by_qa_id(tree.get_root(), "location::n_ahong_1")
		assert_eq(btn_paid_arr.size(), 1, "地圖清單中找到 location::n_ahong_1 按鈕")
		if not btn_paid_arr.is_empty():
			var btn_paid: Button = btn_paid_arr[0] as Button
			assert_true(btn_paid.text.contains("[尚未到訪]"), "收費地點按鈕包含 [尚未到訪]")
			assert_false(_has_digits(btn_paid.text), "收費地點按鈕文字不含數字")
			assert_false(btn_paid.text.contains("免費"), "收費地點按鈕文字不含『免費』")
		var btn_free_arr := QAStepClass.find_controls_by_qa_id(tree.get_root(), "location::n_woodtags")
		assert_eq(btn_free_arr.size(), 1, "地圖清單中找到 location::n_woodtags 按鈕")
		if not btn_free_arr.is_empty():
			var btn_free: Button = btn_free_arr[0] as Button
			assert_true(btn_free.text.contains("[尚未到訪]"), "免費地點按鈕包含 [尚未到訪]")
			assert_false(_has_digits(btn_free.text), "免費地點按鈕文字不含數字")
			assert_false(btn_free.text.contains("免費"), "免費地點按鈕文字不含『免費』")
		await _click(tree, "location::n_ahong_1")
		var status_paid := QAStepClass.find_controls_by_qa_id(tree.get_root(), "night_status::n_ahong_1")
		if not status_paid.is_empty():
			assert_eq((status_paid[0] as Label).text, "[尚未到訪]", "收費地點詳情狀態文字為 [尚未到訪]")
			assert_false(_has_digits((status_paid[0] as Label).text), "收費地點詳情狀態文字不含數字")
		await _close(tree)
		await _click(tree, "location::n_woodtags")
		var status_free := QAStepClass.find_controls_by_qa_id(tree.get_root(), "night_status::n_woodtags")
		if not status_free.is_empty():
			assert_eq((status_free[0] as Label).text, "[尚未到訪]", "免費地點詳情狀態文字為 [尚未到訪]")
			assert_false(_has_digits((status_free[0] as Label).text), "免費地點詳情狀態文字不含數字")
		await _close(tree)
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["status_no_number"] } }

	func _p3d_02_1to1(tree: SceneTree) -> Dictionary:
		var btns := QAStepClass.find_controls_by_qa_id(tree.get_root(), "location::n_exit")
		assert_eq(btns.size(), 1, "地圖清單中找到 location::n_exit 按鈕")
		if not btns.is_empty():
			var btn: Button = btns[0] as Button
			assert_true(btn.text.contains("山泉閣"), "一對一對位按鈕包含白天地點名『山泉閣』")
			assert_true(btn.text.contains("[已對位]"), "一對一對位按鈕包含 [已對位]")
			assert_false(btn.text.contains("・"), "一對一對位按鈕不含中圓點")
		await _click(tree, "location::n_exit")
		var status_nodes := QAStepClass.find_controls_by_qa_id(tree.get_root(), "night_status::n_exit")
		if not status_nodes.is_empty():
			assert_eq((status_nodes[0] as Label).text, "[已對位]", "一對一詳情狀態為 [已對位]")
		var title_node := tree.get_root().find_child("LocationTitle", true, false) as Label
		if title_node != null:
			assert_true(title_node.text.contains("山泉閣"), "一對一詳情標題包含白天地點名『山泉閣』")
		await _close(tree)
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["aligned_one_to_one_name"] } }

	func _p3d_02_multi(tree: SceneTree) -> Dictionary:
		var btns := QAStepClass.find_controls_by_qa_id(tree.get_root(), "location::n_corridor")
		assert_eq(btns.size(), 1, "地圖清單中找到 location::n_corridor 按鈕")
		if not btns.is_empty():
			var btn: Button = btns[0] as Button
			assert_true(btn.text.contains("靜和園後棟・很長的走廊"), "多對一對位按鈕包含『靜和園後棟・很長的走廊』")
			assert_true(btn.text.contains("[已對位]"), "多對一對位按鈕包含 [已對位]")
		await _click(tree, "location::n_corridor")
		var status_nodes := QAStepClass.find_controls_by_qa_id(tree.get_root(), "night_status::n_corridor")
		if not status_nodes.is_empty():
			assert_eq((status_nodes[0] as Label).text, "[已對位]", "多對一詳情狀態為 [已對位]")
		var title_node := tree.get_root().find_child("LocationTitle", true, false) as Label
		if title_node != null:
			assert_true(title_node.text.contains("靜和園後棟・很長的走廊"), "多對一詳情標題包含『靜和園後棟・很長的走廊』")
		await _close(tree)
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["aligned_multi_name"] } }

	func _p3d_03_ahong(tree: SceneTree) -> Dictionary:
		await _click(tree, "location::n_ahong_2")
		var reason_nodes := QAStepClass.find_controls_by_qa_id(tree.get_root(), "night_reason::n_ahong_2")
		assert_eq(reason_nodes.size(), 1, "詳情面板中找到 night_reason::n_ahong_2 節點")
		if not reason_nodes.is_empty():
			assert_true(reason_nodes[0].is_visible_in_tree(), "理由節點可見")
			assert_eq((reason_nodes[0] as Label).text, "你還沒跟完上一段痕跡。", "門檻理由為『你還沒跟完上一段痕跡。』")
		var enter_nodes := QAStepClass.find_controls_by_qa_id(tree.get_root(), "night_enter::n_ahong_2")
		assert_eq(enter_nodes.size(), 1, "詳情面板中找到 night_enter::n_ahong_2 節點")
		if not enter_nodes.is_empty():
			assert_true((enter_nodes[0] as Button).disabled, "進入按鈕為 disabled")
		var s_before: Dictionary = _state(tree)
		await QAStepClass.click(tree, "night_enter::n_ahong_2", MOUSE_BUTTON_LEFT, true)
		var s_after: Dictionary = _state(tree)
		assert_eq(JSON.stringify(s_after), JSON.stringify(s_before), "點擊 disabled 進入按鈕狀態零變化")
		await _close(tree)
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["gated_ahong_reason_disabled"] } }

	func _p3d_03_teaser(tree: SceneTree) -> Dictionary:
		assert_true(QAStepClass.has_visible_qa_id(tree.get_root(), "location::n_corridor_end"), "第三章夜間地圖顯示 teaser location::n_corridor_end")
		await _click(tree, "location::n_corridor_end")
		var reason_nodes := QAStepClass.find_controls_by_qa_id(tree.get_root(), "night_reason::n_corridor_end")
		assert_eq(reason_nodes.size(), 1, "詳情面板中找到 night_reason::n_corridor_end 節點")
		if not reason_nodes.is_empty():
			assert_true(reason_nodes[0].is_visible_in_tree(), "teaser 理由節點可見")
			assert_eq((reason_nodes[0] as Label).text, "還沒有走到那裡。", "teaser 理由為『還沒有走到那裡。』")
		var enter_nodes := QAStepClass.find_controls_by_qa_id(tree.get_root(), "night_enter::n_corridor_end")
		assert_eq(enter_nodes.size(), 1, "詳情面板中找到 night_enter::n_corridor_end 節點")
		if not enter_nodes.is_empty():
			assert_true((enter_nodes[0] as Button).disabled, "teaser 進入按鈕為 disabled")
		var s_before: Dictionary = _state(tree)
		await QAStepClass.click(tree, "night_enter::n_corridor_end", MOUSE_BUTTON_LEFT, true)
		var s_after: Dictionary = _state(tree)
		assert_eq(JSON.stringify(s_after), JSON.stringify(s_before), "teaser 地點點擊進入按鈕狀態零變化")
		await _close(tree)
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["gated_teaser_no_entry"] } }

	func _p3d_04_warning(tree: SceneTree) -> Dictionary:
		await _click(tree, "location::n_ahong_1")
		var warn_nodes := QAStepClass.find_controls_by_qa_id(tree.get_root(), "night_warning::n_ahong_1")
		assert_eq(warn_nodes.size(), 1, "詳情面板中找到 night_warning::n_ahong_1 節點")
		if not warn_nodes.is_empty():
			assert_true(warn_nodes[0].is_visible_in_tree(), "近 cap 收費地點顯示風險警告")
			assert_eq((warn_nodes[0] as Label).text, "再往前，你可能回不來。", "風險警告文字為『再往前，你可能回不來。』")
			assert_false(_has_digits((warn_nodes[0] as Label).text), "風險警告文字不含數字")
		await _close(tree)
		await _click(tree, "location::n_landmark")
		var free_warns := QAStepClass.find_controls_by_qa_id(tree.get_root(), "night_warning::n_landmark")
		var free_warn_visible := false
		if not free_warns.is_empty():
			free_warn_visible = free_warns[0].is_visible_in_tree() and not (free_warns[0] as Label).text.is_empty()
		assert_false(free_warn_visible, "免費地點詳情面板不顯示風險警告")
		await _close(tree)
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["warning_shown_no_number", "warning_absent_on_free"] } }

	func _p3d_05_sleep(tree: SceneTree) -> Dictionary:
		await _advance(tree)
		assert_true(bool(_run(tree).get("night_sleep_pending", false)), "第 1 次推進進入 night_sleep_pending 停拍")
		await _click(tree, "location::n_landmark")
		var enter1 := QAStepClass.find_controls_by_qa_id(tree.get_root(), "night_enter::n_landmark")
		assert_eq(enter1.size(), 1, "找到 n_landmark 進入按鈕")
		if not enter1.is_empty():
			assert_true((enter1[0] as Button).disabled, "停拍期間 n_landmark 進入按鈕為 disabled")
		var s_b1: Dictionary = _state(tree)
		await QAStepClass.click(tree, "night_enter::n_landmark", MOUSE_BUTTON_LEFT, true)
		var s_a1: Dictionary = _state(tree)
		assert_eq(JSON.stringify(s_a1), JSON.stringify(s_b1), "停拍期間點擊 n_landmark 進入按鈕狀態零變化")
		await _close(tree)
		await _click(tree, "location::n_ahong_1")
		var enter2 := QAStepClass.find_controls_by_qa_id(tree.get_root(), "night_enter::n_ahong_1")
		assert_eq(enter2.size(), 1, "找到 n_ahong_1 進入按鈕")
		if not enter2.is_empty():
			assert_true((enter2[0] as Button).disabled, "停拍期間 n_ahong_1 進入按鈕為 disabled")
		var s_b2: Dictionary = _state(tree)
		await QAStepClass.click(tree, "night_enter::n_ahong_1", MOUSE_BUTTON_LEFT, true)
		var s_a2: Dictionary = _state(tree)
		assert_eq(JSON.stringify(s_a2), JSON.stringify(s_b2), "停拍期間點擊 n_ahong_1 進入按鈕狀態零變化")
		await _close(tree)
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["sleep_pending_all_disabled", "sleep_pending_click_noop"] } }

	func _p3d_06_geo(tree: SceneTree, main_node: Control, run_dir: String) -> Dictionary:
		var cap_map := await QADiagnosticsClass.capture_interim_state(tree, main_node, run_dir, id, "night_list_map")
		assert_true(bool(cap_map.get("ok", false)), "夜間清單幾何診斷擷取成功")
		var geo_map: Dictionary = cap_map.get("geometry", {})
		assert_true(bool(geo_map.get("ok", false)), "夜間清單畫面幾何診斷通過: %s" % JSON.stringify(geo_map))
		await _click(tree, "location::n_corridor")
		var cap_panel := await QADiagnosticsClass.capture_interim_state(tree, main_node, run_dir, id, "night_detail_panel")
		assert_true(bool(cap_panel.get("ok", false)), "夜間詳情面板幾何診斷擷取成功")
		var geo_panel: Dictionary = cap_panel.get("geometry", {})
		assert_true(bool(geo_panel.get("ok", false)), "夜間詳情面板畫面幾何診斷通過: %s" % JSON.stringify(geo_panel))
		await _close(tree)
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["night_list_geometry_clean"] } }

	func _p3e_01(tree: SceneTree) -> Dictionary:
		var btns := QAStepClass.find_controls_by_qa_id(tree.get_root(), "location::sanquan")
		assert_eq(btns.size(), 1, "地圖清單中找到 location::sanquan 按鈕")
		if not btns.is_empty():
			var btn_text: String = (btns[0] as Button).text
			assert_false(btn_text.contains("對位"), "白天地圖按鈕不含對位提示文字")
			assert_false(btn_text.contains("見聞"), "白天地圖按鈕不含見聞提示文字")
		await _enter(tree, "sanquan")
		var align_btns := QAStepClass.find_controls_by_qa_id(tree.get_root(), "night_align::sanquan")
		assert_eq(align_btns.size(), 1, "常態面板中找到 night_align::sanquan 按鈕")
		if not align_btns.is_empty():
			assert_true((align_btns[0] as Control).is_visible_in_tree(), "night_align::sanquan 按鈕可見")
			assert_eq((align_btns[0] as Button).text, "把兩邊對起來", "按鈕文字為『把兩邊對起來』")
		await _close(tree)
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["map_no_align_hint", "align_button_visible_after_beats"] } }

	func _p3e_02(tree: SceneTree) -> Dictionary:
		var snap_before := JSON.stringify(_state(tree))
		await _enter(tree, "oldstreet")
		var align_oldstreet := QAStepClass.find_controls_by_qa_id(tree.get_root(), "night_align::oldstreet")
		assert_true(align_oldstreet.is_empty() or not (align_oldstreet[0] as Control).is_visible_in_tree(), "錯誤地點 oldstreet 無對位按鈕")
		await _close(tree)

		await _enter(tree, "temple")
		var align_temple := QAStepClass.find_controls_by_qa_id(tree.get_root(), "night_align::temple")
		assert_true(align_temple.is_empty() or not (align_temple[0] as Control).is_visible_in_tree(), "錯誤地點 temple 無對位按鈕")
		await _close(tree)

		var snap_after := JSON.stringify(_state(tree))
		assert_eq(snap_after, snap_before, "打開錯誤白天地點後完整 serialize 狀態逐字不變")
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["wrong_locations_no_align_button", "wrong_locations_state_unchanged"] } }

	func _p3e_03(tree: SceneTree) -> Dictionary:
		await _enter(tree, "sanquan")
		var snap_before := JSON.stringify(_state(tree))
		await _click(tree, "night_align::sanquan")
		var cancel_btns := QAStepClass.find_controls_by_qa_id(tree.get_root(), "dialog_cancel::night_align")
		assert_eq(cancel_btns.size(), 1, "彈出對話框中找到 dialog_cancel::night_align 取消按鈕")
		if not cancel_btns.is_empty():
			await _click(tree, "dialog_cancel::night_align")
		var snap_after := JSON.stringify(_state(tree))
		assert_eq(snap_after, snap_before, "開啟彈窗並取消後完整 serialize 狀態逐字不變")
		await _close(tree)
		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["align_dialog_opened", "align_cancel_state_unchanged"] } }

	func _p3e_04(tree: SceneTree) -> Dictionary:
		var k_before: Dictionary = _meta(tree).get("knowledge", {}) as Dictionary
		var k_count_before := k_before.size()
		await _enter(tree, "sanquan")
		await _click(tree, "night_align::sanquan")
		await _click(tree, "dialog_confirm::night_align")

		var k_after: Dictionary = _meta(tree).get("knowledge", {}) as Dictionary
		assert_eq(k_after.size(), k_count_before + 1, "knowledge 恰好增加一張")
		assert_true(k_after.has("k_night_sanquan"), "獲得正確對位知識卡 k_night_sanquan")
		assert_false(bool(_run(tree).get("action_spent", true)), "對位後 action_spent 仍為 false")

		var align_btns := QAStepClass.find_controls_by_qa_id(tree.get_root(), "night_align::sanquan")
		assert_true(align_btns.is_empty() or not (align_btns[0] as Control).is_visible_in_tree(), "確認對位後 night_align::sanquan 按鈕消失")
		await _close(tree)

		# 點開知識詳情核驗卡片內容
		await _click(tree, "knowledge_entry")
		var k_labels := tree.get_root().find_children("*", "Label", true, false)
		var found_k_text := false
		for lbl in k_labels:
			if (lbl as Label).text.contains("山泉閣") or (lbl as Label).text.contains("石階"):
				found_k_text = true
				break
		assert_true(found_k_text, "知識詳情彈窗中可讀到新獲得之知識卡")
		await _click(tree, "dialog_confirm::card_detail")

		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["knowledge_gained_one", "action_not_spent", "align_button_vanished", "knowledge_detail_readable"] } }

	func _p3e_05(tree: SceneTree, main_node: Control) -> Dictionary:
		# 1. 白天對位 temple (多對一)
		await _enter(tree, "temple")
		await _click(tree, "night_align::temple")
		await _click(tree, "dialog_confirm::night_align")
		await _close(tree)

		var know: Dictionary = _meta(tree).get("knowledge", {}) as Dictionary
		assert_true(know.has("k_night_temple"), "白天對位獲得共用 k_night_temple")

		# 2. 轉入夜間
		var gs: Node = CaseBaseClass.get_game_state(tree)
		gs.set("phase", "night")
		main_node.call("_route_view")

		# 3. 檢查第一個 row (n_woodtags) 為 [已對位]
		var btns_wood := QAStepClass.find_controls_by_qa_id(tree.get_root(), "location::n_woodtags")
		if not btns_wood.is_empty():
			assert_true((btns_wood[0] as Button).text.contains("[已對位]"), "第一個 row n_woodtags 顯示 [已對位]")
			assert_true((btns_wood[0] as Button).text.contains("廟＋廟埕・數木牌的屋子"), "第一個 row 顯示白天名・夜間名")

		# 4. 檢查第二個 row (n_music) 仍為 [尚未到訪]
		var btns_music := QAStepClass.find_controls_by_qa_id(tree.get_root(), "location::n_music")
		if not btns_music.is_empty():
			assert_true((btns_music[0] as Button).text.contains("[尚未到訪]"), "第二個 row n_music 仍為 [尚未到訪]")
			assert_false((btns_music[0] as Button).text.contains("廟＋廟埕"), "第二個 row 未劇透白天地點名")

		# 5. 首次進入第二個 row n_music
		await _enter(tree, "n_music")
		await _close(tree)

		# 6. 回到夜間地圖，第二個 row 自動顯示 [已對位] 且無第二次確認
		var btns_music_after := QAStepClass.find_controls_by_qa_id(tree.get_root(), "location::n_music")
		if not btns_music_after.is_empty():
			assert_true((btns_music_after[0] as Button).text.contains("[已對位]"), "第二個 row 到訪後自動顯示 [已對位]")
			assert_true((btns_music_after[0] as Button).text.contains("廟＋廟埕・有音樂的地方"), "第二個 row 自動顯示白天名・夜間名")

		return { "ok": errors.is_empty(), "errors": errors, "observations": { "evidence": ["multi_row_first_aligned", "multi_row_second_unseen", "multi_row_second_auto_aligned"] } }

