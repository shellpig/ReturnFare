class_name QAContractMatrix
extends RefCounted

## 47 條 UI 契約的機器可讀目錄。變體由 runner 展開，但完成判定回到這份矩陣。

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
]

const SPECIAL_EVIDENCE := {
	"p1af_03_chapter_boundary": ["chapter_changed_once"],
	"p1af_06_hand_knowledge_split": ["knowledge_label_complete", "knowledge_not_in_hand"],
	"p1af_09_occupant_empty": ["occupant_no_place", "empty_slot_interactive"],
	"p1af_10_requires_locked": ["locked_visual", "locked_click_blocked", "locked_reason"],
	"p1af_11_unlock_same_panel": ["locked_before", "unlocked_same_panel"],
	"p1af_13_competing_beats": ["sanquan_beat", "oldstreet_beat", "temple_beat"],
	"p1af_14_place_effect": ["effect_text_visible", "effect_state"],
	"p1af_16_panel_rebuild": ["old_place_removed", "new_slot_open"],
	"p1af_17_compare_free": ["knowledge_absent_before", "knowledge_gained", "compare_no_extra_action"],
	"p1af_19_attention": ["attention_success", "attention_free_unchanged"],
	"p1af_21_choice_resolved": ["resolved_render", "resolved_click_noop"],
	"p1af_28_d27_order": ["evening_ui_order", "evening_outcome"],
	"p1af_29_night_resolution": ["night_fixed_priority", "night_free_interaction", "night_paid_locked", "night_no_madness"],
	"p1af_30_sleep_d24": ["sleep_input", "sleep_resolution"],
	"p1af_32_d45_coda_full": ["run_fields_cleared", "reset_ui_state"],
	"p1af_33_full_walk": ["full_walk_d45", "first_round_reset", "second_round_arrival", "second_round_protagonist_exactly_one"],
}

static func required_evidence(contract_id: String) -> Array:
	return (SPECIAL_EVIDENCE.get(contract_id, ["case_ok"]) as Array).duplicate()
