# 本機工具與執行規則

本檔承接 [AGENTS.md](../../AGENTS.md) 的本機 Windows 與外部 worker 指令。不是開場必讀；執行相關工作前只讀對應段落。

| 工作 | 先讀 |
|---|---|
| Godot headless 驗證 | 本檔「Godot headless 驗證」；sandbox 限制見 AGENTS.md「Godot Headless 驗證」 |
| 網頁版（`web/`）測試與 build | 本檔「網頁版測試」 |
| 外部 reviewer（唯讀審查） | AGENTS.md「DeepSeek Codex CLI Reviewer」「Antigravity CLI (agy) Reviewer」「Codex CLI (OpenAI) Reviewer」 |
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
| agy 執行紀錄 | `C:\_work\AI_Work\Tools\agy-runs\` | prompt 檔、輸出 JSON、`TEMPLATE.prompt.txt`、`report.py` |
| OpenCode CLI | `C:\Users\User\AppData\Local\Programs\@opencodedesktop\resources\opencode-cli.exe` | OpenCode worker（Nemotron 3.5 Super VL） |

### 外部 Worker CLI

把 agy 或 OpenCode 當 **worker**（實作而非 review）時，流程、step 粒度、檢查節奏與踩坑一律看 `docs/others/conductor-handbook.md`；本段只保留啟動指令。唯讀審查的指令與共通規則在 AGENTS.md，本檔不重抄。

worker 共通：非互動呼叫必須 `< NUL` 關閉 stdin，否則會停在等待輸入永久卡死；輸出重導到檔案保留；**不得 stage / commit / push，commit 權在 Claude**；結果以 `git status` / `git diff` 確認實際改動，不信口頭回報。

| 觸發語 | 走哪個 |
|---|---|
| 「要 agy 做 XXX」（實作） | Antigravity CLI worker |
| 「要 opencode 做 XXX」 | Nemotron 3.5 Super VL via OpenCode CLI |

**Antigravity CLI（worker）**：binary 在 user PATH，但部分 shell 的 PATH 快照可能沒有，直接用完整路徑最穩。

```powershell
cmd /c "C:\Users\User\AppData\Local\agy\bin\agy.exe -p `\"<任務>`\" --model `\"<模型>`\" --add-dir `\"C:\_work\AI_Work\Projects\ReturnFare`\" --dangerously-skip-permissions --output-format json --print-timeout 20m < NUL > C:\_work\AI_Work\Tools\agy-runs\<步驟>.json 2>&1"
```

- `--add-dir` 讓 agy 讀到專案，`--dangerously-skip-permissions` 單次生效不動持久設定，兩者都不可省。
- **`-p` 只能放單行短句，任務本文寫進檔案讓 agy 自己讀**（例：`-p "Your full task is in C:\_work\AI_Work\Tools\agy-runs\<步驟>.prompt.txt. Read it first, then follow every instruction in it."`，並多加一個 `--add-dir C:\_work\AI_Work\Tools\agy-runs`）。多行 prompt 經 `cmd /c` 會在第一個換行截斷，後面的 flag 與重導全部遺失，agy 會以無權限狀態靜默結束。
- **一律 `run_in_background` 啟動**，不同步等；結束時 Claude 會被喚醒，直接讀輸出檔審結果。輸出落在 repo 外的 `C:\_work\AI_Work\Tools\agy-runs\`，session 中斷也找得回。
- `--output-format json` 回傳 `conversation_id`／`status`／`duration_seconds`／`usage`。**同一步驟的修改回合用 `--conversation <id>` 接續**（每輪整段重送、無 cache，累積數輪即換新對話）。**換下一步驟一律開新對話**。
- **prompt 骨架**：`C:\_work\AI_Work\Tools\agy-runs\TEMPLATE.prompt.txt` 是 adventure-table 專案寫的，專案名、repo 路徑與 Phase 文件路徑都要換成本專案（見 [指揮者手冊 §2.2](conductor-handbook.md#22-prompt-骨架)）；第一行「YOU MUST DO THIS STEP YOURSELF」一律保留。
- **拆步原則**：每個 agy 任務要在 15～20 分鐘內收斂到可驗證狀態；prompt 自足，只指向該步要讀的規格段落，明列交付物、focused test 指令與「不得 commit」。
- 每步結束後 Claude 以 `git diff` 審改動、跑該步驗證，通過才 commit；失敗把錯誤餵回同一對話修。**審完若剩餘修改很小（幾行、單一檔案、不需重新理解脈絡），Claude 直接自己改完再 commit，不再開 agy 回合。**
- Model：`--model` 用 `agy models` 列出的完整顯示字串，未指定時預設 `"Gemini 4 Argon (High)"`。

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
