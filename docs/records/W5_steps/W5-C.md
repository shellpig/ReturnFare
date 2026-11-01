# W5-C choice_group

## 派工範圍與來源

- 日期：2026-11-01；起點 main@035b56e；worker：agy／Gemini 3.8 Flash (High)（使用者指定）。
- 契約：docs/web/共用契約.md 的架構、必要驗證與差分；docs/web/W5實作契約.md 的一、二、五（W5-C）、六；沿用 W5-B 已驗收的 checkPlace、settle 與放卡 UI。
- 必須先讀 W5-A、W5-B 步驟檔的 Verifier 段落：新 UI 影響的既有 spec 必須全部列入必跑；玩家介面不得外露英文拒絕碼；effect 內 lose 未持有的已知卡為 no-op（`d45_then.compare_registry` 依賴此語意）。
- 交付：公開 `choose(beatId, groupId, slotId, cardId?)`；`tryPlace` 第 8 步改轉 `choose`；choice 槽直選與帶卡選 UI，被選項唯讀、其他同組選項消失；`choice_requires_card` 空卡拒絕與主角成本。
- 不做：委託、`default_if_unresolved` 離開時段結算、慶典代付、phase_exit 與其他 W6 機制，一律零副作用拒絕；關面板未選不寫任何狀態。
- 工單：C:/_work/AI_Work/Tools/agy-runs/agy-W5-C-20261101.prompt.txt；回報同名前綴 .json。

## 必跑工程檢查

- Node：choice.test.ts、placement.test.ts、effect.test.ts、panel.test.ts、state.test.ts。
- UI：新增 choice.spec.ts，以及既有 placement.spec.ts、map-panel.spec.ts、narration.spec.ts、hand.spec.ts、opening.spec.ts 全部具名列入。
- build；W5 軌跡 12 筆／W3 前綴 5 筆 0 diff；已結算守衛或成本判斷擇一變異轉紅，還原後全綠。
- 直選與帶卡選完整 serialize 比較；關面板、拒絕與重複選擇 serialize 前後逐字一致；測試注入不得進正式產物。

## 指揮者審核修正

- 改動檔案均在白名單內：state.ts、state-types.ts、GameShell／LocationPanel／SlotView／strings／styles，新增 choice.test.ts、ui/choice.spec.ts；未改 docs、data、Godot、基線、依賴；未新增 choice.ts 或 fixture host，高日數 UI 沿用 Playwright 路由注入。
- `choose()` 檢查順序與 `game_state.gd` 逐行一致（not_run → encounter_active → 已結算 → unknown_beat → 槽不存在或不屬該組 → 委託 not_implemented → card_required → checkSlotState → 帶卡 checkPlace → 記帳 → 共用 settle）；只有 choice_requires_card、主角卡且行動時段才消耗行動與記 attention。`tryPlace` 第 8 步改轉 `choose`。
- 指揮者修正 2 處：LocationPanel 的 `onChooseSlot` 原為 optional 並在缺省時直接呼叫 `game.choose`，會繞過結果文字與錯誤顯示，改為必填並移除退路；`strings.choose` 註解原稱對應 `_FMT_CHOOSE_BUTTON`，實際 Godot 為「選擇：%s」，改註為取其前綴。
- 單獨移除 `choose()` 開頭的已結算守衛時 choice.test 仍綠，因 `checkSlotState` 第 6 步同樣擋已結算組（Godot 亦為雙重檢查）；兩處同時移除才轉紅，見下表。

## 交付與測試證據

- Worker：agy／Gemini 3.8 Flash (High)；conversation 47662d85-b3c5-4eb7-86a1-b57cdb001602，1 輪約 946 秒，status SUCCESS；回報 C:/_work/AI_Work/Tools/agy-runs/agy-W5-C-20261101.json。
- 公開 API：`Game.choose(beatId, groupId, slotId, cardId?)`；UI 在 choice 槽（非 choice_requires_card）提供「選擇」直選，帶 accepts 時沿用選卡彈窗經 tryPlace 轉 choose；choice_requires_card 只提供帶卡入口。新增拒絕碼中文 card_required／not_run／not_implemented 標註 W5-C 新增。
- Node：正式 d22_pm_sandbags 直選與帶 equip_polaroid 完整 serialize 逐字相同；重複選擇與同組他項皆 resolved 且 serialize 不變；正式 d43_pm_zhou 空卡 card_required 零變化、主角放置消耗行動；普通 choice 帶主角不耗行動以 fixture 補證（正式資料中所有收主角的 choice 皆為 choice_requires_card）。

| 指揮者實跑工程檢查 | 結果 |
|---|---|
| `npm test` | exit 0；14 files／99 tests |
| `npm run build` | exit 0（指揮者修正前後各一次） |
| `npm run test:ui -- --workers=1` | exit 0；10／10（choice 2、placement 1、map-panel 2、narration 1、hand 2、opening 2），修正後重跑仍 10／10 |
| W5／W3 軌跡 | `_qa/web/W5-C/trace-web-conductor.json`：W5 12 checkpoints／560 fields、W3 5／187，皆 equal=true |
| 成本變異（worker） | 註解 choose 內 `bk.consume_action = true`，choice.test 的 D43 行動消耗斷言轉紅；還原後 3／3 |
| 已結算變異（指揮者） | 同時停用 choose 開頭與 checkSlotState 的 choices 已結算檢查，choice.test 重複選擇斷言轉紅（expected 'locked' to be 'resolved'）；還原後 3／3，git diff 無殘留 |
| 正式產物隔離 | dist JS 無 `__testGame`、`__w5aGame`、`__w5c`、`loadTrustedSnapshot`、快照 override |

## 未解問題與下一步

- 工程檢查已完成，交 verifier 獨立驗收 W5-C；指揮者不標記驗收完成，不修改 PROJECT_BRIEF.md。
- 仍為 not_implemented：委託、default_if_unresolved 離開時段結算、慶典代付、phase_exit 及其他 W6 機制；D3 evening 之後推進仍受開發界線阻擋。
