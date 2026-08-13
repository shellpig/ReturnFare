class_name DataLoader
extends RefCounted

## 把 data/ 底下的 JSON 全部讀進來並建索引。
## 欄位定義見 data/SCHEMA.md——這裡不重複，只負責讀進來與檢查引用。

const DATA_DIR := "res://data/"
const BEATS_DIR := "res://data/beats/"

const CARD_TYPES := [
	"protagonist", "person", "group", "equipment", "consumable", "info",
	"inference", "document", "knowledge", "mood", "madness", "routine",
]

var tuning: Dictionary = {}
var cards: Dictionary = {}          ## id -> card
var locations: Dictionary = {}      ## id -> location（白天與夜間合在一起，id 全域唯一）
var npcs: Dictionary = {}           ## id -> npc
var beats: Array[Dictionary] = []
var beats_by_id: Dictionary = {}

var errors: PackedStringArray = []


func load_all() -> bool:
	errors.clear()

	tuning = _read_json(DATA_DIR + "tuning.json")

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
