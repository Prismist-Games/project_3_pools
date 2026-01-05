extends Resource
class_name OrderData

## 订单数据：表示一个生成的订单实例（运行时创建）。

## 需求项列表：Array[Dictionary]，每个 Dict 格式为：
## { "item_id": StringName, "min_rarity": int, "count": int }
@export var requirements: Array[Dictionary] = []

@export var reward_gold: int = 0
@export var reward_tickets: int = 0
@export var is_mainline: bool = false

## 剩余刷新次数
@export var refresh_count: int = 1

## 运行时标识
var order_id: StringName = &""


func _init() -> void:
	order_id = &"order_%d_%d" % [Time.get_ticks_msec(), randi() % 1000]


## 检查背包中是否有足够的物品满足该订单
func can_fulfill(inventory: Array) -> bool:
	var temp_inventory = inventory.duplicate()
	for req: Dictionary in requirements:
		var count: int = req.get("count", 1)
		var item_id: StringName = req.get("item_id", &"")
		var min_rarity: int = req.get("min_rarity", 0)
		
		var found_count: int = 0
		var indices_to_remove: Array[int] = []
		
		for i: int in temp_inventory.size():
			var it: ItemInstance = temp_inventory[i]
			if it.item_data.id == item_id and it.rarity >= min_rarity:
				found_count += 1
				indices_to_remove.append(i)
				if found_count >= count:
					break
		
		if found_count < count:
			return false
			
		# 从临时背包中移除，避免重复计算
		indices_to_remove.sort()
		indices_to_remove.reverse()
		for idx: int in indices_to_remove:
			temp_inventory.pop_at(idx)
			
	return true


## 获取满足该订单的物品索引列表（从 inventory 中）
func get_fulfillment_items(inventory: Array) -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	var temp_inventory = inventory.duplicate()
	
	for req: Dictionary in requirements:
		var count: int = req.get("count", 1)
		var item_id: StringName = req.get("item_id", &"")
		var min_rarity: int = req.get("min_rarity", 0)
		
		var found_count: int = 0
		var indices: Array[int] = []
		
		for i: int in temp_inventory.size():
			var it: ItemInstance = temp_inventory[i]
			if it.item_data.id == item_id and it.rarity >= min_rarity:
				found_count += 1
				indices.append(i)
				result.append(it)
				if found_count >= count:
					break
					
		indices.sort()
		indices.reverse()
		for idx: int in indices:
			temp_inventory.pop_at(idx)
			
	return result




