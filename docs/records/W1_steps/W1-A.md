# W1-A 網頁骨架與資料同步

## 派工範圍

- 日期：2026-10-31；worker：OpenCode Nemotron 3.5 Super VL Free；起點 `main@8418c35`。
- 契約：`docs/web/W1實作契約.md`「一、交付範圍與依賴」「二、W1-A：網頁骨架與資料同步」及共用契約適用段落。
- 交付：React 18／Vite／TS 空殼、lockfile、Vitest、單向 JSON 同步；不實作 W1-B／C、玩法、資料 lint 或正式 UI。
- 可動檔案：W1-A 契約白名單與 `.gitignore` 指定新增項目；worker 不改本紀錄與其他文件。
- 保護：Godot、正式 data、既有 art／prototype、既存 PROJECT_BRIEF 修改；不使用瀏覽器、不進歷史 archive。
- prompt／log：repo 外 `C:/_work/AI_Work/Tools/agy-runs/opencode-nemotron-W1-A.prompt.txt` 與同名 `.log`。

## 必要驗證與審核清單

- `npm ci`、`npm test`、`npm run build`；確認 build 包含 TS 型別檢查，測試為非 watch 且無測試不能成功。
- 暫存 fixture：巢狀 JSON 內容與路徑、來源刪檔後舊產物消失、相鄰素材保留、測試結束清理。
- 同步 CLI 不依賴 cwd；遞迴刪除前驗證目的目錄，不刪 public／art。
- 正式來源與產物 JSON 集合及 bytes 一致；SCHEMA 不同步、產物不提交。
- 短暫啟動 dev，HTTP 驗空殼、tuning JSON、town.webp，結束關閉本次服務。
- 檔案白名單、React 版本、依賴鎖定、架構與副作用、Windows 路徑、拒絕／失敗退出碼及測試有效性；最小變異證明關鍵同步測試會紅，再還原。

## 交付與指揮者審核修正

- 執行：約 11:57～12:11（Asia/Taipei），同一 OpenCode session `ses_e6fe4eab2ffe0KBSk2HWEqvqal`，共三次 CLI 呼叫。首輪讀檔後超過四分鐘無新輸出，以 session.interrupt 中止；第二次沿用已讀背景產出實作；第三次套用指揮者集中審核意見後正常 exit 0。前兩次為指揮者中止，exit 1，不列為成功交付。
- repo 外 prompt／log：`opencode-nemotron-W1-A`、`opencode-nemotron-W1-A-retry`、`opencode-nemotron-W1-A-review` 三組，均在前述 agy-runs 目錄。
- worker 新增九檔：`web/package.json`、`package-lock.json`、`index.html`、`tsconfig.json`、`vite.config.ts`、`src/main.tsx`、`src/ui/App.tsx`、`scripts/sync-data.mjs`、`tests/sync-data.test.ts`；修改 `.gitignore`，只新增 W1-A 三個產物目錄。
- API：`syncData(sourceDir, targetDir)` 為 async，回傳 `{ source, target, copied, removed }`；import 不執行同步。dev／build 從腳本位置解析資料路徑，build 以 `&&` 串同步、tsc、Vite。
- 首版曾把 TypeScript 型別寫入 mjs、漏 DOM lib；worker 自測後修正。指揮者退回的集中問題：素材 fixture 誤置於目的目錄內、輸出目錄保護不完整、舊工具鏈有六項 audit 漏洞（含兩項 critical）、型別檢查只含 src。
- worker 修正為 sibling art fixture、限制 repo 內輸出位置、清 stale 非 JSON 產物、升級相容工具鏈，tsconfig 納入 tests／scripts／Vite config。指揮者另修跨磁碟 relative 判斷、將外部測試來源／目的限於 OS temp、移除不必要的檔案遞迴刪除，並以 mkdtemp 與 finally 前絕對路徑核對收尾 fixture。
- 最終版本：React／ReactDOM 18.3.1、TypeScript 5.9.3、Vite 8.3.5、Vitest 5.0.5、plugin-react 6.1.2；lockfile 固定實際解析結果。npm audit 最終為 0 漏洞。

## 驗證證據與交接

以下由指揮者對最終程式獨立執行；未修改 Godot／data／既有素材或原型：

| 檢查 | 實際結果 |
|---|---|
| web 內 npm ci | exit 0；安裝 48 packages、audit 49 packages，0 漏洞 |
| npm test | exit 0；1 檔／1 個整合 fixture 通過，涵蓋巢狀 JSON、SCHEMA 排除、stale JSON／非 JSON 清理、sibling art、來源／目的相同拒絕及清理 |
| npm run build | exit 0；同步 19 份 JSON → tsc --noEmit → Vite build；無 TS 編譯錯誤 |
| 最小變異 | 暫時略過 stale rm，npm test exit 1，stale.txt 殘留斷言失敗；finally 還原原 bytes 後 npm test exit 0 |
| npm test -- W1A-no-such-test | exit 1，沒有測試不算成功 |
| 從 OS temp 執行同步 CLI 絕對路徑 | exit 0，仍同步正確 repo 來源／目的，不依賴 cwd |
| JSON 集合與內容 | 來源與產物皆 19 份，相對路徑及原始 bytes 逐檔相同，SCHEMA.md 不在產物 |
| dev HTTP | /、/data/tuning.json、/art/map/town.webp 皆 200；JSON 1534 bytes、圖片 523782 bytes，皆與來源 bytes 相等 |
| 服務清理 | 自建 dev process tree 在 finally 關閉，再次 fetch 失敗，DEV_SERVER_STOPPED |
| 邊界 | PROJECT_BRIEF SHA-256 仍為 B885D16A74D7543EB5F636FA936B98EE77C315B8A1947FBF9350E2494F6FCCC7；產物 ignore，git diff --check 通過 |

本機證據（不提交生成檔）：`_qa/web/w1a-conductor-check.log`、`w1a-dev-server.log`、`w1a-mutation.log`、`w1a-no-tests.log`；HTTP／bytes 檢查器為 `_qa/web/w1a-conductor-check.mjs`。

本步契約對照已檢查工具鏈、API、檔案／副作用邊界、Windows 路徑、失敗退出、HTTP 入口與測試有效性，無待修 blocker。未做瀏覽器、Godot、遊戲玩法或軌跡驗證，均不屬 W1-A。W1-B／C 命令尚未具備。

## Verifier 驗收與文件關門（2026-10-31）

- 判定：**W1-A 通過驗收**；驗證 commit 為 `80f2b7b`。本 session 切換 verifier 角色，逐項核對 W1-A 契約與上述獨立檢查證據；實作者的回報僅作輔助，未以其自評代替驗收。
- 必要驗證三組均有證據：暫存同步 fixture、安裝／測試／型別檢查與建置及正式 JSON 一致性、dev HTTP 與服務清理；另有最小變異及無測試失敗證據，無未解 blocker 或待補驗收項目。
- 本次工作區無程式變動，既有證據仍適用；依 commit／push 指示不重跑測試。PROJECT_BRIEF 與 W1 步驟板已同步；本次文件收尾不代表整個 W1 或網頁版玩法驗收完成。
