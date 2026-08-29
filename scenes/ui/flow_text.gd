class_name FlowText
extends ScrollContainer

## 殘響逐行播出與結局渲染容器（規格書第十一、十五節，B-03，K-40）。

signal typewriter_completed

var _lines: PackedStringArray = []
var _is_typing: bool = false
var _typing_label: Label = null
var _typing_full_text: String = ""
var _typing_current_chars: float = 0.0
var _typing_speed: float = 35.0

@onready var _container: VBoxContainer = $LinesContainer


func _ensure_container() -> VBoxContainer:
	if _container == null:
		_container = get_node_or_null("LinesContainer")
		if _container == null:
			_container = VBoxContainer.new()
			_container.name = "LinesContainer"
			_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
			add_child(_container)
	return _container


func _process(delta: float) -> void:
	if not _is_typing or _typing_label == null:
		return
	_typing_current_chars += _typing_speed * delta
	var target_chars := int(_typing_current_chars)
	_typing_label.visible_characters = target_chars
	var total: int = _typing_label.get_total_character_count()
	if total <= 0:
		total = _typing_full_text.length()
	if target_chars >= total:
		_typing_label.visible_characters = -1
		_is_typing = false
		typewriter_completed.emit()


func clear() -> void:
	_is_typing = false
	_typing_label = null
	_typing_full_text = ""
	_typing_current_chars = 0.0
	_lines.clear()
	var c := _ensure_container()
	for child in c.get_children():
		child.queue_free()


func append_line(text: String) -> void:
	if text.is_empty():
		return
	_lines.append(text)
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ensure_container().add_child(lbl)


func append_lines(lines: PackedStringArray) -> void:
	for l in lines:
		append_line(l)


func get_lines() -> PackedStringArray:
	return _lines


func get_text() -> String:
	return "\n\n".join(_lines)


## P5-E：啟動逐字播放模式。
func start_typewriter(text: String, chars_per_sec: float = 35.0) -> void:
	clear()
	if text.is_empty():
		typewriter_completed.emit()
		return
	_lines.append(text)
	_typing_full_text = text
	_typing_current_chars = 0.0
	_typing_speed = chars_per_sec
	_is_typing = true
	_typing_label = Label.new()
	_typing_label.text = text
	_typing_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_typing_label.visible_characters = 0
	_ensure_container().add_child(_typing_label)


## P5-E：立即補完當前逐字播放。
func finish_typewriter() -> void:
	if not _is_typing:
		return
	_is_typing = false
	if _typing_label != null:
		_typing_label.visible_characters = -1
	typewriter_completed.emit()


## P5-E：查詢是否正在逐字播放中。
func is_typewriting() -> bool:
	return _is_typing


## P5-E：立即顯示完整文字（不打字）。
func show_text_instant(text: String) -> void:
	clear()
	append_line(text)

