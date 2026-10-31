# W3-B `GameState` 與初期推進規則

## 範圍與來源

- 日期：2026-10-31；起點：`main@f8ef87d`。
- 契約：`docs/web/共用契約.md`「二、架構與資料邊界」「三、快速檢查」；`docs/web/W3實作契約.md`「一」「二」「三、W3-B」「五、收尾與交接」。
- 參照來源（唯讀）：`scripts/autoload/game_state.gd`（`serialize`/`deserialize`、`opening_view`、`choose_opening`、`_apply_run_initialization`、`advance_phase`、`_settle_auto_enter_beats`、`play_beat`、`play_evening`、`play_night_fixed`、`_record_forced_night_visit`）、`scripts/core/condition_eval.gd`、`scripts/core/effect_apply.gd`、`tests/headless/playthrough_greedy.gd`、`tools/trace/baselines/greedy-godot.json`。
- 可動檔案：
  - 新增：`web/src/core/state-types.ts`、`web/src/core/state.ts`、`web/src/core/run-initialization.ts`、`web/src/core/trace-entry.ts`、`web/src/core/cards.ts`、`web/src/core/condition.ts`、`web/src/core/effect.ts`、`web/src/core/night.ts`、`web/tests/state.test.ts`、`web/tests/opening.test.ts`、`web/tests/narration.test.ts`、`web/scripts/trace-web.ts`、`web/tests/support/greedy.ts`、`tools/trace/scopes/W3.json`、`docs/records/W3實作紀錄.md`、`docs/records/W3_steps/W3-B.md`
  - 修改：`web/src/core/facts.ts`、`web/tests/facts.test.ts`、`web/package.json`

## 實作摘要與公開 API

- `web/src/core/facts.ts`：補齊 `LAST_DAY = 45`、`phasesForDay(day)`、`nextPhase(phase, day?)`、`nextPhaseTarget(day, phase)`（含 D45 收束於黃昏無夜間）與 `beatsAt(beats, day, phase)`。
- `web/src/core/state-types.ts`：定義 `GameSnapshot`（`flow`、`run`、`meta` 三區，與 Godot `GameState.serialize()` 100% 同名同結構）、`DeepReadonly<T>`、`OpeningScreenView`、`OpeningOptionView`、`PhaseView`、`MutationResult`、`AdvanceResult` 與 `Game` 介面（含契約公開查詢 `chapter()`、`openingScreenView()`、`openingView()` 與相容別名 `getOpeningScreenView()`、`getOpeningView()`）。
- `web/src/core/cards.ts`：`hasCard`、`hasKnowledge`、`handSlotsUsed`、`gainCard`（`protagonist` 恆在 index 0、佔格卡 unique、`slotless:true` 進 `meta.knowledge`、`loop_persistent:true` 同步寫 `meta.loop_persistent_item_ids`；`madness` 在 W3 回 `not_implemented`）、`loseCard`（拒絕丟棄主角卡回 `data_conflict`，其餘在 W3 回 `not_implemented`）。
- `web/src/core/condition.ts`：`evalCondition(condition, state, data)` 支援 `null`/`undefined` → `true`、`opening_choice`、`ending_seen`；空物件／多鍵拋 `ConditionError`（`data_conflict`），未實作運算子拋 `UnsupportedConditionError`（`not_implemented`），絕不預設為 `true`。
- `web/src/core/effect.ts`：`planEffects(blocks, state, data)` 在獨立狀態複本上按固定順序預演（W3 實作 `text`、`gain`、`flag` 與 `ending` 攔截；`flag` 與 Godot `EffectApply` 對齊，只接受 Dictionary（`Record<string, boolean>`），字串／陣列等非物件形狀回 `data_conflict` 並原子拒絕；遇到未實作鍵 `lose`/`switch`/`switch_progress`/`relation`/`madness`/`festival_proxy` 時整筆交易回 `not_implemented`，零半套狀態與零流出文字）。
- `web/src/core/run-initialization.ts`：`createInitialSnapshot()`、`cloneSnapshot(state)`、`deepFreeze(obj)` 與 `initializeRun(state, data)`（重置 `run`、放入 `protagonist`、按 `data.cards` 順序恢復 `meta.loop_persistent_item_ids`、將 `meta.knowledge` 複製凍結為 `run.knowledge_at_start`）。
- `web/src/core/night.ts`：`recordForcedNightVisit(state, locationId, data)` 與 `nightBeatCandidates(day, locationId, currentChapter, data)`。
- `web/src/core/state.ts`：`createGame(data, initialState?)` 實作 `getSnapshot()`（每次建立或 `commitState` 時透過 `deepFreeze` 遞迴凍結，維持讀取期間 reference identity 穩定並防止外部修改巢狀欄位）、`serialize()`、`subscribe()`、`chapter()`、`openingScreenView()`、`openingView()`、`chooseOpening(choiceId)`、`getPhaseView()`、`playBeat(beatId)`、`playEvening()`、`playNightFixed()` 與 `advancePhase()` 七步骨架；`getPhaseView().can_advance` 與 `advancePhase()` 共用同一條純預檢 `preflightAdvancePhase(currentState, data)`，確保就寢停拍、`madness_clock`、`actions_spent_ahead`、`forced_pending`、`pending_delegation_reports` 等所有守衛下兩者永遠一致；暫態演出文字保存在 store 內部，不進 `serialize()`，且同一時段重複讀取或再次呼叫 `playEvening()`／`playNightFixed()` 不重套 `on_enter`、不洗空已結算文字。
- `web/src/core/trace-entry.ts`：`createRunForTrace(data)` 供 `trace-web.ts` 與測試建立無開局走查初態，未由 `main.tsx` 或任何 UI 元件引用。
- `tools/trace/scopes/W3.json`、`web/tests/support/greedy.ts`、`web/scripts/trace-web.ts`：支援 `npm run trace:web -- --output <path>` 產出 `seq: 0..4` 軌跡並與 `tools/trace/baselines/greedy-godot.json` 比對。

## 驗證證據

| 檢查項目 | 結果 |
|---|---|
| `npm test`（cwd `web/`） | exit 0；8 files、55 tests 全綠（含 `state.test.ts`、`opening.test.ts`、`narration.test.ts`、`facts.test.ts`） |
| `npm run build`（cwd `web/`） | exit 0（依序執行 `sync-data.mjs` → `npm run lint:data` → `tsc --noEmit` → `vite build`） |
| `npm run trace:web` + `npm run trace:compare`（`tools/trace/scopes/W3.json`） | exit 0；`comparedCheckpoints=5 comparedFields=187 equal=true`（`seq: 0..4` 0 diff） |
| 變異檢查（開局 `auto_enter` + 4 項 `[P2]` 修正） | 暫時移除 `chapter()`、繞過 `deepFreeze`、繞過 `preflightAdvancePhase` 或放行字串 `flag` 時，`opening.test.ts` 與 `state.test.ts` 對應 4 條測試全數立即轉紅（4 failed）；還原後 55 tests 全綠 |
| 邊界檢查 | `git status` 確認 `data/`、Godot 正式檔、`tools/trace/baselines/greedy-godot.json` 零改動；`main.tsx` 未引用 `trace-entry.ts` |

## 建議 verifier 更新事項

- 驗收通過後，建議於 `PROJECT_BRIEF.md` 將 W3-B 標記為完成，後續推進 W3-A（開局與純演出 UI）。
