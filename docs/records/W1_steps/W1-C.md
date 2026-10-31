# W1-C Node 軌跡比對器

## 派工前範圍

- 日期：2026-10-31；worker：OpenCode `opencode/nemotron-3.5-super-vl-free#high`；起點 `main@f153c2d`。
- 契約：`docs/web/W1實作契約.md`「四、W1-C：Node 軌跡比對器」；共用契約「三、快速檢查」「五、差分範圍與基線管理」。
- 前置：W1-A（`web/` 工具鏈）、W1-B（`tools/trace/baselines/greedy-godot.json`）皆已驗收。
- 可動檔案：`tools/trace/compare.ts`、`tools/trace/cli.ts`（只有拆薄入口時）、`web/tests/trace.test.ts`、`web/package.json`、`web/package-lock.json`、`web/tsconfig.json`／`tsconfig.node.json`（僅為納入工具檔型別檢查）。不改基線、Godot、data、文件。
- 驗收方式：契約第四節「必要驗證」六類案例；指揮者獨立跑 `npm ci`／`npm test`／`npm run build`，CLI 對真實基線自身 exit 0、單欄位反轉 exit 1、壞 JSON exit 2；拔掉比較核心的一處判斷確認測試轉紅。

## 交付與指揮者審核修正

- 執行：2026-10-31 約 13:2x～13:39（Asia/Taipei），一回合 exit 0，未卡住；worker 未做任何 git 寫入，只動白名單檔案。prompt／log：`C:\_work\AI_Work\Tools\agy-runs\opencode-nemotron-W1-C.prompt.txt`／`.log`。
- worker 新增 `tools/trace/compare.ts`（`compareTraces`、`MISSING`、`TraceShapeError`、`TraceConfigError`，無 import）、`tools/trace/cli.ts`（只用 Node 內建）、`web/tests/trace.test.ts`（契約六類案例）；`web/package.json` 加 `trace:compare`（`tsx ../tools/trace/cli.ts`）與 `tsx` devDependency，lock 同步；`web/tsconfig.json` include 加 `../tools/trace/**/*`，型別檢查涵蓋工具檔。
- 指揮者審核修正三處：
  1. ignorePaths 指到單邊缺鍵時仍報差異（缺鍵判斷在忽略判斷之前）。改為先跳過忽略路徑，未移植欄位可整個不存在。
  2. actual 少於 throughSeq 前綴時被當成 scope 設定錯誤（exit 2）。改為：前綴超出 expected 才是設定錯誤；actual 缺 checkpoint 回 `/checkpoints` 差異、exit 1。
  3. manifest／policy／schema 不同時 CLI 只印路徑。改印 `baseline not applicable: <path> differs`，仍 exit 1。
  - 對應補兩個斷言：忽略欄位單邊缺失仍相同；actual 短於前綴為 `/checkpoints` 差異。
- 保留的取捨：`schema_version` 不是 1 時屬格式錯誤（exit 2），因目前只有 v1。

## 測試

| 檢查 | 結果 |
|---|---|
| `npm ci`／`npm test`／`npm run build`（cwd `web/`） | 皆 exit 0；2 files、7 tests |
| 基線對自身 | exit 0；comparedCheckpoints=193、comparedFields=48985 |
| seq 57 單一布林反轉 | exit 1；`seq=57 day=15 phase=morning path=/run/action_spent expected=true actual=false` |
| manifest 改一筆 hash | exit 1；`baseline not applicable: /data_manifest differs` |
| 壞 JSON | exit 2 |
| actual 只有 3 筆、scope throughSeq:4 | exit 1；`seq=3 … path=/checkpoints expected=3 actual=<missing>` |
| 變異：純量比較改成永遠相等 | case 2／3／5／6 轉紅；還原後 7 tests 全綠 |
| 基線 SHA-256 | 不變（`6129328e…26326f`） |

## 未解與下一步

- 待 verifier 驗收 W1-C 與 W1 整體收尾（契約第五節）；指揮者不自行打勾。
- W3 才建立 `tools/trace/scopes/W3.json` 與 `trace:web`。
