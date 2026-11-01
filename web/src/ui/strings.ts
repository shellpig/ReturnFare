// UI 介面詞彙（W-02）：沿用 Godot 原文，逐條註明來源；Godot 無對應原文者另註。
export const strings = {
  // scenes/ui/opening_panel.tscn ConfirmDialog 用引擎預設按鈕、無專案原文；確認／取消為 W3-A 新增。
  confirm: '確認',
  cancel: '取消',
  continue: '繼續演出', // scenes/ui/location_panel.tscn AdvanceBeatButton
  advance: '推進時段', // scenes/main.gd _MSG_ADVANCE；scenes/main.tscn AdvanceButton
  advanceUnseen: '推進時段（還有演出沒看）', // scenes/main.gd _MSG_ADVANCE_UNSEEN
  advanceHint: '推進時段（目前無可做動作）', // scenes/main.gd _MSG_ADVANCE_HINT
  placeCard: '放入卡片',
  preview: '預覽',
  placeableCardsTitle: '可放置卡片：',
  noPlaceableCards: '無可放置卡片',
  previewReason: (reason: string) => `理由：${reason}`,
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
} as const;
