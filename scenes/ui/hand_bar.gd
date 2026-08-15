extends VBoxContainer

## 常駐手牌列。訂閱 GameState 的 hand_changed / knowledge_changed，狀態變化立即重繪。
## 全文字實作（P1 版）；正式 UI 整層替換時此檔廢棄。

const _LABEL_EMPTY_HAND := "(空)"
const _LABEL_EMPTY_KNOWLEDGE := "(無)"
const _FMT_SLOTS := "手牌 %d / %d"
const _LABEL_KNOWLEDGE_PREFIX := "知識："

@onready var _slots_label: Label = $SlotsLabel
@onready var _hand_label: Label = $HandLabel
@onready var _knowledge_label: Label = $KnowledgeLabel


func _ready() -> void:
	_slots_label.set_meta("qa_id", "hand_slots")
	_hand_label.set_meta("qa_id", "hand_cards")
	_knowledge_label.set_meta("qa_id", "knowledge_cards")
	GameState.hand_changed.connect(_refresh)
	GameState.knowledge_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	var limit: int = int(Data.tuning("hand_size"))
	_slots_label.text = _FMT_SLOTS % [GameState.hand_slots_used(), limit]
	_hand_label.text = " ".join(GameState.hand) if not GameState.hand.is_empty() else _LABEL_EMPTY_HAND
	var k_keys: Array = GameState.knowledge.keys()
	_knowledge_label.text = _LABEL_KNOWLEDGE_PREFIX + (
		" ".join(k_keys) if not k_keys.is_empty() else _LABEL_EMPTY_KNOWLEDGE
	)
