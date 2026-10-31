# Agent Instructions

# ReturnFare（溫泉小鎮）

一款單人、敘事驅動的網頁版**卡牌經營／調查遊戲**。45 天一輪、一天 3 個時段，走到結局後回到第一天。

- **類型**：卡牌經營 / 調查 / 迴圈敘事。含戀愛線與克蘇魯風格題材
- **一句話**：45 天，一座小鎮，同時發生太多事——你只能在場一次
- **目標平台**：網頁版（PC 優先）；觸控保留架構，手機版後置；不考慮 Steam 發行
- **當前技術棧**：TypeScript + Vite + React 18；Godot 版凍結為唯讀對照基準
- **目前階段**：網頁版移植期，以 `docs/web/` 的 W 階段契約為實作與驗收入口
- **目前進度**：以 `PROJECT_BRIEF.md` 為單一事實來源

## New Conversation Opening Check

開場依下列順序讀。**`_舊文件/` 是本機歷史 archive（已 gitignore），永遠忽略。**

**Layer 1 — 必讀：**
1. `AGENTS.md`（本檔）
2. `PROJECT_BRIEF.md`（進度與文件索引）
3. `git log --oneline -10`

**Layer 2 — 按任務讀對應段落（勿整份讀，見下方查閱規則）：**
- `docs/web/共用契約.md` — 各 W 階段共用的架構邊界、驗證與差分規則；網頁版各階段動工前必讀
- `docs/web/W1實作契約.md` ～ `W7實作契約.md` — 做哪個 W 階段，就讀該份的對應子階段；內含驗收規格、實作設計與必要驗證
- `docs/web/網頁版移植計畫.md` — 需要全案脈絡、階段拆分或 Godot ↔ TS 檔案對照時查閱
- `待決事項.md` — **全作待決項目的唯一清單**；網頁版 W-01～W-06 在第六節，按當步影響查閱
- `data/SCHEMA.md` — 資料欄位定義與資料規約

**Layer 3 — 按 W 契約點名查閱的實作與對照資料：**
- `data/` — 共用的正式內容與可調數值；卡槽住 `data/beats/`、NPC 住 `data/npcs.json`
- `web/`、`tools/trace/` — 當步相關的網頁程式、測試與軌跡工具；`web/prototype/` 只供示意，不作規則來源
- `scripts/`、`scenes/`、`tests/` — Godot 凍結對照組；按契約查閱對應檔案，W1-B 的測試觀測接點例外依契約辦理
- `docs/records/` — W 階段實作紀錄與交接證據（派工時建立）；整體進度仍只看 `PROJECT_BRIEF.md`

> 根目錄舊五份文件與 `subdocs/` 不再是網頁版例行閱讀入口。`溫泉小鎮企劃.md`、`實作規格書.md`、`開發設計方針.md` 僅在 W 契約點名時按段查閱；`測試指南.md`、`驗證後已知問題.md`、`CODEX_HANDOFF.md` 與故事／卡牌／驗證上游資料平時不讀。需追查契約引用的 Godot 歷史問題時，只讀指定 K 編號。

Report to user: current progress, and any issues with their scope of impact.

**Layer 0 — 每個任務開工前先過這張表（不是只有開場）：**

任務屬於下列哪一類，就先讀對應的 skill，再動手。**判斷任務類型是開工的第一步，不是可選項。**

| 任務類型 | 先讀 |
|---|---|
| 規劃遊戲規格、Phase 規劃、平衡調整、帶 code review 的驗證 | `gamestudio` |
| 診斷 bug、分析錯誤、找根因、效能回歸 | `diagnose` |
| 需求不清、規格討論、要問釐清問題 | `grill-me` |
| 前端／本機 web app 驗證、UI 行為除錯、瀏覽器截圖或 console log | `webapp-testing` |
| 指揮其他 agent（agy／ChatGPT／Muse 等）實作、派工、驗收 | `docs/others/conductor-handbook.md`（按該檔開頭的角色讀取指引只讀對應段落；外部 CLI 指令另見 `docs/others/local-tools.md`） |

四個 skill 已用 junction 同時掛進 `~/.claude/skills/` 與 `~/.agents/skills/`。前者供 Claude 使用；後者供支援 Agent Skills 的其他 agent（包含 Codex）發現。**出現在 session 的技能清單時直接用 skill 名字叫**。原始檔仍在 `C:\_work\AI_Work\Skills\`（改那邊就等於改這邊）；環境沒掛 junction 時退回讀檔：

- `gamestudio` → `Skills\gamestudio\SKILL.md`
- `diagnose` → `Skills\engineering\diagnose\SKILL.md`
- `grill-me` → `Skills\productivity\grill-me\SKILL.md`
- `webapp-testing` → `Skills\engineering\webapp-testing\SKILL.md`

> ⚠️ **這張表原本只住在下面「本機 Windows 環境專用」段，結果被當成參考資料而不是待辦。** 2026-08-20 的 P2-E 驗證整場沒發動 `gamestudio`（該發動：QA mode ＋ `CODEX_HANDOFF.md` 交接區塊）。搬到開場檢查裡就是為了這件事。

## 文件查閱規則

除了 `AGENTS.md` 與 `PROJECT_BRIEF.md`（開場整份讀），**其他文件一律標題 grep 定位、只讀該段**（讀到下一個同級標題為止）。網頁版優先定位 `docs/web/` 契約；不為查一個 W 子階段而整份讀舊 Godot 文件。

**不要依賴行號**——行號隨編輯漂移，一律以標題或關鍵字定位。

各文件的定位鍵：

| 文件 | 定位鍵 | 例 |
|---|---|---|
| `docs/web/共用契約.md` | 架構、驗證、差分等分組標題 | `rg -n '^## ' docs/web/共用契約.md` |
| `docs/web/W<N>實作契約.md` | W 子階段編號與段內標題 | `W1-A`、`驗收規格`、`實作設計`、`必要驗證` |
| `docs/web/網頁版移植計畫.md` | 階段拆分、技術選型、檔案對應等標題 | `rg -n '^#{2,3} ' docs/web/網頁版移植計畫.md` |
| `data/SCHEMA.md` | 檔名小節 | `## beats/*.json`、`### slots[]` |
| `待決事項.md` | 第六節與 W 條目編號 | `rg -n 'W-0[1-6]|^## ' 待決事項.md` |
| `docs/records/` | 當步 W 編號與交接標題 | 只讀該步紀錄與證據 |
| 契約點名的舊文件 | 指定標題、Phase 或 K 編號 | 只查引用段落，不擴讀整份歷史帳本 |

### 按 Phase 查閱規則

實作或驗收某個 W 子階段（例：W1-A）時，先定位共用契約與該階段契約：

```
rg -n '^## ' docs/web/共用契約.md
rg -n 'W1-A|^## |^### ' docs/web/W1實作契約.md
```

先讀共用契約的適用段落，再讀該 W 契約的「交付範圍與依賴」及目標子階段，均讀到下一個同級標題為止。**同一份 W 契約內已包含驗收規格（做成什麼樣）、實作設計（怎麼做）與必要驗證（怎麼驗）**，動工前須讀齊；另讀該步引用的共用格式、前置介面與守衛。不要再例行讀 Godot 的規格書／方針／測試指南三份文件；只有契約點名時才回查。

## 文件分工與單一事實來源

**同一件事只住一個地方。** 這是本專案吃過虧才建立的規則（見 commit `887e4c1` 的合併）。

| 住哪 | 放什麼 | 例 |
|---|---|---|
| **`data/` JSON** | **所有可調數值** | 手牌格數、發狂卡上限、倒數天數、標記價碼 |
| **`docs/web/共用契約.md`** | 網頁版共用架構、驗證與差分規則 | 純 TS 規則層與 UI 的邊界 |
| **`docs/web/W<N>實作契約.md`** | 網頁版各階段驗收規格、實作設計與必要驗證 | W1-A 的可動檔案與資料同步驗證 |
| **`PROJECT_BRIEF.md`** | 全案目前進度與文件索引 | 各 W 子階段狀態 |
| **`溫泉小鎮企劃.md`** | 規則的形狀與**為什麼** | 「為什麼不跨輪——會重演知識卡佔格那個坑」 |
| **`實作規格書.md`** | Godot 原版驗收意圖；網頁版僅按契約引用查閱 | 「發狂卡達到上限時進入發瘋 BE，且不播後日談骨架」 |
| **`開發設計方針.md`** | Godot 原版實作契約；網頁版僅按契約引用查閱 | 「Autoload 只有 Data 與 GameState 兩個」 |
| **`待決事項.md`** | 所有還沒拍板的東西 | — |

**文件裡不寫可調數值**，一律指向 `data/`。理由：prototype 的整個玩法就是一邊玩一邊改數值，文件存了就會過期。

> Godot 原版已完成的 Phase 段落搬進 `subdocs/歸檔/`，原位保留原標題一字不改 ＋ 一行 stub，維持可 grep。歸檔檔 append-only；此為舊版歸檔規則，不作為 W 階段閱讀入口。

## 修改授權與驗證規則

（單一事實來源；其他文件不重複本節內容。）

除非使用者明確要求「修」、「修改」、「實作」、「處理某個 phase」、「commit」或「提交」，否則不得：

- 修改任何程式碼、文件或設定檔
- 自行套 patch
- stage 檔案
- 建立 commit

當使用者要求「驗證」，或只是描述錯誤、貼截圖、詢問原因、要求解釋、要求列出問題、詢問某功能怎麼使用時：只能進行檢查、讀檔、執行測試、code review、啟動本機服務與回報結果。若發現問題，只列出問題、影響範圍與建議修法，等待使用者下一步指示。

(English mirror: only modify files when the user explicitly requests fix / implement / commit. Verify / diagnose = report only.)

## 設計討論的方式

**每個問題都要先想好一個解法再拿出來討論。** 不要把開放題原封退回給使用者。

- 有多種讀法時，把選項連同取捨一起端出來，並且**給出推薦**。
- 發現設計有洞時，講清楚**影響範圍**（哪一天、哪條線、哪個既有規則會被打到），不要只說「這裡怪怪的」。
- 使用者重申某個決定時，那就是拍板；照做，不要重新辯論。

## 實作守則

1. **API 簽名預先核對**：呼叫任何專案內腳本、Autoload、系統 API 前，先 grep / 讀檔核對最新定義與參數列，不憑記憶編寫。
2. **長函式變數加後綴**：大型或長函式中新增的變數要帶專屬後綴（如 `hand_state_phase3`），避免同名衝突。
3. **編譯錯誤同 turn 修完**：跑測試或語法檢查時取同步結果；有錯就在同一個 turn 內修到通過，不讓編譯錯誤流向使用者。
4. **角色分離**：實作者改程式碼、測試、fixture 與 `開發設計方針.md`（implementer-owned）。`測試指南.md`、`驗證後已知問題.md`、`PROJECT_BRIEF.md` 屬 verifier 角色，實作者只列建議、不直接改。實作者跑完只提供證據（exit code、報告路徑、catalog 重數出來的實際數字），打勾與落檔由 verifier 做——**要求實作者自己勾自己的驗收就是分工失效**（K-101）。
5. **驗收對應與變異保真**：新增或修正關鍵規則、接線、拒絕矩陣時，每條驗收契約都要有可定位的測試證據；完成後暫時移除接線或反轉目標判斷，確認對應測試確實轉紅，再還原並重跑全綠。不得只憑測試名稱、註解或成功路徑宣稱已覆蓋。
6. **正式資料的端到端入口必測**：涉及系統流轉時，除了底層 API 測試，至少要有一條使用正式資料、從最高層生命週期入口（時段推進、入夜、UI 發派等）走完整鏈路的驗收；合成 fixture 只作補充，不能取代真實接線證據。
7. **拒絕原子性、效果基數與 fixture 隔離**：契約要求零副作用的拒絕操作，前後可序列化狀態必須逐字一致；「效果只套一次」必須用可累加或可計數結果斷言，能分辨一次與重複套用；測試注入的 mock／壞資料必須在案例結束後完整還原，不得污染後續測試。

## 文件關門的固定提交流程

使用者已於 2026-08-27 明示：verifier 完成已知問題或 Phase 的文件關門後，應在同一 turn `commit` 並 `push`，不必等待再次提醒。這只適用已獲授權的文件關門；其他程式、資料或設定修改仍依「修改授權與驗證規則」。

---

## 本機 Windows 環境專用

> 本段僅適用於使用者本機 Windows 環境（工具都在 `C:\`）。**remote / CI / Linux session 沒有這些路徑與工具，跳過本段**；此類 session 無法執行 Godot headless，驗證項目列出後交回本機執行。

### Project Skills

原始檔住 `C:\_work\AI_Work\Skills\`；四個 skill 已用 junction 掛進 `~/.claude/skills/` 與 `~/.agents/skills/`（`gamestudio`、`diagnose`、`grill-me`、`webapp-testing`）。`.claude/skills` 供 Claude 使用；`.agents/skills` 供支援 Agent Skills 的其他 agent（包含 Codex）發現。改原始檔等於改兩邊掛進去的同一份。

**觸發表已搬到 `New Conversation Opening Check > Layer 0`，本節不重複。**

### 專案外部工具路徑

外部工具不放進本專案 repo。

| 工具 | 路徑 | 用途 |
|---|---|---|
| Godot 4.6.3 editor | `C:\_work\Godot_v4.6.3\Godot_v4.6.3-stable_win64.exe` | 引擎（GUI 版） |
| Godot 4.6.3 console | `C:\_work\Godot_v4.6.3\Godot_v4.6.3-stable_win64_console.exe` | 引擎（CLI 版，headless 驗證用） |
| Godot export templates | `C:\Users\User\AppData\Roaming\Godot\export_templates\4.6.3.stable\` | ✅ 已安裝 |
| agent-sprite-forge | `C:\_work\AI_Work\Tools\agent-sprite-forge` | AI 生成 2D sprite / map / prop |
| Codex DeepSeek home | `C:\_work\AI_Work\Tools\codex-deepseek-home` | DS reviewer 環境 |

### Godot Headless 驗證

在本機 Windows / sandbox 環境中，Godot headless 直接在 sandbox 內執行會因無法開啟 `user://logs/godot*.log` 而 crash（signal 11）。執行 headless 驗證時不要先跑 sandbox 版再讓它 crash；直接用 escalated 權限執行同一命令，並回報這是已知 sandbox log 權限限制。

搬動 `.tscn` / `.gd` 或改 CSV 翻譯後，headless 前先 `--import` 重建快取。

### Python 執行環境規則

⚠️ 本專案目前**沒有 `.venv`**。若之後需要 Python（資料轉換、驗證腳本），先在專案根目錄建立，之後一律使用 `.\.venv\Scripts\python.exe`，讓 agent 與使用者看到一致結果。

### 素材生成

美術方向已定：沿用目前地圖、場景素材與示意版的視覺方向（見 `待決事項.md` W-03），新增素材須保持一致，不因尚無獨立 Art Bible 而重開方向討論。

`g2d 生 XXX 圖` shorthand：`XXX` 是地點 / 場景 / 房間 / 街道 / 地圖時用 `$generate2dmap`，否則用 `$generate2dsprite`。名詞已經明確指向其中一類時不要反問使用者。

網頁版直接使用的成品圖放 `web/public/art/`，一律轉 WebP：

- 地圖：`web/public/art/map/`
- 地點場景圖：`web/public/art/scenes/<地點 id>.webp`（檔名＝`data/locations.json` 的地點 id，程式直接用 id 找圖）
- 其他類別（sprite 等）用到時在 `web/public/art/` 下開對應子資料夾

生成過程的 raw / prompt / 中間檔不進 repo，只保留上線用的成品。

### DeepSeek Codex CLI Reviewer

使用者說「要 ds4 pro 做 XXX」「要 ds4 flash 做 XXX」時，透過本機 Moon Bridge DeepSeek 設定走 Codex CLI。

Model mapping：`ds4 pro` → `deepseek-v4-pro`；`ds4 flash` → `deepseek-v4-flash`；只說 `ds4` 用 `deepseek-v4-pro`。

Default mode: read-only reviewer.
- 用 `CODEX_HOME=C:\_work\AI_Work\Tools\codex-deepseek-home`。
- 不寫檔、不刪檔、不 stage、不 commit、不 push。
- 不讀 `.env`、`data/`、`_舊文件/`、`C:\_work\AI_Work\Tools\`。
- 結果當第二意見，回報前先自己審一遍。
- 非互動呼叫（`codex exec`）必須 `< NUL` 關閉 stdin，否則會停在 `Reading additional input from stdin...` 永久卡死。

### Antigravity CLI (agy) Reviewer

使用者說「要 agy 做 XXX」「用 agy 審 / 驗證 XXX」時走 `agy`。

Binary：`C:\Users\User\AppData\Local\agy\bin\agy.exe`（在 user PATH，但部分 shell 的 PATH 快照可能沒有，直接用完整路徑最穩）。

```powershell
cmd /c "C:\Users\User\AppData\Local\agy\bin\agy.exe -p `"<任務>`" --model `"<模型>`" --add-dir `"C:\_work\AI_Work\Projects\ReturnFare`" --dangerously-skip-permissions --print-timeout 540s < NUL > <輸出檔> 2>&1"
```

四個參數都是必要的，各修一個已驗證的失敗模式：

- `< NUL`：非 TTY 下 agy 會癡等 stdin 永久卡死（連自己的 print-timeout 都不會觸發）。主因是 stdin，不是權限確認框。
- `> 檔案`：非 TTY 下 stdout 不導檔就看不到任何輸出。
- `--add-dir <專案路徑>`：不加的話 agy 只在自己的 sandbox 暫存區活動，cwd 不算數——它會回報成功但專案裡什麼都沒發生。
- `--dangerously-skip-permissions`：單次生效，不動持久設定。

Model selection：`--model` 吃 `agy models` 列出的**完整顯示字串**（含括號內專注程度），例如 `"Gemini 4 Argon (High)"`。未指定時一律預設 `"Gemini 4 Argon (High)"`。

Default mode: read-only reviewer.
- prompt 內明確要求：不建立 / 修改 / 刪除任何檔案、不跑會寫檔的命令、輸出純文字報告。
- 跑完必以 `git status` / `git diff` 確認實際改動；agy 的口頭回報不可作為改動依據。

### Codex CLI (OpenAI) Reviewer

使用者說「要 codex 做 XXX」「用 codex 審 / 驗證 XXX」（不帶 `ds4`）時，用預設 `CODEX_HOME` 走 `codex exec`。

```powershell
cmd /c "codex exec `"<任務>`" --sandbox read-only -C `"C:\_work\AI_Work\Projects\ReturnFare`" --ephemeral -o `"<結果檔>`" < NUL > `"<過程log檔>`" 2>&1"
```

- `< NUL`：非 TTY 下會停在 `Reading additional input from stdin...` 永久卡死，與 agy 同族病因。
- `--sandbox read-only`：引擎層強制唯讀（比 prompt 口頭約束可靠）；寫入任務改 `--sandbox workspace-write`。
- `-o <結果檔>`：只寫最終回覆，與 stdout 的完整過程 log 分離。

Model selection：預設 `gpt-5.5` + `model_reasoning_effort = "high"`（來自 `~/.codex/config.toml`）。要換模型用 `-m <model>`，專注程度用 `-c model_reasoning_effort="low/medium/high"` 覆蓋。

Default mode: read-only reviewer；結果當第二意見。
