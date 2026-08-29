extends Control

## 主場景。P1-F：白天/夜間地圖、晚間演出、夜間解析、P5-E 開局與結局 UI、遭遇與委託。

const ConditionEval := preload("res://scripts/core/condition_eval.gd")
const QAValidationClass := preload("res://tests/ui_sim/qa_validation.gd")

const _MSG_DATA_ERROR := "資料載入失敗，詳情見 Output。"
const _MSG_ADVANCE := "推進時段"
const _MSG_ADVANCE_HINT := "推進時段（目前無可做動作）"
const _MSG_ADVANCE_SLEEP := "直接睡"
const _MSG_ADVANCE_NEXT_DAY := "進入隔天"
const _MSG_ADVANCE_END_NIGHT := "結束今晚"
const _FMT_STATUS := "第 %d 天  %s  第 %d 章"

# 版面：ContentView 內只有「FlowText 在上、內容面板在下」與「內容面板佔滿」兩種形狀。
# 兩者都由 _layout_with_flow() 產生，不在各分支重複寫 offset（P4-E 重構）。
const _LAYOUT_BOTTOM := 400.0
const _LAYOUT_FLOW_SHORT := 120.0  # 與下方內容共存時的 FlowText 高度
const _LAYOUT_FLOW_TALL := 200.0   # 遭遇開場：演出文字佔多一點
const _LAYOUT_GAP := 10.0

@onready var _error_label: Label = $ErrorLabel
@onready var _status_label: Label = $StatusLabel
@onready var _advance_btn: Button = $AdvanceButton
@onready var _opening_panel: Node = $ContentView/OpeningPanel
@onready var _ending_panel: Node = $ContentView/EndingPanel
@onready var _map_list: Node = $ContentView/MapList
@onready var _location_panel: Node = $ContentView/LocationPanel
@onready var _flow_text: FlowText = $ContentView/FlowText
@onready var _hand_bar: Node = $HandBar
@onready var _encounter_panel: Node = $ContentView/EncounterPanel
@onready var _delegation_tutorial_dialog: AcceptDialog = $DelegationTutorialDialog


func _enter_tree() -> void:
	_process_cli_args()


func _ready() -> void:
	_advance_btn.set_meta("qa_id", "phase_advance")

	if not Data.ok:
		_error_label.text = _MSG_DATA_ERROR
		_status_label.visible = false
		_advance_btn.visible = false
		return

	_advance_btn.pressed.connect(_on_advance_pressed)
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.day_changed.connect(_on_day_changed)
	GameState.chapter_changed.connect(_on_chapter_changed)
	GameState.flow_mode_changed.connect(_on_flow_mode_changed)
	GameState.ending_started.connect(_on_ending_started)
	GameState.opening_started.connect(_on_opening_started)
	GameState.delegation_tutorial_available.connect(_on_delegation_tutorial_available)

	_opening_panel.choice_selected.connect(_on_opening_choice_selected)
	_ending_panel.completed.connect(_on_ending_completed)

	_map_list.location_selected.connect(_on_location_selected)
	_location_panel.closed.connect(_on_panel_closed)
	_location_panel.state_changed.connect(_on_location_panel_state_changed)
	_location_panel.night_entry_requested.connect(_on_night_entry_requested)
	_location_panel.delegation_requested.connect(_on_delegation_requested)

	_delegation_tutorial_dialog.confirmed.connect(_on_delegation_tutorial_dismissed)
	_delegation_tutorial_dialog.close_requested.connect(_on_delegation_tutorial_dismissed)
	_delegation_tutorial_dialog.get_ok_button().set_meta("qa_id", "dialog_confirm::delegation_tutorial")

	# P4-E：遭遇面板訊號。面板只送意圖，mutation 由此處轉發至 GameState。
	_encounter_panel.intro_acknowledged.connect(_on_encounter_intro_acknowledged)
	_encounter_panel.response_requested.connect(_on_encounter_response_requested)
	_encounter_panel.discard_requested.connect(_on_encounter_discard_requested)
	_encounter_panel.escape_requested.connect(_on_encounter_escape_requested)
	_encounter_panel.card_detail_requested.connect(func(cid): _hand_bar.call("show_card_detail", cid))

	_refresh_status()
	_route_view()


func _process_cli_args() -> void:
	if not OS.is_debug_build() and not OS.has_feature("editor"):
		return

	var args: PackedStringArray = OS.get_cmdline_user_args()
	var data_root := ""
	var state_path := ""

	var i := 0
	while i < args.size():
		match args[i]:
			"--data-root":
				if i + 1 < args.size() and not args[i + 1].begins_with("--"):
					data_root = args[i + 1]
					i += 1
				else:
					printerr("ERROR: --data-root 缺少有效路徑參數")
					get_tree().quit(1)
					return
			"--state":
				if i + 1 < args.size() and not args[i + 1].begins_with("--"):
					state_path = args[i + 1]
					i += 1
				else:
					printerr("ERROR: --state 缺少有效檔案路徑參數")
					get_tree().quit(1)
					return
		i += 1

	if not data_root.is_empty():
		var normalized := data_root.replace("\\", "/")
		if normalized.ends_with("/"):
			normalized = normalized.substr(0, normalized.length() - 1)
		normalized += "/"
		var ok: bool = Data.load_data(normalized)
		if not ok:
			printerr("ERROR: --data-root 載入失敗: %s" % normalized)
			get_tree().quit(1)
			return

	if not state_path.is_empty():
		if not FileAccess.file_exists(state_path):
			printerr("ERROR: --state 檔案不存在: %s" % state_path)
			get_tree().quit(1)
			return
		var text := FileAccess.get_file_as_string(state_path)
		var json_val: Variant = JSON.parse_string(text)
		if json_val == null or not (json_val is Dictionary):
			printerr("ERROR: --state JSON 解析失敗: %s" % state_path)
			get_tree().quit(1)
			return
		var err_msg: String = QAValidationClass.validate_state_json(json_val as Dictionary, GameState.serialize(), GameState.PHASES)
		if not err_msg.is_empty():
			printerr("ERROR: --state 狀態檔不合法: %s (%s)" % [err_msg, state_path])
			get_tree().quit(1)
			return
		GameState.deserialize(json_val as Dictionary)


## 推進按鈕：RUN mode 下的唯一規則層入口。
## 夜間停拍已由 `advance_phase()` 內部吸收，UI 只負責渲染回傳的 lines 與 `phase_advanced`。
func _on_advance_pressed() -> void:
	if GameState.flow_mode != GameState.FLOW_RUN:
		return

	var res: Dictionary = GameState.advance_phase()
	if not bool(res.get("ok", false)):
		_refresh_advance_hint()
		return
	# 真的換了時段時，`phase_changed` 已經在 advance_phase() 內部重建畫面，回傳的
	# 那幾行（逾期預設）也已經寫進 GameState 的 transient，由 `_settlement_lines()`
	# 播出；這裡再播一次會變兩份。只有停拍（夜間直接睡）要自己渲染。
	if not bool(res.get("phase_advanced", false)):
		var lines: PackedStringArray = res.get("lines", PackedStringArray())
		if lines.size() > 0:
			_flow_text.clear()
			_flow_text.append_lines(lines)
			_flow_text.visible = true
			_layout_with_flow(_map_list)
		_refresh_advance_hint()


func _on_phase_changed(_day: int, _phase: String) -> void:
	_refresh_status()
	if GameState.flow_mode == GameState.FLOW_RUN:
		_route_view()


func _on_day_changed(_day: int) -> void:
	_refresh_status()


func _on_chapter_changed(_chapter: int) -> void:
	_refresh_status()


func _on_flow_mode_changed(_mode: String) -> void:
	_refresh_status()
	_route_view()


func _on_ending_started() -> void:
	_refresh_status()
	_route_view()


func _on_opening_started() -> void:
	_refresh_status()
	_route_view()


func _on_opening_choice_selected(choice_id: String) -> void:
	var res: Dictionary = GameState.choose_opening(choice_id)
	if not bool(res.get("ok", false)):
		printerr("選擇開局失敗: %s" % str(res.get("reason_text", "")))
		return
	_refresh_status()
	_route_view()


func _on_ending_completed() -> void:
	_refresh_status()
	_route_view()


func _on_location_selected(loc_id: String) -> void:
	if GameState.flow_mode != GameState.FLOW_RUN:
		return
	_flow_text.visible = false
	_map_list.visible = false
	_encounter_panel.visible = false
	_location_panel.visible = true
	_advance_btn.disabled = true
	if GameState.phase == "night":
		_location_panel.call("show_night_details", loc_id)
	else:
		_location_panel.call("show_location", loc_id)


func _on_night_entry_requested(loc_id: String) -> void:
	var entry_res: Dictionary = GameState.enter_night_location(loc_id)
	if not bool(entry_res.get("ok", false)):
		return
	if GameState.flow_mode != GameState.FLOW_RUN:
		return
	var extra_lines: PackedStringArray = entry_res.get("lines", PackedStringArray())
	_location_panel.call("show_location", loc_id, extra_lines)
	_refresh_advance_hint()


## P4-C（接線 A）：面板只送委託意圖，delegate() 與即時回報由此接手。
## 即時回報文字落 FlowText（與隔日上午回報同一處呈現）；成功後關面板回地圖。
## 委託不吃行動格，advance 按鈕恢復可用。失敗則保留面板並於面板內顯示原因。
func _on_delegation_requested(beat_id: String, slot_id: String, card_id: String) -> void:
	var result: Dictionary = GameState.delegate(beat_id, slot_id, card_id)
	if not bool(result.get("ok", false)):
		_location_panel.call("report_delegation_failure", result)
		return
	_location_panel.visible = false
	_advance_btn.disabled = false
	_map_list.visible = true
	_map_list.call("refresh")
	var lines_delegation: PackedStringArray = result.get("lines", PackedStringArray())
	_flow_text.clear()
	if lines_delegation.size() > 0:
		_flow_text.append_lines(lines_delegation)
		_flow_text.visible = true
	_layout_with_flow(_map_list)
	_hand_bar.call("refresh")
	_refresh_advance_hint()


func _on_panel_closed() -> void:
	_location_panel.visible = false
	_advance_btn.disabled = false
	_route_view()


func _on_location_panel_state_changed() -> void:
	_refresh_advance_hint()
	_hand_bar.call("refresh")


## P4-C：教學信號到達時彈出，不寫 meta；UI 顯示只是「已彈出」不等於「已看過」。
func _on_delegation_tutorial_available() -> void:
	_delegation_tutorial_dialog.popup_centered()


## P4-C：關閉／略過教學彈窗才算「已看過」，此時才寫入 delegation_tutorial_seen。
func _on_delegation_tutorial_dismissed() -> void:
	GameState.mark_delegation_tutorial_seen()


func _refresh_status() -> void:
	match GameState.flow_mode:
		GameState.FLOW_OPENING:
			_status_label.text = "出門前的十分鐘"
		GameState.FLOW_ENDING:
			_status_label.text = "結局"
		_:
			_status_label.text = _FMT_STATUS % [
				GameState.day, GameState.phase, GameState.chapter()
			]
	_refresh_advance_hint()


func _refresh_advance_hint() -> void:
	if GameState.flow_mode == GameState.FLOW_OPENING or GameState.flow_mode == GameState.FLOW_ENDING:
		_advance_btn.visible = false
		return

	# P4-E：遭遇進行中推進按鈕 disabled
	if not GameState.active_encounter.is_empty():
		_advance_btn.text = _MSG_ADVANCE
		_advance_btn.disabled = true
		_advance_btn.modulate = Color.WHITE
		return
	if GameState.phase == "morning" or GameState.phase == "afternoon":
		var has_action: bool = GameState.has_any_legal_action()
		_advance_btn.text = _MSG_ADVANCE if has_action else _MSG_ADVANCE_HINT
		_advance_btn.modulate = Color.WHITE if has_action else Color(1.0, 0.82, 0.4)
	elif GameState.phase == "night":
		if GameState.night_sleep_pending:
			_advance_btn.text = _MSG_ADVANCE_NEXT_DAY
		elif not GameState.night_location_chosen.is_empty():
			_advance_btn.text = _MSG_ADVANCE_END_NIGHT
		else:
			_advance_btn.text = _MSG_ADVANCE_SLEEP
		_advance_btn.modulate = Color.WHITE
	else:
		_advance_btn.text = _MSG_ADVANCE
		_advance_btn.modulate = Color.WHITE


func _route_view(encounter_lines: PackedStringArray = PackedStringArray()) -> void:
	if GameState.flow_mode == GameState.FLOW_OPENING:
		_opening_panel.visible = true
		_opening_panel.call("refresh")
		_ending_panel.visible = false
		_ending_panel.call("reset")
		_map_list.visible = false
		_location_panel.visible = false
		_encounter_panel.visible = false
		_flow_text.visible = false
		_hand_bar.visible = false
		_advance_btn.visible = false
		_refresh_status()
		return

	if GameState.flow_mode == GameState.FLOW_ENDING:
		_ending_panel.visible = true
		_ending_panel.call("refresh")
		_opening_panel.visible = false
		_map_list.visible = false
		_location_panel.visible = false
		_encounter_panel.visible = false
		_flow_text.visible = false
		_hand_bar.visible = false
		_advance_btn.visible = false
		_refresh_status()
		return

	# RUN 模式
	_opening_panel.visible = false
	_ending_panel.visible = false
	_hand_bar.visible = true
	_advance_btn.visible = true
	_advance_btn.disabled = false

	var phase: String = GameState.phase
	match phase:
		"morning", "afternoon":
			_location_panel.visible = false
			_encounter_panel.visible = false
			if encounter_lines.size() > 0:
				_flow_text.clear()
				_flow_text.append_lines(encounter_lines)
				_flow_text.visible = true
			else:
				_play_forced_lines()
			# P4-E：行動時段（D45 下午）遭遇自動啟動後攔截地圖渲染
			if not GameState.active_encounter.is_empty():
				_show_encounter()
				return
			_map_list.visible = true
			_layout_with_flow(_map_list)
			_map_list.call("refresh")
			_advance_btn.visible = true
		"evening":
			_encounter_panel.visible = false
			# 通用門檻：本時段有 phase_exit 的 fixed beat 就走內容面板，不特判日期或 beat id。
			if bool(GameState.phase_exit_status().get("has_gate", false)):
				_show_final_coda(encounter_lines)
			else:
				_map_list.visible = false
				_location_panel.visible = false
				if encounter_lines.size() > 0:
					_flow_text.clear()
					_flow_text.append_lines(encounter_lines)
					_flow_text.visible = true
				else:
					_play_evening()
					_flow_text.visible = true
				_layout_flow_full()
				_advance_btn.visible = true
		"night":
			_location_panel.visible = false
			_encounter_panel.visible = false
			if encounter_lines.size() > 0:
				_flow_text.clear()
				_flow_text.append_lines(encounter_lines)
				_flow_text.visible = true
			else:
				_play_night_fixed()
			# P4-E：夜間（D8）遭遇由 play_night_fixed() 自動啟動後攔截地圖渲染
			if not GameState.active_encounter.is_empty():
				_show_encounter()
				return
			_map_list.visible = true
			_layout_with_flow(_map_list)
			_map_list.call("refresh")
			_advance_btn.visible = true
	_refresh_advance_hint()


## 依 FlowText 當下是否真的有內容，決定它與下方內容面板的版面（P4-E 重構）。
## 有內容：FlowText 佔上方 flow_height，content 接在下面；沒內容：收起 FlowText，content 佔滿。
func _layout_with_flow(content: Node, flow_height: float = _LAYOUT_FLOW_SHORT) -> void:
	if _flow_text.visible and not _flow_text.get_lines().is_empty():
		_flow_text.offset_top = 0.0
		_flow_text.offset_bottom = flow_height
		content.offset_top = flow_height + _LAYOUT_GAP
		content.offset_bottom = _LAYOUT_BOTTOM
	else:
		_flow_text.visible = false
		content.offset_top = 0.0
		content.offset_bottom = _LAYOUT_BOTTOM


## FlowText 獨佔整個 ContentView（晚間演出、coda 完成）。
func _layout_flow_full() -> void:
	_flow_text.offset_top = 0.0
	_flow_text.offset_bottom = _LAYOUT_BOTTOM


## 進入本時段前後由規則層結算出來的演出文字，依 advance_phase() 內實際的結算順序合併：
## 逾期 choice default（換時段之前）→ 強制縱慾 → 委託延遲回報 → 自動進場 beat。
## 玩家沒有第二次機會看到這些字，因此每一種畫面都要播（K-193）。
func _settlement_lines() -> PackedStringArray:
	var lines: PackedStringArray = GameState.last_choice_default_lines.duplicate()
	lines.append_array(GameState.last_forced_lines)
	lines.append_array(GameState.last_delegation_report_lines)
	lines.append_array(GameState.last_auto_enter_lines)
	return lines


func _play_forced_lines() -> void:
	_flow_text.clear()
	var lines := _settlement_lines()
	if lines.size() > 0:
		_flow_text.append_lines(lines)
		_flow_text.visible = true
	else:
		_flow_text.visible = false


func _play_evening() -> void:
	_flow_text.clear()
	# 進場結算的文字在晚間演出之前，順序與規則層一致。
	_flow_text.append_lines(GameState.last_choice_default_lines)
	_flow_text.append_lines(GameState.play_evening())


func _show_final_coda(encounter_lines: PackedStringArray = PackedStringArray()) -> void:
	# coda 是 evening 的真 beat；它必須先經過地點面板，才能讓 required slot
	# 走正式 UI 放置入口，而不是由 headless 直接 try_place。
	# 門檻與地點都由規則層的 phase_exit 給，UI 不含 beat id 或槽 id 特判（P5-B）。
	var gate: Dictionary = GameState.phase_exit_status()
	var coda_location := str(gate.get("location", ""))
	var coda_done: bool = bool(gate.get("satisfied", false)) or coda_location.is_empty()
	_map_list.visible = false
	_advance_btn.visible = true
	if not coda_done:
		_location_panel.visible = true
		_advance_btn.disabled = true
		if encounter_lines.size() > 0:
			_flow_text.clear()
			_flow_text.append_lines(encounter_lines)
			_flow_text.visible = true
		_layout_with_flow(_location_panel)
		_location_panel.call("show_location", coda_location)
		return

	_location_panel.visible = false
	_flow_text.clear()
	_flow_text.append_line("[結局 coda 已完成]")
	_flow_text.visible = true
	_layout_flow_full()
	_advance_btn.disabled = false


func _play_night_fixed() -> void:
	_flow_text.clear()
	var lines: PackedStringArray = GameState.last_choice_default_lines.duplicate()
	lines.append_array(GameState.play_night_fixed())
	if lines.size() > 0:
		_flow_text.append_lines(lines)
		_flow_text.visible = true
	else:
		_flow_text.visible = false


## P4-E：遭遇 UI 顯示入口。根據 stage 切換 intro / round 呈現。
func _show_encounter() -> void:
	_map_list.visible = false
	_location_panel.visible = false
	_encounter_panel.visible = true
	_advance_btn.visible = true
	_refresh_advance_hint()

	var view: Dictionary = GameState.encounter_view()
	var stage := str(view.get("stage", "intro"))

	if stage == "intro":
		# Intro 階段：FlowText 顯示 beat text（D8 已由 play_night_fixed 填入；D45 需從 data 取出）。
		if not _flow_text.visible or _flow_text.get_lines().is_empty():
			var beat_id := str(GameState.active_encounter.get("beat_id", ""))
			if Data != null and Data.loader != null:
				var beat: Dictionary = Data.loader.beats_by_id.get(beat_id, {}) as Dictionary
				var text := str(beat.get("text", ""))
				if not text.is_empty():
					_flow_text.clear()
					_flow_text.append_line(text)
					_flow_text.visible = true
		_layout_with_flow(_encounter_panel, _LAYOUT_FLOW_TALL)
		_encounter_panel.call("show_intro")
	else:
		# Round 階段：FlowText 保留先前文字（acknowledge 結果或 response 結果）。
		_layout_with_flow(_encounter_panel)
		_encounter_panel.call("show_round", view)

	_refresh_advance_hint()


## P4-E：確認開場 → 進入第一回合。
func _on_encounter_intro_acknowledged() -> void:
	var result: Dictionary = GameState.acknowledge_encounter_intro()
	if not bool(result.get("ok", false)):
		return
	_handle_encounter_result(result)


## P4-E：提交卡片回應。
func _on_encounter_response_requested(card_id: String) -> void:
	var result: Dictionary = GameState.respond_to_encounter(card_id)
	if not bool(result.get("ok", false)):
		return
	_handle_encounter_result(result)


## P4-E：主動丟棄。
func _on_encounter_discard_requested(card_id: String) -> void:
	var result: Dictionary = GameState.discard_in_encounter(card_id)
	if not bool(result.get("ok", false)):
		return
	_handle_encounter_result(result)


## P4-E：逃離遭遇。
func _on_encounter_escape_requested(card_ids: Array[String]) -> void:
	var result: Dictionary = GameState.escape_encounter(card_ids)
	if not bool(result.get("ok", false)):
		return
	_handle_encounter_result(result)


## P4-E：統一處理遭遇 mutation 結果。遭遇結束→關面板重路由；繼續→刷新面板。
func _handle_encounter_result(result: Dictionary) -> void:
	var lines: PackedStringArray = result.get("lines", PackedStringArray())

	if GameState.active_encounter.is_empty():
		# 遭遇結束：關面板 → 重路由，出口文字顯示在 FlowText 上
		_encounter_panel.visible = false
		_hand_bar.call("refresh")
		_route_view(lines)
	else:
		# 遭遇繼續：更新 FlowText，版面與面板渲染一律交給 _show_encounter()，
		# 不再另寫一份 round 分支（原本的複本已與本尊分歧，少了 FlowText 收起那行）。
		if lines.size() > 0:
			_flow_text.clear()
			_flow_text.append_lines(lines)
			_flow_text.visible = true
		_show_encounter()
		_hand_bar.call("refresh")
	_refresh_advance_hint()
