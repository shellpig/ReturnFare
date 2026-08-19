# ReturnFare 專案簡報

本文件供新 session 快速了解專案全貌；需要細節時按下方文件索引深入。**本檔是唯一「隨進度持續更新」的文件**（每個 Phase 收尾更新一次）。

最後更新：2026-08-20

> **當前進度**：第一輪資料層完成（三章 beats 鋪滿、headless 驗證全綠）；四份關鍵文件建立完成；**Phase 1（最小可玩迴圈）P1-A～P1-H 已全部實作並驗證全綠**；**Phase 2-A 發狂卡的產生與倒數、P2-B 縱慾出口與主動縱慾、P2-C 強制縱慾與失控時段均已實作並驗收（全套 14 套 headless exit 0）**；**UI 模擬驗證工具鏈（`tests/ui_sim/`）58 條 UI 契約、76 個案例變體**。⚠️ **UI 模擬的可重現性仍未結案**——2026-08-16 乾淨環境連跑三輪，第 1、3 輪全綠，第 2 輪紅一條（`驗證後已知問題.md > K-48`，已重開）；K-48 要收就得連跑三輪。**下一步進 P2-D 視野門檻與發瘋 BE。**

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
│   ├── cards.json / card_types.json / locations.json / npcs.json
│   └── beats/               # 三章逐日事件，10 檔
├── scenes/main.tscn         # 目前為空殼，P1-A 起長出宿主
├── scripts/
│   ├── data_loader.gd       # class_name DataLoader：載入＋引用檢查
│   └── verify_data.gd       # headless 資料驗證（exit 0 = 綠）
├── subdocs/                 # 故事線／人／卡片／地點／驗證／歸檔
└── _舊文件/                 # 本機歷史 archive（gitignore），永遠忽略
```

## 資料層現況

headless 實測（2026-08-14，`verify_data.gd`）：**54 張卡／48 個地點（白天 20＋夜間 28）／18 個 NPC／257 個 beat**；引用 0 錯誤；地點三分類 10／10／16；lint 1／2／3／5／7／8 全 0 錯誤（lint 3 為 4 筆已豁免警告）；第 1–45 天行動格全覆蓋（第 1 天上午下午、第 32 天下午為刻意留空，名單抽至 `scripts/core/data_facts.gd` 共用）。貪心走查 90 個行動時段用掉 56 格，其餘 34 格逐格分類並印出原因（`playthrough_greedy.gd`）。

## Phase 進度

> 狀態圖例（沿用 AfterTheModel 慣例）：✅ 完成（含可驗收）；🟦 待驗收；🟧 待 headless；📐 規格可實作（三份文件已寫到可動工、程式未開工）；⬜ 待開工／待規劃。
>
> **子階段一律一列一個，不得合併。** 一個 Phase 只要拆出了子階段，本表就照子階段列，不寫成「P2（含 A～E）」那種一列。理由是本表是進度的單一事實來源——合併之後看不出卡在哪一個子階段，而那正是要查這張表的時候想知道的事。尚未規劃子階段的 Phase（目前 P3 之後）維持一列，等規格寫出來再拆。

| Phase | 狀態 | 概要 |
|---|---|---|
| 資料層 | ✅ | 三章 beats 鋪滿、schema 語彙補齊、Godot 專案與 DataLoader／verify_data 站起來（詳見 `git log`） |
| 文件層 | ✅ | 四份關鍵文件建立；文件分工與流向定案（見下方文件索引） |
| P1-A 遊戲狀態與時段狀態機 | ✅ | GameState＋Data autoload、45 天 × 4 時段循環、序列化骨架 |
| P1-B 卡片與手牌 | ✅ | 卡片實體化、手牌／知識分離、主角卡釘死 |
| P1-C 地圖、面板與三態 | ✅ | 面板聚合、三態求值、fixed beat 與 on_enter |
| P1-D 放置與效果結算 | ✅ | 放卡、on_place 結算、行動格消耗、條件求值器、語彙 lint（`test_p1d.gd` 全綠） |
| P1-E choice_group | ✅ | 互斥選擇題、選定即定案、雙入口、選後唯讀 RESOLVED 展示（`test_p1e.gd` 全綠） |
| P1-F 45 天全程走通 | 🟦 | 殘響播出、夜間 stub、結局 coda、迴圈重置、貪心走查（`playthrough_greedy.gd` / `test_p1f.gd` 全綠）；收尾 K 條目已清。**待手動操作驗收** |
| P1-G 面板互動模型 | 🟦 | 規則層已拆成 `build_panel()`／`play_beat()`／`preview_slot()`，刪除 `open_panel()`；UI 改為演出後才建立槽、顯示型別與預覽；走查改走 `play_beat()`；缺 `locations.json.desc` 時退回只顯示地點名。**待手動操作驗收** |
| P1-H 手牌可讀性 | 🟦 | 手牌改 7 欄格線、顯示卡名不顯示 id、卡片與知識各自可點開唯讀詳情。**只解決「看不出手上有什麼」，不碰 UI 型態（待決 23）**。8 條機器契約全綠，待手動操作驗收 |
| P2-A 發狂卡的產生與倒數 | ✅ | `madness_clock` 走真錶（morning 全體 −1、產生當天不倒數、歸零 clamp 於 0）、開收費夜間標記發卡並播提示文字、一夜一個地點、`night_markers_opened` 只收錄收費標記（`test_p2a.gd` 9 組全綠，UI 加 `p1af_29_night_paid` 變體與 `p2a_01_madness_hand_display` 契約）。K-51／K-52／K-53 全數結案 |
| P2-B 縱慾出口與主動縱慾 | ✅ | 六個出口進 `data/beats/indulgence_exits.json`、`indulge()` 原子入口、泡湯特例（標記已用不跳時段、讀取 `soak_cards_cleared`）、`when.day_from` 常駐 beat、出口槽可重複使用（K-54）、Lint 4 & 10 檢查（`test_p2b.gd` 全綠、13 套 headless 全綠）。UI 那一半補了 4 條契約 9 個變體（可見性／放卡／泡湯三態／三個門檻），全套 58 契約 76 變體全綠 |
| P2-C 強制縱慾 | ✅ | 倒數歸零自動執行、`Indulgence.pick_exit()` 挑最重出口、強度級查表、當日不夠順延次日、主動與強制共享曲線（`test_p2c.gd` 10 組全綠、14 套 headless 全綠） |
| P2-D 視野門檻與發瘋 BE | 📐 | `madness_at_least` 在真資料生效、達 `madness_cap` 立即 BE、共用既有 `end_run()` 收尾 |
| P2-E headless 重演三種玩家 | 📐 | `test_p2_sim.gd` 逐項對上 `subdocs/驗證/發狂卡機制模擬.md > 三` 的八個指標與視野窗口。**P2 全部規則的整合測試** |
| P3 夜間層真值化 | ⬜ | 標記收費、對位改名、meta 免費 |
| P4 委託與遭遇 | ⬜ | 人物卡外出／回報、遭遇回合循環 |
| P5 結局、開局與迴圈 | ⬜ | 三結局、開局十分鐘、繼承完整版 |
| i18n 管線 | ⬜ | 抽取工具、可翻譯欄位規約、id 凍結、引擎改走翻譯查詢。**銜接工作不是 Phase**；卡它的是資料 schema 定案（P4 是最後一次長欄位），放 P6 之前讓存檔格式一次定稿 |
| P6 存檔 UI | ⬜ | 槽位、version 遷移、輪中存讀 |
| 內容期 | ⬜ | 文本／演出／UI 正式化／實際翻譯——引擎期玩過之後才排。UI 正式化第一天先拿佔位英文測版面（英文通常比中文長 40–80%） |

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
| `驗證後已知問題.md` | 待修清單（`K-nn`）＋已接受的邊界決定（`B-nn`） | 修 bug 前；動工前掃一遍該 Phase 的條目 |

**流向一句話**：還沒拍板 → 待決事項；規則與為什麼 → 企劃書；具體內容 → subdocs＋data；驗收意圖 → 規格書；怎麼做 → 方針；數值 → tuning。上游往下編譯，永不反向（完整版住 `實作規格書.md > 本檔範圍與邊界`）。

**同一個 Phase 的三份文件**：要做成什麼樣 → `實作規格書.md > P<n>-X`；怎麼做 → `開發設計方針.md > P<n>-X`；怎麼驗 → `測試指南.md > P<n>-X`（`P1-D`、`P2-B`……）。三份文件的子階段標題一字不差，所以一條 `grep -n "P2-B" 實作規格書.md 開發設計方針.md 測試指南.md` 就拿得到全部入口。精準查法（含各文件定位鍵）住 `AGENTS.md > 文件查閱規則`。

## 實作注意事項

- 修改授權／verify-only 規則：`AGENTS.md > 修改授權與驗證規則`（單一事實來源，本檔不重複）。
- 文件角色：方針偏 implementer-owned；測試指南、驗證後已知問題偏 verifier-owned，實作者只列建議。
- 文件裡不寫可調數值，一律指 `data/tuning.json`。
- `.claude/` 是本機 tooling config，不 commit。

## 下一步

- 2026-08-14：**P2 規格寫完，五個子階段可動工**（P2-A 產生與倒數／P2-B 出口與主動縱慾／P2-C 強制縱慾／P2-D 視野與 BE／P2-E 重演三種玩家）。三份文件同標題對齊，另補 `SCHEMA.md` 兩組欄位。**六個縱慾出口在資料裡原本完全不存在**（`data/beats/` 沒有任何 `accepts` 含 `madness` 的槽），落點與條件已設計並寫進 `開發設計方針.md > P2-B`，資料由 P2-B 建 `data/beats/indulgence_exits.json`。**兩個資料缺口刻意不補**：錢卡與「日常卡往心境卡掉」的卡都不存在，屬待決 22 卡片清單；奢侈出口第一輪恆為 LOCKED，不影響保底。**備用區與超載移出 P2**——容量未定（待決 34），且第一輪碰不到 cap，做了壓力測不到。
- 2026-08-15：**UI 模擬驗證工具鏈與全部 47 條契約（59 個案例變體）實作與複驗完成，K-41～K-47 缺陷全數結案**。包含 P1-A～F 與 P1-G 雙階段模型、幾何溢出與遮蔽診斷、真實輸入事件、45 天無注入全流程走查、全狀態等價比對、負向反證測試等。全套 headless（11 套）與 UI 模擬驗收全綠。
- 2026-08-15：**K-48／K-49 結案，UI 模擬從「跑得過」變成「跑得穩」**。原本那個「100% 通過」不可重現——同一份程式碼連跑數輪，每輪紅在不同案例，回到 HEAD 也一樣。真因是 hover 狀態落後輸入事件一拍（`gui_get_hovered_control()` 回報上一個位置的舊值），修法是關掉滑鼠事件累積、每發輸入立即 flush、hover 核驗改成每輪重讀矩形的輪詢（K-48）；另補 launcher 在缺報告時索引 `$null` 的崩潰（K-49）。**連續三輪全套：59/59 variants、47/47 contracts、11/11 負向、0 failed checks。** 同批另修四條驗收品質缺口：等價比對改差異式（不再維護硬編碼排除清單）、evidence 加變體層檢查（不再靠同契約其他變體補 token）、`測試指南.md` 打勾、三份文件的數字漂移收乾淨。
- 2026-08-15：**K-42 的三條尾巴收完，Phase 1 的 UI 驗收才真的是 47／47**。第二次外部審核抓出三條「runner 是綠的、但斷言比條目窄」——`p1af_19` 的免費槽驗成同義反覆、`p1af_22` 拿兩份不同狀態比不了完整最終狀態、`p1af_32` 的 `reset_flag_slots_locked` 驗的是 occupant 槽（連旗標都沒碰）。修法與複驗見 `驗證後已知問題.md > K-42` 的 2026-08-15 追加段。**`p1af_22` 現在兩條入口跑同一份狀態，完整 `serialize()` 逐字相同**；`p1af_32` 改到第二輪第 8 天驗真正的旗標控制槽。複驗：全套兩輪各 59/59 variants、47/47 contracts、11/11 負向、0 failed checks；11 套 headless exit 0。`測試指南.md` 標 🤖 的 44 條全部打勾；標 🤖👤 的 4 條仍留空，**包含 D45 coda——它 runner 那一半才剛補完，人那一半沒做**。
- 2026-08-15：**新增 P1-H 手牌可讀性，三份文件已寫到可動工。** 起因是 P1 收尾後第一次從頭玩——手牌列印的是 `protagonist info_husband_version info_wife_version` 這樣一串 id 接在一起，**玩家看不出兩張「說法卡」差在哪**，而那正是第一章調查線的全部內容（差異早就寫在 `cards.json` 的 `text` 裡，畫面上沒有路徑看得到）。拍板：7 欄 × 2 列格線、顯示卡名、放不下截斷加省略號、不畫空格、知識移到計數右側做成帶數量的按鈕、卡片與知識共用同一個唯讀詳情彈窗。**詳情裡不放放置入口**——放卡一律從槽發起，維持 P1-G 的單一心智模型。`qa_id` 契約同批定案（`hand_card::<實例 id>`／`knowledge_entry`／`dialog_confirm::card_detail`）。**兩件事先做**：K-50（孤兒行程污染驗收）要先修掉，否則 P1-H 紅了無法歸因；`run_ui_sim.ps1` 寫死的契約總數 47 要跟著案例一起改。
- 2026-08-15：**P2-A 發狂卡的產生與倒數實作完成**——`GameState.tick_madness()` 由 `advance_phase()` 跨日 morning 自然倒數且產生當天不倒數、`open_night_marker()` 首次進夜間收費地點依 `madness_cost` 發卡並記入 `night_markers_opened` 集合、`HandBar` 與 `CardDetail` 顯示剩餘天數、序列化與 `end_run` 完整還原與重置。
- 2026-08-16：**P2-A 驗收走了三輪，第一輪抓到五個缺口，兩輪修完。** 第一次驗收（`26cf10b`）發現：**「一夜一個標記」整條沒做**（`available_locations()` 夜間分支沒有任何過濾，而 `p1af_29` 自己就在同一夜進了兩個地點還是綠的）、倒數歸零後繼續往負值走且每天重複回報歸零（會灌爆 P2-C 的 `forced_pending`）、`open_night_marker()` 的回傳文字行是死的、`night_markers_opened` 連免費地點都記、45 天走查完全不開標記。修法：新增 run 層 `night_location_chosen`（`advance_phase()` 每次換時段清空）並在 `PanelBuilder` 過濾、`tick_madness()` 只在 `1 → 0` 那一次進 zeroed 且 clamp、`main.gd` → `location_panel.show_location(loc_id, extra_lines)` 接通提示文字、免費地點在發卡前 return、走查 `execute_night_phase()` 加 `open_markers` 參數（`make_states.gd` 傳 `false` 保持情境快照乾淨）。**UI 覆蓋一度倒退**——修「一夜一個」時把 `p1af_29` 進收費標記那段整個刪掉，`night_paid_locked` 也跟著消失；補法是拆出 `p1af_29_night_paid` 變體，契約仍 53、變體 65 → 66。**收尾三條**：走查開了標記卻零斷言（K-53）、一條順手改壞的（K-52）、多實例顯示未驗（K-51）。**前兩條已於 `259a9f0` 收掉**——`failure_text()` 抽成純函式還原三層優先序（回歸測試 5 條），走查對「開了 14／14 個標記、發了 14 張、重置前手上 14 張」做嚴格相等斷言且期望值從 `locations.json` 現算。K-51 隨 P2-B 的驗收清單一起關。
- 2026-08-16：**P2-B 縱慾出口與主動縱慾實作與驗收完成**——新增 `data/beats/indulgence_exits.json`（定義山泉閣、老街、靜和園三個常駐 beat 與 7 個出口槽）、`DataFacts.beat_matches_time()` 收攏時段與日期區間比對、`Indulgence.level_for()` 實作強度級計算、`GameState.indulge()` 實作原子管線（含泡湯吃 2 格特例與強度等級追加效果）、`try_place()` 轉導發狂卡至 `indulge()`、`PanelBuilder` 正確處理泡湯限制、`DataLoader` 實作 Lint 4（縱慾完整性保底）與 Lint 10（縱慾出口資料完整性）。壞資料 fixture 與專屬驗收測試 `test_p2b.gd` 全綠，13 套 headless 測試無迴歸。（**這一版有四個缺口，見下一條**。）
- 2026-08-19：**P2-C 強制縱慾與失控時段實作與驗收完成**——`Indulgence.pick_exit()` 實作權重與條件挑選演算法（過濾 `auto == false`、不看地點與 when、決定論載入順序決勝）、`GameState._settle_forced_indulgence()` 於行動時段開始時自動消耗行動格執行縱慾、當日兩格吃滿餘卡自然順延次日、主動與強制共享縱慾計數與 `Indulgence.level_for()` 強度級查表追加代價、`main.gd` 正確於上午/下午播出強制縱慾文字、貪心走查 `playthrough_greedy.gd` 動態分類 12 格強制縱慾吃格且 90 格全覆蓋。新建專屬驗收測試 `test_p2c.gd` 10 組驗證全綠，14 套 headless 測試全數通過無迴歸。
- 2026-08-20：**P2-C 驗收 review 抓到 7 條，全部修完（`6e5e51a`）。** ①「泡湯永不入池」的測試是同義反覆——`x_soak` 沒有 `weight` 欄位（Lint 10 對非自動槽本來就不強制），取預設值 0，比任何出口都低，所以**把 `pick_exit()` 的 `auto == false` 過濾整段拿掉，測試照樣綠**；修法是注入一個 `weight: 999` 的非自動槽，過濾器失效就會被挑中（已用突變檢查證實：拿掉過濾器 `test_p2c` exit 1）。②走查的 `forced_indulgence` 分類只看 `action_spent`，任何在時段開頭吃掉行動格的機制（例如泡湯預扣 `_actions_spent_ahead`）都會被貼上這個標籤放行；改成同時要求 `last_forced_lines` 非空。③`_settle_forced_indulgence()` 先 `pop_front()` 才驗出口，`pick_exit()` 失敗時那張卡會離開佇列卻留在手上——**債被吃掉**，與規格「帳不豁免」相反；改成驗完出口與槽才 pop。④新增 `madness_cards_cleared`（在 `lose_card()` 扣發狂卡時 +1）：走查不再用「縱慾次數」換算卡數，泡湯一次清幾張是 tuning 值，調了不會變成假紅。⑤測試 7 補真的執行一次 `_settle_forced_indulgence()`。⑥`test_p2a` 補註解說明歸零驗收改由 `test_p2c` 測試 1 接手。⑦強制縱慾文字整個時段黏著（關掉地點面板回地圖仍在）判定為刻意，寫進 `開發設計方針.md > P2-C` 當契約。
- **走查新基準（`6e5e51a`，90 個行動時段）**：成功放置主角卡 47 格、強制縱慾吃掉 12 格、純比對槽 22 格、條件分支未解鎖 2 格、前置門檻未達 1 格、刻意留空 3 格、純選擇題 3 格。發狂卡帳：發放 14 張＝強制消除 12 張＋重置前手上 2 張。**下一次走查數字變動就跟這一組比。**
- **P2-C 還沒收的三條尾巴**（不擋 P2-D，尚未進 `驗證後已知問題.md`）：③的防吃債修對了但**沒有測試守著**（要壞資料 fixture 才走得到，改回舊寫法 14 套照樣全綠）；②的判定綁在「出口 `on_place` 有文字」，哪天有出口只寫效果不寫文字，走查會判錯；`tests/ui_sim/` **沒有任何 P2-C 契約**，操作層只驗到規則層。
- **下一步進 P2-D 視野門檻與發瘋 BE**。P2 順序：P2-A（✅）→ P2-B（✅）→ P2-C（✅）→ P2-D 視野縮減與 BE → P2-E 重演三種玩家。
- **P1 之後不擋、可順手做的文件小事**：K-24（純措辭，下次動 `實作規格書.md` 時一起改）。**明確排到後面 Phase 的**：K-30／K-33／K-34／K-35 全部等 P3 夜間層真值化（現在改是改在 stub 上），K-08 等 i18n 管線。（K-32 已於 2026-08-15 `2ae62a9` 結案。）
- 2026-08-14：**P1-F 收尾完成**——K-31（`verify_data` 重複檢查刪除）、K-27（lint 3 改以 `(day, phase, location)` 面板分組並更名 `lint_free_slot_rules()`，`d28_morning_xiaowu` 補主角卡槽）、K-29（補齊 K-17／K-18／K-19／K-22 回歸測試）、K-36（走查抽 `run_greedy_walk()` 供 `test_p1f` 共用）、K-28（`FlowText` 接線，殘響／入夜 fixed／結局 stub 三種文字共用容器）、K-37、K-40（`FlowText` 改 `ScrollContainer` ＋ `clip_contents`，夜間文字不再蓋到地點清單與地點面板）。十套 headless 全綠，`main.tscn` 開機無錯誤。
- 2026-08-14：**P1-E 完成**——`GameState.choose()` 原子化唯一選擇入口（驗證未結算、三態 OPEN、帶卡持有與 accepts 檢查、`on_place` 結算、寫入 `choices` 與 `slots_placed`）、`PanelBuilder.build()` 互斥收起與唯讀（RESOLVED）展示、`try_place()` 轉導 `choose()`、`location_panel.gd` 雙入口按鈕支援（直接選擇與帶卡放置）、狀態序列化往返。`test_p1e.gd` 9 項驗證全綠（含真實資料 `d22_pm_sandbags`）。全部既有 headless 測試無迴歸。
- 2026-08-14：**建立 `驗證後已知問題.md`**——P1-A～P1-D 實作 review 的產出，12 條待修（K-01～K-12）＋3 條已接受的邊界決定（B-01～B-03），含優先度與建議批次。最高優先是 K-01：白天面板的 `on_enter` 結算住在 UI 層，headless 走查那條路沒有，屬於七套測試全綠也涵蓋不到的路徑。
- 2026-08-14：`開發設計方針.md > P1-F` 與 `測試指南.md > P1-F` 補上結局收尾的歸屬——`advance_phase()` 自己呼叫 `end_run()`，不把收尾丟給 `run_ended` 的 listener（否則 `main.gd` 與走查腳本各要寫一份順序），並加一條「`run_ended` 一輪恰好發射一次」的驗收。
- 2026-08-13：**P1-D 完成後的 code review 抓到兩個 P1-C 契約缺口，已修**——白天面板沒走 `enter_beat()`（`on_enter` 沒結算、`beats_entered` 沒寫）、beat 級 `requires` LOCKED 沒傳導到槽（view model 與 `try_place` 規則層都補）。細節與回歸測試見 `開發設計方針.md > P1-C` 的 2026-08-13 bugfix 段、`tests/headless/test_p1c_bugfix.gd`。全部既有 headless 測試（`verify_data`／`test_boot`／`test_game_state_p1a`／`test_hand_p1b`／`test_p1c`／`test_p1d`）重跑無迴歸。
- 2026-08-13：**P1-D 完成**——`try_place()` 放置唯一入口（持有→三態→accepts→action_spent 四步檢查）、`EffectApply`（`text`/`gain`/`lose`/`switch`/`switch_progress`/`relation`/`madness`/`flag` 八鍵，固定順序）、`GameState` 新增旗標／開關／關係群、`npc_action_counts` 投入帳、語彙封閉性 lint 1／2（`DataLoader.lint_vocabulary`/`lint_missing_reject_reason`，掛在 `Data._ready()`）。新建 `data/relation_scale.json`（單軸關係序數表，僅「疑似」「恩人」兩個狀態有資料在用，其餘五個是占位排序，見 `開發設計方針.md > P1-D` 說明）。`test_p1d.gd` 全綠，連同既有 `verify_data`／`test_boot`／`test_game_state_p1a`／`test_hand_p1b`／`test_p1c` 一併重跑確認無迴歸。
- **P1-D 過程中發現的測試工具細節**（不影響玩法，記在這裡給後續寫合成 beat 測試的人參考）：headless 測試裡「另建一個 Data 節點＋`Engine.register_singleton`」的慣例，並不會讓 `game_state.gd` 內部的裸 `Data` 全域參照指向那個新節點——`Data` 全域固定綁 `project.godot` 掛的原生 autoload（因為同名節點 `add_child` 時會被引擎自動改名）。至今的測試都只做唯讀斷言所以沒事；P1-D 測試第一次要塞合成 beat 進 `loader.beats_by_id`，就得改寫 `get_root().get_node("Data")` 拿到的那一份，不是自己另外 new 的那個。
- 2026-08-13：verifier 覆審（`P1文件審核.md`）五個契約缺口已全數修正——放置持有檢查、choice 原子化＋RESOLVED、夜間可達性（睡覺解析旅館、附加 beat、`day_at_least` 語彙、lint 7）、卡片 unique／gain 冪等、NPC 投入帳契約；`n_take_something` 與 `n_landmark` 資料已對齊。
- 2026-08-13：codex 全文審查的六條必修＋次要項已全數修正（規則層下沉到 GameState／PanelBuilder、evening 改「非行動格」規則、第 45 天 evening 結局 coda、夜間三步解析、槽一次性 `beat_id+slot_id`、`enter_beat` 統一入口、fixture 化破壞性測試）；第 1、2 夜重複 beat 已清理。
- 2026-08-13：**待決 1／20／37 全部結案**。① 第一章第三次殘響落在第 12 天下午（`d12_pm_awei.echo`），並修掉兩條無 `day` 的複本與 `d8_echo_bathhouse` 的地點綁定——第一章保證播出的殘響從 1 條回到 3 條；全作另有四條缺 `day` 的 echo 一併補齊（現在 7 條齊全）② `k_town_covers` 原本第一輪拿不到（三個 dodger 全擠在第 27 天下午的同一個行動格），兩格改掛 evening 修正 ③ 第 37–38 天兩張證據卡改成真互斥，並補 `d38_clinic` 撐住第 38 天下午的行動格 ④ 待決 20 拍板 18 人、`night_reveal` 全 null。**連帶補了兩條引擎契約**：lint 8（殘響可播出性）與 evening 演出流的結算順序（陣列順序）。
- 未拍板的落差集中在 `實作規格書.md > 附：本檔對資料層的既知落差清單`（縱慾權重、`ending` 鍵、開局選單、委託形狀——各自綁定後續 Phase）。
- 2026-08-13：**待決 20 完成第一版**——`data/npcs.json`（18 人的可及性）＋夜間三分類（`day_counterpart`，10／10／16），四個缺口全部處理，`verify_data` 新增三條檢查。
- 2026-08-13：**發狂卡機制模擬重跑兩次**（現行結論見該檔第一節）。第二次修資料落差（收費標記 10 → 14，`43f29ee` 擴阿宏鏈後一直沒重跑）；第三次修模型自己的錯——前兩次讓玩家一夜開多個標記，而 `實作規格書.md > 九、夜間層` 一直寫著「一晚選一個地點」。**待決 35／36／38／41／42／43／44 全部更新，其中 42、43、44 結案。** 現行數字：收費標記 14、深潛峰值 4（cap 7 餘裕 3）、強制縱慾 11 次其中最重 4 次、視野窗口兩個（第 8–23／26 天、第 42–44 天）。唯一改動的數值是 `forced_normal_until` 5 → 7（待決 43）。
