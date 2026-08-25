# 資料格式

> 本檔描述 `data/` 底下所有 JSON 的欄位。**所有可調數值只住這裡，文件不存數值**（見 `AGENTS.md > 文件分工與單一事實來源`）。
>
> 引擎讀到這些欄位之後**必須做什麼**，住 `實作規格書.md`；本檔只管欄位定義與資料規約。

## id 的穩定性規約（i18n 前置）

`id` 是翻譯的定位鍵。抽取工具從既有結構生 key——`beat_id.slot_id.on_place.text`——所以 **id 改名＝翻譯記憶對不上，要人工重接**。

| 時期 | 規則 |
|---|---|
| **i18n 管線建好之前**（現在） | `id` 可以自由改名。改完跑 `verify_data` 確認引用沒斷即可 |
| **i18n 管線建好之後** | `beats[].id`、`slots[].id`、`cards[].id`、`locations[].id`、`npcs[].id`、`opening_choices[].id`、`endings[].id` 與所有 ending page／variant id **全部凍結**。要換語意就新增一個 id，不改舊的 |

管線的排程住 `開發設計方針.md > Phase 分期總表`（P5 之後、P6 之前）。**在那之前不必為了將來凍結而綁手綁腳**——這一條寫在這裡是為了讓凍結那天有明確的界線，不是現在就生效。

> 已知會踩到的一類：`beats[].id` 帶時段前綴（`d27_pm_*`）。時段改了就得改名，例如 2026-08-13 的 `d27_pm_awei_confirm` → `d27_evening_awei_confirm`。**凍結之後這種改名不再允許**，屆時 id 只是識別碼，不保證與 `when.phase` 一致。

### 可翻譯欄位清單

抽取工具要拿走的就是這些。**新增資料檔時，玩家看得到的字串一律登記在這裡**，不要為單一檔案另立一套翻譯鍵——兩種做法會讓抽取工具要寫兩份。

| 檔 | 可翻譯欄位 |
|---|---|
| `cards.json` | `name`、`text` |
| `locations.json` | `name`、`desc` |
| `npcs.json` | `name`、`locked_name` |
| `card_types.json` | `name` |
| `beats/*.json` | `title`、`text`、`slots[].label`、`slots[].reject_reason`、`reject_reason`、`echo.text`、`on_enter.text`、`on_place.text`、`slots[].delegation.preview`、`slots[].delegation.tendency`、`slots[].delegation.report.text`、`encounter.rounds[].demand`、`encounter.rounds[].responses[].on_resolve.text`、`encounter.rounds[].fallback.on_resolve.text`、`encounter.on_victory.text`／`on_failure.text`／`on_escape.text` |
| `opening_choices.json` | `label`、`preview`、`confirm_text`、`reject_reason`、`on_select.text` |
| `endings.json` | 所有 `pages[]`／`*_pages[]` 內的 `text` |

`note` 與 `_comment` 是給開發者看的，**不翻譯、不抽取**。

現階段這些欄位就直接寫中文，跟現有檔一致；i18n 管線上線時一次抽走，不需要事先改形狀。

## 核心概念：一切都是卡槽

UI 是蘇丹式的——**最底下一排是你的手牌，上方是地圖，點開一個地點就打開它的面板，面板裡是一排卡槽。**

槽有兩種內容：**已經在場的人事物**（occupant，你不能動），以及**空槽**（你可以放卡進去）。

放什麼卡，意思就不一樣：

| 你放進去的 | 意思 |
|---|---|
| **主角卡** | 把這個時段花在這裡 |
| **人物卡（不放主角卡）** | **委託**——他去，你沒去（第一次取得人物卡後可用） |
| **道具卡／情報卡** | 使用這張卡 |
| **情報卡／知識卡放進不收主角卡的槽** | **比對**——見下 |
| **發狂卡** | **縱慾**——在這裡發洩，消掉這張卡 |

> **這一條讓三個子系統收斂成同一個資料結構。**
> **遭遇**＝一個會拒收並吃掉卡、而且每回合多佔你一格手牌的面板。
> **縱慾**＝把發狂卡拖進接受它的槽。
> **委託**＝放人物卡但不放主角卡。
>
> 沒有第二套介面、沒有戰鬥系統、沒有縱慾選單、沒有委託系統。

## 三態可見性（硬規則）

企劃書第十七節：**看不到的路等於不存在。** 每個槽一定是三態之一：

| 態 | 條件 | 呈現 |
|---|---|---|
| 不顯示 | `condition` 不成立 | 槽根本不存在（留給下一輪） |
| **灰掉＋理由** | `condition` 成立但 `requires` 不成立 | 槽顯示、點不下去、附一行 `reject_reason` |
| 可選 | 兩者都成立 | 可放卡 |

判定順序與求值時機：`實作規格書.md > 卡槽三態`。

> **`reject_reason` 要指向缺的那樣東西，不能指向答案。**
> ✅「你手上沒有他一定會記得的事。」
> ❌「你第 3 天沒有陪他搬貨。」——這等於報答案，而且會讓玩家去查攻略。

---

## `tuning.json`

全部可調數值。改這裡不用動任何文件。

| 欄位 | 說明 |
|---|---|
| `hand_size` | 手牌格數（企劃書第三節，暫定 14） |
| `madness_cap` | 發狂卡上限，達到即發瘋 BE |
| `madness_countdown_days` | 每張發狂卡的倒數天數 |
| `madness_vision_threshold` | 桌上幾張發狂卡才看得見某些東西 |
| `reserve_capacity` | 備用區容量，`null` ＝ 無上限 |
| `phases_per_day` | 每天幾個行動時段（夜不算） |
| `indulgence.soak_phase_cost` | 泡湯吃掉幾格（其他出口都是 1） |
| `indulgence.soak_cards_cleared` | 泡湯清掉幾張 |
| `indulgence.forced_light_count` | 本輪前幾次強制縱慾放輕 |
| `indulgence.forced_normal_until` | 第幾次之後開始加碼並改挑最重的出口 |

### 比對

**沒有比對表。比對就是一個 `accepts` 不含 `protagonist` 的槽。**

因為不收主角卡，所以**不吃行動格**（企劃書第三節：罰他去比對等於罰他動腦）。成本是**你人得在那裡**。

三種形態共用同一個結構，差別只在 `accepts` 寫什麼：

```json
{ "id": "compare_years", "label": "把五個名字排在一起看",
  "accepts": ["info_forty_something"],
  "requires": { "has_card": "info_forty_something" },
  "reject_reason": "（你沒有抄過那些名字。）",
  "on_place": { "gain": ["k_forty_something"] } }
```

- **情報 × 情報** —— `accepts` 兩張以上
- **情報 × 槽上的 occupant** —— occupant 就是比對的另一邊（第 22 天阿財、第 39 天照片）
- **知識卡 × 新情報 → 升級的知識卡** —— `accepts` 收知識卡，`on_place` 產出升級版並移除舊的

> 知識卡不佔格，所以它永遠在手上，隨時可以拖過去——第三種形態因此特別順。

#### ⚠️ 不收主角卡的槽，必須跟一個收主角卡的槽在同一個面板裡

否則時段的稀缺性會破功：一個下午可以把三個不同地點的卡都打出去。

**判準：這個動作需不需要移動？**

| 情況 | 怎麼寫 |
|---|---|
| **你已經在那裡**（同一個面板裡另一個槽吃掉了你的主角卡） | `accepts` 不含 `protagonist` → 免費 |
| **需要走過去** | `accepts: ["protagonist"]`，需要的卡寫進 `requires` 當門檻，**不是**寫進 `accepts` |

例：第 9 天納骨塔的「把五個名字排在一起看」免費，因為同一個面板的「算生卒年」已經吃掉主角卡。
第 14 天「拿那個名字去問春阿嬤」要收主角卡，因為那是一趟路——`info_a_name` 只是門檻。

### 縱慾出口

**出口不是獨立資料，就是某些地點的卡槽 `accepts` 裡有 `madness`。** 沒有縱慾選單。

六個出口見企劃書第七節；強制縱慾的挑選演算法、無條件出口保底、泡湯特例：`實作規格書.md > 發狂時鐘與縱慾`。出口的實際落點見 `開發設計方針.md > P2-B`，資料住 `data/beats/indulgence_exits.json`。

`accepts` 含 `madness` 的槽多兩個欄位（P2）：

```json
{ "id": "x_smash", "label": "砸東西",
  "accepts": ["madness"],
  "condition": { "madness_at_least": 1 },
  "indulgence": { "weight": 1 },
  "on_place": { "text": "……", "flag": { "inn_damaged": true } },
  "on_place_by_level": {
    "normal": { "relation": { "npc": "uncle", "delta": -1 } },
    "heavy":  { "relation": { "npc": "uncle", "delta": -2 } }
  } }
```

| 欄位 | 說明 |
|---|---|
| `indulgence.weight` | 代價權重，整數，越大越重。**強制縱慾挑條件成立的出口中權重最大的那個**；同分取資料順序第一個（決定論，不得引入亂數） |
| `indulgence.auto` | 選填，預設 `true`。`false` ＝**永不進強制挑選池**。全作只有泡湯是 `false` |
| `indulgence.soak` | 選填，預設 `false`。`true` ＝套泡湯特例：只在 morning 發動、吃 `tuning.indulgence.soak_phase_cost` 格、清 `soak_cards_cleared` 張。**數值住 `tuning.json`，本欄只標身分** |
| `on_place_by_level` | 選填。強度級的**追加**效果，鍵只能是 `light` / `normal` / `heavy`，值的內部鍵同 `on_place`。**基底 `on_place` 照常先套，再套當次那一級**；缺級＝該級無追加 |

> **為什麼是「基底＋追加」不是三份完整替換。** 企劃書第七節寫的是副作用**疊加**；三份替換會讓內容期改一句文字要改三處，而且看不出三份之間差在哪。

> **`condition` 用 `madness_at_least: 1` 而不是留白**：手上沒有發狂卡的玩家不需要看到「砸東西」這一格。這是三態裡「不顯示」那一態的正當用法——他不缺鑰匙，他只是還沒有那張卡。

### 常駐白天 beat（`when.day_from` / `day_to`）

縱慾出口是地點的**常駐設施**，不是某一天的事件——但 `when.day` 綁死單日，寫 45 份複本不可行。所以 `when` 支援第二種寫法：

```json
{ "when": { "day_from": 1, "day_to": 45, "phase": ["morning", "afternoon"] } }
```

| | |
|---|---|
| `day` 存在 | 舊寫法，只在那一天成立。**故事 beat 一律用這個** |
| `day` 不存在、`day_from` / `day_to` 存在 | 區間內每一天的該時段都成立。`day_from` 預設 1、`day_to` 預設 45 |
| `phase` | 可以是字串或字串陣列。陣列＝這幾個時段都成立 |

> **兩種寫法不得混用在同一個 `when` 裡**（有 `day` 又有 `day_from` ＝資料錯誤）。
>
> **為什麼不另開一個 `data/indulgence_exits.json` 頂層檔**：出口要走的是同一套 beat／槽／三態／`on_place` 機制，另開檔等於多一條解析路徑，而它們的差別只有「哪幾天成立」這一件事。擴 `when` 只動一個判斷式。

## `opening_choices.json`（P5）

故事內「出門前的十分鐘」選項，頂層是**有序陣列**。正式資料恰三筆，順序本身就是 UI 順序：

```json
[
  {
    "id": "take_family_album",
    "label": "帶上父母留下的舊相簿",
    "preview": "……",
    "confirm_text": "……",
    "on_select": { "gain": ["item_family_album"] }
  },
  {
    "id": "return_missed_call",
    "label": "回撥那通未接來電",
    "preview": "……",
    "confirm_text": "……",
    "on_select": { "flag": { "outside_job_waiting": true } }
  },
  {
    "id": "refuse_boarding",
    "label": "不上車",
    "preview": "……",
    "confirm_text": "……",
    "requires": { "ending_seen": "ending_replaced" },
    "reject_reason": "你還沒有理由放棄這趟路。",
    "ending": "ending_refuse_boarding"
  }
]
```

| 欄位 | 規約 |
|---|---|
| `id` | 全檔唯一。正式三 id 與順序如上 |
| `label` | 選項列文字 |
| `preview` | 確認前的故事預覽，不揭露完整結果 |
| `confirm_text` | 確認按鈕／提示文字 |
| `requires`／`reject_reason` | 選填；不成立時選項仍顯示但鎖定。語彙同 condition；有 requires 必須有理由 |
| `on_select` | 成功後初始化 run 再套的效果；形狀同 `on_place` |
| `ending` | 不初始化 run，直接啟動的 ending id |

每筆必須在 `on_select` 與 `ending` 中**恰有一個**。opening choice 不用 `condition` 隱藏；特別是「不上車」永遠可見，只由 `requires` 灰掉。`on_select` 不得再內藏 `ending`，避免同一選項有兩個結算入口。

## `endings.json`（P5）

頂層是有序陣列，正式資料恰四筆：`ending_replaced`、`ending_madness_be`、`ending_inventory_be`、`ending_refuse_boarding`。ending id 是內部穩定鍵，不直接顯示給玩家。

### 共用 page

```json
{ "id": "outside_years", "text": "……" }
```

- 同一 ending 內所有巢狀 page id 全域唯一；不能因 first／repeat 分支不同就重複。
- `text` 必填且非空，是可翻譯欄位。顯示順序只由所在陣列決定。
- runtime page ref 由 ending id、容器路徑與 page id 組成；存檔存 ref，不存中文全文。

### `kind: "linear"`

BE 與不上車使用線性形狀：

```json
{
  "id": "ending_refuse_boarding",
  "kind": "linear",
  "first_seen": {
    "pages": [
      { "id": "outside_years", "text": "……" },
      { "id": "early_death", "text": "……" }
    ]
  },
  "repeat": {
    "pages": [
      { "id": "outside_summary", "text": "……" },
      { "id": "return_again", "text": "……" }
    ],
    "skip_to": "return_again"
  }
}
```

`first_seen.pages` 與 `repeat.pages` 都必須非空。`repeat.skip_to` 必填：值為 repeat 分支內必達的 page id，或字面值 `"complete"`；首見永遠不可整段跳過，所以 first_seen 沒有 skip 欄位。

### `kind: "composite"`

正常替換結局用組合形狀，不為每個人生排列建立 ending id：

```json
{
  "id": "ending_replaced",
  "kind": "composite",
  "first_seen": {
    "prefix_pages": [{ "id": "replacement", "text": "……" }],
    "suffix_pages": [{ "id": "long_return", "text": "……" }]
  },
  "repeat": {
    "prefix_pages": [{ "id": "again", "text": "……" }],
    "suffix_pages": [{ "id": "short_return", "text": "……" }],
    "skip_to": "short_return"
  },
  "variant_groups": [
    {
      "id": "partner",
      "history_field": "partner_variant",
      "rules": [
        {
          "id": "ajie",
          "when": { "flag": "invited_ajie" },
          "first_seen_pages": [{ "id": "partner_ajie_long", "text": "……" }],
          "repeat_pages": [{ "id": "partner_ajie_short", "text": "……" }]
        },
        {
          "id": "none",
          "fallback": true,
          "first_seen_pages": [{ "id": "partner_none_long", "text": "……" }],
          "repeat_pages": [{ "id": "partner_none_short", "text": "……" }]
        }
      ]
    }
  ],
  "lookup_fragments": [
    {
      "id": "uninvited_proxy",
      "when_group": { "group": "partner", "variant": "none" },
      "source_field": "most_invested_npc",
      "entries": [
        {
          "value": "ajie",
          "first_seen_pages": [{ "id": "proxy_ajie_long", "text": "……" }],
          "repeat_pages": [{ "id": "proxy_ajie_short", "text": "……" }]
        }
      ]
    }
  ]
}
```

組裝順序固定為：當次分支的 `prefix_pages` → `variant_groups` 陣列順序中各組命中的 pages → 成立的 `lookup_fragments` 陣列順序 → `suffix_pages`。first_seen 只在 history 尚無同 ending id 時使用；其餘使用 repeat。

| 結構 | 規約 |
|---|---|
| `variant_groups[].id` | `ending_replaced` 正式資料恰有 `partner`、`livelihood`、`inn_appearance`，順序就是後日談順序 |
| `history_field` | 三組分別寫 `partner_variant`、`livelihood_variant`、`inn_appearance_variant`，不得重複 |
| `rules[]` | 依序第一個 `when` 成立者命中；最後恰一筆 `{fallback:true}`，fallback 不得同時有 when |
| `rules[].id` | 寫入 history 的穩定 variant id；同組唯一 |
| `first_seen_pages`／`repeat_pages` | 皆必填陣列，可為空但欄位不可省略 |
| `lookup_fragments[].when_group` | 只在指定 group 命中指定 variant 時啟用；group／variant 必須存在 |
| `source_field` | P5 封閉值只有 `most_invested_npc` |
| `entries[].value` | 對該 source 的完整映射；`most_invested_npc` 必須覆蓋所有 `festival_proxy_eligible:true` 的 NPC |

`when` 使用同一套 condition 語彙。規則重疊是合法的，因為順序承載優先權；lint 只保證 fallback 與引用完整，不假裝能證明兩個任意條件永不重疊。正式 livelihood rules 的順序必須先叔叔、再前老闆、再周先生、最後皆無；各路線與開關帶的組合直接反映在 variant id／when，不另存第四個 history 欄位。

## `cards.json`

| 欄位 | 說明 |
|---|---|
| `id` | 唯一鍵 |
| `type` | 見下表 |
| `name` | 卡面名稱 |
| `text` | 卡面說明 |
| `slotless` | `true` ＝ 不佔手牌格（只有 `knowledge`） |
| `discardable` | **必填 boolean**；遭遇錯答消耗、主動丟棄與逃離支付的唯一真值，不得由 `type` 猜測 |
| `stashable` | 可否放進備用區 |
| `loop_persistent` | **P5 起必填 boolean**；極少數真正穿越時間的魔法物品為 true。一般物品即使劇情重拿也填 false |

`type`：`protagonist` / `person` / `group` / `equipment` / `consumable` / `info` / `inference` / `document` / `knowledge` / `mood` / `madness` / `routine`

> `protagonist` 不可丟棄、不可寄放，但**可以放置**——放它就是花掉那個時段。
> `knowledge` 不佔格，整個集合跨迴圈繼承；這不是 `loop_persistent`，兩者不可混用。
> `madness` 不可丟棄、不可寄放，只能靠縱慾消掉。
> **除 `madness` 外，所有卡都是 unique**：重複取得＝no-op（gain 冪等），不會出現第二張。`madness` 是唯一的多實例卡。堆疊卡等真需求出現再開欄位（規格書第三節）。

`loop_persistent:true` 只可用於 `slotless:false`、unique、非 protagonist、非 madness 的卡。取得時寫入 meta persistent set；每輪開局按 cards 資料順序恢復。所有可能同時恢復的卡加 protagonist 不得超過 `tuning.hand_size`。P5 第一輪正式資料全部為 false；機制只用合成 fixture 驗證。

### 夜間對位知識卡（P3）

- 每個 distinct `locations.json > night[].day_counterpart` 恰好一張 knowledge 卡；多個夜間 row 指向同一白天地點時共用同一張。
- 卡名只陳述「夜裡可以走回該白天地點」，`text` 可描述白天與夜裡是同一座鎮，但**不得列出同地點下尚未到訪的其他夜間分區**。
- 對位卡只由 `night_reveal` 引用；實際 id、名稱與文字住 `cards.json`，其他文件不複製映射表。

## `card_types.json`

卡片型別的顯示名。**卡槽用它告訴玩家「這一格收什麼」**（規格書第五節、P1-G）。

| 欄位 | 說明 |
|---|---|
| `id` | 型別鍵，必須是 `cards.json` 的 `type` 用得到的值 |
| `name` | 顯示名。**沿用企劃書第三節的卡種用語，不另創詞**（可翻譯欄位） |
| `note` | 給開發者的備註，不翻譯 |

- **雙向封閉**：`cards.json` 用到的每個 `type` 都要在本檔有一筆；本檔每一筆的 `id` 也要是合法型別。缺任一邊＝資料錯誤（lint 9）。
- 本檔目前有 12 筆，比 `cards.json` 實際用到的 10 種多兩筆（`group`、`consumable` 第一輪還沒有卡）。**這是刻意的**——型別詞彙表跟隨企劃書，不跟隨當下有沒有卡。
- **不要在本檔放規則**。「知識卡不佔格」「發狂卡不可丟棄」這些住企劃書第三節與 `cards.json` 的欄位；本檔只有顯示名。

> `document` 的名字是「書籍／文件卡」，本身含斜線。**多型別槽串接顯示時用「、」不要用「／」**，否則會讀成三個型別。

## `locations.json`

> `desc` 是 P1-G 新增的欄位：**玩家進到這個地點看到的地方描述**，在 beat 依序演出結束後常駐顯示（規格書第四節）。與 `note` 分開——`note` 是給開發者的，不翻譯、不進畫面。48 個地點的 `desc` 文字尚未填，引擎缺欄位時退回只顯示 `name`。

| 欄位 | 說明 |
|---|---|
檔案分 `day` / `night` 兩組，id 全域唯一。

| 欄位 | 說明 |
|---|---|
| `id` / `name` | `name` 是地點外部可觀察的名稱。night row 在對位前把它當引子顯示，不可直接寫進場後才知道的結果 |
| `phases` | 開放時段：`morning` / `afternoon`（白天地點用） |
| `layer` | `day` / `night` / `both` |
| `chapter` | 第幾章開放。night row（含 `teaser_only`）必須與 `earliest_night` 所屬章節一致；一般 row 仍以 `earliest_night` 控制出現，`teaser_only` 才以 `chapter` 控制可見起點。teaser 的 `earliest_night` 不參與解鎖，只作章節一致性守衛 |
| `earliest_night` | 夜間地點最早可開的夜。**是下限不是期限**——開過與否跨夜持續 |
| `requires` | 夜間地點級門檻；不成立時 row 仍顯示，詳情的「進入」灰掉。走過前一夜間地點用 `night_seen`，不用 `opened_n_*` flag |
| `reject_reason` | 夜間地點灰掉時那一行字（選填；未填時引擎用通用文案） |
| `night_reveal` | 對位後取得的 knowledge 卡 id；有 `day_counterpart` 的 row 必填，夜間限定 row 必須為 null。同一 `day_counterpart` 的 row 必須共用 id |
| `day_counterpart` | **夜間地點專用**：白天去同一個位置是哪個地點；`null` ＝ 白天那裡什麼都沒有。見下 |
| `madness_cost` | 夜間 row 的終身首次主動到訪會產生幾張發狂卡；0 ＝不產生。玩家到訪前不看見數字，UI 不顯示「免費」 |
| `teaser_only` | 選填 boolean。`true` ＝從 `chapter` 起可見但永遠不能進入；必須有 `reject_reason`，且 `madness_cost`／`day_counterpart`／`night_reveal` 必須為 null 或省略 |
| `map` | 地圖座標，`{x, y}` |
| `note` | 設計註記，引擎不讀 |

### 地點三分類（企劃書第十五節）

三分類**不另立欄位，由 `day_counterpart` 推導**——多一個列舉值就多一份會跟配對漂移的事實：

| 類 | 判定 | 現況 |
|---|---|---|
| 一、只有白天 | 沒有任何夜間地點的 `day_counterpart` 指向它 | 10 個白天地點 |
| 二、日夜都有、內容不同 | 夜間地點的 `day_counterpart` 非 null | 10 個白天地點（12 個夜間 row 指過來） |
| 三、只有夜裡存在 | 夜間地點的 `day_counterpart` 為 `null` | 16 個夜間地點 |

**數的是地方不是 row**：48 個 row ＝ 36 個地方（10 ＋ 10 ＋ 16）。多對一是合法的——`n_woodtags` 與 `n_music` 都指向 `temple`，`n_corridor` 與 `n_steam_below` 都指向 `jinghe_back`。`verify_data.gd` 每次跑都印這三個數。

> **第二類必須與它的 `day_counterpart` 同座標。** 「日夜都有」的意思就是白天去同一個位置——座標不同就不是同一個地方，`verify_references()` 會擋下來。

**第三類最值錢**：白天去那個座標是空地、一堵牆、一間沒有門的房子。

> `night_reveal` 只有第二類填得動——沒有白天版就沒有「改成白天名」這回事。第三類一律 `null`。已對位不是儲存欄位；引擎由「該 row 已在 meta `night_locations_seen`」且「meta knowledge 含 `night_reveal`」即時計算。

## `npcs.json`

**誰在哪、什麼時段找得到。** 關係值住 GameState（規格書第十二節）、委託規則等 P4，都不進這裡。

| 欄位 | 說明 |
|---|---|
| `id` / `name` | `id` 與 `on_place.relation.npc`、`slots[].attention_npc` 共用同一組鍵 |
| `locked_name` | 未揭露時 UI 顯示什麼；`null` ＝ 一開始就叫本名。NPC 版的地圖對位（企劃書第十五節） |
| `reveal` | 改叫本名的條件，語彙同 `condition`；`locked_name` 為 `null` 時填 `null` |
| `card` | 對應的 `person` 卡 id；沒有卡就 `null` |
| `festival_proxy_eligible` | **P5 起必填 boolean**；是否可成為 D29 不邀路線的慶典代付候選。不是「有人物卡」的同義詞 |
| `at[]` | 可及性，見下 |
| `note` | 設計註記，引擎不讀 |

### `at[]`

| 欄位 | 說明 |
|---|---|
| `location` | 地點 id，必須存在 |
| `phases` | 在該地點的哪些時段找得到。**必須是該地點 `phases` 的子集**——地點不開的時段，人也不在 |
| `from_day` | 最早哪一天（含） |
| `to_day` | 最後哪一天（含）；省略 ＝ 到第 45 天 |

同一人可以有多筆 `at`（叔叔在山泉閣與診所都找得到）。**夜鎮裡出現的人不進 `at[]`**——那是夜間 beat 的演出內容，不是可及性。

## `beats/*.json`

一個 beat ＝ 一個掛在地點上的事件／標記。面板的內容 ＝ 該地點所有條件通過的 beat 的槽。

| 欄位 | 說明 |
|---|---|
| `id` | 唯一鍵 |
| `location` | 掛在哪個地點 |
| `when` | `{day, phase}`；`phase` ＝ `morning` / `afternoon` / `evening` / `night`。**常駐白天 beat 改用 `{day_from, day_to, phase}`**（見下方專節，P2 新增）。**沒有 `when` 的 beat 是夜間章節變體**——掛在夜間地點上，開放與否由地點的 `earliest_night` / `requires` 決定。`phase: "night"` 的**定日夜 beat** 也存在（引導夜、颱風夜等）；兩者的解析順序住 `實作規格書.md > 夜間層` |
| `fixed` | `true` ＝ 一定發生且**不吃行動格** |
| `condition` | 出現條件，不成立則整個 beat 不存在 |
| `requires` / `reject_reason` | beat 級門檻：不成立時整個 beat 灰掉＋理由（語意同槽級） |
| `meta_once` | 選填 boolean；只供 `when.phase == "night"` 且 `fixed: true` 的 beat。`true` ＝整份存檔只自動播一次，id 記進 meta `night_once_beats_seen`。唯一相反形狀是 `encounter.repeat_each_run: true`：每輪重演，且不得同時 meta-once |
| `title` / `text` | 面板標題與敘述 |
| `slots` | 槽陣列 |
| `on_enter` | beat 首次呈現給玩家時結算一次的效果；鍵同 `on_place` |
| `echo` | 沒到場時留下什麼：`{day, text, condition}`——該天 `condition` 成立才播（企劃書第十七節殘響三級）。**`day` 必填且必須大於本 beat 的 `when.day`**：引擎掃的是 `echo.day == 今天`，缺欄的 echo 永遠不播。同一段 `text` 不得在多個 beat 重複（lint 8） |
| `encounter` | 遭遇定義，精確形狀見本節下方 `encounter` 專節 |
| `chapter` | **只有夜間標記用**。同一個標記的章節變體，見下 |
| `note` | 設計註記，引擎不讀 |

### 夜間標記的章節變體

**「最早可開」是下限，不是期限。** 第 3 夜出現的標記，第 40 夜還在那裡——所以同一個標記可能在任何一章被第一次打開。

而三章的夜性格不同（企劃書第十五節）：

> 第一章夜鎮的人**不理他**；第三章，他們**會轉頭**。

所以**內容跟著章節走，不跟著標記走**：同一個 `location` 可以有多個 beat，各自標 `chapter`，引擎依當下章節挑。沒有對應章節的變體時，往下取最接近的一個。

```json
{ "id": "n_litwindow_ch1", "location": "n_litwindow", "chapter": 1,
  "text": "他敲窗，他們看不見他。" }

{ "id": "n_litwindow_ch3", "location": "n_litwindow", "chapter": 3,
  "text": "他敲窗。這一次，桌邊的每一個人都轉過頭來。" }
```

> **這也讓晚開變成一種不同的體驗，而不是懲罰。** 撐到第三章才第一次開那扇窗的玩家，看到的是另一個畫面。
>
> 文本成本可控：第十五節本來就規定夜間版用 override 只寫差異行。

### `slots[]`

| 欄位 | 說明 |
|---|---|
| `id` / `label` | — |
| `occupant` | 已在場的卡 id；`null` ＝ 空槽 |
| `condition` | 槽級出現條件；不成立則槽不存在（「拿掉而非灰掉」的載體，已拍板支援） |
| `accepts` | 接受的 `type` 或指定卡 id 陣列；`[]` ＝ 純顯示 |
| `requires` | 額外條件；不成立則灰掉 |
| `reject_reason` | 灰掉時那一行字 |
| `on_place` | 放進去產生什麼 |
| `delegation` | **只有委託槽有**：回報時間、預覽與選填的隔日上午 report；見下方專節 |
| `indulgence` | **只有縱慾出口槽有**：`{weight, auto, soak}`，見上方「縱慾出口」 |
| `on_place_by_level` | **只有縱慾出口槽有**：強度級的追加效果，見上方「縱慾出口」 |
| `choice_group` | 同組的槽互斥，見下 |
| `choice_requires_card` | 選填 boolean，預設 false；只有 choice_group 槽可用。true 時不得走無卡 `choose()`，必須提交 `accepts` 內的卡 |
| `default_if_unresolved` | 選填 boolean，預設 false；該 choice group 離開時段仍未結算時，自動選本槽。限制見下 |
| `attention_npc` | 此槽消耗主角行動時，投入帳記給哪位 NPC（選填；未標＝不計。供「不邀任何人時系統挑誰」判定，規格書第十二節） |
| `note` | 設計註記，引擎不讀 |

### `delegation`＝人物委託

委託仍是一個 slot，不是新的事件類型。槽必須：

- `accepts` 只放**一個明確的 person card id**，不可寫型別 `"person"`。
- 與同一任務的親自處理槽及其他人物槽共用同一個非空 `choice_group`。
- 用 `condition: {has_card: ...}` 隱藏未取得人物卡的路線；人物已取得但缺其他條件時才用 `requires`＋`reject_reason` 顯示灰槽。

立即回報：

```json
{
  "id": "ask_ajie",
  "label": "請阿婕去問",
  "accepts": ["npc_ajie"],
  "condition": { "has_card": "npc_ajie" },
  "choice_group": "prescription_route",
  "delegation": {
    "result_timing": "immediate",
    "preview": "請她打聽這張處方的來源。",
    "tendency": "熟人容易開口，但她可能先追問你為什麼在查。"
  },
  "on_place": { "text": "她很快帶著答案回來。" }
}
```

隔日上午回報：

```json
{
  "delegation": {
    "result_timing": "next_morning",
    "preview": "請他沿著送貨路線問一圈。",
    "tendency": "範圍較廣，隔日上午才回報。",
    "report": {
      "text": "他把昨晚問到的名字寫在紙上。",
      "gain": ["info_ajie_class"]
    }
  }
}
```

| 欄位 | 規約 |
|---|---|
| `result_timing` | 必填 enum：`immediate`／`next_morning`。不支援任意 N 天 |
| `preview` | 必填；選擇前看到的任務說明，不列完整結果 |
| `tendency` | 必填；已知傾向或風險，不寫成功率 |
| `report` | `next_morning` 必填、`immediate` 禁止；形狀同 `on_place` 效果 |

`on_place` 仍必填：immediate 時承擔完整當場結果；next_morning 時只承擔派出當下的文字／旗標，真正回報放 `report`。關係增減若有，也寫在對應事件效果；委託沒有預設 relationship delta。任何可能成立到第 45 天的槽不得使用 `next_morning`，避免本輪結束後永遠收不到回報。

人物卡成功受託後留在 hand；資料不寫外出天數、歸還日或人物暫存區。一天一次是 GameState 規則，不重複填在每個槽。

### `encounter`＝遭遇

遭遇掛在 fixed beat 上；beat 的 `text` 是進遭遇前演出，互動要求才放 `rounds[]`。完整形狀：

```json
{
  "encounter": {
    "repeat_each_run": true,
    "charge_first_visit": true,
    "per_round_slot_cost": 1,
    "escape_cost": 1,
    "allow_discard": true,
    "after_finish": "stay",
    "rounds": [
      {
        "id": "first_demand",
        "demand": "它要你證明自己記得。",
        "responses": [
          {
            "id": "answer_with_memory",
            "accepts": ["k_forty_something"],
            "consume_card": false,
            "next_round": "second_demand",
            "on_resolve": { "text": "門後的聲音停了一拍。" }
          }
        ],
        "fallback": {
          "requires_discardable": true,
          "next_round": "second_demand",
          "on_resolve": { "text": "它收走了你的回答。" }
        }
      }
    ],
    "on_victory": { "text": "它暫時退開。" },
    "on_failure": { "text": "你再也騰不出位置。" },
    "on_escape": { "text": "你付出代價離開。" }
  }
}
```

| 欄位 | 規約 |
|---|---|
| `repeat_each_run` | 選填 boolean，預設 false；只可用在**有明確整數 `when.day`** 的 fixed encounter，phase 可為 night。true 時不得 `meta_once` |
| `charge_first_visit` | 選填 boolean，預設 false；true 時 beat 必須 `fixed:true`、有明確整數 `when.day`、`when.phase == "night"`，且所掛 location 的 `layer == "night"`。強制到訪前先保存是否終身 seen，只有此前未 seen 才按 location `madness_cost` 收一次；不是遭遇額外費用。這組限制只屬於本欄，不表示所有 night beat 都必須掛 night-layer location |
| `per_round_slot_cost` | 必填正整數；每進一個 round 增加的壓力佔格。`start_encounter()` 只建立 intro，`acknowledge_encounter_intro()` 進第一回合時收唯一一次；沒有另一筆進場 cost。超載 penalty 是規則層明示例外 |
| `escape_cost` | 必填；`null`＝不可逃，非負整數＝需支付的可丟棄卡數 |
| `allow_discard` | 選填 boolean，預設 true；是否顯示並接受「主動丟一張卡」操作。D45 為 false；不影響 fallback 對錯答卡的處理 |
| `after_finish` | 必填 enum：`stay`＝出口結算後留在原時段；`advance_phase`＝由規則層恰好推進一次。UI 不得依 beat id 自行推進 |
| `rounds` | 非空陣列；第一筆是入口。`id` 在本 encounter 唯一 |
| `demand` | 當前要求文字 |
| `responses` | 非空陣列；同一回合可有多組合理回應 |
| `responses[].id` | 回應分支 id；同一回合唯一，供測試／日誌定位 |
| `responses[].accepts` | 非空的明確 card id 陣列；是隱藏正解集合，不是 UI 允許點擊集合。同回合各 response 不得重疊 |
| `fallback` | 必填；沒有 response 命中時的結果。固定保留本回合壓力，並依 `cards.json.discardable` 決定能否消耗提交卡 |
| `fallback.requires_discardable` | 選填 boolean，預設 false；true 時，未命中 response 的不可丟棄卡不是合法提交，規則層回 `card_not_submittable`，不標 attempted、不套效果、不推進。只限制 fallback，不會排除命中 response 的人物／主角／知識卡 |
| `responses[].consume_card` | 必填 boolean；正解是否消耗提交卡。true 仍只可消耗 `discardable:true` 的卡；命中 response 固定釋放本回合壓力 |
| `next_round` | 下一 round id 或 `null`。response 的 null＝勝利出口；fallback 的 null＝失敗出口 |
| `on_resolve` | 必填；形狀同 `on_place` 效果。卡片轉化以明確 `lose`／`gain` 寫在此處 |
| `on_victory`／`on_failure`／`on_escape` | 三者必填，形狀同效果；即使 `escape_cost:null` 也保留 `on_escape`，讓結構固定 |

遭遇可提交持有集合精確等於 `hand ∪ knowledge`，持有判定共用 `GameState.has_card()`；壓力與容量只計 `hand`。view model 必須為每張候選標出來源與可選狀態，UI 不得因 knowledge 不在 hand 而漏掉它。

每張 base card 同一場只能提交一次。response 的 `consume_card` 與 fallback 都不得移除 `discardable:false` 的卡；若未來要永久失去人物，必須另建明示的特殊事件規格，不能借 encounter 偷做。

`allow_discard` 與 `escape_cost` 都不是 fallback 的前置。`requires_discardable` 省略／false 時，不可丟棄卡答錯仍留手並可照 fallback 推進；true 時則原子拒絕。若依當前 response 與 fallback 篩選後沒有合法尚未嘗試卡，也沒有可用的 discard／escape，直接套 `on_failure`；資料不另寫「無路可走」分支。

round graph 必須從第一筆全部可達、所有 next_round 存在且每條路可抵達 null；不可用無出口 cycle 模擬「一直答到對」。第一輪暫時拿不到某 response 的卡是合法內容設計，不代表該 response 不可達。

### `choice_group`＝選擇題

一組槽標同一個 `choice_group`，就變成一道選擇題：**最多選一個。** 一般組可以都不選；明示逾期預設的組則在離開時段前自動結算預設槽。

| | |
|---|---|
| 成本 | 預設不吃卡、不吃行動格；`choice_requires_card:true` 時走正常放卡成本，提交 protagonist 就消耗該行動時段 |
| 互斥 | 選了一個，同組其他的**收起來**（不是灰掉） |
| 不選 | 無 `default_if_unresolved` 的組＝合法且不套效果；有預設的組＝走開前由規則層選唯一預設槽 |
| `accepts` | 一般組裡是「**可以**放什麼」，不是「必須放什麼」；`choice_requires_card:true` 才是硬成本 |

最後一條是關鍵。第 22 天「你覺得哪裡不對」，手上有拍立得或情報卡的玩家可以拖過去比對，**沒有卡的玩家直接選下去，用主角自己的記憶並列**——故事線的硬規則是兩個入口都要通，而 `accepts` 在組外是硬門檻，在組內只是加分路徑。

> **為什麼是收起來不是灰掉。** 灰掉是「你缺一把鑰匙」，而選擇題不缺鑰匙——你已經選了。三條灰在那裡等於告訴玩家還有三種讀法沒試，那一格問的卻是**你當下的判斷**。

> **同一條時段限制照舊。** 因為不吃格，`choice_group` 只能出現在**同一個面板已經有槽吃掉主角卡**的地方，或 `fixed` beat 裡面。理由跟比對那條一樣（見上）：否則一個下午可以把三個地點的選擇題都做掉。

> **「不選」要不要給一個看得見的選項，由那一格自己決定。** 第 29 天的「不邀」是三個並列選項之一、而且是最差的那張牌，所以它明寫成一個組員並標 `default_if_unresolved:true`；選它跟直接走開結果完全相同。

同一 group 若使用逾期預設，必須恰一槽為 true。該槽必須 `accepts:[]`、沒有 `condition`／`requires`／`delegation`，且可由既有無卡 `choose()` 原子結算；否則玩家可能在推進時卡死。預設槽的 `on_place` 照常套用並寫 choice／slot 記錄，不建立第二套「逾期結果」。

`choice_requires_card:true` 必須有非空 `accepts`，且不得與 `default_if_unresolved:true` 同槽。D43 的前老闆／周先生工作槽都設 true 並只收 protagonist，因此真正接受才會消耗下午；D22 的推論選擇與 D29 邀請維持省略／false，仍可直接選文字答案。無卡直呼 `choose()` 必須回 `card_required` 且零變化，不能只靠 UI 不顯示捷徑。

### `condition` / `requires` 語彙

```json
{ "day": 3 }
{ "day_at_least": 10 }
{ "has_card": "info_ahong_private" }
{ "has_knowledge": "k_forty_something" }
{ "switch": "s1" }
{ "relation_at_least": { "npc": "awei", "state": "疑似" } }
{ "flag": "ahong_missing" }
{ "madness_at_least": 3 }
{ "night_seen": "n_ahong_1" }
{ "opening_choice": "take_family_album" }
{ "ending_seen": "ending_replaced" }
{ "count_at_least": { "n": 2, "of": [ ... ] } }
{ "switch_progress_at_least": { "switch": "s6", "n": 3 } }
{ "not": { ... } }
{ "all": [ ... ] }
{ "any": [ ... ] }
```

#### `count_at_least`＝「這幾個裡面成立了幾個」

`all` 是全部、`any` 是至少一個，**中間那一段一直沒有語彙**。而設計裡到處是中間那一段：第 22 天「兩個觀察開關以上」、第 26–27 天「碰到任意兩個閃躲的人」。

沒有它就只能窮舉配對——三個裡挑兩個要寫三組 `all`，四個裡挑兩個要寫六組。**條件會隨人數平方成長，而且看不出原意。**

```json
{ "count_at_least": { "n": 2, "of": [
  { "flag": "acai_obs_knee" }, { "flag": "acai_obs_hands" }, { "flag": "acai_obs_scar" }
] } }
```

`of` 裡放的是條件，不是旗標名——所以它可以混搭 `has_card`、`relation_at_least` 等等。`n: 1` 等於 `any`，`n` ＝全長等於 `all`；兩者仍優先用 `any` / `all` 寫，讀起來比較清楚。

#### `switch_progress_at_least`＝累計型開關的讀法

`switch_progress` 只能寫入，**沒有辦法問「累計到幾格了」**——而開關 6 第 35 天要結算。這一條補上讀的那一半。

#### `madness_at_least`＝「撐著不清」的報酬

企劃書第七節：**桌面上有 ≥3 張發狂卡才看得見某些東西**（門檻值住 `tuning.json` 的 `madness_vision_threshold`，寫條件時填那個值）。

**這是拖延唯一的正報酬，沒有它那條路只剩壞處**——一張卡不管主動清還是倒數歸零都是一格，拖延省不到行動格。

用在 `condition` 而不是 `requires`：看不見的東西就是不存在，不該灰給玩家看。**這是三態裡「不顯示」那一態的正當用法**——它不是缺鑰匙，是他還不夠不正常。

#### `night_seen`＝「曾經走到過這裡」

`night_seen` 的值是 night location id；求值只讀 meta `night_locations_seen`。它跨輪成立，用於路徑前置與「以前走過就不必重走」的承諾。

它不等於本輪故事 flag，也不等於對位：

- 需要「曾走過某夜間地點」→ `night_seen`
- 需要「本輪發生過某件事」→ `flag`
- 需要「已經把日夜位置對起來」→ `has_knowledge` 讀該 row 的 `night_reveal`

正式資料不得以 `opened_n_*` flag 模擬 `night_seen`。

例外不是保留舊名字，而是把語意寫準：若條件要求「本輪較早已看過某段內容」，使用明確的 run flag。P3-B 落地後，聚會常態內容寫 `saw_n_gathering_intro`，D31 特殊內容讀它；不得改讀 `night_seen: n_gathering`，因為進場會先寫 meta seen，且 meta seen 跨輪。

#### `opening_choice`／`ending_seen`（P5）

- `opening_choice` 比對當前 run 的 `opening_choice_id`；只在 run mode 可能成立。D7 的拒信回聲用這個，不另複製 `took_album` 旗標。
- `ending_seen` 的值是 endings id；只查 meta `ending_history` 是否已有該 id，不看輪數、不看知識卡。開局「不上車」只用 `{ending_seen:"ending_replaced"}`。

### `on_place` 效果

```json
{
  "text":     "放進去之後顯示的文字",
  "gain":     ["card_id"],
  "lose":     ["card_id"],
  "switch":   "s1",
  "switch_progress": { "s6": 1 },
  "relation": { "npc": "ajie", "delta": 1 },
  "madness":  1,
  "flag":     { "ahong_last_seen": true },
  "festival_proxy": { "mode": "fixed", "npc": "ajie" },
  "ending": "ending_inventory_be"
}
```

> **放入主角卡即消耗該時段**，不用每個槽標。`fixed: true` 的 beat 不需要主角卡。

#### 帶條件的卡片項目（`gain` / `lose`）

`gain` 與 `lose` 的元素有兩種寫法。**預設用字串**，只有需要條件時才用物件：

```json
"gain": [
  "k_forty_something",
  { "card": "k_not_today", "if": { "not": { "has_knowledge": "k_already_on_list" } } }
]
```

- `if` 用的是**同一套 `condition` / `requires` 語彙**（見上方「`condition` / `requires` 語彙」），沒有另立第二套。缺 `if` 等於恆成立。
- **守衛下在單張卡上，不是整個效果塊。** 同一個 `on_enter` 裡的 `flag`、`text`、`switch` 都照跑——只有那一張卡被跳過。這是刻意的：升級型比對的那一格通常還要寫旗標，整塊擋掉會連坐。
- `lose` 同樣支援條件，並可為真正跨輪物品明示永久失去：`{ "card":"item_magic", "if": {...}, "permanent":true }`。`permanent` 只允許 boolean、只對 `loop_persistent:true` 卡有意義；省略／false 只移出本輪 hand，true 另從 meta persistent set 移除。一般卡不得靠此欄偽造跨輪規則。

**什麼時候需要它：知識卡跨輪保留，而 `beats_entered` 每輪清空。** 於是第二輪會重演同一個 beat，`on_enter` 又發一次卡。對一般卡沒差（`gain_card` 冪等、佔格卡 unique），但**升級型比對**會出事——舊版被 `lose` 掉之後，第二輪又被發回來，玩家同時持有升級前與升級後兩張。守衛就是用來讓升級保持單向的。

第一個實例是 `d45_then`（第 45 天傍晚，`k_not_today` → `k_already_on_list`）。**之後每做一組升級型比對，都要在發舊版的地方加上這個守衛。**

> **`switch` 與 `switch_progress` 不一樣。** `switch` 是翻開一個開關（一次就到位）；`switch_progress` 是**累計一格**——同一個開關可以被很多個槽各推一格，第 35 天才結算。目前只有開關 6（陪叔叔）是累計型：第二、三章任何一個**主動選的**診所時段都累計，上午那格固定事件不算。

#### `festival_proxy`（P5）

只用在 D29 invitation choice 的 `on_place`，成功後一次寫入 run `selected_festival_proxy_npc`：

```json
{ "festival_proxy": { "mode": "fixed", "npc": "ajie" } }
{ "festival_proxy": { "mode": "highest_eligible", "fallback": "ajie" } }
```

- `fixed` 必須有 `npc`，且該 NPC 為 `festival_proxy_eligible:true`。
- `highest_eligible` 必須有合法 `fallback`；只在 eligible NPC 中比較 `npc_action_counts`，最大者勝，同分按 `npcs.json` 陣列順序；全部為 0 使用 fallback。首輪 eligible 子序列固定為阿婕 → 阿薇 → 阿財。
- 同一輪成功寫入後不得第二次覆寫；D31、D39 與 ending 只讀結果。資料衝突要拒絕整個 choice，不可靜默重算。

#### `ending`（P5）

值是 `endings.json` 的 id。它永遠最後執行：固定效果順序為 `text` → `lose` → `gain` → `switch` → `switch_progress` → `relation` → `madness` → `flag` → `festival_proxy` → `ending`。ending 啟動後其餘 run mutation 會被 mode gate 擋住，因此資料不得在 ending 後期待另一個效果。

`gain`／`madness` 若在同一效果塊途中達發狂上限，只先提出 `ending_madness_be` request；等 `flag`／`festival_proxy` 等剩餘鍵完成後才啟動。資料作者看到的順序仍是上面一條，不存在「寫在 madness 後面的鍵可能跑到下一輪」的例外。

---

## 目前的暫定決定（要記得回頭驗）

- **第 1–3 天不發人物卡。** 人只作為槽上的 occupant 存在。之後人物卡只由各 NPC 的明示故事效果取得，不在第 17 天自動發全員；委託教學跟第一張人物卡取得走，不綁日期。
- **地圖座標先給示意值**，但保留相對位置——`待決事項.md` 第 29 項那條隱藏線索需要地理關係。
- **標記價碼**：全輪 14 個 `madness_cost > 0` row，目前一律 1 張。規則是「往裡走收費，地形不產生卡」，且只收終身第一次主動到訪；多張價碼留給後續內容調整（待決 38 已結案）。
- **章節變體已投入使用。** `n_litwindow` 與 `n_gathering` 現有跨章版本，多數一般 marker 有所屬章節版本；D1／D2 走定日 fixed，teaser 不需要內容。引擎仍必須支援「沒有當章版本時向下取最近版本」。
