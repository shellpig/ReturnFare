# W5-A 卡片、手牌與知識

## 派工範圍與來源

- 日期：2026-11-01；worker：agy／Gemini 3.8 Flash (High)；起點 main@75b2dcb。
- 契約：docs/web/共用契約.md 的架構／驗證／差分；docs/web/W5實作契約.md 的交付範圍、來源定位、三、W5-A；沿用 W3 Game 與 W4 地圖／演出。
- 擴充 cards.ts、state.ts、state-types.ts；新增 HandPanel.tsx、CardDetail.tsx、cards.test.ts、ui/hand.spec.ts，修改 GameShell／styles／strings 的必要接線。
- 卡片普通／slotless／主角／loop_persistent／permanent 按 Godot 最新來源；發狂以可信實例狀態驗顯示，保留尚無 cap／BE 的正常 gain 拒絕，不提前開 W6 玩法。
- 工單與輸出：C:/_work/AI_Work/Tools/agy-runs/agy-W5-A-20261101.prompt.txt、agy-W5-A-20261101.json。

## 必要工程檢查

- Node：cards.test.ts、opening.test.ts；必要時僅加受影響既有案例，不跑整套 npm test。
- UI：hand.spec.ts 正式相簿開局＋可信知識狀態；GameShell 改動另跑 map-panel.spec.ts 的正常 D2 路徑。只用專用 Headless Chromium，禁止 Edge。
- build 與 W3 前綴 5 checkpoints／187 欄位 0 diff；最小關鍵變異紅／綠證據。
- 拒絕與查詢 serialize 前後逐字一致；卡片冪等以實際張數斷言；測試注入不得進正式產物。

## 指揮者審核修正

- 初輪實作檔案均在白名單內，沒有修改正式資料、Godot、effect.ts、panel.ts、基線、依賴或 verifier 文件。
- 指揮者發現初輪 UI 測試標題宣稱零副作用，但只比手牌數或知識集合；未量測彈窗 bounding box。退回同一 agy conversation 補完整 serialize 前後逐字比較、1280x720／1280x800 彈窗邊界與 tuning 上限來源；另補知識與發狂指定實例移除／重複拒絕案例。補充只動兩個測試檔，沒有增加產品能力。
- 所有程式與測試由指定 agy worker 完成；指揮者未代寫主要實作。

## 交付與測試證據

- Worker：Gemini 3.8 Flash (High)，conversation a6c5d184-5955-4a72-83a1-3a95c0b594a8；2 輪，同一對話。CLI 兩次皆 exit 0。第一輪約 698 秒，補充後回報累計約 859 秒；輸出檔與 followup 檔留在 repo 外 agy-runs。
- 新增 CardView 與 Game.hasCard／hasKnowledge／handSlotsUsed／handCapacity／cardView／handView／knowledgeView；卡面從正式 cards 投影、查詢純度與回傳唯讀保護、知識順序維持來源。loseCard 按指定實例或知識移除，loop_persistent 普通／永久及先普通後永久語意依來源實作；主角拒絕零副作用。
- HandPanel 在 run 模式的演出／地圖／地點畫面呈現手牌、容量及獨立知識入口；CardDetail 共用唯讀彈窗，按鈕或 Escape 關閉。測試快照只在 Playwright route wrapper 內注入，不加正式 hook。
- 發狂 gain 維持 not_implemented 守衛；只補可信多實例投影與既有 lose 記帳，未接倒數推進、cap／BE 或縱慾等 W6 玩法；effect.ts 未接放卡／lose 效果。

| 指揮者工程檢查 | 實際結果 |
|---|---|
| npx vitest run tests/cards.test.ts tests/opening.test.ts | exit 0；2 files／17 tests（cards 12＋opening 5），正式相簿開局主角與相簿各一張；移除與查詢零副作用、跨輪物品、指定實例與知識均有斷言 |
| npm run build | exit 0；19 份 JSON、22 條資料規則、0 errors／4 筆既有豁免 warnings，tsc／Vite 通過。之後補充僅測試斷言，產品程式未再改動 |
| npx playwright test tests/ui/hand.spec.ts tests/ui/map-panel.spec.ts --grep "normal album\|separate trusted\|D2 morning" --workers=1 | exit 0；3／3；手牌與知識 2 案例＋既有 D2 正常地圖演出 1 案例。正常相簿 1280x720，可信知識 1280x800；彈窗邊界、關閉／Escape、全 flow/run/meta serialize 前後逐字一致 |
| W3 前綴 | 以 production buildWebTrace／compareTraces 在記憶體中依 tools/trace/scopes/W3.json 對 Godot 基線；exit 0，5 checkpoints／187 fields，equal=true。未改基線或 ignore |
| 最小變異 | 指揮者以 Vite transform 與獨立 cacheDir，在記憶體中反轉 loseCard 主角守衛，命中 1 次；cards 3 failed／9 passed、exit 1（含主角保護斷言）。取消後僅重跑 cards 12／12、exit 0；無原始碼變異殘留 |
| 正式產物隔離與範圍 | dist JS 無 __w5aGame、__w5a_snap_override__、loadTrustedSnapshot、舊測試橋接標記；git diff --check 通過。未跑整套 npm test、全套 UI 或 Godot |

## 未解問題與下一步

- 工程檢查已完成，交 verifier 獨立驗收 W5-A；指揮者不標記驗收完成，不修改 PROJECT_BRIEF.md。
- W5-B／C 及 W6 玩法仍未實作；既有日期／機制守衛未放寬。
- 本輪沒有已知工程檢查失敗；驗收結論由 verifier 決定。
