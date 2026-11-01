# ReturnFare 專案簡報

本文件供新 session 快速了解專案全貌；需要細節時按下方文件索引深入。**本檔是唯一「隨進度持續更新」的文件**（每個階段收尾更新一次）。

最後更新：2026-10-31

> **當前進度（以網頁版為主，Godot 版已凍結）**：專案已拍板轉向**純網頁版（TypeScript + Vite + React）**。`docs/web/` 下的 [網頁版移植計畫.md](docs/web/網頁版移植計畫.md)、[共用契約.md](docs/web/共用契約.md) 與 **W1～W7 實作契約**已全數立定；**W1 骨架與軌跡基線（W1-A 網頁骨架與資料同步、W1-B Godot 黃金軌跡產生器、W1-C 軌跡比對器）已全部完成並通過驗收**，詳見 [W1 紀錄](docs/records/W1實作紀錄.md)，**W2 資料層（W2-A 資料載入與 TS 型別、W2-B build-time 資料 lint）亦已全部完成並通過驗收**，詳見 [W2 紀錄](docs/records/W2實作紀錄.md)；**W3 第一個畫面（W3-B GameState 與初期推進規則、W3-A 開局與純演出 UI）亦已全部完成並通過驗收**，詳見 [W3 紀錄](docs/records/W3實作紀錄.md)；**W4 地圖與面板（W4-A 完整條件求值器、W4-B 白天地圖與地點面板）亦已全部完成並通過驗收**，詳見 [W4 紀錄](docs/records/W4實作紀錄.md)；**W5-A 卡片、手牌與知識、W5-B 交易、放置、預覽與行動格已完成並通過驗收**，詳見 [W5 紀錄](docs/records/W5實作紀錄.md)；其餘子階段仍為 📐 規格可實作。`web/public/art/` 已備妥小鎮地圖與 13 張白天地點場景圖（WebP），`web/prototype/` 已放入示意版原型。Godot 原版（P1～P5 機器層全綠、T-01～T-04 完工、36 套 headless 與 94 條 UI 契約全綠）**現已凍結為唯讀對照基準，其狀態與進度暫不理會**。**下一步：實作 `W5-C`（choice_group 互斥選擇）。**

---

## 專案概述

單人、敘事驅動的**卡牌經營／調查／迴圈敘事**遊戲。45 天一輪、一天 3 個時段，走到結局後回到第一天。含戀愛線與克蘇魯風格題材。

- **目標技術棧（當前主線）**：TypeScript + Vite + React 18（規則層 `web/src/core/` 為純 TS，不依賴 React／DOM，可在 Node 下 headless 執行 45 天走查與軌跡對帳）
- **對照基準（唯讀凍結）**：Godot 4.6.3 / GDScript（`scripts/`、`scenes/` 凍結只讀，供 W1-B 抽取黃金軌跡與移植規則參照）
- **核心資料結構**：一切都是卡槽（`data/SCHEMA.md > 核心概念`）——遭遇、縱慾、委託、比對都是同一個放卡動作；玩法與劇情全住在 `data/`，兩端共用同一份 JSON
- **驗證哲學**：無隨機、決定論、Node CLI 與黃金軌跡差分測試可自動走查對帳

## 目錄結構

```text
.
├── data/                    # 全部遊戲內容與可調數值（Godot 與 Web 共用的單一事實來源）
│   ├── SCHEMA.md            # 欄位定義
│   ├── tuning.json          # 全部可調數值
│   ├── cards.json / card_types.json / locations.json / npcs.json
│   ├── opening_choices.json / endings.json / relation_scale.json
│   └── beats/               # 三章逐日事件與縱慾出口，11 檔
├── docs/
│   ├── web/                 # 網頁版移植計畫、共用契約、W1～W7 實作契約（當前主入口）
│   ├── others/              # 指揮者手冊（conductor-handbook.md）、本機工具（local-tools.md）
│   └── records/             # W 階段實作紀錄與步驟板（派工時建立）
├── web/                     # 網頁版主目錄
│   ├── public/art/          # WebP 成品圖（map/town.webp、scenes/<地點 id>.webp）
│   ├── prototype/           # 示意版原型（d1-demo、map-demo、map-calibration），非規則來源
│   └── src/                 # 已有 React 空殼、data/ 型別與載入、core/ 初期狀態與規則、ui/ 開局與純演出畫面
├── tools/trace/             # baselines/greedy-godot.json 黃金基線＋ compare.ts／cli.ts 引擎無關比對器
├── scripts/ scenes/ tests/  # Godot 版（已凍結，唯讀對照組；W1-B 於 tests/headless/ 加軌跡產生器）
└── _舊文件/                 # 本機歷史 archive（gitignore），永遠忽略
```

## 資料層與對照基準現況

- **正式資料（`data/`）**：**66 張卡／48 個地點（白天 20＋夜間 28，含 T-03／T-04 全數補齊之 `desc`）／18 個 NPC／271 個 beat／4 個 ending／3 個 opening**；引用 0 錯誤；Lint 1～22 全 0 錯誤；第 1–45 天行動格全覆蓋（第 1 天上午／下午為純演出時段，第 32 天下午為刻意留空）。
- **貪心走查 90 個行動時段基準（`playthrough_greedy.gd`）**：成功放置主角卡 46／強制縱慾消耗 12／全 fixed 敘事時段 1／純比對槽 22／刻意留空 1／純演出 2／純選擇題 3／條件未解鎖 HIDDEN 2／前置門檻未達 LOCKED 1 ＝ 90。夜間帳：14 個收費標記全開、發放 14 張發狂卡 ＝ 消除 12 張 ＋ 重置前留存 2 張。
- **美術素材（`web/public/art/`）**：小鎮地圖 `map/town.webp` 已就位；`scenes/` 已完成 13 張白天地點場景圖（`bathhouse`、`busstop`、`clinic`、`columbarium`、`communitycenter`、`jinghe`、`oldhouse`、`oldschool`、`oldstreet`、`police`、`riverside`、`sanquan`、`temple`）。

---

## Phase 進度（網頁版 W 階段）

> 狀態圖例：✅ 已完成並通過驗收；🟦 待驗收；🟧 待 CLI／軌跡驗證；📐 規格可實作（契約已立、程式未開工）；⬜ 待開工／待規劃。
>
> **子階段一律一列一個，不得合併。** Godot 原版（P1～P5、T-01～T-04）已凍結作為唯讀對照基準，不再於本表展開（歷史紀錄見 `git log` 與 `驗證後已知問題.md`）。

| Phase | 狀態 | 概要 |
|---|---|---|
| **W1 骨架與軌跡基線** | — | 詳見 [`docs/web/W1實作契約.md`](docs/web/W1實作契約.md) |
| W1-A `web/` 骨架與資料同步 | ✅ | `80f2b7b`；React 18／Vite／TS 空殼、資料同步、測試與建置完成；19 份 JSON bytes／路徑、HTTP 與變異驗證通過，詳見 [驗收紀錄](docs/records/W1_steps/W1-A.md) |
| W1-B Godot 黃金軌跡產生器 | ✅ | 唯讀觀測、產生器與正式基線完成；193 筆 checkpoint／179 筆 phase_end／19 份 manifest，雙次生成及失敗保護驗證通過，詳見 [驗收紀錄](docs/records/W1_steps/W1-B.md) |
| W1-C 軌跡比對器 | ✅ | `174a9fd`；`compareTraces` 與 `trace:compare` CLI，首個差異報到 seq／天／時段／欄位；基線自比 193 筆／48,985 欄位、單欄位反轉、manifest 不符、壞 JSON、前綴不足與變異驗證通過，詳見 [驗收紀錄](docs/records/W1_steps/W1-C.md) |
| **W2 資料層** | — | 詳見 [`docs/web/W2實作契約.md`](docs/web/W2實作契約.md) |
| W2-A 資料載入與 TS 型別 | ✅ | `1389d05`、`49799a0`；資料型別、Browser／Node 載入、索引與結構事實完成；2026-10-31 使用者確認驗收完成，詳見 [W2-A 紀錄](docs/records/W2_steps/W2-A.md) |
| W2-B 資料 lint 移進 build step | ✅ | `895e938`、`2a4a507`；7 群組／22 條規則與 dev／build 接線，39 tests、24 個頁面反例、8 個合法空陣列案例及壞頁面 build 阻擋通過，詳見 [驗收紀錄](docs/records/W2_steps/W2-B.md) |
| **W3 第一個畫面** | — | 施工順序 B → A，詳見 [`docs/web/W3實作契約.md`](docs/web/W3實作契約.md) |
| W3-B `GameState` 與初期推進規則 | ✅ | `6613001`、`6bc87b6`；正式開局至 D2 morning、公開 API、深層唯讀快照與共用推進預檢完成；55 tests、build 與 W3 軌跡 5 筆／187 欄位 0 diff，詳見 [驗收紀錄](docs/records/W3_steps/W3-B.md) |
| W3-A 開局選擇與純演出 UI | ✅ | `426574b`、`1400b39`；開局預覽／確認／取消與鎖定理由、D1 逐段演出至 D2 morning、兩套自託管字型與 Playwright；55 tests、test:ui 3／3 連兩次、build 與 W3 軌跡 5／187 欄位 0 diff，3 項 P3 已修，詳見 [驗收紀錄](docs/records/W3_steps/W3-A.md) |
| **W4 地圖與面板** | — | 詳見 [`docs/web/W4實作契約.md`](docs/web/W4實作契約.md) |
| W4-A `ConditionEval` 全語彙補齊 | ✅ | `e3ac9b8`；17 個運算子、正式巢狀條件、持有與關係門檻、錯誤拒絕與零副作用；62 tests、build、W3 軌跡 5／187 欄位 0 diff 與正式 requires 變異驗證通過，詳見 [驗收紀錄](docs/records/W4_steps/W4-A.md) |
| W4-B 地圖、地點面板與卡槽三態 | ✅ | `a7c33f8`；白天地圖、地點簡介、逐段演出與唯讀卡槽完成；相關 Node 5／5、UI 3／3、build、W3 軌跡 5／187 欄位 0 diff 與 LOCKED 傳導變異通過；測試注入入口已隔離，詳見 [驗收紀錄](docs/records/W4_steps/W4-B.md) |
| **W5 能玩** | — | 詳見 [`docs/web/W5實作契約.md`](docs/web/W5實作契約.md) |
| W5-A 手牌、卡片實體化與知識分離 | ✅ | `68ba95e`；手牌／知識分區、主角卡不可移除、卡片與知識唯讀詳情完成；npm test 79／79、test:ui 7／7、build、W3 軌跡 5／187 欄位 0 diff 與規則變異通過；narration.spec 斷言已隨手牌面板修正，詳見 [驗收紀錄](docs/records/W5_steps/W5-A.md) |
| W5-B `EffectApply`、放卡結算與行動格 | ✅ | `8b9ca03`；預覽、放卡結算、基礎效果交易、行動格消耗，可從開局玩到 D3 evening；npm test 96／96、test:ui 8／8、build、W5 軌跡 12／560 與 W3 5／187 欄位 0 diff 與行動格變異通過；拒絕碼中文化等 1 項 P2／3 項 P3 已修正，詳見 [驗收紀錄](docs/records/W5_steps/W5-B.md) |
| W5-C `choice_group` 互斥選擇 | 📐 | 互斥選擇題（直接選擇與帶卡選擇）、選定即定案與唯讀 RESOLVED 展示 |
| **W6 全套規則** | — | 施工順序 E1 → A → B → C → D → E2，詳見 [`docs/web/W6實作契約.md`](docs/web/W6實作契約.md) |
| W6-A 夜間地點與發狂時鐘 | 📐 | 夜間 28 地點進入規則、終身首次收費、對位確認、`madness_clock` 倒數與視野門檻 |
| W6-B 縱慾出口（主動與強制） | 📐 | `web/src/core/indulgence.ts` 六個出口、泡湯特例、倒數歸零自動強制縱慾與強度級代價 |
| W6-C 委託 | 📐 | 人物卡委託、一天一人一次、immediate／next_morning 回報與教學提示 |
| W6-D 遭遇 | 📐 | `web/src/core/encounter.ts` 多回合遭遇狀態機、佔格、回應／丟棄／逃離與 D8／D45 接線 |
| W6-E 結局判定與迴圈重置 | 📐 | E1 結局底座先行；E2 整合四類結局、組合後日談、逐頁推進、歷輪 history 與跨輪重置 |
| **W7 收尾與上線** | — | 詳見 [`docs/web/W7實作契約.md`](docs/web/W7實作契約.md) |
| W7-A 45 天全程軌跡對帳全綠 | 📐 | 白名單清空，`trace-web.json` 與 `trace-godot.json` 45 天全程逐欄位一致 |
| W7-B 本機存檔與 UI | 📐 | `localStorage` 自動存檔與手動槽位、反序列化嚴格驗證與存讀 UI |
| W7-C 字型自託管與子集化 | 📐 | 霞鶩文楷 TC／台北黑體子集化 `woff2` 自託管與 `OFL.txt` 確認 |
| W7-D Cloudflare Pages 上線 | 📐 | 靜態建置產物驗證與 Cloudflare Pages 部署 |

---

## 測試速查

### 1. 網頁版命令（在 `web/` 目錄下執行，隨階段推進啟用）

`npm ci`、`npm test`、`npm run build`、`npm run dev`、`npm run trace:compare`、`npm run lint:data`、`npm run trace:web` 已可用；build／dev 已接資料 lint，trace:web 目前只產 W3 的 seq 0～4 前綴；test:ui 自 W3-A 起可用（Playwright headless Chromium）。

```powershell
npm ci                                           # W1-A 起：從 lockfile 安裝依賴
npm test                                         # W1-A 起：非 watch 自動測試（Vitest）
npm run build                                    # W1-A 起：資料同步 → TS 型別檢查 → Vite 建置
npm run trace:compare -- <expected> <actual>     # W1-C 起：Node CLI 比對兩份黃金軌跡
npm run lint:data                                # W2-B 起：Node 執行完整資料驗證（Lint 1～22）
npm run trace:web -- --output <path>             # 具備可對帳規則起：產出網頁版軌跡 JSON
npm run test:ui                                  # W3 起：Playwright Headless Chromium 自動驗證
```

### 2. Godot 對照基準命令（僅 W1-B 產生黃金軌跡或核對基準時使用）

```powershell
C:\_work\Godot_v4.6.3\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://scripts/verify_data.gd
C:\_work\Godot_v4.6.3\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/headless/playthrough_greedy.gd
$traceRevisionW1 = git rev-parse HEAD
& 'C:\_work\Godot_v4.6.3\Godot_v4.6.3-stable_win64_console.exe' --headless --path . --script res://tests/headless/generate_greedy_trace.gd -- --output _qa/web/trace-godot.json --source-revision $traceRevisionW1
```

- 在 sandbox 內跑 Godot headless 會因 `user://logs` 權限 crash，需直接以 escalated 權限執行。
- W1-B 產生器已可用；一般驗證輸出至 `_qa/web/`，不得自動覆寫 `tools/trace/baselines/greedy-godot.json`。基線來源 revision 與觀測接點差異見 W1-B 紀錄；此走法不含正式開局選擇，也不代表 Godot／TS 已對帳。

---

## 文件索引（網頁版期間：哪些要讀、哪些暫時不用看）

### ✅ 網頁版開發期間「要讀」的文件

| 文件 | 職責 | 何時讀 |
|---|---|---|
| `AGENTS.md` | 專案規則、修改／驗證授權、工具與スキル入口 | 新 session 開場必讀 |
| `PROJECT_BRIEF.md`（本檔） | 進度快照與文件導覽 | 新 session 開場必讀 |
| `docs/web/共用契約.md` | 網頁版架構邊界、CLI 命令、差分規則、派工規範 | **網頁版各階段動工前必讀** |
| `docs/web/W1實作契約.md` ～ `W7實作契約.md` | 各 W 階段的驗收規格、實作設計、白名單與必要驗證 | **做哪個 W 階段，就讀對應那一份** |
| `docs/web/網頁版移植計畫.md` | 移植全貌、階段拆分、技術選型、Godot ↔ TS 檔案對應表 | 需要查全案脈絡與檔案對照時 |
| `scripts/` 對應的 `.gd` 檔 | Godot 規則層真值（`data_loader.gd`、`scripts/core/*.gd`、`game_state.gd`） | 移植該模組時按工單點名唯讀對照 |
| `data/SCHEMA.md` | `data/` JSON 欄位定義 | 實作 W2 資料層或涉及資料欄位時按小節查閱 |
| `docs/others/conductor-handbook.md` | 指揮者派工、監看、審 diff 與紀錄規範 | 擔任指揮者派工給外部 agent 時 |

### ⏸️ 網頁版開發期間「暫時不用看」的文件

> 以下文件屬於**已編譯完成的設定／故事上游**或**已凍結的 Godot 原版歷史帳本**。由於 `W1`～`W7` 實作契約已將網頁版需求收斂完畢，**平時完全不必打開，避免浪費 context**：

- **完全不用看（Godot 專屬驗證與歷史交接）**：
  - `測試指南.md` — Godot 版 P1～P5 的 headless／`ui_sim` 驗收清單（網頁版驗收已直接寫在 `W1`～`W7` 實作契約內）。
  - `驗證後已知問題.md` — Godot 版 K-01～K-244 的歷史除錯紀錄（近 3,000 行；除非 W 契約點名某個 K 編號，否則不讀）。
  - `CODEX_HANDOFF.md` — Godot 版 P1～P5 階段交接長檔（網頁版改用 `docs/records/W<N>實作紀錄.md`）。
- **完全不用看（已編譯進 `data/` 的內容上游）**：
  - `subdocs/故事線/*.md`、`subdocs/卡牌/`、`subdocs/驗證/` — 劇情、卡片與數值模擬皆已落入 `data/*.json`；移植期間一字不改內容，直接讀 `data/` 即可。
- **平時不讀，僅在 W 契約點名時按標題 grep 該小節**：
  - `實作規格書.md`、`開發設計方針.md`、`溫泉小鎮企劃.md`、`待決事項.md`（第六節 W-01～W-06 除外）。

---

## 近期動態與下一步

- **2026-11-01**：**W5-B 完成並通過驗收**（`8b9ca03`）。verifier 於 `main@8b9ca03` 驗收：放卡判斷、預覽、推進提示與 `game_state.gd` 逐行一致，效果在 draft 上原子提交、未完成機制整筆拒絕；`npm test` 13 files／96 tests、build、`test:ui` 8／8 皆 exit 0，W5 軌跡 12 checkpoints／560 fields、W3 5／187 皆 0 diff，正式產物無測試注入。首輪 P2：預覽與放卡失敗把英文拒絕碼顯示給玩家，改照 Godot `_REASON_CODE_TEXTS` 轉中文；P3：字串來源與空清單原文、彈窗改 modal 可 Escape 關閉、effect 內 lose 未持有的已知卡改為 no-op、`action_cost` 與 `consume_action` 記帳拆開。三組變異（行動格、拒絕碼對照、lose no-op）均轉紅、還原後全綠。未跑 Godot。詳見 [W5-B 紀錄](docs/records/W5_steps/W5-B.md)；下一步 W5-C。

- **2026-11-01**：**W5-A 完成並通過驗收**（`68ba95e`）。verifier 於 `main@91b4a0d` 驗收：卡片規則與 `game_state.gd` 逐分支一致，手牌面板可見性與 Godot HandBar 相同；`npm test` 11 files／79 tests、build、`test:ui` 7／7 皆 exit 0，W3 前綴 5 checkpoints／187 fields、0 diff，正式產物無測試注入標記。首輪 P2：`narration.spec.ts` 以全頁按鈕數守純演出，被新增的手牌面板打紅；經使用者授權由 verifier 將兩處斷言縮為排除手牌面板並複驗，額外按鈕變異仍會轉紅。將知識計入佔格的變異使 cards.test 轉紅、還原後全綠。未跑 Godot。詳見 [W5-A 紀錄](docs/records/W5_steps/W5-A.md)；下一步 W5-B。

- **2026-10-31**：**W4-B 完成並通過驗收，W4 整體關門**（`a7c33f8`）。verifier 於乾淨的 `main@548710c` 複驗 W4-B 全範圍：僅執行相關 `panel.test.ts` 5／5 與 Playwright `map-panel.spec.ts`、`narration.spec.ts` 3／3，build exit 0，W3 前綴 5 checkpoints／187 fields、0 diff。原 P2「測試快照注入進入正式產物」已修正：Game API 與正式 bundle 均無注入入口，可信快照由 Playwright 路由攔截在測試內注入；移除 beat LOCKED 下傳的記憶體變異使對應斷言轉紅，取消後相關 Node 5／5 恢復全綠。未發現其他阻擋或非阻擋問題；未跑全套 Node／UI 或 Godot 測試。詳見 [W4-B 紀錄](docs/records/W4_steps/W4-B.md)；下一步 W5-A。

- **2026-10-31**：**W4-A 完成並通過驗收**（`e3ac9b8`）。verifier 於 `main@fac9fc3` 上的未提交 W4-A 工作區獨立驗收，驗收後相同實作提交為 `e3ac9b8`：9 files／62 tests、build 皆 exit 0，資料 lint 0 errors／4 筆既有豁免 warnings；透過 production `buildWebTrace()` 與 `compareTraces()` 在記憶體中核對 W3 前綴，5 checkpoints／187 fields、0 diff。逐項核對 17 個運算子、正式巢狀條件、持有與關係門檻、錯誤拒絕及零副作用；在記憶體中僅反轉正式 `d19_pm_upstream.requires`，對應斷言轉紅（exit 1），取消變異後 62 tests 再次全綠。未發現阻擋或非阻擋問題；本步不含 W4-B，未重跑 UI 或 Godot 全套。詳見 [W4-A 紀錄](docs/records/W4_steps/W4-A.md)；下一步 W4-B。

- **2026-10-31**：**W3-A 完成並通過驗收，W3 整體關門**（`426574b`、`1400b39`）。verifier 於乾淨的 `main@426574b` 驗收：55 tests、build、test:ui 連兩次 3／3 皆 exit 0，W3 軌跡 5／187 欄位 0 diff；實走相簿路徑至 D2 morning，正文順序與正式資料一致，兩套字型載入、無水平溢出；移除夜間演出呼叫的變異被攔下。驗收記下 4 項 P3，3 項（文案來源、末段正文消失、錯誤鎖死推進與恆真測試）於 `1400b39` 修正並複驗，確認框顯示 preview 依 SCHEMA 保留。詳見 [W3-A 紀錄](docs/records/W3_steps/W3-A.md)；下一步 W4-A。

- **2026-10-31**：**W3-B 完成並通過驗收**（`6613001`、`6bc87b6`）。verifier 於乾淨的 `main@6bc87b6` 複驗：8 files／55 tests、build 皆 exit 0；W3 軌跡 5 checkpoints／187 fields、0 diff。公開 API、深層唯讀 snapshot、推進預檢一致性與 flag 格式的四項 P2 均已修正；獨立核對 10 組推進情況、拒絕原子性、查詢無副作用、章節邊界及錯誤 flag 的零狀態／零文字洩漏。trace 入口未進瀏覽器產物，正式資料、Godot 與基線未改。詳見 [W3-B 紀錄](docs/records/W3_steps/W3-B.md)；下一步 W3-A。

- **2026-10-31**：**W2-B 完成並通過驗收，W2 整體關門**（`895e938`、`2a4a507`）。verifier 於乾淨的 `main@2a4a507` 複驗：5 files／39 tests、build 皆 exit 0；正式資料 22 條規則、0 errors／4 筆既有豁免 warnings。8 個頁面入口各驗物件／null／缺欄，24 個反例全攔下；8 個合法空陣列與 4 個複合條件反例驗證通過，驗證函式未修改輸入。缺頁面欄位的暫存資料使 build exit 1，未進 Vite。兩項 P2 均已修正；先前半途工作樹的結論不適用此提交。詳見 [W2-B 紀錄](docs/records/W2_steps/W2-B.md)。

- **2026-10-31**：**W2-A 完成並通過驗收**（`1389d05`、`49799a0`），依使用者確認更新狀態。資料型別、Browser／Node 載入、索引與結構事實已交付；既有工程紀錄為 4 files／31 tests、build 皆 exit 0，正式資料 catalog 與 Godot 對照一致。本次文件關門未重跑測試；詳見 [W2-A 紀錄](docs/records/W2_steps/W2-A.md)。

- **2026-10-31**：**W1-C 完成並通過驗收，W1 整體關門**（`174a9fd`）。OpenCode Nemotron 實作 `compareTraces` 與 `trace:compare` CLI，指揮者修正忽略路徑單邊缺鍵、actual 前綴不足退出碼與 manifest 不符訊息。verifier 重跑 npm ci／test／build（7 tests）與 HTTP smoke；基線自比 193 筆／48,985 欄位 exit 0，單欄位反轉精確報到 seq／天／時段／欄位 exit 1，壞 JSON exit 2，純量比較變異使 4 個案例轉紅；W1 改動皆在白名單內、未動 data 與 Godot 正式碼；詳見 [W1-C 紀錄](docs/records/W1_steps/W1-C.md)。
- **2026-10-31**：**W1-B 完成並通過驗收**。既有貪心走查只增唯讀 observer；產生器同時驗觀測開關等價，正式基線 1,947,278 bytes。三個既有入口與兩次生成 exit 0，雙次輸出及基線一致，D45 seq 178／179 均為 evening。結局漏採／重採、Windows 更名失敗、雙重失敗備份保留與回報均驗證通過，移除還原成功守衛的變異被攔截；詳見 [W1-B 紀錄](docs/records/W1_steps/W1-B.md)。
- **2026-10-31**：**W1-A 完成並通過驗收**（`80f2b7b`）。OpenCode Nemotron 實作、指揮者審核修正與獨立驗證；npm ci／test／build exit 0，19 份正式 JSON 相對路徑與原始 bytes 一致，空殼／tuning／地圖 HTTP 皆 200 且服務已關閉。移除 stale 刪除接線時測試轉紅、還原後全綠，無測試時 exit 1，npm audit 0 漏洞。驗收範圍僅 W1-A，不含玩法、瀏覽器或兩引擎軌跡對帳；詳見 [W1-A 紀錄](docs/records/W1_steps/W1-A.md)。
- **2026-10-31**：**確立純網頁版（TypeScript + Vite + React）移植主線，完成 W1～W7 全套實作契約與美術基底。**
  - 新增 `docs/web/`（[網頁版移植計畫.md](docs/web/網頁版移植計畫.md)、[共用契約.md](docs/web/共用契約.md)、[W1實作契約.md](docs/web/W1實作契約.md)～[W7實作契約.md](docs/web/W7實作契約.md)）及 `docs/others/` 指揮手冊，並完成兩輪契約漏洞與夜間／W6 守衛修正（至 `4ee0d79`）。
  - 建立 `web/public/art/`，放入小鎮地圖 `town.webp` 與 13 張白天地點場景圖（WebP），並於 `web/prototype/` 放入示意版原型與座標校準工具。
- **2026-08-30 ～ 2026-08-31（Godot 基準封存前最後更新）**：完成 P5-F 機器層關門、T-01 測試文案解耦、T-02 全 12 檔套語清理、D1 上午／下午純演出時段、T-03 白天地圖空點解鎖與 20 個白天地點 `desc`（含 `c1acc73` B1–B5 修正）、T-04 夜間 28 個地點 `desc` 與防劇透 Lint 22（`49ab0c7`，Godot headless 共 36 套全綠）。
- **後續方向**：W-01～W-06 已全數定案，見 `待決事項.md` 第六節；目前美術方向沿用，W7 先完成繁體中文版，再規劃多語系；不考慮 Steam 或 Godot 存檔相容，Godot 維持凍結。
- **下一步**：依 [`docs/web/W5實作契約.md`](docs/web/W5實作契約.md) 實作 **W5-C（choice_group 互斥選擇）**；W1～W4 與 W5-A／B 已完成驗收，不重做已驗收規則或重產基線。
