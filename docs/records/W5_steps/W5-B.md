# W5-B 交易、放置、預覽與行動格

## 派工範圍與來源

- 日期：2026-11-01；起點 main@d421db6；worker：agy／Gemini 3.8 Flash (High)。
- 契約：docs/web/共用契約.md 的架構、必要驗證與差分；docs/web/W5實作契約.md 的一、二、四（W5-B）、六；W3 狀態所有權與 W4 演出／VM 接線。
- 必須先讀 W5-A 步驟檔 Verifier 與下一步：新 UI 會影響的既有 spec 必須列入回歸。
- 交付：補齊 text／lose／gain／switch／switch_progress／relation／flag 的 draft 交易；共用 placement 檢查、公開 tryPlace／placeableCards／previewSlot／hasAnyLegalAction／hasUnseenContent；點槽選卡與唯讀右鍵預覽、結果保留、行動格與投入帳；正常開局至 D3 evening，十二筆軌跡。
- madness／delegation／choice 路由與未完成效果依契約零副作用拒絕，不做 W5-C 或 W6；不放寬正式資料或黃金基線。
- 工單：C:/_work/AI_Work/Tools/agy-runs/agy-W5-B-20261101.prompt.txt；回報同名前綴 .json。

## 必跑工程檢查

- Node：effect.test.ts、placement.test.ts、cards.test.ts、state.test.ts、opening.test.ts、narration.test.ts、panel.test.ts；只限這些相關檔，修正本步造成過期的預期並保留原守衛意圖。
- UI：新增 placement.spec.ts，以及既有 opening.spec.ts、narration.spec.ts、map-panel.spec.ts、hand.spec.ts 全部具名列入。特別處理 D2 morning 推進不再停用與新增按鈕／彈窗的 selector 範圍，不以刪斷言掩蓋產品錯誤。
- build；trace:web 對 tools/trace/scopes/W5.json（throughSeq 11／ignorePaths 空），十二筆；消耗行動格接線變異使第二次主角拒絕斷言轉紅，再還原重跑相關檔。
- UI 預覽與詳情開關前後 serialize 全 flow/run/meta 逐字一致；拒絕同樣全序列化一致，失敗文字不外洩。只用專用 Headless Chromium，禁止 Edge。

## 指揮者審核修正

- 首輪達 agy 20 分鐘 print_timeout，僅部分回報，未採用 SUCCESS 字樣作通過依據；指揮者實跑確認當時相關 Node 44／44、UI 8／8、build 與 W5 12／560、W3 5／187 零差異。
- 退回同一 conversation 修正三項契約差異：合法 ending 效果必須在 planEffects 原子拒絕；switch 只接受 schema 的字串，移除陣列語法；夜間 runner 以實際 beats_entered 差分與 location layer 驗證強制到訪，不以 lines.length 當播放證據。並共用 gain／lose 條件項目解析，減少重複。
- 指揮者補強 placement.test.ts：LOCKED 實際提交拒絕／完整序列化不變；投入帳、switch_progress、relation 在重複提交後仍只累加一次；另加獨立第二次主角拒絕案例，使 consume action 變異精確在第二次提交斷言轉紅。僅補證據，不增加玩法；effect.ts 說明同步成現行支援鍵。
- 既有 narration.spec.ts 的 D2 morning 推進預期由停用改為可按且顯示「推進時段（還有演出沒看）」；純演出期間排除手牌按鈕後不得有其他操作的原守衛保留。UI 四份既有 spec 已明列並實跑，未再漏 narration。

## 交付與測試證據

- Worker：agy／Gemini 3.8 Flash (High)；conversation 30e8a0e3-fd50-4444-b167-32069ac330cd，同一對話 2 輪。首輪 timeout 部分輸出約 1192 秒；修正後回報累計約 1860 秒。工單／followup／JSON 回報皆在 repo 外 agy-runs。
- 受測工作樹：main@d421db6 加本步改動；最後產品行為檢查後僅更新交接文件，再由指揮者提交。worker 無 git 寫入、無文件修改。
- 新增 placement.ts、effect.test.ts、placement.test.ts、ui/placement.spec.ts 與 tools/trace/scopes/W5.json；修改 effect／state／state-types、GameShell／LocationPanel／SlotView／strings／styles、greedy runner／trace CLI 與直接受影響的 state／narration 測試。未修改來源 data、Godot、素材、依賴、W3 scope、黃金基線或比對器。
- 公開 Game API：tryPlace(cardId,beatId,slotId)、placeableCards(beatId,slotId)、previewSlot(beatId,slotId)、hasAnyLegalAction()、hasUnseenContent()；卡片使用持有實例 ID。effects 與 bookkeeping 共用 detached draft 結算，成功才換入並通知；UI 僅派發、顯示 VM、保存結果文字。
- 正式端到端案例由 chooseOpening 自然走至 D2 afternoon work 取得夫妻情報，D3 afternoon 免費 show_version 後再放主角 help_ahong；不是手塞情報的替代流程。

| 指揮者實跑工程檢查 | 結果 |
|---|---|
| npx vitest run tests/effect.test.ts tests/placement.test.ts tests/cards.test.ts tests/state.test.ts tests/opening.test.ts tests/narration.test.ts tests/panel.test.ts | exit 0；7 files／47 tests；未跑資料、lint、facts、sync 或比對器單元套件 |
| npx playwright test tests/ui/placement.spec.ts tests/ui/opening.spec.ts tests/ui/narration.spec.ts tests/ui/map-panel.spec.ts tests/ui/hand.spec.ts --workers=1 | exit 0；5 files／8 cases，最終版本再次通過。包含新增實際放卡路徑、預覽全序列化比對，以及受新共用 UI 影響的四份既有 spec；專用 Headless Chromium |
| npm run build | exit 0；19 份 JSON 同步、22 條資料規則、0 errors／4 筆既有豁免 warnings，tsc／Vite 通過 |
| W5／W3 軌跡 | 以 production buildWebTrace／compareTraces 在記憶體中對正式基線，W5 scope throughSeq 11／ignorePaths 空：12 checkpoints／560 fields，0 diff；W3 前綴 5／187，0 diff，exit 0。worker 另有 _qa/web/W5-B/trace-web.json |
| 行動格最小變異 | 指揮者用 Vite transform 與獨立 cacheDir 在記憶體中將 bk.consume_action=true 改為 false，命中 1 次；僅執行 second protagonist refuses，第二次提交 ok:false 的斷言轉紅，exit 1（1 failed／5 skipped）。取消變異後 npx vitest run tests/placement.test.ts：6／6，exit 0；原始碼未留變異 |
| 開發界線 | runGreedyW5 正常抵達 D3 evening，advancePhase 原子拒絕 not_implemented、lines 空、完整 serialize 前後逐字一致 |
| 正式產物隔離 | 實際 dist JS 無 __testGame、__w5aGame、快照 override、loadTrustedSnapshot 或舊測試橋接；測試觀測僅 Playwright route 攔截內 |
| 檔案範圍 | git diff --check 通過；沒有改正式資料、Godot、素材、黃金基線，未執行 Godot 或無關 Node 測試 |

## 未解問題與下一步

- 工程檢查已完成，交 verifier 獨立驗收 W5-B；不自行勾驗收、不更新 PROJECT_BRIEF.md。
- 保留 not_implemented：choice_group（W5-C）、一般夜間／睡覺解析、madness gain／倒數／cap／BE、縱慾、委託／回報、遭遇、festival_proxy、ending／重置與相關 phase_exit；可玩範圍停在 D3 evening，未假稱完整 45 天。
- 環境產物：worker 在 repo 根目錄誤產 node_modules（只含 Vitest caches）及 test-results/.last-run.json。指揮者嘗試限定路徑遞迴清理、再縮為逐一已辨識檔案清理，均遭工具自動審核拒絕（僅提供 blocked by policy）。檔案保留未追蹤，不提交、不為隱藏它們改 gitignore；產品程式與工程檢查不受影響。

## Verifier 獨立驗收與修正（2026-11-01）

- 結論：**W5-B 已完成並通過驗收**。首輪發現 1 項 P2、3 項 P3，經使用者授權全部由 verifier 修正並複驗。
- 受驗版本：`main@8b9ca03`（W5-B 實作提交）；修正與本段紀錄同一 commit 提交。
- 規則對照：`checkSlotState`／`checkPlace`／`placeableCards`／`previewSlot`／`hasAnyLegalAction`／`hasUnseenContent` 與 `game_state.gd` 同名函式逐行一致；`tryPlace` 九步分流順序符合契約，madness／delegation／choice 零副作用拒絕。effect 在 draft 上依固定鍵序結算、條件項目讀前序結果，madness／festival_proxy／ending 整筆拒絕且文字不外洩；記帳與效果同一筆提交。推進按鈕三種文案的判斷順序與 `main.gd` 一致。

| 發現 | 等級 | 修正 |
|---|---|---|
| 右鍵預覽與放卡失敗把英文拒絕碼（`not_accepted`、`action_spent` 等）直接顯示給玩家；Godot `location_panel.gd` 以 `_REASON_CODE_TEXTS` 轉中文（K-115 同族） | P2 | `strings.reasonCodes` 照搬 Godot 對照表；預覽理由與放卡失敗（`placeFailed`，對應 `_FMT_PLACE_FAILED`）一律先經對照；placement.spec 補「理由：本時段行動已用完」且不含 `action_spent` 的斷言 |
| 新增 UI 字串未註來源，空清單文字與 Godot「目前沒有可放的卡。」不同；選卡／預覽彈窗為非 modal，Escape 關不掉 | P3 | 字串補 Godot 來源或標 W5-B 新增，空清單改用 `_MSG_PREVIEW_EMPTY` 原文；兩個彈窗改與 CardDetail 相同的 `showModal`＋onCancel，placement.spec 補 Escape 關閉斷言 |
| effect 的 lose 遇到未持有的已知卡會整筆拒絕；Godot `effect_apply.gd` 只報資料錯並繼續（影響 `d45_then.compare_registry` 的 `k_not_today`） | P3 | effect 管線內未持有的已知卡視為 no-op（永久失去的 meta 照處理），未知 id 仍 data_conflict；直接呼叫 `loseCard` 的 W5-A 語意不變；effect.test 補案例 |
| 記帳把 `action_cost` 綁在 `consume_action` 之下；Godot `_apply_bookkeeping` 兩者獨立 | P3 | `applyBookkeepingOnDraft` 拆成兩條獨立記帳；W5 公開路徑尚無 `action_cost` 來源，W6 縱慾／遭遇接上時須補測 |

| 獨立檢查（修正後） | 結果 |
|---|---|
| `npm test` | exit 0；13 files／96 tests（首輪 95） |
| `npm run build` | exit 0 |
| `npm run test:ui -- --workers=1` | exit 0；8／8 |
| `trace:web` + `trace:compare` | W5 scope 12 checkpoints／560 fields、W3 scope 5／187，皆 equal=true（`_qa/web/trace-web-W5B-verifier.json`） |
| 正式產物隔離 | `dist/assets` JS 無 `__testGame`、`__w5aGame`、快照 override、`loadTrustedSnapshot` |
| 行動格變異（首輪） | 將 `bk.consume_action = true` 改 false，placement.test 3 failed（含第二次主角拒絕）；還原後 6／6 |
| 拒絕碼對照變異 | 預覽理由改回原始 code，placement.spec 轉紅（實際顯示「理由：action_spent」）；還原後 1／1 |
| lose no-op 變異 | 停用未持有 no-op 分支，effect.test 對應案例轉紅；還原後 10／10 |

- 驗收界線：只驗 W5-B 與受影響的 W3／W4／W5-A 回歸；不含 W5-C choice 與 W6 機制；未跑 Godot。repo 根目錄的未追蹤 `node_modules/`、`test-results/` 為 worker 產物，未提交，需使用者手動清除。

## 下一步

- 依 `docs/web/W5實作契約.md`「五、W5-C：choice_group」接續實作；W5-C 涉及 `d45_then` 時沿用本步 lose no-op 語意。
