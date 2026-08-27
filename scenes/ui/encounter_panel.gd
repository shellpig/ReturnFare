extends VBoxContainer

## 遭遇面板（P4-E）。
## 純 View 層：渲染 GameState.encounter_view() 結果，不擁有規則。
## 重用 HandBar / CardDetail 提供卡片詳情預覽。
## mutation 一律經由 signal → main.gd → GameState。

signal intro_acknowledged
signal response_requested(card_id: String)
signal discard_requested(card_id: String)
signal escape_requested(card_ids: Array[String])
signal card_detail_requested(card_id: String)

const _DISABLED_TEXTS := {
	"madness_blocked": "發狂卡無法使用",
	"already_attempted": "本場已嘗試過",
	"card_not_submittable": "無法提交此卡",
}

const _FMT_CAPACITY := "可用格數 %d / %d（壓力佔 %d）"
const _FMT_CANDIDATE_KNOWLEDGE := "%s（知識）"
const _FMT_DISCARD_BTN := "丟棄：%s"
const _FMT_ESCAPE_COST := "逃離（支付 %d 張）"
const _MSG_ESCAPE_FREE := "逃離"
const _FMT_ESCAPE_PAY := "支付 %s 逃離"
const _MSG_INTRO_ACK := "確認開場"
const _MSG_RESPOND_TITLE := "確認提交"
const _FMT_RESPOND_TEXT := "提交「%s」回應遭遇？"
const _MSG_DISCARD_TITLE := "確認丟棄"
const _FMT_DISCARD_TEXT := "丟棄「%s」？這張卡會從手上消失。"
const _MSG_ESCAPE_TITLE := "確認逃離"
const _FMT_ESCAPE_TEXT := "支付「%s」逃離遭遇？"
const _MSG_ESCAPE_FREE_TEXT := "確定逃離遭遇？"

@onready var _demand_label: Label = $DemandLabel
@onready var _capacity_label: Label = $CapacityLabel
@onready var _blocked_container: HBoxContainer = $BlockedContainer
@onready var _scroll: ScrollContainer = $ScrollContainer
@onready var _candidate_container: VBoxContainer = $ScrollContainer/CandidateContainer
@onready var _action_row: HBoxContainer = $ActionRow
@onready var _intro_ack_btn: Button = $IntroAckButton
@onready var _respond_dialog: ConfirmationDialog = $RespondConfirmDialog
@onready var _discard_dialog: ConfirmationDialog = $DiscardConfirmDialog
@onready var _escape_dialog: ConfirmationDialog = $EscapeConfirmDialog

var _pending_respond_card_id := ""
var _pending_discard_card_id := ""
var _pending_escape_card_ids: Array[String] = []


func _ready() -> void:
	_intro_ack_btn.set_meta("qa_id", "encounter_intro_ack")
	_intro_ack_btn.pressed.connect(func(): intro_acknowledged.emit())

	_respond_dialog.get_ok_button().set_meta("qa_id", "dialog_confirm::encounter_respond")
	_respond_dialog.get_cancel_button().set_meta("qa_id", "dialog_cancel::encounter_respond")
	_respond_dialog.confirmed.connect(_on_respond_confirmed)
	_respond_dialog.canceled.connect(func(): _pending_respond_card_id = "")

	_discard_dialog.get_ok_button().set_meta("qa_id", "dialog_confirm::encounter_discard")
	_discard_dialog.get_cancel_button().set_meta("qa_id", "dialog_cancel::encounter_discard")
	_discard_dialog.confirmed.connect(_on_discard_confirmed)
	_discard_dialog.canceled.connect(func(): _pending_discard_card_id = "")

	_escape_dialog.get_ok_button().set_meta("qa_id", "dialog_confirm::encounter_escape")
	_escape_dialog.get_cancel_button().set_meta("qa_id", "dialog_cancel::encounter_escape")
	_escape_dialog.confirmed.connect(_on_escape_confirmed)
	_escape_dialog.canceled.connect(func(): _pending_escape_card_ids.clear())


## 顯示開場確認（intro 階段）。beat text 由 main.gd 放進 FlowText。
func show_intro() -> void:
	_demand_label.visible = false
	_capacity_label.visible = false
	_blocked_container.visible = false
	_scroll.visible = false
	_action_row.visible = false
	_intro_ack_btn.visible = true
	for child in _candidate_container.get_children():
		child.queue_free()
	for child in _blocked_container.get_children():
		child.queue_free()
	for child in _action_row.get_children():
		child.queue_free()


## 顯示回合互動畫面（round 階段）。view 來自 GameState.encounter_view()。
func show_round(view: Dictionary) -> void:
	_intro_ack_btn.visible = false

	# Demand
	var demand_text := str(view.get("demand", ""))
	_demand_label.text = demand_text
	_demand_label.set_meta("qa_id", "encounter_demand")
	_demand_label.visible = true

	# Capacity
	var blocked := int(view.get("blocked_slots", 0))
	var capacity := int(view.get("capacity", 14))
	var available := int(view.get("available_slots", 0))
	_capacity_label.text = _FMT_CAPACITY % [available, capacity, blocked]
	_capacity_label.set_meta("qa_id", "encounter_capacity")
	_capacity_label.visible = true

	# Blocked placeholder slots
	for child in _blocked_container.get_children():
		child.queue_free()
	for i in range(blocked):
		var lbl := Label.new()
		lbl.text = "■"
		lbl.set_meta("qa_id", "encounter_blocked::%d" % i)
		_blocked_container.add_child(lbl)
	_blocked_container.visible = blocked > 0

	# Candidates
	for child in _candidate_container.get_children():
		child.queue_free()

	var candidates: Array = view.get("candidates", []) as Array
	var allow_discard := bool(view.get("allow_discard", false))

	for c: Variant in candidates:
		if not c is Dictionary:
			continue
		var cand := c as Dictionary
		var card_id := str(cand.get("card_id", ""))
		var base_id := str(cand.get("base_id", ""))
		var card_name := str(cand.get("name", card_id))
		var source := str(cand.get("source", "hand"))
		var submittable := bool(cand.get("submittable", false))
		var disabled_reason := str(cand.get("disabled_reason", ""))
		var discardable := bool(cand.get("discardable", false))

		var row := HBoxContainer.new()
		_candidate_container.add_child(row)

		# Main candidate button (submit)
		var btn := Button.new()
		var display_name := card_name
		if source == "knowledge":
			display_name = _FMT_CANDIDATE_KNOWLEDGE % card_name
		btn.text = display_name
		btn.set_meta("qa_id", "encounter_candidate::%s" % card_id)
		btn.disabled = not submittable
		if not submittable and not disabled_reason.is_empty():
			btn.tooltip_text = _DISABLED_TEXTS.get(disabled_reason, disabled_reason)
			var reason_text: String = _DISABLED_TEXTS.get(disabled_reason, disabled_reason)
			btn.text += "  [%s]" % reason_text
		btn.custom_minimum_size = Vector2(200, 36)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_candidate_pressed.bind(card_id, card_name))
		btn.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				_on_card_detail_pressed(card_id)
		)
		row.add_child(btn)

		# Detail button (opens CardDetail)
		var detail_btn := Button.new()
		detail_btn.text = "詳情"
		detail_btn.set_meta("qa_id", "encounter_detail::%s" % card_id)
		detail_btn.pressed.connect(_on_card_detail_pressed.bind(card_id))
		row.add_child(detail_btn)

		# Discard button (if allowed and card is discardable hand card, not madness)
		if allow_discard and source == "hand" and discardable and base_id != "madness":
			var discard_btn := Button.new()
			discard_btn.text = _FMT_DISCARD_BTN % card_name
			discard_btn.set_meta("qa_id", "encounter_discard::%s" % card_id)
			discard_btn.pressed.connect(_on_discard_btn_pressed.bind(card_id, card_name))
			row.add_child(discard_btn)

	_scroll.visible = true

	# Action row — escape
	for child in _action_row.get_children():
		child.queue_free()

	var can_escape := bool(view.get("can_escape", false))
	if can_escape:
		var esc_cost_raw: Variant = view.get("escape_cost")
		var esc_cost := int(esc_cost_raw) if esc_cost_raw != null else 0
		if esc_cost == 0:
			var escape_btn := Button.new()
			escape_btn.text = _MSG_ESCAPE_FREE
			escape_btn.set_meta("qa_id", "encounter_escape")
			escape_btn.pressed.connect(_on_escape_free_pressed)
			_action_row.add_child(escape_btn)
		else:
			# Per-card escape payment buttons (D8: cost 1)
			for c: Variant in candidates:
				if not c is Dictionary:
					continue
				var cand := c as Dictionary
				if str(cand.get("source", "")) != "hand":
					continue
				if str(cand.get("base_id", "")) == "madness":
					continue
				if not bool(cand.get("discardable", false)):
					continue
				var esc_card_id := str(cand.get("card_id", ""))
				var esc_card_name := str(cand.get("name", esc_card_id))
				var pay_btn := Button.new()
				pay_btn.text = _FMT_ESCAPE_PAY % esc_card_name
				pay_btn.set_meta("qa_id", "encounter_escape_pay::%s" % esc_card_id)
				pay_btn.pressed.connect(_on_escape_pay_pressed.bind(esc_card_id, esc_card_name))
				_action_row.add_child(pay_btn)

	_action_row.visible = can_escape and _action_row.get_child_count() > 0


func _on_card_detail_pressed(card_id: String) -> void:
	card_detail_requested.emit(card_id)


func _on_candidate_pressed(card_id: String, card_name: String) -> void:
	_pending_respond_card_id = card_id
	_respond_dialog.title = _MSG_RESPOND_TITLE
	_respond_dialog.dialog_text = _FMT_RESPOND_TEXT % card_name
	_respond_dialog.popup_centered()


func _on_respond_confirmed() -> void:
	if _pending_respond_card_id.is_empty():
		return
	var cid := _pending_respond_card_id
	_pending_respond_card_id = ""
	response_requested.emit(cid)


func _on_discard_btn_pressed(card_id: String, card_name: String) -> void:
	_pending_discard_card_id = card_id
	_discard_dialog.title = _MSG_DISCARD_TITLE
	_discard_dialog.dialog_text = _FMT_DISCARD_TEXT % card_name
	_discard_dialog.popup_centered()


func _on_discard_confirmed() -> void:
	if _pending_discard_card_id.is_empty():
		return
	var cid := _pending_discard_card_id
	_pending_discard_card_id = ""
	discard_requested.emit(cid)


func _on_escape_free_pressed() -> void:
	_pending_escape_card_ids.clear()
	_escape_dialog.title = _MSG_ESCAPE_TITLE
	_escape_dialog.dialog_text = _MSG_ESCAPE_FREE_TEXT
	_escape_dialog.popup_centered()


func _on_escape_pay_pressed(card_id: String, card_name: String) -> void:
	_pending_escape_card_ids = [card_id]
	_escape_dialog.title = _MSG_ESCAPE_TITLE
	_escape_dialog.dialog_text = _FMT_ESCAPE_TEXT % card_name
	_escape_dialog.popup_centered()


func _on_escape_confirmed() -> void:
	var ids: Array[String] = _pending_escape_card_ids.duplicate()
	_pending_escape_card_ids.clear()
	escape_requested.emit(ids)
