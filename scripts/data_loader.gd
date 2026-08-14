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
			if beats_by_id.has(b["id"]):
				errors.append("beat id 重複：%s" % b["id"])
			beats_by_id[b["id"]] = b
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

		for s in b.get("slots", []):
			var where := "slot:" + str(s.get("id", "?"))
			_check_card_refs(s.get("requires"), bid, where, problems)
			_check_card_refs(s.get("on_place"), bid, where, problems)
			for a in s.get("accepts", []):
				if not cards.has(a) and not CARD_TYPES.has(a):
					problems.append("%s [%s]：accepts 既不是卡也不是 type → %s" % [bid, where, a])

	return problems


func _check_card_refs(node: Variant, bid: String, where: String, problems: PackedStringArray) -> void:
	if node is Dictionary:
		for k in node.keys():
			var v: Variant = node[k]
			match k:
				"gain", "lose":
					for c in v:
						if not cards.has(c):
							problems.append("%s [%s]：%s 引用不存在的卡 → %s" % [bid, where, k, c])
				"has_card", "has_knowledge":
					if not cards.has(v):
						problems.append("%s [%s]：%s 不存在 → %s" % [bid, where, k, v])
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
	for b in beats_list:
		var bid: String = str(b.get("id", "?"))
		for s: Dictionary in b.get("slots", []) as Array:
			var cg: Variant = s.get("choice_group")
			var is_choice := cg != null and not str(cg).is_empty()
			var accepts: Array = s.get("accepts", []) as Array
			if is_choice and accepts.has("protagonist"):
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
		var phase_str: String = str((w as Dictionary).get("phase", ""))
		if phase_str in ["morning", "afternoon"]:
			var loc_id: String = str(b.get("location", ""))
			var loc: Dictionary = loader.locations.get(loc_id, {}) as Dictionary
			var loc_phases: Array = loc.get("phases", []) as Array
			if not loc_phases.has(phase_str):
				errs.append("%s：beat 時段為 %s，但所屬地點 %s 的 phases 僅有 %s" % [
					str(b.get("id", "")), phase_str, loc_id, str(loc_phases)
				])

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


## 某一天某個時段有哪些 beat（不解 condition，只挑時間對的）。
func beats_at(day: int, phase: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in beats:
		var w: Dictionary = b.get("when", {})
		if w.get("day", -1) == day and w.get("phase", "") == phase:
			out.append(b)
	return out


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
