# ReturnFare 交接狀態

最後更新：2026-08-26

## 目前階段

**P1、P2 已完成；P3 機器層已完成，剩既有人工體感項；P4-A～F 與 P5-A～F 規格已完成，下一個實作任務仍是 P4-A。P5 不得跳過 P4 提前實作。**

- 進度與測試數字的單一事實來源是 `PROJECT_BRIEF.md`；本檔只保存最近交接重點。
- P4：人物委託、遭遇、D8／D45 與超載最小切面已有四份文件契約，尚未開始實作。
- P5：開局、四類結局、歷輪摘要、跨輪重置與 UI 已拆成 P5-A～F，尚未開始實作。

## 最近完成的工作

- P5 文件 review 缺口已同步收斂至 `實作規格書.md`、`開發設計方針.md`、`測試指南.md`、`data/SCHEMA.md`：
  - `advance_phase() -> Dictionary` 自 P4-D 升級，P5-D 固定 mode → encounter → night staging → defaults → `phase_exit` → transition validation → atomic commit 的順序；`resolve_night_advance()` 於 P5-D 退場。
  - D45 coda 改由 beat `phase_exit.required_slots` 資料化，不在 `main.gd` 或 beat／slot id 特判。
  - source ↔ ending 固定四組一對一配對；beat `ending` 只允許 inventory BE。
  - `EffectApply` 改採 preflight／commit；同一 action 的 effects、bookkeeping 與 ending snapshot 整批原子，雙 ending request 回 `data_conflict` 且零變化。
  - active ending、history、page ref、nullable 矩陣與 legacy checkpoint 遷移形狀已固定；壞存檔回 `invalid_save_shape`。
  - `most_invested_npc` 在 P5 未凍結前改名為 `festival_proxy_npc`；D31／D39 以 `festival_proxy_is` 讀 D29 frozen id。
  - lint 19 補 permanent lose 指向非 persistent 卡，以及每位慶典候選缺 D31／D39 內容的負向契約。

## 驗證狀態

- 本次只修改規格文件，未執行 Godot／headless 測試，也未修改 verifier 勾選。
- 已做文字層全域檢查：舊 P5 欄位名零殘留、四份文件的新 reason code／source mapping／serialization 欄位互相對齊、`git diff --check` 通過。
- 最近完整 runtime 驗證證據與 catalog 數字請讀 `PROJECT_BRIEF.md`；不要把本次文件檢查當成 P4／P5 已實作證據。

## 目前風險

- P4、P5 都仍是規格狀態；正式 JSON、runtime、fixtures 與 UI 尚未兌現本文契約。
- P5-B／C fresh boot 暫維持 legacy run，P5-D 才切 opening；分段提交時不可提早改預設而讓遊戲無法 boot。
- P5 的 effect pipeline 是跨既有入口的簽名變更；實作時必須一次盤點 `try_place()`、`choose()`、`play_beat()` 與所有 EffectApply 呼叫者，避免只有單一路徑吃到錯誤結果。
- 本專案沒有 Art Bible，也沒有 `.venv`；目前任務不涉及素材或 Python。

## 下一個任務

依 `實作規格書.md > P4-A`、`開發設計方針.md > P4-A`、`測試指南.md > P4-A` 實作人物卡、委託與 D8／D45 遭遇所需的正式資料與 SCHEMA 真值化：

- 先只做 P4-A 文件列出的資料、lint、fixture 與 headless 範圍，不提前接 P4-B runtime 或 P5。
- 動工前重新核對四份文件與 `data/SCHEMA.md`，尤其人物卡取得劇情、委託 timing、D8 response matrix、`discardable` 與 `hand ∪ knowledge` 提交集合。
- 實作者只提供測試證據，不自行修改 `測試指南.md`、`驗證後已知問題.md` 或驗收勾選。
