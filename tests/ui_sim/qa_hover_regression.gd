extends SceneTree

## K-48 回歸守衛：確認「送出滑鼠移動之後立刻讀 hover」這條規則沒有被改回去。
##
## 為什麼需要它：K-48 已經復發兩次，而它復發的時候**整套 UI 模擬照樣可能全綠**——
## 紅不紅取決於跑測試的當下使用者有沒有動實體滑鼠，不取決於程式對不對。所以不能靠
## 跑全套來守這件事，要靠這一條把機制本身釘死。
##
## 機制：`gui_get_hovered_control()` 記的是「最後一個滑鼠移動事件打到誰」，不是每幀
## 重算的值。案例開的是真視窗，桌面上還有一支實體滑鼠；只要在「送出移動」與「讀取
## hover」之間讓出執行權，使用者手動一下滑鼠，作業系統補進來的真實移動事件就會把
## hover 蓋掉，於是斷言回報「預期某按鈕、實際某個完全不相干的容器」。
##
## 本檔用「每一幀補送一發打到別處的移動事件」來扮演那支實體滑鼠，因此不需要真的動
## 使用者的游標，也不需要碰運氣。
##
## 跑法（要有視窗，**不可**加 --headless）：
##   Godot_v4.6.3-stable_win64_console.exe --path . --script res://tests/ui_sim/qa_hover_regression.gd
## 全綠 exit 0；任一條失敗 exit 1。

const QAStepClass := preload("res://tests/ui_sim/qa_step.gd")

const NOISE_POS := Vector2(40, 640)

var _noise_on := false


func _initialize() -> void:
	Input.use_accumulated_input = false

	var host := Control.new()
	host.name = "RegressionHost"
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	get_root().add_child(host)

	var target := Button.new()
	target.name = "RegressionTarget"
	target.text = "target"
	target.position = Vector2(540, 200)
	target.size = Vector2(200, 40)
	target.set_meta("qa_id", "regression::target")
	host.add_child(target)

	await QAStepClass.wait_draw_frames(self, 3)

	var failed := 0
	failed += await _test_hazard_is_real(host, target)
	failed += await _test_click_survives_foreign_motion(target)

	if failed > 0:
		push_error("K-48 回歸守衛：%d 條失敗" % failed)
		quit(1)
	else:
		print("K-48 回歸守衛：全部通過")
		quit(0)


## 1. 把危害本身釘住：送出移動之後**若讓出執行權**，外來事件會把 hover 蓋掉。
## 這一條紅了不代表程式壞了，代表引擎行為變了——那時要回頭重讀 K-48 再決定修法。
func _test_hazard_is_real(host: Control, target: Button) -> int:
	print("--- 1. 危害存在性：等幀之後 hover 會被外來事件蓋掉 ---")
	var vp := get_root()
	var center: Vector2 = target.get_screen_position() + target.size * 0.5

	_send_motion(center)
	var immediate: Control = vp.gui_get_hovered_control()
	_send_motion(NOISE_POS)
	await QAStepClass.wait_draw_frames(self, 2)
	var after: Control = vp.gui_get_hovered_control()

	var failed := 0
	if immediate == target:
		print("  ok  送出移動之後立刻讀，讀到目標本身")
	else:
		push_error("  FAIL  立刻讀到的不是目標（實際: %s）" % _hname(immediate))
		failed += 1

	if after == host:
		print("  ok  外來移動事件確實把 hover 蓋成別的控制項（危害仍然存在）")
	else:
		push_error("  FAIL  危害假設不成立：等幀之後 hover 是 %s，預期被蓋成 RegressionHost。引擎行為可能已改變，回頭重讀 K-48" % _hname(after))
		failed += 1

	return failed


## 2. 真正的守衛：整條 QAStep.click() 在「每幀都有外來滑鼠移動」的環境下仍須成功。
## 有人把 await 加回「送出移動」與「讀取 hover」之間，這一條就會紅。
func _test_click_survives_foreign_motion(target: Button) -> int:
	print("--- 2. QAStep.click() 在持續的外來滑鼠移動下仍成功 ---")
	var pressed_box := [false]
	target.pressed.connect(func() -> void: pressed_box[0] = true)

	_noise_on = true
	process_frame.connect(_emit_noise)
	var res: Dictionary = await QAStepClass.click(self, "regression::target")
	_noise_on = false
	process_frame.disconnect(_emit_noise)

	var failed := 0
	if bool(res.get("ok", false)):
		print("  ok  click() 回報成功")
	else:
		push_error("  FAIL  click() 失敗: %s" % str(res.get("error", "")))
		failed += 1

	if pressed_box[0]:
		print("  ok  目標確實收到 pressed")
	else:
		push_error("  FAIL  目標沒有收到 pressed")
		failed += 1

	return failed


func _emit_noise() -> void:
	if _noise_on:
		_send_motion(NOISE_POS)


func _send_motion(pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	Input.parse_input_event(motion)
	Input.flush_buffered_events()


func _hname(ctrl: Control) -> String:
	if ctrl == null:
		return "null"
	return str(ctrl.name)
