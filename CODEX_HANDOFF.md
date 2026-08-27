# ReturnFare 交接狀態

最後更新：2026-08-27

## 目前階段

**P1、P2 已完成；P3 機器層已完成；P4-A～P4-C 已完成；P4-D 遭遇規則實作完成，機器層 26 套 headless 測試全數 exit 0。目前等待 verifier 審核與驗證打分。下一步任務為 P4-E 遭遇 UI 與 D8／D45 接線。**

- 進度與測試數字的單一事實來源是 `PROJECT_BRIEF.md`；本檔只保存最近交接重點。
- P4-A：委託／遭遇資料與 lint 真值化已完成。
- P4-B：委託規則已實作並通過 verifier 複驗，K-65 結案。
- P4-C：委託 UI、首張人物卡教學與 D17～19 處方案例已實作並完成第三輪 verifier 關門；K-124／K-125 結案，完整 UI sim 104／104 variants、81／81 contracts、0 failed。
- P4-D：遭遇規則與狀態機實作完成，`test_p4d.gd` 覆蓋 14 大項驗收標準，26 套 headless 全數 exit 0 通過。
- P4-E～F（遭遇 UI、D8／D45 接線與全流程整合）：待 P4-D 驗證後開工。
- P5：開局、四類結局、歷輪摘要、跨輪重置與 UI 已拆成 P5-A～F，尚未開始實作。

## 最近完成的工作

- **P4-D 遭遇規則實作與 18 條待修項目（K-126～K-143）全面修復完成，變異測試全部轉紅驗收。**
  - **核心規則層與引擎防禦修復**：
    - **K-126**：`GameState.play_night_fixed()` 正式接上遭遇啟動邏輯，播完 fixed beat 且帶 `encounter` 時自動呼叫 `start_encounter(bid)`。
    - **K-132**：`respond_to_encounter` 順序調整，`card_not_submittable` 先於 `data_conflict`，嚴格遵從方針。
    - **K-133**：`_finish_encounter` 加入 `gen_before := run_generation` 世代守衛，若重置則不推進 `advance_phase`。
    - **K-134**：`active_encounter` 增加 `visited_round_ids: Array[String]`，進入重複 round 時 `push_error` 回 `data_conflict`，防範圖循環重扣，序列化往返保留。
    - **K-135**：`hand_size` fallback 預設值統一為 `14`。
    - **K-136**：`_check_encounter_capacity_failure()` 移除死參數 `enc`。
    - **K-137**：`_card_base_id` 委派給 `DataFacts.card_base_id`。
    - **K-142**：`playthrough_greedy.gd` 與 `test_p3f.gd` 實作 `solve_active_encounter_if_any` 循環完整結算遭遇（涵蓋 D8 night 與 D45 afternoon）。
    - **K-143**：走查腳本恢復 afternoon `last_ind_count` 快照，`advance_phase` 嚴格消費結果。
  - **測試層強化與變異測試驗收（`tests/headless/test_p4d.gd`）**：
    - **K-127**：覆蓋 D45 afternoon 與 D8 night 自動啟動 hook 測試（拔除即轉紅）。
    - **K-128**：15 碼拒絕矩陣每例前後 `serialize()` 逐字比對零變化（注入副作用即轉紅）。
    - **K-129**：`encounter_view()` 正向（`candidates` 來源標籤）與負向嚴格不洩漏答案／圖結構（洩漏即轉紅）。
    - **K-130**：補 `after_finish: "stay"` 測試，斷言結算後 day/phase 逐字不變。
    - **K-131**：5 個遭遇 mutation 入口各自覆蓋至少一組雙重失敗優先序測試（反序即轉紅）。
    - **K-134**：帶 cycle 的惡意遭遇測試，驗證 `visited_round_ids` 阻擋（拔除即轉紅）。
    - **K-138**：真實故事遭遇走通（D8 `n_manydoors_ch1`、D45 `d45_encounter`），mock fixture 測試後全數乾淨清理。
    - **K-139**：序列化往返改由真實 `respond_to_encounter` 產生 attempted，並與未存檔對照組逐字比對最終 serialize（遺漏即轉紅）。
    - **K-140**：出口效果改用可累加數值（`relation` + 數值、`gain` + 卡片）驗證只套用恰好一次（重複套用即轉紅）。
    - **K-141**：完整遭遇前後斷言 `action_spent`、`indulgence_count`、`forced_pending` 逐字不變（修改即轉紅）。
  - 全專案 26 套 headless 測試（`tests/run_all_headless.ps1`）全數 exit 0 通過。

## 驗證狀態

- P4-D：**實作完成，機器層全通。** `tests/run_all_headless.ps1` 包含的 26 套 headless 測試全部 exit 0；`test_p4d.gd` 12 大項斷言全部通過。待外部 reviewer / verifier 審核與驗收打分。
- P4-C：已關門，狀態 ✅。完整 UI sim 104 variants／81 contracts／0 failed。
- P4-B：已關門，狀態 ✅。
- P4-A：已關門，狀態 ✅。

## 目前風險

- P4-D 為純規則與狀態機層，遭遇 UI 與主畫面整合留待 P4-E 實作。
- D8（`n_manydoors_ch1`）與 D45（`d45_encounter`）的正式 UI 呈現、intro 文字演播與按鈕切換需在 P4-E 完成。
- 本專案沒有 Art Bible，也沒有 `.venv`；目前任務不涉及素材或 Python。

## 下一個任務

**Verifier 審核驗收 P4-D，隨後進入 P4-E 遭遇 UI 與 D8／D45 接線**：
- Verifier 審核 P4-D 程式碼、測試與交接報告並進行打分。
- 下一階段 P4-E 範圍：新增 `scenes/ui/encounter_panel.gd/.tscn`、`main.gd`、`hand_bar.gd`、D8／D45 遭遇 UI 接線與 UI sim 驗證。
