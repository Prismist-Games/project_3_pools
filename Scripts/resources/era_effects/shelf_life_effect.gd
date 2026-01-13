extends Resource
class_name ShelfLifeEffect

## ERA_4: 保质期效果
## 物品有保质期，每次抽奖后递减

@export var effect_name: String = "保质期"
@export var default_shelf_life: int = 25

## 在抽奖后递减所有物品的保质期
func decrement_all_shelf_lives(inventory_system: Node) -> void:
	for item in inventory_system.inventory:
		if item != null and item.shelf_life > 0:
			item.shelf_life -= 1
	# 触发背包更新以刷新 UI
	inventory_system.inventory_changed.emit(inventory_system.inventory)

## 检查物品是否过期
func is_expired(item: ItemInstance) -> bool:
	return item.shelf_life <= 0

func get_description() -> String:
	return "%s：物品有 %d 次抽奖的保质期" % [effect_name, default_shelf_life]
