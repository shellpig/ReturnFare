class_name EndingResolver
extends RefCounted

## 結局資料規則求值器（規格書 P5-B／P5-C、開發設計方針 P5-B）。
## 只做 variant 選擇、lookup fragment 命中與 page ref 組裝；不寫 GameState、不 import scene。
##
## page ref 形狀見 `data/SCHEMA.md > endings.json`：每一段都是既有 id，不含陣列 index。
##   ending_replaced/first_seen/prefix_pages/replacement
##   ending_replaced/first_seen/variant_groups/partner/ajie/partner_ajie_long
##   ending_replaced/repeat/lookup_fragments/uninvited_proxy/acai/proxy_acai_short
##   ending_madness_be/first_seen/pages/madness_lost

const BRANCH_FIRST := "first_seen"
const BRANCH_REPEAT := "repeat"
const SKIP_COMPLETE := "complete"

## `source_field` → GameState 上的凍結欄位。P5 封閉值只有一組。
const SOURCE_FIELD_PROPERTIES := {
	"festival_proxy_npc": "selected_festival_proxy_npc",
}


## 求出本次結局的 variant、lookup 片段與有序 page refs。
## 回傳：{ ok, reason_code, branch, variants: Dictionary, page_refs: Array[String] }
## `variants` 的鍵是資料上的 `history_field`；linear ending 回空字典。
## 失敗只回 `unknown_ending` 或 `data_conflict`，不自行猜測缺漏的資料。
static func resolve(ending_id: String, gs: Node, loader) -> Dictionary:
	if loader == null:
		return _fail("data_conflict")

	var ending: Dictionary = loader.endings_by_id.get(ending_id, {}) as Dictionary
	if ending.is_empty():
		return _fail("unknown_ending")

	var is_first_seen := not bool(gs.call("has_seen_ending", ending_id))
	var branch := BRANCH_FIRST if is_first_seen else BRANCH_REPEAT
	var branch_raw: Variant = ending.get(branch)
	if not branch_raw is Dictionary:
		return _fail("data_conflict")
	var branch_data := branch_raw as Dictionary

	var refs: Array[String] = []
	var variants: Dictionary = {}
	var kind := str(ending.get("kind", ""))

	if kind == "linear":
		if not _append_pages(refs, branch_data.get("pages"), "%s/%s/pages/" % [ending_id, branch]):
			return _fail("data_conflict")

	elif kind == "composite":
		if not _append_pages(refs, branch_data.get("prefix_pages"), "%s/%s/prefix_pages/" % [ending_id, branch]):
			return _fail("data_conflict")

		var chosen_by_group: Dictionary = {}
		var groups_raw: Variant = ending.get("variant_groups")
		if not groups_raw is Array:
			return _fail("data_conflict")
		for vg_raw: Variant in groups_raw as Array:
			if not vg_raw is Dictionary:
				return _fail("data_conflict")
			var vg := vg_raw as Dictionary
			var group_id := str(vg.get("id", ""))
			var history_field := str(vg.get("history_field", ""))
			if group_id.is_empty() or history_field.is_empty():
				return _fail("data_conflict")

			var rule := _pick_rule(vg.get("rules"), gs)
			if rule.is_empty():
				return _fail("data_conflict")
			var rule_id := str(rule.get("id", ""))
			if rule_id.is_empty():
				return _fail("data_conflict")

			variants[history_field] = rule_id
			chosen_by_group[group_id] = rule_id
			if not _append_pages(refs, rule.get(_variant_page_key(is_first_seen)),
					"%s/%s/variant_groups/%s/%s/" % [ending_id, branch, group_id, rule_id]):
				return _fail("data_conflict")

		var fragments_raw: Variant = ending.get("lookup_fragments")
		if fragments_raw is Array:
			for lf_raw: Variant in fragments_raw as Array:
				if not lf_raw is Dictionary:
					return _fail("data_conflict")
				var lf := lf_raw as Dictionary
				var lf_id := str(lf.get("id", ""))
				var when_group_raw: Variant = lf.get("when_group")
				if lf_id.is_empty() or not when_group_raw is Dictionary:
					return _fail("data_conflict")
				var when_group := when_group_raw as Dictionary
				var wg_group := str(when_group.get("group", ""))
				var wg_variant := str(when_group.get("variant", ""))
				if not chosen_by_group.has(wg_group):
					return _fail("data_conflict")
				if str(chosen_by_group[wg_group]) != wg_variant:
					continue

				var source_field := str(lf.get("source_field", ""))
				if not SOURCE_FIELD_PROPERTIES.has(source_field):
					return _fail("data_conflict")
				var lookup_value := str(gs.get(str(SOURCE_FIELD_PROPERTIES[source_field])))
				if lookup_value.is_empty():
					return _fail("data_conflict")

				var entry := _find_entry(lf.get("entries"), lookup_value)
				if entry.is_empty():
					return _fail("data_conflict")
				if not _append_pages(refs, entry.get(_variant_page_key(is_first_seen)),
						"%s/%s/lookup_fragments/%s/%s/" % [ending_id, branch, lf_id, lookup_value]):
					return _fail("data_conflict")

		if not _append_pages(refs, branch_data.get("suffix_pages"), "%s/%s/suffix_pages/" % [ending_id, branch]):
			return _fail("data_conflict")

	else:
		return _fail("data_conflict")

	if refs.is_empty():
		return _fail("data_conflict")

	return {
		"ok": true,
		"reason_code": "",
		"branch": branch,
		"variants": variants,
		"page_refs": refs,
	}


## 解析 page ref 回玩家可見文字。ref 失效一律回 ok:false，不得當成空白頁跳過。
## 回傳：{ ok, text, page_id }
static func resolve_ref(ref: String, loader) -> Dictionary:
	var miss := { "ok": false, "text": "", "page_id": "" }
	if loader == null or ref.is_empty():
		return miss
	var parts := ref.split("/")
	if parts.size() < 4:
		return miss

	var ending: Dictionary = loader.endings_by_id.get(parts[0], {}) as Dictionary
	if ending.is_empty():
		return miss
	var branch := parts[1]
	if branch != BRANCH_FIRST and branch != BRANCH_REPEAT:
		return miss
	var branch_raw: Variant = ending.get(branch)
	if not branch_raw is Dictionary:
		return miss
	var branch_data := branch_raw as Dictionary
	var container := parts[2]

	if container == "pages" or container == "prefix_pages" or container == "suffix_pages":
		if parts.size() != 4:
			return miss
		return _find_page(branch_data.get(container), parts[3])

	if container == "variant_groups":
		if parts.size() != 6:
			return miss
		var group := _find_by_id(ending.get("variant_groups"), parts[3])
		if group.is_empty():
			return miss
		var rule := _find_by_id(group.get("rules"), parts[4])
		if rule.is_empty():
			return miss
		return _find_page(rule.get(_variant_page_key(branch == BRANCH_FIRST)), parts[5])

	if container == "lookup_fragments":
		if parts.size() != 6:
			return miss
		var fragment := _find_by_id(ending.get("lookup_fragments"), parts[3])
		if fragment.is_empty():
			return miss
		var entry := _find_entry(fragment.get("entries"), parts[4])
		if entry.is_empty():
			return miss
		return _find_page(entry.get(_variant_page_key(branch == BRANCH_FIRST)), parts[5])

	return miss


## 重見時資料明示的跳過落點：repeat page id 或字面值 "complete"。
## 首見不提供跳過，因此本函式只讀 repeat 分支。
static func skip_target(ending_id: String, loader) -> String:
	if loader == null:
		return ""
	var ending: Dictionary = loader.endings_by_id.get(ending_id, {}) as Dictionary
	var repeat_raw: Variant = ending.get(BRANCH_REPEAT)
	if not repeat_raw is Dictionary:
		return ""
	return str((repeat_raw as Dictionary).get("skip_to", ""))


## ref 的最後一段就是 page id（page id 本身不得含斜線，由 lint 17 保證）。
static func page_id_of(ref: String) -> String:
	var parts := ref.split("/")
	if parts.is_empty():
		return ""
	return parts[parts.size() - 1]


# ── 內部工具 ─────────────────────────────────────────────────────────────────

static func _fail(code: String) -> Dictionary:
	return { "ok": false, "reason_code": code, "branch": "", "variants": {}, "page_refs": [] as Array[String] }


static func _variant_page_key(is_first_seen: bool) -> String:
	return "first_seen_pages" if is_first_seen else "repeat_pages"


## 把 pages 陣列串成 ref 附加到 refs。空陣列合法（該維度不貢獻頁面）；非陣列或壞 page 回 false。
static func _append_pages(refs: Array[String], pages_raw: Variant, prefix: String) -> bool:
	if not pages_raw is Array:
		return false
	for page_raw: Variant in pages_raw as Array:
		if not page_raw is Dictionary:
			return false
		var page := page_raw as Dictionary
		var page_id := str(page.get("id", ""))
		var text := str(page.get("text", ""))
		if page_id.is_empty() or text.strip_edges().is_empty():
			return false
		refs.append(prefix + page_id)
	return true


## 依資料順序取第一個 when 成立的 rule；都不成立才用 fallback。
## 嚴格要求 rules 必須恰有一個 fallback，且所有項目形狀合法；違反直接回 {} (data_conflict)。
static func _pick_rule(rules_raw: Variant, gs: Node) -> Dictionary:
	if not rules_raw is Array or (rules_raw as Array).is_empty():
		return {}
	var fallback: Dictionary = {}
	var fallback_count := 0
	var matched: Dictionary = {}

	for rule_raw: Variant in rules_raw as Array:
		if not rule_raw is Dictionary:
			return {}
		var rule := rule_raw as Dictionary
		var is_fb: bool = rule.get("fallback", false) == true
		if is_fb:
			fallback_count += 1
			if rule.has("when"):
				return {}
			fallback = rule
		else:
			if not rule.has("when"):
				return {}
			if matched.is_empty() and ConditionEval.eval(rule.get("when"), gs):
				matched = rule

	if fallback_count != 1:
		return {}

	return matched if not matched.is_empty() else fallback


static func _find_entry(entries_raw: Variant, value: String) -> Dictionary:
	if not entries_raw is Array:
		return {}
	for entry_raw: Variant in entries_raw as Array:
		if entry_raw is Dictionary and str((entry_raw as Dictionary).get("value", "")) == value:
			return entry_raw as Dictionary
	return {}


static func _find_by_id(list_raw: Variant, id: String) -> Dictionary:
	if not list_raw is Array:
		return {}
	for item_raw: Variant in list_raw as Array:
		if item_raw is Dictionary and str((item_raw as Dictionary).get("id", "")) == id:
			return item_raw as Dictionary
	return {}


static func _find_page(pages_raw: Variant, page_id: String) -> Dictionary:
	if not pages_raw is Array:
		return { "ok": false, "text": "", "page_id": "" }
	for page_raw: Variant in pages_raw as Array:
		if not page_raw is Dictionary:
			continue
		var page := page_raw as Dictionary
		if str(page.get("id", "")) != page_id:
			continue
		var text := str(page.get("text", ""))
		if text.strip_edges().is_empty():
			return { "ok": false, "text": "", "page_id": "" }
		return { "ok": true, "text": text, "page_id": page_id }
	return { "ok": false, "text": "", "page_id": "" }
