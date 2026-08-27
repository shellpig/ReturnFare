extends SceneTree

## 背景模式預檢：只開一個真視窗、什麼都不做，撐住指定秒數就結束。
##
## 這支本身不斷言任何事——背景模式的隔離是作業系統層的（獨立 desktop），
## 該驗的東西 Godot 這一端看不到，全部由 launcher 的守衛驗
## （見 tests/ui_sim/bg_guards.ps1 的 Invoke-UiSimBackgroundPatrol）。
##
## 存在的理由是成本：這支約 1 秒，全套上百個行程。隔離壞掉時要在第一秒就知道，
## 而不是等 108 個案例各把視窗丟到使用者臉上一次之後才發現。
##
## 使用者參數：--hold <sec>，預設 1。

const DEFAULT_HOLD_SECONDS := 1.0


func _initialize() -> void:
	var hold_seconds := _parse_hold(OS.get_cmdline_user_args())
	var elapsed := 0.0
	while elapsed < hold_seconds:
		await process_frame
		elapsed += get_root().get_process_delta_time()
	print("QA_BACKGROUND_PROBE_OK held=%.2fs display_server=%s" % [elapsed, DisplayServer.get_name()])
	quit(0)


func _parse_hold(user_args: PackedStringArray) -> float:
	var idx := Array(user_args).find("--hold")
	if idx >= 0 and idx + 1 < user_args.size():
		return maxf(0.0, float(user_args[idx + 1]))
	return DEFAULT_HOLD_SECONDS
