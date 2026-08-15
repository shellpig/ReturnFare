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


## 計算 Control 的全域 Z-Index
static func _get_global_z_index(ctrl: CanvasItem) -> int:
	var z := 0
	var curr: Node = ctrl
	while curr != null and curr is CanvasItem:
		var ci := curr as CanvasItem
		z += ci.z_index
		if not ci.z_as_relative:
			break
		curr = curr.get_parent()
	return z


## 執行幾何診斷（遮蔽診斷與溢出診斷）
static func run_geometry_diagnostics(root: Node) -> Dictionary:
	var visible_controls: Array[Control] = []
	_collect_visible_controls(root, visible_controls)

	# 依 (Global Z-Index, Tree Order) 排序以確定繪製順序 (小的在下，大的在上)
	var z_map: Dictionary = {}
	for ctrl in visible_controls:
		z_map[ctrl] = _get_global_z_index(ctrl)

	visible_controls.sort_custom(func(a: Control, b: Control) -> bool:
		var za: int = z_map.get(a, 0)
		var zb: int = z_map.get(b, 0)
		if za != zb:
			return za < zb
		return false # 保持 scene tree 原序
	)

	var occlusion_issues: Array[Dictionary] = []
	var overflow_issues: Array[Dictionary] = []

	var root_vp := root.get_viewport() if root is Control else null
	var vp_size: Vector2 = root_vp.get_visible_rect().size if root_vp != null else Vector2(1280, 720)

	# 1. 遮蔽診斷 (排除祖先子孫，嚴格檢查同層與跨層覆蓋)
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

			# 排除祖先與子孫
			if ctrl_a.is_ancestor_of(ctrl_b) or ctrl_b.is_ancestor_of(ctrl_a):
				continue

			# 同一個 Viewport / CanvasLayer 限制（Window/Popup 為獨立 Viewport）
			if ctrl_a.get_viewport() != ctrl_b.get_viewport():
				continue
			if ctrl_a.get_canvas_layer_node() != ctrl_b.get_canvas_layer_node():
				continue

			var rect_b := get_effective_visible_rect(ctrl_b)
			if rect_b.size.x <= 0 or rect_b.size.y <= 0:
				continue

			# 檢查重疊相交 (面積 > 9px 才計入)
			if rect_a.intersects(rect_b):
				var intersection := rect_a.intersection(rect_b)
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

	# 2. 溢出診斷與保護區檢查
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
			if min_s.x > act_s.x and sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
				overflow_issues.append({
					"path": str(sc.get_path()),
					"reason": "內容水平寬度 (%d) 大於容器 (%d) 且水平捲動被停用" % [int(min_s.x), int(act_s.x)],
				})

		# 檢查常規 Control 視口邊界溢出
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

			# 文字控制項 (Label/RichTextLabel/Button) 最小需求尺寸 vs 實際分配尺寸檢驗 (K-40 防線)
			if ctrl is Label or ctrl is RichTextLabel or ctrl is Button:
				var min_s := ctrl.get_combined_minimum_size()
				var act_s := ctrl.size
				# 若非位於可捲動容器內，且最小文字需求超過配置尺寸，即為文字遭到壓縮或溢出
				var in_scroll := false
				var p_node_scroll: Node = ctrl.get_parent()
				while p_node_scroll != null and p_node_scroll is Control:
					if p_node_scroll is ScrollContainer:
						in_scroll = true
						break
					p_node_scroll = p_node_scroll.get_parent()
				
				if not in_scroll:
					if min_s.x > act_s.x + 2.0 and act_s.x > 0:
						overflow_issues.append({
							"path": str(ctrl.get_path()),
							"reason": "文字控制項水平最小尺寸 (%f) 大於實際配置寬度 (%f)，文字遭到截斷或溢出" % [min_s.x, act_s.x],
						})
					if min_s.y > act_s.y + 2.0 and act_s.y > 0:
						overflow_issues.append({
							"path": str(ctrl.get_path()),
							"reason": "文字控制項垂直最小尺寸 (%f) 大於實際配置高度 (%f)，文字遭到截斷或溢出" % [min_s.y, act_s.y],
						})

			# 檢查元件 combined_minimum_size 與未裁切父容器之邊界
			var raw_rect := ctrl.get_global_rect()
			var p_node := ctrl.get_parent()
			if p_node is Control and not (p_node is ScrollContainer):
				var p_ctrl := p_node as Control
				if not p_ctrl.clip_contents:
					var p_raw := p_ctrl.get_global_rect()
					if raw_rect.position.x + raw_rect.size.x > p_raw.position.x + p_raw.size.x + 2.0 and p_raw.size.x > 0:
						overflow_issues.append({
							"path": str(ctrl.get_path()),
							"reason": "元件右側 (%f) 溢出未裁切父容器 (%f)" % [raw_rect.position.x + raw_rect.size.x, p_raw.position.x + p_raw.size.x],
						})
					if raw_rect.position.y + raw_rect.size.y > p_raw.position.y + p_raw.size.y + 2.0 and p_raw.size.y > 0:
						overflow_issues.append({
							"path": str(ctrl.get_path()),
							"reason": "元件底部 (%f) 溢出未裁切父容器 (%f)" % [raw_rect.position.y + raw_rect.size.y, p_raw.position.y + p_raw.size.y],
						})

			# 保護區檢查 (K-28 / K-40 防線): ContentView 內部內容不得侵入 StatusLabel/AdvanceButton (0..170) 或 HandBar (580..720)
			var path_str := str(ctrl.get_path())
			if path_str.contains("/ContentView/") and not path_str.contains("/AcceptDialog"):
				if raw_rect.position.y < 168.0:
					overflow_issues.append({
						"path": path_str,
						"reason": "內容侵入上方狀態列/推進按鈕保護區 (y=%f < 168)" % raw_rect.position.y,
					})
				if ctrl is ScrollContainer:
					# ScrollContainer 自身外框絕對不得侵入 HandBar
					if raw_rect.position.y + raw_rect.size.y > 582.0:
						overflow_issues.append({
							"path": path_str,
							"reason": "ScrollContainer 容器本體侵入下方 HandBar 手牌保護區 (y2=%f > 582)" % (raw_rect.position.y + raw_rect.size.y),
						})
				else:
					# 若在 ScrollContainer 內部，只要父層 ScrollContainer 有 clip_contents 且其外框在 582 內即可
					var in_clipped_scroll := false
					var p_check: Node = ctrl.get_parent()
					while p_check != null and p_check is Control:
						if p_check is ScrollContainer:
							var sc_parent := p_check as ScrollContainer
							if sc_parent.clip_contents and (sc_parent.get_global_rect().position.y + sc_parent.get_global_rect().size.y <= 582.0):
								in_clipped_scroll = true
								break
						p_check = p_check.get_parent()
					if not in_clipped_scroll and raw_rect.position.y + raw_rect.size.y > 582.0:
						overflow_issues.append({
							"path": path_str,
							"reason": "未裁切內容侵入下方 HandBar 手牌保護區 (y2=%f > 582)" % (raw_rect.position.y + raw_rect.size.y),
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
static func capture_interim_state(tree: SceneTree, root_node: Node, run_dir: String, case_id: String, stage_name: String) -> bool:
	var dump_path := run_dir + "dumps/" + case_id + "_" + stage_name + ".json"
	var dump_data := dump_ui_tree(root_node)
	var f := FileAccess.open(dump_path, FileAccess.WRITE)
	if f == null:
		printerr("capture_interim_state: dump 寫入失敗: %s" % dump_path)
		return false
	f.store_string(JSON.stringify(dump_data, "\t"))
	f.close()

	var shot_path := run_dir + "shots/" + case_id + "_" + stage_name + ".png"
	var shot_ok := capture_screenshot(tree, shot_path)
	if not shot_ok:
		printerr("capture_interim_state: 截圖寫入失敗: %s" % shot_path)
		return false
	return true
