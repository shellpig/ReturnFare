extends SceneTree

## Headless 資料驗證。跑法：
##   Godot_v4.6.3-stable_win64_console.exe --headless --script res://scripts/verify_data.gd
## 有問題回傳 exit code 1。

const DataFacts := preload("res://scripts/core/data_facts.gd")

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

	# Lint 1: 語彙封閉性
	var vocab_errs := DataLoader.lint_vocabulary(loader.beats)
	if vocab_errs.size() > 0:
		print("\n語彙封閉性錯誤 %d 筆：" % vocab_errs.size())
		for e in vocab_errs:
			print("  " + e)
		quit(1)
		return
	print("語彙封閉性 (Lint 1)　0 錯誤")

	# Lint 9：卡片 type 與 card_types.json 顯示型別封閉性。
	var card_type_errs := DataLoader.lint_card_types(loader)
	if card_type_errs.size() > 0:
		print("\n卡片型別封閉性錯誤 %d 筆：" % card_type_errs.size())
		for e in card_type_errs:
			print("  " + e)
		quit(1)
		return
	print("卡片型別封閉性 (Lint 9)　0 錯誤")

	# Lint 2: reject_reason 完整性（warnings）
	var missing_reason_warns := DataLoader.lint_missing_reject_reason(loader.beats)
	if missing_reason_warns.size() > 0:
		print("reject_reason 警告 %d 筆" % missing_reason_warns.size())
	else:
		print("reject_reason 完整性 (Lint 2)　0 警告")

	# Lint 3: 選擇題 / 免費槽同面板規約 (K-16, K-22)
	var choice_res := DataLoader.lint_choice_rules(loader.beats)
	var choice_errs: PackedStringArray = choice_res.get("errors", PackedStringArray())
	var choice_warns: PackedStringArray = choice_res.get("warnings", PackedStringArray())
	if choice_errs.size() > 0:
		print("\n選擇題規約錯誤 %d 筆：" % choice_errs.size())
		for e in choice_errs:
			print("  " + e)
		quit(1)
		return
	if choice_warns.size() > 0:
		print("選擇題規約 (Lint 3)　0 錯誤（%d 筆已豁免警告）" % choice_warns.size())
	else:
		print("選擇題規約 (Lint 3)　0 錯誤")

	# Lint 5: 行動格供需檢查
	var action_errs := DataLoader.lint_action_phases(loader)
	if action_errs.size() > 0:
		print("\n行動格供需錯誤 %d 筆：" % action_errs.size())
		for e in action_errs:
			print("  " + e)
		quit(1)
		return
	print("行動格供需 (Lint 5)　0 錯誤（第 1-45 天全滿，3 格刻意留空）")

	# Lint 7: 夜間可達性
	var night_errs := DataLoader.lint_night_reachability(loader)
	if night_errs.size() > 0:
		print("\n夜間可達性錯誤 %d 筆：" % night_errs.size())
		for e in night_errs:
			print("  " + e)
		quit(1)
		return
	print("夜間可達性 (Lint 7)　0 錯誤")

	# Lint 8: 殘響可播出性
	var echo_errs := DataLoader.lint_echoes(loader.beats)
	if echo_errs.size() > 0:
		print("\n殘響可播出性錯誤 %d 筆：" % echo_errs.size())
		for e in echo_errs:
			print("  " + e)
		quit(1)
		return
	print("殘響可播出性 (Lint 8)　0 錯誤")

	# Lint 4: 縱慾完整性
	var integrity_errs := DataLoader.lint_indulgence_integrity(loader)
	if integrity_errs.size() > 0:
		print("\n縱慾完整性錯誤 %d 筆：" % integrity_errs.size())
		for e in integrity_errs:
			print("  " + e)
		quit(1)
		return
	print("縱慾完整性 (Lint 4)　0 錯誤（第 1-45 天均有保底縱慾出口）")

	# Lint 10: 縱慾出口資料完整性
	var exit_errs := DataLoader.lint_indulgence_exits(loader.beats)
	if exit_errs.size() > 0:
		print("\n縱慾出口資料完整性錯誤 %d 筆：" % exit_errs.size())
		for e in exit_errs:
			print("  " + e)
		quit(1)
		return
	print("縱慾出口資料完整性 (Lint 10)　0 錯誤")

	# Lint 11: 夜間對位完整性
	var alignment_errs := DataLoader.lint_night_alignment(loader)
	if alignment_errs.size() > 0:
		print("\n夜間對位完整性錯誤 %d 筆：" % alignment_errs.size())
		for e in alignment_errs:
			print("  " + e)
		quit(1)
		return
	print("夜間對位完整性 (Lint 11)　0 錯誤")

	# Lint 12: 夜間地點狀態完整性
	var night_loc_errs := DataLoader.lint_night_locations(loader)
	if night_loc_errs.size() > 0:
		print("\n夜間地點狀態完整性錯誤 %d 筆：" % night_loc_errs.size())
		for e in night_loc_errs:
			print("  " + e)
		quit(1)
		return
	print("夜間地點狀態完整性 (Lint 12)　0 錯誤")

	# Lint 13: 舊夜間旗標退場檢查
	var legacy_flag_errs := DataLoader.lint_legacy_night_flags(loader)
	if legacy_flag_errs.size() > 0:
		print("\n舊夜間旗標退場錯誤 %d 筆：" % legacy_flag_errs.size())
		for e in legacy_flag_errs:
			print("  " + e)
		quit(1)
		return
	print("舊夜間旗標退場 (Lint 13)　0 錯誤")

	print("\ntuning：手牌 %d／發狂上限 %d／倒數 %d 天／視野門檻 %d" % [
		loader.tuning.get("hand_size", -1),
		loader.tuning.get("madness_cap", -1),
		loader.tuning.get("madness_countdown_days", -1),
		loader.tuning.get("madness_vision_threshold", -1),
	])

	quit(0)
