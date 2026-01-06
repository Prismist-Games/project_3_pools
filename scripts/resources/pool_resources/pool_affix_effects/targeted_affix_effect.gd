extends PoolAffixEffect
class_name TargetedAffixEffect

## 【有的放矢的】
## 1. 玩家点击奖池 -> 扣除金币。
## 2. 展示该奖池内所有可能的物品类型（如所有水果）。
## 3. 玩家手动点击选择想要的那一种。
## 4. 必定获得该物品（品质随机）。
## 5. 消耗: 4 金币


func on_event(event_id: StringName, context: RefCounted) -> void:
	if event_id != &"draw_requested":
		return
	var ctx: DrawContext = context as DrawContext
	if ctx == null:
		return
	
	# 标记跳过标准抽奖逻辑
	ctx.skip_draw = true
	
	# 获取该奖池所有可能的物品
	var possible_items: Array[ItemData] = GameManager.get_items_for_type(ctx.item_type)
	if possible_items.is_empty():
		possible_items = GameManager.all_items
		
	# 发出信号显示选择弹窗
	EventBus.modal_requested.emit(&"targeted_selection", {
		"items": possible_items,
		"callback": func(selected_data: ItemData):
			if selected_data != null:
				var rarity = Constants.pick_weighted_index(ctx.rarity_weights, GameManager.rng)
				var item_instance = ItemInstance.new(selected_data, rarity)
				EventBus.item_obtained.emit(item_instance)
	})



