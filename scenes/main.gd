extends Control

## 主場景。P1-F：白天/夜間地圖、晚間演出（fixed beats + 殘響）、夜間解析、結局迴圈與 FlowText 容器（K-28）。

const ConditionEval := preload("res://scripts/core/condition_eval.gd")

const _MSG_DATA_ERROR := "資料載入失敗，詳情見 Output。"
const _MSG_ENDING_STUB := "[結局 stub]"
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


func _ready() -> void:
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


func _on_run_ended(_ending_id: String) -> void:
	_is_showing_ending = true
	_flow_text.clear()
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
	_location_panel.call("show_location", loc_id)


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
			_map_list.visible = true
			_map_list.offset_top = 0.0
			_map_list.offset_bottom = 400.0
			_location_panel.visible = false
			_flow_text.visible = false
			_map_list.call("refresh")
			_advance_btn.visible = true
		"evening":
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


func _play_evening() -> void:
	_flow_text.clear()
	var lines := GameState.play_evening()
	_flow_text.append_lines(lines)


func _play_night_fixed() -> void:
	_flow_text.clear()
	var lines := GameState.play_night_fixed()
	if lines.size() > 0:
		_flow_text.append_lines(lines)
		_flow_text.visible = true
	else:
		_flow_text.visible = false
