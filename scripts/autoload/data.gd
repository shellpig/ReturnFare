extends Node

## Data autoload: 啟動時跑 DataLoader，失敗時 ok = false 擋進遊戲。
## GameState 需在此之前載入（project.godot autoload 順序），
## 因為 _ready 用到 GameState.ACTION_PHASES 做一致性驗證。

var loader: DataLoader
var ok: bool = false


func _ready() -> void:
	loader = DataLoader.new()
	if not loader.load_all():
		for e in loader.errors:
			push_error("[Data] " + e)
		return

	var refs := loader.verify_references()
	if not refs.is_empty():
		for e in refs:
			push_error("[Data] " + e)
		return

	# tuning.phases_per_day 只是一致性驗證，它本身不是可調數值（規格書第二節）
	# Engine.get_singleton 讓 headless fixture 測試也能用（--script 模式無 autoload 全域名）
	var ppd: Variant = loader.tuning.get("phases_per_day")
	var gs_node := Engine.get_singleton("GameState")
	if gs_node == null:
		push_error("[Data] GameState singleton not found")
		return
	var expected_count: int = gs_node.ACTION_PHASES.size()
	if ppd != expected_count:
		push_error("[Data] tuning.phases_per_day=%s ≠ ACTION_PHASES count=%d" % [
			str(ppd), expected_count
		])
		return

	ok = true


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
