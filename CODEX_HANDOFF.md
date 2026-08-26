# ReturnFare 交接狀態

最後更新：2026-08-26

## 目前階段

**P1、P2 已完成；P3 機器層已完成，剩既有人工體感項；P4-A 已實作並自驗全綠（機器層）；P4-B～F 與 P5-A～F 仍為規格。下一個實作任務是 P4-B（委託規則）。P5 不得跳過 P4 提前實作。**

- 進度與測試數字的單一事實來源是 `PROJECT_BRIEF.md`；本檔只保存最近交接重點。
- P4-A：委託／遭遇資料與 lint 真值化已完成；P4-B～F（委託／遭遇 runtime 與 UI）尚未開始。
- P5：開局、四類結局、歷輪摘要、跨輪重置與 UI 已拆成 P5-A～F，尚未開始實作。

## 最近完成的工作

- **P4-A 資料與 SCHEMA 真值化已實作，機器層自驗全綠（23 套 headless exit 0，含新 `test_p4a.gd`）。**
  - **卡片**：`cards.json` 全 64 張皆有必填 boolean `discardable`；lint 9（`lint_card_types`）新增缺欄／錯型別檢查。
  - **D8**（`n_manydoors_ch1`）改為 `fixed` + `when {day:8,phase:night}` 的 dated night encounter：`repeat_each_run`+`charge_first_visit`+`allow_discard`、`escape_cost:1`、`after_finish:"stay"`、非 meta_once、三回合 response matrix（正解＋三個 `requires_discardable` fallback），出口旗標 `d8_encounter_victory/failure/escaped`。beat text 放固定姓名開場。
  - **D45**（`d45_encounter`）改為一 round encounter：`escape_cost:null`、`allow_discard:false`、`after_finish:"advance_phase"`，各正式卡路線（自己名字／她／舊紙／周先生／叔叔／三張推論）各一 response，推論 response 帶 `lose`/`gain`。
  - **D17-19 委託**：`d17_morning_phone` 退掉自動發三張人物卡，改條件 gain（阿婕 `not ajie_trust_broken`、阿珠 `azhu_shared_abnormal_medicine`）；新增 `d17_19_prescription`（`day_from 17 day_to 19`，choice_group `prescription_route`，親自處理＋阿婕 immediate／阿珠 next_morning+report／阿財 immediate），刪 `d17_pm_delegate`；阿財三個 work 槽（D17/18/新增 D19 `d19_pm_acai_3`）條件 gain `npc_acai` 並補寫 `acai_obs_scar`；`d16_pm_sanquan` 加 `repair_ajie_trust` 修復接點；`x_lust_ajie` 縱慾出口設 `ajie_trust_broken` 並條件 lose；`d9_morning_clinic` 補寫 `azhu_shared_abnormal_medicine`。
  - **lint**：新增 lint 15（`lint_delegations`）、lint 16（`lint_encounters`，含 round graph 可達／終止、response 引用不重疊、consume_card 不得永久失去人物、repeat/charge_first_visit 適用範圍、on_resolve/三出口封閉效果鍵）；lint 14 加 `repeat_each_run` 窄例外；lint 3（K-22）加 `choice_requires_card:true` 豁免（schema 已允許親自處理槽收 protagonist）。
  - **引擎最小接線（經使用者授權，超出方針 P4-A 檔案列表）**：`game_state.gd::play_night_fixed()` 對 night-layer fixed beat 且 `encounter.charge_first_visit==true` 者，於強制到訪前保存是否終身 seen，未 seen 才按 location `madness_cost` 收一次。理由見「本次的取捨」。
  - **跨階段測試調整（實作者 owned 測試檔）**：`test_p2_sim.gd` A 玩家時間軸移除第 8 夜 n_manydoors 的 `enter_night_location` 事件（D8 改強制到訪，發狂卡仍在 day 8 收、視野窗口不變，26→25 事件）；`test_p3f.gd` sim 以 `_madness_counter` 差額把 D8 強制收費補進 `paid_entered_count`（總 marker cost 仍 13/14）。

- **Codex review 修正（第二批，經使用者授權方案 1 最小 gate）**：
  - **B1 委託槽惰性化（gate）**：`choose()` 對帶 `delegation` 鍵的槽回 `delegation_not_wired` 拒絕，使 P4-A 的委託資料如 encounter 一樣不接玩家操作（P4-B delegate() 兌現後拆除）。同時把 `choice_requires_card` 在規則層兌現：無卡直呼 `choose()` 回 `card_required`；提交 protagonist 的親自處理槽消耗行動時段。理由：Codex 正確指出 encounter 已惰性（`slots:[]`）但委託槽會被舊 UI/`try_place→choose` 真的改狀態，兩者不對稱。
  - **B2 lint 引用/語彙缺口**：`verify_references()` 遞迴進 `encounter` 與 `slot.delegation` → 補齊 `on_resolve.gain`／`report.gain` 存在檢查；lint 15 對 `delegation.report` 跑 `_lint_effect`（封閉效果鍵）。
  - **lint 16 型別缺口**：`per_round_slot_cost`／`escape_cost` 加整數檢查（拒 1.5）、`when.day` 小數（8.5）不算明確整數 day、`repeat_each_run`／`charge_first_visit` 加 boolean 型別檢查、`response.id` 缺失/重複檢查。
  - **NB1**：`play_night_fixed` 的 charge_first_visit 收費若觸發發瘋 BE，`phase` 回 morning 即 return，不再 `play_beat` 寫進重置後新輪。
  - **NB2/NB3**：阿財委託回報文案改 immediate 一致（去掉「隔天」）；D22 過期 note 更新為三個觀察開關的實際寫入端。
  - `test_p4a` 補齊：runtime gate（3 條）、report 語彙/引用、encounter 巢狀引用、小數 cost/day、錯型別 boolean、response id 缺失/重複，共新增約 12 條斷言。

- **Codex review 修正（第三批）**：
  - lint 16 補 `demand` 必填；response/fallback 的 `next_round` 改成**必須有鍵**（缺鍵不再被 `.get()` 當成明示 null 而靜默提前結束遭遇，對齊 SCHEMA line 613/620）。
  - lint 16 graph traversal（reachability 與 `_round_can_reach_null`）全面防呆：malformed round/response 先記錯後不再強制轉型，驗證器不會在回報前 runtime crash。
  - `test_p4a` 補齊 P4-A 明定但先前缺的負向 fixture：`discardable` 缺欄/錯型別（lint 9）、`demand` 缺、response/fallback 缺 `next_round` 鍵、malformed round/response 不 crash，以及 **NB1 直接 regression**（第 8 夜 charge 撞發狂上限 → 恰一次 BE、重置回第 1 天、`beats_entered` 不含 `n_manydoors_ch1`）。

- P5 文件 review 缺口已同步收斂至 `實作規格書.md`、`開發設計方針.md`、`測試指南.md`、`data/SCHEMA.md`：
  - `advance_phase() -> Dictionary` 自 P4-D 升級，P5-D 固定 mode → encounter → night staging → defaults → `phase_exit` → transition validation → atomic commit 的順序；`resolve_night_advance()` 於 P5-D 退場。
  - D45 coda 改由 beat `phase_exit.required_slots` 資料化，不在 `main.gd` 或 beat／slot id 特判。
  - source ↔ ending 固定四組一對一配對；beat `ending` 只允許 inventory BE。
  - `EffectApply` 改採 preflight／commit；同一 action 的 effects、bookkeeping 與 ending snapshot 整批原子，雙 ending request 回 `data_conflict` 且零變化。
  - active ending、history、page ref、nullable 矩陣與 legacy checkpoint 遷移形狀已固定；壞存檔回 `invalid_save_shape`。
  - `most_invested_npc` 在 P5 未凍結前改名為 `festival_proxy_npc`；D31／D39 以 `festival_proxy_is` 讀 D29 frozen id。
  - lint 19 補 permanent lose 指向非 persistent 卡，以及每位慶典候選缺 D31／D39 內容的負向契約。

## 驗證狀態

- P4-A 機器層自驗：**`tests/run_all_headless.ps1` 全部 23 套 exit 0**（含 `test_p4a.gd`：正向動態數＋lint 15/16 逐類負向 fixture＋lint 14 repeat 例外回歸）。`verify_data.gd` lint 1～16 全 0 錯誤。
- 這是實作者自跑證據，**verifier 打勾與 `PROJECT_BRIEF.md`／`測試指南.md` 落檔尚未進行**——實作者未改 `測試指南.md`、`驗證後已知問題.md`、`PROJECT_BRIEF.md` 或驗收勾選。
- 本次的取捨（需 verifier 覆核）：D8 變 dated fixed encounter 會讓既有 `play_night_fixed` 強制到訪 n_manydoors 卻不收費，打破 greedy／sim 的發狂卡統計；使用者授權以「`play_night_fixed` 最小收費接線」解決（見上），而非延後 D8 或接受紅測。
- 待 verifier 處理的建議：`subdocs/驗證/發狂卡機制模擬.md` 的 A 玩家第 8 夜條目需同步為「強制遭遇到訪」（與 `test_p2_sim` 對齊，verifier-owned，實作者未改）。

## 目前風險

- P4、P5 都仍是規格狀態；正式 JSON、runtime、fixtures 與 UI 尚未兌現本文契約。
- P5-B／C fresh boot 暫維持 legacy run，P5-D 才切 opening；分段提交時不可提早改預設而讓遊戲無法 boot。
- P5 的 effect pipeline 是跨既有入口的簽名變更；實作時必須一次盤點 `try_place()`、`choose()`、`play_beat()` 與所有 EffectApply 呼叫者，避免只有單一路徑吃到錯誤結果。
- 本專案沒有 Art Bible，也沒有 `.venv`；目前任務不涉及素材或 Python。

## 下一個任務

**P4-B 委託規則**（`實作規格書.md > P4-B`、`開發設計方針.md > P4-B`、`測試指南.md > P4-B`）：

- P4-A 已把委託／遭遇資料與 lint 真值化；P4-B 起接 runtime。`delegate()` 原子入口、run 層三筆狀態、immediate／next_morning 結算、序列化與換日重置、11 碼拒絕矩陣，不吃行動格。
- **P4-B 要拆除 P4-A 的臨時 gate**：`game_state.gd::choose()` 目前對帶 `delegation` 鍵的槽回 `delegation_not_wired`；delegate() 兌現後把委託槽導向 delegate() 而非直接拒絕。`choice_requires_card` 的規則層兌現（card_required／消耗行動格）已在 P4-A 做好，P4-B 可直接沿用。
- 動工前先核對 P4-A 落地的資料形狀：`d17_19_prescription` 的 choice_group、三種 timing、人物卡條件 gain 接點（阿婕／阿珠／阿財）、`x_lust_ajie` 破壞與 `repair_ajie_trust` 修復。
- 注意 P4-A 已在 `play_night_fixed` 做了 charge_first_visit 最小接線；P4-D 正式接遭遇引擎時要確認不與此重複收費。
- 實作者只提供測試證據，不自行修改 `測試指南.md`、`驗證後已知問題.md` 或驗收勾選。
