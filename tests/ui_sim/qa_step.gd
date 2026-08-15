class_name QAStep
extends RefCounted

## UI 模擬單步輸入 Helper（寫死在 開發設計方針.md > 固定輸入流程）。
## 案例一律透過此 helper 進行互動，嚴禁自訂 timer 或呼叫 pressed.emit()。


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


## 檢查特定 qa_id 是否存在於畫面上且可見
static func has_visible_qa_id(root: Node, qa_id: String) -> bool:
	var list := find_controls_by_qa_id(root, qa_id)
	for ctrl in list:
		if ctrl.is_visible_in_tree():
			return true
	return false


## 執行固定 9 步輸入模擬流程
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

	# 驗證唯一性
	if candidates.is_empty():
		result["error"] = "找不到 qa_id: %s (命中數 0)" % qa_id
		return result

	var visible_candidates: Array[Control] = []
	for c in candidates:
		if c.is_visible_in_tree():
			visible_candidates.append(c)

	if visible_candidates.is_empty():
		result["error"] = "qa_id: %s 存在但不可見 (is_visible_in_tree 為 false)" % qa_id
		return result

	if visible_candidates.size() > 1:
		result["error"] = "qa_id: %s 違反唯一性契約 (可見命中數 %d)" % [qa_id, visible_candidates.size()]
		return result

	var target := visible_candidates[0]
	result["target_path"] = str(target.get_path())

	# 2. 檢查 disabled 狀態
	if target is BaseButton:
		var btn := target as BaseButton
		if btn.disabled != expected_disabled:
			result["error"] = "按鈕 disabled 狀態與預期不符 (實際: %s, 預期: %s)" % [str(btn.disabled), str(expected_disabled)]
			return result

	# 3. 計算中心點並送 InputEventMouseMotion
	var rect := target.get_global_rect()
	var center := rect.position + rect.size * 0.5
	result["target_pos"] = center

	var motion := InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	Input.parse_input_event(motion)

	# 4. 送 InputEventMouseButton (pressed = true)
	var press_event := InputEventMouseButton.new()
	press_event.button_index = button_index
	press_event.pressed = true
	press_event.position = center
	press_event.global_position = center
	Input.parse_input_event(press_event)

	# 5. 等一次 frame_post_draw
	await wait_draw_frames(tree, 1)

	# 6. 送 InputEventMouseButton (pressed = false)
	var release_event := InputEventMouseButton.new()
	release_event.button_index = button_index
	release_event.pressed = false
	release_event.position = center
	release_event.global_position = center
	Input.parse_input_event(release_event)

	# 7. 等兩次 frame_post_draw
	await wait_draw_frames(tree, 2)

	# 8. 成功完成點擊
	result["ok"] = true
	return result


## 等待指定次數的 frame_post_draw
static func wait_draw_frames(tree: SceneTree, count: int = 1) -> void:
	for i in range(count):
		await RenderingServer.frame_post_draw
		await tree.process_frame


## 診斷當前 hover 之節點
static func get_hovered_info(tree: SceneTree) -> Dictionary:
	var vp := tree.get_root()
	var hovered: Control = vp.gui_get_hovered_control()
	if hovered == null:
		return { "path": "", "qa_id": "", "type": "" }
	return {
		"path": str(hovered.get_path()),
		"qa_id": str(hovered.get_meta("qa_id")) if hovered.has_meta("qa_id") else "",
		"type": hovered.get_class(),
	}
