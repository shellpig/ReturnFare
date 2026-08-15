class_name CaseBase
extends RefCounted

## UI 模擬案例基底類別。

var id: String = ""
var description: String = ""
var required_state: String = ""
var required_data_root: String = ""
var contract_id: String = ""
var comparison_group: String = ""
var errors: Array[String] = []


func _init(
	case_id: String,
	desc: String,
	req_state: String = "",
	req_data_root: String = "",
	req_contract_id: String = "",
	compare_group: String = ""
) -> void:
	id = case_id
	description = desc
	required_state = req_state
	required_data_root = req_data_root
	contract_id = req_contract_id if not req_contract_id.is_empty() else _default_contract_id(case_id)
	comparison_group = compare_group
	errors = []


func _default_contract_id(case_id: String) -> String:
	# 既有 P1-G 變體以尾端 a/b/c 表示同一條驗收；其他案例 id 本身就是契約 id。
	if case_id.begins_with("p1g_case_"):
		var suffix := case_id.trim_prefix("p1g_case_")
		var underscore := suffix.find("_")
		var case_tag := suffix if underscore < 0 else suffix.substr(0, underscore)
		if case_tag.length() > 0 and case_tag[-1] in ["a", "b", "c"]:
			case_tag = case_tag.substr(0, case_tag.length() - 1)
		return "p1g_case_" + case_tag
	return case_id


## 取得 GameState 節點
static func get_game_state(tree: SceneTree) -> Node:
	return tree.get_root().get_node("GameState")


## 取得 Data 節點
static func get_data(tree: SceneTree) -> Node:
	if tree != null and tree.get_root() != null:
		return tree.get_root().get_node_or_null("Data")
	return null



## 從畫面上真的顯示出的預覽文字取卡片名稱；案例不讀 Data、cards.json 或任何規則層查詢。
static func preview_bullet_names(dialog: AcceptDialog) -> Array[String]:
	var names: Array[String] = []
	for line in dialog.dialog_text.split("\n"):
		var text := str(line)
		if text.begins_with("  • "):
			names.append(text.trim_prefix("  • "))
	return names


static func place_button_names(tree: SceneTree, prefix: String) -> Array[String]:
	var names: Array[String] = []
	for ctrl in QAStep.find_controls_by_qa_id_prefix(tree.get_root(), prefix):
		if not ctrl.is_visible_in_tree() or not ctrl is Button:
			continue
		names.append((ctrl as Button).text.trim_prefix("放入："))
	return names


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
