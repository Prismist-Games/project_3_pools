extends RefCounted
class_name ItemInstance

## 背包中的动态物品实例（由 ItemData + 运行时属性组成）。

var item_data: ItemData
var rarity: int
var sterile: bool
var shelf_life: int = -1 # -1 表示无限保质期（非保质期时代）

var is_expired: bool:
	get:
		# 仅在启用保质期的时代才会过期
		var cfg = EraManager.current_config if EraManager else null
		if not cfg:
			return false
		var shelf_life_effect = cfg.get_effect_of_type("ShelfLifeEffect")
		if not shelf_life_effect:
			return false
		return shelf_life_effect.is_expired(self)


func _init(p_item_data: ItemData, p_rarity: int, p_sterile: bool = false, p_shelf_life: int = -1) -> void:
	item_data = p_item_data
	rarity = p_rarity
	sterile = p_sterile
	
	# 设置保质期
	if p_shelf_life >= 0:
		# 显式传入保质期
		shelf_life = p_shelf_life
	else:
		# 检查当前时代是否有保质期效果
		var cfg = EraManager.current_config if EraManager else null
		if cfg:
			var shelf_life_effect = cfg.get_effect_of_type("ShelfLifeEffect")
			if shelf_life_effect:
				shelf_life = shelf_life_effect.default_shelf_life


func get_display_name() -> String:
	if item_data != null and "name" in item_data:
		return String(item_data.get("name"))
	return "ITEM_UNKNOWN"


