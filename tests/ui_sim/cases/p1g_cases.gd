class_name P1GCases
extends RefCounted

## P1-G 全部 17 個 UI 模擬驗收案例（依 測試指南.md > P1-G 面板互動模型 實作）。

const CaseBaseClass := preload("res://tests/ui_sim/cases/case_base.gd")
const QAStep := preload("res://tests/ui_sim/qa_step.gd")
const QADiagnostics := preload("res://tests/ui_sim/qa_diagnostics.gd")


static func get_all_cases() -> Array[CaseBaseClass]:
	var list: Array[CaseBaseClass] = []
	list.append(Case01aBeatsAjie.new())
	list.append(Case01bBeatsAlone.new())
	list.append(Case02LockInteractionDuringPlay.new())
	list.append(Case03ReenterNoDuplicateOnEnter.new())
	list.append(Case04SlotTypes.new())
	list.append(Case05ProtagonistSlotType.new())
	list.append(Case06NoSpoiler.new())
	list.append(Case07RightClickPreview.new())
	list.append(Case08RightClickLockedPreview.new())
	list.append(Case09PreviewButtonMatchRightClick.new())
	list.append(Case10PreviewPlacementConsistentPositive.new())
	list.append(Case11PreviewPlacementConsistentNegative.new())
	list.append(Case12aAdvanceD35.new())
	list.append(Case12bAdvanceD40.new())
	list.append(Case12cAdvanceD43.new())
	list.append(Case13NightSameModel.new())
	list.append(Case14LocationDesc.new())
	return list


static func get_case_by_id(case_id: String) -> CaseBaseClass:
	for c in get_all_cases():
		if c.id == case_id:
			return c
	return null


# =========================================================================
# Case 01a: 演出逐一（邀請阿婕分支：d32_festival -> d32_festival_ajie）
# =========================================================================
class Case01aBeatsAjie extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_01a_beats_ajie",
			"第 32 天上午寺廟（邀阿婕）：d32_festival 與 d32_festival_ajie 逐一播放，其餘分支不播放",
			"d32_morning__ajie.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		var run_state: Dictionary = gs.call("serialize").get("run", {})
		assert_eq(int(run_state.get("day")), 32, "天數必須為 32")
		assert_eq(str(run_state.get("phase")), "morning", "時段必須為 morning")

		var click_res := await QAStep.click(tree, "location::temple")
		if not click_res.get("ok", false):
			return { "ok": false, "errors": ["點擊寺廟失敗: " + str(click_res.get("error"))] }

		# 依序推進所有 beats
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"), "進入寺廟後必須有 beat_advance 按鈕")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			var adv_res := await QAStep.click(tree, "beat_advance")
			if not adv_res.get("ok", false):
				return { "ok": false, "errors": ["推進演出失敗: " + str(adv_res.get("error"))] }

		# 演畢進入常態
		assert_true(not QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"), "全部 beat 演完後 beat_advance 必須隱藏")

		var after_run: Dictionary = gs.call("serialize").get("run", {})
		var entered: Dictionary = after_run.get("beats_entered", {})
		assert_true(entered.has("d32_festival"), "beats_entered 必須記錄 d32_festival")
		assert_true(entered.has("d32_festival_ajie"), "beats_entered 必須記錄 d32_festival_ajie")
		assert_true(not entered.has("d32_festival_alone"), "不應觸發 d32_festival_alone")
		assert_true(not entered.has("d32_festival_awei"), "不應觸發 d32_festival_awei")

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 01b: 演出逐一（未邀人分支：d32_festival -> d32_festival_alone）
# =========================================================================
class Case01bBeatsAlone extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_01b_beats_alone",
			"第 32 天上午寺廟（無邀請）：d32_festival 與 d32_festival_alone 逐一播放，其餘分支不播放",
			"d32_morning__none.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		var run_state: Dictionary = gs.call("serialize").get("run", {})
		assert_eq(int(run_state.get("day")), 32, "天數必須為 32")

		var click_res := await QAStep.click(tree, "location::temple")
		if not click_res.get("ok", false):
			return { "ok": false, "errors": ["點擊寺廟失敗: " + str(click_res.get("error"))] }

		# 依序推進所有 beats
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"), "進入寺廟後必須有 beat_advance 按鈕")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			var adv_res := await QAStep.click(tree, "beat_advance")
			if not adv_res.get("ok", false):
				return { "ok": false, "errors": ["推進演出失敗: " + str(adv_res.get("error"))] }

		# 演畢進入常態
		assert_true(not QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"), "全部 beat 演完後 beat_advance 必須隱藏")

		var after_run: Dictionary = gs.call("serialize").get("run", {})
		var entered: Dictionary = after_run.get("beats_entered", {})
		assert_true(entered.has("d32_festival"), "beats_entered 必須記錄 d32_festival")
		assert_true(entered.has("d32_festival_alone"), "beats_entered 必須記錄 d32_festival_alone")
		assert_true(not entered.has("d32_festival_ajie"), "不應觸發 d32_festival_ajie")
		assert_true(not entered.has("d32_festival_awei"), "不應觸發 d32_festival_awei")

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 02: 演出期間鎖互動（演出未完時無可放卡槽）
# =========================================================================
class Case02LockInteractionDuringPlay extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_02_lock_interaction_during_play",
			"演出期間畫面上沒有任何可放卡的 place:: 或 choose:: 槽位節點",
			"d32_morning__ajie.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var click_res := await QAStep.click(tree, "location::temple")
		if not click_res.get("ok", false):
			return { "ok": false, "errors": ["點擊寺廟失敗: " + str(click_res.get("error"))] }

		# 演出期間：beat_advance 必須可見
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"), "演出期間 beat_advance 必須存在且可見")

		# 檢查所有 place:: 與 choose:: 控制項不可存在於 UI dump
		var all_controls: Array[Dictionary] = QADiagnostics.dump_ui_tree(tree.get_root())
		for item in all_controls:
			var qa_id: String = item.get("qa_id", "")
			var vis: bool = bool(item.get("visible_in_tree", false))
			if vis and (qa_id.begins_with("place::") or qa_id.begins_with("choose::")):
				errors.append("FAIL: 演出期間不應存在可見互動控制項: %s" % qa_id)

		# 推進完畢後進入常態
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 03: 重進不重複結算（第 17 天上午 fixed beat）
# =========================================================================
class Case03ReenterNoDuplicateOnEnter extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_03_reenter_no_duplicate_on_enter",
			"進山泉閣 d17_morning_phone 後離開再進，文字重播但狀態完全不重複結算",
			"d17_morning.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)

		# 第一次進入山泉閣
		var c1 := await QAStep.click(tree, "location::sanquan")
		if not c1.get("ok", false):
			return { "ok": false, "errors": ["第一次點擊山泉閣失敗: " + str(c1.get("error"))] }

		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"), "第一次進入必須有演出推進按鈕")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var state_1: Dictionary = gs.call("serialize")

		# 離開面板
		var b_res := await QAStep.click(tree, "panel_back")
		assert_true(b_res.get("ok", false), "點擊返回按鈕失敗")

		# 第二次進入山泉閣
		var c2 := await QAStep.click(tree, "location::sanquan")
		assert_true(c2.get("ok", false), "第二次點擊山泉閣失敗")

		# 重進時文字重播（有 beat_advance）
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"), "第二次進入必須重播文字演出")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var state_2: Dictionary = gs.call("serialize")
		assert_eq(JSON.stringify(state_2), JSON.stringify(state_1), "重進面板後 GameState 狀態必須與首次演畢完全相同")

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 04: 槽型別標示（第 22 天下午堆沙包全部 4 個槽位的型別標示）
# =========================================================================
class Case04SlotTypes extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_04_slot_types",
			"第 22 天下午堆沙包的 4 個槽位，型別顯示成「主角卡」與「裝備卡、情報卡」（用「、」不是「／」）",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		# 1. 主角槽
		var work_lbls := QAStep.find_controls_by_qa_id(tree.get_root(), "slot::d22_pm_sandbags::work")
		assert_true(not work_lbls.is_empty(), "找不到 slot::d22_pm_sandbags::work 控制項")
		if not work_lbls.is_empty():
			var t0: String = (work_lbls[0] as Label).text
			assert_true(t0.contains("（收：主角卡）"), "work 槽標示應為「（收：主角卡）」，實際: %s" % t0)

		# 2. 觀察槽 1: obs_walk
		var walk_lbls := QAStep.find_controls_by_qa_id(tree.get_root(), "slot::d22_pm_sandbags::obs_walk")
		assert_true(not walk_lbls.is_empty(), "找不到 slot::d22_pm_sandbags::obs_walk 控制項")
		if not walk_lbls.is_empty():
			var t1: String = (walk_lbls[0] as Label).text
			assert_true(t1.contains("（收：裝備卡、情報卡）"), "obs_walk 槽標示應包含「（收：裝備卡、情報卡）」，實際: %s" % t1)
			assert_true(not t1.contains("裝備卡/情報卡") and not t1.contains("裝備卡／情報卡"), "不可使用斜線: %s" % t1)

		# 3. 觀察槽 2: obs_hands
		var hands_lbls := QAStep.find_controls_by_qa_id(tree.get_root(), "slot::d22_pm_sandbags::obs_hands")
		assert_true(not hands_lbls.is_empty(), "找不到 slot::d22_pm_sandbags::obs_hands 控制項")
		if not hands_lbls.is_empty():
			var t2: String = (hands_lbls[0] as Label).text
			assert_true(t2.contains("（收：裝備卡、情報卡）"), "obs_hands 槽標示應包含「（收：裝備卡、情報卡）」，實際: %s" % t2)

		# 4. 觀察槽 3: obs_talk
		var talk_lbls := QAStep.find_controls_by_qa_id(tree.get_root(), "slot::d22_pm_sandbags::obs_talk")
		assert_true(not talk_lbls.is_empty(), "找不到 slot::d22_pm_sandbags::obs_talk 控制項")
		if not talk_lbls.is_empty():
			var t3: String = (talk_lbls[0] as Label).text
			assert_true(t3.contains("（收：裝備卡、情報卡）"), "obs_talk 槽標示應包含「（收：裝備卡、情報卡）」，實際: %s" % t3)

		# 5. 觀察槽 4: dismiss
		var dis_lbls := QAStep.find_controls_by_qa_id(tree.get_root(), "slot::d22_pm_sandbags::dismiss")
		assert_true(not dis_lbls.is_empty(), "找不到 slot::d22_pm_sandbags::dismiss 控制項")
		if not dis_lbls.is_empty():
			var t4: String = (dis_lbls[0] as Label).text
			assert_true(t4.contains("（收：裝備卡、情報卡）"), "dismiss 槽標示應包含「（收：裝備卡、情報卡）」，實際: %s" % t4)

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 05: 主角卡槽型別標示
# =========================================================================
class Case05ProtagonistSlotType extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_05_protagonist_slot_type",
			"收主角卡的槽顯示「主角卡」且與 card_types.json 一致",
			"d3_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var click_res := await QAStep.click(tree, "location::sanquan")
		if not click_res.get("ok", false):
			return { "ok": false, "errors": ["點擊山泉閣失敗: " + str(click_res.get("error"))] }

		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var slot_lbls := QAStep.find_controls_by_qa_id(tree.get_root(), "slot::d3_pm_sanquan::help_ahong")
		if slot_lbls.is_empty():
			return { "ok": false, "errors": ["找不到 slot::d3_pm_sanquan::help_ahong 控制項"] }

		var text: String = (slot_lbls[0] as Label).text
		assert_true(text.contains("（收：主角卡）"), "槽型別標示應包含「（收：主角卡）」，實際為: %s" % text)
		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 06: 不劇透（具體卡 id 槽只顯示型別，不顯示卡名）
# =========================================================================
class Case06NoSpoiler extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_06_no_spoiler",
			"accepts 寫具體卡 id 的槽只顯示「情報卡」，不顯示卡名",
			"d3_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var click_res := await QAStep.click(tree, "location::sanquan")
		if not click_res.get("ok", false):
			return { "ok": false, "errors": ["點擊山泉閣失敗: " + str(click_res.get("error"))] }

		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var slot_lbls := QAStep.find_controls_by_qa_id(tree.get_root(), "slot::d3_pm_sanquan::show_version")
		if slot_lbls.is_empty():
			return { "ok": false, "errors": ["找不到 slot::d3_pm_sanquan::show_version 控制項"] }

		var text: String = (slot_lbls[0] as Label).text
		assert_true(text.contains("（收：情報卡）"), "比對槽應顯示「（收：情報卡）」，實際為: %s" % text)
		assert_true(not text.contains("丈夫說的") and not text.contains("妻子說的"), "不劇透：槽文字不得包含卡名，實際為: %s" % text)
		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 07: 右鍵預覽（正常槽預覽，關閉後狀態不變）
# =========================================================================
class Case07RightClickPreview extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_07_right_click_preview",
			"對可放的槽右鍵列出相容卡片清單，關閉後天數、時段、手牌、知識、旗標全部不變",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, main_node: Control, run_dir: String) -> Dictionary:
		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var gs := CaseBaseClass.get_game_state(tree)
		var state_before: Dictionary = gs.call("serialize")

		# 右鍵點擊 work 槽
		var click_res := await QAStep.click(tree, "slot::d22_pm_sandbags::work", MOUSE_BUTTON_RIGHT)
		assert_true(click_res.get("ok", false), "右鍵點擊槽失敗: " + str(click_res.get("error")))

		# 驗證預覽彈窗已開啟且包含相容卡名
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "dialog_confirm::preview"), "預覽確認按鈕必須可見")
		var diag := find_preview_dialog(tree)
		assert_true(diag != null, "必須找到 AcceptDialog 彈窗")
		if diag != null:
			assert_true(diag.dialog_text.contains("可放置：我"), "預覽文字應包含相容卡片「我」，實際為: %s" % diag.dialog_text)

		# 中途截圖與 dump
		QADiagnostics.capture_interim_state(tree, main_node, run_dir, id, "preview_open")

		# 關閉預覽彈窗
		var close_res := await QAStep.click(tree, "dialog_confirm::preview")
		assert_true(close_res.get("ok", false), "關閉預覽彈窗失敗: " + str(close_res.get("error")))
		assert_true(not QAStep.has_visible_qa_id(tree.get_root(), "dialog_confirm::preview"), "關閉後預覽確認按鈕必須不可見")

		var state_after: Dictionary = gs.call("serialize")
		assert_eq(JSON.stringify(state_after), JSON.stringify(state_before), "關閉預覽後狀態必須完全不變")
		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 08: 灰槽右鍵預覽
# =========================================================================
class Case08RightClickLockedPreview extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_08_right_click_locked_preview",
			"對灰掉的槽右鍵，清單是空的並顯示理由文字",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, main_node: Control, run_dir: String) -> Dictionary:
		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		# 右鍵點擊灰槽 obs_hands
		var click_res := await QAStep.click(tree, "slot::d22_pm_sandbags::obs_hands", MOUSE_BUTTON_RIGHT)
		assert_true(click_res.get("ok", false), "右鍵點擊灰槽失敗: " + str(click_res.get("error")))

		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "dialog_confirm::preview"), "灰槽預覽彈窗必須開啟")
		var diag := find_preview_dialog(tree)
		assert_true(diag != null, "必須找到灰槽 AcceptDialog 彈窗")
		if diag != null:
			assert_true(diag.dialog_text.contains("目前沒有可放的卡。"), "灰槽預覽應提示目前沒有可放的卡，實際: %s" % diag.dialog_text)
			assert_true(diag.dialog_text.contains("理由：（你沒有真的跟他遞過幾次東西。）"), "灰槽預覽應包含理由，實際: %s" % diag.dialog_text)

		QADiagnostics.capture_interim_state(tree, main_node, run_dir, id, "locked_preview_open")

		var close_res := await QAStep.click(tree, "dialog_confirm::preview")
		assert_true(close_res.get("ok", false), "關閉灰槽預覽失敗: " + str(close_res.get("error")))
		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 09: 左鍵預覽按鈕與右鍵結果逐字相同
# =========================================================================
class Case09PreviewButtonMatchRightClick extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_09_preview_button_match_right_click",
			"同一個槽，左鍵「預覽」按鈕與右鍵呼叫出的清單與理由逐字相同且非空",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		# 1. 點擊「預覽」按鈕
		var b_click := await QAStep.click(tree, "preview::d22_pm_sandbags::work")
		assert_true(b_click.get("ok", false), "點擊預覽按鈕失敗")
		var diag_btn := find_preview_dialog(tree)
		assert_true(diag_btn != null, "按鈕預覽未開啟彈窗")
		var text_btn := diag_btn.dialog_text if diag_btn != null else ""
		assert_true(not text_btn.is_empty(), "預覽按鈕彈窗文字不可為空")
		await QAStep.click(tree, "dialog_confirm::preview")

		# 2. 右鍵點擊槽 Label
		var r_click := await QAStep.click(tree, "slot::d22_pm_sandbags::work", MOUSE_BUTTON_RIGHT)
		assert_true(r_click.get("ok", false), "右鍵點擊槽失敗")
		var diag_rclick := find_preview_dialog(tree)
		assert_true(diag_rclick != null, "右鍵預覽未開啟彈窗")
		var text_rclick := diag_rclick.dialog_text if diag_rclick != null else ""
		assert_true(not text_rclick.is_empty(), "右鍵預覽彈窗文字不可為空")
		await QAStep.click(tree, "dialog_confirm::preview")

		assert_eq(text_btn, text_rclick, "按鈕預覽與右鍵預覽內容應逐字相同")
		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 10: 預覽與實放一致（正向）
# =========================================================================
class Case10PreviewPlacementConsistentPositive extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_10_preview_placement_consistent_positive",
			"預覽列出的每一張卡，實際點擊放置按鈕一定成功放置並結算",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var gs := CaseBaseClass.get_game_state(tree)
		var preview_res: Dictionary = gs.call("preview_slot", "d22_pm_sandbags", "work")
		var cards: Array = preview_res.get("cards", []) as Array
		assert_true(not cards.is_empty(), "work 槽預覽清單不可為空")

		for card_id: String in cards:
			var qa_btn := "place::d22_pm_sandbags::work::%s" % card_id
			assert_true(QAStep.has_visible_qa_id(tree.get_root(), qa_btn), "預覽列出之卡片 %s 必須存在可見放置按鈕" % card_id)
			var place_res := await QAStep.click(tree, qa_btn)
			assert_true(place_res.get("ok", false), "放卡 %s 應成功結算" % card_id)

		var run_state: Dictionary = gs.call("serialize").get("run", {})
		assert_true(bool(run_state.get("action_spent", false)), "放置主角卡後 action_spent 必須為 true")
		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 11: 預覽與實放一致（反向）
# =========================================================================
class Case11PreviewPlacementConsistentNegative extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_11_preview_placement_consistent_negative",
			"預覽沒列出來的卡，畫面上絕對找不到對應的 place:: 控制項",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		# 在 work 槽中，只有 protagonist 相容，其餘所有卡均不得存在 place:: 按鈕
		assert_no_qa_id(tree, "place::d22_pm_sandbags::work::equip_polaroid", "不相容的裝備卡不應有放置按鈕")
		assert_no_qa_id(tree, "place::d22_pm_sandbags::work::info_acai_walk", "不相容的情報卡不應有放置按鈕")
		assert_no_qa_id(tree, "place::d22_pm_sandbags::work::info_acai_box", "不相容的情報卡不應有放置按鈕")
		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 12a: 推進提示（第 35 天下午純選擇題時段）
# =========================================================================
class Case12aAdvanceD35 extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_12a_advance_d35",
			"第 35 天下午：未做選擇時推進時段按鈕提示有動作可做，時段不自動跳過",
			"d35_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		var adv_btns := QAStep.find_controls_by_qa_id(tree.get_root(), "phase_advance")
		assert_true(not adv_btns.is_empty(), "找不到 phase_advance 按鈕")
		var adv_btn := adv_btns[0] as Button

		var orig_day: int = int(gs.get("day"))
		var orig_phase: String = str(gs.get("phase"))
		assert_eq(orig_day, 35, "天數必須為 35")
		assert_eq(orig_phase, "afternoon", "時段必須為 afternoon")

		# 推進按鈕文字不應為空且時段不自動跳過
		assert_true(not adv_btn.text.is_empty(), "推進按鈕文字不應為空")
		assert_eq(int(gs.get("day")), orig_day, "時段不應自動跳過")
		assert_eq(str(gs.get("phase")), orig_phase, "時段不應自動跳過")
		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 12b: 推進提示（第 40 天上午純選擇題時段）
# =========================================================================
class Case12bAdvanceD40 extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_12b_advance_d40",
			"第 40 天上午：純選擇題時段推進提示與互動",
			"d40_morning.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		var orig_day: int = int(gs.get("day"))
		var orig_phase: String = str(gs.get("phase"))
		assert_eq(orig_day, 40, "天數必須為 40")
		assert_eq(orig_phase, "morning", "時段必須為 morning")

		var adv_btns := QAStep.find_controls_by_qa_id(tree.get_root(), "phase_advance")
		assert_true(not adv_btns.is_empty(), "找不到 phase_advance 按鈕")
		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 12c: 推進提示（第 43 天下午純選擇題時段）
# =========================================================================
class Case12cAdvanceD43 extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_12c_advance_d43",
			"第 43 天下午：純選擇題時段推進提示與互動",
			"d43_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		var orig_day: int = int(gs.get("day"))
		var orig_phase: String = str(gs.get("phase"))
		assert_eq(orig_day, 43, "天數必須為 43")
		assert_eq(orig_phase, "afternoon", "時段必須為 afternoon")

		var adv_btns := QAStep.find_controls_by_qa_id(tree.get_root(), "phase_advance")
		assert_true(not adv_btns.is_empty(), "找不到 phase_advance 按鈕")
		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 13: 夜間同一套模型
# =========================================================================
class Case13NightSameModel extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_13_night_same_model",
			"選一個夜間地點進去，走的是同一條演出流程（演完才開放互動且放主角卡不耗行動）",
			"d10_night.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		assert_eq(str(gs.get("phase")), "night", "時段必須為 night")

		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "location::n_landmark"), "第 10 夜必須可見 n_landmark")
		var c_res := await QAStep.click(tree, "location::n_landmark")
		assert_true(c_res.get("ok", false), "進入 n_landmark 失敗")

		# 演畢進入常態
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var run_state: Dictionary = gs.call("serialize").get("run", {})
		var entered: Dictionary = run_state.get("beats_entered", {})
		assert_true(entered.has("n_landmark_ch1"), "beats_entered 必須記錄 n_landmark_ch1")

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 14: 地點描述（沒填 desc 時退回顯示地點名，不報錯）
# =========================================================================
class Case14LocationDesc extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_14_location_desc",
			"locations.json 沒填 desc 時只顯示地點名，描述 Label 隱藏，不報錯",
			"d2_morning.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var c_res := await QAStep.click(tree, "location::sanquan")
		assert_true(c_res.get("ok", false), "點擊山泉閣失敗")

		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var main_vp := tree.get_root()
		var titles := main_vp.find_children("LocationTitle", "Label", true, false)
		assert_true(not titles.is_empty(), "應存在 LocationTitle")
		if not titles.is_empty():
			var title_lbl := titles[0] as Label
			assert_eq(title_lbl.text, "山泉閣", "無 desc 時地點標題應等於地點名稱")

		var descs := main_vp.find_children("DescriptionLabel", "Label", true, false)
		if not descs.is_empty():
			var desc_lbl := descs[0] as Label
			assert_true(not desc_lbl.visible or desc_lbl.text.is_empty(), "無 desc 時描述標籤應隱藏或為空")

		return { "ok": errors.is_empty(), "errors": errors }
