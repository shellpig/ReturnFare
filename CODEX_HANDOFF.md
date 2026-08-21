# ReturnFare 交接狀態

最後更新：2026-08-21

## 目前階段

**Phase 3-A（夜間資料真值化）實作與驗收完成。下一步是 P3-B 夜間狀態與進入規則。**

- Phase 1（P1-A～P1-H）：實作全綠。P1-F／G／H 三個子階段仍標 🟦「待手動操作驗收」。
- Phase 2（P2-A～P2-E）：全部實作並驗收。發狂卡的產生與倒數、縱慾出口與主動縱慾、強制縱慾與失控時段、視野門檻與發瘋 BE、headless 重演三種玩家。
- Phase 3（P3-A～P3-F）：P3-A 已實作並全套驗收；P3-B～F 規格定案待實作。

## 最近完成的工作

- `870db64` P3 文件第三輪複審，K-98～K-102 落檔並同批回寫。
- 本次：**P3-A 夜間資料真值化實作與驗收完成**：
  - Baseline checkpoint（`_qa/p3a_baseline/`，commit `870db64` 產生）：D14 night 前置狀態四項後置條件通過，P3-A 變更後重演 `available_locations()`、首次發卡、fixed 流程三項輸出基準與 `expected.json` 逐字全等（K-100）。後續已按 review 意見更新 `make_states.gd`（動態 `madness_cap` 與明示 `n_ahong_1`，K-105／K-106）並重跑產出基準。
  - `data/cards.json` 新增 10 張 slotless knowledge 對位卡（`k_night_<day_counterpart>`），名稱忠實包含白天地點名稱、文字動態防護 28 個夜間名稱劇透（K-103）。
  - `data/locations.json` 12 個可對位 night row 填入 `night_reveal`，16 個夜間限定 row 維持 `null`；`n_ahong_2` 正式改名為進場前引子名「有血跡的地方」；阿宏鏈 6 個門檻地點補齊具體 `reject_reason`（區分 5 與 6 的路線知識階段，K-109）；`n_corridor_end` 配置為 `teaser_only: true` 且三欄為 `null`；刪除已兌現的 `_pending.night_reveal`。
  - `DataFacts` 新增 `CHAPTER_START_DAYS` 與 `chapter_for_day(day)`；`GameState` 相容轉接。
  - `DataLoader` 新增 Lint 11（夜間對位完整性，含雙向單射檢查）與 Lint 12（夜間地點狀態完整性，含 `madness_cost` 拼錯檢查、teaser 雙欄必填與一致性檢查 K-108），接通 `verify_data.gd` 與 `Data._validate_loader()`。
  - 新建 6 組獨立負向壞資料 fixture（`tests/fixtures/broken/p3a_*`），各證明一種錯誤能被 Lint 11／12 攔截。
  - 新建專屬驗收測試 `tests/headless/test_p3a.gd` 7 組驗收全綠，語意斷言覆蓋阿宏 6 門檻（K-109），28 個夜間名稱人工 code review 對照表記錄於 `驗證後已知問題.md`（K-104）。
  - 同步更新 `subdocs/卡牌/知識卡.md` 索引至 21 張知識卡。

## 驗證狀態

- **17 套 headless 全部 exit 0**（`verify_data`、`test_boot`、P1-A～G、P2-A～E、`playthrough_greedy`、`test_p2_sim`、`test_p3a`）。
- **UI 模擬 63 條契約／82 個變體／11 個負向反證全綠，0 failed checks**。
- 走查基準（`6e5e51a` 起，90 個行動時段）：主角卡 47／強制縱慾 12／純比對 22／刻意留空 3／純選擇題 3／HIDDEN 2／LOCKED 1。發狂卡帳 14 張 ＝ 強制消除 12 ＋ 重置前留存 2。

測試命令見 `PROJECT_BRIEF.md > 測試速查`。sandbox 內 headless 會因 `user://logs` 權限 crash，直接用 escalated 權限跑。

## 已知風險與未驗區

- **P3-F 會改動第一輪基準**：D15 fixed 讓 `n_plaza` 永久免費、night-layer fixed 消耗今晚，第一輪 marker cost 拆成「路徑效率 13／最大壓力 14」兩條具名策略，要以新流程重跑並更新 `subdocs/驗證/發狂卡機制模擬.md`。
- **第二輪的發狂卡供給仍是待決**（`待決事項.md > 25／26`）。第一輪走滿既有收費 row 的玩家，第二輪從既有 marker cost 拿到 0 張；主要壓力應由第二輪新增／深化的內容提供，P3 不補內容。
- **待修清單**見 `驗證後已知問題.md`。與 P3 有關的：K-30／K-33／K-34／K-35／K-69 等 P3 夜間層真值化；K-68 卡在 K-69；K-65 排內容期。
- 本專案**沒有 Art Bible，也還沒談美術方向**；**沒有 `.venv`**。

## 下一個任務

依 `實作規格書.md > P3-B`＋`開發設計方針.md > P3-B`＋`測試指南.md > P3-B` 三段實作 **P3-B 夜間狀態與進入規則**：
- `night_locations_seen` 與 `night_once_beats_seen` 進 meta 序列化、跨輪保留。
- 新增 `enter_night_location()` / `night_location_seen()` / `would_night_entry_end_run()`，刪除 `open_night_marker()`。
- 八碼拒絕矩陣（`not_night`／`unknown_location`／`not_night_layer`／`teaser`／`too_early`／`locked`／`already_chosen`／`already_slept`）與雙欄 `{reason_code, reason_text}` 回傳。
- 退役正式資料所有 `opened_n_*`（改用 `night_seen`，聚會改 `saw_n_gathering_intro`），新增 Lint 13。

