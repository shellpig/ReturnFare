class_name DataLoader
extends RefCounted

const DataFacts := preload("res://scripts/core/data_facts.gd")

## 把 data/ 底下的 JSON 全部讀進來並建索引。
## 欄位定義見 data/SCHEMA.md——這裡不重複，只負責讀進來與檢查引用。
## data_dir 可選參數供壞資料 fixture 測試使用（全域結構決策的唯一豁免）。

const CARD_TYPES := [
	"protagonist", "person", "group", "equipment", "consumable", "info",
	"inference", "document", "knowledge", "mood", "madness", "routine",
]

var DATA_DIR: String
var BEATS_DIR: String

var tuning: Dictionary = {}
var relation_scale: Dictionary = {} ## 狀態名 -> 最低整數值（規格書第十二節單軸暫行案）
var card_types: Dictionary = {}     ## id -> card type definition
var cards: Dictionary = {}          ## id -> card
var locations: Dictionary = {}      ## id -> location（白天與夜間合在一起，id 全域唯一）
var npcs: Dictionary = {}           ## id -> npc
var beats: Array[Dictionary] = []
var beats_by_id: Dictionary = {}

var errors: PackedStringArray = []


func _init(data_dir: String = "res://data/") -> void:
	DATA_DIR = data_dir
	BEATS_DIR = data_dir + "beats/"


func load_all() -> bool:
	errors.clear()

	tuning = _read_json(DATA_DIR + "tuning.json")
	relation_scale = _read_json(DATA_DIR + "relation_scale.json")

	var card_types_file := _read_json(DATA_DIR + "card_types.json")
	for card_type in card_types_file.get("card_types", []):
		var type_id: String = str(card_type.get("id", ""))
		if card_types.has(type_id):
			errors.append("卡片型別 id 重複：%s" % type_id)
		card_types[type_id] = card_type

	var cards_file := _read_json(DATA_DIR + "cards.json")
	for c in cards_file.get("cards", []):
		if cards.has(c["id"]):
			errors.append("卡片 id 重複：%s" % c["id"])
		cards[c["id"]] = c

	var locs := _read_json(DATA_DIR + "locations.json")
	for group in ["day", "night"]:
		for l in locs.get(group, []):
			if locations.has(l["id"]):
				errors.append("地點 id 重複：%s" % l["id"])
			locations[l["id"]] = l

	var npcs_file := _read_json(DATA_DIR + "npcs.json")
	for n in npcs_file.get("npcs", []):
		if npcs.has(n["id"]):
			errors.append("NPC id 重複：%s" % n["id"])
		npcs[n["id"]] = n

	for path in _beat_files():
		var d := _read_json(path)
		for b in d.get("beats", []):
			var bid: String = str(b.get("id", "?"))
			if beats_by_id.has(bid):
				errors.append("beat id 重複：%s" % bid)
			var w: Variant = b.get("when")
			if w is Dictionary:
				var wd := w as Dictionary
				if wd.has("day") and wd.has("day_from"):
					errors.append("%s：when 同時包含 day 與 day_from" % bid)
			beats_by_id[bid] = b
			beats.append(b)

	return errors.is_empty()


## 跨檔引用檢查：beat 指到的地點與卡片是否真的存在。
func verify_references() -> PackedStringArray:
	var problems: PackedStringArray = []

	# 夜間地點的白天版：指到的地點要存在，而且必須是白天地點。
	for lid in locations:
		var loc: Dictionary = locations[lid]
		var counterpart: Variant = loc.get("day_counterpart")
		if counterpart == null:
			continue
		if not locations.has(counterpart):
			problems.append("%s：day_counterpart 不存在 → %s" % [lid, counterpart])
		elif locations[counterpart].get("layer", "") != "day":
			problems.append("%s：day_counterpart 不是白天地點 → %s" % [lid, counterpart])
		elif locations[counterpart].get("map", {}) != loc.get("map", {}):
			# 第二類的意思就是「白天去同一個位置」——座標不同就不是同一個地方。
			problems.append("%s：座標與 day_counterpart %s 不一致" % [lid, counterpart])

	# 地點級門檻 requires 引用檢查
	for lid in locations:
		var loc: Dictionary = locations[lid]
		if loc.has("requires"):
			_check_card_refs(loc["requires"], lid, "location.requires", problems)

	# NPC 可及性：地點要存在，時段不能超出該地點開放的時段。
	for nid in npcs:
		var npc: Dictionary = npcs[nid]
		var card_id: Variant = npc.get("card")
		if card_id != null and not cards.has(card_id):
			problems.append("NPC %s：card 不存在 → %s" % [nid, card_id])
		for at in npc.get("at", []):
			var at_loc: String = at.get("location", "")
			if not locations.has(at_loc):
				problems.append("NPC %s：at.location 不存在 → %s" % [nid, at_loc])
				continue
			var open_phases: Array = locations[at_loc].get("phases", [])
			for p in at.get("phases", []):
				if not open_phases.has(p):
					problems.append("NPC %s：%s 沒有 %s 這個時段" % [nid, at_loc, p])

	for b in beats:
		var bid: String = b["id"]

		if not locations.has(b.get("location", "")):
			problems.append("%s：location 不存在 → %s" % [bid, b.get("location", "")])

		for key in ["condition", "requires", "on_enter", "echo"]:
			_check_card_refs(b.get(key), bid, key, problems)

		# P4-A：encounter 的巢狀效果（response/fallback on_resolve、三種出口）也要走引用檢查。
		_check_card_refs(b.get("encounter"), bid, "encounter", problems)

		for s in b.get("slots", []):
			var where := "slot:" + str(s.get("id", "?"))
			_check_card_refs(s.get("requires"), bid, where, problems)
			_check_card_refs(s.get("on_place"), bid, where, problems)
			# P4-A：委託 delegation.report 的 gain/lose 引用檢查。
			_check_card_refs(s.get("delegation"), bid, where + ".delegation", problems)
			if s.has("on_place_by_level") and s["on_place_by_level"] is Dictionary:
				for lvl in (s["on_place_by_level"] as Dictionary).values():
					_check_card_refs(lvl, bid, where + ".on_place_by_level", problems)
			for a in s.get("accepts", []):
				if not cards.has(a) and not CARD_TYPES.has(a):
					problems.append("%s [%s]：accepts 既不是卡也不是 type → %s" % [bid, where, a])

	return problems


## lint 9：卡片 type 與 card_types.json 的顯示型別封閉性。
## 每張卡使用的 type 必須有定義；資料檔定義的 id 也必須是合法型別名。
static func lint_card_types(loader: DataLoader) -> PackedStringArray:
	var problems: PackedStringArray = []
	for card_id: String in loader.cards:
		var card: Dictionary = loader.cards[card_id] as Dictionary
		var type_id: String = str(card.get("type", ""))
		if not loader.card_types.has(type_id):
			problems.append("卡片 %s：type 未在 card_types.json 定義 → %s" % [card_id, type_id])

		# P4-A：discardable 升格為每張卡必填 boolean（遭遇丟棄與支付的唯一真值，不得由 type 猜）。
		if not card.has("discardable"):
			problems.append("卡片 %s：缺少必填欄位 discardable" % card_id)
		elif not (card["discardable"] is bool):
			problems.append("卡片 %s：discardable 必須是 boolean（實際型別錯誤）" % card_id)

	for type_id: String in loader.card_types:
		if not CARD_TYPES.has(type_id):
			problems.append("card_types.json：未知型別 id → %s" % type_id)

	return problems


func _check_card_refs(node: Variant, bid: String, where: String, problems: PackedStringArray) -> void:
	if node is Dictionary:
		for k in node.keys():
			var v: Variant = node[k]
			match k:
				"gain", "lose":
					for c in v:
						# 兩種形態：卡 id 字串，或 { card, if } 帶條件項目（EffectApply.CARD_ENTRY_KEYS）
						if c is Dictionary:
							var entry := c as Dictionary
							var entry_card: String = str(entry.get("card", ""))
							if not cards.has(entry_card):
								problems.append("%s [%s]：%s 引用不存在的卡 → %s" % [bid, where, k, entry_card])
							_check_card_refs(entry.get("if"), bid, where, problems)
						elif not cards.has(c):
							problems.append("%s [%s]：%s 引用不存在的卡 → %s" % [bid, where, k, c])
				"has_card", "has_knowledge":
					if not cards.has(v) and not DataFacts.is_pending_card_ref_by_design(str(v)):
						problems.append("%s [%s]：%s 不存在 → %s" % [bid, where, k, v])
				"night_seen":
					var loc_id := str(v)
					if not locations.has(loc_id):
						problems.append("%s [%s]：%s 引用不存在的地點 → %s" % [bid, where, k, loc_id])
					elif locations[loc_id].get("layer", "") != "night":
						problems.append("%s [%s]：%s 引用的地點不是夜間地點 → %s" % [bid, where, k, loc_id])
				_:
					_check_card_refs(v, bid, where, problems)
	elif node is Array:
		for v in node:
			_check_card_refs(v, bid, where, problems)


## 語彙封閉性 lint（規格書第十七節 lint 1）：condition/requires/on_place/on_enter/echo.condition
## 用到的鍵，是否都在 ConditionEval / EffectApply 的封閉集合內。未知鍵即回傳問題。
static func lint_vocabulary(beats_list: Array[Dictionary]) -> PackedStringArray:
	var problems: PackedStringArray = []
	for b in beats_list:
		var bid: String = str(b.get("id", "?"))
		_lint_condition(b.get("condition"), bid, "beat.condition", problems)
		_lint_condition(b.get("requires"), bid, "beat.requires", problems)
		_lint_effect(b.get("on_enter"), bid, "beat.on_enter", problems)
		var echo: Variant = b.get("echo")
		if echo is Dictionary:
			_lint_condition((echo as Dictionary).get("condition"), bid, "echo.condition", problems)
		for s in b.get("slots", []) as Array:
			var where := "slot:" + str(s.get("id", "?"))
			_lint_condition(s.get("condition"), bid, where + ".condition", problems)
			_lint_condition(s.get("requires"), bid, where + ".requires", problems)
			_lint_effect(s.get("on_place"), bid, where + ".on_place", problems)
	return problems


static func _lint_condition(node: Variant, bid: String, where: String, problems: PackedStringArray) -> void:
	if node == null:
		return
	if not node is Dictionary:
		problems.append("%s [%s]：condition 不是 Dictionary" % [bid, where])
		return
	var d := node as Dictionary
	if d.is_empty():
		problems.append("%s [%s]：condition 是空的 Dictionary（非 null）" % [bid, where])
		return
	if d.keys().size() > 1:
		problems.append("%s [%s]：condition 包含多個運算子鍵（應使用 all）→ %s" % [bid, where, str(d.keys())])
	for k: String in d.keys():
		if not ConditionEval.KNOWN_KEYS.has(k):
			problems.append("%s [%s]：未知 condition 運算子 → %s" % [bid, where, k])
			continue
		match k:
			"not":
				_lint_condition(d[k], bid, where, problems)
			"all", "any":
				for sub: Variant in d[k] as Array:
					_lint_condition(sub, bid, where, problems)
			"count_at_least":
				var ca: Dictionary = d[k] as Dictionary
				for sub: Variant in ca.get("of", []) as Array:
					_lint_condition(sub, bid, where, problems)


static func _lint_effect(node: Variant, bid: String, where: String, problems: PackedStringArray) -> void:
	if node == null:
		return
	if not node is Dictionary:
		problems.append("%s [%s]：效果不是 Dictionary" % [bid, where])
		return
	for k: String in (node as Dictionary).keys():
		if not EffectApply.KNOWN_KEYS.has(k):
			problems.append("%s [%s]：未知效果鍵 → %s" % [bid, where, k])
			continue
		if k == "gain" or k == "lose":
			_lint_card_entries((node as Dictionary)[k], bid, where + "." + k, problems)


## 語彙封閉性 lint 1 的一部分：gain / lose 的元素形態。
## 允許卡 id 字串，或 { card, if }；`if` 走一般 condition 語彙檢查。
static func _lint_card_entries(node: Variant, bid: String, where: String, problems: PackedStringArray) -> void:
	if not node is Array:
		problems.append("%s [%s]：應為陣列" % [bid, where])
		return
	for entry: Variant in node as Array:
		if entry is String:
			continue
		if not entry is Dictionary:
			problems.append("%s [%s]：卡片項目必須是字串或 { card, if } 物件" % [bid, where])
			continue
		var d := entry as Dictionary
		for k: String in d.keys():
			if not EffectApply.CARD_ENTRY_KEYS.has(k):
				problems.append("%s [%s]：卡片項目未知鍵 → %s" % [bid, where, k])
		var card_val: Variant = d.get("card")
		if not (card_val is String) or (card_val as String).is_empty():
			problems.append("%s [%s]：卡片項目缺少 card" % [bid, where])
		if d.has("if"):
			_lint_condition(d["if"], bid, where + ".if", problems)


## 語彙封閉性 lint 2：有 requires 但沒填 reject_reason（架構要求灰掉一定要附理由）。回傳警告，不擋 Data.ok。
static func lint_missing_reject_reason(beats_list: Array[Dictionary]) -> PackedStringArray:
	var warnings: PackedStringArray = []
	for b in beats_list:
		var bid: String = str(b.get("id", "?"))
		if b.has("requires") and str(b.get("reject_reason", "")).is_empty():
			warnings.append("%s [beat]：有 requires 但沒有 reject_reason" % bid)
		for s in b.get("slots", []) as Array:
			if s.has("requires") and str(s.get("reject_reason", "")).is_empty():
				warnings.append("%s [slot:%s]：有 requires 但沒有 reject_reason" % [bid, str(s.get("id", "?"))])
	return warnings


## lint 3：免費槽／選擇題同面板規約（SCHEMA規約、K-16、K-22、K-27）。
## 回傳 Dictionary { "errors": PackedStringArray, "warnings": PackedStringArray }
static func lint_free_slot_rules(beats_list: Array[Dictionary]) -> Dictionary:
	var errs: PackedStringArray = []
	var warns: PackedStringArray = []

	# 1. 檢查 choice 槽不可收 protagonist（K-22）
	#    例外：choice_requires_card:true 是明示的硬成本槽，提交 protagonist 就消耗該行動時段
	#    （SCHEMA choice_group：D43 工作槽、P4 prescription_route 的親自處理槽都走這條）。
	for b in beats_list:
		var bid: String = str(b.get("id", "?"))
		for s: Dictionary in b.get("slots", []) as Array:
			var cg: Variant = s.get("choice_group")
			var is_choice := cg != null and not str(cg).is_empty()
			var accepts: Array = s.get("accepts", []) as Array
			var requires_card := bool(s.get("choice_requires_card", false))
			if is_choice and accepts.has("protagonist") and not requires_card:
				errs.append("%s [slot:%s]：choice 槽的 accepts 不得包含 protagonist" % [bid, str(s.get("id", "?"))])

	# 2. 同面板規約（K-27）：以 (day, phase, location) 為單位檢查非 fixed 面板是否至少有一格收主角卡
	var panels_map := {}
	for b in beats_list:
		var w: Variant = b.get("when")
		if not w is Dictionary:
			continue
		var phase_str: String = str((w as Dictionary).get("phase", ""))
		if not phase_str in ["morning", "afternoon"]:
			continue
		var day_num: int = int((w as Dictionary).get("day", -1))
		var loc_id: String = str(b.get("location", ""))
		if loc_id.is_empty():
			continue

		var pkey := "第 %d 天 %s・%s" % [day_num, phase_str, loc_id]
		if not panels_map.has(pkey):
			panels_map[pkey] = []
		(panels_map[pkey] as Array).append(b)

	for pkey: String in panels_map:
		var pbeats: Array = panels_map[pkey] as Array
		var all_fixed := true
		var has_protag_slot := false
		var beat_ids: PackedStringArray = []

		for b: Dictionary in pbeats:
			beat_ids.append(str(b.get("id", "?")))
			if not bool(b.get("fixed", false)):
				all_fixed = false
			for s: Dictionary in b.get("slots", []) as Array:
				var accepts: Array = s.get("accepts", []) as Array
				if accepts.has("protagonist"):
					has_protag_slot = true
					break

		if all_fixed:
			continue

		if not has_protag_slot:
			var all_exempt := true
			for bid in beat_ids:
				if not DataFacts.BY_DESIGN_CHOICE_ONLY_BEATS.has(bid):
					all_exempt = false
					break
			if all_exempt:
				warns.append("%s (%s)：面板僅有免費槽（已列入 DataFacts 豁免名單）" % [", ".join(beat_ids), pkey])
			else:
				errs.append("%s (%s)：非 fixed 面板無任何主角卡槽，違反 SCHEMA 同面板規約" % [", ".join(beat_ids), pkey])

	return { "errors": errs, "warnings": warns }


static func lint_choice_rules(beats_list: Array[Dictionary]) -> Dictionary:
	return lint_free_slot_rules(beats_list)


## lint 5：行動格覆蓋與地點時段支援檢查（規格書第十七節 lint 5、K-16）。
## 1. 驗證每一天每個行動時段（morning / afternoon）皆有 beat（刻意留空者除外）。
## 2. 驗證所有白天 beat 所屬地點的 phases 均支援該 beat 的時段。
static func lint_action_phases(loader: DataLoader) -> PackedStringArray:
	var errs: PackedStringArray = []
	for d in range(1, 46):
		for p in ["morning", "afternoon"]:
			if DataFacts.is_empty_phase_by_design(d, p):
				continue
			var beats_in_phase := loader.beats_at(d, p)
			if beats_in_phase.is_empty():
				errs.append("第 %d 天 %s：沒有任何 beat" % [d, p])

	for b in loader.beats:
		var w: Variant = b.get("when")
		if not w is Dictionary:
			continue
		var p_val: Variant = (w as Dictionary).get("phase")
		var phases_to_check: Array[String] = []
		if p_val is Array:
			for p_item in p_val as Array:
				phases_to_check.append(str(p_item))
		elif p_val is String:
			phases_to_check.append(str(p_val))

		var loc_id: String = str(b.get("location", ""))
		var loc: Dictionary = loader.locations.get(loc_id, {}) as Dictionary
		var loc_phases: Array = loc.get("phases", []) as Array
		for phase_str in phases_to_check:
			if phase_str in ["morning", "afternoon"]:
				if not loc_phases.has(phase_str):
					errs.append("%s：beat 時段為 %s，但所屬地點 %s 的 phases 僅有 %s" % [
						str(b.get("id", "")), phase_str, loc_id, str(loc_phases)
					])

	return errs


## lint 4：縱慾完整性（規格書第十七節 lint 4）。
## 驗證 1～45 天的每一天（morning 與 afternoon），至少存在一個無條件自動縱慾出口。
## 判準是「進得了強制縱慾挑選池」，只看 condition / requires，不驗地點開放時段。
static func lint_indulgence_integrity(loader: DataLoader) -> PackedStringArray:
	var errs: PackedStringArray = []
	for d in range(1, 46):
		for p in ["morning", "afternoon"]:
			var has_unconditional_exit := false
			for b in loader.beats_at(d, p):
				var b_cond: Variant = b.get("condition")
				var b_req: Variant = b.get("requires")
				if b_req != null and not (b_req is Dictionary and (b_req as Dictionary).is_empty()):
					continue
				if not _is_unconditional_or_madness_only(b_cond):
					continue

				for s: Dictionary in b.get("slots", []) as Array:
					var accepts: Array = s.get("accepts", []) as Array
					if not accepts.has("madness"):
						continue
					var ind: Dictionary = s.get("indulgence", {}) as Dictionary
					if ind.get("auto", true) == false:
						continue
					var s_req: Variant = s.get("requires")
					if s_req != null and not (s_req is Dictionary and (s_req as Dictionary).is_empty()):
						continue
					var s_cond: Variant = s.get("condition")
					if not _is_unconditional_or_madness_only(s_cond):
						continue

					has_unconditional_exit = true
					break
				if has_unconditional_exit:
					break

			if not has_unconditional_exit:
				errs.append("第 %d 天 %s：無任何無條件自動縱慾出口" % [d, p])

	return errs


static func _is_unconditional_or_madness_only(cond: Variant) -> bool:
	if cond == null:
		return true
	if not cond is Dictionary:
		return false
	var d := cond as Dictionary
	if d.is_empty():
		return true
	if d.keys().size() == 1 and d.has("madness_at_least"):
		return true
	return false


## lint 10：縱慾出口資料完整性（規格書第十七節 lint 10）。
## 1. accepts 含 madness 的槽必須有 indulgence 物件且 weight 是整數。
## 2. on_place_by_level 的鍵只能是 light / normal / heavy，值的內部鍵照第十四節效果鍵表。
## 3. indulgence.auto 為 false 的槽全作至多一個（泡湯）。
static func lint_indulgence_exits(beats_list: Array[Dictionary]) -> PackedStringArray:
	var errs: PackedStringArray = []
	var non_auto_count := 0

	for b in beats_list:
		var bid: String = str(b.get("id", "?"))
		for s: Dictionary in b.get("slots", []) as Array:
			var sid: String = str(s.get("id", "?"))
			var where := "%s [slot:%s]" % [bid, sid]
			var accepts: Array = s.get("accepts", []) as Array
			if not accepts.has("madness"):
				continue

			var ind_val: Variant = s.get("indulgence")
			if ind_val == null or not ind_val is Dictionary:
				errs.append("%s：accepts 含 madness 但缺少有效的 indulgence 物件" % where)
				continue

			var ind := ind_val as Dictionary
			var auto_val: Variant = ind.get("auto")
			var is_auto: bool = true
			if auto_val != null:
				if not auto_val is bool:
					errs.append("%s：indulgence.auto 必須是布林值" % where)
				else:
					is_auto = bool(auto_val)

			if not is_auto:
				non_auto_count += 1

			# 非 auto 槽（泡湯）不強制 weight；auto 槽必須有整數 weight
			if is_auto:
				var weight_val: Variant = ind.get("weight")
				if weight_val == null or not (weight_val is int or weight_val is float) or float(int(weight_val)) != float(weight_val):
					errs.append("%s：indulgence.weight 必須是整數" % where)

			# on_place_by_level 檢查
			if s.has("on_place_by_level"):
				var by_lvl_val: Variant = s.get("on_place_by_level")
				if not by_lvl_val is Dictionary:
					errs.append("%s：on_place_by_level 必須是 Dictionary" % where)
				else:
					var by_lvl := by_lvl_val as Dictionary
					for lvl_key: String in by_lvl.keys():
						if not lvl_key in ["light", "normal", "heavy"]:
							errs.append("%s：on_place_by_level 未知強度鍵 → %s" % [where, lvl_key])
						else:
							_lint_effect(by_lvl[lvl_key], bid, where + ".on_place_by_level." + lvl_key, errs)

	if non_auto_count > 1:
		errs.append("全作 indulgence.auto 為 false 的槽至多 1 個，實際有 %d 個" % non_auto_count)

	return errs


## lint 7：夜間可達性檢查（規格書第十七節 lint 7）。
static func lint_night_reachability(loader: DataLoader) -> PackedStringArray:
	var errs: PackedStringArray = []
	for b in loader.beats:
		var bid: String = str(b.get("id", "?"))
		var loc_id: String = str(b.get("location", ""))
		var loc: Dictionary = loader.locations.get(loc_id, {}) as Dictionary
		var is_fixed: bool = bool(b.get("fixed", false))
		var w: Variant = b.get("when")
		var is_night := false

		if w is Dictionary and str((w as Dictionary).get("phase", "")) == "night":
			is_night = true
			var night_day: int = int((w as Dictionary).get("day", -1))
			var earliest: int = int(loc.get("earliest_night", 1))
			if night_day < earliest:
				errs.append("%s：定日夜 beat 日期（%d）早於地點 %s 的 earliest_night（%d）" % [
					bid, night_day, loc_id, earliest
				])

		if is_night or b.has("chapter") or (not b.has("when") and str(loc.get("layer", "")) == "night"):
			# 非 fixed 的夜間 beat 必須掛在 night layer 地點或旅館（sanquan）
			if not is_fixed:
				var layer: String = str(loc.get("layer", ""))
				if layer != "night" and loc_id != "sanquan":
					errs.append("%s：非 fixed 夜間 beat 掛在非夜間地點且非 sanquan（%s）" % [bid, loc_id])
	return errs


## lint 8：殘響可播出性（規格書第十七節 lint 8）。
static func lint_echoes(beats_list: Array[Dictionary]) -> PackedStringArray:
	var errs: PackedStringArray = []
	var seen_echo_texts: Dictionary = {}

	for b in beats_list:
		var bid: String = str(b.get("id", "?"))
		var echo_raw: Variant = b.get("echo")
		if echo_raw == null:
			continue
		if not echo_raw is Dictionary:
			errs.append("%s：echo 不是 Dictionary" % bid)
			continue
		var echo := echo_raw as Dictionary
		if not echo.has("day") or not (echo["day"] is int or echo["day"] is float) or int(echo["day"]) <= 0:
			errs.append("%s：echo 缺少有效的 day 欄位" % bid)
			continue

		var echo_day: int = int(echo["day"])
		var w: Variant = b.get("when")
		if w is Dictionary:
			var beat_day: int = int((w as Dictionary).get("day", -1))
			if beat_day > 0 and echo_day <= beat_day:
				errs.append("%s：echo.day（%d）必須大於 beat.when.day（%d）" % [bid, echo_day, beat_day])

		var text: String = str(echo.get("text", "")).strip_edges()
		if text.is_empty():
			errs.append("%s：echo.text 為空" % bid)
		elif seen_echo_texts.has(text):
			errs.append("%s：echo.text 與 %s 重複" % [bid, str(seen_echo_texts[text])])
		else:
			seen_echo_texts[text] = bid

	return errs


## lint 11：夜間對位完整性（規格書第十七節 lint 11）。
static func lint_night_alignment(loader: DataLoader) -> PackedStringArray:
	var errs: PackedStringArray = []
	var counterpart_to_card: Dictionary = {} # day_counterpart -> card_id
	var card_to_counterparts: Dictionary = {} # card_id -> Array (day_counterparts)

	for lid in loader.locations:
		var loc: Dictionary = loader.locations[lid]
		if loc.get("layer", "") != "night":
			continue

		var cp_val: Variant = loc.get("day_counterpart")
		var reveal_val: Variant = loc.get("night_reveal")

		if cp_val != null:
			var cp := str(cp_val)
			if reveal_val == null or not (reveal_val is String) or str(reveal_val).is_empty():
				errs.append("%s：有 day_counterpart（%s）但缺少有效的 night_reveal" % [lid, cp])
				continue

			var card_id := str(reveal_val)
			if not loader.cards.has(card_id):
				errs.append("%s：night_reveal 卡片不存在：%s" % [lid, card_id])
			else:
				var cdef: Dictionary = loader.cards[card_id]
				var ctype: String = str(cdef.get("type", ""))
				var slotless: bool = bool(cdef.get("slotless", false))
				if ctype != "knowledge":
					errs.append("%s：night_reveal 卡片 %s 型別不是 knowledge（實際為 %s）" % [lid, card_id, ctype])
				if not slotless:
					errs.append("%s：night_reveal 卡片 %s slotless 必須為 true" % [lid, card_id])

			# 驗證同一 day_counterpart 共用同一張卡
			if counterpart_to_card.has(cp):
				if counterpart_to_card[cp] != card_id:
					errs.append("%s：day_counterpart %s 指向多個不同的 night_reveal（%s vs %s）" % [
						lid, cp, counterpart_to_card[cp], card_id
					])
			else:
				counterpart_to_card[cp] = card_id

			# 雙向單射：不同 day_counterpart 不得共用同一張卡
			if not card_to_counterparts.has(card_id):
				card_to_counterparts[card_id] = []
			var cp_list: Array = card_to_counterparts[card_id]
			if not cp_list.has(cp):
				cp_list.append(cp)
				if cp_list.size() > 1:
					errs.append("不同 day_counterpart（%s）共用了同一張對位卡 %s" % [
						" 與 ".join(cp_list), card_id
					])
		else:
			if reveal_val != null:
				errs.append("%s：day_counterpart 為 null，但 night_reveal 不為 null（實際為 %s）" % [lid, str(reveal_val)])

	return errs


## lint 12：夜間地點狀態完整性（規格書第十七節 lint 12）。
static func lint_night_locations(loader: DataLoader) -> PackedStringArray:
	var errs: PackedStringArray = []

	for lid in loader.locations:
		var loc: Dictionary = loader.locations[lid]
		if loc.get("layer", "") != "night":
			continue

		# 1. 通用時間欄位與章節一致性檢查（含 teaser_only 與一般 night row）
		var earliest_val: Variant = loc.get("earliest_night")
		if earliest_val == null or not (earliest_val is int or earliest_val is float) or float(int(earliest_val)) != float(earliest_val) or int(earliest_val) < 1 or int(earliest_val) > 45:
			errs.append("%s：缺少有效的 earliest_night（1-45 整數）" % lid)

		var ch_val: Variant = loc.get("chapter")
		if ch_val == null or not (ch_val is int or ch_val is float) or float(int(ch_val)) != float(ch_val) or int(ch_val) < 1 or int(ch_val) > 3:
			errs.append("%s：缺少有效的 chapter（1-3 整數）" % lid)

		if earliest_val != null and (earliest_val is int or earliest_val is float) and ch_val != null and (ch_val is int or ch_val is float):
			var earliest := int(earliest_val)
			var ch := int(ch_val)
			var expected_ch := DataFacts.chapter_for_day(earliest)
			if ch != expected_ch:
				errs.append("%s：chapter（%d）與 earliest_night（%d 所屬章節 %d）不一致" % [
					lid, ch, earliest, expected_ch
				])

		# 2. teaser vs 一般 row 分支檢查
		var is_teaser: bool = bool(loc.get("teaser_only", false))
		if is_teaser:
			var reason_val: Variant = loc.get("reject_reason")
			if reason_val == null or not (reason_val is String) or str(reason_val).strip_edges().is_empty():
				errs.append("%s：teaser_only 地點缺少有效的 reject_reason" % lid)

			var cost_val: Variant = loc.get("madness_cost")
			if cost_val != null:
				errs.append("%s：teaser_only 地點的 madness_cost 必須為 null 或省略（實際為 %s）" % [lid, str(cost_val)])

			var cp_val: Variant = loc.get("day_counterpart")
			if cp_val != null:
				errs.append("%s：teaser_only 地點的 day_counterpart 必須為 null 或省略（實際為 %s）" % [lid, str(cp_val)])

			var rev_val: Variant = loc.get("night_reveal")
			if rev_val != null:
				errs.append("%s：teaser_only 地點的 night_reveal 必須為 null 或省略（實際為 %s）" % [lid, str(rev_val)])
		else:
			if not loc.has("madness_cost"):
				errs.append("%s：缺少 madness_cost 欄位" % lid)
			else:
				var cost_val: Variant = loc.get("madness_cost")
				if cost_val == null or not (cost_val is int or cost_val is float) or float(int(cost_val)) != float(cost_val) or int(cost_val) < 0:
					errs.append("%s：madness_cost 必須為 >= 0 之整數（實際為 %s）" % [lid, str(cost_val)])

	return errs


## lint 13：舊夜間旗標退場檢查（規格書第十七節 lint 13 / P3-B）。
## 遞迴掃整份 location 與 beat，含 slots[] 的 condition/requires/on_place/on_enter 等，
## 任何 key 或字串值包含 "opened_n_" 都報錯。
static func lint_legacy_night_flags(loader: DataLoader) -> PackedStringArray:
	var problems: PackedStringArray = []
	for lid: String in loader.locations:
		var loc: Dictionary = loader.locations[lid] as Dictionary
		_scan_legacy_flags(loc, lid, "location:" + lid, problems)
	for b in loader.beats:
		var bid: String = str(b.get("id", "?"))
		_scan_legacy_flags(b, bid, "beat:" + bid, problems)
	return problems


static func _scan_legacy_flags(node: Variant, bid: String, where: String, problems: PackedStringArray) -> void:
	if node is Dictionary:
		var d := node as Dictionary
		for k in d.keys():
			var k_str := str(k)
			if k_str.contains("opened_n_"):
				problems.append("%s [%s]：包含舊夜間旗標鍵 → %s" % [bid, where, k_str])
			var v: Variant = d[k]
			if v is String and str(v).contains("opened_n_"):
				problems.append("%s [%s.%s]：包含舊夜間旗標值 → %s" % [bid, where, k_str, str(v)])
			else:
				_scan_legacy_flags(v, bid, where + "." + k_str, problems)
	elif node is Array:
		var arr := node as Array
		for i in range(arr.size()):
			var item: Variant = arr[i]
			if item is String and str(item).contains("opened_n_"):
				problems.append("%s [%s[%d]]：包含舊夜間旗標值 → %s" % [bid, where, i, str(item)])
			else:
				_scan_legacy_flags(item, bid, "%s[%d]" % [where, i], problems)


## 某一天某個時段有哪些 beat（不解 condition，只挑時間對的）。
func beats_at(day: int, phase: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in beats:
		if DataFacts.beat_matches_time(b, day, phase):
			out.append(b)
	return out


## 取得某地點在夜間的結構候選（P3-C，唯一結構候選入口）。
## 純資料形狀選擇，不求值 condition / requires。
## 回傳：{ "primaries": Array[Dictionary], "addons": Array[Dictionary] }
func night_beat_candidates(day: int, location_id: String, current_chapter: int) -> Dictionary:
	var primaries: Array[Dictionary] = []
	var addons: Array[Dictionary] = []

	# 1. 定日夜間候選（同地點、non-fixed、exact when.day 且 matches_time 成立）
	for b in beats:
		if str(b.get("location", "")) != location_id:
			continue
		if bool(b.get("fixed", false)):
			continue
		var w_raw: Variant = b.get("when")
		if not (w_raw is Dictionary):
			continue
		var wd := w_raw as Dictionary
		if not wd.has("day") or wd.has("day_from") or wd.has("day_to"):
			continue
		if DataFacts.beat_matches_time(b, day, "night"):
			primaries.append(b)

	# 2. 章節變體（同地點、無 when、has chapter、chapter <= current_chapter，chapter 由高至低排序，同章保留資料原序）
	for ch in range(current_chapter, 0, -1):
		for b in beats:
			if str(b.get("location", "")) != location_id:
				continue
			if b.has("when"):
				continue
			if b.has("chapter") and int(b.get("chapter", 1)) == ch:
				primaries.append(b)

	# 3. 附加 beat（同地點、無 when、無 chapter，保留資料原序）
	for b in beats:
		if str(b.get("location", "")) != location_id:
			continue
		if not b.has("when") and not b.has("chapter"):
			addons.append(b)

	return {
		"primaries": primaries,
		"addons": addons,
	}


## Lint 14: 夜間一次性 beat 完整性檢查（P3-C、SCHEMA.md）。
## 1. meta_once 僅能為 boolean true，且僅供 fixed: true 與 exact night when 的 beat。
## 2. 所有 night-layer 地點上的 fixed beat（when.phase == 'night' 或 contains 'night'）必須標記 meta_once: true。
## 3. 同一個 when.day 至多只能有一個 night-layer fixed beat。
static func lint_night_once(loader: DataLoader) -> PackedStringArray:
	var problems := PackedStringArray()
	var night_fixed_by_day: Dictionary = {} # day: int -> beat_id: String

	for b in loader.beats:
		var bid := str(b.get("id", ""))
		var is_fixed := bool(b.get("fixed", false))
		var w_raw: Variant = b.get("when")
		var is_exact_night := false
		var beat_day := -1

		if w_raw is Dictionary:
			var wd := w_raw as Dictionary
			var p_val: Variant = wd.get("phase")
			var is_night_phase := false
			if p_val is String:
				is_night_phase = (p_val == "night")
			elif p_val is Array:
				is_night_phase = (p_val as Array).has("night")

			if is_night_phase and wd.has("day") and not wd.has("day_from") and not wd.has("day_to"):
				is_exact_night = true
				beat_day = int(wd.get("day", -1))

		# P4-A：repeat_each_run 遭遇是 meta_once 的相反形狀（每輪重演），兩者不得同時存在。
		var enc_raw: Variant = b.get("encounter")
		var repeat_raw: Variant = (enc_raw as Dictionary).get("repeat_each_run", false) if enc_raw is Dictionary else false
		var is_repeat: bool = repeat_raw is bool and repeat_raw

		var has_meta_once := b.has("meta_once")
		if has_meta_once:
			var mo_val: Variant = b.get("meta_once")
			if not (mo_val is bool and mo_val == true):
				problems.append("%s：meta_once 欄位值必須為 boolean true" % bid)
			if not is_fixed:
				problems.append("%s：meta_once 只能用於 fixed: true 的 beat" % bid)
			if not is_exact_night:
				problems.append("%s：meta_once 只能用於具有 exact night when 的 beat" % bid)
			if is_repeat:
				problems.append("%s：encounter.repeat_each_run 與 meta_once 不得同時存在" % bid)

		var loc_id := str(b.get("location", ""))
		var loc: Dictionary = loader.locations.get(loc_id, {}) as Dictionary
		var is_night_layer := str(loc.get("layer", "")) == "night"

		if is_fixed and is_exact_night and is_night_layer:
			# 窄例外：fixed && exact night when && encounter.repeat_each_run 可不 meta_once（P4-A、D8）。
			if not bool(b.get("meta_once", false)) and not is_repeat:
				problems.append("%s：night-layer 地點 (%s) 的 fixed night beat 必須標記 meta_once: true（或為 repeat_each_run 遭遇）" % [bid, loc_id])

			if beat_day > 0:
				if night_fixed_by_day.has(beat_day):
					var prev_bid: String = night_fixed_by_day[beat_day]
					problems.append("第 %d 夜存在多個 night-layer fixed beat：%s 與 %s（同一夜至多一個）" % [beat_day, prev_bid, bid])
				else:
					night_fixed_by_day[beat_day] = bid

	return problems



## Lint 15：委託資料完整性（P4-A、SCHEMA delegation）。
## 委託槽必須：accepts 恰一明確 person card id、與親自處理槽共用非空 choice_group、
## result_timing/report 配對、next_morning 不落第 45 天之後、preview/tendency 齊全、鎖定附理由。
static func lint_delegations(loader: DataLoader) -> PackedStringArray:
	var problems := PackedStringArray()
	for b in loader.beats:
		var bid := str(b.get("id", ""))
		# 本 beat 各 choice_group 是否有 protagonist（親自處理）槽
		var group_has_protag := {}
		for s0 in b.get("slots", []) as Array:
			var acc0: Array = (s0 as Dictionary).get("accepts", []) as Array
			var cg0 := str((s0 as Dictionary).get("choice_group", ""))
			if not cg0.is_empty() and acc0.has("protagonist"):
				group_has_protag[cg0] = true
		for s in b.get("slots", []) as Array:
			var slot := s as Dictionary
			if not slot.has("delegation"):
				continue
			var sid := str(slot.get("id", "?"))
			var where := "%s [slot:%s]" % [bid, sid]
			var deleg: Variant = slot.get("delegation")
			if not (deleg is Dictionary):
				problems.append("%s：delegation 不是 Dictionary" % where)
				continue
			var d := deleg as Dictionary
			# accepts 恰一明確 person card id
			var acc: Array = slot.get("accepts", []) as Array
			if acc.size() != 1 or not (acc[0] is String):
				problems.append("%s：委託槽 accepts 必須恰好一個明確 person card id" % where)
			else:
				var pid := str(acc[0])
				if pid == "person":
					problems.append("%s：委託槽 accepts 不可用型別泛稱 person" % where)
				elif not loader.cards.has(pid):
					problems.append("%s：委託槽 accepts 引用不存在的卡 -> %s" % [where, pid])
				elif str((loader.cards[pid] as Dictionary).get("type", "")) != "person":
					problems.append("%s：委託槽 accepts 的卡 %s 型別不是 person" % [where, pid])
			# choice_group 非空且本 beat 有親自處理槽共用
			var cg := str(slot.get("choice_group", ""))
			if cg.is_empty():
				problems.append("%s：委託槽必須有非空 choice_group" % where)
			elif not group_has_protag.has(cg):
				problems.append("%s：委託槽的 choice_group %s 缺親自處理（protagonist）槽" % [where, cg])
			# result_timing enum + report 配對
			var timing := str(d.get("result_timing", ""))
			if timing != "immediate" and timing != "next_morning":
				problems.append("%s：result_timing 非法 -> %s" % [where, timing])
			var has_report := d.has("report")
			if timing == "next_morning":
				if not has_report:
					problems.append("%s：next_morning 委託必須有 report" % where)
				elif not (d["report"] is Dictionary) or str((d["report"] as Dictionary).get("text", "")).is_empty():
					problems.append("%s：report 必須是含 text 的 Dictionary" % where)
				else:
					# report 共用 EffectApply 封閉效果鍵（不讓委託偷讀任意鍵）。
					_lint_effect(d["report"], bid, where + ".report", problems)
				var latest := _beat_latest_day(b)
				if latest >= 45:
					problems.append("%s：next_morning 委託最晚成立日 %d 會落到第 45 天之後" % [where, latest])
			elif timing == "immediate":
				if has_report:
					problems.append("%s：immediate 委託不得有 report" % where)
			# preview / tendency 必填
			if str(d.get("preview", "")).is_empty():
				problems.append("%s：delegation 缺 preview" % where)
			if str(d.get("tendency", "")).is_empty():
				problems.append("%s：delegation 缺 tendency" % where)
			# 鎖定條件必須附 reject_reason
			if slot.has("requires") and str(slot.get("reject_reason", "")).is_empty():
				problems.append("%s：委託槽有 requires 但缺 reject_reason" % where)
	return problems


## beat 最晚可能成立日（when.day 或 when.day_to；無 when 視為 45）。
static func _beat_latest_day(b: Dictionary) -> int:
	var w: Variant = b.get("when")
	if not (w is Dictionary):
		return 45
	var wd := w as Dictionary
	if wd.has("day"):
		return int(wd.get("day", 45))
	if wd.has("day_to"):
		return int(wd.get("day_to", 45))
	return 45


## Lint 16：遭遇資料完整性（P4-A、SCHEMA encounter）。
## round graph 從首回合可達、可結束；response 引用/不重疊；fallback/三出口/型別/enum；
## per-run fixed 與首次收費適用範圍。
static func lint_encounters(loader: DataLoader) -> PackedStringArray:
	var problems := PackedStringArray()
	for b in loader.beats:
		if not b.has("encounter"):
			continue
		var bid := str(b.get("id", ""))
		var enc_v: Variant = b.get("encounter")
		if not (enc_v is Dictionary):
			problems.append("%s [encounter]：encounter 不是 Dictionary" % bid)
			continue
		var enc := enc_v as Dictionary
		var where := "%s [encounter]" % bid

		var prsc: Variant = enc.get("per_round_slot_cost")
		if not _is_whole_number(prsc) or int(prsc) <= 0:
			problems.append("%s：per_round_slot_cost 必須為正整數" % where)
		if not enc.has("escape_cost"):
			problems.append("%s：escape_cost 必填（null 或非負整數）" % where)
		else:
			var ec: Variant = enc.get("escape_cost")
			if ec != null and (not _is_whole_number(ec) or int(ec) < 0):
				problems.append("%s：escape_cost 必須為 null 或非負整數" % where)
		if enc.has("allow_discard") and not (enc["allow_discard"] is bool):
			problems.append("%s：allow_discard 必須是 boolean" % where)
		if enc.has("repeat_each_run") and not (enc["repeat_each_run"] is bool):
			problems.append("%s：repeat_each_run 必須是 boolean" % where)
		if enc.has("charge_first_visit") and not (enc["charge_first_visit"] is bool):
			problems.append("%s：charge_first_visit 必須是 boolean" % where)
		var af := str(enc.get("after_finish", ""))
		if af != "stay" and af != "advance_phase":
			problems.append("%s：after_finish 必須是 stay 或 advance_phase -> %s" % [where, af])
		for exit_key in ["on_victory", "on_failure", "on_escape"]:
			if not (enc.get(exit_key) is Dictionary):
				problems.append("%s：缺少或型別錯誤的 %s" % [where, exit_key])
			else:
				_lint_effect(enc.get(exit_key), bid, "%s.%s" % [where, exit_key], problems)

		var rounds_v: Variant = enc.get("rounds")
		if not (rounds_v is Array) or (rounds_v as Array).is_empty():
			problems.append("%s：rounds 必須是非空陣列" % where)
			continue
		var rounds := rounds_v as Array
		var round_ids := {}
		var round_by_id := {}
		for r_v in rounds:
			if not (r_v is Dictionary):
				problems.append("%s：round 不是 Dictionary" % where)
				continue
			var r := r_v as Dictionary
			var rid := str(r.get("id", ""))
			if rid.is_empty():
				problems.append("%s：round 缺 id" % where)
				continue
			if round_ids.has(rid):
				problems.append("%s：round id 重複 -> %s" % [where, rid])
			round_ids[rid] = true
			round_by_id[rid] = r

		for rid_k in round_by_id.keys():
			var r: Dictionary = round_by_id[rid_k]
			var rwhere := "%s round:%s" % [where, rid_k]
			var resp_v: Variant = r.get("responses")
			if not (resp_v is Array) or (resp_v as Array).is_empty():
				problems.append("%s：responses 必須非空" % rwhere)
			else:
				var seen_accepts := {}
				var seen_resp_ids := {}
				for resp_vv in resp_v as Array:
					if not (resp_vv is Dictionary):
						problems.append("%s：response 不是 Dictionary" % rwhere)
						continue
					var resp := resp_vv as Dictionary
					var respid := str(resp.get("id", "?"))
					if not resp.has("id") or str(resp.get("id", "")).is_empty():
						problems.append("%s：response 缺 id" % rwhere)
					elif seen_resp_ids.has(respid):
						problems.append("%s：response id 重複 -> %s" % [rwhere, respid])
					else:
						seen_resp_ids[respid] = true
					var accs: Variant = resp.get("accepts")
					if not (accs is Array) or (accs as Array).is_empty():
						problems.append("%s response:%s：accepts 必須非空" % [rwhere, respid])
					else:
						for c_v in accs as Array:
							var cid := str(c_v)
							if not loader.cards.has(cid):
								problems.append("%s response:%s：accepts 引用不存在的卡 -> %s" % [rwhere, respid, cid])
							if seen_accepts.has(cid):
								problems.append("%s response:%s：accepts 卡 %s 與同 round 其他 response 重疊" % [rwhere, respid, cid])
							else:
								seen_accepts[cid] = respid
					if not (resp.get("consume_card") is bool):
						problems.append("%s response:%s：consume_card 必填 boolean" % [rwhere, respid])
					elif bool(resp["consume_card"]):
						for c_v2 in (resp.get("accepts", []) as Array):
							var cid2 := str(c_v2)
							if loader.cards.has(cid2) and not bool((loader.cards[cid2] as Dictionary).get("discardable", false)):
								problems.append("%s response:%s：consume_card:true 不可消耗不可丟棄卡 %s（禁止通用事件永久失去人物）" % [rwhere, respid, cid2])
					if not (resp.get("on_resolve") is Dictionary):
						problems.append("%s response:%s：缺 on_resolve" % [rwhere, respid])
					else:
						_lint_effect(resp.get("on_resolve"), bid, "%s response:%s.on_resolve" % [rwhere, respid], problems)
					_lint_next_round(resp.get("next_round"), round_ids, "%s response:%s" % [rwhere, respid], problems)
			var fb_v: Variant = r.get("fallback")
			if not (fb_v is Dictionary):
				problems.append("%s：缺 fallback" % rwhere)
			else:
				var fb := fb_v as Dictionary
				if fb.has("requires_discardable") and not (fb["requires_discardable"] is bool):
					problems.append("%s fallback：requires_discardable 必須是 boolean" % rwhere)
				if not (fb.get("on_resolve") is Dictionary):
					problems.append("%s fallback：缺 on_resolve" % rwhere)
				else:
					_lint_effect(fb.get("on_resolve"), bid, "%s fallback.on_resolve" % rwhere, problems)
				_lint_next_round(fb.get("next_round"), round_ids, "%s fallback" % rwhere, problems)

		if not round_by_id.is_empty():
			var first_id := str((rounds[0] as Dictionary).get("id", ""))
			var reachable := {}
			var stack := [first_id]
			while not stack.is_empty():
				var cur: String = str(stack.pop_back())
				if reachable.has(cur) or not round_by_id.has(cur):
					continue
				reachable[cur] = true
				var cr: Dictionary = round_by_id[cur]
				for resp_vv in cr.get("responses", []) as Array:
					var nr: Variant = (resp_vv as Dictionary).get("next_round")
					if nr != null:
						stack.append(str(nr))
				var fbb: Dictionary = cr.get("fallback", {}) as Dictionary
				var fnr: Variant = fbb.get("next_round")
				if fnr != null:
					stack.append(str(fnr))
			for rid2 in round_ids.keys():
				if not reachable.has(rid2):
					problems.append("%s：round %s 不可從第一回合到達" % [where, rid2])
			for rid3 in round_by_id.keys():
				if not _round_can_reach_null(str(rid3), round_by_id, {}):
					problems.append("%s：round %s 無法抵達任何結束出口（無出口 cycle）" % [where, rid3])

		var is_fixed := bool(b.get("fixed", false))
		var wd := {}
		if b.get("when") is Dictionary:
			wd = b.get("when") as Dictionary
		var has_exact_day: bool = wd.has("day") and not wd.has("day_from") and not wd.has("day_to") and _is_whole_number(wd.get("day"))
		var repeat_val: Variant = enc.get("repeat_each_run", false)
		if repeat_val is bool and repeat_val:
			if not is_fixed or not has_exact_day:
				problems.append("%s：repeat_each_run 只可用於有明確整數 when.day 的 fixed encounter" % where)
		var charge_val: Variant = enc.get("charge_first_visit", false)
		if charge_val is bool and charge_val:
			var phase_ok: bool = str(wd.get("phase", "")) == "night"
			var loc_id := str(b.get("location", ""))
			var loc: Dictionary = loader.locations.get(loc_id, {}) as Dictionary
			var layer_night: bool = str(loc.get("layer", "")) == "night"
			if not is_fixed:
				problems.append("%s：charge_first_visit 要求 beat 為 fixed" % where)
			if not has_exact_day:
				problems.append("%s：charge_first_visit 要求明確整數 when.day" % where)
			if not phase_ok:
				problems.append("%s：charge_first_visit 要求 when.phase == night" % where)
			if not layer_night:
				problems.append("%s：charge_first_visit 要求所掛 location layer == night" % where)
	return problems


## 是否為整數值（JSON 數字可能是 int 或 float；8.5 這種小數不算）。
static func _is_whole_number(v: Variant) -> bool:
	if v is int:
		return true
	if v is float:
		return float(v) == floor(float(v))
	return false


static func _lint_next_round(nr: Variant, round_ids: Dictionary, where: String, problems: PackedStringArray) -> void:
	if nr == null:
		return
	if not (nr is String) or not round_ids.has(str(nr)):
		problems.append("%s：next_round 引用不存在的 round -> %s" % [where, str(nr)])


## 該 round 是否存在一條抵達 null 出口的路徑（無出口 cycle 回 false）。
static func _round_can_reach_null(rid: String, round_by_id: Dictionary, visiting: Dictionary) -> bool:
	if not round_by_id.has(rid):
		return false
	if visiting.has(rid):
		return false
	visiting[rid] = true
	var r: Dictionary = round_by_id[rid]
	for resp_vv in r.get("responses", []) as Array:
		var nr: Variant = (resp_vv as Dictionary).get("next_round")
		if nr == null:
			return true
		if _round_can_reach_null(str(nr), round_by_id, visiting):
			return true
	var fb: Dictionary = r.get("fallback", {}) as Dictionary
	var fnr: Variant = fb.get("next_round")
	if fnr == null:
		return true
	if _round_can_reach_null(str(fnr), round_by_id, visiting):
		return true
	return false


func _beat_files() -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(BEATS_DIR)
	if dir == null:
		errors.append("開不了 %s" % BEATS_DIR)
		return out
	for f in dir.get_files():
		# 匯出後 JSON 可能被加上 .remap，兩種都收
		if f.ends_with(".json"):
			out.append(BEATS_DIR + f)
		elif f.ends_with(".json.remap"):
			out.append(BEATS_DIR + f.trim_suffix(".remap"))
	out.sort()
	return out


func _read_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		errors.append("讀不到或是空的：%s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		errors.append("JSON 解析失敗：%s" % path)
		return {}
	return parsed as Dictionary
