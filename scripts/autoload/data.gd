extends Node

## Data autoload: 啟動時跑 DataLoader，失敗時 ok = false 擋進遊戲。
## GameState 需在此之前載入（project.godot autoload 順序），
## 因為 _ready 用到 GameState.ACTION_PHASES 做一致性驗證。
## GameState 的取得方式見 _find_game_state()——autoload 不是 Engine singleton。

var loader: DataLoader
var ok: bool = false


func _ready() -> void:
	load_data("res://data/")


func load_data(data_dir: String = "res://data/") -> bool:
	ok = false
	loader = DataLoader.new(data_dir)
	if not loader.load_all():
		for e in loader.errors:
			push_error("[Data] " + e)
		return false

	var refs := loader.verify_references()
	if not refs.is_empty():
		for e in refs:
			push_error("[Data] " + e)
		return false

	# 語彙封閉性 lint 1（規格書第十七節）：未知 condition/effect 鍵擋開機。
	var vocab_problems := DataLoader.lint_vocabulary(loader.beats)
	if not vocab_problems.is_empty():
		for e in vocab_problems:
			push_error("[Data] " + e)
		return false

	# lint 2：有 requires 卻沒填 reject_reason，只警告不擋開機。
	for w in DataLoader.lint_missing_reject_reason(loader.beats):
		push_warning("[Data] " + w)

	# tuning.phases_per_day 只是一致性驗證，它本身不是可調數值（規格書第二節）
	var ppd: Variant = loader.tuning.get("phases_per_day")
	var gs_node := _find_game_state()
	if gs_node == null:
		push_error("[Data] GameState not found (既非 Engine singleton，/root 底下也沒有)")
		return false
	var expected_count: int = gs_node.ACTION_PHASES.size()
	if ppd != expected_count:
		push_error("[Data] tuning.phases_per_day=%s ≠ ACTION_PHASES count=%d" % [
			str(ppd), expected_count
		])
		return false

	ok = true
	return true


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
