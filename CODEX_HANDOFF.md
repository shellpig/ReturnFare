# ReturnFare 交接狀態

最後更新：2026-08-28

## 目前狀態

**P5-B（頂層流程與結局狀態機）實作完成，等 verifier 複驗關門。下一步 P5-C 四類結局與組合後日談。**

P5-B 實作證據（實作者自跑，打勾與落檔由 verifier 做）：

- 新增 `tests/headless/test_p5b.gd`：10 組、涵蓋測試指南 P5-B 全部 10 條；exit 0
- 全套 30 套 headless（含新增的 `test_p5b`，已加進 `tests/run_all_headless.ps1`）：exit 0
- UI sim：**108 variants／85 catalog contracts／85 executed／85 completed／0 failed checks**（與 P5-A 關門時同數）
- 變異驗證：12 個關鍵接線逐一反轉，結果見下方「變異記錄」

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

## 走查與 UI 為了走到結局所加的暫時接線（P5-D 要拆掉）

- `playthrough_greedy` 新增 `PRIORITY_SLOTS`：第 13 天下午定向放 `d13_pm_registry::read`。`info_registry` 是 D45 `compare_registry` 唯一收的卡，沒有它就過不了 coda 門檻。
- `playthrough_greedy` 與 UI `full_walk`：第 29 天下午若邀請組未結算，明示呼叫 `choose(..., "invite_none")` 凍結慶典代付者。**逾期預設是 P5-D 的規則層工作**，落地後這兩段要刪。
- UI `coda_full`／`full_walk`：結局啟動後以 legacy `end_run()` 銜接第二輪。
- `make_states.gd` 的 `d45_evening`／`p4e_d45_afternoon` 走查加了同一筆 D29 決策，fixture 驗證也一併要求代付者非空。

## 變異記錄（12／12 精確轉紅）

每一條都是「暫時關掉該接線 → 跑 `test_p5b` → 確認轉紅 → 還原」，還原後基準線重跑 exit 0。

| # | 變異點 | 結果 |
|---|---|---|
| M1 | `_reject_unless_run()` 永遠放行 | exit 1 |
| M2 | `start_ending()` 拿掉 `ending_active` 檢查 | exit 1 |
| M3 | `_build_ending_plan()` 拿掉 source 配對檢查 | exit 1 |
| M4 | `_build_ending_plan()` 拿掉代付者前置檢查 | exit 1 |
| M5 | `reveal_ending_page()` 拿掉 `already_revealed` | exit 1 |
| M6 | `advance_ending_page()` 拿掉 `page_not_revealed` | exit 1 |
| M7 | `skip_seen_ending()` 拿掉首見檢查 | exit 1 |
| M8 | `deserialize()` 跳過快照形狀驗證 | exit 1 |
| M9 | `EffectApply.preflight()` 拿掉雙 request 衝突檢查 | exit 1 |
| M10 | `advance_phase()` 拿掉 `phase_exit` 門檻 | exit 1 |
| M11 | 結局快照改讀真狀態而非 preflight 複本 | exit 1 |
| M12 | lint 17 拿掉 madness＋ending 檢查 | exit 1 |

> M4 第一輪是**假綠**：原本的空代付者案例會先被 resolver 的 `uninvited_proxy` 片段查表擋掉，
> 測不到 `start_ending()` 自己的前置。已補「伴侶命中阿婕（fragment 不啟用）時空值／非候選仍須拒絕，
> 換成合法候選即成功」三條，M4 才真的轉紅。M9 第一輪是變異點字串沒對上（縮排），修正後轉紅。

## 給 verifier 的發現（未自行修）

1. **D45 coda 門檻可能鎖死一輪（新增，建議編號後落 `驗證後已知問題.md`）**：`compare_registry` 只收 `info_registry`，而該卡只有第 13 天下午的信徒名冊會發。沒拿到的玩家在第 45 天 evening 會永遠停在 `phase_requirements_incomplete`。舊行為之所以看不出來，是因為 D45 evening 無條件呼叫 `end_run()`。貪心走查原本就沒拿那張卡，因此這次要加定向優先槽才走得完。**要拍板的是資料／設計**：補第二個取得管道、給 coda 一條無卡出口，或接受「錯過就得撐到發瘋 BE」。
2. `phase_exit` 門檻只在父 beat 的 `condition`／`requires` 成立時生效（d45_then 是 `flag: final_day`）。條件不成立時第 45 天 evening 會照一般規則進 night，也就是走到第 46 天；正式資料上 `final_day` 由 D45 上午的 beat 寫入，不會發生，但這條分支目前沒有第二道防線。
3. K-182 已在 preflight 收斂（非 Dictionary 的 `festival_proxy` 現在拒絕整個動作）。

## 已知殘留

- K-183：`repeat_page_ids` 尚未納入 fragment 的 `repeat_pages`；現行 `skip_to` 指 suffix，不受影響
- K-190：舊壞資料 fixture 缺 P5 新必填欄位；下次動 fixture 或 lint 19 時處理
- K-191：P5-A 首次交付的大面積 JSON 重排只記紀律，不回頭重排
- P4-E／P4-F：K-165 ①、K-175、K-176、K-177 四條低度殘留
- 人工體感：P3-F 與 P4-F 合計 8 項待真人落檔
- `lose` 的 `permanent` 與 `loop_persistent_item_ids` 只有結構，尚未接行為（依方針屬 P5-D）

## P5-C 下一步

依三份文件的 `P5-C` 同名段落動工：

- `EndingResolver.resolve()` 已可用，P5-C 補四類結局的內容覆蓋與首見／重見判定測試
- 兩種 BE 的 pages 不得含替換後日談 refs；不上車快照不建立 run、day／phase 為 null
- `ready_to_complete` 只在必播頁完成或合法 skip 後為 true；`complete_ending()` 仍留 P5-D
- 結構版文字要實際播一次，確認沒有缺頁、重頁、空白頁與互斥人生同時出現

> 跑 UI 模擬一律加 `-Background`：
> `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\ui_sim\run_ui_sim.ps1 -Background`
