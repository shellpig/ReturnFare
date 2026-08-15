extends SceneTree

## UI 模擬 Runner。
## 每個案例在獨立 Godot 程序執行；狀態檔在建立主場景前驗證，避免壞狀態
## 先建立一半的 UI 再中止，留下 ObjectDB leak 並污染失敗診斷。

const CaseBaseClass := preload("res://tests/ui_sim/cases/case_base.gd")
const P1GCasesClass := preload("res://tests/ui_sim/cases/p1g_cases.gd")
const QAStepClass := preload("res://tests/ui_sim/qa_step.gd")
const QADiagnosticsClass := preload("res://tests/ui_sim/qa_diagnostics.gd")


func _initialize() -> void:
	await process_frame

	var args: PackedStringArray = OS.get_cmdline_user_args()
	var parsed := _parse_args(args)

	if bool(parsed.get("list_cases", false)):
		await _write_case_manifest(str(parsed.get("output", "")))
		return

	var case_id := str(parsed.get("case", ""))
	var run_dir := str(parsed.get("run_dir", ""))
	var state_path := str(parsed.get("state", ""))

	if case_id.is_empty():
		printerr("qa_runner: 缺少必要參數 --case <case_id>")
		quit(1)
		return
	if run_dir.is_empty():
		printerr("qa_runner: 缺少必要參數 --run-dir <run_dir>")
		quit(1)
		return

	run_dir = _normalize_dir(run_dir)
	DirAccess.make_dir_recursive_absolute(run_dir + "dumps/")
	DirAccess.make_dir_recursive_absolute(run_dir + "shots/")
	DirAccess.make_dir_recursive_absolute(run_dir + "reports/")

	var case_obj: CaseBaseClass = P1GCasesClass.get_case_by_id(case_id)
	if case_obj == null:
		_fail_before_scene(case_id, run_dir, "找不到案例 id: %s" % case_id)
		return

	var mapping_error := _validate_case_mapping(case_obj, state_path)
	if not mapping_error.is_empty():
		_fail_before_scene(case_id, run_dir, mapping_error)
		return

	var state_error := _validate_state_file(state_path)
	if not state_error.is_empty():
		_fail_before_scene(case_id, run_dir, state_error)
		return

	# 強制內嵌子視窗（防止 AcceptDialog 分離到獨立 OS 視窗）。
	get_root().gui_embed_subwindows = true

	var main_res := load("res://scenes/main.tscn")
	if main_res == null:
		_fail_before_scene(case_id, run_dir, "無法載入 res://scenes/main.tscn")
		return

	var main_node: Control = main_res.instantiate() as Control
	get_root().add_child(main_node)
	await QAStepClass.wait_draw_frames(self, 3)

	print("=== QA Runner: 開始執行案例 [%s] ===" % case_id)
	print("  描述: %s" % case_obj.description)
	QAStepClass.begin_interim_capture(self, main_node, run_dir, case_id)

	var res: Dictionary = await case_obj.run(self, main_node, run_dir)
	var is_ok: bool = bool(res.get("ok", false))
	var errors: Array = res.get("errors", []) as Array
	for interim_error in QAStepClass.get_interim_failures():
		errors.append(str(interim_error))
	is_ok = is_ok and QAStepClass.get_interim_failures().is_empty()
	QAStepClass.end_interim_capture()

	# 案例結束時再跑一次，並且把每次 click 的中途診斷一併納入結果。
	var geo_res := QADiagnosticsClass.run_geometry_diagnostics(main_node)
	if not geo_res.get("ok", false):
		for occ in geo_res.get("occlusion_issues", []) as Array:
			errors.append("幾何遮蔽缺陷: %s 被 %s 遮住" % [str(occ.get("under")), str(occ.get("over"))])
		for of in geo_res.get("overflow_issues", []) as Array:
			errors.append("幾何溢出缺陷: %s (%s)" % [str(of.get("path")), str(of.get("reason"))])
		is_ok = false

	var ui_dump := QADiagnosticsClass.dump_ui_tree(main_node)
	var dump_file := run_dir + "dumps/" + case_id + ".json"
	var f_dump := FileAccess.open(dump_file, FileAccess.WRITE)
	if f_dump != null:
		f_dump.store_string(JSON.stringify(ui_dump, "\t"))
		f_dump.close()
	else:
		errors.append("無法寫入 dump 檔案: " + dump_file)
		is_ok = false

	var shot_file := run_dir + "shots/" + case_id + ".png"
	var shot_ok := QADiagnosticsClass.capture_screenshot(self, shot_file)
	if not shot_ok:
		errors.append("無法儲存截圖: " + shot_file)
		is_ok = false

	var report := {
		"case_id": case_id,
		"description": case_obj.description,
		"contract_id": case_obj.contract_id,
		"comparison_group": case_obj.comparison_group,
		"required_state": case_obj.required_state,
		"required_data_root": case_obj.required_data_root,
		"ok": is_ok and errors.is_empty(),
		"errors": errors,
		"geometry": geo_res,
		"observations": res.get("observations", {}),
		"shot_file": shot_file,
		"dump_file": dump_file,
	}
	var rep_file := run_dir + "reports/" + case_id + ".json"
	var f_rep := FileAccess.open(rep_file, FileAccess.WRITE)
	if f_rep != null:
		f_rep.store_string(JSON.stringify(report, "\t"))
		f_rep.close()
	else:
		printerr("無法寫入報告檔案: " + rep_file)
		await _cleanup_and_quit(main_node, 1)
		return

	if bool(report.get("ok", false)):
		print("=== QA Runner: 案例 [%s] 通過 (OK) ===" % case_id)
		await _cleanup_and_quit(main_node, 0)
	else:
		printerr("=== QA Runner: 案例 [%s] 失敗 (FAIL) ===" % case_id)
		for e in errors:
			printerr("  " + str(e))
		await _cleanup_and_quit(main_node, 1)


func _parse_args(args: PackedStringArray) -> Dictionary:
	var result := {
		"case": "",
		"state": "",
		"run_dir": "",
		"output": "",
		"list_cases": false,
	}
	var i := 0
	while i < args.size():
		match args[i]:
			"--case":
				if i + 1 < args.size():
					result["case"] = args[i + 1]
					i += 1
			"--state":
				if i + 1 < args.size():
					result["state"] = args[i + 1]
					i += 1
			"--run-dir":
				if i + 1 < args.size():
					result["run_dir"] = args[i + 1]
					i += 1
			"--list-cases":
				result["list_cases"] = true
			"--output":
				if i + 1 < args.size():
					result["output"] = args[i + 1]
					i += 1
		i += 1
	return result


func _write_case_manifest(output_path: String) -> void:
	if output_path.is_empty():
		printerr("qa_runner: --list-cases 缺少 --output <path>")
		quit(1)
		return
	var cases: Array[Dictionary] = []
	for case_obj in P1GCasesClass.get_all_cases():
		cases.append({
			"id": case_obj.id,
			"description": case_obj.description,
			"contract_id": case_obj.contract_id,
			"required_state": case_obj.required_state,
			"required_data_root": case_obj.required_data_root,
			"comparison_group": case_obj.comparison_group,
		})
	var absolute_path := output_path.replace("\\", "/")
	var parent := absolute_path.get_base_dir()
	if not parent.is_empty():
		DirAccess.make_dir_recursive_absolute(parent)
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		printerr("qa_runner: 無法寫入案例 manifest: %s" % absolute_path)
		quit(1)
		return
	file.store_string(JSON.stringify({ "cases": cases }, "\t"))
	file.close()
	print("qa_runner: 已寫入案例 manifest (%d variants)" % cases.size())
	quit(0)


func _validate_case_mapping(case_obj: CaseBaseClass, state_path: String) -> String:
	var actual_state := state_path.replace("\\", "/").get_file() if not state_path.is_empty() else ""
	if case_obj.required_state.is_empty() and not actual_state.is_empty():
		return "案例不接受 --state，但實際傳入: %s" % actual_state
	if not case_obj.required_state.is_empty() and actual_state.is_empty():
		return "案例要求狀態檔: %s" % case_obj.required_state
	if not case_obj.required_state.is_empty() and actual_state != case_obj.required_state:
		return "案例要求狀態檔 %s，實際傳入 %s" % [case_obj.required_state, actual_state]
	return ""


func _validate_state_file(state_path: String) -> String:
	if state_path.is_empty():
		return ""
	if not FileAccess.file_exists(state_path):
		return "--state 檔案不存在: %s" % state_path
	var text := FileAccess.get_file_as_string(state_path)
	var json_val: Variant = JSON.parse_string(text)
	if json_val == null or not (json_val is Dictionary):
		return "--state JSON 解析失敗: %s" % state_path
	var err_msg := _validate_state_json(json_val as Dictionary)
	if not err_msg.is_empty():
		return "--state 狀態檔不合法: %s (%s)" % [err_msg, state_path]
	return ""


func _validate_state_json(data: Dictionary) -> String:
	var gs := get_root().get_node_or_null("GameState")
	if gs == null:
		return "GameState autoload 尚未建立"
	var template: Dictionary = gs.call("serialize") as Dictionary
	var dict_err := _validate_dict_shape(data, template, "")
	if not dict_err.is_empty():
		return dict_err
	var run: Dictionary = data.get("run", {}) as Dictionary
	var day_val: Variant = run.get("day")
	if day_val == null:
		return "run.day 遺失"
	var day_int := int(day_val)
	if day_int < 1 or day_int > 45:
		return "run.day 超出範圍 (1..45): %d" % day_int
	var phase_val: Variant = run.get("phase")
	if phase_val == null or not (str(phase_val) in ["morning", "afternoon", "evening", "night"]):
		return "run.phase 不合法: %s" % str(phase_val)
	return ""


func _validate_dict_shape(data: Dictionary, template: Dictionary, prefix: String) -> String:
	for key: Variant in template.keys():
		var k := str(key)
		var full_key := (prefix + "." + k) if not prefix.is_empty() else k
		if not data.has(k):
			return "必要欄位遺失: %s" % full_key
		var val: Variant = data[k]
		var tpl_val: Variant = template[k]
		if typeof(tpl_val) == TYPE_INT or typeof(tpl_val) == TYPE_FLOAT:
			if typeof(val) != TYPE_INT and typeof(val) != TYPE_FLOAT:
				return "欄位型別錯誤: %s 應為數字" % full_key
		elif typeof(tpl_val) == TYPE_DICTIONARY:
			if typeof(val) != TYPE_DICTIONARY:
				return "欄位型別錯誤: %s 應為 Dictionary" % full_key
			if not (tpl_val as Dictionary).is_empty():
				var sub_err := _validate_dict_shape(val as Dictionary, tpl_val as Dictionary, full_key)
				if not sub_err.is_empty():
					return sub_err
		elif typeof(tpl_val) == TYPE_ARRAY and typeof(val) != TYPE_ARRAY:
			return "欄位型別錯誤: %s 應為 Array" % full_key
		elif typeof(tpl_val) == TYPE_STRING and typeof(val) != TYPE_STRING:
			return "欄位型別錯誤: %s 應為 String" % full_key
		elif typeof(tpl_val) == TYPE_BOOL and typeof(val) != TYPE_BOOL:
			return "欄位型別錯誤: %s 應為 bool" % full_key
	return ""


func _normalize_dir(path: String) -> String:
	var normalized := path.replace("\\", "/")
	if not normalized.ends_with("/"):
		normalized += "/"
	return normalized


func _fail_before_scene(case_id: String, run_dir: String, message: String) -> void:
	printerr("qa_runner: " + message)
	if not run_dir.is_empty():
		var report_dir := _normalize_dir(run_dir) + "reports/"
		DirAccess.make_dir_recursive_absolute(report_dir)
		var report := {
			"case_id": case_id,
			"ok": false,
			"errors": [message],
			"observations": {},
		}
		var file := FileAccess.open(report_dir + case_id + ".json", FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "\t"))
			file.close()
	quit(1)


func _cleanup_and_quit(main_node: Node, exit_code: int) -> void:
	QAStepClass.end_interim_capture()
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	await process_frame
	quit(exit_code)
