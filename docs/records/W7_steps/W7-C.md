# W7-C 字型自託管與子集化

## 派工

- 日期：2026-11-02；worker：agy Gemini 3.8 Flash (High)，透過共用 agent-worker 控制器。
- 起始：main@9aad56c；W7-A／B 已驗收。既有未提交 AGENTS.md、docs/others/conductor-handbook.md、local-tools.md 為前一任務文件修改，worker 不得動；`.claude/` 忽略。
- 契約：W7 實作契約「一、範圍、順序與已定邊界」「四、W7-C：字型自託管與子集化」「六、完成判準與角色」；共用契約一～四、六；W3-A 紀錄「字型來源與轉檔」。
- 範圍：正式 data 字串與 UI 語料收集、可重跑 subset 命令、兩套部署 woff2、授權保留、必要字元／大小／建置／代表 UI 證據。
- 可動：web/scripts/collect-font-text.ts、tools/fonts/subset_fonts.py、tools/fonts/requirements.txt、必要的對應測試、web/package.json、web/public/fonts/ 成品；styles.css／boot.ts 僅授權要求改名時同步引用。原字型與中間檔只放 `_qa/fonts/`。
- 禁止：data、Godot、基線、玩法、art、prototype、其他 UI 行為、verifier 文件；不 stage／commit／push、不開 Edge、不委派。

## 必要驗證

1. 收集正式資料與 UI（含 template literal）所需字元；逐套以 cmap 驗缺字與輸出實際 bytes。
2. 重跑命令仍可從未子集化來源生成；缺字／生成失敗須保留原可用部署檔。
3. 相關工具測試、npm test、npm run build；不改規則則沿用既有 W7-A 對帳證據。
4. 專用 headless Chromium：字型 HTTP 成功、實際載入，正式長文／罕見角色字與換行代表畫面；禁止 Edge，瀏覽器 finally 關閉。
5. 指揮者檢查 diff、授權、白名單與測試有效性。只交工程證據，驗收與全案進度由 verifier 決定。

## 執行與證據

- 第一輪 task ID：`e3f2214b24d149b9b250cc5c794cfa2f`。
- run_dir：`C:\_work\AI_Work\Tools\agent-worker\runs\e3f2214b24d149b9b250cc5c794cfa2f`。
- 原始 prompt：`C:\_work\AI_Work\Tools\agy-runs\agy-W7-C.prompt.txt`；時限 1200 秒。
- 第一輪 08:16:30～08:29:48 UTC（約 13 分 18 秒）由指揮者停止，控制器確認 `stopped`／exit 1。留下 collector、requirements 與完整 WOFF2 備份；未動部署字型。stderr 出現 root idle／2 background tasks，期間仍有多輪 fontTools 試跑；collector 於停前寫入，但仍缺 Python、測試與入口，因此停止試跑並調整來源。未發出 final report／conversation_id。
- 指揮者隔離探針：TTFont 初始化 0.056 秒，但完整 WOFF2 glyf 重建超過 22 秒，stack 位於 `fontTools/ttLib/woff2.py` 的輪廓解碼。改用 W3 同版官方原始 TTF，SHA256 分別與 W3-A 已記值一致；同一文楷樣本的 TTF load＋subset 為 0.078 秒。來源放 `_qa/fonts/source/`；不把來源／中間檔提交。
- 第二輪 task ID：`afaa1f1ef3fb4986823c2a7895b3f8b3`，run_dir：`C:\_work\AI_Work\Tools\agent-worker\runs\afaa1f1ef3fb4986823c2a7895b3f8b3`，prompt：`C:\_work\AI_Work\Tools\agy-runs\agy-W7-C-round2.prompt.txt`，同模型／1200 秒。第一輪無 conversation_id，依接手規則在保留產物後新開對話。
- 第二輪另要求 collector 的 JSON 解析錯誤不可僅記 log 後繼續；缺正式來源應拒絕，避免生成不完整語料。
- 第二輪 08:31:18～08:41:21 UTC exit 0，agy conversation_id：`8de1cc27-15c4-4d13-9417-d850fe0ea7bf`。交付 collector／subsetter／測試／npm 入口；worker 回報 Node 277 tests、Python 4 tests、build 通過，但指揮者實查兩檔 magic=`00010000`／TTFont.flavor=None，實際為 TTF，不能接受其 WOFF2／完成宣稱。
- 指揮者第三輪同對話退修：正確 WOFF2 保存及格式驗證、第二次替換失敗時回復兩份原字型、移除公開 test-only hash bypass、補 template／escape／JSX 獨立測試、修正 report 路徑提示及清除本輪根目錄測試快取。prompt：`C:\_work\AI_Work\Tools\agy-runs\agy-W7-C-round3.prompt.txt`。
- 第三輪 task ID：`fadb002ffcdc476ba77eff9e21d2dc2c`；run_dir：`C:\_work\AI_Work\Tools\agent-worker\runs\fadb002ffcdc476ba77eff9e21d2dc2c`，08:42:26～08:47:12 UTC exit 0。

## 交付與使用

- `web/scripts/collect-font-text.ts`：`collectFontCorpus(options)` 與 CLI。收集 root data JSON 值、src 的 TS／TSX 字串／template／JSX、index.html 與可列印 ASCII；壞 JSON、缺必要目錄或無來源檔拒絕。明列排除 LF 與 U+FE0F 等非獨立 glyph 字元。
- `tools/fonts/subset_fonts.py`：`run_subsetting(...)`、`subset_ttf_to_woff2(...)`、`verify_woff2_format_and_coverage(...)`。來源 TTF 固定 SHA256；兩候選皆通過 magic／flavor／cmap 後配對替換，替換失敗回復舊檔；不提供公開 hash bypass。
- `tools/fonts/requirements.txt`：fonttools 4.68.0、brotli 1.2.1。`web/package.json` 新增 `fonts:collect`／`fonts:subset`；正常 build 不做字型生成或下載。
- 新增 `web/tests/font-text.test.ts`（5 案）與 `tools/fonts/test_subset_fonts.py`（6 案）。
- 兩套成品仍沿既有檔名及 CSS `WenKai`／`TaipeiSans`；styles／boot 未改，`font-display: swap` 保留、不加 CDN。既有 OFL 標頭未列 Reserved Font Name；OFL／NOTICE 與派工前逐 bytes 相同，name IDs 0／13／14 保留。

重跑：

```powershell
# repo root；來源 TTF 不進 repo，缺檔時腳本會列來源 URL、路徑與預期 SHA256。
.\.venv\Scripts\python.exe -m pip install -r tools/fonts/requirements.txt
# 將 W3 已核對的同版 TTF 放到 _qa/fonts/source/：
# LXGWWenKaiTC-Regular.ttf、TaipeiSansTCBeta-Regular.ttf
Set-Location web
npm run fonts:collect
npm run fonts:subset
```

`fonts:subset` 自動先重新收集當前語料。來源 URL／hash 在腳本與 `_qa/fonts/report.json`；不從已子集化部署檔反推完整來源。原檔、語料、候選與報告都只在忽略的 `_qa/fonts/`。

## 指揮者審核修正

- 第一輪 full WOFF2 glyf 解碼耗時：由隔離 stack／計時探針確認，改提供原已驗證版 TTF；未更換字型版本。
- 第二輪格式檢查發現 TTF 偽裝 WOFF2：核對實際 `subset.load_font`／`save_font` API 後退修，加入真實格式正反例。
- 配對替換原先無 rollback：退修並以第二次 `os.replace` 故障注入證明回復；不以「兩次 replace」宣稱交易原子性。
- 補 template head／tail、Unicode escape、JSX 獨立標記測試，移除公開 test-only CLI；根目錄 worker 產生的 node_modules 快取已清除。
- 指揮者僅另修新測試的 Unicode 排序斷言：以 code point 陣列迭代，並補 `𠮷` 非 BMP 案例，避免把 surrogate pair 當兩字；相關 5 案全綠。

## 獨立驗證（main@9aad56c 上本步未提交工作區）

| 項目 | 結果與證據 |
|---|---|
| 語料獨立核對 | `_qa/web/W7-C/audit-charset.mjs` 從正式 data／src 另算 2,291 字，與 collector 相同；漏收 0。LF／FE0F 非獨立 glyph 的排除有明確紀錄 |
| 文楷 | 5,526,068 → **694,028 bytes**；SHA256 `BA1171F4C71EFD107CAB2F09ADD0B9A2608E8D60D77CCBB2D09DDF1F42F806BA`；WOFF2／2,291 字／缺字 0 |
| 台北黑體 | 7,215,276 → **508,516 bytes**；SHA256 `5742AE705581EDFAA9653397C97F04D53E326855275F8F8382FB8D8667897EEB`；WOFF2／2,291 字／缺字 0 |
| 合計 | 12,741,344 → **1,202,544 bytes**，減少約 **90.6%**。原始大小由 HEAD blob 獨立讀取，避免重跑報告的 before 已變成子集大小 |
| 來源／授權 | 兩 TTF hash 與 W3-A 一致；`check-fonts.py` 另核對成品 cmap、不是 .notdef、magic、flavor、name metadata 與派工前授權檔 hash。報告 `_qa/web/W7-C/font-report.json` |
| 可重跑性 | 指揮者 `npm run fonts:subset` exit 0；同語料重跑後兩成品 SHA256 與上述逐字相同 |
| Node／build | 指揮者 `npm test`：25 files／278 tests；`npm run build`（含 tsc）：exit 0；22 lint 規則 0 errors／4 既有豁免 warnings。最後僅測試 Unicode 補強後再跑 `npm test -- tests/font-text.test.ts`：5／5 exit 0 |
| Python | 指揮者 `.venv\Scripts\python.exe tools/fonts/test_subset_fonts.py`：6／6 exit 0。涵蓋第二套生成失敗、第二次替換失敗、實質格式、偽裝 TTF、缺來源與 hash |
| 拒絕保留 | `_qa/web/W7-C/probe-collector.ts` 壞 JSON 拒絕且舊語料保留；`probe-guards.py` 注入 U+10FFFF：缺字拒絕、兩舊字型 bytes 不變 |
| 變異保真 | `probe-guards.py` 在記憶體停用格式驗證、跳過 rollback copy 各使對應案例轉紅（2／2）；還原後 Python 6／6 綠。報告 `_qa/web/W7-C/guard-report.json`，未改正式檔 |
| 代表 UI | Playwright 專用 `chromium.launch({ headless: true })`，finally 關 browser／自啟 Vite。正式 `d1_morning_departure` 224 字含「婕」；兩字型 HTTP 200、載入且 swap；CDP 確認正文實用 LXGW WenKai TC（219 glyphs）、按鈕實用 Taipei Sans TC Beta（4 glyphs），均 custom font；1280／390 寬分別 14／22 行、無水平溢出、pageerror 0。`_qa/web/W7-C/ui-report.json`、`font-1280.png`／`font-390.png` 已檢視 |
| 範圍 | 只新增工具／測試、改 package 入口與兩字型；data、core、Godot、基線、art、prototype、package-lock、既有授權與 UI 引用未改。先前三份工具文件修改保留；無 Edge、部署、git stage／commit／push |

UI harness 初次因把已整理 response 的 `url` 欄位當函式而 TypeError，browser／服務已 finally 關閉；只修忽略目錄內 harness 欄位存取後執行成功，未發現 Chromium 或產品 UI 問題。字型授權檔用派工前原始 bytes hash 比對，避免 Windows CRLF 與 git blob LF 的誤判。

## 限制與交接

- 工程證據已交付，步驟板標「待獨立驗收」；不改 PROJECT_BRIEF、不代 verifier 關門，未 commit／push。
- 非阻擋：fontTools 對來源 `meta` 表印出不支援 subset 而丟棄的訊息；既有 OFL 與 name 0／13／14 均保留。故意繞過來源檢查的壞 TTF 測試偶有 fontTools 開檔 `ResourceWarning`；正常 CLI 先以 hash 拒絕，6 案皆通過。
- 不重跑 W7-A 全程 trace／Godot 或全套 UI：本步無規則／資料／UI 行為改動，沿用既有對帳證據。未驗所有頁面、其他瀏覽器、真人體感或 W7-D 部署。
- 下一步：獨立 verifier 依 W7 四驗收本工作區；通過後再進 W7-D。

## P2 修正：CSS 生成括號漏收（2026-11-02）

- reviewer 指出 `.slot-occupant::before/after` 的 `〔〕`（U+3014／U+3015）只存在 CSS，先前 collector 與獨立 audit 都漏掃，兩成品確實缺字。因此前述 2,291 字零缺漏證據僅涵蓋不完整語料，不能證明全 UI 完整；本節修正後證據優先。
- 使用者已明示「指揮 agy 去修」。沿同 conversation `8de1cc27-15c4-4d13-9417-d850fe0ea7bf`，Gemini 3.8 Flash (High)；task `e6b0505f9297445d9fa200b005bf6757`，run_dir `C:\_work\AI_Work\Tools\agent-worker\runs\e6b0505f9297445d9fa200b005bf6757`。
- 原始 prompt：`C:\_work\AI_Work\Tools\agy-runs\agy-W7-C-css-fix.prompt.txt`。白名單只限 collector、對應 Node 測試與兩份重產字型；不改 CSS／玩法／正式資料／Python subsetter／依賴／授權或其他既有修改。
- 目標：遞迴收取 src CSS 字串（可用全部引號字串作安全超集），正確解 CSS hex／引號／反斜線／換行 escape，略過 comments；補正式括號與隔離 CSS 回歸測試，先紅後綠並重產兩套字型。指揮者另驗 cmap 與實際卡名括號 UI，不再只拍純敘事。
- worker 09:04:15～09:08:48 UTC exit 0。`extractCssStrings(css)` 掃描全部 CSS 引號字串作安全超集，略過字串外 comments、保留字串內 comment-like 文字；解碼 CSS hex／可選空白結尾、引號／反斜線／換行續接，統計新增 `cssCharsCount`。collector 正式語料由 2,291 → **2,293**（CSS 類別 24，新增必需字為 U+3014／U+3015）。
- 指揮者另補 CSS 無效 scalar escape 的小修：`\0`、surrogate、超出 Unicode 範圍轉為 U+FFFD，避免 `String.fromCodePoint` RangeError。先新增案例重現 1 failed／5 passed，修後 279 tests 全綠；不改目前正式語料或字型 bytes。另補 collector 檔頭的 CSS 來源說明。

| P2 修後驗證 | 結果 |
|---|---|
| 文楷 WOFF2 | **694,244 bytes**；SHA256 `11406F448D37D019071FCE3D387E51B2FEB03CF6F5D80471C0C6F57266D39FC0`；2,293 字全覆蓋，含 U+3014／U+3015 |
| 台北黑體 WOFF2 | **508,816 bytes**；SHA256 `AFC14E16A9D96324E0EBF48BC7239BE7D7ECE834DC598AB9074C3F77EB49988E`；2,293 字全覆蓋，含 U+3014／U+3015 |
| 獨立 cmap／授權 | `check-fonts.py` 另將 CSS 兩字列為必要下限：expected／corpus 均 2,293、漏收 0、兩套缺字 0、真 WOFF2、name 0／13／14 與原授權仍保留；最新 `_qa/web/W7-C/font-report.json` |
| 接線變異 | `_qa/web/W7-C/probe-css-mutation.py` 暫時移除遞迴 CSS 收集：6 案中 2 failed／4 passed（正式括號與隔離 CSS 案）；finally 還原原始 bytes 後 6／6 pass。log：`css-mutation.log`／`css-restored.log` |
| 指揮者測試 | 最後 Node 25 files／**279 tests**、build／tsc 皆 exit 0；22 lint 規則 0 errors／4 既有豁免 warnings。Python subsetter 未改，不重跑其已有效的 6 案與 trace／Godot |
| 真實卡槽 UI | 專用 headless Chromium，自正式相簿開局走 D1、D2 下午實際放主角卡，再進 D3 下午山泉閣。正式 ledger 卡槽 `阿源叔` 的 before=`〔`、after=`〕`；CDP 對兩 pseudo-element 各確認 Taipei Sans TC Beta／isCustomFont=true／glyphCount=1，無系統字型 fallback。兩字型 HTTP 200、pageerror 0；finally 關 browser／自啟服務。`slot-css-report.json`、`slot-css-1280.png` 已檢視 |

本節畫面證據確認的是既有 occupant 的 CSS 卡名括號，與玩家放置後會隱藏的普通 resolved 槽分開；不以純敘事截圖替代。collector／測試／兩份字型以外的產品檔未改；CSS、UI／core、正式資料、Python 工具、package／lock、授權均維持原樣。P2 修正已交付並經指揮者檢查，仍待獨立 verifier，未 commit／push 或更新全案進度。

## Verifier 驗收（2026-11-02）

靜態審查未提交工作區：collector 以 TS 語法樹收 TS／TSX 字串、template 片段與 JSX，壞 JSON／缺目錄拒絕；subsetter 驗來源 TTF SHA256、候選真 WOFF2 與 cmap 後成對替換、失敗回復；name 0／13／14、檔名、font-family、`font-display: swap` 保留，無 CDN。首輪發現 P2：`styles.css` `.slot-occupant` 的 `content: '〔'／'〕'` 未進語料，兩成品 cmap 缺 U+3014／U+3015，放卡後括號會退系統字型。

P2 修正後複驗：verifier 以 CLI 另收語料 2,293 字（CSS 24），兩成品皆 `wOF2`／flavor woff2、cmap 2,293、缺字 0，含 U+3014／U+3015；`npm test` 25 files／279、`npm run build`、`test_subset_fonts.py` 6／6 皆 exit 0。log `_qa/web/W7-C-verify/`。CSS 接線變異與卡槽 pseudo-element 實際渲染沿用上節指揮者證據。

無 P0～P2。殘留 P3（不擋關）：
1. 測試未檢查「已提交字型涵蓋目前語料」；改 data／UI 文字忘了重跑子集化時，build 與測試仍全綠。
2. `fonts:subset` 寫死 Windows `.venv` 路徑；W7-D 雲端 build 不跑，不影響部署。
3. 台北黑體來源為 Google Drive 連結；若失效且 `_qa/fonts/source/` 被清，腳本不認 git 歷史中的完整 woff2（如 `git show 9aad56c:web/public/fonts/taipei-sans-tc.woff2`）為替代來源。

**通過驗收，W7-C 關門**；下一步 W7-D。
