extends SceneTree

## Boot 測試：正式啟動路徑走不走得通。
## 跑法：
##   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/test_boot.gd
## 全綠 exit 0；任一失敗 exit 1。
##
## **本檔刻意不呼叫 Engine.register_singleton()。** 其他測試都自己組裝 GameState 與 Data
## 再註冊成 Engine singleton，走的是注入路徑；正式遊戲走的是 project.godot 的 autoload 路徑。
## 兩條路組裝方式不同，而只有前者被驗過——2026-08-13 就因此漏掉一個「遊戲開不起來」的 bug
## （data.gd 用 Engine.get_singleton 找 autoload，永遠拿到 null，Data.ok 恆為 false）。
## 這一檔補的就是那個盲區：autoload 起得來嗎、main.tscn 進得到正常分支嗎。
##
## 加測試時請注意：**任何在這裡手動註冊 singleton 的行為都會讓本檔失去意義。**


func _initialize() -> void:
	await process_frame

	var failed := 0
	failed += _test_autoloads_present()
	failed += _test_data_ok()
	failed += await _test_main_scene_enters_normal_branch()

	if failed > 0:
		push_error("boot: %d test(s) failed" % failed)
		quit(1)
	else:
		print("boot: all tests passed")
		quit(0)


func _ok(msg: String) -> int:
	print("  ok  " + msg)
	return 0


func _fail(msg: String) -> int:
	push_error("  FAIL  " + msg)
	return 1


# ── autoload 真的掛在 /root 底下 ────────────────────────────────────────────

func _test_autoloads_present() -> int:
	print("--- autoloads ---")
	var failed := 0

	for name in ["GameState", "Data"]:
		if get_root().get_node_or_null(NodePath(name)) == null:
			failed += _fail("/root/%s 不存在（project.godot 的 autoload 沒掛上）" % name)
		else:
			failed += _ok("/root/%s 存在" % name)

	# autoload 不是 Engine singleton——這是 data.gd 當初踩到的前提，釘住它。
	if Engine.has_singleton("GameState"):
		failed += _fail("Engine.has_singleton(GameState) 為真：前提變了，_find_game_state() 要重看")
	else:
		failed += _ok("autoload 不是 Engine singleton（前提成立）")

	return failed


# ── Data.ok：正式啟動路徑的總開關 ──────────────────────────────────────────

func _test_data_ok() -> int:
	print("--- Data.ok ---")
	var failed := 0

	var data_node: Node = get_root().get_node_or_null("Data")
	if data_node == null:
		return _fail("/root/Data 不存在，後續全部略過")

	if not data_node.get("ok"):
		failed += _fail("Data.ok 為 false：正式啟動路徑走不通，遊戲會停在錯誤畫面")
	else:
		failed += _ok("Data.ok 為 true")

	return failed


# ── main.tscn 走到正常分支，不是錯誤分支 ───────────────────────────────────

func _test_main_scene_enters_normal_branch() -> int:
	print("--- main.tscn ---")
	var failed := 0

	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		return _fail("main.tscn 載不進來")

	var main: Node = scene.instantiate()
	get_root().add_child(main)
	await process_frame

	# main.gd 的錯誤分支會寫 ErrorLabel 並把 StatusLabel／AdvanceButton 藏起來，
	# 而且在接任何 signal 之前就 return。用這三件事分辨走了哪一條。
	var error_label: Label = main.get_node_or_null("ErrorLabel")
	var status_label: Label = main.get_node_or_null("StatusLabel")
	var advance_btn: Button = main.get_node_or_null("AdvanceButton")

	if error_label == null or status_label == null or advance_btn == null:
		failed += _fail("main.tscn 少了 ErrorLabel／StatusLabel／AdvanceButton 其中之一")
		main.queue_free()
		return failed

	if not error_label.text.is_empty():
		failed += _fail("ErrorLabel 有字，走的是錯誤分支：" + error_label.text)
	else:
		failed += _ok("ErrorLabel 是空的")

	if not status_label.visible:
		failed += _fail("StatusLabel 被藏起來，走的是錯誤分支")
	else:
		failed += _ok("StatusLabel 可見")

	if not advance_btn.visible:
		failed += _fail("AdvanceButton 被藏起來，走的是錯誤分支")
	else:
		failed += _ok("AdvanceButton 可見")

	# _refresh_status() 只在正常分支跑。不能只驗「有字」——main.tscn 本身帶佔位字，
	# 壞掉時那條斷言照樣過。驗開場狀態的實際內容才分得出來。
	if not status_label.text.begins_with("第 1 天"):
		failed += _fail("StatusLabel 不是開場狀態，_refresh_status() 沒跑到：「%s」" % status_label.text)
	else:
		failed += _ok("StatusLabel 是 _refresh_status() 寫的：「%s」" % status_label.text)

	main.queue_free()
	return failed
