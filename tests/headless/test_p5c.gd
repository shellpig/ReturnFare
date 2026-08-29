extends SceneTree

## P5-C 四類結局與組合後日談測試（實作規格書 P5-C、測試指南 P5-C）。
## 涵蓋：正常結局三組 variant 求值與優先序、關係獨立性、
## uninvited_proxy 查表與防篡改、首見長版 vs 重見短版分支、
## 兩種 BE 的後日談隔離與獨立首見計算、不上車外地人生快照、
## 逐頁 ready_to_complete 門檻與動作原子性、48 組全排列結構版文字走查。
## 跑法：Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/test_p5c.gd

const PlaythroughGreedy := preload("res://tests/headless/playthrough_greedy.gd")

var _failed := 0


func _initialize() -> void:
	var data_node: Node = PlaythroughGreedy.setup_data(self)
	var gs: Node = PlaythroughGreedy.setup_game_state(self, data_node)
	await process_frame

	if not bool(data_node.get("ok")):
		push_error("P5-C: Data 載入失敗，中止")
		quit(1)
		return

	print("=== P5-C 四類結局與組合後日談測試 ===")
	_test_1_partner_variants(gs, data_node)
	_test_2_livelihood_variants(gs, data_node)
	_test_3_inn_appearance_variants(gs, data_node)
	_test_4_uninvited_proxy_lookup(gs, data_node)
	_test_5_first_seen_vs_repeat(gs, data_node)
	_test_6_be_endings_independence(gs, data_node)
	_test_7_refuse_boarding_ending(gs, data_node)
	_test_8_lifecycle_ready_to_complete_and_atomicity(gs, data_node)
	_test_9_structural_text_walkthrough(gs, data_node)

	if _failed > 0:
		push_error("test_p5c: %d 個斷言失敗" % _failed)
		quit(1)
	else:
		print("\n=== P5-C 全部測試通過 ===")
		quit(0)


# ── 共用工具 ─────────────────────────────────────────────────────────────────

func _ok(msg: String) -> void:
	print("  ok  " + msg)


func _fail(msg: String) -> void:
	push_error("  FAIL  " + msg)
	_failed += 1


func _check(cond: bool, msg: String) -> void:
	if cond:
		_ok(msg)
	else:
		_fail(msg)


func _state_text(gs: Node) -> String:
	return JSON.stringify(gs.call("serialize"))


func _fresh_run(gs: Node, day: int = 45, phase: String = "evening") -> void:
	gs.call("end_run", "test_reset")
	gs.set("day", day)
	gs.set("phase", phase)
	gs.set("ending_history", [] as Array[Dictionary])
	gs.set("run_number", 1)
	(gs.get("knowledge") as Dictionary).clear()
	(gs.get("knowledge_at_start") as Dictionary).clear()
	(gs.get("night_locations_seen") as Dictionary).clear()
	(gs.get("flags") as Dictionary).clear()
	(gs.get("relations") as Dictionary).clear()
	(gs.get("npc_action_counts") as Dictionary).clear()
	gs.set("selected_festival_proxy_npc", "")
	gs.set("opening_choice_id", "")


func _force_opening_mode(gs: Node) -> void:
	var state: Dictionary = gs.call("serialize")
	(state["flow"] as Dictionary)["mode"] = "opening"
	var res: Dictionary = gs.call("deserialize", state)
	if not bool(res.get("ok", false)):
		_fail("_force_opening_mode: deserialize 失敗")


func _refs_contain(refs: Array, needle: String) -> bool:
	for r: Variant in refs:
		if needle in str(r):
			return true
	return false


# ── 1. 伴侶 variants 涵蓋與關係獨立性 ─────────────────────────────────────────

func _test_1_partner_variants(gs: Node, data_node: Node) -> void:
	print("\n--- 1. 伴侶 variants 覆蓋與關係獨立性 ---")
	var loader: DataLoader = data_node.get("loader") as DataLoader

	# (a) invited_ajie -> partner_variant: "ajie"
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["invited_ajie"] = true
	var res_ajie := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(bool(res_ajie.get("ok", false)), "邀阿婕 resolve 成功")
	_check(str((res_ajie.get("variants") as Dictionary).get("partner_variant", "")) == "ajie", "伴侶為 ajie")
	var refs_ajie: Array = res_ajie.get("page_refs", []) as Array
	_check(_refs_contain(refs_ajie, "partner_ajie_long"), "包含 partner_ajie_long 頁面")
	_check(not _refs_contain(refs_ajie, "partner_awei_long") and not _refs_contain(refs_ajie, "partner_none_long"), "不包含其他伴侶頁面")

	# (b) invited_awei -> partner_variant: "awei"
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "awei")
	(gs.get("flags") as Dictionary)["invited_awei"] = true
	var res_awei := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(bool(res_awei.get("ok", false)), "邀阿薇 resolve 成功")
	_check(str((res_awei.get("variants") as Dictionary).get("partner_variant", "")) == "awei", "伴侶為 awei")
	var refs_awei: Array = res_awei.get("page_refs", []) as Array
	_check(_refs_contain(refs_awei, "partner_awei_long"), "包含 partner_awei_long 頁面")
	_check(not _refs_contain(refs_awei, "partner_ajie_long") and not _refs_contain(refs_awei, "partner_none_long"), "不包含其他伴侶頁面")

	# (c) 無邀請 (invited_none 或未邀) -> fallback partner_variant: "none"
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "acai")
	(gs.get("flags") as Dictionary)["invited_none"] = true
	var res_none := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(bool(res_none.get("ok", false)), "無邀請 resolve 成功")
	_check(str((res_none.get("variants") as Dictionary).get("partner_variant", "")) == "none", "伴侶為 fallback none")
	var refs_none: Array = res_none.get("page_refs", []) as Array
	_check(_refs_contain(refs_none, "partner_none_long"), "包含 partner_none_long 頁面")

	# (d) 關係完成度獨立性：只改 relations 不改 flags，伴侶仍為 none
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "acai")
	(gs.get("relations") as Dictionary)["ajie"] = 100
	(gs.get("relations") as Dictionary)["awei"] = 100
	var res_rel := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(bool(res_rel.get("ok", false)), "高關係值但無 choice 旗標 resolve 成功")
	_check(str((res_rel.get("variants") as Dictionary).get("partner_variant", "")) == "none",
		"只改 relation 不改 D29 choice 時伴侶仍為 none（resolver 不偷看關係度）")


# ── 2. 生計 variants 涵蓋與優先序 ─────────────────────────────────────────────

func _test_2_livelihood_variants(gs: Node, data_node: Node) -> void:
	print("\n--- 2. 生計 variants 覆蓋、優先序與合成防禦 ---")
	var loader: DataLoader = data_node.get("loader") as DataLoader

	# (a) accepted_inn -> livelihood_variant: "uncle"
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["accepted_inn"] = true
	var res_uncle := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(str((res_uncle.get("variants") as Dictionary).get("livelihood_variant", "")) == "uncle", "生計為 uncle")
	_check(_refs_contain(res_uncle.get("page_refs", []) as Array, "livelihood_uncle_long"), "包含 livelihood_uncle_long 頁面")

	# (b) accepted_outside_job -> livelihood_variant: "boss"
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["accepted_outside_job"] = true
	var res_boss := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(str((res_boss.get("variants") as Dictionary).get("livelihood_variant", "")) == "boss", "生計為 boss")
	_check(_refs_contain(res_boss.get("page_refs", []) as Array, "livelihood_boss_long"), "包含 livelihood_boss_long 頁面")

	# (c) accepted_job -> livelihood_variant: "zhou"
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["accepted_job"] = true
	var res_zhou := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(str((res_zhou.get("variants") as Dictionary).get("livelihood_variant", "")) == "zhou", "生計為 zhou")
	_check(_refs_contain(res_zhou.get("page_refs", []) as Array, "livelihood_zhou_long"), "包含 livelihood_zhou_long 頁面")

	# (d) 皆無 -> fallback livelihood_variant: "none"
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	var res_none := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(str((res_none.get("variants") as Dictionary).get("livelihood_variant", "")) == "none", "生計為 fallback none")
	_check(_refs_contain(res_none.get("page_refs", []) as Array, "livelihood_none_long"), "包含 livelihood_none_long 頁面")

	# (e) 優先序：同時令 accepted_inn, accepted_outside_job, accepted_job 為 true -> 依資料順序只取 uncle
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["accepted_inn"] = true
	(gs.get("flags") as Dictionary)["accepted_outside_job"] = true
	(gs.get("flags") as Dictionary)["accepted_job"] = true
	var res_multi := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(str((res_multi.get("variants") as Dictionary).get("livelihood_variant", "")) == "uncle", "三旗標同時成立時依資料順序只取 uncle")
	var refs_multi: Array = res_multi.get("page_refs", []) as Array
	_check(_refs_contain(refs_multi, "livelihood_uncle_long"), "優先取 uncle 頁面")
	_check(not _refs_contain(refs_multi, "livelihood_boss_long") and not _refs_contain(refs_multi, "livelihood_zhou_long"), "不包含 boss 或 zhou 頁面")

	# (f) 合成防禦案例：無 accepted_inn，但同時成立 accepted_outside_job 與 accepted_job -> 依序取 boss
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["accepted_outside_job"] = true
	(gs.get("flags") as Dictionary)["accepted_job"] = true
	var res_dual := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(str((res_dual.get("variants") as Dictionary).get("livelihood_variant", "")) == "boss", "無叔叔但雙 D43 旗標同時成立時只取前老闆 (boss)")
	var refs_dual: Array = res_dual.get("page_refs", []) as Array
	_check(_refs_contain(refs_dual, "livelihood_boss_long"), "只有前老闆入頁")
	_check(not _refs_contain(refs_dual, "livelihood_zhou_long"), "周先生頁面未入頁（不拼裝互斥人生）")


# ── 3. 旅館修繕 variants 涵蓋與排他 ───────────────────────────────────────────

func _test_3_inn_appearance_variants(gs: Node, data_node: Node) -> void:
	print("\n--- 3. 旅館修繕 variants 覆蓋與互斥人生隔離 ---")
	var loader: DataLoader = data_node.get("loader") as DataLoader

	# (a) repaired_sign -> sign
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["repaired_sign"] = true
	var res_sign := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(str((res_sign.get("variants") as Dictionary).get("inn_appearance_variant", "")) == "sign", "旅館外觀為 sign")
	_check(_refs_contain(res_sign.get("page_refs", []) as Array, "inn_sign_long"), "包含 inn_sign_long")

	# (b) repaired_pipes -> pipes
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["repaired_pipes"] = true
	var res_pipes := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(str((res_pipes.get("variants") as Dictionary).get("inn_appearance_variant", "")) == "pipes", "旅館外觀為 pipes")
	_check(_refs_contain(res_pipes.get("page_refs", []) as Array, "inn_pipes_long"), "包含 inn_pipes_long")

	# (c) repaired_windows -> windows
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["repaired_windows"] = true
	var res_win := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(str((res_win.get("variants") as Dictionary).get("inn_appearance_variant", "")) == "windows", "旅館外觀為 windows")
	_check(_refs_contain(res_win.get("page_refs", []) as Array, "inn_windows_long"), "包含 inn_windows_long")

	# (d) 無修繕 -> none
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	var res_none := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(str((res_none.get("variants") as Dictionary).get("inn_appearance_variant", "")) == "none", "旅館外觀為 fallback none")
	_check(_refs_contain(res_none.get("page_refs", []) as Array, "inn_none_long"), "包含 inn_none_long")

	# (e) 多修繕同時成立時按資料順序只取第一項 (sign)
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["repaired_sign"] = true
	(gs.get("flags") as Dictionary)["repaired_pipes"] = true
	(gs.get("flags") as Dictionary)["repaired_windows"] = true
	var res_multi := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(str((res_multi.get("variants") as Dictionary).get("inn_appearance_variant", "")) == "sign", "多修繕旗標同時成立時依序取 sign")
	var refs_multi: Array = res_multi.get("page_refs", []) as Array
	_check(_refs_contain(refs_multi, "inn_sign_long"), "只有 sign 頁面入頁")
	_check(not _refs_contain(refs_multi, "inn_pipes_long") and not _refs_contain(refs_multi, "inn_windows_long"), "互斥修繕不拼在一起")

	# (f) 負向防禦：無 fallback 且 when 不成立的壞 group fixture -> data_conflict
	var bad_loader := DataLoader.new()
	bad_loader.endings_by_id = loader.endings_by_id.duplicate(true)
	var bad_ending: Dictionary = (bad_loader.endings_by_id["ending_replaced"] as Dictionary).duplicate(true)
	var bad_groups: Array = (bad_ending["variant_groups"] as Array).duplicate(true)
	var bad_inn: Dictionary = (bad_groups[2] as Dictionary).duplicate(true)
	var bad_rules: Array = [
		{ "id": "only_sign", "when": { "flag": "repaired_sign" }, "first_seen_pages": [{ "id": "s", "text": "sign" }] }
	]
	bad_inn["rules"] = bad_rules
	bad_groups[2] = bad_inn
	bad_ending["variant_groups"] = bad_groups
	bad_loader.endings_by_id["ending_replaced"] = bad_ending

	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	var bad_res := EndingResolver.resolve("ending_replaced", gs, bad_loader)
	_check(not bool(bad_res.get("ok", false)) and str(bad_res.get("reason_code", "")) == "data_conflict",
		"無 fallback 且 when 不成立時回 data_conflict")


# ── 4. uninvited_proxy 查表與防篡改 ──────────────────────────────────────────

func _test_4_uninvited_proxy_lookup(gs: Node, data_node: Node) -> void:
	print("\n--- 4. uninvited_proxy 查表與後續動作計數防篡改 ---")
	var loader: DataLoader = data_node.get("loader") as DataLoader

	# (a) partner: none + proxy: acai -> proxy_acai_long
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "acai")
	var res_acai := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(bool(res_acai.get("ok", false)), "proxy acai resolve 成功")
	var refs_acai: Array = res_acai.get("page_refs", []) as Array
	_check(_refs_contain(refs_acai, "proxy_acai_long"), "包含 proxy_acai_long 頁面")

	# (b) partner: none + proxy: ajie -> proxy_ajie_long
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	var res_ajie := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(_refs_contain(res_ajie.get("page_refs", []) as Array, "proxy_ajie_long"), "包含 proxy_ajie_long 頁面")

	# (c) partner: none + proxy: awei -> proxy_awei_long
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "awei")
	var res_awei := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(_refs_contain(res_awei.get("page_refs", []) as Array, "proxy_awei_long"), "包含 proxy_awei_long 頁面")

	# (d) D29 凍結後改動 npc_action_counts：結局 festival_proxy_npc 仍為凍結 id
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "acai")
	(gs.get("npc_action_counts") as Dictionary)["ajie"] = 999
	(gs.get("npc_action_counts") as Dictionary)["awei"] = 888
	var res_tamper := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(_refs_contain(res_tamper.get("page_refs", []) as Array, "proxy_acai_long"),
		"改動 npc_action_counts 後結局仍讀凍結的 acai 片段（不重算投入）")
	_check(not _refs_contain(res_tamper.get("page_refs", []) as Array, "proxy_ajie_long"), "未受竄改的 ajie 影響")

	# (e) 邀阿婕／阿薇時，uninvited_proxy fragment 不啟用
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "acai")
	(gs.get("flags") as Dictionary)["invited_ajie"] = true
	var res_invited := EndingResolver.resolve("ending_replaced", gs, loader)
	var refs_inv: Array = res_invited.get("page_refs", []) as Array
	_check(_refs_contain(refs_inv, "partner_ajie_long"), "邀阿婕時有 partner_ajie_long")
	_check(not _refs_contain(refs_inv, "proxy_acai_long") and not _refs_contain(refs_inv, "proxy_ajie_long"),
		"邀阿婕時 uninvited_proxy 查表片段不啟用")


# ── 5. 首見長版 vs 重見短版分支 ───────────────────────────────────────────────

func _test_5_first_seen_vs_repeat(gs: Node, data_node: Node) -> void:
	print("\n--- 5. 首見長版 vs 重見短版分支 ---")
	var loader: DataLoader = data_node.get("loader") as DataLoader

	# (a) history 為空但 run_number > 1 (如第 5 輪) -> 首見長版
	_fresh_run(gs)
	gs.set("run_number", 5)
	gs.set("selected_festival_proxy_npc", "ajie")
	var res_first := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(str(res_first.get("branch", "")) == "first_seen", "history 為空但 run_number > 1 時仍為 first_seen")
	var refs_first: Array = res_first.get("page_refs", []) as Array
	_check(_refs_contain(refs_first, "replacement") and _refs_contain(refs_first, "long_return"), "首見包含長版 prefix/suffix")
	_check(not _refs_contain(refs_first, "again_replaced") and not _refs_contain(refs_first, "short_return"), "首見不包含短版 prefix/suffix")

	# (b) history 只有 BE 結局 -> 首見長版
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("ending_history") as Array[Dictionary]).append({ "ending_id": "ending_madness_be", "run_number": 1 })
	(gs.get("ending_history") as Array[Dictionary]).append({ "ending_id": "ending_inventory_be", "run_number": 2 })
	var res_be_hist := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(str(res_be_hist.get("branch", "")) == "first_seen", "只有 BE history 時正常結局仍為 first_seen")

	# (c) history 已有 ending_replaced -> 重見短版
	_fresh_run(gs)
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("flags") as Dictionary)["invited_ajie"] = true
	(gs.get("flags") as Dictionary)["accepted_inn"] = true
	(gs.get("flags") as Dictionary)["repaired_sign"] = true
	(gs.get("ending_history") as Array[Dictionary]).append({ "ending_id": "ending_replaced", "run_number": 1 })
	var res_repeat := EndingResolver.resolve("ending_replaced", gs, loader)
	_check(str(res_repeat.get("branch", "")) == "repeat", "history 已有 ending_replaced 時為 repeat")
	var refs_rep: Array = res_repeat.get("page_refs", []) as Array
	_check(_refs_contain(refs_rep, "again_replaced") and _refs_contain(refs_rep, "short_return"), "重見包含短版 prefix/suffix")
	_check(_refs_contain(refs_rep, "partner_ajie_short"), "重見包含 partner_ajie_short")
	_check(_refs_contain(refs_rep, "livelihood_uncle_short"), "重見包含 livelihood_uncle_short")
	_check(_refs_contain(refs_rep, "inn_sign_short"), "重見包含 inn_sign_short")
	_check(EndingResolver.skip_target("ending_replaced", loader) == "short_return", "正常結局 skip_to 指向 short_return")


# ── 6. 兩種 BE 結局獨立性 ────────────────────────────────────────────────────

func _test_6_be_endings_independence(gs: Node, data_node: Node) -> void:
	print("\n--- 6. 兩種 BE 結局隔離與獨立首見計算 ---")
	var loader: DataLoader = data_node.get("loader") as DataLoader

	# (a) ending_madness_be
	_fresh_run(gs, 20, "morning")
	var res_mad_first := EndingResolver.resolve("ending_madness_be", gs, loader)
	_check(bool(res_mad_first.get("ok", false)), "madness BE 首見 resolve 成功")
	var refs_mad_first: Array = res_mad_first.get("page_refs", []) as Array
	_check(refs_mad_first.size() == 1 and str(refs_mad_first[0]).ends_with("/madness_lost"), "madness BE 首見恰 1 頁 (madness_lost)")
	_check(not _refs_contain(refs_mad_first, "replacement") and not _refs_contain(refs_mad_first, "partner_"), "madness BE 不含替換後日談 refs")

	# (b) ending_inventory_be
	_fresh_run(gs, 20, "morning")
	var res_inv_first := EndingResolver.resolve("ending_inventory_be", gs, loader)
	_check(bool(res_inv_first.get("ok", false)), "inventory BE 首見 resolve 成功")
	var refs_inv_first: Array = res_inv_first.get("page_refs", []) as Array
	_check(refs_inv_first.size() == 1 and str(refs_inv_first[0]).ends_with("/inventory_confined"), "inventory BE 首見恰 1 頁 (inventory_confined)")
	_check(not _refs_contain(refs_inv_first, "replacement") and not _refs_contain(refs_inv_first, "partner_"), "inventory BE 不含替換後日談 refs")

	# (c) 獨立首見／重見計算
	_fresh_run(gs)
	(gs.get("ending_history") as Array[Dictionary]).append({ "ending_id": "ending_madness_be", "run_number": 1 })
	_check(bool(gs.call("has_seen_ending", "ending_madness_be")), "has_seen_ending(madness_be) 為 true")
	_check(not bool(gs.call("has_seen_ending", "ending_inventory_be")), "has_seen_ending(inventory_be) 為 false")

	var res_mad_rep := EndingResolver.resolve("ending_madness_be", gs, loader)
	_check(str(res_mad_rep.get("branch", "")) == "repeat", "madness BE 為 repeat")
	var refs_mad_rep: Array = res_mad_rep.get("page_refs", []) as Array
	_check(refs_mad_rep.size() == 1 and str(refs_mad_rep[0]).ends_with("/madness_summary"), "madness BE 重見為 summary 頁")

	var res_inv_still_first := EndingResolver.resolve("ending_inventory_be", gs, loader)
	_check(str(res_inv_still_first.get("branch", "")) == "first_seen", "inventory BE 仍為 first_seen（狀態彼此獨立）")


# ── 7. 不上車 ending_refuse_boarding ──────────────────────────────────────────

func _test_7_refuse_boarding_ending(gs: Node, data_node: Node) -> void:
	print("\n--- 7. 不上車外地人生與快照規格 ---")
	var loader: DataLoader = data_node.get("loader") as DataLoader

	# (a) opening mode 下啟動 ending_refuse_boarding
	_fresh_run(gs)
	_force_opening_mode(gs)
	var start_res: Dictionary = gs.call("_start_ending_from_opening", "refuse_boarding")
	_check(bool(start_res.get("ok", false)), "_start_ending_from_opening 成功")
	_check(str(gs.get("flow_mode")) == "ending", "啟動後進入 ending mode")

	var snapshot: Dictionary = gs.get("active_ending") as Dictionary
	_check(str(snapshot.get("ending_id", "")) == "ending_refuse_boarding", "快照 ending_id 為 ending_refuse_boarding")
	_check(str(snapshot.get("source_id", "")) == "opening_choice", "快照 source_id 為 opening_choice")
	_check(str(snapshot.get("opening_choice_id", "")) == "refuse_boarding", "快照 opening_choice_id 為 refuse_boarding")
	_check(snapshot.get("ended_day") == null, "不上車快照 ended_day 為 null")
	_check(snapshot.get("ended_phase") == null, "不上車快照 ended_phase 為 null")
	_check(snapshot.get("partner_variant") == null, "不上車快照 partner_variant 為 null")
	_check(snapshot.get("livelihood_variant") == null, "不上車快照 livelihood_variant 為 null")
	_check(snapshot.get("inn_appearance_variant") == null, "不上車快照 inn_appearance_variant 為 null")
	_check(snapshot.get("festival_proxy_npc") == null, "不上車快照 festival_proxy_npc 為 null")
	_check((snapshot.get("knowledge_gained_this_run", []) as Array).is_empty(), "不上車快照 knowledge_gained_this_run 為空陣列")

	# (b) 內容順序涵蓋外地生活、癌症早死與庇佑回歸
	var refs: Array = snapshot.get("page_refs", []) as Array
	_check(refs.size() == 2, "不上車首見恰 2 頁 (page_count=%d)" % refs.size())
	var page0 := EndingResolver.resolve_ref(str(refs[0]), loader)
	var page1 := EndingResolver.resolve_ref(str(refs[1]), loader)
	_check(bool(page0.get("ok", false)) and ("外面的城市" in str(page0.get("text", ""))), "第 1 頁描述外地普通生活")
	_check(bool(page1.get("ok", false)) and ("四十出頭" in str(page1.get("text", ""))) and ("庇佑再次發動" in str(page1.get("text", ""))), "第 2 頁描述四十出頭癌症早死與庇佑回歸")

	# (c) 重見不上車為摘要短篇
	_fresh_run(gs)
	_force_opening_mode(gs)
	(gs.get("ending_history") as Array[Dictionary]).append({ "ending_id": "ending_refuse_boarding", "run_number": 1 })
	var rep_start: Dictionary = gs.call("_start_ending_from_opening", "refuse_boarding")
	_check(bool(rep_start.get("ok", false)), "重見不上車啟動成功")
	var rep_snap: Dictionary = gs.get("active_ending") as Dictionary
	var rep_refs: Array = rep_snap.get("page_refs", []) as Array
	_check(rep_refs.size() == 1, "重見不上車恰 1 頁")
	var rep_p0 := EndingResolver.resolve_ref(str(rep_refs[0]), loader)
	_check(bool(rep_p0.get("ok", false)) and ("不上車" in str(rep_p0.get("text", ""))), "重見不上車播摘要文字")
	_check(EndingResolver.skip_target("ending_refuse_boarding", loader) == "complete", "不上車 skip_to 指向 complete")


# ── 8. 逐頁 ready_to_complete 門檻與動作原子性 ───────────────────────────────

func _test_8_lifecycle_ready_to_complete_and_atomicity(gs: Node, data_node: Node) -> void:
	print("\n--- 8. 逐頁 ready_to_complete 門檻與動作原子性 ---")

	# (a) 四類 ending 在末頁揭露前 ready_to_complete 恆為 false
	var cases := [
		{ "id": "ending_replaced", "source": "d45_coda", "proxy": "ajie" },
		{ "id": "ending_madness_be", "source": "madness_cap", "proxy": "" },
		{ "id": "ending_inventory_be", "source": "ending_effect", "proxy": "" },
	]
	for c in cases:
		_fresh_run(gs, 45, "evening")
		if not str(c["proxy"]).is_empty():
			gs.set("selected_festival_proxy_npc", str(c["proxy"]))
		var sres: Dictionary = gs.call("start_ending", str(c["id"]), str(c["source"]))
		_check(bool(sres.get("ok", false)), "啟動 %s 成功" % str(c["id"]))

		var view: Dictionary = gs.call("ending_view")
		var total_pages := int(view.get("page_count", 0))
		_check(not bool(view.get("can_complete", true)), "%s 初始 can_complete 為 false" % str(c["id"]))

		for i in range(total_pages):
			var rev: Dictionary = gs.call("reveal_ending_page")
			_check(bool(rev.get("ok", false)), "%s 揭露第 %d 頁成功" % [str(c["id"]), i])
			var cur_view: Dictionary = gs.call("ending_view")
			if i < total_pages - 1:
				_check(not bool(cur_view.get("can_complete", true)), "%s 非末頁 (第 %d 頁) can_complete 仍為 false" % [str(c["id"]), i])
				var adv: Dictionary = gs.call("advance_ending_page")
				_check(bool(adv.get("ok", false)), "%s 翻到第 %d 頁成功" % [str(c["id"]), i + 1])
			else:
				_check(bool(cur_view.get("can_complete", false)), "%s 末頁揭露後 can_complete 變為 true" % str(c["id"]))

	# (b) 重見結局 skip_seen_ending 後直接進入 ready
	_fresh_run(gs, 45, "evening")
	gs.set("selected_festival_proxy_npc", "ajie")
	(gs.get("ending_history") as Array[Dictionary]).append({ "ending_id": "ending_replaced", "run_number": 1 })
	gs.call("start_ending", "ending_replaced", "d45_coda")
	var before_skip: Dictionary = gs.call("ending_view")
	_check(bool(before_skip.get("can_skip", false)), "重見結局 can_skip 為 true")
	var skip_res: Dictionary = gs.call("skip_seen_ending")
	_check(bool(skip_res.get("ok", false)), "skip_seen_ending 成功")
	var after_skip: Dictionary = gs.call("ending_view")
	_check(bool(after_skip.get("can_complete", false)), "跳過後直接進入 can_complete")

	# (c) 重複 start_ending 被擋，且不產生第二份快照
	var snap_before := JSON.stringify(gs.get("active_ending"))
	var dup_res: Dictionary = gs.call("start_ending", "ending_replaced", "d45_coda")
	_check(str(dup_res.get("reason_code", "")) == "not_run", "ending mode 重複呼叫 start_ending 回 not_run")
	_check(JSON.stringify(gs.get("active_ending")) == snap_before, "重複呼叫不產生第二份快照，active_ending 零變化")


# ── 9. 全 48 組排列與全結局結構版文字走查 ──────────────────────────────────────

func _test_9_structural_text_walkthrough(gs: Node, data_node: Node) -> void:
	print("\n--- 9. 全 48 組 normal composite 與全結局結構版文字走查 ---")
	var loader: DataLoader = data_node.get("loader") as DataLoader

	var partners := ["invited_ajie", "invited_awei", "invited_none"]
	var livelihoods := ["accepted_inn", "accepted_outside_job", "accepted_job", "none"]
	var inn_repairs := ["repaired_sign", "repaired_pipes", "repaired_windows", "none"]
	var proxy_npcs := ["ajie", "awei", "acai"]

	var total_combos := 0
	for p in partners:
		for l in livelihoods:
			for r in inn_repairs:
				for prx in proxy_npcs:
					total_combos += 1
					_fresh_run(gs)
					gs.set("selected_festival_proxy_npc", prx)
					if p != "invited_none":
						(gs.get("flags") as Dictionary)[p] = true
					if l != "none":
						(gs.get("flags") as Dictionary)[l] = true
					if r != "none":
						(gs.get("flags") as Dictionary)[r] = true

					# 驗證首見 (long)
					var res_long := EndingResolver.resolve("ending_replaced", gs, loader)
					_check_walkthrough_result(res_long, "combo_long_%d" % total_combos, loader)

					# 驗證重見 (short)
					(gs.get("ending_history") as Array[Dictionary]).append({ "ending_id": "ending_replaced", "run_number": 1 })
					var res_short := EndingResolver.resolve("ending_replaced", gs, loader)
					_check_walkthrough_result(res_short, "combo_short_%d" % total_combos, loader)

	_ok("48 組組合（含 3 位 proxy NPC × 首見／重見）共 288 次求值全部無缺頁、無重頁、無空白頁")

	# 走查 linear 結局 (madness, inventory, refuse_boarding)
	for lid in ["ending_madness_be", "ending_inventory_be", "ending_refuse_boarding"]:
		_fresh_run(gs)
		var l_first := EndingResolver.resolve(lid, gs, loader)
		_check_walkthrough_result(l_first, "%s_first" % lid, loader)

		(gs.get("ending_history") as Array[Dictionary]).append({ "ending_id": lid, "run_number": 1 })
		var l_rep := EndingResolver.resolve(lid, gs, loader)
		_check_walkthrough_result(l_rep, "%s_repeat" % lid, loader)

	_ok("三類 linear 結局首見與重見全部走查通過")


func _check_walkthrough_result(res: Dictionary, label: String, loader: DataLoader) -> void:
	if not bool(res.get("ok", false)):
		_fail("%s: resolve 失敗: %s" % [label, str(res.get("reason_code", ""))])
		return
	var refs: Array = res.get("page_refs", []) as Array
	if refs.is_empty():
		_fail("%s: page_refs 為空" % label)
		return

	var seen_pages: Dictionary = {}
	for ref_val: Variant in refs:
		var ref_str := str(ref_val)
		if seen_pages.has(ref_str):
			_fail("%s: 發現重複頁面 ref: %s" % [label, ref_str])
		seen_pages[ref_str] = true

		var page := EndingResolver.resolve_ref(ref_str, loader)
		if not bool(page.get("ok", false)):
			_fail("%s: resolve_ref 失敗: %s" % [label, ref_str])
		var text := str(page.get("text", "")).strip_edges()
		if text.is_empty():
			_fail("%s: 頁面文字為空: %s" % [label, ref_str])
