# ReturnFare 交接狀態

最後更新：2026-08-27

## 目前階段

**P1～P3 已完成；P4-A～P4-F 全部實作完成。全套 28 套 headless 測試全數 exit 0（含 test_p4f.gd 4 大項全流程與跨輪整合測試），全套 UI Sim（85 契約、108 變體與負向測試）全數 exit 0（0 failed checks）。** K-148、K-165、K-166、K-167、K-168 全數修復完成。待 verifier 複驗關門 P4-F。**下一步 Phase 5（P5-A 結局、開局與跨輪資料）。**

- 進度與測試數字的單一事實來源是 `PROJECT_BRIEF.md`；本檔只保存最近交接重點。
- **工具變更（2026-08-27）：UI 模擬新增 `-Background`，之後跑一律加。** `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\ui_sim\run_ui_sim.ps1 -Background`。每個 Godot 行程開在獨立 Windows desktop 上，不佔畫面、不搶焦點、不碰實體滑鼠；產物與前景模式逐位元組相同（2078 張截圖與 2078 份 dump 全部 SHA256 相同）。機制與已排除的四種做法見 `開發設計方針.md > UI 模擬驗證 > 背景模式`——**那四種都實測失敗過，不要再試一次**。
- P4-A：委託／遭遇資料與 lint 真值化已完成。
- P4-B：委託規則已實作並通過 verifier 複驗，K-65 結案。
- P4-C：委託 UI、首張人物卡教學與 D17～19 處方案例已完成。
- P4-D：遭遇規則與狀態機實作完成，26 套 headless 全數 exit 0 通過。
- P4-E：遭遇 UI 面板、CardDetail 詳情整合、D8／D45 遭遇生命週期與時段推進接線完成。
- P4-F：全流程與跨輪整合實作完成。28 套 headless（含 `test_p4f.gd` 4 大項）與 85 條 UI 契約全綠。
- P5：開局、四類結局、歷輪摘要、跨輪重置與 UI 已拆成 P5-A～F，待 P4-F 關門後開工。

## 最近完成的工作（P4-F 全流程與跨輪驗收實作）

1. **`tests/headless/test_p4f.gd` 實作完成（四大整合測試項，exit 0 全綠）**：
   - **D17～19 處方委託四狀態覆蓋**：零人物卡親自做（find_self 消耗行動格、獲得處方卡）、阿婕即時回報（不耗格、人物在手、即時獲得處方與情報）、阿珠隔日上午回報（派出當下不發卡、隔日上午依序結算）、阿財主觀回報（獲得箱子情報、不給處方），以及每日一人一次限制與 choice_group prescription_route 互斥。
   - **D8／D45 遭遇 Response Matrix 動態資料衍生**：D8 正解前進、Fallback 消耗可丟棄卡、逃離、零可丟棄卡 direct failure；D45 推論卡三種特殊轉化（`inf_health_disappearance`、`inf_jinghe_does_it`、`inf_hotspring_kills` 轉為對應知識卡）、主角卡與人物卡保留在手、直呼逃離／丟棄拒絕、選後推進至 evening。
   - **跨輪重置與第二輪驗證**：第一輪真實 `end_run()` 後，Meta 層（`delegation_tutorial_seen`、`knowledge`、`night_locations_seen`、`night_once_beats_seen`）完整保留；Run 層（`delegates_used_today`、`pending_delegation_reports`、`active_encounter`、`flags` 等）完整清空；第二輪 D8 重演且因 `n_manydoors` 已見不重複收取首次 marker cost。
   - **跨輪決定論測試**：相同第一輪終態 serialize 載入兩次，執行相同之第二輪操作序列，最終 `serialize()` 產物與時間軸記錄逐字完全相同。

2. **K-148 修復（`playthrough_greedy.gd` 移除 `assert` 地雷）**：
   - `run_greedy_walk()` 將 4 處 `assert` 改為將錯誤訊息 append 進 `errors: Array[String]` 並於回傳字典提供，消費端（`test_p1f.gd`、`test_p3f.gd`）檢查並報錯。

3. **K-165 修復（`p1af_cases.gd` UI Sim 斷言補強）**：
   - `_p4e_02` 進入 R2 後多一次 `find_controls_by_qa_id` 斷言主角卡按鈕 disabled。
   - `_p4e_04` 出口後斷言 `EncounterPanel` 不可見且 `encounter_blocked::0` 在場景樹中不存在。

4. **K-166 修復（`test_p4e.gd` 睡覺阻斷可證偽斷言）**：
   - 第 12 項補上 round 階段 `sleep_night()` 呼叫前後 serialize 逐字比對。
   - 增加 D24 颱風夜可播定日 sleep 內容對照組，證明「有內容但被遭遇擋住返回空陣列且狀態零變化」具備可證偽性。

5. **K-167 修復（`scenes/main.gd` 推進按鈕禁用單一事實來源）**：
   - `_show_encounter()` 移除手動 `_advance_btn.disabled = true`，統一呼叫 `_refresh_advance_hint()`。

6. **K-168 修復（`test_p4e.gd` 滿手容量測試改用合法卡片）**：
   - 第 9 項 Path 3 填充滿手改用 13 張獨立合法卡片 ID。

7. **工具鏈整合（`tests/run_all_headless.ps1` 擴展至 28 套）**：
   - 新增 `tests/headless/test_p4f.gd`，全套 28 套 headless 測試全部 exit 0 通過。

## 驗證狀態

- **Headless 測試**：`tests/run_all_headless.ps1` 包含的 28 套 headless 測試全部 exit 0 通過。
- **UI Sim 測試**：`tests/ui_sim/run_ui_sim.ps1 -Background` 執行 108 variants、85 catalog contracts、85 executed contracts、85 completed contracts、0 failed checks，exit 0 全綠。

## 目前風險

- 無已知阻斷性缺陷。全套 28 套 headless 與 UI sim 全綠。

## 下一個任務

**P4-F 實作已完成，交由 verifier 進行複驗、4 項體感記錄與文件關門。** 關門後下一步依序進入 Phase 5（P5-A 結局、開局與跨輪資料）。
