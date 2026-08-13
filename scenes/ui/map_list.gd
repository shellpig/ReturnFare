extends VBoxContainer

## 白天地點清單。只渲染 PanelBuilder.available_locations() 的結果，自己不過濾。
## 每次 refresh() 清空重建按鈕。

signal location_selected(id: String)

@onready var _container: VBoxContainer = $LocationsContainer


func refresh() -> void:
	for child in _container.get_children():
		child.queue_free()

	var locs: Array[String] = PanelBuilder.available_locations(GameState, Data)
	for loc_id in locs:
		var loc: Dictionary = Data.loader.locations.get(loc_id, {}) as Dictionary
		var btn := Button.new()
		btn.text = str(loc.get("name", loc_id))
		btn.pressed.connect(_on_location_pressed.bind(loc_id))
		_container.add_child(btn)


func _on_location_pressed(loc_id: String) -> void:
	location_selected.emit(loc_id)
