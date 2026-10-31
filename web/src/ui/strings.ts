// Godot: opening_panel.tscn ConfirmDialog; location_panel.tscn; main.gd status/advance.
export const strings = {
  confirm: '確認', cancel: '取消', continue: '繼續演出', advance: '推進時段',
  loading: '資料載入中…', dataError: '資料載入失敗',
  status: (day: number, phase: string, chapter: number) => `第 ${day} 天  ${phase}  第 ${chapter} 章`,
  phases: { morning: '上午', afternoon: '下午', evening: '傍晚', night: '夜晚' },
} as const;
