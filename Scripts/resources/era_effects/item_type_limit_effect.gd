extends Resource
class_name ItemTypeLimitEffect

## ERA_3: 背包物品种类限制效果
## 限制背包中不同名称物品的种类数量

@export var effect_name: String = "物品种类限制"
@export var max_item_types: int = 7

## 检查是否超出种类限制
func would_exceed_limit(inventory_system: Node, new_item: ItemInstance) -> bool:
	var current_names = inventory_system.get_unique_item_names()
	# 如果新物品的名称已存在，则不会超限
	if new_item.item_data.id in current_names:
		return false
	return current_names.size() >= max_item_types

func get_description() -> String:
	return "%s：最多 %d 种不同物品" % [effect_name, max_item_types]
