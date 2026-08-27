extends Node

## GameState autoload: 全部 runtime 狀態的唯一容器（規格書第一節）。
## P1-A：時間群與序列化骨架。
## P1-B：手牌群（hand / knowledge / madness_clock）。
## P1-C：beat 事件群（beats_entered / slots_placed / enter_beat）。
## P1-D：旗標／開關／關係群、放置與效果結算（try_place）、行動格消耗。

const DataFacts := preload("res://scripts/core/data_facts.gd")
const Indulgence := preload("res://scripts/core/indulgence.gd")
const Encounter := preload("res://scripts/core/encounter.gd")

const CHAPTER_START_DAYS := DataFacts.CHAPTER_START_DAYS
const LAST_DAY := 45
const PHASES := ["morning", "afternoon", "evening", "night"]
const ACTION_PHASES := ["morning", "afternoon"]

# --- 時間群（run 層）---
var day: int = 1
var phase: String = "morning"

# --- 手牌群 ---
var hand: Array[String] = []          # 佔格卡 id，有序；主角卡恆在 index 0（run 層）
var knowledge: Dictionary = {}        # id -> true（Set；slotless 卡；meta 層，不隨輪重置）
var night_locations_seen: Dictionary = {} # location_id -> true（meta 層，不隨輪重置）
var night_once_beats_seen: Dictionary = {} # beat_id -> true（meta 層，不隨輪重置）
var delegation_tutorial_seen: bool = false # 委託教學是否已由 UI 顯示並關閉／略過（meta 層，不隨輪重置，P4-C）
var madness_clock: Dictionary = {}    # 實例 id -> 剩餘天數（P1 只建結構，P2 才走錶；run 層）
var _madness_counter: int = 0         # 實例編號計數器（run 層）

# --- Beat 事件群（P1-C, run 層）---
var beats_entered: Dictionary = {}    # beat_id -> true（一次性 on_enter 追蹤）
var slots_placed: Dictionary = {}     # "beat_id::slot_id" -> true（P1-D 填入，P1-C 保留空結構）
var choices: Dictionary = {}          # "beat_id::group_id" -> slot_id（P1-E 互斥選擇記錄，run 層）

# --- 委託群（P4-B, run 層）---
var delegates_used_today: Dictionary = {}         # person_card_id -> true（Set；今日已受託人物）
var pending_delegation_reports: Array[Dictionary] = [] # [{due_day, beat_id, slot_id, person_id}]；隔日上午回報接點
var last_delegation_report_lines: PackedStringArray = [] # 當前上午回報產生的演出文字行（transient UI）

# --- 遭遇群（P4-D, run 層）---
var active_encounter: Dictionary = {} # 空＝無遭遇；非空含 beat_id, stage, round_id, blocked_slots, attempted_card_ids

# --- 旗標／開關／關係群（P1-D, run 層）---
var flags: Dictionary = {}            # name -> bool
var switches: Dictionary = {}         # id -> true
var switch_progress: Dictionary = {}  # id -> int（累計型開關）
var relations: Dictionary = {}        # npc -> int（單軸整數暫行案，規格書第十二節）

# --- 其他群 ---
var action_spent: bool = false                 # 當前行動格是否已放過主角卡（run 層）
var _actions_spent_ahead: int = 0              # 預先消耗之當日後續行動格數（泡湯特例／順延，run 層）
var npc_action_counts: Dictionary = {}         # npc_id -> 本輪投入的主角行動數（run 層，規格書第十二節）
var night_location_chosen: String = ""         # 當夜已選定的夜間地點 id（run 層，每夜重置，規格書第九節）
var night_sleep_pending: bool = false          # 當夜是否已播完直接睡內容停在「進入隔天」（run 層，每夜重置）
var indulgence_count: int = 0                  # 本輪縱慾次數（主動＋強制合計，run 層）
var madness_cards_cleared: int = 0             # 本輪消除的發狂卡張數累計（run 層，避免依賴縱慾次數換算卡數）
var forced_pending: Array[String] = []         # 已歸零、還沒吃到行動格的發狂卡實例 id（run 層）
var last_forced_lines: PackedStringArray = []  # 當前時段強制縱慾產生的演出文字行（transient UI）
var run_generation: int = 0                    # 輪次世代計數（單調遞增，供 EffectApply 與結算器偵測 end_run）

signal phase_changed(day: int, phase: String)
signal day_changed(day: int)
signal chapter_changed(chapter: int)
signal run_ended(ending_id: String)
signal hand_changed
signal knowledge_changed
signal delegation_tutorial_available # P4-C：玩家首次由零張變一張 person card 時發出，UI 顯示並關閉／略過後才呼叫 mark_delegation_tutorial_seen()


# ── 時段狀態機 ──────────────────────────────────────────────────────────────

func chapter() -> int:
	return DataFacts.chapter_for_day(day)


func advance_phase() -> Dictionary:
	if not active_encounter.is_empty():
		return { "ok": false, "reason_code": "encounter_active", "reason_text": "遭遇進行中，無法推進時段", "lines": PackedStringArray(), "phase_advanced": false }

	var prev_ch := chapter()

	# 第 45 天特殊路徑：afternoon → evening（結局 coda）→ end_run 回第 1 天 morning，不進 night
	if day == LAST_DAY and phase == "afternoon":
		phase = "evening"
		action_spent = false
		last_forced_lines.clear()
		last_delegation_report_lines.clear()
		_check_fixed_encounter_for_current_phase()
		phase_changed.emit(day, phase)
		return { "ok": true, "reason_code": "", "reason_text": "", "lines": PackedStringArray(), "phase_advanced": true }

	if day == LAST_DAY and phase == "evening":
		end_run("ending_default")
		return { "ok": true, "reason_code": "", "reason_text": "", "lines": PackedStringArray(), "phase_advanced": false }

	last_forced_lines.clear()
	last_delegation_report_lines.clear()

	# 一般推進
	var idx := PHASES.find(phase)
	if idx < PHASES.size() - 1:
		phase = PHASES[idx + 1]
	else:
		# night → 次日 morning
		day += 1
		phase = PHASES[0]
		day_changed.emit(day)
		var zeroed := tick_madness()
		for inst_id: String in zeroed:
			forced_pending.append(inst_id)

	if _actions_spent_ahead > 0 and ACTION_PHASES.has(phase):
		_actions_spent_ahead -= 1
		action_spent = true
	else:
		action_spent = false

	if not ACTION_PHASES.has(phase):
		_actions_spent_ahead = 0

	night_location_chosen = ""
	night_sleep_pending = false

	# P2-C: 行動時段開始時執行強制縱慾（每個行動時段最多一次）
	if ACTION_PHASES.has(phase) and not action_spent and not forced_pending.is_empty():
		last_forced_lines = _settle_forced_indulgence()

	# P4-B: 換日上午先完成既有發狂倒數／強制縱慾，再依 pending 順序回查並套 report，最後清前一日 daily set
	if phase == "morning":
		_settle_pending_delegation_reports()
		delegates_used_today.clear()

	_check_fixed_encounter_for_current_phase()

	phase_changed.emit(day, phase)

	var new_ch := chapter()
	if new_ch != prev_ch:
		chapter_changed.emit(new_ch)

	return { "ok": true, "reason_code": "", "reason_text": "", "lines": PackedStringArray(), "phase_advanced": true }


## 輪結束結算與迴圈重置（規格書第十六節、P1-F、B-02）。
## 順序固定：發射 run_ended -> meta 層保留 -> run 層重置 -> 回第 1 天 morning。
func end_run(ending_id: String = "ending_default") -> void:
	run_generation += 1
	run_ended.emit(ending_id)

	day = 1
	phase = PHASES[0]
	action_spent = false
	_actions_spent_ahead = 0
	hand.clear()
	hand.append("protagonist")
	flags.clear()
	switches.clear()
	switch_progress.clear()
	relations.clear()
	slots_placed.clear()
	choices.clear()
	beats_entered.clear()
	npc_action_counts.clear()
	madness_clock.clear()
	_madness_counter = 0
	night_location_chosen = ""
	night_sleep_pending = false
	indulgence_count = 0
	madness_cards_cleared = 0
	forced_pending.clear()
	last_forced_lines.clear()
	delegates_used_today.clear()
	pending_delegation_reports.clear()
	last_delegation_report_lines.clear()
	active_encounter.clear()

	day_changed.emit(day)
	phase_changed.emit(day, phase)
	chapter_changed.emit(chapter())
	hand_changed.emit()


## 晚間演出規則層唯一入口（UI、走查腳本、測試共用，規格書第十一節、K-26）。
## 依序：
## 1. 依陣列順序結算當日 evening fixed beat 之 play_beat()
## 2. 掃描當日成立之殘響（echo.day == day）並收集文字
## 回傳全部要播放的文字行（PackedStringArray）。
func play_evening() -> PackedStringArray:
	var lines := PackedStringArray()
	if Data == null or Data.loader == null:
		return lines

	var cur_day: int = day

	# 1. 當日 evening fixed beats（依陣列順序，保證連鎖條件如 d27 正確生效）
	for b in Data.loader.beats_at(cur_day, "evening"):
		if not b.get("fixed", false):
			continue
		if ConditionEval.eval(b.get("condition"), self) and ConditionEval.eval(b.get("requires"), self):
			var beat_lines := play_beat(str(b.get("id", "")))
			lines.append_array(beat_lines)

	# 2. 當日殘響
	for b in Data.loader.beats:
		var echo_raw: Variant = b.get("echo")
		if not echo_raw is Dictionary:
			continue
		var echo := echo_raw as Dictionary
		if int(echo.get("day", -1)) != cur_day:
			continue
		if ConditionEval.eval(echo.get("condition"), self) and ConditionEval.eval(echo.get("requires"), self):
			var text: String = str(echo.get("text", "")).strip_edges()
			if not text.is_empty():
				lines.append(text)

	return lines


## 夜間固定演出規則層唯一入口（UI、走查腳本、測試共用，規格書第九節、P3-C）。
## 遇 meta_once 且已在 night_once_beats_seen 則跳過；首次先記 seen 再播放。
## 若掛 night-layer 地點，呼叫 _record_forced_night_visit() 記錄 chosen 與 seen。
## 非 meta_once fixed 遇本輪 beats_entered 已有 id 時跳過（避免 route 重建重複播放）。
func play_night_fixed() -> PackedStringArray:
	var lines := PackedStringArray()
	if Data == null or Data.loader == null:
		return lines

	var cur_day: int = day
	for b in Data.loader.beats_at(cur_day, "night"):
		if not bool(b.get("fixed", false)):
			continue
		var bid := str(b.get("id", ""))
		var is_meta_once := bool(b.get("meta_once", false))
		if is_meta_once:
			if night_once_beats_seen.has(bid):
				continue
		else:
			if beats_entered.has(bid):
				continue

		if ConditionEval.eval(b.get("condition"), self) and ConditionEval.eval(b.get("requires"), self):
			var loc_id := str(b.get("location", ""))
			if Data != null and Data.loader != null and Data.loader.locations.has(loc_id):
				var loc: Dictionary = Data.loader.locations[loc_id] as Dictionary
				if str(loc.get("layer", "")) == "night":
					var was_seen_cfv := night_locations_seen.has(loc_id)
					if not _record_forced_night_visit(loc_id):
						continue
					# charge_first_visit 遭遇（P4-A、SCHEMA encounter.charge_first_visit）：
					# 強制到訪前先保存是否終身 seen，只有此前未 seen 才按 location madness_cost 收一次。
					var enc_cfv: Variant = b.get("encounter")
					if enc_cfv is Dictionary and bool((enc_cfv as Dictionary).get("charge_first_visit", false)) and not was_seen_cfv:
						var cost_cfv := int(loc.get("madness_cost", 0))
						if cost_cfv > 0:
							for _i_cfv in range(cost_cfv):
								gain_card("madness", false)
							_check_madness_cap()
							# 首次收費若觸發發瘋 BE，end_run() 已重置本輪（phase 回 morning）；
							# 不可再 play_beat 本 beat，否則把文字/beats_entered 寫進重置後的新輪。
							if phase != "night":
								return lines
			if is_meta_once:
				night_once_beats_seen[bid] = true
			var beat_lines := play_beat(bid)
			lines.append_array(beat_lines)
			if b.has("encounter") and not (b.get("encounter") as Dictionary).is_empty():
				start_encounter(bid)
				# 遭遇啟動後不再播同夜後續 fixed beat：與 _check_fixed_encounter_for_current_phase()
				# 的白天路徑對齊，避免遭遇畫面已開、底下仍附加下一段旁白。
				break

	return lines


## 取得地點在夜間的有狀態解析內容（P3-C，唯一求值入口）。
## condition 成立之首個 primary 勝出（若定日不成立則退回章節變體）；addons 保留 condition 成立者。
## requires 不參與候選選擇，不成立仍為選中之 LOCKED 內容。
## 回傳：{ "primary": Dictionary, "addons": Array[Dictionary] }
func resolved_night_content(location_id: String) -> Dictionary:
	var primary: Dictionary = {}
	var addons: Array[Dictionary] = []

	if Data == null or Data.loader == null:
		return { "primary": primary, "addons": addons }

	var candidates: Dictionary = Data.loader.night_beat_candidates(day, location_id, chapter())

	for cand: Dictionary in candidates.get("primaries", []) as Array:
		if ConditionEval.eval(cand.get("condition"), self):
			primary = cand
			break

	for addon_cand: Dictionary in candidates.get("addons", []) as Array:
		if ConditionEval.eval(addon_cand.get("condition"), self):
			addons.append(addon_cand)

	return {
		"primary": primary,
		"addons": addons,
	}


## 檢查當前時段是否有應啟動的 fixed encounter（規格書第十三節、P4-D）。
func _check_fixed_encounter_for_current_phase() -> void:
	if Data == null or Data.loader == null:
		return
	if not active_encounter.is_empty():
		return
	if phase == "night":
		return
	for b in Data.loader.beats_at(day, phase):
		if not bool(b.get("fixed", false)):
			continue
		if not b.has("encounter"):
			continue
		var enc: Dictionary = b.get("encounter", {}) as Dictionary
		if enc.is_empty():
			continue
		var bid := str(b.get("id", ""))
		var is_meta_once := bool(b.get("meta_once", false))
		if is_meta_once and night_once_beats_seen.has(bid):
			continue
		if ConditionEval.eval(b.get("condition"), self) and ConditionEval.eval(b.get("requires"), self):
			start_encounter(bid)
			break


## 直接睡＝解析旅館（sanquan）的夜間內容（規格書第九節、P3-C）。
## 面板與睡覺共用 resolved_night_content("sanquan")；睡覺跳過 requires 不成立的內容。
func sleep_night() -> PackedStringArray:
	var lines := PackedStringArray()
	if not active_encounter.is_empty():
		return lines
	var resolved := resolved_night_content("sanquan")
	var primary: Dictionary = resolved.get("primary", {})
	if not primary.is_empty():
		if ConditionEval.eval(primary.get("requires"), self):
			var beat_lines := play_beat(str(primary.get("id", "")))
			lines.append_array(beat_lines)

	for addon in resolved.get("addons", []) as Array:
		if addon is Dictionary and not (addon as Dictionary).is_empty():
			if ConditionEval.eval((addon as Dictionary).get("requires"), self):
				var addon_lines := play_beat(str((addon as Dictionary).get("id", "")))
				lines.append_array(addon_lines)

	return lines


## 夜間推進唯一決策入口（P3-C，main.gd 與走查共用）。
## 回傳：{ "advance": bool, "lines": PackedStringArray }
func resolve_night_advance() -> Dictionary:
	if not active_encounter.is_empty():
		return { "advance": false, "lines": PackedStringArray(), "reason_code": "encounter_active" }

	if not night_location_chosen.is_empty():
		return { "advance": true, "lines": PackedStringArray() }

	if night_sleep_pending:
		night_sleep_pending = false
		return { "advance": true, "lines": PackedStringArray() }

	var lines := sleep_night()
	if lines.size() > 0:
		night_sleep_pending = true
		return { "advance": false, "lines": lines }

	return { "advance": true, "lines": PackedStringArray() }


## 查詢該夜間地點是否已曾到訪（規格書第九節、P3-B）。
func night_location_seen(location_id: String) -> bool:
	return night_locations_seen.has(location_id)


## 進入夜間地點唯一原子入口（規格書第九節、P3-B）。
## 拒絕順序固定：
## 1. not_night: phase != "night"
## 2. encounter_active: not active_encounter.is_empty()（P4-D）
## 3. overloaded: is_overloaded()（P4-D）
## 4. unknown_location: location 不存在
## 5. not_night_layer: location.layer != "night"
## 6. teaser: bool(loc.teaser_only)
## 7. too_early: day < earliest_night
## 8. locked: loc.requires 不成立（附 reject_reason）
## 9. already_chosen: night_location_chosen 非空
## 10. already_slept: night_sleep_pending 為真
## 任一步未過回 { "ok": false, "reason_code": code, "reason_text": text, "lines": [] }，狀態零變化。
## 成功：寫 chosen -> 寫 meta seen -> 首次 paid 則發卡 + 批次 check cap -> 回傳提示文字（未結束本輪才回傳）。
func enter_night_location(location_id: String) -> Dictionary:
	if phase != "night":
		return { "ok": false, "reason_code": "not_night", "reason_text": "", "lines": PackedStringArray() }

	if not active_encounter.is_empty():
		return { "ok": false, "reason_code": "encounter_active", "reason_text": "遭遇進行中，無法進入地點", "lines": PackedStringArray() }

	if is_overloaded():
		return { "ok": false, "reason_code": "overloaded", "reason_text": "手牌超載，無法進入夜間地點", "lines": PackedStringArray() }

	if Data == null or Data.loader == null or not Data.loader.locations.has(location_id):
		return { "ok": false, "reason_code": "unknown_location", "reason_text": "", "lines": PackedStringArray() }

	var loc: Dictionary = Data.loader.locations.get(location_id, {}) as Dictionary
	if str(loc.get("layer", "")) != "night":
		return { "ok": false, "reason_code": "not_night_layer", "reason_text": "", "lines": PackedStringArray() }

	if bool(loc.get("teaser_only", false)):
		return { "ok": false, "reason_code": "teaser", "reason_text": "", "lines": PackedStringArray() }

	if day < int(loc.get("earliest_night", 1)):
		return { "ok": false, "reason_code": "too_early", "reason_text": "", "lines": PackedStringArray() }

	if loc.has("requires") and not ConditionEval.eval(loc["requires"], self):
		return { "ok": false, "reason_code": "locked", "reason_text": str(loc.get("reject_reason", "")), "lines": PackedStringArray() }

	if not night_location_chosen.is_empty():
		return { "ok": false, "reason_code": "already_chosen", "reason_text": "", "lines": PackedStringArray() }

	if night_sleep_pending:
		return { "ok": false, "reason_code": "already_slept", "reason_text": "", "lines": PackedStringArray() }

	night_location_chosen = location_id
	var is_first_time: bool = not night_locations_seen.has(location_id)
	var will_end_run: bool = would_night_entry_end_run(location_id)
	night_locations_seen[location_id] = true

	var lines := PackedStringArray()
	if is_first_time:
		var cost: int = int(loc.get("madness_cost", 0))
		if cost > 0:
			for i in range(cost):
				gain_card("madness", false)
			_check_madness_cap()
			if not will_end_run:
				lines.append("推開了夜色深處的門。獲得 %d 張發狂卡。" % cost)

	return { "ok": true, "reason_code": "", "reason_text": "", "lines": lines }


## 白天地點對位確認的唯一規則層入口（規格書第十七節、P3-E）。
## 回傳：{ "ok": bool, "reason_code": String, "reason_text": String, "knowledge_id": String }
## 六碼封閉拒絕矩陣（依序優先）：
## 1. not_day_phase: phase != "morning" and phase != "afternoon"
## 2. unknown_location: day_location_id 不在 locations.json
## 3. not_day_layer: location.layer == "night"
## 4. no_seen_row: 該白天地點對應的夜間 row 一個都未在 night_locations_seen 中
## 5. data_conflict: 已到訪 row 之 night_reveal 存在衝突或遺失（同時 push_error）
## 6. already_known: 對應之知識卡已在 knowledge 集合中
## 拒絕時完整狀態零變化；成功時呼叫 gain_card(knowledge_id)，不消耗行動格。
func confirm_night_alignment(day_location_id: String) -> Dictionary:
	if phase != "morning" and phase != "afternoon":
		return { "ok": false, "reason_code": "not_day_phase", "reason_text": "", "knowledge_id": "" }

	if not active_encounter.is_empty():
		return { "ok": false, "reason_code": "encounter_active", "reason_text": "遭遇進行中，無法對位", "knowledge_id": "" }

	if Data == null or Data.loader == null or not Data.loader.locations.has(day_location_id):
		return { "ok": false, "reason_code": "unknown_location", "reason_text": "", "knowledge_id": "" }

	var day_loc: Dictionary = Data.loader.locations.get(day_location_id, {}) as Dictionary
	if str(day_loc.get("layer", "")) == "night":
		return { "ok": false, "reason_code": "not_day_layer", "reason_text": "", "knowledge_id": "" }

	var seen_night_ids: Array[String] = []
	var reveals: Array[String] = []

	for lid: String in Data.loader.locations:
		var loc: Dictionary = Data.loader.locations[lid] as Dictionary
		if str(loc.get("layer", "")) == "night" and str(loc.get("day_counterpart", "")) == day_location_id:
			if night_locations_seen.has(lid):
				seen_night_ids.append(lid)
				var rev_val: Variant = loc.get("night_reveal")
				if rev_val != null and not str(rev_val).is_empty():
					var rev_str := str(rev_val)
					if not reveals.has(rev_str):
						reveals.append(rev_str)
				else:
					reveals.append("")

	if seen_night_ids.is_empty():
		return { "ok": false, "reason_code": "no_seen_row", "reason_text": "", "knowledge_id": "" }

	if reveals.size() != 1 or reveals[0].is_empty():
		push_error("confirm_night_alignment: data conflict or missing night_reveal for day location '%s'" % day_location_id)
		return { "ok": false, "reason_code": "data_conflict", "reason_text": "", "knowledge_id": "" }

	var reveal_card_id := reveals[0]
	if knowledge.has(reveal_card_id):
		return { "ok": false, "reason_code": "already_known", "reason_text": "", "knowledge_id": "" }

	gain_card(reveal_card_id)
	return { "ok": true, "reason_code": "", "reason_text": "", "knowledge_id": reveal_card_id }


## 純查詢：進入該夜間地點是否會因首次 marker cost 觸發發瘋 BE（規格書第八、九節、P3-B）。
func would_night_entry_end_run(location_id: String) -> bool:
	if night_locations_seen.has(location_id):
		return false
	if Data == null or Data.loader == null or not Data.loader.locations.has(location_id):
		return false
	var loc: Dictionary = Data.loader.locations.get(location_id, {}) as Dictionary
	if str(loc.get("layer", "")) != "night":
		return false
	if bool(loc.get("teaser_only", false)):
		return false
	if day < int(loc.get("earliest_night", 1)):
		return false
	if loc.has("requires") and not ConditionEval.eval(loc["requires"], self):
		return false
	var cost: int = int(loc.get("madness_cost", 0))
	if cost <= 0:
		return false
	var cap: int = int(Data.tuning("madness_cap", 0))
	if cap <= 0:
		return false
	var madness_count := 0
	for c: String in hand:
		if _card_base_id(c) == "madness":
			madness_count += 1
	return (madness_count + cost) >= cap


## fixed 到訪私有 helper：驗證地點後寫 chosen 與 seen，明確跳過 marker cost（規格書第九節、P3-B/P3-C）。
## 若當夜已選定地點或已就寢，回傳 false 並拒絕；成功寫入回傳 true。
func _record_forced_night_visit(location_id: String) -> bool:
	if not night_location_chosen.is_empty():
		push_error("_record_forced_night_visit: night_location_chosen already set to '%s', refusing overwrite with '%s'" % [night_location_chosen, location_id])
		return false
	if night_sleep_pending:
		push_error("_record_forced_night_visit: night_sleep_pending is true, refusing forced night visit to '%s'" % location_id)
		return false
	if Data != null and Data.loader != null and Data.loader.locations.has(location_id):
		night_location_chosen = location_id
		night_locations_seen[location_id] = true
		return true
	return false


## 每天 morning 開始時，桌上每張發狂卡的剩餘天數 −1（規格書第八節，P2-A）。
## 回傳這次歸零的實例 id 陣列（Array[String]）。
func tick_madness() -> Array[String]:
	var zeroed: Array[String] = []
	for inst: String in madness_clock.keys():
		var cur := int(madness_clock[inst])
		if cur > 0:
			var remaining := cur - 1
			madness_clock[inst] = remaining
			if remaining == 0:
				zeroed.append(inst)
		else:
			madness_clock[inst] = 0
	if not madness_clock.is_empty():
		hand_changed.emit()
	return zeroed


## 檢查 beat 在當前天與時段是否屬於合法範圍（K-18, P2-B, P3-C）。
func _is_beat_time_valid(beat: Dictionary) -> bool:
	if phase != "night" or bool(beat.get("fixed", false)):
		return DataFacts.beat_matches_time(beat, day, phase)

	# 夜間 non-fixed beat：僅接受該地點當下 resolved_night_content 選中之 primary / addon id
	var loc_id := str(beat.get("location", ""))
	if loc_id.is_empty():
		return false
	var resolved := resolved_night_content(loc_id)
	var bid := str(beat.get("id", ""))
	if str(resolved.get("primary", {}).get("id", "")) == bid:
		return true
	for addon: Dictionary in resolved.get("addons", []) as Array:
		if str(addon.get("id", "")) == bid:
			return true
	return false


# ── 手牌操作 ────────────────────────────────────────────────────────────────

## 取得卡片（按型別分流：slotless → knowledge；madness → 新實例進 hand；其餘 unique）。
func gain_card(id: String, check_cap: bool = true) -> void:
	var card: Dictionary = Data.loader.cards.get(id, {})
	if card.is_empty():
		push_error("gain_card: unknown card id '%s'" % id)
		return

	if card.get("slotless", false):
		# knowledge 類：不佔格，進知識集合（冪等）
		if knowledge.has(id):
			return
		knowledge[id] = true
		knowledge_changed.emit()
		return

	if card.get("type", "") == "madness":
		# 唯一的多實例卡
		_madness_counter += 1
		var inst := id + "#" + str(_madness_counter)
		hand.append(inst)
		madness_clock[inst] = int(Data.tuning("madness_countdown_days"))
		_check_hand_overflow(id)
		hand_changed.emit()
		if check_cap:
			_check_madness_cap()
		return

	# 其餘卡：unique（已持有 = no-op，含知識集合）
	if has_card(id):
		return

	# P4-C：玩家由零張 person card 變一張時發出教學信號；不在此寫 delegation_tutorial_seen，
	# 由 UI 實際顯示並關閉／略過後才呼叫 mark_delegation_tutorial_seen()。
	var is_first_person_card := false
	if str(card.get("type", "")) == "person" and not delegation_tutorial_seen:
		is_first_person_card = true
		for h: String in hand:
			if str(Data.loader.cards.get(_card_base_id(h), {}).get("type", "")) == "person":
				is_first_person_card = false
				break

	hand.append(id)
	_check_hand_overflow(id)
	hand_changed.emit()
	if is_first_person_card:
		delegation_tutorial_available.emit()


## 檢查手牌發狂卡是否達到上限（規格書第八節，P2-D）。
## 若達到 madness_cap 立即觸發發瘋 BE 並結束本輪。
func _check_madness_cap() -> void:
	if Data == null or not Data.ok:
		return
	var cap: int = int(Data.tuning("madness_cap", 0))
	if cap <= 0:
		return
	var madness_count := 0
	for c: String in hand:
		if _card_base_id(c) == "madness":
			madness_count += 1
	if madness_count >= cap:
		end_run("ending_madness_be")


func _check_hand_overflow(card_id: String) -> void:
	var max_hand: int = int(Data.tuning("hand_size"))
	if hand.size() > max_hand:
		push_warning("gain_card: hand is full (%d/%d), card '%s' gained anyway" % [hand.size(), max_hand, card_id])


## 丟棄卡片（can作用於 hand 與 knowledge；丟主角卡 = push_error）。
func lose_card(id: String) -> void:
	var base_id := _card_base_id(id)
	var card: Dictionary = Data.loader.cards.get(base_id, {})
	if card.get("type", "") == "protagonist":
		push_error("lose_card: cannot lose protagonist card (data bug)")
		return

	var idx := hand.find(id)
	if idx >= 0:
		hand.remove_at(idx)
		if card.get("type", "") == "madness":
			madness_clock.erase(id)
			madness_cards_cleared += 1
		hand_changed.emit()
		return

	if knowledge.has(id):
		knowledge.erase(id)
		knowledge_changed.emit()
		return

	push_error("lose_card: card '%s' not found in hand or knowledge" % id)


## 持有檢查：hand ∪ knowledge（備用區不算）。
func has_card(id: String) -> bool:
	return hand.has(id) or knowledge.has(id)


func has_knowledge(id: String) -> bool:
	return knowledge.has(id)


## 手牌佔格數（hand 裡的每個元素都佔一格；knowledge 不算）。
func hand_slots_used() -> int:
	return hand.size()


# ── Beat 呈現 ───────────────────────────────────────────────────────────────

## Beat 演出的規則層入口（P1-G）。
## 一次性判定：beats_entered 記錄是否第一次。
## on_enter 效果走正式 EffectApply（規格書第十四節）。
## 回傳要播的文字行（PackedStringArray）。
func play_beat(beat_id: String) -> PackedStringArray:
	var beat: Dictionary = Data.loader.beats_by_id.get(beat_id, {})
	if beat.is_empty():
		push_error("play_beat: unknown beat id '%s'" % beat_id)
		return PackedStringArray()

	var is_first := not beats_entered.has(beat_id)
	beats_entered[beat_id] = true

	var lines := PackedStringArray()

	# beat 主文（每次呈現都顯示）
	var text: Variant = beat.get("text")
	if text is String and not (text as String).is_empty():
		lines.append(text as String)

	# on_enter 效果（只在第一次結算）
	if is_first:
		lines.append_array(EffectApply.apply(beat.get("on_enter"), self))

	return lines


## 面板求值的規則層入口（P1-G）。純計算，不結算 on_enter、不改 GameState。
func build_panel(location_id: String) -> Dictionary:
	return PanelBuilder.build(location_id, self, Data)


## 右鍵預覽的規則層入口（P1-G）。純查詢，不結算任何效果。
## 回傳 { "cards": Array[String], "reason": String }。
func preview_slot(beat_id: String, slot_id: String) -> Dictionary:
	var beat: Dictionary = Data.loader.beats_by_id.get(beat_id, {})
	if beat.is_empty():
		return { "cards": [], "reason": _REASON_UNKNOWN_BEAT }
	var slot: Dictionary = _find_slot(beat, slot_id)
	if slot.is_empty():
		return { "cards": [], "reason": _REASON_UNKNOWN_SLOT }

	var state_result := _check_slot_state(beat, slot)
	if not state_result.get("ok", false):
		return {
			"cards": [],
			"reason": _result_reason(state_result),
		}

	var cards_result := placeable_cards(beat_id, slot_id)
	if not cards_result.is_empty():
		return { "cards": cards_result, "reason": "" }

	# OPEN 槽沒有可用卡時仍維持唯讀空清單；若是 action_spent 等狀態，
	# 用同一個規則檢查取得理由，避免預覽與實放分岔。
	var candidates := _held_cards()
	for card_id: String in candidates:
		var check_result := _check_place(card_id, beat, slot)
		if not check_result.get("ok", false):
			var reason := _result_reason(check_result)
			if not reason.is_empty() and reason != _REASON_NOT_HELD:
				return { "cards": [], "reason": reason }
	return { "cards": [], "reason": "" }


# ── 放置與效果結算（P1-D）───────────────────────────────────────────────────

const _REASON_UNKNOWN_BEAT := "unknown_beat"
const _REASON_UNKNOWN_SLOT := "unknown_slot"
const _REASON_NOT_HELD := "not_held"
const _REASON_HIDDEN := "hidden"
const _REASON_LOCKED := "locked"
const _REASON_RESOLVED := "resolved"
const _REASON_NOT_ACCEPTED := "not_accepted"
const _REASON_ACTION_SPENT := "action_spent"
const _REASON_CARD_REQUIRED := "card_required"
const _REASON_NOT_ACTION_PHASE := "not_action_phase"
const _REASON_NOT_DELEGATION := "not_delegation"
const _REASON_NOT_PERSON := "not_person"
const _REASON_ALREADY_DELEGATED_TODAY := "already_delegated_today"
const _REASON_ALREADY_RESOLVED := "already_resolved"
const _REASON_DATA_CONFLICT := "data_conflict"
const _REASON_LOCKED_FALLBACK := "（條件不足）"


func set_flag(name: String, value: bool = true) -> void:
	flags[name] = value


func open_switch(id: String) -> void:
	switches[id] = true


func add_switch_progress(id: String, n: int) -> void:
	switch_progress[id] = int(switch_progress.get(id, 0)) + n


func add_relation(npc: String, delta: int) -> void:
	relations[npc] = int(relations.get(npc, 0)) + delta


## `relation_at_least` 求值：讀 `data/relation_scale.json`（規格書第十二節）。
func relation_at_least(npc: String, state: String) -> bool:
	var scale: Dictionary = Data.loader.relation_scale
	if not scale.has(state):
		push_error("relation_at_least: unknown state '%s' (data/relation_scale.json)" % state)
		return false
	return int(relations.get(npc, 0)) >= int(scale[state])


## 取得當天剩餘可用之行動格數（規格書第六節、P2-B）。
func remaining_actions_today() -> int:
	if phase == "morning":
		var m_avail := 0 if action_spent else 1
		var a_avail := 0 if _actions_spent_ahead > 0 else 1
		return m_avail + a_avail
	elif phase == "afternoon":
		return 0 if action_spent else 1
	return 0


## 標記當前行動格已用（規格書第六節、P2-B）。
## n > 1 適用於泡湯特例或順延：標記當前行動格已用，並在當天後續時段自動扣除行動格。
## 絕不在此修改 phase 或發射 phase_changed，保持放置管線的原子性。
func consume_action(n: int = 1) -> void:
	action_spent = true
	if n > 1:
		_actions_spent_ahead += (n - 1)


func _find_slot(beat: Dictionary, slot_id: String) -> Dictionary:
	for slot: Dictionary in beat.get("slots", []) as Array:
		if str(slot.get("id", "")) == slot_id:
			return slot
	return {}


func _held_cards() -> Array[String]:
	var result: Array[String] = []
	for card_id: String in hand:
		result.append(card_id)
	for knowledge_id: Variant in (knowledge as Dictionary).keys():
		result.append(str(knowledge_id))
	return result


## 只檢查槽當前三態與時間，不檢查傳入卡片。
## _check_place() 與 preview_slot() 共用這段，確保灰槽理由一致。
func _check_slot_state(beat: Dictionary, slot: Dictionary) -> Dictionary:
	var beat_id := str(beat.get("id", ""))
	var slot_id := str(slot.get("id", ""))
	if not _is_beat_time_valid(beat):
		return { "ok": false, "reason_code": _REASON_HIDDEN, "reason_text": "" }
	if not ConditionEval.eval(beat.get("condition"), self):
		return { "ok": false, "reason_code": _REASON_HIDDEN, "reason_text": "" }
	if not ConditionEval.eval(beat.get("requires"), self):
		return {
			"ok": false,
			"reason_code": _REASON_LOCKED,
			"reason_text": str(beat.get("reject_reason", _REASON_LOCKED_FALLBACK)),
		}
	if not ConditionEval.eval(slot.get("condition"), self):
		return { "ok": false, "reason_code": _REASON_HIDDEN, "reason_text": "" }
	var slot_key := beat_id + "::" + slot_id
	if slots_placed.has(slot_key):
		return { "ok": false, "reason_code": _REASON_RESOLVED, "reason_text": "" }
	var choice_group: String = str(slot.get("choice_group", ""))
	if not choice_group.is_empty() and choices.has(beat_id + "::" + choice_group):
		return { "ok": false, "reason_code": _REASON_RESOLVED, "reason_text": "" }
	if not ConditionEval.eval(slot.get("requires"), self):
		return {
			"ok": false,
			"reason_code": _REASON_LOCKED,
			"reason_text": str(slot.get("reject_reason", _REASON_LOCKED_FALLBACK)),
		}
	return { "ok": true, "reason_code": "", "reason_text": "" }


## 放置前共用判斷。try_place() 與 preview_slot() 必須走同一條規則。
func _check_place(card_id: String, beat: Dictionary, slot: Dictionary) -> Dictionary:
	if card_id.is_empty() or not has_card(card_id):
		return { "ok": false, "reason_code": _REASON_NOT_HELD, "reason_text": "" }
	var state_result := _check_slot_state(beat, slot)
	if not state_result.get("ok", false):
		return state_result

	var base_id := _card_base_id(card_id)
	var card: Dictionary = Data.loader.cards.get(base_id, {})
	var accepts: Array = slot.get("accepts", []) as Array
	var card_type := str(card.get("type", ""))
	if not (accepts.has(base_id) or accepts.has(card_type)):
		return { "ok": false, "reason_code": _REASON_NOT_ACCEPTED, "reason_text": "" }

	var is_protagonist := card_type == "protagonist"
	if is_protagonist and ACTION_PHASES.has(phase) and action_spent:
		return { "ok": false, "reason_code": _REASON_ACTION_SPENT, "reason_text": "" }

	var is_madness := card_type == "madness"
	if is_madness:
		var ind_val: Variant = slot.get("indulgence")
		if ind_val is Dictionary:
			var ind := ind_val as Dictionary
			var is_soak := bool(ind.get("soak", false))
			if is_soak:
				var soak_cost := int(Data.tuning("indulgence.soak_phase_cost", 2))
				var rem_actions := remaining_actions_today()
				if rem_actions < soak_cost:
					var lock_reason := "（只能在上午發動）" if phase != "morning" else "（格數不足）"
					return { "ok": false, "reason_code": _REASON_LOCKED, "reason_text": lock_reason }
			else:
				if ACTION_PHASES.has(phase) and action_spent:
					return { "ok": false, "reason_code": _REASON_ACTION_SPENT, "reason_text": "" }

	return { "ok": true, "reason_code": "", "reason_text": "" }


func _result_reason(result: Dictionary) -> String:
	var reason_text := str(result.get("reason_text", ""))
	if not reason_text.is_empty():
		return reason_text
	return str(result.get("reason_code", ""))


## 當前時段是否仍有任一動作可做（合法卡放置或未結算選擇題）。純查詢，不推進時段。
func has_any_legal_action() -> bool:
	var locations := PanelBuilder.available_locations(self, Data)
	for location_id: String in locations:
		var view := build_panel(location_id)
		for beat_view: Dictionary in view.get("beats", []) as Array:
			if int(beat_view.get("tri", -1)) != PanelBuilder.TriState.OPEN:
				continue
			var beat_id := str((beat_view["beat"] as Dictionary).get("id", ""))
			for slot_view: Dictionary in beat_view.get("slots", []) as Array:
				if int(slot_view.get("tri", -1)) != PanelBuilder.TriState.OPEN:
					continue
				if bool(slot_view.get("is_choice", false)):
					return true
				var slot_id := str((slot_view["slot"] as Dictionary).get("id", ""))
				if not placeable_cards(beat_id, slot_id).is_empty():
					return true
	return false


## 取得某個槽當前可放置的手牌或知識卡 id 列表（UI 專用查詢，規則層統一計算）。
## 與 try_place() 共用 _check_place()，不在 UI 重複判斷。
func placeable_cards(beat_id: String, slot_id: String) -> Array[String]:
	var result: Array[String] = []
	var beat: Dictionary = Data.loader.beats_by_id.get(beat_id, {})
	if beat.is_empty():
		return result
	var slot := _find_slot(beat, slot_id)
	if slot.is_empty():
		return result
	for card_id: String in _held_cards():
		if _check_place(card_id, beat, slot).get("ok", false):
			result.append(card_id)

	return result


## 選擇題選定的唯一入口（UI 與 headless 走查共用，規格書 P1-E、開發設計方針 P1-E）。
## 原子操作：驗證未結算 → 三態 OPEN →（若帶卡）持有與 accepts 檢查 → on_place 結算 →
## 同步寫入 choices[beat_id::group_id] 與 slots_placed[beat_id::slot_id]。
## 不吃卡、不吃行動格（SCHEMA 規範）。
## 重複呼叫為 no-op，回傳 { ok: false, reason_code: "resolved" }。
## 回傳：{ "ok": bool, "reason_code": String, "reason_text": String, "lines": PackedStringArray }
func choose(beat_id: String, group_id: String, slot_id: String, card_id: String = "") -> Dictionary:
	if not active_encounter.is_empty():
		return { "ok": false, "reason_code": "encounter_active", "reason_text": "遭遇進行中，無法選擇", "lines": PackedStringArray() }

	var choice_key := beat_id + "::" + group_id
	if choices.has(choice_key):
		return { "ok": false, "reason_code": _REASON_RESOLVED, "reason_text": "", "lines": PackedStringArray() }

	var beat: Dictionary = Data.loader.beats_by_id.get(beat_id, {})
	if beat.is_empty():
		return { "ok": false, "reason_code": _REASON_UNKNOWN_BEAT, "reason_text": "", "lines": PackedStringArray() }

	var slot: Dictionary = _find_slot(beat, slot_id)
	if str(slot.get("choice_group", "")) != group_id:
		slot = {}
	if slot.is_empty():
		return { "ok": false, "reason_code": _REASON_UNKNOWN_SLOT, "reason_text": "", "lines": PackedStringArray() }

	# 委託槽的正式入口是 delegate()。通用 choose() 轉導至 delegate()。
	if slot.has("delegation"):
		return delegate(beat_id, slot_id, card_id)

	# choice_requires_card:true 是硬成本槽（SCHEMA choice_group）：無卡直呼必須拒絕，不走免費捷徑。
	if bool(slot.get("choice_requires_card", false)) and card_id.is_empty():
		return { "ok": false, "reason_code": _REASON_CARD_REQUIRED, "reason_text": "", "lines": PackedStringArray() }

	var state_result := _check_slot_state(beat, slot)
	if not state_result.get("ok", false):
		return {
			"ok": false,
			"reason_code": str(state_result.get("reason_code", "")),
			"reason_text": str(state_result.get("reason_text", "")),
			"lines": PackedStringArray(),
		}

	# 帶卡檢查（若傳入 card_id）
	if not card_id.is_empty():
		var place_result := _check_place(card_id, beat, slot)
		if not place_result.get("ok", false):
			return {
				"ok": false,
				"reason_code": str(place_result.get("reason_code", "")),
				"reason_text": str(place_result.get("reason_text", "")),
				"lines": PackedStringArray(),
			}

	# 效果結算（原子操作）
	var lines: PackedStringArray = EffectApply.apply(slot.get("on_place", {}), self)
	var slot_key := beat_id + "::" + slot_id
	choices[choice_key] = slot_id
	slots_placed[slot_key] = true

	# choice_requires_card 的親自處理槽提交 protagonist 就消耗該行動時段（SCHEMA choice_group）。
	# 一般 choice_group（無此旗標）維持不吃行動格。
	if bool(slot.get("choice_requires_card", false)) and not card_id.is_empty():
		var cr_base := _card_base_id(card_id)
		var cr_card: Dictionary = Data.loader.cards.get(cr_base, {})
		if str(cr_card.get("type", "")) == "protagonist" and ACTION_PHASES.has(phase):
			consume_action()
			var cr_attn: Variant = slot.get("attention_npc")
			if cr_attn != null:
				var cr_npc := str(cr_attn)
				npc_action_counts[cr_npc] = int(npc_action_counts.get(cr_npc, 0)) + 1

	return { "ok": true, "reason_code": "", "reason_text": "", "lines": lines }


## 主動縱慾的唯一入口（UI 與 headless 共用，規格書 P2-B、開發設計方針 P2-B）。
## 7 步固定順序，任一步失敗則 GameState 零變化：
## 1. 卡在手上、且 base id 是 madness
## 2. 槽存在、indulgence 欄位存在、三態為 OPEN
## 3. 泡湯特例：soak == true 時檢查 phase == "morning" 且當天剩餘行動格 >= soak_phase_cost；非泡湯檢查 action_spent
## 4. 消耗行動格（泡湯消 soak_phase_cost 格，其餘消 1 格）
## 5. 消掉卡（泡湯消 soak_cards_cleared 張，其餘消傳入那張）
## 6. indulgence_count += 1
## 7. 套 on_place，再套 on_place_by_level 當次強度級那一組
##
## **刻意不寫 slots_placed**（K-54）。出口 beat 的 when 是 day_from 1 → day_to 45，
## 同一個 beat_id::slot_id 撐滿整輪；一旦寫進去就再也不會被清，等於「砸東西一輪只能砸一次」。
## 縱慾是可重複的行為，節流閥是行動格（一天最多 2 次），不是槽的一次性。
## 企劃書第七節「任何時刻都必須至少有一個出口點得下去」靠的就是這一點。
## 回傳：{ "ok": bool, "reason_code": String, "reason_text": String, "lines": PackedStringArray }
func indulge(beat_id: String, slot_id: String, card_inst_id: String) -> Dictionary:
	if not active_encounter.is_empty():
		return { "ok": false, "reason_code": "encounter_active", "reason_text": "遭遇進行中，無法縱慾", "lines": PackedStringArray() }

	# 1. 卡持有檢查與 base_id 檢查
	if card_inst_id.is_empty() or not has_card(card_inst_id):
		return { "ok": false, "reason_code": _REASON_NOT_HELD, "reason_text": "", "lines": PackedStringArray() }
	var base_id := _card_base_id(card_inst_id)
	if base_id != "madness":
		return { "ok": false, "reason_code": _REASON_NOT_ACCEPTED, "reason_text": "", "lines": PackedStringArray() }

	# 2. beat 與 slot 存在性、indulgence 欄位存在、三態 OPEN、未放置過
	var beat: Dictionary = Data.loader.beats_by_id.get(beat_id, {})
	if beat.is_empty():
		return { "ok": false, "reason_code": _REASON_UNKNOWN_BEAT, "reason_text": "", "lines": PackedStringArray() }

	var slot: Dictionary = _find_slot(beat, slot_id)
	if slot.is_empty():
		return { "ok": false, "reason_code": _REASON_UNKNOWN_SLOT, "reason_text": "", "lines": PackedStringArray() }

	var ind_val: Variant = slot.get("indulgence")
	if ind_val == null or not ind_val is Dictionary:
		return { "ok": false, "reason_code": _REASON_NOT_ACCEPTED, "reason_text": "", "lines": PackedStringArray() }

	var state_result := _check_slot_state(beat, slot)
	if not state_result.get("ok", false):
		return {
			"ok": false,
			"reason_code": str(state_result.get("reason_code", "")),
			"reason_text": str(state_result.get("reason_text", "")),
			"lines": PackedStringArray(),
		}

	# 3. 泡湯特例或行動格已耗盡檢查
	var ind := ind_val as Dictionary
	var is_soak := bool(ind.get("soak", false))
	var soak_cost := int(Data.tuning("indulgence.soak_phase_cost", 2))

	if is_soak:
		var rem_actions := remaining_actions_today()
		if rem_actions < soak_cost:
			var lock_reason := "（只能在上午發動）" if phase != "morning" else "（格數不足）"
			return { "ok": false, "reason_code": _REASON_LOCKED, "reason_text": lock_reason, "lines": PackedStringArray() }
	else:
		if ACTION_PHASES.has(phase) and action_spent:
			return { "ok": false, "reason_code": _REASON_ACTION_SPENT, "reason_text": "", "lines": PackedStringArray() }

	# 4. 消耗行動格
	if is_soak:
		consume_action(soak_cost)
	else:
		consume_action(1)

	# 5. 消掉卡片（泡湯消 soak_cards_cleared 張，以傳入的 card_inst_id 為主；其餘消傳入那張）
	if is_soak:
		var cards_cleared := int(Data.tuning("indulgence.soak_cards_cleared", 1))
		lose_card(card_inst_id)
		var remaining_to_clear := cards_cleared - 1
		if remaining_to_clear > 0:
			var to_remove: Array[String] = []
			for c in hand:
				if _card_base_id(c) == "madness" and c != card_inst_id:
					to_remove.append(c)
					if to_remove.size() == remaining_to_clear:
						break
			for c in to_remove:
				lose_card(c)
	else:
		lose_card(card_inst_id)

	# 6. indulgence_count += 1
	indulgence_count += 1

	# 7. 套 on_place，再套 on_place_by_level
	var lines: PackedStringArray = EffectApply.apply(slot.get("on_place", {}), self)
	var by_level: Variant = slot.get("on_place_by_level")
	if by_level is Dictionary:
		var lvl := Indulgence.level_for(indulgence_count, Data.loader.tuning)
		var lvl_effect: Variant = (by_level as Dictionary).get(lvl)
		if lvl_effect is Dictionary:
			var lvl_lines := EffectApply.apply(lvl_effect, self)
			lines.append_array(lvl_lines)

	# 出口槽不記入 slots_placed，理由見函式開頭註解（K-54）。
	return { "ok": true, "reason_code": "", "reason_text": "", "lines": lines }


## 強制縱慾結算（規格書第八節、P2-C、開發設計方針 P2-C）。
## 規則層入口（由 advance_phase 於行動時段開始時自動呼叫）：
## 1. 取 forced_pending 隊首有效的發狂卡（若已被消則取下一張）
## 2. Indulgence.pick_exit 挑選當前條件成立之最高權重出口
## 3. consume_action(1) 消耗當前時段行動格
## 4. lose_card(card_inst_id) 消除該發狂卡
## 5. indulgence_count += 1
## 6. 套用 base on_place，再套用 on_place_by_level[lvl]
## 回傳要播出的文字行（PackedStringArray）。
func _settle_forced_indulgence() -> PackedStringArray:
	if forced_pending.is_empty() or action_spent:
		return PackedStringArray()

	# 清理前面已不在手上的無效實例
	while not forced_pending.is_empty() and not has_card(str(forced_pending[0])):
		forced_pending.pop_front()

	if forced_pending.is_empty():
		return PackedStringArray()

	# 先驗證出口，若出口異常或找不到槽則不 pop 隊首，債留在 forced_pending（帳不豁免）
	var exit_result := Indulgence.pick_exit(self, Data)
	if exit_result.is_empty():
		push_error("_settle_forced_indulgence: Indulgence.pick_exit returned empty exit (data bug)")
		return PackedStringArray()

	var beat_id := str(exit_result.get("beat_id", ""))
	var slot_id := str(exit_result.get("slot_id", ""))
	var beat: Dictionary = Data.loader.beats_by_id.get(beat_id, {})
	var slot: Dictionary = _find_slot(beat, slot_id)
	if slot.is_empty():
		push_error("_settle_forced_indulgence: slot not found '%s::%s'" % [beat_id, slot_id])
		return PackedStringArray()

	# 確定執行後才 pop 隊首
	var card_inst_id := str(forced_pending.pop_front())

	# 1. 消耗該時段行動格
	consume_action(1)

	# 2. 消掉發狂卡
	lose_card(card_inst_id)

	# 3. 累計縱慾次數
	indulgence_count += 1

	# 4. 套用效果：基底 on_place + 當次強度級追加效果
	var lines: PackedStringArray = EffectApply.apply(slot.get("on_place", {}), self)
	var by_level: Variant = slot.get("on_place_by_level")
	if by_level is Dictionary:
		var lvl := Indulgence.level_for(indulgence_count, Data.loader.tuning)
		var lvl_effect: Variant = (by_level as Dictionary).get(lvl)
		if lvl_effect is Dictionary:
			var lvl_lines := EffectApply.apply(lvl_effect, self)
			lines.append_array(lvl_lines)

	return lines


## 隔日上午委託回報結算（規格書 P4-B、開發設計方針 P4-B）。
## 由 advance_phase 於換日進入 morning 時呼叫（在強制縱慾之後、清空 delegates_used_today 之前）：
## 依 pending_delegation_reports 順序套用 report 效果，並收集文字行。
## 接點失效時視為資料衝突保留於 pending 並 push_error（不靜默丟棄）。
func _settle_pending_delegation_reports() -> void:
	if pending_delegation_reports.is_empty():
		return

	var current_day := day
	var remaining_reports: Array[Dictionary] = []
	var due_reports: Array[Dictionary] = []

	for r: Dictionary in pending_delegation_reports:
		if int(r.get("due_day", 0)) > current_day:
			remaining_reports.append(r)
			continue

		# 驗證接點合法性（beat 存在、slot 存在、delegation 為 next_morning 且 report 為非空字典）
		var b_id := str(r.get("beat_id", ""))
		var s_id := str(r.get("slot_id", ""))
		var beat_dict: Dictionary = Data.loader.beats_by_id.get(b_id, {}) if (Data != null and Data.loader != null) else {}
		var slot_dict: Dictionary = _find_slot(beat_dict, s_id)
		var del_val: Variant = slot_dict.get("delegation")
		var is_valid_del: bool = del_val is Dictionary and str((del_val as Dictionary).get("result_timing", "")) == "next_morning"
		var rep_val: Variant = (del_val as Dictionary).get("report") if is_valid_del else null
		var is_valid_rep: bool = rep_val is Dictionary and not (rep_val as Dictionary).is_empty()

		if beat_dict.is_empty() or slot_dict.is_empty() or not is_valid_del or not is_valid_rep:
			push_error("GameState: pending delegation report data conflict on beat '%s', slot '%s' (retaining in pending)" % [b_id, s_id])
			remaining_reports.append(r)
		else:
			due_reports.append(r)

	pending_delegation_reports = remaining_reports

	var rep_lines: PackedStringArray = []
	for r: Dictionary in due_reports:
		var b_id := str(r.get("beat_id", ""))
		var s_id := str(r.get("slot_id", ""))
		var beat_dict: Dictionary = Data.loader.beats_by_id[b_id]
		var slot_dict: Dictionary = _find_slot(beat_dict, s_id)
		var del_dict: Dictionary = slot_dict["delegation"] as Dictionary
		var rep_dict: Dictionary = del_dict["report"] as Dictionary

		var gen_before := run_generation
		var out := EffectApply.apply(rep_dict, self)

		# K-65 防呆：若回報效果觸發 BE / end_run，立即中斷結算、不寫入文字
		if run_generation != gen_before or day != current_day:
			return

		rep_lines.append_array(out)

	last_delegation_report_lines = rep_lines


## 人物委託的唯一原子入口（UI 與 headless 共用，規格書 P4-B、開發設計方針 P4-B）。
## 11 步固定檢查順序，任一步失敗則 GameState 零變化：
## 1. not_action_phase：白天行動時段（morning / afternoon）
## 2. unknown_beat：beat 存在、時段吻合且 condition 成立
## 3. unknown_slot：slot 存在且 condition 成立
## 4. not_delegation：slot 帶 delegation 字典
## 5. not_held：person_card_id 非空且在手牌
## 6. not_person：卡片 type 為 person
## 7. not_accepted：slot accepts 包含該卡 base_id
## 8. already_delegated_today：該人物今日未曾成功受託
## 9. locked：beat / slot requires 條件成立（失敗帶 reject_reason）
## 10. already_resolved：槽未放置且 choice_group 未結算
## 11. data_conflict：timing / report 結構合法（immediate 無 report；next_morning 有合法 report 字典）
##
## 成功順序（原子性）：
## - 寫 choices 與 slots_placed
## - delegates_used_today[base_id] = true
## - immediate：套 on_place 效果
## - next_morning：套 on_place 效果（派出當下效果），並 append {due_day, beat_id, slot_id, person_id} 至 pending_delegation_reports
## - 委託不消耗主角行動格、不增 npc_action_counts、不移動人物卡
## 回傳：{ "ok": bool, "reason_code": String, "reason_text": String, "lines": PackedStringArray }
func delegate(beat_id: String, slot_id: String, person_card_id: String) -> Dictionary:
	if not active_encounter.is_empty():
		return { "ok": false, "reason_code": "encounter_active", "reason_text": "遭遇進行中，無法委託", "lines": PackedStringArray() }

	# 1. 白天行動時段
	if not ACTION_PHASES.has(phase):
		return { "ok": false, "reason_code": _REASON_NOT_ACTION_PHASE, "reason_text": "", "lines": PackedStringArray() }

	# 2. beat 存在、時段吻合、condition 成立
	var beat: Dictionary = Data.loader.beats_by_id.get(beat_id, {})
	if beat.is_empty() or not _is_beat_time_valid(beat) or not ConditionEval.eval(beat.get("condition"), self):
		return { "ok": false, "reason_code": _REASON_UNKNOWN_BEAT, "reason_text": "", "lines": PackedStringArray() }

	# 3. slot 存在、condition 成立
	var slot: Dictionary = _find_slot(beat, slot_id)
	if slot.is_empty() or not ConditionEval.eval(slot.get("condition"), self):
		return { "ok": false, "reason_code": _REASON_UNKNOWN_SLOT, "reason_text": "", "lines": PackedStringArray() }

	# 4. slot 必須帶 delegation
	var del_val: Variant = slot.get("delegation")
	if del_val == null or not (del_val is Dictionary):
		return { "ok": false, "reason_code": _REASON_NOT_DELEGATION, "reason_text": "", "lines": PackedStringArray() }
	var delegation := del_val as Dictionary

	# 5. 卡在手
	if person_card_id.is_empty() or not has_card(person_card_id):
		return { "ok": false, "reason_code": _REASON_NOT_HELD, "reason_text": "", "lines": PackedStringArray() }

	# 6. 卡型別為 person
	var base_id := _card_base_id(person_card_id)
	var card: Dictionary = Data.loader.cards.get(base_id, {})
	if str(card.get("type", "")) != "person":
		return { "ok": false, "reason_code": _REASON_NOT_PERSON, "reason_text": "", "lines": PackedStringArray() }

	# 7. accepts 命中
	var accepts: Array = slot.get("accepts", []) as Array
	if not accepts.has(base_id):
		return { "ok": false, "reason_code": _REASON_NOT_ACCEPTED, "reason_text": "", "lines": PackedStringArray() }

	# 8. 今日未受託
	if bool(delegates_used_today.get(base_id, false)):
		return { "ok": false, "reason_code": _REASON_ALREADY_DELEGATED_TODAY, "reason_text": "", "lines": PackedStringArray() }

	# 9. requires 成立
	if not ConditionEval.eval(beat.get("requires"), self):
		return {
			"ok": false,
			"reason_code": _REASON_LOCKED,
			"reason_text": str(beat.get("reject_reason", _REASON_LOCKED_FALLBACK)),
			"lines": PackedStringArray(),
		}
	if not ConditionEval.eval(slot.get("requires"), self):
		return {
			"ok": false,
			"reason_code": _REASON_LOCKED,
			"reason_text": str(slot.get("reject_reason", _REASON_LOCKED_FALLBACK)),
			"lines": PackedStringArray(),
		}

	# 10. choice_group 未結算、槽未放置過
	var slot_key := beat_id + "::" + slot_id
	if slots_placed.has(slot_key):
		return { "ok": false, "reason_code": _REASON_ALREADY_RESOLVED, "reason_text": "", "lines": PackedStringArray() }
	var choice_group: String = str(slot.get("choice_group", ""))
	if not choice_group.is_empty() and choices.has(beat_id + "::" + choice_group):
		return { "ok": false, "reason_code": _REASON_ALREADY_RESOLVED, "reason_text": "", "lines": PackedStringArray() }

	# 11. timing / report 結構合法
	var timing := str(delegation.get("result_timing", ""))
	if timing != "immediate" and timing != "next_morning":
		return { "ok": false, "reason_code": _REASON_DATA_CONFLICT, "reason_text": "", "lines": PackedStringArray() }
	if timing == "next_morning":
		var rep_val: Variant = delegation.get("report")
		if rep_val == null or not (rep_val is Dictionary):
			return { "ok": false, "reason_code": _REASON_DATA_CONFLICT, "reason_text": "", "lines": PackedStringArray() }
	elif timing == "immediate":
		if delegation.has("report"):
			return { "ok": false, "reason_code": _REASON_DATA_CONFLICT, "reason_text": "", "lines": PackedStringArray() }

	# ── 成功（原子操作）──
	if not choice_group.is_empty():
		choices[beat_id + "::" + choice_group] = slot_id
	slots_placed[slot_key] = true
	delegates_used_today[base_id] = true

	var lines: PackedStringArray = EffectApply.apply(slot.get("on_place", {}), self)

	if timing == "next_morning":
		pending_delegation_reports.append({
			"due_day": day + 1,
			"beat_id": beat_id,
			"slot_id": slot_id,
			"person_id": base_id,
		})

	return { "ok": true, "reason_code": "", "reason_text": "", "lines": lines }


## 查詢人物卡當前受託狀態（UI 專用查詢，規格書 P4-B、開發設計方針 P4-B）。
func delegation_status(person_card_id: String) -> Dictionary:
	var base_id := _card_base_id(person_card_id)
	var is_held := has_card(person_card_id)
	var used_today := bool(delegates_used_today.get(base_id, false))
	var has_pending := false
	for r: Dictionary in pending_delegation_reports:
		if str(r.get("person_id", "")) == base_id:
			has_pending = true
			break
	return {
		"held": is_held,
		"delegated_today": used_today,
		"available": is_held and not used_today,
		"has_pending_report": has_pending,
	}


## P4-C：UI 實際顯示委託教學並關閉／略過後呼叫，寫入 meta 層，跨輪保留。冪等。
func mark_delegation_tutorial_seen() -> void:
	delegation_tutorial_seen = true


## 放卡的唯一入口（UI 與 headless 走查共用；UI 內不做任何判斷）。
## 放置合法性四步檢查，順序固定（規格書第六節）：
## ①持有 → ②三態 OPEN（beat 與槽兩級 condition/requires 都要過，含一次性未放過）→
## ③accepts → ④action_spent（僅行動格內的主角卡）。
## 若該槽帶 choice_group，直接轉導 choose() 保證規則層單一入口（P1-E）。
## 若該槽為委託槽，直接轉導 delegate() 保證規則層單一入口（P4-B）。
## 若卡片為發狂卡，直接轉導 indulge() 保證規則層單一入口（P2-B）。
## 任一步不過 → { ok=false, reason_code, reason_text, lines=[] }，GameState 零變化。
## 回傳：{ "ok": bool, "reason_code": String, "reason_text": String, "lines": PackedStringArray }
func try_place(card_id: String, beat_id: String, slot_id: String) -> Dictionary:
	if not active_encounter.is_empty():
		return { "ok": false, "reason_code": "encounter_active", "reason_text": "遭遇進行中，無法放置卡片", "lines": PackedStringArray() }

	# K-17: 空卡 id 走 try_place 直接擋下，不轉導 choose
	if card_id.is_empty():
		return { "ok": false, "reason_code": _REASON_NOT_HELD, "reason_text": "", "lines": PackedStringArray() }

	var base_id := _card_base_id(card_id)
	if base_id == "madness":
		return indulge(beat_id, slot_id, card_id)

	var beat: Dictionary = Data.loader.beats_by_id.get(beat_id, {})
	if beat.is_empty():
		return { "ok": false, "reason_code": _REASON_UNKNOWN_BEAT, "reason_text": "", "lines": PackedStringArray() }

	var slot := _find_slot(beat, slot_id)
	if slot.is_empty():
		return { "ok": false, "reason_code": _REASON_UNKNOWN_SLOT, "reason_text": "", "lines": PackedStringArray() }

	if slot.has("delegation"):
		return delegate(beat_id, slot_id, card_id)

	var choice_group: Variant = slot.get("choice_group")
	if choice_group != null and not str(choice_group).is_empty():
		return choose(beat_id, str(choice_group), slot_id, card_id)

	var check_result := _check_place(card_id, beat, slot)
	if not check_result.get("ok", false):
		return {
			"ok": false,
			"reason_code": str(check_result.get("reason_code", "")),
			"reason_text": str(check_result.get("reason_text", "")),
			"lines": PackedStringArray(),
		}

	var card: Dictionary = Data.loader.cards.get(base_id, {})
	var slot_key := beat_id + "::" + slot_id
	var card_type := str(card.get("type", ""))
	var is_protagonist := card_type == "protagonist"
	var in_action_phase := ACTION_PHASES.has(phase)

	# 全過 → 效果結算（原子操作：全部套完才重求值）。
	var lines: PackedStringArray = EffectApply.apply(slot.get("on_place", {}), self)
	slots_placed[slot_key] = true

	if is_protagonist and in_action_phase:
		consume_action()
		var attn: Variant = slot.get("attention_npc")
		if attn != null:
			var npc_id := str(attn)
			npc_action_counts[npc_id] = int(npc_action_counts.get(npc_id, 0)) + 1

	return { "ok": true, "reason_code": "", "reason_text": "", "lines": lines }


# ── 遭遇系統（P4-D）─────────────────────────────────────────────────────────

## 手牌是否超載（純查詢，不序列化，規格書第十三節、P4-D）。
func is_overloaded() -> bool:
	var max_hand: int = int(Data.tuning("hand_size", 14)) if Data != null else 14
	return hand_slots_used() > max_hand


## 啟動遭遇（規格書第十三節、開發設計方針 P4-D）。
## 檢查順序固定：
## 1. active:已有進行中遭遇（encounter_active）
## 2. unknown beat:未知的 beat id 或無 encounter 欄位（unknown_beat）
## 3. data conflict:遭遇資料結構異常（data_conflict）
## 成功建立 stage == "intro"，blocked_slots 初始化為 0。
## 回傳：{ "ok": bool, "reason_code": String, "reason_text": String }
func start_encounter(beat_id: String) -> Dictionary:
	# 1. active
	if not active_encounter.is_empty():
		return { "ok": false, "reason_code": "encounter_active", "reason_text": "已有進行中的遭遇" }

	# 2. unknown beat
	if Data == null or Data.loader == null or not Data.loader.beats_by_id.has(beat_id):
		return { "ok": false, "reason_code": "unknown_beat", "reason_text": "未知的遭遇事件" }

	var beat: Dictionary = Data.loader.beats_by_id.get(beat_id, {}) as Dictionary
	if not beat.has("encounter"):
		return { "ok": false, "reason_code": "unknown_beat", "reason_text": "未知的遭遇事件" }

	var enc_val: Variant = beat.get("encounter")
	if not enc_val is Dictionary:
		return { "ok": false, "reason_code": "data_conflict", "reason_text": "遭遇資料格式錯誤" }

	var enc := enc_val as Dictionary
	# 3. data conflict
	var rounds_val: Variant = enc.get("rounds")
	if not rounds_val is Array or (rounds_val as Array).is_empty():
		return { "ok": false, "reason_code": "data_conflict", "reason_text": "遭遇資料缺少回合定義" }
	if not enc.has("per_round_slot_cost") or int(enc.get("per_round_slot_cost", 0)) <= 0:
		return { "ok": false, "reason_code": "data_conflict", "reason_text": "遭遇資料 slot_cost 錯誤" }
	if not enc.has("after_finish"):
		return { "ok": false, "reason_code": "data_conflict", "reason_text": "遭遇資料缺少 after_finish" }

	var attempted_ids: Array[String] = []
	var visited_ids: Array[String] = []
	active_encounter = {
		"beat_id": beat_id,
		"stage": "intro",
		"round_id": "",
		"blocked_slots": 0,
		"attempted_card_ids": attempted_ids,
		"visited_round_ids": visited_ids
	}

	return { "ok": true, "reason_code": "", "reason_text": "" }


## 確認開場演出並進入第一回合（規格書第十三節、開發設計方針 P4-D）。
## 檢查順序固定：
## 1. inactive:目前無遭遇（no_active_encounter）
## 2. wrong stage:目前不是 intro 階段（wrong_stage）
## 3. data conflict:第一回合資料異常（data_conflict）
## 成功進入第一回合，超載時先加一次 penalty，第一回合各加一次 cost；可用格歸零或無合法解直接 failure。
## 回傳：{ "ok": bool, "reason_code": String, "reason_text": String, "lines": PackedStringArray }
func acknowledge_encounter_intro() -> Dictionary:
	# 1. inactive
	if active_encounter.is_empty():
		return { "ok": false, "reason_code": "no_active_encounter", "reason_text": "目前沒有進行中的遭遇", "lines": PackedStringArray() }

	# 2. wrong stage
	if str(active_encounter.get("stage", "")) != "intro":
		return { "ok": false, "reason_code": "wrong_stage", "reason_text": "目前不是開場演出階段", "lines": PackedStringArray() }

	# 3. data conflict
	var beat_id := str(active_encounter.get("beat_id", ""))
	var beat: Dictionary = Data.loader.beats_by_id.get(beat_id, {}) as Dictionary if Data != null and Data.loader != null else {}
	var enc: Dictionary = beat.get("encounter", {}) as Dictionary
	var first_round_id := Encounter.get_first_round_id(enc)
	if first_round_id.is_empty():
		return { "ok": false, "reason_code": "data_conflict", "reason_text": "遭遇資料缺少第一回合定義", "lines": PackedStringArray() }

	var first_round := Encounter.get_round(enc, first_round_id)
	if first_round.is_empty():
		return { "ok": false, "reason_code": "data_conflict", "reason_text": "遭遇第一回合資料遺失", "lines": PackedStringArray() }

	var cost := int(enc.get("per_round_slot_cost", 1))

	# 超載時先加一次 penalty cost
	if is_overloaded():
		active_encounter["blocked_slots"] = int(active_encounter.get("blocked_slots", 0)) + cost
		if _check_encounter_capacity_failure():
			var fail_res := _finish_encounter("failure", enc.get("on_failure", {}))
			return { "ok": true, "reason_code": "", "reason_text": "", "lines": fail_res.get("lines", PackedStringArray()) }

	# 進入第一回合
	active_encounter["stage"] = "round"
	active_encounter["round_id"] = first_round_id
	active_encounter["blocked_slots"] = int(active_encounter.get("blocked_slots", 0)) + cost
	var visited: Array = active_encounter.get("visited_round_ids", []) as Array
	if not visited.has(first_round_id):
		visited.append(first_round_id)

	# 檢查佔格是否已達/超出手牌上限
	if _check_encounter_capacity_failure():
		var fail_res := _finish_encounter("failure", enc.get("on_failure", {}))
		return { "ok": true, "reason_code": "", "reason_text": "", "lines": fail_res.get("lines", PackedStringArray()) }

	# 檢查是否有合法動作
	if not Encounter.has_legal_moves(enc, first_round, active_encounter, self, Data.loader):
		var fail_res := _finish_encounter("failure", enc.get("on_failure", {}))
		return { "ok": true, "reason_code": "", "reason_text": "", "lines": fail_res.get("lines", PackedStringArray()) }

	return { "ok": true, "reason_code": "", "reason_text": "", "lines": PackedStringArray() }


## 遭遇 View Model（規格書第十三節、P4-D）。
func encounter_view() -> Dictionary:
	if active_encounter.is_empty() or Data == null or Data.loader == null:
		return {}
	var beat_id := str(active_encounter.get("beat_id", ""))
	var beat: Dictionary = Data.loader.beats_by_id.get(beat_id, {}) as Dictionary
	var enc: Dictionary = beat.get("encounter", {}) as Dictionary
	return Encounter.build_view(enc, active_encounter, self, Data.loader, Data.loader.tuning)


## 回應遭遇（規格書第十三節、開發設計方針 P4-D）。
## 檢查順序固定：
## 1. inactive:目前無遭遇（no_active_encounter）
## 2. wrong stage:目前不是 round 階段（wrong_stage）
## 3. unknown card:卡片不存在（unknown_card）
## 4. not held:未持有該卡片（not_held）
## 5. madness:發狂卡不可提交（madness_blocked）
## 6. already attempted:同一 base card 本場已嘗試過（already_attempted）
## 7. card not submittable:未命中 response 且 fallback.requires_discardable 且卡不可丟棄（card_not_submittable）
## 8. data conflict:回合資料異常（data_conflict）
## 回傳：{ "ok": bool, "reason_code": String, "reason_text": String, "lines": PackedStringArray }
func respond_to_encounter(card_id: String) -> Dictionary:
	# 1. inactive
	if active_encounter.is_empty():
		return { "ok": false, "reason_code": "no_active_encounter", "reason_text": "目前沒有進行中的遭遇", "lines": PackedStringArray() }

	# 2. wrong stage
	if str(active_encounter.get("stage", "")) != "round":
		return { "ok": false, "reason_code": "wrong_stage", "reason_text": "目前不是回應回合階段", "lines": PackedStringArray() }

	# 3. unknown card
	if card_id.is_empty():
		return { "ok": false, "reason_code": "unknown_card", "reason_text": "未知的卡片", "lines": PackedStringArray() }
	var base_id := _card_base_id(card_id)
	if Data == null or Data.loader == null or not Data.loader.cards.has(base_id):
		return { "ok": false, "reason_code": "unknown_card", "reason_text": "未知的卡片", "lines": PackedStringArray() }

	# 4. not held
	if not has_card(card_id):
		return { "ok": false, "reason_code": "not_held", "reason_text": "未持有該卡片", "lines": PackedStringArray() }

	# 5. madness
	if base_id == "madness" or madness_clock.has(card_id):
		return { "ok": false, "reason_code": "madness_blocked", "reason_text": "發狂卡不可作為回應提交", "lines": PackedStringArray() }

	# 6. already attempted
	var attempted: Array = active_encounter.get("attempted_card_ids", []) as Array
	if attempted.has(base_id):
		return { "ok": false, "reason_code": "already_attempted", "reason_text": "此卡片本場已嘗試過", "lines": PackedStringArray() }

	# 取得當前回合定義
	var beat_id := str(active_encounter.get("beat_id", ""))
	var beat: Dictionary = Data.loader.beats_by_id.get(beat_id, {}) as Dictionary if Data != null and Data.loader != null else {}
	var enc: Dictionary = beat.get("encounter", {}) as Dictionary
	var round_id := str(active_encounter.get("round_id", ""))
	var round_data := Encounter.get_round(enc, round_id)

	var card_def: Dictionary = Data.loader.cards.get(base_id, {}) as Dictionary
	var is_discardable := bool(card_def.get("discardable", false))
	var matching_resp := Encounter.find_matching_response(round_data, card_id, base_id)
	var fallback: Dictionary = round_data.get("fallback", {}) as Dictionary
	var req_discardable := bool(fallback.get("requires_discardable", false))

	# 7. card not submittable (K-132: 依方針順序先於 data_conflict)
	if matching_resp.is_empty() and req_discardable and not is_discardable:
		return { "ok": false, "reason_code": "card_not_submittable", "reason_text": "該卡無法作為錯答提交", "lines": PackedStringArray() }

	# 8. data conflict
	if round_data.is_empty():
		return { "ok": false, "reason_code": "data_conflict", "reason_text": "當前回合資料遺失", "lines": PackedStringArray() }

	# 通過所有檢查 → 開始結算
	attempted.append(base_id)
	var cost := int(enc.get("per_round_slot_cost", 1))
	var lines := PackedStringArray()

	if not matching_resp.is_empty():
		# ── 命中 Response ──
		if bool(matching_resp.get("consume_card", false)) and is_discardable:
			lose_card(card_id)

		# 正解釋放本回合佔格
		active_encounter["blocked_slots"] = max(0, int(active_encounter.get("blocked_slots", 0)) - cost)

		# 套用 on_resolve
		if matching_resp.has("on_resolve"):
			lines.append_array(EffectApply.apply(matching_resp["on_resolve"], self))

		var next_round_val: Variant = matching_resp.get("next_round")
		if next_round_val == null or str(next_round_val).is_empty():
			# 勝利出口
			var fin_res := _finish_encounter("victory", enc.get("on_victory", {}))
			lines.append_array(fin_res.get("lines", PackedStringArray()))
			return { "ok": true, "reason_code": "", "reason_text": "", "lines": lines }
		else:
			var next_rid := str(next_round_val)
			var visited: Array = active_encounter.get("visited_round_ids", []) as Array
			if visited.has(next_rid):
				push_error("Encounter: cycle detected on round '%s'" % next_rid)
				var fail_res := _finish_encounter("failure", enc.get("on_failure", {}))
				lines.append_array(fail_res.get("lines", PackedStringArray()))
				return { "ok": true, "reason_code": "", "reason_text": "", "lines": lines }
			visited.append(next_rid)

			active_encounter["round_id"] = next_rid
			active_encounter["blocked_slots"] = int(active_encounter.get("blocked_slots", 0)) + cost

			if _check_encounter_capacity_failure():
				var fail_res := _finish_encounter("failure", enc.get("on_failure", {}))
				lines.append_array(fail_res.get("lines", PackedStringArray()))
				return { "ok": true, "reason_code": "", "reason_text": "", "lines": lines }

			var next_round := Encounter.get_round(enc, next_rid)
			if not Encounter.has_legal_moves(enc, next_round, active_encounter, self, Data.loader):
				var fail_res := _finish_encounter("failure", enc.get("on_failure", {}))
				lines.append_array(fail_res.get("lines", PackedStringArray()))
				return { "ok": true, "reason_code": "", "reason_text": "", "lines": lines }

			return { "ok": true, "reason_code": "", "reason_text": "", "lines": lines }
	else:
		# ── 未命中 Fallback ──
		if is_discardable:
			lose_card(card_id)
		# 錯答保留佔格（不釋放）

		if fallback.has("on_resolve"):
			lines.append_array(EffectApply.apply(fallback["on_resolve"], self))

		var next_round_val: Variant = fallback.get("next_round")
		if next_round_val == null or str(next_round_val).is_empty():
			# 失敗出口
			var fail_res := _finish_encounter("failure", enc.get("on_failure", {}))
			lines.append_array(fail_res.get("lines", PackedStringArray()))
			return { "ok": true, "reason_code": "", "reason_text": "", "lines": lines }
		else:
			var next_rid := str(next_round_val)
			var visited: Array = active_encounter.get("visited_round_ids", []) as Array
			if visited.has(next_rid):
				push_error("Encounter: cycle detected on round '%s'" % next_rid)
				var fail_res := _finish_encounter("failure", enc.get("on_failure", {}))
				lines.append_array(fail_res.get("lines", PackedStringArray()))
				return { "ok": true, "reason_code": "", "reason_text": "", "lines": lines }
			visited.append(next_rid)

			active_encounter["round_id"] = next_rid
			active_encounter["blocked_slots"] = int(active_encounter.get("blocked_slots", 0)) + cost

			if _check_encounter_capacity_failure():
				var fail_res := _finish_encounter("failure", enc.get("on_failure", {}))
				lines.append_array(fail_res.get("lines", PackedStringArray()))
				return { "ok": true, "reason_code": "", "reason_text": "", "lines": lines }

			var next_round := Encounter.get_round(enc, next_rid)
			if not Encounter.has_legal_moves(enc, next_round, active_encounter, self, Data.loader):
				var fail_res := _finish_encounter("failure", enc.get("on_failure", {}))
				lines.append_array(fail_res.get("lines", PackedStringArray()))
				return { "ok": true, "reason_code": "", "reason_text": "", "lines": lines }

			return { "ok": true, "reason_code": "", "reason_text": "", "lines": lines }


## 主動丟棄卡片（規格書第十三節、開發設計方針 P4-D）。
## 檢查順序固定：
## 1. inactive:目前無遭遇（no_active_encounter）
## 2. wrong stage:目前不是 round 階段（wrong_stage）
## 3. discard disabled:此遭遇不允許主動丟棄（discard_disabled）
## 4. unknown card:卡片不存在（unknown_card）
## 5. not held:未持有該卡片（not_held）
## 6. not discardable:發狂卡或 discardable:false 卡（not_discardable）
## 成功移除該卡，不改 blocked_slots、不推進 round；若無合法解則失敗。
## 回傳：{ "ok": bool, "reason_code": String, "reason_text": String, "lines": PackedStringArray }
func discard_in_encounter(card_id: String) -> Dictionary:
	# 1. inactive
	if active_encounter.is_empty():
		return { "ok": false, "reason_code": "no_active_encounter", "reason_text": "目前沒有進行中的遭遇", "lines": PackedStringArray() }

	# 2. wrong stage
	if str(active_encounter.get("stage", "")) != "round":
		return { "ok": false, "reason_code": "wrong_stage", "reason_text": "目前不是回應回合階段", "lines": PackedStringArray() }

	# 3. discard disabled
	var beat_id := str(active_encounter.get("beat_id", ""))
	var beat: Dictionary = Data.loader.beats_by_id.get(beat_id, {}) as Dictionary if Data != null and Data.loader != null else {}
	var enc: Dictionary = beat.get("encounter", {}) as Dictionary
	if not bool(enc.get("allow_discard", true)):
		return { "ok": false, "reason_code": "discard_disabled", "reason_text": "此遭遇不允許主動丟棄", "lines": PackedStringArray() }

	# 4. unknown card
	if card_id.is_empty():
		return { "ok": false, "reason_code": "unknown_card", "reason_text": "未知的卡片", "lines": PackedStringArray() }
	var base_id := _card_base_id(card_id)
	if Data == null or Data.loader == null or not Data.loader.cards.has(base_id):
		return { "ok": false, "reason_code": "unknown_card", "reason_text": "未知的卡片", "lines": PackedStringArray() }

	# 5. not held
	if not has_card(card_id):
		return { "ok": false, "reason_code": "not_held", "reason_text": "未持有該卡片", "lines": PackedStringArray() }

	# 6. not discardable
	if base_id == "madness" or madness_clock.has(card_id):
		return { "ok": false, "reason_code": "not_discardable", "reason_text": "發狂卡不可丟棄", "lines": PackedStringArray() }
	var card_def: Dictionary = Data.loader.cards.get(base_id, {}) as Dictionary
	if not bool(card_def.get("discardable", false)):
		return { "ok": false, "reason_code": "not_discardable", "reason_text": "此卡片不可丟棄", "lines": PackedStringArray() }

	lose_card(card_id)

	# 檢查丟棄後是否仍有合法動作
	var round_id := str(active_encounter.get("round_id", ""))
	var round_data := Encounter.get_round(enc, round_id)
	if not Encounter.has_legal_moves(enc, round_data, active_encounter, self, Data.loader):
		var fail_res := _finish_encounter("failure", enc.get("on_failure", {}))
		return { "ok": true, "reason_code": "", "reason_text": "", "lines": fail_res.get("lines", PackedStringArray()) }

	return { "ok": true, "reason_code": "", "reason_text": "", "lines": PackedStringArray() }


## 逃離遭遇（規格書第十三節、開發設計方針 P4-D）。
## 檢查順序固定：
## 1. inactive:目前無遭遇（no_active_encounter）
## 2. wrong stage:目前不是 round 階段（wrong_stage）
## 3. cannot escape:escape_cost 為 null（cannot_escape）
## 4. wrong escape count:支付卡片數量不等於 escape_cost（wrong_escape_count）
## 5. duplicate payment:支付卡片存在重複 id（duplicate_payment）
## 6. unknown card:支付卡片不存在（unknown_card）
## 7. not held:未持有支付卡片（not_held）
## 8. not discardable:支付卡片含發狂卡或不可丟棄卡（not_discardable）
## 9. data conflict:遭遇資料格式錯誤（data_conflict）
## 回傳：{ "ok": bool, "reason_code": String, "reason_text": String, "lines": PackedStringArray }
func escape_encounter(card_ids: Array[String]) -> Dictionary:
	# 1. inactive
	if active_encounter.is_empty():
		return { "ok": false, "reason_code": "no_active_encounter", "reason_text": "目前沒有進行中的遭遇", "lines": PackedStringArray() }

	# 2. wrong stage
	if str(active_encounter.get("stage", "")) != "round":
		return { "ok": false, "reason_code": "wrong_stage", "reason_text": "目前不是回應回合階段", "lines": PackedStringArray() }

	# 3. cannot escape
	var beat_id := str(active_encounter.get("beat_id", ""))
	var beat: Dictionary = Data.loader.beats_by_id.get(beat_id, {}) as Dictionary if Data != null and Data.loader != null else {}
	var enc: Dictionary = beat.get("encounter", {}) as Dictionary
	var esc_val: Variant = enc.get("escape_cost")
	if esc_val == null:
		return { "ok": false, "reason_code": "cannot_escape", "reason_text": "此遭遇無法逃離", "lines": PackedStringArray() }

	# 4. wrong escape count
	var esc_cost := int(esc_val)
	if card_ids.size() != esc_cost:
		return { "ok": false, "reason_code": "wrong_escape_count", "reason_text": "逃離支付張數不正確", "lines": PackedStringArray() }

	# 5. duplicate payment
	var seen_ids: Dictionary = {}
	for cid in card_ids:
		if seen_ids.has(cid):
			return { "ok": false, "reason_code": "duplicate_payment", "reason_text": "支付卡片重複", "lines": PackedStringArray() }
		seen_ids[cid] = true

	# 6. unknown card, 7. not held, 8. not discardable
	for cid in card_ids:
		if cid.is_empty():
			return { "ok": false, "reason_code": "unknown_card", "reason_text": "未知的卡片", "lines": PackedStringArray() }
		var base_id := _card_base_id(cid)
		if Data == null or Data.loader == null or not Data.loader.cards.has(base_id):
			return { "ok": false, "reason_code": "unknown_card", "reason_text": "未知的卡片", "lines": PackedStringArray() }
		if not has_card(cid):
			return { "ok": false, "reason_code": "not_held", "reason_text": "未持有支付卡片", "lines": PackedStringArray() }
		if base_id == "madness" or madness_clock.has(cid):
			return { "ok": false, "reason_code": "not_discardable", "reason_text": "發狂卡不可作為逃離代價", "lines": PackedStringArray() }
		var card_def: Dictionary = Data.loader.cards.get(base_id, {}) as Dictionary
		if not bool(card_def.get("discardable", false)):
			return { "ok": false, "reason_code": "not_discardable", "reason_text": "不可丟棄卡無法作為逃離代價", "lines": PackedStringArray() }

	# 支付代價
	for cid in card_ids:
		lose_card(cid)

	var fin_res := _finish_encounter("escape", enc.get("on_escape", {}))
	return { "ok": true, "reason_code": "", "reason_text": "", "lines": fin_res.get("lines", PackedStringArray()) }


## 遭遇結束出口（內部 helper）。
func _finish_encounter(outcome: String, effect_data: Dictionary) -> Dictionary:
	var beat_id := str(active_encounter.get("beat_id", ""))
	var beat: Dictionary = Data.loader.beats_by_id.get(beat_id, {}) as Dictionary if Data != null and Data.loader != null else {}
	var enc: Dictionary = beat.get("encounter", {}) as Dictionary
	var after_finish := str(enc.get("after_finish", "stay"))

	active_encounter.clear()

	var gen_before := run_generation
	var lines := PackedStringArray()
	if not effect_data.is_empty():
		lines.append_array(EffectApply.apply(effect_data, self))

	if run_generation != gen_before:
		return { "ok": true, "outcome": outcome, "lines": lines }

	if after_finish == "advance_phase":
		var adv_res := advance_phase()
		lines.append_array(adv_res.get("lines", PackedStringArray()))

	return { "ok": true, "outcome": outcome, "lines": lines }


## 檢查可用格數是否歸零或小於 0（容量超載失敗，K-135/K-136）。
func _check_encounter_capacity_failure() -> bool:
	var hand_size := int(Data.tuning("hand_size", 14)) if Data != null else 14
	var blocked := int(active_encounter.get("blocked_slots", 0))
	return (hand_size - hand.size() - blocked) <= 0


# ── 序列化 ──────────────────────────────────────────────────────────────────

func serialize() -> Dictionary:
	var reports_copy: Array[Dictionary] = []
	for r: Dictionary in pending_delegation_reports:
		reports_copy.append(r.duplicate())

	return {
		"run": {
			"day": day,
			"phase": phase,
			"action_spent": action_spent,
			"actions_spent_ahead": _actions_spent_ahead,
			"hand": hand.duplicate(),
			"madness_clock": madness_clock.duplicate(),
			"_madness_counter": _madness_counter,
			"beats_entered": beats_entered.duplicate(),
			"slots_placed": slots_placed.duplicate(),
			"choices": choices.duplicate(),
			"flags": flags.duplicate(),
			"switches": switches.duplicate(),
			"switch_progress": switch_progress.duplicate(),
			"relations": relations.duplicate(),
			"npc_action_counts": npc_action_counts.duplicate(),
			"night_location_chosen": night_location_chosen,
			"night_sleep_pending": night_sleep_pending,
			"indulgence_count": indulgence_count,
			"madness_cards_cleared": madness_cards_cleared,
			"forced_pending": forced_pending.duplicate(),
			"delegates_used_today": delegates_used_today.duplicate(),
			"pending_delegation_reports": reports_copy,
			"active_encounter": active_encounter.duplicate(true),
		},
		"meta": {
			"knowledge": knowledge.duplicate(),
			"night_locations_seen": night_locations_seen.duplicate(),
			"night_once_beats_seen": night_once_beats_seen.duplicate(),
			"delegation_tutorial_seen": delegation_tutorial_seen,
		}
	}


func deserialize(d: Dictionary) -> void:
	var run: Dictionary = d.get("run", {})
	day = int(run.get("day", 1))
	phase = str(run.get("phase", "morning"))
	action_spent = bool(run.get("action_spent", false))
	_actions_spent_ahead = int(run.get("actions_spent_ahead", 0))
	hand.clear()
	for item in run.get("hand", []):
		hand.append(str(item))
	madness_clock.clear()
	var mc: Dictionary = run.get("madness_clock", {})
	for k in mc.keys():
		madness_clock[str(k)] = int(mc[k])
	_madness_counter = int(run.get("_madness_counter", 0))
	beats_entered = run.get("beats_entered", {}).duplicate()
	slots_placed = run.get("slots_placed", {}).duplicate()
	choices = run.get("choices", {}).duplicate()
	flags = run.get("flags", {}).duplicate()
	switches = run.get("switches", {}).duplicate()
	switch_progress = run.get("switch_progress", {}).duplicate()
	relations = run.get("relations", {}).duplicate()
	npc_action_counts = run.get("npc_action_counts", {}).duplicate()
	night_location_chosen = str(run.get("night_location_chosen", ""))
	night_sleep_pending = bool(run.get("night_sleep_pending", false))
	indulgence_count = int(run.get("indulgence_count", 0))
	madness_cards_cleared = int(run.get("madness_cards_cleared", 0))
	forced_pending.clear()
	for item in run.get("forced_pending", []):
		forced_pending.append(str(item))
	delegates_used_today.clear()
	var dut: Dictionary = run.get("delegates_used_today", {})
	for k in dut.keys():
		delegates_used_today[str(k)] = bool(dut[k])
	pending_delegation_reports.clear()
	for item in run.get("pending_delegation_reports", []):
		if item is Dictionary:
			pending_delegation_reports.append((item as Dictionary).duplicate())

	active_encounter.clear()
	var enc_raw: Dictionary = run.get("active_encounter", {})
	if not enc_raw.is_empty():
		active_encounter["beat_id"] = str(enc_raw.get("beat_id", ""))
		active_encounter["stage"] = str(enc_raw.get("stage", "intro"))
		active_encounter["round_id"] = str(enc_raw.get("round_id", ""))
		active_encounter["blocked_slots"] = int(enc_raw.get("blocked_slots", 0))
		var att: Array[String] = []
		for item in enc_raw.get("attempted_card_ids", []):
			att.append(str(item))
		active_encounter["attempted_card_ids"] = att
		var vis: Array[String] = []
		for item in enc_raw.get("visited_round_ids", []):
			vis.append(str(item))
		active_encounter["visited_round_ids"] = vis

	var meta: Dictionary = d.get("meta", {})
	knowledge = meta.get("knowledge", {}).duplicate()
	night_locations_seen = meta.get("night_locations_seen", {}).duplicate()
	night_once_beats_seen = meta.get("night_once_beats_seen", {}).duplicate()
	delegation_tutorial_seen = bool(meta.get("delegation_tutorial_seen", false))


# ── 內部工具 ─────────────────────────────────────────────────────────────────

func _card_base_id(id: String) -> String:
	return DataFacts.card_base_id(id)

