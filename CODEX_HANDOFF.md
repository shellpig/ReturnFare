# ReturnFare 交接狀態

最後更新：2026-08-26

## 目前階段

**P1、P2 已完成；P3 機器層已完成，剩既有人工體感項；P4-A、P4-B 已實作並自驗全綠（機器層）；P4-C～F 與 P5-A～F 仍為規格。下一個實作任務是 P4-C（委託 UI 與首個案例）。P5 不得跳過 P4 提前實作。**

- 進度與測試數字的單一事實來源是 `PROJECT_BRIEF.md`；本檔只保存最近交接重點。
- P4-A：委託／遭遇資料與 lint 真值化已完成。
- P4-B：委託規則已實作完成，機器層 24 套 headless 測試全數 exit 0。
- P4-C～F（委託 UI、遭遇 runtime 與 UI）尚未開始。
- P5：開局、四類結局、歷輪摘要、跨輪重置與 UI 已拆成 P5-A～F，尚未開始實作。

## 最近完成的工作

- **P4-B 委託規則已實作完成，機器層自驗全綠（24 套 headless exit 0，含新 `test_p4b.gd`）。**
  - **Run 狀態擴充**：
    - `delegates_used_today: Dictionary`：追蹤今日已受託人物卡（單日單人限制）。
    - `pending_delegation_reports: Array[Dictionary]`：儲存 `[{due_day, beat_id, slot_id, person_id}]` 隔日上午待結算回報接點。
    - `last_delegation_report_lines: PackedStringArray`：收集當前上午回報所產生的文字演出行。
    - `run_generation: int`：單調遞增的世代計數器，供 `EffectApply` 與結算器無瑕疵偵測 `end_run()` 重置事件。
  - **`delegate(beat_id, slot_id, person_card_id) -> Dictionary` 入口**：
    - 嚴格落實 11 步檢查順序：`not_action_phase` → `unknown_beat` → `unknown_slot` → `not_delegation` → `not_held` → `not_person` → `not_accepted` → `already_delegated_today` → `locked` → `already_resolved` → `data_conflict`。
    - 成功時原子寫入 `choices`、`slots_placed`、`delegates_used_today`。`immediate` 當場套用 `on_place`；`next_morning` 當場套用 `on_place` 並將接點 append 至 `pending_delegation_reports`。
    - 委託成功不消耗主角行動格（`action_spent` 維持不變）、不增加 `npc_action_counts`、人物卡不移出手牌。
  - **`delegation_status(person_card_id) -> Dictionary` 查詢**：
    - 回傳 `{ held: bool, delegated_today: bool, available: bool, has_pending_report: bool }`。
  - **隔日上午結算與重置（含接點失效保留與 K-65 徹底修復）**：
    - `advance_phase()` 進入 morning 時，在既有發狂倒數與強制縱慾結算之後，呼叫 `_settle_pending_delegation_reports()` 依序套用 due reports 的 `report` 效果並收集文字行至 `last_delegation_report_lines`。
    - 結算前完整驗證接點（beat/slot/timing/report）：若接點失效則保留於 pending 並 `push_error` 顯式回報 data_conflict，不靜默丟棄。
    - **K-65 根因徹底修復**：`EffectApply.apply` 於 `_check_madness_cap()` 觸發重置時立即停止後續效果鍵（flag 等），回傳空陣列；結算器偵測到重置時立即 `return`，不寫入文字、不覆蓋已清空的 `last_delegation_report_lines`、且中斷後續回報迴圈。
    - 結算完成後呼叫 `delegates_used_today.clear()` 重置每日受託名單。
  - **P4-A 臨時 Gate 拆除與轉導**：
    - 拆除 `choose()` 原有的 `delegation_not_wired` 臨時 gate。
    - `choose()` 與 `try_place()` 遇到帶 `delegation` 鍵的槽時，自動轉導至 `delegate()` 處理。
    - 更新 `test_p4a.gd` 第 5 組測試，使 choice_requires_card 與委託轉導各自獨立驗證。
  - **序列化與健全度**：
    - `serialize()` / `deserialize()` 完整支援 `delegates_used_today` 與 `pending_delegation_reports`。
    - 人物卡在派出後若被事件移除，隔日上午回報仍依接點如期結算。
    - `end_run()` 完整清空所有委託相關狀態。
  - **驗收審查修正**：
    - `test_p4b.gd` 補齊嚴格回報陣列索引比對（`lines[0]==rep1, lines[1]==rep2`）。
    - `test_p4b.gd` 增加強制縱慾先於回報執行的因果依賴測試（消發狂卡後回報條件 gain 成立）。
    - `test_p4b.gd` 增加第 9 測試段：4 類接點失效保留驗證，以及同筆 report 後置 flag/文字阻擋 + 跨 report 迴圈中斷防呆驗證。
    - `測試指南.md` 修正 line 413 關於 afternoon (`already_delegated_today`) 與 evening (`not_action_phase`) 拒絕碼文字說明。

- **P4-A 資料與 SCHEMA 真值化（前期完成）**：
  - **卡片**：`cards.json` 全 64 張皆有必填 boolean `discardable`；lint 9 新增缺欄／錯型別檢查。
  - **D8**（`n_manydoors_ch1`）改為 dated night encounter；**D45**（`d45_encounter`）改為一 round encounter。
  - **D17-19 委託**：`d17_19_prescription` 建立親自處理＋阿婕 immediate／阿珠 next_morning+report／阿財 immediate 路線。
  - **lint 15 / 16**：委託與遭遇資料結構 lint 全綠。

## 驗證狀態

- P4-B 機器層自驗：**`tests/run_all_headless.ps1` 全部 24 套 exit 0**（含 `test_p4b.gd` 9 大測試段）。`verify_data.gd` lint 1～16 全 0 錯誤。
- 這是實作者自跑證據，**verifier 打勾與 `PROJECT_BRIEF.md` 落檔尚未進行**。

## 目前風險

- P4-C～F、P5 都仍是規格狀態；正式 UI、遭遇 runtime 與 P5 各項系統尚未兌現。
- P4-C 進行 UI 接線時需注意：委託槽留在 location panel，不建立獨立畫面；教學視窗之 `mark_delegation_tutorial_seen()` 需進 meta 序列化。
- 本專案沒有 Art Bible，也沒有 `.venv`；目前任務不涉及素材或 Python。

## 下一個任務

**P4-C 委託 UI 與首個案例**（`實作規格書.md > P4-C`、`開發設計方針.md > P4-C`、`測試指南.md > P4-C`）：

- 動的檔：`panel_builder.gd`、`location_panel.gd/.tscn`、`hand_bar.gd`、`card_detail.gd`、`main.gd`、P4-C UI sim／checkpoints、`CODEX_HANDOFF.md`。
- 不建獨立委託畫面：委託槽留在 location panel，view model 增加 `{result_timing, preview, tendency, delegation_state}`。
- 未取得候選不出現；今日用過者留在原位顯示「今日已受託」；缺條件者顯示資料理由。
- 確認視窗顯示 preview、tendency 與「立即／隔日上午回報」；`main.gd` 送意圖給 `delegate()`、lines 送 FlowText 並刷新。
- HandBar 由 `delegation_status()` 顯示人物狀態。首次獲得人物卡且 `delegation_tutorial_seen == false` 時 emit `delegation_tutorial_available`，關閉/略過時呼叫 `mark_delegation_tutorial_seen()`。
