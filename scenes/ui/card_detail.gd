extends AcceptDialog

## 卡片詳情與知識清單共用彈窗（P1-H 實作契約）。
## 唯讀，不接任何變更 GameState 的訊號，無 place:: / choose:: 控制項。

@onready var _scroll: ScrollContainer = $ScrollContainer
@onready var _content: VBoxContainer = $ScrollContainer/ContentContainer


func _ready() -> void:
	get_ok_button().set_meta("qa_id", "dialog_confirm::card_detail")
	get_label().visible = false
	# 限制彈窗在 1280x720 視口內
	min_size = Vector2i(560, 360)
	max_size = Vector2i(1000, 600)


func show_card(card_id: String) -> void:
	title = "卡片詳情"
	_clear_content()

	var display_name := Data.card_display_name(card_id)
	var base_id: String = card_id.split("#")[0]
	var card_data: Dictionary = Data.loader.cards.get(base_id, {}) as Dictionary
	var text_content: String = str(card_data.get("text", ""))

	var name_label := Label.new()
	name_label.text = display_name
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = text_content
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(desc_label)

	popup_centered(Vector2i(600, 380))


func show_knowledge(knowledge_dict: Dictionary) -> void:
	title = "知識清單"
	_clear_content()

	if knowledge_dict.is_empty():
		var empty_label := Label.new()
		empty_label.text = "(目前無知識)"
		_content.add_child(empty_label)
	else:
		var k_keys: Array = knowledge_dict.keys()
		k_keys.sort()
		var first := true
		for k_id in k_keys:
			if not first:
				_content.add_child(HSeparator.new())
			first = false

			var display_name := Data.card_display_name(str(k_id))
			var card_data: Dictionary = Data.loader.cards.get(str(k_id), {}) as Dictionary
			var text_content: String = str(card_data.get("text", ""))

			var item_box := VBoxContainer.new()
			item_box.name = "KnowledgeItem_%s" % str(k_id)

			var name_label := Label.new()
			name_label.text = display_name
			name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			item_box.add_child(name_label)

			var desc_label := Label.new()
			desc_label.text = text_content
			desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			item_box.add_child(desc_label)

			_content.add_child(item_box)

	popup_centered(Vector2i(640, 440))


func _clear_content() -> void:
	for child in _content.get_children():
		child.queue_free()
