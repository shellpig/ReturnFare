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
			"第 32 天上午寺廟（邀阿婕）：進門零狀態修改，點擊推進逐一結算 d32_festival 與 d32_festival_ajie",
			"d32_morning__ajie.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		var run_state: Dictionary = gs.call("serialize").get("run", {})
		assert_eq(int(run_state.get("day", 1)), 32, "天數必須為 32")
		assert_eq(str(run_state.get("phase", "")), "morning", "時段必須為 morning")

		var initial_count: int = (run_state.get("beats_entered", {}) as Dictionary).size()

		var click_res := await QAStep.click(tree, "location::temple")
		if not click_res.get("ok", false):
			return { "ok": false, "errors": ["點擊寺廟失敗: " + str(click_res.get("error"))] }

		# 1. 進入寺廟時僅建立演出佇列，零狀態修改 (beats_entered 數量不變)
		var entered0: Dictionary = gs.call("serialize").get("run", {}).get("beats_entered", {})
		assert_eq(entered0.size(), initial_count, "進入地點時不得直接結算 beat，beats_entered 數量必須不變")
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"), "第 1 階段必須顯示繼續演出按鈕")

		# 2. 第 1 次點擊推進按鈕 -> 結算第 1 個 beat: d32_festival
		var adv1 := await QAStep.click(tree, "beat_advance")
		assert_true(adv1.get("ok", false), "第 1 次點擊推進失敗: " + str(adv1.get("error")))

		var entered1: Dictionary = gs.call("serialize").get("run", {}).get("beats_entered", {})
		assert_true(entered1.has("d32_festival"), "第 1 次推進後必須進入 d32_festival")
		assert_eq(entered1.size(), initial_count + 1, "第 1 次推進後 beats_entered 數量必須恰 +1")
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"), "第 2 階段必須仍顯示繼續演出按鈕")

		# 3. 第 2 次點擊推進按鈕 -> 結算第 2 個 beat: d32_festival_ajie
		var adv2 := await QAStep.click(tree, "beat_advance")
		assert_true(adv2.get("ok", false), "第 2 次點擊推進失敗: " + str(adv2.get("error")))

		var entered2: Dictionary = gs.call("serialize").get("run", {}).get("beats_entered", {})
		assert_true(entered2.has("d32_festival_ajie"), "第 2 次推進後必須進入 d32_festival_ajie")
		assert_eq(entered2.size(), initial_count + 2, "第 2 次推進後 beats_entered 數量必須恰 +2")
		assert_true(not entered2.has("d32_festival_alone"), "不應觸發 d32_festival_alone")
		assert_true(not entered2.has("d32_festival_awei"), "不應觸發 d32_festival_awei")

		# 4. 第 3 次點擊推進按鈕 -> 演畢進入常態畫面，推進按鈕隱藏
		if QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			var adv3 := await QAStep.click(tree, "beat_advance")
			assert_true(adv3.get("ok", false), "第 3 次點擊推進失敗: " + str(adv3.get("error")))

		assert_true(not QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"), "全部 beat 演完後 beat_advance 必須隱藏")

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 01b: 演出逐一（未邀人分支：d32_festival -> d32_festival_alone）
# =========================================================================
class Case01bBeatsAlone extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_01b_beats_alone",
			"第 32 天上午寺廟（無邀請）：進門零狀態修改，點擊推進逐一結算 d32_festival 與 d32_festival_alone",
			"d32_morning__none.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		var run_state: Dictionary = gs.call("serialize").get("run", {})
		assert_eq(int(run_state.get("day", 1)), 32, "天數必須為 32")
		assert_eq(str(run_state.get("phase", "")), "morning", "時段必須為 morning")

		var initial_count: int = (run_state.get("beats_entered", {}) as Dictionary).size()

		var click_res := await QAStep.click(tree, "location::temple")
		if not click_res.get("ok", false):
			return { "ok": false, "errors": ["點擊寺廟失敗: " + str(click_res.get("error"))] }

		# 1. 進入寺廟時僅建立演出佇列，零狀態修改 (beats_entered 數量不變)
		var entered0: Dictionary = gs.call("serialize").get("run", {}).get("beats_entered", {})
		assert_eq(entered0.size(), initial_count, "進入地點時不得直接結算 beat，beats_entered 數量必須不變")
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"), "第 1 階段必須顯示繼續演出按鈕")

		# 2. 第 1 次點擊推進按鈕 -> 結算第 1 個 beat: d32_festival
		var adv1 := await QAStep.click(tree, "beat_advance")
		assert_true(adv1.get("ok", false), "第 1 次點擊推進失敗: " + str(adv1.get("error")))

		var entered1: Dictionary = gs.call("serialize").get("run", {}).get("beats_entered", {})
		assert_true(entered1.has("d32_festival"), "第 1 次推進後必須進入 d32_festival")
		assert_eq(entered1.size(), initial_count + 1, "第 1 次推進後 beats_entered 數量必須恰 +1")
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"), "第 2 階段必須仍顯示繼續演出按鈕")

		# 3. 第 2 次點擊推進按鈕 -> 結算第 2 個 beat: d32_festival_alone
		var adv2 := await QAStep.click(tree, "beat_advance")
		assert_true(adv2.get("ok", false), "第 2 次點擊推進失敗: " + str(adv2.get("error")))

		var entered2: Dictionary = gs.call("serialize").get("run", {}).get("beats_entered", {})
		assert_true(entered2.has("d32_festival_alone"), "第 2 次推進後必須進入 d32_festival_alone")
		assert_eq(entered2.size(), initial_count + 2, "第 2 次推進後 beats_entered 數量必須恰 +2")
		assert_true(not entered2.has("d32_festival_ajie"), "不應觸發 d32_festival_ajie")
		assert_true(not entered2.has("d32_festival_awei"), "不應觸發 d32_festival_awei")

		# 4. 第 3 次點擊推進按鈕 -> 演畢進入常態畫面，推進按鈕隱藏
		if QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			var adv3 := await QAStep.click(tree, "beat_advance")
			assert_true(adv3.get("ok", false), "第 3 次點擊推進失敗: " + str(adv3.get("error")))

		assert_true(not QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"), "全部 beat 演完後 beat_advance 必須隱藏")

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 02: 演出中鎖定互動
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
		var run_state: Dictionary = gs.call("serialize").get("run", {})
		assert_eq(int(run_state.get("day", 1)), 32, "天數必須為 32")

		await QAStep.click(tree, "location::temple")

		# 演出期間：在全樹範圍檢查
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"), "演出期間必須顯示繼續演出按鈕")

		var forbidden_prefixes: Array[String] = ["place::", "choose::"]
		for node in _collect_all_nodes(tree.get_root()):
			if node.has_meta("qa_id"):
				var qid := str(node.get_meta("qa_id"))
				for pfx in forbidden_prefixes:
					if qid.begins_with(pfx):
						assert_true(false, "演出期間場景樹不得存在槽位互動節點: %s (路徑: %s)" % [qid, str(node.get_path())])

		# 演畢進入常態
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		return { "ok": errors.is_empty(), "errors": errors }

	static func _collect_all_nodes(node: Node) -> Array[Node]:
		var res: Array[Node] = [node]
		for child in node.get_children(true):
			res.append_array(_collect_all_nodes(child))
		return res


# =========================================================================
# Case 03: 重進不重複結算 on_enter
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
		var run_state: Dictionary = gs.call("serialize").get("run", {})
		assert_eq(int(run_state.get("day", 1)), 17, "天數必須為 17")

		# 第一次進入山泉閣
		var c1 := await QAStep.click(tree, "location::sanquan")
		assert_true(c1.get("ok", false), "第一次進山泉閣失敗: " + str(c1.get("error")))
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var dump1 := QADiagnostics.dump_ui_tree(main_node)
		var state1: Dictionary = gs.call("serialize")

		# 離開山泉閣回到地圖
		var back_res := await QAStep.click(tree, "panel_back")
		assert_true(back_res.get("ok", false), "點擊返回失敗: " + str(back_res.get("error")))

		# 第二次進入山泉閣
		var c2 := await QAStep.click(tree, "location::sanquan")
		assert_true(c2.get("ok", false), "第二次進山泉閣失敗: " + str(c2.get("error")))
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
# Case 04: 槽型別標示（全 4 觀察槽位與工作槽型別名正確標示）
# =========================================================================
class Case04SlotTypes extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_04_slot_types",
			"第 22 天下午山泉閣 4 個觀察槽與工作槽型別標示均正確",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		var run_state: Dictionary = gs.call("serialize").get("run", {})
		assert_eq(int(run_state.get("day", 1)), 22, "天數必須為 22")
		assert_eq(str(run_state.get("phase", "")), "afternoon", "時段必須為 afternoon")

		var click_res := await QAStep.click(tree, "location::sanquan")
		assert_true(click_res.get("ok", false), "進山泉閣失敗: " + str(click_res.get("error")))
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var expected_markers: Dictionary = {
			"slot::d22_pm_sandbags::work": "主角卡",
			"slot::d22_pm_sandbags::obs_walk": "裝備卡、情報卡",
			"slot::d22_pm_sandbags::obs_hands": "裝備卡、情報卡",
			"slot::d22_pm_sandbags::obs_talk": "裝備卡、情報卡",
			"slot::d22_pm_sandbags::dismiss": "裝備卡、情報卡",
		}

		for qid: String in expected_markers.keys():
			var marker: String = expected_markers[qid]
			var controls := QAStep.find_controls_by_qa_id(tree.get_root(), qid)
			assert_true(not controls.is_empty(), "找不到槽標籤: %s" % qid)
			if not controls.is_empty():
				var label := controls[0] as Label
				assert_true(label != null and label.text.contains(marker), "槽位 %s 必須包含型別標示 [%s]，實際為: %s" % [qid, marker, label.text if label != null else "null"])

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 05: 主角槽型別標示
# =========================================================================
class Case05ProtagonistSlotType extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_05_protagonist_slot_type",
			"第 22 天下午山泉閣 work 槽常駐標示「主角卡」",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		var run_state: Dictionary = gs.call("serialize").get("run", {})
		assert_eq(int(run_state.get("day", 1)), 22, "天數必須為 22")

		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var controls := QAStep.find_controls_by_qa_id(tree.get_root(), "slot::d22_pm_sandbags::work")
		assert_true(not controls.is_empty(), "找不到 work 槽")
		if not controls.is_empty():
			var label := controls[0] as Label
			assert_true(label != null and label.text.contains("主角卡"), "work 槽標籤必須包含「主角卡」")

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 06: 不劇透特定卡
# =========================================================================
class Case06NoSpoiler extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_06_no_spoiler",
			"第 22 天下午山泉閣 obs_walk 槽僅標示「裝備卡、情報卡」，不洩漏 accepts 清單具體卡名",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		var run_state: Dictionary = gs.call("serialize").get("run", {})
		assert_eq(int(run_state.get("day", 1)), 22, "天數必須為 22")

		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var controls := QAStep.find_controls_by_qa_id(tree.get_root(), "slot::d22_pm_sandbags::obs_walk")
		assert_true(not controls.is_empty(), "找不到 obs_walk 槽")
		if not controls.is_empty():
			var label := controls[0] as Label
			var t := label.text if label != null else ""
			assert_true(t.contains("裝備卡") and t.contains("情報卡"), "槽位必須標示概括型別「裝備卡、情報卡」")
			# 嚴格防劇透檢查：accepts 包含 equip_polaroid (夫妻留下的拍立得) 與 info_acai_box (阿財說裡面沒什麼)
			assert_true(not t.contains("夫妻留下的拍立得"), "槽標籤不得洩漏「夫妻留下的拍立得」")
			assert_true(not t.contains("拍立得"), "槽標籤不得洩漏「拍立得」")
			assert_true(not t.contains("阿財說裡面沒什麼"), "槽標籤不得洩漏「阿財說裡面沒什麼」")
			assert_true(not t.contains("阿財的紙箱"), "槽標籤不得洩漏「阿財的紙箱」")
			assert_true(not t.contains("equip_polaroid"), "槽標籤不得洩漏卡片 ID equip_polaroid")
			assert_true(not t.contains("info_acai_box"), "槽標籤不得洩漏卡片 ID info_acai_box")

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 07: 右鍵預覽（右鍵點擊槽叫出彈窗，狀態完全不變）
# =========================================================================
class Case07RightClickPreview extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_07_right_click_preview",
			"右鍵點擊可放卡槽叫出預覽彈窗，GameState 逐欄位不變，確認後彈窗關閉",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, main_node: Control, run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		var run_state: Dictionary = gs.call("serialize").get("run", {})
		assert_eq(int(run_state.get("day", 1)), 22, "天數必須為 22")

		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var state_before: Dictionary = gs.call("serialize")

		# 右鍵點擊槽位 Label 呼叫預覽
		var rclick_res := await QAStep.click(tree, "slot::d22_pm_sandbags::work", MOUSE_BUTTON_RIGHT)
		assert_true(rclick_res.get("ok", false), "右鍵點擊槽失敗: " + str(rclick_res.get("error")))

		# 擷取彈窗開啟之中途狀態並確認成功
		var cap_ok := await QADiagnostics.capture_interim_state(tree, main_node, run_dir, id, "dialog_open")
		assert_true(cap_ok, "中途截圖與 Dump 必須寫入成功")

		var diag := find_preview_dialog(tree)
		assert_true(diag != null, "預覽彈窗必須開啟")
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "dialog_confirm::preview"), "彈窗確認按鈕必須可見")

		# 狀態完全不變
		assert_eq(JSON.stringify(gs.call("serialize")), JSON.stringify(state_before), "開啟預覽彈窗後 GameState 必須完全不變")

		# 點擊確認按鈕關閉彈窗
		var close_res := await QAStep.click(tree, "dialog_confirm::preview")
		assert_true(close_res.get("ok", false), "點擊彈窗確認按鈕失敗: " + str(close_res.get("error")))
		assert_false(QAStep.has_visible_qa_id(tree.get_root(), "dialog_confirm::preview"), "彈窗確認按鈕必須已不可見")

		assert_eq(JSON.stringify(gs.call("serialize")), JSON.stringify(state_before), "關閉預覽彈窗後 GameState 必須完全不變")
		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 08: 右鍵鎖定槽預覽附理由（點擊真正的 LOCKED 槽位 obs_hands）
# =========================================================================
class Case08RightClickLockedPreview extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_08_right_click_locked_preview",
			"右鍵點擊 LOCKED 槽位 obs_hands 預覽顯示鎖定理由，關閉後狀態不變",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, main_node: Control, run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		var run_state: Dictionary = gs.call("serialize").get("run", {})
		assert_eq(int(run_state.get("day", 1)), 22, "天數必須為 22")

		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var state_before: Dictionary = gs.call("serialize")

		# 右鍵點擊真正的 LOCKED 槽: obs_hands (理由: （你沒有真的跟他遞過幾次東西。）)
		var rclick_res := await QAStep.click(tree, "slot::d22_pm_sandbags::obs_hands", MOUSE_BUTTON_RIGHT)
		assert_true(rclick_res.get("ok", false), "右鍵點擊 LOCKED 槽失敗: " + str(rclick_res.get("error")))

		var cap_ok := await QADiagnostics.capture_interim_state(tree, main_node, run_dir, id, "dialog_open")
		assert_true(cap_ok, "中途截圖與 Dump 必須寫入成功")

		var diag := find_preview_dialog(tree)
		assert_true(diag != null, "預覽彈窗必須開啟")
		var diag_text := diag.dialog_text if diag != null else ""
		assert_true(diag_text.contains("你沒有真的跟他遞過幾次東西"), "LOCKED 預覽彈窗必須精確顯示 reject_reason，實際為: %s" % diag_text)
		assert_true(not diag_text.contains("我"), "LOCKED 預覽清單不得包含可放卡片")
		assert_true(not diag_text.contains("卡片類型不符"), "不可使用通用缺卡理由代替特定鎖定理由")

		# 點擊確認按鈕關閉彈窗
		var close_res := await QAStep.click(tree, "dialog_confirm::preview")
		assert_true(close_res.get("ok", false), "點擊彈窗確認按鈕失敗: " + str(close_res.get("error")))
		assert_false(QAStep.has_visible_qa_id(tree.get_root(), "dialog_confirm::preview"), "彈窗確認按鈕必須已不可見")

		assert_eq(JSON.stringify(gs.call("serialize")), JSON.stringify(state_before), "關閉預覽彈窗後 GameState 必須完全不變")
		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 09: 預覽按鈕與右鍵逐字相符
# =========================================================================
class Case09PreviewButtonMatchRightClick extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_09_preview_button_match_right_click",
			"觸控/按鈕預覽與右鍵預覽彈窗內容逐字完全相同",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		var run_state: Dictionary = gs.call("serialize").get("run", {})
		assert_eq(int(run_state.get("day", 1)), 22, "天數必須為 22")

		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		# 1. 點擊預覽按鈕
		var btn_click := await QAStep.click(tree, "preview::d22_pm_sandbags::work")
		assert_true(btn_click.get("ok", false), "點擊預覽按鈕失敗: " + str(btn_click.get("error")))
		var diag_btn := find_preview_dialog(tree)
		assert_true(diag_btn != null, "按鈕預覽未開啟彈窗")
		var text_btn := diag_btn.dialog_text if diag_btn != null else ""
		assert_true(not text_btn.is_empty(), "預覽彈窗文字不可為空")
		await QAStep.click(tree, "dialog_confirm::preview")

		# 2. 右鍵點擊槽 Label
		var r_click := await QAStep.click(tree, "slot::d22_pm_sandbags::work", MOUSE_BUTTON_RIGHT)
		assert_true(r_click.get("ok", false), "右鍵點擊槽失敗: " + str(r_click.get("error")))
		var diag_rclick := find_preview_dialog(tree)
		assert_true(diag_rclick != null, "右鍵預覽未開啟彈窗")
		var text_rclick := diag_rclick.dialog_text if diag_rclick != null else ""
		assert_true(not text_rclick.is_empty(), "右鍵預覽彈窗文字不可為空")
		await QAStep.click(tree, "dialog_confirm::preview")

		assert_eq(text_btn, text_rclick, "按鈕預覽與右鍵預覽內容應逐字相同")
		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 10: 預覽與實放一致（正向：結構化 metadata 解析預覽集合＝可放按鈕集合，實放結算）
# =========================================================================
class Case10PreviewPlacementConsistentPositive extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_10_preview_placement_consistent_positive",
			"預覽集合＝可放按鈕集合，點擊放置按鈕成功結算",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		var run_state: Dictionary = gs.call("serialize").get("run", {})
		assert_eq(int(run_state.get("day", 1)), 22, "天數必須為 22")

		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		# 1. 真實點擊 UI 預覽按鈕
		var prev_click := await QAStep.click(tree, "preview::d22_pm_sandbags::work")
		assert_true(prev_click.get("ok", false), "點擊預覽按鈕失敗: " + str(prev_click.get("error")))

		var diag := find_preview_dialog(tree)
		assert_true(diag != null, "預覽彈窗必須開啟")
		var preview_meta: Array = diag.get_meta("preview_card_ids", []) as Array if diag != null else []
		var previewed_cards: Array[String] = []
		for c in preview_meta:
			previewed_cards.append(str(c))
		await QAStep.click(tree, "dialog_confirm::preview")

		assert_true(not previewed_cards.is_empty(), "預覽可放卡片集合不可為空")

		# 2. 解析畫面上實際存在的 place 按鈕集合
		var button_cards: Array[String] = []
		var prefix := "place::d22_pm_sandbags::work::"
		for ctrl in QAStep.find_controls_by_qa_id_prefix(tree.get_root(), prefix):
			if ctrl.has_meta("qa_id"):
				var qid := str(ctrl.get_meta("qa_id"))
				button_cards.append(qid.substr(prefix.length()))

		previewed_cards.sort()
		button_cards.sort()
		assert_eq(JSON.stringify(button_cards), JSON.stringify(previewed_cards), "預覽卡片集合必須與畫面上可放按鈕集合完全一致")

		# 3. 真實點擊放置按鈕
		for card_id in previewed_cards:
			var place_btn_qid := "place::d22_pm_sandbags::work::" + card_id
			var place_res := await QAStep.click(tree, place_btn_qid)
			assert_true(place_res.get("ok", false), "點擊放置按鈕失敗: %s (%s)" % [place_btn_qid, str(place_res.get("error"))])

		# 4. 斷言 slots_placed 與 action_spent 結算
		var state_after: Dictionary = gs.call("serialize").get("run", {})
		var slots_placed: Dictionary = state_after.get("slots_placed", {})
		assert_true(slots_placed.has("d22_pm_sandbags::work"), "slots_placed 必須記錄 d22_pm_sandbags::work")
		assert_true(bool(state_after.get("action_spent", false)), "白天放置主角卡後 action_spent 必須為 true")

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 11: 預覽與實放一致（負向：嚴格手牌差集，無可放按鈕）
# =========================================================================
class Case11PreviewPlacementConsistentNegative extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_11_preview_placement_consistent_negative",
			"預覽沒列出來的手牌卡片，畫面上絕對找不到對應的 place:: 控制項",
			"d22_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		var run_state: Dictionary = gs.call("serialize").get("run", {})
		assert_eq(int(run_state.get("day", 1)), 22, "天數必須為 22")
		assert_eq(str(run_state.get("phase", "")), "afternoon", "時段必須為 afternoon")

		var click_res := await QAStep.click(tree, "location::sanquan")
		if not click_res.get("ok", false):
			return { "ok": false, "errors": ["點擊山泉閣失敗: " + str(click_res.get("error"))] }

		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		# 1. 確認 work 槽存在
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "slot::d22_pm_sandbags::work"), "work 槽必須存在")

		# 2. 取得預覽可放卡片集合
		var prev_click := await QAStep.click(tree, "preview::d22_pm_sandbags::work")
		assert_true(prev_click.get("ok", false), "點擊預覽按鈕失敗: " + str(prev_click.get("error")))
		var diag := find_preview_dialog(tree)
		assert_true(diag != null, "預覽彈窗必須開啟")
		var preview_meta: Array = diag.get_meta("preview_card_ids", []) as Array if diag != null else []
		var compatible_cards: Array[String] = []
		for c in preview_meta:
			compatible_cards.append(str(c))
		await QAStep.click(tree, "dialog_confirm::preview")

		assert_true(compatible_cards.has("protagonist"), "預覽必須包含「我」")

		# 3. 取得手牌全部卡片，扣除 compatible_cards
		var hand_cards: Array = run_state.get("hand", []) as Array
		assert_true(not hand_cards.is_empty(), "手牌不可為空")

		var incompatible_cards: Array[String] = []
		for card_val in hand_cards:
			var cid := str(card_val)
			if not compatible_cards.has(cid) and not incompatible_cards.has(cid):
				incompatible_cards.append(cid)

		assert_true(not incompatible_cards.is_empty(), "手牌必須包含不可放於 work 槽的卡片")

		# 4. 對每張不可放卡片，確認場景樹絕對不存在對應 place 按鈕
		for bad_card in incompatible_cards:
			var bad_qa_id := "place::d22_pm_sandbags::work::" + bad_card
			assert_no_qa_id(tree, bad_qa_id, "不相容卡片 %s 絕對不得出現放置按鈕" % bad_card)

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 12a: 推進提示（第 35 天下午：純選擇題時段推進提示與重進/逛街）
# =========================================================================
class Case12aAdvanceD35 extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_12a_advance_d35",
			"第 35 天下午：純選擇題時段推進提示、完成 choice 後提示更新與時段推進",
			"d35_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		var run_state: Dictionary = gs.call("serialize").get("run", {})
		assert_eq(int(run_state.get("day", 1)), 35, "天數必須為 35")
		assert_eq(str(run_state.get("phase", "")), "afternoon", "時段必須為 afternoon")

		var adv_btns := QAStep.find_controls_by_qa_id(tree.get_root(), "phase_advance")
		assert_true(not adv_btns.is_empty(), "找不到 phase_advance 按鈕")
		var adv_btn := adv_btns[0] as Button

		# 1. 操作前應顯示「推進時段」（有 choice 可做）
		assert_eq(adv_btn.text, "推進時段", "未做選擇前推進按鈕應顯示「推進時段」")

		# 2. 進入診所完成 choice (accept)
		var click_clinic := await QAStep.click(tree, "location::clinic")
		assert_true(click_clinic.get("ok", false), "進入診所失敗: " + str(click_clinic.get("error")))

		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var choose_res := await QAStep.click(tree, "choose::d35_pm_answer::inheritance::accept")
		assert_true(choose_res.get("ok", false), "選擇 accept 失敗: " + str(choose_res.get("error")))

		# 3. 退出地點面板回到地圖
		var back_res := await QAStep.click(tree, "panel_back")
		assert_true(back_res.get("ok", false), "返回地圖失敗: " + str(back_res.get("error")))

		# 4. 操作後應變更為「推進時段（目前無可做動作）」
		assert_eq(adv_btn.text, "推進時段（目前無可做動作）", "動作耗盡後推進按鈕應顯示提示文字")

		# 5. 驗證地圖清單仍可見且可重新點擊進診所（查看已定案之 choice 展示），天數與時段不變
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "location::clinic"), "地圖診所按鈕必須仍可見可互動")
		var reenter_clinic := await QAStep.click(tree, "location::clinic")
		assert_true(reenter_clinic.get("ok", false), "重進診所應成功: " + str(reenter_clinic.get("error")))
		var s_mid: Dictionary = gs.call("serialize").get("run", {})
		assert_eq(int(s_mid.get("day", 1)), 35, "重進地點天數不變")
		assert_eq(str(s_mid.get("phase", "")), "afternoon", "重進地點時段不變")
		await QAStep.click(tree, "panel_back")

		# 6. 點擊推進時段成功進入 evening
		var adv_res := await QAStep.click(tree, "phase_advance")
		assert_true(adv_res.get("ok", false), "點擊時段推進按鈕失敗: " + str(adv_res.get("error")))
		var s_after: Dictionary = gs.call("serialize").get("run", {})
		assert_eq(str(s_after.get("phase", "")), "evening", "時段必須成功推進至 evening")

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 12b: 推進提示（第 40 天上午：純選擇題時段推進提示與逛其他地點）
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
		var run_state: Dictionary = gs.call("serialize").get("run", {})
		assert_eq(int(run_state.get("day", 1)), 40, "天數必須為 40")
		assert_eq(str(run_state.get("phase", "")), "morning", "時段必須為 morning")

		var adv_btns := QAStep.find_controls_by_qa_id(tree.get_root(), "phase_advance")
		assert_true(not adv_btns.is_empty(), "找不到 phase_advance 按鈕")
		var adv_btn := adv_btns[0] as Button

		# 1. 操作前顯示「推進時段」
		assert_eq(adv_btn.text, "推進時段", "未做選擇前推進按鈕應顯示「推進時段」")

		# 2. 進入山泉閣完成 choice
		var click_sq := await QAStep.click(tree, "location::sanquan")
		assert_true(click_sq.get("ok", false), "進入山泉閣失敗: " + str(click_sq.get("error")))

		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var choose_res := await QAStep.click(tree, "choose::d40_tell_someone::d40_tell::tell_her")
		assert_true(choose_res.get("ok", false), "選擇 tell_her 失敗: " + str(choose_res.get("error")))

		# 3. 退出地點面板回到地圖
		var back_res := await QAStep.click(tree, "panel_back")
		assert_true(back_res.get("ok", false), "返回地圖失敗: " + str(back_res.get("error")))

		# 4. 操作後應變更為「推進時段（目前無可做動作）」
		assert_eq(adv_btn.text, "推進時段（目前無可做動作）", "動作耗盡後推進按鈕應顯示提示文字")

		# 5. 驗證地圖清單仍可重新進入山泉閣查看展示，天數與時段不變
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "location::sanquan"), "地圖山泉閣按鈕必須仍可見可互動")
		var reenter_sq := await QAStep.click(tree, "location::sanquan")
		assert_true(reenter_sq.get("ok", false), "重進山泉閣應成功: " + str(reenter_sq.get("error")))
		var s_mid: Dictionary = gs.call("serialize").get("run", {})
		assert_eq(int(s_mid.get("day", 1)), 40, "重進地點天數不變")
		assert_eq(str(s_mid.get("phase", "")), "morning", "重進地點時段不變")
		await QAStep.click(tree, "panel_back")

		# 6. 點擊推進時段成功進入 afternoon
		var adv_res := await QAStep.click(tree, "phase_advance")
		assert_true(adv_res.get("ok", false), "點擊時段推進按鈕失敗: " + str(adv_res.get("error")))
		var s_after: Dictionary = gs.call("serialize").get("run", {})
		assert_eq(str(s_after.get("phase", "")), "afternoon", "時段必須成功推進至 afternoon")

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 12c: 推進提示（第 43 天下午：純選擇題時段推進提示、走去其他地點 sanquan 與時段推進）
# =========================================================================
class Case12cAdvanceD43 extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_12c_advance_d43",
			"第 43 天下午：完成 riverside choice 後提示更新，可繼續走去別的地點 sanquan，時段不自動推進",
			"d43_afternoon.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		var run_state: Dictionary = gs.call("serialize").get("run", {})
		assert_eq(int(run_state.get("day", 1)), 43, "天數必須為 43")
		assert_eq(str(run_state.get("phase", "")), "afternoon", "時段必須為 afternoon")

		var adv_btns := QAStep.find_controls_by_qa_id(tree.get_root(), "phase_advance")
		assert_true(not adv_btns.is_empty(), "找不到 phase_advance 按鈕")
		var adv_btn := adv_btns[0] as Button

		# 1. 操作前顯示「推進時段」
		assert_eq(adv_btn.text, "推進時段", "未做選擇前推進按鈕應顯示「推進時段」")

		# 2. 進入河邊完成 choice
		var click_riv := await QAStep.click(tree, "location::riverside")
		assert_true(click_riv.get("ok", false), "進入河邊失敗: " + str(click_riv.get("error")))

		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		var choose_res := await QAStep.click(tree, "choose::d43_pm_zhou::leaving::say_yes")
		assert_true(choose_res.get("ok", false), "選擇 say_yes 失敗: " + str(choose_res.get("error")))

		# 3. 退出地點面板回到地圖
		var back_res := await QAStep.click(tree, "panel_back")
		assert_true(back_res.get("ok", false), "返回地圖失敗: " + str(back_res.get("error")))

		# 4. 此時山泉閣仍有未結算之 choice (theory)，因此時段推進按鈕仍應保持「推進時段」
		assert_eq(adv_btn.text, "推進時段", "城鎮中仍有其他地點 choice 未完成時，推進按鈕仍應保持「推進時段」")

		# 5. 走去別的地點：驗證地圖清單上的另一個可用地點山泉閣 (sanquan) 仍可進入，天數與時段不變
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "location::sanquan"), "地圖山泉閣按鈕必須仍可見可互動")
		var enter_sq := await QAStep.click(tree, "location::sanquan")
		assert_true(enter_sq.get("ok", false), "走去別的地點（山泉閣）應成功: " + str(enter_sq.get("error")))
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		# 完成山泉閣的 choice (theory_exchange)
		var choose_sq := await QAStep.click(tree, "choose::d43_conclusion::theory::theory_exchange")
		assert_true(choose_sq.get("ok", false), "選擇 theory_exchange 失敗: " + str(choose_sq.get("error")))

		var s_mid: Dictionary = gs.call("serialize").get("run", {})
		assert_eq(int(s_mid.get("day", 1)), 43, "走去別的地點後天數不變")
		assert_eq(str(s_mid.get("phase", "")), "afternoon", "走去別的地點後時段不變")
		await QAStep.click(tree, "panel_back")

		# 6. 全鎮所有地點動作與 choice 均耗盡後，按鈕變更為「推進時段（目前無可做動作）」
		assert_eq(adv_btn.text, "推進時段（目前無可做動作）", "所有地點 choice 耗盡後推進按鈕應顯示提示文字")

		# 7. 點擊推進時段成功進入 evening
		var adv_res := await QAStep.click(tree, "phase_advance")
		assert_true(adv_res.get("ok", false), "點擊時段推進按鈕失敗: " + str(adv_res.get("error")))
		var s_after: Dictionary = gs.call("serialize").get("run", {})
		assert_eq(str(s_after.get("phase", "")), "evening", "時段必須成功推進至 evening")

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 13: 夜間同一互動模型（夜間演完 beat 開放常態互動，實質放卡且不耗行動）
# =========================================================================
class Case13NightSameModel extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_13_night_same_model",
			"第 10 夜進入 n_landmark，演完 beat 後開放常態互動，實質放卡且不耗行動",
			"d10_night.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		var run_state: Dictionary = gs.call("serialize").get("run", {})
		assert_eq(int(run_state.get("day", 1)), 10, "天數必須為 10")
		assert_eq(str(run_state.get("phase", "")), "night", "時段必須為 night")

		# 點進夜間地標地點
		var click_res := await QAStep.click(tree, "location::n_landmark")
		assert_true(click_res.get("ok", false), "進入 n_landmark 失敗: " + str(click_res.get("error")))

		# 演出固定 beat
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		# 演畢進入常態畫面，確認槽位可見
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "slot::n_take_something::take"), "夜間常態槽位 take 必須呈現")

		# 實質點擊放置主角卡
		var place_qid := "place::n_take_something::take::protagonist"
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), place_qid), "夜間放置按鈕必須可見")
		var place_res := await QAStep.click(tree, place_qid)
		assert_true(place_res.get("ok", false), "夜間放置主角卡失敗: " + str(place_res.get("error")))

		# 斷言結算：slots_placed 記錄、旗標設定，且 action_spent 仍為 false
		var s_after: Dictionary = gs.call("serialize").get("run", {})
		var slots_placed: Dictionary = s_after.get("slots_placed", {})
		assert_true(slots_placed.has("n_take_something::take"), "slots_placed 必須記錄 n_take_something::take")
		var flags: Dictionary = s_after.get("flags", {})
		assert_true(bool(flags.get("took_from_night", false)), "旗標 took_from_night 必須為 true")
		assert_false(bool(s_after.get("action_spent", false)), "夜間放卡絕不消耗行動格 (action_spent 必須為 false)")

		# 驗證可正常返回夜間地圖
		var back_res := await QAStep.click(tree, "panel_back")
		assert_true(back_res.get("ok", false), "夜間返回地圖失敗: " + str(back_res.get("error")))
		assert_true(QAStep.has_visible_qa_id(tree.get_root(), "location::n_landmark"), "返回夜間地圖後地標按鈕必須可見")

		return { "ok": errors.is_empty(), "errors": errors }


# =========================================================================
# Case 14: 地點描述文字缺欄位 fallback
# =========================================================================
class Case14LocationDesc extends CaseBaseClass:
	func _init() -> void:
		super._init(
			"p1g_case_14_location_desc",
			"locations.json 缺 desc 時正常顯示地點名稱且畫面無錯誤",
			"d2_morning.json"
		)

	func run(tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
		var gs := CaseBaseClass.get_game_state(tree)
		var run_state: Dictionary = gs.call("serialize").get("run", {})
		assert_eq(int(run_state.get("day", 1)), 2, "天數必須為 2")

		# 第 2 天上午進山泉閣
		await QAStep.click(tree, "location::sanquan")
		while QAStep.has_visible_qa_id(tree.get_root(), "beat_advance"):
			await QAStep.click(tree, "beat_advance")

		# 驗證地點名稱正確顯示
		var title_controls := QAStep.find_controls_by_name(tree.get_root(), "LocationTitle")
		assert_true(not title_controls.is_empty(), "找不到 LocationTitle")
		if not title_controls.is_empty():
			var title_lbl := title_controls[0] as Label
			assert_eq(title_lbl.text, "山泉閣", "LocationTitle 必須為「山泉閣」")

		return { "ok": errors.is_empty(), "errors": errors }
