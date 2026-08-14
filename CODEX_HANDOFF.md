# ReturnFare 交接狀態

- 目前階段：P1-G 面板互動模型已實作，等待 P1 手動操作驗收。
- 已完成：規則層 `build_panel()`／`play_beat()`／`preview_slot()`；移除 `open_panel()`；兩階段地點面板；槽型別標示、右鍵／預覽按鈕、推進提示；`locations.json.desc` 缺欄位 fallback；走查改走 `play_beat()`；lint 9。
- 主要修改：`scripts/autoload/game_state.gd`、`scripts/core/panel_builder.gd`、`scripts/data_loader.gd`、`scripts/autoload/data.gd`、`scripts/verify_data.gd`、`scenes/main.gd`、`scenes/ui/location_panel.gd`、`scenes/ui/location_panel.tscn`、`scenes/ui/map_list.gd`、相關 headless tests。
- 驗證：`verify_data.gd`、P1-A～P1-F、P1-G、P1-C bugfix、`test_boot.gd`、`playthrough_greedy.gd` 全部通過；45 天走查仍為 56 次成功放置、回到第 1 天 morning。
- 未驗證風險：尚未人工跑 `測試指南.md > Phase 1` 的 35 條操作清單；48 個 `locations.json.desc` 仍未填內容。
- 下一個最安全任務：依 `測試指南.md > P1-G` 先跑人工互動驗收；發現的 UI／操作問題由 verifier 登錄，再另行指定修正。
