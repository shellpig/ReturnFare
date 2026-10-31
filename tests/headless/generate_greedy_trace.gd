extends SceneTree

## W1-B Godot 黃金軌跡產生器（SceneTree runner）。
## 沿用 playthrough_greedy.gd 的 setup_data()、setup_game_state()、run_greedy_walk()，
## 以唯讀 observer 收集 45 天貪心走查的時段邊界與結局狀態快照，輸出 Trace v1 JSON。
## 跑法：
##   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/generate_greedy_trace.gd -- --output _qa/web/trace-godot.json --source-revision <rev>
## 成功 exit 0；參數缺少、走查失敗、取樣不完整、觀測不等價或寫檔失敗均 exit 1 且不覆蓋既有輸出檔。

const PlaythroughGreedy := preload("res://tests/headless/playthrough_greedy.gd")
const VALID_PHASES := ["morning", "afternoon", "evening", "night"]


func _initialize() -> void:
	await process_frame

	var parsed_args := _parse_cli_args()
	if not bool(parsed_args.get("ok", false)):
		push_error("generate_greedy_trace: %s" % str(parsed_args.get("error", "invalid arguments")))
		quit(1)
		return

	var output_arg := str(parsed_args.get("output", ""))
	var source_revision := str(parsed_args.get("source_revision", ""))
	var resolved_output := _resolve_output_path(output_arg)
	if resolved_output.is_empty():
		push_error("generate_greedy_trace: 無效的 --output 路徑：%s" % output_arg)
		quit(1)
		return

	var data_node := PlaythroughGreedy.setup_data(self)
	if data_node == null or not bool(data_node.get("ok")) or data_node.get("loader") == null:
		push_error("generate_greedy_trace: Data 載入失敗，中止產生軌跡")
		quit(1)
		return

	var gs := PlaythroughGreedy.setup_game_state(self, data_node)
	if gs == null:
		push_error("generate_greedy_trace: GameState 初始化失敗")
		quit(1)
		return

	var manifest_res := _build_data_manifest("res://data")
	if not bool(manifest_res.get("ok", false)):
		push_error("generate_greedy_trace: %s" % str(manifest_res.get("error", "manifest build failed")))
		quit(1)
		return
	var data_manifest: Array[Dictionary] = manifest_res.get("manifest", [])

	# 建立獨立未觀測對照實例，確認初始狀態一致
	var gs_unobserved: Node = (gs.get_script() as GDScript).new()
	gs_unobserved.set("Data", data_node)
	PlaythroughGreedy.start_fresh_run(gs_unobserved)
	var initial_observed_state: Dictionary = (gs.call("serialize") as Dictionary).duplicate(true)
	var initial_unobserved_state: Dictionary = (gs_unobserved.call("serialize") as Dictionary).duplicate(true)
	if initial_observed_state != initial_unobserved_state:
		gs_unobserved.free()
		push_error("generate_greedy_trace: 觀測與未觀測實例的初始 serialize() 不一致")
		quit(1)
		return

	var checkpoints: Array[Dictionary] = []
	var observer_errors: Array[String] = []
	var observer := func(label: String, target_gs: Node) -> void:
		if target_gs == null:
			observer_errors.append("observer 收到 null GameState (label=%s)" % label)
			return
		var snap: Dictionary = (target_gs.call("serialize") as Dictionary).duplicate(true)
		var seq_num: int = checkpoints.size()
		var live_day: int = int(target_gs.get("day"))
		var live_phase: String = str(target_gs.get("phase"))
		checkpoints.append({
			"seq": seq_num,
			"label": label,
			"day": live_day,
			"phase": live_phase,
			"state": snap,
		})

	var observed_res: Dictionary = PlaythroughGreedy.run_greedy_walk(gs, data_node, false, observer)
	var final_observed_state: Dictionary = (gs.call("serialize") as Dictionary).duplicate(true)

	var unobserved_res: Dictionary = PlaythroughGreedy.run_greedy_walk(gs_unobserved, data_node, false)
	var final_unobserved_state: Dictionary = (gs_unobserved.call("serialize") as Dictionary).duplicate(true)
	gs_unobserved.free()

	if not observer_errors.is_empty():
		for err in observer_errors:
			push_error("generate_greedy_trace: %s" % err)
		quit(1)
		return

	if not bool(observed_res.get("ok", false)):
		push_error("generate_greedy_trace: run_greedy_walk 執行失敗 (errors=%s, illegal_phases=%d)" % [
			str(observed_res.get("errors", [])),
			int(observed_res.get("illegal_phases", -1)),
		])
		quit(1)
		return

	if observed_res != unobserved_res:
		push_error("generate_greedy_trace: 觀測開關兩次走查的回傳結果不一致")
		quit(1)
		return

	if final_observed_state != final_unobserved_state:
		push_error("generate_greedy_trace: 觀測開關兩次走查的最終 serialize() 不一致")
		quit(1)
		return

	var validation_err := _validate_checkpoints(checkpoints, initial_observed_state, final_observed_state)
	if not validation_err.is_empty():
		push_error("generate_greedy_trace: 取樣驗證失敗：%s" % validation_err)
		quit(1)
		return

	var self_test_err := _run_self_tests(checkpoints, initial_observed_state, final_observed_state)
	if not self_test_err.is_empty():
		push_error("generate_greedy_trace: 內部回歸自檢失敗：%s" % self_test_err)
		quit(1)
		return

	var trace_doc := {
		"schema_version": 1,
		"policy": "greedy-v1",
		"source_revision": source_revision,
		"data_manifest": data_manifest,
		"checkpoints": checkpoints,
	}

	var json_text := JSON.stringify(trace_doc, "  ", false) + "\n"
	if json_text.strip_edges().is_empty():
		push_error("generate_greedy_trace: JSON 序列化失敗")
		quit(1)
		return

	var write_err := _write_text_atomic(resolved_output, json_text)
	if not write_err.is_empty():
		push_error("generate_greedy_trace: 寫檔失敗：%s" % write_err)
		quit(1)
		return

	var written_bytes := FileAccess.get_file_as_bytes(resolved_output).size()
	print("generate_greedy_trace: ok | checkpoints=%d | phase_end=179 | manifest_files=%d | bytes=%d | output=%s" % [
		checkpoints.size(),
		data_manifest.size(),
		written_bytes,
		output_arg,
	])
	quit(0)


func _parse_cli_args() -> Dictionary:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var output_path := ""
	var source_revision := ""
	var has_output := false
	var has_revision := false

	var i := 0
	while i < args.size():
		var arg := str(args[i])
		if arg == "--output":
			if has_output:
				return { "ok": false, "error": "--output 重複指定" }
			if i + 1 >= args.size():
				return { "ok": false, "error": "--output 缺少路徑值" }
			var val := str(args[i + 1]).strip_edges()
			if val.is_empty() or val.begins_with("--"):
				return { "ok": false, "error": "--output 缺少有效路徑值" }
			output_path = val
			has_output = true
			i += 2
		elif arg.begins_with("--output="):
			if has_output:
				return { "ok": false, "error": "--output 重複指定" }
			var val := arg.substr("--output=".length()).strip_edges()
			if val.is_empty() or val.begins_with("--"):
				return { "ok": false, "error": "--output 缺少有效路徑值" }
			output_path = val
			has_output = true
			i += 1
		elif arg == "--source-revision":
			if has_revision:
				return { "ok": false, "error": "--source-revision 重複指定" }
			if i + 1 >= args.size():
				return { "ok": false, "error": "--source-revision 缺少數值" }
			var val := str(args[i + 1]).strip_edges()
			if val.is_empty() or val.begins_with("--"):
				return { "ok": false, "error": "--source-revision 缺少有效數值" }
			source_revision = val
			has_revision = true
			i += 2
		elif arg.begins_with("--source-revision="):
			if has_revision:
				return { "ok": false, "error": "--source-revision 重複指定" }
			var val := arg.substr("--source-revision=".length()).strip_edges()
			if val.is_empty() or val.begins_with("--"):
				return { "ok": false, "error": "--source-revision 缺少有效數值" }
			source_revision = val
			has_revision = true
			i += 1
		else:
			return { "ok": false, "error": "不支援的參數：%s" % arg }

	if not has_output or output_path.is_empty():
		return { "ok": false, "error": "缺少必要參數 --output <path>" }
	if not has_revision or source_revision.is_empty():
		return { "ok": false, "error": "缺少必要參數 --source-revision <rev>" }

	return {
		"ok": true,
		"output": output_path,
		"source_revision": source_revision,
	}


func _resolve_output_path(output_arg: String) -> String:
	var trimmed := output_arg.strip_edges()
	if trimmed.is_empty() or trimmed.ends_with("/") or trimmed.ends_with("\\"):
		return ""
	var resolved := ""
	if trimmed.begins_with("res://") or trimmed.begins_with("user://"):
		resolved = ProjectSettings.globalize_path(trimmed)
	elif trimmed.is_absolute_path():
		resolved = trimmed
	else:
		resolved = ProjectSettings.globalize_path("res://").path_join(trimmed)
	resolved = resolved.simplify_path()
	if DirAccess.dir_exists_absolute(resolved):
		return ""
	return resolved


func _build_data_manifest(root_res_dir: String) -> Dictionary:
	var rel_paths: Array[String] = []
	if not _collect_json_files(root_res_dir, "", rel_paths):
		return { "ok": false, "error": "無法遍歷資料目錄：%s" % root_res_dir }
	if rel_paths.is_empty():
		return { "ok": false, "error": "資料目錄下找不到任何 .json 檔案" }

	rel_paths.sort()
	var manifest: Array[Dictionary] = []
	for rel_path: String in rel_paths:
		if not rel_path.ends_with(".json") or rel_path.ends_with(".md"):
			return { "ok": false, "error": "manifest 包含非 JSON 檔案：%s" % rel_path }
		var full_res_path := root_res_dir.path_join(rel_path)
		var sha := FileAccess.get_sha256(full_res_path).strip_edges().to_lower()
		if sha.length() != 64:
			return { "ok": false, "error": "無法計算 SHA-256：%s" % full_res_path }
		manifest.append({
			"path": rel_path,
			"sha256": sha,
		})

	return { "ok": true, "manifest": manifest }


func _collect_json_files(cur_dir: String, rel_prefix: String, out_paths: Array[String]) -> bool:
	var dir := DirAccess.open(cur_dir)
	if dir == null:
		return false
	if dir.list_dir_begin() != OK:
		return false
	while true:
		var entry := dir.get_next()
		if entry.is_empty():
			break
		if entry == "." or entry == "..":
			continue
		var rel := entry if rel_prefix.is_empty() else (rel_prefix + "/" + entry)
		var full := cur_dir.path_join(entry)
		if dir.current_is_dir():
			if not _collect_json_files(full, rel, out_paths):
				dir.list_dir_end()
				return false
		elif entry.ends_with(".json"):
			out_paths.append(rel)
	dir.list_dir_end()
	return true


func _validate_checkpoints(
	checkpoints: Array[Dictionary],
	initial_state: Dictionary,
	final_state: Dictionary
) -> String:
	if checkpoints.is_empty():
		return "checkpoints 為空"

	for i in range(checkpoints.size()):
		var cp: Dictionary = checkpoints[i]
		if int(cp.get("seq", -1)) != i:
			return "seq 不連續：index=%d 實際 seq=%s" % [i, str(cp.get("seq"))]
		var st_var: Variant = cp.get("state")
		if not (st_var is Dictionary):
			return "seq=%d 缺少 state 物件" % i
		var st: Dictionary = st_var as Dictionary
		if not (st.get("flow") is Dictionary) or not (st.get("run") is Dictionary) or not (st.get("meta") is Dictionary):
			return "seq=%d state 缺少 flow/run/meta 結構" % i
		var run_block: Dictionary = st["run"] as Dictionary
		var cp_day: int = int(cp.get("day", -1))
		var cp_phase: String = str(cp.get("phase", ""))
		if cp_day != int(run_block.get("day", -2)) or cp_phase != str(run_block.get("phase", "")):
			return "seq=%d day/phase (%d/%s) 與 state.run (%s/%s) 不一致" % [
				i, cp_day, cp_phase, str(run_block.get("day")), str(run_block.get("phase"))
			]
		if not VALID_PHASES.has(cp_phase):
			return "seq=%d 非法 phase：%s" % [i, cp_phase]

	# 0. run_start 檢查（確認深複製未被後續操作覆寫）
	var cp0: Dictionary = checkpoints[0]
	if str(cp0.get("label", "")) != "run_start" or int(cp0.get("day", 0)) != 1 or str(cp0.get("phase", "")) != "morning":
		return "seq=0 必須為 1/morning 的 run_start"
	if (cp0["state"] as Dictionary) != initial_state:
		return "seq=0 state 與初始狀態不一致（疑似深複製失效被後續操作污染）"

	# 1..179. phase_end 檢查（1～44 天四時段 + 第 45 天三時段 = 179 筆）
	var phase_end_count := 0
	for cp: Dictionary in checkpoints:
		if str(cp.get("label", "")) == "phase_end":
			phase_end_count += 1
	if phase_end_count != 179 or checkpoints.size() <= 180:
		return "phase_end 總筆數應為 179，實得 %d (總 checkpoints=%d)" % [phase_end_count, checkpoints.size()]

	var seq_idx := 1
	for d in range(1, 45):
		for expected_phase: String in VALID_PHASES:
			var cp: Dictionary = checkpoints[seq_idx]
			if str(cp.get("label", "")) != "phase_end":
				return "seq=%d 預期 label=phase_end，實得 %s" % [seq_idx, str(cp.get("label"))]
			if int(cp.get("day", 0)) != d or str(cp.get("phase", "")) != expected_phase:
				return "seq=%d 預期 %d/%s，實得 %d/%s" % [
					seq_idx, d, expected_phase, int(cp.get("day", 0)), str(cp.get("phase", ""))
				]
			seq_idx += 1

	# 第 45 天：seq 177 為 45/morning；seq 178（afternoon helper 內遭遇推進）與 seq 179 皆為 45/evening
	var cp177: Dictionary = checkpoints[177]
	var cp178: Dictionary = checkpoints[178]
	var cp179: Dictionary = checkpoints[179]
	if str(cp177.get("label", "")) != "phase_end" or int(cp177.get("day", 0)) != 45 or str(cp177.get("phase", "")) != "morning":
		return "seq=177 預期為 45/morning phase_end"
	if str(cp178.get("label", "")) != "phase_end" or int(cp178.get("day", 0)) != 45 or str(cp178.get("phase", "")) != "evening":
		return "seq=178 預期為 45/evening phase_end（D45 afternoon 遭遇推進後）"
	if str(cp179.get("label", "")) != "phase_end" or int(cp179.get("day", 0)) != 45 or str(cp179.get("phase", "")) != "evening":
		return "seq=179 預期為 45/evening phase_end"

	# 180. ending_started
	var cp180: Dictionary = checkpoints[180]
	if str(cp180.get("label", "")) != "ending_started":
		return "seq=180 預期為 ending_started，實得 %s" % str(cp180.get("label"))
	var cp180_state: Dictionary = cp180["state"] as Dictionary
	var cp180_flow: Dictionary = cp180_state["flow"] as Dictionary
	if str(cp180_flow.get("mode", "")) != "ending":
		return "seq=180 flow.mode 應為 ending"
	var active0_var: Variant = cp180_flow.get("active_ending")
	if not (active0_var is Dictionary):
		return "seq=180 active_ending 必須為 Dictionary"
	var active0: Dictionary = active0_var as Dictionary
	var page_refs_var: Variant = active0.get("page_refs")
	if not (page_refs_var is Array) or (page_refs_var as Array).is_empty():
		return "seq=180 active_ending.page_refs 必須為非空陣列"
	var page_refs: Array = page_refs_var as Array
	var page_count: int = page_refs.size()
	if int(active0.get("page_index", -1)) != 0 or bool(active0.get("page_revealed", true)) or bool(active0.get("ready_to_complete", true)):
		return "seq=180 ending_started 初始頁狀態應為 page_index=0, page_revealed=false, ready_to_complete=false"

	# 181..last-1. ending_step（依當次 page_refs 驗證完整 reveal/advance 序列，攔截漏採與重採）
	var last_idx := checkpoints.size() - 1
	if last_idx <= 180:
		return "缺少 ending_step 與 opening_ready"
	var expected_ending_steps: int = 2 * page_count - 1
	var actual_ending_steps: int = last_idx - 181
	if actual_ending_steps != expected_ending_steps:
		return "ending_step 筆數與 page_refs (%d 頁) 不符：預期 %d 筆，實得 %d 筆" % [
			page_count, expected_ending_steps, actual_ending_steps
		]

	for s in range(expected_ending_steps):
		var k: int = 181 + s
		var cp_step: Dictionary = checkpoints[k]
		if str(cp_step.get("label", "")) != "ending_step":
			return "seq=%d 預期為 ending_step，實得 %s" % [k, str(cp_step.get("label"))]
		var step_state: Dictionary = cp_step["state"] as Dictionary
		var step_flow: Dictionary = step_state["flow"] as Dictionary
		if str(step_flow.get("mode", "")) != "ending":
			return "seq=%d ending_step 的 flow.mode 應為 ending" % k
		var step_active_var: Variant = step_flow.get("active_ending")
		if not (step_active_var is Dictionary):
			return "seq=%d ending_step 缺少 active_ending" % k
		var step_active: Dictionary = step_active_var as Dictionary

		var expected_page_idx: int = int((s + 1) / 2)
		var expected_revealed: bool = (s % 2 == 0)
		var expected_ready: bool = (expected_page_idx == page_count - 1 and expected_revealed)
		var actual_page_idx: int = int(step_active.get("page_index", -1))
		var actual_revealed: bool = bool(step_active.get("page_revealed", not expected_revealed))
		var actual_ready: bool = bool(step_active.get("ready_to_complete", not expected_ready))
		if actual_page_idx != expected_page_idx or actual_revealed != expected_revealed or actual_ready != expected_ready:
			return "seq=%d ending_step 序列異常：預期 (page=%d, revealed=%s, ready=%s)，實得 (page=%d, revealed=%s, ready=%s)" % [
				k,
				expected_page_idx, str(expected_revealed), str(expected_ready),
				actual_page_idx, str(actual_revealed), str(actual_ready),
			]
		var expected_active: Dictionary = active0.duplicate(true)
		expected_active["page_index"] = expected_page_idx
		expected_active["page_revealed"] = expected_revealed
		expected_active["ready_to_complete"] = expected_ready
		if step_active != expected_active:
			return "seq=%d ending_step 的 active_ending 非翻頁欄位與 ending_started 不一致" % k
		if (step_state["run"] as Dictionary) != (cp180_state["run"] as Dictionary) or (step_state["meta"] as Dictionary) != (cp180_state["meta"] as Dictionary):
			return "seq=%d ending_step 期間 run/meta 狀態發生非預期變動" % k

	# last. opening_ready
	var cp_last: Dictionary = checkpoints[last_idx]
	if str(cp_last.get("label", "")) != "opening_ready":
		return "末筆 (seq=%d) 預期為 opening_ready，實得 %s" % [last_idx, str(cp_last.get("label"))]
	var last_state: Dictionary = cp_last["state"] as Dictionary
	if str((last_state["flow"] as Dictionary).get("mode", "")) != "opening":
		return "opening_ready 的 flow.mode 應為 opening"
	if last_state != final_state:
		return "opening_ready 快照與最終 serialize() 不一致"

	return ""


func _write_text_atomic(
	target_path: String,
	content: String,
	after_backup_hook: Callable = Callable()
) -> String:
	var parent_dir := target_path.get_base_dir()
	if not parent_dir.is_empty() and not DirAccess.dir_exists_absolute(parent_dir):
		var mkdir_err := DirAccess.make_dir_recursive_absolute(parent_dir)
		if mkdir_err != OK:
			return "無法建立父目錄 %s (err=%d)" % [parent_dir, mkdir_err]

	var had_target := FileAccess.file_exists(target_path)
	var backup_bytes := PackedByteArray()
	if had_target:
		backup_bytes = FileAccess.get_file_as_bytes(target_path)
		if FileAccess.get_open_error() != OK:
			return "無法讀取既有目標檔作為備份保護 %s (err=%d)" % [target_path, FileAccess.get_open_error()]

	var pid := OS.get_process_id()
	var tmp_path := "%s.tmp.%d" % [target_path, pid]
	var backup_path := "%s.bak.%d" % [target_path, pid]

	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return "無法開啟暫存寫入檔 %s (err=%d)" % [tmp_path, FileAccess.get_open_error()]
	file.store_string(content)
	var write_err := file.get_error()
	file.flush()
	file.close()
	if write_err != OK:
		if FileAccess.file_exists(tmp_path):
			DirAccess.remove_absolute(tmp_path)
		return "寫入暫存檔失敗 %s (err=%d)" % [tmp_path, write_err]

	var written := FileAccess.get_file_as_string(tmp_path)
	if written.is_empty() or written.length() != content.length() or written != content:
		if FileAccess.file_exists(tmp_path):
			DirAccess.remove_absolute(tmp_path)
		return "暫存檔回讀驗證失敗：%s" % tmp_path

	if had_target:
		if FileAccess.file_exists(backup_path):
			var rm_bak_err := DirAccess.remove_absolute(backup_path)
			if rm_bak_err != OK:
				if FileAccess.file_exists(tmp_path):
					DirAccess.remove_absolute(tmp_path)
				return "無法清理舊備份檔 %s (err=%d)" % [backup_path, rm_bak_err]
		var bak_err := DirAccess.rename_absolute(target_path, backup_path)
		if bak_err != OK:
			if FileAccess.file_exists(tmp_path):
				DirAccess.remove_absolute(tmp_path)
			return "無法移置既有目標檔至備份 %s -> %s (err=%d)" % [target_path, backup_path, bak_err]

	if after_backup_hook.is_valid():
		after_backup_hook.call(tmp_path, backup_path, target_path)

	var ren_err := DirAccess.rename_absolute(tmp_path, target_path)
	if ren_err != OK:
		if FileAccess.file_exists(tmp_path):
			DirAccess.remove_absolute(tmp_path)
		if had_target:
			if FileAccess.file_exists(backup_path) and not DirAccess.dir_exists_absolute(target_path):
				DirAccess.rename_absolute(backup_path, target_path)
			var restored_ok := (
				not DirAccess.dir_exists_absolute(target_path)
				and FileAccess.file_exists(target_path)
				and FileAccess.get_file_as_bytes(target_path) == backup_bytes
			)
			if not restored_ok and not DirAccess.dir_exists_absolute(target_path):
				var restore_file := FileAccess.open(target_path, FileAccess.WRITE)
				if restore_file != null:
					restore_file.store_buffer(backup_bytes)
					var restore_write_err := restore_file.get_error()
					restore_file.flush()
					restore_file.close()
					if restore_write_err == OK:
						restored_ok = (
							FileAccess.file_exists(target_path)
							and FileAccess.get_file_as_bytes(target_path) == backup_bytes
						)
			if restored_ok:
				if FileAccess.file_exists(backup_path):
					DirAccess.remove_absolute(backup_path)
				return "暫存檔更名失敗 %s -> %s (err=%d)；原目標檔已完整還原" % [tmp_path, target_path, ren_err]
			return "暫存檔更名失敗 %s -> %s (err=%d)，且原目標檔還原失敗；已保留備份檔：%s" % [
				tmp_path, target_path, ren_err, backup_path
			]
		return "暫存檔更名失敗 %s -> %s (err=%d)" % [tmp_path, target_path, ren_err]

	if had_target and FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)

	return ""


func _run_self_tests(
	checkpoints: Array[Dictionary],
	initial_state: Dictionary,
	final_state: Dictionary
) -> String:
	# 1. 回歸測試：刪除一筆 ending_step 並重新編號 seq，必須被 _validate_checkpoints 攔截
	var missing_step_cps: Array[Dictionary] = []
	for i in range(checkpoints.size()):
		if i == 181:
			continue
		var copy_cp: Dictionary = checkpoints[i].duplicate(true)
		copy_cp["seq"] = missing_step_cps.size()
		missing_step_cps.append(copy_cp)
	if _validate_checkpoints(missing_step_cps, initial_state, final_state).is_empty():
		return "刪除一筆 ending_step 後重新編號未觸發錯誤"

	# 2. 回歸測試：重複一筆 ending_step 並重新編號 seq，必須被 _validate_checkpoints 攔截
	var dup_step_cps: Array[Dictionary] = []
	for i in range(checkpoints.size()):
		var copy_cp: Dictionary = checkpoints[i].duplicate(true)
		copy_cp["seq"] = dup_step_cps.size()
		dup_step_cps.append(copy_cp)
		if i == 181:
			var dup_cp: Dictionary = checkpoints[i].duplicate(true)
			dup_cp["seq"] = dup_step_cps.size()
			dup_step_cps.append(dup_cp)
	if _validate_checkpoints(dup_step_cps, initial_state, final_state).is_empty():
		return "重複一筆 ending_step 後重新編號未觸發錯誤"

	# 3. 回歸測試：刪除一筆並重複另一筆 ending_step（總筆數不變）後重新編號，必須被攔截
	var swapped_step_cps: Array[Dictionary] = []
	for i in range(checkpoints.size()):
		if i == 183:
			continue
		var copy_cp: Dictionary = checkpoints[i].duplicate(true)
		copy_cp["seq"] = swapped_step_cps.size()
		swapped_step_cps.append(copy_cp)
		if i == 181:
			var dup_cp: Dictionary = checkpoints[i].duplicate(true)
			dup_cp["seq"] = swapped_step_cps.size()
			swapped_step_cps.append(dup_cp)
	if _validate_checkpoints(swapped_step_cps, initial_state, final_state).is_empty():
		return "同筆數下漏採並重採 ending_step 未觸發錯誤"

	# 4. 回歸測試：Windows 暫存檔讀取鎖導致 rename 失敗時，原目標檔必須完整保留
	var pid := OS.get_process_id()
	var test_dir := OS.get_temp_dir().path_join("returnfare_w1b_test_%d" % pid).simplify_path()
	var test_target := test_dir.path_join("baseline.json")
	var test_tmp := "%s.tmp.%d" % [test_target, pid]
	var orig_content := "{\"baseline\":true}\n"

	var prep_err := _write_text_atomic(test_target, orig_content)
	if not prep_err.is_empty():
		return "無法建立回歸測試基準檔：%s" % prep_err

	var seed_tmp := FileAccess.open(test_tmp, FileAccess.WRITE)
	if seed_tmp == null:
		DirAccess.remove_absolute(test_target)
		DirAccess.remove_absolute(test_dir)
		return "無法預建暫存鎖測試檔"
	seed_tmp.store_string("seed")
	seed_tmp.close()

	var lock_handle := FileAccess.open(test_tmp, FileAccess.READ)
	var lock_write_err := _write_text_atomic(test_target, "{\"baseline\":false}\n")
	if lock_handle != null:
		lock_handle.close()
	if FileAccess.file_exists(test_tmp):
		DirAccess.remove_absolute(test_tmp)

	var target_exists_after_tmp_lock := FileAccess.file_exists(test_target)
	var target_content_after_tmp_lock := FileAccess.get_file_as_string(test_target) if target_exists_after_tmp_lock else ""

	# 5. 回歸測試：原目標檔本身持有讀取鎖無法移置時，原目標檔必須完整保留
	var target_lock_handle := FileAccess.open(test_target, FileAccess.READ)
	var target_lock_err := _write_text_atomic(test_target, "{\"baseline\":false}\n")
	if target_lock_handle != null:
		target_lock_handle.close()

	var target_exists_after_target_lock := FileAccess.file_exists(test_target)
	var target_content_after_target_lock := FileAccess.get_file_as_string(test_target) if target_exists_after_target_lock else ""

	# 6. 回歸測試：雙重失敗（暫存檔更名失敗 + 備份檔更名與回寫皆失敗，且備份檔本身無外部鎖）時，必須保留唯一備份檔並回報其路徑
	var test_bak := "%s.bak.%d" % [test_target, pid]
	var double_fail_hook := func(_tmp_p: String, _bak_p: String, tgt_p: String) -> void:
		DirAccess.make_dir_recursive_absolute(tgt_p)

	var double_fail_err := _write_text_atomic(test_target, "{\"baseline\":false}\n", double_fail_hook)
	var bak_exists_on_double_fail := FileAccess.file_exists(test_bak)
	var bak_content_on_double_fail := FileAccess.get_file_as_string(test_bak) if bak_exists_on_double_fail else ""

	# 清理測試目錄與殘留檔案
	if DirAccess.dir_exists_absolute(test_target):
		DirAccess.remove_absolute(test_target)
	elif FileAccess.file_exists(test_target):
		DirAccess.remove_absolute(test_target)
	if FileAccess.file_exists(test_bak):
		DirAccess.remove_absolute(test_bak)
	if FileAccess.file_exists(test_tmp):
		DirAccess.remove_absolute(test_tmp)
	if DirAccess.dir_exists_absolute(test_dir):
		DirAccess.remove_absolute(test_dir)

	if lock_write_err.is_empty():
		return "暫存檔持有讀取鎖時 _write_text_atomic 預期應失敗卻成功"
	if not target_exists_after_tmp_lock or target_content_after_tmp_lock != orig_content:
		return "暫存檔更名失敗後原目標檔遺失或內容被破壞"
	if target_lock_err.is_empty():
		return "目標檔持有讀取鎖時 _write_text_atomic 預期應失敗卻成功"
	if not target_exists_after_target_lock or target_content_after_target_lock != orig_content:
		return "目標檔移置失敗後原目標檔遺失或內容被破壞"
	if double_fail_err.is_empty() or not double_fail_err.contains(test_bak):
		return "雙重失敗時未回報保留之備份檔路徑 (實得: %s)" % double_fail_err
	if not bak_exists_on_double_fail or bak_content_on_double_fail != orig_content:
		return "雙重失敗時唯一備份檔被刪除或內容損毀"

	return ""
