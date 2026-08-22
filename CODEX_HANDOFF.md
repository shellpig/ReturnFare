# ReturnFare 交接狀態

最後更新：2026-08-22

## 目前階段

**Phase 3-C（夜間內容流程）實作與驗收完成。下一步是 P3-D 夜間地點清單與詳情 UI。**

- Phase 1（P1-A～P1-H）：實作全綠。P1-F／G／H 三個子階段仍標 🟦「待手動操作驗收」。
- Phase 2（P2-A～P2-E）：全部實作並驗收。發狂卡的產生與倒數、縱慾出口與主動縱慾、強制縱慾與失控時段、視野門檻與發瘋 BE、headless 重演三種玩家。
- Phase 3（P3-A～P3-F）：P3-A／P3-B／P3-C 已實作並驗收；P3-D～F 規格定案待實作。

## 最近完成的工作

- `ce7c41a`／`41d2d8e`／`188541a` P3-A 夜間資料真值化與 K-103～K-110 修正。
- `2ef58f3`／`7c5184b` P3-B 夜間狀態與進入規則、八碼拒絕矩陣、舊旗標退場、lint 13。
- 本次：**P3-C 夜間內容流程實作與驗收完成**（`bdfa5fd` 實作、`01ccff4` 修 review 尾巴）：
  - **候選層與求值層分離**：`DataLoader.night_beat_candidates(day, location_id, chapter)` 只做結構選擇（定日 primary → 章節變體由高至低 → add-on），`GameState.resolved_night_content(location_id)` 才求值 `condition`；`requires` 不參與候選選擇，不成立仍是選中的 LOCKED 內容。`PanelBuilder.build()`、`sleep_night()`、`_is_beat_time_valid()` 三處共用同一份結果（K-30）。
  - `DataFacts.beat_matches_time()` 縮成三參數、只判有 `when` 的 beat；無 `when` 一律 false。夜間章節變體與 add-on 只由候選層分類。
  - **fixed 流程**：D1／D2／D15 加 `meta_once: true`（整份存檔只強制播一次），D24 不加（每輪重播）；D3 `n3_map_opens` 由 `n_queue` 改掛 `sanquan`、改 fixed＋meta_once、刪三個 slots 與 madness 效果，成為環境引導而非到訪。
  - **夜間推進唯一入口** `resolve_night_advance()`：chosen 非空 → 直接推進不呼叫 sleep（K-33）；pending → 清 pending 並推進；其餘 → 呼叫 `sleep_night()`，有 lines 就停一拍、寫進 `FlowText`、本次不換日（K-69）。`_refresh_advance_hint()` 夜間三態按鈕：直接睡／進入隔天／結束今晚。
  - **`empty_result`**：合法但零內容的夜間地點回 `empty_result: true`，不合成假 beat id。
  - 新增 **Lint 14**（`lint_night_once`）：`meta_once` 只能用於 fixed＋exact night when；night-layer fixed 必須 `meta_once`；同一個 `when.day` 至多一個 night-layer fixed（K-90）。`when.phase` 認字串也認陣列。
  - `_record_forced_night_visit()` 改回傳 `bool`，`night_location_chosen` 非空或 `night_sleep_pending` 為真時拒絕；`play_night_fixed()` 拿到 false 就跳過該 beat，`night_once_beats_seen` 的寫入點在到訪成功之後。
  - `tests/headless/test_p3c.gd` 12 組 69 條斷言；lint 14 負向 fixture 7 個。

## 驗證狀態

- **19 套 headless 全部 exit 0**（`verify_data`、`test_boot`、P1-A～G、P2-A～E、`test_p2_sim`、P3-A／B／C、`playthrough_greedy`）。
- `test_p3c` **12 組 69 條斷言全綠**；lint 14 掃正式資料 0 錯誤。
- **UI 模擬只跑了夜間相關 6 個變體**（`p2d_01_vision_zero`／`_three`、`p1af_29_night_resolution`／`_paid`／`_d1_fixed`、`p1af_30_sleep_d24`），failed checks 0。其餘 57 條契約與本次改動無交集，未跑——**要宣稱全套無迴歸得自己補跑**。
- **變異測試 3 種全部如預期轉紅**：刪 `_refresh_advance_hint()` 夜間分支（3 條紅）、刪 `_record_forced_night_visit()` 的 chosen 保險（4 條紅）、刪 lint 14 陣列 phase 分支（2 條紅）。同樣三刀在 `bdfa5fd` 上是全綠——那正是 K-116／K-117／K-118 的由來。
- `測試指南.md > P3-C` **13 條打勾 12 條**，剩下的那條是 K-68 的「清回 2 張又不存在」，P3-D 補。

測試命令見 `PROJECT_BRIEF.md > 測試速查`。sandbox 內 headless 會因 `user://logs` 權限 crash，直接用 escalated 權限跑。

## 已知風險與未驗區

- **K-122：`subdocs/驗證/發狂卡機制模擬.md` 已與程式基準分岔。** `bdfa5fd` 因「D15 night-layer fixed 消耗今晚」把 `test_p2_sim` 期望值改成 A 18／45、B 21／45（視野窗口各挖掉第 15 天），模擬文件仍寫 19／45、22／45。方針要求「先更新模擬、再同步 P2-E 基準」，這次順序反了。**P3-F 用具名策略重跑後一次對齊，不要拿測試期望值回填文件。**
- **K-123：P3-C 的按鈕三態只有 `test_p3c` 第 12 組的場景級證據**（載入真 `main.tscn` 讀 `AdvanceButton.text`），沒有 `tests/ui_sim/` 契約，catalog 仍 63。P3-F 的「所有 UI 契約以真實 input event 跑過」要記得它。
- **K-68 剩三分之一**：K-69 解封後 `p2d_01` 兩個變體已改讀畫面文字（2 張看不到、3 張看得到），缺「清回 2 張又消失」的狀態轉換。連帶 K-94（`開發設計方針.md` UI 表改回 ✅）仍未到期。
- **P3-F 會改動第一輪基準**：第一輪 marker cost 拆成「路徑效率 13／最大壓力 14」兩條具名策略，要以新流程重跑。
- **第二輪的發狂卡供給仍是待決**（`待決事項.md > 25／26`）。
- 待修清單見 `驗證後已知問題.md`。與 P3 有關的：K-34（P3-D 地點級 `requires`）、K-35（收尾證據等 P3-F）、K-115（拒絕文案 UI 消費端，P3-D）、K-112（低）、K-65（內容期）。
- 本專案**沒有 Art Bible，也還沒談美術方向**；**沒有 `.venv`**。

## 下一個任務

依 `實作規格書.md > P3-D`＋`開發設計方針.md > P3-D`＋`測試指南.md > P3-D` 三段實作 **P3-D 夜間地點清單與詳情 UI**：
- 清單只按 `earliest_night`＋資料順序排列，狀態改變不跳位；四種狀態文字與夜間限定 row 兩態逐字符合規格書第九節。
- 地點項目先開唯讀詳情、再進入；門檻不成立時詳情可讀、理由可見（接上 K-115 的 `reason_code`→文案對照表與 `reason_text` 優先顯示）、進入鍵 disabled。
- **`available_locations()` 語意在本階段改變**：`p1af_29_night_resolution` 與 `p1af_29_night_paid` 的「已選過地點後其他地點不可見」兩條斷言必須反轉為「其他地點仍可見、`night_enter::<id>` 全部 disabled」，斷言訊息一起改；`make_states.gd` 與 `playthrough_greedy.gd` 同批確認（K-91）。
- 順手收掉 K-68 的第三腳（同一狀態下 3 張 → 清回 2 張，睡覺內容節點消失）與 K-123（把按鈕三態塞進 ui_sim 契約，契約總數五處一起改）。
