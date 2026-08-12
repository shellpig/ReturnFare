extends SceneTree

## Headless 資料驗證。跑法：
##   Godot_v4.6.3-stable_win64_console.exe --headless --script res://scripts/verify_data.gd
## 有問題回傳 exit code 1。

func _initialize() -> void:
	var loader := DataLoader.new()
	var ok := loader.load_all()

	print("=== ReturnFare 資料載入 ===")
	print("卡片　%d" % loader.cards.size())
	print("地點　%d" % loader.locations.size())
	print("beat　%d" % loader.beats.size())

	if not ok:
		print("\n讀取錯誤 %d 筆：" % loader.errors.size())
		for e in loader.errors:
			print("  " + e)
		quit(1)
		return

	var problems := loader.verify_references()
	if problems.size() > 0:
		print("\n引用錯誤 %d 筆：" % problems.size())
		for p in problems:
			print("  " + p)
		quit(1)
		return

	print("引用檢查　0 錯誤")

	# 45 天每一格都要有東西——這是第一輪資料完整的最低標準
	var empty: PackedStringArray = []
	for day in range(1, 46):
		for phase in ["morning", "afternoon"]:
			if loader.beats_at(day, phase).is_empty():
				empty.append("第 %d 天 %s" % [day, phase])

	if empty.size() > 0:
		print("\n沒有任何 beat 的行動格 %d 個：" % empty.size())
		for e in empty:
			print("  " + e)
	else:
		print("行動格覆蓋　第 1-45 天全部有內容")

	print("\ntuning：手牌 %d／發狂上限 %d／倒數 %d 天／視野門檻 %d" % [
		loader.tuning.get("hand_size", -1),
		loader.tuning.get("madness_cap", -1),
		loader.tuning.get("madness_countdown_days", -1),
		loader.tuning.get("madness_vision_threshold", -1),
	])

	quit(0)
