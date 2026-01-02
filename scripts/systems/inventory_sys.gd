extends Node
class_name InventorySystem

## 背包系统：处理物品的添加、移除、合成和回收逻辑。

func _ready() -> void:
	pass

## 合成两个物品
func synthesize_items(idx1: int, idx2: int) -> bool:
	var items = GameManager.inventory
	if idx1 < 0 or idx1 >= items.size() or idx2 < 0 or idx2 >= items.size() or idx1 == idx2:
		return false
		
	var item1: ItemInstance = items[idx1]
	var item2: ItemInstance = items[idx2]
	
	# 合成规则：同名、同品质、非绝育
	if item1.item_data.id == item2.item_data.id \
		and item1.rarity == item2.rarity \
		and not item1.sterile and not item2.sterile \
		and item1.rarity < Constants.Rarity.MYTHIC:
		
		# 移除旧物品
		var indices = [idx1, idx2]
		indices.sort()
		GameManager.remove_item_at(indices[1])
		GameManager.remove_item_at(indices[0])
		
		# 添加新物品（品质+1）
		var next_rarity = item1.rarity + 1
		var new_item = ItemInstance.new(item1.item_data, next_rarity)
		GameManager.add_item(new_item)
		
		return true
	
	return false

## 回收物品
func salvage_item(index: int) -> void:
	var item: ItemInstance = GameManager.remove_item_at(index)
	if item == null:
		return
		
	var context = SalvageContext.new()
	context.item = item
	
	# 计算基础奖励
	context.reward_gold = Constants.rarity_salvage_value(item.rarity)
	
	# 发出信号让技能修改奖励
	EventBus.game_event.emit(&"salvage_requested", context)
	
	# 给予奖励
	if context.reward_gold > 0:
		GameManager.add_gold(context.reward_gold)
	if context.reward_tickets > 0:
		GameManager.add_tickets(context.reward_tickets)
		
	EventBus.game_event.emit(&"salvage_finished", context)

