extends SceneTree

## P5-A 結局、開局與跨輪資料測試（實作規格書 P5-A、測試指南 P5-A）。
## 正向：載入正式資料，驗 lint 17/18/19 全綠、卡片/NPC/ending/opening 動態斷言與故事映射。
## 負向：以 in-memory loader 建每個錯誤類別的最小反例，逐條驗對應 lint 抓到。
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
	_test_nested_effects_and_required_shapes()

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


func _make_loader_for_p5(endings: Array, opening: Array, beats: Array, cards: Dictionary, npcs: Dictionary) -> DataLoader:
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


# ─────────────────────────── 2. Lint 17 負向 Fixtures ───────────────────────────
func _test_lint17_negative() -> void:
	print("\n--- 2. Lint 17 負向 Fixtures ---")
	var base_loader := DataLoader.new()
	base_loader.load_all()

	# 2.1 缺少 ending id
	var l_missing := _make_loader_for_p5(base_loader.endings.slice(0, 3), base_loader.opening_choices, base_loader.beats, base_loader.cards, base_loader.npcs)
	var errs := DataLoader.lint_endings(l_missing)
	if _errs_contain(errs, "缺少必填 ending id") and _errs_contain(errs, "預期恰 4 筆 ending"):
		_ok("2.1 抓到缺少 ending id")
	else:
		_fail("2.1 未抓到缺少 ending id: " + str(errs))

	# 2.2 未知 kind
	var bad_kind_endings = base_loader.endings.duplicate(true)
	bad_kind_endings[0]["kind"] = "branching"
	var l_bad_kind := _make_loader_for_p5(bad_kind_endings, base_loader.opening_choices, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_endings(l_bad_kind)
	if _errs_contain(errs, "kind 必須為 composite") or _errs_contain(errs, "未知 kind"):
		_ok("2.2 抓到未知/錯誤 kind")
	else:
		_fail("2.2 未抓到未知/錯誤 kind: " + str(errs))

	# 2.3 缺少 fallback
	var bad_fb_endings = base_loader.endings.duplicate(true)
	var vgs: Array = bad_fb_endings[0]["variant_groups"]
	vgs[0]["rules"][2].erase("fallback")
	vgs[0]["rules"][2]["when"] = { "flag": "no_such_flag" }
	var l_bad_fb := _make_loader_for_p5(bad_fb_endings, base_loader.opening_choices, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_endings(l_bad_fb)
	if _errs_contain(errs, "必須恰有一個 fallback"):
		_ok("2.3 抓到缺少 fallback")
	else:
		_fail("2.3 未抓到缺少 fallback: " + str(errs))

	# 2.4 多個 fallback
	var multi_fb_endings = base_loader.endings.duplicate(true)
	var vgs2: Array = multi_fb_endings[0]["variant_groups"]
	vgs2[0]["rules"][0]["fallback"] = true
	vgs2[0]["rules"][0].erase("when")
	var l_multi_fb := _make_loader_for_p5(multi_fb_endings, base_loader.opening_choices, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_endings(l_multi_fb)
	if _errs_contain(errs, "必須恰有一個 fallback"):
		_ok("2.4 抓到多個 fallback")
	else:
		_fail("2.4 未抓到多個 fallback: " + str(errs))

	# 2.5 文案洩漏內部 ending id
	var leak_endings = base_loader.endings.duplicate(true)
	leak_endings[0]["first_seen"]["prefix_pages"][0]["text"] = "你走向了 ending_replaced 的結局。"
	var l_leak := _make_loader_for_p5(leak_endings, base_loader.opening_choices, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_endings(l_leak)
	if _errs_contain(errs, "玩家文字直接包含內部 ending id"):
		_ok("2.5 抓到文案洩漏內部 ending id")
	else:
		_fail("2.5 未抓到文案洩漏內部 ending id: " + str(errs))

	# 2.6 phase_exit 引用不存在的槽
	var bad_pe_beats = base_loader.beats.duplicate(true)
	for b in bad_pe_beats:
		if b.get("id") == "d45_then":
			b["phase_exit"]["required_slots"] = ["non_existent_slot"]
	var l_bad_pe := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, bad_pe_beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_endings(l_bad_pe)
	if _errs_contain(errs, "required_slots 引用父 beat 不存在的 slot id"):
		_ok("2.6 抓到 phase_exit 引用外部/不存在 slot")
	else:
		_fail("2.6 未抓到 phase_exit 引用不存在 slot: " + str(errs))


# ─────────────────────────── 3. Lint 18 負向 Fixtures ───────────────────────────
func _test_lint18_negative() -> void:
	print("\n--- 3. Lint 18 負向 Fixtures ---")
	var base_loader := DataLoader.new()
	base_loader.load_all()

	# 3.1 opening choices 缺選項
	var l_missing_oc := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices.slice(0, 2), base_loader.beats, base_loader.cards, base_loader.npcs)
	var errs := DataLoader.lint_opening_and_defaults(l_missing_oc)
	if _errs_contain(errs, "順序或項目不符預期"):
		_ok("3.1 抓到 opening choices 缺少選項")
	else:
		_fail("3.1 未抓到 opening choices 缺少選項: " + str(errs))

	# 3.2 opening choice 同時包含 on_select 與 ending
	var bad_oc = base_loader.opening_choices.duplicate(true)
	bad_oc[0]["ending"] = "ending_replaced"
	var l_both := _make_loader_for_p5(base_loader.endings, bad_oc, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_both)
	if _errs_contain(errs, "不得同時包含 on_select 與 ending"):
		_ok("3.2 抓到 opening choice 同時包含 on_select 與 ending")
	else:
		_fail("3.2 未抓到 on_select 與 ending 並存: " + str(errs))

	# 3.3 不上車缺少 requires 門檻
	var bad_refuse = base_loader.opening_choices.duplicate(true)
	bad_refuse[2].erase("requires")
	var l_no_req := _make_loader_for_p5(base_loader.endings, bad_refuse, base_loader.beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_no_req)
	if _errs_contain(errs, "不上車必須包含 requires 門檻"):
		_ok("3.3 抓到不上車缺少 requires")
	else:
		_fail("3.3 未抓到不上車缺少 requires: " + str(errs))

	# 3.4 choice group 包含多個 default_if_unresolved
	var multi_def_beats = base_loader.beats.duplicate(true)
	for b in multi_def_beats:
		if b.get("id") == "d29_pm_invitation":
			b["slots"][0]["default_if_unresolved"] = true
	var l_multi_def := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, multi_def_beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_multi_def)
	if _errs_contain(errs, "包含多個 default_if_unresolved 槽"):
		_ok("3.4 抓到同組多個 default_if_unresolved")
	else:
		_fail("3.4 未抓到多個 default_if_unresolved: " + str(errs))

	# 3.5 default 槽收卡
	var def_card_beats = base_loader.beats.duplicate(true)
	for b in def_card_beats:
		if b.get("id") == "d29_pm_invitation":
			b["slots"][2]["accepts"] = ["protagonist"]
	var l_def_card := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, def_card_beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_def_card)
	if _errs_contain(errs, "default 槽不得收卡"):
		_ok("3.5 抓到 default 槽收卡")
	else:
		_fail("3.5 未抓到 default 槽收卡: " + str(errs))

	# 3.6 choice_requires_card:true 但 accepts 為空
	var empty_acc_beats = base_loader.beats.duplicate(true)
	for b in empty_acc_beats:
		if b.get("id") == "d43_pm_zhou":
			b["slots"][0]["accepts"] = []
	var l_empty_acc := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, empty_acc_beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_empty_acc)
	if _errs_contain(errs, "choice_requires_card:true 必須有非空 accepts"):
		_ok("3.6 抓到 choice_requires_card:true 但 accepts 為空")
	else:
		_fail("3.6 未抓到 choice_requires_card:true 空 accepts: " + str(errs))


# ─────────────────────────── 4. Lint 19 負向 Fixtures ───────────────────────────
func _test_lint19_negative() -> void:
	print("\n--- 4. Lint 19 負向 Fixtures ---")
	var base_loader := DataLoader.new()
	base_loader.load_all()

	# 4.1 卡片缺少 loop_persistent
	var bad_cards = base_loader.cards.duplicate(true)
	bad_cards["protagonist"].erase("loop_persistent")
	var l_missing_lp := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, base_loader.beats, bad_cards, base_loader.npcs)
	var errs := DataLoader.lint_loop_and_festival(l_missing_lp)
	if _errs_contain(errs, "缺少必填欄位 loop_persistent"):
		_ok("4.1 抓到卡片缺少 loop_persistent")
	else:
		_fail("4.1 未抓到卡片缺少 loop_persistent: " + str(errs))

	# 4.2 protagonist 設 loop_persistent:true
	var bad_pro_cards = base_loader.cards.duplicate(true)
	bad_pro_cards["protagonist"]["loop_persistent"] = true
	var l_pro_lp := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, base_loader.beats, bad_pro_cards, base_loader.npcs)
	errs = DataLoader.lint_loop_and_festival(l_pro_lp)
	if _errs_contain(errs, "loop_persistent:true 只能用於"):
		_ok("4.2 抓到 protagonist 設 loop_persistent:true")
	else:
		_fail("4.2 未抓到 protagonist 設 loop_persistent:true: " + str(errs))

	# 4.3 permanent lose 指向非 loop_persistent 卡
	var bad_lose_beats = base_loader.beats.duplicate(true)
	bad_lose_beats[0]["on_enter"] = {
		"lose": [ { "card": "info_husband_version", "permanent": true } ]
	}
	var l_bad_lose := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, bad_lose_beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_loop_and_festival(l_bad_lose)
	if _errs_contain(errs, "lose 的 permanent:true 指向非 loop_persistent 卡"):
		_ok("4.3 抓到 permanent:true 指向普通卡")
	else:
		_fail("4.3 未抓到 permanent:true 指向普通卡: " + str(errs))

	# 4.4 刪除 D31 festival_proxy_is 內容
	var no_d31_beats: Array[Dictionary] = []
	for b in base_loader.beats:
		if b.get("id") != "d31_proxy_ajie":
			no_d31_beats.append(b)
	var l_no_d31 := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, no_d31_beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_loop_and_festival(l_no_d31)
	if _errs_contain(errs, "缺少第 31 天 festival_proxy_is 內容"):
		_ok("4.4 抓到缺少第 31 天 festival_proxy_is 內容")
	else:
		_fail("4.4 未抓到缺少 D31 festival_proxy_is: " + str(errs))

	# 4.5 刪除 D39 festival_proxy_is 內容
	var no_d39_beats: Array[Dictionary] = []
	for b in base_loader.beats:
		if b.get("id") != "d39_proxy_awei":
			no_d39_beats.append(b)
	var l_no_d39 := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, no_d39_beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_loop_and_festival(l_no_d39)
	if _errs_contain(errs, "缺少第 39 天 festival_proxy_is 內容"):
		_ok("4.5 抓到缺少第 39 天 festival_proxy_is 內容")
	else:
		_fail("4.5 未抓到缺少 D39 festival_proxy_is: " + str(errs))

	# 4.6 非候選 NPC (azhu) 被標為 eligible
	var bad_npcs = base_loader.npcs.duplicate(true)
	bad_npcs["azhu"]["festival_proxy_eligible"] = true
	var l_bad_npc := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, base_loader.beats, base_loader.cards, bad_npcs)
	errs = DataLoader.lint_loop_and_festival(l_bad_npc)
	if _errs_contain(errs, "未被任何 slot 的 attention_npc 引用") or _errs_contain(errs, "缺少對應 fragment"):
		_ok("4.6 抓到未完全具備條件之 NPC 被設為 festival_proxy_eligible")
	else:
		_fail("4.6 未抓到非候選 NPC 違規: " + str(errs))


# ─────────────────────────── 5. Source 配對矩陣 ───────────────────────────
func _test_source_pairing_matrix() -> void:
	print("\n--- 5. Source 配對矩陣測試 ---")
	var base_loader := DataLoader.new()
	base_loader.load_all()

	# Beat ending 效果引用非 inventory BE (例如引用 ending_replaced)
	var bad_beat_ending = base_loader.beats.duplicate(true)
	bad_beat_ending[0]["on_enter"] = { "ending": "ending_replaced" }
	var l_bad_be := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, bad_beat_ending, base_loader.cards, base_loader.npcs)
	var errs := DataLoader.lint_endings(l_bad_be)
	if _errs_contain(errs, "beat ending 效果只能引用 ending_inventory_be"):
		_ok("5.1 抓到 beat ending 效果引用非 inventory BE")
	else:
		_fail("5.1 未抓到 beat ending 引用非 inventory BE: " + str(errs))

	# Beat phase_exit 錯配 source/ending
	var bad_pe_pair = base_loader.beats.duplicate(true)
	for b in bad_pe_pair:
		if b.get("id") == "d45_then":
			b["phase_exit"]["source"] = "opening_choice"
	var l_bad_pe_pair := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, bad_pe_pair, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_endings(l_bad_pe_pair)
	if _errs_contain(errs, "不合法的 ending/source 配對"):
		_ok("5.2 抓到 phase_exit 錯配 ending/source")
	else:
		_fail("5.2 未抓到 phase_exit 錯配: " + str(errs))


# ─────────────────── 6. 巢狀效果掃描與 D29／D43 正向形狀 ───────────────────
## lint 17／19 的效果掃描不能只看 on_enter 與 on_place；lint 18 要正面強制
## 規格書第十七節 lint 18 的「D29 必須有預設」與「D43 兩槽必須要求主角卡」。
func _test_nested_effects_and_required_shapes() -> void:
	print("\n--- 6. 巢狀效果掃描與 D29／D43 正向形狀 ---")
	var base_loader := DataLoader.new()
	base_loader.load_all()

	# 6.1 encounter 出口寫非法 ending：lint 17 必須抓到
	var enc_end_beats = base_loader.beats.duplicate(true)
	for b in enc_end_beats:
		if b.get("id") == "n_manydoors_ch1":
			b["encounter"]["on_victory"]["ending"] = "ending_replaced"
	var l_enc_end := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, enc_end_beats, base_loader.cards, base_loader.npcs)
	var errs := DataLoader.lint_endings(l_enc_end)
	if _errs_contain(errs, "beat ending 效果只能引用 ending_inventory_be"):
		_ok("6.1 抓到 encounter 出口的非法 ending 效果")
	else:
		_fail("6.1 未抓到 encounter 出口的 ending 效果: " + str(errs))

	# 6.2 encounter 的 on_resolve 寫非法 ending：lint 17 必須抓到
	var enc_res_beats = base_loader.beats.duplicate(true)
	for b in enc_res_beats:
		if b.get("id") == "n_manydoors_ch1":
			b["encounter"]["rounds"][0]["responses"][0]["on_resolve"]["ending"] = "ending_madness_be"
	var l_enc_res := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, enc_res_beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_endings(l_enc_res)
	if _errs_contain(errs, "beat ending 效果只能引用 ending_inventory_be"):
		_ok("6.2 抓到 encounter on_resolve 的非法 ending 效果")
	else:
		_fail("6.2 未抓到 encounter on_resolve 的 ending 效果: " + str(errs))

	# 6.3 on_place_by_level 藏 permanent:true 指普通卡：lint 19 必須抓到
	var lvl_lose_beats = base_loader.beats.duplicate(true)
	for b in lvl_lose_beats:
		if b.get("id") == "exit_sanquan":
			for s in b.get("slots", []):
				if s.get("id") == "x_smash":
					s["on_place_by_level"]["light"]["lose"] = [ { "card": "info_husband_version", "permanent": true } ]
	var l_lvl_lose := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, lvl_lose_beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_loop_and_festival(l_lvl_lose)
	if _errs_contain(errs, "lose 的 permanent:true 指向非 loop_persistent 卡"):
		_ok("6.3 抓到 on_place_by_level 內的 permanent:true")
	else:
		_fail("6.3 未抓到 on_place_by_level 內的 permanent:true: " + str(errs))

	# 6.4 encounter 出口藏 permanent:true 指普通卡：lint 19 必須抓到
	var enc_lose_beats = base_loader.beats.duplicate(true)
	for b in enc_lose_beats:
		if b.get("id") == "n_manydoors_ch1":
			b["encounter"]["on_failure"]["lose"] = [ { "card": "info_husband_version", "permanent": true } ]
	var l_enc_lose := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, enc_lose_beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_loop_and_festival(l_enc_lose)
	if _errs_contain(errs, "lose 的 permanent:true 指向非 loop_persistent 卡"):
		_ok("6.4 抓到 encounter 出口內的 permanent:true")
	else:
		_fail("6.4 未抓到 encounter 出口內的 permanent:true: " + str(errs))

	# 6.5 D29 邀請組零 default：lint 18 必須抓到
	var no_def_beats = base_loader.beats.duplicate(true)
	for b in no_def_beats:
		if b.get("id") == "d29_pm_invitation":
			for s in b.get("slots", []):
				s.erase("default_if_unresolved")
	var l_no_def := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, no_def_beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_no_def)
	if _errs_contain(errs, "必須有一個 default_if_unresolved 槽"):
		_ok("6.5 抓到 D29 邀請組零 default")
	else:
		_fail("6.5 未抓到 D29 邀請組零 default: " + str(errs))

	# 6.6 D29 default 槽帶 requires（無卡結算會被門檻擋住）：lint 18 必須抓到
	var gated_def_beats = base_loader.beats.duplicate(true)
	for b in gated_def_beats:
		if b.get("id") == "d29_pm_invitation":
			for s in b.get("slots", []):
				if s.get("default_if_unresolved") == true:
					s["requires"] = { "flag": "no_such_flag" }
	var l_gated_def := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, gated_def_beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_gated_def)
	if _errs_contain(errs, "否則無法由無卡 choose() 結算"):
		_ok("6.6 抓到 D29 default 槽帶門檻")
	else:
		_fail("6.6 未抓到 D29 default 槽帶門檻: " + str(errs))

	# 6.7 D43 工作槽拿掉 choice_requires_card：lint 18 必須抓到
	var free_job_beats = base_loader.beats.duplicate(true)
	for b in free_job_beats:
		if b.get("id") == "d43_pm_zhou":
			b["slots"][0].erase("choice_requires_card")
	var l_free_job := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, free_job_beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_free_job)
	if _errs_contain(errs, "的槽必須設 choice_requires_card:true"):
		_ok("6.7 抓到 D43 工作槽未要求主角卡")
	else:
		_fail("6.7 未抓到 D43 工作槽未要求主角卡: " + str(errs))

	# 6.8 D43 工作槽改收別的卡：lint 18 必須抓到
	var wrong_accepts_beats = base_loader.beats.duplicate(true)
	for b in wrong_accepts_beats:
		if b.get("id") == "d43_pm_zhou":
			b["slots"][1]["accepts"] = ["item_gradphoto"]
	var l_wrong_accepts := _make_loader_for_p5(base_loader.endings, base_loader.opening_choices, wrong_accepts_beats, base_loader.cards, base_loader.npcs)
	errs = DataLoader.lint_opening_and_defaults(l_wrong_accepts)
	if _errs_contain(errs, "的槽 accepts 只能收 protagonist"):
		_ok("6.8 抓到 D43 工作槽 accepts 收錯卡")
	else:
		_fail("6.8 未抓到 D43 工作槽 accepts 收錯卡: " + str(errs))
