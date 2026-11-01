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
