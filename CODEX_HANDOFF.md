# ReturnFare 交接狀態

最後更新：2026-08-28

## 目前狀態

**P1～P4 全部關門。P5-A（結局、開局與跨輪資料）的功能已經做完，但關門被擋住——測試覆蓋有洞，不是程式有錯。**

機器層目前全綠：

- `verify_data`：卡片 66／地點 48／NPC 18／beat 268／ending 4／opening 3；引用檢查 0 錯誤；Lint 1～19 全部 0 錯誤
- 全套 29 套 headless exit 0（`test_p5a` 52 條斷言全綠）
- UI sim 108 variants／85 catalog contracts／85 executed／85 completed／0 failed checks

**下一步：先做完下面「你要做的事」，P5-A 才能關門，然後才進 P5-B。**

> 跑 UI 模擬一律加 `-Background`：
> `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\ui_sim\run_ui_sim.ps1 -Background`
>
> 進度與測試數字的單一事實來源是 `PROJECT_BRIEF.md`；問題清單的單一事實來源是 `驗證後已知問題.md`。本檔只放「現在手上這件事」。

---

## 你要做的事

**任務：補回被刪掉的回歸覆蓋，收尾 K-186～K-192。只動測試與文件，不要改任何 lint 行為。**

背景：`f5cdc77` 修了 K-178～K-181 並附了 8 條回歸斷言；`2f332c7` 重寫 `test_p5a.gd` 時把那 8 條連同 `_initialize()` 的呼叫整段刪掉了，舊的第 3.6 條也一起消失，而且同一次新增的 K-182 六個檢查從頭到尾沒有測試。lint 程式碼本身完好，功能沒退化——**沒有的是守它的網**。

verifier 逐一還原修法後重跑 `test_p5a`，下列 **15 個檢查拿掉都不會有任何斷言轉紅**。這就是你要補的清單。

### 1（必做，這是關門阻斷）K-186：補回 15 條負向反例到 `tests/headless/test_p5a.gd`

被刪掉的 9 條：

| # | 反例 | 應該由誰抓到 |
|---|---|---|
| 1 | `permanent:true` 指普通卡藏在 `slots[].on_place_by_level` | lint 19 |
| 2 | `permanent:true` 指普通卡藏在 `encounter` 出口（`on_victory`／`on_failure`／`on_escape`） | lint 19 |
| 3 | `ending: ending_replaced` 藏在 `encounter` 出口 | lint 17 |
| 4 | `ending: ending_madness_be` 藏在 `encounter.rounds[].responses[].on_resolve` | lint 17 |
| 5 | `d29_pm_invitation` 三個槽都拿掉 `default_if_unresolved` | lint 18 |
| 6 | `d29_pm_invitation` 的 default 槽加上 `requires` | lint 18 |
| 7 | `d43_pm_zhou` 任一槽拿掉 `choice_requires_card` | lint 18 |
| 8 | `d43_pm_zhou` 任一槽 `accepts` 改成非 protagonist | lint 18 |
| 9 | `choice_requires_card:true` 但 `accepts` 為空（原第 3.6 條） | lint 18 |

從來沒有過的 6 條：

| # | 反例 | 應該由誰抓到 |
|---|---|---|
| 10 | `festival_proxy.mode:"fixed"` 的 `npc` 指向 `festival_proxy_eligible:false` 的 NPC | 引用檢查 |
| 11 | `festival_proxy.mode:"highest_eligible"` 的 `fallback` 指向非候選 NPC | 引用檢查 |
| 12 | `festival_proxy_is` 指向非候選 NPC | 引用檢查 |
| 13 | `endings.json` 的 `lookup_fragments.entries[].value` 指向非候選 NPC | lint 17 |
| 14 | `festival_proxy.mode` 給未知值 | 引用檢查 |
| 15 | `lookup_fragments.when_group.variant` 指向不存在的 rule id | lint 17 |

### 2（必做）補完後跑變異驗證，逐條記錄

把上面 15 個檢查逐一在 `data_loader.gd` 還原成修法前的樣子，重跑 `test_p5a`，確認**各自都有對應斷言轉紅**。

- 本次量到的基準是這 15 個全部「仍全綠」，所以任何一條沒轉紅就是還沒補到。
- `repeat.skip_to`（17.5）與組裝路徑至少一頁（17.9）已確認有覆蓋，不用重做。
- **不要只回報「測試全綠」——沒有變異記錄一樣退回。**

### 3 K-187：補齊測試指南列的剩餘負向類別

`2f332c7` 的段落標題寫「(9 類)／(13 類)／(11 類)」，那是自己的分類數，不是 `測試指南.md > P5-A` 那份清單。對照後仍缺：

- lint 17：linear ending 缺 `first_seen.pages`、缺 `repeat.pages`、壞 condition 引用、壞 effect 引用
- lint 18：opening choice 重複 id、`choice_requires_card` 與 `default_if_unresolved` 同槽並存（「accepts 空」與上面第 9 條是同一件，不重複做）
- lint 19：D29 的 `festival_proxy.fallback` 指向非候選

### 4 K-188：`data/SCHEMA.md` 補 `draft` / `draft_note`

`endings.json` 四筆 ending 已加這兩個欄位，SCHEMA 的欄位表沒有。補兩列定義，並寫明「文案定稿後移除」的退場條件。

### 5 K-192：補 `.uid`

`tests/headless/test_p5a.gd` 與 `test_p4f.gd` 都沒有配對的 `.gd.uid` 進版控（K-23／K-38 之後第三次）。跑一次 `--import` 產生後補進版控。

### 6 K-190（低，可延後）fixture 必填欄位

14 個 `tests/fixtures/broken/*/` 的 `cards.json` 缺 `loop_persistent`、`npcs.json` 缺 `festival_proxy_eligible`。目前不炸只因為用它們的測試不跑 lint 19。建議做法與取捨見 `驗證後已知問題.md > K-190`；不做也不擋 P5-A 關門，做的話請一併處理 14 份 `endings.json` 複本的同步問題。

### 完成標準

- 29 套 headless exit 0、UI sim 0 failed、`verify_data` Lint 1～19 全 0 錯誤
- **加上第 2 點那份 15 條逐條轉紅的變異驗證記錄**

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
