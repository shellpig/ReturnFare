extends Control

## 主場景。P1-F：白天/夜間地圖、晚間演出（fixed beats + 殘響）、夜間解析、結局迴圈與 FlowText 容器（K-28）。

const ConditionEval := preload("res://scripts/core/condition_eval.gd")
const QAValidationClass := preload("res://tests/ui_sim/qa_validation.gd")

const _MSG_DATA_ERROR := "資料載入失敗，詳情見 Output。"
const _MSG_ENDING_STUB := "[結局 stub]"
const _MSG_ENDING_MADNESS_BE := "[發瘋 BE]"
const _MSG_ADVANCE := "推進時段"
const _MSG_ADVANCE_HINT := "推進時段（目前無可做動作）"
const _FMT_STATUS := "第 %d 天  %s  第 %d 章"

@onready var _error_label: Label = $ErrorLabel
@onready var _status_label: Label = $StatusLabel
@onready var _advance_btn: Button = $AdvanceButton
@onready var _map_list: Node = $ContentView/MapList
@onready var _location_panel: Node = $ContentView/LocationPanel
@onready var _flow_text: FlowText = $ContentView/FlowText

var _is_showing_ending := false


func _enter_tree() -> void:
	_process_cli_args()


func _ready() -> void:
	_advance_btn.set_meta("qa_id", "phase_advance")

	if not Data.ok:
		_error_label.text = _MSG_DATA_ERROR
		_status_label.visible = false
		_advance_btn.visible = false
		return

	_advance_btn.pressed.connect(_on_advance_pressed)
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.day_changed.connect(_on_day_changed)
	GameState.chapter_changed.connect(_on_chapter_changed)
	GameState.run_ended.connect(_on_run_ended)

	_map_list.location_selected.connect(_on_location_selected)
	_location_panel.closed.connect(_on_panel_closed)
	_location_panel.state_changed.connect(_on_location_panel_state_changed)

	_refresh_status()
	_route_view()


func _process_cli_args() -> void:
	if not OS.is_debug_build() and not OS.has_feature("editor"):
		return

	var args: PackedStringArray = OS.get_cmdline_user_args()
	var data_root := ""
	var state_path := ""

	var i := 0
	while i < args.size():
		match args[i]:
			"--data-root":
				if i + 1 < args.size() and not args[i + 1].begins_with("--"):
					data_root = args[i + 1]
					i += 1
				else:
					printerr("ERROR: --data-root 缺少有效路徑參數")
					get_tree().quit(1)
					return
			"--state":
				if i + 1 < args.size() and not args[i + 1].begins_with("--"):
					state_path = args[i + 1]
					i += 1
				else:
					printerr("ERROR: --state 缺少有效檔案路徑參數")
					get_tree().quit(1)
					return
		i += 1

	if not data_root.is_empty():
		var normalized := data_root.replace("\\", "/")
		if normalized.ends_with("/"):
			normalized = normalized.substr(0, normalized.length() - 1)
		normalized += "/"
		var ok: bool = Data.load_data(normalized)
		if not ok:
			printerr("ERROR: --data-root 載入失敗: %s" % normalized)
			get_tree().quit(1)
			return

	if not state_path.is_empty():
		if not FileAccess.file_exists(state_path):
			printerr("ERROR: --state 檔案不存在: %s" % state_path)
			get_tree().quit(1)
			return
		var text := FileAccess.get_file_as_string(state_path)
		var json_val: Variant = JSON.parse_string(text)
		if json_val == null or not (json_val is Dictionary):
			printerr("ERROR: --state JSON 解析失敗: %s" % state_path)
			get_tree().quit(1)
			return
		var err_msg: String = QAValidationClass.validate_state_json(json_val as Dictionary, GameState.serialize(), GameState.PHASES)
		if not err_msg.is_empty():
			printerr("ERROR: --state 狀態檔不合法: %s (%s)" % [err_msg, state_path])
			get_tree().quit(1)
			return
		GameState.deserialize(json_val as Dictionary)


func _on_advance_pressed() -> void:
	if _is_showing_ending:
		_is_showing_ending = false
		_route_view()
		return

	if GameState.phase == "night":
		GameState.sleep_night()
	GameState.advance_phase()


func _on_phase_changed(_day: int, _phase: String) -> void:
	_refresh_status()
	if not _is_showing_ending:
		_route_view()


func _on_day_changed(_day: int) -> void:
	_refresh_status()


func _on_chapter_changed(_chapter: int) -> void:
	_refresh_status()


func _on_run_ended(ending_id: String) -> void:
	_is_showing_ending = true
	_flow_text.clear()
	if ending_id == "ending_madness_be":
		_flow_text.append_line(_MSG_ENDING_MADNESS_BE)
	else:
		_flow_text.append_line(_MSG_ENDING_STUB)
	_flow_text.visible = true
	_map_list.visible = false
	_location_panel.visible = false
	_advance_btn.visible = true


func _on_location_selected(loc_id: String) -> void:
	_flow_text.visible = false
	_map_list.visible = false
	_location_panel.visible = true
	_advance_btn.disabled = true
	var extra_lines := PackedStringArray()
	if GameState.phase == "night":
		extra_lines = GameState.open_night_marker(loc_id)
	if _is_showing_ending:
		return
	_location_panel.call("show_location", loc_id, extra_lines)


func _on_panel_closed() -> void:
	_location_panel.visible = false
	_advance_btn.disabled = false
	_route_view()


func _on_location_panel_state_changed() -> void:
	_refresh_advance_hint()


func _refresh_status() -> void:
	_status_label.text = _FMT_STATUS % [
		GameState.day, GameState.phase, GameState.chapter()
	]
	_refresh_advance_hint()


func _refresh_advance_hint() -> void:
	if GameState.phase == "morning" or GameState.phase == "afternoon":
		var has_action: bool = GameState.has_any_legal_action()
		_advance_btn.text = _MSG_ADVANCE if has_action else _MSG_ADVANCE_HINT
		_advance_btn.modulate = Color.WHITE if has_action else Color(1.0, 0.82, 0.4)
	else:
		_advance_btn.text = _MSG_ADVANCE
		_advance_btn.modulate = Color.WHITE


func _route_view() -> void:
	_advance_btn.disabled = false
	if _is_showing_ending:
		_flow_text.visible = true
		_flow_text.offset_top = 0.0
		_flow_text.offset_bottom = 400.0
		_map_list.visible = false
		_location_panel.visible = false
		_advance_btn.visible = true
		return

	var phase: String = GameState.phase
	match phase:
		"morning", "afternoon":
			_location_panel.visible = false
			_play_forced_lines()
			_map_list.visible = true
			if _flow_text.visible:
				_flow_text.offset_top = 0.0
				_flow_text.offset_bottom = 120.0
				_map_list.offset_top = 130.0
				_map_list.offset_bottom = 400.0
			else:
				_map_list.offset_top = 0.0
				_map_list.offset_bottom = 400.0
			_map_list.call("refresh")
			_advance_btn.visible = true
		"evening":
			if GameState.day == GameState.LAST_DAY:
				_show_final_coda()
			else:
				_map_list.visible = false
				_location_panel.visible = false
				_play_evening()
				_flow_text.visible = true
				_flow_text.offset_top = 0.0
				_flow_text.offset_bottom = 400.0
				_advance_btn.visible = true
		"night":
			_location_panel.visible = false
			_play_night_fixed()
			_map_list.visible = true
			if _flow_text.visible:
				_flow_text.offset_top = 0.0
				_flow_text.offset_bottom = 120.0
				_map_list.offset_top = 130.0
				_map_list.offset_bottom = 400.0
			else:
				_map_list.offset_top = 0.0
				_map_list.offset_bottom = 400.0
			_map_list.call("refresh")
			_advance_btn.visible = true


func _play_forced_lines() -> void:
	_flow_text.clear()
	var lines: PackedStringArray = GameState.last_forced_lines
	if lines.size() > 0:
		_flow_text.append_lines(lines)
		_flow_text.visible = true
	else:
		_flow_text.visible = false


func _play_evening() -> void:
	_flow_text.clear()
	var lines := GameState.play_evening()
	_flow_text.append_lines(lines)


func _show_final_coda() -> void:
	# d45_then 是 evening 的真 beat；它必須先經過地點面板，才能讓
	# compare_registry 走正式 UI 放置入口，而不是由 headless 直接 try_place。
	var placed: Dictionary = GameState.slots_placed as Dictionary
	var coda_done := placed.has("d45_then::compare_registry")
	_map_list.visible = false
	_flow_text.visible = false
	_advance_btn.visible = true
	if not coda_done:
		_location_panel.visible = true
		_advance_btn.disabled = true
		_location_panel.call("show_location", "jinghe_back")
		return

	_location_panel.visible = false
	_flow_text.clear()
	_flow_text.append_line("[結局 coda 已完成]")
	_flow_text.visible = true
	_flow_text.offset_top = 0.0
	_flow_text.offset_bottom = 400.0
	_advance_btn.disabled = false


func _play_night_fixed() -> void:
	_flow_text.clear()
	var lines := GameState.play_night_fixed()
	if lines.size() > 0:
		_flow_text.append_lines(lines)
		_flow_text.visible = true
	else:
		_flow_text.visible = false
