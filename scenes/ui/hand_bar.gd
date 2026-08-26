extends VBoxContainer

## 常駐手牌列（P1-H 手牌可讀性）。
## 訂閱 GameState 的 hand_changed / knowledge_changed，狀態變化立即重繪。
## 7 欄格線呈現手牌，顯示卡名與省略符號；知識抽離為獨立入口；點擊開出唯讀詳情。

const CardDetailScene := preload("res://scenes/ui/card_detail.tscn")

const _FMT_SLOTS := "手牌 %d / %d"
const _FMT_KNOWLEDGE := "知識 (%d)"
const _SUFFIX_DELEGATED_TODAY := "（今日已受託）"
const _SUFFIX_DELEGATION_PENDING := "（委託中）"

@onready var _slots_label: Label = $TopRow/SlotsLabel
@onready var _knowledge_btn: Button = $TopRow/KnowledgeButton
@onready var _cards_grid: GridContainer = $ScrollContainer/CardsGrid

var _detail_dialog: AcceptDialog


func _ready() -> void:
	if not Data.ok or Data.loader == null:
		return
	_slots_label.set_meta("qa_id", "hand_slots")
	_knowledge_btn.set_meta("qa_id", "knowledge_entry")
	_knowledge_btn.pressed.connect(_on_knowledge_pressed)

	_detail_dialog = CardDetailScene.instantiate()
	add_child(_detail_dialog)

	GameState.hand_changed.connect(_refresh)
	GameState.knowledge_changed.connect(_refresh)
	_refresh()


## 供 P4-C 委託確認後外部呼叫，強制立即重繪（委託不改動 hand/knowledge，不會自動觸發 hand_changed）。
func refresh() -> void:
	_refresh()


func _refresh() -> void:
	var limit: int = int(Data.tuning("hand_size"))
	_slots_label.text = _FMT_SLOTS % [GameState.hand_slots_used(), limit]

	var k_count: int = GameState.knowledge.size()
	_knowledge_btn.text = _FMT_KNOWLEDGE % k_count

	for child in _cards_grid.get_children():
		child.queue_free()

	_cards_grid.columns = 7
	for card_id: String in GameState.hand:
		var btn := Button.new()
		btn.name = "Card_%s" % card_id.replace("#", "_")
		var display_text := Data.card_display_name(card_id)
		if GameState.madness_clock.has(card_id):
			display_text = "%s (%d天)" % [display_text, maxi(0, int(GameState.madness_clock[card_id]))]
		elif str((Data.loader.cards.get(card_id.split("#")[0], {}) as Dictionary).get("type", "")) == "person":
			var status: Dictionary = GameState.delegation_status(card_id)
			if bool(status.get("has_pending_report", false)):
				display_text += _SUFFIX_DELEGATION_PENDING
			elif bool(status.get("delegated_today", false)):
				display_text += _SUFFIX_DELEGATED_TODAY
		btn.text = display_text
		btn.set_meta("qa_id", "hand_card::%s" % card_id)
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		btn.clip_text = true
		btn.custom_minimum_size = Vector2(120, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_card_pressed.bind(card_id))
		_cards_grid.add_child(btn)


func _on_card_pressed(card_id: String) -> void:
	if _detail_dialog != null and _detail_dialog.has_method("show_card"):
		_detail_dialog.show_card(card_id)


func _on_knowledge_pressed() -> void:
	if _detail_dialog != null and _detail_dialog.has_method("show_knowledge"):
		_detail_dialog.show_knowledge(GameState.knowledge)
