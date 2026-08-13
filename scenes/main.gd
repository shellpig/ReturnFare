extends Control

const _MSG_DATA_ERROR := "資料載入失敗，詳情見 Output。"
const _MSG_ENDING_STUB := "[結局 stub]"

@onready var _error_label: Label = $ErrorLabel
@onready var _status_label: Label = $StatusLabel
@onready var _advance_btn: Button = $AdvanceButton


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
	_refresh()


func _on_advance_pressed() -> void:
	GameState.advance_phase()


func _on_phase_changed(_day: int, _phase: String) -> void:
	_refresh()


func _on_day_changed(_day: int) -> void:
	_refresh()


func _on_chapter_changed(_chapter: int) -> void:
	_refresh()


func _on_run_ended(_ending_id: String) -> void:
	_status_label.text += "\n" + _MSG_ENDING_STUB
	_advance_btn.visible = false


func _refresh() -> void:
	_status_label.text = "第 %d 天  %s  第 %d 章" % [
		GameState.day, GameState.phase, GameState.chapter()
	]
