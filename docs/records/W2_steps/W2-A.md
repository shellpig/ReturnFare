# W2-A 型別、載入、索引與結構事實

## 派工前範圍

- 日期：2026-10-31；worker：OpenCode `opencode/nemotron-3.5-super-vl-free#high`；起點 `main@26d7c20`。
- 契約：`docs/web/W2實作契約.md`「一」「二」「三、W2-A」「五」；共用契約「二、架構與資料邊界」「三、快速檢查」。
- 參照來源（唯讀）：`scripts/data_loader.gd`（`load_all`、`_beat_files`、`_read_json_array`、`_read_opening_data`）、`scripts/core/data_facts.gd`、`scripts/core/condition_eval.gd`／`effect_apply.gd` 的 `KNOWN_KEYS`／`CARD_ENTRY_KEYS`、`data/SCHEMA.md`。
- 可動檔案：新增 `web/src/data/types.ts`、`vocabulary.ts`、`loader.ts`、`load-browser.ts`、`load-node.ts`、`web/src/core/facts.ts`、`web/tests/data.test.ts`、`facts.test.ts`；修改 `web/scripts/sync-data.mjs`、`web/tests/sync-data.test.ts`、`.gitignore`（僅加 manifest 產物）；必要時 `web/package.json`／lock／TS 設定。
- 劇情文字保護：worker 只以 node one-liner 看資料鍵與形狀，不印出 text／title／desc 等劇情欄位。
- 驗收方式：契約 W2-A「必要驗證」四項；指揮者另以 Godot `verify_data.gd` 的 catalog 數字對照 Node 載入結果，並做一處變異檢查（拿掉重複 id 偵測，對應測試應轉紅）。

## 交付與指揮者審核修正

- 執行：2026-10-31 約 13:54～14:40（Asia/Taipei），一回合 exit 0；讀完背景後約 9 分鐘無輸出（模型思考），之後正常產出。worker 無 git 寫入，只動白名單檔案。prompt／log：`C:\_work\AI_Work\Tools\agy-runs\opencode-nemotron-W2-A.prompt.txt`／`.log`。
- worker 新增 `web/src/data/types.ts`（Condition 為 17 運算子封閉 union、Effect／Encounter／Delegation／Ending linear+composite 等完整型別，無 `any`）、`vocabulary.ts`、`loader.ts`（`loadGameData(readText, manifest)`，七類 id 重複與 when day+day_from 彙整後以相對檔名拋錯）、`load-browser.ts`（`loadGameDataBrowser`）、`load-node.ts`（`loadGameDataNode`、`buildManifest`）、`web/src/core/facts.ts`；`sync-data.mjs` 另產 `web/public/data-manifest.json`，`.gitignore` 加一行；測試 `data.test.ts`、`facts.test.ts`，擴充 `sync-data.test.ts`。
- 指揮者審核修正三處：
  1. `load-browser.ts` 以整段 `encodeURIComponent` 組 URL，`beats/` 的斜線會變 `%2F`。Vite dev 會解碼所以 smoke 看不出來，但一般靜態主機找不到檔。改為逐段編碼。
  2. `Indulgence.weight` 標為必填，但正式資料的泡湯出口（auto:false）沒有 weight。改為選填。
  3. `facts.ts` 另存了一份 PHASES／ACTION_PHASES，與 `types.ts` 重複。改為從 `types.ts` 轉出，只留一份。
- 保留的偏離：`load-node.ts` 與 `sync-data.mjs` 各有一份「遞迴列 JSON＋SHA-256＋排序」，規則相同但未共用模組（worker 說明 .mjs 與 TS 模組分屬兩邊）。目前兩者產出一致；若之後改列舉規則須兩處同改。
- 型別只描述形狀，loader 除 id／容器形狀外不做欄位驗證；欄位與引用檢查屬 W2-B lint。

## 測試

| 檢查 | 結果 |
|---|---|
| `npm ci`／`npm test`／`npm run build`（cwd `web/`） | 皆 exit 0；4 files、22 tests；build 含資料同步、tsc、vite |
| Node 載入 vs Godot `verify_data.gd` | 卡片 66、地點 48、NPC 18、beat 271、ending 4、opening 3，兩邊一致；beat 首末 `d1_morning_phone`／`exit_jinghe`，11 個 beat 檔依檔名排序 |
| 瀏覽器 loader 經 dev server（127.0.0.1:5318）實際載入 | 與 Node 載入的數量、首末 beat、完整 beat 順序相同；結束後確認埠已關 |
| 變異：拿掉 beat 重複 id 偵測 | 重複 id 測試轉紅（1 failed）；還原後 22 tests 全綠 |
| main／ui／core 不 import Node 模組 | 已確認 |

## 未解與下一步

- 待 verifier 驗收 W2-A。
- 下一步派 W2-B（build-time lint）。
