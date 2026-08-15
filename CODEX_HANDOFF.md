# ReturnFare 交接狀態

- 目前階段：Phase 1（P1-A～P1-G）全部實作完成，UI 模擬驗證工具鏈（`tests/ui_sim/`）完成全面重構與缺陷修復，P1-G 第一批 14 條需求（17 個案例變體）100% 通過；其餘 33 條與全流程無注入走查列入後續擴充計畫。P2 規格已齊備，隨時可動工。
- 已完成：
  - Phase 1 全部規則與面板互動模型（`build_panel()`／`play_beat()`／`preview_slot()`、兩階段地點面板、槽型別標示、右鍵／按鈕預覽、推進提示）。
  - UI 模擬驗證工具鏈：`make_states.gd`（動態狀態模板、19 個 checkpoints 驗證）、`run_ui_sim.ps1`（.NET Process 原生啟動、參數轉義與 binary 預檢）、`qa_step.gd`（子視窗座標轉換、純真實輸入事件、事前 Hover 命中強校驗）、`qa_diagnostics.gd`（Z-Index 繪製順序、Panel 遮蔽、視口邊界與未裁切容器溢出檢測、保護區侵入檢查）、`p1g_cases.gd` 包含 17 個案例變體（單步推進、去作弊預覽集合比對、夜間實質放卡、防劇透等）。
- 主要修改：`scenes/main.gd`、`scenes/ui/location_panel.gd`、`tests/ui_sim/`、`scripts/`。
- 驗證：
  - UI 模擬：17 案例變體全綠（`run_ui_sim.ps1`：Total 17, Passed 17, Failed 0）。
  - 反證測試（Negative Tests）：錯誤 fixture 與反向狀態全數 Exit Code 1 轉紅。
  - Headless 回歸：`verify_data.gd`、P1-A～P1-G、`test_boot.gd`、`playthrough_greedy.gd` 全部 exit 0 通過。
- 下一個任務：依 `實作規格書.md > P2-A` 開始實作 P2-A 發狂卡的產生與倒數時鐘機制。
