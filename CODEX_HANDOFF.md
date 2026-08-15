# ReturnFare 交接狀態

- 目前階段：Phase 1（P1-A～P1-G）全部實作完成，UI 模擬驗證工具鏈（`tests/ui_sim/`）完成全面重構與缺陷修復，17 個案例變體 100% 通過；P2 規格已齊備，隨時可動工。
- 已完成：
  - Phase 1 全部規則與面板互動模型（`build_panel()`／`play_beat()`／`preview_slot()`、兩階段地點面板、槽型別標示、右鍵／按鈕預覽、推進提示）。
  - UI 模擬驗證工具鏈：`make_states.gd`（動態狀態模板、19 個 checkpoints 驗證）、`run_ui_sim.ps1`（.NET Process 原生啟動）、`qa_step.gd`（子視窗座標轉換、真實輸入事件、事前 Hover 命中強校驗、視口邊界檢驗、視野自動捲動）、`qa_diagnostics.gd`（主視口邊界與容器尺寸溢出檢測）、`p1g_cases.gd` 包含 17 個案例變體。
- 主要修改：`scenes/main.gd`、`scenes/main.tscn`、`scenes/ui/`、`tests/ui_sim/`、`scripts/`。
- 驗證：
  - UI 模擬：17 案例變體全綠（`run_ui_sim.ps1`：Total 17, Passed 17, Failed 0）。
  - 反證測試（Negative Tests）：錯誤 fixture（如 `d2_morning.json` 跑 Case 02/07/11/12a/13）全數 Exit Code 1 轉紅。
  - Headless 回歸：`verify_data.gd`、P1-A～P1-G、`test_boot.gd`、`playthrough_greedy.gd` 全部 exit 0 通過。
- 下一個任務：依 `實作規格書.md > P2-A` 開始實作 P2-A 發狂卡的產生與倒數時鐘機制。
