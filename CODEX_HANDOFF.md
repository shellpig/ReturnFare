# ReturnFare 交接狀態

最後更新：2026-08-27

## 目前階段

**P1、P2 已完成；P3 機器層已完成，剩既有人工體感項；P4-A、P4-B 已通過 verifier 複驗；P4-C 已實作並完成 headless／新案例驗證，但完整 UI regression 被 K-125 阻塞，維持 🟦。下一個任務是修 K-125 並完成 P4-C 關門；不得先進 P4-D，也不得跳到 P5。**

- 進度與測試數字的單一事實來源是 `PROJECT_BRIEF.md`；本檔只保存最近交接重點。
- P4-A：委託／遭遇資料與 lint 真值化已完成。
- P4-B：委託規則已實作並通過 verifier 複驗，機器層 24 套 headless 測試全數 exit 0；K-65 結案。
- P4-C：委託 UI、首張人物卡教學與 D17～19 處方案例已實作；K-124 已結案。完整 UI sim 因 K-125 為 98／102 variants、76／79 contracts，尚未關門。
- P4-D～F（遭遇 runtime、UI 與全流程）尚未開始。
- P5：開局、四類結局、歷輪摘要、跨輪重置與 UI 已拆成 P5-A～F，尚未開始實作。

## 最近完成的工作

- **K-124 修復經 verifier 複驗結案（`4b0ba1c`）。** 8 組精確 madness fixture 逐案正規化，後置條件改驗精確張數／clock／day／phase，P4-C 零人物卡改按 type 計數；同批結 K-112，P3-A baseline 只在明示旗標時產生。獨立 fixture 生成 exit 0、baseline mtime 不變、25 套 headless 全綠。
- **P4-C 完整 UI launcher 首次跑到底並定位 K-125。** Run `20260827-074010-986-p50004-a1c03a80`：102 variants、79 contracts 全執行、98 variants 通過、76 contracts 完成、11 條負向反證如期失敗；4 個失敗變體都由 D17 教學 modal 遮住底層 `beat_advance`，而 `drain_beats()` 只看 tree visibility 所致。production 玩家可按 OK 繼續，不是 beat 無限迴圈。

- **P4-B 委託規則已實作完成並通過 verifier 複驗（24 套 headless exit 0，含 `test_p4b.gd`）。**
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

- K-124：**已修、已複驗**。`make_states.gd` pipeline blocker 解除，79 contracts 可全部啟動；其餘失敗獨立移至 K-125。
- P4-C：25 套 headless 全綠，`p4c_01`～`p4c_05` 全過；完整 UI sim 98／102 variants、76／79 contracts，故仍為 🟦，`測試指南.md > P4-C` 尚未打勾。
- P4-B verifier 複驗：**`tests/run_all_headless.ps1` 全部 24 套 exit 0**（含 `test_p4b.gd` 9 大測試段）。`verify_data.gd` 64／48／18／261、引用與 lint 1～16 全 0 錯誤；接點失效保留、嚴格回報順序、強制縱慾先行與 K-65 同筆／跨筆／文字三條均有可辨識斷言。

## 目前風險

- K-125 是目前唯一 P4-C 機器關門 blocker：教學 modal 出現時，UI sim 仍把被遮住的底層 control 當作可操作；同族風險限測試工具的 modal／visibility 判準，未證實為 production 缺陷。
- P4-D～F、P5 都仍是規格狀態；遭遇 runtime／UI 與 P5 各項系統尚未兌現。
- 本專案沒有 Art Bible，也沒有 `.venv`；目前任務不涉及素材或 Python。

## 下一個任務

**修 K-125，完成 P4-C 關門驗證**（詳見 `驗證後已知問題.md > K-125`）：

- production 與正式 D17 資料不動；保留首次取得人物卡時的 modal 教學。
- `drain_beats()` 每輪先處理明示允許的 `dialog_confirm::delegation_tutorial`，透過真實 input 關閉後才繼續 `beat_advance`；未知 modal 回具名錯誤，不可全部靜默關閉。
- dialog 與 beat 分開計數，補 D17 第一次教學／關閉寫 meta／有限步數結束／重進不重複 `on_enter` 的回歸證據。
- 先重跑 K-125 的 4 個失敗 variants，再跑完整 UI launcher；只有達 102／102 variants、79／79 contracts、0 failed checks，且 11 條負向反證仍如期失敗，才由 verifier 打勾 P4-C、轉 ✅ 並進 P4-D。
