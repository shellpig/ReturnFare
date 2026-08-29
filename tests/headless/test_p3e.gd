extends SceneTree

## P3-E headless 驗收測試：
## 1. 多對一與一對一對位確認、共用 knowledge 發放與 View-Model 衍生名稱
## 2. 部分到訪與日後首次到訪自動顯示已對位（無二次確認）
## 3. 狀態純粹性：直接注入 knowledge / 只有 seen、無 matched/aligned 第三份狀態
## 4. 資料衝突 fixture 測試與 push_error
## 5. 繞過 UI 直呼 confirm_night_alignment 的封閉六碼負向拒絕矩陣與狀態零變化
## 6. alignment_offer 與 confirm_night_alignment 判準逐項對齊反證

const DataLoader := preload("res://scripts/data_loader.gd")
const ConditionEval := preload("res://scripts/core/condition_eval.gd")
const PlaythroughGreedy := preload("res://tests/headless/playthrough_greedy.gd")

func _initialize() -> void:
	var data_node: Node = PlaythroughGreedy.setup_data(self)
	var gs: Node = PlaythroughGreedy.setup_game_state(self, data_node)

	await process_frame

	if not data_node.get("ok"):
		push_error("P3-E: Data failed to load; abort")
		quit(1)
		return

	var failed := 0
	print("\n=== P3-E Headless Test Suite ===")

	failed += _test_1to1_and_multi_row_alignment(gs, data_node)
	failed += _test_multi_row_partial_seen_and_subsequent_visit(gs, data_node)
	failed += _test_state_purity_no_third_state(gs, data_node)
	failed += _test_data_conflict_fixture(gs, data_node)
	failed += _test_closed_six_code_rejection_matrix(gs, data_node)
	failed += _test_offer_and_confirm_criteria_alignment(gs, data_node)

	if failed > 0:
		push_error("\nP3-E: %d assertion(s) failed\n" % failed)
		quit(1)
	else:
		print("\nP3-E: all tests passed\n")
		quit(0)


func _ok(msg: String) -> int:
	print("  ok  " + msg)
	return 0


func _fail(msg: String) -> int:
	push_error("  FAIL  " + msg)
	return 1


func _reset_gs(gs: Node) -> void:
	# P5-D：fresh state 是 opening，本檔驗的是 run 層規則。
	gs.set("flow_mode", "run")
	(gs.get("active_ending") as Dictionary).clear()
	PlaythroughGreedy.start_fresh_run(gs)
	gs.set("night_locations_seen", {})
	gs.set("night_once_beats_seen", {})
	gs.set("knowledge", {})
	gs.set("night_location_chosen", "")
	gs.set("night_sleep_pending", false)
	gs.set("day", 10)
	gs.set("phase", "morning")


# ── 1. 一對一與多對一對位確認、共用 knowledge 與名稱衍生 ─────────────────────

func _test_1to1_and_multi_row_alignment(gs: Node, data_node: Node) -> int:
	print("--- 1. 1-to-1 and multi-row alignment and name derivation ---")
	var failed := 0
	_reset_gs(gs)

	# 1.1 一對一對位：sanquan -> n_exit -> k_night_sanquan
	var seen_dict: Dictionary = gs.get("night_locations_seen") as Dictionary
	seen_dict["n_exit"] = true

	var offer_1to1: Dictionary = PanelBuilder.alignment_offer("sanquan", gs, data_node)
	if bool(offer_1to1.get("available", false)) and str(offer_1to1.get("knowledge_id", "")) == "k_night_sanquan":
		failed += _ok("一對一地點 sanquan 產生有效 offer，knowledge_id 為 k_night_sanquan")
	else:
		failed += _fail("一對一 offer 失敗: %s" % str(offer_1to1))

	var res_1to1: Dictionary = gs.call("confirm_night_alignment", "sanquan")
	if bool(res_1to1.get("ok", false)) and str(res_1to1.get("knowledge_id", "")) == "k_night_sanquan":
		failed += _ok("confirm_night_alignment('sanquan') 成功取得 k_night_sanquan")
	else:
		failed += _fail("confirm_night_alignment 失敗: %s" % str(res_1to1))

	if not bool(gs.get("action_spent")) and (gs.get("slots_placed") as Dictionary).is_empty() and (gs.get("choices") as Dictionary).is_empty():
		failed += _ok("一對一對位成功後 action_spent 仍為 false，slots/choices 均未寫入")
	else:
		failed += _fail("一對一對位成功後誤寫入行動格或槽位狀態")

	var summary_1to1: Dictionary = PanelBuilder.location_summary("n_exit", gs, data_node)
	if str(summary_1to1.get("status_text", "")) == "[已對位]" and str(summary_1to1.get("display_name", "")) == "山泉閣":
		failed += _ok("一對一對位後 summary 顯示『山泉閣』且無分區後綴，狀態為 [已對位]")
	else:
		failed += _fail("一對一 summary 異常: %s" % str(summary_1to1))

	# 1.2 多對一對位：temple -> n_woodtags & n_music -> k_night_temple
	_reset_gs(gs)
	seen_dict = gs.get("night_locations_seen") as Dictionary
	seen_dict["n_woodtags"] = true
	seen_dict["n_music"] = true

	var offer_multi: Dictionary = PanelBuilder.alignment_offer("temple", gs, data_node)
	if bool(offer_multi.get("available", false)) and str(offer_multi.get("knowledge_id", "")) == "k_night_temple":
		var night_ids: Array = offer_multi.get("night_ids", []) as Array
		if night_ids.has("n_woodtags") and night_ids.has("n_music") and night_ids.size() == 2:
			failed += _ok("多對一地點 temple 兩個 row 均 seen 時，offer 回傳單一共用 knowledge_id 並收錄兩 row")
		else:
			failed += _fail("多對一 offer night_ids 不符: %s" % str(night_ids))
	else:
		failed += _fail("多對一 offer 失敗: %s" % str(offer_multi))

	var res_multi: Dictionary = gs.call("confirm_night_alignment", "temple")
	if bool(res_multi.get("ok", false)) and str(res_multi.get("knowledge_id", "")) == "k_night_temple":
		failed += _ok("多對一確認對位成功取得共用 k_night_temple")
	else:
		failed += _fail("多對一 confirm 失敗: %s" % str(res_multi))

	if not bool(gs.get("action_spent")) and (gs.get("slots_placed") as Dictionary).is_empty() and (gs.get("choices") as Dictionary).is_empty():
		failed += _ok("多對一對位成功後 action_spent 仍為 false，slots/choices 均未寫入")
	else:
		failed += _fail("多對一對位成功後誤寫入行動格或槽位狀態")

	var sum_woodtags: Dictionary = PanelBuilder.location_summary("n_woodtags", gs, data_node)
	var sum_music: Dictionary = PanelBuilder.location_summary("n_music", gs, data_node)
	if str(sum_woodtags.get("status_text", "")) == "[已對位]" and str(sum_woodtags.get("display_name", "")) == "廟＋廟埕・數木牌的屋子":
		failed += _ok("多對一 row 1 (n_woodtags) 對位後顯示『廟＋廟埕・數木牌的屋子』與 [已對位]")
	else:
		failed += _fail("n_woodtags summary 異常: %s" % str(sum_woodtags))

	if str(sum_music.get("status_text", "")) == "[已對位]" and str(sum_music.get("display_name", "")) == "廟＋廟埕・有音樂的地方":
		failed += _ok("多對一 row 2 (n_music) 對位後顯示『廟＋廟埕・有音樂的地方』與 [已對位]")
	else:
		failed += _fail("n_music summary 異常: %s" % str(sum_music))

	return failed


# ── 2. 多對一部分到訪與日後首次到訪自動顯示已對位 ─────────────────────────────

func _test_multi_row_partial_seen_and_subsequent_visit(gs: Node, data_node: Node) -> int:
	print("--- 2. Multi-row partial seen and automatic alignment on second row visit ---")
	var failed := 0
	_reset_gs(gs)

	# 僅 seen 第一個 row n_woodtags
	var seen_dict: Dictionary = gs.get("night_locations_seen") as Dictionary
	seen_dict["n_woodtags"] = true

	# 白天對位 temple
	var res: Dictionary = gs.call("confirm_night_alignment", "temple")
	if not bool(res.get("ok", false)):
		return failed + _fail("多對一部分 seen 對位失敗: %s" % str(res))

	# 驗證第一個 row 已對位，第二個 row 仍為 [尚未到訪] 且不劇透白天地點名
	var sum_woodtags: Dictionary = PanelBuilder.location_summary("n_woodtags", gs, data_node)
	var sum_music: Dictionary = PanelBuilder.location_summary("n_music", gs, data_node)
	if str(sum_woodtags.get("status_text", "")) == "[已對位]" and str(sum_woodtags.get("display_name", "")) == "廟＋廟埕・數木牌的屋子":
		failed += _ok("已到訪 row (n_woodtags) 正確顯示已對位名稱")
	else:
		failed += _fail("n_woodtags summary 異常: %s" % str(sum_woodtags))

	if str(sum_music.get("status_text", "")) == "[尚未到訪]" and str(sum_music.get("display_name", "")) == "有音樂的地方":
		failed += _ok("未到訪 row (n_music) 維持 [尚未到訪] 且維持原夜間名『有音樂的地方』（不劇透）")
	else:
		failed += _fail("未到訪 row n_music 提前洩漏對位狀態或名稱: %s" % str(sum_music))

	# 入夜首次進入第二個 row n_music
	gs.set("phase", "night")
	gs.set("day", 10)
	var enter_res: Dictionary = gs.call("enter_night_location", "n_music")
	if not bool(enter_res.get("ok", false)):
		return failed + _fail("進入 n_music 失敗: %s" % str(enter_res))

	# 驗證離開後查看 summary：n_music 自動顯示 [已對位] 與『廟＋廟埕・有音樂的地方』，無須第二次白天確認
	var sum_music_after: Dictionary = PanelBuilder.location_summary("n_music", gs, data_node)
	if str(sum_music_after.get("status_text", "")) == "[已對位]" and str(sum_music_after.get("display_name", "")) == "廟＋廟埕・有音樂的地方":
		failed += _ok("首次到訪第二個 row 後，自動衍生 [已對位] 與白天名・夜間名，無須第二次確認")
	else:
		failed += _fail("第二個 row 到訪後未能自動衍生對位: %s" % str(sum_music_after))

	# 白天再次檢查 offer：已持有 knowledge，offer.available 為 false
	gs.set("phase", "morning")
	var offer_again: Dictionary = PanelBuilder.alignment_offer("temple", gs, data_node)
	if not bool(offer_again.get("available", true)):
		failed += _ok("共用 knowledge 已在手時，白天 offer.available 正確為 false（不重複給按鈕）")
	else:
		failed += _fail("offer 重複提供已持有之對位: %s" % str(offer_again))

	return failed


# ── 3. 狀態純粹性：無第三份 matched/aligned 狀態 ────────────────────────────

func _test_state_purity_no_third_state(gs: Node, data_node: Node) -> int:
	print("--- 3. State purity: no matched/aligned third state in serialize ---")
	var failed := 0
	_reset_gs(gs)

	# 3.1 僅注入 knowledge 但無 seen
	gs.call("gain_card", "k_night_sanquan")
	var sum_unseen: Dictionary = PanelBuilder.location_summary("n_exit", gs, data_node)
	if str(sum_unseen.get("status_text", "")) == "[尚未到訪]" and str(sum_unseen.get("display_name", "")) == "石階外的鎮":
		failed += _ok("手上有 knowledge 但無 seen 時，地點維持 [尚未到訪] 與引子名")
	else:
		failed += _fail("無 seen 卻因 knowledge 誤顯示對位: %s" % str(sum_unseen))

	# 3.2 僅 seen 但無 knowledge
	_reset_gs(gs)
	var seen_dict: Dictionary = gs.get("night_locations_seen") as Dictionary
	seen_dict["n_exit"] = true
	var sum_unaligned: Dictionary = PanelBuilder.location_summary("n_exit", gs, data_node)
	if str(sum_unaligned.get("status_text", "")) == "[已到訪，尚未對位]" and str(sum_unaligned.get("display_name", "")) == "石階外的鎮":
		failed += _ok("有 seen 但無 knowledge 時，地點顯示 [已到訪，尚未對位] 與引子名")
	else:
		failed += _fail("無 knowledge 卻誤顯示已對位: %s" % str(sum_unaligned))

	# 3.3 對位完成後，檢查 serialize 中不存在任何 matched / aligned 鍵
	gs.call("confirm_night_alignment", "sanquan")
	var snap: Dictionary = gs.call("serialize") as Dictionary
	var snap_text: String = JSON.stringify(snap)
	if not snap_text.contains("aligned") and not snap_text.contains("matched"):
		failed += _ok("serialize 完整字串中不存在 'aligned' 或 'matched' 鍵值，證明對位狀態純屬衍生")
	else:
		failed += _fail("serialize 存在疑似持久化對位狀態: %s" % snap_text)

	# 3.4 拿掉 knowledge 即刻失效
	(gs.get("knowledge") as Dictionary).erase("k_night_sanquan")
	var sum_revert: Dictionary = PanelBuilder.location_summary("n_exit", gs, data_node)
	if str(sum_revert.get("status_text", "")) == "[已到訪，尚未對位]" and str(sum_revert.get("display_name", "")) == "石階外的鎮":
		failed += _ok("刪除 knowledge 後，衍生的已對位狀態立即退回 [已到訪，尚未對位]，無狀態殘留")
	else:
		failed += _fail("刪除 knowledge 後未能立即退回未對位: %s" % str(sum_revert))

	return failed


# ── 4. 資料衝突 fixture 測試與 push_error ───────────────────────────────────

func _test_data_conflict_fixture(gs: Node, data_node: Node) -> int:
	print("--- 4. Data conflict fixture and push_error ---")
	var failed := 0
	_reset_gs(gs)

	# 4.1 多 row 衝突 fixture：同一 day_counterpart 'conflict_day' 下有兩個夜間 row 指向不同 night_reveal
	var fake_locations: Dictionary = {
		"conflict_day": { "id": "conflict_day", "name": "衝突白天地點", "layer": "day" },
		"n_conf_1": { "id": "n_conf_1", "name": "衝突夜間1", "layer": "night", "day_counterpart": "conflict_day", "night_reveal": "k_rev_1" },
		"n_conf_2": { "id": "n_conf_2", "name": "衝突夜間2", "layer": "night", "day_counterpart": "conflict_day", "night_reveal": "k_rev_2" },
	}
	var fake_loader := DataLoader.new()
	fake_loader.locations = fake_locations
	var fake_data := Node.new()
	fake_data.set("loader", fake_loader)

	var seen_dict: Dictionary = gs.get("night_locations_seen") as Dictionary
	seen_dict["n_conf_1"] = true
	seen_dict["n_conf_2"] = true

	# 驗證 alignment_offer 在資料衝突時回傳 available: false
	var offer: Dictionary = PanelBuilder.alignment_offer("conflict_day", gs, fake_data)
	fake_data.free()
	if not bool(offer.get("available", true)):
		failed += _ok("資料衝突 fixture (多 row 衝突) 下 alignment_offer 回傳 available == false")
	else:
		failed += _fail("alignment_offer 未能阻擋資料衝突 fixture: %s" % str(offer))

	# 驗證 confirm_night_alignment 拒絕並回傳 data_conflict
	var real_data_loader: DataLoader = data_node.loader
	data_node.loader = fake_loader
	var snap_before := (gs.call("serialize") as Dictionary).duplicate(true)
	var res: Dictionary = gs.call("confirm_night_alignment", "conflict_day")
	var snap_after := (gs.call("serialize") as Dictionary).duplicate(true)
	data_node.loader = real_data_loader

	if not bool(res.get("ok", true)) and str(res.get("reason_code", "")) == "data_conflict":
		failed += _ok("confirm_night_alignment 遇到多 row 衝突回傳 reason_code == 'data_conflict'")
	else:
		failed += _fail("confirm_night_alignment 未回傳 data_conflict: %s" % str(res))

	if snap_before == snap_after:
		failed += _ok("data_conflict (多 row 衝突) 拒絕後狀態零變化")
	else:
		failed += _fail("data_conflict 拒絕造成狀態變異")

	# 4.2 單一 row 缺失 night_reveal (null 或空字串) 同樣視為 data_conflict
	_reset_gs(gs)
	var fake_locations_missing: Dictionary = {
		"missing_rev_day": { "id": "missing_rev_day", "name": "缺卡白天地點", "layer": "day" },
		"n_missing_1": { "id": "n_missing_1", "name": "缺卡夜間1", "layer": "night", "day_counterpart": "missing_rev_day", "night_reveal": null },
	}
	var fake_loader_missing := DataLoader.new()
	fake_loader_missing.locations = fake_locations_missing
	var fake_data_missing := Node.new()
	fake_data_missing.set("loader", fake_loader_missing)

	seen_dict = gs.get("night_locations_seen") as Dictionary
	seen_dict["n_missing_1"] = true

	var offer_missing: Dictionary = PanelBuilder.alignment_offer("missing_rev_day", gs, fake_data_missing)
	fake_data_missing.free()
	if not bool(offer_missing.get("available", true)):
		failed += _ok("單一 row 缺 night_reveal fixture 下 alignment_offer 回傳 available == false")
	else:
		failed += _fail("alignment_offer 未能阻擋單一 row 缺 night_reveal fixture: %s" % str(offer_missing))

	data_node.loader = fake_loader_missing
	snap_before = (gs.call("serialize") as Dictionary).duplicate(true)
	var res_missing: Dictionary = gs.call("confirm_night_alignment", "missing_rev_day")
	snap_after = (gs.call("serialize") as Dictionary).duplicate(true)
	data_node.loader = real_data_loader

	if not bool(res_missing.get("ok", true)) and str(res_missing.get("reason_code", "")) == "data_conflict":
		failed += _ok("confirm_night_alignment 遇到單一 row 缺 night_reveal 回傳 reason_code == 'data_conflict'")
	else:
		failed += _fail("confirm_night_alignment 缺卡未回傳 data_conflict: %s" % str(res_missing))

	if snap_before == snap_after:
		failed += _ok("data_conflict (單 row 缺卡) 拒絕後狀態零變化")
	else:
		failed += _fail("data_conflict 缺卡拒絕造成狀態變異")

	return failed


# ── 5. 六碼封閉拒絕矩陣與狀態零變化 ─────────────────────────────────────────

func _test_closed_six_code_rejection_matrix(gs: Node, data_node: Node) -> int:
	print("--- 5. Closed 6-code rejection matrix & zero-state mutation ---")
	var failed := 0

	# 5.1 not_day_phase (evening & night)
	_reset_gs(gs)
	var seen_dict: Dictionary = gs.get("night_locations_seen") as Dictionary
	seen_dict["n_exit"] = true

	gs.set("phase", "evening")
	var snap_before := (gs.call("serialize") as Dictionary).duplicate(true)
	var res_eve: Dictionary = gs.call("confirm_night_alignment", "sanquan")
	var snap_after := (gs.call("serialize") as Dictionary).duplicate(true)
	if not bool(res_eve.get("ok", true)) and str(res_eve.get("reason_code", "")) == "not_day_phase" and snap_before == snap_after:
		failed += _ok("1.1 not_day_phase (evening): 拒絕成功且狀態零變化")
	else:
		failed += _fail("1.1 not_day_phase (evening) 失敗: %s" % str(res_eve))

	gs.set("phase", "night")
	snap_before = (gs.call("serialize") as Dictionary).duplicate(true)
	var res_night: Dictionary = gs.call("confirm_night_alignment", "sanquan")
	snap_after = (gs.call("serialize") as Dictionary).duplicate(true)
	if not bool(res_night.get("ok", true)) and str(res_night.get("reason_code", "")) == "not_day_phase" and snap_before == snap_after:
		failed += _ok("1.2 not_day_phase (night): 拒絕成功且狀態零變化")
	else:
		failed += _fail("1.2 not_day_phase (night) 失敗: %s" % str(res_night))

	# 5.2 unknown_location
	_reset_gs(gs)
	snap_before = (gs.call("serialize") as Dictionary).duplicate(true)
	var res_unk: Dictionary = gs.call("confirm_night_alignment", "nonexistent_loc_xyz")
	snap_after = (gs.call("serialize") as Dictionary).duplicate(true)
	if not bool(res_unk.get("ok", true)) and str(res_unk.get("reason_code", "")) == "unknown_location" and snap_before == snap_after:
		failed += _ok("2. unknown_location: 拒絕成功且狀態零變化")
	else:
		failed += _fail("2. unknown_location 失敗: %s" % str(res_unk))

	# 5.3 not_day_layer (傳入夜間 row id)
	_reset_gs(gs)
	snap_before = (gs.call("serialize") as Dictionary).duplicate(true)
	var res_layer: Dictionary = gs.call("confirm_night_alignment", "n_exit")
	snap_after = (gs.call("serialize") as Dictionary).duplicate(true)
	if not bool(res_layer.get("ok", true)) and str(res_layer.get("reason_code", "")) == "not_day_layer" and snap_before == snap_after:
		failed += _ok("3. not_day_layer: 傳入夜間地點拒絕成功且狀態零變化")
	else:
		failed += _fail("3. not_day_layer 失敗: %s" % str(res_layer))

	# 5.4 no_seen_row (白天地點存在，但對應夜間 row 一個都未 seen)
	_reset_gs(gs)
	snap_before = (gs.call("serialize") as Dictionary).duplicate(true)
	var res_noseen: Dictionary = gs.call("confirm_night_alignment", "sanquan")
	snap_after = (gs.call("serialize") as Dictionary).duplicate(true)
	if not bool(res_noseen.get("ok", true)) and str(res_noseen.get("reason_code", "")) == "no_seen_row" and snap_before == snap_after:
		failed += _ok("4. no_seen_row: 未到訪夜間 row 拒絕成功且狀態零變化")
	else:
		failed += _fail("4. no_seen_row 失敗: %s" % str(res_noseen))

	# 5.5 data_conflict (同一 counterpart 多 row 之 night_reveal 衝突)
	_reset_gs(gs)
	var fake_locations_5: Dictionary = {
		"day_test": { "id": "day_test", "name": "測試白天", "layer": "day" },
		"n_test_1": { "id": "n_test_1", "name": "夜間1", "layer": "night", "day_counterpart": "day_test", "night_reveal": "k_a" },
		"n_test_2": { "id": "n_test_2", "name": "夜間2", "layer": "night", "day_counterpart": "day_test", "night_reveal": "k_b" },
	}
	var fake_loader_5 := DataLoader.new()
	fake_loader_5.locations = fake_locations_5
	var real_loader: DataLoader = data_node.loader
	data_node.loader = fake_loader_5
	seen_dict = gs.get("night_locations_seen") as Dictionary
	seen_dict["n_test_1"] = true
	seen_dict["n_test_2"] = true
	snap_before = (gs.call("serialize") as Dictionary).duplicate(true)
	var res_conf: Dictionary = gs.call("confirm_night_alignment", "day_test")
	snap_after = (gs.call("serialize") as Dictionary).duplicate(true)
	data_node.loader = real_loader
	if not bool(res_conf.get("ok", true)) and str(res_conf.get("reason_code", "")) == "data_conflict" and snap_before == snap_after:
		failed += _ok("5. data_conflict: 資料衝突拒絕成功且狀態零變化")
	else:
		failed += _fail("5. data_conflict 失敗: %s" % str(res_conf))

	# 5.6 already_known (knowledge 已在手)
	_reset_gs(gs)
	seen_dict = gs.get("night_locations_seen") as Dictionary
	seen_dict["n_exit"] = true
	gs.call("gain_card", "k_night_sanquan")
	snap_before = (gs.call("serialize") as Dictionary).duplicate(true)
	var res_known: Dictionary = gs.call("confirm_night_alignment", "sanquan")
	snap_after = (gs.call("serialize") as Dictionary).duplicate(true)
	if not bool(res_known.get("ok", true)) and str(res_known.get("reason_code", "")) == "already_known" and snap_before == snap_after:
		failed += _ok("6. already_known: 已持有 knowledge 拒絕成功且狀態零變化")
	else:
		failed += _fail("6. already_known 失敗: %s" % str(res_known))

	return failed


# ── 6. alignment_offer 與 confirm_night_alignment 判準逐項對齊反證 ──────────

func _test_offer_and_confirm_criteria_alignment(gs: Node, data_node: Node) -> int:
	print("--- 6. Offer and Confirm criteria exact alignment across all cases ---")
	var failed := 0

	# 驗證：任何狀態下，alignment_offer().available == true 當且僅當 confirm_night_alignment().ok == true
	var cases: Array[Dictionary] = [
		{ "name": "非白天 (evening)", "phase": "evening", "loc": "sanquan", "seen": ["n_exit"], "know": [], "expect_ok": false },
		{ "name": "非白天 (night)", "phase": "night", "loc": "sanquan", "seen": ["n_exit"], "know": [], "expect_ok": false },
		{ "name": "未知地點", "phase": "morning", "loc": "unknown_loc", "seen": [], "know": [], "expect_ok": false },
		{ "name": "傳入夜間地點", "phase": "morning", "loc": "n_exit", "seen": ["n_exit"], "know": [], "expect_ok": false },
		{ "name": "未到訪任何 row", "phase": "morning", "loc": "sanquan", "seen": [], "know": [], "expect_ok": false },
		{ "name": "已持有知識卡", "phase": "morning", "loc": "sanquan", "seen": ["n_exit"], "know": ["k_night_sanquan"], "expect_ok": false },
		{ "name": "交集：非白天 且 未知地點 (phase優先)", "phase": "evening", "loc": "unknown_loc", "seen": [], "know": [], "expect_ok": false, "expected_reason": "not_day_phase" },
		{ "name": "交集：非白天 且 傳入夜間地點 (phase優先)", "phase": "night", "loc": "n_exit", "seen": ["n_exit"], "know": [], "expect_ok": false, "expected_reason": "not_day_phase" },
		{ "name": "交集：非白天 且 已持有知識卡 (phase優先)", "phase": "evening", "loc": "sanquan", "seen": ["n_exit"], "know": ["k_night_sanquan"], "expect_ok": false, "expected_reason": "not_day_phase" },
		{ "name": "合法可對位狀態", "phase": "morning", "loc": "sanquan", "seen": ["n_exit"], "know": [], "expect_ok": true },
	]

	for tc in cases:
		_reset_gs(gs)
		gs.set("phase", tc["phase"])
		var seen_dict: Dictionary = gs.get("night_locations_seen") as Dictionary
		for s in tc["seen"] as Array:
			seen_dict[str(s)] = true
		for k in tc["know"] as Array:
			gs.call("gain_card", str(k))

		var offer: Dictionary = PanelBuilder.alignment_offer(tc["loc"], gs, data_node)
		var offer_avail := bool(offer.get("available", false))

		var snap_before := (gs.call("serialize") as Dictionary).duplicate(true)
		var res: Dictionary = gs.call("confirm_night_alignment", tc["loc"])
		var confirm_ok := bool(res.get("ok", false))

		if tc["expect_ok"]:
			if offer_avail and confirm_ok:
				failed += _ok("案例『%s』：offer 與 confirm 一致為 true" % tc["name"])
			else:
				failed += _fail("案例『%s』預期成功但分歧：offer=%s, confirm=%s" % [tc["name"], offer_avail, confirm_ok])
		else:
			if not offer_avail and not confirm_ok:
				var code := str(res.get("reason_code", ""))
				if tc.has("expected_reason"):
					if code == str(tc["expected_reason"]):
						failed += _ok("案例『%s』：offer 與 confirm 一致為 false 且 reason_code == %s" % [tc["name"], code])
					else:
						failed += _fail("案例『%s』reason_code 優先序不符 (實際: %s, 預期: %s)" % [tc["name"], code, str(tc["expected_reason"])])
				else:
					failed += _ok("案例『%s』：offer 與 confirm 一致為 false (reason=%s)" % [tc["name"], code])
			else:
				failed += _fail("案例『%s』預期拒絕但分歧：offer=%s, confirm=%s" % [tc["name"], offer_avail, confirm_ok])

	return failed
