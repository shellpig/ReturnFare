extends SceneTree

## P4-D 遭遇規則 headless 驗收測試：
## 1. 遭遇啟動與開場確認（start_encounter, stage intro, acknowledge_encounter_intro, stage round）
## 2. 遭遇進行中時段與各類放置／委託／縱慾／夜間操作阻擋（encounter_active）
## 3. 15 碼封閉拒絕矩陣與 6 個入口之拒絕順序優先驗證
## 4. 超載規則（is_overloaded 查詢、enter_night_location 阻擋、開場 penalty 佔格）
## 5. 佔格計算與扣除（進入回合加佔格、正解釋放本回合佔格、錯答保留佔格）
## 6. 錯答與可丟棄檢查（fallback.requires_discardable 阻擋不可丟棄卡、可丟棄卡錯答扣除）
## 7. 主動丟棄卡片（allow_discard 阻擋、合法丟棄扣卡不變佔格不推進）
## 8. 逃離遭遇（cannot_escape 阻擋、足額支付扣卡結算）
## 9. 無合法解自動結算 failure
## 10. 容量上限失敗結算（手牌數＋佔格數 >= 容量）
## 11. 遭遇勝利與效果套用（多回合圖走完勝利、on_victory 效果套用、active_encounter 清空）
## 12. 遭遇結束後推進（after_finish: "advance_phase" 推進時段、"stay" 停留原時段）
## 13. 遭遇狀態序列化與還原往返（serialize / deserialize）
## 14. 故事線遭遇契約驗證（D8 河豚毒素、D45 結局 coda）

const DataLoader := preload("res://scripts/data_loader.gd")
const ConditionEval := preload("res://scripts/core/condition_eval.gd")
const Encounter := preload("res://scripts/core/encounter.gd")
const PlaythroughGreedy := preload("res://tests/headless/playthrough_greedy.gd")

func _initialize() -> void:
	var data_node: Node = PlaythroughGreedy.setup_data(self)
	var gs: Node = PlaythroughGreedy.setup_game_state(self, data_node)

	await process_frame

	if not bool(data_node.get("ok")):
		push_error("P4-D: Data failed to load; abort")
		quit(1)
		return

	var failed: int = 0
	print("\n=== P4-D 遭遇規則測試套件 ===")

	failed += _test_encounter_lifecycle_and_view(gs, data_node)
	failed += _test_mutation_blocking_during_encounter(gs, data_node)
	failed += _test_15_code_rejection_matrix(gs, data_node)
	failed += _test_rejection_priority_orders(gs, data_node)
	failed += _test_overload_and_penalty(gs, data_node)
	failed += _test_slot_blocking_and_release(gs, data_node)
	failed += _test_discard_and_escape(gs, data_node)
	failed += _test_no_legal_moves_auto_failure(gs, data_node)
	failed += _test_capacity_exhaustion_failure(gs, data_node)
	failed += _test_victory_and_after_finish(gs, data_node)
	failed += _test_serialization_roundtrip(gs, data_node)
	failed += _test_storyline_encounters_contract(gs, data_node)

	if failed > 0:
		push_error("\nP4-D: %d assertion(s) failed\n" % failed)
		quit(1)
	else:
		print("\nP4-D: all tests passed\n")
		quit(0)


func _ok(msg: String) -> int:
	print("  [OK] %s" % msg)
	return 0


func _err(msg: String) -> int:
	push_error("  [FAIL] %s" % msg)
	return 1


## Helper: 建立乾淨測試環境與自訂 beat
func _reset_gs(gs: Node) -> void:
	gs.end_run("test_reset")
	gs.day = 1
	gs.phase = "morning"
	gs.hand.clear()
	gs.hand.append("protagonist")
	gs.knowledge.clear()
	gs.active_encounter.clear()


func _create_mock_encounter_beat(data_node: Node, beat_id: String, enc_data: Dictionary) -> void:
	var b: Dictionary = {
		"id": beat_id,
		"location": "sanquan",
		"when": { "day_from": 1, "day_to": 45, "phases": ["morning", "afternoon", "evening", "night"] },
		"encounter": enc_data
	}
	data_node.loader.beats_by_id[beat_id] = b


# ── 1. 遭遇啟動與開場確認 ───────────────────────────────────────────────────

func _test_encounter_lifecycle_and_view(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)

	data_node.loader.cards["k_fugu_cure"] = { "id": "k_fugu_cure", "type": "knowledge", "slotless": true, "discardable": false }

	var mock_enc: Dictionary = {
		"repeat_each_run": true,
		"charge_first_visit": false,
		"per_round_slot_cost": 1,
		"escape_cost": 1,
		"allow_discard": true,
		"after_finish": "stay",
		"rounds": [
			{
				"id": "r1",
				"prompt": "第一回合提示",
				"responses": [
					{
						"accepts": ["k_fugu_cure"],
						"consume_card": false,
						"next_round": "r2",
						"on_resolve": { "flag": { "r1_cleared": true } }
					}
				],
				"fallback": {
					"prompt": "錯答提示",
					"requires_discardable": true,
					"next_round": null,
					"on_resolve": {}
				}
			},
			{
				"id": "r2",
				"prompt": "第二回合提示",
				"responses": [
					{
						"accepts": ["k_fugu_cure"],
						"consume_card": false,
						"next_round": null,
						"on_resolve": {}
					}
				],
				"fallback": {
					"requires_discardable": false,
					"next_round": null
				}
			}
		],
		"on_victory": { "flag": { "enc_victory": true } },
		"on_failure": { "flag": { "enc_failed": true } }
	}
	_create_mock_encounter_beat(data_node, "mock_enc_lifecycle", mock_enc)

	# 啟動遭遇
	var res_start: Dictionary = gs.start_encounter("mock_enc_lifecycle")
	if not bool(res_start.get("ok", false)):
		failed += _err("start_encounter failed: %s" % str(res_start))
	elif str(gs.active_encounter.get("stage", "")) != "intro":
		failed += _err("active_encounter stage should be 'intro', got '%s'" % str(gs.active_encounter.get("stage", "")))
	elif int(gs.active_encounter.get("blocked_slots", -1)) != 0:
		failed += _err("blocked_slots should be 0 on intro, got %d" % int(gs.active_encounter.get("blocked_slots", -1)))
	else:
		failed += _ok("start_encounter correctly enters stage 'intro' with blocked_slots=0")

	# View model 檢查
	var view: Dictionary = gs.encounter_view()
	if str(view.get("stage", "")) != "intro":
		failed += _err("encounter_view stage should be 'intro'")
	elif int(view.get("blocked_slots", -1)) != 0:
		failed += _err("encounter_view blocked_slots should be 0")
	else:
		failed += _ok("encounter_view correctly reflects intro stage")

	# acknowledge intro 進入 round 1
	gs.knowledge["k_fugu_cure"] = true
	var res_ack: Dictionary = gs.acknowledge_encounter_intro()
	if not bool(res_ack.get("ok", false)):
		failed += _err("acknowledge_encounter_intro failed: %s" % str(res_ack))
	elif str(gs.active_encounter.get("stage", "")) != "round":
		failed += _err("active_encounter stage should be 'round', got '%s'" % str(gs.active_encounter.get("stage", "")))
	elif str(gs.active_encounter.get("round_id", "")) != "r1":
		failed += _err("round_id should be 'r1', got '%s'" % str(gs.active_encounter.get("round_id", "")))
	elif int(gs.active_encounter.get("blocked_slots", -1)) != 1:
		failed += _err("blocked_slots should be 1 after r1 entry, got %d" % int(gs.active_encounter.get("blocked_slots", -1)))
	else:
		failed += _ok("acknowledge_encounter_intro enters stage 'round' at r1 with blocked_slots=1")

	return failed


# ── 2. 遭遇進行中時段與各類操作阻擋 ──────────────────────────────────────────

func _test_mutation_blocking_during_encounter(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)

	var mock_enc: Dictionary = {
		"repeat_each_run": true,
		"per_round_slot_cost": 1,
		"escape_cost": null,
		"allow_discard": true,
		"after_finish": "stay",
		"rounds": [
			{
				"id": "r1",
				"responses": [{ "accepts": ["protagonist"], "next_round": null }],
				"fallback": { "requires_discardable": false, "next_round": null }
			}
		]
	}
	_create_mock_encounter_beat(data_node, "mock_enc_block", mock_enc)
	gs.start_encounter("mock_enc_block")

	# 1. advance_phase
	var res_adv: Dictionary = gs.advance_phase()
	if bool(res_adv.get("ok", true)) or str(res_adv.get("reason_code", "")) != "encounter_active" or bool(res_adv.get("phase_advanced", true)):
		failed += _err("advance_phase should be blocked with reason_code 'encounter_active'")
	else:
		failed += _ok("advance_phase is blocked during active encounter")

	# 2. try_place
	var res_place: Dictionary = gs.try_place("protagonist", "some_beat", "some_slot")
	if bool(res_place.get("ok", true)) or str(res_place.get("reason_code", "")) != "encounter_active":
		failed += _err("try_place should be blocked with reason_code 'encounter_active'")
	else:
		failed += _ok("try_place is blocked during active encounter")

	# 3. choose
	var res_choose: Dictionary = gs.choose("some_beat", "g1", "slot1", "protagonist")
	if bool(res_choose.get("ok", true)) or str(res_choose.get("reason_code", "")) != "encounter_active":
		failed += _err("choose should be blocked with reason_code 'encounter_active'")
	else:
		failed += _ok("choose is blocked during active encounter")

	# 4. delegate
	var res_del: Dictionary = gs.delegate("some_beat", "slot1", "protagonist")
	if bool(res_del.get("ok", true)) or str(res_del.get("reason_code", "")) != "encounter_active":
		failed += _err("delegate should be blocked with reason_code 'encounter_active'")
	else:
		failed += _ok("delegate is blocked during active encounter")

	# 5. indulge
	var res_ind: Dictionary = gs.indulge("some_beat", "slot1", "protagonist")
	if bool(res_ind.get("ok", true)) or str(res_ind.get("reason_code", "")) != "encounter_active":
		failed += _err("indulge should be blocked with reason_code 'encounter_active'")
	else:
		failed += _ok("indulge is blocked during active encounter")

	# 6. confirm_night_alignment
	var res_align: Dictionary = gs.confirm_night_alignment("sanquan")
	if bool(res_align.get("ok", true)) or str(res_align.get("reason_code", "")) != "encounter_active":
		failed += _err("confirm_night_alignment should be blocked with reason_code 'encounter_active'")
	else:
		failed += _ok("confirm_night_alignment is blocked during active encounter")

	# 7. enter_night_location
	gs.phase = "night"
	var res_night: Dictionary = gs.enter_night_location("sanquan_night")
	if bool(res_night.get("ok", true)) or str(res_night.get("reason_code", "")) != "encounter_active":
		failed += _err("enter_night_location should be blocked with reason_code 'encounter_active'")
	else:
		failed += _ok("enter_night_location is blocked during active encounter")

	# 8. resolve_night_advance
	var res_night_adv: Dictionary = gs.resolve_night_advance()
	if bool(res_night_adv.get("advance", true)) or str(res_night_adv.get("reason_code", "")) != "encounter_active":
		failed += _err("resolve_night_advance should be blocked with reason_code 'encounter_active'")
	else:
		failed += _ok("resolve_night_advance is blocked during active encounter")

	return failed


# ── 3. 15 碼封閉拒絕矩陣驗證 ────────────────────────────────────────────────

func _test_15_code_rejection_matrix(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)

	data_node.loader.cards["k_clue"] = { "id": "k_clue", "type": "knowledge", "slotless": true, "discardable": false }

	var mock_enc: Dictionary = {
		"repeat_each_run": true,
		"per_round_slot_cost": 1,
		"escape_cost": 1,
		"allow_discard": false,
		"after_finish": "stay",
		"rounds": [
			{
				"id": "r1",
				"responses": [{ "accepts": ["k_clue"], "next_round": null }],
				"fallback": { "requires_discardable": true, "next_round": null }
			}
		]
	}
	_create_mock_encounter_beat(data_node, "mock_enc_matrix", mock_enc)

	# 1. no_active_encounter (when inactive)
	var r_ack_no: Dictionary = gs.acknowledge_encounter_intro()
	if str(r_ack_no.get("reason_code", "")) != "no_active_encounter":
		failed += _err("acknowledge without active encounter should give 'no_active_encounter'")
	var r_resp_no: Dictionary = gs.respond_to_encounter("protagonist")
	if str(r_resp_no.get("reason_code", "")) != "no_active_encounter":
		failed += _err("respond without active encounter should give 'no_active_encounter'")
	var r_disc_no: Dictionary = gs.discard_in_encounter("protagonist")
	if str(r_disc_no.get("reason_code", "")) != "no_active_encounter":
		failed += _err("discard without active encounter should give 'no_active_encounter'")
	var esc_p: Array[String] = ["protagonist"]
	var r_esc_no: Dictionary = gs.escape_encounter(esc_p)
	if str(r_esc_no.get("reason_code", "")) != "no_active_encounter":
		failed += _err("escape without active encounter should give 'no_active_encounter'")
	failed += _ok("no_active_encounter tested across all endpoints")

	# 2. unknown_beat
	var r_unk_beat: Dictionary = gs.start_encounter("non_existent_beat_id")
	if str(r_unk_beat.get("reason_code", "")) != "unknown_beat":
		failed += _err("start_encounter with invalid beat_id should give 'unknown_beat'")
	else:
		failed += _ok("unknown_beat tested")

	# 3. data_conflict on start_encounter (missing rounds)
	var mock_bad_enc: Dictionary = { "per_round_slot_cost": 1, "after_finish": "stay" }
	_create_mock_encounter_beat(data_node, "mock_bad_enc", mock_bad_enc)
	var r_bad: Dictionary = gs.start_encounter("mock_bad_enc")
	if str(r_bad.get("reason_code", "")) != "data_conflict":
		failed += _err("start_encounter with missing rounds should give 'data_conflict'")
	else:
		failed += _ok("data_conflict on start_encounter tested")

	# Start valid encounter -> stage: "intro"
	gs.start_encounter("mock_enc_matrix")

	# 4. encounter_active (calling start_encounter while active)
	var r_start_active: Dictionary = gs.start_encounter("mock_enc_matrix")
	if str(r_start_active.get("reason_code", "")) != "encounter_active":
		failed += _err("start_encounter while active should give 'encounter_active'")
	else:
		failed += _ok("encounter_active tested on start_encounter")

	# 5. wrong_stage (respond, discard, escape during intro stage)
	var r_resp_stage: Dictionary = gs.respond_to_encounter("protagonist")
	if str(r_resp_stage.get("reason_code", "")) != "wrong_stage":
		failed += _err("respond during intro stage should give 'wrong_stage'")
	var r_disc_stage: Dictionary = gs.discard_in_encounter("protagonist")
	if str(r_disc_stage.get("reason_code", "")) != "wrong_stage":
		failed += _err("discard during intro stage should give 'wrong_stage'")
	var r_esc_stage: Dictionary = gs.escape_encounter(esc_p)
	if str(r_esc_stage.get("reason_code", "")) != "wrong_stage":
		failed += _err("escape during intro stage should give 'wrong_stage'")
	failed += _ok("wrong_stage tested during intro stage")

	# Acknowledge intro -> enter round
	gs.knowledge["k_clue"] = true
	gs.acknowledge_encounter_intro()

	# 6. wrong_stage (acknowledge during round stage)
	var r_ack_stage: Dictionary = gs.acknowledge_encounter_intro()
	if str(r_ack_stage.get("reason_code", "")) != "wrong_stage":
		failed += _err("acknowledge during round stage should give 'wrong_stage'")
	else:
		failed += _ok("wrong_stage tested during round stage")

	# 7. unknown_card
	var r_unk_c: Dictionary = gs.respond_to_encounter("totally_fake_card_id")
	if str(r_unk_c.get("reason_code", "")) != "unknown_card":
		failed += _err("respond with unknown card should give 'unknown_card'")
	else:
		failed += _ok("unknown_card tested")

	# 8. not_held
	var r_not_held: Dictionary = gs.respond_to_encounter("info_husband_version") # exists in data, not held
	if str(r_not_held.get("reason_code", "")) != "not_held":
		failed += _err("respond with unheld card should give 'not_held', got '%s'" % str(r_not_held))
	else:
		failed += _ok("not_held tested")

	# 9. madness_blocked
	gs.gain_card("madness")
	var madness_inst: String = str(gs.hand[gs.hand.size() - 1])
	var r_mad: Dictionary = gs.respond_to_encounter(madness_inst)
	if str(r_mad.get("reason_code", "")) != "madness_blocked":
		failed += _err("respond with madness card should give 'madness_blocked', got '%s'" % str(r_mad))
	else:
		failed += _ok("madness_blocked tested")

	# 10. card_not_submittable (fallback requires discardable, but protagonist is discardable: false)
	var r_not_sub: Dictionary = gs.respond_to_encounter("protagonist")
	if str(r_not_sub.get("reason_code", "")) != "card_not_submittable":
		failed += _err("respond with non-discardable card on fallback requiring discardable should give 'card_not_submittable'")
	else:
		failed += _ok("card_not_submittable tested")

	# 11. discard_disabled
	var r_disc_dis: Dictionary = gs.discard_in_encounter("protagonist")
	if str(r_disc_dis.get("reason_code", "")) != "discard_disabled":
		failed += _err("discard when allow_discard:false should give 'discard_disabled'")
	else:
		failed += _ok("discard_disabled tested")

	# 12. not_discardable (on discard and escape)
	mock_enc["allow_discard"] = true
	var r_disc_nd: Dictionary = gs.discard_in_encounter(madness_inst)
	if str(r_disc_nd.get("reason_code", "")) != "not_discardable":
		failed += _err("discard madness card should give 'not_discardable'")
	var r_disc_prot: Dictionary = gs.discard_in_encounter("protagonist")
	if str(r_disc_prot.get("reason_code", "")) != "not_discardable":
		failed += _err("discard protagonist should give 'not_discardable'")
	failed += _ok("not_discardable tested on discard")

	# 13. cannot_escape
	mock_enc["escape_cost"] = null
	var r_cannot_esc: Dictionary = gs.escape_encounter(esc_p)
	if str(r_cannot_esc.get("reason_code", "")) != "cannot_escape":
		failed += _err("escape when escape_cost is null should give 'cannot_escape'")
	else:
		failed += _ok("cannot_escape tested")

	# 14. wrong_escape_count & duplicate_payment
	mock_enc["escape_cost"] = 2
	var r_esc_cnt: Dictionary = gs.escape_encounter(esc_p)
	if str(r_esc_cnt.get("reason_code", "")) != "wrong_escape_count":
		failed += _err("escape with wrong count should give 'wrong_escape_count'")
	var esc_dup: Array[String] = ["protagonist", "protagonist"]
	var r_esc_dup: Dictionary = gs.escape_encounter(esc_dup)
	if str(r_esc_dup.get("reason_code", "")) != "duplicate_payment":
		failed += _err("escape with duplicate cards should give 'duplicate_payment'")
	failed += _ok("wrong_escape_count and duplicate_payment tested")

	# 15. already_attempted
	(gs.active_encounter["attempted_card_ids"] as Array).append("k_clue")
	var r_att: Dictionary = gs.respond_to_encounter("k_clue")
	if str(r_att.get("reason_code", "")) != "already_attempted":
		failed += _err("respond with already attempted card should give 'already_attempted'")
	else:
		failed += _ok("already_attempted tested")

	return failed


# ── 4. 拒絕優先順序驗證 ────────────────────────────────────────────────────

func _test_rejection_priority_orders(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)

	data_node.loader.cards["k_clue"] = { "id": "k_clue", "type": "knowledge", "slotless": true, "discardable": false }
	gs.gain_card("madness")
	var m_inst: String = str(gs.hand[gs.hand.size() - 1])

	var mock_enc: Dictionary = {
		"repeat_each_run": true,
		"per_round_slot_cost": 1,
		"escape_cost": null,
		"allow_discard": true,
		"after_finish": "stay",
		"rounds": [
			{
				"id": "r1",
				"responses": [{ "accepts": ["k_clue"], "next_round": null }],
				"fallback": { "requires_discardable": false, "next_round": null }
			}
		]
	}
	_create_mock_encounter_beat(data_node, "mock_enc_prio", mock_enc)
	gs.knowledge["k_clue"] = true
	gs.start_encounter("mock_enc_prio")
	gs.acknowledge_encounter_intro()

	(gs.active_encounter["attempted_card_ids"] as Array).append("madness")
	var r_mad_prio: Dictionary = gs.respond_to_encounter(m_inst)
	if str(r_mad_prio.get("reason_code", "")) != "madness_blocked":
		failed += _err("madness_blocked should take priority over already_attempted, got '%s'" % str(r_mad_prio))
	else:
		failed += _ok("madness_blocked takes priority over already_attempted")

	# enter_night_location 優先順序：not_night > encounter_active > overloaded
	gs.phase = "morning"
	var r_loc_not_night: Dictionary = gs.enter_night_location("sanquan_night")
	if str(r_loc_not_night.get("reason_code", "")) != "not_night":
		failed += _err("enter_night_location not_night should take priority over encounter_active")
	else:
		failed += _ok("enter_night_location: not_night > encounter_active verified")

	gs.phase = "night"
	var r_loc_enc_active: Dictionary = gs.enter_night_location("sanquan_night")
	if str(r_loc_enc_active.get("reason_code", "")) != "encounter_active":
		failed += _err("enter_night_location encounter_active should take priority over overloaded")
	else:
		failed += _ok("enter_night_location: encounter_active > overloaded verified")

	return failed


# ── 5. 超載規則 ────────────────────────────────────────────────────────────

func _test_overload_and_penalty(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)

	data_node.loader.cards["k_clue"] = { "id": "k_clue", "type": "knowledge", "slotless": true, "discardable": false }
	var max_hand: int = int(data_node.tuning("hand_size", 14))

	# 1. is_overloaded 測試
	if gs.is_overloaded():
		failed += _err("is_overloaded should be false with 1 card")
	else:
		failed += _ok("is_overloaded false for hand <= %d" % max_hand)

	# 手牌填滿至 max_hand + 1 張（超載）
	while gs.hand.size() <= max_hand:
		var dummy_id := "test_card_%d" % gs.hand.size()
		data_node.loader.cards[dummy_id] = { "id": dummy_id, "type": "item", "discardable": false }
		gs.hand.append(dummy_id)

	if not gs.is_overloaded():
		failed += _err("is_overloaded should be true with %d cards (hand_size=%d)" % [gs.hand.size(), max_hand])
	else:
		failed += _ok("is_overloaded true for hand > %d" % max_hand)

	# 2. 超載時進入夜間地點被阻擋（無遭遇時）
	gs.active_encounter.clear()
	gs.phase = "night"
	var res_loc_ov: Dictionary = gs.enter_night_location("sanquan_night")
	if str(res_loc_ov.get("reason_code", "")) != "overloaded":
		failed += _err("enter_night_location should return 'overloaded' when overloaded, got '%s'" % str(res_loc_ov))
	else:
		failed += _ok("enter_night_location correctly rejected with code 'overloaded'")

	# 3. 超載進入遭遇時，acknowledge_encounter_intro 先扣一次 penalty cost
	gs.phase = "morning"
	var mock_enc: Dictionary = {
		"repeat_each_run": true,
		"per_round_slot_cost": 2,
		"escape_cost": null,
		"allow_discard": true,
		"after_finish": "stay",
		"rounds": [
			{
				"id": "r1",
				"responses": [{ "accepts": ["k_clue"], "next_round": null }],
				"fallback": { "requires_discardable": false, "next_round": null }
			}
		],
		"on_failure": { "flag": { "overload_failed": true } }
	}
	_create_mock_encounter_beat(data_node, "mock_enc_ov", mock_enc)
	gs.start_encounter("mock_enc_ov")

	gs.knowledge["k_clue"] = true
	var res_ack_ov: Dictionary = gs.acknowledge_encounter_intro()
	if not bool(gs.flags.get("overload_failed", false)):
		failed += _err("overloaded acknowledge should trigger capacity failure on entry")
	else:
		failed += _ok("overloaded encounter start correctly applies penalty and triggers capacity failure")

	return failed


# ── 6. 佔格計算與扣除 ───────────────────────────────────────────────────────

func _test_slot_blocking_and_release(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)

	data_node.loader.cards["k_cure"] = { "id": "k_cure", "type": "knowledge", "slotless": true, "discardable": false }
	data_node.loader.cards["k_herb"] = { "id": "k_herb", "type": "knowledge", "slotless": true, "discardable": false }
	data_node.loader.cards["k_water"] = { "id": "k_water", "type": "knowledge", "slotless": true, "discardable": false }
	data_node.loader.cards["p_lan"] = { "id": "p_lan", "type": "person", "slotless": false, "discardable": false }

	var mock_enc: Dictionary = {
		"repeat_each_run": true,
		"per_round_slot_cost": 1,
		"escape_cost": null,
		"allow_discard": true,
		"after_finish": "stay",
		"rounds": [
			{
				"id": "r1",
				"responses": [{ "accepts": ["k_cure"], "next_round": "r2" }],
				"fallback": { "requires_discardable": false, "next_round": "r2" }
			},
			{
				"id": "r2",
				"responses": [{ "accepts": ["k_herb"], "next_round": "r3" }],
				"fallback": { "requires_discardable": false, "next_round": "r3" }
			},
			{
				"id": "r3",
				"responses": [{ "accepts": ["k_water"], "next_round": null }],
				"fallback": { "requires_discardable": false, "next_round": null }
			}
		],
		"on_victory": { "flag": { "v_cleared": true } }
	}
	_create_mock_encounter_beat(data_node, "mock_enc_slots", mock_enc)
	gs.knowledge["k_cure"] = true
	gs.knowledge["k_water"] = true
	gs.hand.append("p_lan")

	gs.start_encounter("mock_enc_slots")
	gs.acknowledge_encounter_intro() # r1: blocked_slots = 1

	if int(gs.active_encounter.get("blocked_slots", 0)) != 1:
		failed += _err("r1 entry blocked_slots should be 1")

	# r1 正解 (k_cure) -> releases 1, enters r2 (+1) -> blocked_slots should be 1
	var r1_res: Dictionary = gs.respond_to_encounter("k_cure")
	if not bool(r1_res.get("ok", false)):
		failed += _err("r1 respond failed: %s" % str(r1_res))
	elif str(gs.active_encounter.get("round_id", "")) != "r2":
		failed += _err("should advance to r2")
	elif int(gs.active_encounter.get("blocked_slots", 0)) != 1:
		failed += _err("after r1 correct answer, blocked_slots should be 1, got %d" % int(gs.active_encounter.get("blocked_slots", 0)))
	else:
		failed += _ok("correct answer released round cost and added next round cost (blocked_slots=1)")

	# r2 錯答 (p_lan) -> retains 1, enters r3 (+1) -> blocked_slots should be 2
	var r2_res: Dictionary = gs.respond_to_encounter("p_lan")
	if not bool(r2_res.get("ok", false)):
		failed += _err("r2 respond failed: %s" % str(r2_res))
	elif str(gs.active_encounter.get("round_id", "")) != "r3":
		failed += _err("should advance to r3")
	elif int(gs.active_encounter.get("blocked_slots", 0)) != 2:
		failed += _err("after r2 fallback, blocked_slots should be 2, got %d" % int(gs.active_encounter.get("blocked_slots", 0)))
	else:
		failed += _ok("fallback retained round cost and added next round cost (blocked_slots=2)")

	return failed


# ── 7. 主動丟棄與逃離遭遇 ───────────────────────────────────────────────────

func _test_discard_and_escape(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)

	data_node.loader.cards["k_cure"] = { "id": "k_cure", "type": "knowledge", "slotless": true, "discardable": false }
	data_node.loader.cards["item_leaf"] = { "id": "item_leaf", "type": "item", "discardable": true }
	data_node.loader.cards["item_stone"] = { "id": "item_stone", "type": "item", "discardable": true }

	gs.hand.append("item_leaf")
	gs.hand.append("item_stone")

	var mock_enc: Dictionary = {
		"repeat_each_run": true,
		"per_round_slot_cost": 1,
		"escape_cost": 1,
		"allow_discard": true,
		"after_finish": "stay",
		"rounds": [
			{
				"id": "r1",
				"responses": [{ "accepts": ["k_cure"], "next_round": null }],
				"fallback": { "requires_discardable": false, "next_round": null }
			}
		],
		"on_escape": { "flag": { "escaped_ok": true } }
	}
	_create_mock_encounter_beat(data_node, "mock_enc_disc_esc", mock_enc)
	gs.knowledge["k_cure"] = true

	gs.start_encounter("mock_enc_disc_esc")
	gs.acknowledge_encounter_intro()

	# 主動丟棄 item_leaf
	var res_disc: Dictionary = gs.discard_in_encounter("item_leaf")
	if not bool(res_disc.get("ok", false)):
		failed += _err("discard_in_encounter failed: %s" % str(res_disc))
	elif gs.has_card("item_leaf"):
		failed += _err("item_leaf should be lost after discard")
	elif int(gs.active_encounter.get("blocked_slots", 0)) != 1:
		failed += _err("blocked_slots should remain 1 after discard")
	elif str(gs.active_encounter.get("round_id", "")) != "r1":
		failed += _err("round_id should not advance on discard")
	else:
		failed += _ok("discard_in_encounter cleanly removed card without changing blocked_slots or round")

	# 逃離遭遇（支付 item_stone）
	var esc_payment: Array[String] = ["item_stone"]
	var res_esc: Dictionary = gs.escape_encounter(esc_payment)
	if not bool(res_esc.get("ok", false)):
		failed += _err("escape_encounter failed: %s" % str(res_esc))
	elif gs.has_card("item_stone"):
		failed += _err("item_stone should be lost after escape payment")
	elif not bool(gs.flags.get("escaped_ok", false)):
		failed += _err("on_escape effect should be applied")
	elif not gs.active_encounter.is_empty():
		failed += _err("active_encounter should be cleared after escape")
	else:
		failed += _ok("escape_encounter successfully paid cost, applied effect, and closed encounter")

	return failed


# ── 8. 無合法解自動結算 failure ─────────────────────────────────────────────

func _test_no_legal_moves_auto_failure(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)

	data_node.loader.cards["k_clue"] = { "id": "k_clue", "type": "knowledge", "slotless": true, "discardable": false }

	# 玩家只有 protagonist（不可丟棄），無 knowledge，不可逃離（escape_cost: null），不可丟棄（allow_discard: false）
	# fallback 要求 requires_discardable: true
	# 此時玩家進入第一回合將無任何合法解，應立即自動結算 failure！
	var mock_enc: Dictionary = {
		"repeat_each_run": true,
		"per_round_slot_cost": 1,
		"escape_cost": null,
		"allow_discard": false,
		"after_finish": "stay",
		"rounds": [
			{
				"id": "r1",
				"responses": [{ "accepts": ["k_clue"], "next_round": null }],
				"fallback": { "requires_discardable": true, "next_round": null }
			}
		],
		"on_failure": { "flag": { "no_legal_failed": true } }
	}
	_create_mock_encounter_beat(data_node, "mock_enc_no_legal", mock_enc)

	gs.start_encounter("mock_enc_no_legal")
	var res_ack: Dictionary = gs.acknowledge_encounter_intro()

	if not bool(gs.flags.get("no_legal_failed", false)):
		failed += _err("acknowledge_encounter_intro should auto-fail when player has no legal moves")
	elif not gs.active_encounter.is_empty():
		failed += _err("active_encounter should be cleared after failure")
	else:
		failed += _ok("no legal moves triggers immediate auto-failure settlement")

	return failed


# ── 9. 容量上限失敗結算 ─────────────────────────────────────────────────────

func _test_capacity_exhaustion_failure(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)

	data_node.loader.cards["k_clue"] = { "id": "k_clue", "type": "knowledge", "slotless": true, "discardable": false }
	var max_hand: int = int(data_node.tuning("hand_size", 14))

	# 填手牌至 max_hand - 1 張
	while gs.hand.size() < max_hand - 1:
		var dummy_id := "test_c_%d" % gs.hand.size()
		data_node.loader.cards[dummy_id] = { "id": dummy_id, "type": "item", "discardable": false }
		gs.hand.append(dummy_id)

	# Encounter per_round_slot_cost is 2.
	# Round 1 entry: blocked_slots becomes 2.
	# Remaining slots = max_hand - (max_hand - 1) - 2 = -1 <= 0 -> capacity failure!
	var mock_enc: Dictionary = {
		"repeat_each_run": true,
		"per_round_slot_cost": 2,
		"escape_cost": null,
		"allow_discard": true,
		"after_finish": "stay",
		"rounds": [
			{
				"id": "r1",
				"responses": [{ "accepts": ["k_clue"], "next_round": null }],
				"fallback": { "requires_discardable": false, "next_round": null }
			}
		],
		"on_failure": { "flag": { "cap_failed": true } }
	}
	_create_mock_encounter_beat(data_node, "mock_enc_cap", mock_enc)
	gs.knowledge["k_clue"] = true

	gs.start_encounter("mock_enc_cap")
	var res_ack: Dictionary = gs.acknowledge_encounter_intro()

	if not bool(gs.flags.get("cap_failed", false)):
		failed += _err("capacity exhaustion should trigger auto failure")
	elif not gs.active_encounter.is_empty():
		failed += _err("active_encounter should be cleared after capacity failure")
	else:
		failed += _ok("capacity exhaustion correctly triggers auto-failure")

	return failed


# ── 10. 遭遇勝利與結束推進 ──────────────────────────────────────────────────

func _test_victory_and_after_finish(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)

	data_node.loader.cards["k_sol"] = { "id": "k_sol", "type": "knowledge", "slotless": true, "discardable": false }

	# 遭遇 A: after_finish: "advance_phase"
	var mock_enc_adv: Dictionary = {
		"repeat_each_run": true,
		"per_round_slot_cost": 1,
		"escape_cost": null,
		"allow_discard": true,
		"after_finish": "advance_phase",
		"rounds": [
			{
				"id": "r1",
				"responses": [{ "accepts": ["k_sol"], "next_round": null }],
				"fallback": { "requires_discardable": false, "next_round": null }
			}
		],
		"on_victory": { "flag": { "adv_victory": true } }
	}
	_create_mock_encounter_beat(data_node, "mock_enc_adv", mock_enc_adv)
	gs.knowledge["k_sol"] = true
	gs.phase = "morning"

	gs.start_encounter("mock_enc_adv")
	gs.acknowledge_encounter_intro()

	var res_win: Dictionary = gs.respond_to_encounter("k_sol")
	if not bool(res_win.get("ok", false)):
		failed += _err("respond_to_encounter victory failed: %s" % str(res_win))
	elif not bool(gs.flags.get("adv_victory", false)):
		failed += _err("on_victory effect not applied")
	elif not gs.active_encounter.is_empty():
		failed += _err("active_encounter should be empty after victory")
	elif gs.phase != "afternoon":
		failed += _err("phase should advance to 'afternoon' with after_finish: advance_phase, got '%s'" % gs.phase)
	else:
		failed += _ok("victory with after_finish: advance_phase advanced phase to afternoon")

	return failed


# ── 11. 序列化與還原往返 ────────────────────────────────────────────────────

func _test_serialization_roundtrip(gs: Node, data_node: Node) -> int:
	var failed: int = 0
	_reset_gs(gs)

	data_node.loader.cards["k_a"] = { "id": "k_a", "type": "knowledge", "slotless": true, "discardable": false }
	data_node.loader.cards["k_b"] = { "id": "k_b", "type": "knowledge", "slotless": true, "discardable": false }

	var mock_enc: Dictionary = {
		"repeat_each_run": true,
		"per_round_slot_cost": 1,
		"escape_cost": 1,
		"allow_discard": true,
		"after_finish": "stay",
		"rounds": [
			{
				"id": "r1",
				"responses": [{ "accepts": ["k_a"], "next_round": "r2" }],
				"fallback": { "requires_discardable": false, "next_round": "r2" }
			},
			{
				"id": "r2",
				"responses": [{ "accepts": ["k_b"], "next_round": null }],
				"fallback": { "requires_discardable": false, "next_round": null }
			}
		]
	}
	_create_mock_encounter_beat(data_node, "mock_enc_ser", mock_enc)
	gs.knowledge["k_a"] = true
	gs.knowledge["k_b"] = true

	# 1. 測試 intro stage 序列化
	gs.start_encounter("mock_enc_ser")
	var ser1: Dictionary = gs.serialize()
	gs.deserialize(ser1)

	if str(gs.active_encounter.get("beat_id", "")) != "mock_enc_ser":
		failed += _err("deserialized beat_id mismatch")
	elif str(gs.active_encounter.get("stage", "")) != "intro":
		failed += _err("deserialized stage mismatch")
	else:
		failed += _ok("intro stage serialization roundtrip verified")

	# 2. 測試 round stage 序列化
	gs.acknowledge_encounter_intro()
	(gs.active_encounter["attempted_card_ids"] as Array).append("dummy_card")

	var ser2: Dictionary = gs.serialize()
	_reset_gs(gs)
	gs.deserialize(ser2)

	if str(gs.active_encounter.get("beat_id", "")) != "mock_enc_ser":
		failed += _err("deserialized round beat_id mismatch")
	elif str(gs.active_encounter.get("stage", "")) != "round":
		failed += _err("deserialized round stage mismatch")
	elif str(gs.active_encounter.get("round_id", "")) != "r1":
		failed += _err("deserialized round_id mismatch")
	elif int(gs.active_encounter.get("blocked_slots", 0)) != 1:
		failed += _err("deserialized blocked_slots mismatch")
	elif not (gs.active_encounter.get("attempted_card_ids", []) as Array).has("dummy_card"):
		failed += _err("deserialized attempted_card_ids mismatch")
	else:
		failed += _ok("round stage serialization roundtrip verified")

	return failed


# ── 12. 故事線遭遇契約驗證 ──────────────────────────────────────────────────

func _test_storyline_encounters_contract(gs: Node, data_node: Node) -> int:
	var failed: int = 0

	# 1. D8: n_manydoors_ch1
	var fugu: Dictionary = data_node.loader.beats_by_id.get("n_manydoors_ch1", {}) as Dictionary
	if fugu.is_empty():
		failed += _err("n_manydoors_ch1 not found in beats")
	elif not fugu.has("encounter"):
		failed += _err("n_manydoors_ch1 missing encounter definition")
	else:
		var enc: Dictionary = fugu.get("encounter", {}) as Dictionary
		if not bool(enc.get("charge_first_visit", false)):
			failed += _err("n_manydoors_ch1 encounter charge_first_visit should be true")
		elif int(enc.get("per_round_slot_cost", 0)) != 1:
			failed += _err("n_manydoors_ch1 encounter per_round_slot_cost should be 1")
		elif int(enc.get("escape_cost", 0)) != 1:
			failed += _err("n_manydoors_ch1 encounter escape_cost should be 1")
		elif not bool(enc.get("allow_discard", false)):
			failed += _err("n_manydoors_ch1 encounter allow_discard should be true")
		elif str(enc.get("after_finish", "")) != "stay":
			failed += _err("n_manydoors_ch1 encounter after_finish should be 'stay'")
		elif (enc.get("rounds", []) as Array).size() != 3:
			failed += _err("n_manydoors_ch1 encounter rounds count should be 3, got %d" % (enc.get("rounds", []) as Array).size())
		else:
			failed += _ok("n_manydoors_ch1 encounter schema contract fully verified")

	# 2. D45: d45_encounter
	var coda: Dictionary = data_node.loader.beats_by_id.get("d45_encounter", {}) as Dictionary
	if coda.is_empty():
		failed += _err("d45_encounter not found in beats")
	elif not coda.has("encounter"):
		failed += _err("d45_encounter missing encounter definition")
	else:
		var enc: Dictionary = coda.get("encounter", {}) as Dictionary
		if int(enc.get("per_round_slot_cost", 0)) != 1:
			failed += _err("d45_encounter encounter per_round_slot_cost should be 1")
		elif enc.get("escape_cost") != null:
			failed += _err("d45_encounter encounter escape_cost should be null")
		elif bool(enc.get("allow_discard", true)):
			failed += _err("d45_encounter encounter allow_discard should be false")
		elif str(enc.get("after_finish", "")) != "advance_phase":
			failed += _err("d45_encounter encounter after_finish should be 'advance_phase'")
		elif (enc.get("rounds", []) as Array).size() != 1:
			failed += _err("d45_encounter encounter rounds count should be 1, got %d" % (enc.get("rounds", []) as Array).size())
		else:
			failed += _ok("d45_encounter encounter schema contract fully verified")

	return failed
