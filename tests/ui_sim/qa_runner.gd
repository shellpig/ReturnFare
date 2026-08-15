extends SceneTree

## UI 模擬 Runner（依 開發設計方針.md > Runner 的啟動架構 實作）。
## 啟動獨立 Godot 程序，設定 gui_embed_subwindows，載入主場景，執行指定案例並寫入產物。

const CaseBaseClass := preload("res://tests/ui_sim/cases/case_base.gd")
const P1GCasesClass := preload("res://tests/ui_sim/cases/p1g_cases.gd")
const QAStepClass := preload("res://tests/ui_sim/qa_step.gd")
const QADiagnosticsClass := preload("res://tests/ui_sim/qa_diagnostics.gd")


func _initialize() -> void:
	await process_frame

	var args: PackedStringArray = OS.get_cmdline_user_args()
	var case_id := ""
	var run_dir := ""

	var i := 0
	while i < args.size():
		match args[i]:
			"--case":
				if i + 1 < args.size():
					case_id = args[i + 1]
					i += 1
			"--run-dir":
				if i + 1 < args.size():
					run_dir = args[i + 1]
					i += 1
		i += 1

	if case_id.is_empty():
		case_id = "p1g_case_04_slot_types"

	if run_dir.is_empty():
		run_dir = "res://_qa/runs/latest/"

	run_dir = run_dir.replace("\\", "/")
	if not run_dir.ends_with("/"):
		run_dir += "/"

	DirAccess.make_dir_recursive_absolute(run_dir + "dumps/")
	DirAccess.make_dir_recursive_absolute(run_dir + "shots/")
	DirAccess.make_dir_recursive_absolute(run_dir + "reports/")

	# 1. 強制內嵌子視窗（防止 AcceptDialog 分離到獨立 OS 視窗）
	get_root().gui_embed_subwindows = true

	# 2. 實例化主場景
	var main_res := load("res://scenes/main.tscn")
	if main_res == null:
		printerr("qa_runner: 無法載入 res://scenes/main.tscn")
		quit(1)
		return

	var main_node: Control = main_res.instantiate() as Control
	get_root().add_child(main_node)

	# 3. 等候初始化與首幀繪製
	await QAStepClass.wait_draw_frames(self, 3)

	# 4. 尋找對應的 Case
	var case_obj: CaseBaseClass = P1GCasesClass.get_case_by_id(case_id)
	if case_obj == null:
		printerr("qa_runner: 找不到案例 id: %s" % case_id)
		quit(1)
		return

	print("=== QA Runner: 開始執行案例 [%s] ===" % case_id)
	print("  描述: %s" % case_obj.description)

	# 5. 執行案例
	var res: Dictionary = await case_obj.run(self, main_node, run_dir)
	var is_ok: bool = bool(res.get("ok", false))
	var errors: Array = res.get("errors", []) as Array

	# 6. 幾何診斷
	var geo_res := QADiagnosticsClass.run_geometry_diagnostics(main_node)
	if not geo_res.get("ok", false):
		for occ in geo_res.get("occlusion_issues", []) as Array:
			errors.append("幾何遮蔽缺陷: %s 被 %s 遮住" % [str(occ.get("under")), str(occ.get("over"))])
		for of in geo_res.get("overflow_issues", []) as Array:
			errors.append("幾何溢出缺陷: %s (%s)" % [str(of.get("path")), str(of.get("reason"))])
		is_ok = false

	# 7. 產生 UI Dump 與截圖
	var ui_dump := QADiagnosticsClass.dump_ui_tree(main_node)
	var dump_file := run_dir + "dumps/" + case_id + ".json"
	var f_dump := FileAccess.open(dump_file, FileAccess.WRITE)
	if f_dump != null:
		f_dump.store_string(JSON.stringify(ui_dump, "\t"))
		f_dump.close()

	var shot_file := run_dir + "shots/" + case_id + ".png"
	QADiagnosticsClass.capture_screenshot(self, shot_file)

	# 8. 寫入 Case 報告
	var report := {
		"case_id": case_id,
		"description": case_obj.description,
		"ok": is_ok,
		"errors": errors,
		"geometry": geo_res,
		"shot_file": shot_file,
		"dump_file": dump_file,
	}
	var rep_file := run_dir + "reports/" + case_id + ".json"
	var f_rep := FileAccess.open(rep_file, FileAccess.WRITE)
	if f_rep != null:
		f_rep.store_string(JSON.stringify(report, "\t"))
		f_rep.close()

	if is_ok:
		print("=== QA Runner: 案例 [%s] 通過 (OK) ===" % case_id)
		quit(0)
	else:
		printerr("=== QA Runner: 案例 [%s] 失敗 (FAIL) ===" % case_id)
		for e in errors:
			printerr("  " + str(e))
		quit(1)
