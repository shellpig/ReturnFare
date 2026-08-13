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
	print("NPC　%d" % loader.npcs.size())
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

	# 地點三分類（企劃書第十五節）：由 day_counterpart 推導，不另存欄位。
	var paired := {}
	var night_only := 0
	for lid in loader.locations:
		var loc: Dictionary = loader.locations[lid]
		if loc.get("layer", "") != "night":
			continue
		var counterpart: Variant = loc.get("day_counterpart")
		if counterpart == null:
			night_only += 1
		else:
			paired[counterpart] = true
	var day_total := 0
	for lid in loader.locations:
		if loader.locations[lid].get("layer", "") == "day":
			day_total += 1
	print("地點三分類　只有白天 %d／日夜都有 %d／只有夜裡 %d" % [
		day_total - paired.size(), paired.size(), night_only,
	])

	# 45 天每一格都要有東西——這是第一輪資料完整的最低標準。
	# 三格是刻意留空的：第 1 天是搭車上山（只有傍晚與夜），
	# 第 32 天下午整個被慶典的連續選項鏈吃掉。
	var by_design := {
		"1|morning": true,
		"1|afternoon": true,
		"32|afternoon": true,
	}
	var empty: PackedStringArray = []
	for day in range(1, 46):
		for phase in ["morning", "afternoon"]:
			if loader.beats_at(day, phase).is_empty() and not by_design.has("%d|%s" % [day, phase]):
				empty.append("第 %d 天 %s" % [day, phase])

	if empty.size() > 0:
		print("\n沒有任何 beat 的行動格 %d 個：" % empty.size())
		for e in empty:
			print("  " + e)
		quit(1)
		return
	print("行動格覆蓋　第 1-45 天全滿（3 格刻意留空）")

	print("\ntuning：手牌 %d／發狂上限 %d／倒數 %d 天／視野門檻 %d" % [
		loader.tuning.get("hand_size", -1),
		loader.tuning.get("madness_cap", -1),
		loader.tuning.get("madness_countdown_days", -1),
		loader.tuning.get("madness_vision_threshold", -1),
	])

	quit(0)
