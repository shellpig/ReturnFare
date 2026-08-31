extends VBoxContainer

## 地點清單（白天與夜間共用）。只渲染 PanelBuilder.available_locations() 的結果，自己不過濾。
## 每次 refresh() 清空重建按鈕；一行四個（地點多了單欄排不下，會蓋到手牌列）。
##
## 空面板地點（PanelBuilder.build() 回傳 beats 為空）在 debug 版加後綴標示並停用——
## 點進去只會看到空面板。正式版這種地點改為不顯示，屆時這裡改成不產生按鈕。
## 夜間收費地點回的是 LOCKED stub beat（附價碼理由），不算空面板，仍可點。

signal location_selected(id: String)

@onready var _container: GridContainer = $LocationsContainer


func refresh() -> void:
	for child in _container.get_children():
		_container.remove_child(child)
		child.queue_free()

	var locs: Array[String] = PanelBuilder.available_locations(GameState, Data)
	var is_night: bool = (GameState.phase == "night")
	for loc_id in locs:
		var loc: Dictionary = Data.loader.locations.get(loc_id, {}) as Dictionary
		var btn := Button.new()
		if is_night:
			var summary: Dictionary = PanelBuilder.location_summary(loc_id, GameState, Data)
			btn.text = "%s %s" % [summary.get("display_name", loc_id), summary.get("status_text", "")]
			btn.disabled = false
		else:
			btn.text = str(loc.get("name", loc_id))
			var panel_view: Dictionary = GameState.build_panel(loc_id)
			var has_beats: bool = not (panel_view.get("beats", []) as Array).is_empty()
			var visited_dict: Dictionary = GameState.get("day_locations_visited") as Dictionary if GameState.get("day_locations_visited") is Dictionary else {}
			var has_visited: bool = visited_dict.has(loc_id)
			btn.disabled = not (has_beats or has_visited)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.set_meta("qa_id", "location::" + loc_id)
		btn.pressed.connect(_on_location_pressed.bind(loc_id))
		_container.add_child(btn)


func _on_location_pressed(loc_id: String) -> void:
	location_selected.emit(loc_id)
