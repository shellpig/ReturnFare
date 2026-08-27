# ReturnFare 交接狀態

最後更新：2026-08-27

## 目前階段

**P1、P2 已完成；P3 機器層已完成，剩既有人工體感項；P4-A～P4-C 已通過 verifier 複驗，K-124／K-125 結案，P4-C 轉 ✅。下一個任務是 P4-D 遭遇規則；不得先做 P4-E，也不得跳到 P5。**

- 進度與測試數字的單一事實來源是 `PROJECT_BRIEF.md`；本檔只保存最近交接重點。
- P4-A：委託／遭遇資料與 lint 真值化已完成。
- P4-B：委託規則已實作並通過 verifier 複驗，機器層 24 套 headless 測試全數 exit 0；K-65 結案。
- P4-C：委託 UI、首張人物卡教學與 D17～19 處方案例已實作並關門；K-124／K-125 結案，25 套 headless 全綠，完整 UI sim 102／102 variants、79／79 contracts、0 failed。
- P4-D～F（遭遇 runtime、UI 與全流程）尚未開始。
- P5：開局、四類結局、歷輪摘要、跨輪重置與 UI 已拆成 P5-A～F，尚未開始實作。

## 最近完成的工作

- **P4-C 接線 A 補強與四條缺口補測（本次，尚待 verifier 複驗與文件關門）。** 委託即時回報改由 `main.gd` 經 `delegate()` 意圖信號寫入 FlowText（`location_panel.gd` 只發 `delegation_requested`，不再自呼 `try_place()`／寫面板內 `_status_label`），與隔日回報同一處呈現，成功後關面板回地圖；失敗經 `report_delegation_failure()` 保留面板顯示原因。補 `test_p4c.gd` 四段：阿婕信任修復重取、D18／D19 完成處方、任一路線結算後跨日回 `already_resolved`、候選永遠照資料槽序。UI sim `p4c_03` 改斷言即時回報落 FlowText＋面板關閉＋choice 收起（evidence 改 `immediate_report_in_flowtext`，`qa_contract_matrix.gd` 同步）。**證據：25 套 headless exit 0（`test_p4c` 10 段全綠）；完整 UI sim 102／102 variants、79／79 contracts、0 failed、11 條負向反證如期失敗。** 這批補的是先前七條打勾中缺直接證據的六項（今日已受託顯示、穩定排序、修復重取、D18／D19、跨日不重複、immediate→FlowText），打勾與文件關門仍由 verifier 落。
- **K-125 修復經 verifier 複驗結案，P4-C 文件關門（`7a439f6`）。** `drain_beats()` 優先以真實輸入處理已知教學 modal，dialog 與 beat 分開計數；D17 回歸斷言教學曾處理且 meta 已寫入。原 4 個失敗變體全數通過；完整 run `20260827-081934-525-p21024-40718853` 為 102／102 variants、79／79 contracts、0 failed，11 條負向反證如期失敗。P4-C 七條驗收全數打勾並轉 ✅。
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

- K-124／K-125：**已修、已複驗**。fixture pipeline 與教學 modal 輸入 blocker 均解除。
- P4-C：25 套 headless 全綠；完整 UI sim 102／102 variants、79／79 contracts、0 failed，11 條負向反證如期失敗；七條驗收已打勾，狀態 ✅。
- P4-B verifier 複驗：**`tests/run_all_headless.ps1` 全部 24 套 exit 0**（含 `test_p4b.gd` 9 大測試段）。`verify_data.gd` 64／48／18／261、引用與 lint 1～16 全 0 錯誤；接點失效保留、嚴格回報順序、強制縱慾先行與 K-65 同筆／跨筆／文字三條均有可辨識斷言。

## 目前風險

- P4-C 已無機器關門 blocker。低優先觀察：未列入白名單的未知 modal 仍可能最終被 helper 報成 beat 上限，而非立即回具名 blocking-dialog 錯誤；只影響失敗診斷精度，未證實為 production 缺陷。
- **命名漂移未動**：view model 欄位實作為 `delegated_today`，方針 P4-C（`開發設計方針.md` line 802）寫的是 `delegation_state`。本次接線 A 未改此欄位名（不在指定範圍，且改名會波及 `panel_builder`／`location_panel`／`card_detail`／`hand_bar`／`delegation_status` 與測試）。留待決定：改碼對齊文件，或改文件對齊碼。
- P4-D～F、P5 都仍是規格狀態；遭遇 runtime／UI 與 P5 各項系統尚未兌現。
- 本專案沒有 Art Bible，也沒有 `.venv`；目前任務不涉及素材或 Python。

## 下一個任務

**實作 P4-D 遭遇規則**：

- 開工前依 Phase 查閱規則讀 `實作規格書.md`、`開發設計方針.md`、`測試指南.md` 的 P4-D 段落，並核對 `data/SCHEMA.md` 的 encounter 契約。
- 實作遭遇狀態機、intro／round 推進、回應／錯答／丟棄／逃離與封閉拒絕矩陣，補專屬 headless 回歸。
- 保持 P4-D 範圍：先完成規則層與機器驗收，不先做 P4-E 遭遇 UI。
