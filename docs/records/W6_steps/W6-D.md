# W6-D 遭遇 — 指揮交付紀錄

## 派工範圍與輸入

- 日期：2026-11-01；worker：agy Gemini 3.8 Flash (High)；起始 main@0151d06。
- 契約：`docs/web/共用契約.md`；`docs/web/W6實作契約.md` 一、二、七及九的當步規則。
- 前置：W6-E1／A／B／C 已驗收；E2 尚未實作，不擴大 trace 前綴、不改結局整合。
- 交付：純 TS 遭遇查詢與候選、Game 狀態機與交易、D8 night／D45 afternoon 正式 transition、EncounterPanel 與共用卡片詳情、Node／UI 測試、greedy helper。
- 必驗：正式 D8／D45 各由前時段 advancePhase 啟動；intro、回應、出口、錯答、丟棄、逃離、容量；重複 base／未持有／不可丟卡拒絕 serialize 不變；一次性效果與不洩漏答案；UI 確認取消及阻擋日常推進。
- 指揮 gate：npm test、build、UI、W3／W5 前綴對帳；移除 transition 遭遇接線，生命週期測試須轉紅，還原後重跑。
- 修改白名單：web/src/core/{encounter,state,state-types,effect,cards,panel}.ts、web/src/ui/{EncounterPanel,GameShell,CardDetail,HandPanel}.tsx、必要既有 UI stylesheet、web/tests/encounter.test.ts、web/tests/ui/encounter.spec.ts、web/tests/support/greedy.ts；若需其他程式檔先列理由交指揮者。
- 禁止：改正式 data、Godot、基線、依賴、契約、PROJECT_BRIEF 與 verifier 文件；不替自己勾驗收。

## 交付與審核

程式交付：`7eb3d98`；指揮者最後的壞定義丟棄修正：`12f6aed`。下列最終 gate 在相同工作樹內容上執行，提交後 `git diff -- web/` 為空；本紀錄不替 verifier 勾驗收。

- 核心對話：`e0f66b0f-ab69-4505-b452-01d7d581ee70`；UI／greedy 對話：`7d8738fa-036a-45f9-b280-3d3c2a56bc5f`。模型均 Gemini 3.8 Flash (High)，未使用 subagent。
- 首輪約 18:34～18:43 無程式改動後停止；核心重送 18:44，18:49 接續同對話改 stream-json，約 19:02 交付。UI 約 19:02～19:16 完成，worker 回報 duration 825.7 秒。未證明首輪停滯根因。
- worker 核心交付：encounter 純查詢／候選、Game 生命週期與交易、Game API／拒絕碼、11 個正式資料規則測試；build 通過，既有 night 有兩個待改的 W6-D 守衛斷言。
- 指揮修正：effect plan 會 clone snapshot，回應進下一回合前須重綁 active encounter，容量判定才看到新壓力；效果預演失敗立即原子拒絕。VM 型別放回 encounter 模組並由 state-types 重匯出；去掉新增的 tuning／cost 假預設。
- 指揮修正：遭遇 intro／round 阻擋 playBeat／playEvening／playNightFixed 及日間到訪記帳。D45 intro 由 PhaseView 提供正式 beat text，不新增 VM 的答案或未到回合欄位。
- 補測至 18 個案例：最新回合容量、hand／knowledge attempted 與嚴格 VM keys、發狂卡／未持有拒絕、三出口累加 relation 恰一次、壞出口支付原子性、ending 壓住 after_finish、intro／round 非遭遇操作零變化。

## 指揮者驗證證據（核心暫存版本）

- `npm --prefix web test -- encounter.test.ts`：18／18，exit 0；Node build exit 0，資料 lint 22 規則、0 errors／4 筆既有豁免 warnings。
- lifecycle 變異：移除 daytime transition 的 startEncounterOnDraft 接線，D45 生命週期案例 exit 1；逐 byte 還原。
- draft 變異：移除 effect 預演後重新綁定 active encounter，新增容量案例 exit 1；逐 byte 還原。
- multiplicity 變異：將出口 blocks 重複兩次，三種出口累加斷言 exit 1；逐 byte 還原後 encounter 18／18 全綠。
- 變異 log：repo 外 `C:/_work/AI_Work/Tools/agy-runs/W6-D-mutation-{lifecycle,draft,once}.log`。
- `trace:web -- --output ../_qa/web/W6-D/trace-web.json`：12 checkpoints。W5 scope 12 checkpoints／560 fields、W3 scope 5／187，均 equal=true、exit 0，ignorePaths 空。這不是完整 45 天對帳。

## 最終整合交付與審核

- EncounterPanel 接 intro／round、壓力 placeholder、手牌／知識候選與 disabled 理由、CardDetail、提交／丟棄／逃離確認及取消。GameShell 優先路由遭遇並保留出口結果文字；介面詞彙取 Godot 來源，統一在 strings.ts。
- greedy 只讀候選 VM，不偷看 accepts，完整迴圈處理遭遇；仍 active 時明確報錯。既有 night 測試移除 W6-D 未實作假設，改驗 D8 自然入夜、首次收費與結算。
- 指揮 UI 修正：取消快照移到開啟預覽前，另驗逃離支付取消；使用非 optional 的測試 game，避免 undefined 自比。移除 UI 重複的 madness 判斷與從地圖反查 intro 的備援，直接讀 PhaseView；拒絕碼文字依 Godot 原文。intro 確認成功後清掉已讀入夜旁白，避免出口後重播開場。
- 最終丟棄交易修正：拒絕遺失 encounter／round 的壞定義，不再用空物件補值；回歸斷言完整 serialize 不變。
- 正式 D45 推理卡轉知識補測：從前時段進遭遇，依正式 response 的 lose/gain 衍生斷言，舊卡移除、知識不佔手牌、自動推進一次；D45 主角回應亦確認主角留手。
- worker 首輪 UI 1／2，錯誤為 D45 evening 誤斷言 narration-shell；改驗 daytime-shell 與日期／傍晚後 2／2，worker 全套 UI 18／18。worker 曾違反 prompt 的「瀏覽器失敗先停並回報」而自行重跑；未啟用 Edge，設定始終為專用 headless Chromium。本項為派工程序偏差，非機器驗收通過的替代證明。
- worker trace CLI 曾漏 scope／誤把 12 當 scope 檔，均非玩法差分；指揮使用 W3.json／W5.json 正確範圍重跑。worker 放錯的 web/_qa/web/trace-web.json 已移至 ignored _qa/web/W6-D/worker-trace-web.json，未進 repo。

### 指揮最終 gate（2026-11-01，約 19:18～19:23）

| 檢查 | 結果 |
|---|---|
| `npm --prefix web test` | exit 0；20 files／210 tests，其中 encounter 19 tests |
| `npm --prefix web run build` | exit 0；22 lint 規則、0 errors／4 筆既有豁免 warnings；TS／Vite 通過 |
| `npm --prefix web run test:ui` | exit 0；18／18，含兩條遭遇 UI 與逃離支付取消；專用 headless Chromium |
| `trace:web` ＋ W5.json scope | exit 0；12 checkpoints／560 fields，equal=true |
| W3.json scope | exit 0；5 checkpoints／187 fields，equal=true |
| 正式 bundle 掃描 | dist 無 __testGame／__w6d_snap／__origCreateGame／createRunForTrace／trace-entry |
| 三組最小變異 | transition 接線／effect draft 壓力／出口重複效果均 exit 1；逐 byte 還原後相關測試全綠 |

### 審核範圍與限制

- 已核對 W6-D 與必要 P4-D／E／F 契約、Godot 同名 API／檢查順序、schema、D8／D45 真實生命週期、拒絕原子性、效果基數、VM 白名單、UI 接線與測試隔離。未留下已知阻擋事項；不替 verifier 作獨立驗收結論。
- VM／規則不曝光未到回合與 accepts；支付與出口共用既有 draft transaction。after_finish 沿 Godot 在操作交易外呼叫同一 advancePhase；若後續推進拒絕，不回滾已成功的遭遇結算。
- D8 入夜仍依 Godot 分工：advancePhase 到 night，再由 playNightFixed 強制到訪／收費／演出／啟動；GameShell 與 greedy 均走此管線。超載開場立即 failure 的現行 P4-D 契約優先於舊 prose penalty 描述。
- 正式 data、Godot、基線、依賴、契約與 verifier 文件未修改。未跑 Godot、未做完整 45 天／跨輪走查或真人體感；本步不擴 trace 前綴。E2、W7 尚未交付。
- 此為指揮交付工作紀錄，不替 verifier 勾選驗收，不改 PROJECT_BRIEF.md；E2 與全程 runner 保留。
