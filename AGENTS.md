# Agent Instructions

# ReturnFare（溫泉小鎮）

一款 Steam 買斷制、單人、敘事驅動的**卡牌經營／調查遊戲**。45 天一輪、一天 3 個時段，走到結局後回到第一天。

- **類型**：卡牌經營 / 調查 / 迴圈敘事。含戀愛線與克蘇魯風格題材
- **一句話**：45 天，一座小鎮，同時發生太多事——你只能在場一次
- **目標平台**：Steam（PC）優先；觸控保留架構，手機版後置
- **引擎**：Godot 4.6 / GDScript（GL Compatibility）
- **目前階段**：⚠️ **設計文件階段，尚無 Godot 專案**。正在準備第一輪可玩 prototype（目標是 45 天一路玩到底、一邊玩一邊調整）
- **目前進度**：以 `PROJECT_BRIEF.md` 為單一事實來源（該檔尚未建立時，以 `git log` 為準）

## New Conversation Opening Check

開場依下列順序讀。**`_舊文件/` 是本機歷史 archive（已 gitignore），永遠忽略。**

**Layer 1 — 必讀：**
1. `AGENTS.md`（本檔）
2. `PROJECT_BRIEF.md`（進度與文件索引）
3. `git log --oneline -10`

**Layer 2 — 按任務讀對應段落（勿整份讀，見下方查閱規則）：**
- `溫泉小鎮企劃.md` — 設計聖經：**規則與為什麼**
- `待決事項.md` — **全作待決項目的唯一清單**。其他文件遇到 ⚠️ 待決標記時，條目都在這裡
- `技術概念.md` — 架構、資料格式、存檔分層
- `開發設計方針.md` — Phase 實作契約（含該 Phase 的驗收）
- `測試指南.md` — 操作層驗收（verifier 角色）
- `驗證後已知問題.md` — 待修清單與已接受的邊界決定；修 bug 前先看

**Layer 3 — 任務相關細節（不逐檔枚舉，開工時 `ls subdocs/<分類>/` 再挑）：**
- `subdocs/故事線/` — 第一輪三章逐日事件層
- `subdocs/地點/` — 地點的卡槽定義
- `subdocs/人/` — NPC 設定
- `subdocs/卡片/` — 卡片清單
- `subdocs/驗證/` — 體驗模擬等驗證產出
- `subdocs/歸檔/` — 歷史歸檔；除非考古不必讀

Report to user: current progress, and any issues with their scope of impact.

## 大文件查閱規則

`溫泉小鎮企劃.md`（約 90 KB）與三章故事線（各 50–70 KB）**一次讀不完，工具會截斷**。任何情況下都不要整份讀。

用標題 grep 定位，只讀該段（讀到下一個同級標題為止）：

```
grep -n "^#\{1,3\} " 溫泉小鎮企劃.md          # 先看章節標題
grep -n "第 22 天\|發狂卡" subdocs/故事線/*.md  # 再依關鍵字定位
```

- **不要依賴行號**——行號隨編輯漂移，一律以標題或關鍵字定位。
- 企劃書的章節是中文數字（`## 七、迴圈與回溯`），故事線是「第 N 天」小節。

## 文件分工與單一事實來源

**同一件事只住一個地方。** 這是本專案吃過虧才建立的規則（見 commit `887e4c1` 的合併）。

| 住哪 | 放什麼 | 例 |
|---|---|---|
| **`data/` JSON** | **所有可調數值** | 手牌格數、發狂卡上限、倒數天數、標記價碼 |
| **`溫泉小鎮企劃.md`** | 規則的形狀與**為什麼** | 「為什麼不跨輪——會重演知識卡佔格那個坑」 |
| **`開發設計方針.md`** | 這個 Phase**什麼必須為真**（驗收） | 「發狂卡達到上限時進入發瘋 BE，且不播後日談骨架」 |
| **`待決事項.md`** | 所有還沒拍板的東西 | — |

**文件裡不寫可調數值**，一律指向 `data/`。理由：prototype 的整個玩法就是一邊玩一邊改數值，文件存了就會過期。

> 已完成的 Phase 段落搬進 `subdocs/歸檔/`，原位保留原標題一字不改 ＋ 一行 stub，維持可 grep。歸檔檔 append-only。

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
4. **角色分離**：實作者只改程式碼、測試與 fixture。`測試指南.md`、`驗證後已知問題.md`、`開發設計方針.md` 屬 verifier 角色，實作者只列建議、不直接改。

---

## 本機 Windows 環境專用

> 本段僅適用於使用者本機 Windows 環境（工具都在 `C:\`）。**remote / CI / Linux session 沒有這些路徑與工具，跳過本段**；此類 session 無法執行 Godot headless，驗證項目列出後交回本機執行。

### Project Skills

This project uses local skills from `C:\_work\AI_Work\Skills\`.

Trigger rules:
- Diagnosing bugs / analyzing errors / finding root cause → read `Skills\engineering\diagnose\SKILL.md` first
- Requirements unclear / spec discussion / planning / need to ask clarifying questions → read `Skills\productivity\grill-me\SKILL.md` first
- Planning game specs / verification with code review → read `Skills\gamestudio\SKILL.md` first
- Frontend / local web app verification, UI behavior debugging, browser screenshots, or console logs → read `Skills\engineering\webapp-testing\SKILL.md` first

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

⚠️ **本專案目前還沒有 Godot 專案**，以下在 `project.godot` 建立之後才適用。

在本機 Windows / sandbox 環境中，Godot headless 直接在 sandbox 內執行會因無法開啟 `user://logs/godot*.log` 而 crash（signal 11）。執行 headless 驗證時不要先跑 sandbox 版再讓它 crash；直接用 escalated 權限執行同一命令，並回報這是已知 sandbox log 權限限制。

搬動 `.tscn` / `.gd` 或改 CSV 翻譯後，headless 前先 `--import` 重建快取。

### Python 執行環境規則

⚠️ 本專案目前**沒有 `.venv`**。若之後需要 Python（資料轉換、驗證腳本），先在專案根目錄建立，之後一律使用 `.\.venv\Scripts\python.exe`，讓 agent 與使用者看到一致結果。

### 素材生成

⚠️ 本專案目前**沒有 Art Bible，也還沒談美術方向**。開始生圖前要先定，避免風格漂移。

`g2d 生 XXX 圖` shorthand：`XXX` 是地點 / 場景 / 房間 / 街道 / 地圖時用 `$generate2dmap`，否則用 `$generate2dsprite`。名詞已經明確指向其中一類時不要反問使用者。

預設輸出路徑：

- 地圖類：`C:\_work\AI_Work\Projects\ReturnFare\assets\generated\maps\<asset_name>\`
- Sprite 類：`C:\_work\AI_Work\Projects\ReturnFare\assets\generated\sprites\<asset_name>\<action_or_variant>\`

生成的 raw / processed / frame / prompt / metadata 全部留在該資產資料夾內。檔名帶秒級 timestamp 後綴避免碰撞（例如 `hot-spring-inn-20260811-164029.png`），不要重用 `prompt-used.txt`、`concept.png` 這種通用名。

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

Model selection：`--model` 吃 `agy models` 列出的**完整顯示字串**（含括號內專注程度），例如 `"Gemini 3.5 Flash (High)"`。未指定時一律預設 `"Gemini 3.5 Flash (High)"`。

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
