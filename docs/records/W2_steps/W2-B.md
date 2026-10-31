# W2-B build-time 資料 lint

## 範圍與來源

- 日期：2026-10-31；起點：`main@49799a0`。
- 契約：`docs/web/共用契約.md`「二、架構與資料邊界」「三、快速檢查」；`docs/web/W2實作契約.md`「四、W2-B：build-time lint」「五、收尾與交接」。
- 參照來源（唯讀）：`scripts/data_loader.gd`（`verify_references` 與 `lint_*` 1～22）、`scripts/verify_data.gd`、`scripts/autoload/data.gd`（`REQUIRED_TUNING_KEYS` 與 `ACTION_PHASES` 時段數一致性）、`scripts/core/data_facts.gd`。
- 可動檔案：
  - 新增：`web/src/data/validate.ts`、`web/scripts/lint-data.ts`、`web/tests/data-lint.test.ts`、`docs/records/W2_steps/W2-B.md`
  - 修改：`web/src/data/vocabulary.ts`、`web/src/data/load-node.ts`、`web/package.json`、`docs/records/W2實作紀錄.md`

## 實作摘要與公開 API

- `web/src/data/vocabulary.ts`：擴充匯出封閉語彙常數 `CARD_TYPE_IDS`、`LEGAL_NARRATIVE_BEAT_TAGS`、`LEGAL_REJECT_REASON_TAGS`、`REQUIRED_TUNING_KEYS`、`INDULGENCE_LEVEL_KEYS`、`EXPECTED_ENDING_IDS`、`EXPECTED_OPENING_CHOICE_IDS`。
- `web/src/data/load-node.ts`：新增 `getDefaultDataDir()`、`createNodeReadText(dataDir?)`，並讓 `buildManifest(dataDir?)` 與 `loadGameDataNode(dataDir?)` 支援傳入目錄或 `RETURNFARE_DATA_DIR` 環境變數注入，供測試注入壞資料 fixture 而不觸碰正式 `data/`。
- `web/src/data/validate.ts`：
  - `validateData(data: GameData): ValidationReport`（回傳 `{ errors: Diagnostic[], warnings: Diagnostic[], executedRules: string[] }`，`Diagnostic` 含 `{ ruleId, source, message }`）。
  - `LINT_REGISTRY` 涵蓋 7 大群組、共 22 條規則（`lint_choice_rules` 與 `lint_free_slot_rules` 同源只登錄一次）：
    1. `structure_refs_tuning`：`verify_references`、`Data.REQUIRED_TUNING_KEYS`（含 `tuning.phases_per_day === ACTION_PHASES.length`）
    2. `vocabulary_card_types`：`lint_vocabulary`、`lint_card_types`、`lint_missing_reject_reason`（warning）
    3. `day_supply_free_slot_echo`：`lint_free_slot_rules`（error + 豁免 warning）、`lint_action_phases`、`lint_echoes`
    4. `indulgence`：`lint_indulgence_integrity`、`lint_indulgence_exits`
    5. `night`：`lint_night_reachability`、`lint_night_alignment`、`lint_night_locations`、`lint_legacy_night_flags`、`lint_night_once`、`lint_night_location_descs`
    6. `delegation_encounter`：`lint_delegations`、`lint_encounters`
    7. `opening_ending_loop`：`lint_endings`、`lint_opening_and_defaults`、`lint_loop_and_festival`、`lint_phase_lifecycle`
- `web/scripts/lint-data.ts`：提供 `runLintData(argv?, envDataDir?)` 與 CLI 入口 `npm run lint:data [-- --data-dir <dir>]`；先跑 `loadGameDataNode` 攔截讀檔／JSON／重複 id／`when` 互斥，再執行 `validateData`；error 或載入失敗 `exit 1`，warning 只報實數不擋建置。
- `web/package.json`：
  - 新增 `"lint:data": "tsx scripts/lint-data.ts"`
  - `"dev"` 改為 `"node scripts/sync-data.mjs && npm run lint:data && vite"`
  - `"build"` 改為 `"node scripts/sync-data.mjs && npm run lint:data && tsc --noEmit && vite build"`

## 驗證證據

| 檢查項目 | 結果 |
|---|---|
| Godot 對照基準 `verify_data.gd` | exit 0；卡片 66／地點 48／NPC 18／beat 271／ending 4／opening 3；0 錯誤、Lint 3 已豁免警告 4 筆 |
| `npm run lint:data`（cwd `web/`） | exit 0；catalog：卡片 66／地點 48／NPC 18／beat 271／ending 4／opening 3／cardTypes 12；已執行規則 22 條；警告 4 筆（`d35_pm_answer`、`d40_tell_someone`、`d43_morning_ask_paper`、`d43_conclusion`）、錯誤 0 筆 |
| `npm test`（cwd `web/`） | exit 0；5 files、39 tests 全綠（含 `data-lint.test.ts` 8 條案例：正式資料基線、未知引用／tuning、未知語彙與複合條件容器型別檢查、結局頁面列表非陣列與缺欄檢查、warning vs 未豁免免費槽 error、壞遭遇 `next_round` 與不可達／cycle、缺夜間 `desc` 與劇透名稱、CLI 暫存目錄注入與缺檔回報） |
| `npm run build`（cwd `web/`） | exit 0（依序執行 `sync-data.mjs` → `npm run lint:data` → `tsc --noEmit` → `vite build`） |
| 變異 1（拔掉 build 的 lint 接線） | 暫存目錄注入 `n_corridor.desc = ""` 時，拔掉 `npm run lint:data` 後 `RETURNFARE_DATA_DIR=<tempDir> npm run build` 誤過（exit 0）；還原 `package.json` 接線後同一命令被 `[lint_night_location_descs]` 擋下（exit 1），正式 `data/` 零改動 |
| 變異 2（從 `LINT_REGISTRY` 註解 `lint_night_location_descs`） | `npm test` 立即轉紅（`data-lint.test.ts` 3 failed）；還原後全綠 |
| 驗收回饋修正（2 項 `[P2]` 漏檢與變異驗證） | ① `lintConditionNode` 補齊 `all`/`any` 非空 Array、`count_at_least` Dictionary／正整數 `n`／非空 Array `of` 及子條件禁止 `null`/`undefined`；② `lintPageList` 對非 Array 明確報錯，並移除 `ending_replaced` 8 處 `?? []` fallback、補檢 `lookup_fragments` 陣列與元素型別。暫時移除這兩處容器型別檢查時 `data-lint.test.ts` 對應 2 條測試立即轉紅（2 failed），還原後 39 tests 與 `npm run build` 全綠 |

## 下一步

- 待 verifier 驗收 W2（W2-A 與 W2-B）。
