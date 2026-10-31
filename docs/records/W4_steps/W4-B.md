# W4-B 白天地圖、地點面板與卡槽三態

## 範圍與來源

- 日期：2026-10-31；起點：`main@be6fcee`。
- 契約：`docs/web/共用契約.md`「二、架構與資料邊界」「三、快速檢查」「四、必要驗證的取捨」；`docs/web/W4實作契約.md`「一、交付範圍與順序」「二、必讀與對照來源」「四、W4-B：白天地圖與面板」「五、軌跡與交接」；`docs/web/W5實作契約.md`（預對齊卡槽唯讀與 W5 放卡／選邊邊界）。
- 參照來源（唯讀）：`scripts/core/panel_builder.gd`、`scripts/autoload/game_state.gd`（`available_locations`、`mark_day_location_visited`、`remaining_actions_today`）、`scenes/ui/map_list.gd`、`scenes/ui/location_panel.gd`、`scenes/main.gd`、`實作規格書.md`（第四、五節與 P1-G）、`開發設計方針.md`（P1-G、T-03）、`data/SCHEMA.md`（三態可見性、`locations.json`、`slots[]`）。
- 可動檔案：
  - 新增：`web/src/core/panel.ts`、`web/src/ui/MapPanel.tsx`、`web/src/ui/LocationPanel.tsx`、`web/src/ui/SlotView.tsx`、`web/tests/panel.test.ts`、`web/tests/ui/map-panel.spec.ts`、`docs/records/W4_steps/W4-B.md`
  - 修改：`web/src/core/state-types.ts`、`web/src/core/state.ts`、`web/src/ui/GameShell.tsx`、`web/src/ui/strings.ts`、`web/src/ui/styles.css`、`web/tests/ui/narration.spec.ts`（配合 `D2 morning` 白天地圖開啟調整末尾斷言）、`docs/records/W4實作紀錄.md`

## 實作摘要與公開 API

- `web/src/core/panel.ts`（純 TS 規則層）：
  - 匯出 `TriState`（`HIDDEN = 0`、`LOCKED = 1`、`OPEN = 2`、`RESOLVED = 3`）、`MapLocationView`、`PanelView`、`BeatView`、`SlotView`。
  - `availableLocations(state, data)`：於非夜間且非純演出時段回傳 `layer === 'day' || layer === 'both'`、`chapter <= currentChapter` 且 `phases` 含當前時段的地點 ID（保持 `data.locations` 來源順序）。
  - `remainingActionsToday(state)`：`morning` 依 `action_spent` 與 `actions_spent_ahead > 0` 回傳 `0..2`，`afternoon` 依 `action_spent` 回傳 `0..1`，其餘時段回傳 `0`。
  - `buildPanel(locationId, state, data)`：依序評估當前時段掛在該地點的 beat（`condition` 不過 → `HIDDEN` 省略；`requires` 不過 → `LOCKED` 並取 `reject_reason || '（條件不足）'`；否則 `OPEN`）與其 `slots`（先處理已結算 `choice_group` 收起未選項目並保留已選項目為 `RESOLVED`；再評估 `slot.condition`、`slots_placed`、`slot.requires` 與 `indulgence.soak` 行動格門檻；若 beat 為 `LOCKED`，底下未 `RESOLVED` 的 slot 一併降為 `LOCKED` 並繼承 beat 理由）。`acceptTypes` 將具體卡 ID 反查 `card.type`、去重保序後轉成 `cardTypesById` 中文名稱。`occupant` 結合 `npcs.json`（含 `locked_name`／`reveal` 條件）與 `cards.json` 解析顯示名稱。
  - `mapView(state, data)`：對 `availableLocations` 計算 `enabled = buildPanel(locId).beats.length > 0 || state.meta.day_locations_visited[locId] === true`。所有查詢皆零副作用。
- `web/src/core/state-types.ts` 與 `web/src/core/state.ts`：
  - 於 `Game` 公開 `availableLocations()`、`mapView()`、`buildPanel(locationId)`、`remainingActionsToday()` 與顯式變更命令 `markDayLocationVisited(locationId)`。
  - `markDayLocationVisited(locationId)` 與 `playBeat()` 共用 `recordDayLocationVisitedOnDraft`：僅在 `locationId` 非空、存在於 `data.locationsById` 且 `layer === 'day'` 時寫入 `meta.day_locations_visited[locationId] = true`。
- `web/src/ui/`（`MapPanel.tsx`、`LocationPanel.tsx`、`SlotView.tsx`、`GameShell.tsx`、`strings.ts`、`styles.css`）：
  - 白天行動時段顯示地圖底圖（`/art/map/town.webp`）與地點按鈕列表；未造訪且無可見 beat 的空地點為 `disabled`。
  - 點開可用地點時，於點擊處理器顯式呼叫 `markDayLocationVisited(locationId)`；若有 `OPEN` beat 則立即呼叫 `playBeat()` 進入第一階段演出（不提前渲染 `desc` 與卡槽），每次點「繼續演出」重新 `buildPanel()` 找下一筆未播出的 `OPEN` beat，全部播完後進入第二階段常態面板顯示 `location.desc`、beat 標題／鎖定理由與唯讀 `SlotView`（以 `、` 連接 `acceptTypes`，無放卡／選邊提交按鈕）。有對應場景圖的地點顯示 `/art/scenes/<id>.webp`，無場景圖的地點（如 `upstream`）以純文字版面呈現。

## 實作者驗證證據

| 檢查項目 | 結果 |
|---|---|
| `npm test`（cwd `web/`） | exit 0；10 files、67 tests 全綠（含新增 `panel.test.ts` 5 tests 及既有 `condition.test.ts`、`opening.test.ts`、`narration.test.ts`、`state.test.ts`） |
| `npm run build`（cwd `web/`） | exit 0（`sync-data.mjs` → `npm run lint:data` → `tsc --noEmit` → `vite build`） |
| `npm run test:ui`（cwd `web/`，Headless Chromium 連續兩次） | exit 0；兩次皆為 5 passed（`opening.spec.ts` 2、`narration.spec.ts` 1、`map-panel.spec.ts` 2） |
| `npm run trace:web` + `npm run trace:compare`（`tools/trace/scopes/W3.json`） | exit 0；`comparedCheckpoints=5 comparedFields=187 equal=true`（產物 `_qa/web/trace-web-w4b.json`） |
| 變異檢查（`panel.ts` beat `LOCKED` 下傳移除） | 暫時註解 `web/src/core/panel.ts` 的 `beatTri === TriState.LOCKED` 對 slot 的下傳邏輯，執行 `npx --prefix web vitest run tests/panel.test.ts` 立即轉紅（exit 1，`d19_pm_upstream.look` 斷言失敗）；還原後重跑 67 tests 全綠 |
| 邊界檢查 | `git status` 確認 `data/`、Godot `scripts/`／`scenes/`、`web/public/art/`、`tools/trace/baselines/greedy-godot.json` 零改動 |

## Verifier 獨立驗收與複驗（2026-10-31）

- 結論：**W4-B 已完成並通過驗收，W4 整體關門**；原 P2 已修正，未發現其他阻擋或非阻擋問題。
- 受驗版本：乾淨的 `main@548710c`；W4-B 程式與測試提交為 `a7c33f8`。`548710c` 為獨立夜間場景素材提交，不屬本次驗收範圍。
- 首輪曾發現 P2：GameShell 無條件掛出全域測試橋接，並新增公開 loadTrustedSnapshot，導致正式 bundle 包含直接覆寫狀態的測試入口。修正後移除正式 API／橋接，高日數 UI 案例改由 Playwright route 攔截 state 模組，包裝原 createGame 並以既有 initialState 注入可信快照；測試繼續走 production Game 與實際點擊。
- 複驗重新核對 W4-B 完整範圍：API／型別、map／panel 查詢純度、beat／slot 三態順序、choice／RESOLVED、泡湯行動格、正式文字與卡型展示、到訪雙入口與通知、逐段演出／重看、來源與檔案邊界、錯誤及測試注入隔離。

| 獨立檢查 | 結果 |
|---|---|
| `npx vitest run tests/panel.test.ts` | exit 0；1 file／5 tests；取消變異後同範圍重跑仍為 5／5；未跑全套 npm test |
| `npx playwright test tests/ui/map-panel.spec.ts tests/ui/narration.spec.ts --workers=1` | exit 0；3／3；專用 Headless Chromium。含正常 opening → D2 morning → 山泉閣立即演出／演完出槽／重開，以及 D19 LOCKED upstream 點擊到訪且 playBeat 0 次 → D20 空點仍可開。另驗受本步修改影響的 W3 演出接線；未跑 opening.spec.ts 或其他 UI 測試 |
| `npm run build` | exit 0；19 份 JSON 同步、22 條 lint，0 errors／4 筆既有豁免 warnings，型別與 Vite 建置通過 |
| 正式入口隔離 | 正式 Game 無 loadTrustedSnapshot；檢查實際 dist/assets JS，舊橋接、快照載入方法與新 Playwright 注入用的 6 個標記均不存在 |
| W3 前綴軌跡 | 在記憶體中直接呼叫 production buildWebTrace／compareTraces，沿 tools/trace/scopes/W3.json 對正式 Godot 基線：exit 0，5 checkpoints／187 fields、0 diff；未新增 checkpoint、擴大 ignore 或重產基線 |
| 最小變異保真 | 使用 Vite transform 與獨立快取目錄，在記憶體中停用 beat LOCKED 對 slot 的傳導，命中 1 次；panel.test.ts 的 d19_pm_upstream.look 斷言轉紅（exit 1，1 failed／4 passed）。取消變異後相關 5 tests 全綠，未修改原始碼 |
| 邊界與清理 | git diff --check 通過；正式 data、Godot 與黃金基線未改；工作區乾淨，Playwright 測試服務已關閉（4178 無 listener） |

- 驗收界線：只驗 W4-B 與必要 W3 回歸；不代表高日數已可從正常開局遊玩、不含 W5 放卡／選擇／預覽、未跑 Godot 或全套 Node／UI 測試。文件關門階段沿用上述複驗證據，未重跑測試。

## 下一步

- 依 `docs/web/W5實作契約.md`「三、W5-A：卡片、手牌與知識」接續實作；沿用已驗收的 Game、map／panel VM 與逐段演出接線，不另建平行規則。
