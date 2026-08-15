class_name QADiagnostics
extends RefCounted

## UI 模擬幾何診斷與 UI Dump Helper（依 開發設計方針.md > 矩形診斷 實作）。


## 產生全 UI 樹 Dump
static func dump_ui_tree(root: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_dump_node_recursive(root, result)
	return result


static func _dump_node_recursive(node: Node, list: Array[Dictionary]) -> void:
	if node is Control:
		var ctrl := node as Control
		var entry := {
			"name": ctrl.name,
			"path": str(ctrl.get_path()),
			"class": ctrl.get_class(),
			"visible": ctrl.visible,
			"visible_in_tree": ctrl.is_visible_in_tree(),
			"rect": {
				"x": ctrl.get_global_rect().position.x,
				"y": ctrl.get_global_rect().position.y,
				"w": ctrl.get_global_rect().size.x,
				"h": ctrl.get_global_rect().size.y,
			},
			"qa_id": str(ctrl.get_meta("qa_id")) if ctrl.has_meta("qa_id") else "",
		}
		if ctrl is Label:
			entry["text"] = (ctrl as Label).text
		elif ctrl is Button:
			entry["text"] = (ctrl as Button).text
			entry["disabled"] = (ctrl as Button).disabled
		list.append(entry)

	for child in node.get_children(true):
		_dump_node_recursive(child, list)


## 取得受祖先裁切 (clip_contents) 影響後的有效可視區域
static func get_effective_visible_rect(ctrl: Control) -> Rect2:
	var rect := ctrl.get_global_rect()
	var curr: Node = ctrl.get_parent()
	while curr != null and curr is Control:
		var parent_ctrl := curr as Control
		if parent_ctrl.clip_contents:
			rect = rect.intersection(parent_ctrl.get_global_rect())
			if rect.size.x <= 0 or rect.size.y <= 0:
				return Rect2()
		curr = curr.get_parent()
	return rect


## 判斷節點是否位於獨立 Window/Popup 內
static func _is_inside_window(node: Node) -> bool:
	var curr: Node = node.get_parent()
	while curr != null:
		if curr is Window and not (curr is SubViewport):
			return true
		curr = curr.get_parent()
	return false


## 執行幾何診斷（遮蔽診斷與溢出診斷）
static func run_geometry_diagnostics(root: Node) -> Dictionary:
	var visible_controls: Array[Control] = []
	_collect_visible_controls(root, visible_controls)

	var occlusion_issues: Array[Dictionary] = []
	var overflow_issues: Array[Dictionary] = []

	var root_vp := root.get_viewport() if root is Control else null
	var vp_size: Vector2 = root_vp.get_visible_rect().size if root_vp != null else Vector2(1280, 720)

	# 1. 遮蔽診斷 (五條防呆)
	for i in range(visible_controls.size()):
		var ctrl_a := visible_controls[i]
		if not _has_renderable_content(ctrl_a):
			continue
		var rect_a := get_effective_visible_rect(ctrl_a)
		if rect_a.size.x <= 0 or rect_a.size.y <= 0:
			continue

		for j in range(i + 1, visible_controls.size()):
			var ctrl_b := visible_controls[j]
			if not _has_renderable_content(ctrl_b):
				continue

			# 防呆 2: 排除祖先與子孫
			if ctrl_a.is_ancestor_of(ctrl_b) or ctrl_b.is_ancestor_of(ctrl_a):
				continue

			# 防呆 3: 同一個 Viewport / CanvasLayer 限制（Window/Popup 為獨立 Viewport）
			if ctrl_a.get_viewport() != ctrl_b.get_viewport():
				continue
			if ctrl_a.get_canvas_layer_node() != ctrl_b.get_canvas_layer_node():
				continue

			# 防呆 4: 背景容器（Panel）不視為遮蔽前景元件
			if ctrl_a is Panel or ctrl_b is Panel:
				continue

			var rect_b := get_effective_visible_rect(ctrl_b)
			if rect_b.size.x <= 0 or rect_b.size.y <= 0:
				continue

			# 檢查重疊相交
			if rect_a.intersects(rect_b):
				var intersection := rect_a.intersection(rect_b)
				# 面積大於 9px 才計入，避免 1px 邊框鄰接誤報
				if intersection.size.x > 3.0 and intersection.size.y > 3.0:
					occlusion_issues.append({
						"under": str(ctrl_a.get_path()),
						"under_qa_id": str(ctrl_a.get_meta("qa_id")) if ctrl_a.has_meta("qa_id") else "",
						"over": str(ctrl_b.get_path()),
						"over_qa_id": str(ctrl_b.get_meta("qa_id")) if ctrl_b.has_meta("qa_id") else "",
						"intersect_rect": {
							"x": intersection.position.x,
							"y": intersection.position.y,
							"w": intersection.size.x,
							"h": intersection.size.y,
						}
					})

	# 2. 溢出診斷
	for ctrl in visible_controls:
		if ctrl is ScrollContainer:
			var sc := ctrl as ScrollContainer
			if not sc.clip_contents:
				overflow_issues.append({
					"path": str(sc.get_path()),
					"reason": "ScrollContainer 未開啟 clip_contents",
				})
			var min_s := sc.get_combined_minimum_size()
			var act_s := sc.size
			if min_s.y > act_s.y and sc.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
				overflow_issues.append({
					"path": str(sc.get_path()),
					"reason": "內容垂直高度 (%d) 大於容器 (%d) 且垂直捲動被停用" % [int(min_s.y), int(act_s.y)],
				})

		# 檢查常規 Control 右側/底部是否溢出視口邊界（未在 ScrollContainer 內）
		if _has_renderable_content(ctrl) and not _is_inside_window(ctrl):
			var eff := get_effective_visible_rect(ctrl)
			if eff.size.x > 0 and eff.size.y > 0:
				if eff.position.x + eff.size.x > vp_size.x + 2.0:
					overflow_issues.append({
						"path": str(ctrl.get_path()),
						"reason": "元件右側超出主視口邊界 (x2=%f > %f)" % [eff.position.x + eff.size.x, vp_size.x],
					})
				if eff.position.y + eff.size.y > vp_size.y + 2.0:
					overflow_issues.append({
						"path": str(ctrl.get_path()),
						"reason": "元件底部超出主視口邊界 (y2=%f > %f)" % [eff.position.y + eff.size.y, vp_size.y],
					})

	return {
		"ok": occlusion_issues.is_empty() and overflow_issues.is_empty(),
		"occlusion_issues": occlusion_issues,
		"overflow_issues": overflow_issues,
	}


static func _collect_visible_controls(node: Node, results: Array[Control]) -> void:
	if node is Control:
		var ctrl := node as Control
		if ctrl.is_visible_in_tree():
			results.append(ctrl)
	for child in node.get_children(true):
		_collect_visible_controls(child, results)


static func _has_renderable_content(ctrl: Control) -> bool:
	if ctrl is Label or ctrl is Button or ctrl is TextureRect or ctrl is ColorRect or ctrl is NinePatchRect or ctrl is Panel:
		return true
	return false


## 擷取當前畫面截圖
static func capture_screenshot(tree: SceneTree, file_path: String) -> bool:
	var vp := tree.get_root()
	var img := vp.get_texture().get_image()
	if img == null:
		return false
	var err := img.save_png(file_path)
	return err == OK


## 中途狀態擷取（截圖 + UI dump）
static func capture_interim_state(tree: SceneTree, root_node: Node, run_dir: String, case_id: String, stage_name: String) -> void:
	var dump_path := run_dir + "dumps/" + case_id + "_" + stage_name + ".json"
	var dump_data := dump_ui_tree(root_node)
	var f := FileAccess.open(dump_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(dump_data, "\t"))
		f.close()

	var shot_path := run_dir + "shots/" + case_id + "_" + stage_name + ".png"
	capture_screenshot(tree, shot_path)
