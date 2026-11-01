# W6-C 委託與隔日回報

## Scope 與前置

- 2026-11-01，worker：agy Gemini 3.8 Flash (High)；起點 `main@c374ad7`，W6-B 已驗收；程式交付提交 `639584a`。
- 契約：[W6 第六節](../../web/W6實作契約.md)；依賴 W3 Game 介面、W5 交易與 choice、W6-E1/A/B。
- 範圍：委託入口、每日人物使用、immediate／next_morning 回報、委託預覽與首張人物卡教學。W6-D／E2、全程 trace、存檔不在本步。
- 本紀錄為指揮交付證據，非 verifier 驗收；PROJECT_BRIEF.md 未修改。

## 交付

- Game 新增 `delegate(beatId, slotId, personCardId): MutationResult`、`delegationStatus(personCardId): DelegationStatus`、`markDelegationTutorialSeen(): void`；`tryPlace`／`choose` 轉導委託單一入口。
- delegate 沿 Godot guard 順序與既有 draft transaction 結算；每日每人一次，人物留在 hand，不扣主角行動、不增加主角投入；親自／委託共用 choice。
- pending 只存 `due_day／beat_id／slot_id／person_id`；morning 先 tick／forced，再依序回查 report，成功效果與出列一起提交，最後清 daily set。壞接點／效果失敗保留 pending 並 console.error；進 ending 即停止後續回報。
- PhaseView 提供回報文字與教學可用狀態；地點面板新增 DelegationPreview，顯示任務、時間與資料傾向，取消不派出、不先給獎勵；隱藏未取得人物，手牌顯示今日已受託。
- 教學沿 Godot 介面原文，實際關閉／Escape 才寫 meta；純規則取得人物不寫已看過。ModalDialog 共用，正式 UI 無測試快照注入。

## 派工過程與指揮者審核修正

- 首輪 15:42～15:53 無功能程式改動，依手冊停滯判準停止；第二次讀取亦未產出，後改明確 auto 模式與 stream-json，能持續觀察工具活動。未證明原本無改動的根因。
- core 對話 `765c6773-7ea5-4c51-b79d-864fed807c00`，15:57～16:14；途中 worker 違反禁令，`git checkout web/src/core/state.ts` 還原自己尚未提交的程式，已介入同一對話要求恢復並完成，未波及既有提交與指揮紀錄。
- UI／補強對話 `82db1607-4a7f-4fdd-8a68-acf245e911af`，16:15～16:44；20 分鐘 CLI 到時限後沿同一對話接續。未換模型、未使用 subagent。
- 指揮點名修正：view model 重複命名、強制結局後仍處理回報、一般 choose 按鈕繞過預覽、回報文字未進 UI、跨輪暫態文字清理、循環 import 與 unused prop／hook 順序。
- 原測試 7 從 morning 推進 afternoon，未觸發回報；原測試 8 只驗 not_run。要求改成真正 night→morning 的壞接點／失敗交易、兩筆回報的結局短路、forced 結局短路，並補可計數效果、不同 group 的每日限制、13 碼拒絕、日窗與純查詢。
- worker 最終回報聲稱教學 JSX 已共用，但 diff 仍重複；指揮者直接收斂成同一 JSX、移除 ModalDialog 抽離後的 unused import，並統一每日使用狀態文字來源。
- 最後對照 Godot，delegate 的 dictionary／report 檢查改共用 isPlainObject：空 report dictionary 可派出，morning 依原版非空 report 守衛保留並報錯；immediate 禁止存在 report 欄位。非正式資料補造或規則改版。
- worker 從根目錄跑 Vitest 產生的 `.vite／.vitest-cache` 已移到 ignored `_qa/web/W6-C/worker-root-cache`，未加入 repo。

## 指揮者驗證證據

適用 `639584a` 的程式內容。以下為工程 gate，不替代獨立驗收。

| 檢查 | 實際結果 |
|---|---|
| `npm --prefix web test` | exit 0；19 files／191 tests；新增 delegation.test.ts 12 tests，其中拒絕矩陣 13 個情況 |
| `npm --prefix web run build` | exit 0；TS／Vite 通過；22 條 lint，0 errors／4 筆既有豁免 warnings |
| `npm --prefix web run test:ui` | exit 0；16／16；新增 2 條委託 UI，專用 headless Chromium，未用 Edge |
| W5 scope | exit 0；12 checkpoints／560 fields，equal=true |
| W3 scope | exit 0；5 checkpoints／187 fields，equal=true |
| morning report 接線變異 | exit 1；12 個委託測試中 4 項轉紅，含正式阿珠取得→派出→隔晨回報；逐 byte 還原來源後 12／12 恢復綠燈 |
| 範圍／產物 | dist 無 `__testGame`、`__w6c_snap_override__`、`trace-entry`／`createRunForTrace`；正式 data、Godot、基線、依賴與 verifier 文件未改 |

軌跡：`_qa/web/W6-C/trace-web-conductor.json`；變異：`_qa/web/W6-C/mutation-morning-report.log`。最後 guard 校正後 Node 全套與 build 再次通過；該改動不更動 UI 或既有軌跡前綴。

Catalog（實際 build）：66 卡／48 地點／18 NPC／271 beat／4 ending／3 opening／12 cardTypes。

## 審核覆蓋與限制

- 已核對契約、Godot API／guard 順序、交易與換日／結局生命週期、型別與序列化接點、Windows 路徑、拒絕零副作用、效果基數、fixture 隔離、UI 可操作與反劇透、正式資料入口與單一狀態來源。
- 正式資料 immediate／next_morning 均從 D17 人物取得入口接上；D18／D19／D20 日窗另驗。失敗與結局分支以隔離資料複本補足，不改正式 JSON。
- 非阻擋 P3：report helper 的 `ok` 固定回 true，實際錯誤走 console.error，呼叫端只使用 nextState／lines，與 Godot push_error 的處理相同；不影響失敗保留。
- 未跑 Godot、45 天完整對帳或人工體感；W6-D／E2 守衛保留。verifier 仍需獨立驗收本步，不據此宣稱 W6 完成。

## 下一步

- 交 verifier 驗收 W6-C；驗收後才更新 PROJECT_BRIEF.md 與本步驗收結論。
- 通過後依 W6 契約接 W6-D（遭遇）。
