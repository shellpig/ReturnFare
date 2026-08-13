extends VBoxContainer

## 地點面板：顯示 GameState.open_panel() 的 view model（beat 標題、文字、槽三態）。
## P1 文字版：OPEN 槽顯示 occupant／可放置卡按鈕；LOCKED 槽顯示 reject_reason；RESOLVED 槽顯示已放記號。
## 放置一律走 GameState.try_place()（放置的唯一入口，UI 內不做任何判斷），
## 可放置卡列表由 GameState.placeable_cards() 提供（UI 內不做 accepts 與 action_spent 檢查），
## 面板內任何狀態變化後，呼叫 show_location 整包重繪即可（P1 資料量下全量重算）。

signal closed

const _LABEL_NO_TITLE := "（無標題）"
const _FMT_BEAT_TITLE := "== %s =="
const _FMT_BEAT_LOCKED_SUFFIX := "  [%s]"
const _FMT_SLOT_OCCUPIED := "  [出席] %s（%s）"
const _PREFIX_SLOT_EMPTY := "  [空槽] "
const _FMT_SLOT_LOCKED := "  [灰] %s  %s"
const _PREFIX_SLOT_RESOLVED := "  [已放] "
const _PREFIX_SLOT_UNKNOWN := "  [?] "
const _FMT_PLACE_BUTTON := "放入：%s"
const _FMT_PLACE_FAILED := "（無法放置：%s）"

const _REASON_CODE_TEXTS := {
	"not_held": "未持有此卡",
	"hidden": "此事件未出現",
	"resolved": "此格已放置完成",
	"not_accepted": "卡片類型不符",
	"action_spent": "本時段行動已用完",
	"unknown_beat": "未知的事件",
	"unknown_slot": "未知的卡槽",
	"locked": "條件不足",
}

@onready var _back_btn: Button = $BackButton
@onready var _status_label: Label = Label.new()
@onready var _beat_container: VBoxContainer = $BeatContainer

var _current_location: String = ""


func _ready() -> void:
	_back_btn.pressed.connect(func(): closed.emit())
	add_child(_status_label)
	move_child(_status_label, _back_btn.get_index() + 1)


func show_location(location_id: String) -> void:
	_current_location = location_id
	_status_label.text = ""
	_rebuild()


func _rebuild() -> void:
	for child in _beat_container.get_children():
		child.queue_free()

	var view: Dictionary = GameState.open_panel(_current_location)

	for beat_view in view.get("beats", []):
		var beat: Dictionary = beat_view["beat"] as Dictionary
		var beat_id: String = str(beat.get("id", ""))
		var tri: int = beat_view["tri"]
		var reason: String = str(beat_view["reason"])

		# Beat 標題
		var title_lbl := Label.new()
		var title_text: String = str(beat.get("title", _LABEL_NO_TITLE))
		if tri == PanelBuilder.TriState.LOCKED:
			title_text += _FMT_BEAT_LOCKED_SUFFIX % reason
		title_lbl.text = _FMT_BEAT_TITLE % title_text
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
						slot_lbl.text = _FMT_SLOT_OCCUPIED % [npc_name, label_text]
					else:
						slot_lbl.text = _PREFIX_SLOT_EMPTY + label_text
				PanelBuilder.TriState.LOCKED:
					slot_lbl.text = _FMT_SLOT_LOCKED % [label_text, sreason]
				PanelBuilder.TriState.RESOLVED:
					slot_lbl.text = _PREFIX_SLOT_RESOLVED + label_text
				_:
					slot_lbl.text = _PREFIX_SLOT_UNKNOWN + label_text
			_beat_container.add_child(slot_lbl)

			if stri == PanelBuilder.TriState.OPEN:
				var slot_id: String = str(slot.get("id", ""))
				for card_id in GameState.placeable_cards(beat_id, slot_id):
					var place_btn := Button.new()
					place_btn.text = _FMT_PLACE_BUTTON % _card_display_name(card_id)
					place_btn.pressed.connect(_on_place_pressed.bind(beat_id, slot_id, card_id))
					_beat_container.add_child(place_btn)

		_beat_container.add_child(HSeparator.new())


func _card_display_name(card_id: String) -> String:
	var base_id: String = card_id.split("#")[0]
	var card: Dictionary = Data.loader.cards.get(base_id, {}) as Dictionary
	return str(card.get("name", card_id))


func _on_place_pressed(beat_id: String, slot_id: String, card_id: String) -> void:
	var result: Dictionary = GameState.try_place(card_id, beat_id, slot_id)
	if result.get("ok", false):
		_status_label.text = ""
	else:
		var text: String = str(result.get("reason_text", ""))
		if text.is_empty():
			var code: String = str(result.get("reason_code", result.get("reason", "")))
			text = _REASON_CODE_TEXTS.get(code, code)
		_status_label.text = _FMT_PLACE_FAILED % text
	_rebuild()
