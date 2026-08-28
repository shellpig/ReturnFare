# ReturnFare 交接狀態

最後更新：2026-08-28

## 目前階段

**P1～P4 全部完成且關門；P5-A（結局、開局與跨輪資料）實作與驗證全數完成。全套 29 套 headless 測試全數 exit 0（含 test_p5a.gd 5 大項正負向測試與 verify_data.gd Lint 1～19 全綠），全套 UI Sim（85 契約、108 變體與負向測試）全數 exit 0（0 failed checks）。** 待 verifier 複驗關門 P5-A。**下一步 Phase 5-B（頂層流程與結局狀態機）。**

- 進度與測試數字的單一事實來源是 `PROJECT_BRIEF.md`；本檔只保存最近交接重點。
- **工具變更（2026-08-27）：UI 模擬新增 `-Background`，之後跑一律加。** `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\ui_sim\run_ui_sim.ps1 -Background`。
- P5-A：結局、開局與跨輪資料已實作完成，Lint 17（結局完整性）、Lint 18（開局與選擇完整性）、Lint 19（跨輪與慶典代付完整性）全數上線且 0 錯誤。嚴格遵守「不接新玩家操作／UI mutation」限制。
- P5-B：頂層流程與結局狀態機（待 P5-A 關門後開工）。

## 最近完成的工作（P5-A 結局、開局與跨輪資料實作）

1. **`data/opening_choices.json` 建立完成**：
   - 定義 3 筆開局選項（`take_family_album`、`return_missed_call`、`refuse_boarding`）。
   - 前兩筆提供 `on_select`，最後一筆以 `requires: { ending_seen: "ending_replaced" }` 鎖定並直接引用 `ending: "ending_refuse_boarding"`，兩類形狀互斥。

2. **`data/endings.json` 建立完成**：
   - 定義 4 筆穩定 ending id（`ending_replaced` 為 composite；`ending_madness_be`、`ending_inventory_be`、`ending_refuse_boarding` 為 linear）。
   - `ending_replaced` 包含 `first_seen`、`repeat`（`skip_to: "partner"`）、3 組有序 `variant_groups`（`partner`、`livelihood`、`inn_appearance` 各恰有 1 筆 fallback），以及 `lookup_fragments`（`uninvited_proxy` 完整覆蓋阿婕、阿薇、阿財）。

3. **`data/cards.json` 擴充完成**：
   - 64 張既有卡片全數補齊必填 `loop_persistent: false`。
   - 新增 2 張卡片：`item_family_album`（裝備、佔格、可暫存、可丟棄、`loop_persistent: false`）與 `k_i_returned`（知識、不佔格、不可暫存、不可丟棄、`loop_persistent: false`）。總卡片數達 66 張。

4. **`data/npcs.json` 擴充完成**：
   - 18 位 NPC 全數補齊必填 `festival_proxy_eligible: boolean`。正式候選精確為 `ajie`、`awei`、`acai` 3 位（其餘 15 位均為 `false`）。

5. **故事線 Beat 資料檔 P5-A 映射更新**：
   - `ch1_d04_d15.json`：D7 新增 `outside_job_waiting` 分支殘響；D11 `compare` 槽相容 `item_family_album`；D7 與 D10 分別補齊阿婕與阿薇之 `attention_npc` 反向引用。
   - `ch2_d23_d26.json`：D26 3 個修復槽正式改用 `choice_group: "repairs"` 與 `choice_requires_card: true`。
   - `ch2_d27_d32.json`：D29 `d29_pm_invitation` 配置 `festival_proxy`（邀阿婕/阿薇為 fixed，不邀槽兼任 `default_if_unresolved: true` 並配置 highest-eligible + fallback 阿婕）；新增 D31 3 筆 `festival_proxy_is` 結構版內容。
   - `ch3_d39_d45.json`：新增 D39 3 筆 `festival_proxy_is` 結構版內容；D43 兩條離開工作共用 `choice_group: "leaving"` 與 `choice_requires_card: true`；D45 `d45_then` 配置 `phase_exit`（required_slots: `["compare_registry"]`, ending: `ending_replaced`, source: `d45_coda`）。

6. **核心語彙與檢查擴充（`ConditionEval` / `EffectApply` / `DataLoader`）**：
   - `ConditionEval.KNOWN_KEYS` 增加 `opening_choice`、`ending_seen`、`festival_proxy_is`。
   - `EffectApply.KNOWN_KEYS` 增加 `ending`、`festival_proxy`，`CARD_ENTRY_KEYS` 增加 `permanent`。
   - `DataLoader` 新增 `endings`、`opening_choices` 載入與跨檔引用檢查；實作 Lint 17（`lint_endings`）、Lint 18（`lint_opening_and_defaults`）、Lint 19（`lint_loop_and_festival`）。
   - `verify_data.gd` 串接 Lint 17～19 驗證。

7. **`tests/headless/test_p5a.gd` 測試套件實作（全綠）**：
   - 涵蓋 1 大項正式資料正向斷言、3 大項共 18 條 Lint 17/18/19 負向 fixture 測試、1 大項 Source ↔ Ending 封閉配對矩陣測試。
   - 納入 `tests/run_all_headless.ps1`，全套 29 套測試全數 exit 0 通過。
   - UI Sim 85 個契約（108 個變體）全數 exit 0 通過（0 failed checks）。

## verifier 複驗後的收斂（K-178～K-181）

第一次複驗抓到 lint 17～19 有四個「規格明列但檢查沒實作」的洞，同批修畢：

1. **K-178　lint 19 的 `permanent` lose 掃描範圍不足**：`_check_permanent_lose` 原本只掃 `beat.on_enter` 與 `slots[].on_place`，漏掉 `on_place_by_level`、encounter 的 `on_resolve` 與三種出口、`delegation.report`。改為逐層走訪整份 beat。
2. **K-179　lint 17 的 beat `ending` 效果掃描漏 encounter**：`_check_beat_ending_effects` 同樣改為逐層走訪；`phase_exit` 子樹整棵跳過，因為那是結局接點不是效果，由既有的 ending/source 配對檢查負責。
3. **K-180　lint 18 沒有強制「D29 invitation 必須具有預設」**：原本只擋同組多個 default，零個不擋。新增 `REQUIRED_DEFAULT_GROUPS`，並一併驗該預設槽不得帶 `condition`／`requires`／`delegation`（SCHEMA `choice_group` 那條的「可由無卡 `choose()` 結算」）。
4. **K-181　lint 18 沒有強制「D43 兩個工作槽必須要求主角卡」**：新增 `REQUIRED_CARD_GROUPS`，驗 `leaving` 組恰兩槽、各設 `choice_requires_card:true` 且 `accepts` 只收 `protagonist`。

`test_p5a.gd` 新增第 6 大項 8 條負向斷言對應這四條（總數 30 → 38）。**變異驗證**：把四個修法逐一還原後重跑，各自恰好 2 條轉紅（6.1／6.2、6.3／6.4、6.5／6.6、6.7／6.8），既有 4.3 與 5.1 在變異下仍為綠——確認新契約由新斷言承載，不是靠舊斷言順便蓋到。

## 驗證狀態

- **資料驗證（`verify_data.gd`）**：卡片 66、地點 48、NPC 18、beat 268、ending 4、opening 3；引用檢查 0 錯誤；Lint 1～19 全部 0 錯誤。
- **Headless 測試**：`tests/run_all_headless.ps1` 包含的 29 套 headless 測試全部 exit 0 通過。
- **UI Sim 測試**：`tests/ui_sim/run_ui_sim.ps1 -Background` 執行 108 variants、85 catalog contracts、85 executed contracts、85 completed contracts、0 failed checks，exit 0 全綠。

## 目前風險

- 無已知阻斷性缺陷。全套 29 套 headless 與 UI sim 全綠。

## 下一個任務

**P5-A 實作已完成，交由 verifier 進行複驗與文件關門。** 關門後下一步依序進入 Phase 5-B（頂層流程與結局狀態機）。
