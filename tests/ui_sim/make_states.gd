extends SceneTree

## 情境狀態產生器（依 開發設計方針.md > 情境狀態：產生的，不手寫，不進版控 實作）。
## 透過走查策略 + 指定決策，在各時段執行前擷取 checkpoint 狀態，產出驗收用 JSON。

const PanelBuilder := preload("res://scripts/core/panel_builder.gd")
const PlaythroughGreedy := preload("res://tests/headless/playthrough_greedy.gd")

static var _clean_state_template: Dictionary = {}


func _initialize() -> void:
	await process_frame

	var args: PackedStringArray = OS.get_cmdline_user_args()
	var output_dir := ""
	var regen_p3a_baseline := false
	var i := 0
	while i < args.size():
		if args[i] == "--output-dir" and i + 1 < args.size():
			output_dir = args[i + 1]
			i += 1
		elif args[i] == "--p3a-baseline":
			regen_p3a_baseline = true
		i += 1

	# 嚴禁 fallback 固定路徑：狀態產生失敗時 runner 若吃到上一次殘留在固定路徑
	# 的舊檔案，會綠燈但驗的是舊狀態，比紅燈更危險（開發設計方針.md > P1-G）。
	if output_dir.is_empty():
		printerr("make_states: 缺少必要參數 --output-dir <dir>")
		quit(1)
		return

	output_dir = output_dir.replace("\\", "/")
	if not output_dir.ends_with("/"):
		output_dir += "/"

	DirAccess.make_dir_recursive_absolute(output_dir)

	var ok := generate_all_states(self, output_dir, regen_p3a_baseline)
	if ok:
		print("make_states: 全部情境狀態產生完畢且後置條件通過。輸出目錄: %s" % output_dir)
		quit(0)
	else:
		printerr("make_states: 狀態產生失敗！")
		quit(1)


static func generate_all_states(tree: SceneTree, output_dir: String, regen_p3a_baseline: bool = false) -> bool:
	var data_node: Node = PlaythroughGreedy.setup_data(tree)

	# 1. 產生標準走查路徑上的 checkpoints（無覆寫決策）
	var standard_checkpoints: Dictionary = {
		"d3_morning": { "day": 3, "phase": "morning" },
		"d2_morning": { "day": 2, "phase": "morning" },
		"d3_afternoon": { "day": 3, "phase": "afternoon" },
		"d9_afternoon": { "day": 9, "phase": "afternoon" },
		"d10_night": { "day": 10, "phase": "night" },
		"d15_night": { "day": 15, "phase": "night" },
		"d24_night": { "day": 24, "phase": "night" },
		"d32_night": { "day": 32, "phase": "night" },
		"d45_afternoon": { "day": 45, "phase": "afternoon" },
		"d17_morning": { "day": 17, "phase": "morning" },
		"d22_afternoon": { "day": 22, "phase": "afternoon" },
		"d35_afternoon": { "day": 35, "phase": "afternoon" },
		"d43_morning": { "day": 43, "phase": "morning" },
		"d8_evening": { "day": 8, "phase": "evening" },
		"d13_evening": { "day": 13, "phase": "evening" },
		"d33_night": { "day": 33, "phase": "night" },
		"p3a_night_baseline": { "day": 14, "phase": "night" },
	}

	var res_std := _run_walk_with_checkpoints(tree, data_node, [], standard_checkpoints, output_dir)
	if not res_std:
		return false

	# K-112：_qa/p3a_baseline/ 只在明示 --p3a-baseline 時重生，一般 UI launcher 不再順手改寫。
	if regen_p3a_baseline:
		var p3a_dict: Dictionary = _load_state(output_dir, "p3a_night_baseline.json")
		if not p3a_dict.is_empty():
			if not _generate_p3a_baseline(tree, data_node, p3a_dict):
				printerr("p3a_baseline 產出失敗")
				return false

	# D3 的 requires 負向案例需要「尚未在 D2 下午拿到兩張情報」的合法起點；
	# 仍由走查器建立，只在產生情境時刻意跳過那一個行動時段。
	var d3_no_info_decisions: Array[Dictionary] = [
		{ "day": 2, "phase": "afternoon", "skip": true }
	]
	var d3_no_info_cp: Dictionary = { "d3_afternoon__no_info": { "day": 3, "phase": "afternoon" } }
	if not _run_walk_with_checkpoints(tree, data_node, d3_no_info_decisions, d3_no_info_cp, output_dir):
		return false

	# D9 的乾淨 checkpoint 給比較案例使用；知識列案例另產生到 D10，
	# 不直接改寫 checkpoint JSON，避免把規則效果偽造進狀態。
	var d9_knowledge_decisions: Array[Dictionary] = [
		{ "day": 3, "phase": "afternoon", "beat_id": "d3_pm_sanquan", "slot_id": "help_ahong", "card_id": "protagonist" },
		{ "day": 9, "phase": "afternoon", "beat_id": "d9_pm_columbarium", "slot_id": "count", "card_id": "protagonist" },
		{ "day": 9, "phase": "afternoon", "beat_id": "d9_pm_columbarium", "slot_id": "compare_years", "card_id": "info_forty_something" }
	]
	var d9_knowledge_cp: Dictionary = { "d10_night__knowledge": { "day": 10, "phase": "night" } }
	if not _run_walk_with_checkpoints(tree, data_node, d9_knowledge_decisions, d9_knowledge_cp, output_dir):
		return false

	# 產生 P1-H 完整知識清單狀態（從 D10 知識狀態出發，以合法 gain_card() 加入全部 slotless 卡）
	var gs_full: Node = PlaythroughGreedy.setup_game_state(tree, data_node)
	_reset_state(gs_full)
	var d10_bytes := FileAccess.get_file_as_bytes(output_dir + "d10_night__knowledge.json")
	var d10_dict: Dictionary = JSON.parse_string(d10_bytes.get_string_from_utf8())
	gs_full.deserialize(d10_dict)
	for card_id_key: String in data_node.loader.cards.keys():
		var c_def: Dictionary = data_node.loader.cards[card_id_key] as Dictionary
		if bool(c_def.get("slotless", false)):
			gs_full.gain_card(card_id_key)
	var full_snapshot: Dictionary = gs_full.serialize()
	var full_path := output_dir + "p1h_knowledge_full.json"
	var f_full := FileAccess.open(full_path, FileAccess.WRITE)
	if f_full == null:
		printerr("無法寫入狀態檔: %s" % full_path)
		return false
	f_full.store_string(JSON.stringify(full_snapshot, "\t"))
	f_full.close()
	if not _verify_checkpoint_postcondition("p1h_knowledge_full", full_snapshot, data_node):
		printerr("p1h_knowledge_full 後置條件失敗")
		return false

	# 產生 P2-A 多實例發狂卡狀態（3 張發狂卡，分別為 7, 5, 3 天倒數）
	var gs_mad: Node = PlaythroughGreedy.setup_game_state(tree, data_node)
	_reset_state(gs_mad)
	gs_mad.deserialize(d10_dict)
	_normalize_madness_only(gs_mad) # K-124：清掉標準路徑（D8）已合法產生的發狂卡，情境才是宣稱的精確張數
	gs_mad.gain_card("madness") # madness#1
	gs_mad.gain_card("madness") # madness#2
	gs_mad.gain_card("madness") # madness#3
	var mc: Dictionary = gs_mad.get("madness_clock") as Dictionary
	mc["madness#1"] = 7
	mc["madness#2"] = 5
	mc["madness#3"] = 3
	var mad_snapshot: Dictionary = gs_mad.serialize()
	var mad_path := output_dir + "p2a_multi_madness.json"
	var f_mad := FileAccess.open(mad_path, FileAccess.WRITE)
	if f_mad == null:
		printerr("無法寫入狀態檔: %s" % mad_path)
		return false
	f_mad.store_string(JSON.stringify(mad_snapshot, "\t"))
	f_mad.close()
	if not _verify_checkpoint_postcondition("p2a_multi_madness", mad_snapshot, data_node):
		printerr("p2a_multi_madness 後置條件失敗")
		return false

	# 產生 P2-B 縱慾出口的五個情境。全部從既有 checkpoint 出發，只用規則層入口
	# （gain_card / consume_action / add_relation）加工——不直接改 JSON（K-45）。
	# 手上兩張的用意：泡湯只清 soak_cards_cleared 張，一張的話「沒有全清」驗不出來。
	var d3am_dict: Dictionary = _load_state(output_dir, "d3_morning.json")
	var d3pm_dict: Dictionary = _load_state(output_dir, "d3_afternoon.json")
	var d17am_dict: Dictionary = _load_state(output_dir, "d17_morning.json")
	if d3am_dict.is_empty() or d3pm_dict.is_empty() or d17am_dict.is_empty():
		printerr("P2-B 情境的來源 checkpoint 讀取失敗")
		return false

	var gs_p2b: Node = PlaythroughGreedy.setup_game_state(tree, data_node)

	# ① 第 3 天上午、手上兩張發狂卡：出口槽可見性、放卡、泡湯成功路徑
	_reset_state(gs_p2b)
	gs_p2b.deserialize(d3am_dict)
	gs_p2b.gain_card("madness")
	gs_p2b.gain_card("madness")
	if not _write_p2b_state(output_dir, "p2b_morning_madness", gs_p2b.serialize(), data_node):
		return false

	# ② 第 3 天下午、手上兩張：泡湯呈灰（只能上午發動）
	_reset_state(gs_p2b)
	gs_p2b.deserialize(d3pm_dict)
	gs_p2b.gain_card("madness")
	gs_p2b.gain_card("madness")
	if not _write_p2b_state(output_dir, "p2b_afternoon_madness", gs_p2b.serialize(), data_node):
		return false

	# ③ 第 3 天上午、行動格已用掉：泡湯呈灰（格數不足）。
	# consume_action() 是規則層入口，不是直接把 action_spent 塞進 JSON。
	_reset_state(gs_p2b)
	gs_p2b.deserialize(d3am_dict)
	gs_p2b.gain_card("madness")
	gs_p2b.gain_card("madness")
	gs_p2b.consume_action(1)
	if not _write_p2b_state(output_dir, "p2b_morning_spent", gs_p2b.serialize(), data_node):
		return false

	# ④ 第 17 天上午、手上一張：暴力對人過了第 16 天門檻，性慾仍未達關係門檻
	_reset_state(gs_p2b)
	gs_p2b.deserialize(d17am_dict)
	_normalize_madness_only(gs_p2b) # K-124：D17 起點可能已帶標準路徑（D8）的發狂卡，清掉才是宣稱的一張
	gs_p2b.gain_card("madness")
	if not _write_p2b_state(output_dir, "p2b_d17_madness", gs_p2b.serialize(), data_node):
		return false

	# ⑤ 同上但與阿婕已達「疑似」（relation_scale.json 的序數是 1）：性慾槽出現
	_reset_state(gs_p2b)
	gs_p2b.deserialize(d17am_dict)
	_normalize_madness_only(gs_p2b)
	gs_p2b.gain_card("madness")
	gs_p2b.add_relation("ajie", 1)
	if not _write_p2b_state(output_dir, "p2b_d17_ajie", gs_p2b.serialize(), data_node):
		return false

	# 產生 P2-C 強制縱慾的兩個情境（K-61）。起點都是第 10 夜、發狂卡倒數壓到 1——
	# UI 案例只要推進一次跨到第 11 天 morning，跨日 tick 就會歸零並自動執行強制縱慾。
	# 倒數值直接寫 madness_clock，作法沿用 p2a_multi_madness：規則層沒有「設定倒數」
	# 這個入口，改用走 6 天只是把同一件事拉長，還會讓情境綁上那 6 天的內容。
	var d10n_dict: Dictionary = _load_state(output_dir, "d10_night.json")
	if d10n_dict.is_empty():
		printerr("P2-C 情境的來源 checkpoint 讀取失敗")
		return false

	var gs_p2c: Node = PlaythroughGreedy.setup_game_state(tree, data_node)

	# ① 一張歸零：文字播出、時段內留存、行動格被吃掉
	_reset_state(gs_p2c)
	gs_p2c.deserialize(d10n_dict)
	_normalize_madness_only(gs_p2c) # K-124：清掉標準路徑（D8）的發狂卡，情境才是宣稱的唯一一張
	gs_p2c.gain_card("madness")
	var mc_one: Dictionary = gs_p2c.get("madness_clock") as Dictionary
	mc_one["madness#1"] = 1
	if not _write_p2b_state(output_dir, "p2c_night_one_forced", gs_p2c.serialize(), data_node):
		return false

	# ② 同日兩張歸零：上午一格、下午一格，那一天完全沒有行動格
	_reset_state(gs_p2c)
	gs_p2c.deserialize(d10n_dict)
	_normalize_madness_only(gs_p2c)
	gs_p2c.gain_card("madness")
	gs_p2c.gain_card("madness")
	var mc_two: Dictionary = gs_p2c.get("madness_clock") as Dictionary
	mc_two["madness#1"] = 1
	mc_two["madness#2"] = 1
	if not _write_p2b_state(output_dir, "p2c_night_two_forced", gs_p2c.serialize(), data_node):
		return false

	# 產生 P2-D 視野門檻與發瘋 BE 的情境（K-68）。
	var d24n_dict: Dictionary = _load_state(output_dir, "d24_night.json")
	if d24n_dict.is_empty():
		printerr("P2-D 情境的來源 checkpoint (d24_night) 讀取失敗")
		return false

	var gs_p2d: Node = PlaythroughGreedy.setup_game_state(tree, data_node)

	# ① D24 night 2 張發狂卡（二樓有人在走 HIDDEN）
	_reset_state(gs_p2d)
	gs_p2d.deserialize(d24n_dict)
	_normalize_madness_only(gs_p2d) # K-124：清掉標準路徑（D8）的發狂卡，情境才是宣稱的精確張數
	gs_p2d.set_flag("boundary_bleeding", true)
	gs_p2d.set_flag("hold_d24am", false)
	gs_p2d.set_flag("hold_d24pm", false)
	gs_p2d.gain_card("madness")
	gs_p2d.gain_card("madness")
	if not _write_p2b_state(output_dir, "p2d_d24_two_cards", gs_p2d.serialize(), data_node):
		return false

	# ② D24 night 3 張發狂卡（二樓有人在走 OPEN）
	_reset_state(gs_p2d)
	gs_p2d.deserialize(d24n_dict)
	_normalize_madness_only(gs_p2d)
	gs_p2d.set_flag("boundary_bleeding", true)
	gs_p2d.set_flag("hold_d24am", false)
	gs_p2d.set_flag("hold_d24pm", false)
	gs_p2d.gain_card("madness")
	gs_p2d.gain_card("madness")
	gs_p2d.gain_card("madness")
	if not _write_p2b_state(output_dir, "p2d_d24_three_cards", gs_p2d.serialize(), data_node):
		return false

	# ③ 接近 cap 狀態：D10 night 手上 cap-1 張發狂卡，再開一次收費標記即達 cap。
	# 張數從 tuning 現算，不寫死 6——`madness_cap` 是可調數值，釘死會讓調值後這份情境
	# 變成「早就撞破」或「離 cap 還很遠」，而 UI 案例仍宣稱自己在驗 cap 邊界（K-114）。
	_reset_state(gs_p2d)
	gs_p2d.deserialize(d10n_dict)
	_normalize_madness_only(gs_p2d) # K-124：清掉標準路徑（D8）的發狂卡，張數才是從乾淨底重算的 cap-1
	var near_cap_count := int(data_node.tuning("madness_cap", 7)) - 1
	for i in range(near_cap_count):
		gs_p2d.gain_card("madness")
	if not _write_p2b_state(output_dir, "p2d_near_cap", gs_p2d.serialize(), data_node):
		return false

	# 產生 P3-D 夜間地點清單與詳情 UI 驗收情境。
	# 起點皆為 D14 night 狀態（p3a_night_baseline 或 d10_night），以規則層入口加工。
	var d14n_dict: Dictionary = _load_state(output_dir, "p3a_night_baseline.json")
	if d14n_dict.is_empty():
		d14n_dict = _load_state(output_dir, "d10_night.json")
	if d14n_dict.is_empty():
		printerr("P3-D 情境的來源 checkpoint (d14_night) 讀取失敗")
		return false

	var gs_p3d: Node = PlaythroughGreedy.setup_game_state(tree, data_node)

	# ① p3d_seen_unaligned: 已到訪未對位（enter_night_location("n_exit")，seen 但 knowledge 缺 k_night_sanquan）
	_reset_state(gs_p3d)
	gs_p3d.deserialize(d14n_dict)
	gs_p3d.enter_night_location("n_exit")
	gs_p3d.set("night_location_chosen", "")
	if not _write_p2b_state(output_dir, "p3d_seen_unaligned", gs_p3d.serialize(), data_node):
		return false

	# ② p3d_seen_nightonly: 已到訪夜間限定（enter_night_location("n_landmark")，seen 且無 day_counterpart）
	_reset_state(gs_p3d)
	gs_p3d.deserialize(d14n_dict)
	gs_p3d.enter_night_location("n_landmark")
	gs_p3d.set("night_location_chosen", "")
	if not _write_p2b_state(output_dir, "p3d_seen_nightonly", gs_p3d.serialize(), data_node):
		return false

	# ③ p3d_aligned_1to1: 已對位一對一（enter_night_location("n_exit") + gain_card("k_night_sanquan")）
	_reset_state(gs_p3d)
	gs_p3d.deserialize(d14n_dict)
	gs_p3d.enter_night_location("n_exit")
	gs_p3d.gain_card("k_night_sanquan")
	gs_p3d.set("night_location_chosen", "")
	if not _write_p2b_state(output_dir, "p3d_aligned_1to1", gs_p3d.serialize(), data_node):
		return false

	# ④ p3d_aligned_multi: 已對位多對一（enter_night_location("n_corridor") + gain_card("k_night_jinghe_back")）
	_reset_state(gs_p3d)
	gs_p3d.deserialize(d14n_dict)
	gs_p3d.enter_night_location("n_corridor")
	gs_p3d.gain_card("k_night_jinghe_back")
	gs_p3d.set("night_location_chosen", "")
	if not _write_p2b_state(output_dir, "p3d_aligned_multi", gs_p3d.serialize(), data_node):
		return false

	# 產生 P3-E 對位系統驗收情境（白天上午時段，seen 對應之夜間 row）
	var gs_p3e: Node = PlaythroughGreedy.setup_game_state(tree, data_node)

	# ① p3e_seen_counterpart: 白天上午，n_exit 已 seen，knowledge 缺 k_night_sanquan
	_reset_state(gs_p3e)
	gs_p3e.deserialize(d3am_dict)
	var seen_p3e := gs_p3e.get("night_locations_seen") as Dictionary
	seen_p3e["n_exit"] = true
	(gs_p3e.get("knowledge") as Dictionary).erase("k_night_sanquan")
	if not _write_p2b_state(output_dir, "p3e_seen_counterpart", gs_p3e.serialize(), data_node):
		return false

	# ② p3e_multi_first_seen: 白天上午 (D17)，多對一第一個 row (n_woodtags) 已 seen，knowledge 缺 k_night_temple
	_reset_state(gs_p3e)
	gs_p3e.deserialize(d17am_dict)
	var seen_multi := gs_p3e.get("night_locations_seen") as Dictionary
	seen_multi["n_woodtags"] = true
	(gs_p3e.get("knowledge") as Dictionary).erase("k_night_temple")
	if not _write_p2b_state(output_dir, "p3e_multi_first_seen", gs_p3e.serialize(), data_node):
		return false

	# 產生 P4-C 委託 UI 驗收情境。從既有 d17_morning checkpoint（標準走查器 custom_decisions=[]
	# 產出，只到訪演出、不放任何卡，protagonist 已在第 1 天 evening 到站演出取得，
	# d17_morning_phone 這個 fixed on_enter beat 尚未播過，人物卡尚未發出）推進一步到下午——
	# d17_19_prescription 是 afternoon-only 槽，這是唯一能保證「乾淨、零人物卡」的可靠起點。
	var gs_p4c: Node = PlaythroughGreedy.setup_game_state(tree, data_node)
	_reset_state(gs_p4c)
	gs_p4c.deserialize(d17am_dict)
	gs_p4c.call("advance_phase") # morning -> afternoon

	# ① p4c_d17_no_person: 零人物卡、教學未看過——委託候選應完全不出現，且是唯一能在
	# 真實 UI 中觸發 delegation_tutorial_available 信號的起點（經由「跟阿財做事」的 gain）。
	if not _write_p2b_state(output_dir, "p4c_d17_no_person", gs_p4c.serialize(), data_node):
		return false

	# ② p4c_d17_with_person: 已持有阿婕與阿珠兩張人物卡（跳過教學，用於候選確認流程案例）。
	gs_p4c.call("gain_card", "npc_ajie")
	gs_p4c.call("mark_delegation_tutorial_seen")
	gs_p4c.call("gain_card", "npc_azhu")
	if not _write_p2b_state(output_dir, "p4c_d17_with_person", gs_p4c.serialize(), data_node):
		return false

	# ③ p4c_ajie_indulge_ready: 在 ② 之上再備一張發狂卡、把阿婕關係設到「疑似」——
	# D17 下午山泉閣會同時出現 x_lust_ajie 縱慾出口與 ask_ajie 委託候選，
	# 用於驗「對阿婕縱慾即失去委託資格、候選當場消失」的 P2→P4-C 整合（p4c_07）。
	gs_p4c.call("gain_card", "madness")                    # madness#1 ＋ madness_clock（縱慾前置）
	(gs_p4c.get("relations") as Dictionary)["ajie"] = 1    # 疑似（data/relation_scale.json）
	if not _write_p2b_state(output_dir, "p4c_ajie_indulge_ready", gs_p4c.serialize(), data_node):
		return false

	# D45 coda 的 UI 案例必須真的帶著第 13 天名冊情報卡，否則只能驗到
	# 「比對槽不存在」而不是結局的升級路徑。
	var d45_coda_decisions: Array[Dictionary] = [
		{ "day": 13, "phase": "afternoon", "beat_id": "d13_pm_registry", "slot_id": "read", "card_id": "protagonist" }
	]
	var d45_coda_cp: Dictionary = {
		"d45_evening": { "day": 45, "phase": "evening" },
		"p4e_d45_afternoon": { "day": 45, "phase": "afternoon" }
	}
	if not _run_walk_with_checkpoints(tree, data_node, d45_coda_decisions, d45_coda_cp, output_dir):
		return false

	# 2. 產生 D32 邀請分支（阿婕、阿薇、無邀請）
	var ajie_decisions: Array[Dictionary] = [
		{ "day": 29, "phase": "afternoon", "beat_id": "d29_pm_invitation", "slot_id": "invite_ajie", "group_id": "invitation" }
	]
	var ajie_cp: Dictionary = { "d32_morning__ajie": { "day": 32, "phase": "morning" } }
	if not _run_walk_with_checkpoints(tree, data_node, ajie_decisions, ajie_cp, output_dir):
		return false

	var awei_decisions: Array[Dictionary] = [
		{ "day": 29, "phase": "afternoon", "beat_id": "d29_pm_invitation", "slot_id": "invite_awei", "group_id": "invitation" }
	]
	var awei_cp: Dictionary = { "d32_morning__awei": { "day": 32, "phase": "morning" } }
	if not _run_walk_with_checkpoints(tree, data_node, awei_decisions, awei_cp, output_dir):
		return false

	var none_decisions: Array[Dictionary] = [
		{ "day": 29, "phase": "afternoon", "beat_id": "d29_pm_invitation", "slot_id": "invite_none", "group_id": "invitation" }
	]
	var none_cp: Dictionary = { "d32_morning__none": { "day": 32, "phase": "morning" } }
	if not _run_walk_with_checkpoints(tree, data_node, none_decisions, none_cp, output_dir):
		return false

	# 3. 產生 D5 evening 殘響分支（到場陪阿宏 vs 錯過去老街）
	var attend_d3_decisions: Array[Dictionary] = [
		{ "day": 3, "phase": "afternoon", "beat_id": "d3_pm_sanquan", "slot_id": "help_ahong", "card_id": "protagonist" }
	]
	var d5_attend_cp: Dictionary = { "d5_evening__attended": { "day": 5, "phase": "evening" } }
	if not _run_walk_with_checkpoints(tree, data_node, attend_d3_decisions, d5_attend_cp, output_dir):
		return false

	var miss_d3_decisions: Array[Dictionary] = [
		{ "day": 3, "phase": "afternoon", "beat_id": "d3_pm_oldstreet", "slot_id": "wander", "card_id": "protagonist" }
	]
	var d5_miss_cp: Dictionary = { "d5_evening__miss_sanquan": { "day": 5, "phase": "evening" } }
	if not _run_walk_with_checkpoints(tree, data_node, miss_d3_decisions, d5_miss_cp, output_dir):
		return false

	# 4. 產生 D22 拍立得分支（兩條都由 D3 的真實選擇自然產生）
	var polaroid_decisions: Array[Dictionary] = [
		{ "day": 3, "phase": "afternoon", "beat_id": "d3_pm_sanquan", "slot_id": "handle_couple", "card_id": "protagonist" }
	]
	var d22_polaroid_cp: Dictionary = { "d22_afternoon__with_polaroid": { "day": 22, "phase": "afternoon" } }
	if not _run_walk_with_checkpoints(tree, data_node, polaroid_decisions, d22_polaroid_cp, output_dir):
		return false
	var no_polaroid_decisions: Array[Dictionary] = [
		{ "day": 3, "phase": "afternoon", "beat_id": "d3_pm_sanquan", "slot_id": "help_ahong", "card_id": "protagonist" }
	]
	var d22_no_polaroid_cp: Dictionary = { "d22_afternoon__no_polaroid": { "day": 22, "phase": "afternoon" } }
	if not _run_walk_with_checkpoints(tree, data_node, no_polaroid_decisions, d22_no_polaroid_cp, output_dir):
		return false

	# 5. 產生 D27 evening 知識分流（收留阿薇且問陳醫師 vs 僅收留）
	var d27_both_decisions: Array[Dictionary] = [
		{ "day": 23, "phase": "morning", "beat_id": "d23_am_settle_grandma", "slot_id": "settle", "card_id": "protagonist" },
		{ "day": 27, "phase": "afternoon", "beat_id": "d27_pm_clinic", "slot_id": "chen", "card_id": "protagonist" }
	]
	var d27_both_cp: Dictionary = { "d27_evening__both": { "day": 27, "phase": "evening" } }
	if not _run_walk_with_checkpoints(tree, data_node, d27_both_decisions, d27_both_cp, output_dir):
		return false

	var d27_partial_decisions: Array[Dictionary] = [
		{ "day": 23, "phase": "morning", "beat_id": "d23_am_settle_grandma", "slot_id": "settle", "card_id": "protagonist" },
		{ "day": 27, "phase": "afternoon", "beat_id": "d27_pm_clinic", "slot_id": "uncle", "card_id": "protagonist" }
	]
	var d27_partial_cp: Dictionary = { "d27_evening__partial": { "day": 27, "phase": "evening" } }
	if not _run_walk_with_checkpoints(tree, data_node, d27_partial_decisions, d27_partial_cp, output_dir):
		return false

	# 6. 產生 D40 morning 具有 info_something_off 分支（D3 拍立得 + D29 邀阿婕 + D39 比對照片）
	var d40_decisions: Array[Dictionary] = [
		{ "day": 3, "phase": "afternoon", "beat_id": "d3_pm_sanquan", "slot_id": "handle_couple", "card_id": "protagonist" },
		{ "day": 29, "phase": "afternoon", "beat_id": "d29_pm_invitation", "slot_id": "invite_ajie", "group_id": "invitation" },
		{ "day": 39, "phase": "afternoon", "beat_id": "d39_pm_readings", "slot_id": "objective", "card_id": "equip_polaroid" }
	]
	var d40_cp: Dictionary = { "d40_morning": { "day": 40, "phase": "morning" } }
	if not _run_walk_with_checkpoints(tree, data_node, d40_decisions, d40_cp, output_dir):
		return false

	# 7. 產生 D43 afternoon 同時開放 riverside (d43_pm_zhou) 與 sanquan (d43_conclusion)
	var d43_decisions: Array[Dictionary] = [
		{ "day": 3, "phase": "afternoon", "beat_id": "d3_pm_sanquan", "slot_id": "handle_couple", "card_id": "protagonist" },
		{ "day": 22, "phase": "afternoon", "beat_id": "d22_pm_sandbags", "slot_id": "obs_walk", "card_id": "equip_polaroid", "group_id": "acai_read" }
	]
	var d43_cp: Dictionary = { "d43_afternoon": { "day": 43, "phase": "afternoon" } }
	if not _run_walk_with_checkpoints(tree, data_node, d43_decisions, d43_cp, output_dir):
		return false

	# 8. P4-E：遭遇 UI 驗收情境
	# ① p4e_d8_night: D8 夜間，遭遇已啟動（intro 階段）。
	# 從既有 d8_evening 狀態推進一步至 night，並呼叫 play_night_fixed() 啟動 n_manydoors_ch1。
	var gs_p4e_d8: Node = PlaythroughGreedy.setup_game_state(tree, data_node)
	_reset_state(gs_p4e_d8)
	var d8_eve_dict := _load_state(output_dir, "d8_evening.json")
	if d8_eve_dict.is_empty():
		printerr("p4e: 缺少前置 d8_evening.json")
		return false
	gs_p4e_d8.deserialize(d8_eve_dict)
	gs_p4e_d8.call("advance_phase") # evening -> night
	gs_p4e_d8.call("play_night_fixed") # starts n_manydoors_ch1 in intro stage
	if not _write_p2b_state(output_dir, "p4e_d8_night", gs_p4e_d8.serialize(), data_node):
		return false

	# ② p4e_d45_afternoon: D45 下午，遭遇已啟動（intro 階段）。
	# 由既有 d45_coda_cp 走查直接自然產生，不需人為修剪手牌（D45 遭遇 per_round_slot_cost: 0）。

	return true


static func _run_walk_with_checkpoints(
	tree: SceneTree,
	data_node: Node,
	custom_decisions: Array[Dictionary],
	checkpoints: Dictionary,
	output_dir: String
) -> bool:
	var gs: Node = PlaythroughGreedy.setup_game_state(tree, data_node)
	_reset_state(gs)

	for d in range(1, 46):
		for phase in ["morning", "afternoon", "evening", "night"]:
			if d == 45 and phase == "night":
				break

			# 檢查是否有 checkpoint
			for cp_name: String in checkpoints.keys():
				var cp_spec: Dictionary = checkpoints[cp_name] as Dictionary
				if int(cp_spec.get("day", -1)) == d and str(cp_spec.get("phase", "")) == phase:
					var snapshot: Dictionary = gs.serialize()
					var file_path := output_dir + cp_name + ".json"
					var json_text := JSON.stringify(snapshot, "\t")
					var f := FileAccess.open(file_path, FileAccess.WRITE)
					if f == null:
						printerr("無法寫入狀態檔: %s" % file_path)
						return false
					f.store_string(json_text)
					f.close()

					# 驗證後置條件
					var post_ok := _verify_checkpoint_postcondition(cp_name, snapshot, data_node)
					if not post_ok:
						printerr("checkpoint 後置條件失敗: %s" % cp_name)
						return false

			# 執行時段動作
			match phase:
				"morning", "afternoon":
					# 先演出當前時段所有 OPEN beats，讓 on_enter 效果結算
					var locs := PanelBuilder.available_locations(gs, data_node)
					var played_beats: Dictionary = {}
					var changed := true
					while changed:
						changed = false
						for loc_id in locs:
							var view: Dictionary = gs.build_panel(loc_id)
							for beat_view: Dictionary in view.get("beats", []) as Array:
								if int(beat_view.get("tri", -1)) != PanelBuilder.TriState.OPEN:
									continue
								var b: Dictionary = beat_view.get("beat", {}) as Dictionary
								var b_id := str(b.get("id", ""))
								if b_id.is_empty() or played_beats.has(b_id):
									continue
								played_beats[b_id] = true
								gs.play_beat(b_id)
								changed = true

					var overridden := false
					var skipped := false
					for dec in custom_decisions:
						if int(dec.get("day", -1)) == d and str(dec.get("phase", "")) == phase:
							if bool(dec.get("skip", false)):
								if overridden:
									printerr("自訂決策同一時段不可同時 skip 與放置: %s" % str(dec))
									return false
								skipped = true
								continue
							var b_id := str(dec.get("beat_id", ""))
							var s_id := str(dec.get("slot_id", ""))
							var c_id := str(dec.get("card_id", ""))
							var g_id := str(dec.get("group_id", ""))
							if not g_id.is_empty():
								var res: Dictionary = gs.choose(b_id, g_id, s_id, c_id)
								if not res.get("ok", false):
									printerr("自訂決策 choose 失敗: %s (reason: %s)" % [str(dec), str(res)])
									return false
							else:
								var res: Dictionary = gs.try_place(c_id, b_id, s_id)
								if not res.get("ok", false):
									printerr("自訂決策 try_place 失敗: %s (reason: %s)" % [str(dec), str(res)])
									return false
							overridden = true
							# 不 break：同一時段可依序執行多個自然決策。
					if not overridden and not skipped:
						PlaythroughGreedy.execute_action_phase(gs, data_node, d, phase)
					if gs.phase == phase:
						gs.advance_phase()
				"evening":
					PlaythroughGreedy.execute_evening_phase(gs, data_node, d)
					if gs.phase == phase:
						gs.advance_phase()
				"night":
					PlaythroughGreedy.execute_night_phase(gs, data_node, d, false)
					if gs.phase == phase:
						gs.advance_phase()

	return true


## 讀既有 checkpoint JSON 當作加工起點；讀不到回空字典（呼叫端當失敗處理）。
static func _load_state(output_dir: String, file_name: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(output_dir + file_name)
	if bytes.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	return parsed as Dictionary if parsed is Dictionary else {}


## 寫出 P2-B 情境並跑後置條件。與既有情境同一套規約：寫檔失敗或後置條件不過就整支失敗。
static func _write_p2b_state(output_dir: String, cp_name: String, snapshot: Dictionary, data_node: Node = null) -> bool:
	var path := output_dir + cp_name + ".json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("無法寫入狀態檔: %s" % path)
		return false
	f.store_string(JSON.stringify(snapshot, "\t"))
	f.close()
	if not _verify_checkpoint_postcondition(cp_name, snapshot, data_node):
		printerr("%s 後置條件失敗" % cp_name)
		return false
	return true


## Fixture-only 正規化（K-124）：只供「精確張數」合成情境使用。標準路徑（含 D8 定日遭遇）
## 已合法產生的發狂卡會混進後續 checkpoint，讓「手上恰好 N 張」的宣稱失真；呼叫端在
## deserialize() 之後、gain_card() 之前呼叫本函式，清掉 hand 內既有 madness instance、
## 對應 madness_clock、forced_pending，並重設 _madness_counter，讓後續 gain_card() 生出的
## instance id 從 #1 起算。不清其他 flags／relations／歷史計數——那些是標準路徑的真實歷史。
static func _normalize_madness_only(gs: Node) -> void:
	var kept: Array[String] = []
	for c in (gs.get("hand") as Array):
		var c_str := str(c)
		if not c_str.begins_with("madness#"):
			kept.append(c_str)
	gs.set("hand", kept)
	gs.set("madness_clock", {})
	gs.set("forced_pending", [])
	gs.set("_madness_counter", 0)
	for c: String in kept:
		if c.begins_with("madness#"):
			push_error("_normalize_madness_only: 殘留 madness instance 未清除: %s" % c)


## hand 內 madness instance 的張數（不含其他卡）。
static func _madness_hand_count(hand: Array) -> int:
	var n := 0
	for c in hand:
		if str(c).begins_with("madness#"):
			n += 1
	return n


## madness_clock 的 key 集合必須與 hand 內的 madness instance 完全一致——
## 不多（沒清乾淨的殘留）、不少（漏建 clock）。
static func _madness_clock_matches_hand(run: Dictionary) -> bool:
	var hand: Array = run.get("hand", []) as Array
	var mc: Dictionary = run.get("madness_clock", {}) as Dictionary
	var hand_set: Dictionary = {}
	for c in hand:
		var c_str := str(c)
		if c_str.begins_with("madness#"):
			hand_set[c_str] = true
	if hand_set.size() != mc.size():
		return false
	for k in hand_set.keys():
		if not mc.has(k):
			return false
	return true


static func _fixture_card_base_id(id: String) -> String:
	var hash_idx := id.rfind("#")
	if hash_idx >= 0:
		return id.substr(0, hash_idx)
	return id


static func _verify_checkpoint_postcondition(cp_name: String, snapshot: Dictionary, data_node: Node = null) -> bool:
	var run: Dictionary = snapshot.get("run", {}) as Dictionary
	var flags: Dictionary = run.get("flags", {}) as Dictionary
	var choices: Dictionary = run.get("choices", {}) as Dictionary
	var hand: Array = run.get("hand", []) as Array
	var day := int(run.get("day", 0))
	var phase := str(run.get("phase", ""))

	match cp_name:
		"d2_morning":
			return day == 2 and phase == "morning" and hand.has("protagonist")
		"d3_morning":
			return day == 3 and phase == "morning" and hand.has("protagonist")
		"d3_afternoon":
			return day == 3 and phase == "afternoon" and hand.has("protagonist")
		"d5_evening":
			return day == 5 and phase == "evening"
		"d5_evening__attended":
			return day == 5 and phase == "evening" and flags.get("ahong_last_normal_contact", false) == true
		"d5_evening__miss_sanquan":
			return day == 5 and phase == "evening" and flags.get("ahong_last_normal_contact", false) == false
		"d9_afternoon":
			return day == 9 and phase == "afternoon"
		"d10_night":
			return day == 10 and phase == "night"
		"d10_night__knowledge":
			return day == 10 and phase == "night" and (_state_knowledge(snapshot).has("k_forty_something"))
		"p1h_knowledge_full":
			return day == 10 and phase == "night" and (_state_knowledge(snapshot).size() >= 10)
		"p2a_multi_madness":
			var mc_p2a: Dictionary = run.get("madness_clock", {}) as Dictionary
			return day == 10 and phase == "night" and _madness_clock_matches_hand(run) \
				and _madness_hand_count(hand) == 3 \
				and hand.has("madness#1") and hand.has("madness#2") and hand.has("madness#3") \
				and int(mc_p2a.get("madness#1", -1)) == 7 and int(mc_p2a.get("madness#2", -1)) == 5 and int(mc_p2a.get("madness#3", -1)) == 3
		"p2b_morning_madness":
			return day == 3 and phase == "morning" and hand.has("madness#1") and hand.has("madness#2") \
				and not bool(run.get("action_spent", true))
		"p2b_afternoon_madness":
			return day == 3 and phase == "afternoon" and hand.has("madness#1") and hand.has("madness#2")
		"p2b_morning_spent":
			return day == 3 and phase == "morning" and hand.has("madness#1") and hand.has("madness#2") \
				and bool(run.get("action_spent", false))
		"p2b_d17_madness":
			return day == 17 and phase == "morning" and _madness_clock_matches_hand(run) \
				and _madness_hand_count(hand) == 1 and hand.has("madness#1") \
				and int((run.get("relations", {}) as Dictionary).get("ajie", 0)) < 1
		"p2b_d17_ajie":
			return day == 17 and phase == "morning" and _madness_clock_matches_hand(run) \
				and _madness_hand_count(hand) == 1 and hand.has("madness#1") \
				and int((run.get("relations", {}) as Dictionary).get("ajie", 0)) >= 1
		"p2c_night_one_forced":
			return day == 10 and phase == "night" and _madness_clock_matches_hand(run) \
				and _madness_hand_count(hand) == 1 and hand.has("madness#1") \
				and int((run.get("madness_clock", {}) as Dictionary).get("madness#1", 0)) == 1
		"p2c_night_two_forced":
			return day == 10 and phase == "night" and _madness_clock_matches_hand(run) \
				and _madness_hand_count(hand) == 2 \
				and hand.has("madness#1") and hand.has("madness#2") \
				and int((run.get("madness_clock", {}) as Dictionary).get("madness#1", 0)) == 1 \
				and int((run.get("madness_clock", {}) as Dictionary).get("madness#2", 0)) == 1
		"p2d_d24_two_cards":
			return day == 24 and phase == "night" and _madness_clock_matches_hand(run) \
				and _madness_hand_count(hand) == 2 and hand.has("madness#1") and hand.has("madness#2")
		"p2d_d24_three_cards":
			return day == 24 and phase == "night" and _madness_clock_matches_hand(run) \
				and _madness_hand_count(hand) == 3 and hand.has("madness#1") and hand.has("madness#2") and hand.has("madness#3")
		"p2d_near_cap":
			# 「手上恰好 cap-1 張」——張數與 instance 名都從 tuning 現算，不寫死 6／7（K-114）。
			var cap := 7
			if data_node != null and data_node.has_method("tuning"):
				cap = int(data_node.tuning("madness_cap", 7))
			return day == 10 and phase == "night" and _madness_clock_matches_hand(run) \
				and _madness_hand_count(hand) == cap - 1 \
				and hand.has("madness#%d" % (cap - 1)) and not hand.has("madness#%d" % cap)
		"d15_night":
			return day == 15 and phase == "night"
		"d24_night":
			return day == 24 and phase == "night"
		"d32_night":
			return day == 32 and phase == "night"
		"d45_afternoon":
			return day == 45 and phase == "afternoon" and flags.get("final_day", false) == true
		"d17_morning":
			return day == 17 and phase == "morning"
		"d22_afternoon":
			return day == 22 and phase == "afternoon"
		"d22_afternoon__with_polaroid":
			return day == 22 and phase == "afternoon" and hand.has("equip_polaroid")
		"d22_afternoon__no_polaroid":
			return day == 22 and phase == "afternoon" and not hand.has("equip_polaroid")
		"d3_afternoon__no_info":
			return day == 3 and phase == "afternoon" and not hand.has("info_husband_version") and not hand.has("info_wife_version")
		"d27_evening__both":
			return day == 27 and phase == "evening" and flags.get("awei_sheltering", false) == true and flags.get("dodger_chen", false) == true
		"d27_evening__partial":
			return day == 27 and phase == "evening" and flags.get("awei_sheltering", false) == true and flags.get("dodger_chen", false) == false
		"d32_morning__ajie":
			return day == 32 and phase == "morning" and choices.get("d29_pm_invitation::invitation", "") == "invite_ajie"
		"d32_morning__awei":
			return day == 32 and phase == "morning" and choices.get("d29_pm_invitation::invitation", "") == "invite_awei"
		"d32_morning__none":
			return day == 32 and phase == "morning" and choices.get("d29_pm_invitation::invitation", "") == "invite_none"
		"d35_afternoon":
			return day == 35 and phase == "afternoon" and flags.get("inheritance_offered", false) == true
		"d40_morning":
			return day == 40 and phase == "morning" and hand.has("info_something_off")
		"d43_morning":
			return day == 43 and phase == "morning"
		"d43_afternoon":
			return day == 43 and phase == "afternoon" and hand.has("info_acai_walk")
		"d45_evening":
			return day == 45 and phase == "evening" and hand.has("info_registry")
		"d8_evening":
			return day == 8 and phase == "evening"
		"d13_evening":
			return day == 13 and phase == "evening"
		"d33_night":
			return day == 33 and phase == "night"
		"p3d_seen_unaligned":
			var seen_unaligned: Dictionary = _state_meta(snapshot).get("night_locations_seen", {}) as Dictionary
			return day == 14 and phase == "night" and seen_unaligned.has("n_exit") and not _state_knowledge(snapshot).has("k_night_sanquan")
		"p3d_seen_nightonly":
			var seen_nightonly: Dictionary = _state_meta(snapshot).get("night_locations_seen", {}) as Dictionary
			return day == 14 and phase == "night" and seen_nightonly.has("n_landmark")
		"p3d_aligned_1to1":
			var seen_1to1: Dictionary = _state_meta(snapshot).get("night_locations_seen", {}) as Dictionary
			return day == 14 and phase == "night" and seen_1to1.has("n_exit") and _state_knowledge(snapshot).has("k_night_sanquan")
		"p3d_aligned_multi":
			var seen_multi: Dictionary = _state_meta(snapshot).get("night_locations_seen", {}) as Dictionary
			return day == 14 and phase == "night" and seen_multi.has("n_corridor") and _state_knowledge(snapshot).has("k_night_jinghe_back")
		"p4c_d17_no_person":
			# K-124：零人物卡按卡片 type 計數，不能用 hand.size()==1——D17 真實走查手上
			# 合法帶著其他非人物卡（發狂卡、情報卡等），契約只承諾「沒有人物卡」。
			if data_node == null:
				return false
			var meta_no_person: Dictionary = _state_meta(snapshot)
			var person_count := 0
			for c: String in hand:
				var cdef: Dictionary = data_node.loader.cards.get(_fixture_card_base_id(c), {}) as Dictionary
				if str(cdef.get("type", "")) == "person":
					person_count += 1
			return day == 17 and phase == "afternoon" and person_count == 0 \
				and bool(meta_no_person.get("delegation_tutorial_seen", true)) == false
		"p4c_d17_with_person":
			var meta_with_person: Dictionary = _state_meta(snapshot)
			return day == 17 and phase == "afternoon" and hand.has("npc_ajie") and hand.has("npc_azhu") \
				and bool(meta_with_person.get("delegation_tutorial_seen", false)) == true
		"p4c_ajie_indulge_ready":
			var has_madness := false
			for c: String in hand:
				if str(c).begins_with("madness#"):
					has_madness = true
					break
			return day == 17 and phase == "afternoon" and hand.has("npc_ajie") and has_madness
		"p3a_night_baseline":
			if day != 14:
				printerr("p3a_night_baseline 後置條件失敗：預期 day == 14，實際 %d" % day)
				return false
			if phase != "night":
				printerr("p3a_night_baseline 後置條件失敗：預期 phase == 'night'，實際 %s" % phase)
				return false
			var chosen: String = str(run.get("night_location_chosen", ""))
			if not chosen.is_empty():
				printerr("p3a_night_baseline 後置條件失敗：預期 night_location_chosen 為空，實際 %s" % chosen)
				return false
			var madness_count := 0
			for c in hand:
				if str(c).begins_with("madness"):
					madness_count += 1
			var madness_cap: int = 7
			if data_node != null and data_node.has_method("tuning"):
				madness_cap = int(data_node.tuning("madness_cap", 7))
			elif FileAccess.file_exists("res://data/tuning.json"):
				var tf := FileAccess.open("res://data/tuning.json", FileAccess.READ)
				if tf != null:
					var tj: Variant = JSON.parse_string(tf.get_as_text())
					if tj is Dictionary and tj.has("madness_cap"):
						madness_cap = int(tj.get("madness_cap", 7))
			if madness_count >= madness_cap:
				printerr("p3a_night_baseline 後置條件失敗：預期 madness < %d，實際 %d" % [madness_cap, madness_count])
				return false
			return true
		"p4e_d8_night":
			var enc_d8: Dictionary = snapshot.get("run", {}).get("active_encounter", {}) as Dictionary
			return day == 8 and phase == "night" \
				and str(enc_d8.get("beat_id", "")) == "n_manydoors_ch1" \
				and str(enc_d8.get("stage", "")) == "intro"
		"p4e_d45_afternoon":
			var enc_d45: Dictionary = snapshot.get("run", {}).get("active_encounter", {}) as Dictionary
			return day == 45 and phase == "afternoon" \
				and str(enc_d45.get("beat_id", "")) == "d45_encounter" \
				and str(enc_d45.get("stage", "")) == "intro"
		_:
			return true


static func _generate_p3a_baseline(tree: SceneTree, data_node: Node, baseline_snapshot: Dictionary) -> bool:
	var base_dir := "res://_qa/p3a_baseline/"
	var global_dir := ProjectSettings.globalize_path(base_dir).replace("\\", "/")
	if not global_dir.ends_with("/"):
		global_dir += "/"
	DirAccess.make_dir_recursive_absolute(global_dir)

	# 1. 寫出狀態檔
	var f_state := FileAccess.open(global_dir + "p3a_night_baseline.json", FileAccess.WRITE)
	if f_state == null:
		printerr("無法寫入 _qa/p3a_baseline/p3a_night_baseline.json")
		return false
	f_state.store_string(JSON.stringify(baseline_snapshot, "\t"))
	f_state.close()

	# 2. 計算 expected 基準值
	# (a) available_locations()
	var gs_avail: Node = PlaythroughGreedy.setup_game_state(tree, data_node)
	_reset_state(gs_avail)
	gs_avail.deserialize(baseline_snapshot)
	var avail_locs: Array[String] = PanelBuilder.available_locations(gs_avail, data_node)

	# (b) 首次發卡 (first_card_grant)
	var gs_grant: Node = PlaythroughGreedy.setup_game_state(tree, data_node)
	_reset_state(gs_grant)
	gs_grant.deserialize(baseline_snapshot)
	var paid_loc := "n_ahong_1"
	if not avail_locs.has(paid_loc):
		printerr("p3a_baseline: 在 D14 night 可用地點中找不到指定的收費標記 %s" % paid_loc)
		return false
	var ldef: Dictionary = data_node.loader.locations.get(paid_loc, {}) as Dictionary
	if int(ldef.get("madness_cost", 0)) <= 0:
		printerr("p3a_baseline: 指定的地點 %s 不是收費標記（madness_cost <= 0）" % paid_loc)
		return false
	var entry_res: Dictionary = gs_grant.enter_night_location(paid_loc)
	var grant_lines: PackedStringArray = entry_res.get("lines", PackedStringArray())
	var grant_seen: Dictionary = (gs_grant.get("night_locations_seen") as Dictionary).duplicate(true)
	var grant_hand: Array = (gs_grant.get("hand") as Array).duplicate(true)
	var grant_clock: Dictionary = (gs_grant.get("madness_clock") as Dictionary).duplicate(true)
	var grant_res: Dictionary = {
		"target_location": paid_loc,
		"lines": Array(grant_lines),
		"night_locations_seen": grant_seen,
		"hand": grant_hand,
		"madness_clock": grant_clock,
	}

	# (c) fixed 流程 (fixed_flow)
	var gs_fixed: Node = PlaythroughGreedy.setup_game_state(tree, data_node)
	_reset_state(gs_fixed)
	gs_fixed.deserialize(baseline_snapshot)
	gs_fixed.sleep_night()
	gs_fixed.advance_phase()
	PlaythroughGreedy.execute_action_phase(gs_fixed, data_node, 15, "morning")
	gs_fixed.advance_phase()
	PlaythroughGreedy.execute_action_phase(gs_fixed, data_node, 15, "afternoon")
	gs_fixed.advance_phase()
	PlaythroughGreedy.execute_evening_phase(gs_fixed, data_node, 15)
	gs_fixed.advance_phase()
	var avail_d15: Array[String] = PanelBuilder.available_locations(gs_fixed, data_node)
	gs_fixed.play_night_fixed()
	var beats_entered_d15: Array = (gs_fixed.get("beats_entered") as Dictionary).keys()
	beats_entered_d15.sort()
	var fixed_res: Dictionary = {
		"day": int(gs_fixed.get("day")),
		"phase": str(gs_fixed.get("phase")),
		"available_locations": avail_d15,
		"beats_entered": beats_entered_d15,
	}

	var expected_dict: Dictionary = {
		"available_locations": avail_locs,
		"first_card_grant": grant_res,
		"fixed_flow": fixed_res,
	}

	var f_exp := FileAccess.open(global_dir + "p3a_night_baseline.expected.json", FileAccess.WRITE)
	if f_exp == null:
		printerr("無法寫入 _qa/p3a_baseline/p3a_night_baseline.expected.json")
		return false
	f_exp.store_string(JSON.stringify(expected_dict, "\t"))
	f_exp.close()

	print("p3a_baseline 成功產出至 %s" % global_dir)
	return true


static func _reset_state(gs: Node) -> void:
	if _clean_state_template.is_empty():
		gs.set("day", 1)
		gs.set("phase", "morning")
		gs.set("hand", ["protagonist"])
		gs.set("beats_entered", {})
		gs.set("slots_placed", {})
		gs.set("choices", {})
		gs.set("flags", {})
		gs.set("switches", {})
		gs.set("switch_progress", {})
		gs.set("relations", {})
		gs.set("action_spent", false)
		gs.set("npc_action_counts", {})
		gs.set("knowledge", {})
		_clean_state_template = (gs.call("serialize") as Dictionary).duplicate(true)
	gs.call("deserialize", _clean_state_template.duplicate(true))

static func _state_knowledge(snapshot: Dictionary) -> Dictionary:
	return (snapshot.get("meta", {}) as Dictionary).get("knowledge", {}) as Dictionary

static func _state_meta(snapshot: Dictionary) -> Dictionary:
	return snapshot.get("meta", {}) as Dictionary
