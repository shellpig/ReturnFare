# ReturnFare 交接狀態

最後更新：2026-08-27

## 目前階段

**P1、P2 已完成；P3 機器層已完成；P4-A～P4-C 已完成；P4-D 遭遇規則實作完成，超載確認立即失敗規則與 P3-F 假綠已全數修復，機器層 26 套 headless 測試全數 exit 0。目前等待 verifier 審核與驗證落檔。下一步任務為 P4-E 遭遇 UI 與 D8／D45 接線。**

- 進度與測試數字的單一事實來源是 `PROJECT_BRIEF.md`；本檔只保存最近交接重點。
- P4-A：委託／遭遇資料與 lint 真值化已完成。
- P4-B：委託規則已實作並通過 verifier 複驗，K-65 結案。
- P4-C：委託 UI、首張人物卡教學與 D17～19 處方案例已實作並完成第三輪 verifier 關門；K-124／K-125 結案，完整 UI sim 104／104 variants、81／81 contracts、0 failed。
- P4-D：遭遇規則與狀態機實作完成，超載確認立即失敗規則與 P3-F 假綠／runner 守門全面修復，`test_p4d.gd` 覆蓋 16 大項驗收標準，26 套 headless 全數 exit 0 通過。
- P4-E～F（遭遇 UI、D8／D45 接線與全流程整合）：待 P4-D 驗證後開工。
- P5：開局、四類結局、歷輪摘要、跨輪重置與 UI 已拆成 P5-A～F，尚未開始實作。

## 最近完成的工作

- **超載進入遭遇規則修改（確認後立即走 failure 出口）**：
  - `scripts/autoload/game_state.gd`：`acknowledge_encounter_intro()` 在 `is_overloaded()` 為 true 時，確認開場後立即結算 failure 出口（`_finish_encounter("failure", enc.get("on_failure", {}))`），不進入第一 round、不加第一 round cost、不保留 active encounter，`on_failure` 效果與文字恰好套用一次；移除無效的 penalty 中繼累加；非超載路徑維持原行為。
  - `acknowledge_encounter_intro()` 的成功結果新增 `entered_round`：超載立即 failure 回 false，真正進入第一 round（即使隨後容量 failure）回 true，讓兩條原本最終狀態相同的路徑可被黑箱測試區分。
  - `tests/headless/test_p4d.gd`：改寫超載測試，逐項斷言：1) `start_encounter` 停在 intro 未套 failure；2) `acknowledge_encounter_intro` 回 `ok:true`＋`entered_round:false`；3) active encounter 已清空；4) 可累加 failure 效果恰好套用一次；5) 無殘留狀態；6) 非超載 acknowledge 回 `entered_round:true` 且只加第一 round cost 一次。
  - `開發設計方針.md > P4-D`：同步更新超載確認立即失敗與 `entered_round` 契約。
  - 變異測試自檢：暫時把明確超載分支改為永不成立，舊容量 failure 路徑回 `entered_round:true`，`test_p4d.gd` 精確 exit 1；還原後 exit 0 全綠。

- **P3-F 假綠修正與 runner 守門收斂（K-152）**：
  - `tests/headless/test_p3f.gd`：`_test_determinism_across_two_runs` 對 `gs_a`、`gs_b` 各自維護 `last_ind_count`，morning／afternoon 正確推導 `forced_m` 與 `forced_a`；每次呼叫 `execute_action_phase()` 接回 Dictionary 且 `ok == false` 累計進 `failed`；所有 `advance_phase()` 均消費結果並檢查 `phase_advanced == true`。
  - `tests/run_all_headless.ps1`：精確守門收斂（K-152），攔截 `SCRIPT ERROR: Assertion failed`、`Invalid access`、`Invalid index`、`Invalid call` 與 stderr 的 `ERROR:\s+FAIL`，不誤傷負向 fixture 合法 ERROR。
  - 變異測試自檢：
    1. 暫時拿掉 gs_a／gs_b 在 D8 `play_night_fixed()` 後的 `solve_active_encounter_if_any()`，`test_p3f.gd` 因 night advance 遭 `encounter_active` 拒絕及後續 action 失敗被明確計數，精確 exit 1（4 assertions failed）。
    2. 注入 `push_error("FAIL: runner sentinel")`，`run_all_headless.ps1` 精確 exit 1 攔截。
    3. 還原後：`test_p3f.gd` exit 0、stderr 0 筆 `FAIL`、0 筆 `SCRIPT ERROR`；完整 26 套 runner exit 0 且顯示 `ALL HEADLESS TESTS PASSED!`。

## 驗證狀態

- P4-D：**實作與阻斷修復完成，機器層全通。** `tests/run_all_headless.ps1` 包含的 26 套 headless 測試全部 exit 0；`test_p4d.gd`、`test_p3f.gd`、`test_p2_sim.gd`、`playthrough_greedy.gd`、`verify_data.gd` 均 exit 0 通過。待 verifier 審核與驗收落檔。
- P4-C：已關門，狀態 ✅。完整 UI sim 104 variants／81 contracts／0 failed。
- P4-B：已關門，狀態 ✅。
- P4-A：已關門，狀態 ✅。

## 目前風險

- P4-D 為純規則與狀態機層，遭遇 UI 與主畫面整合留待 P4-E 實作。
- D8（`n_manydoors_ch1`）與 D45（`d45_encounter`）的正式 UI 呈現、intro 文字演播與按鈕切換需在 P4-E 完成。
- 本專案沒有 Art Bible，也沒有 `.venv`；目前任務不涉及素材或 Python。

## 下一個任務

**Verifier 審核驗收 P4-D 與已知問題落檔，隨後進入 P4-E 遭遇 UI 與 D8／D45 接線**：
- Verifier 審核 P4-D 程式碼、測試與交接報告並落檔文件。
- 下一階段 P4-E 範圍：新增 `scenes/ui/encounter_panel.gd/.tscn`、`main.gd`、`hand_bar.gd`、D8／D45 遭遇 UI 接線與 UI sim 驗證。
