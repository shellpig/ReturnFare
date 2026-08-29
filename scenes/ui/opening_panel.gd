extends Control

## 開局選擇面板（規格書 P5-E、開發設計方針 P5-E）。
## 依 GameState.opening_view() 渲染三個固定順序選項，提供預覽、確認與取消。

signal choice_selected(choice_id: String)

const _MSG_TITLE := "出門前的十分鐘"
const _MSG_PROMPT := "雨還在下。玄關放著那幾樣東西，你打算拿哪一樣？"

@onready var _title_label: Label = $TitleLabel
@onready var _prompt_label: Label = $PromptLabel
@onready var _choices_container: VBoxContainer = $ChoicesContainer
@onready var _reason_label: Label = $ReasonLabel
@onready var _confirm_dialog: ConfirmationDialog = $ConfirmDialog

var _pending_choice_id: String = ""


func _ready() -> void:
	_title_label.text = _MSG_TITLE
	_prompt_label.text = _MSG_PROMPT
	_confirm_dialog.confirmed.connect(_on_dialog_confirmed)
	_confirm_dialog.canceled.connect(_on_dialog_canceled)
	_confirm_dialog.get_ok_button().set_meta("qa_id", "dialog_confirm::opening")
	_confirm_dialog.get_cancel_button().set_meta("qa_id", "dialog_cancel::opening")
	refresh()


func refresh() -> void:
	_pending_choice_id = ""
	_reason_label.text = ""
	for child in _choices_container.get_children():
		_choices_container.remove_child(child)
		child.queue_free()

	var choices: Array[Dictionary] = GameState.opening_view()
	for choice in choices:
		var cid := str(choice.get("id", ""))
		var label_text := str(choice.get("label", ""))
		var available := bool(choice.get("available", false))
		var reason := str(choice.get("reason_text", ""))

		var btn := Button.new()
		btn.text = label_text
		btn.set_meta("qa_id", "opening_choice::" + cid)
		btn.disabled = not available
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		if available:
			btn.pressed.connect(_on_choice_pressed.bind(choice))
		else:
			# locked 選項仍可聚焦查看理由（規格書 P5-E）
			btn.focus_entered.connect(_on_locked_focused.bind(reason))
			btn.mouse_entered.connect(_on_locked_focused.bind(reason))
			# 如果當前 reason_label 是空的，可展示預設鎖定提示
			if not reason.is_empty() and _reason_label.text.is_empty():
				_reason_label.text = reason

		_choices_container.add_child(btn)


func _on_locked_focused(reason_text: String) -> void:
	_reason_label.text = reason_text


func _on_choice_pressed(choice: Dictionary) -> void:
	_pending_choice_id = str(choice.get("id", ""))
	_confirm_dialog.title = str(choice.get("label", ""))
	var confirm_msg := str(choice.get("confirm_text", ""))
	if confirm_msg.is_empty():
		confirm_msg = str(choice.get("preview", ""))
	_confirm_dialog.dialog_text = confirm_msg
	_reason_label.text = ""
	_confirm_dialog.popup_centered()


func _on_dialog_confirmed() -> void:
	if _pending_choice_id.is_empty():
		return
	var cid := _pending_choice_id
	_pending_choice_id = ""
	choice_selected.emit(cid)


func _on_dialog_canceled() -> void:
	_pending_choice_id = ""
