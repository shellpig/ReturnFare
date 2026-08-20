class_name QAContractMatrix
extends RefCounted

## 63 條 UI 契約的機器可讀目錄。變體由 runner 展開，但完成判定回到這份矩陣。

const CONTRACT_IDS := [
	"p1g_case_01", "p1g_case_02", "p1g_case_03", "p1g_case_04",
	"p1g_case_05", "p1g_case_06", "p1g_case_07", "p1g_case_08",
	"p1g_case_09", "p1g_case_10", "p1g_case_11", "p1g_case_12",
	"p1g_case_13", "p1g_case_14",
	"p1af_01_boot", "p1af_02_phase_cycle", "p1af_03_chapter_boundary",
	"p1af_04_d45_coda", "p1af_05_hand_capacity", "p1af_06_hand_knowledge_split",
	"p1af_07_arrival", "p1af_08_map_filter", "p1af_09_occupant_empty",
	"p1af_10_requires_locked", "p1af_11_unlock_same_panel", "p1af_12_condition_hidden",
	"p1af_13_competing_beats", "p1af_14_place_effect", "p1af_15_action_spent",
	"p1af_16_panel_rebuild", "p1af_17_compare_free", "p1af_18_incompatible_absent",
	"p1af_19_attention", "p1af_20_choice_collapse", "p1af_21_choice_resolved",
	"p1af_22_choice_equivalence", "p1af_23_choice_leave", "p1af_24_choice_no_card",
	"p1af_25_choice_card", "p1af_26_echo_d5", "p1af_27_ch1_echoes",
	"p1af_28_d27_order", "p1af_29_night_resolution", "p1af_30_sleep_d24",
	"p1af_31_night_place", "p1af_32_d45_coda_full", "p1af_33_full_walk",
	"p1h_01_hand_cards", "p1h_02_card_detail", "p1h_03_detail_readonly",
	"p1h_04_knowledge_detail", "p1h_05_name_truncation", "p1h_06_handbar_geometry",
	"p2a_01_madness_hand_display",
	"p2b_01_exit_visibility", "p2b_02_exit_place", "p2b_03_soak",
	"p2b_04_exit_thresholds",
	"p2c_01_forced_text", "p2c_02_forced_action_spent", "p2c_03_forced_two_same_day",
	"p2d_01_vision_visibility", "p2d_02_be_screen",
]

const SPECIAL_EVIDENCE := {
	"p1af_03_chapter_boundary": ["chapter_changed_once"],
	"p1af_06_hand_knowledge_split": ["knowledge_count_exact", "knowledge_not_in_hand"],
	"p1af_09_occupant_empty": ["occupant_no_place", "empty_slot_interactive"],
	"p1af_10_requires_locked": ["locked_visual", "locked_click_blocked", "locked_reason"],
	"p1af_11_unlock_same_panel": ["locked_before", "unlocked_same_panel"],
	"p1af_13_competing_beats": ["sanquan_beat", "oldstreet_beat", "temple_beat"],
	"p1af_14_place_effect": ["effect_text_visible", "effect_state"],
	"p1af_15_action_spent": ["action_spent_ui_blocked", "second_location_input_noop"],
	"p1af_16_panel_rebuild": ["old_place_removed", "new_slot_open"],
	"p1af_17_compare_free": ["compare_no_action_spent", "action_still_available_after_compare", "compare_effect_applied"],
	"p1af_19_attention": ["attention_success", "attention_repeat_unchanged"],
	"p1af_21_choice_resolved": ["resolved_render", "resolved_click_noop"],
	"p1af_22_choice_equivalence": ["choice_equivalence_complete"],
	"p1af_28_d27_order": ["evening_ui_order", "evening_outcome"],
	"p1af_29_night_resolution": ["night_fixed_priority", "night_free_interaction", "night_chapter_and_additional_order", "night_paid_locked", "night_one_location_limit", "night_no_madness"],
	"p1af_30_sleep_d24": ["sleep_input", "sleep_resolution"],
	"p1af_32_d45_coda_full": ["run_fields_cleared", "reset_ui_state", "reset_flag_slots_locked"],
	"p1af_33_full_walk": ["full_walk_d45", "first_round_reset", "second_round_arrival", "second_round_protagonist_exactly_one"],
	"p1h_01_hand_cards": ["hand_cards_visible", "no_card_id_visible"],
	"p1h_02_card_detail": ["husband_detail_ok", "wife_detail_ok", "state_unchanged"],
	"p1h_03_detail_readonly": ["no_placement_controls", "dialog_close_ok"],
	"p1h_04_knowledge_detail": ["all_knowledge_present", "scroll_last_visible", "state_unchanged"],
	"p1h_05_name_truncation": ["ellipsis_displayed", "full_name_in_detail"],
	"p1h_06_handbar_geometry": ["grid_columns_7", "no_empty_slots", "rects_preserved"],
	"p2a_01_madness_hand_display": ["madness_multi_distinct_buttons", "madness_countdown_labels", "madness_detail_dialog_ok"],
	"p2b_01_exit_visibility": ["exit_slots_absent", "exit_slots_visible", "exit_slot_type_label"],
	"p2b_02_exit_place": ["indulge_place_effect", "indulge_action_spent", "exit_rejects_non_madness"],
	"p2b_03_soak": ["soak_eats_day", "soak_afternoon_locked", "soak_not_enough_actions"],
	"p2b_04_exit_thresholds": ["violence_day_gate_before", "violence_day_gate_after", "lust_relation_gate", "splurge_locked_reason"],
	"p2c_01_forced_text": ["forced_text_visible", "forced_text_persists_in_phase"],
	"p2c_02_forced_action_spent": ["forced_action_spent", "forced_no_protagonist_place"],
	"p2c_03_forced_two_same_day": ["forced_two_same_day", "forced_day_fully_eaten"],
	"p2d_01_vision_visibility": ["vision_hidden_at_2", "vision_visible_at_3"],
	"p2d_02_be_screen": ["be_text_visible", "be_no_coda_stub", "be_map_hidden"],
}

## 契約的 token 由多個變體分頭提供時，逐變體列出各自該證明的那幾個。
## 沒列的變體＝要自己提供整份契約 token。runner 兩層都查：
## 變體層防「某個變體少送 token 卻被同契約另一個變體補掉」，契約層防變體漏跑。
const VARIANT_EVIDENCE := {
	"p1af_29_night_d1_fixed": ["night_fixed_priority"],
	"p1af_29_night_resolution": [
		"night_free_interaction", "night_chapter_and_additional_order",
		"night_one_location_limit", "night_no_madness",
	],
	"p1af_29_night_paid": [
		"night_paid_locked", "night_one_location_limit",
	],
	"p2b_01_exit_zero": ["exit_slots_absent"],
	"p2b_01_exit_one": ["exit_slots_visible", "exit_slot_type_label"],
	"p2b_03_soak_morning": ["soak_eats_day"],
	"p2b_03_soak_afternoon": ["soak_afternoon_locked"],
	"p2b_03_soak_spent": ["soak_not_enough_actions"],
	"p2b_04_violence_before": ["violence_day_gate_before"],
	"p2b_04_violence_after": ["violence_day_gate_after", "splurge_locked_reason"],
	"p2b_04_lust_relation": ["lust_relation_gate"],
	"p2d_01_vision_zero": ["vision_hidden_at_2"],
	"p2d_01_vision_three": ["vision_visible_at_3"],
}


static func required_evidence(contract_id: String) -> Array:
	return (SPECIAL_EVIDENCE.get(contract_id, ["case_ok"]) as Array).duplicate()


static func required_variant_evidence(case_id: String, contract_id: String) -> Array:
	if VARIANT_EVIDENCE.has(case_id):
		return (VARIANT_EVIDENCE[case_id] as Array).duplicate()
	return required_evidence(contract_id)
