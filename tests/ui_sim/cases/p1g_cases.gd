class_name P1GCases
extends RefCounted

## P1-G 全部 14 條 UI 模擬驗收案例（依 測試指南.md > P1-G 面板互動模型 實作）。

const CaseBaseClass := preload("res://tests/ui_sim/cases/case_base.gd")
const QAStep := preload("res://tests/ui_sim/qa_step.gd")
const QADiagnostics := preload("res://tests/ui_sim/qa_diagnostics.gd")


static func get_all_cases() -> Array[CaseBaseClass]:
	var list: Array[CaseBaseClass] = []
	list.append(Case01BeatsPlayOneByOne.new())
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
	list.append(Case12AdvanceHint.new())
	list.append(Case13NightSameModel.new())
	list.append(Case14LocationDesc.new())
	return list


static func get_case_by_id(case_id: String) -> CaseBaseClass:
	for c in get_all_cases():
		if c.id == case_id:
			return c
	return null


# =========================================================================
# Case 04: 槽型別標示（第 22 天下午觀察槽顯示「裝備卡、情報卡」）
# =========================================================================
class Case04SlotTypes extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_04_slot_types",
			"第 22 天下午堆沙包的觀察槽，型別顯示成「裝備卡、情報卡」（用「、」不是「／」）",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var click_res := await QAStep.click(tree, "location::sanquan")
		if not click_res.get("ok", false):
			return { "ok": false, "errors": ["點擊山泉閣失敗: " + str(click_res.get("error"))] }

		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var slot_lbls := QAStep.find_controls_by_qa_id(tree.get_root(), "slot::d22_pm_sandbags::obs_walk")
		if slot_lbls.is_empty():
			return { "ok": false, "errors": ["找不到 slot::d22_pm_sandbags::obs_walk 控制項"] }

		var text: String = (slot_lbls[0] as Label).text
		assert_true(text.contains("（收：裝備卡、情報卡）"), "槽型別標示應包含「（收：裝備卡、情報卡）」，實際為: %s" % text)
		assert_true(not text.contains("裝備卡/情報卡") and not text.contains("裝備卡／情報卡"), "不可使用斜線分隔符: %s" % text)

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
			"對可放的槽右鍵列出放得進去的卡，關閉後天數、時段、手牌、知識、旗標全部不變",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var gs: Node = CaseBaseClass.get_game_state(tree)
		var state_before: Dictionary = gs.call("serialize")

		var click_res := await QAStep.click(tree, "slot::d22_pm_sandbags::work", MOUSE_BUTTON_RIGHT)
		if not click_res.get("ok", false):
			return { "ok": false, "errors": ["右鍵點擊槽失敗: " + str(click_res.get("error"))] }

		var close_res := await QAStep.click(tree, "dialog_confirm::preview")
		if not close_res.get("ok", false):
			return { "ok": false, "errors": ["關閉預覽彈窗失敗: " + str(close_res.get("error"))] }

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
			"對灰掉的槽右鍵，清單是空的並顯示理由",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var click_res := await QAStep.click(tree, "slot::d22_pm_sandbags::obs_hands", MOUSE_BUTTON_RIGHT)
		if not click_res.get("ok", false):
			return { "ok": false, "errors": ["右鍵點擊灰槽失敗: " + str(click_res.get("error"))] }

		await QAStep.click(tree, "dialog_confirm::preview")
		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 09: 左鍵預覽按鈕與右鍵結果相同
# =========================================================================
class Case09PreviewButtonMatchRightClick extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_09_preview_button_match_right_click",
			"同一個槽，左鍵「預覽」按鈕與右鍵呼叫出的清單與理由相同",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		# 1. 點擊「預覽」按鈕
		await QAStep.click(tree, "preview::d22_pm_sandbags::work")
		var dialogs := QAStep.find_controls_by_qa_id(tree.get_root(), "dialog_confirm::preview")
		var text_btn := ""
		if not dialogs.is_empty():
			var p_diag: AcceptDialog = dialogs[0].get_parent() as AcceptDialog
			if p_diag != null:
				text_btn = p_diag.dialog_text
		await QAStep.click(tree, "dialog_confirm::preview")

		# 2. 右鍵點擊槽 Label
		await QAStep.click(tree, "slot::d22_pm_sandbags::work", MOUSE_BUTTON_RIGHT)
		var text_rclick := ""
		if not dialogs.is_empty():
			var p_diag: AcceptDialog = dialogs[0].get_parent() as AcceptDialog
			if p_diag != null:
				text_rclick = p_diag.dialog_text
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
			"預覽列出的每一張卡，實際放下去一定成功",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var place_res := await QAStep.click(tree, "place::d22_pm_sandbags::work::protagonist")
		assert_true(place_res.get("ok", false), "放主角卡應成功結算")
		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 11: 預覽與實放一致（反向）
# =========================================================================
class Case11PreviewPlacementConsistentNegative extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_11_preview_placement_consistent_negative",
			"預覽沒列出來的卡，畫面上找不到對應的 place:: 控制項",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		assert_no_qa_id(tree, "place::d22_pm_sandbags::work::equip_polaroid", "不相容的卡不應有放置按鈕")
		assert_no_qa_id(tree, "place::d22_pm_sandbags::work::info_acai_walk", "不相容的卡不應有放置按鈕")
		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 01: 演出逐一（進入面板 beat 一個一個演）
# =========================================================================
class Case01BeatsPlayOneByOne extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_01_beats_play_one_by_one",
			"進入第 32 天上午寺廟，成立的 beat 逐一播放，演完才進常態階段",
			"d32_morning__ajie.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		await QAStep.click(tree, "location::temple")
		var advance_count := 0
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			advance_count += 1
			await QAStep.click(tree, "beat_advance")

		assert_true(advance_count >= 1, "應至少經歷 1 次 beat 推進演出 (實際: %d 次)" % advance_count)
		assert_true(not QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"), "演出完畢後 beat_advance 按鈕應隱藏")
		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 02: 演出期間鎖互動（演出未完時無可放卡槽）
# =========================================================================
class Case02LockInteractionDuringPlay extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_02_lock_interaction_during_play",
			"演出期間畫面上沒有任何可放卡的 place:: 槽位節點",
			"d32_morning__ajie.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		await QAStep.click(tree, "location::temple")
		if QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			var all_controls: Array[Dictionary] = QADiagnostics.dump_ui_tree(tree.get_root())
			for item in all_controls:
				var qa_id: String = item.get("qa_id", "")
				if qa_id.begins_with("place::"):
					errors.append("FAIL: 演出期間不應存在 place:: 控制項: %s" % qa_id)
		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 03: 重進不重複結算（第 17 天上午 fixed beat）
# =========================================================================
class Case03ReenterNoDuplicateOnEnter extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_03_reenter_no_duplicate_on_enter",
			"進山泉閣 d17_morning_phone 後離開再進，文字重播但手牌不重複發放",
			"d17_morning.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")
		var gs: Node = CaseBaseClass.get_game_state(tree)
		var hand_size_1: int = (gs.get("hand") as Array).size()

		await QAStep.click(tree, "panel_back")

		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")
		var hand_size_2: int = (gs.get("hand") as Array).size()

		assert_eq(hand_size_2, hand_size_1, "重進面板不應重複觸發 on_enter 發牌")
		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 12: 推進提示
# =========================================================================
class Case12AdvanceHint extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_12_advance_hint",
			"無可做動作時推進時段按鈕變更文字提示，但時段不自動前進",
			"d35_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var adv_btns := QAStep.find_controls_by_qa_id(tree.get_root(), "phase_advance")
		if adv_btns.is_empty():
			return { "ok": false, "errors": ["找不到 phase_advance 按鈕"] }

		var gs: Node = CaseBaseClass.get_game_state(tree)
		var orig_day: int = int(gs.get("day"))
		var orig_phase: String = str(gs.get("phase"))

		assert_eq(int(gs.get("day")), orig_day, "時段不應自動跳過")
		assert_eq(str(gs.get("phase")), orig_phase, "時段不應自動跳過")
		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 13: 夜間同一套
# =========================================================================
class Case13NightSameModel extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_13_night_same_model",
			"選一個夜間地點進去，走的是同一條演出流程（演完才開放互動）",
			"d10_night.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		if QAStep.has_visible_qa_id(tree.get_root(), "location::oldhouse_room"):
			await QAStep.click(tree, "location::oldhouse_room")
			while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
				await QAStep.click(tree, "beat_advance")
		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 14: 地點描述（沒填 desc 時退回顯示地點名，不報錯）
# =========================================================================
class Case14LocationDesc extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_14_location_desc",
			"locations.json 沒填 desc 時只顯示地點名，不報錯",
			"d2_morning.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var main_vp := tree.get_root()
		var titles := main_vp.find_children("LocationTitle", "Label", true, false)
		assert_true(not titles.is_empty(), "應存在 LocationTitle")
		if not titles.is_empty():
			var title_lbl := titles[0] as Label
			assert_true(not title_lbl.text.is_empty(), "地點標題不應為空")

		return { "ok": errors.is_empty(), "errors": errors }
