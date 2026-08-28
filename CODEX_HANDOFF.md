# ReturnFare 交接狀態

最後更新：2026-08-28

## 目前狀態

**P5-A（結局、開局與跨輪資料）已由 verifier 關門並轉 ✅。下一步實作 P5-B 頂層流程與結局狀態機。**

P5-A 關門證據：

- `verify_data`：卡片 66／地點 48／NPC 18／beat 268／ending 4／opening 3；引用與 Lint 1～19 全部 0 錯誤
- `test_p5a.gd`：80 個 ok／exit 0
- 全套 29 套 headless：exit 0
- UI sim：108 variants／85 catalog contracts／85 executed／85 completed／0 failed checks
- K-186：15 個關鍵檢查都有負向案例，實作者逐項變異記錄 15／15 exit 1；verifier 已逐條核對記錄與現行斷言
- D7 已讀精確 `opening_choice`；D43 周先生工作已恢復 `has_card: info_zhou_job` 履歷門檻

> 跑 UI 模擬一律加 `-Background`：
> `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\ui_sim\run_ui_sim.ps1 -Background`

---

## P5-B 下一步

依 `實作規格書.md`、`開發設計方針.md`、`測試指南.md` 的 P5-B 同名段落動工：

- 建立 `opening`／`run`／`ending` 頂層 mode 與固定序列化形狀
- 實作 `start_ending()`、ending snapshot、逐頁 reveal／advance／skip 與封閉拒絕矩陣
- ending mode 立即封鎖所有 run mutation；拒絕完整序列化零變化
- `EffectApply` 進入兩階段 preflight／commit；同一 action 的不同 ending request 衝突要原子拒絕
- D45 `phase_exit`、發狂 cap、inventory effect、opening choice 四種 source ↔ ending 配對接入同一入口
- P5-B 仍不接正式畫面；opening 真初始化與跨輪清理留 P5-D，UI 留 P5-E

## 已知殘留

- K-182：`festival_proxy` 非 Dictionary 時仍靜默略過；不擋 P5-A，P5-B／D 實作 preflight 時應一併收斂
- K-183：`repeat_page_ids` 尚未納入 fragment 的 `repeat_pages`；現行 `skip_to` 指 suffix，不受影響
- K-190：舊壞資料 fixture 缺 P5 新必填欄位；下次動 fixture 或 lint 19 時處理
- K-191：P5-A 首次交付的大面積 JSON 重排只記紀律，不回頭重排
- P4-E／P4-F：K-165 ①、K-175、K-176、K-177 四條低度殘留
- 人工體感：P3-F 與 P4-F 合計 8 項待真人落檔

## 文件狀態

- `測試指南.md > P5-A`：11 條全打勾，附 verifier 關門證據
- `驗證後已知問題.md`：K-184／K-186／K-187／K-188／K-192 結案
- `PROJECT_BRIEF.md`：P5-A 轉 ✅，下一步改為 P5-B
