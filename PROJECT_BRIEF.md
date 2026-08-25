# ReturnFare 專案簡報

本文件供新 session 快速了解專案全貌；需要細節時按下方文件索引深入。**本檔是唯一「隨進度持續更新」的文件**（每個 Phase 收尾更新一次）。

最後更新：2026-08-25

> **當前進度**：第一輪資料層完成（三章 beats 鋪滿、headless 驗證全綠）；四份關鍵文件建立完成；**Phase 1（最小可玩迴圈）P1-A～P1-H 已全部實作並驗證全綠**；**Phase 2 全數完工——P2-A 發狂卡的產生與倒數、P2-B 縱慾出口與主動縱慾、P2-C 強制縱慾與失控時段、P2-D 視野門檻與發瘋 BE、P2-E headless 重演三種玩家均已實作並驗收（全套 16 套 headless exit 0）**；**Phase 3 已完成規格拆分——P3-A～P3-F 三份階段文件與 Schema 契約均寫到可實作**；**P3-A 夜間資料真值化已實作並驗收（17 套 headless exit 0、`test_p3a` 17 項含 11 個獨立負向 fixture）**；**P3-B 夜間狀態與進入規則已實作並驗收（18 套 headless exit 0、`test_p3b` 12 組全綠、7 種變異測試逐條轉紅）**；**P3-C 夜間內容流程已實作並驗收（19 套 headless exit 0、`test_p3c` 12 組 69 條斷言全綠、驗收 13 條打勾 12 條，K-30／K-33／K-69 結案）**；**P3-D 夜間地點清單與詳情 UI 已實作並驗收（20 套 headless exit 0、UI 模擬工具鏈擴為 69 條 UI 契約／92 個案例變體、K-68／K-91／K-94／K-115 結案）**。**P3-E 對位系統已實作並驗收（21 套 headless exit 0、UI sim 97／74／0 failed、10 條驗收全打勾）。P3-F 全流程驗收機器層已完工並驗證全綠（22 套 headless exit 0、UI sim 97／74／0、K-122／K-123 結案），轉 🟦——剩 👤 人工體感 4 項待真人玩過落檔。**；**Phase 4 已完成規格拆分——P4-A～F 三份階段文件與 `data/SCHEMA.md` 的 `delegation`／`encounter` 契約均寫到可實作，兩輪 review 六條缺口結案（`46cb5ef`／`e3916e5`）。下一步依序實作 P4-A 資料與 SCHEMA 真值化。**

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

headless 實測（2026-08-14，`verify_data.gd`）：**54 張卡／48 個地點（白天 20＋夜間 28）／18 個 NPC／257 個 beat**；引用 0 錯誤；地點三分類 10／10／16；lint 1／2／3／5／7／8 全 0 錯誤（lint 3 為 4 筆已豁免警告）；第 1–45 天行動格全覆蓋（第 1 天上午下午、第 32 天下午為刻意留空，名單抽至 `scripts/core/data_facts.gd` 共用）。

**貪心走查 90 個行動時段的分類（`playthrough_greedy.gd`，最新基準 2026-08-20，P2 完工後）**：成功放置主角卡 47／強制縱慾消耗 12／純比對槽 22／刻意留空 3（名單內）／純選擇題 3（豁免名單）／條件未解鎖 HIDDEN 2／前置門檻未達 LOCKED 1 ＝ 90。夜間帳同時對上：14 個收費標記全開、發放 14 張發狂卡 ＝ 消除 12 張 ＋ 重置前留存 2 張。⚠️ **P2 之後強制縱慾會吃行動格，這組數字每次動 P2 規則都要重記**——舊基準是 P1 期的「用掉 56 格、其餘 34 格分類」，已不適用。

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
| P2-D 視野門檻與發瘋 BE | ✅ | 達 `madness_cap` 立即 BE、批次發卡只結束一次、共用既有 `end_run()` 收尾、BE 走獨立顯示分支（`test_p2d.gd` 全綠）。驗收六條尾巴（K-63～K-68）**已結案五條**：K-63／K-64（`673f62e` 當批）、K-66／K-67（`9e342de`）；**K-68 只做到一半**——BE 畫面那條補完了，視野門檻那條驗的是旗標不是畫面，卡在 K-69。K-65 排內容期 |
| P2-E headless 重演三種玩家 | ✅ | `test_p2_sim.gd` 重演 A 深潛／B 典型／C 謹慎 45 天，八個指標、視野窗口與 A 的 26 項時間軸逐項對上 `subdocs/驗證/發狂卡機制模擬.md > 三`，並驗同存檔重跑兩次逐字相同。走真規則層入口（`open_night_marker()`／`indulge()`／`advance_phase()`）。**P2 全部規則的整合測試**，16 套 headless exit 0、UI 全套 82／63 無迴歸 |
| P3-A 夜間資料真值化 | ✅ | 10 張對位 knowledge／12 筆 `night_reveal`／16 夜間限定 row 全部從真資料衍生；28 名稱審查落檔對照表；6 個阿宏門檻理由分階段區分；`n_corridor_end` 改 teaser-only；lint 11～12 與 6 個獨立壞資料 fixture。17 套 headless exit 0、UI 82 變體／63 契約／0 failed。負向 fixture 11 個、`test_p3a` 17 項。**baseline 由 verifier 以 `870db64` 資料獨立重跑對過三次（逐字相同），所以「沒改玩家流程」這個結論成立**。K-103～K-111 全數結案；剩 K-112（UI 模擬會重生 baseline，低）與 B-04（原 K-107，不修） |
| P3-B 夜間狀態與進入規則 | ✅ | `enter_night_location()` 取代 `open_night_marker()`（八碼封閉拒絕矩陣、順序固定、任一拒絕 `serialize()` 逐字零變化）；`night_locations_seen`／`night_once_beats_seen` 進 meta、`end_run()` 不清，終身首次才收 marker cost；seen 寫在 cap 檢查之前，撞 BE 仍記 seen；`_record_forced_night_visit()` 私有、無 `forced` 參數；`night_seen` 進 `ConditionEval` 並帶引用檢查；正式資料 `opened_n_*` 全退場（阿宏前三級改讀 `night_seen`，9 個純寫入旗標刪除，聚會旗標改名 run flag `saw_n_gathering_intro` 且 ch2／ch3 兩個變體都寫），lint 13 掃正式資料 0 筆。`test_p3b.gd` 12 組全綠，18 套 headless exit 0。**review 抓到 8 條「修正做了、測試沒跟上」，`7c5184b` 全數補齊並逐條變異測試**。剩 K-115（拒絕文案的 UI 消費端由 P3-D 承接，低） |
| P3-C 夜間內容流程 | ✅ | `night_beat_candidates()` 結構候選＋`resolved_night_content()` 狀態求值兩層分離，`PanelBuilder.build()`／`sleep_night()`／`_is_beat_time_valid()` 三處共用同一份結果；`DataFacts.beat_matches_time()` 縮成「有 `when` 才判」；D1／D2／D15 加 `meta_once`、D3 `n3_map_opens` 改掛 `sanquan` 的無槽環境引導、D24 每輪重播；`resolve_night_advance()` 統一夜間推進、睡覺停拍與三態按鈕。**K-30／K-33／K-69 三條夜間老帳結案。** 19 套 headless exit 0、`test_p3c` 12 組 69 條斷言全綠、負向 fixture 7 個、夜間相關 UI 契約 6 變體 failed 0。**驗收 13 條打勾 12 條**（剩 K-68 的「清回 2 張」那一腳，P3-D 補）。**review 抓到 8 條，`01ccff4` 修完六條並逐條變異測試**；剩 K-122（模擬文件基準）與 K-123（按鈕三態缺 ui_sim 契約），兩條都排 P3-F |
| P3-D 夜間地點清單與詳情 UI | ✅ | `location_summary()` 純 view-model、`show_night_details()` 詳情面板、`main.gd` 拆「詳情→進入」兩步、`map_list` 讀 summary 並移除 `_SUFFIX_EMPTY`；四種狀態文字＋teaser 鎖定＋隱藏價碼＋LOCKED 理由＋風險 warning。K-91 斷言反轉、K-68 第三腳、K-115 拒絕文案接線、K-94 方針表回 ✅ 均結案。20 套 headless exit 0、UI sim 92 變體／69 契約（P3-D 補 6 契約 10 變體）／0 failed；verifier 變異測試逐條轉紅。不做座標地圖 |
| P3-E 對位系統 | ✅ | `PanelBuilder.alignment_offer()`＋`GameState.confirm_night_alignment()` 六碼封閉拒絕矩陣（`not_day_phase`／`unknown_location`／`not_day_layer`／`no_seen_row`／`data_conflict`／`already_known`）、白天正確地點免費確認、共用 knowledge、多對一命名衍生、matched 狀態純衍生（serialize 無 aligned／matched）、offer 與 confirm 判準逐項對齊。`location_panel` 加 `NightAlignButton`＋`ConfirmationDialog`。21 套 headless exit 0、`test_p3e` 6 組全綠、UI sim 97 變體／74 契約（P3-E 補 5 契約）／0 failed。**verifier 驗收 10 條全打勾**；review 三條次要觀察（offer/confirm 順序、成功路徑無變異斷言、單 row 缺 reveal）於 `37f4b58` 修畢並各帶測試，變異測試逐條轉紅 |
| P3-F 全流程驗收 | 🟦 | 28-row matrix、第一輪 13／14 具名策略＋第二輪規則重演、P1／P2 回歸、UI 契約均已實作並驗證全綠（`test_p3f` 5 組、22 套 headless exit 0、UI sim 97／74／0）。K-122／K-123 結案。**機器層七條打勾，剩 👤 人工體感 4 項未落檔——待真人玩過逐項記錄** |
| P4-A 資料與 SCHEMA 真值化 | 📐 | `delegation`／`encounter` schema、翻譯欄位、lint 15～16；D8／D17～19／D45 改正式案例、退掉 D17 自動發三張人物卡；不接玩家操作 |
| P4-B 委託規則 | 📐 | run 層三筆狀態、`delegate()` 原子入口、immediate／隔日上午結算、序列化與換日重置、11 碼拒絕矩陣；不吃行動格 |
| P4-C 委託 UI 與首個案例 | 📐 | 委託候選／預覽／確認、第一張人物卡教學（不綁日期）、接通 D17～19 處方案例；不建獨立委託畫面 |
| P4-D 遭遇規則 | 📐 | 遭遇狀態機、佔格、回應／錯答／丟棄／逃離、13 碼封閉拒絕矩陣與固定檢查順序、無合法解直接失敗；不消耗行動、不開縱慾備用區 |
| P4-E 遭遇 UI 與 D8／D45 | 📐 | 共用卡片互動遭遇畫面、D8 首次到訪共用收費（已 seen 不重收）、D45 單回合不可逃不可丟；UI 不繞過規則層 |
| P4-F 全流程與跨輪驗收 | 📐 | 委託／遭遇 matrix 從資料衍生、第一輪四狀態走 D17～19、第二輪保留 meta 清 run state、greedy 跨兩場遭遇、UI 契約＋人工四項體感 |
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

- 2026-08-25：**P4 委託與遭遇規格完成，拆成六個可獨立驗收子階段，並通過兩輪 review。** `實作規格書.md`、`開發設計方針.md`、`測試指南.md` 使用完全對齊的 P4-A～P4-F 標題；`data/SCHEMA.md` 補 `delegation`（`result_timing`／`preview`／`tendency`／`report`）與 `encounter`（`repeat_each_run`／`charge_first_visit`／`per_round_slot_cost`／`escape_cost`／`allow_discard`／round graph）兩組契約。核心拍板：委託是「放人物卡不放主角卡」的 slot、一天一人一次、immediate／next_morning 兩種回報、不吃行動格、不增 `npc_action_counts`；遭遇是每回合多佔一格手牌的面板、13 碼封閉拒絕矩陣＋四入口固定檢查順序、三出口、無合法解直接失敗；run 層只加三筆（`delegates_used_today`／`pending_delegation_reports`／`active_encounter`）、`end_run()` 全清；D8 是 `repeat_each_run`＋`charge_first_visit` 的 dated night 遭遇（地點 `n_manydoors`、首次到訪共用收費且已 seen 不重收）、D45 單回合不可逃不可丟、D17 退掉自動發三張人物卡（改具名事件取得）；P4 不做第二套卡組、戰鬥數值、成功率或通用永久失去人物。**第一輪 review 抓到六條缺口——遭遇拒絕碼未釘機器字串、進場佔格是否雙計語意、D45 discard 引用不存在欄位、`charge_first_visit` 重收語意、定日／night-layer 術語易混、fallback 無可丟棄卡的行為；`e3916e5` 六條全修並同批補齊測試指南驗收條目（含拒絕順序測試與 `discard_disabled`／無合法解 failure 兩條新驗收）。** 複審確認四份文件互相對齊、未引入新矛盾；剩一條極低觀察（`when.phase==night` 與 location `layer==night` 兩套判準未由 lint 強制一致，現行資料不變式下對 D8 一致，未落 K）。**下一步依序實作 P4-A，先定資料與 lint，不先接玩家操作。**
- 2026-08-25：**P3-F 機器層完工並通過 verifier 驗證，測試指南七條機器條目全打勾，P3-F 轉 🟦（剩 👤 人工體感）**（`72b84ca` headless 套件＋K-123 契約、`98949f1` 模擬文件第四次重跑）。verifier 自跑證據：**22 套 headless 逐套 exit 0**（`test_p3f` 5 組：28-row 動態 matrix／路徑效率 13／最大壓力 14／第二輪五路徑抽樣／跨輪決定論）、**UI sim 97 變體／74 catalog／74 executed／failed 0**、11 條負向反證如期失敗。**K-122 結案**：`發狂卡機制模擬.md` 改第四次重跑，補路徑效率（13 Cost）與最大壓力（14 Cost）兩條具名策略，A 視野 18／B 21／窗口 8–14＋16–23＋42–44 與 `test_p2_sim.gd` 現行斷言逐項對上。**K-123 結案**：夜間按鈕三態塞進 `p3d_05_sleep`（「直接睡」→「進入隔天」）走真實 input event。code review：`open_night_marker` 全退場、builder／gs／main 無 night `when` 掃描，K-34／35 由 `test_p3f` 測試 1 明示斷言，K-68→`p2d_01_vision_three`、K-70→`p2d_02_be_screen` 兩契約綠，K-72 未被擴張（commit 僅動三檔）。**手牌溢位**落檔 B-05（warning-only 軟上限＝刻意，超載處置＝待決 34，觸發點 P4 後實際遊玩，不修）。**剩 👤 人工體感 4 項**（28 項掃讀不跳位／三種按鈕停拍／灰地點理由／多對一命名）未落檔，需真人玩第一輪＋第二輪抽查後逐項寫入，P3-F 才轉 ✅。
- 2026-08-23：**P3-E 對位系統完工並通過 verifier 驗收，10 條驗收全打勾**（`cfd6796` 實作、`37f4b58` 修 review 三條次要觀察）。`cfd6796` 做 `PanelBuilder.alignment_offer()`（純衍生 offer）＋`GameState.confirm_night_alignment()`（六碼封閉拒絕矩陣、成功呼叫 `gain_card()` 不耗行動格）、`location_panel` 加 `NightAlignButton`＋`ConfirmationDialog`、UI sim 補 `p3e_01`～`05` 5 契約（catalog 69→74、變體 92→97）。**verifier 自跑證據**：21 套 headless exit 0（含 `test_p3e` 6 組）、UI sim **97 變體／74 契約／0 failed**、11 條負向反證如期失敗、`p3e_01`～`05` 全 OK。**第一輪 review 抓到三條次要觀察**（非假綠，都有測試會咬）：①`alignment_offer` 與 `confirm_night_alignment` 檢查順序分歧（offer 先查地點/layer、confirm 先查 phase）；②headless 成功路徑沒斷言 `action_spent` 不變/未寫 slot；③`data_conflict` 也涵蓋單 row 缺 `night_reveal` 但無測試釘。**`37f4b58` 三條全修**：offer 改先查 phase 與 confirm 同序、test 6 加 3 個交集案例驗 phase 優先；一對一/多對一 confirm 後補「action_spent=false 且 slots/choices 空」斷言；test 4.2 加單 row 缺卡 fixture。**verifier 獨立變異測試**：釘掉 `already_known` → `test_p3e` 轉 2 紅（reject 5.6 ＋ offer/confirm parity）；對調 confirm 的 phase/unknown 順序 → 交集案例轉 1 紅，均還原乾淨。**如實補充**：offer 只回 `available` 布林、不回 `reason_code`，其內部檢查順序對測試不可觀測——交集案例守的是 confirm 的優先序（可觀測那半），offer 重排屬防禦性一致化。**驗證過程插曲**：verifier 首輪變異測試誤用 `git checkout` 還原，把當時未提交的 `confirm_night_alignment` 一併還原掉，污染了兩次 UI sim 的 p3e_04/05 結果；逐字還原（52/0 與原 diffstat 吻合）後重跑全綠，已改用 Edit 正反做變異、不再對未提交碼用 checkout。
- 2026-08-22：**P3-D 夜間地點清單與詳情 UI 完工並通過 verifier 驗收，13 條全數打勾**（`0047aaa` 實作、`70f4fc5` 補齊 9 條 🤖 UI 契約）。`0047aaa` 做 view-model（`PanelBuilder.location_summary()`）、詳情面板（`location_panel.show_night_details()`）、`main.gd` 兩步拆分、`map_list` 讀 summary 並移除 `_SUFFIX_EMPTY`，同批結 K-91（斷言反轉）、K-68 第三腳、K-115（`_NIGHT_REJECT_TEXTS` 接線）。**第一輪 verifier review 抓到 altitude 缺口**：13 條裡 9 條標 🤖 UI 卻只有 headless view-model（`test_p3d`）證據，方針明列的 `tests/ui_sim/ P3-D cases` 沒補、catalog 仍 63——非假綠（`test_p3d` 經變異證實會咬），是缺真實輸入層契約。`70f4fc5` 補齊 6 契約／10 變體（catalog 63→69、變體 82→92），fixtures 走規則層入口（`enter_night_location()`＋`gain_card()`）並補後置條件。**verifier 自跑證據**：20 套 headless exit 0（含 `test_p3d` 7 組）、UI sim **92 變體／69 契約／0 failed**、11 條負向反證仍如期失敗。**verifier 獨立變異測試**：釘死 `location_summary` 的 `is_aligned=false` → `p3d_02` 兩變體轉 5 紅；拿掉 `already_chosen`/`already_slept` 阻斷 → `test_p3d` 轉 2 紅，均還原乾淨。**K-68／K-91／K-94／K-115 結案**（K-94 方針 UI 表回 ✅）。剩 K-122（模擬文件基準）與 K-123（按鈕三態缺專屬 ui_sim 契約），兩條排 P3-F，不擋 P3-E。
- 2026-08-22：**P3-C 夜間內容流程完工並通過 verifier 驗收，13 條驗收打勾 12 條**（`bdfa5fd` 實作、`01ccff4` 修 review 尾巴）。verifier 自跑證據：**19 套 headless 全部 exit 0**、`test_p3c` **12 組 69 條斷言全綠**、lint 14 掃正式資料 0 錯誤、夜間相關 UI 契約（`p2d_01` 兩變體、`p1af_29` 三變體、`p1af_30`）**6 變體 failed 0**（其餘 57 條契約與本次改動無交集，未跑）。**K-30／K-33／K-69 三條從 P1-F 掛到現在的夜間老帳一次結清**：K-30 靠兩層唯一入口（`night_beat_candidates()` 結構層、`resolved_night_content()` 狀態層），grep 確認 `panel_builder.gd`／`game_state.gd`／`main.gd` 已無 night `when` 掃描；K-33 靠 `resolve_night_advance()` 在 chosen 非空時直接推進，並以同夜確實有 sleep 內容的 D24 狀態反證；K-69 靠 `_on_advance_pressed()` 把 lines 寫進 `FlowText` 並停一拍。**第一輪 review 抓到 8 條，落檔 K-116～K-123，其中兩條又是 P3-A／P3-B 的同一個形狀——「修正做了、測試沒跟上」，把實作整段刪掉測試照樣全綠**：K-116（`_refresh_advance_hint()` 夜間三態按鈕文字整段零覆蓋）、K-117（`_record_forced_night_visit()` 的 K-90 保險零覆蓋，**而且擋不住它要擋的事**——helper `return` 之後 `play_night_fixed()` 照樣播、meta-once 更在之前就寫進去）。另有 K-118（lint 14 的 `when.phase` 寫成陣列就整條繞過）、K-119（「0 筆 `<location>_locked`」是空斷言）、K-120（定日候選會收 `day_from` 區間 beat）、K-121（fixed 到訪 helper 不看 `night_sleep_pending`）。**`01ccff4` 六條全修**：helper 改回傳 `bool` 且呼叫端 `continue`、meta-once 寫入點移到到訪成功之後、lint 認陣列 phase、候選層自檢 exact day、第 5 組改對 `PanelBuilder.build()` 輸出斷言且 beats 為空即 fail；`test_p3c` 由 10 組增為 12 組，負向 fixture 由 4 個增為 7 個。**verifier 對修正逐條重跑變異測試——刪 `_refresh_advance_hint()` 夜間分支／刪 chosen 覆寫保險／刪 lint 14 陣列分支，三種全部如預期轉紅**（同樣三刀在 `bdfa5fd` 上是全綠）。**K-68 從「卡住」變成三腳成立兩腳**——K-69 解封後 `p2d_01` 兩變體改讀畫面文字，缺「清回 2 張又消失」的狀態轉換，K-94（方針 UI 表改回 ✅）因此仍未到期。剩 K-122（`發狂卡機制模擬.md` 仍是舊基準，與改後的 `test_p2_sim` 分岔）與 K-123（按鈕三態只有場景級證據、catalog 仍 63），兩條都排 P3-F，不擋 P3-D。
- 2026-08-21：**P3 文件第三輪複審，再抓 5 條並同批回寫，落檔 K-98～K-102。** 只改文件（`實作規格書.md`、`開發設計方針.md`、`測試指南.md`、`AGENTS.md`、`CODEX_HANDOFF.md`、`驗證後已知問題.md`），**沒有動任何程式或資料**。這輪抓的不是規格寫錯，而是**「照這條寫出來的測試，寫錯了不會紅」**：**K-98**（P3-B 定了八個 `reason_code`，測試指南只有兩個有條目；拒絕順序寫反時只驗布林值的測試照樣全綠）、**K-99**（P3-E 的 `confirm_night_alignment()` 根本沒定 `reason_code` 集合，且現有條目全走 UI——「按鈕沒出現」驗的是 offer，不是這個可被直呼的入口）、**K-100**（P3-A 的 baseline checkpoint 沒規定產生方式、名稱與前置狀態；更關鍵的是沒寫明「前」那一半必須在改資料之前產生，否則該條驗收恆真）。另兩條是舊帳：**K-101**（P3-F 把 verifier-owned 的 `測試指南.md` 列進 implementer 動的檔，順帶定案 `PROJECT_BRIEF.md` 也歸 verifier）、**K-102**（K-93 只清掉規格書一處，測試指南與方針的 K-37 還在）。**K-98／K-99 的測試本身要等 P3-B／P3-E 實作時才寫；K-100 的 baseline 檔必須在 P3-A 動資料之前產出。**
- 2026-08-21：**K-82～K-97 全數回寫完成，P3 開工閘清空。** 十六條全部只改文件（`實作規格書.md`、`開發設計方針.md`、`測試指南.md`、`AGENTS.md`、`CODEX_HANDOFF.md`），**沒有動任何程式或資料**。四條阻擋項已解：K-84（lint 編號總表對調）、K-82（進場規則加 `night_sleep_pending`）、K-83（通用結果驗收移到 P3-C）、K-86（三個簽名改 `{reason_code, reason_text}` 雙欄，並升格為 P3 全域結構決策）。**三條只做得完文件那一半**：K-91（`p1af_29` 兩條斷言在 P3-D 實作時才反轉）、K-95（`知識卡.md` 索引在 P3-A 有卡之後才重建）、K-94（方針 UI 表要等 P3-C 補完畫面證據才改回 ✅）。
- 2026-08-21：**P3 文件第二輪複審，再抓 16 條，落檔 K-82～K-97。** 前一輪的九條回寫本身沒問題，這一輪抓的是**回寫沒覆蓋到的地方**。**四條擋開工，全部只動文件**：**K-84**（K-78 只修一半——`實作規格書.md` 的 lint 編號總表仍是「13＝一次性 beat／14＝舊旗標」，與其他所有段落相反，錯了會傳到函式名）、**K-82**（`night_sleep_pending` 那一拍沒有任何檢查擋進場，玩家可以「先睡看完外溢文字、再探索一個地點」，一夜拿兩份夜間內容）、**K-83**（P3-B 驗收要「顯示通用結果」，方針卻把該機制排在 P3-C，同一件事指派給兩個階段）、**K-86**（`enter_night_location()`／`confirm_night_alignment()` 只回單一 `reason`，重演已結案的 K-03）。其餘 12 條綁各子階段開工當批處理，完整時機表見 `驗證後已知問題.md > 一、待修清單` 的分組行。
- 2026-08-20：**K-73～K-81 已討論定案並回寫，P3 開工前文件閘已通過。** K-73 掛回待決 25／26：第二輪主要壓力由新增／深化收費 row 提供、事件發卡只補充，P3 不提前做內容。K-74 不再誤寫成單一 14 → 13：D14 走 `n_ahong_3`、D15 fixed 免費取得 `n_plaza` 是路徑效率 13；D14 主動走 `n_plaza` 是最大壓力 14，P3-F 以明示 id 的兩條策略重跑。K-75 保留完整夜間清單、chosen 後只停用全部入口。K-76／77 拆成 DataLoader 候選層與 GameState 求值層，condition 可 fallback、requires 不 fallback，DataFacts 只管 dated。K-78～81 的 lint 編號、teaser 一致性、聚會 run flag 與 D24 測試措辭一併收正。九條均為文件修正；K-74 完整時間軸仍待 P3-F，K-73 第二輪內容仍待決。
- 2026-08-20：**P3 三份文件的規格審核完成，九條缺口落檔為 K-73～K-81。** 規格與資料對得上（28 row／12 對位／10 卡／16 夜間限定／6 門檻／14 收費 row 全部實測相符）。初查抓出第二輪供給與 D15 fixed 的數值後果；其中 K-74 第一版把結果寫成單一 14 → 13，後續依真實資料順序與玩家策略補查，修正為 13／14 雙基準。處置結果見上一則與 `驗證後已知問題.md`。
- 2026-08-20：**P3 夜間層真值化規格完成，拆成六個可獨立驗收子階段。** `實作規格書.md`、`開發設計方針.md`、`測試指南.md` 使用完全對齊的 P3-A～P3-F 標題；`data/SCHEMA.md` 補 `teaser_only`、`meta_once`、`night_seen` 與衍生對位契約。核心拍板：marker cost 只收終身第一次主動到訪；seen 與 night-once 住 meta；對位免費、只在正確白天地點出現、matched 不另存；D1／D2／D15 fixed 是一次性強制到訪，D24 每輪、D3 只作一次性環境引導；P3 維持文字清單，不做座標地圖。**下一步依序實作 P3-A，不先跳做流程或 UI。**
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
- **P2-C 收尾修正**：**K-59**（防吃債測試）於 `test_p2c.gd` 補第 11 組測試，完成出口池無效與 slot 遺失之債務保留斷言（含突變驗證）；**K-60**（走查解耦文字）於 `playthrough_greedy.gd` 改比對推進前後 `indulgence_count`。**兩條均已結案全綠**。**K-61**（`tests/ui_sim/` P2-C 契約）留待 K-48 收掉後處理。
- 2026-08-20：**K-48 結案，UI 模擬終於可重現。** 真因不是 hover 落後、不是殘留行程、也不是排版未定案——**案例是開真視窗跑的，桌面上還有一支實體滑鼠**。`gui_get_hovered_control()` 記的是「最後一個滑鼠移動事件打到誰」，而 `click()` 送出移動之後等了 2 幀才讀；這段空檔裡使用者手動一下滑鼠，作業系統補進來的真實事件就把 hover 蓋掉。最小重現一字不差地複製了失敗訊息（`預期 AdvanceBeatButton、實際 Main`）。**同源的第二個缺口一併修掉**：按下與放開之間也等了 2 幀，中途的外來移動會讓按鈕收到 `MOUSE_EXIT`、放開時不發 `pressed`，症狀是「click 回報成功但畫面沒反應」。修法是兩段之間都不再等幀。**防再犯**：新增 `qa_hover_regression.gd`，用「每幀補送一發打到別處的移動事件」扮演實體滑鼠，不靠運氣也不用真的動游標；接進 launcher 第 2 步，不過就整套中止，且已驗證還原修法後守衛會紅。複驗：三輪全套各 76 variants／58 contracts／0 failed checks，14 套 headless exit 0。**教訓寫進 K-48**：干擾源在測試程序之外時，「連跑三輪全綠」沒有證明力——那只證明那三輪沒人碰滑鼠。
- 2026-08-20：**K-61 結案，P2-C 的操作層補齊。** 新增 3 條 UI 契約（契約 58 → 61、變體 76 → 79）：`p2c_01_forced_text`（效果文字播在地圖上、第一次是輕的且明講下次更重、**關掉地點面板回地圖仍留存**）、`p2c_02_forced_action_spent`（行動格被吃掉，**兩個地點**都沒有主角卡放入入口——擋的是行動格不是單一面板）、`p2c_03_forced_two_same_day`（同日兩張歸零，上午下午各吃一格）。狀態由 `make_states.gd` 產生兩個：第 10 夜、發狂卡倒數壓到 1，UI 推進一次就跨日歸零並自動結算。**突變檢查確認不是同義反覆**：拿掉 `_play_forced_lines()` → `p2c_01` 紅三條；拿掉 `consume_action(1)` → `p2c_02`／`p2c_03` 各紅三條。K-58 的五處契約數已同步改完。
- **K-48 結案的連帶影響**：**K-61（`tests/ui_sim/` 沒有 P2-C 契約）解除封鎖並已補完**。另新增 **K-62 並已修**——`run_ui_sim.ps1` 用 `Set-Location` 決定測哪個專案，但 Godot 是用 `ProcessStartInfo` 起的、`--path .` 吃行程的工作目錄，所以從別的目錄呼叫會**安靜地去測別的專案**。診斷 K-48 時真的踩到了。修法是補 `$psi.WorkingDirectory = $projectRoot`。**待修清單現在只剩排到後面 Phase 的那幾條。**
- 2026-08-20：**P2-D 視野門檻與發瘋 BE 實作與驗收完成**——`madness_at_least` 視野門檻動態顯隱（2 張隱藏、3 張出現、扣回 2 張再隱藏）、`GameState._check_madness_cap()` 於 `gain_card()` 與 `open_night_marker()` 批次發卡後檢查 `madness_cap` 並即刻轉導 `end_run("ending_madness_be")`、`main.gd` 收到 `ending_madness_be` 時分支呈現 `[發瘋 BE]` 且不播後日談骨架、跨輪重置保留知識卡且清空 run 層。新建專屬驗收測試 `test_p2d.gd` 6 組驗證全綠。
- 2026-08-20：**P2-E headless 重演三種玩家實作與全套驗收完成，Phase 2 全數完工！**
  - 新建 `tests/headless/test_p2_sim.gd`，完整重演 A 深潛、B 典型、C 謹慎三種玩家 45 天行為與決定論跨輪一致性，逐項對齊 `subdocs/驗證/發狂卡機制模擬.md` 基準（A 峰值 4 第 11 天、B 峰值 3 第 8 天、C 峰值 1 第 6 天；均未觸發 BE；主動縱慾 C 14 次 A/B 0 次；A 視野 19 天、B 22 天、C 0 天；均開滿 14 收費標記）；補正 D45 上午第 38 夜卡片自然倒數到期結算之第 12 次強制縱慾（14 供給 = 12 強制消除 + 2 重置前留存，最重級 5 次）。
  - 同批解決 **K-66**（`_check_madness_cap()` 嚴格依手牌發狂卡計算）、**K-67**（`test_p2d.gd` 走真規則層發卡觸發 BE）；**K-68 只做到一半**（`tests/ui_sim/` 補了 `p2d_01_vision_visibility`、`p2d_02_be_screen` 兩條契約，但視野門檻那條驗的是旗標不是畫面，見下一則）。
  - **全套 16 套 headless 測試全綠**（`test_p2_sim.gd` 是新增的第 16 套；commit message 與本檔原本都誤寫 15，已更正）、**全套 63 條 UI 模擬契約（82 個變體 + 11 個負向反證）全綠**、0 failed checks。
- 2026-08-20：**P2-E 與 K-66／K-67／K-68 的驗證完成，四條新尾巴落檔為 K-69～K-72。** 16 套 headless 全部 exit 0、UI 全套 82 變體／63 契約／0 failed checks、`playthrough_greedy` 的 90 格新分類已重記（見上方資料層現況）。逐條判定：**K-66、K-67 真的修好了**（cap 改數手牌、BE 測試改讓 `GameState` 自己發 `run_ended`，接線斷掉會紅）；A 深潛 26 項時間軸與模擬文件逐行比對相符；模擬文件把強制縱慾 11 → 12 的補正經獨立驗算為正確（第 38 夜那張卡第 39–45 天各扣 1，第 45 天上午歸零；14 ＝ 12 ＋ 2）。**四條新尾巴**：**K-69**（睡覺解析的 beat 文字被 `main.gd` 丟掉，颱風三夜的外溢文字玩家一個字都看不到，排 P3 與 K-33 同批）、**K-68 未完的那一半**（視野門檻契約用 `serialize()` 的旗標判定，不是畫面節點；**卡在 K-69**——那三格在畫面上本來就沒有節點可查）、**K-70**（`be_map_hidden` 這個 token 只查地點面板沒查地圖，低）、**K-72**（`test_p2_sim.gd` 兩處自行重算，低）。另 **K-71 已修**：契約數與 headless 套數又只改到一部分（K-58 同族第二次），五處已補齊，名單擴充為含走查基準。
- 2026-08-21：**P3-A 夜間資料真值化實作完成並通過 verifier 驗收**（`ce7c41a` 實作、`41d2d8e` 修 review 尾巴）。verifier 自跑證據：17 套 headless 全部 exit 0、`verify_data` 的 lint 11／12 各 0 錯誤、`test_p3a` 12 項全綠、UI 全套 82 變體／63 契約／0 failed。**K-100 的結論由 verifier 獨立證明**——把 worktree 開在 `870db64`（P3-A 之前的資料）＋現行 generator 重跑，產出的 baseline 與現檔逐字相同，`ce7c41a` 與 `41d2d8e` 各驗一次。**三輪 review 共落檔 K-103～K-112**：第一輪 7 條當日修掉 5 條；複驗發現剩下三條（K-105／K-108／K-110）**共同形狀是「修正做了、測試沒跟上」**——把那次修改整段刪掉測試不會紅；第二批補齊後全過，負向 fixture 由 6 個增為 11 個。最後對三條做**變異測試**（把修正整段拿掉看測試會不會紅），又抓出 K-113（fixture 11 用 `"chapter": "one"`，實際是被範圍檢查代勞，型別檢查沒被證明過）與 K-114（`p2d_near_cap` 把 `madness_cap` 釘死在 7，調 tuning 就讓 UI 模擬整組掛掉），兩條當批修掉並各自以變異測試確認。**剩兩條不擋 P3-B**：K-112（baseline 產生掛在 `generate_all_states()` 裡，跑一次 UI 模擬就被當前資料重寫，下次動 `make_states.gd` 時順手拆成明示旗標）與 B-04（原 K-107，baseline 的「先產再改」在 K-112 修好前守不住，改記為不修的紀律條目）。
- 2026-08-22：**P3-B 夜間狀態與進入規則實作完成並通過 verifier 驗收**（`2ef58f3` 實作、`7c5184b` 修 review 尾巴）。verifier 自跑證據：**18 套 headless 全部 exit 0**、`test_p3b` **12 組全綠**、lint 13 掃正式資料 0 筆、相關三個 UI 契約 failed 0（其餘 60 個契約與本次改動無交集，未跑）。**第一輪 review 抓到 8 條，共同形狀與 P3-A 的 K-105／K-108／K-110 完全一樣——「修正做了、測試沒跟上」，把那段實作整段刪掉測試照樣全綠**：lint 13 的槽級負向 fixture 缺席（K-87 白修）、跨輪重進不收費沒測（終身首次收費的主規則）、`night_seen` 引用檢查沒有負向 fixture、`main.gd` 真入口的 BE 路徑沒驗、`NIGHT_REJECT_MESSAGES` 是宣告了沒人讀的死常數、`if day != 1 or phase == "night"` 是「本輪沒結束」的隱式代理、舊 API 名稱殘留在註解與 timeline 字串、阿宏 gate 沒有結構性斷言。`7c5184b` 全數補齊（`test_p3b` 由 9 組增為 12 組）。**verifier 對修正逐條做變異測試**——不掃 `slots[]`／收費集合退回 run 層／刪 `night_seen` 引用檢查／拿掉 `_is_showing_ending` guard／`will_end_run` 恆真／`will_end_run` 改在寫 seen 之後算／阿宏 gate 改回 run flag，**七種全部如預期轉紅**，且第 2 種只讓跨輪那條紅、meta 保留那條仍綠（證明新斷言不是重複）。剩 K-115 不擋 P3-C。
- **下一步實作 P3-C 夜間內容流程。** 重點是唯一 resolver（`night_beat_candidates()` ＋ `resolved_night_content()`）、fixed／D3／D24 與睡覺停拍三種按鈕，並收 K-30／K-33／K-69；lint 14（`lint_night_once`）同批啟用。P3-B 留下的 `night_once_beats_seen` 已進 meta 序列化但**尚無寫入端**，由 P3-C 的 meta-once fixed 接上。
- **P1 之後不擋、可順手做的文件小事**：K-24（純措辭，下次動 `實作規格書.md` 時一起改）。**明確排到後面 Phase 的**：K-30／K-33／K-34／K-35／K-69 全部等 P3 夜間層真值化（現在改是改在 stub 上），K-08 等 i18n 管線。（K-32 已於 2026-08-15 `2ae62a9` 結案。）
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
