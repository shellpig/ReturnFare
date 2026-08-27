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

- **P4-D 遭遇規則實作完成（最新，待 verifier 複驗與打分）。**
  - **核心模組建立 (`scripts/core/encounter.gd`)**：
    - 建立 `Encounter` 類別，負責遭遇純判斷、Graph 節點查找、Response 匹配、合法動作求值（`has_legal_moves`）與 View Model 構建（`build_view`）。
    - 嚴格落實資料封裝與無狀態設計（runtime 狀態皆由 `GameState.active_encounter` 持有）。
    - `build_view()` 絕不外洩未達到的 round 或正解 `accepts` / `fallback` 結構。
  - **GameState Autoload 遭遇狀態機與 API 實作 (`scripts/autoload/game_state.gd`)**：
    - `active_encounter: Dictionary`：追蹤當前遭遇狀態 `{ beat_id, stage, round_id, blocked_slots, attempted_card_ids }`。
    - `is_overloaded() -> bool`：純查詢 `hand_slots_used() > int(Data.tuning("hand_size", 14))`。
    - **5 大遭遇操作 API**：
      - `start_encounter(beat_id) -> Dictionary`：檢查 active → unknown beat → data conflict，成功時 stage 為 `"intro"`，`blocked_slots = 0`。
      - `acknowledge_encounter_intro() -> Dictionary`：檢查 inactive → wrong stage → data conflict，超載時加收 penalty cost，進入第一 round（`blocked_slots += cost`），若可用格歸零或無合法解自動結算 failure。
      - `encounter_view() -> Dictionary`：提供給 UI 或走查的安全 View Model。
      - `respond_to_encounter(card_id) -> Dictionary`：檢查 inactive → wrong stage → unknown card → not held → madness → attempted → card not submittable → data conflict。正解命中釋放本回合 cost、套用 on_resolve；錯答保留 cost、若要求 discardable 則檢查扣卡並轉入 fallback；若為最後回合則走 victory/failure 結算。
      - `discard_in_encounter(card_id) -> Dictionary`：檢查 inactive → wrong stage → discard disabled → unknown card → not held → not discardable。扣除卡片、不改 blocked_slots、不推進回合。
      - `escape_encounter(card_ids: Array[String]) -> Dictionary`：檢查 inactive → wrong stage → cannot escape → wrong count → duplicate payment → unknown card → not held → not discardable → data conflict。扣除卡片並套用 on_escape 結算。
    - **15 碼封閉拒絕代碼與固定優先順序**：
      - `encounter_active`, `no_active_encounter`, `wrong_stage`, `unknown_beat`, `unknown_card`, `not_held`, `madness_blocked`, `already_attempted`, `card_not_submittable`, `discard_disabled`, `not_discardable`, `cannot_escape`, `wrong_escape_count`, `duplicate_payment`, `data_conflict`。
    - **既有 API 升級與阻擋接線**：
      - `advance_phase() -> Dictionary`：遇活躍遭遇時拒絕推進（`{ ok: false, reason_code: "encounter_active", phase_advanced: false }`）；白天時段切換時自動掃描應觸發之定日 fixed encounter（如 D45 afternoon）；夜間 fixed beats 仍走 `play_night_fixed()` 流程。
      - `try_place()`, `choose()`, `delegate()`, `indulge()`, `confirm_night_alignment()`, `enter_night_location()`, `resolve_night_advance()` 全面加入 `encounter_active` 阻擋。
      - `enter_night_location()` 加入 `overloaded` 檢查阻擋。
    - **序列化與健全度**：
      - `serialize()` 與 `deserialize()` 完整保存／還原 `active_encounter`。
      - `end_run()` 完整清空 `active_encounter`。
  - **自動化測試套件 (`tests/headless/test_p4d.gd`)**：
    - 撰寫 12 大測試組，完整涵蓋 測試指南 P4-D 的 14 項驗收標準：
      1. 遭遇啟動與開場確認（intro 階段 blocked_slots=0，acknowledge 後進入 round 1 blocked_slots=1）
      2. 遭遇進行中時段與各類操作阻擋（advance_phase, try_place, choose, delegate, indulge, enter_night_location 等）
      3. 15 碼封閉拒絕代碼矩陣
      4. 拒絕優先順序驗證（如 madness_blocked > already_attempted, not_night > encounter_active > overloaded）
      5. 超載規則（is_overloaded 查詢、enter_night_location 阻擋、開場 penalty 佔格）
      6. 佔格計算與扣除（正解釋放 cost、錯答保留 cost）
      7. 主動丟棄與逃離遭遇
      8. 無合法解自動結算 failure
      9. 容量上限失敗結算
      10. 遭遇勝利與結束推進（after_finish: "advance_phase" 推進時段、"stay" 停留原時段）
      11. 序列化與還原往返
      12. 故事線遭遇契約驗證（D8 n_manydoors_ch1, D45 d45_encounter）
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
