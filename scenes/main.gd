extends Control

## 主場景。P1-F：白天/夜間地圖、晚間演出（fixed beats + 殘響）、夜間解析、結局迴圈與 FlowText 容器（K-28）。

const ConditionEval := preload("res://scripts/core/condition_eval.gd")
const QAValidationClass := preload("res://tests/ui_sim/qa_validation.gd")

const _MSG_DATA_ERROR := "資料載入失敗，詳情見 Output。"
const _MSG_ENDING_STUB := "[結局 stub]"
const _MSG_ENDING_MADNESS_BE := "[發瘋 BE]"
const _MSG_ADVANCE := "推進時段"
const _MSG_ADVANCE_HINT := "推進時段（目前無可做動作）"
const _MSG_ADVANCE_SLEEP := "直接睡"
const _MSG_ADVANCE_NEXT_DAY := "進入隔天"
const _MSG_ADVANCE_END_NIGHT := "結束今晚"
const _FMT_STATUS := "第 %d 天  %s  第 %d 章"

@onready var _error_label: Label = $ErrorLabel
@onready var _status_label: Label = $StatusLabel
@onready var _advance_btn: Button = $AdvanceButton
@onready var _map_list: Node = $ContentView/MapList
@onready var _location_panel: Node = $ContentView/LocationPanel
@onready var _flow_text: FlowText = $ContentView/FlowText
@onready var _hand_bar: Node = $HandBar
@onready var _encounter_panel: Node = $ContentView/EncounterPanel
@onready var _delegation_tutorial_dialog: AcceptDialog = $DelegationTutorialDialog

var _is_showing_ending := false


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
	GameState.run_ended.connect(_on_run_ended)
	GameState.delegation_tutorial_available.connect(_on_delegation_tutorial_available)

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


func _on_advance_pressed() -> void:
	if _is_showing_ending:
		_is_showing_ending = false
		_route_view()
		return

	if GameState.phase == "night":
		var night_res: Dictionary = GameState.resolve_night_advance()
		if not bool(night_res.get("advance", false)):
			var lines: PackedStringArray = night_res.get("lines", PackedStringArray())
			if lines.size() > 0:
				_flow_text.clear()
				_flow_text.append_lines(lines)
				_flow_text.visible = true
				_flow_text.offset_top = 0.0
				_flow_text.offset_bottom = 120.0
				_map_list.offset_top = 130.0
				_map_list.offset_bottom = 400.0
			_refresh_advance_hint()
			return

	GameState.advance_phase()


func _on_phase_changed(_day: int, _phase: String) -> void:
	_refresh_status()
	if not _is_showing_ending:
		_route_view()


func _on_day_changed(_day: int) -> void:
	_refresh_status()


func _on_chapter_changed(_chapter: int) -> void:
	_refresh_status()


func _on_run_ended(ending_id: String) -> void:
	_is_showing_ending = true
	_flow_text.clear()
	if ending_id == "ending_madness_be":
		_flow_text.append_line(_MSG_ENDING_MADNESS_BE)
	else:
		_flow_text.append_line(_MSG_ENDING_STUB)
	_flow_text.visible = true
	_map_list.visible = false
	_location_panel.visible = false
	_encounter_panel.visible = false
	_advance_btn.visible = true
	_advance_btn.disabled = false


func _on_location_selected(loc_id: String) -> void:
	if _is_showing_ending:
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
	if _is_showing_ending:
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
		_flow_text.offset_top = 0.0
		_flow_text.offset_bottom = 120.0
		_map_list.offset_top = 130.0
		_map_list.offset_bottom = 400.0
	else:
		_flow_text.visible = false
		_map_list.offset_top = 0.0
		_map_list.offset_bottom = 400.0
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
	_status_label.text = _FMT_STATUS % [
		GameState.day, GameState.phase, GameState.chapter()
	]
	_refresh_advance_hint()


func _refresh_advance_hint() -> void:
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
	_advance_btn.disabled = false
	if _is_showing_ending:
		_flow_text.visible = true
		_flow_text.offset_top = 0.0
		_flow_text.offset_bottom = 400.0
		_map_list.visible = false
		_location_panel.visible = false
		_encounter_panel.visible = false
		_advance_btn.visible = true
		return

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
			if _flow_text.visible and not _flow_text.get_lines().is_empty():
				_flow_text.offset_top = 0.0
				_flow_text.offset_bottom = 120.0
				_map_list.offset_top = 130.0
				_map_list.offset_bottom = 400.0
			else:
				_flow_text.visible = false
				_map_list.offset_top = 0.0
				_map_list.offset_bottom = 400.0
			_map_list.call("refresh")
			_advance_btn.visible = true
		"evening":
			_encounter_panel.visible = false
			if GameState.day == GameState.LAST_DAY:
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
				_flow_text.offset_top = 0.0
				_flow_text.offset_bottom = 400.0
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
			if _flow_text.visible and not _flow_text.get_lines().is_empty():
				_flow_text.offset_top = 0.0
				_flow_text.offset_bottom = 120.0
				_map_list.offset_top = 130.0
				_map_list.offset_bottom = 400.0
			else:
				_flow_text.visible = false
				_map_list.offset_top = 0.0
				_map_list.offset_bottom = 400.0
			_map_list.call("refresh")
			_advance_btn.visible = true
	_refresh_advance_hint()


func _play_forced_lines() -> void:
	_flow_text.clear()
	# P4-B 強制縱慾與 P4-C 委託延遲回報同屬「換日上午既有結算」產生的演出文字，
	# 依 advance_phase() 內實際結算順序（強制縱慾先、委託回報後）合併播出。
	var lines: PackedStringArray = GameState.last_forced_lines.duplicate()
	lines.append_array(GameState.last_delegation_report_lines)
	if lines.size() > 0:
		_flow_text.append_lines(lines)
		_flow_text.visible = true
	else:
		_flow_text.visible = false


func _play_evening() -> void:
	_flow_text.clear()
	var lines := GameState.play_evening()
	_flow_text.append_lines(lines)


func _show_final_coda(encounter_lines: PackedStringArray = PackedStringArray()) -> void:
	# d45_then 是 evening 的真 beat；它必須先經過地點面板，才能讓
	# compare_registry 走正式 UI 放置入口，而不是由 headless 直接 try_place。
	var placed: Dictionary = GameState.slots_placed as Dictionary
	var coda_done := placed.has("d45_then::compare_registry")
	_map_list.visible = false
	_advance_btn.visible = true
	if not coda_done:
		_location_panel.visible = true
		_advance_btn.disabled = true
		if encounter_lines.size() > 0:
			_flow_text.clear()
			_flow_text.append_lines(encounter_lines)
			_flow_text.visible = true
			_flow_text.offset_top = 0.0
			_flow_text.offset_bottom = 120.0
			_location_panel.offset_top = 130.0
			_location_panel.offset_bottom = 400.0
		elif _flow_text.visible and not _flow_text.get_lines().is_empty():
			_flow_text.offset_top = 0.0
			_flow_text.offset_bottom = 120.0
			_location_panel.offset_top = 130.0
			_location_panel.offset_bottom = 400.0
		else:
			_flow_text.visible = false
			_location_panel.offset_top = 0.0
			_location_panel.offset_bottom = 400.0
		_location_panel.call("show_location", "jinghe_back")
		return

	_location_panel.visible = false
	_flow_text.clear()
	_flow_text.append_line("[結局 coda 已完成]")
	_flow_text.visible = true
	_flow_text.offset_top = 0.0
	_flow_text.offset_bottom = 400.0
	_advance_btn.disabled = false


func _play_night_fixed() -> void:
	_flow_text.clear()
	var lines := GameState.play_night_fixed()
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
		_flow_text.offset_top = 0.0
		_flow_text.offset_bottom = 200.0
		_encounter_panel.offset_top = 210.0
		_encounter_panel.offset_bottom = 400.0
		_encounter_panel.call("show_intro")
	else:
		# Round 階段：FlowText 保留先前文字（acknowledge 結果或 response 結果）。
		if _flow_text.visible and not _flow_text.get_lines().is_empty():
			_flow_text.offset_top = 0.0
			_flow_text.offset_bottom = 120.0
			_encounter_panel.offset_top = 130.0
			_encounter_panel.offset_bottom = 400.0
		else:
			_flow_text.visible = false
			_encounter_panel.offset_top = 0.0
			_encounter_panel.offset_bottom = 400.0
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
		# 遭遇繼續：更新 FlowText 與面板
		if lines.size() > 0:
			_flow_text.clear()
			_flow_text.append_lines(lines)
			_flow_text.visible = true
		var view: Dictionary = GameState.encounter_view()
		var stage := str(view.get("stage", ""))
		if stage == "round":
			if _flow_text.visible and not _flow_text.get_lines().is_empty():
				_flow_text.offset_top = 0.0
				_flow_text.offset_bottom = 120.0
				_encounter_panel.offset_top = 130.0
				_encounter_panel.offset_bottom = 400.0
			else:
				_encounter_panel.offset_top = 0.0
				_encounter_panel.offset_bottom = 400.0
			_encounter_panel.call("show_round", view)
		else:
			_show_encounter()
		_hand_bar.call("refresh")
	_refresh_advance_hint()
