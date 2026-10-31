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

## Verifier 獨立驗收與修正（2026-11-01）

- 結論：**W5-A 已完成並通過驗收**。首輪發現 1 項 P2（既有 UI 測試轉紅），經使用者授權由 verifier 直接修正測試斷言並複驗；產品程式未改動。
- 受驗版本：`main@91b4a0d`；W5-A 程式與測試提交為 `68ba95e`。`75b2dcb`、`b4d85f1`、`91b4a0d` 為獨立夜間場景素材提交，不屬本次驗收範圍。
- 規則對照：`gainCard`／`loseCard`／`hasCard`／`hasKnowledge`／`handSlotsUsed` 與 `game_state.gd` 同名函式逐分支一致（slotless 冪等、普通卡 unique、主角拒絕、loop_persistent 普通／永久與先普通後永久、發狂實例移除記帳）；發狂 gain 仍維持 not_implemented 守衛。`CardView` 正文只來自 cards，以 instanceId 作 key；知識沿 meta.knowledge 取得順序；容量讀 tuning `hand_size`。
- UI 對照：手牌與知識分區，詳情彈窗按鈕／Escape 關閉；HandPanel 於 opening／ending 不顯示，與 Godot `main.gd` 的 HandBar 可見性一致。
- 首輪 P2：`tests/ui/narration.spec.ts` 以「全頁按鈕數為 1」守純演出畫面，W5-A 依契約在演出畫面加入手牌面板後變為 3，`npm run test:ui` 失敗；實作端只跑 map-panel 的 D2 案例而未發現。修正：兩處斷言縮為排除 `.hand-panel` 內按鈕，原本「演出時沒有地圖／卡槽操作」的守衛不變。此檔不在 W5-A 白名單，由使用者授權 verifier 修改。

| 獨立檢查 | 結果 |
|---|---|
| `npm test` | exit 0；11 files／79 tests |
| `npx vitest run tests/cards.test.ts tests/opening.test.ts` | exit 0；2 files／17 tests |
| `npm run build` | exit 0 |
| `npm run test:ui -- --workers=1`（修正後） | exit 0；7／7。修正前 narration.spec 1 failed（Expected 1，Received 3） |
| `trace:web` + `trace:compare`（`tools/trace/scopes/W3.json`） | exit 0；`comparedCheckpoints=5 comparedFields=187 equal=true`（產物 `_qa/web/trace-web-W5A-verifier.json`） |
| 正式產物隔離 | `dist/assets` JS 無 `__w5aGame`、`__w5a_snap_override__`、`loadTrustedSnapshot` |
| 規則變異 | 暫改 `handSlotsUsed` 將知識計入佔格，cards.test.ts 1 failed／11 passed；`git checkout` 還原後 12／12 |
| 測試修正變異 | 暫在 NarrationPanel 多插一顆按鈕，修正後的 narration.spec 轉紅（Expected 1，Received 2）；還原後 1／1 |

- 驗收界線：只驗 W5-A 與受影響的 W3／W4 UI 回歸；不含 W5-B 放卡／效果、W5-C 選擇與 W6 發狂玩法；未跑 Godot。

## 下一步

- 依 `docs/web/W5實作契約.md`「四、W5-B：交易、放置、預覽與行動格」接續實作；派工時把會受新 UI 影響的既有 UI spec 一併列入必跑範圍。
