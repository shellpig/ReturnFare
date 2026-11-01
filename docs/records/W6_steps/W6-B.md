# W6-B 主動／強制縱慾 — 指揮紀錄

## Scope 與前置

- 日期：2026-11-01；起點 `main@4c51ad4`；實作提交 `1672747`。
- worker：agy **Gemini 3.8 Flash (High)**，使用者指定。主體由 worker 實作，指揮者審核修正並補回歸測試。
- 契約：`docs/web/W6實作契約.md`「一、二、五」及共用契約的架構／必要驗證／差分；前置 W6-E1、W6-A 已驗收。
- 交付主動／強制共用結算、泡湯預扣、出口挑選與強度、時段接線、地圖強制文字及測試。不做 W6-C／D／E2、存檔、全程 trace、正式資料或 Godot 修改。
- 工單與串流紀錄：`C:\_work\AI_Work\Tools\agy-runs\agy-W6-B*.prompt.txt`、`agy-W6-B-run*.jsonl`；接續 conversation `c4fffea3-7e48-43e6-a524-28c824764978`。

## 交付與高風險規則

- `indulgence.ts`：純函式 `pickExit(state,data)`、`levelFor(count,tuning)`。自動池檢查 beat／slot 的 condition 與 requires，不看時間、地點可達性或 slots_placed；排除 auto:false，同權重維持來源順序。
- Game 新增 `indulge(beatId,slotId,cardInstanceId): MutationResult`；tryPlace 保留 `madness#N` 原實例路由。出口不寫 slots_placed，普通槽的一次性規則不動。
- 擴充既有 bookkeeping 與 `settleEffectsOnDraft`：扣卡、扣格、次數與 forced 出列先在 draft 上記帳，再執行 base＋當次強度效果，整筆成功才提交。效果失敗無半套扣款、無文字洩漏。
- 泡湯獨立檢查 morning 與剩餘行動，按 tuning 清卡並預扣後續行動，不直接跳時段。
- morning tick 入列，首個可用行動格結算隊首，一格一張，餘債跨日。失敗保留有效債、卡與行動；已不在手的舊隊首依 Godot 清理。
- PhaseView 新增必要欄位 `forced_lines`；GameShell 地圖顯示正式效果原文，進出面板仍保留。強制效果觸發結局後不繼續建立遭遇。

## 指揮者審核修正

- worker 前兩輪過度讀檔／基線檢查，依手冊中斷；改串流並在同一 conversation 明確要求直接實作。CLI 模型名稱已自帶 High，不接受額外 `--effort high`，錯誤參數已移除。
- 退回修正 tuning 硬編碼與多形 fallback、泡湯對數值偶合的依賴、強制結局後仍檢查遭遇、強制文字只在一般演出出現，以及 UI 猜測 selector／可跳過斷言。
- worker 壓縮上下文後誤用 git checkout／刪除指揮者建立的兩份紀錄，違反工單。僅本次指揮紀錄受影響，無使用者原有改動；立即停止 worker，指揮者重建紀錄。後續 worker 不得自行清理他人改動。
- 指揮者收尾：修正 soakCost 作用域、測試 fixture 的正式型別與 when、required forced_lines；補成本一格仍限上午、強制結局優先、主動／強制共用強度、查詢無副作用、失敗原子性與泡湯指定實例／清卡數證據。
- UI 改用既有實際 DOM 與正式 D2 afternoon `work`／D11 morning `checkin` 主角槽，直接確認候選不存在；強制文字於面板往返前後均斷言。未增加正式測試注入入口。
- 移除無實際共享資料 mutation 的 fixture 還原樣板；刪除 worker 在 repo 根目錄產生的 test-results/.last-run.json。未修改 data、Godot、基線、依賴或 verifier 文件。

## 指揮者驗證證據

以下適用 `1672747` 的程式與測試內容；文件提交不改程式。這是交付證據，不是獨立 verifier 驗收。

| 檢查 | 結果 |
|---|---|
| `npm test` | exit 0；18 files／179 tests；新增 indulgence.test 17 tests |
| `npm run build` | exit 0；型別檢查、資料 lint 與 Vite 成功；0 errors／4 筆既有豁免 warnings |
| `npm run test:ui` | exit 0；14／14，含新增 2 條 W6-B UI；Playwright 專用 headless Chromium，未用 Edge |
| W5 軌跡 | 12 checkpoints／560 fields，equal=true |
| W3 軌跡 | 5 checkpoints／187 fields，equal=true |
| 正式產物與範圍 | dist 無 __testGame、__w6b_snap_override__、trace-entry；git diff --check 通過；data／Godot／基線未改 |

軌跡：`_qa/web/W6-B/trace-web-conductor.json`。最小變異各自對應測試 exit 1，finally 逐 byte 還原來源後，全套 Node 與 build 再次 exit 0：

| 變異 | 反證與報告 |
|---|---|
| 移除 auto:false 過濾 | 高權重非自動出口被錯選；`_qa/web/W6-B/mutation-auto-filter.log` |
| 拔除強制結算接線 | 前夜 advancePhase 歸零後未扣卡／扣格；`mutation-forced-wiring.log` |
| 取消結局後停止遭遇 | ending 被目標遭遇守衛擋下；`mutation-ending-short-circuit.log` |
| 效果先於成本記帳 | 條件仍看見待扣發狂卡，使交易失敗；`mutation-post-cost-effects.log` |

## 待驗收與限制

- 指揮者已完成契約、生命週期／架構、公開簽名與型別、序列化拒絕原子性、正式資料接線、UI 可達性、錯誤保債、跨檔一致性與測試反證檢查；未發現尚未處理的阻擋問題。
- 尚未由獨立 verifier 驗收；未修改 PROJECT_BRIEF.md 或勾選全案驗收。下一步是 W6-B 獨立驗收，之後才接 W6-C。
- 未跑 Godot；只對帳既有 W3／W5 前綴，不代表 45 天或所有分支已一致。W6-C／D／E2 守衛保留。

## Verifier 獨立驗收（2026-11-01）

- 結論：**W6-B 已完成並通過驗收**，無 P0／P1／P2；2 項 P3 不阻擋，未修正，列於下方。
- 受驗版本：`main@f4dfd13`（實作 `1672747`＋指揮紀錄）；本段紀錄與文件關門同一 commit 提交，未改程式碼。
- 規則對照：`pickExit` 與 `indulgence.gd` `pick_exit` 逐行一致（beat／slot condition 與 requires、不看 when／地點、排除 auto:false、嚴格大於取來源順序第一、不寫 slots_placed）；`levelFor` 以含本次的次數查 tuning。`indulge` 檢查順序與 `indulge()` 一致（not_run → encounter_active → not_held → not_accepted → unknown_beat → unknown_slot → 無 indulgence → checkSlotState → 泡湯／action_spent），扣卡、扣格、次數先記帳再套 base＋強度效果，整筆提交；`tryPlace` 以原實例 id 轉 `indulge`。
- 強制結算與 `_commit_phase_transition` 一致：night→morning tick 入列，預扣行動格先抵，首個可用行動格才結算；不在手的舊隊首清理，出口無效或效果失敗保留債、卡與格；強制效果進結局後不結算 auto_enter 與遭遇。`loseCard` 對發狂卡刪倒數並累計清卡數，同 `lose_card`。

| 獨立檢查 | 結果 |
|---|---|
| `npm test` | exit 0；18 files／179 tests |
| `npm run build` | exit 0 |
| `npx playwright test --workers=1` | exit 0；14／14 |
| W5／W3 軌跡 | `_qa/web/W6-B-verifier/trace-web.json`：W5 12 checkpoints／560 fields、W3 5／187，皆 equal=true |
| 泡湯預扣變異（verifier） | 換時段抵預扣時 `action_spent` 改 false，泡湯預扣與推進骨架 2 筆轉紅；還原後 git diff 無殘留 |
| 正式產物隔離 | dist JS 無 `__testGame`、`__w6b`、`snap_override`、trace-entry（0 檔） |

- 未重跑：指揮者四組變異（沿用 `_qa/web/W6-B/mutation-*.log`）、Godot。

| 發現 | 等級 | 建議 |
|---|---|---|
| 泡湯 TS 先擋非 morning；Godot 只看剩餘格數，`soak_phase_cost` 調為 1 時 Godot 允許下午泡湯。現值 2 兩者行為相同，TS 依 W6 契約「泡湯限 morning」 | P3 | 接受；若日後調 tuning 為 1，需回頭確認意圖 |
| `settleForcedIndulgenceOnDraft` 回傳的 `ok` 恆為 true，欄位無作用 | P3 | 後續動到該函式時移除或改為真實狀態 |

## 驗收後下一步

- 依 W6 施工順序接 W6-C（委託與隔日回報）。
