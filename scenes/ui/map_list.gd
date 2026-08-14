extends VBoxContainer

## 地點清單（白天與夜間共用）。只渲染 PanelBuilder.available_locations() 的結果，自己不過濾。
## 每次 refresh() 清空重建按鈕；一行四個（地點多了單欄排不下，會蓋到手牌列）。
##
## 空面板地點（PanelBuilder.build() 回傳 beats 為空）在 debug 版加後綴標示並停用——
## 點進去只會看到空面板。正式版這種地點改為不顯示，屆時這裡改成不產生按鈕。
## 夜間收費地點回的是 LOCKED stub beat（附價碼理由），不算空面板，仍可點。

signal location_selected(id: String)

## debug 版的空面板標示。正式版拿掉（改不顯示）。
const _SUFFIX_EMPTY := "（無內容）"

@onready var _container: GridContainer = $LocationsContainer


func refresh() -> void:
	for child in _container.get_children():
		child.queue_free()

	var locs: Array[String] = PanelBuilder.available_locations(GameState, Data)
	for loc_id in locs:
		var loc: Dictionary = Data.loader.locations.get(loc_id, {}) as Dictionary
		var view: Dictionary = PanelBuilder.build(loc_id, GameState, Data)
		var is_empty: bool = (view.get("beats", []) as Array).is_empty()
		var btn := Button.new()
		btn.text = str(loc.get("name", loc_id)) + (_SUFFIX_EMPTY if is_empty else "")
		btn.disabled = is_empty
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_location_pressed.bind(loc_id))
		_container.add_child(btn)


func _on_location_pressed(loc_id: String) -> void:
	location_selected.emit(loc_id)
