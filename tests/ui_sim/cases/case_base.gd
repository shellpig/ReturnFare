class_name CaseBase
extends RefCounted

## UI 模擬案例基底類別。

var id: String = ""
var description: String = ""
var required_state: String = ""
var errors: Array[String] = []


func _init(case_id: String, desc: String, req_state: String = "") -> void:
	id = case_id
	description = desc
	required_state = req_state
	errors = []


## 取得 GameState 節點
static func get_game_state(tree: SceneTree) -> Node:
	return tree.get_root().get_node("GameState")


## 尋找當前可見之 AcceptDialog
static func find_preview_dialog(tree: SceneTree) -> AcceptDialog:
	var list := QAStep.find_controls_by_qa_id(tree.get_root(), "dialog_confirm::preview")
	if list.is_empty():
		return null
	var curr: Node = list[0]
	while curr != null:
		if curr is AcceptDialog:
			return curr as AcceptDialog
		curr = curr.get_parent()
	return null


## 由 runner 呼叫的主要執行進入點
func run(_tree: SceneTree, _main_node: Control, _run_dir: String) -> Dictionary:
	return { "ok": false, "errors": ["尚未實作 run()"] }


func assert_true(cond: bool, msg: String) -> bool:
	if not cond:
		errors.append("FAIL: " + msg)
		return false
	return true


func assert_false(cond: bool, msg: String) -> bool:
	if cond:
		errors.append("FAIL: " + msg)
		return false
	return true


func assert_eq(actual: Variant, expected: Variant, msg: String) -> bool:
	if actual != expected:
		errors.append("FAIL: %s (實際: %s, 預期: %s)" % [msg, str(actual), str(expected)])
		return false
	return true


func assert_has_qa_id(tree: SceneTree, qa_id: String, msg: String = "") -> bool:
	var matches := QAStep.find_controls_by_qa_id(tree.get_root(), qa_id)
	if matches.is_empty():
		var err := "找不到 qa_id: %s" % qa_id
		if not msg.is_empty():
			err += " (%s)" % msg
		errors.append("FAIL: " + err)
		return false
	return true


func assert_no_qa_id(tree: SceneTree, qa_id: String, msg: String = "") -> bool:
	var matches := QAStep.find_controls_by_qa_id(tree.get_root(), qa_id)
	if not matches.is_empty():
		var err := "不應存在 qa_id: %s (找到 %d 個)" % [qa_id, matches.size()]
		if not msg.is_empty():
			err += " (%s)" % msg
		errors.append("FAIL: " + err)
		return false
	return true
