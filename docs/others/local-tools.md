# 本機工具與執行規則

本檔承接 [AGENTS.md](../../AGENTS.md) 的本機 Windows 與外部 worker 指令。不是開場必讀；執行相關工作前只讀對應段落。

| 工作 | 先讀 |
|---|---|
| Godot headless 驗證 | 本檔「Godot headless 驗證」；sandbox 限制見 AGENTS.md「Godot Headless 驗證」 |
| 網頁版（`web/`）測試與 build | 本檔「網頁版測試」 |
| agy reviewer／worker | 本檔「agy 共用控制器」；實作流程另讀 [指揮者手冊 §3](conductor-handbook.md#3-agyantigravity-cli流程) |
| 其他外部 reviewer（唯讀審查） | AGENTS.md「DeepSeek Codex CLI Reviewer」「Codex CLI (OpenAI) Reviewer」 |
| 外部 worker（實作） | 本檔「外部 Worker CLI」；流程另讀 [指揮者手冊](conductor-handbook.md) 共通段落與所選 worker 段落 |

## 本機 Windows 環境專用

> 本段僅適用於使用者本機 Windows 環境（工具都在 `C:\`）。**remote / CI / Linux session 沒有這些路徑與工具，跳過本段。**

專案路徑：`C:\_work\AI_Work\Projects\ReturnFare`

### Godot headless 驗證

整套 headless 測試從 repo root 執行，**直接用 escalated 權限**（sandbox 內會因寫不了 `user://logs/` 而 signal 11 crash，見 AGENTS.md）：

```
powershell -ExecutionPolicy Bypass -File tests/run_all_headless.ps1
```

- 要第一個失敗就停加 `-FailFast`。
- 搬動 `.tscn` / `.gd` 或改 CSV 翻譯後，先跑一次 `--import` 重建快取再驗。
- 測試清單寫死在 `tests/run_all_headless.ps1` 的 `$tests` 陣列，新增測試檔要加進去，否則全套不會跑到。

### 網頁版測試

> `web/` 目前只有美術成品與 `prototype/`，`package.json` 由 W1-A 建立。建好之前本段不適用。

規劃中的指令（cwd `web/`，以 W1-A 實際建立的 script 為準）：

```
npm test
npm run build
```

示意版（`web/prototype/*/`）由同目錄 build 腳本從 `data/` 產生 HTML，產出不進 git：

```
python web/prototype/map-demo/build-map.py
python web/prototype/d1-demo/build.py
```

本專案沒有 `.venv`（見 AGENTS.md「Python 執行環境規則」）；`map-calibration/make_layout.py` 需要 Pillow，用系統 Python 執行，不要加 `-I`。

### 本機工具

外部工具不放進本專案 repo。Godot 與其他工具路徑見 AGENTS.md「專案外部工具路徑」。

| 工具 | 路徑 | 用途 |
|---|---|---|
| Antigravity CLI | `C:\Users\User\AppData\Local\agy\bin\agy.exe` | agy reviewer / worker |
| agy 共用控制器 | `C:\_work\AI_Work\Tools\agent-worker\` | `worker.py`、工具專用 `.venv`、`runs/<task ID>/` 任務紀錄 |
| agent-worker 共用 skill | `C:\_work\AI_Work\Skills\engineering\agent-worker\SKILL.md` | `.agents`／`.claude`／`.codex` skills 目錄透過 junction 共用 |
| agy 提示詞與舊紀錄 | `C:\_work\AI_Work\Tools\agy-runs\` | 原始 prompt、`TEMPLATE.prompt.txt` 與歷史輸出；新任務執行紀錄改存控制器的 `runs/` |
| OpenCode CLI | `C:\Users\User\AppData\Local\Programs\@opencodedesktop\resources\opencode-cli.exe` | OpenCode worker（Nemotron 3.5 Super VL） |

### agy 共用控制器

本機各 agent 統一透過 Python 控制器呼叫 agy。先讀共用 [agent-worker skill](C:/_work/AI_Work/Skills/engineering/agent-worker/SKILL.md)；完整工具說明見 [README](C:/_work/AI_Work/Tools/agent-worker/README.md)。這是專案外的獨立工具，**一律用工具自己的 venv**，不使用系統 Python，也不要求 ReturnFare 建立 `.venv`。

先將自足的任務本文存成 repo 外的 UTF-8 檔案（可沿用 `agy-runs/<phase>-<step>.prompt.txt`）。明列角色、必讀契約、可動檔案、禁止事項、必要驗證與回報格式；prompt 骨架與分工見指揮者手冊 §2.2。再執行：

```powershell
$workerPython = 'C:\_work\AI_Work\Tools\agent-worker\.venv\Scripts\python.exe'
$workerCli = 'C:\_work\AI_Work\Tools\agent-worker\worker.py'

# 審查；只有使用者授權實作後才改為 --mode implement。
& $workerPython $workerCli start --repo 'C:\_work\AI_Work\Projects\ReturnFare' --prompt-file 'C:\_work\AI_Work\Tools\agy-runs\W7-C.prompt.txt' --mode review --timeout 1200

# 將 TASK_ID 換成 start 回傳的 id。
& $workerPython $workerCli status TASK_ID
& $workerPython $workerCli result TASK_ID
& $workerPython $workerCli stop TASK_ID
```

- `start` 立即回傳 JSON（`id`、`run_dir` 等），不等 agy 完成。記下 task ID；控制器自行關閉 stdin、指定 workspace、保存輸出、以隱藏 supervisor 執行。**不要加 `cmd /c`、`< NUL`、輸出重導或 `run_in_background` 包裝**。它不依賴特定 agent 的完成通知，指揮者須主動查 `status`。
- 預設模型 `Gemini 4 Argon (High)`；要指定模型時加 `--model '完整顯示名稱'`，可用 `agy models` 核對。`--timeout` 單位秒，預設 1200，從 worker 啟動時計算，不含排隊。同一 canonical repo 路徑的任務（含 review）會互斥等待；派工固定使用上述專案根目錄，不以子目錄或不同路徑規避鎖。
- `review` 的禁止寫入規則是**提示詞約束，不是強制唯讀沙箱**。底層 agy 仍使用 `--dangerously-skip-permissions`；前後必查 `git status`／`git diff`。`implement` 也不授予 stage／commit／push 權限，沿用專案角色分工。
- `runs/<task ID>/` 保存有效 `prompt.txt`、`config.json`、`status.json`、`stdout.log`、`stderr.log` 與 `supervisor.log`。`result` 回傳 stdout／stderr 路徑與各最多 64 KiB 的尾端；完整 agy JSON（`conversation_id`／`status`／`response` 等）在 `stdout.log`，不再用舊 `report.py` 讀新任務。
- `queued`／`running` 都未完成；`completed`／`failed`／`stopped`／`timed_out`／`start_failed`／`supervisor_error` 是終態。`completed` 只代表程序 exit 0，仍須讀 agy 報告並驗證實際交付，不能當驗收通過。
- `stop` 只提出停止請求，須再查 `status` 確認終態。停止與逾時會清理該任務程序樹，**不回復已改的檔案**。`cleanup_error` 表示清理未確認，仍持有 repo 鎖並重試；heartbeat 過期的 `observation` 表示狀態不確定，均不得當成已停止。不要按程序名稱殺整批 agy／node，也不要自行刪除執行中的紀錄來解鎖。
- 同一步修正：先檢查既有產物，再寫新 prompt，以 `start ... --conversation '實際 conversation_id'` 接續；task ID 與 conversation ID 不同。換步驟開新對話。不自動重送失敗或逾時任務，也不用隱含的「最近一次對話」接續。
- session 中斷後用紀錄中的 task ID 查回；ID 未記下時，查看 `runs/*/status.json` 的 repo、建立時間及 prompt 確認所屬任務，不直接重派。控制器不執行 commit／push，也不代替指揮者驗證。

### 外部 Worker CLI

把 agy 或 OpenCode 當 **worker**（實作而非 review）時，流程、step 粒度、檢查節奏與踩坑一律看 `docs/others/conductor-handbook.md`；本段保留啟動入口。agy 的 review／implement 操作共用上一節；其他 reviewer 指令見 AGENTS.md。

worker 共通：非互動呼叫須關閉 stdin 並保存輸出（agy 由上述控制器處理）；**不得 stage / commit / push，commit 權在指揮者**；結果以 `git status` / `git diff` 確認實際改動，不信口頭回報。

| 觸發語 | 走哪個 |
|---|---|
| 「要 agy 做 XXX」（實作） | 上述 agy 共用控制器，`--mode implement` |
| 「要 opencode 做 XXX」 | Nemotron 3.5 Super VL via OpenCode CLI |

**Antigravity CLI（worker）**：操作統一見上方「agy 共用控制器」，不再直接組合 agy shell 指令。
- **prompt 骨架**：`C:\_work\AI_Work\Tools\agy-runs\TEMPLATE.prompt.txt` 是 adventure-table 專案寫的，專案名、repo 路徑與 Phase 文件路徑都要換成本專案（見 [指揮者手冊 §2.2](conductor-handbook.md#22-prompt-骨架)）；第一行「YOU MUST DO THIS STEP YOURSELF」一律保留。
- **拆步原則**：每個 agy 任務要在 15～20 分鐘內收斂到可驗證狀態；prompt 自足，只指向該步要讀的規格段落，明列交付物、focused test 指令與「不得 commit」。
- 每步結束後指揮者以 `git diff` 審改動、跑該步驗證，通過才依既有授權 commit；失敗把錯誤餵回同一對話修。**審完若剩餘修改很小（幾行、單一檔案、不需重新理解脈絡），指揮者直接自己改完，不再開 agy 回合。**

**Nemotron 3.5 Super VL via OpenCode CLI**（worker）：2026-10-31 起 OpenCode 已不能用 Muse，改用 `opencode/nemotron-3.5-super-vl-free`（UI 顯示名 Nemotron 3.5 Super VL Free）。用 OpenCode 桌面版內建的 CLI；不要再裝 npm 版 `opencode`（舊版資料庫與桌面版不相容，啟動即報 `Database is not empty and has no session table`）。流程、檢查節奏與權責見 [指揮者手冊 §4c](conductor-handbook.md#4c-opencode-cli-worker)。

```powershell
$c = "C:\Users\User\AppData\Local\Programs\@opencodedesktop\resources\opencode-cli.exe"
Set-Location C:\_work\AI_Work\Projects\ReturnFare
& $c run -m "opencode/nemotron-3.5-super-vl-free#high" --auto --title "<步驟>" (Get-Content -Raw -Encoding utf8 "C:\_work\AI_Work\Tools\agy-runs\opencode-<步驟>.prompt.txt") *> "C:\_work\AI_Work\Tools\agy-runs\opencode-<步驟>.log"
```

- 模型字串的 `#high` 是 effort variant；`opencode-cli.exe models` 可列出可用模型，同系列另有較小的 `opencode/nemotron-3.5-lightning-free`。
- 2026-10-31 只做過唯讀 smoke test（不加 `--auto`，讀 `PROJECT_BRIEF.md` 第一行並回傳），有無 `#high` 都 exit 0、回傳正確、工作樹無變動。**寫檔、跑 npm／Godot 尚未驗證**，第一次派正式步驟前先用小任務試。
- ⚠️ 這是免費方案，資料分享條款未核對（Muse 免費方案會分享資料）。使用者 2026-10-31 指定本專案改用此模型；派送含未公開劇情文字的任務前仍先向使用者確認。
- 加 `--auto` 才能寫檔與跑 shell，代價是 shell 指令不會被擋，禁止事項必須寫進 prompt。
- **prompt 一律寫成檔案再傳入**；長文字直接放在 PowerShell 命令列，引號會被轉壞。
- 一律 `run_in_background` 啟動，工作目錄是 repo root；worker 直接改本機工作樹。
