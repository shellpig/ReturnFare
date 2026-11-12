import type { GameData } from '../data/types';

/** 開場畫面插圖。 */
export const OPENING_ART = '/art/story/opening.webp';

/** 敘事段落插圖：beat id → 圖檔。未列入的段落不顯示圖。 */
export const STORY_ART: Readonly<Record<string, string>> = {
  d1_morning_departure: '/art/story/d1_morning_departure.webp',
  d1_pm_mountain_road: '/art/story/d1_pm_mountain_road.webp',
  d1_arrival: '/art/story/d1_arrival.webp',
  d1_ambient_couple: '/art/story/d1_ambient_couple.webp',
  d2_morning_intro: '/art/story/d2_morning_intro.webp',
  d2_evening_bath: '/art/story/d2_evening_bath.webp',
  d2_ambient_debt: '/art/story/d2_ambient_debt.webp',
  d3_morning_ahong: '/art/story/d3_morning_ahong.webp',
  d4_morning_missing: '/art/story/d4_morning_missing.webp',
  d5_morning_stillmissing: '/art/story/d5_morning_stillmissing.webp',
  d6_evening_inherit: '/art/story/d6_evening_inherit.webp',
  d7_pm_numbers: '/art/story/d7_pm_numbers.webp',
  d8_echo_bathhouse: '/art/story/d8_echo_bathhouse.webp',
  d8_ambient_monkey: '/art/story/d8_ambient_monkey.webp',
  d10_morning_landslide: '/art/story/d10_morning_landslide.webp',
  d12_morning_medicine: '/art/story/d12_morning_medicine.webp',
  d15_morning_collapse: '/art/story/d15_morning_collapse.webp',
  d16_morning_awake: '/art/story/d16_morning_awake.webp',
  d17_morning_phone: '/art/story/d17_morning_phone.webp',
  d19_evening_arrive: '/art/story/d19_evening_arrive.webp',
  d19_evening_acai_leave: '/art/story/d19_evening_acai_leave.webp',
  d20_morning_wu: '/art/story/d20_morning_wu.webp',
  d22_evening_ajie_leaves: '/art/story/d22_evening_ajie_leaves.webp',
  d23_morning_awei_knocks: '/art/story/d23_morning_awei_knocks.webp',
  d24_evening_student_missing: '/art/story/d24_evening_student_missing.webp',
  d25_morning_found: '/art/story/d25_morning_found.webp',
  d27_morning_school_call: '/art/story/d27_morning_school_call.webp',
  d27_morning_ajie_back: '/art/story/d27_morning_ajie_back.webp',
  d30_morning_rules: '/art/story/d30_morning_rules.webp',
  d31_anchor: '/art/story/d31_anchor.webp',
  n_corridor_ch1: '/art/scenes/n_corridor.webp',
};

/** 進場後第二段文字（beat.on_enter.text）的插圖：beat id → 圖檔。 */
export const STORY_ART_ON_ENTER: Readonly<Record<string, string>> = {
  d1_arrival: '/art/story/d1_arrival_dinner.webp',
  d15_pm_clinic: '/art/story/d15_pm_clinic_awei.webp',
};

/** 段落文字即 beat.text（state.ts playBeatOnDraft），以此反查插圖。 */
export function storyArtFor(data: GameData, passage: string | undefined): string | null {
  if (!passage) return null;
  for (const [beatId, src] of Object.entries(STORY_ART)) {
    if (data.beatsById.get(beatId)?.text === passage) return src;
  }
  for (const [beatId, src] of Object.entries(STORY_ART_ON_ENTER)) {
    const onEnter = data.beatsById.get(beatId)?.on_enter as { text?: unknown } | undefined;
    if (onEnter?.text === passage) return src;
  }
  return null;
}
