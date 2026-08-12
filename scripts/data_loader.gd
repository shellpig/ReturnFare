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
