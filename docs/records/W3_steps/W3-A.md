# W3-A 開局與純演出 UI

## 派工前範圍（2026-10-31）

- 指揮者：Codex；worker：OpenCode `opencode/nemotron-3.5-super-vl-free#high`；branch main，起點 `899d48f`，W3-B 已驗收。
- 契約：共用契約架構／快速檢查／必要驗證；W3 契約交付範圍、W3-B 公開介面、完整 W3-A 與軌跡交接；W-02／W-03 已定。
- 交付：正式 browser loader → Game → React；opening 預覽／確認／取消、鎖定理由；D1 逐段演出至 D2 morning；兩套自託管 woff2 與正式授權；必要 Chromium Playwright 測試。
- 可動檔案：新增 ui/use-game.ts、OpeningPanel.tsx、NarrationPanel.tsx、GameShell.tsx、strings.ts、styles.css、playwright.config.ts、tests/ui/opening.spec.ts、narration.spec.ts、必要 vitest.config.ts、public/fonts/ 指定兩套成品及授權；修改 App.tsx、main.tsx、package.json／lock；tsconfig 僅必要測試設定，.gitignore 僅測試產物。精確路徑與界線見外部工單。
- 不可動：core/、data/、Godot、黃金基線、verifier 文件；worker 不寫 git、不改紀錄、不委派。只用專用 headless Chromium，禁止 Edge。
- 驗證：npm test／build、test:ui 連續兩次、W3 軌跡 5 筆／187 欄位對帳；必要字型／長文排版截圖、載入失敗與取消拒絕路徑、最小 UI 接線變異後還原。
- 外部工單：`C:\_work\AI_Work\Tools\agy-runs\opencode-ReturnFare-W3-A.prompt.txt`；stdout／stderr 見同名 log。

## 交付與指揮者審核

## 第一輪結果與受阻原因（2026-10-31）

- OpenCode session：`ses_e6ed63d96ffeAKLIUQU1n8fpLG`；模型 `opencode/nemotron-3.5-super-vl-free#high`，約 16:53～17:07（Asia/Taipei）。
- 第一輪已讀取契約與 API、檢查 Node／npm／專用 Chromium、建立專案 .venv 並安裝 fonttools／brotli；原始字型只下載至 repo 外暫存區，尚未產出正式字型或 UI 程式碼。
- 退出原因經 session export 確認：`provider.quota`、HTTP 429、`Free usage limit reached`。不是已完成，也不是瀏覽器驗收失敗；未啟動 Edge。
- 產品交付：0 檔；尚未執行 W3-A npm test／build／test:ui 或 UI 接線變異，未提交／推送產品改動，不宣稱已驗收。
- 指揮者準備的 W3-A step 紀錄與 W3 步驟板尚在工作樹；正式 core／data／Godot／基線未改動。
- 當時已向使用者詢問接續方式，未自行改用付費模型；後續使用者指定 Terra subagent，見接續派工與交付紀錄。

## 已核對字型入口（供接續工單）

- LXGW WenKai TC：https://github.com/lxgw/LxgwWenKaiTC；官方授權 https://raw.githubusercontent.com/lxgw/LxgwWenKaiTC/main/OFL.txt。worker 暫存 `LXGWWenKaiTC-Regular.ttf` 為 15,341,148 bytes，尚未轉檔或交付。
- Taipei Sans TC 官方：https://sites.google.com/view/jtfoundry/zh-tw/downloads；頁面連到 Google Drive 官方資料夾 `1OJOOly6jo9RID3EE2f7S3N7T-8ZWPv6N`，Regular 檔案 id `1eGAsTN1HBpJAkeVM57_C7ccp7hbgSz3_`。worker 目前下載的非官方 raw 檔只有 133 bytes，是 Git LFS 指標，不得用作正式字型。
- 下一輪直接使用上述官方入口，不重做搜尋；仍須核對實際下載 bytes、字型格式、授權原文及必要轉檔。

## 接續派工（2026-10-31）

- 使用者指定：單一 `gpt-6.1-terra`、medium 專注程度 subagent，任務 `/root/w3a_terra`；不再使用 OpenCode，也不再委派。
- 沿用上述 W3-A 範圍、檔案白名單與驗證要求；先完成 UI／測試，再處理既知來源的字型，不重做前一輪搜尋。
- worker 不改 docs、不寫 git；指揮者監看與工程檢查後提交，另交 verifier 獨立驗收。

## Terra 交付與指揮者工程檢查（2026-10-31）

- Worker：單一 `gpt-6.1-terra` medium subagent `/root/w3a_terra`；一個實作回合加一個 Chromium 環境修正回合，未另計時，未再委派。未執行 git 寫入，文件由指揮者維護。
- 交付檔案：修改 `web/src/main.tsx`、`web/src/ui/App.tsx`、`web/package.json`／lock；新增 `use-game.ts`、`OpeningPanel.tsx`、`NarrationPanel.tsx`、`GameShell.tsx`、`strings.ts`、`styles.css`、`web/playwright.config.ts`、`web/vitest.config.ts`、`web/tests/ui/opening.spec.ts`／`narration.spec.ts`，兩套 woff2／OFL 與台北黑體 `NOTICE.txt`。
- 公開 UI：正式 browser loader 成功後才 createGame；`useGame(game)` 透過 useSyncExternalStore 訂閱既有 store；opening 預覽／確認／取消、鎖定理由及逐段閱讀皆呼叫既有 view／command。evening／night 在推進操作中顯式呼叫演出命令，不以 render／mount effect 結算。D2 morning 不提供假造地圖或放卡。
- 指揮者審核：逐檔核對 loader／Game API、取消與錯誤分支、文字來源與次序、scope、純 UI 與 core 邊界、字型、Vitest／Playwright 分流；未需修改 worker 產品程式。額外授權的唯一檔案為台北黑體 `NOTICE.txt`，保存官方來源與原始 name table，不套用其他字型版權抬頭。
- 初次 UI 驗證因 Playwright 需要 headless shell 1248、現有快取只有舊版而在 browser launch 前失敗；依規則停止該輪。指揮者授權補裝對應官方版本，worker 執行 `npx playwright install chromium --only-shell --no-remove` exit 0 後另開驗證回合；全程未啟動 Edge。

### 工程檢查證據

| 項目 | 實際結果 |
|---|---|
| Worker `npm test`／`npm run build` | 皆 exit 0；8 files／55 tests；資料 lint 0 errors／4 筆既有 warnings |
| Worker `npm run test:ui` | 專用 port 4178、headless Chromium fixture；連續兩次各 3 tests、exit 0 |
| Worker 確認接線變異 | 暫將 `chooseOpening(selected.id)` 改為未知選項，opening 測試因未進入 D1 正文而 exit 1；完整還原後再跑 test:ui，3／3、exit 0 |
| 指揮者 `npm test`／`npm run build`／`npm run test:ui` | 最終工作樹皆 exit 0；55 Node tests、3 UI tests；字型實載、中文無水平溢出、正式開局至第一夜／D2 morning、載入失敗與取消路徑通過 |
| 指揮者 W3 軌跡 | `trace:web --output ../_qa/web/trace-web-W3A-conductor.json` 與 W3 scope 比對皆 exit 0；5 checkpoints／187 fields、equal=true |
| 字型完整性 | fontTools 讀回兩個 woff2，flavor 正確；與各自官方原始 TTF 的 glyph order／cmap 相同，未子集化。文楷 25,893 glyphs／25,694 cmap；台北 32,806 glyphs／32,731 cmap |
| 排版截圖 | `_qa/web/W3-A/evening.png`，1280×800 桌面；指揮者目視字型、換行與版面，無明顯溢出 |
| 範圍與產物 | core／data／Godot／黃金基線未改；.venv、暫存原字型與 _qa 皆不進提交。Playwright 無 Edge channel／executablePath，測試服務由 fixture 管理。暫存區檢查僅官方文楷 OFL 原文一處行尾空白；已核對與官方全文相同並保留，排除此授權檔後 git diff --cached --check exit 0 |

### 字型來源與轉檔

- 兩套都以專案 `.venv/Scripts/python.exe` 的 fontTools／Brotli 從完整 TTF 轉 woff2，`font-display:swap` 自託管，不接 CDN；W7-C 再做子集化。
- 文楷 TC：官方 https://github.com/lxgw/LxgwWenKaiTC/releases/tag/v1.530 ，OFL 原文 https://raw.githubusercontent.com/lxgw/LxgwWenKaiTC/main/OFL.txt 。原始 TTF 15,341,148 bytes，SHA256 `6662480A3F95B4A90C80B189C679617A48ADCE3A505118A6AF63CE5A482B83FA`（worker 已對 release API）；成品 5,526,068 bytes，SHA256 `2360E22E3949FECEB5E82480FDD814D83678AA1E279091FCE2343FF5DDDC7D69`。
- 台北黑體：官方 https://sites.google.com/view/jtfoundry/zh-tw/downloads ，官方 Drive 原檔 id `1eGAsTN1HBpJAkeVM57_C7ccp7hbgSz3_`；官方授權正文 https://openfontlicense.org/documents/OFL.txt ，原始 name table／來源另保留於 NOTICE。原始 TTF 20,659,344 bytes，SHA256 `8CC967E1E428C552701C461E8169E6AE76C7A23694EA1A6A786D6746ADEC53C4`；成品 7,215,276 bytes，SHA256 `B13DA4993C3715A8CE6299EA1C0A9CD71E4FA15EA72775E90D15B0AFFD4281F2`。

## 未解與下一步

- 工程檢查通過，交 verifier 獨立驗收 W3-A；指揮者不自行勾驗收、不更新 PROJECT_BRIEF.md，W3 整體尚未關門。
- 接續以本次提交為驗證對象，檢查正式 UI 與來源；完整玩法、地圖、卡片操作、存檔與多語系仍依後續 W 契約處理。