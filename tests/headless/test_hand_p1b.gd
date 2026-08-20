extends SceneTree

## P1-B headless 驗收測試：手牌群 gain_card / lose_card / has_card / serialize。
## 跑法：
##   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/test_hand_p1b.gd
## 全綠 exit 0；任一失敗 exit 1。

## 已知 card id（來自 data/cards.json）
const ID_PROTAGONIST := "protagonist"
const ID_KNOWLEDGE    := "k_forty_something"
const ID_INFO         := "info_husband_version"
const ID_MADNESS      := "madness"


func _initialize() -> void:
	# 手動建立兩個 singleton。
	# get_root().add_child() 讓 _ready() 在第一幀執行，所以先等一幀再繼續。
	var gs: Node = load("res://scripts/autoload/game_state.gd").new()
	gs.name = "GameState"
	get_root().add_child(gs)
	Engine.register_singleton("GameState", gs)

	var data_node: Node = load("res://scripts/autoload/data.gd").new()
	data_node.name = "Data"
	get_root().add_child(data_node)
	Engine.register_singleton("Data", data_node)

	# 等第一幀：讓 _ready() 執行完
	await process_frame

	if not data_node.get("ok"):
		push_error("P1-B: Data failed to load; abort")
		quit(1)
		return

	var failed := 0
	failed += _test_knowledge_routing(gs)
	failed += _test_info_gain_unique(gs)
	failed += _test_protagonist_gain_lose(gs)
	failed += _test_madness_multi_instance(gs)
	failed += _test_slots_used(gs)
	failed += _test_serialize_roundtrip(gs)
	failed += _test_hand_overflow_warning(gs)

	Engine.unregister_singleton("Data")
	Engine.unregister_singleton("GameState")

	if failed > 0:
		push_error("P1-B: %d test(s) failed" % failed)
		quit(1)
	else:
		print("P1-B: all tests passed")
		quit(0)


func _ok(msg: String) -> int:
	print("  ok  " + msg)
	return 0


func _fail(msg: String) -> int:
	push_error("  FAIL  " + msg)
	return 1


# knowledge 型別卡 → 進 knowledge，不進 hand；重複取得 no-op
func _test_knowledge_routing(gs: Node) -> int:
	print("--- knowledge_routing ---")
	_reset(gs)
	gs.call("gain_card", ID_KNOWLEDGE)
	var failed := 0
	if not gs.get("knowledge").has(ID_KNOWLEDGE):
		failed += _fail("knowledge not in knowledge dict after gain")
	else:
		failed += _ok("gain knowledge → knowledge dict")
	if gs.get("hand").has(ID_KNOWLEDGE):
		failed += _fail("knowledge appeared in hand (should never)")
	else:
		failed += _ok("knowledge not in hand")

	gs.call("gain_card", ID_KNOWLEDGE)
	if gs.get("knowledge").size() != 1:
		failed += _fail("gain same knowledge twice: size=%d (expect 1)" % gs.get("knowledge").size())
	else:
		failed += _ok("gain same knowledge twice: no-op (idempotent)")
	return failed


# 一般卡（info）→ 進 hand；重複取得 no-op
func _test_info_gain_unique(gs: Node) -> int:
	print("--- info_gain_unique ---")
	_reset(gs)
	gs.call("gain_card", ID_INFO)
	var failed := 0
	if not gs.get("hand").has(ID_INFO):
		failed += _fail("info not in hand after gain")
	else:
		failed += _ok("gain info → hand")

	gs.call("gain_card", ID_INFO)
	var count := 0
	for c in gs.get("hand"):
		if c == ID_INFO:
			count += 1
	if count != 1:
		failed += _fail("gain same info twice: count=%d (expect 1)" % count)
	else:
		failed += _ok("gain same info twice: no-op (idempotent)")

	gs.call("lose_card", ID_INFO)
	if gs.get("hand").has(ID_INFO):
		failed += _fail("info still in hand after lose")
	else:
		failed += _ok("lose info → removed from hand")
	return failed


# protagonist → 進 hand；lose protagonist = push_error（不 crash，不改狀態）
func _test_protagonist_gain_lose(gs: Node) -> int:
	print("--- protagonist_gain_lose ---")
	_reset(gs)
	gs.call("gain_card", ID_PROTAGONIST)
	var failed := 0
	if not gs.get("hand").has(ID_PROTAGONIST):
		failed += _fail("protagonist not in hand after gain")
	else:
		failed += _ok("gain protagonist → hand")

	var size_before: int = gs.get("hand").size()
	gs.call("lose_card", ID_PROTAGONIST)
	if gs.get("hand").size() != size_before:
		failed += _fail("hand size changed after lose protagonist (should be push_error only)")
	else:
		failed += _ok("lose protagonist: hand unchanged (push_error only)")
	return failed


# madness → 多實例；每次 gain 新建一個 id
func _test_madness_multi_instance(gs: Node) -> int:
	print("--- madness_multi_instance ---")
	_reset(gs)
	gs.call("gain_card", ID_MADNESS)
	gs.call("gain_card", ID_MADNESS)
	var hand: Array = gs.get("hand")
	var failed := 0

	if hand.size() != 2:
		failed += _fail("madness: expected 2 instances in hand, got %d" % hand.size())
	else:
		failed += _ok("madness: 2 distinct instances in hand")
	if hand.size() >= 2 and hand[0] == hand[1]:
		failed += _fail("madness: two instances have same id '%s'" % hand[0])
	elif hand.size() >= 2:
		failed += _ok("madness: instance ids are distinct (%s / %s)" % [hand[0], hand[1]])

	var inst0: String = hand[0]
	gs.call("lose_card", inst0)
	var hand_after: Array = gs.get("hand")
	if hand_after.has(inst0):
		failed += _fail("madness instance still in hand after lose")
	else:
		failed += _ok("lose madness instance: removed from hand")
	if hand_after.size() != 1:
		failed += _fail("hand size after lose one madness: %d (expect 1)" % hand_after.size())
	else:
		failed += _ok("hand size after lose one madness: 1")
	return failed


# hand_slots_used = hand.size()；knowledge 不計入
func _test_slots_used(gs: Node) -> int:
	print("--- slots_used ---")
	_reset(gs)
	gs.call("gain_card", ID_PROTAGONIST)
	gs.call("gain_card", ID_INFO)
	gs.call("gain_card", ID_KNOWLEDGE)

	var slots: int = gs.call("hand_slots_used")
	var failed := 0
	if slots != 2:
		failed += _fail("hand_slots_used: expect 2 (protagonist+info), got %d" % slots)
	else:
		failed += _ok("hand_slots_used: 2 (knowledge not counted)")
	if gs.call("has_card", ID_KNOWLEDGE):
		failed += _ok("has_card(knowledge): true")
	else:
		failed += _fail("has_card(knowledge): should be true (in knowledge dict)")
	if not gs.call("has_knowledge", ID_KNOWLEDGE):
		failed += _fail("has_knowledge: should be true")
	else:
		failed += _ok("has_knowledge: true")
	return failed


# serialize/deserialize: hand + knowledge 往返相等（meta 層保留 knowledge）
func _test_serialize_roundtrip(gs: Node) -> int:
	print("--- serialize_roundtrip_p1b ---")
	_reset(gs)
	gs.call("gain_card", ID_PROTAGONIST)
	gs.call("gain_card", ID_INFO)
	gs.call("gain_card", ID_KNOWLEDGE)

	var snap: Dictionary = gs.call("serialize")
	var json_str := JSON.stringify(snap)
	var parsed: Dictionary = JSON.parse_string(json_str)

	_reset(gs)
	gs.call("deserialize", parsed)

	var failed := 0
	if not gs.get("hand").has(ID_PROTAGONIST):
		failed += _fail("roundtrip: protagonist missing from hand")
	else:
		failed += _ok("roundtrip: protagonist in hand")
	if not gs.get("hand").has(ID_INFO):
		failed += _fail("roundtrip: info missing from hand")
	else:
		failed += _ok("roundtrip: info in hand")
	if not gs.get("knowledge").has(ID_KNOWLEDGE):
		failed += _fail("roundtrip: knowledge missing from knowledge dict (meta layer)")
	else:
		failed += _ok("roundtrip: knowledge in meta layer")
	return failed


# 超載時 gain 先直接照收並記警告
func _test_hand_overflow_warning(gs: Node) -> int:
	print("--- hand_overflow_warning ---")
	_reset(gs)
	var failed := 0

	var data_node: Node = get_root().get_node_or_null("Data")
	var orig_cap = 7
	if data_node != null and data_node.get("loader") != null:
		orig_cap = data_node.get("loader").tuning.get("madness_cap", 7)
		data_node.get("loader").tuning["madness_cap"] = 99

	# 塞滿 15 張卡（tuning hand_size 為 14）
	for i in range(15):
		gs.call("gain_card", ID_MADNESS)

	var hand_array: Array = gs.get("hand")
	if hand_array.size() != 15:
		failed += _fail("hand overflow: expected 15 cards, got %d" % hand_array.size())
	else:
		failed += _ok("hand overflow: 15 cards gained despite exceeding hand_size (warning emitted)")

	if data_node != null and data_node.get("loader") != null:
		data_node.get("loader").tuning["madness_cap"] = orig_cap

	return failed


func _reset(gs: Node) -> void:
	# Array[String] 不接受 set("hand", []) 替換，用 clear() 清空現有引用
	(gs.get("hand") as Array).clear()
	(gs.get("knowledge") as Dictionary).clear()
	(gs.get("madness_clock") as Dictionary).clear()
	gs.set("_madness_counter", 0)
