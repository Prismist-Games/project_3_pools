extends Resource
class_name OrderData

## 订单数据：表示一个生成的订单实例（运行时创建）。

## 需求项列表：Array[Dictionary]，每个 Dict 格式为：
## { "item_id": StringName, "min_rarity": int, "count": int }
@export var requirements: Array[Dictionary] = []

@export var reward_gold: int = 0

## 剩余刷新次数
@export var refresh_count: int = 1

## 运行时标识
@export var is_mainline: bool = false
var order_id: StringName = &""


func _init() -> void:
	order_id = &"order_%d_%d" % [Time.get_ticks_msec(), randi() % 1000]


## 检查背包中是否有足够的物品满足该订单
func can_fulfill(inventory: Array) -> bool:
	if requirements.is_empty(): return true
	
	for req in requirements:
		var item_id = req.get("item_id", &"")
		var min_rarity = req.get("min_rarity", 0)
		
		var found = false
		for it in inventory:
			if it != null and it.item_data.id == item_id and it.rarity >= min_rarity:
				found = true
				break
		
		if not found:
			return false
			
	return true


## 获取满足该订单的物品实例列表（从 inventory 中，用于自动选择）
func get_fulfillment_items(inventory: Array) -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	
	for req in requirements:
		var item_id = req.get("item_id", &"")
		var min_rarity = req.get("min_rarity", 0)
		
		var best_match: ItemInstance = null
		for it in inventory:
			if it != null and it.item_data.id == item_id and it.rarity >= min_rarity:
				if best_match == null or it.rarity > best_match.rarity:
					best_match = it
		
		if best_match != null and not best_match in result:
			result.append(best_match)
			
	return result


## 智能选择：在背包中寻找能满足该订单的最佳物品（优先高品质）
func find_smart_selection(inventory: Array) -> Array[int]:
	var result_indices: Array[int] = []
	
	for req in requirements:
		var item_id = req.get("item_id", &"")
		var min_rarity = req.get("min_rarity", 0)
		
		var best_idx = -1
		for i in range(inventory.size()):
			var it = inventory[i]
			if it != null and it.item_data.id == item_id and it.rarity >= min_rarity:
				if best_idx == -1 or it.rarity > inventory[best_idx].rarity:
					best_idx = i
		
		if best_idx != -1 and not best_idx in result_indices:
			result_indices.append(best_idx)
			
	return result_indices


## 计算奖励预览：返回是否满足以及计算后的金币/奖券
func calculate_preview_rewards(selected_items: Array) -> Dictionary:
	var res = {
		"is_satisfied": false,
		"gold": reward_gold,
		"fulfilled_requirements": [] # 记录哪些需求已满足
	}
	
	# 检查单个需求的满足情况（用于图标亮起）
	# 修改：一个物品可以满足多个需求（不消耗匹配项）
	for i in range(requirements.size()):
		var req = requirements[i]
		var item_id = req.get("item_id", &"")
		var min_rarity = req.get("min_rarity", 0)
		
		var is_req_fulfilled = false
		for it in selected_items:
			if it != null and it.item_data.id == item_id and it.rarity >= min_rarity:
				is_req_fulfilled = true
				break
		
		if is_req_fulfilled:
			res.fulfilled_requirements.append(i)
	
	var validation = validate_selection(selected_items)
	if validation.valid:
		res.is_satisfied = true
		res.gold = roundi(reward_gold * (1.0 + validation.total_overflow_bonus))
	
	return res


## 检查提供的物品列表是否满足订单需求（手动选择模式）
func validate_selection(selected_items: Array) -> Dictionary:
	var result = {
		"valid": false,
		"total_overflow_bonus": 0.0,
		"consumed_items": selected_items
	}
	
	if selected_items.is_empty() and not requirements.is_empty():
		return result
		
	var total_bonus = 0.0
	
	for req in requirements:
		var item_id = req.get("item_id", &"")
		var min_rarity = req.get("min_rarity", 0)
		
		# 寻找最佳匹配项（最高品质以获得最高加成）
		var best_match: ItemInstance = null
		for it in selected_items:
			if it != null and it.item_data.id == item_id and it.rarity >= min_rarity:
				if best_match == null or it.rarity > best_match.rarity:
					best_match = it
		
		if best_match == null:
			return result # 任何一个需求没满足，整个订单就不合法
		
		# 计算该需求槽位的加成
		var overflow = Constants.rarity_bonus(best_match.rarity) - Constants.rarity_bonus(min_rarity)
		total_bonus += maxf(overflow, 0.0)
			
	result.valid = true
	result.total_overflow_bonus = total_bonus
	return result
