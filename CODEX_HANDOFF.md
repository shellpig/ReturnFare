# ReturnFare 交接狀態

最後更新：2026-08-30

## 目前狀態

**P5-F 機器層已由 verifier 關門（2026-08-30），`PROJECT_BRIEF.md` 轉 🟦。三輪 review 的 B1／B2、N1～N9、R1～R3 共十七條全數處理，已落檔為 K-223～K-236。P5-F 是 P5 的最後一個子階段，沒有 P5-G。**

**唯一未完成的是 `測試指南.md > P5-F` 最後一條 👤 人工驗收**——首輪三種 ending、正常長／短版、不上車 locked／unlocked／重見摘要、相簿／電話開局、逐字補完與翻頁、至少一次完整跨輪回場，每項附當下輪數與路徑。與 P3-F／P4-F 同狀態，只有真人玩過才能落檔。人工那條過了之後 P5 整段轉 ✅，接 i18n 管線與 P6 存檔 UI。

**下一個 implementer 任務不是 P5-F，是本檔下一節的「T-01 文案解耦」**（使用者 2026-08-30 指派，為之後大改文案鋪路）。P5-F 的人工驗收由使用者自己跑，不擋 T-01。

---

# T-01 文案解耦（implementer 待辦）

## 為什麼要做

使用者接下來要把全作文案改得更故事性。盤點結果：文案本身**沒有散落**——`data/SCHEMA.md > 可翻譯欄位清單` 已是單一權威清單，玩家可見字串集中在 `data/beats/*.json`（525 條 `text`／約 13,900 字）、`endings.json`、`cards.json`、`locations.json`、`npcs.json`、`opening_choices.json`。`subdocs/故事線/` 是設計層不是第二份台詞（實測只有 12% 的 beat 台詞首句能在故事線裡找到）。

真正的阻礙是**測試直接把台詞當字面斷言**：自動掃描找到 126 處，改一句台詞就會弄紅一批跟該改動無關的測試。K-222 只講了開局標題那三處，這是同一個病的全貌。

**介面用語（`scenes/*.gd` 約 115 條硬寫中文）本次不動**——使用者明示不改，那批留給 i18n 管線（K-221 同族）。

## 起始清單怎麼來的（可重現）

用一支一次性腳本掃出來的，不進版控：對 `tests/**/*.gd` 抽出所有長度 ≥4 且含中日韓字、不含 `%` 的字串字面，逐一檢查是否原文出現在任何 `data/**/*.json` 裡。

| 測試檔 | 命中數 |
|---|---|
| `tests/ui_sim/cases/p1af_cases.gd` | 46 |
| `tests/headless/test_p5c.gd` | 30 |
| `tests/headless/test_p1f.gd` | 6 |
| `tests/headless/test_p3c.gd` | 6 |
| `tests/headless/test_p4e.gd` | 5 |
| `test_p1c_bugfix` / `test_p3d` / `test_p3e` / `p1g_cases` | 各 4 |
| `test_p1e` / `test_p3a` | 各 3 |
| `test_boot` / `test_p1g` / `test_p5d` | 各 2 |
| `test_p2b` / `test_p2c` / `test_p3b` / `test_p3f` / `test_p4c` | 各 1 |

> ⚠️ **126 是起始清單，不是工單。** 掃描有偽陽性：`assert_eq(int(run.get("day",0)), 1, "第 1 天")` 的 `"第 1 天"` 只是斷言訊息，剛好也出現在資料裡；`p1af_cases.gd:1016-1018` 是 case 自己的預期值對照表。**第一步是逐條分類，不是逐條改。**

## 核心：兩類斷言，做法完全相反

**這一節是本任務最重要的部分。搞混會把真實契約改成恆真式，正是 P5-F 三輪 review 一路在殺的那個病（K-225／K-226／K-227／K-230／K-231／K-234／K-235）。**

### A 類｜呈現契約：「UI 有沒有把資料裡那一句播出來」

長相：

```gdscript
assert_true(_has_text(tree.get_root(), "碎片散了一地"), "on_place 效果文字必須在 UI 顯示")
if lines[0] != "陳醫師溫和地解釋，說是老毛病，要多休息。":
assert_false(_has_text(tree.get_root(), "壓抑不住的衝動"), "出口 beat 的文字也不得播出")
```

驗的是「資料 → UI」這條線通不通，句子本身是什麼不重要。

**做法**：從 `Data.loader` 取出那個 beat／slot／page 的字串，再拿它去比對 UI。K-222 建議的修法就是這一招。

```gdscript
# 之前
assert_true(_has_text(root, "碎片散了一地"), "on_place 效果文字必須在 UI 顯示")
# 之後
var expected := str((slot.get("on_place", {}) as Dictionary).get("text", ""))
assert_true(not expected.is_empty(), "fixture 前提：該槽有 on_place 文字")   # 防空跑
assert_true(_has_text(root, expected), "on_place 效果文字必須在 UI 顯示")
```

**每一條都必須配一句「取出來的字串非空」的防空跑斷言。** 沒有這句的話，資料欄位改名或路徑寫錯時 `expected` 會變空字串，`_has_text(root, "")` 恆真——又生一條假綠。

否定斷言（`assert_false` / `not ... in ...`）同樣照做：取出「不該出現的那個 beat」的字串再斷言看不到，不要留字面。

### B 類｜敘事契約：「這段文案必須／不得包含某個敘事要素」

長相（`test_p5c` 那 30 條幾乎全是）：

```gdscript
_check("四十出頭" in long_text and "癌症" in long_text and "走得很快" in long_text, ...)
_check(not ("另一個你" in t0) and not ("替換" in t0), "首見 prefix 不過早揭露替換真相")
_check("她先" in t3_ajie and "癌症" in t3_ajie, "伴侶頁包含「她先」與癌症")
_check("然後是他" in t3_ajie and "同一個病" in t3_ajie, "伴侶頁包含主角同病死亡（承重線索）")
```

這些**不是**在驗呈現，是在守 K-200／K-203／K-206／K-208 拍板的敘事規則：首見不得提前揭露替換、伴侶先死、主角同病同速、proxy 回顧要排在死亡之前。

**❌ 絕對不可以改成從 `endings.json` 讀同一段文字再比對。** 那就變成拿資料驗資料的恆真式，契約等於沒了。

**✅ 做法：把敘事要素從測試搬進資料，變成可查詢的語意標籤。**

在 `endings.json` 的 page 物件上新增一個選填欄位（欄名自訂，建議 `beats`，與「劇情節拍」同義；**定案前先跟 verifier 確認欄名不與既有 `beats/*.json` 概念混淆**），值是封閉字彙的字串陣列：

```json
{
  "id": "replaced_partner_ajie_long",
  "text": "……",
  "beats": ["spouse_first_death", "same_illness", "died_early_forties"]
}
```

測試改成斷言標籤：

```gdscript
_check(page_beats.has("spouse_first_death") and page_beats.has("same_illness"),
    "伴侶頁包含「她先離世」與主角同病（K-203 承重線索）")
```

配套三件，缺一不可：

1. **封閉字彙 ＋ lint**：`data_loader.gd` 新增一條 lint，`beats[]` 的值必須來自一份寫死的合法標籤清單（放 `data_loader.gd` 常數或 `card_types.json` 同級的小檔），拼錯即 `verify_data` 轉紅。**沒有 lint 的話標籤打錯字測試會靜靜變綠。**
2. **`data/SCHEMA.md` 登記**：在 `endings.json` 小節說明這個欄位、封閉字彙、以及「它是設計契約不是文案，改文案時要維持，改敘事順序才動它」。**明確寫進「不翻譯、不抽取」那一類**（與 `note` 同級），免得 i18n 管線把它當文案抽走。
3. **順序類契約仍用索引**：K-206 那種「proxy 回顧必須排在死亡之前」是頁面**順序**，不是單頁內容。用兩個標籤在 `pages[]` 裡的索引比大小來斷言，不要塞回字面。

### 分類判準（拿不準時用這句）

> **把資料裡那句話整段換成另一句意思相同但用字全不同的文案，這條斷言應不應該還是綠的？**
>
> - 應該還綠 → A 類（驗的是通路）
> - 應該轉紅 → B 類（驗的是敘事要素），走標籤

## 執行步驟

1. **分類**：重跑掃描產生清單，逐條標 A／B／偽陽性。**分類表交給 verifier 過目再動手**——這是本任務唯一需要事前確認的關卡，改錯方向比不改更糟。
2. **A 類**：改讀資料，每條配防空跑斷言。
3. **B 類**：先跟 verifier 敲定欄名與封閉字彙，再改 `endings.json` ＋ lint ＋ `SCHEMA.md` ＋ 測試。
4. **偽陽性**：不動。在分類表註明理由即可。
5. **驗證**：全套 headless ＋ UI sim 全綠。
6. **真正的收尾證明（本任務的驗收核心）**：挑 **5 句以上**跨不同檔的台詞（至少涵蓋 `beats/`、`endings.json`、`cards.json` 或 `locations.json`），**把文字整句改寫成意思相同、用字全不同的版本**，再跑一次全套。
   - **A 類覆蓋處必須全綠**——這證明解耦真的成功。
   - **B 類契約必須仍然守住**（改寫時刻意維持敘事要素 → 綠；刻意拿掉一個要素 → 該條轉紅）。
   - 兩邊都做完再 `git checkout` 還原文案，附上改了哪五句與兩次結果。

## 不要做的事

- **不要動 `scenes/*.gd` 的介面用語**（使用者明示不改，留給 i18n）。
- **不要為了讓測試變綠而刪掉斷言。** 分不出 A／B 的條目留著並在分類表標「待確認」，交回 verifier，不要自行猜。
- **不要動 `note` 與 `_comment`**，那是開發者註解。
- **不要順手改文案。** 本任務只解耦，改文案是使用者之後的事；步驟 6 的改寫是驗證用，做完要還原。

## 交回時要附

- 分類表（126 條逐條標 A／B／偽陽性，含判準理由）
- 全套 headless ＋ UI sim 的 run id
- 步驟 6 的文案改寫實驗：改了哪五句、A 類全綠的證據、B 類正反兩向各自的結果
- 更新本檔（只增不刪 verifier 區塊，見 K-236）

### verifier 關門證據（`69158c5`）

- Headless：**33 套 exit 0**，`ALL HEADLESS TESTS PASSED!`（`test_p5f` 9 組全通過；`verify_data` Lint 1～20 全 0、45 天貪心走查通過）
- UI Sim：run `20260830-101817-705-p19044-2097d7c1`，117 variants／94 catalog contracts／94 executed／94 completed／**0 failed checks**，8 條負向反證皆以預期原因失敗
  - 此 run 取自 `36077fc`；`69158c5` 只動 `test_p5f.gd` 與本檔，UI sim 不載入這兩個檔，故未重跑。**這是依 diff 做的判斷，不是省略。**
- **K-198 的 8 行 `ERROR: clone_for_preflight: deserialize 失敗` 是第 9 組刻意注入的預期輸出**，不是回歸。P5-D 對 `test_p5d` 立的「stderr 全空」慣例不適用於本檔，`test_p5f.gd` 第 9 組檔頭已註明。

### 變異驗證（append-only，不得刪除）

> 這一節是 verifier 的證據，記錄哪些斷言真的有牙齒。**implementer 更新本檔時只增不刪。**

**第一輪（對 `36077fc`）**

| 變異 | 注入 | 結果 |
|---|---|---|
| M1（K-224 lint） | `d45_then > empty_handed` 的 `condition` 改成也要求持 `info_registry`（整組無無條件槽且不互補） | `verify_data` exit 1，命中「無無條件槽且未具可驗證之互補條件保證」 |
| M2（K-225 守衛） | 給 `d37_clinic` 掛 `on_enter.ending = ending_inventory_be` | `test_p5f` exit 1，catalog 斷言轉紅 |
| M3（K-226 否定斷言） | `d31_proxy_awei` 的 `festival_proxy_is` 改成 `ajie` | `test_p5f` exit 1，**3 條路徑**的「非目標 proxy beat 條件不成立」轉紅 |
| M4（K-230 集合覆蓋） | 從 `test_p5f` 的 `bands` 拿掉 mid 帶 | 轉紅並列出缺漏 `["uncle_mid","boss_mid","zhou_mid","none_mid"]` |
| M5（K-227 跨輪保留） | `game_state.gd` 的 `is_first_time` 硬寫 `true` | 第 2、3 輪「零扣費」轉紅 |

**第二輪（對 `69158c5`）**

| 變異 | 注入 | 結果 |
|---|---|---|
| MR1（K-231） | `deserialize()` 拿掉 `ending_history.clear()`，讓重載後殘留舊紀錄 | 「重載完成後 `ending_history` 筆數仍為 2」轉紅 |
| MR2（K-234） | `choose_opening` 的 preflight 拒絕前偷加 `run_number += 1` | 「`choose_opening` 被拒後狀態逐字無變化」轉紅 |
| MR3（K-235） | `d31_proxy_ajie` 的 `festival_proxy_is` 改成 `acai` | 3 條 ajie 路徑的**正向**斷言＋1 條 acai 路徑的**否定**斷言，四條精確對位轉紅 |

> 第一次 MR3 用了不存在的 NPC `nobody`，被 loader 的「`festival_proxy_is` 引用不存在的 NPC」lint 擋在載入階段——那條防線本身也是有效的。
>
> 八個變異每次都以 `git checkout` 還原，事後 `git status` 乾淨。

### 使用者拍板（append-only，不得刪除）

- **2026-08-30，庫存 BE（選項 b）**：`ending_inventory_be` 在 `data/beats/` 完全沒有觸發點（全 11 檔 grep 為 0），因為「被盯上」翻面成「療養通知」的資料寫法尚未存在——`cards.json` 的 `mood_watched` note 與 `ch3_d39_d45.json` D40 曝光槽的 note 都已自標。使用者拍板：**屬內容供給缺口（待決 25／26），不在 P5-F 補資料。** `實作規格書.md > P5-F` 與 `測試指南.md > P5-F` 已改成「規則層可達即可」，並新增一條「斷言 `data/beats/` 目前沒有任何 beat 帶 `ending: ending_inventory_be`」的守衛，第一輪內容補上翻面寫法時這條會轉紅提醒把資料層走通那一條加回驗收（M2 已證有牙齒）。

### 流程規則（K-236）

`69158c5` 的狀態更新曾把上面兩節整段刪除。往後：

1. implementer 更新本檔時**只增不刪 verifier 區塊與使用者拍板**；狀態改寫只動「目前狀態」開頭那段。
2. 回報 UI sim 一律附 `_qa/runs/<run_id>`，沒有 run id 的數字不可查核、不算證據。

### 三輪 review 的收斂形狀（供下一階段參考）

十七條裡有八條是同一個病：**測試是綠的，但斷言不存在、恆真、或證的不是那件事。**

- 用 `start_ending()` 直呼冒充「第一輪走通」（K-225）
- `gs.set("day",31)` 之後讀同一個欄位比自己（K-226）
- 同一圈迴圈裡自己先寫 `night_locations_seen` 再驗「不重收」（K-227）
- 自稱動態衍生、實為手抄對照表（K-230）
- `ready_checkpoint`、`snap_before` 兩個變數指派後從未被讀（K-231、K-234）
- `play_beat()` 不檢查 `condition`，正向斷言對任何值都會過（K-235）

**下一階段開工前先過這張清單**：新增斷言時問「把被驗的那段程式整個拿掉，這條會不會紅？」；宣稱「零副作用／不重收／一致」時，正向對照與前後快照比對缺一不可。

---

## P5-F 第二輪 review 待修清單（R1～R3，已全數處理）

三條全在 `tests/headless/test_p5f.gd`，可以一批修。修完只需重跑 `test_p5f`（不動資料與 UI，UI sim 與其他 32 套不受影響），再交回 verifier 做對應變異。

### R1（阻擋）｜N6 沒做，`ready_checkpoint` 是死變數

`tests/headless/test_p5f.gd:740` 指派了 `ready_checkpoint` 之後**從未被讀**。第 6 組實際測的是「`complete_ending()` 成功、回到 opening 之後再呼叫一次被拒（`not_ending`）」——這與第 2 組結尾已有的斷言是同一件事，不是新證據。

`測試指南.md > P5-F` 要的是「**同一 ready checkpoint** 重複完成只有第一個成功」，目前零證據。

**要做的**：在末頁 `can_complete == true` 時存下的那份 `ready_checkpoint`，於第一次 `complete_ending()` 成功後 `deserialize()` 回去，再完成一次，斷言：① 第二次被拒或不產生第二筆 history；② `ending_history` 筆數與第一次完成後相同；③ `run_number` 不再加。做法若與規則層現況衝突（例如重載 ready 快照在設計上就該可再完成一次），不要硬改測試遷就——把衝突寫進本檔，交由 verifier 與使用者決定契約該怎麼收。

**變異驗證**：把 `complete_ending()` 的重複保護拿掉，本條必須轉紅。

### R2（阻擋）｜第 9 組沒有任何狀態零變化斷言，`snap_before` 是死變數

`tests/headless/test_p5f.gd:878` 指派了 `snap_before` 之後**從未被讀**。函式名寫「K-198 preflight null 防禦反例與狀態零變化斷言」，但七個拒絕點只驗了 `reason_code`，沒有任何前後狀態比對。

這違反 `AGENTS.md > 實作守則 7`（「契約要求零副作用的拒絕操作，前後可序列化狀態必須逐字一致」），也沒做到第一輪交接檔 N4 明寫的「狀態逐字不變」。

**要做的**：七個拒絕點（`choose_opening`、`_settle_effects`、`EffectApply.preflight`、`acknowledge_encounter_intro`、`respond_to_encounter`、`discard_in_encounter`、`resolve_unfinished_choice_groups`）**各自**在呼叫前後取 `JSON.stringify(gs.serialize())` 逐字比對。注意每個點之間測試自己會改狀態（設 `flow_mode`、發卡、塞 `active_encounter`），所以要每點各取一次 before，不能共用開頭那一份。

**變異驗證**：讓其中一個拒絕點在回傳前先改一個欄位（例如 `run_number += 1`），本條必須轉紅。

### R3（高，非阻擋）｜B2 的正向斷言是空的

`play_beat()`（`scripts/autoload/game_state.gd:1697-1704`）只擋 unknown beat id 與非 run mode，**完全不檢查 `condition`**。所以第 4 組的「D31／D39 成功演出目標 proxy beat」不論凍結值是什麼都會過，證不到 proxy。

契約目前是被那兩條「非目標 proxy beat 條件不成立」的否定斷言守住的（M3 已證），但有一個洞：若凍結值變成第四個 NPC，`d31_proxy_ajie`／`awei`／`acai` 三個 `festival_proxy_is` 全部 false，**正負斷言會一起假通過**。

**要做的**：每條路徑補一句 `ConditionEval.eval(target_def.get("condition"), gs) == true`，把目標 beat 的條件也納入斷言。

**變異驗證**：把凍結值改成一個不存在的 NPC id，本條必須轉紅。

### 附帶兩條（不是缺陷，但要處理）

1. **`CODEX_HANDOFF.md` 第一輪修完沒更新**。`36077fc` 動了程式、資料與測試，本檔卻停在第一輪的待修清單，與實際狀態不符。本次由 verifier 補上；之後每次交回複驗前 implementer 自己更新。
2. **`test_p5f` 現在會吐 8 行 `ERROR: clone_for_preflight: deserialize 失敗 (invalid_save_shape)`**。這是 K-198 修法刻意的 `push_error`，屬預期輸出、不是回歸。P5-D 當初對 `test_p5d` 立的「stderr 全空」慣例對本檔不成立——修 R2 時順手在 `test_p5f.gd` 第 9 組的檔頭註解寫明，免得下一輪被當成新問題。

---

## P5-F 第一輪 review 待修清單（B1～N9，已全數處理於 `36077fc`）

> 保留供對照。落地與否見上方「目前狀態」的變異表。修完全部後跑：全套 headless → UI sim → 逐條變異驗證（把修改整段拿掉，對應測試必須轉紅），再交回 verifier。

### B1（阻擋，規格已改，改為補守衛測試）

`ending_inventory_be` 在 `data/beats/` 完全沒有觸發點（全 11 檔 grep 為 0）。它只能由 beat 的 `ending` 效果啟動（`data/SCHEMA.md > ending`、`scripts/autoload/game_state.gd:27` 的 `ENDING_SOURCE_PAIRS`），而翻面寫法尚未存在——`data/cards.json` 的 `mood_watched` note 與 `data/beats/ch3_d39_d45.json` D40 曝光槽的 note 都自標了這件事。

**要做的**：在 `tests/headless/test_p5f.gd` 第 1 組補一條 catalog 守衛，掃 `Data.loader.beats_by_id` 全部 beat（含 `slots[].on_place`、`choice` 分支、`encounter` 的 `on_resolve` 與三種出口、`on_enter`／`phase_exit`），斷言帶 `ending: ending_inventory_be` 的效果數為 **0**，並在斷言訊息寫明「補上翻面寫法時本條會轉紅，屆時把資料層走通那一條加回驗收」。同時把第 1 組 (c) 的註解改成「規則層可達性驗證，非資料層走通」，不要再讓輸出看起來像走完了一條真實路徑。

### B2（阻擋）

`tests/headless/test_p5f.gd` 第 4 組的 D31／D39 一致性斷言是恆真式：`gs.set("day", 31)` 之後讀 `gs.get("selected_festival_proxy_npc")` 再跟 `frozen_proxy` 比，同一個變數比自己，中間沒有任何 D31／D39 的讀取行為，結構上不可能轉紅。

**要做的**：改成走真實讀取點。D31 與 D39 都要實際 `play_beat()` 對應的 proxy beat（`d39_proxy_ajie` 那一族），從**演出結果**（beat 是否出現、選到哪一支、文字或 flag）反推使用的 proxy，而不是回頭讀同一個欄位。做不到就改用 `panel_view()`／`build_panel()` 之外的合法觀察面取證，並在註解寫清楚取的是哪一個讀取點。變異驗證：把 D29 的凍結值人為改掉，D31／D39 的斷言必須轉紅。

### N1（高）

第 5 組的「D8 首次費不重收」在同一圈迴圈裡自己先 `night_locations_seen["n_manydoors"] = true` 再驗，證的是同輪內不重收，不是跨輪保留；三張知識卡與 `night_once_beats_seen` 也都是測試自己塞進去的，不是玩出來的。

**要做的**：第 1 輪用真實入口走一次 `enter_night_location("n_manydoors")` 並斷言**確實收了** madness cost（正向對照），不手動寫 `night_locations_seen`；第 2、3 輪再進同一地點並斷言零扣費。知識卡同理，至少一張改成由真實 beat／槽產出。

### N2（高）

第 4 組的 `timeout_tie` 與 `unvisited_panel` 都沒有 `play_beat("d29_pm_invitation")`，兩條走同一條程式路徑。測試指南要的「**進面板**逾期同分」零覆蓋，六條路徑實際只有五條。

**要做的**：`timeout_tie` 改成先 `play_beat("d29_pm_invitation")` 進面板、不做選擇就 `advance_phase()` 逾期；`unvisited_panel` 維持完全不進面板。兩條的差異要能被斷言分辨（例如 beat 是否進 `beats_entered`）。

### N3（高）

K-198 修法的 8 個呼叫點中 7 個回 `data_conflict`，唯獨 `scripts/autoload/game_state.gd:2661` 的 `_plan_encounter_response()` 回空 plan，流到 `_commit_encounter_action()`（同檔 `2736`）結算 0 個 block，最後 `respond_to_encounter()` 回 **`ok: true`**。資料衝突被吞成假成功，正是 K-198 要修的形狀。

**要做的**：讓 `_plan_encounter_response()` 能表達失敗（回傳帶 `ok`／`reason_code` 的結構，或另開一個 sentinel 欄位），`respond_to_encounter()` 收到後回 `data_conflict` 且**狀態零變化**。順手檢查同族的 `acknowledge_encounter_intro()`（`2541`）與 `discard_in_encounter()`（`2796`）是否確實原子拒絕。

### N4（中）

K-198 全專案零測試覆蓋——`grep -rn "clone_for_preflight" tests/` 無任何結果。K-198 條目本身要求的「來源 snapshot 非法的最小反例」沒做。

**要做的**：補一個最小反例，讓 `serialize()` 產出的來源狀態無法通過 `deserialize()`（例如注入一筆壞 `ending_history` 紀錄或壞 variant id），驗證每一個 preflight 呼叫端都回 `data_conflict`、狀態逐字不變、且沒有洩漏未 `free()` 的 shadow 節點。fixture 必須在案例結束後完整還原。

### N5（中）

第 3 組自稱「動態衍生」，實際手抄 `["uncle", "boss", "zhou", "none"]`、三個 band 名、四個外觀 flag 與預期 variant 名；只從 `endings.json` 讀了 group 是否存在。測試指南寫的是「不手抄一份完整 ending 對照表」。

**要做的**：改成從 `loader.endings_by_id["ending_replaced"].variant_groups` 枚舉每個 group 的全部 rule id，跑完後做集合差集斷言「每條 rule 至少命中一次」，未命中就列出缺哪幾條。條件的設置可以留一張 rule id → flags 的對照，但**覆蓋完整性必須由資料枚舉決定**，資料新增 rule 時測試要自動轉紅。

### N6（中）

「同一 ready checkpoint 重複完成只有第一個成功」未覆蓋。第 6 組驗的是 opening 模式下 `complete_ending()` 被拒，不是同一份 ready 快照完成兩次。

**要做的**：在 ending 末頁、`can_complete == true` 的當下 `serialize()` 存一份 ready checkpoint，`complete_ending()` 成功一次後**重新 `deserialize()` 同一份**再完成一次，斷言第二次被拒且 history 不多一筆。

### N7（中）

第 4 組只斷言 `flow_mode == "ending"`，未斷言 `ending_id == "ending_replaced"`。測試指南要求最後一條 town 路徑必能合法進 `ending_replaced`，不能在 resolver 才因空 proxy 卡住。

**要做的**：六條路徑每條都補 `active_ending.ending_id` 斷言。

### N8（低）

K-195 修法後 `d45_then` 的 `d45_coda` 整組沒有任何無條件槽（`compare_registry` 需持卡、`empty_handed` 需不持卡）。目前兩者互補所以不會死鎖，但 `scripts/data_loader.gd` 沒有任何 lint 保證 `phase_exit.required_choice_groups` 引用的 group 恆有可用出口。

**要做的**：補一條 lint（接在既有 `required_choice_groups` 檢查後，`data_loader.gd:1618` 一帶），要求該 group 至少有一槽無 `condition`／`requires`，或整組條件在資料上可證互補。做不到靜態證明就退而求其次：只允許「恰有一槽無條件」或「明確標註已驗互補」的形狀，並補負向 fixture。

### N9（低）

兩件小事：

- `測試指南.md > P5-F` 要求「GameState 無具名 ending 分支」，實際 `scripts/autoload/game_state.gd` 的 `495`、`513`、`3140`、`3167` 仍以 `ending_id == ENDING_REPLACED`／`ENDING_REFUSE_BOARDING` 分支（P5-B／P5-D 遺留，非 P5-F 新增）。判斷「這個 ending 要不要凍結代付者」「opening_choice_id 該不該有值」應該是 `endings.json` 的欄位。**這條可留到 P6 動 endings schema 時一起收，不擋 P5-F**；但要在 `開發設計方針.md > P5-F` 明記它目前不成立，不要讓打勾掩蓋。
- `scenes/main.gd:5` 的 `ConditionEval` preload 全檔未使用，刪掉。

---

## P5-F 第一輪實作項目（`2712849`，供對照）

> ⚠️ 原標題為「實作與驗收完成項目」，但當時尚未經 verifier 複驗，兩輪 review 各開出 11 條與 3 條。標題已改為不宣稱驗收完成。


1. **K-195 後半修復（`data/beats/ch3_d39_d45.json`）**
   - 在 `d45_then > empty_handed` slot 補上 `"condition": { "not": { "has_card": "info_registry" } }`，持名冊玩家不再看到「你手上什麼都沒有」。
   - UI Sim 契約拆分為 `p5e_08a_no_registry`（無名冊走 empty_handed）與 `p5e_08b_with_registry`（有名冊 empty_handed 隱藏且比對槽可放卡），兩條皆通過。
2. **K-198 preflight null 防禦修復（`scripts/core/effect_apply.gd` & `scripts/autoload/game_state.gd`）**
   - `EffectApply.preflight()` 與 `GameState.clone_for_preflight()` 在 preflight 複本建立為 null 時回傳 `data_conflict`，防止崩潰。
3. **P5-F 專屬 Headless 整合測試（`tests/headless/test_p5f.gd`，8 組測試全通過）**
   - **Group 1（第一輪具名策略與不上車解鎖差異）**：驗證正常替換結局（`ending_replaced`）、發狂 BE（`ending_madness_be`）、庫存 BE（`ending_inventory_be`）。正常結局後不上車解鎖（`available: true`），兩種 BE 結算後不上車仍鎖定（`available: false`），皆取得知識卡 `k_i_returned`。⚠️ **庫存 BE 那一條是直呼 `start_ending()` 的規則層可達性驗證，不是資料層走通**——第一輪沒有任何 beat 帶該效果（見上方 B1）。原文寫成「成功啟動」有誤導，B1 修完後這裡要一併改寫。
   - **Group 2（連續四次結算）**：走「BE → 正常長版（首次，不可跳過） → 不上車（直接進結局，不建 run） → 正常短版（重見，可 skip 且呼叫 `skip_seen_ending()`）」。驗證 run number 遞增（1→2→3→4→5）、history 累積 4 筆、知識卡保留、opening 模式下 `complete_ending()` 冪等被拒。
   - **Group 3（正常 ending matrix 動態衍生）**：從 `endings.json` 動態求值。生計優先序 `uncle > boss > zhou > none`；驗證 4 生計 × 3 開關帶（12 種組合）全部正確映射；驗證旅館外觀 4 種狀態（sign/pipes/windows/none）；驗證伴侶 3 種狀態（ajie/awei/none）。
   - **Group 4（D29 慶典代付者六條路徑）**：驗證邀阿婕（`invite_ajie`）、邀阿薇（`invite_awei`）、不邀且阿柴最高（`invite_none_acai`）、逾期同分（`timeout_tie`）、未進面板（`unvisited_panel`）、全零 fallback（`zero_fallback`）。6 條路徑在 D29 結束後均凍結合法代付者，D31／D39／D45 ending snapshot 讀取值皆完全一致。
   - **Group 5（連續至少三輪 town run 狀態清洗與持久化保留）**：驗證跨 3 輪 run 層狀態（`delegates_used_today`, `pending_delegation_reports`, `active_encounter`, run flags）清空；meta 層狀態（`knowledge`, `night_locations_seen`, `night_once_beats_seen`, `delegation_tutorial_seen`）跨 3 輪完整保留；D8 重演不重收首次 madness cost。
   - **Group 6（Ending 快照載入續播與非法跨 mode 呼叫拒絕）**：同一 ending checkpoint 分別以「逐頁補完」與「skip 重載」完成，產生的 history 記錄欄位完全一致；在 opening 模式下呼叫 `try_place` 與 `advance_phase` 均被規則層原子拒絕（`not_run`）。
   - **Group 7（loop_persistent 魔法物品生命週期）**：正式卡片庫斷言 `loop_persistent: true` 數量為 0；以動態合成卡 `magic_ring` 驗證取得 → 跨輪恢復 → 普通 lose 下輪再現 → permanent lose 次輪不再恢復的完整生命週期。
   - **Group 8（代碼庫無舊 API 殘留）**：GameState 無舊 `end_run()`、`resolve_night_advance()`、`run_ended`；`flow_mode` 嚴格限制於 `opening`／`run`／`ending`。
4. **測試套件更新**
   - `tests/run_all_headless.ps1` 納入 `test_p5f.gd`（共 33 套 headless 測試）。
   - `tests/ui_sim/cases/p1af_cases.gd`、`tests/ui_sim/qa_contract_matrix.gd`、`tests/ui_sim/run_ui_sim.ps1` 更新為 94 條契約。

---

## 歷史狀態

**P5-E（開局與結局 UI）已完成實作與覆驗。**

1. **`scenes/ui/flow_text.gd`**
   - 擴充 typewriter 逐字播放機制：新增 `signal typewriter_completed`。
   - 新增 API：`start_typewriter(text: String, speed: float = 0.03)`、`finish_typewriter()`、`is_typewriting() -> bool`、`show_text_instant(text: String)`。
2. **`scenes/ui/opening_panel.gd` / `.tscn`（新增）**
   - 呈現故事內開局「出門前的十分鐘」。
   - 依 `GameState.opening_view()` 固定渲染 3 個選項按鈕（QA IDs: `opening_choice::take_family_album`, `opening_choice::return_missed_call`, `opening_choice::refuse_boarding`）。
   - 鎖定選項（首輪不上車）呈現 disabled，並在 `ReasonLabel` 顯示不劇透的鎖定理由（「你還沒有理由放棄這趟路。」）。
   - 點擊可用選項彈出 `ConfirmationDialog` 預覽效果（QA IDs: `dialog_confirm::opening`, `dialog_cancel::opening`），取消零副作用，確認後成功建立 run 並進入遊戲。
3. **`scenes/ui/ending_panel.gd` / `.tscn`（新增）**
   - 讀取 `GameState.ending_view()`，內嵌 `EndingFlowText` 逐字逐頁播映（節點名稱命名為 `EndingFlowText`，避免與主畫面 `FlowText` 發生全域搜尋衝突）。
   - 推進按鈕（QA ID: `ending_advance`）及點擊/鍵盤（Space/Enter）支援：打字中按一次補完全文、已 revealed 按一次翻進下一頁、末頁且 ready 按一次呼叫 `complete_ending()`。
   - 注：鍵盤與點擊在第一版其實不可達（`_gui_input` 收不到鍵盤事件、`EndingFlowText` 擋掉點擊），由 `311200f` 改走 `_unhandled_key_input` ＋ `mouse_filter` PASS 才真的接上。
   - 跳過按鈕（QA ID: `ending_skip`）：首見結局完全隱藏（visible=false）；重見同 ending id 且未 ready 時可見，點擊直接跳至資料指定的 skip 落點頁面。
4. **`scenes/main.gd` / `.tscn`**
   - 掛載 `OpeningPanel` 與 `EndingPanel`，移除舊的過渡 stub 函式。
   - 依 `GameState.flow_mode` 動態掛載與切換（`FLOW_OPENING`, `FLOW_RUN`, `FLOW_ENDING`）。
   - ending 模式下 HandBar、MapList、LocationPanel、EncounterPanel、AdvanceButton 等 run 控制項全部隱藏。
5. **`scenes/ui/location_panel.gd`**
   - `choice_requires_card: true` 的 slot 不再生成直接選取按鈕，強制玩家依持卡路徑或 fallback 選擇。
   - ⚠️ K-195 後半（`empty_handed` 無「未持 `info_registry`」條件，持卡玩家仍看得到）**未修**，已改列 P5-F。
6. **測試與 UI Sim 契約套件**
   - 擴充 `tests/ui_sim/cases/p1af_cases.gd`，新增 P5-E 專屬 8 個驗收案例（`p5e_01` ~ `p5e_08`），UI 契約總數從 85 條擴充至 93 條（含 variants 共 116 種組合）。
   - `tests/ui_sim/qa_contract_matrix.gd` 註冊 8 條 P5-E 契約及 Special Evidence tokens。
   - `tests/ui_sim/run_ui_sim.ps1` 更新契約總數檢查為 93 條。
   - 更新既有 headless 測試（`test_boot.gd`, `test_p2d.gd`, `test_p3b.gd`）適配 `EndingPanel` 與 `EndingFlowText` 節點結構。

### P5-E review 修正（`311200f`）

verifier 第一輪 review 開四個 blocker 與 N1～N12，`311200f` 處理如下（複驗確認四個 blocker 全數解除）：

- **B1／B2**：新增 `d45_evening__no_registry` 走查狀態——`make_states.gd` 讓 D13 下午改去 `d13_pm_festival_business` 自然錯過名冊，後置條件斷言 `not hand.has("info_registry")`；`p5e_08` 改吃這個狀態，真實點 `empty_handed` 並斷言進 ending。原本 `p5e_08` 用的是持卡 fixture 卻斷言「未持名冊」，方向相反。
- **B3**：`p5e_07` 原本 checkpoint 為空、停在開局畫面，而 `_texts()` 只收 `visible_in_tree`，七個 forbidden key 全是 ending 相關 → 結構性空跑。改吃 `d45_evening.json` 並先進 ending，加 `assert_true(not texts.is_empty())` 防空跑，補 `festival_proxy_is`／`ch3_coda_`／`{"has_card"`／`"condition"`。
- **B4**：`_gui_input` 的鍵盤分支移到 `_unhandled_key_input`（不需 focus）；tscn 補 `focus_mode = 2`、`EndingPanel` `mouse_filter = 0`、`EndingFlowText` `mouse_filter = 1`（PASS）；`p5e_04` 改送真實 `InputEventKey`（Space → Enter）。
- **N1～N4**：`p5e_03` 補 run 入口全面拒絕矩陣（`advance_phase`／`enter_night_location`／`try_place`／`choose`／`start_encounter`）＋ serialize 零變化；`p5e_04` 補 serialize→deserialize 保頁；`p5e_05` 補重見 `ending_replaced` 並 skip 到 `short_return`；`p5e_06` 補畫面與手牌零殘留。
- **N5～N9**：`confirm_text` 接上（`preview` 為 fallback）、`remove_child` 先於 `queue_free`、`_is_showing_ending` 移除、`finish_typewriter()` 後補 `reveal_ending_page()`、`manifest.json` 刪除並 gitignore。

### P5-E 自跑證據（實作者，非驗收）

> 以下為 `5f93cdf` 當下的自跑數字，已被上方 verifier 的 `311200f` 複驗取代，保留供對照。

- **Headless 測試套件**：全部 32 套測試全數 exit 0 通過（`tests/run_all_headless.ps1`），`ALL HEADLESS TESTS PASSED!`。
- **UI Simulation 測試套件**：全套 93 條契約（116 variants）全數 exit 0 通過（`tests/ui_sim/run_ui_sim.ps1 -Background`），`completed contracts 93, failed checks 0`（Run ID: `20260829-221358-446-p31236-587b677e`）。
- **45 天貪心走查（playthrough_greedy.gd）**：exit 0 通過，走查全程 46 次行動成功走完 45 天、結算 `ending_replaced`、回到 opening，第二輪相簿開局正常。

### P5-E 變異測試記錄

| 變異項目 | 變異內容 | 測試結果 |
|---|---|---|
| 變異 1：Skip 按鈕顯示條件反轉 | `_skip_btn.visible = not can_skip` | `p5e_05_ending_skip_seen_only` 確切轉紅（5 checks failed），還原後回綠 |
| 變異 2：開局選項鎖定狀態反轉 | `btn.disabled = false` | `p5e_01_boot_opening` 確切轉紅（1 check failed），還原後回綠 |
| 變異 3：ending 顯示 HandBar | `_route_view()` ending 分支令 `_hand_bar.visible = true` | `p5e_03_ending_isolation` 轉紅：`HandBar 在 ending 時不可見`（run `20260830-082134-376-p36380-d27d3f3b`） |
| 變異 4：補完當頁後不 return | `_on_advance_pressed()` 第一分支拿掉 `return` | `p5e_04_ending_typewriter_and_advance` 轉紅：首次輸入由 page 0 跨到 1，四個直接斷言失敗（run `20260830-082224-834-p13324-236d6fee`） |
| 變異 5：回 opening 仍顯示 EndingPanel | opening 分支令 `_ending_panel.visible = true` | `p5e_06_ending_complete_to_opening` 轉紅：EndingPanel 未隱藏並攔截後續開局操作（run `20260830-082316-177-p20032-567f50ca`） |
| 變異 6：玩家 UI 注入內部 ending id | `_MSG_ADVANCE_REVEAL = "ending_replaced"` | `p5e_07_no_internal_keys_leaked` 精確轉紅並指出該字串（run `20260830-082405-568-p68044-c7397c05`） |
| 變異 7：card-required choice 重建直選按鈕 | `if is_choice and not requires_card` 退回 `if is_choice` | `p5e_08_coda_choice_requires_card` 精確轉紅：出現禁止的 direct choose（run `20260830-082456-045-p46300-03d43432`） |

五個 K-213 變異皆已逐一還原；`rg "MUTATION K-213|DEBUG-"` 無殘留，最終全套 UI 基準為 `20260830-082633-494-p16984-bc987c65`（116 variants／93 contracts／0 failed）。

---

## 歷史狀態

**P5-D（開局、歷輪摘要與跨輪重置）已由 Verifier 完整複驗關門並轉 ✅。** 開局三選項、唯一 `complete_ending()`、history、跨輪繼承、D29 逾期預設與 `advance_phase()` 七步固定順序全部落地；`end_run()`／`run_ended`／`resolve_night_advance()` 三個舊接線同批退場。

### P5-D 實際改了什麼

**`scripts/autoload/game_state.gd`**

- fresh state 預設改為 `flow_mode = "opening"`；`signal run_ended` 與公開 `end_run()` 刪除。
- 新增 `opening_view()`／`choose_opening()`／`complete_ending()`／`resolve_unfinished_choice_groups()`，以及私有 `_reset_run_state()`／`_apply_run_initialization()`／`_build_history_record()`／`_pending_default_groups()`／`_commit_choice_default_plan()`。
- `advance_phase()` 重構為固定七步：mode gate → active encounter → 夜間停拍 → 逾期 default 純 preflight → `phase_exit` 門檻 → 目標與 ending 快照驗證 → 一次 commit。換時段那一段抽成 `_commit_phase_transition()`，是唯一改 day／phase 的地方。
- `gain_card()` 遇 `loop_persistent:true` 同步寫 meta set；`lose_card(id, permanent := false)` 只有 `permanent:true` 才移除 meta set。
- `deserialize()` 新增 `_parse_persistent_items()`：meta set 引用不存在或非 persistent 卡一律 `invalid_save_shape`，且與 flow 形狀一樣在任何 mutation 之前驗完。

**`scripts/core/effect_apply.gd`**：`lose` op 帶上 `permanent`（新增 `_entry_permanent()`），commit 時轉給 `lose_card(id, permanent)`。

**`scenes/main.gd`**：`run_ended` 接線換成 `ending_started`／`opening_started`；推進按鈕成為三種 mode 的唯一入口，夜間不再自己呼叫 sleep。**開局與結局畫面目前只有過渡 stub**（FlowText 列出選項、推進鍵確認第一個可選項；結局逐頁補完 → 翻頁 → 結算），正式面板是 P5-E 的工作。

**測試**：新增 `tests/headless/test_p5d.gd`（16 組）並登記進 `tests/run_all_headless.ps1`。`playthrough_greedy.gd` 新增測試專用 `start_fresh_run()` 與 `advance_until_phase_changes()`；走查改為走到 D45 → 進 ending → 逐頁播完 → `complete_ending()` → 停在 opening → 明示選開局才開始下一輪，D29 的過渡接線刪除。既有 P1～P5 測試把 `end_run()` 換成 `start_fresh_run()`、`run_ended` 換成 `ending_started`；`tests/ui_sim/` 的三個「新局」案例先確認開局，`p1af_32`／`p1af_33` 改走正式結算。

### P5-D 自跑證據（實作者，非驗收）

- 32 套 headless 全數 exit 0（`run_all_headless.ps1`，含新增的 `test_p5d`）。
- UI sim run `20260829-163054-101-p42092-3a277b06`：108 variants／85 catalog contracts／85 executed／85 completed／0 failed checks。
- 正式資料 `verify_data` 全綠：66 卡／48 地點／18 NPC／268 beat／4 ending／3 opening，引用 0 錯誤，lint 1～20 全 0 錯誤。
- 45 天貪心走查端到端跑通 D29 逾期預設 → 凍結代付者 → D45 `ending_replaced` → `complete_ending()` → opening → 第二輪相簿開局。

### P5-D 變異測試記錄

八個變異各自套用後跑 `test_p5d` 與 `playthrough_greedy`，還原後全綠：

| 變異 | 結果 |
|---|---|
| 拆掉逾期預設掃描 | 兩支都轉紅 |
| `complete_ending()` 不加輪數 | 兩支都轉紅 |
| 跨輪重置不清 `flags` | 兩支都轉紅 |
| `lose_card()` 忽略 `permanent` | `test_p5d` 轉紅 |
| `advance_phase()` 拿掉夜間停拍 | `test_p5d` 轉紅 |
| `gain_card()` 不寫 persistent meta | `test_p5d` 轉紅 |
| `lose` op 不帶 `permanent` | `test_p5d` 轉紅 |
| 拆掉 proxy 後置條件 | **仍全綠（唯一未覆蓋分支）** |

最後一列是已知且刻意保留的缺口：`resolve_unfinished_choice_groups()` 的「代付者必須非空且 eligible」後置條件，在 `EffectApply._resolve_festival_proxy()` 已擋掉非候選與已凍結兩種情形之後，沒有任何合法資料能讓它為真。程式碼註解已明寫這是擋 EffectApply 回歸用的第二道防線、且不宣稱已覆蓋。

### P5-D 第一輪 review 修復（2026-08-29）

Verifier 提兩個 blocker、三條非阻擋，全部已修並各自有變異證據。

**Blocker 1：`advance_phase()` 沒有在 commit 前驗證目標時段的 fixed encounter。**
第 ⑥ 步新增 `_next_phase_target()`（純函式算目標時段）與 `_due_encounter_data_error()`：把目標 day／phase 上**所有**掛 `encounter` 的 fixed beat 逐一過資料檢查，任一壞掉就回 `data_conflict` 且完整狀態零變化。這裡刻意不求值 `condition`——換時段途中的 auto_enter 效果可能才讓某個遭遇成立，「哪一個會開場」在 commit 前無法確定，能確定的是任何一個都不能是壞資料。資料檢查抽成 `_encounter_data_error()`，`start_encounter()` 改用同一份，避免兩份分歧的判斷讓「預檢過了、真的開場卻失敗」。`_check_fixed_encounter_for_current_phase()` 不再吞掉 `start_encounter()` 的失敗，改 `push_error`。

**Blocker 2：`complete_ending()` 沒有完整重驗 snapshot。**
`_build_history_record()` 第一步改成呼叫 `_parse_ending_snapshot()`——讀檔用的那份逐欄驗證（ending 專屬 nullable 矩陣、variant 合法集合、page ref 一致性、日期／時段型別）整套重跑一次，不合法就回 `data_conflict`，全部發生在 append 之前。

**K-193：規則層結算文字上不了畫面。**
GameState 新增 transient `last_choice_default_lines`（與既有三個 transient 同族，不進存檔），在第 ⑦ 步 commit 逾期預設之後、換時段之前寫入；`_commit_phase_transition()` 刻意不清它。`main.gd` 新增 `_settlement_lines()`，依規則層實際結算順序合併「逾期預設 → 強制縱慾 → 委託回報 → 自動進場」，morning／afternoon 走它，evening 與 night 各自在演出前插入逾期預設那一段。推進成功時 main.gd 不再自己渲染回傳的 lines（畫面已由 `phase_changed` 重建），只有停拍那一種自己畫。

**Persistent 邊界兩條。**
`lose_card()` 的 permanent 分支移到手牌查找之前，「本輪先普通失去、之後才永久失去」也真的斷掉跨輪繼承。`_parse_persistent_items()` 改成 set 語意：值只接受 boolean `true`，`false`／字串／數字一律 `invalid_save_shape`，不再靜默正規化。

**`.uid`**：`tests/headless/test_p5d.gd.uid` 由 `--import` 補上，headless 測試不再有缺 uid 的檔案。

**新增測試**：`test_p5d.gd` 由 16 組擴到 20 組——第 17 組（目標時段遭遇壞資料，含正向對照與還原後回綠）、第 18 組（八種 snapshot 破壞法逐一驗 `data_conflict`＋history 零污染）、第 19 組（persistent 邊界與存檔 set 型別）、第 20 組（結算文字真的走到 FlowText，含 D29 evening、D45 morning auto_enter 與合成 beat 的行動時段路徑）。

**修復後自跑證據**：32 套 headless exit 0；UI sim run `20260829-200245-959-p23404-0913928c` 為 108 variants／85 contracts／85 completed／0 failed checks。

**本輪變異記錄**（各自套用後 `test_p5d` 轉紅，還原後全綠）：拿掉 due encounter 預檢、history 不重驗 snapshot、permanent lose 又看手牌、persistent set 收 false、`_settlement_lines()` 不含逾期預設、不含 auto_enter、`_play_evening()` 不含逾期預設。

### P5-D 第二輪 review 修復（2026-08-29）

Verifier 提一個 blocker、三條非阻擋，全部已修。

**Blocker：`ending_history` 在 `deserialize()` 完全沒有驗證。**
舊路徑只要元素是 Dictionary 就 `duplicate(true)` 收下，`{"ending_id":"ending_replaced"}` 這種殘缺紀錄足以讓 `has_seen_ending()` 解鎖不上車。修法是把「結局結果那十欄」抽成 `_parse_ending_result_fields()`，讓寫入端與讀檔端共用同一份判斷——寫得進去卻讀不回來（或反過來）就是規約分歧：

- `_parse_ending_snapshot()` 改成先跑這一份，再驗它自己專屬的 `source_id`／`page_refs`／`page_index`／`page_revealed`／`ready_to_complete`。
- 新增 `_parse_history_records()`：每筆精確十欄（不多不少）、四類 ending 的 nullable 矩陣、opening／variant／proxy 引用合法、當輪知識必須真的是 knowledge 卡（`slotless` ＋ `type`）、無重複且依 `cards.json` 順序、不上車一律為空。任一筆不合法整份回 `invalid_save_shape`，且與 flow／persistent 一樣在任何 mutation 之前驗完。
- 順帶補齊寫入端：`_parse_ending_result_fields()` 現在也管 opening 引用存在與知識卡型別／順序，`_build_history_record()` 因此收斂成「驗完 → 取十欄」。

**非阻擋 1：permanent lose 的正向案例仍吐 ERROR。**
`lose_card()` 走完 permanent 分支但卡已不在手上時會落到 `push_error`。改成記下 `breaks_persistence`，在 push_error 之前 return——永久失去跨輪物品是可重演且冪等的合法終點。

**非阻擋 2：opening 拒絕矩陣缺 `data_conflict`。**
`test_p5d` 第 15 組補三例（同時有 `on_select` 與 `ending`、兩者都沒有、`on_select` 內藏 ending），各驗零變化，並在還原資料後驗同一個選項恢復可用。

**非阻擋 3：D29 凍結後追加投入的直接反證。**
第 11 組在凍結為阿薇之後把阿婕投入拉到 99，再驗 `selected_festival_proxy_npc`、D31、D39 與 ending 快照四處仍讀同一個 id。

**新增測試**：第 21 組（讀檔的 `ending_history` 逐筆驗形狀）——對照組 round trip 逐字相同、16 種壞形狀各回 `invalid_save_shape` 且完整狀態零變化、殘缺紀錄不得解鎖不上車、一好一壞整份拒絕、`ending_history` 非陣列拒絕、缺欄的舊 checkpoint 仍可讀。

**修復後自跑證據**：`test_p5d` 382 個 ok、exit 0 且 **stderr 全空**（修復前有 `lose_card: card ... not found in hand or knowledge`）；32 套 headless 全數 exit 0；UI sim run `20260829-205247-527-p3196-0dbb1b0e` 為 108 variants／85 catalog contracts／85 executed／85 completed／0 failed checks。

**本輪變異記錄**（各自套用後跑 `test_p5d`，還原後全綠）：

| 變異 | 結果 |
|---|---|
| `deserialize()` 拿掉 history 驗證的 guard | 37 個斷言失敗，exit 1 |
| 不驗 opening 引用是否存在 | 10 個斷言失敗，exit 1 |
| 知識卡不驗資料順序與重複 | 3 個斷言失敗，exit 1 |
| 知識卡不驗型別 | 5 個斷言失敗，exit 1 |
| history 不驗欄位數 | 1 個斷言失敗，exit 1 |
| 拿掉 opening 的 `on_select`／`ending` 形狀檢查 | 5 個斷言失敗，exit 1 |
| `lose_card()` permanent 分支又落回 push_error | **仍 exit 0，但 stderr 重新出現 2 行 ERROR** |

最後一列說明白：這條修的是 log 行為，GDScript 無法在同一個 process 內攔截 `push_error`，因此沒有斷言能守住它，證據是 stderr 的有無。D29 那條反證的靈敏度由既有第 10 組承擔（`{ajie:1, awei:5}` → 阿薇、`{ajie:3, awei:1}` → 阿婕，投入確實會改變結果）。

### P5-D 留給 verifier 的判斷點

- `main.gd` 的開局／結局 stub 是過渡品，`測試指南.md > P5-D` 沒有 UI 條目；正式面板與逐字節奏屬 P5-E。
- 測試工廠 `PlaythroughGreedy.setup_game_state()` 現在每個 process 正規化一次成 run mode（autoload 也可能已把 GameState 掛在 `/root` 底下），fresh boot 為 opening 這條由 `test_boot` 與 `test_p5d` 驗。
- 「備用區」在 `測試指南.md > P5-D` 的逐欄清單裡有一項，但該系統目前不存在（P2 時移出範圍），因此 `_reset_run_state()` 沒有對應欄位可清。
- 目標時段遭遇的預檢是**資料形狀檢查**，不是「這一次會不會開場」的預測；後者要等 auto_enter 效果落地才能確定，規格第 ⑥ 步要的也是壞資料攔截。
- `last_choice_default_lines` 是第四個 UI transient，與既有三個一樣不進 `serialize()`；P5-E 做正式面板時沿用同一組。

---

## P5-C 目前狀態

**P5-C（四類結局與組合後日談）已由 Verifier 完整複驗關門並轉 ✅。** 四類 ending、正常結局 4×3 生計／開關帶與組合後日談、首見／重見、逐頁門檻、resolver 壞資料與 snapshot/ref 一致性均完成；P5-C 已無已知 blocker 或非阻擋缺口。

實作者第四輪修復與自跑證據（2026-08-29）：

- **P5C-V5（Blocker 已修復：不邀時間軸修復）**：`data/endings.json` 修正 `partner_none_long` 僅敘述「他沒有結婚，一個人過完二十年。」；將主角四十出頭癌症早死移至 `uninvited_proxy` 各 NPC 條目中（`proxy_ajie_long`、`proxy_awei_long`、`proxy_acai_long`），在「很多年後的一張照片……」回顧之後接「四十出頭。癌症，走得很快。」，最後接 `long_return` 黑畫面與庇佑發動。消除主角死後又看生前照片之時間順序矛盾。
- **P5C-V6（關門測試缺口與變異已修復）**：`tests/headless/test_p5c.gd` 包含 `s1`～`s6` 獨立 3→4 邊界測試與 4 條 high 生計規則 `count_at_least.of` 的 6 條件結構斷言。完成 `s5`（M-C7）與 `s6`（M-C8）分別移除的變異測試，均精確轉紅（4 個斷言失敗，exit 1），還原後重回 exit 0。
- **P5C-V7（非阻擋已修復：存檔 Variant 與 Lookup Ref 交叉校驗）**：`scripts/autoload/game_state.gd` 的 `_parse_ending_snapshot()` 不僅驗證 3 個 variant 欄位合法性及與 `page_refs` 一致性，更擴充驗證 `lookup_fragments`：提取 lookup_value 與 `when_group`，交叉驗證必須與 snapshot 的 `festival_proxy_npc` 及 `partner_variant` 嚴格一致；若有矛盾回 `invalid_save_shape` 且狀態零變化。
- **測試與矩陣覆蓋**：`test_p5c.gd` 12 組全綠（exit 0）。
- **全套迴歸**：31 套 headless 全數 exit 0；UI sim run `20260829-141401-422-p74208-e6424f96`：108 variants／85 catalog contracts／85 executed／85 completed／0 failed checks。
- **變異記錄**：新增 M-C7（移除 s5 條件，4 斷言失敗，exit 1）、M-C8（移除 s6 條件，4 斷言失敗，exit 1）、M-C9（proxy lookup 快照矛盾，1 斷言失敗，exit 1）。

最後一筆主詞修正與自跑證據（2026-08-29）：

- `data/endings.json` 的 `proxy_ajie`／`proxy_awei`／`proxy_acai` 長版明示「至於那個走出山泉閣的人」，短版明示「那個走出山泉閣的人在四十出頭病逝」；不新增 NPC 死亡結果，也不提早揭露替換者身分。
- `test_p5c.gd` 逐一解析三位 proxy 的首見與重見共 6 個正式頁面，斷言 NPC 仍在回顧文字中，死亡主詞則精確切回走出山泉閣的人。
- `test_p5c.gd` 12 組 exit 0；31 套 headless（含 `verify_data`、greedy）全數 exit 0；UI sim run `20260829-143245-094-p36912-2d0e76af` 為 108 variants／85 contracts／0 failed checks。

Verifier 關門結論（2026-08-29，實作至 `44e1dd9`）：

- `測試指南.md > P5-C` 十一條機器／文字驗收全數打勾；`驗證後已知問題.md` 的 K-199～K-208 全數結案。
- 正常長版代表路徑（阿婕、阿薇、不邀）與兩種 BE、不上車首見／重見逐頁審讀通過；沒有缺頁、重頁、主詞錯置、互斥人生並存或提早揭露替換真相。
- 下一階段為 P5-D；P5-D 才公開 `complete_ending()`、寫 history、完成 opening 與跨輪 reset，不回頭把這些責任塞進 P5-C resolver。

## P5-B 實際改了什麼

**新檔**

- `scripts/core/ending_resolver.gd`（`class_name EndingResolver`，static）：variant 規則求值、lookup fragment 命中、page ref 組裝與反解析、`skip_to` 落點。只讀資料，不寫 GameState。
- `tests/headless/test_p5b.gd`。

**`scripts/autoload/game_state.gd`**

- 新增 flow 層：`flow_mode`（`opening`／`run`／`ending`）、`active_ending`，以及 run 欄位 `opening_choice_id`／`knowledge_at_start`／`selected_festival_proxy_npc`、meta 欄位 `run_number`／`ending_history`／`loop_persistent_item_ids`。
- `start_ending()`／`ending_view()`／`reveal_ending_page()`／`advance_ending_page()`／`skip_seen_ending()`，以及純函式 `_build_ending_plan()` 與 `_commit_ending_plan()`（公開入口與 action pipeline 共用同一份驗證）。
- `_reject_unless_run()` 掛進全部 run mutation 入口（推進、放卡、choice、委託、縱慾、遭遇五個入口、夜間進入、對位、夜間推進、演出入口）。
- `advance_phase()` 改成：mode gate → active encounter → 通用 `phase_exit` 門檻 → 一般 transition。D45 的 `end_run()` stub 退場，改由 `phase_exit` 的 `ending`／`source` 啟動 `ending_replaced`，day／phase 不動、run 不清。
- `_settle_effects()` 成為所有效果的唯一結算入口：preflight（複本模擬）→ 驗 action bookkeeping 與結局快照 → commit（effects → bookkeeping → ending）。`play_beat`／`choose`／`try_place`／`indulge`／強制縱慾／委託／委託回報／遭遇 on_resolve 與三種出口全部改走這條。
- `_check_madness_cap()` 改成啟動 `ending_madness_be`；`simulation_mode` 的複本只記錄請求。
- `serialize()` 新增 `flow` 區塊與上述欄位；`deserialize()` 改回傳 `{ok, reason_code}`，原子驗完形狀才寫入，壞形狀回 `invalid_save_shape` 且零變化；無 `flow` 的舊 checkpoint 一律遷移成 run＋active null，並以載入當下的 meta knowledge 當 `knowledge_at_start`。

**`scripts/core/effect_apply.gd`**

- `apply()` 退場，改為 `preflight(blocks, gs)`／`commit(plan, gs)`；plan 是有序 op 陣列，模擬與 commit 共用同一個 `_apply_op()`。
- `festival_proxy` 真的落地（fixed／highest_eligible 都在 preflight 求值後寫進 plan），非 Dictionary、非候選 NPC、已凍結覆寫一律 `data_conflict`（K-182 收斂）。
- `ending` 效果只提出 request，不自己呼叫 `start_ending()`；同一 action 兩個不同 request 回 `data_conflict`。

**`scripts/data_loader.gd`**：lint 17 新增「同一效果塊不得同時有 `madness` 與 `ending`」（正式資料先擋雙 request，runtime preflight 是第二道防線）。

**`scenes/main.gd`**：刪掉 `d45_then::compare_registry` 與 `jinghe_back` 硬編碼，改讀 `GameState.phase_exit_status()`；evening 是否走 coda 面板也改用通用門檻判斷，不再特判第 45 天。

## 這一階段動到的既有測試（契約變更，不是修紅）

`end_run()` 的跨輪重置在 P5-B 仍保留為 legacy API（P5-D 才由 `complete_ending()` 取代），但**發狂上限與 D45 coda 不再呼叫它**，因此下列測試改為「先驗結局狀態機、再以 legacy `end_run()` 做跨輪重置驗收」：

- `test_game_state_p1a`：D45 evening 改驗門檻未完成 → `phase_requirements_incomplete`，完成後進 ending mode 且 day／phase 不動。
- `test_p1f`：coda 與 `run_ended` 恰一次兩組。
- `test_p2d`：撞 cap 後 run 不清、四張卡留在本輪；走查結局改為 `ending_replaced`。
- `test_p3b`／`test_p4a`：撞 cap 進 ending mode，meta seen 照常保留。
- `test_p4b`（K-65）：同一筆 report 的 `madness`＋`flag` 屬於同一個動作，flag 現在會落地；跨筆 report 的迴圈中斷不變。
- `test_p4d`：K-133 改驗「結局啟動後不得再推進時段」；K-139 對照組補清 `knowledge_at_start`。
- `test_p1e`：`_reset_gs` 補清 `selected_festival_proxy_npc`（一輪只能凍結一次）。
- `test_p1d`：改用 preflight／commit 取代 `EffectApply.apply()`。
- `playthrough_greedy`／`test_p2_sim`／`test_p3f`：終局數字改在走查結束時直接取，不再依賴 `run_ended`。

## P5-B 五項必修：實作紀錄（2026-08-29 第二輪）

依使用者拍板的決定 A1／B1／C 施作，順序 5 → 4 → 3 → 2 → 1。每一項都補了負向案例與變異驗證。

### 5. 公開 `start_ending()` 只收 run 來源

`game_state.gd` 新增 `RUN_ENDING_SOURCES`（`madness_cap`／`ending_effect`／`d45_coda`）。
`_build_ending_plan()` 加第四個參數 `allow_opening_source`（預設 false），檢查點排在 source 配對之後，
因此 `unknown_ending` 仍先於 `invalid_ending_source`。P5-D 的 `_start_ending_from_opening()` 屆時傳 true 借道同一 helper。

**兩道 source 檢查刻意分開**：一道擋錯配、一道擋「配對正確但不是 run 來源」，兩道都回 `invalid_ending_source`。
`test_p5b` 第 9 組因此改成：合法成功只認前三個 run 來源，第四組在 run 中必須原子拒絕；
另用 `get_script_constant_map()` 驗第四組配對仍留在封閉表裡，供 P5-D 使用。

### 4. `deserialize()` 的 ending-specific 矩陣

依決定 C **只收 `flow`／`active_ending`**，run／meta 不做全面型別驗證（那會擋掉現有手寫 fixture）。
`_parse_ending_snapshot()` 新增：

- variant 欄有值 ⇔ 該 ending 真的有同名 variant group（讀 `endings.json`，不寫死 ending id 清單）
- 代付者：`ending_replaced` 必須是已凍結的正式候選；不上車一律 null；兩種 BE 有值就得是候選
- 不上車：`ended_day`／`ended_phase` 必須為 null，其餘三個結局必須非 null
- 不上車的 `opening_choice_id` 必須等於資料中指向它的那個開局選項（`_opening_choice_for_ending()`，不寫死字串）
- page ref 必須屬於本 ending，且全部同一個 branch（`resolve_ref` 只驗「可解析」，擋不掉指向別的 ending）
- `ready_to_complete` ⇔ 頁碼在末頁且已揭露（雙向都擋）

`flow` 的驗證本來就在任何寫入之前完成，因此決定 C 的範圍內已經是 candidate-then-commit。

### 3. 完整玩家動作的原子性

`_settle_effects(blocks, bookkeeping, pre_bookkeeping)` 新增第三個參數。`pre_bookkeeping` 是「這個動作的代價」，
先落在來源複本上（效果因此看得到扣卡、扣格、遭遇轉態），成功後才與效果一起 commit。
`_apply_bookkeeping()` 新增 `action_cost`／`lose_cards`／`indulgence_delta`／`forced_pop`／`report_removed`／`encounter_set`。

四條漏網路徑改法：

- `indulge()`：行動格、卡片（含泡湯多張）、次數併進 `pre_bookkeeping`。強度級改用「含這一次」的次數計算。
- `_settle_forced_indulgence()`：不再先 `pop_front()`，改用 `forced_pop`。結算失敗時債原樣留在 `forced_pending`。
- `_settle_pending_delegation_reports()`：不再整份覆寫 pending；每一筆用 `report_removed` 隨自己的效果一起出列。
- 遭遇：`respond_to_encounter()` 改成 `_plan_encounter_response()`（複本推演整回合）＋ `_commit_encounter_action()`。
  `on_resolve` 與同一次的出口效果併成同一批 blocks，因此雙 ending request 會被 preflight 抓到並整個動作拒絕。
  `acknowledge_encounter_intro()`／`discard_in_encounter()`／`escape_encounter()` 走同一組 helper。
  `_finish_encounter()` 與 `_settle_encounter_effect()` 因此退場。
  **`after_finish: advance_phase` 留在原子區塊外**，不讓 commit 裡跑一個可能失敗的推進。
  容量與死局判定原本跑在 `on_resolve` 之後的真狀態上；合併成單一 plan 後，複本上也要先把 `on_resolve` 套下去才判定，
  否則換回合會用錯的手牌張數算容量。這條有自己的斷言與變異（M-Z）。

### 2. D45 終局鏈成為時段生命週期（決定 A1）

- SCHEMA 新增 beat 欄位 `auto_enter`（只供 `fixed:true`）。`advance_phase()` 進時段時自動 `play_beat()`，
  順序在固定遭遇檢查之前。`d45_morning_invitation` 標上此欄，`final_day` 因此不再依賴玩家開山泉閣。
- 第二道防線：`advance_phase()` 在 `day == LAST_DAY and phase == "evening"` 一律拒絕離場。
- **Lint 20（新）**：`auto_enter` 只能掛 `fixed:true`；帶 `phase_exit` 的 beat，其 condition 依賴的每個 flag
  都必須有更早的 `auto_enter` beat 寫入。已接進 `verify_data.gd`。
- 演出文字收在 `last_auto_enter_lines`（transient UI），**目前沒有接進 `main.gd`**——見下方待辦。

### 1. D45 未持名冊的替代 coda（決定 B1）

- `d45_then` 兩槽同屬 `choice_group: "d45_coda"`：`compare_registry`（收 `info_registry`，維持 `k_already_on_list` 升級）
  ＋ 新增 `empty_handed`（`accepts: []`，**什麼都不給**：不發旗標、不發知識）。
- `phase_exit` 改成 `required_choice_groups: ["d45_coda"]`。SCHEMA 的 `phase_exit` 因此支援兩種門檻形態，
  至少一個非空；`_phase_exit_gate()` 對 choice group 查 `choices[beat::group]`。
- 比對槽補上 `choice_requires_card: true`。沒有這一條，玩家可以直接按「選擇：名冊上你自己那一格」
  在沒有名冊的情況下結算選擇組——那會多出一條看起來像比對、實際上什麼都沒升級的第三條路。
- lint 17 的 phase_exit 檢查擴充：group 引用、重複、兩種形態皆空。
- `playthrough_greedy` 的 `PRIORITY_SLOTS` 已刪除。走查現在自然錯過第 13 天的名冊，
  走空手路收尾（實測 `coda_path: empty_handed`），跨輪保留的是 `k_not_today`。

## 這一輪動到的既有測試（契約變更）

- `test_game_state_p1a`：D45 門檻改設 `choices["d45_then::d45_coda"]`；45 天時間軸測試每步先清 `active_encounter`
  （D45 afternoon 現在必定自動起遭遇）。
- `test_p1f`：`run_ended` 恰一次那組改設 choice group。
- `test_p5a`：`d45_then` phase_exit 契約改驗 `required_choice_groups`；新增 PE-4～PE-6 與 LC-0～LC-4。
- `playthrough_greedy`：知識卡斷言改成「保留的那張要對得上本輪真的走的 coda 路徑」。

## 變異記錄（第二輪 25／25 精確轉紅）

每一條都是「暫時關掉該接線 → 跑對應測試 → 確認轉紅 → 還原」，還原後基準線重跑 exit 0。

| # | 變異點 | 對應測試 | 結果 |
|---|---|---|---|
| M-A | `_build_ending_plan()` 拿掉 run-source 檢查 | `test_p5b` | exit 1（12 種錯配仍綠，只有第四組轉紅） |
| M-B | 快照 variant 矩陣失效 | `test_p5b` | exit 1 |
| M-C | 快照代付者矩陣失效 | `test_p5b` | exit 1 |
| M-D | 不上車結束日矩陣失效 | `test_p5b` | exit 1 |
| M-E | page ref 歸屬檢查失效 | `test_p5b` | exit 1 |
| M-F | page ref branch 一致性失效 | `test_p5b` | exit 1 |
| M-G | `ready_to_complete` 一致性失效 | `test_p5b` | exit 1 |
| M-H | 不上車開局選項比對失效 | `test_p5b` | exit 1 |
| M-I | 代價改回「先改真狀態再 preflight」 | `test_p5b` | exit 1 |
| M-J | 出口效果不併進同一批 blocks | `test_p5b` | exit 1 |
| M-K | `report_removed` 不生效 | `test_p5b` | exit 1 |
| M-L | `forced_pop` 不生效 | `test_p2c` | exit 1 |
| M-M | `lose_cards` 不生效 | `test_p5b` | exit 1 |
| M-N | `action_cost` 不生效 | `test_p5b` | exit 1 |
| M-O | `indulgence_delta` 不生效 | `test_p5b` | exit 1 |
| M-P | `encounter_set` 不生效 | `test_p5b` | exit 1 |
| M-Q | `auto_enter` 進場鉤子失效 | `test_p5b` | exit 1 |
| M-R | D45 evening 第二道防線失效 | `test_p5b` | exit 1 |
| M-S | `required_choice_groups` 門檻失效 | `test_p5b` | exit 1 |
| M-T | lint 20 缺寫入者檢查失效 | `test_p5a` | exit 1 |
| M-U | lint 20 時序檢查失效 | `test_p5a` | exit 1 |
| M-V | lint 20 fixed 檢查失效 | `test_p5a` | exit 1 |
| M-W | lint `required_choice_groups` 引用檢查失效 | `test_p5a` | exit 1 |
| M-X | lint「兩種門檻皆空」檢查失效 | `test_p5a` | exit 1 |
| M-Y | greedy 空手收尾路徑失效 | `playthrough_greedy` | exit 1 |
| M-Z | `on_resolve` 不套到複本（容量順序回歸） | `test_p5b` | exit 1 |

> M-E 第一輪是**假綠**：原本的「page ref 指向另一個 ending」案例把 refs 換成單一元素，
> 結果是被 `ready_to_complete` 一致性那道擋掉，不是被歸屬檢查擋掉。改成只替換其中一個 ref
> （頁數、index、revealed、ready 全部不動）之後，M-E 才真的轉紅。
> 這和第一輪 M4 是同一個病：**拒絕碼相同不代表擋的是同一道檢查。**

## 走查與 UI 為了走到結局所加的暫時接線（P5-D 要拆掉）

- `playthrough_greedy` 與 UI `full_walk`：第 29 天下午若邀請組未結算，明示呼叫 `choose(..., "invite_none")` 凍結慶典代付者。**逾期預設是 P5-D 的規則層工作**，落地後這兩段要刪。
- `playthrough_greedy` 與 UI：D45 coda 未持名冊時明示 `choose(..., "empty_handed")`。P5-D 的 `default_if_unresolved` 可以直接套在 `d45_coda` 這一組上，落地後這段也能刪。
- UI `coda_full`／`full_walk`：結局啟動後以 legacy `end_run()` 銜接第二輪。
- `make_states.gd` 的 `d45_evening`／`p4e_d45_afternoon` 走查加了同一筆 D29 決策，fixture 驗證也一併要求代付者非空。

## Verifier 關門結論

- `測試指南.md > P5-B` 已按三個公開 run source＋一個 opening 私有 source 重寫，並補入 D45、四類完整動作、nullable 矩陣與 Lint 20 證據。
- `d45_then::empty_handed` 的結構版草稿沒有新增世界規則或改寫角色命運，可供 prototype 使用；正式文案仍留內容期潤飾。
- 五項修正的程式、資料與斷言互相對齊，P5-B 規則／機器層可關門。

## P5-C 變異記錄

| 編號 | 變異點 | 預期失敗測試 | 實際結果 |
|---|---|---|---|
| M-C1 | `EndingResolver._pick_rule` 逆轉 rules 遍歷順序 | `test_p5c` (生計/修繕優先序) | 轉紅（9 斷言失敗，exit 1） |
| M-C2 | `EndingResolver.resolve` 略過 `has_seen_ending` 強制 `is_first_seen := true` | `test_p5c` (首見/重見/BE/不上車) | 轉紅（11 斷言失敗，exit 1） |
| M-C3 | `EndingResolver.resolve` 略過 lookup fragments 的 `when_group` 門控 | `test_p5c` (未邀代付片段啟用) | 轉紅（1 斷言失敗，exit 1） |
| M-C4 | `GameState._build_ending_plan` 破壞不上車快照 `ended_day` 為 1 | `test_p5c` (不上車快照 null 斷言) | 轉紅（1 斷言失敗，exit 1） |
| M-C5 | `data/endings.json` 反轉 uncle_high 開關門檻為 n: 7 | `test_p5c` (12 格生計開關帶矩陣) | 轉紅（6 斷言失敗，exit 1） |
| M-C6 | `EndingResolver._pick_rule` 移除多 fallback 防禦檢查 | `test_p5c` (Resolver 壞資料防禦) | 轉紅（1 斷言失敗，exit 1） |
| M-C7 | `data/endings.json` 移除 uncle_high 的 s5 條件 | `test_p5c` (獨立開關邊界與結構斷言) | 轉紅（4 斷言失敗，exit 1） |
| M-C8 | `data/endings.json` 移除 uncle_high 的 s6 (switch_progress_at_least) 條件 | `test_p5c` (獨立開關邊界與結構斷言) | 轉紅（4 斷言失敗，exit 1） |
| M-C9 | `GameState._parse_ending_snapshot` 移除 lookup ref 交叉驗證 | `test_p5c` (快照與 lookup ref 矛盾防禦) | 轉紅（2 斷言失敗，exit 1） |

## P5-C 第一輪 verifier 待修任務單（P5C-V1～V4）

### P5C-V1（blocker，已修）生計完全漏掉六開關帶

- **證據**：`data/endings.json` 的 livelihood 只有 `uncle`／`boss`／`zhou`／`none` 四條，只讀 `accepted_inn`／`accepted_outside_job`／`accepted_job`；沒有任何 `switch`、`switch_progress_at_least` 或 `count_at_least`。`test_p5c.gd` 同樣只排列四個生計旗標。
- **違反契約**：`實作規格書.md > 十五、結局流程／P5-C`、`開發設計方針.md > P5-C`、`data/SCHEMA.md > endings.json` 與 `subdocs/故事線/故事線_第一輪_第三章.md > 槽二：生計` 都要求同一生計再分 0–1／2–3／4–6 三個開關帶，variant id／when 必須承載結果，不另存第四個 history 欄位。
- **影響**：四條生計的 12 格人生結果被壓成 4 格。旅館應關閉／縮小／撐住／做起來，以及叔叔是否死在診所或主角手上，都不會反映本輪六個經營選擇；P5-F 的開關帶組合驗收也無法成立。
- **建議修法**：用現有 `count_at_least` 計算六個條件（`s1`～`s5` 與 `switch_progress_at_least(s6, 3)`），把每條生計展開為 high（4–6）／mid（2–3）／low（0–1）的有序 rule 與穩定 variant id；保留「叔叔 → 前老闆 → 周先生 → 皆無」主優先序，文字逐格對齊第三章 4×3 表。
- **必要反證**：測試至少各造 0、1、2、3、4、6 個開關，覆蓋四條生計共 12 格；同時成立多生計仍只取高優先者。暫時拿掉開關帶條件或把門檻反轉時，對應矩陣測試必須精確轉紅。

### P5C-V2（blocker，部分修復；殘留轉 P5C-V5）正常首見長版提早揭露核心真相且時間順序倒置

- **證據一**：`data/endings.json` 的首頁直接寫「你被留在了這裡，而另一個你……走出了山泉閣」，由旁白替玩家確認誰被留下、誰是另一個，違反企劃「第一輪只感到不對勁、不解釋替換；第二輪才知道後日談是別人的人生」。
- **證據二**：現行組裝順序是 partner → livelihood → inn → suffix；阿婕／阿薇 partner 頁已先寫她四十出頭癌逝，後面才寫生計、旅館狀態與「二十年」，與第三章長版骨架「生計 → 婚姻 → 二十年 → 她先死 → 主角死亡」相反。
- **影響**：首輪核心錯愕被直接解謎；有邀請的兩條長版後日談時間線不連貫，未通過 `測試指南.md > P5-C` 的真人閱讀條目。
- **建議修法**：首見 prefix 改成只呈現可觀察畫面，不命名原件／替換者；重見摘要可保留較明示語氣。重新安排 group／page 內容，讓四條生計與旅館狀態先落地，再播婚姻、二十年與兩次死亡；若更動 group 順序，同步修正 `data/SCHEMA.md` 的單一事實來源。不得新增 lore 或改寫既定角色命運。
- **必要驗收**：至少實播有邀阿婕、有邀阿薇、不邀三條正常長版並逐頁記錄；確認沒有「另一個你／替換者」等過早定論、沒有死亡後才倒回二十年前的順序，也沒有缺頁／重頁／空白頁。

### P5C-V3（非阻擋，已修）四類 ready-to-complete 測試實際只跑三類

- **證據**：`test_p5c.gd::_test_8_lifecycle_ready_to_complete_and_atomicity()` 的 `cases` 只有 `ending_replaced`、`ending_madness_be`、`ending_inventory_be`；不上車只驗快照與文字，沒有走 reveal／advance／skip 到 `ready_to_complete`。
- **建議修法**：opening mode 以私有 helper 建立首見與重見不上車快照，首見逐頁走到末頁才 ready，重見另驗合法 skip；揭露前與非末頁都必須 false。

### P5C-V4（非阻擋，已修）resolver 未完全兌現壞資料 `data_conflict` 防禦

- **證據**：`EndingResolver._append_pages()` 把 `null` 當合法空陣列，故 composite 必填的 prefix／suffix／variant page 欄遺失時可能繼續組裝；`_pick_rule()` 遇多 fallback 只保留第一筆。正式 JSON 目前會被 lint 17 擋住，所以不是現行玩家路徑 blocker，但與方針「引用缺漏或零／多個最終選擇回 data error」不一致。
- **建議修法**：由呼叫端區分選填容器與必填 page 陣列；必填欄缺失／錯型別直接 `data_conflict`。rule 掃描同時驗恰一個 fallback 與項目形狀，不靜默跳過壞項目。
- **必要反證**：獨立合成 loader 分別刪 prefix、刪 suffix、刪 variant page 欄、建立多 fallback，四例都必須由 resolver 本身回 `data_conflict`，不能只靠 lint 測試代勞。

### 修復後 verifier 重驗範圍

1. `test_p5c.gd` 新增上述 4×3 開關帶矩陣、不上車完成門檻與 resolver 壞資料案例，並對關鍵接線做變異驗證。
2. 逐頁閱讀正常三條代表路徑、兩種 BE 與不上車首見／重見，記錄資訊揭露與時間順序。
3. 重跑 `verify_data`、`test_p5c`、31 套以上全 headless、greedy 與 UI sim；回報當時 catalog 實際數字。
4. 全部通過後才由 verifier 更新 `測試指南.md`、`驗證後已知問題.md`、`PROJECT_BRIEF.md`，依固定流程同 turn commit＋push 關門 P5-C。

## P5-C 第二輪 verifier 待修任務單（P5C-V5～V7，2026-08-29）

### P5C-V5（blocker）阿婕／阿薇長版漏掉「她先死」的既定結果

- **證據**：`data/endings.json` 的 `partner_ajie_long`／`partner_awei_long` 現在只剩結婚與沒有小孩；共用 suffix 只寫主角四十出頭癌逝。`subdocs/故事線/故事線_第一輪_第三章.md > 尾巴：四十幾歲` 明定邀請路徑必須先播「她先，癌症」，再播「然後是他，同一個病」。
- **影響**：有邀阿婕／阿薇的兩條正常長版少掉承重線索——取走順序就是死亡順序；第三章明列的既定角色結果被省略，P5C-V2 仍未完整關閉。
- **建議修法**：維持目前 livelihood → inn → partner 的前半順序；把「二十年＋她先死」放入阿婕／阿薇的 long partner 內容，無伴侶 long 則放「二十年獨居」，移除共用 `years_passed`；共用 `long_return` 只接主角因同一病死亡與庇佑回歸。也可採其他資料形狀，但不得重新提早揭露替換真相或改角色命運。
- **必要驗收**：逐頁走阿婕、阿薇、無伴侶三條首見長版；兩條有邀請路徑都必須依序包含婚姻／無子 → 二十年 → 她先癌逝 → 主角同病死亡，無伴侶路徑不得誤播「她先」。對應文字或條件暫時拿掉時，測試必須轉紅。

### P5C-V6（關門測試缺口）六開關矩陣沒有獨立守住 s5／s6

- **證據**：`test_p5c.gd::_set_switches()` 只建立 s1 → s6 的連續集合；所有 high 邊界案例在 count=4 時已靠 s1～s4 達標。若從 livelihood rules 的 `of[]` 刪除 s5 或 s6，count=4／6 仍是 high，count=2／3 仍是 mid，count=0／1 仍是 low，現有矩陣與 M-C5 都不會證明這兩條接線。
- **影響**：正式資料目前六個條件都在，但回歸測試允許第 17 天開關或叔叔累計開關日後靜默失效；不符合專案「每條關鍵接線移除時對應測試必須轉紅」的變異保真規則。
- **建議修法**：為 s1～s6 各造一個獨立的 3→4 邊界案例——三個其他開關時為 mid，加上被測開關後必為 high；s6 必須真的以 `switch_progress.s6 = 3` 參與。可另加正式 livelihood rule 的 `of[]` 精確六條結構斷言作第二層。
- **必要反證**：分別暫時刪除 s5、刪除 s6 條件，兩次都必須讓各自專屬測試精確轉紅；還原後 targeted 與全套重回 exit 0。

### P5C-V7（非阻擋，P5-D 前置）deserialize 不驗 variant 值與 page refs 是否一致

- **證據**：`GameState._parse_ending_snapshot()` 只驗 composite 的三個 variant 欄非 null，沒有確認值是對應 `variant_groups[].rules[].id`。`livelihood_variant: "uncle"` 或任意字串可以搭配 `uncle_high` page refs 通過；P5-D 若直接寫 history，會保存互相矛盾的摘要。
- **影響**：目前沒有正式存檔 UI，正常 runtime 產出的 snapshot 正確，因此不阻擋 P5-C 玩家路徑；但 P5-D 即將把 snapshot 寫進 append-only history，屆時壞值會永久進 meta。
- **建議修法**：deserialize 由 ending 資料建立 group → rule id 集合，驗三個 variant 值存在；再驗 page refs 中各 variant group 的 rule id 與 snapshot 欄位一致。linear ending 維持三欄 null。
- **必要反證**：未知 variant id、合法但與 page refs 不同的 variant id 各回 `invalid_save_shape`，完整 serialize 零變化；合法快照往返仍逐字相同。

## 已知殘留

- K-193：✅ 已於 `1b48c8a` 接進 `main.gd._settlement_lines()`，P5-D 關門時結案。
- K-194：✅ 已於 `311200f` 結案（`d45_evening__no_registry` 自然走查狀態＋`p5e_08` 真實輸入點 `empty_handed`），verifier 2026-08-30 複驗通過。
- K-195：**前半**已於 `5f93cdf` 修（card-required 槽不再建直選按鈕）；**後半**（`empty_handed` 無「未持 `info_registry`」條件，持卡玩家仍看得到）未動，改列 P5-F。
- K-213～K-219：P5-E 複驗新增，K-213／K-214 是關門條件，明細見本檔開頭的待辦表。
- K-196：✅ `test_p5b.gd.uid`／`test_p5c.gd.uid` 已進版控。
- K-197：✅ 已於 P5-C 由 implementer 修復。
- K-198：`clone_for_preflight()` 未檢查 `deserialize()` 回傳值；下次動 preflight 時補防禦。
- K-209～K-212：✅ 均於 `ec9c56d` 結案。K-210（permanent lose 的假 ERROR）沒有斷言守得住——GDScript 無法在同一 process 攔截 `push_error`，證據是 `test_p5d` 的 stderr 全空。
- K-183：`repeat_page_ids` 尚未納入 fragment 的 `repeat_pages`；現行 `skip_to` 指 suffix，不受影響
- K-190：舊壞資料 fixture 缺 P5 新必填欄位；下次動 fixture 或 lint 19 時處理
- K-191：P5-A 首次交付的大面積 JSON 重排只記紀律，不回頭重排
- P4-E／P4-F：K-165 ①、K-175、K-176、K-177 四條低度殘留
- 人工體感：P3-F 與 P4-F 合計 8 項待真人落檔
- `lose` 的 `permanent` 與 `loop_persistent_item_ids`：✅ 已於 P5-D 接上行為（取得寫 meta set、`permanent:true` 才斷跨輪繼承、開局按資料順序恢復）。正式 catalog 的 `loop_persistent:true` 仍為 0 張，第一輪玩不到。

## 下一個最安全任務

**補 K-213 的變異證據，然後更新本檔（K-214），P5-E 即可關門。** 兩條都不動功能程式碼：K-213 是對 `p5e_03`／`04`／`06`／`07`／`08` 逐條反轉接線驗紅再還原，把結果填進上面的變異表；K-214 是把複驗 run ID 與 `311200f` 的變更寫進「目前狀態」。順手能收的非阻擋項是 K-215（恆真斷言）與 K-218（`p5e_04` 時序），都在 `p1af_cases.gd`，同一次動檔一起改。

關門後才進 P5-F 多結局與跨輪全流程驗收；K-195 後半與 K-216 的雙狀態／連點契約歸在那一階段。

> 跑 UI 模擬一律加 `-Background`：
> `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\ui_sim\run_ui_sim.ps1 -Background`
