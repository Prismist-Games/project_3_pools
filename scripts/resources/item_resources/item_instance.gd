extends RefCounted
class_name ItemInstance

## 背包中的动态物品实例（由 ItemData + 运行时属性组成）。

var item_data: Resource
var rarity: int
var sterile: bool


func _init(p_item_data: Resource, p_rarity: int, p_sterile: bool = false) -> void:
	item_data = p_item_data
	rarity = p_rarity
	sterile = p_sterile


func get_display_name() -> String:
	if item_data != null and "name" in item_data:
		return String(item_data.get("name"))
	return "未知物品"


