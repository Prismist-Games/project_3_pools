extends Resource
class_name EraConfig

## 时代配置资源，定义每个时代的起始状态和全局效果。

@export var era_name: String = "时代 1"
@export var starting_gold: int = 30
@export var inventory_size: int = 10

## 时代全局效果列表（按顺序应用）
@export var effects: Array[Resource] = []

## 订单生成配置
@export_group("Order Generation")
@export_subgroup("Order Count Weights")
## 订单包含 2 个物品的概率
@export var count_2_items: float = 0.20
## 订单包含 3 个物品的概率
@export var count_3_items: float = 0.65
## 订单包含 4 个物品的概率
@export var count_4_items: float = 0.15

## 获取排序后的订单数量权重数组 (用于 OrderSystem) (index 0 -> 2 items, index 1 -> 3 items...)
func get_count_weights() -> PackedFloat32Array:
	return PackedFloat32Array([
		count_2_items,
		count_3_items,
		count_4_items
	])

@export_subgroup("Rarity Weights")
@export var rarity_common: float = 0.40
@export var rarity_uncommon: float = 0.35
@export var rarity_rare: float = 0.20
@export var rarity_epic: float = 0.05
@export var rarity_legendary: float = 0.0
@export var rarity_mythic: float = 0.0

## 获取排序后的品质权重数组 (用于 OrderSystem)
func get_rarity_weights() -> PackedFloat32Array:
	return PackedFloat32Array([
		rarity_common,
		rarity_uncommon,
		rarity_rare,
		rarity_epic,
		rarity_legendary,
		rarity_mythic
	])


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
