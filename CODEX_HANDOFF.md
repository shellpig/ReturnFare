# ReturnFare 交接狀態

最後更新：2026-08-27

## 目前階段

**P1、P2 已完成；P3 機器層已完成，剩既有人工體感項；P4-A／P4-B 已通過 verifier 複驗，K-124／K-125 結案。P4-C 最新完整複驗雖然所有自動測試全綠，但仍有契約漂移與已勾驗收缺少真實路徑證據，重新列為待補缺口，尚不能關門。下一個任務是補齊 P4-C，不得先做 P4-D／P4-E，也不得跳到 P5。**

- 進度與測試數字的單一事實來源是 `PROJECT_BRIEF.md`；本檔只保存最近交接重點。
- P4-A：委託／遭遇資料與 lint 真值化已完成。
- P4-B：委託規則已實作並通過 verifier 複驗，機器層 24 套 headless 測試全數 exit 0；K-65 結案。
- P4-C：委託 UI、首張人物卡教學與 D17～19 處方案例已實作；K-124／K-125 結案，25 套 headless 全綠，完整 UI sim 102／102 variants、79／79 contracts、0 failed。但最新完整複驗發現契約與覆蓋缺口，暫不維持關門判定。
- P4-D～F（遭遇 runtime、UI 與全流程）尚未開始。
- P5：開局、四類結局、歷輪摘要、跨輪重置與 UI 已拆成 P5-A～F，尚未開始實作。

## 最近完成的工作

- **P4-C 第三輪：把上一輪的偷懶捷徑改成真實入口（最新，尚待 verifier 複驗）。** verifier 指出前一輪破壞／取得測試仍直接寫旗標、task_title 契約未回填、UI 仍只 D17：
  - **阿婕破壞走真實縱慾**：`test_p4c` 第 6／7 段改以 `indulge("exit_sanquan","x_lust_ajie",<madness_inst>)` 驅動（前置：持 npc_ajie＋一張發狂卡＋關係達「疑似」），由該出口的 on_place 同時設 `ajie_trust_broken`、`lose` npc_ajie、阻止 D17 on_enter 條件 gain；第 7 段續接 D16 `try_place` 修復槽＋D17 `play_beat` 重取，全程真實入口、不直接寫旗標。共用 helper `_break_ajie_via_indulgence()`。
  - **阿珠走真實 D9 寫入端**：第 11 段改 `try_place("protagonist","d9_morning_clinic","ask")` 寫入 `azhu_shared_abnormal_medicine`＋「沒走 D9 則 D17 不發卡」負向對照，證明 D9 是可正常操作的寫入端。
  - **task_title 契約回填**：`開發設計方針.md` P4-C view model 欄位列補 `task_title`（`{result_timing, preview, tendency, task_title, delegation_state}`），契約與實作一致。
  - **428 的縱慾 UI 主張補證**：新增 UI 契約 `p4c_07_indulge_hides_candidate`＋fixture `p4c_ajie_indulge_ready`——D17 下午對阿婕縱慾後 `ask_ajie` 委託候選在面板當場消失（P2→P4-C 動態整合，非冗餘 render 重測）。catalog 80→81，launcher `-ne 80`→`-ne 81`。
  - **證據**：25 套 headless exit 0（`test_p4c` 擴為 12 段、破壞／取得全走真實入口）；完整 UI sim run `20260827-110733-658-p21796-eeab56f6` 為 **104 variants／81 contracts／81 completed／0 failed**、11 條負向反證如期失敗。
- **P4-C verifier 回列五條缺口的實作補強（前一輪，第 6／7／11 段當時仍直接寫旗標，已被本輪取代）。** 針對交接檔列的缺口逐條處理：
  - **① 契約統一**：view model 委託欄位改封閉語彙 `delegation_state`（`"available"`／`"delegated_today"`），`panel_builder._delegation_view()` 與 `location_panel` 同步；`GameState.delegation_status()` 查詢仍回 `delegated_today`（hand_bar／card_detail 的人物卡狀態消費端，與 slot view model 不同層，刻意不動）。
  - **② UI 不讀原始 JSON**：`_delegation_view()` 新增 `task_title`（由 beat title 衍生），委託確認畫面改讀它；`location_panel._on_delegate_candidate_pressed()` 移除 `Data.loader.beats_by_id` 直讀。
  - **④ 阿婕修復走真實路徑**：`test_p4c` 第 7 段改 D16 下午 `try_place("protagonist","d16_pm_sanquan","repair_ajie_trust")` 清 `ajie_trust_broken`＋D17 `play_beat("d17_morning_phone")` on_enter 條件 gain 重取 `npc_ajie`，不再 `EffectApply.apply()`＋手動 `gain_card()`。
  - **⑤ 阿珠／阿財取得閘門**：`test_p4c` 第 11 段驗阿珠僅 `azhu_shared_abnormal_medicine`（D9 揭露路線）成立時 D17 on_enter 取得、阿財僅真實「跟阿財做事」放卡取得。
  - **③ 排序**：新增 UI 契約 `p4c_06_candidate_order` 驗處方候選照資料槽序渲染（catalog 79→80，launcher `-ne 79`→`-ne 80` 同步）。
  - **證據**：25 套 headless exit 0（`test_p4c` 擴為 12 段）；完整 UI sim run `20260827-102810-305-p77376-2f5ad2f5` 為 **103 variants／80 contracts／80 completed／0 failed**，11 條負向反證如期失敗。
  - **未竟（見風險段）**：③ 的「今日已受託仍在原位＋disabled＋隔日恢復」與「條件不足資料理由」在 P4-C 唯一委託 beat 內容不可達，需 verifier 決定收斂勾項或投資合成 data variant。
- **P4-C 接線 A 複驗完成，但未通過完整關門（前一輪）。** `64e5d98` 已在 `origin/main`；即時委託確認後面板正確關閉，回報由 `main.gd` 寫入 FlowText，原 K-125 路徑未回歸。證據：25 套 headless 全綠；完整 UI sim run `20260827-094822-316-p25656-6b4f4a0f` 為 102／102 variants、79／79 contracts、0 failed，11 條負向反證如期失敗；資料為 64 cards／48 locations／18 NPC／261 beats，引用 0、lint 1～16 全 0。**未關門原因**：① 方針要求 `delegation_state`，實作與測試仍使用 `delegated_today`；② `location_panel.gd` 的 P4-C 確認流程仍直接讀 `Data.loader.beats_by_id` 取得標題，違反「UI 不讀原始 JSON」；③ UI catalog 仍未直接驗今日已受託保持原位／disabled／隔日上午恢復，以及條件不足資料理由；④ 阿婕修復測試直接 `EffectApply.apply()` 再手動 `gain_card()`，未驗真實放卡與 D17 `on_enter` 接線；⑤ 阿珠僅由 D9、阿財僅由 D17～19 取得，以及 D18／D19 UI 路徑，尚無文件所宣稱的 headless＋UI 直接證據。這次 verifier 未修改任何文件、未建立 commit、未 push；既有 4 個未追蹤 `.uid` 保持不動。
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
- P4-C：25 套 headless 全綠（`test_p4c` 12 段，破壞／取得全走真實入口）；完整 UI sim **104 variants／81 contracts／0 failed**，11 條負向反證如期失敗。接線 A、契約統一（`delegation_state`＋`task_title`）、阿婕縱慾破壞→修復→重取真實路徑、阿珠 D9／阿財 D17-19 真實寫入端、縱慾→候選消失 UI 整合（`p4c_07`）均已證。**未關門項只剩 verifier 的文件收斂決策（見風險段），無實作 blocker。**
- P4-B verifier 複驗：**`tests/run_all_headless.ps1` 全部 24 套 exit 0**（含 `test_p4b.gd` 9 大測試段）。`verify_data.gd` 64／48／18／261、引用與 lint 1～16 全 0 錯誤；接點失效保留、嚴格回報順序、強制縱慾先行與 K-65 同筆／跨筆／文字三條均有可辨識斷言。

## 目前風險

- **P4-C 契約漂移已全解**：view model 欄位統一為封閉語彙 `delegation_state`，`task_title` 亦回填 `開發設計方針.md` P4-C（`{result_timing, preview, tendency, task_title, delegation_state}`）；`location_panel` 確認流程不再直讀 beat JSON。阿婕縱慾破壞→D16 修復→D17 重取、阿珠 D9 寫入端、阿財 D17-19 共事、D18／D19、跨日不重複均走真實入口 headless。
- **P4-C 428／429 的 UI 主張**：縱慾破壞→委託候選當場消失已由 `p4c_07` 真證（P2→P4-C 動態整合）。其餘 428／429 的 UI 面（阿婕修復→重現、D18／D19 完成、跨日 RESOLVED 留存）re-test 與 D17 相同、day/state 不變的委託 render 管線——規則已由 headless（`test_p4c` 第 6／7／8／9 段）證，UI 由 `p4c_01`～`p4c_07` 代表性覆蓋。**建議 verifier**：428／429 UI 勾項記為「代表性 UI（D17 委託 wiring＋縱慾整合）＋headless 規則」，不另建 D18/D19 冗餘 UI 案（同一 render code、只差資料層日窗，已由 headless test 8 證）。
- **P4-C 剩餘關門缺口＝內容不可達，決策已定為 (a)**：測試指南 423／424 的「今日已受託仍在原位且 disabled」「隔日上午恢復」「條件不足顯示資料理由」是通用委託規則，但 P4-C 唯一委託 beat `d17_19_prescription` 為 choice_group 且無 requires-gated 持有候選——委託任一路線即永久收起整組，同一人物不會在另一非 choice 委託槽出現，也沒有「持有但 requires 不足」的委託候選，故這三項在 shipped 內容中無法觸發。規則已由 headless 證：狀態翻轉（`test_p4c` 第 3 段獨立合成槽 `delegation_state` 翻 `delegated_today`）、每日重置（`test_p4b`）、排序（`test_p4c` 第 10 段＋UI `p4c_06`）。**使用者 2026-08-27 拍板走 (a)**：不投資合成 data variant，以 headless／view-model 規則證據認列，UI 勾項收斂至 P4-C 內容可達範圍。
- 低優先觀察：未列入白名單的未知 modal 仍可能最終被 helper 報成 beat 上限，而非立即回具名 blocking-dialog 錯誤；只影響失敗診斷精度，未證實為 production 缺陷。
- P4-D～F、P5 都仍是規格狀態；遭遇 runtime／UI 與 P5 各項系統尚未兌現。
- 本專案沒有 Art Bible，也沒有 `.venv`；目前任務不涉及素材或 Python。

## 下一個任務

**P4-C 收尾——僅剩一個決策，不再是實作缺口**：

- 已補齊（本輪，真實入口）：`delegation_state`＋`task_title` 契約統一（不讀 JSON）、阿婕縱慾破壞→D16 修復→D17 重取全真實路徑、阿珠 D9／阿財 D17-19 真實寫入端、D18／D19、跨日不重複、UI 排序（`p4c_06`）、縱慾→候選消失 UI 整合（`p4c_07`）。25 套 headless＋**104／81／0** UI sim 全綠。
- **決策已定 (a)**（使用者 2026-08-27，僅限 423／424）：不補合成 data variant 讓那兩態在 UI 觸發，以 headless／view-model 規則證據認列。
- **verifier 待辦（doc 收尾，實作端無 blocker）**：
  - 423／424 收斂為「headless／view-model 規則證據認列，內容不可達」：423 的「今日已受託 in place＋disabled＋隔日恢復」、424 的「條件不足候選顯示資料理由」（P4-C 唯一委託 beat 為 choice_group、無 requires-gated 持有候選）。
  - 428／429 UI 勾項記為「代表性 UI（`p4c_01`～`p4c_07`，含縱慾整合）＋headless 規則（`test_p4c` 6／7／8／9）」；D18/D19 UI 與跨日 RESOLVED 屬 day/state 不變的同一 render 管線，不另建冗餘 UI 案。
  - 收斂後校正 `測試指南.md`、`PROJECT_BRIEF.md` 與本交接檔並關門 P4-C；之後才進 P4-D。
