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

# --- 頂層流程（flow 層；不屬於任一輪，開發設計方針 P5-B）---
const FLOW_OPENING := "opening"
const FLOW_RUN := "run"
const FLOW_ENDING := "ending"
const FLOW_MODES := [FLOW_OPENING, FLOW_RUN, FLOW_ENDING]

## 封閉的 source ↔ ending 配對。未知 source、已知 source 配錯 ending 都不是合法來源。
const ENDING_SOURCE_PAIRS := {
	"madness_cap": "ending_madness_be",
	"ending_effect": "ending_inventory_be",
	"d45_coda": "ending_replaced",
	"opening_choice": "ending_refuse_boarding",
}

## 公開 `start_ending()` 只收這三個 run 來源。`opening_choice` 專屬 P5-D 的
## `_start_ending_from_opening()`，在 run 生命週期中不得成立。
const RUN_ENDING_SOURCES := ["madness_cap", "ending_effect", "d45_coda"]

## 三個 variant 欄位。欄名去掉 `_variant` 就是 `endings.json` 的 variant group id，
## 因此「這個 ending 該不該有這一欄」由資料決定，不由這裡列白名單。
const ENDING_VARIANT_KEYS := ["partner_variant", "livelihood_variant", "inn_appearance_variant"]
const ENDING_REPLACED := "ending_replaced"
const ENDING_REFUSE_BOARDING := "ending_refuse_boarding"

## active_ending 快照的固定欄位；缺一不可，也不得用空字串代替 null。
const ENDING_SNAPSHOT_KEYS := [
	"ending_id", "source_id", "run_number", "opening_choice_id", "ended_day", "ended_phase",
	"partner_variant", "livelihood_variant", "inn_appearance_variant", "festival_proxy_npc",
	"knowledge_gained_this_run", "page_refs", "page_index", "page_revealed", "ready_to_complete",
]

# --- 時間群（run 層）---
var day: int = 1
var phase: String = "morning"

# --- 手牌群 ---
var hand: Array[String] = []          # 佔格卡 id，有序；主角卡恆在 index 0（run 層）
var knowledge: Dictionary = {}        # id -> true（Set；slotless 卡；meta 層，不隨輪重置）
var night_locations_seen: Dictionary = {} # location_id -> true（meta 層，不隨輪重置）
var night_once_beats_seen: Dictionary = {} # beat_id -> true（meta 層，不隨輪重置）
var day_locations_visited: Dictionary = {} # location_id -> true（meta 層，不隨輪重置）
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
var last_auto_enter_lines: PackedStringArray = [] # 當前時段自動進場 beat 產生的演出文字行（transient UI）
var last_choice_default_lines: PackedStringArray = [] # 離場前結算的逾期 choice default 演出文字行（transient UI）
var run_generation: int = 0                    # 輪次世代計數（單調遞增，供 EffectApply 與結算器偵測 end_run）

# --- 頂層流程與結局狀態機（P5-B）---
var flow_mode: String = FLOW_OPENING           # opening／run／ending；fresh boot 一律從開局進場（P5-D）
var active_ending: Dictionary = {}             # 空＝序列化的 null；只有 ending mode 非空
var opening_choice_id: String = ""             # 本輪由哪個開局選項進場；""＝序列化的 null（run 層）
var knowledge_at_start: Dictionary = {}        # 開輪時的 knowledge set；只供結局凍結當輪新增知識（run 層）
var selected_festival_proxy_npc: String = ""   # D29 一次固定；""＝序列化的 null（run 層）
var run_number: int = 1                        # 即將／正在結算的輪次（meta 層）
var ending_history: Array[Dictionary] = []     # 精簡歷輪結果，append-only（meta 層）
var loop_persistent_item_ids: Dictionary = {}  # card id -> true；真正跨輪的魔法物品（meta 層）
var simulation_mode: bool = false              # true＝本實例是 preflight 複本，發狂上限只記錄不啟動結局
var pending_ending_request: Dictionary = {}    # 複本上記下的結局請求（simulation_mode 專用）

signal phase_changed(day: int, phase: String)
signal day_changed(day: int)
signal chapter_changed(chapter: int)
signal flow_mode_changed(mode: String)
signal ending_started
signal ending_page_changed
signal opening_started
signal hand_changed
signal knowledge_changed
signal delegation_tutorial_available # P4-C：玩家首次由零張變一張 person card 時發出，UI 顯示並關閉／略過後才呼叫 mark_delegation_tutorial_seen()


# ── 時段狀態機 ──────────────────────────────────────────────────────────────

func chapter() -> int:
	return DataFacts.chapter_for_day(day)


## 時段推進的唯一公開入口（開發設計方針 P5-D）。
## 固定七步：
##   ① `flow.mode != "run"` → `not_run`
##   ② active encounter → `encounter_active`
##   ③ 夜間停拍：已選地點直接續行；`night_sleep_pending` 由本次 transition 清掉後續行；
##      兩者皆無才解析睡覺，有文字就只停拍（`phase_advanced:false`），無文字才續行
##   ④ 當下所有逾期 choice group default 的純 preflight → `unresolved_choice_conflict`
##   ⑤ 當下所有 fixed beat 的 `phase_exit` 門檻 → `phase_requirements_incomplete`
##   ⑥ 目標 day／phase 與可能的 ending／source／snapshot 驗證 → `data_conflict`
##   ⑦ 一次 commit 逾期預設與 transition（或 D45 結局）
## 任一拒絕都必須完整 serialize 零變化。
## 回傳：{ ok, reason_code, reason_text, lines, phase_advanced }
func advance_phase() -> Dictionary:
	# ① mode gate
	if flow_mode != FLOW_RUN:
		return _advance_reject("not_run", _REASON_TEXT_NOT_RUN)

	# ② 遭遇進行中
	if not active_encounter.is_empty():
		return _advance_reject("encounter_active", "遭遇進行中，無法推進時段")

	# ③ 夜間停拍。只有「還沒選地點也還沒睡過」才需要解析睡覺；
	#    此時若真的有內容就停在原時段，讓玩家先讀完再按一次。
	#    解析睡覺本身會結算 beat，因此刻意排在 ④ 之前——它成功時直接回傳，
	#    不會與後面的拒絕碼共用同一條路徑。
	if phase == "night" and night_location_chosen.is_empty() and not night_sleep_pending:
		var sleep_lines := sleep_night()
		if sleep_lines.size() > 0:
			night_sleep_pending = true
			return { "ok": true, "reason_code": "", "reason_text": "", "lines": sleep_lines, "phase_advanced": false }
		# 睡覺內容的效果也可能把玩家推進結局，之後就不該再推進時段。
		if flow_mode != FLOW_RUN:
			return { "ok": true, "reason_code": "", "reason_text": "", "lines": PackedStringArray(), "phase_advanced": false }

	# ④ 逾期 choice group default：只 preflight，不落地。
	var defaults := resolve_unfinished_choice_groups()
	if not bool(defaults.get("ok", false)):
		return _advance_reject("unresolved_choice_conflict", str(defaults.get("reason_text", "")))
	var default_plan: Dictionary = defaults.get("plan", {}) as Dictionary

	# ⑤ 通用 phase_exit 門檻（SCHEMA phase_exit、P5-B）：規則層只掃當下 fixed beat 的
	#    資料欄位，不看 beat id 或槽 id 字面值。
	var gate := _phase_exit_gate()
	var has_gate := bool(gate.get("has_gate", false))
	if has_gate and not bool(gate.get("satisfied", false)):
		return _advance_reject("phase_requirements_incomplete", "本時段的內容尚未完成")

	var gate_ending := str(gate.get("ending", "")) if has_gate else ""

	# 第二道防線：最後一天的 evening 只有結局一個出口。門檻沒接上（資料壞掉或
	# 條件不成立）時寧可卡在原地，也不能讓時段機把玩家送進第 46 天。
	if day == LAST_DAY and phase == "evening" and gate_ending.is_empty():
		return _advance_reject("phase_requirements_incomplete", "本時段的內容尚未完成")

	# ⑥ 目標與結局資料驗證。逾期預設會影響結局快照（D29 的代付者就是這樣凍結的），
	#    因此快照要在「已套完預設」的複本上算，不能用當下狀態。
	var ending_snapshot: Dictionary = {}
	if not gate_ending.is_empty():
		var ending_shadow := clone_for_preflight()
		if ending_shadow == null:
			return _advance_reject("data_conflict", "preflight 複本建立失敗")
		_commit_choice_default_plan(default_plan, ending_shadow)
		var plan := _build_ending_plan(gate_ending, str(gate.get("source", "")), ending_shadow)
		ending_shadow.free()
		if not bool(plan.get("ok", false)):
			return _advance_reject("data_conflict", str(plan.get("reason_text", "")))
		ending_snapshot = plan.get("snapshot", {}) as Dictionary
	else:
		var target := _next_phase_target()
		if int(target.get("day", 0)) > LAST_DAY:
			# 最後一天沒有 night，走到這裡代表資料把玩家帶往第 46 天。
			return _advance_reject("data_conflict", "推進目標超出最後一天")
		# 目標時段的 fixed 遭遇由規則層自動建立，UI 沒有第二次機會擋。任何一筆壞掉
		# 就必須在換時段之前擋下來——換過去才發現，玩家會停在一個「本該有遭遇卻沒有」
		# 的時段，而且狀態已經動了。
		var enc_error := _due_encounter_data_error(int(target.get("day", 0)), str(target.get("phase", "")))
		if not enc_error.is_empty():
			return _advance_reject("data_conflict", enc_error)

	# ⑦ 一次 commit：先落地逾期預設，再走 transition 或啟動結局。
	_commit_choice_default_plan(default_plan, self)
	var lines: PackedStringArray = defaults.get("lines", PackedStringArray())
	# 逾期預設發生在換時段之前，因此它的文字要在新時段的畫面最上面。
	# `_commit_phase_transition()` 刻意不清這一個 transient（其餘三個它自己清）。
	last_choice_default_lines = lines

	if not ending_snapshot.is_empty():
		_commit_ending_plan(ending_snapshot)
		return { "ok": true, "reason_code": "", "reason_text": "", "lines": lines, "phase_advanced": false }

	_commit_phase_transition()
	return { "ok": true, "reason_code": "", "reason_text": "", "lines": lines, "phase_advanced": true }


func _advance_reject(code: String, text: String) -> Dictionary:
	return { "ok": false, "reason_code": code, "reason_text": text, "lines": PackedStringArray(), "phase_advanced": false }


## 純函式：一般推進的目標時段。與 `_commit_phase_transition()` 的走法必須一致。
## 第 45 天 afternoon 直接跳 evening（沒有第 45 夜）。
func _next_phase_target() -> Dictionary:
	if day == LAST_DAY and phase == "afternoon":
		return { "day": day, "phase": "evening" }
	var idx := PHASES.find(phase)
	if idx < PHASES.size() - 1:
		return { "day": day, "phase": PHASES[idx + 1] }
	return { "day": day + 1, "phase": PHASES[0] }


## 純函式：目標時段所有掛遭遇的 fixed beat 的資料檢查。回空字串＝全部合格。
## 這裡刻意不求值 condition——換時段途中的 auto_enter 效果可能才讓某個遭遇成立，
## 因此「哪一個會開場」在 commit 前無法確定，能確定的是**任何一個都不能是壞資料**。
func _due_encounter_data_error(target_day: int, target_phase: String) -> String:
	if Data == null or Data.loader == null:
		return "資料未載入"
	if target_phase == "night":
		return ""
	for b in Data.loader.beats_at(target_day, target_phase):
		if not bool(b.get("fixed", false)) or not b.has("encounter"):
			continue
		var err := _encounter_data_error(b)
		if not err.is_empty():
			return err
	return ""


## 遭遇資料形狀的唯一檢查點：`start_encounter()` 與換時段前的預檢共用同一份規則，
## 避免兩份分歧的判斷讓「預檢過了、真的開場卻失敗」。回空字串＝資料合格。
func _encounter_data_error(beat: Dictionary) -> String:
	if not beat.has("encounter"):
		return "未知的遭遇事件"
	var enc_val: Variant = beat.get("encounter")
	if not enc_val is Dictionary:
		return "遭遇資料格式錯誤"
	var enc := enc_val as Dictionary
	var rounds_val: Variant = enc.get("rounds")
	if not rounds_val is Array or (rounds_val as Array).is_empty():
		return "遭遇資料缺少回合定義"
	if not enc.has("per_round_slot_cost") or int(enc.get("per_round_slot_cost", 0)) < 0:
		return "遭遇資料 slot_cost 錯誤"
	if not enc.has("after_finish"):
		return "遭遇資料缺少 after_finish"
	return ""


## 真正換時段的那一步。只在 advance_phase() 第 ⑦ 步呼叫，別處不得複製一份。
func _commit_phase_transition() -> void:
	var prev_ch := chapter()

	# 第 45 天特殊路徑：afternoon → evening（結局 coda）；evening 由 phase_exit 門檻接結局，不進 night
	if day == LAST_DAY and phase == "afternoon":
		phase = "evening"
		action_spent = false
		last_forced_lines.clear()
		last_delegation_report_lines.clear()
		last_auto_enter_lines = _settle_auto_enter_beats()
		if flow_mode == FLOW_RUN:
			_check_fixed_encounter_for_current_phase()
		phase_changed.emit(day, phase)
		return

	last_forced_lines.clear()
	last_delegation_report_lines.clear()
	last_auto_enter_lines.clear()

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

	# 生命週期 beat 先於固定遭遇：遭遇的 condition 可能就靠這一步寫進來的旗標。
	last_auto_enter_lines = _settle_auto_enter_beats()

	# 換時段途中若被強制縱慾、委託回報或自動進場的效果推進到結局，就不再自動建立新遭遇。
	if flow_mode == FLOW_RUN:
		_check_fixed_encounter_for_current_phase()

	phase_changed.emit(day, phase)

	var new_ch := chapter()
	if new_ch != prev_ch:
		chapter_changed.emit(new_ch)


## 進入時段時自動結算的 fixed beat（SCHEMA `auto_enter`）。
## 這類 beat 是時段生命週期的一部分，不能等玩家主動打開某個地點才成立——
## D45 的終局鏈就是靠這條走通的。規則層只讀資料欄位，不特判 beat id。
## `play_beat()` 的 on_enter 只結算一次，因此重複進場只會重播文字。
func _settle_auto_enter_beats() -> PackedStringArray:
	var lines := PackedStringArray()
	if Data == null or Data.loader == null or flow_mode != FLOW_RUN:
		return lines
	for b in Data.loader.beats_at(day, phase):
		if not bool(b.get("fixed", false)) or not bool(b.get("auto_enter", false)):
			continue
		if not ConditionEval.eval(b.get("condition"), self) or not ConditionEval.eval(b.get("requires"), self):
			continue
		lines.append_array(play_beat(str(b.get("id", ""))))
		# 自動進場的效果本身也可能啟動結局，之後就不該再播下一個。
		if flow_mode != FLOW_RUN:
			break
	return lines


## P1～P4 run 層欄位的唯一窮舉清除點（開發設計方針 P5-D）。
## **不重建主角卡**——手牌由 `choose_opening()` 依開局選項與跨輪魔法物品重新組裝。
## meta 層（knowledge、night seen、教學、run_number、ending_history、persistent set）一律不動。
func _reset_run_state() -> void:
	run_generation += 1

	day = 1
	phase = PHASES[0]
	action_spent = false
	_actions_spent_ahead = 0

	hand.clear()
	madness_clock.clear()
	_madness_counter = 0

	beats_entered.clear()
	slots_placed.clear()
	choices.clear()

	flags.clear()
	switches.clear()
	switch_progress.clear()
	relations.clear()
	npc_action_counts.clear()

	night_location_chosen = ""
	night_sleep_pending = false
	indulgence_count = 0
	madness_cards_cleared = 0
	forced_pending.clear()
	last_forced_lines.clear()
	last_auto_enter_lines.clear()
	last_choice_default_lines.clear()

	delegates_used_today.clear()
	pending_delegation_reports.clear()
	last_delegation_report_lines.clear()

	active_encounter.clear()

	opening_choice_id = ""
	knowledge_at_start.clear()
	selected_festival_proxy_npc = ""


# ── 頂層流程與結局狀態機（P5-B）─────────────────────────────────────────────

const _REASON_TEXT_NOT_RUN := "本輪已結束，無法再進行遊戲操作"


## 所有 run 層 mutation 的第一道 gate。回空字典＝目前是 run mode，可以繼續。
func _reject_unless_run() -> Dictionary:
	if flow_mode == FLOW_RUN:
		return {}
	return _mutation_reject("not_run", _REASON_TEXT_NOT_RUN)


func _mutation_reject(code: String, text: String) -> Dictionary:
	return { "ok": false, "reason_code": code, "reason_text": text, "lines": PackedStringArray() }


## 歷輪是否已看過同一 ending id（只掃 history，不看 run_number）。
func has_seen_ending(ending_id: String) -> bool:
	for record: Dictionary in ending_history:
		if str(record.get("ending_id", "")) == ending_id:
			return true
	return false


## ConditionEval `ending_seen` 的查詢接點。
func ending_seen(ending_id: String) -> bool:
	return has_seen_ending(ending_id)


## 資料 loader 的取得接點，讓 core 腳本不必自己抓 autoload。
func loader() -> DataLoader:
	return Data.loader if Data != null else null


## D29 慶典代付者的唯一寫入點；已凍結時不覆寫（EffectApply 已在 preflight 擋下）。
func set_festival_proxy(npc_id: String) -> void:
	if npc_id.is_empty():
		push_error("set_festival_proxy: empty npc id")
		return
	if not selected_festival_proxy_npc.is_empty():
		push_error("set_festival_proxy: 已凍結為 '%s'，拒絕覆寫為 '%s'" % [selected_festival_proxy_npc, npc_id])
		return
	selected_festival_proxy_npc = npc_id


## 建立 preflight 用的複本：同一份序列化狀態、simulation_mode 打開。**呼叫端負責 free()**。
func clone_for_preflight() -> Node:
	var shadow: Node = (get_script() as GDScript).new()
	var res: Dictionary = shadow.call("deserialize", serialize())
	if not bool(res.get("ok", false)):
		push_error("clone_for_preflight: deserialize 失敗 (%s)" % str(res.get("reason_code", "unknown")))
		shadow.free()
		return null
	shadow.set("simulation_mode", true)
	shadow.set("pending_ending_request", {})
	return shadow


## 結局啟動的唯一公開入口（run 來源）。固定檢查順序：
## mode run → 無 active ending → ending 存在 → source 與 ending 精確配對 →
## source 屬於 run 生命週期 → ending 專屬前置完整 → resolver 成功。
## 拒絕後完整序列化零變化。
func start_ending(ending_id: String, source_id: String) -> Dictionary:
	if flow_mode != FLOW_RUN:
		return _mutation_reject("not_run", _REASON_TEXT_NOT_RUN)
	if not active_ending.is_empty():
		return _mutation_reject("ending_active", "已有進行中的結局")

	var plan := _build_ending_plan(ending_id, source_id, self)
	if not bool(plan.get("ok", false)):
		return _mutation_reject(str(plan.get("reason_code", "data_conflict")), str(plan.get("reason_text", "")))

	_commit_ending_plan(plan.get("snapshot", {}) as Dictionary)
	return { "ok": true, "reason_code": "", "reason_text": "", "lines": PackedStringArray() }


## 純函式：依 `src` 的當下狀態建結局快照，不寫任何狀態。
## `src` 可以是自己，也可以是 preflight 複本（因此快照看得到剛完成的動作）。
## `allow_opening_source` 只有 P5-D 的 opening 私有入口會給 true。
## 回傳：{ ok, reason_code, reason_text, snapshot }
func _build_ending_plan(ending_id: String, source_id: String, src: Node, allow_opening_source: bool = false) -> Dictionary:
	if Data == null or Data.loader == null:
		return { "ok": false, "reason_code": "data_conflict", "reason_text": "資料未載入", "snapshot": {} }
	if not Data.loader.endings_by_id.has(ending_id):
		return { "ok": false, "reason_code": "unknown_ending", "reason_text": "", "snapshot": {} }
	if str(ENDING_SOURCE_PAIRS.get(source_id, "")) != ending_id:
		return { "ok": false, "reason_code": "invalid_ending_source", "reason_text": "", "snapshot": {} }
	# 配對正確不代表這條入口收得起：run 生命週期只認 RUN_ENDING_SOURCES。
	if not allow_opening_source and not RUN_ENDING_SOURCES.has(source_id):
		return { "ok": false, "reason_code": "invalid_ending_source", "reason_text": "來源不屬於 run 生命週期：%s" % source_id, "snapshot": {} }

	var frozen_proxy := str(src.get("selected_festival_proxy_npc"))
	var is_composite := ending_id == ENDING_REPLACED
	if is_composite:
		# 結局當下不得重算投入：代付者必須已在 D29 凍結，且必須是正式候選。
		if frozen_proxy.is_empty() or not _is_festival_candidate(frozen_proxy):
			return { "ok": false, "reason_code": "data_conflict", "reason_text": "慶典代付者尚未凍結", "snapshot": {} }

	var resolved := EndingResolver.resolve(ending_id, src, Data.loader)
	if not bool(resolved.get("ok", false)):
		return { "ok": false, "reason_code": str(resolved.get("reason_code", "data_conflict")), "reason_text": "", "snapshot": {} }

	var refs: Array[String] = []
	for ref: Variant in resolved.get("page_refs", []) as Array:
		var ref_str := str(ref)
		if not bool(EndingResolver.resolve_ref(ref_str, Data.loader).get("ok", false)):
			return { "ok": false, "reason_code": "data_conflict", "reason_text": "page ref 無法解析：%s" % ref_str, "snapshot": {} }
		refs.append(ref_str)

	var variants: Dictionary = resolved.get("variants", {}) as Dictionary
	var is_refuse := ending_id == ENDING_REFUSE_BOARDING
	var src_opening := str(src.get("opening_choice_id"))

	var snapshot := {
		"ending_id": ending_id,
		"source_id": source_id,
		"run_number": int(src.get("run_number")),
		"opening_choice_id": _opening_choice_for_ending(ending_id) if is_refuse else (null if src_opening.is_empty() else src_opening),
		"ended_day": null if is_refuse else int(src.get("day")),
		"ended_phase": null if is_refuse else str(src.get("phase")),
		"partner_variant": variants.get("partner_variant", null),
		"livelihood_variant": variants.get("livelihood_variant", null),
		"inn_appearance_variant": variants.get("inn_appearance_variant", null),
		# 正常結局用凍結值；兩種 BE 有凍結就複製，不上車一律 null。
		"festival_proxy_npc": null if (is_refuse or frozen_proxy.is_empty()) else frozen_proxy,
		"knowledge_gained_this_run": [] as Array[String] if is_refuse else _knowledge_gained_since_start(src),
		"page_refs": refs,
		"page_index": 0,
		"page_revealed": false,
		"ready_to_complete": false,
	}
	return { "ok": true, "reason_code": "", "reason_text": "", "snapshot": snapshot }


## 開局選擇不上車啟動結局的私有入口（P5-D 由 choose_opening 呼叫，P5-C/D 測試共用）。
func _start_ending_from_opening(choice_id: String) -> Dictionary:
	if flow_mode != FLOW_OPENING:
		return _mutation_reject("not_opening", "目前不在開局中")
	if not active_ending.is_empty():
		return _mutation_reject("ending_active", "已有進行中的結局")
	if Data == null or Data.loader == null:
		return _mutation_reject("data_conflict", "資料未載入")
	var choice: Dictionary = Data.loader.opening_choices_by_id.get(choice_id, {}) as Dictionary
	if choice.is_empty():
		return _mutation_reject("unknown_opening_choice", "未知的開局選項：%s" % choice_id)
	var ending_id := str(choice.get("ending", ""))
	if ending_id.is_empty():
		return _mutation_reject("data_conflict", "開局選項未設定 ending")

	var plan := _build_ending_plan(ending_id, "opening_choice", self, true)
	if not bool(plan.get("ok", false)):
		return _mutation_reject(str(plan.get("reason_code", "data_conflict")), str(plan.get("reason_text", "")))

	_commit_ending_plan(plan.get("snapshot", {}) as Dictionary)
	return { "ok": true, "reason_code": "", "reason_text": "", "lines": PackedStringArray() }


## 快照落地：先寫 active_ending，再切 mode，最後才通知 UI。
func _commit_ending_plan(snapshot: Dictionary) -> void:
	active_ending = snapshot
	flow_mode = FLOW_ENDING
	flow_mode_changed.emit(FLOW_ENDING)
	ending_started.emit()


## 本輪新增的知識卡，依 `cards.json` 資料順序輸出，確保快照可逐字比較。
func _knowledge_gained_since_start(src: Node) -> Array[String]:
	var gained: Array[String] = []
	var now_set: Dictionary = src.get("knowledge") as Dictionary
	var start_set: Dictionary = src.get("knowledge_at_start") as Dictionary
	if Data == null or Data.loader == null:
		return gained
	for card_id: Variant in Data.loader.cards.keys():
		var cid := str(card_id)
		if now_set.has(cid) and not start_set.has(cid):
			gained.append(cid)
	return gained


func _is_festival_candidate(npc_id: String) -> bool:
	if Data == null or Data.loader == null or not Data.loader.npcs.has(npc_id):
		return false
	return (Data.loader.npcs[npc_id] as Dictionary).get("festival_proxy_eligible", false) == true


## 結局畫面的唯一查詢入口：只回玩家可見資訊，不洩漏 condition、ending id、未採用 variant
## 或後續頁內容。非 ending mode 回空字典。
func ending_view() -> Dictionary:
	if flow_mode != FLOW_ENDING or active_ending.is_empty():
		return {}
	var refs: Array = active_ending.get("page_refs", []) as Array
	var idx := int(active_ending.get("page_index", 0))
	var page_text := ""
	if idx >= 0 and idx < refs.size():
		var page := EndingResolver.resolve_ref(str(refs[idx]), Data.loader if Data != null else null)
		if bool(page.get("ok", false)):
			page_text = str(page.get("text", ""))
	var ready := bool(active_ending.get("ready_to_complete", false))
	return {
		"page_text": page_text,
		"page_index": idx,
		"page_count": refs.size(),
		"page_revealed": bool(active_ending.get("page_revealed", false)),
		"is_last_page": idx == refs.size() - 1,
		"can_skip": has_seen_ending(str(active_ending.get("ending_id", ""))) and not ready,
		"can_complete": ready,
	}


## 三個 page mutation 的共用前置：mode ending → active 存在 → 尚未 ready。
func _ending_stage_gate() -> Dictionary:
	if flow_mode != FLOW_ENDING:
		return _mutation_reject("not_ending", "目前不在結局中")
	if active_ending.is_empty():
		return _mutation_reject("no_active_ending", "沒有進行中的結局")
	if bool(active_ending.get("ready_to_complete", false)):
		return _mutation_reject("wrong_ending_stage", "結局已可結算")
	return {}


## 逐字補完當頁。typewriter 自然跑完或玩家要求補完都走這裡。
## 揭露末頁時同一步把 ready_to_complete 設為 true。
func reveal_ending_page() -> Dictionary:
	var gate := _ending_stage_gate()
	if not gate.is_empty():
		return gate
	if bool(active_ending.get("page_revealed", false)):
		return _mutation_reject("already_revealed", "本頁已完整顯示")
	var idx := int(active_ending.get("page_index", 0))
	if not _page_ref_playable(idx):
		return _mutation_reject("data_conflict", "結局頁面資料異常")

	active_ending["page_revealed"] = true
	if idx == (active_ending.get("page_refs", []) as Array).size() - 1:
		active_ending["ready_to_complete"] = true
	ending_page_changed.emit()
	return { "ok": true, "reason_code": "", "reason_text": "", "lines": PackedStringArray() }


## 翻頁。只接受「已揭露且非末頁」；同一次輸入不得同時補完與翻頁，因此呼叫端只能擇一。
func advance_ending_page() -> Dictionary:
	var gate := _ending_stage_gate()
	if not gate.is_empty():
		return gate
	if not bool(active_ending.get("page_revealed", false)):
		return _mutation_reject("page_not_revealed", "本頁尚未完整顯示")
	var idx := int(active_ending.get("page_index", 0))
	if idx >= (active_ending.get("page_refs", []) as Array).size() - 1:
		return _mutation_reject("last_page", "已是最後一頁")
	if not _page_ref_playable(idx + 1):
		return _mutation_reject("data_conflict", "結局頁面資料異常")

	active_ending["page_index"] = idx + 1
	active_ending["page_revealed"] = false
	ending_page_changed.emit()
	return { "ok": true, "reason_code": "", "reason_text": "", "lines": PackedStringArray() }


## 重見同一 ending id 才提供的整段跳過；落點由資料的 `repeat.skip_to` 指定。
## 首見一律 `ending_not_seen`，偽造呼叫也擋在規則層。任何跳過都不寫 history。
func skip_seen_ending() -> Dictionary:
	var gate := _ending_stage_gate()
	if not gate.is_empty():
		return gate
	var ending_id := str(active_ending.get("ending_id", ""))
	if not has_seen_ending(ending_id):
		return _mutation_reject("ending_not_seen", "這個結局還沒看過，不能跳過")

	var target := EndingResolver.skip_target(ending_id, Data.loader if Data != null else null)
	if target.is_empty():
		return _mutation_reject("data_conflict", "結局缺少跳過落點")

	var refs: Array = active_ending.get("page_refs", []) as Array
	var last_index := refs.size() - 1
	var target_index := last_index
	if target != EndingResolver.SKIP_COMPLETE:
		target_index = -1
		for i in range(refs.size()):
			if EndingResolver.page_id_of(str(refs[i])) == target:
				target_index = i
				break
		if target_index < 0:
			return _mutation_reject("data_conflict", "跳過落點不在本次結局頁面內")
	if not _page_ref_playable(target_index):
		return _mutation_reject("data_conflict", "結局頁面資料異常")

	active_ending["page_index"] = target_index
	active_ending["page_revealed"] = true
	if target_index == last_index:
		active_ending["ready_to_complete"] = true
	ending_page_changed.emit()
	return { "ok": true, "reason_code": "", "reason_text": "", "lines": PackedStringArray() }


func _page_ref_playable(idx: int) -> bool:
	var refs: Array = active_ending.get("page_refs", []) as Array
	if idx < 0 or idx >= refs.size():
		return false
	if Data == null or Data.loader == null:
		return false
	return bool(EndingResolver.resolve_ref(str(refs[idx]), Data.loader).get("ok", false))


# ── 開局、歷輪摘要與跨輪重置（P5-D）─────────────────────────────────────────

## 結局結算時發給玩家的跨輪知識卡。資料層由 lint 保證它存在且是 slotless 知識卡。
const RETURNED_KNOWLEDGE_CARD := "k_i_returned"

## history record 的封閉欄位集合。active snapshot 的結果摘要，
## **不含** `source_id`、`page_refs`、頁面進度或任何 UI 字串。
const HISTORY_RECORD_KEYS := [
	"run_number", "ending_id", "opening_choice_id", "ended_day", "ended_phase",
	"partner_variant", "livelihood_variant", "inn_appearance_variant",
	"festival_proxy_npc", "knowledge_gained_this_run",
]


## 開局畫面的故事文案 view model。UI 不讀 raw JSON，也不在腳本複製故事字串。
func opening_screen_view() -> Dictionary:
	if Data == null or Data.loader == null:
		return {}
	return {
		"title": str(Data.loader.opening_screen.get("title", "")),
		"prompt": str(Data.loader.opening_screen.get("prompt", "")),
	}


## 開局畫面的唯一查詢入口。依 `opening_choices.json` 資料順序回傳，
## 只給玩家看得到的字串與鎖定理由，不洩漏 unlock condition 或 `on_select`。
func opening_view() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if Data == null or Data.loader == null:
		return out
	for choice: Dictionary in Data.loader.opening_choices:
		var available := ConditionEval.eval(choice.get("requires"), self)
		out.append({
			"id": str(choice.get("id", "")),
			"label": str(choice.get("label", "")),
			"preview": str(choice.get("preview", "")),
			"confirm_text": str(choice.get("confirm_text", "")),
			"available": available,
			"reason_text": "" if available else str(choice.get("reject_reason", _REASON_LOCKED_FALLBACK)),
		})
	return out


## 開局選項的唯一確認入口。檢查順序固定：
## mode opening → choice 存在 → unlock 成立 → 資料形狀合法。
## `on_select` 形狀初始化 run；`ending` 形狀不建立 run，直接進結局。
## 拒絕後完整序列化零變化。
func choose_opening(choice_id: String) -> Dictionary:
	if flow_mode != FLOW_OPENING:
		return _mutation_reject("not_opening", "目前不在開局中")
	if Data == null or Data.loader == null:
		return _mutation_reject("data_conflict", "資料未載入")

	var choice: Dictionary = Data.loader.opening_choices_by_id.get(choice_id, {}) as Dictionary
	if choice.is_empty():
		return _mutation_reject("unknown_opening_choice", "未知的開局選項：%s" % choice_id)

	if not ConditionEval.eval(choice.get("requires"), self):
		return _mutation_reject("opening_choice_locked", str(choice.get("reject_reason", _REASON_LOCKED_FALLBACK)))

	# SCHEMA：每筆必須在 `on_select` 與 `ending` 中恰有一個。
	var has_ending := not str(choice.get("ending", "")).is_empty()
	var on_select_raw: Variant = choice.get("on_select")
	var has_select: bool = on_select_raw is Dictionary and not (on_select_raw as Dictionary).is_empty()
	if has_ending == has_select:
		return _mutation_reject("data_conflict", "開局選項必須恰有一個 on_select 或 ending：%s" % choice_id)

	if has_ending:
		return _start_ending_from_opening(choice_id)
	return _start_run_from_opening(choice_id, on_select_raw as Dictionary)


## 相簿／電話兩條開局的原子初始化。
## 驗證全部在複本上完成：複本先走完「重置 → 主角卡 → 恢復魔法物品 → 凍結開輪知識」，
## `on_select` 才在真正的開局初態上求值，避免上一輪殘留讓效果誤過或誤擋。
func _start_run_from_opening(choice_id: String, on_select: Dictionary) -> Dictionary:
	var probe := clone_for_preflight()
	if probe == null:
		return _mutation_reject("data_conflict", "preflight 複本建立失敗")
	_apply_run_initialization(probe)
	var pf := EffectApply.preflight([on_select], probe)
	probe.free()
	if not bool(pf.get("ok", false)):
		return _mutation_reject("data_conflict", str(pf.get("reason_text", "")))
	var pf_shadow: Node = pf.get("shadow")
	var raised_ending: bool = not (pf.get("ending_request", {}) as Dictionary).is_empty()
	if pf_shadow != null:
		pf_shadow.free()
	if raised_ending:
		return _mutation_reject("data_conflict", "開局選項的 on_select 不得啟動結局")

	_apply_run_initialization(self)
	EffectApply.commit(pf.get("plan", {}) as Dictionary, self)
	opening_choice_id = choice_id
	flow_mode = FLOW_RUN

	# 開局落地的 D1 morning 沒有經過 _commit_phase_transition()，這裡補結算一次進場
	# beat，否則第 1 天上午的演出永遠不會播。填在 emit 之前，UI 收到訊號時才讀得到。
	last_auto_enter_lines = _settle_auto_enter_beats()

	flow_mode_changed.emit(FLOW_RUN)
	day_changed.emit(day)
	phase_changed.emit(day, phase)
	chapter_changed.emit(chapter())
	hand_changed.emit()
	return { "ok": true, "reason_code": "", "reason_text": "", "lines": PackedStringArray() }


## run 初始化的固定順序，真狀態與複本共用同一條：
## `_reset_run_state()` → 主角卡 → 按 `cards.json` 資料順序恢復跨輪魔法物品 → 凍結開輪知識。
## 恢復回來的物品仍是普通手牌，照樣服從卡片既有的佔格與唯一性規則。
func _apply_run_initialization(target: Node) -> void:
	target.call("_reset_run_state")
	target.call("gain_card", "protagonist", false)
	if Data != null and Data.loader != null:
		var persistent: Dictionary = target.get("loop_persistent_item_ids") as Dictionary
		for card_id: Variant in Data.loader.cards.keys():
			var cid := str(card_id)
			if persistent.has(cid):
				target.call("gain_card", cid, false)
	target.set("knowledge_at_start", (target.get("knowledge") as Dictionary).duplicate())


## 正式的輪結束結算：任何結局都只從這裡回到開局。固定順序為
## 驗 mode／active／ready → 在記憶體中建好並驗完 history record → append →
## 取得「我回來過」→ `run_number += 1` → `_reset_run_state()` → 清 active → mode opening。
## 前三步依序回 `not_ending`、`no_active_ending`、`not_ready`；record 或引用不合法回
## `data_conflict`，且全部發生在 append 前。成功後 mode 已是 opening，重試自然回 `not_ending`。
func complete_ending() -> Dictionary:
	if flow_mode != FLOW_ENDING:
		return _mutation_reject("not_ending", "目前不在結局中")
	if active_ending.is_empty():
		return _mutation_reject("no_active_ending", "沒有進行中的結局")
	if not bool(active_ending.get("ready_to_complete", false)):
		return _mutation_reject("not_ready", "結局尚未播完")

	var record := _build_history_record(active_ending)
	if record.is_empty():
		return _mutation_reject("data_conflict", "結局結果不合法，無法寫入歷輪摘要")
	if Data == null or Data.loader == null or not Data.loader.cards.has(RETURNED_KNOWLEDGE_CARD):
		return _mutation_reject("data_conflict", "缺少跨輪知識卡：%s" % RETURNED_KNOWLEDGE_CARD)

	ending_history.append(record)
	# history 的 knowledge_gained_this_run 取自凍結快照，因此不含這一步才發的知識卡。
	gain_card(RETURNED_KNOWLEDGE_CARD)
	run_number += 1
	_reset_run_state()
	active_ending.clear()
	flow_mode = FLOW_OPENING

	flow_mode_changed.emit(FLOW_OPENING)
	opening_started.emit()
	hand_changed.emit()
	return { "ok": true, "reason_code": "", "reason_text": "", "lines": PackedStringArray() }


## 由 active snapshot 建 history record 並驗完所有引用。任一不合法回空字典（＝ data_conflict）。
## 只複製封閉欄位集合，不整包帶進 page 進度或 source。
func _build_history_record(snapshot: Dictionary) -> Dictionary:
	if Data == null or Data.loader == null:
		return {}
	# 先用讀檔那一份逐欄驗證重跑一次：ending 專屬 nullable 矩陣、variant 合法集合、
	# opening／proxy 引用、當輪知識、page ref 一致性、日期／時段型別都在裡面。
	# history 是 append-only，寧可在這裡擋下來。
	var parsed := _parse_ending_snapshot(snapshot)
	if parsed.is_empty():
		return {}

	var record: Dictionary = {}
	for key: String in HISTORY_RECORD_KEYS:
		record[key] = parsed[key]
	return record


## 當下 day／phase 所有逾期 choice group 的 default 結算計畫（只 preflight，不落地）。
## 掃描條件：父 beat 為 `fixed` 且三態成立、group 仍未結算、組內有 `default_if_unresolved` 槽。
## **不以 `beats_entered` 或面板是否開過為前置**——沒進過面板與明示走開結果必須相同。
## 任何一筆不合法就整批失敗，成功 plan 由 `advance_phase()` 最後一步一次 commit。
## 回傳：{ ok, reason_code, reason_text, lines, plan }
func resolve_unfinished_choice_groups() -> Dictionary:
	var groups := _pending_default_groups()
	if groups.is_empty():
		return { "ok": true, "reason_code": "", "reason_text": "", "lines": PackedStringArray(), "plan": {} }

	var shadow := clone_for_preflight()
	if shadow == null:
		return { "ok": false, "reason_code": "data_conflict", "reason_text": "preflight 複本建立失敗", "lines": PackedStringArray(), "plan": {} }
	var steps: Array[Dictionary] = []
	var lines := PackedStringArray()
	var expects_proxy := false

	for group: Dictionary in groups:
		var slot: Dictionary = group.get("slot", {}) as Dictionary
		var effect: Dictionary = slot.get("on_place", {}) as Dictionary
		if effect.has("festival_proxy"):
			expects_proxy = true
		var bookkeeping := {
			"choice_key": str(group.get("beat_id", "")) + "::" + str(group.get("group_id", "")),
			"choice_slot_id": str(group.get("slot_id", "")),
			"slot_key": str(group.get("beat_id", "")) + "::" + str(group.get("slot_id", "")),
		}
		# bookkeeping 先落在複本上，後面那一組的 condition 才看得到前一組的結果。
		_apply_bookkeeping(shadow, bookkeeping)

		var pf := EffectApply.preflight([effect], shadow)
		if not bool(pf.get("ok", false)):
			shadow.free()
			return _default_plan_reject(str(pf.get("reason_text", "")))
		var pf_shadow: Node = pf.get("shadow")
		var raised_ending: bool = not (pf.get("ending_request", {}) as Dictionary).is_empty()
		if pf_shadow != null:
			pf_shadow.free()
		if raised_ending:
			shadow.free()
			return _default_plan_reject("逾期預設不得啟動結局")

		var plan: Dictionary = pf.get("plan", {}) as Dictionary
		EffectApply.commit(plan, shadow)
		steps.append({ "bookkeeping": bookkeeping, "plan": plan })
		lines.append_array(pf.get("lines", PackedStringArray()))

	# 通用後置條件：只要這批預設裡有人要寫慶典代付者，離開本時段前它就必須非空且是正式候選。
	# 這條保證 D31／D39／ending 之後可以安全地只讀凍結值，不必在 resolver 補算。
	# **目前沒有任何合法資料能讓它為真**——EffectApply._resolve_festival_proxy() 已經
	# 先擋掉非候選與已凍結兩種情形。留著是為了擋 EffectApply 那一層的回歸（例如哪天它
	# 開始回傳空字串），因此本分支沒有對應的測試案例，不宣稱已覆蓋。
	if expects_proxy:
		var frozen := str(shadow.get("selected_festival_proxy_npc"))
		if frozen.is_empty() or not _is_festival_candidate(frozen):
			shadow.free()
			return _default_plan_reject("逾期預設未能凍結合法的慶典代付者")

	shadow.free()
	return { "ok": true, "reason_code": "", "reason_text": "", "lines": lines, "plan": { "steps": steps } }


func _default_plan_reject(text: String) -> Dictionary:
	return {
		"ok": false, "reason_code": "unresolved_choice_conflict", "reason_text": text,
		"lines": PackedStringArray(), "plan": {},
	}


## 掃當下 day／phase 仍未結算、且組內有唯一 default 槽的 choice group。
## 同組恰一筆 default 與父 beat `fixed:true` 由 lint 18 保證，這裡不重複驗資料。
func _pending_default_groups() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if Data == null or Data.loader == null:
		return out
	for b in Data.loader.beats_at(day, phase):
		if not bool(b.get("fixed", false)):
			continue
		if not ConditionEval.eval(b.get("condition"), self) or not ConditionEval.eval(b.get("requires"), self):
			continue
		var beat_id := str(b.get("id", ""))
		for slot: Dictionary in b.get("slots", []) as Array:
			if slot.get("default_if_unresolved", false) != true:
				continue
			var group_id := str(slot.get("choice_group", ""))
			if group_id.is_empty():
				continue
			if choices.has(beat_id + "::" + group_id):
				continue
			out.append({
				"beat_id": beat_id,
				"group_id": group_id,
				"slot_id": str(slot.get("id", "")),
				"slot": slot,
			})
	return out


## 逾期預設 plan 的唯一落地點；`target` 可以是真狀態，也可以是結局快照用的複本。
func _commit_choice_default_plan(plan: Dictionary, target: Node) -> void:
	for step: Variant in plan.get("steps", []) as Array:
		var step_dict := step as Dictionary
		_apply_bookkeeping(target, step_dict.get("bookkeeping", {}) as Dictionary)
		EffectApply.commit(step_dict.get("plan", {}) as Dictionary, target)


## 當下 day／phase 的通用離場門檻（SCHEMA `phase_exit`）。
## 只讀資料欄位，不看 beat id 或槽 id 字面值。
func _phase_exit_gate() -> Dictionary:
	var out := {
		"has_gate": false, "satisfied": true, "beat_id": "", "location": "",
		"ending": "", "source": "", "required_slots": [] as Array[String],
		"required_choice_groups": [] as Array[String],
	}
	if Data == null or Data.loader == null:
		return out

	for b in Data.loader.beats_at(day, phase):
		if not bool(b.get("fixed", false)):
			continue
		var pe_raw: Variant = b.get("phase_exit")
		if not pe_raw is Dictionary:
			continue
		if not ConditionEval.eval(b.get("condition"), self) or not ConditionEval.eval(b.get("requires"), self):
			continue

		var pe := pe_raw as Dictionary
		var beat_id := str(b.get("id", ""))
		var required: Array[String] = []
		var required_groups: Array[String] = []
		var satisfied := true
		for rs: Variant in pe.get("required_slots", []) as Array:
			var slot_id := str(rs)
			required.append(slot_id)
			if not slots_placed.has(beat_id + "::" + slot_id):
				satisfied = false
		# choice group 形態：組內任一槽結算就算完成，因此「有替代選項」的時段
		# 不會因為玩家沒有那張特定的卡而卡死。
		for rg: Variant in pe.get("required_choice_groups", []) as Array:
			var group_id := str(rg)
			required_groups.append(group_id)
			if not choices.has(beat_id + "::" + group_id):
				satisfied = false
		return {
			"has_gate": true,
			"satisfied": satisfied,
			"beat_id": beat_id,
			"location": str(b.get("location", "")),
			"ending": str(pe.get("ending", "")),
			"source": str(pe.get("source", "")),
			"required_slots": required,
			"required_choice_groups": required_groups,
		}
	return out


## UI 專用查詢：當前時段是否有尚未完成的內容門檻（讓畫面不必特判 beat／槽 id）。
func phase_exit_status() -> Dictionary:
	return _phase_exit_gate()


## 效果結算的唯一入口（P5-B 兩階段契約）：
## preflight（複本模擬）→ 驗 action bookkeeping 與結局快照 → commit（effects → bookkeeping → ending）。
## 任一步失敗則完整狀態零變化，並原樣回傳精確的 reason_code。
## 回傳：{ ok, reason_code, reason_text, lines }
func _settle_effects(blocks: Array, bookkeeping: Dictionary = {}, pre_bookkeeping: Dictionary = {}) -> Dictionary:
	if not _has_any_effect(blocks):
		_apply_bookkeeping(self, pre_bookkeeping)
		_apply_bookkeeping(self, bookkeeping)
		return { "ok": true, "reason_code": "", "reason_text": "", "lines": PackedStringArray() }

	# 效果必須看得到這個動作「已經付出的代價」（扣卡、扣格、遭遇轉態），
	# 因此 pre bookkeeping 先落在來源複本上，preflight 再從那份複本出發。
	var source: Node = self
	var pre_shadow: Node = null
	if not pre_bookkeeping.is_empty():
		pre_shadow = clone_for_preflight()
		if pre_shadow == null:
			return _mutation_reject("data_conflict", "preflight 複本建立失敗")
		_apply_bookkeeping(pre_shadow, pre_bookkeeping)
		source = pre_shadow

	var pf := EffectApply.preflight(blocks, source)
	if pre_shadow != null:
		pre_shadow.free()
	if not bool(pf.get("ok", false)):
		return _mutation_reject(str(pf.get("reason_code", "data_conflict")), str(pf.get("reason_text", "")))

	var shadow: Node = pf.get("shadow")
	var ending_snapshot: Dictionary = {}
	# bookkeeping 也要先落在複本上，結局快照才看得到剛完成的這個動作。
	_apply_bookkeeping(shadow, bookkeeping)
	var request: Dictionary = pf.get("ending_request", {}) as Dictionary
	if not request.is_empty():
		var plan := _build_ending_plan(str(request.get("ending_id", "")), str(request.get("source_id", "")), shadow)
		if not bool(plan.get("ok", false)):
			shadow.free()
			return _mutation_reject(str(plan.get("reason_code", "data_conflict")), str(plan.get("reason_text", "")))
		ending_snapshot = plan.get("snapshot", {}) as Dictionary
	shadow.free()

	_apply_bookkeeping(self, pre_bookkeeping)
	var commit_res := EffectApply.commit(pf.get("plan", {}) as Dictionary, self)
	_apply_bookkeeping(self, bookkeeping)
	if not ending_snapshot.is_empty():
		_commit_ending_plan(ending_snapshot)

	return {
		"ok": true,
		"reason_code": "",
		"reason_text": "",
		"lines": commit_res.get("lines", PackedStringArray()),
	}


func _has_any_effect(blocks: Array) -> bool:
	for block: Variant in blocks:
		if block is Dictionary and not (block as Dictionary).is_empty():
			return true
	return false


## action bookkeeping：槽／選擇／beat 進場紀錄、行動格與投入。複本與真狀態走同一份。
func _apply_bookkeeping(target: Node, bk: Dictionary) -> void:
	if target == null or bk.is_empty():
		return

	var beat_entered := str(bk.get("beat_entered", ""))
	if not beat_entered.is_empty():
		(target.get("beats_entered") as Dictionary)[beat_entered] = true

	var choice_key := str(bk.get("choice_key", ""))
	if not choice_key.is_empty():
		(target.get("choices") as Dictionary)[choice_key] = str(bk.get("choice_slot_id", ""))

	var slot_key := str(bk.get("slot_key", ""))
	if not slot_key.is_empty():
		(target.get("slots_placed") as Dictionary)[slot_key] = true

	var delegate_person := str(bk.get("delegate_person", ""))
	if not delegate_person.is_empty():
		(target.get("delegates_used_today") as Dictionary)[delegate_person] = true

	var report: Variant = bk.get("pending_report")
	if report is Dictionary:
		(target.get("pending_delegation_reports") as Array).append((report as Dictionary).duplicate())

	var removed_report: Variant = bk.get("report_removed")
	if removed_report is Dictionary:
		var pend: Array = target.get("pending_delegation_reports") as Array
		for i in range(pend.size()):
			if (pend[i] as Dictionary) == (removed_report as Dictionary):
				pend.remove_at(i)
				break

	if bool(bk.get("consume_action", false)):
		target.call("consume_action")
		var npc_id := str(bk.get("attention_npc", ""))
		if not npc_id.is_empty():
			var counts: Dictionary = target.get("npc_action_counts") as Dictionary
			counts[npc_id] = int(counts.get(npc_id, 0)) + 1

	# ── 縱慾與遭遇的代價：與效果同屬一個動作，因此也走這條共用路徑 ──────────
	var action_cost := int(bk.get("action_cost", 0))
	if action_cost > 0:
		target.call("consume_action", action_cost)

	for card_inst: Variant in bk.get("lose_cards", []) as Array:
		target.call("lose_card", str(card_inst))

	var indulgence_delta := int(bk.get("indulgence_delta", 0))
	if indulgence_delta != 0:
		target.set("indulgence_count", int(target.get("indulgence_count")) + indulgence_delta)

	var forced_pop := str(bk.get("forced_pop", ""))
	if not forced_pop.is_empty():
		var pending: Array = target.get("forced_pending") as Array
		var pos := pending.find(forced_pop)
		if pos >= 0:
			pending.remove_at(pos)

	# 遭遇轉態一律以「這個動作結束後的完整狀態」落地；空字典＝遭遇結束。
	var enc_set: Variant = bk.get("encounter_set")
	if enc_set is Dictionary:
		var enc_target: Dictionary = target.get("active_encounter") as Dictionary
		enc_target.clear()
		var enc_src := enc_set as Dictionary
		for key: Variant in enc_src.keys():
			enc_target[key] = enc_src[key]


## 晚間演出規則層唯一入口（UI、走查腳本、測試共用，規格書第十一節、K-26）。
## 依序：
## 1. 依陣列順序結算當日 evening fixed beat 之 play_beat()
## 2. 掃描當日成立之殘響（echo.day == day）並收集文字
## 回傳全部要播放的文字行（PackedStringArray）。
func play_evening() -> PackedStringArray:
	var lines := PackedStringArray()
	if flow_mode != FLOW_RUN:
		return lines
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
	if flow_mode != FLOW_RUN:
		return lines
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
							# 首次收費若觸發發瘋 BE，本輪已進 ending mode；
							# 不可再 play_beat 本 beat，否則把文字/beats_entered 寫進已結束的輪。
							if flow_mode != FLOW_RUN or phase != "night":
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
			# 資料已由 advance_phase() 第 ⑥ 步預檢過，這裡再失敗就是規則層的 bug，不吞掉。
			var start_res := start_encounter(bid)
			if not bool(start_res.get("ok", false)):
				push_error("_check_fixed_encounter_for_current_phase: 自動建立遭遇失敗 '%s'（%s）"
					% [bid, str(start_res.get("reason_code", ""))])
			break


## 直接睡＝解析旅館（sanquan）的夜間內容（規格書第九節、P3-C）。
## 面板與睡覺共用 resolved_night_content("sanquan")；睡覺跳過 requires 不成立的內容。
func sleep_night() -> PackedStringArray:
	var lines := PackedStringArray()
	if flow_mode != FLOW_RUN:
		return lines
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
	var mode_gate := _reject_unless_run()
	if not mode_gate.is_empty():
		return mode_gate

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
	if flow_mode != FLOW_RUN:
		return { "ok": false, "reason_code": "not_run", "reason_text": _REASON_TEXT_NOT_RUN, "knowledge_id": "" }

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

	# 跨輪魔法物品：取得當下就寫進 meta set，不等結局結算（開發設計方針 P5-D）。
	if card.get("loop_persistent", false) == true:
		loop_persistent_item_ids[id] = true

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
	if madness_count < cap:
		return

	# preflight 複本只記錄請求；真正的啟動由呼叫端在 commit 後統一 dispatch（P5-B）。
	if simulation_mode:
		if pending_ending_request.is_empty():
			pending_ending_request = { "ending_id": "ending_madness_be", "source_id": "madness_cap" }
		return
	start_ending("ending_madness_be", "madness_cap")


func _check_hand_overflow(card_id: String) -> void:
	var max_hand: int = int(Data.tuning("hand_size"))
	if hand.size() > max_hand:
		push_warning("gain_card: hand is full (%d/%d), card '%s' gained anyway" % [hand.size(), max_hand, card_id])


## 丟棄卡片（作用於 hand 與 knowledge；丟主角卡 = push_error）。
## `permanent` 只對 `loop_persistent:true` 卡有意義：省略／false 只移出本輪手牌，
## true 才同步從 meta persistent set 移除，之後不再跨輪恢復。
func lose_card(id: String, permanent: bool = false) -> void:
	var base_id := _card_base_id(id)
	var card: Dictionary = Data.loader.cards.get(base_id, {})
	if card.get("type", "") == "protagonist":
		push_error("lose_card: cannot lose protagonist card (data bug)")
		return

	# 一般 lose 只令這一輪消失，下一輪照樣恢復；只有明示 permanent 才真的斷掉跨輪繼承。
	# 這一步不看卡還在不在手上——「本輪先普通失去、之後才永久失去」也必須真的斷掉。
	var breaks_persistence: bool = permanent and card.get("loop_persistent", false) == true
	if breaks_persistence:
		loop_persistent_item_ids.erase(base_id)

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

	# 永久失去跨輪物品是冪等的：這一輪早就普通失去過、或同一張再永久失去一次，
	# 手上找不到都是合法終點，不是資料錯誤。
	if breaks_persistence:
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

	if flow_mode != FLOW_RUN:
		return PackedStringArray()

	var is_first := not beats_entered.has(beat_id)

	var lines := PackedStringArray()

	# beat 主文（每次呈現都顯示）
	var text: Variant = beat.get("text")
	if text is String and not (text as String).is_empty():
		lines.append(text as String)

	# on_enter 效果（只在第一次結算）與 beats_entered 一起原子落地
	var blocks: Array = [beat.get("on_enter")] if is_first else []
	var settle := _settle_effects(blocks, { "beat_entered": beat_id })
	if not bool(settle.get("ok", false)):
		push_error("play_beat: on_enter 結算失敗 '%s' → %s" % [beat_id, str(settle.get("reason_code", ""))])
		return lines
	lines.append_array(settle.get("lines", PackedStringArray()))

	var loc_id := str(beat.get("location", ""))
	if not loc_id.is_empty():
		mark_day_location_visited(loc_id)

	return lines


## 記錄白天地點已到訪（meta 層，不隨輪重置）。只記錄 layer 為 "day" 的白天地點。
func mark_day_location_visited(location_id: String) -> void:
	if location_id.is_empty():
		return
	if Data != null and Data.loader != null:
		var loc: Dictionary = Data.loader.locations.get(location_id, {}) as Dictionary
		if str(loc.get("layer", "")) == "day":
			day_locations_visited[location_id] = true
	else:
		day_locations_visited[location_id] = true


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


## 當前時段是否仍有尚未進入過的 OPEN beat（UI 專用查詢，決定推進按鈕文案）。
func has_unseen_content() -> bool:
	var locations := PanelBuilder.available_locations(self, Data)
	for location_id: String in locations:
		var view := build_panel(location_id)
		for beat_view: Dictionary in view.get("beats", []) as Array:
			if int(beat_view.get("tri", -1)) != PanelBuilder.TriState.OPEN:
				continue
			var beat_id := str((beat_view["beat"] as Dictionary).get("id", ""))
			if beat_id.is_empty():
				continue
			if not (beats_entered is Dictionary and beats_entered.has(beat_id)):
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
	var mode_gate := _reject_unless_run()
	if not mode_gate.is_empty():
		return mode_gate

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

	# 效果結算（原子操作：preflight 全過才 commit）
	var bookkeeping := {
		"choice_key": choice_key,
		"choice_slot_id": slot_id,
		"slot_key": beat_id + "::" + slot_id,
	}

	# choice_requires_card 的親自處理槽提交 protagonist 就消耗該行動時段（SCHEMA choice_group）。
	# 一般 choice_group（無此旗標）維持不吃行動格。
	if bool(slot.get("choice_requires_card", false)) and not card_id.is_empty():
		var cr_base := _card_base_id(card_id)
		var cr_card: Dictionary = Data.loader.cards.get(cr_base, {})
		if str(cr_card.get("type", "")) == "protagonist" and ACTION_PHASES.has(phase):
			bookkeeping["consume_action"] = true
			var cr_attn: Variant = slot.get("attention_npc")
			if cr_attn != null:
				bookkeeping["attention_npc"] = str(cr_attn)

	return _settle_effects([slot.get("on_place", {})], bookkeeping)


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
	var mode_gate := _reject_unless_run()
	if not mode_gate.is_empty():
		return mode_gate

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

	# 4~7 是同一個玩家動作：行動格、卡片、次數與效果一起 preflight，
	# 任何一步失敗都不得留下扣卡或扣格的殘骸。
	var cards_to_lose: Array[String] = [card_inst_id]
	if is_soak:
		var cards_cleared := int(Data.tuning("indulgence.soak_cards_cleared", 1))
		if cards_cleared > 1:
			for c in hand:
				if _card_base_id(c) == "madness" and c != card_inst_id:
					cards_to_lose.append(c)
					if cards_to_lose.size() == cards_cleared:
						break

	var pre_bk := {
		"action_cost": soak_cost if is_soak else 1,
		"lose_cards": cards_to_lose,
		"indulgence_delta": 1,
	}

	# 出口槽不記入 slots_placed，理由見函式開頭註解（K-54）。
	return _settle_indulgence_effects(slot, pre_bk)


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

	# 隊首出列、行動格、發狂卡與效果同屬一個動作：結算失敗則債留在 forced_pending，
	# 行動格與手牌都不動（帳不豁免，也不會被扣兩次）。
	var card_inst_id := str(forced_pending[0])
	var pre_bk := {
		"forced_pop": card_inst_id,
		"action_cost": 1,
		"lose_cards": [card_inst_id] as Array[String],
		"indulgence_delta": 1,
	}

	var settle := _settle_indulgence_effects(slot, pre_bk)
	if not bool(settle.get("ok", false)):
		push_error("_settle_forced_indulgence: 效果結算失敗 → %s" % str(settle.get("reason_code", "")))
		return PackedStringArray()

	return settle.get("lines", PackedStringArray())


## 縱慾效果的共用結算：基底 on_place 與當次強度級追加塊合併成同一個動作。
func _settle_indulgence_effects(slot: Dictionary, pre_bookkeeping: Dictionary) -> Dictionary:
	var blocks: Array = [slot.get("on_place", {})]
	var by_level: Variant = slot.get("on_place_by_level")
	if by_level is Dictionary:
		# 強度級看的是「含這一次」的縱慾次數，因此用尚未落地的 delta 先加上去。
		var effective_count := indulgence_count + int(pre_bookkeeping.get("indulgence_delta", 0))
		var lvl := Indulgence.level_for(effective_count, Data.loader.tuning)
		var lvl_effect: Variant = (by_level as Dictionary).get(lvl)
		if lvl_effect is Dictionary:
			blocks.append(lvl_effect)
	return _settle_effects(blocks, {}, pre_bookkeeping)


## 隔日上午委託回報結算（規格書 P4-B、開發設計方針 P4-B）。
## 由 advance_phase 於換日進入 morning 時呼叫（在強制縱慾之後、清空 delegates_used_today 之前）：
## 依 pending_delegation_reports 順序套用 report 效果，並收集文字行。
## 接點失效時視為資料衝突保留於 pending 並 push_error（不靜默丟棄）。
func _settle_pending_delegation_reports() -> void:
	if pending_delegation_reports.is_empty():
		return

	var current_day := day
	var due_reports: Array[Dictionary] = []

	for r: Dictionary in pending_delegation_reports:
		if int(r.get("due_day", 0)) > current_day:
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
		else:
			due_reports.append(r)

	# pending 不在這裡整份覆寫：每一筆回報的「出列」與它自己的效果同屬一個動作，
	# 由 pre bookkeeping 一起落地。未到期、資料壞掉與結算失敗的三種都原樣留在原位。

	var rep_lines: PackedStringArray = []
	for r: Dictionary in due_reports:
		var b_id := str(r.get("beat_id", ""))
		var s_id := str(r.get("slot_id", ""))
		var beat_dict: Dictionary = Data.loader.beats_by_id[b_id]
		var slot_dict: Dictionary = _find_slot(beat_dict, s_id)
		var del_dict: Dictionary = slot_dict["delegation"] as Dictionary
		var rep_dict: Dictionary = del_dict["report"] as Dictionary

		var gen_before := run_generation
		var settle := _settle_effects([rep_dict], {}, { "report_removed": r })
		if not bool(settle.get("ok", false)):
			push_error("_settle_pending_delegation_reports: 回報效果結算失敗 → %s" % str(settle.get("reason_code", "")))
			return

		# K-65 防呆：若回報效果觸發 BE / 結局，立即中斷結算、不寫入文字
		if run_generation != gen_before or day != current_day or flow_mode != FLOW_RUN:
			return

		rep_lines.append_array(settle.get("lines", PackedStringArray()))

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
	var mode_gate := _reject_unless_run()
	if not mode_gate.is_empty():
		return mode_gate

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

	# ── 成功（原子操作：preflight 全過才 commit）──
	var bookkeeping := {
		"slot_key": slot_key,
		"delegate_person": base_id,
	}
	if not choice_group.is_empty():
		bookkeeping["choice_key"] = beat_id + "::" + choice_group
		bookkeeping["choice_slot_id"] = slot_id
	if timing == "next_morning":
		bookkeeping["pending_report"] = {
			"due_day": day + 1,
			"beat_id": beat_id,
			"slot_id": slot_id,
			"person_id": base_id,
		}

	return _settle_effects([slot.get("on_place", {})], bookkeeping)


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
	var mode_gate := _reject_unless_run()
	if not mode_gate.is_empty():
		return mode_gate

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
	var card_type := str(card.get("type", ""))
	var is_protagonist := card_type == "protagonist"
	var in_action_phase := ACTION_PHASES.has(phase)

	# 全過 → 效果結算（原子操作：preflight 全過才 commit）。
	var bookkeeping := { "slot_key": beat_id + "::" + slot_id }
	if is_protagonist and in_action_phase:
		bookkeeping["consume_action"] = true
		var attn: Variant = slot.get("attention_npc")
		if attn != null:
			bookkeeping["attention_npc"] = str(attn)

	return _settle_effects([slot.get("on_place", {})], bookkeeping)


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
	var mode_gate := _reject_unless_run()
	if not mode_gate.is_empty():
		return mode_gate

	# 1. active
	if not active_encounter.is_empty():
		return { "ok": false, "reason_code": "encounter_active", "reason_text": "已有進行中的遭遇" }

	# 2. unknown beat
	if Data == null or Data.loader == null or not Data.loader.beats_by_id.has(beat_id):
		return { "ok": false, "reason_code": "unknown_beat", "reason_text": "未知的遭遇事件" }

	var beat: Dictionary = Data.loader.beats_by_id.get(beat_id, {}) as Dictionary
	if not beat.has("encounter"):
		return { "ok": false, "reason_code": "unknown_beat", "reason_text": "未知的遭遇事件" }

	# 3. data conflict（與換時段前的預檢共用同一份檢查）
	var enc_error := _encounter_data_error(beat)
	if not enc_error.is_empty():
		return { "ok": false, "reason_code": "data_conflict", "reason_text": enc_error }

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
## 成功進入第一回合；若超載則確認開場後立即走 failure 出口；非超載時第一回合加一次 cost；可用格歸零或無合法解直接 failure。
## 成功回傳另含 entered_round：超載立即 failure 為 false；實際進入第一 round（即使隨後 failure）為 true。
## 回傳：{ "ok": bool, "reason_code": String, "reason_text": String, "lines": PackedStringArray, "entered_round"?: bool }
func acknowledge_encounter_intro() -> Dictionary:
	var mode_gate := _reject_unless_run()
	if not mode_gate.is_empty():
		return mode_gate

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

	# 進場與「開場就結束」的失敗出口屬同一個動作：先在複本推演，再一次落地。
	var sh: Node = clone_for_preflight()
	if sh == null:
		return { "ok": false, "reason_code": "data_conflict", "reason_text": "preflight 複本建立失敗", "lines": PackedStringArray() }
	var sh_enc: Dictionary = sh.get("active_encounter") as Dictionary
	var entered_round := true
	var outcome := ""

	if is_overloaded():
		# 超載時確認開場後立即結算 failure 出口（不進入第一回合、不增加佔格）
		entered_round = false
		outcome = "failure"
	else:
		var cost := int(enc.get("per_round_slot_cost", 1))
		sh_enc["stage"] = "round"
		sh_enc["round_id"] = first_round_id
		sh_enc["blocked_slots"] = int(sh_enc.get("blocked_slots", 0)) + cost
		var visited: Array = sh_enc.get("visited_round_ids", []) as Array
		if not visited.has(first_round_id):
			visited.append(first_round_id)

		# 佔格達/超出手牌上限，或第一回合就沒有合法動作，都直接走 failure 出口
		if bool(sh.call("_check_encounter_capacity_failure")):
			outcome = "failure"
		elif not Encounter.has_legal_moves(enc, first_round, sh_enc, sh, Data.loader):
			outcome = "failure"

	var plan := _encounter_plan(enc, [], [] as Array[String], sh_enc.duplicate(true), outcome)
	sh.free()
	var res := _commit_encounter_action(plan)
	res["entered_round"] = entered_round if bool(res.get("ok", false)) else false
	return res


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
	var mode_gate := _reject_unless_run()
	if not mode_gate.is_empty():
		return mode_gate

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

	# 通過所有檢查 → 先在複本上把整回合推演到出口，回應與出口效果合併成同一個動作。
	var plan := _plan_encounter_response(card_id, base_id, enc, round_data, is_discardable)
	if plan.has("ok") and not bool(plan.get("ok", false)):
		return plan
	return _commit_encounter_action(plan)


## 在複本上推演一次回應：扣卡、佔格、換回合、容量與死局判定全部先在複本跑完，
## 回傳單一 action plan。真狀態在這裡完全不動。
## 回傳：{ blocks, pre, advance_after } 或失敗 { ok: false, reason_code: "data_conflict", ... }
func _plan_encounter_response(card_id: String, base_id: String, enc: Dictionary, round_data: Dictionary, is_discardable: bool) -> Dictionary:
	var sh: Node = clone_for_preflight()
	if sh == null:
		return { "ok": false, "reason_code": "data_conflict", "reason_text": "preflight 複本建立失敗", "lines": PackedStringArray() }
	var sh_enc: Dictionary = sh.get("active_encounter") as Dictionary
	var lose_cards: Array[String] = []
	var blocks: Array = []

	(sh_enc["attempted_card_ids"] as Array).append(base_id)
	var cost := int(enc.get("per_round_slot_cost", 1))
	var matching_resp := Encounter.find_matching_response(round_data, card_id, base_id)
	var hit := not matching_resp.is_empty()
	var branch: Dictionary = matching_resp if hit else (round_data.get("fallback", {}) as Dictionary)

	if hit:
		if bool(matching_resp.get("consume_card", false)) and is_discardable:
			lose_cards.append(card_id)
		# 正解釋放本回合佔格
		sh_enc["blocked_slots"] = max(0, int(sh_enc.get("blocked_slots", 0)) - cost)
	elif is_discardable:
		# 錯答保留佔格（不釋放）
		lose_cards.append(card_id)

	for c: String in lose_cards:
		sh.call("lose_card", c)

	if branch.has("on_resolve"):
		blocks.append(branch["on_resolve"])
		# 容量與死局判定看的是 on_resolve 之後的手牌，因此複本上要先把它套下去。
		# 複本是 simulation_mode，撞 cap 只會被記錄，不會在這裡啟動結局。
		var pf_sh := EffectApply.preflight([branch["on_resolve"]], sh)
		var pf_shadow: Node = pf_sh.get("shadow")
		if pf_shadow != null:
			pf_shadow.free()
		if bool(pf_sh.get("ok", false)):
			EffectApply.commit(pf_sh.get("plan", {}) as Dictionary, sh)

	var outcome := ""
	var next_round_val: Variant = branch.get("next_round")
	if next_round_val == null or str(next_round_val).is_empty():
		outcome = "victory" if hit else "failure"
	else:
		var next_rid := str(next_round_val)
		var visited: Array = sh_enc.get("visited_round_ids", []) as Array
		if visited.has(next_rid):
			push_error("Encounter: cycle detected on round '%s'" % next_rid)
			outcome = "failure"
		else:
			visited.append(next_rid)
			sh_enc["round_id"] = next_rid
			sh_enc["blocked_slots"] = int(sh_enc.get("blocked_slots", 0)) + cost
			if bool(sh.call("_check_encounter_capacity_failure")):
				outcome = "failure"
			elif not Encounter.has_legal_moves(enc, Encounter.get_round(enc, next_rid), sh_enc, sh, Data.loader):
				outcome = "failure"

	var plan := _encounter_plan(enc, blocks, lose_cards, sh_enc.duplicate(true), outcome)
	sh.free()
	return plan


## 遭遇 action plan 的共用組裝：有出口就把出口效果併進同一批 blocks 並清掉遭遇。
func _encounter_plan(enc: Dictionary, blocks: Array, lose_cards: Array[String], final_enc: Dictionary, outcome: String) -> Dictionary:
	var pre: Dictionary = { "lose_cards": lose_cards, "encounter_set": final_enc }
	var advance_after := false
	if not outcome.is_empty():
		var exit_key := "on_%s" % outcome
		var exit_effect: Dictionary = enc.get(exit_key, {}) as Dictionary
		if not exit_effect.is_empty():
			blocks.append(exit_effect)
		pre["encounter_set"] = {}
		advance_after = str(enc.get("after_finish", "stay")) == "advance_phase"
	return { "blocks": blocks, "pre": pre, "advance_after": advance_after }


## 遭遇 action plan 的唯一落地點。`after_finish` 的推進本身可能失敗，
## 因此固定留在原子區塊外，不混進 commit。
func _commit_encounter_action(plan: Dictionary) -> Dictionary:
	var gen_before := run_generation
	var settle := _settle_effects(plan.get("blocks", []) as Array, {}, plan.get("pre", {}) as Dictionary)
	if not bool(settle.get("ok", false)):
		return settle

	var lines: PackedStringArray = settle.get("lines", PackedStringArray())
	if bool(plan.get("advance_after", false)) and run_generation == gen_before and flow_mode == FLOW_RUN:
		var adv_res := advance_phase()
		lines.append_array(adv_res.get("lines", PackedStringArray()))
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
	var mode_gate := _reject_unless_run()
	if not mode_gate.is_empty():
		return mode_gate

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

	# 丟棄與「丟完沒棋可走」的失敗出口屬同一個動作：先在複本判定，再一次落地。
	var sh: Node = clone_for_preflight()
	if sh == null:
		return { "ok": false, "reason_code": "data_conflict", "reason_text": "preflight 複本建立失敗", "lines": PackedStringArray() }
	sh.call("lose_card", card_id)
	var round_id := str(active_encounter.get("round_id", ""))
	var round_data := Encounter.get_round(enc, round_id)
	var sh_enc: Dictionary = sh.get("active_encounter") as Dictionary
	var out_of_moves := not Encounter.has_legal_moves(enc, round_data, sh_enc, sh, Data.loader)
	var plan := _encounter_plan(enc, [], [card_id] as Array[String], sh_enc.duplicate(true), "failure" if out_of_moves else "")
	sh.free()
	return _commit_encounter_action(plan)


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
	var mode_gate := _reject_unless_run()
	if not mode_gate.is_empty():
		return mode_gate

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

	# 支付代價與逃離出口效果屬同一個動作：任一步失敗都不得只扣卡不逃離。
	var paid: Array[String] = []
	for cid in card_ids:
		paid.append(cid)
	var plan := _encounter_plan(enc, [], paid, {}, "escape")
	return _commit_encounter_action(plan)


## 檢查可用格數是否歸零或小於 0（容量超載失敗，K-135/K-136）。
## 當 blocked_slots == 0 時（如 D45），僅在手牌超載（> hand_size）時判定容量失敗。
func _check_encounter_capacity_failure() -> bool:
	var hand_size := int(Data.tuning("hand_size", 14)) if Data != null else 14
	var blocked := int(active_encounter.get("blocked_slots", 0))
	if blocked <= 0:
		return is_overloaded()
	return (hand_size - hand.size() - blocked) <= 0


# ── 序列化 ──────────────────────────────────────────────────────────────────

func serialize() -> Dictionary:
	var reports_copy: Array[Dictionary] = []
	for r: Dictionary in pending_delegation_reports:
		reports_copy.append(r.duplicate())

	var history_copy: Array[Dictionary] = []
	for record: Dictionary in ending_history:
		history_copy.append(record.duplicate(true))

	return {
		"flow": {
			"mode": flow_mode,
			"active_ending": null if active_ending.is_empty() else active_ending.duplicate(true),
		},
		"run": {
			"day": day,
			"phase": phase,
			"opening_choice_id": null if opening_choice_id.is_empty() else opening_choice_id,
			"knowledge_at_start": knowledge_at_start.duplicate(),
			"selected_festival_proxy_npc": null if selected_festival_proxy_npc.is_empty() else selected_festival_proxy_npc,
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
			"day_locations_visited": day_locations_visited.duplicate(),
			"delegation_tutorial_seen": delegation_tutorial_seen,
			"run_number": run_number,
			"ending_history": history_copy,
			"loop_persistent_item_ids": loop_persistent_item_ids.duplicate(),
		}
	}


## 載入存檔（P5-B 起回傳結果而非 void）。
## 先原子驗完 flow 形狀（型別、nullable 規則、page ref 可解析、page index 範圍、
## mode 與 active_ending 一致性），壞形狀精確回 `invalid_save_shape` 且現有狀態零變化。
## 沒有 `flow` 的 P1～P4 舊 checkpoint 一律遷移為 run＋active null，並以載入當下的 meta
## knowledge 複製成 `knowledge_at_start`，避免把舊知識誤算成本輪新增。
## 回傳：{ ok, reason_code }
func deserialize(d: Dictionary) -> Dictionary:
	var flow_parsed := _parse_flow_block(d)
	if not bool(flow_parsed.get("ok", false)):
		return { "ok": false, "reason_code": "invalid_save_shape" }

	var persistent_parsed := _parse_persistent_items(d)
	if not bool(persistent_parsed.get("ok", false)):
		return { "ok": false, "reason_code": "invalid_save_shape" }

	var history_parsed := _parse_history_records(d)
	if not bool(history_parsed.get("ok", false)):
		return { "ok": false, "reason_code": "invalid_save_shape" }

	var visited_parsed := _parse_day_locations_visited(d)
	if not bool(visited_parsed.get("ok", false)):
		return { "ok": false, "reason_code": "invalid_save_shape" }

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
	switch_progress.clear()
	var sp: Dictionary = run.get("switch_progress", {})
	for k in sp.keys():
		switch_progress[str(k)] = int(sp[k])
	relations.clear()
	var rel: Dictionary = run.get("relations", {})
	for k in rel.keys():
		relations[str(k)] = int(rel[k])
	npc_action_counts.clear()
	var nac: Dictionary = run.get("npc_action_counts", {})
	for k in nac.keys():
		npc_action_counts[str(k)] = int(nac[k])
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
	day_locations_visited = visited_parsed.get("visited", {}).duplicate()
	delegation_tutorial_seen = bool(meta.get("delegation_tutorial_seen", false))

	# ── P5 欄位（缺欄的舊 checkpoint 以規格初值補齊，這條相容路徑在 P5-D 後仍保留）──
	run_number = int(meta.get("run_number", 1))
	ending_history.clear()
	for record: Dictionary in history_parsed.get("records", []) as Array[Dictionary]:
		ending_history.append(record)
	loop_persistent_item_ids = persistent_parsed.get("ids", {}) as Dictionary

	var opening_raw: Variant = run.get("opening_choice_id")
	opening_choice_id = "" if opening_raw == null else str(opening_raw)
	var proxy_raw: Variant = run.get("selected_festival_proxy_npc")
	selected_festival_proxy_npc = "" if proxy_raw == null else str(proxy_raw)

	var start_raw: Variant = run.get("knowledge_at_start")
	knowledge_at_start.clear()
	if start_raw is Dictionary:
		for card_id: Variant in (start_raw as Dictionary).keys():
			knowledge_at_start[str(card_id)] = true
	else:
		# 舊 checkpoint 沒有這欄：以載入當下的 knowledge 當開輪基準。
		knowledge_at_start = knowledge.duplicate()

	flow_mode = str(flow_parsed.get("mode", FLOW_RUN))
	active_ending = flow_parsed.get("active_ending", {}) as Dictionary

	return { "ok": true, "reason_code": "" }


## meta day locations visited set 的原子驗證。引用不存在的地點、非白天地點或值非 true，
## 一律視為資料錯誤。回傳 { ok, visited }。
func _parse_day_locations_visited(d: Dictionary) -> Dictionary:
	var meta_raw: Variant = d.get("meta", {})
	if not meta_raw is Dictionary:
		return { "ok": true, "visited": {} }
	if not (meta_raw as Dictionary).has("day_locations_visited"):
		return { "ok": true, "visited": {} }
	var raw: Variant = (meta_raw as Dictionary).get("day_locations_visited", {})
	if not raw is Dictionary:
		return { "ok": false, "visited": {} }
	var visited: Dictionary = {}
	for loc_id: Variant in (raw as Dictionary).keys():
		var lid := str(loc_id)
		var flag: Variant = (raw as Dictionary)[loc_id]
		if typeof(flag) != TYPE_BOOL or not bool(flag):
			return { "ok": false, "visited": {} }
		if Data == null or Data.loader == null:
			return { "ok": false, "visited": {} }
		var loc: Dictionary = Data.loader.locations.get(lid, {}) as Dictionary
		if loc.is_empty() or str(loc.get("layer", "")) != "day":
			return { "ok": false, "visited": {} }
		visited[lid] = true
	return { "ok": true, "visited": visited }



## meta persistent set 的原子驗證。引用不存在或非 `loop_persistent:true` 的卡，
## 在 P6 存檔遷移機制上線前一律視為資料錯誤，不靜默修復。回傳 { ok, ids }。
func _parse_persistent_items(d: Dictionary) -> Dictionary:
	var meta_raw: Variant = d.get("meta", {})
	if not meta_raw is Dictionary:
		return { "ok": true, "ids": {} }
	var raw: Variant = (meta_raw as Dictionary).get("loop_persistent_item_ids", {})
	if not raw is Dictionary:
		return { "ok": false, "ids": {} }
	var ids: Dictionary = {}
	for card_id: Variant in (raw as Dictionary).keys():
		var cid := str(card_id)
		# 這是一個 set：值只能是 true。收 false 再靜默正規化成 true 等於偷偷改存檔語意。
		var flag: Variant = (raw as Dictionary)[card_id]
		if typeof(flag) != TYPE_BOOL or not bool(flag):
			return { "ok": false, "ids": {} }
		if Data == null or Data.loader == null or not Data.loader.cards.has(cid):
			return { "ok": false, "ids": {} }
		if (Data.loader.cards[cid] as Dictionary).get("loop_persistent", false) != true:
			return { "ok": false, "ids": {} }
		ids[cid] = true
	return { "ok": true, "ids": ids }


## flow 區塊的原子驗證。回傳 { ok, mode, active_ending }。
func _parse_flow_block(d: Dictionary) -> Dictionary:
	if not d.has("flow"):
		# 無 flow 的舊 checkpoint：永遠遷移為 run＋active null。
		return { "ok": true, "mode": FLOW_RUN, "active_ending": {} }

	var flow_raw: Variant = d["flow"]
	if not flow_raw is Dictionary:
		return { "ok": false }
	var flow := flow_raw as Dictionary
	if not flow.has("mode") or not flow.has("active_ending"):
		return { "ok": false }

	var mode_raw: Variant = flow["mode"]
	if typeof(mode_raw) != TYPE_STRING or not FLOW_MODES.has(mode_raw):
		return { "ok": false }
	var mode := str(mode_raw)

	var active_raw: Variant = flow["active_ending"]
	if active_raw == null:
		if mode == FLOW_ENDING:
			return { "ok": false }
		return { "ok": true, "mode": mode, "active_ending": {} }

	if not active_raw is Dictionary or mode != FLOW_ENDING:
		return { "ok": false }

	var snapshot := _parse_ending_snapshot(active_raw as Dictionary)
	if snapshot.is_empty():
		return { "ok": false }
	return { "ok": true, "mode": mode, "active_ending": snapshot }


## 結局「結果欄位」的逐欄驗證，也就是 `HISTORY_RECORD_KEYS` 那十欄。
## active snapshot 與 history record 共用同一份判斷：兩邊記的是同一件事，
## 寫得進去卻讀不回來（或反過來）就是規約分歧。任一不合法回空字典。
## 回傳正規化後的十欄（`ended_day` 轉 int、知識卡陣列轉 `Array[String]`）。
func _parse_ending_result_fields(raw: Dictionary) -> Dictionary:
	if Data == null or Data.loader == null:
		return {}

	var ending_id: Variant = raw["ending_id"]
	if typeof(ending_id) != TYPE_STRING or not Data.loader.endings_by_id.has(ending_id):
		return {}

	var run_no: Variant = _strict_int(raw["run_number"])
	if run_no == null or int(run_no) < 1:
		return {}

	if not _is_null_or_filled_string(raw["opening_choice_id"]):
		return {}
	for variant_key: String in ENDING_VARIANT_KEYS + ["festival_proxy_npc"]:
		if not _is_null_or_filled_string(raw[variant_key]):
			return {}

	# ── ending 專屬矩陣：泛用 nullable 過關不代表這個 ending 收得起這組值 ──────
	var ending_data: Dictionary = Data.loader.endings_by_id[str(ending_id)] as Dictionary
	var is_refuse := str(ending_id) == ENDING_REFUSE_BOARDING

	# 開局選項有值就必須真的存在；不上車另外要求正是資料中指向它的那一個。
	var opening_ref: Variant = raw["opening_choice_id"]
	if opening_ref != null and not Data.loader.opening_choices_by_id.has(str(opening_ref)):
		return {}
	if is_refuse and str(opening_ref) != _opening_choice_for_ending(str(ending_id)):
		return {}

	# variant 欄有值 ⇔ 這個 ending 真的有同名 variant group，且值必須是該 group 宣告的合法 rule id。
	var valid_rules_by_group := _variant_rules_by_group(ending_data)

	for variant_key: String in ENDING_VARIANT_KEYS:
		var gid := variant_key.trim_suffix("_variant")
		var val: Variant = raw[variant_key]
		if valid_rules_by_group.has(gid):
			if typeof(val) != TYPE_STRING or not (valid_rules_by_group[gid] as Dictionary).has(str(val)):
				return {}
		else:
			if val != null:
				return {}

	# 代付者：正常結局必須是已凍結的正式候選；不上車一律 null；BE 有值就得是候選。
	var proxy_raw: Variant = raw["festival_proxy_npc"]
	if is_refuse:
		if proxy_raw != null:
			return {}
	elif str(ending_id) == ENDING_REPLACED:
		if proxy_raw == null or not _is_festival_candidate(str(proxy_raw)):
			return {}
	elif proxy_raw != null and not _is_festival_candidate(str(proxy_raw)):
		return {}

	var ended_day: Variant = raw["ended_day"]
	var ended_phase: Variant = raw["ended_phase"]
	if (ended_day == null) != (ended_phase == null):
		return {}
	# 不上車沒有 run，因此沒有結束日；其餘三個結局一定結束在某個時段。
	if is_refuse != (ended_day == null):
		return {}
	if ended_day != null:
		var day_val: Variant = _strict_int(ended_day)
		if day_val == null or int(day_val) < 1 or int(day_val) > LAST_DAY:
			return {}
		ended_day = int(day_val)
		if typeof(ended_phase) != TYPE_STRING or not PHASES.has(ended_phase):
			return {}

	# 當輪知識：必須真的是知識卡、不重複，且與 `_knowledge_gained_since_start()`
	# 一樣依 `cards.json` 順序排列，快照與 history 才逐字可比。不上車沒有 run，一律空。
	if not raw["knowledge_gained_this_run"] is Array:
		return {}
	var gained: Array[String] = []
	var last_order := -1
	for item: Variant in raw["knowledge_gained_this_run"] as Array:
		if typeof(item) != TYPE_STRING or str(item).is_empty():
			return {}
		var cid := str(item)
		if gained.has(cid):
			return {}
		var order := _card_catalog_order(cid)
		if order < 0 or order <= last_order:
			return {}
		var card_data: Dictionary = Data.loader.cards[cid] as Dictionary
		if not bool(card_data.get("slotless", false)) or str(card_data.get("type", "")) != "knowledge":
			return {}
		last_order = order
		gained.append(cid)
	if is_refuse and not gained.is_empty():
		return {}

	return {
		"run_number": int(run_no),
		"ending_id": str(ending_id),
		"opening_choice_id": opening_ref,
		"ended_day": ended_day,
		"ended_phase": ended_phase,
		"partner_variant": raw["partner_variant"],
		"livelihood_variant": raw["livelihood_variant"],
		"inn_appearance_variant": raw["inn_appearance_variant"],
		"festival_proxy_npc": proxy_raw,
		"knowledge_gained_this_run": gained,
	}


## 某個 ending 的 variant group id → 合法 rule id 集合。
func _variant_rules_by_group(ending_data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for group: Variant in ending_data.get("variant_groups", []) as Array:
		if group is Dictionary:
			var gid := str((group as Dictionary).get("id", ""))
			var rules_dict := {}
			for r: Variant in (group as Dictionary).get("rules", []) as Array:
				if r is Dictionary:
					rules_dict[str((r as Dictionary).get("id", ""))] = true
			out[gid] = rules_dict
	return out


## 卡片在 `cards.json` 中的位置；不存在回 -1。用來驗知識卡陣列的資料順序。
func _card_catalog_order(card_id: String) -> int:
	if Data == null or Data.loader == null:
		return -1
	return (Data.loader.cards.keys() as Array).find(card_id)


## active_ending 快照的逐欄驗證。任何缺欄、多欄、錯型別、空字串代 null、
## 失效 page ref 或越界 index 都回空字典（＝不合法）。
func _parse_ending_snapshot(raw: Dictionary) -> Dictionary:
	if raw.size() != ENDING_SNAPSHOT_KEYS.size():
		return {}
	for key: String in ENDING_SNAPSHOT_KEYS:
		if not raw.has(key):
			return {}

	if Data == null or Data.loader == null:
		return {}

	var result := _parse_ending_result_fields(raw)
	if result.is_empty():
		return {}

	var ending_id: Variant = result["ending_id"]
	var source_id: Variant = raw["source_id"]
	if typeof(source_id) != TYPE_STRING or str(ENDING_SOURCE_PAIRS.get(source_id, "")) != str(ending_id):
		return {}

	var ending_data: Dictionary = Data.loader.endings_by_id[str(ending_id)] as Dictionary
	var ended_day: Variant = result["ended_day"]
	var ended_phase: Variant = result["ended_phase"]
	var gained: Array[String] = result["knowledge_gained_this_run"]

	if not raw["page_refs"] is Array:
		return {}
	var refs: Array[String] = []
	var branch_seen := ""
	for item: Variant in raw["page_refs"] as Array:
		if typeof(item) != TYPE_STRING:
			return {}
		if not bool(EndingResolver.resolve_ref(str(item), Data.loader).get("ok", false)):
			return {}
		# 可解析不等於屬於這一次結局：ref 必須指向本 ending，且全部同一個 branch。
		var parts := str(item).split("/")
		if parts[0] != str(ending_id):
			return {}
		if branch_seen.is_empty():
			branch_seen = parts[1]
		elif parts[1] != branch_seen:
			return {}
		# 驗證 variant_groups 的 page ref rule id 與 snapshot 欄位完全一致
		if parts.size() >= 5 and parts[2] == "variant_groups":
			var group_id := parts[3]
			var rule_id := parts[4]
			var snapshot_val := str(raw.get(group_id + "_variant", ""))
			if snapshot_val != rule_id:
				return {}
		# 驗證 lookup_fragments 的 page ref lookup_value 與 snapshot 欄位及 when_group 完全一致
		if parts.size() >= 5 and parts[2] == "lookup_fragments":
			var lf_id := parts[3]
			var lookup_val := parts[4]
			var found_lf: Dictionary = {}
			for lf_item: Variant in ending_data.get("lookup_fragments", []) as Array:
				if lf_item is Dictionary and str((lf_item as Dictionary).get("id", "")) == lf_id:
					found_lf = lf_item as Dictionary
					break
			if found_lf.is_empty():
				return {}
			var when_group := found_lf.get("when_group", {}) as Dictionary
			var wg_group := str(when_group.get("group", ""))
			var wg_variant := str(when_group.get("variant", ""))
			if not wg_group.is_empty() and str(raw.get(wg_group + "_variant", "")) != wg_variant:
				return {}
			var source_field := str(found_lf.get("source_field", ""))
			if not source_field.is_empty() and str(raw.get(source_field, "")) != lookup_val:
				return {}
		refs.append(str(item))
	if refs.is_empty():
		return {}

	var index_val: Variant = _strict_int(raw["page_index"])
	if index_val == null or int(index_val) < 0 or int(index_val) >= refs.size():
		return {}

	if typeof(raw["page_revealed"]) != TYPE_BOOL or typeof(raw["ready_to_complete"]) != TYPE_BOOL:
		return {}
	# ready 只由「揭露末頁」或「跳到末頁」產生，兩者都同時把頁碼停在末頁並標記已揭露。
	var at_last := int(index_val) == refs.size() - 1
	if bool(raw["ready_to_complete"]) != (at_last and bool(raw["page_revealed"])):
		return {}

	return {
		"ending_id": str(ending_id),
		"source_id": str(source_id),
		"run_number": int(result["run_number"]),
		"opening_choice_id": result["opening_choice_id"],
		"ended_day": ended_day,
		"ended_phase": ended_phase,
		"partner_variant": result["partner_variant"],
		"livelihood_variant": result["livelihood_variant"],
		"inn_appearance_variant": result["inn_appearance_variant"],
		"festival_proxy_npc": result["festival_proxy_npc"],
		"knowledge_gained_this_run": gained,
		"page_refs": refs,
		"page_index": int(index_val),
		"page_revealed": bool(raw["page_revealed"]),
		"ready_to_complete": bool(raw["ready_to_complete"]),
	}


## meta `ending_history` 的原子驗證。每一筆都必須是 append 當下那個封閉形狀：
## 精確十欄、四類 ending 的 nullable 矩陣、opening／variant／proxy 引用合法、
## 當輪知識真的是知識卡且無重複、依資料順序。任一筆不合法就整份拒絕
## （＝ `invalid_save_shape`），不靜默丟棄或修補。回傳 { ok, records }。
func _parse_history_records(d: Dictionary) -> Dictionary:
	var empty: Array[Dictionary] = []
	var meta_raw: Variant = d.get("meta", {})
	if not meta_raw is Dictionary:
		return { "ok": true, "records": empty }
	var raw: Variant = (meta_raw as Dictionary).get("ending_history", [])
	if not raw is Array:
		return { "ok": false, "records": empty }

	var records: Array[Dictionary] = []
	for item: Variant in raw as Array:
		if not item is Dictionary:
			return { "ok": false, "records": empty }
		var entry := item as Dictionary
		if entry.size() != HISTORY_RECORD_KEYS.size():
			return { "ok": false, "records": empty }
		for key: String in HISTORY_RECORD_KEYS:
			if not entry.has(key):
				return { "ok": false, "records": empty }
		var parsed := _parse_ending_result_fields(entry)
		if parsed.is_empty():
			return { "ok": false, "records": empty }
		var record: Dictionary = {}
		for key: String in HISTORY_RECORD_KEYS:
			record[key] = parsed[key]
		records.append(record)
	return { "ok": true, "records": records }


## 資料中宣告 `ending` 指向 `ending_id` 的開局選項 id；找不到回空字串。
func _opening_choice_for_ending(ending_id: String) -> String:
	if Data == null or Data.loader == null:
		return ""
	for choice: Dictionary in Data.loader.opening_choices:
		if str(choice.get("ending", "")) == ending_id:
			return str(choice.get("id", ""))
	return ""


## JSON 往返會把 int 變 float，因此整數欄位接受「值為整數的 float」，其餘一律拒絕。
func _strict_int(v: Variant) -> Variant:
	if typeof(v) == TYPE_INT:
		return int(v)
	if typeof(v) == TYPE_FLOAT:
		var f := float(v)
		if is_nan(f) or is_inf(f) or floor(f) != f:
			return null
		return int(f)
	return null


## nullable 字串欄位：只允許 null 或非空字串；空字串不得代替 null。
func _is_null_or_filled_string(v: Variant) -> bool:
	if v == null:
		return true
	return typeof(v) == TYPE_STRING and not str(v).is_empty()


# ── 內部工具 ─────────────────────────────────────────────────────────────────

func _card_base_id(id: String) -> String:
	return DataFacts.card_base_id(id)

