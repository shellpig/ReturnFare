class_name QAStep
extends RefCounted

## UI 模擬單步輸入 Helper（依 開發設計方針.md > 固定輸入流程 實作）。
## 案例一律透過此 helper 進行互動，嚴禁自訂 timer 或呼叫 pressed.emit()。

const QADiagnosticsClass := preload("res://tests/ui_sim/qa_diagnostics.gd")

static var _interim_enabled := false
static var _interim_tree: SceneTree
static var _interim_root: Node
static var _interim_run_dir := ""
static var _interim_case_id := ""
static var _interim_step := 0
static var _interim_failures: Array[String] = []


static func begin_interim_capture(tree: SceneTree, root: Node, run_dir: String, case_id: String) -> void:
	_interim_enabled = true
	_interim_tree = tree
	_interim_root = root
	_interim_run_dir = run_dir
	_interim_case_id = case_id
	_interim_step = 0
	_interim_failures.clear()


static func end_interim_capture() -> void:
	_interim_enabled = false
	_interim_tree = null
	_interim_root = null
	_interim_run_dir = ""
	_interim_case_id = ""
	_interim_step = 0


static func get_interim_failures() -> Array[String]:
	return _interim_failures.duplicate()


## 依 qa_id 遞迴搜尋所有 Control 節點（支援 internal 節點與萬用字元）
static func find_controls_by_qa_id(root: Node, qa_id_pattern: String) -> Array[Control]:
	var results: Array[Control] = []
	_search_qa_id_recursive(root, qa_id_pattern, results)
	return results


static func _search_qa_id_recursive(node: Node, qa_id_pattern: String, results: Array[Control]) -> void:
	if node is Control:
		var ctrl := node as Control
		if ctrl.has_meta("qa_id"):
			var qid := str(ctrl.get_meta("qa_id"))
			if _matches_pattern(qid, qa_id_pattern):
				results.append(ctrl)
	for child in node.get_children(true):
		_search_qa_id_recursive(child, qa_id_pattern, results)


static func _matches_pattern(str_val: String, pattern: String) -> bool:
	if pattern == str_val:
		return true
	if pattern.ends_with("*"):
		var prefix := pattern.substr(0, pattern.length() - 1)
		return str_val.begins_with(prefix)
	return false


static func find_controls_by_qa_id_prefix(root: Node, prefix: String) -> Array[Control]:
	var results: Array[Control] = []
	_search_qa_id_prefix_recursive(root, prefix, results)
	return results


static func _search_qa_id_prefix_recursive(node: Node, prefix: String, results: Array[Control]) -> void:
	if node is Control:
		var ctrl := node as Control
		if ctrl.has_meta("qa_id"):
			var qid := str(ctrl.get_meta("qa_id"))
			if qid.begins_with(prefix):
				results.append(ctrl)
	for child in node.get_children(true):
		_search_qa_id_prefix_recursive(child, prefix, results)


static func find_controls_by_name(root: Node, node_name: String) -> Array[Control]:
	var results: Array[Control] = []
	_search_name_recursive(root, node_name, results)
	return results


static func _search_name_recursive(node: Node, node_name: String, results: Array[Control]) -> void:
	if node is Control and node.name == node_name:
		results.append(node as Control)
	for child in node.get_children(true):
		_search_name_recursive(child, node_name, results)


## 檢查特定 qa_id 是否存在於畫面上且可見
static func has_visible_qa_id(root: Node, qa_id: String) -> bool:
	var list := find_controls_by_qa_id(root, qa_id)
	for ctrl in list:
		if ctrl.is_visible_in_tree():
			return true
	return false


## 執行固定 9 步真實輸入模擬流程（含子視窗座標轉換、Hover 命中核驗與邊界防呆）
static func click(
	tree: SceneTree,
	qa_id: String,
	button_index: MouseButton = MOUSE_BUTTON_LEFT,
	expected_disabled: bool = false
) -> Dictionary:
	var result := {
		"ok": false,
		"qa_id": qa_id,
		"target_path": "",
		"target_pos": Vector2.ZERO,
		"hovered_before": {},
		"hovered_after": {},
		"error": "",
	}

	# 1. 搜尋特定 qa_id 之 Control
	var root := tree.get_root()
	var candidates := find_controls_by_qa_id(root, qa_id)

	if candidates.is_empty():
		result["error"] = "找不到 qa_id: %s (命中數 0)" % qa_id
		return result

	if candidates.size() > 1:
		result["error"] = "qa_id: %s 違反唯一性契約 (全樹命中數 %d，包含隱藏)" % [qa_id, candidates.size()]
		return result

	var visible_candidates: Array[Control] = []
	for c in candidates:
		if c.is_visible_in_tree():
			visible_candidates.append(c)

	if visible_candidates.is_empty():
		result["error"] = "qa_id: %s 存在但不可見 (is_visible_in_tree 為 false)" % qa_id
		return result

	var target := visible_candidates[0]
	result["target_path"] = str(target.get_path())

	# 2. 檢查 disabled 狀態
	if target is BaseButton:
		var btn := target as BaseButton
		if btn.disabled != expected_disabled:
			result["error"] = "按鈕 disabled 狀態與預期不符 (實際: %s, 預期: %s)" % [str(btn.disabled), str(expected_disabled)]
			return result

	# 2.5 若目標位於 ScrollContainer 內，送真實滾輪事件捲動至可視範圍（嚴禁呼叫
	# ensure_control_visible() 這種程式化 API 捷徑，那不是玩家能做的輸入，會掩蓋
	# 捲軸被停用、目標捲不到等真實故障）
	var p_scroll: Node = target.get_parent()
	while p_scroll != null:
		if p_scroll is ScrollContainer:
			var scroll_res := await scroll_into_view(tree, p_scroll as ScrollContainer, target)
			if not scroll_res.get("ok", false):
				result["error"] = "捲動至可視範圍失敗: %s" % str(scroll_res.get("error"))
				return result
		p_scroll = p_scroll.get_parent()
	await wait_draw_frames(tree, 2)

	# 3. 計算螢幕/視口真實中心點與子視窗轉換
	var target_vp := target.get_viewport()
	var screen_pos: Vector2 = target.get_screen_position()
	var rect_size: Vector2 = target.size
	if rect_size.x <= 0 or rect_size.y <= 0:
		rect_size = target.get_global_rect().size

	if rect_size.x <= 0 or rect_size.y <= 0:
		result["error"] = "目標元件尺寸為 0 (size: %s)" % str(rect_size)
		return result

	var screen_center: Vector2 = screen_pos + rect_size * 0.5
	result["target_pos"] = screen_center

	# 邊界檢查：中心點必須落在主視口範圍內 (1280x720)
	var root_rect := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	if not root_rect.has_point(screen_center):
		result["error"] = "目標中心點越界 (點: %s, 視口: %s)" % [str(screen_center), str(root_rect.size)]
		return result

	# 4. 送 InputEventMouseMotion 並等候 2 幀更新 Hover 狀態
	var motion := InputEventMouseMotion.new()
	motion.position = screen_center
	motion.global_position = screen_center
	Input.parse_input_event(motion)
	await wait_draw_frames(tree, 2)

	# 5. 核驗 Hover 命中：目標所屬 Viewport 實際 Hover 之 Control 必須為目標或其子孫
	var hovered: Control = target_vp.gui_get_hovered_control()
	result["hovered_before"] = _control_info(hovered)

	var hit_ok := false
	if hovered == target or (hovered != null and target.is_ancestor_of(hovered)):
		hit_ok = true
	else:
		# 重試一次滑鼠移動事件並等待 2 幀以應對佈局剛更新之情況
		Input.parse_input_event(motion)
		await wait_draw_frames(tree, 2)
		hovered = target_vp.gui_get_hovered_control()
		result["hovered_before"] = _control_info(hovered)
		if hovered == target or (hovered != null and target.is_ancestor_of(hovered)):
			hit_ok = true

	if not hit_ok:
		var hovered_name: String = str(hovered.name) if hovered != null else "null"
		var hovered_path: String = str(hovered.get_path()) if hovered != null else "none"
		var hovered_qa: String = str(hovered.get_meta("qa_id")) if hovered != null and hovered.has_meta("qa_id") else ""
		result["error"] = "Hover 未命中目標 (預期: %s [%s], 實際: %s [%s, qa_id=%s], pos=%s)" % [
			target.name, str(target.get_path()), hovered_name, hovered_path, hovered_qa, str(screen_center)
		]
		return result

	# 6. 送 InputEventMouseButton (pressed = true)
	var press_event := InputEventMouseButton.new()
	press_event.button_index = button_index
	press_event.pressed = true
	press_event.position = screen_center
	press_event.global_position = screen_center
	Input.parse_input_event(press_event)
	await wait_draw_frames(tree, 2)

	# 7. 送 InputEventMouseButton (pressed = false)
	var release_event := InputEventMouseButton.new()
	release_event.button_index = button_index
	release_event.pressed = false
	release_event.position = screen_center
	release_event.global_position = screen_center
	Input.parse_input_event(release_event)
	await wait_draw_frames(tree, 2)

	# 8. 紀錄點擊後 Hover 狀態
	var hovered_after: Control = target_vp.gui_get_hovered_control()
	result["hovered_after"] = _control_info(hovered_after)
	result["ok"] = true

	# 9. 額外等候 2 幀讓狀態變更與 UI 重繪完全就緒
	await wait_draw_frames(tree, 2)

	# 每一次真實輸入都做一次中途幾何擷取。案例尾端的診斷無法捕捉
	# AcceptDialog、演出中面板與其他一閃即逝的畫面。
	if _interim_enabled and _interim_tree == tree:
		_interim_step += 1
		var stage := "step_%04d" % _interim_step
		var capture_res := await QADiagnosticsClass.capture_interim_state(
			tree, _interim_root, _interim_run_dir, _interim_case_id, stage
		)
		if not bool(capture_res.get("ok", false)):
			_interim_failures.append("中途畫面擷取失敗 [%s]" % stage)
		else:
			var geometry: Dictionary = capture_res.get("geometry", {}) as Dictionary
			if not bool(geometry.get("ok", false)):
				_interim_failures.append("中途畫面幾何診斷失敗 [%s]: %s" % [stage, JSON.stringify(geometry)])

	return result


## 送出真實滑鼠滾輪事件，將 target 捲入 scroll_container 的可視範圍。
## 每一輪都重新量測 target 相對可視範圍的位置，直到完全（或捲到底後盡量）可見，
## 或達到步數上限。捲動已到極限（位置連兩輪不再移動）但目標仍不可見時視為失敗，
## 讓呼叫端拿到明確錯誤，而不是悄悄放行一個玩家實際上摸不到的目標。
static func scroll_into_view(tree: SceneTree, scroll_container: ScrollContainer, target: Control, max_ticks: int = 60) -> Dictionary:
	var result := { "ok": false, "ticks": 0, "error": "" }

	var sc_rect := scroll_container.get_global_rect()
	if sc_rect.size.x <= 0 or sc_rect.size.y <= 0:
		result["error"] = "ScrollContainer 尺寸為 0，無法定位滾輪事件座標"
		return result
	var wheel_pos: Vector2 = sc_rect.position + sc_rect.size * 0.5

	var motion := InputEventMouseMotion.new()
	motion.position = wheel_pos
	motion.global_position = wheel_pos
	Input.parse_input_event(motion)
	await wait_draw_frames(tree, 1)

	var last_target_y := INF
	for i in range(max_ticks):
		var visible_rect := QADiagnostics.get_effective_visible_rect(scroll_container)
		var target_rect := target.get_global_rect()
		var visible_h: float = visible_rect.intersection(target_rect).size.y

		if visible_h >= min(target_rect.size.y, visible_rect.size.y) - 1.0:
			result["ok"] = true
			result["ticks"] = i
			return result

		if is_equal_approx(target_rect.position.y, last_target_y):
			# 捲動已到極限（位置不再變化），目標仍未進入可視範圍即判失敗
			result["ok"] = visible_h > 0.0
			result["ticks"] = i
			if not result["ok"]:
				result["error"] = "捲動已到極限，目標仍不在可視範圍內"
			return result
		last_target_y = target_rect.position.y

		var button_index: int = MOUSE_BUTTON_WHEEL_UP if target_rect.position.y < visible_rect.position.y else MOUSE_BUTTON_WHEEL_DOWN

		var press := InputEventMouseButton.new()
		press.button_index = button_index
		press.pressed = true
		press.position = wheel_pos
		press.global_position = wheel_pos
		Input.parse_input_event(press)
		var release := InputEventMouseButton.new()
		release.button_index = button_index
		release.pressed = false
		release.position = wheel_pos
		release.global_position = wheel_pos
		Input.parse_input_event(release)
		# Container 的重新排版是 queue_sort() 延遲處理，1 幀不一定夠讓捲動後的
		# 新位置真正落地；等不夠幀會在下一輪誤讀到舊座標，被「位置沒變」的
		# 收斂判斷誤認成捲動已到底而提早失敗。全檔其餘輸入步驟統一等 2 幀，這裡跟著對齊。
		await wait_draw_frames(tree, 2)

	result["error"] = "捲動 %d 次仍未能將目標捲入可視範圍" % max_ticks
	return result


## 推進演出佇列直到 beat_advance 消失，遇到第一個點擊失敗立即返回，並設步數上限，
## 避免案例在演出卡住時無限迴圈到 launcher timeout 才被發現，只得到「逾時」而非
## 命中診斷。
static func drain_beats(tree: SceneTree, max_steps: int = 20) -> Dictionary:
	var steps := 0
	while has_visible_qa_id(tree.get_root(), "beat_advance"):
		if steps >= max_steps:
			return { "ok": false, "steps": steps, "error": "beat_advance 推進次數超過上限 (%d)，疑似無限迴圈" % max_steps }
		var click_res := await click(tree, "beat_advance")
		if not click_res.get("ok", false):
			return { "ok": false, "steps": steps, "error": "第 %d 次推進失敗: %s" % [steps + 1, str(click_res.get("error"))] }
		steps += 1
	return { "ok": true, "steps": steps, "error": "" }


## 等待指定次數的 frame_post_draw
static func wait_draw_frames(tree: SceneTree, count: int = 1) -> void:
	for i in range(count):
		await RenderingServer.frame_post_draw
		await tree.process_frame


## 取得 Control 診斷摘要資訊
static func _control_info(ctrl: Control) -> Dictionary:
	if ctrl == null:
		return { "path": "", "name": "", "qa_id": "", "type": "" }
	return {
		"path": str(ctrl.get_path()),
		"name": ctrl.name,
		"qa_id": str(ctrl.get_meta("qa_id")) if ctrl.has_meta("qa_id") else "",
		"type": ctrl.get_class(),
	}


## 診斷當前 root viewport hover 之節點
static func get_hovered_info(tree: SceneTree) -> Dictionary:
	var vp := tree.get_root()
	var hovered: Control = vp.gui_get_hovered_control()
	return _control_info(hovered)
