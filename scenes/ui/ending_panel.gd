extends VBoxContainer

## 結局逐頁呈現面板（規格書 P5-E、開發設計方針 P5-E）。
## 讀取 GameState.ending_view()，提供逐字播放、按一下補整頁、再按翻頁、首見/重見跳過。

signal completed

const _MSG_ADVANCE_REVEAL := "顯示全文"
const _MSG_ADVANCE_NEXT := "下一頁"
const _MSG_ADVANCE_COMPLETE := "完成"
const _MSG_SKIP := "跳過"
const _FMT_PAGE := "第 %d / %d 頁"

@onready var _flow_text: FlowText = $EndingFlowText
@onready var _controls_row: HBoxContainer = $ControlsRow
@onready var _advance_btn: Button = $ControlsRow/AdvanceButton
@onready var _skip_btn: Button = $ControlsRow/SkipButton
@onready var _page_label: Label = $ControlsRow/PageLabel

var _current_rendered_page_index: int = -1


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	_advance_btn.set_meta("qa_id", "ending_advance")
	_skip_btn.set_meta("qa_id", "ending_skip")
	_advance_btn.pressed.connect(_on_advance_pressed)
	_skip_btn.pressed.connect(_on_skip_pressed)
	_flow_text.typewriter_completed.connect(_on_typewriter_completed)
	GameState.ending_page_changed.connect(_on_ending_page_changed)


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and (k.keycode == KEY_SPACE or k.keycode == KEY_ENTER or k.keycode == KEY_RIGHT or k.keycode == KEY_DOWN):
			get_viewport().set_input_as_handled()
			_on_advance_pressed()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			_on_advance_pressed()


func reset() -> void:
	_current_rendered_page_index = -1
	if _flow_text != null:
		_flow_text.clear()


func refresh() -> void:
	var view: Dictionary = GameState.ending_view()
	if view.is_empty():
		return

	var idx := int(view.get("page_index", 0))
	var count := int(view.get("page_count", 1))
	var text := str(view.get("page_text", ""))
	var revealed := bool(view.get("page_revealed", false))
	var is_last := bool(view.get("is_last_page", false))
	var can_skip := bool(view.get("can_skip", false))
	var can_complete := bool(view.get("can_complete", false))

	_page_label.text = _FMT_PAGE % [idx + 1, count]

	# Skip 按鈕：首見 ending 畫面完全不建立/顯示；重見同 ending id 且未 ready 時才可見
	_skip_btn.visible = can_skip

	# 若切換了新頁面
	if idx != _current_rendered_page_index:
		_current_rendered_page_index = idx
		if revealed:
			_flow_text.show_text_instant(text)
		else:
			_flow_text.start_typewriter(text)
	else:
		# 同一頁但 revealed 狀態改變（如手動補完或自然播完）
		if revealed and _flow_text.is_typewriting():
			_flow_text.finish_typewriter()

	# 更新推進按鈕文字
	if _flow_text.is_typewriting() or not revealed:
		_advance_btn.text = _MSG_ADVANCE_REVEAL
	elif not is_last:
		_advance_btn.text = _MSG_ADVANCE_NEXT
	else:
		_advance_btn.text = _MSG_ADVANCE_COMPLETE

	_advance_btn.disabled = false


func _on_typewriter_completed() -> void:
	var view: Dictionary = GameState.ending_view()
	if not view.is_empty() and not bool(view.get("page_revealed", false)):
		GameState.reveal_ending_page()


func _on_ending_page_changed() -> void:
	refresh()


func _on_advance_pressed() -> void:
	var view: Dictionary = GameState.ending_view()
	if view.is_empty():
		return

	# ① 逐字未跑完：按一次立即補完全文，當頁 index 不變
	if _flow_text.is_typewriting() or not bool(view.get("page_revealed", false)):
		_flow_text.finish_typewriter()
		var v_now: Dictionary = GameState.ending_view()
		if not bool(v_now.get("page_revealed", false)):
			GameState.reveal_ending_page()
		return

	# ② 已揭露且非末頁：翻下一頁
	if not bool(view.get("is_last_page", false)):
		GameState.advance_ending_page()
		return

	# ③ 已揭露且末頁 ready：完成結局
	if bool(view.get("can_complete", false)):
		GameState.complete_ending()
		completed.emit()


func _on_skip_pressed() -> void:
	var view: Dictionary = GameState.ending_view()
	if bool(view.get("can_skip", false)):
		GameState.skip_seen_ending()
