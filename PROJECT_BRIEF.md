# ReturnFare 專案簡報

本文件供新 session 快速了解專案全貌；需要細節時按下方文件索引深入。**本檔是唯一「隨進度持續更新」的文件**（每個 Phase 收尾更新一次）。

最後更新：2026-08-13

> **當前進度**：第一輪資料層完成（三章 beats 鋪滿、headless 驗證全綠）；四份關鍵文件（實作規格書／開發設計方針／測試指南／本檔）建立完成；**Phase 1（最小可玩迴圈）規格可實作、程式未動工**。

---

## 專案概述

Steam 買斷制、單人、敘事驅動的**卡牌經營／調查／迴圈敘事**遊戲。45 天一輪、一天 3 個時段，走到結局後回到第一天。含戀愛線與克蘇魯風格題材。

- **引擎**：Godot 4.6.3 / GDScript（GL Compatibility）
- **核心資料結構**：一切都是卡槽（`data/SCHEMA.md > 核心概念`）——遭遇、縱慾、委託、比對都是同一個放卡動作
- **規模基準**：《蘇丹的遊戲》量級的內容量；架構按正式商用遊戲立（`實作規格書.md > 架構基線`）
- **驗證哲學**：無隨機、決定論、headless 可自動走查

## 目錄結構

```text
.
├── project.godot            # 資料夾與文件庫共用（刻意，見檔內註解）
├── data/                    # 全部遊戲內容與可調數值（單一事實來源）
│   ├── SCHEMA.md            # 欄位定義
│   ├── tuning.json          # 全部可調數值
│   ├── cards.json / locations.json / npcs.json
│   └── beats/               # 三章逐日事件，10 檔
├── scenes/main.tscn         # 目前為空殼，P1-A 起長出宿主
├── scripts/
│   ├── data_loader.gd       # class_name DataLoader：載入＋引用檢查
│   └── verify_data.gd       # headless 資料驗證（exit 0 = 綠）
├── subdocs/                 # 故事線／人／卡片／地點／驗證／歸檔
└── _舊文件/                 # 本機歷史 archive（gitignore），永遠忽略
```

## 資料層現況

headless 實測（2026-08-13，`verify_data.gd`）：**54 張卡／48 個地點（白天 20＋夜間 28）／18 個 NPC／252 個 beat**；引用 0 錯誤；地點三分類 10／10／16；第 1–45 天行動格全覆蓋（第 1 天上午下午、第 32 天下午為刻意留空，名單將抽至 `scripts/core/data_facts.gd` 共用）。

## Phase 進度

> 狀態圖例（沿用 AfterTheModel 慣例）：✅ 完成（含可驗收）；🟦 待驗收；🟧 待 headless；📐 規格可實作（三份文件已寫到可動工、程式未開工）；⬜ 待開工／待規劃。

| Phase | 狀態 | 概要 |
|---|---|---|
| 資料層 | ✅ | 三章 beats 鋪滿、schema 語彙補齊、Godot 專案與 DataLoader／verify_data 站起來（詳見 `git log`） |
| 文件層 | ✅ | 四份關鍵文件建立；文件分工與流向定案（見下方文件索引） |
| P1-A 遊戲狀態與時段狀態機 | 📐 | GameState＋Data autoload、45 天 × 4 時段循環、序列化骨架 |
| P1-B 卡片與手牌 | 📐 | 卡片實體化、手牌／知識分離、主角卡釘死 |
| P1-C 地圖、面板與三態 | 📐 | 面板聚合、三態求值、fixed beat 與 on_enter |
| P1-D 放置與效果結算 | 📐 | 放卡、on_place 結算、行動格消耗、條件求值器、語彙 lint |
| P1-E choice_group | 📐 | 互斥選擇題、選定即定案、雙入口 |
| P1-F 45 天全程走通 | 📐 | 殘響播出、夜間 stub、結局 stub、迴圈重置、貪心走查腳本 |
| P2 發狂時鐘與縱慾 | ⬜ | 驗收＝headless 重演 `subdocs/驗證/發狂卡機制模擬.md` 三種玩家 |
| P3 夜間層真值化 | ⬜ | 標記收費、對位改名、meta 免費 |
| P4 委託與遭遇 | ⬜ | 人物卡外出／回報、遭遇回合循環 |
| P5 結局、開局與迴圈 | ⬜ | 三結局、開局十分鐘、繼承完整版 |
| P6 存檔 UI | ⬜ | 槽位、version 遷移、輪中存讀 |
| 內容期 | ⬜ | 文本／演出／UI 正式化／i18n——引擎期玩過之後才排 |

## 測試速查

```powershell
C:\_work\Godot_v4.6.3\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://scripts/verify_data.gd
C:\_work\Godot_v4.6.3\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/playthrough_greedy.gd   # P1-F 起
```

- sandbox 內 headless 會因 `user://logs` 權限 crash：直接 escalated 執行（`AGENTS.md > Godot Headless 驗證`）。
- 搬動 `.tscn` / `.gd` 後先 `--import`。
- 最新測試結果不在本檔維護：看 `git log` 最近 commit message。

## 文件索引（誰住哪、何時讀）

| 文件 | 職責 | 何時讀 |
|---|---|---|
| `AGENTS.md` | 專案規則、修改／驗證授權、本機工具路徑 | 新 session 開場必讀 |
| `PROJECT_BRIEF.md`（本檔） | 進度快照與索引 | 開場第二讀，再按需深入 |
| `溫泉小鎮企劃.md` | 設計聖經：**規則的形狀與為什麼** | 設計討論；90 KB，一律標題 grep |
| `實作規格書.md` | **引擎必須做什麼**＋各 Phase 驗收意圖 | 實作與驗收；按系統章或 Phase 標題 grep |
| `開發設計方針.md` | 各 Phase **實作契約**（檔案、API、接線） | 動工前；implementer-owned |
| `測試指南.md` | headless 命令＋操作層驗收清單 | 自我驗收與驗證；verifier-owned |
| `data/SCHEMA.md` | 資料欄位定義 | 讀寫 `data/` 之前 |
| `待決事項.md` | **全作待決項目的唯一清單** | 遇到 ⚠️ 標記時 |
| `subdocs/故事線/` | 三章逐日事件層（各 50–70 KB，標題 grep） | 改動某天內容時 |
| `subdocs/驗證/` | 體驗模擬與機制模擬 | 調數值前 |
| `subdocs/歸檔/` | 已完成 Phase 段落與歷史歸檔 | 考古時 |
| `驗證後已知問題.md` | 待修清單（**尚未建立**，第一波驗證收尾時建） | 修 bug 前 |

**流向一句話**：還沒拍板 → 待決事項；規則與為什麼 → 企劃書；具體內容 → subdocs＋data；驗收意圖 → 規格書；怎麼做 → 方針；數值 → tuning。上游往下編譯，永不反向（完整版住 `實作規格書.md > 本檔範圍與邊界`）。

**同一個 Phase 的三份文件**：要做成什麼樣 → `實作規格書.md > P1-X`；怎麼做 → `開發設計方針.md > P1-X`；怎麼驗 → `測試指南.md > P1-X`。精準查法（含各文件定位鍵）住 `AGENTS.md > 文件查閱規則`。

## 實作注意事項

- 修改授權／verify-only 規則：`AGENTS.md > 修改授權與驗證規則`（單一事實來源，本檔不重複）。
- 文件角色：方針偏 implementer-owned；測試指南、驗證後已知問題偏 verifier-owned，實作者只列建議。
- 文件裡不寫可調數值，一律指 `data/tuning.json`。
- `.claude/` 是本機 tooling config，不 commit。

## 下一步

- **P1-A 動工**（契約見 `開發設計方針.md > P1-A`）。依賴線性：A → B → C → D → E → F。
- 2026-08-13：verifier 覆審（`P1文件審核.md`）五個契約缺口已全數修正——放置持有檢查、choice 原子化＋RESOLVED、夜間可達性（睡覺解析旅館、附加 beat、`day_at_least` 語彙、lint 7）、卡片 unique／gain 冪等、NPC 投入帳契約；`n_take_something` 與 `n_landmark` 資料已對齊。
- 2026-08-13：codex 全文審查的六條必修＋次要項已全數修正（規則層下沉到 GameState／PanelBuilder、evening 改「非行動格」規則、第 45 天 evening 結局 coda、夜間三步解析、槽一次性 `beat_id+slot_id`、`enter_beat` 統一入口、fixture 化破壞性測試）；第 1、2 夜重複 beat 已清理。
- 2026-08-13：**待決 1／20／37 全部結案**。① 第一章第三次殘響落在第 12 天下午（`d12_pm_awei.echo`），並修掉兩條無 `day` 的複本與 `d8_echo_bathhouse` 的地點綁定——第一章保證播出的殘響從 1 條回到 3 條；全作另有四條缺 `day` 的 echo 一併補齊（現在 7 條齊全）② `k_town_covers` 原本第一輪拿不到（三個 dodger 全擠在第 27 天下午的同一個行動格），兩格改掛 evening 修正 ③ 第 37–38 天兩張證據卡改成真互斥，並補 `d38_clinic` 撐住第 38 天下午的行動格 ④ 待決 20 拍板 18 人、`night_reveal` 全 null。**連帶補了兩條引擎契約**：lint 8（殘響可播出性）與 evening 演出流的結算順序（陣列順序）。
- 未拍板的落差集中在 `實作規格書.md > 附：本檔對資料層的既知落差清單`（縱慾權重、`ending` 鍵、開局選單、委託形狀——各自綁定後續 Phase）。
- 2026-08-13：**待決 20 完成第一版**——`data/npcs.json`（18 人的可及性）＋夜間三分類（`day_counterpart`，10／10／16），四個缺口全部處理，`verify_data` 新增三條檢查。
- 2026-08-13：**發狂卡機制模擬重跑兩次**（現行結論見該檔第一節）。第二次修資料落差（收費標記 10 → 14，`43f29ee` 擴阿宏鏈後一直沒重跑）；第三次修模型自己的錯——前兩次讓玩家一夜開多個標記，而 `實作規格書.md > 九、夜間層` 一直寫著「一晚選一個地點」。**待決 35／36／38／41／42／43／44 全部更新，其中 42、43、44 結案。** 現行數字：收費標記 14、深潛峰值 4（cap 7 餘裕 3）、強制縱慾 11 次其中最重 4 次、視野窗口兩個（第 8–23／26 天、第 42–44 天）。唯一改動的數值是 `forced_normal_until` 5 → 7（待決 43）。
