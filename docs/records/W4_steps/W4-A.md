# W4-A `ConditionEval` 全語彙補齊

## 範圍與來源

- 日期：2026-10-31；起點：`main@fac9fc3`。
- 契約：`docs/web/共用契約.md`「二、架構與資料邊界」「三、快速檢查」「四、必要驗證的取捨」；`docs/web/W4實作契約.md`「一、交付範圍與順序」「二、必讀與對照來源」「三、W4-A：完整條件求值器」「五、軌跡與交接」。
- 參照來源（唯讀）：`scripts/core/condition_eval.gd`、`scripts/autoload/game_state.gd`（`has_card`、`has_knowledge`、`night_location_seen`、`ending_seen`、`relation_at_least`）、`data/SCHEMA.md`（`condition` / `requires` 語彙）、`data/relation_scale.json`。
- 可動檔案：
  - 修改：`web/src/core/condition.ts`、`web/src/core/cards.ts`、`web/tests/state.test.ts`（僅將 W3 子集對 `flag` 拋 `UnsupportedConditionError` 的舊斷言更新為 W4-A 正式求值與未知運算子拋 `ConditionError`）
  - 新增：`web/tests/condition.test.ts`、`docs/records/W4實作紀錄.md`、`docs/records/W4_steps/W4-A.md`

## 實作摘要與公開 API

- `web/src/core/cards.ts`：將 `hasCard`、`hasKnowledge`、`handSlotsUsed` 的 `state` 參數型別調整為 `DeepReadonly<GameSnapshot>`（相容 `GameSnapshot` 與 `getSnapshot()` 回傳之深層凍結快照），並以 `=== true` 嚴格檢查 `meta.knowledge[cardId]`。
- `web/src/core/condition.ts`：
  - 保留單一主入口 `evalCondition(condition: Condition | null | undefined, state: DeepReadonly<GameSnapshot>, data: GameData): boolean`，以及輔助純查詢 `hasSeenEnding`、`hasSeenNightLocation`、`relationAtLeast`。
  - 完整支援 `web/src/data/vocabulary.ts` 的全部 17 個 `CONDITION_OPERATORS`：`day`、`day_at_least`、`has_card`、`has_knowledge`、`switch`、`switch_progress_at_least`、`flag`、`relation_at_least`、`madness_at_least`、`count_at_least`、`not`、`all`、`any`、`night_seen`、`opening_choice`、`ending_seen`、`festival_proxy_is`。
  - 語意對齊 Godot：頂層 `null`／`undefined` 為 `true`；`all: []` 為 `true`、`any: []` 為 `false`；`has_card` 僅查 `run.hand` ∪ `meta.knowledge`，不從 `data.cardsById` 存在推導持有；`relation_at_least` 查 `data.relationScale` 整數門檻（未記錄關係之 NPC 預設為 `0`，未知狀態或 `_comment` 拋 `ConditionError`）；`madness_at_least` 計 `Object.keys(state.run.madness_clock).length`。
  - 拒絕契約：非單鍵物件、未知運算子鍵、運算元型別不符或複合條件內含 `null`／壞子條件時，一律拋出 `ConditionError`（`reason_code = 'data_conflict'`），且 `all`／`any` 不因短路而吞掉後續壞子條件，絕不預設為 `true`。

## 實作者驗證證據

| 檢查項目 | 結果 |
|---|---|
| `npm test`（cwd `web/`） | exit 0；9 files、62 tests 全綠（含新增 `condition.test.ts` 7 tests 及 W3 既有 `opening.test.ts`、`narration.test.ts`、`state.test.ts`） |
| `npm run build`（cwd `web/`） | exit 0（依序執行 `sync-data.mjs` → `npm run lint:data` → `tsc --noEmit` → `vite build`） |
| `npm run trace:web` + `npm run trace:compare`（`tools/trace/scopes/W3.json`） | exit 0；`comparedCheckpoints=5 comparedFields=187 equal=true`（產物 `_qa/web/trace-web-w4a.json`） |
| 變異檢查（正式面板 `requires` 反轉） | 於 `web/src/core/condition.ts` 分別暫時反轉 `has_card`（影響 `d3_pm_sanquan::show_version.requires`）與 `has_knowledge`（影響 `d19_pm_upstream.requires`），執行 `npx vitest run tests/condition.test.ts` 均立即轉紅（exit 1，2 failed）；還原後重跑 `npm test` 62 tests 全綠 |
| 邊界檢查 | `git status` 確認 `data/`、Godot `scripts/`／`scenes/`、`tools/trace/baselines/greedy-godot.json` 零改動 |

## Verifier 獨立驗收（2026-10-31）

- 結論：**W4-A 已完成並通過驗收**；未發現阻擋或非阻擋問題。
- 受驗版本：`main@fac9fc3` 上的未提交 W4-A 改動；驗收後相同程式與測試提交為 `e3ac9b8`。文件關門與提交階段未重跑測試。
- 完成核對：契約與檔案範圍、17 個運算子及 Godot 語意、W2 型別與語彙單一來源、唯讀快照與純 TS 邊界、查詢與拒絕零副作用、既有 Game／EffectApply 錯誤處理接線、正式資料與 W3 開局回歸、測試保真及 Windows 路徑。

| 獨立檢查 | 結果 |
|---|---|
| `npm test` | exit 0；9 files／62 tests；含 W3 正式開局與演出案例。取消變異後再次全綠 |
| `npm run build` | exit 0；19 份 JSON 同步、22 條資料規則、0 errors／4 筆既有豁免 warnings，型別與 Vite 建置通過 |
| W3 軌跡 | 直接呼叫 production `buildWebTrace()` 與 `compareTraces()`，依 `tools/trace/scopes/W3.json` 在記憶體中對正式 Godot 基線；exit 0，5 checkpoints／187 fields、0 diff；未新增軌跡檔或重產基線 |
| 正式門檻變異 | 以 Vite transform 與獨立快取目錄在記憶體中僅反轉 `d19_pm_upstream.requires` 的 has_knowledge 結果，變異命中 1 次；condition.test.ts 的正式 requires 斷言轉紅（exit 1，1 failed／6 passed）。原始碼未改動；取消變異後全套 62 tests 通過 |
| 狀態與檔案邊界 | 持有／關係／巢狀／錯誤查詢前後 serialize 一致；git diff --check 通過；正式 data、Godot 與黃金基線零改動 |

- 覆蓋界線：本步為條件求值器驗收；不含 W4-B 面板／地圖 UI，不以高日數快照宣稱玩家能走到該日。依 W4-A 契約未重跑瀏覽器或 Godot 全套。

## 下一步

- 依 `docs/web/W4實作契約.md`「四、W4-B：白天地圖與面板」實作 W4-B；W4-A 不需重做。
