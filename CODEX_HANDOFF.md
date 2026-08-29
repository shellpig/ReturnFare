# ReturnFare 交接狀態

最後更新：2026-08-29

## 目前狀態

**P5-B 的 verifier 五項必修已全部實作完成，等待 verifier 複驗關門。尚未進 P5-C。**

第一版實作在 commit `db41ba8`；本次是依使用者拍板的決定 A1／B1／C 做的第二輪修正，詳見下方
「P5-B 五項必修：實作紀錄」。實作者自跑證據（打勾與落檔仍由 verifier 做）：

- 30 套 headless 全數 exit 0（`tests/run_all_headless.ps1`）
- `verify_data`：引用 0 錯誤、Lint 1～20 全 0 錯誤（Lint 20 為本次新增）
- `test_p5b` 新增第 11 組（四類完整動作的原子性）與第 12 組（D45 終局鏈正式資料端到端）
- `test_p5a` 新增 PE-4～PE-6（phase_exit choice group）與 LC-0～LC-4（lint 20）
- 變異驗證 25 條逐一反轉並確認精確轉紅，見下方「變異記錄」
- UI sim run `20260829-084809-561-p41632-333d0387`：108 variants／85 catalog contracts／85 executed／85 completed／0 failed checks

## P5-B 實際改了什麼

**新檔**

- `scripts/core/ending_resolver.gd`（`class_name EndingResolver`，static）：variant 規則求值、lookup fragment 命中、page ref 組裝與反解析、`skip_to` 落點。只讀資料，不寫 GameState。
- `tests/headless/test_p5b.gd`。

**`scripts/autoload/game_state.gd`**

- 新增 flow 層：`flow_mode`（`opening`／`run`／`ending`）、`active_ending`，以及 run 欄位 `opening_choice_id`／`knowledge_at_start`／`selected_festival_proxy_npc`、meta 欄位 `run_number`／`ending_history`／`loop_persistent_item_ids`。
- `start_ending()`／`ending_view()`／`reveal_ending_page()`／`advance_ending_page()`／`skip_seen_ending()`，以及純函式 `_build_ending_plan()` 與 `_commit_ending_plan()`（公開入口與 action pipeline 共用同一份驗證）。
- `_reject_unless_run()` 掛進全部 run mutation 入口（推進、放卡、choice、委託、縱慾、遭遇五個入口、夜間進入、對位、夜間推進、演出入口）。
- `advance_phase()` 改成：mode gate → active encounter → 通用 `phase_exit` 門檻 → 一般 transition。D45 的 `end_run()` stub 退場，改由 `phase_exit` 的 `ending`／`source` 啟動 `ending_replaced`，day／phase 不動、run 不清。
- `_settle_effects()` 成為所有效果的唯一結算入口：preflight（複本模擬）→ 驗 action bookkeeping 與結局快照 → commit（effects → bookkeeping → ending）。`play_beat`／`choose`／`try_place`／`indulge`／強制縱慾／委託／委託回報／遭遇 on_resolve 與三種出口全部改走這條。
- `_check_madness_cap()` 改成啟動 `ending_madness_be`；`simulation_mode` 的複本只記錄請求。
- `serialize()` 新增 `flow` 區塊與上述欄位；`deserialize()` 改回傳 `{ok, reason_code}`，原子驗完形狀才寫入，壞形狀回 `invalid_save_shape` 且零變化；無 `flow` 的舊 checkpoint 一律遷移成 run＋active null，並以載入當下的 meta knowledge 當 `knowledge_at_start`。

**`scripts/core/effect_apply.gd`**

- `apply()` 退場，改為 `preflight(blocks, gs)`／`commit(plan, gs)`；plan 是有序 op 陣列，模擬與 commit 共用同一個 `_apply_op()`。
- `festival_proxy` 真的落地（fixed／highest_eligible 都在 preflight 求值後寫進 plan），非 Dictionary、非候選 NPC、已凍結覆寫一律 `data_conflict`（K-182 收斂）。
- `ending` 效果只提出 request，不自己呼叫 `start_ending()`；同一 action 兩個不同 request 回 `data_conflict`。

**`scripts/data_loader.gd`**：lint 17 新增「同一效果塊不得同時有 `madness` 與 `ending`」（正式資料先擋雙 request，runtime preflight 是第二道防線）。

**`scenes/main.gd`**：刪掉 `d45_then::compare_registry` 與 `jinghe_back` 硬編碼，改讀 `GameState.phase_exit_status()`；evening 是否走 coda 面板也改用通用門檻判斷，不再特判第 45 天。

## 這一階段動到的既有測試（契約變更，不是修紅）

`end_run()` 的跨輪重置在 P5-B 仍保留為 legacy API（P5-D 才由 `complete_ending()` 取代），但**發狂上限與 D45 coda 不再呼叫它**，因此下列測試改為「先驗結局狀態機、再以 legacy `end_run()` 做跨輪重置驗收」：

- `test_game_state_p1a`：D45 evening 改驗門檻未完成 → `phase_requirements_incomplete`，完成後進 ending mode 且 day／phase 不動。
- `test_p1f`：coda 與 `run_ended` 恰一次兩組。
- `test_p2d`：撞 cap 後 run 不清、四張卡留在本輪；走查結局改為 `ending_replaced`。
- `test_p3b`／`test_p4a`：撞 cap 進 ending mode，meta seen 照常保留。
- `test_p4b`（K-65）：同一筆 report 的 `madness`＋`flag` 屬於同一個動作，flag 現在會落地；跨筆 report 的迴圈中斷不變。
- `test_p4d`：K-133 改驗「結局啟動後不得再推進時段」；K-139 對照組補清 `knowledge_at_start`。
- `test_p1e`：`_reset_gs` 補清 `selected_festival_proxy_npc`（一輪只能凍結一次）。
- `test_p1d`：改用 preflight／commit 取代 `EffectApply.apply()`。
- `playthrough_greedy`／`test_p2_sim`／`test_p3f`：終局數字改在走查結束時直接取，不再依賴 `run_ended`。

## P5-B 五項必修：實作紀錄（2026-08-29 第二輪）

依使用者拍板的決定 A1／B1／C 施作，順序 5 → 4 → 3 → 2 → 1。每一項都補了負向案例與變異驗證。

### 5. 公開 `start_ending()` 只收 run 來源

`game_state.gd` 新增 `RUN_ENDING_SOURCES`（`madness_cap`／`ending_effect`／`d45_coda`）。
`_build_ending_plan()` 加第四個參數 `allow_opening_source`（預設 false），檢查點排在 source 配對之後，
因此 `unknown_ending` 仍先於 `invalid_ending_source`。P5-D 的 `_start_ending_from_opening()` 屆時傳 true 借道同一 helper。

**兩道 source 檢查刻意分開**：一道擋錯配、一道擋「配對正確但不是 run 來源」，兩道都回 `invalid_ending_source`。
`test_p5b` 第 9 組因此改成：合法成功只認前三個 run 來源，第四組在 run 中必須原子拒絕；
另用 `get_script_constant_map()` 驗第四組配對仍留在封閉表裡，供 P5-D 使用。

### 4. `deserialize()` 的 ending-specific 矩陣

依決定 C **只收 `flow`／`active_ending`**，run／meta 不做全面型別驗證（那會擋掉現有手寫 fixture）。
`_parse_ending_snapshot()` 新增：

- variant 欄有值 ⇔ 該 ending 真的有同名 variant group（讀 `endings.json`，不寫死 ending id 清單）
- 代付者：`ending_replaced` 必須是已凍結的正式候選；不上車一律 null；兩種 BE 有值就得是候選
- 不上車：`ended_day`／`ended_phase` 必須為 null，其餘三個結局必須非 null
- 不上車的 `opening_choice_id` 必須等於資料中指向它的那個開局選項（`_opening_choice_for_ending()`，不寫死字串）
- page ref 必須屬於本 ending，且全部同一個 branch（`resolve_ref` 只驗「可解析」，擋不掉指向別的 ending）
- `ready_to_complete` ⇔ 頁碼在末頁且已揭露（雙向都擋）

`flow` 的驗證本來就在任何寫入之前完成，因此決定 C 的範圍內已經是 candidate-then-commit。

### 3. 完整玩家動作的原子性

`_settle_effects(blocks, bookkeeping, pre_bookkeeping)` 新增第三個參數。`pre_bookkeeping` 是「這個動作的代價」，
先落在來源複本上（效果因此看得到扣卡、扣格、遭遇轉態），成功後才與效果一起 commit。
`_apply_bookkeeping()` 新增 `action_cost`／`lose_cards`／`indulgence_delta`／`forced_pop`／`report_removed`／`encounter_set`。

四條漏網路徑改法：

- `indulge()`：行動格、卡片（含泡湯多張）、次數併進 `pre_bookkeeping`。強度級改用「含這一次」的次數計算。
- `_settle_forced_indulgence()`：不再先 `pop_front()`，改用 `forced_pop`。結算失敗時債原樣留在 `forced_pending`。
- `_settle_pending_delegation_reports()`：不再整份覆寫 pending；每一筆用 `report_removed` 隨自己的效果一起出列。
- 遭遇：`respond_to_encounter()` 改成 `_plan_encounter_response()`（複本推演整回合）＋ `_commit_encounter_action()`。
  `on_resolve` 與同一次的出口效果併成同一批 blocks，因此雙 ending request 會被 preflight 抓到並整個動作拒絕。
  `acknowledge_encounter_intro()`／`discard_in_encounter()`／`escape_encounter()` 走同一組 helper。
  `_finish_encounter()` 與 `_settle_encounter_effect()` 因此退場。
  **`after_finish: advance_phase` 留在原子區塊外**，不讓 commit 裡跑一個可能失敗的推進。
  容量與死局判定原本跑在 `on_resolve` 之後的真狀態上；合併成單一 plan 後，複本上也要先把 `on_resolve` 套下去才判定，
  否則換回合會用錯的手牌張數算容量。這條有自己的斷言與變異（M-Z）。

### 2. D45 終局鏈成為時段生命週期（決定 A1）

- SCHEMA 新增 beat 欄位 `auto_enter`（只供 `fixed:true`）。`advance_phase()` 進時段時自動 `play_beat()`，
  順序在固定遭遇檢查之前。`d45_morning_invitation` 標上此欄，`final_day` 因此不再依賴玩家開山泉閣。
- 第二道防線：`advance_phase()` 在 `day == LAST_DAY and phase == "evening"` 一律拒絕離場。
- **Lint 20（新）**：`auto_enter` 只能掛 `fixed:true`；帶 `phase_exit` 的 beat，其 condition 依賴的每個 flag
  都必須有更早的 `auto_enter` beat 寫入。已接進 `verify_data.gd`。
- 演出文字收在 `last_auto_enter_lines`（transient UI），**目前沒有接進 `main.gd`**——見下方待辦。

### 1. D45 未持名冊的替代 coda（決定 B1）

- `d45_then` 兩槽同屬 `choice_group: "d45_coda"`：`compare_registry`（收 `info_registry`，維持 `k_already_on_list` 升級）
  ＋ 新增 `empty_handed`（`accepts: []`，**什麼都不給**：不發旗標、不發知識）。
- `phase_exit` 改成 `required_choice_groups: ["d45_coda"]`。SCHEMA 的 `phase_exit` 因此支援兩種門檻形態，
  至少一個非空；`_phase_exit_gate()` 對 choice group 查 `choices[beat::group]`。
- 比對槽補上 `choice_requires_card: true`。沒有這一條，玩家可以直接按「選擇：名冊上你自己那一格」
  在沒有名冊的情況下結算選擇組——那會多出一條看起來像比對、實際上什麼都沒升級的第三條路。
- lint 17 的 phase_exit 檢查擴充：group 引用、重複、兩種形態皆空。
- `playthrough_greedy` 的 `PRIORITY_SLOTS` 已刪除。走查現在自然錯過第 13 天的名冊，
  走空手路收尾（實測 `coda_path: empty_handed`），跨輪保留的是 `k_not_today`。

## 這一輪動到的既有測試（契約變更）

- `test_game_state_p1a`：D45 門檻改設 `choices["d45_then::d45_coda"]`；45 天時間軸測試每步先清 `active_encounter`
  （D45 afternoon 現在必定自動起遭遇）。
- `test_p1f`：`run_ended` 恰一次那組改設 choice group。
- `test_p5a`：`d45_then` phase_exit 契約改驗 `required_choice_groups`；新增 PE-4～PE-6 與 LC-0～LC-4。
- `playthrough_greedy`：知識卡斷言改成「保留的那張要對得上本輪真的走的 coda 路徑」。

## 變異記錄（第二輪 25／25 精確轉紅）

每一條都是「暫時關掉該接線 → 跑對應測試 → 確認轉紅 → 還原」，還原後基準線重跑 exit 0。

| # | 變異點 | 對應測試 | 結果 |
|---|---|---|---|
| M-A | `_build_ending_plan()` 拿掉 run-source 檢查 | `test_p5b` | exit 1（12 種錯配仍綠，只有第四組轉紅） |
| M-B | 快照 variant 矩陣失效 | `test_p5b` | exit 1 |
| M-C | 快照代付者矩陣失效 | `test_p5b` | exit 1 |
| M-D | 不上車結束日矩陣失效 | `test_p5b` | exit 1 |
| M-E | page ref 歸屬檢查失效 | `test_p5b` | exit 1 |
| M-F | page ref branch 一致性失效 | `test_p5b` | exit 1 |
| M-G | `ready_to_complete` 一致性失效 | `test_p5b` | exit 1 |
| M-H | 不上車開局選項比對失效 | `test_p5b` | exit 1 |
| M-I | 代價改回「先改真狀態再 preflight」 | `test_p5b` | exit 1 |
| M-J | 出口效果不併進同一批 blocks | `test_p5b` | exit 1 |
| M-K | `report_removed` 不生效 | `test_p5b` | exit 1 |
| M-L | `forced_pop` 不生效 | `test_p2c` | exit 1 |
| M-M | `lose_cards` 不生效 | `test_p5b` | exit 1 |
| M-N | `action_cost` 不生效 | `test_p5b` | exit 1 |
| M-O | `indulgence_delta` 不生效 | `test_p5b` | exit 1 |
| M-P | `encounter_set` 不生效 | `test_p5b` | exit 1 |
| M-Q | `auto_enter` 進場鉤子失效 | `test_p5b` | exit 1 |
| M-R | D45 evening 第二道防線失效 | `test_p5b` | exit 1 |
| M-S | `required_choice_groups` 門檻失效 | `test_p5b` | exit 1 |
| M-T | lint 20 缺寫入者檢查失效 | `test_p5a` | exit 1 |
| M-U | lint 20 時序檢查失效 | `test_p5a` | exit 1 |
| M-V | lint 20 fixed 檢查失效 | `test_p5a` | exit 1 |
| M-W | lint `required_choice_groups` 引用檢查失效 | `test_p5a` | exit 1 |
| M-X | lint「兩種門檻皆空」檢查失效 | `test_p5a` | exit 1 |
| M-Y | greedy 空手收尾路徑失效 | `playthrough_greedy` | exit 1 |
| M-Z | `on_resolve` 不套到複本（容量順序回歸） | `test_p5b` | exit 1 |

> M-E 第一輪是**假綠**：原本的「page ref 指向另一個 ending」案例把 refs 換成單一元素，
> 結果是被 `ready_to_complete` 一致性那道擋掉，不是被歸屬檢查擋掉。改成只替換其中一個 ref
> （頁數、index、revealed、ready 全部不動）之後，M-E 才真的轉紅。
> 這和第一輪 M4 是同一個病：**拒絕碼相同不代表擋的是同一道檢查。**

## 走查與 UI 為了走到結局所加的暫時接線（P5-D 要拆掉）

- `playthrough_greedy` 與 UI `full_walk`：第 29 天下午若邀請組未結算，明示呼叫 `choose(..., "invite_none")` 凍結慶典代付者。**逾期預設是 P5-D 的規則層工作**，落地後這兩段要刪。
- `playthrough_greedy` 與 UI：D45 coda 未持名冊時明示 `choose(..., "empty_handed")`。P5-D 的 `default_if_unresolved` 可以直接套在 `d45_coda` 這一組上，落地後這段也能刪。
- UI `coda_full`／`full_walk`：結局啟動後以 legacy `end_run()` 銜接第二輪。
- `make_states.gd` 的 `d45_evening`／`p4e_d45_afternoon` 走查加了同一筆 D29 決策，fixture 驗證也一併要求代付者非空。

## 給 verifier 的建議（實作者不改這些檔）

- `測試指南.md > P5-B` 第 9 條：「四組合法 source ↔ ending 各成功一次」的字面要求要改。
  收緊後只有三個 run 來源會在 runtime 成功；第四組由資料層配對（lint 17）＋ run 中的原子拒絕證明。
- `測試指南.md > P5-B` 建議增列：D45 只按推進的端到端案例、持名冊／未持名冊兩條 coda 路、
  四類完整動作的雙 request 原子拒絕、ending-specific nullable 矩陣。
- `d45_then::empty_handed` 的文字是結構版草稿（「你沒有那本名冊。你只是又想了一遍那句話。／蒸氣沒有散。水裡那個人也沒有再轉頭。」），
  沒有新增世界規則、沒有改寫角色命運，待 verifier 審。

## 已知殘留

- `clone_for_preflight()` 沒有檢查 `deserialize()` 的回傳值。目前所有呼叫點的來源狀態都是合法的，
  但如果哪天不是，複本會安靜地變成一個空狀態而不是報錯。這是 P5-B 第一版就在的形狀，本輪沒動。
- `last_auto_enter_lines` 尚未接進 `main.gd` 的演出流。D45 上午邀請的**效果**已經是生命週期的一部分，
  但它的**文字**目前只在玩家打開山泉閣時才看得到。屬 P5-E（開局與結局 UI）的接線工作。
- K-183：`repeat_page_ids` 尚未納入 fragment 的 `repeat_pages`；現行 `skip_to` 指 suffix，不受影響
- K-190：舊壞資料 fixture 缺 P5 新必填欄位；下次動 fixture 或 lint 19 時處理
- K-191：P5-A 首次交付的大面積 JSON 重排只記紀律，不回頭重排
- P4-E／P4-F：K-165 ①、K-175、K-176、K-177 四條低度殘留
- 人工體感：P3-F 與 P4-F 合計 8 項待真人落檔
- `lose` 的 `permanent` 與 `loop_persistent_item_ids` 只有結構，尚未接行為（依方針屬 P5-D）

## 下一個最安全任務

**等 verifier 複驗這五項並關門 P5-B，再進 P5-C。**

> 跑 UI 模擬一律加 `-Background`：
> `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\ui_sim\run_ui_sim.ps1 -Background`
