extends SceneTree

## 情境狀態產生器（依 開發設計方針.md > 情境狀態：產生的，不手寫，不進版控 實作）。
## 透過走查策略 + 指定決策，在各時段執行前擷取 checkpoint 狀態，產出驗收用 JSON。

const PanelBuilder := preload("res://scripts/core/panel_builder.gd")
const PlaythroughGreedy := preload("res://tests/headless/playthrough_greedy.gd")


func _initialize() -> void:
	await process_frame

	var args: PackedStringArray = OS.get_cmdline_user_args()
	var output_dir := ""
	var i := 0
	while i < args.size():
		if args[i] == "--output-dir" and i + 1 < args.size():
			output_dir = args[i + 1]
			i += 1
		i += 1

	if output_dir.is_empty():
		output_dir = "res://_qa/states/"

	output_dir = output_dir.replace("\\", "/")
	if not output_dir.ends_with("/"):
		output_dir += "/"

	DirAccess.make_dir_recursive_absolute(output_dir)

	var ok := generate_all_states(self, output_dir)
	if ok:
		print("make_states: 全部情境狀態產生完畢且後置條件通過。輸出目錄: %s" % output_dir)
		quit(0)
	else:
		printerr("make_states: 狀態產生失敗！")
		quit(1)


static func generate_all_states(tree: SceneTree, output_dir: String) -> bool:
	var data_node: Node = PlaythroughGreedy.setup_data(tree)

	# 1. 產生標準走查路徑上的 checkpoints（無覆寫決策）
	var standard_checkpoints: Dictionary = {
		"d2_morning": { "day": 2, "phase": "morning" },
		"d3_afternoon": { "day": 3, "phase": "afternoon" },
		"d9_afternoon": { "day": 9, "phase": "afternoon" },
		"d10_night": { "day": 10, "phase": "night" },
		"d17_morning": { "day": 17, "phase": "morning" },
		"d22_afternoon": { "day": 22, "phase": "afternoon" },
		"d35_afternoon": { "day": 35, "phase": "afternoon" },
		"d40_morning": { "day": 40, "phase": "morning" },
		"d43_morning": { "day": 43, "phase": "morning" },
		"d43_afternoon": { "day": 43, "phase": "afternoon" },
		"d45_evening": { "day": 45, "phase": "evening" },
	}

	var res_std := _run_walk_with_checkpoints(tree, data_node, [], standard_checkpoints, output_dir)
	if not res_std:
		return false

	# 2. 產生 D32 邀請分支（阿婕、阿薇、無邀請）
	# D29 邀請阿婕
	var ajie_decisions: Array[Dictionary] = [
		{ "day": 29, "phase": "afternoon", "beat_id": "d29_pm_invitation", "slot_id": "invite_ajie", "group_id": "invitation" }
	]
	var ajie_cp: Dictionary = { "d32_morning__ajie": { "day": 32, "phase": "morning" } }
	if not _run_walk_with_checkpoints(tree, data_node, ajie_decisions, ajie_cp, output_dir):
		return false

	# D29 邀請阿薇
	var awei_decisions: Array[Dictionary] = [
		{ "day": 29, "phase": "afternoon", "beat_id": "d29_pm_invitation", "slot_id": "invite_awei", "group_id": "invitation" }
	]
	var awei_cp: Dictionary = { "d32_morning__awei": { "day": 32, "phase": "morning" } }
	if not _run_walk_with_checkpoints(tree, data_node, awei_decisions, awei_cp, output_dir):
		return false

	# D29 不邀請任何人
	var none_decisions: Array[Dictionary] = [
		{ "day": 29, "phase": "afternoon", "beat_id": "d29_pm_invitation", "slot_id": "invite_none", "group_id": "invitation" }
	]
	var none_cp: Dictionary = { "d32_morning__none": { "day": 32, "phase": "morning" } }
	if not _run_walk_with_checkpoints(tree, data_node, none_decisions, none_cp, output_dir):
		return false

	# 3. 產生 D5 evening 殘響分支（到場陪阿宏 vs 錯過去老街）
	# 到場山泉閣陪阿宏（獲得 ahong_last_normal_contact 旗標，D5 傍晚不播殘響）
	var attend_d3_decisions: Array[Dictionary] = [
		{ "day": 3, "phase": "afternoon", "beat_id": "d3_pm_sanquan", "slot_id": "help_ahong", "card_id": "protagonist" }
	]
	var d5_attend_cp: Dictionary = { "d5_evening__attended": { "day": 5, "phase": "evening" } }
	if not _run_walk_with_checkpoints(tree, data_node, attend_d3_decisions, d5_attend_cp, output_dir):
		return false

	# 錯過山泉閣去老街（無 ahong_last_normal_contact 旗標，D5 傍晚播出殘響）
	var miss_d3_decisions: Array[Dictionary] = [
		{ "day": 3, "phase": "afternoon", "beat_id": "d3_pm_oldstreet", "slot_id": "wander", "card_id": "protagonist" }
	]
	var d5_miss_cp: Dictionary = { "d5_evening__miss_sanquan": { "day": 5, "phase": "evening" } }
	if not _run_walk_with_checkpoints(tree, data_node, miss_d3_decisions, d5_miss_cp, output_dir):
		return false

	# 4. 產生 D22 拍立得分支（持有拍立得 vs 未持有）
	# D3 下午選處理吵架夫妻（獲得 equip_polaroid）
	var polaroid_decisions: Array[Dictionary] = [
		{ "day": 3, "phase": "afternoon", "beat_id": "d3_pm_sanquan", "slot_id": "handle_couple", "card_id": "protagonist" }
	]
	var d22_polaroid_cp: Dictionary = { "d22_afternoon__with_polaroid": { "day": 22, "phase": "afternoon" } }
	if not _run_walk_with_checkpoints(tree, data_node, polaroid_decisions, d22_polaroid_cp, output_dir):
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
					var post_ok := _verify_checkpoint_postcondition(cp_name, snapshot)
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
					for dec in custom_decisions:
						if int(dec.get("day", -1)) == d and str(dec.get("phase", "")) == phase:
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
							break
					if not overridden:
						PlaythroughGreedy.execute_action_phase(gs, data_node, d, phase)
					gs.advance_phase()
				"evening":
					PlaythroughGreedy.execute_evening_phase(gs, data_node, d)
					gs.advance_phase()
				"night":
					PlaythroughGreedy.execute_night_phase(gs, data_node, d)
					gs.advance_phase()

	return true


static func _verify_checkpoint_postcondition(cp_name: String, snapshot: Dictionary) -> bool:
	var run: Dictionary = snapshot.get("run", {}) as Dictionary
	var flags: Dictionary = run.get("flags", {}) as Dictionary
	var choices: Dictionary = run.get("choices", {}) as Dictionary

	match cp_name:
		"d32_morning__ajie":
			return flags.get("invited_ajie", false) == true and not bool(run.get("action_spent", false))
		"d32_morning__awei":
			return flags.get("invited_awei", false) == true and not bool(run.get("action_spent", false))
		"d32_morning__none":
			return (choices.get("d29_pm_invitation::invitation", "") == "invite_none" or flags.get("invited_none", false) == true) and not bool(run.get("action_spent", false))
		"d5_evening__attended":
			var flags_map: Dictionary = run.get("flags", {}) as Dictionary
			return flags_map.get("ahong_last_normal_contact", false) == true
		"d5_evening__miss_sanquan":
			var flags_map: Dictionary = run.get("flags", {}) as Dictionary
			return flags_map.get("ahong_last_normal_contact", false) == false
		"d22_afternoon__with_polaroid":
			var hand_arr: Array = run.get("hand", []) as Array
			return hand_arr.has("equip_polaroid")
		"d27_evening__both":
			var flags_map: Dictionary = run.get("flags", {}) as Dictionary
			return flags_map.get("awei_sheltering", false) == true
		"d27_evening__partial":
			var flags_map: Dictionary = run.get("flags", {}) as Dictionary
			return flags_map.get("awei_sheltering", false) == true
		_:
			return true


static func _reset_state(gs: Node) -> void:
	gs.deserialize({
		"meta": {
			"knowledge": {}
		},
		"run": {
			"day": 1,
			"phase": "morning",
			"hand": ["protagonist"],
			"madness_clock": {},
			"_madness_counter": 0,
			"beats_entered": {},
			"slots_placed": {},
			"choices": {},
			"flags": {},
			"switches": {},
			"switch_progress": {},
			"relations": {},
			"action_spent": false,
			"npc_action_counts": {}
		}
	})

