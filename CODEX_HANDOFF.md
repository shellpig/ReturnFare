# ReturnFare 交接狀態

最後更新：2026-08-28

## 目前狀態

**P1～P4 全部關門。P5-A（結局、開局與跨輪資料）的功能、安全網與 15 項變異驗證已全數完成，等待 verifier 關門簽收。**

機器層目前全綠：

- `verify_data`：卡片 66／地點 48／NPC 18／beat 268／ending 4／opening 3；引用檢查 0 錯誤；Lint 1～19 全部 0 錯誤
- 全套 29 套 headless exit 0（`test_p5a` 62 條斷言全綠）
- UI sim 108 variants／85 catalog contracts／85 executed／85 completed／0 failed checks

**下一步：verifier 複驗簽收並關門 P5-A，進入 P5-B。**

> 跑 UI 模擬一律加 `-Background`：
> `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\ui_sim\run_ui_sim.ps1 -Background`
>
> 進度與測試數字的單一事實來源是 `PROJECT_BRIEF.md`；問題清單的單一事實來源是 `驗證後已知問題.md`。本檔只放「現在手上這件事」。

---

## 本輪完成項目與變異記錄

### 1. 故事線與單一真值修復（P1 / P2）
- **[P1] D43 周先生工作門檻修復**：`data/beats/ch3_d39_d45.json` 的 `d43_pm_zhou.say_yes` 補回 `"condition": { "has_card": "info_zhou_job" }`，防止未走 D11/D12 履歷線的玩家誤寫入 `accepted_job` 污染 `livelihood_zhou` 結局。
- **[P2] D7 單一真值契約修復**：`data/beats/ch1_d04_d15.json` 的 `d7_ambient_rejection_called` 改為 `"condition": { "opening_choice": "return_missed_call" }`，`d7_ambient_rejection` 改為 `"condition": { "opening_choice": "take_family_album" }`，嚴格遵守 SCHEMA「D7 依 opening_choice 判定」契約。

### 2. K-186：15 條負向變異測試逐條轉紅記錄

15 個關鍵檢查經獨立變異腳本逐一還原後重跑 `test_p5a.gd`，**15 / 15 項全數精確轉紅（Exit Code 1）**：

| # | 檢查項目 | 所屬驗證 | 變異注入方式 | 變異測試結果 | 捕捉之失敗斷言 |
|---|---|---|---|---|---|
| 1 | `permanent:true` in `slots[].on_place_by_level` | Lint 19 | 拿掉巢狀遞迴走訪 | **RED (Exit 1)** | `19.12 (K-186.1)` 未抓到 on_place_by_level 內的 permanent lose |
| 2 | `permanent:true` in `encounter` 出口 | Lint 19 | 拿掉 `permanent:true` 判定 | **RED (Exit 1)** | `19.13 (K-186.2)` 未抓到 encounter 出口 permanent lose |
| 3 | `ending: ending_replaced` in `encounter` 出口 | Lint 17 | 拿掉巢狀遞迴走訪 | **RED (Exit 1)** | `17.13 (K-186.3)` 未抓到 encounter 出口 ending |
| 4 | `ending` in `encounter.responses.on_resolve` | Lint 17 | 拿掉 ending 名稱合法性檢查 | **RED (Exit 1)** | `17.14 (K-186.4)` 未抓到 on_resolve ending |
| 5 | D29 invitation 缺少 `default_if_unresolved` | Lint 18 | 拿掉 `REQUIRED_DEFAULT_GROUPS` 檢查 | **RED (Exit 1)** | `18.14 (K-186.5)` 未抓到 D29 缺少 default |
| 6 | D29 default 槽帶有 `requires` / `condition` | Lint 18 | 拿掉 default 槽 blocker 檢查 | **RED (Exit 1)** | `18.15 (K-186.6)` 未抓到 default 槽帶 requires |
| 7 | D43 slot 缺少 `choice_requires_card:true` | Lint 18 | 拿掉 `REQUIRED_CARD_GROUPS` 的 card 要求檢查 | **RED (Exit 1)** | `18.16 (K-186.7)` 未抓到 D43 缺 choice_requires_card |
| 8 | D43 slot accepts 非 `protagonist` | Lint 18 | 拿掉 `REQUIRED_CARD_GROUPS` 的 accepts 檢查 | **RED (Exit 1)** | `18.17 (K-186.8)` 未抓到 D43 accepts 錯誤 |
| 9 | `choice_requires_card:true` 但 `accepts` 為空 | Lint 18 | 拿掉 empty accepts 檢查 | **RED (Exit 1)** | `18.18 (K-186.9)` 未抓到 empty accepts |
| 10 | fixed proxy 引用非 eligible NPC | 引用檢查 | 拿掉 fixed mode 的 eligibility 檢查 | **RED (Exit 1)** | `Ref-1 (K-186.10)` 未抓到 fixed 非 eligible NPC |
| 11 | highest_eligible fallback 引用非 eligible NPC | 引用檢查 | 拿掉 fallback 的 eligibility 檢查 | **RED (Exit 1)** | `Ref-2 (K-186.11)` 未抓到 fallback 非 eligible NPC |
| 12 | `festival_proxy_is` 引用非 eligible NPC | 引用檢查 | 拿掉 festival_proxy_is 的 eligibility 檢查 | **RED (Exit 1)** | `Ref-3 (K-186.12)` 未抓到 festival_proxy_is 非 eligible NPC |
| 13 | `lookup_fragments.entries[].value` 引用非 eligible NPC | Lint 17 | 拿掉 entries.value 的 eligibility 檢查 | **RED (Exit 1)** | `17.15 (K-186.13)` 未抓到非候選 NPC fragment |
| 14 | `festival_proxy.mode` 給未知值 | 引用檢查 | 拿掉未知 mode 報錯 | **RED (Exit 1)** | `Ref-4 (K-186.14)` 未抓到未知 mode |
| 15 | `lookup_fragments.when_group.variant` 指向不存在 rule id | Lint 17 | 拿掉 variant 存在性檢查 | **RED (Exit 1)** | `17.16 (K-186.15)` 未抓到壞 when_group.variant |

### 3. K-187～K-192 收尾
- **K-187**：`test_p5a.gd` 補齊 linear ending 缺 `first_seen.pages` (17.10)、缺 `repeat.pages` (17.11)、rule when 包含未知運算子 (17.12)、rule when 引用不存在 ending (17.12b)、opening choice 重複 id (18.19)、`choice_requires_card` 與 default 同槽並存 (18.20)、D29 fallback 引用非候選 (19.14)，以及引用負向區的壞 opening_choice (Ref-5)、壞 ending_seen (Ref-6)、壞 ending 效果 (Ref-7)。
- **K-188**：`data/SCHEMA.md` 補齊 `draft` 與 `draft_note` 規約與退場說明。
- **K-192**：`test_p5a.gd.uid` 與 `test_p4f.gd.uid` 補進版控。

---

## 目前風險

- **K-186 是 P5-A 關門阻斷。** K-178～K-182 共 9 個 lint 檢查現在零覆蓋，拿掉都不會有測試轉紅。
- 功能面沒有已知阻斷性缺陷；lint 程式碼與正式資料都正確。

## 已知的殘留（不擋關門，別忘了）

- **K-182 殘留**：`festival_proxy` 不是 Dictionary 時仍靜默跳過（`if v is Dictionary:` 沒有 else）。
- **K-183 殘留**：`repeat_page_ids` 沒有收 `lookup_fragments.entries[].repeat_pages`，若 `skip_to` 哪天指向 fragment 的重播頁會誤報。目前 `skip_to` 指的是 suffix page，踩不到。
- **K-191**：`d9cda37` 把四個 beat JSON 大面積重排，1,494 行 diff 裡實際內容改動占少數。不回頭改；之後動資料檔保持既有排版，要重排就獨立成純格式 commit。
- **P4-E／P4-F 低度殘留**：K-165 ①、K-175、K-176、K-177 四條。
- **人工體感**：P3-F 與 P4-F 合計 8 項待真人玩過落檔。

---

## P5-A 已完成的內容（供查閱）

資料層：`data/opening_choices.json`（3 筆）、`data/endings.json`（4 筆，含 `draft` 標示）、`cards.json` 補 `loop_persistent` 並新增 `item_family_album`／`k_i_returned`（66 張）、`npcs.json` 補 `festival_proxy_eligible`（候選精確為阿婕／阿薇／阿財）。

Beat 映射：D7 拒信雙分支、D11 相容家庭相簿、D26 修繕三選一、D29 邀請組與 `festival_proxy`（不邀槽兼任 `default_if_unresolved`，fallback 阿婕）、D31／D39 各三筆 `festival_proxy_is` 內容、D43 `leaving` 兩槽要求主角卡、D45 `d45_then` 的 `phase_exit`。

引擎層：`ConditionEval.KNOWN_KEYS` 加 `opening_choice`／`ending_seen`／`festival_proxy_is`；`EffectApply.KNOWN_KEYS` 加 `ending`／`festival_proxy`，`CARD_ENTRY_KEYS` 加 `permanent`；`DataLoader` 新增 `endings`／`opening_choices` 載入與 Lint 17～19；`verify_data.gd` 串接。

> ⚠️ `EffectApply` 只是把 `ending` 與 `festival_proxy` 收進 `KNOWN_KEYS`，`apply()` **沒有實作它們**。這符合 P5-A「不接流程」的邊界，但代表 D29 三個槽的 proxy 寫入目前是 no-op，P5-B／P5-D 必須補上。別把 lint 綠當成機制已通。
