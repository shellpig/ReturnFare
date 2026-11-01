# W6-A 夜間、發狂錶與對位

## 派工範圍與來源

- 日期：2026-11-01；起點 main@71d36a0（W6-E1 驗收關門提交）；worker：Claude Code 子代理 Sonnet 5.5，effort high（使用者指定）。
- 契約：docs/web/共用契約.md 的架構、必要驗證與差分；docs/web/W6實作契約.md 的一、二、四（W6-A）；沿用 W6-E1 的 `startEndingOnDraft`／ending request、W5 `EffectPlan` 與 W3 `advancePhase` 預檢。
- Godot 對照：`game_state.gd` 的 play_night_fixed／resolved_night_content／sleep_night／night_location_seen／enter_night_location／confirm_night_alignment／would_night_entry_end_run／_record_forced_night_visit／tick_madness／_check_madness_cap 與 advance_phase 夜間段；`data_loader.gd` night_beat_candidates；`panel_builder.gd` location_summary 夜間分支與 alignment_offer；`effect_apply.gd` madness 效果；`scenes/ui/map_list.gd` 與地點面板夜間分支。
- 交付：先以機制守衛取代 W5 的 D3 evening 日期界線；`madness.ts`；Game `nightLocationSummary`、`resolvedNightContent`、`enterNightLocation`、`alignmentOffer`、`confirmNightAlignment`；睡覺併入 `advancePhase()`；`madness` 效果與發狂卡上限接 E1 ending request；`NightDetails.tsx`；greedy helper 接夜間地點。
- 不做：強制縱慾結算（W6-B）、委託（W6-C）、遭遇（W6-D）、phase_exit／D45／D29（E2）；需要它們的推進或操作在 mutation 前原子拒絕 not_implemented。trace runner 的 D3 截止不動（E2）。
- 工單：C:/_work/AI_Work/Tools/agy-runs/sonnet-W6-A-20261101.prompt.txt。

## 必跑工程檢查

- Node：新增 night.test.ts、madness.test.ts；`npm test` 全套。
- UI：新增 night.spec.ts，以及既有 opening／narration／map-panel／hand／placement／choice／ending 全部具名列入。
- build；W5 軌跡 12 筆／W3 前綴 5 筆 0 diff。
- 契約變異：移除「已 seen 不再收費」判定，重訪測試轉紅，還原後全綠。
- D6 起點以可信快照注入，證據須標明「注入 D6 起點」；拒絕前後 serialize 逐字一致；dist 無測試注入。

## 指揮者審核修正

- 改動檔案均在白名單內：core 的 night／madness（新）／cards／effect／panel／placement／state／state-types，UI 的 NightDetails（新）／GameShell／LocationPanel／strings／styles，greedy helper，新增 night.test／madness.test／ui/night.spec，修改 cards／effect／state 測試與 narration／map-panel／placement spec 既有斷言。未改 docs、data、Godot、基線、scope、trace 工具、依賴、ending.ts。MapPanel／HandPanel 未改（夜間列表走 mapView，倒數已在手牌顯示）。
- 對照 Godot：`advancePhase` 夜間停拍與 advance_phase ③一致（未選未睡才睡；有文字只停拍、時段不動；睡覺效果進結局則不推進）；`planEnterNightLocation` 拒絕順序與 enter_night_location 逐條一致（not_run → not_night → encounter_active → overloaded → unknown_location → not_night_layer → teaser → too_early → locked → already_chosen → already_slept），先記 chosen／seen、首訪才收費、收完再查 cap；`tickMadnessOnDraft` 與 tick_madness 一致；發狂卡實例 id／counter／倒數與 gain_card madness 分支一致，cap 以手牌實例數計。
- 接受的偏離：睡覺在 draft 上執行，無文字的睡覺若後續推進被拒會一併丟棄（Godot 先落地），只會更原子；`alignmentOffer` 多加 mode／遭遇守衛，維持「有 offer 則 confirm 成功」，其餘順序同 Godot。
- 守衛替換後仍保留的 not_implemented：預扣行動格、forced_pending 待強制縱慾（tick 後判斷，B）；委託回報（C）；目標時段 fixed 遭遇與 playNightFixed 遭遇 beat（D）；D45 phase_exit、festival_proxy（E2）；放發狂卡（B）、委託槽（C）。
- 指揮者未改程式。新檔 madness.ts／night.ts／NightDetails.tsx 共 4 行超過 140 字元（工單要求不超過），不影響行為，列 P3。

## 交付與測試證據

- Worker：Claude Code 子代理 Sonnet 5.5（effort high），1 輪約 1,497 秒、147 次工具呼叫；工單 C:/_work/AI_Work/Tools/agy-runs/sonnet-W6-A-20261101.prompt.txt。
- 公開 API：`nightLocationSummary`、`resolvedNightContent`（只露 id／title）、`enterNightLocation`、`alignmentOffer`、`confirmNightAlignment`；`PhaseView.night_advance` 三態、`PanelView.empty_result`；新增 12 個 reason code 皆有中文對照。
- 自然走查從開局可走到 D8 evening（停在 W6-D 遭遇守衛）；D6 夜間與 D17 UI 起點皆為注入快照並於測試標明。trace-web 截止仍為 D3。

| 指揮者實跑工程檢查 | 結果 |
|---|---|
| `npm test` | exit 0；17 files／162 tests |
| `npm run build` | exit 0 |
| `npx playwright test --workers=1` | exit 0；12／12（含新 night 1）；worker 曾遇一次 Chromium worker crash（map-panel，無斷言失敗），指揮者重跑未再發生 |
| W5／W3 軌跡 | `_qa/web/W6-A/trace-web-conductor.json`：W5 12 checkpoints／560 fields、W3 5／187，皆 equal=true |
| 契約變異（指揮者） | `planEnterNightLocation` 的 isFirstTime 改恆真，night.test 重訪免費與入夜 fixed 2 筆轉紅；還原後逐位元相同，14／14 |
| 額外變異（worker） | 移除 tick 5 紅、移除強制結算守衛 3 紅、移除 cap 合併 2 紅，皆還原 |
| 正式產物隔離 | dist JS 無 `__w6a`、`__testGame`、`__origCreateGame`、`snap_override`（0 檔） |

## 未解問題與下一步

- 對位可達性（與 Godot 相同）：白天地點無可見 beat 且未到訪時地圖按鈕停用，對位鈕無法到達，例如 D17 `upstream`、D38 `jinghe_back`、D43 `temple_back`；交 verifier 判斷是否需記入待決。
- 空結果文字「走了很久。什麼都沒有遇到。」：實作規格書.md 第九節明文要求合法地點無內容時顯示此通用結果，網頁版照規格顯示，不改；Godot UI 未渲染屬凍結版缺口，不跟。
- 更正：上方「4 行超過 140 字元」為誤判。指揮者用 awk 依 bytes 計長，中文行被高估；以 UTF-8 字元重算，madness.ts／night.ts／NightDetails.tsx 與 W6-E1 的 ending.ts 皆 0 行超過 140 字元，無需修改。
- 交 W6-B：forced_pending 守衛、放發狂卡、預扣行動格；交 C／D／E2 見上方守衛清單。
- 工程檢查已完成，交 verifier 獨立驗收 W6-A。
