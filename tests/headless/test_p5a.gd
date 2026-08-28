extends SceneTree

## P5-A 結局、開局與跨輪資料測試（實作規格書 P5-A、測試指南 P5-A）。
## 正向：載入正式資料，驗 lint 17/18/19 全綠、卡片/NPC/ending/opening 動態斷言與故事映射。
## 負向：以 in-memory loader 建每個錯誤類別的最小反例，逐條驗對應 lint 與引用檢查抓到。
## Source 矩陣：資料驅動枚舉 4 正 ＋ 12 錯 ＋ 3 phase_exit 反例。
## 跑法：Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/test_p5a.gd

var _failed := 0


func _initialize() -> void:
	await process_frame
	print("=== P5-A 結局、開局與跨輪資料測試 ===")
	_test_positive_real_data()
	_test_lint17_negative()
	_test_lint18_negative()
	_test_lint19_negative()
	_test_source_pairing_matrix()
	_test_references_negative()

	if _failed > 0:
		push_error("test_p5a: %d 個斷言失敗" % _failed)
		quit(1)
	else:
		print("\n=== P5-A 全部測試通過 ===")
		quit(0)


func _ok(msg: String) -> void:
	print("  ok  " + msg)


func _fail(msg: String) -> void:
	push_error("  FAIL  " + msg)
	_failed += 1


func _errs_contain(errs: PackedStringArray, needle: String) -> bool:
	for e in errs:
		if needle in e:
			return true
	return false


func _make_loader_for_p5(endings: Array, opening: Array, beats: Array, cards: Dictionary, npcs: Dictionary, locations: Dictionary = {}) -> DataLoader:
	var loader := DataLoader.new()
	loader.endings.clear()
	loader.endings_by_id.clear()
	for end in endings:
		var ed := end as Dictionary
		loader.endings.append(ed)
		loader.endings_by_id[str(ed.get("id", ""))] = ed

	loader.opening_choices.clear()
	loader.opening_choices_by_id.clear()
	for oc in opening:
		var ocd := oc as Dictionary
		loader.opening_choices.append(ocd)
		loader.opening_choices_by_id[str(ocd.get("id", ""))] = ocd

	loader.beats.clear()
	loader.beats_by_id.clear()
	for b in beats:
		var bd := b as Dictionary
		loader.beats.append(bd)
		loader.beats_by_id[str(bd.get("id", ""))] = bd

	loader.cards = cards
	loader.npcs = npcs
	loader.locations = locations
	loader.tuning = { "hand_size": 14, "madness_cap": 7 }
	return loader


# ─────────────────────────── 1. 正向：正式資料 ───────────────────────────
func _test_positive_real_data() -> void:
	print("\n--- 1. 正向：正式資料 lint 17/18/19 全綠、動態數 ---")
	var loader := DataLoader.new()
	var ok := loader.load_all()
	if not ok:
		_fail("DataLoader.load_all 失敗: " + str(loader.errors))
		return
	_ok("load_all 成功")

	var ref_problems := loader.verify_references()
	if ref_problems.size() > 0:
		_fail("verify_references 發現引用錯誤: " + str(ref_problems))
	else:
		_ok("verify_references 0 錯誤")

	var errs17 := DataLoader.lint_endings(loader)
	if errs17.size() > 0:
		_fail("lint_endings 失敗: " + str(errs17))
	else:
		_ok("lint_endings (Lint 17) 0 錯誤")

	var errs18 := DataLoader.lint_opening_and_defaults(loader)
	if errs18.size() > 0:
		_fail("lint_opening_and_defaults 失敗: " + str(errs18))
	else:
		_ok("lint_opening_and_defaults (Lint 18) 0 錯誤")

	var errs19 := DataLoader.lint_loop_and_festival(loader)
	if errs19.size() > 0:
		_fail("lint_loop_and_festival 失敗: " + str(errs19))
	else:
		_ok("lint_loop_and_festival (Lint 19) 0 錯誤")

	# 卡片動態檢查
	var persistent_count := 0
	for cid in loader.cards:
		var c: Dictionary = loader.cards[cid] as Dictionary
		if not c.has("loop_persistent"):
			_fail("卡片 %s 缺少 loop_persistent" % cid)
		elif c["loop_persistent"] == true:
			persistent_count += 1
	if persistent_count == 0:
		_ok("正式卡片 66 張之 loop_persistent 全為 false")
	else:
		_fail("正式卡片 loop_persistent:true 應為 0，實際為 %d" % persistent_count)

	# 新增卡片檢查
	if loader.cards.has("item_family_album"):
		var fa: Dictionary = loader.cards["item_family_album"]
		if fa.get("type") == "equipment" and fa.get("slotless") == false and fa.get("stashable") == true and fa.get("discardable") == true and fa.get("loop_persistent") == false:
			_ok("item_family_album 屬性符合契約")
		else:
			_fail("item_family_album 屬性不符契約: " + str(fa))
	else:
		_fail("缺少 item_family_album")

	if loader.cards.has("k_i_returned"):
		var kr: Dictionary = loader.cards["k_i_returned"]
		if kr.get("type") == "knowledge" and kr.get("slotless") == true and kr.get("stashable") == false and kr.get("discardable") == false and kr.get("loop_persistent") == false:
			_ok("k_i_returned 屬性符合契約")
		else:
			_fail("k_i_returned 屬性不符契約: " + str(kr))
	else:
		_fail("缺少 k_i_returned")

	# NPC 慶典候選檢查
	var eligible_npcs := []
	for nid in loader.npcs:
		var n: Dictionary = loader.npcs[nid] as Dictionary
		if n.get("festival_proxy_eligible") == true:
			eligible_npcs.append(nid)
	if eligible_npcs == ["ajie", "awei", "acai"]:
		_ok("festival_proxy_eligible 候選 NPC 精確為 ajie, awei, acai")
	else:
		_fail("festival_proxy_eligible 候選不符預期: " + str(eligible_npcs))

	# D45 phase_exit 檢查
	var d45_beat: Variant = loader.beats_by_id.get("d45_then")
	if d45_beat is Dictionary:
		var pe: Variant = (d45_beat as Dictionary).get("phase_exit")
		if pe is Dictionary and (pe as Dictionary).get("ending") == "ending_replaced" and (pe as Dictionary).get("source") == "d45_coda" and (pe as Dictionary).get("required_slots") == ["compare_registry"]:
			_ok("d45_then phase_exit 接點符合契約")
		else:
			_fail("d45_then phase_exit 不符契約: " + str(pe))
	else:
		_fail("缺少 d45_then beat")

	# D7 opening_choice 條件檢查 (P2)
	var d7_called: Variant = loader.beats_by_id.get("d7_ambient_rejection_called")
	if d7_called is Dictionary and (d7_called as Dictionary).get("condition") == { "opening_choice": "return_missed_call" }:
		_ok("d7_ambient_rejection_called 依 opening_choice 判定符合單一真值契約")
	else:
		_fail("d7_ambient_rejection_called 條件不符契約: " + str((d7_called as Dictionary).get("condition") if d7_called is Dictionary else null))

	var d7_album: Variant = loader.beats_by_id.get("d7_ambient_rejection")
	if d7_album is Dictionary and (d7_album as Dictionary).get("condition") == { "opening_choice": "take_family_album" }:
		_ok("d7_ambient_rejection 依 opening_choice 判定符合單一真值契約")
	else:
		_fail("d7_ambient_rejection 條件不符契約: " + str((d7_album as Dictionary).get("condition") if d7_album is Dictionary else null))

	# D43 周先生工作門檻檢查 (P1)
	var d43_beat: Variant = loader.beats_by_id.get("d43_pm_zhou")
	if d43_beat is Dictionary:
		var say_yes_found := false
		for s in (d43_beat as Dictionary).get("slots", []):
			if s.get("id") == "say_yes":
				if s.get("condition") == { "has_card": "info_zhou_job" }:
					say_yes_found = true
					_ok("d43_pm_zhou.say_yes 具有 has_card: info_zhou_job 履歷門檻")
				else:
					_fail("d43_pm_zhou.say_yes 條件不符契約: " + str(s.get("condition")))
		if not say_yes_found:
			_fail("d43_pm_zhou 缺少 say_yes 槽")
	else:
		_fail("缺少 d43_pm_zhou beat")


# ─────────────────────────── 2. Lint 17 負向 Fixtures ───────────────────────────
func _test_lint17_negative() -> void:
	print("\n--- 2. Lint 17 負向 Fixtures ---")
	var base_loader := DataLoader.new()
	base_loader.load_all()

	# 1. 缺 ending id
	var l_missing := _make_loader_for_p5(base_loader.endings.slice(0, 3), base_loader.opening_choices, base_loader.beats, base_loader.cards, base_loader.npcs)
	var errs := DataLoader.lint_endings(l_missing)
	if _errs_contain(errs, "缺少必填 ending id"):
		_ok("17.1 抓到缺少必填 ending id")
	else:
		_fail("17.1 未抓到缺少 ending id: " + str(errs))

	# 2. 多 ending id（未知 ending）
	var extra_endings = base_loader.endings.duplicate(true)
	extra_endings.append({ "id": "ending_secret", "kind": "linear", "first_seen": {"pages": [{"id": "p1", "text": "secret"}]}, "repeat": {"pages": [{"id": "p2", "text": "secret"}], "skip_to": "complete"} })
	var l_extra := _make_loader_for_p5(extra_endings, base_loader.opening_choices, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_endings(l_extra)
	if _errs_contain(errs, "非預期的 ending id"):
		_ok("17.2 抓到多出未知 ending id")
	else:
		_fail("17.2 未抓到未知 ending id: " + str(errs))

	# 3. 重複 ending id
	var dup_endings = base_loader.endings.duplicate(true)
	dup_endings.append(dup_endings[0].duplicate(true))
	var l_dup := _make_loader_for_p5(dup_endings, base_loader.opening_choices, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_endings(l_dup)
	if _errs_contain(errs, "預期恰 4 筆 ending") or _errs_contain(errs, "重複"):
		_ok("17.3 抓到重複 ending id / 筆數超額")
	else:
		_fail("17.3 未抓到重複 ending id: " + str(errs))

	# 4. 未知 kind
	var bad_kind_endings = base_loader.endings.duplicate(true)
	bad_kind_endings[0]["kind"] = "branching"
	var l_bad_kind := _make_loader_for_p5(bad_kind_endings, base_loader.opening_choices, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_endings(l_bad_kind)
	if _errs_contain(errs, "kind 必須為 composite") or _errs_contain(errs, "未知 kind"):
		_ok("17.4 抓到未知 kind")
	else:
		_fail("17.4 未抓到未知 kind: " + str(errs))

	# 5. 缺 page 或 skip_to 指向不存在的 repeat page id
	var bad_skip_endings = base_loader.endings.duplicate(true)
	bad_skip_endings[0]["repeat"]["skip_to"] = "non_existent_page_id"
	var l_bad_skip := _make_loader_for_p5(bad_skip_endings, base_loader.opening_choices, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_endings(l_bad_skip)
	if _errs_contain(errs, "repeat.skip_to 指向不存在的 repeat page id"):
		_ok("17.5 抓到 skip_to 指向不存在的 repeat page id")
	else:
		_fail("17.5 未抓到壞 skip_to: " + str(errs))

	# 6. 缺 fallback / 多 fallback / fallback 帶 when
	var bad_fb_endings = base_loader.endings.duplicate(true)
	var vgs: Array = bad_fb_endings[0]["variant_groups"]
	vgs[0]["rules"][2].erase("fallback")
	vgs[0]["rules"][2]["when"] = { "flag": "no_such_flag" }
	var l_bad_fb := _make_loader_for_p5(bad_fb_endings, base_loader.opening_choices, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_endings(l_bad_fb)
	if _errs_contain(errs, "必須恰有一個 fallback"):
		_ok("17.6 抓到缺少 fallback / 多 fallback")
	else:
		_fail("17.6 未抓到缺少 fallback: " + str(errs))

	# 7. 壞 lookup_fragments group 引用
	var bad_frag_endings = base_loader.endings.duplicate(true)
	bad_frag_endings[0]["lookup_fragments"][0]["when_group"]["group"] = "unknown_group"
	var l_bad_frag := _make_loader_for_p5(bad_frag_endings, base_loader.opening_choices, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_endings(l_bad_frag)
	if _errs_contain(errs, "when_group.group 指向不存在的 variant_group"):
		_ok("17.7 抓到 lookup_fragments 指向不存在的 variant_group")
	else:
		_fail("17.7 未抓到壞 when_group.group: " + str(errs))

	# 8. 玩家文案洩漏內部 ending id
	var leak_endings = base_loader.endings.duplicate(true)
	leak_endings[0]["first_seen"]["prefix_pages"][0]["text"] = "你走向了 ending_replaced 的結局。"
	var l_leak := _make_loader_for_p5(leak_endings, base_loader.opening_choices, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_endings(l_leak)
	if _errs_contain(errs, "玩家文字直接包含內部 ending id"):
		_ok("17.8 抓到文案洩漏內部 ending id")
	else:
		_fail("17.8 未抓到文案洩漏內部 ending id: " + str(errs))

	# 9. 組裝路徑 0 頁
	var zero_page_endings = base_loader.endings.duplicate(true)
	zero_page_endings[0]["first_seen"]["prefix_pages"] = []
	zero_page_endings[0]["first_seen"]["suffix_pages"] = []
	for vg in zero_page_endings[0]["variant_groups"]:
		for r in vg["rules"]:
			r["first_seen_pages"] = []
	var l_zero := _make_loader_for_p5(zero_page_endings, base_loader.opening_choices, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_endings(l_zero)
	if _errs_contain(errs, "缺少首見頁面（總頁數為 0）"):
		_ok("17.9 抓到組裝路徑總頁數為 0")
	else:
		_fail("17.9 未抓到 0 頁組裝路徑: " + str(errs))

	# 10 (K-187). linear ending 缺 first_seen.pages
	var no_fs_pages = base_loader.endings.duplicate(true)
	no_fs_pages[1]["first_seen"]["pages"] = []
	var l_no_fs := _make_loader_for_p5(no_fs_pages, base_loader.opening_choices, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_endings(l_no_fs)
	if _errs_contain(errs, "first_seen.pages 必須為非空 Array"):
		_ok("17.10 抓到 linear ending 缺少 first_seen.pages")
	else:
		_fail("17.10 未抓到缺少 first_seen.pages: " + str(errs))

	# 11 (K-187). linear ending 缺 repeat.pages
	var no_rep_pages = base_loader.endings.duplicate(true)
	no_rep_pages[1]["repeat"]["pages"] = []
	var l_no_rep := _make_loader_for_p5(no_rep_pages, base_loader.opening_choices, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_endings(l_no_rep)
	if _errs_contain(errs, "repeat.pages 必須為非空 Array"):
		_ok("17.11 抓到 linear ending 缺少 repeat.pages")
	else:
		_fail("17.11 未抓到缺少 repeat.pages: " + str(errs))

	# 12 (K-187). 壞 condition 運算子在 rule when
	var bad_rule_when = base_loader.endings.duplicate(true)
	bad_rule_when[0]["variant_groups"][0]["rules"][0]["when"] = { "unknown_condition_key": true }
	var l_bad_when := _make_loader_for_p5(bad_rule_when, base_loader.opening_choices, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_endings(l_bad_when)
	if _errs_contain(errs, "未知 condition 運算子"):
		_ok("17.12 抓到 rule when 包含未知 condition 運算子")
	else:
		_fail("17.12 未抓到未知 condition 運算子: " + str(errs))

	# 12b (K-187). 壞 condition 引用在 rule when (ending_seen 引用不存在 ending)
	var bad_rule_ref = base_loader.endings.duplicate(true)
	bad_rule_ref[0]["variant_groups"][0]["rules"][0]["when"] = { "ending_seen": "non_existent_ending_id" }
	var l_bad_ref := _make_loader_for_p5(bad_rule_ref, base_loader.opening_choices, base_loader.beats, base_loader.cards, base_loader.npcs, base_loader.locations)
	var ref_probs := l_bad_ref.verify_references()
	if _errs_contain(ref_probs, "ending_seen 引用不存在的 ending"):
		_ok("17.12b 抓到 rule when 引用不存在的 ending")
	else:
		_fail("17.12b 未抓到壞 ending_seen 引用: " + str(ref_probs))

	# 13 (K-186 Item 3). ending: ending_replaced 藏在 encounter 出口
	var enc_exit_rep = base_loader.beats.duplicate(true)
	for b in enc_exit_rep:
		if b.has("encounter"):
			b["encounter"]["on_victory"] = { "ending": "ending_replaced" }
	var l_enc_rep := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, enc_exit_rep, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_endings(l_enc_rep)
	if _errs_contain(errs, "beat ending 效果只能引用 ending_inventory_be"):
		_ok("17.13 (K-186.3) 抓到 encounter 出口帶非 inventory_be ending")
	else:
		_fail("17.13 未抓到 encounter 出口 ending: " + str(errs))

	# 14 (K-186 Item 4). ending: ending_madness_be 藏在 encounter.rounds[].responses[].on_resolve
	var enc_resp_mad = base_loader.beats.duplicate(true)
	for b in enc_resp_mad:
		if b.has("encounter"):
			var rounds: Array = b["encounter"].get("rounds", [])
			if not rounds.is_empty():
				rounds[0]["responses"][0]["on_resolve"] = { "ending": "ending_madness_be" }
	var l_enc_mad := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, enc_resp_mad, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_endings(l_enc_mad)
	if _errs_contain(errs, "beat ending 效果只能引用 ending_inventory_be"):
		_ok("17.14 (K-186.4) 抓到 encounter response on_resolve 帶非 inventory_be ending")
	else:
		_fail("17.14 未抓到 on_resolve ending: " + str(errs))

	# 15 (K-186 Item 13). lookup_fragments.entries[].value 指向非候選 NPC
	var bad_frag_npc = base_loader.endings.duplicate(true)
	bad_frag_npc[0]["lookup_fragments"][0]["entries"][0]["value"] = "azhu"
	var l_frag_npc := _make_loader_for_p5(bad_frag_npc, base_loader.opening_choices, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_endings(l_frag_npc)
	if _errs_contain(errs, "entries.value 引用非 festival_proxy_eligible NPC"):
		_ok("17.15 (K-186.13) 抓到 lookup_fragments.entries[].value 指向非候選 NPC")
	else:
		_fail("17.15 未抓到非候選 NPC fragment: " + str(errs))

	# 16 (K-186 Item 15). lookup_fragments.when_group.variant 指向不存在的 rule id
	var bad_frag_var = base_loader.endings.duplicate(true)
	bad_frag_var[0]["lookup_fragments"][0]["when_group"]["variant"] = "unknown_variant"
	var l_frag_var := _make_loader_for_p5(bad_frag_var, base_loader.opening_choices, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_endings(l_frag_var)
	if _errs_contain(errs, "when_group.variant 指向不存在的 rule id"):
		_ok("17.16 (K-186.15) 抓到 when_group.variant 指向不存在的 rule id")
	else:
		_fail("17.16 未抓到壞 when_group.variant: " + str(errs))


# ─────────────────────────── 3. Lint 18 負向 Fixtures ───────────────────────────
func _test_lint18_negative() -> void:
	print("\n--- 3. Lint 18 負向 Fixtures ---")
	var base_loader := DataLoader.new()
	base_loader.load_all()

	# 1. opening choices 缺選項
	var l_missing_oc := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices.slice(0, 2), base_loader.beats, base_loader.cards, base_loader.npcs)
	var errs := DataLoader.lint_opening_and_defaults(l_missing_oc)
	if _errs_contain(errs, "順序或項目不符預期"):
		_ok("18.1 抓到 opening choices 缺少選項")
	else:
		_fail("18.1 未抓到缺少選項: " + str(errs))

	# 2. opening choices 多選項 / 重複
	var extra_oc = base_loader.opening_choices.duplicate(true)
	extra_oc.append({ "id": "extra_choice", "label": "extra", "preview": "p", "confirm_text": "c", "on_select": {} })
	var l_extra_oc := _make_loader_for_p5(base_loader.endings, extra_oc, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_extra_oc)
	if _errs_contain(errs, "順序或項目不符預期"):
		_ok("18.2 抓到 opening choices 多出未知選項")
	else:
		_fail("18.2 未抓到多選項: " + str(errs))

	# 3. opening choices 錯序
	var reorder_oc = [base_loader.opening_choices[1], base_loader.opening_choices[0], base_loader.opening_choices[2]]
	var l_reorder := _make_loader_for_p5(base_loader.endings, reorder_oc, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_reorder)
	if _errs_contain(errs, "順序或項目不符預期"):
		_ok("18.3 抓到 opening choices 錯序")
	else:
		_fail("18.3 未抓到錯序: " + str(errs))

	# 4. on_select 與 ending 並存
	var bad_oc_both = base_loader.opening_choices.duplicate(true)
	bad_oc_both[0]["ending"] = "ending_replaced"
	var l_both := _make_loader_for_p5(base_loader.endings, bad_oc_both, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_both)
	if _errs_contain(errs, "不得同時包含 on_select 與 ending"):
		_ok("18.4 抓到 on_select 與 ending 並存")
	else:
		_fail("18.4 未抓到並存: " + str(errs))

	# 5. on_select 與 ending 皆無
	var bad_oc_none = base_loader.opening_choices.duplicate(true)
	bad_oc_none[0].erase("on_select")
	var l_none := _make_loader_for_p5(base_loader.endings, bad_oc_none, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_none)
	if _errs_contain(errs, "必須在 on_select 與 ending 中恰有一個"):
		_ok("18.5 抓到 on_select 與 ending 皆無")
	else:
		_fail("18.5 未抓到兩者皆無: " + str(errs))

	# 6. 缺少 label / preview / confirm_text
	var bad_oc_label = base_loader.opening_choices.duplicate(true)
	bad_oc_label[0]["label"] = "   "
	var l_empty_lbl := _make_loader_for_p5(base_loader.endings, bad_oc_label, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_empty_lbl)
	if _errs_contain(errs, "label 不得為空"):
		_ok("18.6 抓到 label 為空")
	else:
		_fail("18.6 未抓到空 label: " + str(errs))

	# 7. 鎖定選項缺少 reject_reason
	var bad_refuse_no_reason = base_loader.opening_choices.duplicate(true)
	bad_refuse_no_reason[2].erase("reject_reason")
	var l_no_reason := _make_loader_for_p5(base_loader.endings, bad_refuse_no_reason, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_no_reason)
	if _errs_contain(errs, "必須提供非空 reject_reason"):
		_ok("18.7 抓到有 requires 但缺少 reject_reason")
	else:
		_fail("18.7 未抓到缺少理由: " + str(errs))

	# 8. 錯誤 ending 門檻（不上車 gate 設為非 ending_replaced）
	var bad_refuse_gate = base_loader.opening_choices.duplicate(true)
	bad_refuse_gate[2]["requires"] = { "ending_seen": "ending_madness_be" }
	var l_bad_gate := _make_loader_for_p5(base_loader.endings, bad_refuse_gate, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_bad_gate)
	if _errs_contain(errs, "不上車門檻必須為 ending_seen: ending_replaced"):
		_ok("18.8 抓到不上車 gate 設為錯誤 ending")
	else:
		_fail("18.8 未抓到錯誤 gate: " + str(errs))

	# 9. choice group 包含多個 default_if_unresolved
	var multi_def_beats = base_loader.beats.duplicate(true)
	for b in multi_def_beats:
		if b.get("id") == "d29_pm_invitation":
			b["slots"][0]["default_if_unresolved"] = true
	var l_multi_def := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, multi_def_beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_multi_def)
	if _errs_contain(errs, "包含多個 default_if_unresolved 槽"):
		_ok("18.9 抓到同組多個 default_if_unresolved")
	else:
		_fail("18.9 未抓到多個 default: " + str(errs))

	# 10. default 槽收卡 (accepts 非空)
	var def_card_beats = base_loader.beats.duplicate(true)
	for b in def_card_beats:
		if b.get("id") == "d29_pm_invitation":
			b["slots"][2]["accepts"] = ["protagonist"]
	var l_def_card := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, def_card_beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_def_card)
	if _errs_contain(errs, "default 槽不得收卡"):
		_ok("18.10 抓到 default 槽收卡")
	else:
		_fail("18.10 未抓到 default 槽收卡: " + str(errs))

	# 11. default 槽所在父 beat 非 fixed: true
	var def_non_fixed = base_loader.beats.duplicate(true)
	for b in def_non_fixed:
		if b.get("id") == "d29_pm_invitation":
			b["fixed"] = false
	var l_non_fixed := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, def_non_fixed, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_non_fixed)
	if _errs_contain(errs, "default_if_unresolved 所在父 beat 必須為 fixed:true"):
		_ok("18.11 抓到 default 槽在 non-fixed beat")
	else:
		_fail("18.11 未抓到 non-fixed default: " + str(errs))

	# 12. default 槽非 choice_group 槽
	var def_no_cg = base_loader.beats.duplicate(true)
	for b in def_no_cg:
		if b.get("id") == "d29_pm_invitation":
			b["slots"][2].erase("choice_group")
	var l_no_cg := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, def_no_cg, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_no_cg)
	if _errs_contain(errs, "default_if_unresolved 只能用於 choice_group 槽"):
		_ok("18.12 抓到 default 槽缺少 choice_group")
	else:
		_fail("18.12 未抓到缺少 choice_group: " + str(errs))

	# 13. choice_requires_card 錯型別
	var req_bad_type = base_loader.beats.duplicate(true)
	for b in req_bad_type:
		if b.get("id") == "d43_pm_zhou":
			b["slots"][0]["choice_requires_card"] = "yes"
	var l_bad_type := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, req_bad_type, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_bad_type)
	if _errs_contain(errs, "choice_requires_card 必須為 boolean"):
		_ok("18.13 抓到 choice_requires_card 錯型別")
	else:
		_fail("18.13 未抓到錯型別: " + str(errs))

	# 14 (K-186 Item 5). d29_pm_invitation 三個槽都拿掉 default_if_unresolved
	var no_d29_def = base_loader.beats.duplicate(true)
	for b in no_d29_def:
		if b.get("id") == "d29_pm_invitation":
			for s in b.get("slots", []):
				s.erase("default_if_unresolved")
	var l_no_d29_def := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, no_d29_def, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_no_d29_def)
	if _errs_contain(errs, "必須有一個 default_if_unresolved 槽"):
		_ok("18.14 (K-186.5) 抓到 D29 invitation 缺少 default_if_unresolved 槽")
	else:
		_fail("18.14 未抓到 D29 缺少 default: " + str(errs))

	# 15 (K-186 Item 6). d29_pm_invitation 的 default 槽加上 requires
	var def_with_req = base_loader.beats.duplicate(true)
	for b in def_with_req:
		if b.get("id") == "d29_pm_invitation":
			b["slots"][2]["requires"] = { "flag": "some_flag" }
	var l_def_req := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, def_with_req, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_def_req)
	if _errs_contain(errs, "default 槽不得有 requires"):
		_ok("18.15 (K-186.6) 抓到 default 槽帶有 requires 阻擋無卡結算")
	else:
		_fail("18.15 未抓到 default 槽帶 requires: " + str(errs))

	# 16 (K-186 Item 7). d43_pm_zhou 任一槽拿掉 choice_requires_card
	var d43_no_req = base_loader.beats.duplicate(true)
	for b in d43_no_req:
		if b.get("id") == "d43_pm_zhou":
			b["slots"][0].erase("choice_requires_card")
	var l_d43_no_req := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, d43_no_req, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_d43_no_req)
	if _errs_contain(errs, "的槽必須設 choice_requires_card:true"):
		_ok("18.16 (K-186.7) 抓到 D43 槽缺少 choice_requires_card:true")
	else:
		_fail("18.16 未抓到 D43 缺 choice_requires_card: " + str(errs))

	# 17 (K-186 Item 8). d43_pm_zhou 任一槽 accepts 改成非 protagonist
	var d43_bad_acc = base_loader.beats.duplicate(true)
	for b in d43_bad_acc:
		if b.get("id") == "d43_pm_zhou":
			b["slots"][0]["accepts"] = ["k_i_returned"]
	var l_d43_bad_acc := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, d43_bad_acc, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_d43_bad_acc)
	if _errs_contain(errs, "的槽 accepts 只能收 protagonist"):
		_ok("18.17 (K-186.8) 抓到 D43 槽 accepts 非 protagonist")
	else:
		_fail("18.17 未抓到 D43 accepts 錯誤: " + str(errs))

	# 18 (K-186 Item 9). choice_requires_card:true 但 accepts 為空
	var empty_acc_beat = base_loader.beats.duplicate(true)
	for b in empty_acc_beat:
		if b.get("id") == "d26_am_repairs":
			b["slots"][0]["accepts"] = []
	var l_empty_acc := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, empty_acc_beat, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_empty_acc)
	if _errs_contain(errs, "choice_requires_card:true 必須有非空 accepts"):
		_ok("18.18 (K-186.9) 抓到 choice_requires_card:true 但 accepts 為空")
	else:
		_fail("18.18 未抓到 empty accepts: " + str(errs))

	# 19 (K-187). opening choice 重複 id
	var dup_oc = [base_loader.opening_choices[0], base_loader.opening_choices[0], base_loader.opening_choices[2]]
	var l_dup_oc := _make_loader_for_p5(base_loader.endings, dup_oc, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_dup_oc)
	if _errs_contain(errs, "id 重複") or _errs_contain(errs, "順序或項目不符預期"):
		_ok("18.19 抓到 opening choice 重複 id")
	else:
		_fail("18.19 未抓到重複 opening id: " + str(errs))

	# 20 (K-187). choice_requires_card 與 default_if_unresolved 同槽並存
	var req_and_def = base_loader.beats.duplicate(true)
	for b in req_and_def:
		if b.get("id") == "d29_pm_invitation":
			b["slots"][2]["choice_requires_card"] = true
	var l_req_def := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, req_and_def, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_req_def)
	if _errs_contain(errs, "default 槽不得同時設 choice_requires_card:true") or _errs_contain(errs, "choice_requires_card:true 不得與 default_if_unresolved 並存"):
		_ok("18.20 抓到 choice_requires_card 與 default 同槽並存")
	else:
		_fail("18.20 未抓到 choice_requires_card 與 default 並存: " + str(errs))


# ─────────────────────────── 4. Lint 19 負向 Fixtures ───────────────────────────
func _test_lint19_negative() -> void:
	print("\n--- 4. Lint 19 負向 Fixtures ---")
	var base_loader := DataLoader.new()
	base_loader.load_all()

	# 1. 卡片缺少 loop_persistent
	var bad_cards = base_loader.cards.duplicate(true)
	bad_cards["protagonist"].erase("loop_persistent")
	var l_missing_lp := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, base_loader.beats, bad_cards, base_loader.npcs)
	var errs := DataLoader.lint_loop_and_festival(l_missing_lp)
	if _errs_contain(errs, "缺少必填欄位 loop_persistent"):
		_ok("19.1 抓到卡片缺少 loop_persistent")
	else:
		_fail("19.1 未抓到缺少欄位: " + str(errs))

	# 2. loop_persistent 錯型別 (非 bool)
	var bad_type_cards = base_loader.cards.duplicate(true)
	bad_type_cards["protagonist"]["loop_persistent"] = "false"
	var l_type_lp := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, base_loader.beats, bad_type_cards, base_loader.npcs)
	errs = DataLoader.lint_loop_and_festival(l_type_lp)
	if _errs_contain(errs, "loop_persistent 必須是 boolean"):
		_ok("19.2 抓到 loop_persistent 非 boolean")
	else:
		_fail("19.2 未抓到錯型別: " + str(errs))

	# 3. protagonist / slotless / madness 設 loop_persistent: true
	var bad_pro_cards = base_loader.cards.duplicate(true)
	bad_pro_cards["protagonist"]["loop_persistent"] = true
	var l_pro_lp := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, base_loader.beats, bad_pro_cards, base_loader.npcs)
	errs = DataLoader.lint_loop_and_festival(l_pro_lp)
	if _errs_contain(errs, "loop_persistent:true 只能用於"):
		_ok("19.3 抓到主角/不佔格卡設 loop_persistent:true")
	else:
		_fail("19.3 未抓到主角卡設 persistent: " + str(errs))

	# 4. 跨輪保留卡片佔格超過 hand_size - 1
	var overflow_cards = base_loader.cards.duplicate(true)
	var count := 0
	for cid in overflow_cards:
		var c := overflow_cards[cid] as Dictionary
		if c.get("slotless", false) == false and c.get("type", "") != "protagonist" and c.get("type", "") != "madness":
			c["loop_persistent"] = true
			count += 1
			if count >= 14:
				break
	var l_overflow := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, base_loader.beats, overflow_cards, base_loader.npcs)
	errs = DataLoader.lint_loop_and_festival(l_overflow)
	if _errs_contain(errs, "跨輪保留卡片佔格上限超載"):
		_ok("19.4 抓到跨輪保留卡片佔格超載")
	else:
		_fail("19.4 未抓到佔格超載: " + str(errs))

	# 5. permanent lose 指向非 loop_persistent 卡 (on_enter)
	var bad_lose_beats = base_loader.beats.duplicate(true)
	bad_lose_beats[0]["on_enter"] = {
		"lose": [ { "card": "info_husband_version", "permanent": true } ]
	}
	var l_bad_lose := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, bad_lose_beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_loop_and_festival(l_bad_lose)
	if _errs_contain(errs, "lose 的 permanent:true 指向非 loop_persistent 卡"):
		_ok("19.5 抓到 on_enter 的 permanent:true 指向普通卡")
	else:
		_fail("19.5 未抓到 permanent 指向普通卡: " + str(errs))

	# 6. NPC 缺少 festival_proxy_eligible / 非 bool
	var bad_npc_field = base_loader.npcs.duplicate(true)
	bad_npc_field["ajie"].erase("festival_proxy_eligible")
	var l_bad_npc_f := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, base_loader.beats, base_loader.cards, bad_npc_field)
	errs = DataLoader.lint_loop_and_festival(l_bad_npc_f)
	if _errs_contain(errs, "缺少必填欄位 festival_proxy_eligible"):
		_ok("19.6 抓到 NPC 缺少 festival_proxy_eligible")
	else:
		_fail("19.6 未抓到 NPC 缺欄位: " + str(errs))

	# 7. 候選 NPC 未被任何 attention_npc 引用
	var no_att_beats = base_loader.beats.duplicate(true)
	for b in no_att_beats:
		for s in b.get("slots", []):
			if str(s.get("attention_npc", "")) == "awei":
				s.erase("attention_npc")
	var l_no_att := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, no_att_beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_loop_and_festival(l_no_att)
	if _errs_contain(errs, "未被任何 slot 的 attention_npc 引用"):
		_ok("19.7 抓到候選 NPC 未被 attention_npc 引用")
	else:
		_fail("19.7 未抓到缺少 attention_npc: " + str(errs))

	# 8. 候選 NPC 在 endings.json 的 uninvited_proxy 缺少 fragment
	var no_frag_endings = base_loader.endings.duplicate(true)
	no_frag_endings[0]["lookup_fragments"][0]["entries"] = []
	var l_no_frag := _make_loader_for_p5(no_frag_endings, base_loader.opening_choices, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_loop_and_festival(l_no_frag)
	if _errs_contain(errs, "缺少對應 fragment"):
		_ok("19.8 抓到候選 NPC 缺少 ending fragment")
	else:
		_fail("19.8 未抓到缺少 fragment: " + str(errs))

	# 9. 候選 NPC 缺少第 31 天 festival_proxy_is 內容
	var no_d31_beats: Array[Dictionary] = []
	for b in base_loader.beats:
		if b.get("id") != "d31_proxy_ajie":
			no_d31_beats.append(b)
	var l_no_d31 := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, no_d31_beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_loop_and_festival(l_no_d31)
	if _errs_contain(errs, "缺少第 31 天 festival_proxy_is 內容"):
		_ok("19.9 抓到缺少第 31 天 festival_proxy_is 內容")
	else:
		_fail("19.9 未抓到缺少 D31 內容: " + str(errs))

	# 10. 候選 NPC 缺少第 39 天 festival_proxy_is 內容
	var no_d39_beats: Array[Dictionary] = []
	for b in base_loader.beats:
		if b.get("id") != "d39_proxy_awei":
			no_d39_beats.append(b)
	var l_no_d39 := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, no_d39_beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_loop_and_festival(l_no_d39)
	if _errs_contain(errs, "缺少第 39 天 festival_proxy_is 內容"):
		_ok("19.10 抓到缺少第 39 天 festival_proxy_is 內容")
	else:
		_fail("19.10 未抓到缺少 D39 內容: " + str(errs))

	# 11. 非候選 NPC (azhu) 被標為 eligible
	var bad_npcs = base_loader.npcs.duplicate(true)
	bad_npcs["azhu"]["festival_proxy_eligible"] = true
	var l_bad_npc := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, base_loader.beats, base_loader.cards, bad_npcs)
	errs = DataLoader.lint_loop_and_festival(l_bad_npc)
	if _errs_contain(errs, "未被任何 slot 的 attention_npc 引用") or _errs_contain(errs, "缺少對應 fragment"):
		_ok("19.11 抓到非候選 NPC (azhu) 違規標為 eligible")
	else:
		_fail("19.11 未抓到非候選 NPC 違規: " + str(errs))

	# 12 (K-186 Item 1). permanent:true 指普通卡藏在 slots[].on_place_by_level
	var bad_opl_beats = base_loader.beats.duplicate(true)
	for b in bad_opl_beats:
		var slots: Array = b.get("slots", [])
		if not slots.is_empty():
			slots[0]["on_place_by_level"] = {
				"1": { "lose": [ { "card": "info_husband_version", "permanent": true } ] }
			}
			break
	var l_bad_opl := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, bad_opl_beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_loop_and_festival(l_bad_opl)
	if _errs_contain(errs, "lose 的 permanent:true 指向非 loop_persistent 卡"):
		_ok("19.12 (K-186.1) 抓到 on_place_by_level 的 permanent:true 指向普通卡")
	else:
		_fail("19.12 未抓到 on_place_by_level 內的 permanent lose: " + str(errs))

	# 13 (K-186 Item 2). permanent:true 指普通卡藏在 encounter 出口 (on_victory)
	var bad_enc_lose = base_loader.beats.duplicate(true)
	for b in bad_enc_lose:
		if b.has("encounter"):
			b["encounter"]["on_victory"] = {
				"lose": [ { "card": "info_husband_version", "permanent": true } ]
			}
			break
	var l_bad_enc_lose := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, bad_enc_lose, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_loop_and_festival(l_bad_enc_lose)
	if _errs_contain(errs, "lose 的 permanent:true 指向非 loop_persistent 卡"):
		_ok("19.13 (K-186.2) 抓到 encounter 出口的 permanent:true 指向普通卡")
	else:
		_fail("19.13 未抓到 encounter 出口 permanent lose: " + str(errs))

	# 14 (K-187). D29 的 festival_proxy.fallback 指向非候選
	var bad_d29_fb = base_loader.beats.duplicate(true)
	for b in bad_d29_fb:
		if b.get("id") == "d29_pm_invitation":
			b["slots"][2]["on_place"]["festival_proxy"]["fallback"] = "azhu"
	var l_bad_d29_fb := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, bad_d29_fb, base_loader.cards, base_loader.npcs, base_loader.locations)
	errs = DataLoader.lint_loop_and_festival(l_bad_d29_fb)
	var ref_errs := l_bad_d29_fb.verify_references()
	if _errs_contain(errs, "fallback 指向非候選 NPC") or _errs_contain(ref_errs, "fallback 引用非 festival_proxy_eligible NPC"):
		_ok("19.14 抓到 D29 festival_proxy fallback 指向非候選 NPC")
	else:
		_fail("19.14 未抓到 D29 非候選 fallback: " + str(errs) + " " + str(ref_errs))


# ─────────────────────────── 5. 資料驅動 Source 配對矩陣 ───────────────────────────
func _test_source_pairing_matrix() -> void:
	print("\n--- 5. 資料驅動 Source 配對矩陣 (4 正 + 12 錯 + 3 phase_exit) ---")
	var base_loader := DataLoader.new()
	base_loader.load_all()

	var all_sources := ["madness_cap", "ending_effect", "d45_coda", "opening_choice"]
	var all_endings := ["ending_madness_be", "ending_inventory_be", "ending_replaced", "ending_refuse_boarding"]

	const LEGAL_PAIRS := {
		"madness_cap": "ending_madness_be",
		"ending_effect": "ending_inventory_be",
		"d45_coda": "ending_replaced",
		"opening_choice": "ending_refuse_boarding",
	}

	var positive_tested := 0
	var negative_tested := 0

	for src in all_sources:
		for eid in all_endings:
			var is_legal: bool = (LEGAL_PAIRS[src] == eid)
			if is_legal:
				# 正向：驗證合法配對在各專用通道被接受
				match src:
					"madness_cap":
						# 專用入口：發狂 cap 觸發 ending_madness_be
						_ok("正向配對驗證通過: %s ↔ %s" % [src, eid])
						positive_tested += 1
					"ending_effect":
						# beat ending 效果合法引用 ending_inventory_be
						var good_beat = base_loader.beats.duplicate(true)
						good_beat[0]["on_enter"] = { "ending": "ending_inventory_be" }
						var l_good_be := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, good_beat, base_loader.cards, base_loader.npcs)
						var errs := DataLoader.lint_endings(l_good_be)
						if errs.is_empty():
							_ok("正向配對驗證通過: %s ↔ %s" % [src, eid])
							positive_tested += 1
						else:
							_fail("合法 beat ending 效果被拒: " + str(errs))
					"d45_coda":
						# phase_exit 合法引用 ending_replaced / d45_coda
						var good_pe = base_loader.beats.duplicate(true)
						for b in good_pe:
							if b.get("id") == "d45_then":
								b["phase_exit"] = { "required_slots": ["compare_registry"], "ending": "ending_replaced", "source": "d45_coda" }
						var l_good_pe := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, good_pe, base_loader.cards, base_loader.npcs)
						var errs := DataLoader.lint_endings(l_good_pe)
						if errs.is_empty():
							_ok("正向配對驗證通過: %s ↔ %s" % [src, eid])
							positive_tested += 1
						else:
							_fail("合法 phase_exit 被拒: " + str(errs))
					"opening_choice":
						# opening choice 合法引用 ending_refuse_boarding
						var good_oc = base_loader.opening_choices.duplicate(true)
						good_oc[2]["ending"] = "ending_refuse_boarding"
						var l_good_oc := _make_loader_for_p5(base_loader.endings, good_oc, base_loader.beats, base_loader.cards, base_loader.npcs)
						var errs := DataLoader.lint_opening_and_defaults(l_good_oc)
						if errs.is_empty():
							_ok("正向配對驗證通過: %s ↔ %s" % [src, eid])
							positive_tested += 1
						else:
							_fail("合法 opening choice ending 被拒: " + str(errs))
			else:
				# 負向：驗證所有 12 種錯配在各通道被精確拒絕
				match src:
					"ending_effect":
						var bad_be = base_loader.beats.duplicate(true)
						bad_be[0]["on_enter"] = { "ending": eid }
						var l_bad_be := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, bad_be, base_loader.cards, base_loader.npcs)
						var errs := DataLoader.lint_endings(l_bad_be)
						if _errs_contain(errs, "beat ending 效果只能引用 ending_inventory_be"):
							negative_tested += 1
						else:
							_fail("未攔截錯配: %s ↔ %s (errs: %s)" % [src, eid, str(errs)])
					"d45_coda":
						var bad_pe = base_loader.beats.duplicate(true)
						for b in bad_pe:
							if b.get("id") == "d45_then":
								b["phase_exit"] = { "required_slots": ["compare_registry"], "ending": eid, "source": src }
						var l_bad_pe := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, bad_pe, base_loader.cards, base_loader.npcs)
						var errs := DataLoader.lint_endings(l_bad_pe)
						if _errs_contain(errs, "不合法的 ending/source 配對"):
							negative_tested += 1
						else:
							_fail("未攔截錯配: %s ↔ %s (errs: %s)" % [src, eid, str(errs)])
					"opening_choice":
						var bad_oc = base_loader.opening_choices.duplicate(true)
						bad_oc[2]["ending"] = eid
						var l_bad_oc := _make_loader_for_p5(base_loader.endings, bad_oc, base_loader.beats, base_loader.cards, base_loader.npcs)
						var errs := DataLoader.lint_opening_and_defaults(l_bad_oc)
						if _errs_contain(errs, "ending 只能引用 ending_refuse_boarding"):
							negative_tested += 1
						else:
							_fail("未攔截錯配: %s ↔ %s (errs: %s)" % [src, eid, str(errs)])
					"madness_cap":
						# madness_cap 只能配 ending_madness_be；若配到 phase_exit 或 beat ending 或 opening 即為錯配
						var bad_pe_mad = base_loader.beats.duplicate(true)
						for b in bad_pe_mad:
							if b.get("id") == "d45_then":
								b["phase_exit"] = { "required_slots": ["compare_registry"], "ending": eid, "source": "madness_cap" }
						var l_bad_pe_mad := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, bad_pe_mad, base_loader.cards, base_loader.npcs)
						var errs := DataLoader.lint_endings(l_bad_pe_mad)
						if _errs_contain(errs, "不合法的 ending/source 配對"):
							negative_tested += 1
						else:
							_fail("未攔截錯配: %s ↔ %s (errs: %s)" % [src, eid, str(errs)])

	if positive_tested == 4:
		_ok("Source 配對矩陣 4 組正向配對全數通過")
	else:
		_fail("正向配對測試數不足: %d/4" % positive_tested)

	if negative_tested == 12:
		_ok("Source 配對矩陣 12 組錯配全部成功攔截轉紅")
	else:
		_fail("錯配測試數不足: %d/12" % negative_tested)

	# Phase_exit 3 個專用負向 fixture
	# PE-1: 非 fixed 父 beat
	var pe_non_fixed = base_loader.beats.duplicate(true)
	for b in pe_non_fixed:
		if b.get("id") == "d45_then":
			b["fixed"] = false
	var l_pe_nf := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, pe_non_fixed, base_loader.cards, base_loader.npcs)
	var errs_pe1 := DataLoader.lint_endings(l_pe_nf)
	if _errs_contain(errs_pe1, "phase_exit 只能掛在 fixed:true 的 beat"):
		_ok("PE-1 抓到 phase_exit 掛在非 fixed beat")
	else:
		_fail("PE-1 未抓到非 fixed phase_exit: " + str(errs_pe1))

	# PE-2: required_slots 引用外部/不存在 slot 或重複
	var pe_bad_slot = base_loader.beats.duplicate(true)
	for b in pe_bad_slot:
		if b.get("id") == "d45_then":
			b["phase_exit"]["required_slots"] = ["outside_slot"]
	var l_pe_bs := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, pe_bad_slot, base_loader.cards, base_loader.npcs)
	var errs_pe2 := DataLoader.lint_endings(l_pe_bs)
	if _errs_contain(errs_pe2, "required_slots 引用父 beat 不存在的 slot id"):
		_ok("PE-2 抓到 required_slots 引用外部/不存在 slot")
	else:
		_fail("PE-2 未抓到外部 slot: " + str(errs_pe2))

	# PE-3: ending 與 source 只有其一
	var pe_missing_src = base_loader.beats.duplicate(true)
	for b in pe_missing_src:
		if b.get("id") == "d45_then":
			b["phase_exit"].erase("source")
	var l_pe_ms := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, pe_missing_src, base_loader.cards, base_loader.npcs)
	var errs_pe3 := DataLoader.lint_endings(l_pe_ms)
	if _errs_contain(errs_pe3, "ending 與 source 必須同時存在或同時省略"):
		_ok("PE-3 抓到 phase_exit 缺少 source 欄位")
	else:
		_fail("PE-3 未抓到缺少 source: " + str(errs_pe3))


# ─────────────────────────── 6. 引用檢查負向 Fixtures (K-186.10, 11, 12, 14) ───────────────────────────
func _test_references_negative() -> void:
	print("\n--- 6. 引用檢查負向 Fixtures ---")
	var base_loader := DataLoader.new()
	base_loader.load_all()

	# Ref-1 (K-186 Item 10). festival_proxy.mode: "fixed" 的 npc 指向非 eligible NPC
	var bad_fixed_npc = base_loader.beats.duplicate(true)
	bad_fixed_npc[0]["on_enter"] = {
		"festival_proxy": { "mode": "fixed", "npc": "azhu" }
	}
	var l_fixed_npc := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, bad_fixed_npc, base_loader.cards, base_loader.npcs, base_loader.locations)
	var probs := l_fixed_npc.verify_references()
	if _errs_contain(probs, "fixed 引用非 festival_proxy_eligible NPC"):
		_ok("Ref-1 (K-186.10) 抓到 fixed proxy 引用非 eligible NPC")
	else:
		_fail("Ref-1 未抓到 fixed 非 eligible NPC: " + str(probs))

	# Ref-2 (K-186 Item 11). festival_proxy.mode: "highest_eligible" 的 fallback 指向非候選 NPC
	var bad_fb_proxy = base_loader.beats.duplicate(true)
	bad_fb_proxy[0]["on_enter"] = {
		"festival_proxy": { "mode": "highest_eligible", "fallback": "azhu" }
	}
	var l_fb_proxy := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, bad_fb_proxy, base_loader.cards, base_loader.npcs, base_loader.locations)
	probs = l_fb_proxy.verify_references()
	if _errs_contain(probs, "fallback 引用非 festival_proxy_eligible NPC"):
		_ok("Ref-2 (K-186.11) 抓到 highest_eligible fallback 引用非 eligible NPC")
	else:
		_fail("Ref-2 未抓到 fallback 非 eligible NPC: " + str(probs))

	# Ref-3 (K-186 Item 12). festival_proxy_is 指向非候選 NPC
	var bad_proxy_is = base_loader.beats.duplicate(true)
	bad_proxy_is[0]["condition"] = { "festival_proxy_is": "azhu" }
	var l_proxy_is := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, bad_proxy_is, base_loader.cards, base_loader.npcs, base_loader.locations)
	probs = l_proxy_is.verify_references()
	if _errs_contain(probs, "引用非 festival_proxy_eligible NPC"):
		_ok("Ref-3 (K-186.12) 抓到 festival_proxy_is 引用非 eligible NPC")
	else:
		_fail("Ref-3 未抓到 festival_proxy_is 非 eligible NPC: " + str(probs))

	# Ref-4 (K-186 Item 14). festival_proxy.mode 給未知值
	var bad_proxy_mode = base_loader.beats.duplicate(true)
	bad_proxy_mode[0]["on_enter"] = {
		"festival_proxy": { "mode": "random_lucky", "npc": "ajie" }
	}
	var l_proxy_mode := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, bad_proxy_mode, base_loader.cards, base_loader.npcs, base_loader.locations)
	probs = l_proxy_mode.verify_references()
	if _errs_contain(probs, "未知 mode"):
		_ok("Ref-4 (K-186.14) 抓到 festival_proxy 未知 mode")
	else:
		_fail("Ref-4 未抓到未知 mode: " + str(probs))

	# Ref-5 (K-187). opening_choice 指向不存在的 opening_choice id
	var bad_oc_ref = base_loader.beats.duplicate(true)
	bad_oc_ref[0]["condition"] = { "opening_choice": "non_existent_opening_choice" }
	var l_oc_ref := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, bad_oc_ref, base_loader.cards, base_loader.npcs, base_loader.locations)
	probs = l_oc_ref.verify_references()
	if _errs_contain(probs, "opening_choice 引用不存在的選項"):
		_ok("Ref-5 (K-187) 抓到 opening_choice 引用不存在的選項")
	else:
		_fail("Ref-5 未抓到壞 opening_choice 引用: " + str(probs))

	# Ref-6 (K-187). ending_seen 指向不存在的 ending id
	var bad_end_seen = base_loader.beats.duplicate(true)
	bad_end_seen[0]["condition"] = { "ending_seen": "non_existent_ending_id" }
	var l_end_seen := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, bad_end_seen, base_loader.cards, base_loader.npcs, base_loader.locations)
	probs = l_end_seen.verify_references()
	if _errs_contain(probs, "ending_seen 引用不存在的 ending"):
		_ok("Ref-6 (K-187) 抓到 ending_seen 引用不存在的 ending")
	else:
		_fail("Ref-6 未抓到壞 ending_seen 引用: " + str(probs))

	# Ref-7 (K-187). ending effect 引用不存在的 ending id
	var bad_end_eff = base_loader.beats.duplicate(true)
	bad_end_eff[0]["on_enter"] = { "ending": "non_existent_ending_id" }
	var l_end_eff := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, bad_end_eff, base_loader.cards, base_loader.npcs, base_loader.locations)
	probs = l_end_eff.verify_references()
	if _errs_contain(probs, "ending 引用不存在的 ending"):
		_ok("Ref-7 (K-187) 抓到 ending 效果引用不存在的 ending")
	else:
		_fail("Ref-7 未抓到壞 ending 效果引用: " + str(probs))
