// UI 介面詞彙（W-02）：沿用 Godot 原文，逐條註明來源；Godot 無對應原文者另註。
export const strings = {
  // scenes/ui/opening_panel.tscn ConfirmDialog 用引擎預設按鈕、無專案原文；確認／取消為 W3-A 新增。
  confirm: '確認',
  cancel: '取消',
  continue: '繼續演出', // scenes/ui/location_panel.tscn AdvanceBeatButton
  advance: '推進時段', // scenes/main.gd _MSG_ADVANCE；scenes/main.tscn AdvanceButton
  advanceUnseen: '推進時段（還有演出沒看）', // scenes/main.gd _MSG_ADVANCE_UNSEEN
  advanceHint: '推進時段（目前無可做動作）', // scenes/main.gd _MSG_ADVANCE_HINT
  // Godot 為每張候選卡各一顆放置鈕（_FMT_PLACE_BUTTON）；Web 改「點槽 → 選卡」，此按鈕文字為 W5-B 新增。
  placeCard: '放入卡片',
  choose: '選擇', // scenes/ui/location_panel.gd _FMT_CHOOSE_BUTTON「選擇：%s」的前綴；Web 按鈕位於槽內，槽名已另行顯示
  preview: '預覽', // scenes/ui/location_panel.gd:369 preview_btn；:468 預覽標題預設值
  placeableCardsTitle: '可放置卡片：', // scenes/ui/location_panel.gd:459
  noPlaceableCards: '目前沒有可放的卡。', // scenes/ui/location_panel.gd _MSG_PREVIEW_EMPTY
  previewReason: (reason: string) => `理由：${reason}`, // scenes/ui/location_panel.gd:467
  placeFailed: (reason: string) => `（無法放置：${reason}）`, // scenes/ui/location_panel.gd _FMT_PLACE_FAILED
  // scenes/ui/location_panel.gd _REASON_CODE_TEXTS：拒絕碼不得以英文原樣顯示給玩家（K-115 同族）。
  reasonCodes: {
    not_held: '未持有此卡',
    hidden: '此事件未出現',
    resolved: '此格已放置完成',
    not_accepted: '卡片類型不符',
    action_spent: '本時段行動已用完',
    unknown_beat: '未知的事件',
    unknown_slot: '未知的卡槽',
    locked: '條件不足',
    not_action_phase: '非白天行動時段',
    not_delegation: '此格不是委託格',
    not_person: '此卡不是人物卡',
    already_delegated_today: '今日已受託',
    already_resolved: '此格已結算完成',
    data_conflict: '委託資料異常',
    encounter_active: '遭遇進行中',
    card_required: '需要放入卡片', // W5-C 新增
    not_run: '遊戲尚未開始', // W5-C 新增
    not_implemented: '功能尚未實作', // W5-C 新增
    // W6-E1 新增：文字取自 scripts/autoload/game_state.gd 結局相關 reason_text，讓英文碼不外露。
    not_ending: '目前不在結局中',
    no_active_ending: '沒有進行中的結局',
    wrong_ending_stage: '結局已可結算',
    already_revealed: '本頁已完整顯示',
    page_not_revealed: '本頁尚未完整顯示',
    last_page: '已是最後一頁',
    ending_not_seen: '這個結局還沒看過，不能跳過',
    not_ready: '結局尚未播完',
    ending_active: '已有進行中的結局',
    // W6-A 新增：夜間進入拒絕碼，文字取自 scenes/ui/location_panel.gd _NIGHT_REJECT_TEXTS（locked／teaser 以資料理由優先）。
    not_night: '非夜間時段',
    unknown_location: '未知的地點',
    not_night_layer: '非夜間地點',
    teaser: '還沒有走到那裡。',
    too_early: '時機未到',
    already_chosen: '今夜已探索過其他地點',
    already_slept: '今夜已準備就寢',
    overloaded: '手牌超載，無法進入夜間地點', // scripts/autoload/game_state.gd enter_night_location reason_text
    // W6-A 新增：對位拒絕碼；Godot 的對位入口只回碼、UI 不顯示，中文為 W6-A 新增。
    not_day_phase: '現在不是白天時段',
    not_day_layer: '這裡不是白天地點',
    no_seen_row: '還沒有在夜裡走到這裡',
    already_known: '已經對位過了',
  } as Record<string, string>,
  // scenes/ui/ending_panel.gd
  endingReveal: '顯示全文', // _MSG_ADVANCE_REVEAL
  endingNext: '下一頁', // _MSG_ADVANCE_NEXT
  endingComplete: '完成', // _MSG_ADVANCE_COMPLETE
  endingSkip: '跳過', // _MSG_SKIP
  endingPage: (index: number, count: number) => `第 ${index} / ${count} 頁`, // _FMT_PAGE
  endingRegion: '結局', // W6-E1 新增：區域無障礙標籤，Godot 無對應原文
  // scenes/main.gd 夜間主按鈕：_MSG_ADVANCE_SLEEP／_MSG_ADVANCE_END_NIGHT／_MSG_ADVANCE_NEXT_DAY
  advanceSleep: '直接睡',
  advanceEndNight: '結束今晚',
  advanceNextDay: '進入隔天',
  // scripts/core/panel_builder.gd location_summary 狀態文字與風險警告
  nightStatusUnseen: '[尚未到訪]',
  nightStatusAligned: '[已對位]',
  nightStatusSeenUnaligned: '[已到訪，尚未對位]',
  nightStatusSeen: '[已到訪]',
  nightWarning: '再往前，你可能回不來。',
  nightMultiName: (dayName: string, nightName: string) => `${dayName}・${nightName}`, // panel_builder.gd "%s・%s"
  nightListEntry: (name: string, status: string) => `${name} ${status}`, // scenes/ui/map_list.gd
  nightEnter: '進入', // scenes/ui/location_panel.gd show_night_details
  nightAlign: '把兩邊對起來', // scenes/ui/location_panel.gd _rebuild
  nightAlignDialogTitle: '確認對位', // scenes/ui/location_panel.tscn NightAlignConfirmDialog.title
  nightAlignDialogText: '要將白天地點與夜間見聞對位嗎？', // 同上 dialog_text
  nightEnterMadness: (cost: number) => `推開了夜色深處的門。獲得 ${cost} 張發狂卡。`, // game_state.gd enter_night_location
  // 實作規格書.md 第九節「到訪、收費與一夜一地點」通用空結果；Godot UI 未渲染（只回 empty_result 旗標），文字取自規格書。
  nightEmptyResult: '走了很久。什麼都沒有遇到。',
  loading: '載入中...', // scenes/main.tscn StatusLabel 初始文字
  dataError: '資料載入失敗', // scenes/main.gd _MSG_DATA_ERROR，去掉僅適用 Godot 編輯器的「詳情見 Output。」
  status: (day: number, phase: string, chapter: number) => `第 ${day} 天  ${phase}  第 ${chapter} 章`, // scenes/main.gd _FMT_STATUS
  // Godot 狀態列直接顯示 phase id（morning 等）；中文時段名為 W3-A 新增，Godot 無原文。
  phases: { morning: '上午', afternoon: '下午', evening: '傍晚', night: '夜晚' },
  backToMap: '返回地圖', // scenes/ui/location_panel.tscn:25 BackButton
  noTitle: '（無標題）', // scenes/ui/location_panel.gd:41,111
  reasonFallback: '（條件不足）', // scripts/core/panel_builder.gd:54,97；scripts/autoload/game_state.gd:940
  soakMorningOnly: '（只能在上午發動）', // scripts/core/panel_builder.gd:104；scripts/autoload/game_state.gd:1299
  soakInsufficientActions: '（格數不足）', // scripts/core/panel_builder.gd:104；scripts/autoload/game_state.gd:1300
  slotTypesDelimiter: '、', // scenes/ui/slot_widget.gd:31
  slotTypes: (types: string) => `（收：${types}）`, // scenes/ui/slot_widget.gd:31
  close: '關閉', // scenes/ui/card_detail.gd AcceptDialog 關閉
  handSlots: (used: number, limit: number) => `手牌 ${used} / ${limit}`, // scenes/ui/hand_bar.gd:9 _FMT_SLOTS
  knowledgeCount: (count: number) => `知識 (${count})`, // scenes/ui/hand_bar.gd:10 _FMT_KNOWLEDGE
  cardCountdown: (name: string, days: number) => `${name} (${days}天)`, // scenes/ui/hand_bar.gd:63
  cardDetailTitle: '卡片詳情', // scenes/ui/card_detail.gd:19
  knowledgeListTitle: '知識清單', // scenes/ui/card_detail.gd:55
  emptyKnowledge: '（目前無知識）', // scenes/ui/card_detail.gd:60
  // W6-C 委託與教學介面文字（對齊 scenes/main.tscn、scenes/ui/location_panel.gd、scenes/ui/hand_bar.gd）
  delegate: '委託', // scenes/ui/location_panel.gd _FMT_DELEGATE_BUTTON
  delegatedToday: '今日已受託', // scenes/ui/location_panel.gd _MSG_DELEGATED_TODAY
  delegatedTodaySuffix: '（今日已受託）', // scenes/ui/hand_bar.gd:11 _SUFFIX_DELEGATED_TODAY
  delegationDialogTitle: '確認委託', // scenes/ui/location_panel.gd _MSG_DELEGATION_DIALOG_TITLE
  timingImmediate: '立即回報', // scenes/ui/location_panel.gd _TIMING_LABELS.immediate
  timingNextMorning: '隔日上午回報', // scenes/ui/location_panel.gd _TIMING_LABELS.next_morning
  delegationTask: (title: string) => `任務：${title}`, // scenes/ui/location_panel.gd _FMT_DELEGATION_DIALOG_TEXT
  delegationTendency: (tendency: string) => `傾向：${tendency}`, // scenes/ui/location_panel.gd _FMT_DELEGATION_DIALOG_TEXT
  delegationTutorialTitle: '委託', // scenes/main.tscn DelegationTutorialDialog.title
  delegationTutorialText:
    '你拿到了第一張人物卡。你可以委託他們代你去做某些事——委託不佔用你的行動格，一天只能委託同一人一次，回報有些立即、有些要等到隔天上午。', // scenes/main.tscn DelegationTutorialDialog.dialog_text
} as const;
