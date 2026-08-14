class_name FlowText
extends VBoxContainer

## 殘響逐行播出與結局 stub 渲染容器（規格書第十一、十五節，B-03）。

var _lines: PackedStringArray = []


func clear() -> void:
	_lines.clear()
	for child in get_children():
		child.queue_free()


func append_line(text: String) -> void:
	if text.is_empty():
		return
	_lines.append(text)
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(lbl)


func append_lines(lines: PackedStringArray) -> void:
	for l in lines:
		append_line(l)


func get_lines() -> PackedStringArray:
	return _lines


func get_text() -> String:
	return "\n\n".join(_lines)
