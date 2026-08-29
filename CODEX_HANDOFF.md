# ReturnFare 交接狀態

最後更新：2026-08-29

## 目前狀態

**P5-C（四類結局與組合後日談）最後一筆死亡主詞修正完成，實作面已無已知 blocker 或非阻擋缺口。** 三位 proxy 的首見／重見頁均明確由「那個走出山泉閣的人」病逝，不再把死亡語意接到阿婕／阿薇／阿財；待 Verifier 做文件關門。

實作者第四輪修復與自跑證據（2026-08-29）：

- **P5C-V5（Blocker 已修復：不邀時間軸修復）**：`data/endings.json` 修正 `partner_none_long` 僅敘述「他沒有結婚，一個人過完二十年。」；將主角四十出頭癌症早死移至 `uninvited_proxy` 各 NPC 條目中（`proxy_ajie_long`、`proxy_awei_long`、`proxy_acai_long`），在「很多年後的一張照片……」回顧之後接「四十出頭。癌症，走得很快。」，最後接 `long_return` 黑畫面與庇佑發動。消除主角死後又看生前照片之時間順序矛盾。
- **P5C-V6（關門測試缺口與變異已修復）**：`tests/headless/test_p5c.gd` 包含 `s1`～`s6` 獨立 3→4 邊界測試與 4 條 high 生計規則 `count_at_least.of` 的 6 條件結構斷言。完成 `s5`（M-C7）與 `s6`（M-C8）分別移除的變異測試，均精確轉紅（4 個斷言失敗，exit 1），還原後重回 exit 0。
- **P5C-V7（非阻擋已修復：存檔 Variant 與 Lookup Ref 交叉校驗）**：`scripts/autoload/game_state.gd` 的 `_parse_ending_snapshot()` 不僅驗證 3 個 variant 欄位合法性及與 `page_refs` 一致性，更擴充驗證 `lookup_fragments`：提取 lookup_value 與 `when_group`，交叉驗證必須與 snapshot 的 `festival_proxy_npc` 及 `partner_variant` 嚴格一致；若有矛盾回 `invalid_save_shape` 且狀態零變化。
- **測試與矩陣覆蓋**：`test_p5c.gd` 12 組全綠（exit 0）。
- **全套迴歸**：31 套 headless 全數 exit 0；UI sim run `20260829-141401-422-p74208-e6424f96`：108 variants／85 catalog contracts／85 executed／85 completed／0 failed checks。
- **變異記錄**：新增 M-C7（移除 s5 條件，4 斷言失敗，exit 1）、M-C8（移除 s6 條件，4 斷言失敗，exit 1）、M-C9（proxy lookup 快照矛盾，1 斷言失敗，exit 1）。

最後一筆主詞修正與自跑證據（2026-08-29）：

- `data/endings.json` 的 `proxy_ajie`／`proxy_awei`／`proxy_acai` 長版明示「至於那個走出山泉閣的人」，短版明示「那個走出山泉閣的人在四十出頭病逝」；不新增 NPC 死亡結果，也不提早揭露替換者身分。
- `test_p5c.gd` 逐一解析三位 proxy 的首見與重見共 6 個正式頁面，斷言 NPC 仍在回顧文字中，死亡主詞則精確切回走出山泉閣的人。
- `test_p5c.gd` 12 組 exit 0；31 套 headless（含 `verify_data`、greedy）全數 exit 0；UI sim run `20260829-143245-094-p36912-2d0e76af` 為 108 variants／85 contracts／0 failed checks。

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

## Verifier 關門結論

- `測試指南.md > P5-B` 已按三個公開 run source＋一個 opening 私有 source 重寫，並補入 D45、四類完整動作、nullable 矩陣與 Lint 20 證據。
- `d45_then::empty_handed` 的結構版草稿沒有新增世界規則或改寫角色命運，可供 prototype 使用；正式文案仍留內容期潤飾。
- 五項修正的程式、資料與斷言互相對齊，P5-B 規則／機器層可關門。

## P5-C 變異記錄

| 編號 | 變異點 | 預期失敗測試 | 實際結果 |
|---|---|---|---|
| M-C1 | `EndingResolver._pick_rule` 逆轉 rules 遍歷順序 | `test_p5c` (生計/修繕優先序) | 轉紅（9 斷言失敗，exit 1） |
| M-C2 | `EndingResolver.resolve` 略過 `has_seen_ending` 強制 `is_first_seen := true` | `test_p5c` (首見/重見/BE/不上車) | 轉紅（11 斷言失敗，exit 1） |
| M-C3 | `EndingResolver.resolve` 略過 lookup fragments 的 `when_group` 門控 | `test_p5c` (未邀代付片段啟用) | 轉紅（1 斷言失敗，exit 1） |
| M-C4 | `GameState._build_ending_plan` 破壞不上車快照 `ended_day` 為 1 | `test_p5c` (不上車快照 null 斷言) | 轉紅（1 斷言失敗，exit 1） |
| M-C5 | `data/endings.json` 反轉 uncle_high 開關門檻為 n: 7 | `test_p5c` (12 格生計開關帶矩陣) | 轉紅（6 斷言失敗，exit 1） |
| M-C6 | `EndingResolver._pick_rule` 移除多 fallback 防禦檢查 | `test_p5c` (Resolver 壞資料防禦) | 轉紅（1 斷言失敗，exit 1） |
| M-C7 | `data/endings.json` 移除 uncle_high 的 s5 條件 | `test_p5c` (獨立開關邊界與結構斷言) | 轉紅（4 斷言失敗，exit 1） |
| M-C8 | `data/endings.json` 移除 uncle_high 的 s6 (switch_progress_at_least) 條件 | `test_p5c` (獨立開關邊界與結構斷言) | 轉紅（4 斷言失敗，exit 1） |
| M-C9 | `GameState._parse_ending_snapshot` 移除 lookup ref 交叉驗證 | `test_p5c` (快照與 lookup ref 矛盾防禦) | 轉紅（2 斷言失敗，exit 1） |

## P5-C 第一輪 verifier 待修任務單（P5C-V1～V4）

### P5C-V1（blocker，已修）生計完全漏掉六開關帶

- **證據**：`data/endings.json` 的 livelihood 只有 `uncle`／`boss`／`zhou`／`none` 四條，只讀 `accepted_inn`／`accepted_outside_job`／`accepted_job`；沒有任何 `switch`、`switch_progress_at_least` 或 `count_at_least`。`test_p5c.gd` 同樣只排列四個生計旗標。
- **違反契約**：`實作規格書.md > 十五、結局流程／P5-C`、`開發設計方針.md > P5-C`、`data/SCHEMA.md > endings.json` 與 `subdocs/故事線/故事線_第一輪_第三章.md > 槽二：生計` 都要求同一生計再分 0–1／2–3／4–6 三個開關帶，variant id／when 必須承載結果，不另存第四個 history 欄位。
- **影響**：四條生計的 12 格人生結果被壓成 4 格。旅館應關閉／縮小／撐住／做起來，以及叔叔是否死在診所或主角手上，都不會反映本輪六個經營選擇；P5-F 的開關帶組合驗收也無法成立。
- **建議修法**：用現有 `count_at_least` 計算六個條件（`s1`～`s5` 與 `switch_progress_at_least(s6, 3)`），把每條生計展開為 high（4–6）／mid（2–3）／low（0–1）的有序 rule 與穩定 variant id；保留「叔叔 → 前老闆 → 周先生 → 皆無」主優先序，文字逐格對齊第三章 4×3 表。
- **必要反證**：測試至少各造 0、1、2、3、4、6 個開關，覆蓋四條生計共 12 格；同時成立多生計仍只取高優先者。暫時拿掉開關帶條件或把門檻反轉時，對應矩陣測試必須精確轉紅。

### P5C-V2（blocker，部分修復；殘留轉 P5C-V5）正常首見長版提早揭露核心真相且時間順序倒置

- **證據一**：`data/endings.json` 的首頁直接寫「你被留在了這裡，而另一個你……走出了山泉閣」，由旁白替玩家確認誰被留下、誰是另一個，違反企劃「第一輪只感到不對勁、不解釋替換；第二輪才知道後日談是別人的人生」。
- **證據二**：現行組裝順序是 partner → livelihood → inn → suffix；阿婕／阿薇 partner 頁已先寫她四十出頭癌逝，後面才寫生計、旅館狀態與「二十年」，與第三章長版骨架「生計 → 婚姻 → 二十年 → 她先死 → 主角死亡」相反。
- **影響**：首輪核心錯愕被直接解謎；有邀請的兩條長版後日談時間線不連貫，未通過 `測試指南.md > P5-C` 的真人閱讀條目。
- **建議修法**：首見 prefix 改成只呈現可觀察畫面，不命名原件／替換者；重見摘要可保留較明示語氣。重新安排 group／page 內容，讓四條生計與旅館狀態先落地，再播婚姻、二十年與兩次死亡；若更動 group 順序，同步修正 `data/SCHEMA.md` 的單一事實來源。不得新增 lore 或改寫既定角色命運。
- **必要驗收**：至少實播有邀阿婕、有邀阿薇、不邀三條正常長版並逐頁記錄；確認沒有「另一個你／替換者」等過早定論、沒有死亡後才倒回二十年前的順序，也沒有缺頁／重頁／空白頁。

### P5C-V3（非阻擋，已修）四類 ready-to-complete 測試實際只跑三類

- **證據**：`test_p5c.gd::_test_8_lifecycle_ready_to_complete_and_atomicity()` 的 `cases` 只有 `ending_replaced`、`ending_madness_be`、`ending_inventory_be`；不上車只驗快照與文字，沒有走 reveal／advance／skip 到 `ready_to_complete`。
- **建議修法**：opening mode 以私有 helper 建立首見與重見不上車快照，首見逐頁走到末頁才 ready，重見另驗合法 skip；揭露前與非末頁都必須 false。

### P5C-V4（非阻擋，已修）resolver 未完全兌現壞資料 `data_conflict` 防禦

- **證據**：`EndingResolver._append_pages()` 把 `null` 當合法空陣列，故 composite 必填的 prefix／suffix／variant page 欄遺失時可能繼續組裝；`_pick_rule()` 遇多 fallback 只保留第一筆。正式 JSON 目前會被 lint 17 擋住，所以不是現行玩家路徑 blocker，但與方針「引用缺漏或零／多個最終選擇回 data error」不一致。
- **建議修法**：由呼叫端區分選填容器與必填 page 陣列；必填欄缺失／錯型別直接 `data_conflict`。rule 掃描同時驗恰一個 fallback 與項目形狀，不靜默跳過壞項目。
- **必要反證**：獨立合成 loader 分別刪 prefix、刪 suffix、刪 variant page 欄、建立多 fallback，四例都必須由 resolver 本身回 `data_conflict`，不能只靠 lint 測試代勞。

### 修復後 verifier 重驗範圍

1. `test_p5c.gd` 新增上述 4×3 開關帶矩陣、不上車完成門檻與 resolver 壞資料案例，並對關鍵接線做變異驗證。
2. 逐頁閱讀正常三條代表路徑、兩種 BE 與不上車首見／重見，記錄資訊揭露與時間順序。
3. 重跑 `verify_data`、`test_p5c`、31 套以上全 headless、greedy 與 UI sim；回報當時 catalog 實際數字。
4. 全部通過後才由 verifier 更新 `測試指南.md`、`驗證後已知問題.md`、`PROJECT_BRIEF.md`，依固定流程同 turn commit＋push 關門 P5-C。

## P5-C 第二輪 verifier 待修任務單（P5C-V5～V7，2026-08-29）

### P5C-V5（blocker）阿婕／阿薇長版漏掉「她先死」的既定結果

- **證據**：`data/endings.json` 的 `partner_ajie_long`／`partner_awei_long` 現在只剩結婚與沒有小孩；共用 suffix 只寫主角四十出頭癌逝。`subdocs/故事線/故事線_第一輪_第三章.md > 尾巴：四十幾歲` 明定邀請路徑必須先播「她先，癌症」，再播「然後是他，同一個病」。
- **影響**：有邀阿婕／阿薇的兩條正常長版少掉承重線索——取走順序就是死亡順序；第三章明列的既定角色結果被省略，P5C-V2 仍未完整關閉。
- **建議修法**：維持目前 livelihood → inn → partner 的前半順序；把「二十年＋她先死」放入阿婕／阿薇的 long partner 內容，無伴侶 long 則放「二十年獨居」，移除共用 `years_passed`；共用 `long_return` 只接主角因同一病死亡與庇佑回歸。也可採其他資料形狀，但不得重新提早揭露替換真相或改角色命運。
- **必要驗收**：逐頁走阿婕、阿薇、無伴侶三條首見長版；兩條有邀請路徑都必須依序包含婚姻／無子 → 二十年 → 她先癌逝 → 主角同病死亡，無伴侶路徑不得誤播「她先」。對應文字或條件暫時拿掉時，測試必須轉紅。

### P5C-V6（關門測試缺口）六開關矩陣沒有獨立守住 s5／s6

- **證據**：`test_p5c.gd::_set_switches()` 只建立 s1 → s6 的連續集合；所有 high 邊界案例在 count=4 時已靠 s1～s4 達標。若從 livelihood rules 的 `of[]` 刪除 s5 或 s6，count=4／6 仍是 high，count=2／3 仍是 mid，count=0／1 仍是 low，現有矩陣與 M-C5 都不會證明這兩條接線。
- **影響**：正式資料目前六個條件都在，但回歸測試允許第 17 天開關或叔叔累計開關日後靜默失效；不符合專案「每條關鍵接線移除時對應測試必須轉紅」的變異保真規則。
- **建議修法**：為 s1～s6 各造一個獨立的 3→4 邊界案例——三個其他開關時為 mid，加上被測開關後必為 high；s6 必須真的以 `switch_progress.s6 = 3` 參與。可另加正式 livelihood rule 的 `of[]` 精確六條結構斷言作第二層。
- **必要反證**：分別暫時刪除 s5、刪除 s6 條件，兩次都必須讓各自專屬測試精確轉紅；還原後 targeted 與全套重回 exit 0。

### P5C-V7（非阻擋，P5-D 前置）deserialize 不驗 variant 值與 page refs 是否一致

- **證據**：`GameState._parse_ending_snapshot()` 只驗 composite 的三個 variant 欄非 null，沒有確認值是對應 `variant_groups[].rules[].id`。`livelihood_variant: "uncle"` 或任意字串可以搭配 `uncle_high` page refs 通過；P5-D 若直接寫 history，會保存互相矛盾的摘要。
- **影響**：目前沒有正式存檔 UI，正常 runtime 產出的 snapshot 正確，因此不阻擋 P5-C 玩家路徑；但 P5-D 即將把 snapshot 寫進 append-only history，屆時壞值會永久進 meta。
- **建議修法**：deserialize 由 ending 資料建立 group → rule id 集合，驗三個 variant 值存在；再驗 page refs 中各 variant group 的 rule id 與 snapshot 欄位一致。linear ending 維持三欄 null。
- **必要反證**：未知 variant id、合法但與 page refs 不同的 variant id 各回 `invalid_save_shape`，完整 serialize 零變化；合法快照往返仍逐字相同。

## 已知殘留

- K-193：`last_auto_enter_lines` 尚未接進 `main.gd`；D45 邀請效果成立但文字可能看不到，歸 P5-D transition lines 接線。
- K-194：UI `full_walk` 仍優先取得 D13 名冊，空手 coda 尚無真實輸入 UI 證據，歸 P5-E／F。
- K-195：`choice_requires_card` 仍建立直接選擇按鈕，且持名冊時空手選項仍顯示，歸 P5-E UI 收斂。
- K-196：✅ `test_p5b.gd.uid`／`test_p5c.gd.uid` 已進版控。
- K-197：✅ 已於 P5-C 由 implementer 修復。
- K-198：`clone_for_preflight()` 未檢查 `deserialize()` 回傳值；下次動 preflight 時補防禦。
- K-183：`repeat_page_ids` 尚未納入 fragment 的 `repeat_pages`；現行 `skip_to` 指 suffix，不受影響
- K-190：舊壞資料 fixture 缺 P5 新必填欄位；下次動 fixture 或 lint 19 時處理
- K-191：P5-A 首次交付的大面積 JSON 重排只記紀律，不回頭重排
- P4-E／P4-F：K-165 ①、K-175、K-176、K-177 四條低度殘留
- 人工體感：P3-F 與 P4-F 合計 8 項待真人落檔
- `lose` 的 `permanent` 與 `loop_persistent_item_ids` 只有結構，尚未接行為（依方針屬 P5-D）

## 下一個最安全任務

**交由 Verifier 關門 P5-C。** 依既定分工更新 `測試指南.md`、`驗證後已知問題.md`、`PROJECT_BRIEF.md`，完成文件關門後同 turn commit＋push；下一個實作階段才是 **P5-D 開局、歷輪摘要與跨輪重置**。

> 跑 UI 模擬一律加 `-Background`：
> `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\ui_sim\run_ui_sim.ps1 -Background`
