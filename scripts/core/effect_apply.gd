class_name EffectApply
extends RefCounted

## on_place / on_enter 效果鍵結算（規格書第十四節、P5-B 兩階段契約）。
## 結算順序固定：text → lose → gain → switch → switch_progress → relation → madness → flag
##              → festival_proxy → ending。
## lose 先於 gain，讓「升級知識卡」不會瞬間超格；ending 永遠最後。
##
## **兩階段**（開發設計方針 P5-B）：
##   preflight(blocks, gs) 在 GameState 複本上按固定鍵序純模擬，成功回 mutation plan、
##   文字行與零／一個 ending request；真狀態零變化。
##   commit(plan, gs) 才把 plan 逐條套到真狀態上。
## 同一玩家動作（含 on_place ＋ on_place_by_level 等追加塊）產生兩個不同 ending request 時，
## preflight 回 data_conflict，呼叫端不得 commit。

const KNOWN_KEYS := [
	"text", "gain", "lose", "switch", "switch_progress", "relation", "madness", "flag",
	"festival_proxy", "ending",
]

## gain / lose 的陣列元素有兩種形態：
##   "card_id"                                → 無條件執行（既有形態，仍是預設寫法）
##   { "card": "card_id", "if": <condition>, "permanent": <bool> } → `if` 成立才執行；語彙沿用 ConditionEval，不另立
## 用途見 `data/SCHEMA.md > on_place 效果 > 帶條件的卡片項目`。
const CARD_ENTRY_KEYS := ["card", "if", "permanent"]

## beat 效果提出的 ending request 固定用這個 source；配對合法性由 GameState 驗。
const EFFECT_ENDING_SOURCE := "ending_effect"


## 純模擬：在 gs 的複本上依序跑完所有效果塊。
## 回傳：{ ok, reason_code, reason_text, lines, plan, ending_request, shadow }
## `shadow` 是模擬後的複本節點，**呼叫端負責 free()**；成功時可據以驗證 bookkeeping 與結局快照。
static func preflight(blocks: Array, gs: Node) -> Dictionary:
	var shadow: Node = gs.call("clone_for_preflight")
	var ops: Array[Dictionary] = []
	var lines := PackedStringArray()
	var ending_request: Dictionary = {}

	for block: Variant in blocks:
		if not block is Dictionary:
			continue
		var res := _simulate_block(block as Dictionary, shadow, ops, lines)
		if not bool(res.get("ok", false)):
			return _reject(shadow, str(res.get("reason_code", "data_conflict")), str(res.get("reason_text", "")))
		var req: Dictionary = res.get("ending_request", {}) as Dictionary
		if not req.is_empty():
			if not ending_request.is_empty() and ending_request != req:
				return _reject(shadow, "data_conflict", "同一動作提出兩個不同的結局")
			ending_request = req

	# 發狂上限由複本的 _check_madness_cap() 記錄，不在複本上真的啟動結局。
	var cap_request: Dictionary = shadow.get("pending_ending_request") as Dictionary
	if not cap_request.is_empty():
		if not ending_request.is_empty() and ending_request != cap_request:
			return _reject(shadow, "data_conflict", "同一動作提出兩個不同的結局")
		ending_request = cap_request

	return {
		"ok": true,
		"reason_code": "",
		"reason_text": "",
		"lines": lines,
		"plan": { "ops": ops, "lines": lines },
		"ending_request": ending_request,
		"shadow": shadow,
	}


## 把 preflight 產生的 plan 逐條套到真狀態。plan 已在複本驗過，這裡不再有可失敗的判斷。
static func commit(plan: Dictionary, gs: Node) -> Dictionary:
	var ops: Array = plan.get("ops", []) as Array
	for op_raw: Variant in ops:
		var op := op_raw as Dictionary
		_apply_op(op, gs)
	return {
		"ok": true,
		"reason_code": "",
		"reason_text": "",
		"lines": plan.get("lines", PackedStringArray()),
	}


# ── 模擬 ─────────────────────────────────────────────────────────────────────

## 單一效果塊的固定鍵序模擬。回傳 { ok, reason_code, reason_text, ending_request }。
static func _simulate_block(e: Dictionary, shadow: Node, ops: Array[Dictionary], lines: PackedStringArray) -> Dictionary:
	var text: Variant = e.get("text")
	if text is String and not (text as String).is_empty():
		lines.append(text as String)

	for entry: Variant in e.get("lose", []) as Array:
		if _entry_passes(entry, shadow):
			var op := { "op": "lose", "card": _entry_card_id(entry), "permanent": _entry_permanent(entry) }
			_apply_op(op, shadow)
			ops.append(op)

	for entry: Variant in e.get("gain", []) as Array:
		if _entry_passes(entry, shadow):
			var op := { "op": "gain", "card": _entry_card_id(entry) }
			_apply_op(op, shadow)
			ops.append(op)
	# 上限判定只在複本上做（simulation_mode 記錄 request，不啟動結局）；commit 不重複檢查。
	shadow.call("_check_madness_cap")

	if e.has("switch"):
		var op := { "op": "switch", "id": str(e["switch"]) }
		_apply_op(op, shadow)
		ops.append(op)

	if e.has("switch_progress"):
		var sp_raw: Variant = e["switch_progress"]
		if not sp_raw is Dictionary:
			return _block_fail("data_conflict", "switch_progress 必須為 Dictionary")
		for switch_id: Variant in (sp_raw as Dictionary).keys():
			var op := { "op": "switch_progress", "id": str(switch_id), "n": int((sp_raw as Dictionary)[switch_id]) }
			_apply_op(op, shadow)
			ops.append(op)

	if e.has("relation"):
		var r_raw: Variant = e["relation"]
		if not r_raw is Dictionary:
			return _block_fail("data_conflict", "relation 必須為 Dictionary")
		var r := r_raw as Dictionary
		var op := { "op": "relation", "npc": str(r.get("npc", "")), "delta": int(r.get("delta", 0)) }
		_apply_op(op, shadow)
		ops.append(op)

	if e.has("madness"):
		var op := { "op": "madness", "count": int(e["madness"]) }
		_apply_op(op, shadow)
		ops.append(op)
		shadow.call("_check_madness_cap")

	if e.has("flag"):
		var f_raw: Variant = e["flag"]
		if not f_raw is Dictionary:
			return _block_fail("data_conflict", "flag 必須為 Dictionary")
		for flag_name: Variant in (f_raw as Dictionary).keys():
			var op := { "op": "flag", "name": str(flag_name), "value": true if (f_raw as Dictionary)[flag_name] else false }
			_apply_op(op, shadow)
			ops.append(op)

	if e.has("festival_proxy"):
		var proxy_res := _resolve_festival_proxy(e["festival_proxy"], shadow)
		if not bool(proxy_res.get("ok", false)):
			return _block_fail("data_conflict", str(proxy_res.get("reason_text", "")))
		var op := { "op": "festival_proxy", "npc": str(proxy_res.get("npc", "")) }
		_apply_op(op, shadow)
		ops.append(op)

	var request: Dictionary = {}
	if e.has("ending"):
		var ending_id := str(e["ending"])
		var loader: Variant = shadow.call("loader")
		if loader == null or not (loader.endings_by_id as Dictionary).has(ending_id):
			return _block_fail("unknown_ending", "效果引用不存在的結局：%s" % ending_id)
		request = { "ending_id": ending_id, "source_id": EFFECT_ENDING_SOURCE }

	return { "ok": true, "reason_code": "", "reason_text": "", "ending_request": request }


## plan op 的唯一執行點：模擬與 commit 走同一條，避免兩份分歧的效果邏輯。
static func _apply_op(op: Dictionary, gs: Node) -> void:
	match str(op.get("op", "")):
		"lose":
			gs.call("lose_card", str(op.get("card", "")), bool(op.get("permanent", false)))
		"gain":
			# 上限由 plan 的 ending request 負責，這裡一律不重複觸發結局。
			gs.call("gain_card", str(op.get("card", "")), false)
		"switch":
			gs.call("open_switch", str(op.get("id", "")))
		"switch_progress":
			gs.call("add_switch_progress", str(op.get("id", "")), int(op.get("n", 0)))
		"relation":
			gs.call("add_relation", str(op.get("npc", "")), int(op.get("delta", 0)))
		"madness":
			for _i in range(int(op.get("count", 0))):
				gs.call("gain_card", "madness", false)
		"flag":
			gs.call("set_flag", str(op.get("name", "")), bool(op.get("value", false)))
		"festival_proxy":
			gs.call("set_festival_proxy", str(op.get("npc", "")))


## `festival_proxy` 的兩種模式都在此求值，結果寫進 plan；commit 不再重算（K-182）。
static func _resolve_festival_proxy(raw: Variant, shadow: Node) -> Dictionary:
	if not raw is Dictionary:
		return { "ok": false, "reason_text": "festival_proxy 必須為 Dictionary" }
	var cfg := raw as Dictionary
	var loader: Variant = shadow.call("loader")
	if loader == null:
		return { "ok": false, "reason_text": "資料未載入" }

	if not str(shadow.get("selected_festival_proxy_npc")).is_empty():
		return { "ok": false, "reason_text": "慶典代付者已凍結，不得覆寫" }

	var mode := str(cfg.get("mode", ""))
	if mode == "fixed":
		var npc_id := str(cfg.get("npc", ""))
		if not _is_eligible(loader, npc_id):
			return { "ok": false, "reason_text": "fixed 引用非慶典候選 NPC：%s" % npc_id }
		return { "ok": true, "npc": npc_id }

	if mode == "highest_eligible":
		var fallback := str(cfg.get("fallback", ""))
		if not _is_eligible(loader, fallback):
			return { "ok": false, "reason_text": "fallback 引用非慶典候選 NPC：%s" % fallback }
		var counts: Dictionary = shadow.get("npc_action_counts") as Dictionary
		var best := ""
		var best_count := 0
		for npc_id: Variant in (loader.npcs as Dictionary).keys():
			var npc_str := str(npc_id)
			if not _is_eligible(loader, npc_str):
				continue
			var c := int(counts.get(npc_str, 0))
			if c > best_count:
				best_count = c
				best = npc_str
		if best.is_empty():
			return { "ok": true, "npc": fallback }
		return { "ok": true, "npc": best }

	return { "ok": false, "reason_text": "未知的 festival_proxy mode：%s" % mode }


static func _is_eligible(loader: Variant, npc_id: String) -> bool:
	if npc_id.is_empty() or not (loader.npcs as Dictionary).has(npc_id):
		return false
	return (loader.npcs[npc_id] as Dictionary).get("festival_proxy_eligible", false) == true


static func _reject(shadow: Node, code: String, text: String) -> Dictionary:
	if shadow != null:
		shadow.free()
	return {
		"ok": false,
		"reason_code": code,
		"reason_text": text,
		"lines": PackedStringArray(),
		"plan": {},
		"ending_request": {},
		"shadow": null,
	}


static func _block_fail(code: String, text: String) -> Dictionary:
	return { "ok": false, "reason_code": code, "reason_text": text, "ending_request": {} }


## 卡片項目的永久旗標：只有物件形態的 `permanent:true` 才成立。
## 語意由 GameState 執行——只有 `loop_persistent:true` 卡才真的從 meta set 移除。
static func _entry_permanent(entry: Variant) -> bool:
	if entry is Dictionary:
		return (entry as Dictionary).get("permanent", false) == true
	return false


## 卡片項目的 id：字串形態直接回傳，物件形態取 `card`。
static func _entry_card_id(entry: Variant) -> String:
	if entry is Dictionary:
		return str((entry as Dictionary).get("card", ""))
	return str(entry)


## 卡片項目的守衛：字串形態恆成立；物件形態求值 `if`（缺 `if` 亦恆成立，同 ConditionEval 契約）。
## 逐項求值而非整塊求值——同一個效果塊裡其他鍵（例如 flag）不受影響。
static func _entry_passes(entry: Variant, gs: Node) -> bool:
	if not entry is Dictionary:
		return true
	return ConditionEval.eval((entry as Dictionary).get("if"), gs)
