# W1-B Godot 黃金軌跡產生器

## 範圍與來源追溯

- 日期：2026-10-31（Asia/Taipei）；branch：`main`。實作由使用者提供的工作區變更交付，本 session 以 verifier 角色完成審核、複驗與文件關門。
- 契約：`docs/web/W1實作契約.md`「三、W1-B：Godot 黃金軌跡」及共用契約的資料邊界、差分與基線管理。
- 基線來源 revision：`e1650f0c6b1948305222790115d9e1be2f6c8daa`。此 revision 含原 Godot 正式程式與資料；產生時 observer 與產生器尚未提交，不能宣稱它們已在該 revision。
- 本次一併提交的差異僅四檔：`tests/headless/playthrough_greedy.gd`、`generate_greedy_trace.gd`、`generate_greedy_trace.gd.uid`、`tools/trace/baselines/greedy-godot.json`。沒有修改正式 `scripts/`、`scenes/`、`data/` 或既有測試斷言／走法。
- 觀測差異：`run_greedy_walk` 增可選第四參數 `observer: Callable = Callable()`；在 run_start、四種 helper 結束且外層推進前、ending_started、每次 reveal／advance 後、complete 成功回 opening 後呼叫。既有三參數呼叫仍有效；complete 回傳值僅供判斷 opening_ready 接點。
- 新產生器沿用既有工廠與走查，await 初始 frame；每筆完整 `serialize().duplicate(true)`；manifest 遞迴列出全部正式 JSON，相對路徑排序、SHA-256 取原始 bytes。一般驗證不更新 expected。

## 交付

- CLI：`generate_greedy_trace.gd -- --output <path> --source-revision <rev>`；output 相對路徑以 repo 根目錄解析，也接受絕對路徑。缺參數、走查／觀測／取樣／寫檔失敗非零退出。
- 每次生成會比較觀測開關的初態、走查結果及最終 serialize，並執行結局完整性、Windows 鎖定與雙重寫檔失敗回歸自檢。
- 寫入先驗暫存內容、保存原檔備份；更名失敗時確認完整還原才刪備份。若還原亦失敗，保留原 bytes 的備份並回報其路徑。
- 正式基線：`tools/trace/baselines/greedy-godot.json`，**1,947,278 bytes**；schema_version 1、policy greedy-v1、19 份 manifest、193 筆 checkpoint。
- checkpoint 分布：run_start 1、phase_end 179、ending_started 1、ending_step 11、opening_ready 1。D45 seq 178（下午 helper 結束）／179（傍晚 helper 結束）皆為 45/evening，與 state.run 一致，不去重。
- 限制：從 start_fresh_run helper 起跑，不走正式 choose_opening，初態沒有 D1 morning auto_enter。正式開局另由 W3 驗證；本基線不代表 TS 已實作或兩引擎已對帳。

## 審核問題與修正

1. 原 writer 先刪舊檔再更名；Windows 暫存檔鎖會造成更名失敗後原檔遺失。已修為備份／還原流程。
2. 原完整性檢查只要求至少一筆 ending_step；刪除或重複取樣再編 seq 仍通過。已依本次 page_refs 驗完整 reveal／advance 序列，也攔截總筆數相同的漏採＋重採。
3. 第一版還原 fallback 未確認成功就刪備份。已改為原 bytes 回讀核對，雙重失敗保留唯一備份並回報路徑，且補可定位回歸自檢。

## Verifier 驗收證據

驗證對象為本次提交的 W1-B 程式／觀測接點與基線；最終程式在本次文件關門前已完成下列檢查，無後續程式變動，因此不重跑。

| 檢查 | 實際結果與本機證據（不提交生成檔） |
|---|---|
| 三個既有入口 | playthrough_greedy、test_p1f、test_p2d 均 exit 0；`_qa/web/w1b-final-<入口>.log` |
| 雙次生成及內部自檢 | 兩次 exit 0；`w1b-final-gen1.log`／`gen2.log`，包含觀測開關等價、結局漏採／重採／同筆數錯序與三種寫檔失敗自檢 |
| 生成結果與正式基線 | `w1b-final-run1.json`／`run2.json` 與基線完整 JSON 語意相同；193 筆，19 份 manifest 的 path／原始 bytes SHA-256 由 Node 獨立核對一致 |
| 快照與生命週期 | seq 連續、flow/run/meta 欄位完整、day／phase 與 state.run 相同；首筆未被後續狀態污染；末筆 opening_ready；D45 evening 雙取樣保留 |
| Windows 更名失敗 | 獨立鎖住暫存檔、允許寫入但阻止更名，函式回失敗且原檔完整還原；`_qa/web/w1b-recheck-write.stdout.log` |
| 雙重失敗 | `_qa/web/w1b-final-backup-probe.log`：備份原始二進位 bytes 保留、錯誤含備份路徑，probe exit 0 |
| 變異保真 | 僅在 `_qa` 程式副本繞過 restored_ok 守衛；新增自檢攔截，exit 1，既有輸出 sentinel 未被覆寫；`_qa/web/w1b-final-mutation.log` |
| 必要參數拒絕 | 缺 output exit 1；`_qa/web/w1b-review-missing-arg.log`。CLI 未變，既有證據仍有效 |
| 範圍與格式 | 只有契約允許的四個程式／基線檔案，UID 已交付；git diff --check 通過。首次 import 的額外 metadata 已清理，未混入提交 |

驗收判定：**W1-B 通過，無待修 blocker**。驗收涵蓋契約、API、完整序列化與取樣生命週期、Windows 路徑／故障保護、可重現性與回歸測試有效性；不擴大為 Godot 人工 UI、TS 遊戲規則或全分支驗收。

## 交接

- PROJECT_BRIEF 與 W1 步驟板同步標記完成；本次已獲使用者授權提交程式、基線及文件收尾。
- 下一步 W1-C 使用這份正式基線，實作 Node 比對器與必要差分測試。不得在日常測試中自動重產或覆寫 expected；需要更新基線時另行明示原因與來源。
