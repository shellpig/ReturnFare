class_name FlowText
extends ScrollContainer

## 殘響逐行播出與結局 stub 渲染容器（規格書第十一、十五節，B-03，K-40）。

var _lines: PackedStringArray = []
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


func clear() -> void:
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
