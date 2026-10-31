// UI 介面詞彙（W-02）：沿用 Godot 原文，逐條註明來源；Godot 無對應原文者另註。
export const strings = {
  // scenes/ui/opening_panel.tscn ConfirmDialog 用引擎預設按鈕、無專案原文；確認／取消為 W3-A 新增。
  confirm: '確認',
  cancel: '取消',
  continue: '繼續演出', // scenes/ui/location_panel.tscn AdvanceBeatButton
  advance: '推進時段', // scenes/main.gd _MSG_ADVANCE；scenes/main.tscn AdvanceButton
  loading: '載入中...', // scenes/main.tscn StatusLabel 初始文字
  dataError: '資料載入失敗', // scenes/main.gd _MSG_DATA_ERROR，去掉僅適用 Godot 編輯器的「詳情見 Output。」
  status: (day: number, phase: string, chapter: number) => `第 ${day} 天  ${phase}  第 ${chapter} 章`, // scenes/main.gd _FMT_STATUS
  // Godot 狀態列直接顯示 phase id（morning 等）；中文時段名為 W3-A 新增，Godot 無原文。
  phases: { morning: '上午', afternoon: '下午', evening: '傍晚', night: '夜晚' },
} as const;
