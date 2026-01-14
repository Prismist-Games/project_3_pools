extends Resource
class_name EraConfig

## 时代配置资源，定义每个时代的起始状态和全局效果。

@export var era_name: String = "时代 1"
@export var starting_gold: int = 30
@export var inventory_size: int = 10

## 时代全局效果列表（按顺序应用）
@export var effects: Array[Resource] = []


## 辅助方法：获取特定类型的效果
func get_effect_of_type(effect_type: String) -> Resource:
	for effect in effects:
		if effect != null and effect.get_script().get_global_name() == effect_type:
			return effect
	return null


## 检查是否有价格波动效果
func has_price_fluctuation() -> bool:
	return get_effect_of_type("PriceFluctuationEffect") != null


## 检查是否有种类限制效果
func has_item_type_limit() -> bool:
	return get_effect_of_type("ItemTypeLimitEffect") != null


## 检查是否有保质期效果
func has_shelf_life() -> bool:
	return get_effect_of_type("ShelfLifeEffect") != null
