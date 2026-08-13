extends Control

## 主場景。P1-C：依時段路由到地圖（白天）、晚間演出（evening）或夜間 stub（night）。

const _MSG_DATA_ERROR := "資料載入失敗，詳情見 Output。"
const _MSG_ENDING_STUB := "[結局 stub]"
const _FMT_STATUS := "第 %d 天  %s  第 %d 章"

@onready var _error_label: Label = $ErrorLabel
@onready var _status_label: Label = $StatusLabel
@onready var _advance_btn: Button = $AdvanceButton
@onready var _map_list: Node = $ContentView/MapList
@onready var _location_panel: Node = $ContentView/LocationPanel
@onready var _evening_label: Label = $ContentView/EveningLabel
@onready var _night_label: Label = $ContentView/NightLabel


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

	_refresh_status()
	_route_view()


func _on_advance_pressed() -> void:
	GameState.advance_phase()


func _on_phase_changed(_day: int, _phase: String) -> void:
	_refresh_status()
	_route_view()


func _on_day_changed(_day: int) -> void:
	_refresh_status()


func _on_chapter_changed(_chapter: int) -> void:
	_refresh_status()


func _on_run_ended(_ending_id: String) -> void:
	_status_label.text += "\n" + _MSG_ENDING_STUB
	_advance_btn.visible = false


func _on_location_selected(loc_id: String) -> void:
	_map_list.visible = false
	_location_panel.visible = true
	_location_panel.call("show_location", loc_id)


func _on_panel_closed() -> void:
	_location_panel.visible = false
	_map_list.visible = true


func _refresh_status() -> void:
	_status_label.text = _FMT_STATUS % [
		GameState.day, GameState.phase, GameState.chapter()
	]


func _route_view() -> void:
	var phase: String = GameState.phase
	match phase:
		"morning", "afternoon":
			_map_list.visible = true
			_location_panel.visible = false
			_evening_label.visible = false
			_night_label.visible = false
			_map_list.call("refresh")
			_advance_btn.visible = true
		"evening":
			_map_list.visible = false
			_location_panel.visible = false
			_evening_label.visible = true
			_night_label.visible = false
			_play_evening()
			_advance_btn.visible = true
		"night":
			_map_list.visible = false
			_location_panel.visible = false
			_evening_label.visible = false
			_night_label.visible = true
			_advance_btn.visible = true


func _play_evening() -> void:
	var lines := PackedStringArray()
	for b in Data.loader.beats:
		var w: Dictionary = b.get("when", {}) as Dictionary
		if int(w.get("day", -1)) != GameState.day:
			continue
		if str(w.get("phase", "")) != "evening":
			continue
		if not b.get("fixed", false):
			continue
		var beat_lines: PackedStringArray = GameState.enter_beat(str(b.get("id", "")))
		lines.append_array(beat_lines)
	_evening_label.text = "\n\n".join(lines)
