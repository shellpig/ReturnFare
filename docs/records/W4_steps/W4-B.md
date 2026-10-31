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

## 下一步

- 提交 verifier 進行 W4-B（及 W4 階段）驗收；通過後進入 W5（手牌、備用區、放卡／選邊交易與推進時段三態提示）。
