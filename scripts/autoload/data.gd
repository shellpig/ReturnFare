extends Node

## Data autoload: 啟動時跑 DataLoader，失敗時 ok = false 擋進遊戲。
## GameState 需在此之前載入（project.godot autoload 順序），
## 因為 _ready 用到 GameState.ACTION_PHASES 做一致性驗證。
## GameState 的取得方式見 _find_game_state()——autoload 不是 Engine singleton。

const REQUIRED_TUNING_KEYS := [
	"hand_size",
	"phases_per_day",
	"madness_cap",
	"madness_countdown_days",
	"madness_vision_threshold",
	"indulgence.soak_phase_cost",
	"indulgence.soak_cards_cleared",
	"indulgence.forced_light_count",
	"indulgence.forced_normal_until",
]

var loader: DataLoader
var ok: bool = false


func _ready() -> void:
	load_data("res://data/")


func load_data(data_dir: String = "res://data/") -> bool:
	ok = false
	var candidate := DataLoader.new(data_dir)
	var validation := _validate_loader(candidate)
	for e in validation.errors:
		push_error("[Data] " + str(e))
	for w in validation.warnings:
		push_warning("[Data] " + str(w))
	if not validation.errors.is_empty():
		return false
	loader = candidate
	ok = true
	return true


## QA runner 在建立主場景前使用；失敗時不替換目前有效 loader。
func validate_data_root(data_dir: String) -> PackedStringArray:
	var candidate := DataLoader.new(data_dir)
	return _validate_loader(candidate).errors


func _validate_loader(candidate: DataLoader) -> Dictionary:
	var errors: PackedStringArray = []
	var warnings: PackedStringArray = []
	if not candidate.load_all():
		errors.append_array(candidate.errors)
		return {"errors": errors, "warnings": warnings}

	errors.append_array(candidate.verify_references())
	errors.append_array(DataLoader.lint_vocabulary(candidate.beats))
	errors.append_array(DataLoader.lint_card_types(candidate))
	errors.append_array(DataLoader.lint_indulgence_exits(candidate.beats))
	errors.append_array(DataLoader.lint_night_alignment(candidate))
	errors.append_array(DataLoader.lint_night_locations(candidate))
	warnings.append_array(DataLoader.lint_missing_reject_reason(candidate.beats))
	for key: String in REQUIRED_TUNING_KEYS:
		if _candidate_tuning(candidate, key) == null:
			errors.append("tuning.json 缺少必要鍵：%s" % key)

	var ppd: Variant = candidate.tuning.get("phases_per_day")
	var gs_node := _find_game_state()
	if gs_node == null:
		errors.append("GameState not found (既非 Engine singleton，/root 底下也沒有)")
	else:
		var expected_count: int = gs_node.ACTION_PHASES.size()
		if ppd != expected_count:
			errors.append("tuning.phases_per_day=%s ≠ ACTION_PHASES count=%d" % [str(ppd), expected_count])
	return {"errors": errors, "warnings": warnings}


func _candidate_tuning(candidate: DataLoader, key: String) -> Variant:
	var node: Variant = candidate.tuning
	for part in key.split("."):
		if node is Dictionary and node.has(part):
			node = node[part]
		else:
			return null
	return node


## 取得 GameState，兩條路依序試。
##
## **autoload 不是 Engine singleton**——它是掛在 `/root` 底下的節點，
## `Engine.get_singleton()` 只認引擎自己的 singleton 與 `register_singleton()` 註冊過的東西。
## 所以正式遊戲走的是第二條（`/root/GameState`）。
##
## 第一條留著是給 headless fixture 測試：測試自己 `Engine.register_singleton()` 塞一個
## 獨立 instance 進來，就會優先命中它，而不是 autoload 那個。這是刻意的注入接縫。
## `has_singleton()` 的守衛不可省——`get_singleton()` 找不到時會自己 push_error。
func _find_game_state() -> Object:
	if Engine.has_singleton("GameState"):
		return Engine.get_singleton("GameState")
	return get_node_or_null("/root/GameState")


## 讀 tuning.json 的值，key 用點路徑（例：「indulgence.soak_phase_cost」）。
func tuning(key: String, fallback: Variant = null) -> Variant:
	var parts := key.split(".")
	var node: Variant = loader.tuning
	for part in parts:
		if node is Dictionary and node.has(part):
			node = node[part]
		else:
			return fallback
	return node


## 卡槽顯示型別查詢。缺少定義時退回 type id，讓 UI 仍可顯示而不崩潰；
## 正式資料由 lint 9 保證每個已使用型別都有定義。
func card_type_name(type_id: String) -> String:
	if loader == null:
		return type_id
	var card_type: Dictionary = loader.card_types.get(type_id, {}) as Dictionary
	return str(card_type.get("name", type_id))


## 卡片顯示名查詢。自動切除實例後綴（madness#1 -> madness）後查表；
## 缺少定義或查不到時退回原本的 id，讓 UI 仍可顯示且保留除錯線索。
func card_display_name(card_id: String) -> String:
	if loader == null:
		return card_id
	var base_id: String = card_id.split("#")[0]
	var card: Dictionary = loader.cards.get(base_id, {}) as Dictionary
	var name_val: Variant = card.get("name")
	if name_val != null and str(name_val) != "":
		return str(name_val)
	return card_id

