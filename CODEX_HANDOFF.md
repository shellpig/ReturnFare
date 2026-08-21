# ReturnFare 交接狀態

最後更新：2026-08-21

## 目前階段

**Phase 2 全數完工，Phase 3 規格完成、程式未開工。下一步是 P3-A 夜間資料真值化。**

- Phase 1（P1-A～P1-H）：實作全綠。P1-F／G／H 三個子階段仍標 🟦「待手動操作驗收」。
- Phase 2（P2-A～P2-E）：全部實作並驗收。發狂卡的產生與倒數、縱慾出口與主動縱慾、強制縱慾與失控時段、視野門檻與發瘋 BE、headless 重演三種玩家。
- Phase 3（P3-A～P3-F）：三份文件與 `data/SCHEMA.md` 契約已寫到可動工，並經三輪規格審核（K-73～K-102）回寫完畢。

## 最近完成的工作

- `9e342de` P2-E headless 三種玩家重演與 Phase 2 全套驗收。
- `a05e0cf` P2-E 驗證落檔，四條尾巴記為 K-69～K-72。
- `92383e6` P3 夜間層六階段規格完成。
- `9b7f1c8`／`00551c1` P3 文件兩輪規格審核，K-73～K-97 落檔。
- `e9bf8bf` K-82～K-97 全數回寫（文件層），P3 開工閘清空。
- 本次：P3 文件第三輪複審，K-98～K-102 落檔並同批回寫（文件層，未動程式與資料）。補的是「驗收證不出來」那一類——P3-B 八碼拒絕矩陣、P3-E 對位入口的六碼與負向矩陣、P3-A baseline checkpoint 的產生方式、P3-F 角色分工、K-37 殘留。

## 驗證狀態

- **16 套 headless 全部 exit 0**（`verify_data`、`test_boot`、P1-A～G、P2-A～E、`playthrough_greedy`、`test_p2_sim`）。
- **UI 模擬 63 條契約／82 個變體／11 個負向反證全綠，0 failed checks**。
- 走查基準（`6e5e51a` 起，90 個行動時段）：主角卡 47／強制縱慾 12／純比對 22／刻意留空 3／純選擇題 3／HIDDEN 2／LOCKED 1。發狂卡帳 14 張 ＝ 強制消除 12 ＋ 重置前留存 2。

測試命令見 `PROJECT_BRIEF.md > 測試速查`。sandbox 內 headless 會因 `user://logs` 權限 crash，直接用 escalated 權限跑。

## 已知風險與未驗區

- **P3-F 會改動第一輪基準**：D15 fixed 讓 `n_plaza` 永久免費、night-layer fixed 消耗今晚，第一輪 marker cost 拆成「路徑效率 13／最大壓力 14」兩條具名策略，要以新流程重跑並更新 `subdocs/驗證/發狂卡機制模擬.md`。
- **第二輪的發狂卡供給仍是待決**（`待決事項.md > 25／26`）。第一輪走滿既有收費 row 的玩家，第二輪從既有 marker cost 拿到 0 張；主要壓力應由第二輪新增／深化的內容提供，P3 不補內容。
- **待修清單**見 `驗證後已知問題.md`。與 P3 有關的：K-30／K-33／K-34／K-35／K-69 等 P3 夜間層真值化；K-68 卡在 K-69；K-65 排內容期。
- 本專案**沒有 Art Bible，也還沒談美術方向**；**沒有 `.venv`**。

## 下一個任務

依 `實作規格書.md > P3-A`＋`開發設計方針.md > P3-A`＋`測試指南.md > P3-A` 三段實作 **P3-A 夜間資料真值化**：10 張對位 knowledge 卡、12 筆 `night_reveal`、28 個夜間名稱審查、6 個阿宏門檻理由、`teaser_only` schema、lint 11～12 與各自獨立的壞資料 fixture。

**⚠️ P3-A 的第一件事不是改資料，是產 baseline。** 在動 `cards.json`／`locations.json` 之前，先於乾淨工作區跑 `make_states.gd` 的 `p3a_night_baseline` 情境，產出 `_qa/p3a_baseline/p3a_night_baseline.json` 與 `.expected.json`，並把當時的 commit sha 記回本檔。事後補產一律不算——舊資料已經不在，拿到的「前」其實是「後」，那條驗收會恆真（K-100）。契約在 `開發設計方針.md > P3-A`。

**不得跳過 P3-A／P3-B 的資料與狀態前置去先做 P3-C 的流程或 P3-D 的 UI。**

> 每個 P3 子階段收尾時更新本檔（`開發設計方針.md > 全域結構決策（P3 期間建立）` 有同一條規約）。內容過期比沒有更糟——本檔曾停在 P1-G 五個子階段之久，落檔為 K-97。
