extends VBoxContainer

## 地點面板：先逐一播放 GameState.play_beat()，演完才渲染常態槽位。
## UI 只渲染 GameState.build_panel() / preview_slot() 的結果，不自行判斷規則。

signal closed
signal state_changed
signal night_entry_requested(id: String)

const _LABEL_NO_TITLE := "（無標題）"
const _FMT_BEAT_TITLE := "== %s =="
const _FMT_BEAT_LOCKED_SUFFIX := "  [%s]"
const _PREFIX_SLOT_OCCUPIED := "  [出席] "
const _PREFIX_SLOT_EMPTY := "  [空槽] "
const _FMT_SLOT_LOCKED := "  [灰] %s  %s"
const _PREFIX_SLOT_RESOLVED := "  [已放] "
const _PREFIX_SLOT_UNKNOWN := "  [?] "
const _FMT_PLACE_BUTTON := "放入：%s"
const _FMT_CHOOSE_BUTTON := "選擇：%s"
const _FMT_PLACE_FAILED := "（無法放置：%s）"
const _FMT_SLOT_TYPES := "（收：%s）"
const _FMT_PREVIEW_TITLE := "預覽：%s"
const _FMT_PREVIEW_CARDS := "可放置：%s"
const _MSG_PREVIEW_EMPTY := "目前沒有可放的卡。"

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

const _NIGHT_REJECT_TEXTS := {
	"not_night": "非夜間時段",
	"unknown_location": "未知的地點",
	"not_night_layer": "非夜間地點",
	"teaser": "還沒有走到那裡。",
	"too_early": "時機未到",
	"locked": "條件不足",
	"already_chosen": "今夜已探索過其他地點",
	"already_slept": "今夜已準備就寢",
}

@onready var _back_btn: Button = $BackButton
@onready var _advance_beat_btn: Button = $AdvanceBeatButton
@onready var _night_enter_btn: Button = $NightEnterButton
@onready var _location_title: Label = $LocationTitle
@onready var _description_label: Label = $DescriptionLabel
@onready var _status_label: Label = Label.new()
@onready var _beat_container: VBoxContainer = $ScrollContainer/BeatContainer

var _current_location: String = ""
var _pending_beat_ids: Array[String] = []
var _visit_seen: Dictionary = {}
var _current_beat_id: String = ""
var _current_lines := PackedStringArray()
var _current_played := false
var _is_playing := false
var _preview_dialog: AcceptDialog


func _ready() -> void:
	_back_btn.set_meta("qa_id", "panel_back")
	_advance_beat_btn.set_meta("qa_id", "beat_advance")
	_back_btn.pressed.connect(func(): closed.emit())
	_advance_beat_btn.pressed.connect(_on_advance_beat_pressed)
	_night_enter_btn.pressed.connect(_on_night_enter_pressed)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)
	move_child(_status_label, _back_btn.get_index() + 1)
	_preview_dialog = AcceptDialog.new()
	add_child(_preview_dialog)
	_preview_dialog.get_ok_button().set_meta("qa_id", "dialog_confirm::preview")


func show_location(location_id: String, extra_lines: PackedStringArray = PackedStringArray()) -> void:
	_current_location = location_id
	_night_enter_btn.visible = false
	_status_label.text = "\n".join(extra_lines) if not extra_lines.is_empty() else ""
	_status_label.visible = not extra_lines.is_empty()
	_pending_beat_ids.clear()
	_visit_seen.clear()
	_current_beat_id = ""
	_current_lines = PackedStringArray()
	_current_played = false
	_queue_open_beats()
	_is_playing = not _pending_beat_ids.is_empty()
	_rebuild()


func show_night_details(location_id: String) -> void:
	_current_location = location_id
	_pending_beat_ids.clear()
	_visit_seen.clear()
	_current_beat_id = ""
	_current_lines = PackedStringArray()
	_current_played = false
	_is_playing = false
	_advance_beat_btn.visible = false
	_description_label.visible = false
	_status_label.visible = false
	_status_label.text = ""

	for child in _beat_container.get_children():
		child.queue_free()

	var summary: Dictionary = PanelBuilder.location_summary(location_id, GameState, Data)
	_location_title.text = str(summary.get("display_name", location_id))
	_location_title.visible = true

	var status_text := str(summary.get("status_text", ""))
	if not status_text.is_empty():
		var status_lbl := Label.new()
		status_lbl.text = status_text
		status_lbl.set_meta("qa_id", "night_status::" + location_id)
		_beat_container.add_child(status_lbl)

	var can_enter := bool(summary.get("can_enter", false))
	if not can_enter:
		var reason_text := str(summary.get("reason_text", "")).strip_edges()
		var reason_code := str(summary.get("reason_code", "")).strip_edges()
		var display_reason := reason_text
		if display_reason.is_empty():
			if _NIGHT_REJECT_TEXTS.has(reason_code):
				display_reason = _NIGHT_REJECT_TEXTS[reason_code]
			else:
				display_reason = reason_code
		if not display_reason.is_empty():
			var reason_lbl := Label.new()
			reason_lbl.text = display_reason
			reason_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			reason_lbl.set_meta("qa_id", "night_reason::" + location_id)
			_beat_container.add_child(reason_lbl)

	var warning_text := str(summary.get("warning", "")).strip_edges()
	if not warning_text.is_empty():
		var warn_lbl := Label.new()
		warn_lbl.text = warning_text
		warn_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn_lbl.set_meta("qa_id", "night_warning::" + location_id)
		_beat_container.add_child(warn_lbl)

	_night_enter_btn.visible = true
	_night_enter_btn.text = "進入"
	_night_enter_btn.disabled = not can_enter
	_night_enter_btn.set_meta("qa_id", "night_enter::" + location_id)


func _on_night_enter_pressed() -> void:
	if not _current_location.is_empty():
		night_entry_requested.emit(_current_location)


func _queue_open_beats() -> void:
	var view: Dictionary = GameState.build_panel(_current_location)
	for beat_view: Dictionary in view.get("beats", []) as Array:
		if int(beat_view.get("tri", -1)) != PanelBuilder.TriState.OPEN:
			continue
		var beat_id := str((beat_view["beat"] as Dictionary).get("id", ""))
		if beat_id.is_empty() or _visit_seen.has(beat_id) or _pending_beat_ids.has(beat_id):
			continue
		_pending_beat_ids.append(beat_id)


func _on_advance_beat_pressed() -> void:
	if not _is_playing:
		return
	if not _pending_beat_ids.is_empty():
		_current_beat_id = _pending_beat_ids.pop_front()
		_visit_seen[_current_beat_id] = true
		_current_lines = GameState.play_beat(_current_beat_id)
		_current_played = true
		state_changed.emit()
		_rebuild()
	else:
		_is_playing = false
		_current_beat_id = ""
		_current_lines = PackedStringArray()
		_current_played = false
		_rebuild()


func _rebuild() -> void:
	_night_enter_btn.visible = false
	for child in _beat_container.get_children():
		child.queue_free()

	var view: Dictionary = GameState.build_panel(_current_location)
	var location: Dictionary = view.get("location", {}) as Dictionary
	var location_name := str(location.get("name", _current_location))
	_location_title.text = location_name
	_location_title.visible = true

	if _is_playing:
		_description_label.visible = false
		_advance_beat_btn.visible = true
		_advance_beat_btn.text = "繼續演出"
		if not _current_beat_id.is_empty():
			var current_view := _find_beat(view, _current_beat_id)
			if current_view.is_empty():
				var beat: Dictionary = Data.loader.beats_by_id.get(_current_beat_id, {}) as Dictionary
				current_view = { "beat": beat, "tri": PanelBuilder.TriState.OPEN, "reason": "", "slots": [] }
			_render_beat(current_view, _current_lines, false)
		return

	_advance_beat_btn.visible = false
	var description := str(location.get("desc", "")).strip_edges()
	_description_label.text = description
	_description_label.visible = not description.is_empty()
	for beat_view: Dictionary in view.get("beats", []) as Array:
		_render_beat(beat_view, PackedStringArray(), true)


func _find_beat(view: Dictionary, beat_id: String) -> Dictionary:
	for beat_view: Dictionary in view.get("beats", []) as Array:
		if str((beat_view["beat"] as Dictionary).get("id", "")) == beat_id:
			return beat_view
	return {}


func _render_beat(beat_view: Dictionary, lines: PackedStringArray, show_slots: bool) -> void:
	var beat: Dictionary = beat_view.get("beat", {}) as Dictionary
	var beat_id := str(beat.get("id", ""))
	var tri: int = int(beat_view.get("tri", PanelBuilder.TriState.HIDDEN))
	var reason := str(beat_view.get("reason", ""))

	var title_lbl := Label.new()
	var title_text := str(beat.get("title", _LABEL_NO_TITLE))
	if tri == PanelBuilder.TriState.LOCKED:
		title_text += _FMT_BEAT_LOCKED_SUFFIX % reason
	title_lbl.text = _FMT_BEAT_TITLE % title_text
	_beat_container.add_child(title_lbl)

	if not lines.is_empty():
		for line: String in lines:
			_add_text_label(line)
	else:
		var beat_text: Variant = beat.get("text")
		if beat_text is String and not (beat_text as String).is_empty():
			_add_text_label(beat_text as String)

	if not show_slots:
		_beat_container.add_child(HSeparator.new())
		return

	for slot_view: Dictionary in beat_view.get("slots", []) as Array:
		_render_slot(beat_id, slot_view)
	_beat_container.add_child(HSeparator.new())


func _add_text_label(text: String) -> void:
	var text_lbl := Label.new()
	text_lbl.text = text
	text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_beat_container.add_child(text_lbl)


func _render_slot(beat_id: String, slot_view: Dictionary) -> void:
	var slot: Dictionary = slot_view.get("slot", {}) as Dictionary
	var slot_id := str(slot.get("id", ""))
	var tri: int = int(slot_view.get("tri", PanelBuilder.TriState.HIDDEN))
	var reason := str(slot_view.get("reason", ""))
	var label_text := str(slot.get("label", slot_id if not slot_id.is_empty() else "?"))
	var accept_types: PackedStringArray = slot_view.get("accept_types", PackedStringArray())
	if not accept_types.is_empty():
		label_text += _FMT_SLOT_TYPES % "、".join(accept_types)
	var occupant: Variant = slot.get("occupant")

	var slot_lbl := Label.new()
	slot_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	slot_lbl.set_meta("qa_id", "slot::%s::%s" % [beat_id, slot_id])
	slot_lbl.gui_input.connect(_on_slot_gui_input.bind(beat_id, slot_id))
	match tri:
		PanelBuilder.TriState.OPEN:
			if occupant != null:
				slot_lbl.text = _PREFIX_SLOT_OCCUPIED + label_text
			else:
				slot_lbl.text = _PREFIX_SLOT_EMPTY + label_text
		PanelBuilder.TriState.LOCKED:
			slot_lbl.text = _FMT_SLOT_LOCKED % [label_text, reason]
		PanelBuilder.TriState.RESOLVED:
			slot_lbl.text = _PREFIX_SLOT_RESOLVED + label_text
		_:
			slot_lbl.text = _PREFIX_SLOT_UNKNOWN + label_text
	_beat_container.add_child(slot_lbl)

	var accepts: Array = slot.get("accepts", []) as Array
	if not accepts.is_empty():
		var preview_btn := Button.new()
		preview_btn.text = "預覽"
		preview_btn.set_meta("qa_id", "preview::%s::%s" % [beat_id, slot_id])
		preview_btn.pressed.connect(_show_preview.bind(beat_id, slot_id, label_text))
		_beat_container.add_child(preview_btn)

	if tri != PanelBuilder.TriState.OPEN:
		return

	var is_choice := bool(slot_view.get("is_choice", false))
	if is_choice:
		var choice_group := str(slot.get("choice_group", ""))
		var choose_btn := Button.new()
		choose_btn.text = _FMT_CHOOSE_BUTTON % label_text
		choose_btn.set_meta("qa_id", "choose::%s::%s::%s" % [beat_id, choice_group, slot_id])
		choose_btn.pressed.connect(_on_choose_pressed.bind(beat_id, choice_group, slot_id, ""))
		_beat_container.add_child(choose_btn)

	for card_id: String in GameState.placeable_cards(beat_id, slot_id):
		var place_btn := Button.new()
		place_btn.text = _FMT_PLACE_BUTTON % Data.card_display_name(card_id)
		place_btn.set_meta("qa_id", "place::%s::%s::%s" % [beat_id, slot_id, card_id])
		place_btn.pressed.connect(_on_place_pressed.bind(beat_id, slot_id, card_id))
		_beat_container.add_child(place_btn)


func _on_slot_gui_input(event: InputEvent, beat_id: String, slot_id: String) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			_show_preview(beat_id, slot_id, "")


func _show_preview(beat_id: String, slot_id: String, label_text: String) -> void:
	var result: Dictionary = GameState.preview_slot(beat_id, slot_id)
	var cards: Array = result.get("cards", []) as Array
	var message := _MSG_PREVIEW_EMPTY
	if not cards.is_empty():
		var lines: Array[String] = ["可放置卡片："]
		for card_id_val in cards:
			var card_id := str(card_id_val)
			lines.append("  • %s" % Data.card_display_name(card_id))
		message = "\n".join(lines)
	else:
		var reason := str(result.get("reason", ""))
		if not reason.is_empty():
			message += "\n理由：" + _REASON_CODE_TEXTS.get(reason, reason)
	_preview_dialog.title = _FMT_PREVIEW_TITLE % label_text if not label_text.is_empty() else "預覽"
	_preview_dialog.dialog_text = message
	_preview_dialog.popup_centered()



func _on_place_pressed(beat_id: String, slot_id: String, card_id: String) -> void:
	var result: Dictionary = GameState.try_place(card_id, beat_id, slot_id)
	if result.get("ok", false):
		_status_label.text = "\n".join(result.get("lines", PackedStringArray()))
		_status_label.visible = not _status_label.text.is_empty()
		state_changed.emit()
	else:
		_set_failure_status(result)
	_rebuild()


func _on_choose_pressed(beat_id: String, group_id: String, slot_id: String, card_id: String) -> void:
	var result: Dictionary = GameState.choose(beat_id, group_id, slot_id, card_id)
	if result.get("ok", false):
		_status_label.text = "\n".join(result.get("lines", PackedStringArray()))
		_status_label.visible = not _status_label.text.is_empty()
		state_changed.emit()
	else:
		_set_failure_status(result)
	_rebuild()


static func failure_text(result: Dictionary) -> String:
	var reason_text := str(result.get("reason_text", "")).strip_edges()
	if not reason_text.is_empty():
		return reason_text
	var reason_code := str(result.get("reason_code", "")).strip_edges()
	if _REASON_CODE_TEXTS.has(reason_code):
		return _REASON_CODE_TEXTS[reason_code]
	return reason_code


func _set_failure_status(result: Dictionary) -> void:
	var text := failure_text(result)
	_status_label.text = _FMT_PLACE_FAILED % text
	_status_label.visible = true
