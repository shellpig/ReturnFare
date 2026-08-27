# ReturnFare 交接狀態

最後更新：2026-08-27

## 目前階段

**P1～P3 已完成；P4-A～P4-D 已完成；P4-E 遭遇 UI 面板、D8／D45 生命週期接線、CardDetail 整合、F1～F6 與 N1～N6 驗收補強全數完成。全套 27 套 headless 測試全數 exit 0（含 test_p4e.gd 15 大項整合測試），全套 UI Sim（85 契約、108 變體與負向測試）全數 exit 0（0 failed checks）。**已通過 verifier 三輪複驗關門：`測試指南.md > P4-E` 七條全打勾、`PROJECT_BRIEF.md` 轉 ✅、K-153～K-164 結案，低度殘留 K-165～K-168 留待 P4-F。**下一步 P4-F 全流程與跨輪驗收。**

- 進度與測試數字的單一事實來源是 `PROJECT_BRIEF.md`；本檔只保存最近交接重點。
- **工具變更（2026-08-27）：UI 模擬新增 `-Background`，之後跑一律加。** `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\ui_sim\run_ui_sim.ps1 -Background`。每個 Godot 行程開在獨立 Windows desktop 上，不佔畫面、不搶焦點、不碰實體滑鼠；產物與前景模式逐位元組相同（2078 張截圖與 2078 份 dump 全部 SHA256 相同）。機制與已排除的四種做法見 `開發設計方針.md > UI 模擬驗證 > 背景模式`——**那四種都實測失敗過，不要再試一次**。
- P4-A：委託／遭遇資料與 lint 真值化已完成。
- P4-B：委託規則已實作並通過 verifier 複驗，K-65 結案。
- P4-C：委託 UI、首張人物卡教學與 D17～19 處方案例已完成。
- P4-D：遭遇規則與狀態機實作完成，26 套 headless 全數 exit 0 通過。
- P4-E：遭遇 UI 面板、CardDetail 詳情整合、D8／D45 遭遇生命週期與時段推進接線完成。27 套 headless（含 `test_p4e.gd` 15 項）與 85 條 UI 契約全綠。
- P4-F：全流程整合與預算走查。
- P5：開局、四類結局、歷輪摘要、跨輪重置與 UI 已拆成 P5-A～F，尚未開始實作。

## 最近完成的工作（N1～N6 驗收補齊與重構）

1. **P4-E 規則層驗收補齊（`tests/headless/test_p4e.gd` 擴展至 15 大項）**：
   - **D8 night 直接睡／延後／地點進場被擋**：intro 與 round 階段呼叫 `sleep_night()`、`enter_night_location()`、`advance_phase()` 與 `resolve_night_advance()` 均被 `encounter_active` 攔截，狀態零變化。
   - **D8 姓名段不消耗主角卡**：R1 嘗試主角卡被拒絕 `card_not_submittable` 或 fallback 消耗其他合法卡時，主角卡仍在手牌中未被消耗。
   - **D45 直呼 escape／discard 精確回拒絕碼**：呼叫 `escape_encounter()` 回 `cannot_escape`、呼叫 `discard_in_encounter()` 回 `discard_disabled`，狀態零變化。
   - **D45 人物卡回應後仍在手**：提交 `protagonist` 後仍在 hand，未永久失去。
   - **D8 零可丟棄卡直接 failure（非容量失敗）**：手牌僅有 `protagonist`（手牌數 2，遠小於 14 容量）進入 R1 時，因無合法移動立即判定失敗，不進入容量判定。
   - **D8 後續輪 knowledge 改寫第一題**：持對應知識卡 `k_not_today` 在 R1 直接答對命中 response 進入 R2，完全不消耗手牌可丟棄卡。
   - **D8 勝／敗都回夜間「結束今晚」**：勝／敗結算後均停在 Day 8 Night，夜間推進狀態正常，呼叫 `resolve_night_advance()` 成功推進至 Day 9 Morning。
   - **第二輪 D8 不重收費經由真實 `end_run()`**：第一輪走完 D8（扣費 1 瘋狂值，寫入 `night_locations_seen`），呼叫真實 `end_run("truth")` 跨輪，第二輪 D8 `play_night_fixed()` 不再扣費。

2. **N1｜新增 `.gitattributes` 與全檔 LF 規範化**：
   - 根目錄新增 `.gitattributes`（`* text=auto eol=lf`），將 `ch3_d39_d45.json`、`make_states.gd` 等所有受影響檔案統一為 LF，徹底消除 1800 行 CRLF 換行噪音。

3. **N2｜`scenes/main.gd` 路由去重構**：
   - 將 `_route_view()` 與 `_route_view_after_encounter()` 統一合併為 `_route_view(encounter_lines = PackedStringArray())`，消除 85 行複製貼上代碼；所有時段分支均保留 `active_encounter` 遭遇攔截防護與 FlowText 出口文字保留。

4. **N3｜`開發設計方針.md` 同步容量分歧規則**：
   - 明確記錄容量判定兩套語意契約：`blocked_slots > 0`（如 D8）以可用格數判定容量耗盡；`blocked_slots <= 0`（如 D45 `per_round_slot_cost: 0`）僅在手牌超載（`is_overloaded()`，手牌數超過 14 張）時判定失敗。

5. **N4｜`p4e_03` 知識卡斷言強化**：
   - 移除弱化 `if` 守衛，強制斷言 `assert_true(not k_cands.is_empty())` 並斷言帶有 `（知識）` 標記。

6. **N5｜清理 `_coda_jump` 死碼分支**：
   - 移除無效的 `if/else: _advance(tree)` 分支，直接走遭遇確認與回應路徑。

7. **N6｜變異測試自檢（守則 5）**：
   - **F2 變異**：暫時移除 `_check_encounter_capacity_failure()` 中的 `is_overloaded()` 分支，D45 滿手 14 張時 `test_p4e.gd` 立即精確轉紅（`[FAIL] D45 with full 14-card hand should NOT fail capacity`，exit 1）；還原後 exit 0 全綠。
   - **D8 零可丟棄卡直接失敗變異**：暫時繞過 `acknowledge_encounter_intro()` 中的 `has_legal_moves` 檢查，`test_p4e.gd` 立即轉紅（`[FAIL] Encounter should immediately settle as failure due to zero legal moves`，exit 1）；還原後 exit 0 全綠。

## 驗證狀態

- **Headless 測試**：`tests/run_all_headless.ps1` 包含的 27 套 headless 測試全部 exit 0 通過。
- **UI Sim 測試**：`tests/ui_sim/run_ui_sim.ps1` 執行 108 variants、85 catalog contracts、85 executed contracts、85 completed contracts、0 failed checks，exit 0 全綠。

## 目前風險

- 無已知阻斷性缺陷。全套 headless 與 UI sim 全綠。

## 下一個任務

**P4-E 已由 verifier 關門（2026-08-27）。下一步：P4-F 全流程與跨輪驗收**。開工前先讀 `驗證後已知問題.md` 的 K-165～K-168（四條低度殘留，均指定在 P4-F 一併處理）。
