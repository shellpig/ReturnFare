# ReturnFare 交接狀態

最後更新：2026-08-27

## 目前階段

**P1～P3 已完成；P4-A～P4-D 已完成；P4-E 遭遇 UI 面板、D8／D45 生命週期接線、CardDetail 整合與 F1～F6 修復全數完成。全套 27 套 headless 測試全數 exit 0，全套 UI Sim（85 契約、108 變體與負向測試）全數 exit 0（0 failed checks）。待 verifier 審核與落檔。**

- 進度與測試數字的單一事實來源是 `PROJECT_BRIEF.md`；本檔只保存最近交接重點。
- P4-A：委託／遭遇資料與 lint 真值化已完成。
- P4-B：委託規則已實作並通過 verifier 複驗，K-65 結案。
- P4-C：委託 UI、首張人物卡教學與 D17～19 處方案例已完成。
- P4-D：遭遇規則與狀態機實作完成，26 套 headless 全數 exit 0 通過。
- P4-E：遭遇 UI 面板、CardDetail 詳情整合、D8／D45 遭遇生命週期與時段推進接線完成。27 套 headless（含 `test_p4e.gd`）與 85 條 UI 契約全綠。
- P4-F：全流程整合與預算走查。
- P5：開局、四類結局、歷輪摘要、跨輪重置與 UI 已拆成 P5-A～F，尚未開始實作。

## 最近完成的工作（P4-E 與 F1～F6 修復）

1. **F1｜遭遇出口文字畫面保留**：
   - `scenes/main.gd`：新增 `_route_view_after_encounter(encounter_lines)` 與 `_show_final_coda(encounter_lines)`，遭遇結束時（勝／敗／逃離／回應）出口文字寫入 FlowText 並保留於畫面頂部（0..120），不被後續時段路由的 `clear()` 沖刷；D45 遭遇回應後 FlowText 顯示回應文字且 coda 地點面板（`jinghe_back`）於下方（130..400）同時可見。
   - `_p4e_04` 補強真斷言：嚴格斷言 FlowText 呈現 `「你拿出了你自己」` 或 `「這個名字已經登記」`，排除 coda 地點面板名稱誤判。

2. **F2｜D45 遭遇不吃容量（per_round_slot_cost: 0）**：
   - `data/beats/ch3_d39_d45.json`：設定 D45 遭遇 `per_round_slot_cost: 0`。
   - `data/SCHEMA.md` & `scripts/data_loader.gd` & `scripts/autoload/game_state.gd`：規範 `per_round_slot_cost` 為非負整數（允許 0），`_check_encounter_capacity_failure()` 在 `blocked_slots <= 0` 時僅於手牌超載（`is_overloaded()`）時判定容量失敗。
   - `tests/ui_sim/make_states.gd`：移除手牌裁減 hack，自然走查滿手 14 張正常進入 D45 答題。

3. **F3｜D10 手牌狀態自然反映 D8 消耗**：
   - `tests/ui_sim/make_states.gd`：移除補打 `info_husband_version` / `info_wife_version` hack。
   - `tests/ui_sim/cases/p1af_cases.gd`（`_p1h_02`、`_p1h_05`）與 `run_ui_sim.ps1`（`long_card_name`）：改為測試 D10 自然持有之卡片（`routine_debt` 與 `info_ahong_private`），忠實反映故事線 D8 消耗。

4. **F4｜test_p4e.gd loader 污染隔離（守則 7）**：
   - `tests/headless/test_p4e.gd`：`_test_5` 備份 `cards` 並在容量測試後立即還原 `data_node.loader.cards`，徹底杜絕測試間污染。

5. **F5｜P4-E 關鍵特性全量 UI 斷言補齊**：
   - `tests/ui_sim/cases/p1af_cases.gd` & `tests/ui_sim/qa_contract_matrix.gd`：
     - 遭遇進行中推進按鈕 disabled 守衛斷言（intro 與 round 階段）。
     - `encounter_blocked::N` 壓力 placeholder 黑色方塊斷言。
     - `encounter_capacity` 標籤文字（包含可用格數與壓力佔格）斷言。
     - 知識卡標記「（知識）」斷言。
     - `madness_blocked` 與 `already_attempted` disabled 理由呈現斷言。
     - D8 遭遇之 `discard` 與 `escape_pay` 按鈕確認／取消／狀態逐字不變斷言。

6. **F6｜重用 HandBar / CardDetail**：
   - `scenes/ui/encounter_panel.gd`：候選卡旁新增 `[詳情]` 按鈕並支援右鍵點擊，透過 `card_detail_requested` 訊號轉發至 `HandBar.show_card_detail()`，重用全域唯一 `CardDetail` 彈窗，無重複實例，支援唯讀檢視卡面資訊。

## 驗證狀態

- **Headless 測試**：`tests/run_all_headless.ps1` 包含的 27 套 headless 測試全部 exit 0 通過。
- **UI Sim 測試**：`tests/ui_sim/run_ui_sim.ps1` 執行 108 variants、85 catalog contracts、85 executed contracts、85 completed contracts、0 failed checks，exit 0 全綠。

## 目前風險

- 無已知阻斷性缺陷。全套 headless 與 UI sim 全綠。

## 下一個任務

**Verifier 審核與驗收落檔 P4-E，準備進入 P4-F 全流程整合與預算走查**。
