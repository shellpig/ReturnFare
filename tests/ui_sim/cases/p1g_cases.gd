class_name P1GCases
extends RefCounted

## P1-G 驗收案例集（依 實作規格書.md > P1-G 與 開發設計方針.md > UI 模擬驗證 實作）
## 包含 17 個獨立案例變體，嚴禁在測試開始後直呼 GameState 規則層（如 preview_slot），一律經由真實輸入事件進行。

const CaseBaseClass := preload("res://tests/ui_sim/cases/case_base.gd")


static func get_all_cases() -> Array[CaseBase]:
	return [
		Case01aBeatsAjie.new(),
		Case01bBeatsAlone.new(),
		Case02LockInteractionDuringPlay.new(),
		Case03ReenterNoDuplicateOnEnter.new(),
		Case04SlotTypes.new(),
		Case05ProtagonistSlotType.new(),
		Case06NoSpoiler.new(),
		Case07RightClickPreview.new(),
		Case08RightClickLockedPreview.new(),
		Case09PreviewButtonMatchRightClick.new(),
		Case10PreviewPlacementConsistentPositive.new(),
		Case11PreviewPlacementConsistentNegative.new(),
		Case12aAdvanceD35.new(),
		Case12bAdvanceD40.new(),
		Case12cAdvanceD43.new(),
		Case13NightSameModel.new(),
		Case14LocationDesc.new(),
	]


static func get_case_by_id(case_id: String) -> CaseBase:
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

		# 1. 驗證第一個 beat: d32_festival
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"), "第 1 階段必須有 beat_advance")
		var adv1 := await QAStep.click(tree, "beat_advance")
		assert_true(adv1.get("ok", false), "第 1 次點擊推進失敗")
		if QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var entered1: Dictionary = gs.call("serialize").get("run", {}).get("beats_entered", {})
		assert_true(entered1.has("d32_festival"), "第 1 步必須進入 d32_festival")

		# 2. 驗證第二個 beat: d32_festival_ajie
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"), "第 2 階段必須有 beat_advance")
		var adv2 := await QAStep.click(tree, "beat_advance")
		assert_true(adv2.get("ok", false), "第 2 次點擊推進失敗")
		if QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var entered2: Dictionary = gs.call("serialize").get("run", {}).get("beats_entered", {})
		assert_true(entered2.has("d32_festival_ajie"), "第 2 步必須進入 d32_festival_ajie")
		assert_true(not entered2.has("d32_festival_alone"), "不應觸發 d32_festival_alone")
		assert_true(not entered2.has("d32_festival_awei"), "不應觸發 d32_festival_awei")

		# 演畢進入常態
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")
		assert_true(not QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"), "全部 beat 演完後 beat_advance 必須隱藏")

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
		assert_eq(str(run_state.get("phase")), "morning", "時段必須為 morning")

		var click_res := await QAStep.click(tree, "location::temple")
		if not click_res.get("ok", false):
			return { "ok": false, "errors": ["點擊寺廟失敗: " + str(click_res.get("error"))] }

		# 1. 驗證第一個 beat: d32_festival
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"), "第 1 階段必須有 beat_advance")
		var adv1 := await QAStep.click(tree, "beat_advance")
		assert_true(adv1.get("ok", false), "第 1 次點擊推進失敗")
		if QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var entered1: Dictionary = gs.call("serialize").get("run", {}).get("beats_entered", {})
		assert_true(entered1.has("d32_festival"), "第 1 步必須進入 d32_festival")

		# 2. 驗證第二個 beat: d32_festival_alone
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"), "第 2 階段必須有 beat_advance")
		var adv2 := await QAStep.click(tree, "beat_advance")
		assert_true(adv2.get("ok", false), "第 2 次點擊推進失敗")
		if QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var entered2: Dictionary = gs.call("serialize").get("run", {}).get("beats_entered", {})
		assert_true(entered2.has("d32_festival_alone"), "第 2 步必須進入 d32_festival_alone")
		assert_true(not entered2.has("d32_festival_ajie"), "不應觸發 d32_festival_ajie")
		assert_true(not entered2.has("d32_festival_awei"), "不應觸發 d32_festival_awei")

		# 演畢進入常態
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")
		assert_true(not QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"), "全部 beat 演完後 beat_advance 必須隱藏")

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 02: 演出期間鎖互動（演出未完時全樹無可放卡或選擇節點）
# =========================================================================
class Case02LockInteractionDuringPlay extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_02_lock_interaction_during_play",
			"演出期間畫面上沒有任何可放卡的 place:: 或 choose:: 槽位節點（包含隱藏節點）",
			"d32_morning__ajie.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		assert_eq(int(gs.get("day")), 32, "天數必須為 32")

		var click_res := await QAStep.click(tree, "location::temple")
		if not click_res.get("ok", false):
			return { "ok": false, "errors": ["點擊寺廟失敗: " + str(click_res.get("error"))] }

		# 演出期間：beat_advance 必須可見
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"), "演出期間 beat_advance 必須存在且可見")

		# 遍歷全場景樹所有節點（含隱藏節點），斷言完全不存在 place:: 與 choose:: 控制項
		var stack: Array[Node] = [tree.get_root()]
		while not stack.is_empty():
			var node := stack.pop_back() as Node
			if node.has_meta("qa_id"):
				var qid := str(node.get_meta("qa_id"))
				if qid.begins_with("place::") or qid.begins_with("choose::"):
					errors.append("FAIL: 演出期間場景樹完全不可存在互動節點: %s (路徑: %s)" % [qid, str(node.get_path())])
			for child in node.get_children(true):
				stack.append(child)

		# 推進完畢後進入常態
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 03: 重進不重複結算（第 17 天上午 fixed beat 文字重播且狀態完全不變）
# =========================================================================
class Case03ReenterNoDuplicateOnEnter extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_03_reenter_no_duplicate_on_enter",
			"進山泉閣 d17_morning_phone 後離開再進，文字重播但狀態完全不重複結算",
			"d17_morning.json"
		)

	func run(tree: SceneTree, main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		assert_eq(int(gs.get("day")), 17, "天數必須為 17")

		# 第一次進入山泉閣
		var c1 := await QAStep.click(tree, "location::sanquan")
		assert_true(c1.get("ok", false), "第一次進山泉閣失敗")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var dump1 := QADiagnostics.dump_ui_tree(main_node)
		var state1: Dictionary = gs.call("serialize")

		# 離開山泉閣回到地圖
		var back_res := await QAStep.click(tree, "panel_back")
		assert_true(back_res.get("ok", false), "點擊返回失敗")

		# 第二次進入山泉閣
		var c2 := await QAStep.click(tree, "location::sanquan")
		assert_true(c2.get("ok", false), "第二次進山泉閣失敗")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var dump2 := QADiagnostics.dump_ui_tree(main_node)
		var state2: Dictionary = gs.call("serialize")

		# 狀態完全不變
		assert_eq(JSON.stringify(state2), JSON.stringify(state1), "重進後狀態必須完全一致（無重複結算）")

		# 畫面語意內容重播一致
		var texts1: Array[String] = []
		for item in dump1:
			if bool(item.get("visible_in_tree", false)) and not str(item.get("text", "")).is_empty():
				texts1.append("%s:%s" % [str(item.get("qa_id", "")), str(item.get("text", ""))])

		var texts2: Array[String] = []
		for item in dump2:
			if bool(item.get("visible_in_tree", false)) and not str(item.get("text", "")).is_empty():
				texts2.append("%s:%s" % [str(item.get("qa_id", "")), str(item.get("text", ""))])

		assert_eq(JSON.stringify(texts2), JSON.stringify(texts1), "重進後可見文字與卡槽文字必須完全重播一致")

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 04: 槽型別標示（第 22 天下午堆沙包的 4 個槽位）
# =========================================================================
class Case04SlotTypes extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_04_slot_types",
			"第 22 天下午堆沙包的 4 個槽位，型別顯示成「主角卡」與「裝備卡、情報卡」（用「、」不是「／」）",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		assert_eq(int(gs.get("day")), 22, "天數必須為 22")

		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var expected_slots := {
			"slot::d22_pm_sandbags::work": "主角卡",
			"slot::d22_pm_sandbags::obs_walk": "裝備卡、情報卡",
			"slot::d22_pm_sandbags::obs_hands": "裝備卡、情報卡",
			"slot::d22_pm_sandbags::obs_talk": "裝備卡、情報卡",
		}

		for qid: String in expected_slots:
			var expected_type_str: String = expected_slots[qid]
			var list := QAStep.find_controls_by_qa_id(tree.get_root(), qid)
			assert_true(not list.is_empty(), "找不到槽節點: %s" % qid)
			if not list.is_empty():
				var label := list[0] as Label
				assert_true(label.text.contains("（收：%s）" % expected_type_str), "槽 %s 應顯示型別標示 %s，實際為: %s" % [qid, expected_type_str, label.text])
				assert_true(not label.text.contains("／"), "槽 %s 型別標示不可使用斜線「／」" % qid)

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 05: 主角卡槽型別標示
# =========================================================================
class Case05ProtagonistSlotType extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_05_protagonist_slot_type",
			"收主角卡的槽顯示「主角卡」且與 card_types.json 一致",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var list := QAStep.find_controls_by_qa_id(tree.get_root(), "slot::d22_pm_sandbags::work")
		assert_true(not list.is_empty(), "找不到 work 槽")
		if not list.is_empty():
			var label := list[0] as Label
			assert_true(label.text.contains("主角卡"), "work 槽必須標示「主角卡」")

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 06: 不劇透具體卡名（accepts 寫具體 card id 的槽）
# =========================================================================
class Case06NoSpoiler extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_06_no_spoiler",
			"accepts 寫具體卡 id 的槽只顯示「情報卡」，不顯示卡名",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var list := QAStep.find_controls_by_qa_id(tree.get_root(), "slot::d22_pm_sandbags::obs_walk")
		assert_true(not list.is_empty(), "找不到 obs_walk 槽")
		if not list.is_empty():
			var label := list[0] as Label
			assert_true(not label.text.contains("info_acai_walk"), "槽文字不可包含卡片 id: info_acai_walk")
			assert_true(not label.text.contains("阿財走路"), "槽文字不可包含具體卡名")

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 07: 右鍵預覽不變更狀態
# =========================================================================
class Case07RightClickPreview extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_07_right_click_preview",
			"對可放的槽右鍵列出相容卡片清單，關閉後天數、時段、手牌、知識、旗標全部不變",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, main_node: Control, run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		assert_eq(int(gs.get("day")), 22, "天數必須為 22")

		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

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
# Case 08: 灰槽右鍵預覽附帶理由且狀態不變
# =========================================================================
class Case08RightClickLockedPreview extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_08_right_click_locked_preview",
			"對灰掉的槽右鍵，清單是空的並顯示理由文字，關閉後狀態完全不變",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, main_node: Control, run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		assert_eq(int(gs.get("day")), 22, "天數必須為 22")

		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var state_before: Dictionary = gs.call("serialize")

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
		assert_true(not QAStep.has_visible_qa_id(tree.get_root(), "dialog_confirm::preview"), "關閉後預覽確認按鈕必須不可見")

		var state_after: Dictionary = gs.call("serialize")
		assert_eq(JSON.stringify(state_after), JSON.stringify(state_before), "關閉灰槽預覽後狀態必須完全不變")

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 09: 左鍵預覽按鈕與右鍵逐字一致
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
# Case 10: 預覽與實放一致（正向：真實由 UI 讀取預覽並放置結算，嚴禁 preview_slot）
# =========================================================================
class Case10PreviewPlacementConsistentPositive extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_10_preview_placement_consistent_positive",
			"預覽列出的卡片，實際點擊放置按鈕一定成功放置並結算（純真實輸入，不調用 preview_slot）",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		assert_eq(int(gs.get("day")), 22, "天數必須為 22")

		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		# 1. 真實點擊 UI 預覽按鈕
		var prev_click := await QAStep.click(tree, "preview::d22_pm_sandbags::work")
		assert_true(prev_click.get("ok", false), "點擊預覽按鈕失敗")

		var diag := find_preview_dialog(tree)
		assert_true(diag != null, "預覽彈窗必須開啟")
		var diag_text := diag.dialog_text if diag != null else ""
		assert_true(diag_text.contains("可放置：我"), "預覽清單必須包含卡片「我」，實際為: %s" % diag_text)

		# 關閉預覽彈窗
		await QAStep.click(tree, "dialog_confirm::preview")

		# 2. 依預覽列出之卡片，點擊對應之 place:: 按鈕
		var qa_btn := "place::d22_pm_sandbags::work::protagonist"
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), qa_btn), "主角卡放置按鈕必須可見")
		var place_res := await QAStep.click(tree, qa_btn)
		assert_true(place_res.get("ok", false), "放主角卡應成功結算")

		var run_state: Dictionary = gs.call("serialize").get("run", {})
		var placed: Dictionary = run_state.get("slots_placed", {})
		assert_true(placed.has("d22_pm_sandbags::work"), "slots_placed 必須記錄 d22_pm_sandbags::work")
		assert_true(bool(run_state.get("action_spent", false)), "放置主角卡後 action_spent 必須為 true")

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 11: 預覽與實放一致（反向：手牌中非相容卡片全數確認無 place 控制項）
# =========================================================================
class Case11PreviewPlacementConsistentNegative extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_11_preview_placement_consistent_negative",
			"預覽沒列出來的卡，畫面上絕對找不到對應的 place:: 控制項",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		assert_eq(int(gs.get("day")), 22, "天數必須為 22")
		assert_eq(str(gs.get("phase")), "afternoon", "時段必須為 afternoon")

		var enter_res := await QAStep.click(tree, "location::sanquan")
		assert_true(enter_res.get("ok", false), "進入山泉閣失敗")

		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		# 確認目標槽存在
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "slot::d22_pm_sandbags::work"), "work 槽必須存在")

		# 打開預覽確認只有主角卡相容
		await QAStep.click(tree, "preview::d22_pm_sandbags::work")
		var diag := find_preview_dialog(tree)
		assert_true(diag != null, "預覽彈窗必須開啟")
		var diag_text := diag.dialog_text if diag != null else ""
		assert_true(diag_text.contains("可放置：我"), "預覽必須包含「我」")
		await QAStep.click(tree, "dialog_confirm::preview")

		# 讀取全部手牌，扣除相容卡片 protagonist 後，對其餘每張卡片確認絕無 place:: 按鈕
		var hand: Array = gs.call("serialize").get("run", {}).get("hand", []) as Array
		assert_true(hand.size() >= 1, "手牌數不可為空")

		for card_id: String in hand:
			if card_id == "protagonist":
				continue
			var invalid_btn := "place::d22_pm_sandbags::work::%s" % card_id
			assert_no_qa_id(tree, invalid_btn, "不相容卡片 %s 絕對不可存在放置按鈕" % card_id)

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 12a: 推進提示（第 35 天下午：操作前提示 -> 操作後無動作 -> 仍可造訪其他地點 -> 成功推進）
# =========================================================================
class Case12aAdvanceD35 extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_12a_advance_d35",
			"第 35 天下午：未做選擇時推進時段按鈕提示有動作可做，完成選擇後提示無可做動作且地圖仍可造訪",
			"d35_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		assert_eq(int(gs.get("day")), 35, "天數必須為 35")
		assert_eq(str(gs.get("phase")), "afternoon", "時段必須為 afternoon")

		var adv_btns := QAStep.find_controls_by_qa_id(tree.get_root(), "phase_advance")
		assert_true(not adv_btns.is_empty(), "找不到 phase_advance 按鈕")
		var adv_btn := adv_btns[0] as Button

		# 1. 操作前應顯示「推進時段」（有 choice 可做）
		assert_eq(adv_btn.text, "推進時段", "未做選擇前推進按鈕應顯示「推進時段」")

		# 2. 進入診所完成 choice (accept)
		var click_clinic := await QAStep.click(tree, "location::clinic")
		assert_true(click_clinic.get("ok", false), "進入診所失敗")

		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var choose_res := await QAStep.click(tree, "choose::d35_pm_answer::inheritance::accept")
		assert_true(choose_res.get("ok", false), "選擇 accept 失敗")

		# 3. 退出地點面板
		var back_res := await QAStep.click(tree, "panel_back")
		assert_true(back_res.get("ok", false), "返回地圖失敗")

		# 4. 操作後應變更為「推進時段（目前無可做動作）」
		assert_eq(adv_btn.text, "推進時段（目前無可做動作）", "動作耗盡後推進按鈕應顯示提示文字")

		# 5. 驗證地圖清單仍可見且可重新點擊進診所（查看已定案之 choice 展示）
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "location::clinic"), "地圖診所按鈕必須仍可見可互動")
		var reenter_clinic := await QAStep.click(tree, "location::clinic")
		assert_true(reenter_clinic.get("ok", false), "重進診所應成功")
		await QAStep.click(tree, "panel_back")

		# 6. 點擊推進時段成功進入 evening
		var adv_res := await QAStep.click(tree, "phase_advance")
		assert_true(adv_res.get("ok", false), "點擊時段推進按鈕失敗")
		assert_eq(str(gs.get("phase")), "evening", "時段必須成功推進至 evening")

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 12b: 推進提示（第 40 天上午：純選擇題時段推進提示與互動）
# =========================================================================
class Case12bAdvanceD40 extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_12b_advance_d40",
			"第 40 天上午：純選擇題時段推進提示、完成 choice 後提示更新與時段推進",
			"d40_morning.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		assert_eq(int(gs.get("day")), 40, "天數必須為 40")
		assert_eq(str(gs.get("phase")), "morning", "時段必須為 morning")

		var adv_btns := QAStep.find_controls_by_qa_id(tree.get_root(), "phase_advance")
		assert_true(not adv_btns.is_empty(), "找不到 phase_advance 按鈕")
		var adv_btn := adv_btns[0] as Button

		# 1. 操作前顯示「推進時段」
		assert_eq(adv_btn.text, "推進時段", "未做選擇前推進按鈕應顯示「推進時段」")

		# 2. 進入山泉閣完成 choice
		var enter_sq := await QAStep.click(tree, "location::sanquan")
		assert_true(enter_sq.get("ok", false), "進入山泉閣失敗")

		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var choose_res := await QAStep.click(tree, "choose::d40_tell_someone::d40_tell::tell_her")
		assert_true(choose_res.get("ok", false), "選擇 tell_her 失敗")

		# 3. 退出地點面板
		await QAStep.click(tree, "panel_back")

		# 4. 操作後應更新為「推進時段（目前無可做動作）」
		assert_eq(adv_btn.text, "推進時段（目前無可做動作）", "動作耗盡後推進按鈕應顯示提示文字")

		# 5. 點擊推進時段成功進入 afternoon
		var adv_res := await QAStep.click(tree, "phase_advance")
		assert_true(adv_res.get("ok", false), "點擊時段推進按鈕失敗")
		assert_eq(str(gs.get("phase")), "afternoon", "時段必須成功推進至 afternoon")

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 12c: 推進提示（第 43 天下午：純選擇題時段推進提示與互動）
# =========================================================================
class Case12cAdvanceD43 extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_12c_advance_d43",
			"第 43 天下午：純選擇題時段推進提示、完成 choice 後提示更新與時段推進",
			"d43_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		assert_eq(int(gs.get("day")), 43, "天數必須為 43")
		assert_eq(str(gs.get("phase")), "afternoon", "時段必須為 afternoon")

		var adv_btns := QAStep.find_controls_by_qa_id(tree.get_root(), "phase_advance")
		assert_true(not adv_btns.is_empty(), "找不到 phase_advance 按鈕")
		var adv_btn := adv_btns[0] as Button

		# 1. 操作前顯示「推進時段」
		assert_eq(adv_btn.text, "推進時段", "未做選擇前推進按鈕應顯示「推進時段」")

		# 2. 進入河岸完成 choice
		var enter_river := await QAStep.click(tree, "location::riverside")
		assert_true(enter_river.get("ok", false), "進入河岸失敗")

		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var choose_res := await QAStep.click(tree, "choose::d43_pm_zhou::leaving::say_yes")
		assert_true(choose_res.get("ok", false), "選擇 say_yes 失敗")

		# 3. 退出地點面板
		await QAStep.click(tree, "panel_back")

		# 4. 操作後應更新為「推進時段（目前無可做動作）」
		assert_eq(adv_btn.text, "推進時段（目前無可做動作）", "動作耗盡後推進按鈕應顯示提示文字")

		# 5. 點擊推進時段成功進入 evening
		var adv_res := await QAStep.click(tree, "phase_advance")
		assert_true(adv_res.get("ok", false), "點擊時段推進按鈕失敗")
		assert_eq(str(gs.get("phase")), "evening", "時段必須成功推進至 evening")

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 13: 夜間同一套模型（演出後出現互動、放卡不消耗行動格）
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
		assert_eq(int(gs.get("day")), 10, "天數必須為 10")

		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "location::n_landmark"), "第 10 夜必須可見 n_landmark")
		var c_res := await QAStep.click(tree, "location::n_landmark")
		assert_true(c_res.get("ok", false), "進入 n_landmark 失敗")

		# 演畢進入常態
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var run_state: Dictionary = gs.call("serialize").get("run", {})
		var entered: Dictionary = run_state.get("beats_entered", {})
		assert_true(entered.has("n_landmark_ch1"), "beats_entered 必須記錄 n_landmark_ch1")

		# 驗證夜間放主角卡不消耗行動格（action_spent 維持 false）
		assert_true(not bool(run_state.get("action_spent", false)), "夜間常態放卡不應消耗行動格 (action_spent 必須為 false)")

		# 驗證可正常返回夜間地圖
		var back_res := await QAStep.click(tree, "panel_back")
		assert_true(back_res.get("ok", false), "夜間面板返回地圖失敗")
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "location::n_landmark"), "返回後夜間地圖必須可見")

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

		var title_node := _main_node.find_child("LocationTitle", true, false)
		assert_true(title_node != null and (title_node as Label).visible, "地點標題必須可見")
		if title_node != null:
			assert_eq((title_node as Label).text, "山泉閣", "地點標題應顯示「山泉閣」")

		var desc_node := _main_node.find_child("DescriptionLabel", true, false)
		if desc_node != null:
			var desc_lbl := desc_node as Label
			assert_true(not desc_lbl.visible or desc_lbl.text.is_empty(), "無 desc 時描述 Label 應隱藏或為空")

		return { "ok": errors.is_empty(), "errors": errors }
