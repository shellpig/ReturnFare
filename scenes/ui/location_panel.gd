extends VBoxContainer

## 地點面板：顯示 PanelBuilder.build() 的 view model（beat 標題、文字、槽三態）。
## P1 文字版：OPEN 槽顯示 occupant 或空槽標記；LOCKED 槽顯示 reject_reason；RESOLVED 槽顯示已放記號。
## 面板內任何狀態變化後，呼叫 show_location 整包重繪即可（P1 資料量下全量重算）。

signal closed

@onready var _back_btn: Button = $BackButton
@onready var _beat_container: VBoxContainer = $BeatContainer

var _current_location: String = ""


func _ready() -> void:
	_back_btn.pressed.connect(func(): closed.emit())


func show_location(location_id: String) -> void:
	_current_location = location_id
	_rebuild()


func _rebuild() -> void:
	for child in _beat_container.get_children():
		child.queue_free()

	var view: Dictionary = PanelBuilder.build(_current_location, GameState, Data)

	for beat_view in view["beats"]:
		var beat: Dictionary = beat_view["beat"] as Dictionary
		var tri: int = beat_view["tri"]
		var reason: String = str(beat_view["reason"])

		# Beat 標題
		var title_lbl := Label.new()
		var title_text: String = str(beat.get("title", "（無標題）"))
		if tri == PanelBuilder.TriState.LOCKED:
			title_text += "  [%s]" % reason
		title_lbl.text = "== " + title_text + " =="
		_beat_container.add_child(title_lbl)

		# Beat 主文
		var btext: Variant = beat.get("text")
		if btext is String and not (btext as String).is_empty():
			var text_lbl := Label.new()
			text_lbl.text = btext as String
			text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_beat_container.add_child(text_lbl)

		# 槽列表
		for slot_view in beat_view["slots"]:
			var slot: Dictionary = slot_view["slot"] as Dictionary
			var stri: int = slot_view["tri"]
			var sreason: String = str(slot_view["reason"])
			var label_text: String = str(slot.get("label", slot.get("id", "?")))
			var occupant: Variant = slot.get("occupant")

			var slot_lbl := Label.new()
			match stri:
				PanelBuilder.TriState.OPEN:
					if occupant != null:
						var npc: Dictionary = Data.loader.npcs.get(str(occupant), {}) as Dictionary
						var npc_name: String = str(npc.get("name", occupant))
						slot_lbl.text = "  [出席] %s（%s）" % [npc_name, label_text]
					else:
						slot_lbl.text = "  [空槽] " + label_text
				PanelBuilder.TriState.LOCKED:
					slot_lbl.text = "  [灰] %s  %s" % [label_text, sreason]
				PanelBuilder.TriState.RESOLVED:
					slot_lbl.text = "  [已放] " + label_text
				_:
					slot_lbl.text = "  [?] " + label_text
			_beat_container.add_child(slot_lbl)

		_beat_container.add_child(HSeparator.new())
