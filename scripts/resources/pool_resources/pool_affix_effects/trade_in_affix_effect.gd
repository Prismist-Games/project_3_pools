extends PoolAffixEffect
class_name TradeInAffixEffect

## 【以旧换新的】
## 1. 玩家点击奖池 -> 进入 "选择消耗品" 模式。
## 2. 玩家点击背包中任意一个 非主线 物品。
## 3. 执行置换: 移除该物品，从奖池中随机抽取一个 同品质 的新物品放入背包。
## 4. 小概率 (5%) 升级品质。
## 5. 消耗: 1 金币

@export var cost: int = 1


func on_event(event_id: StringName, context: RefCounted) -> void:
	if event_id != &"draw_requested":
		return
	var ctx: DrawContext = context as DrawContext
	if ctx == null:
		return
	
	# 标记跳过标准逻辑，且先不扣费（置换成功后再扣）
	ctx.skip_draw = true
	ctx.gold_cost = 0
	
	# 进入选择模式
	# 我们发送一个 game_event，UI (Inventory) 会监听它
	var selection_data = ContextProxy.new({
		"type": "trade_in",
		"item_type": ctx.item_type,
		"callback": func(item_to_trade: ItemInstance):
			if item_to_trade == null:
				return
				
			# 1. 检查金币 (trade_in 消耗)
			if not GameManager.spend_gold(cost):
				return
				
			# 2. 决定新物品品质 (5% 概率升级)
			var rarity = item_to_trade.rarity
			if GameManager.rng.randf() < 0.05:
				rarity = min(rarity + 1, Constants.Rarity.MYTHIC)
				
			# 3. 从奖池中随机获取新物品数据 (确保产出物品与投入的不同)
			var pool_items: Array[ItemData] = GameManager.get_items_for_type(ctx.item_type)
			if pool_items.is_empty():
				pool_items = GameManager.all_items
			
			# 过滤掉当前交换的物品
			var filtered_items: Array = pool_items.filter(func(d): return d != item_to_trade.item_data)
			
			# 如果过滤后为空（说明池子里只有这一个物品类型），尝试从全局普通物品中选取
			if filtered_items.is_empty():
				var all_normal: Array[ItemData] = GameManager.get_all_normal_items()
				filtered_items = all_normal.filter(func(d): return d != item_to_trade.item_data)
			
			if filtered_items.is_empty():
				push_error("Trade-in error: No items found to replace " + item_to_trade.item_data.item_name)
				return
			
			var new_item_data = filtered_items.pick_random()
			var new_item_instance = ItemInstance.new(new_item_data, rarity)
			
			# 4. 执行置换
			InventorySystem.remove_items([item_to_trade])
			
			EventBus.item_obtained.emit(new_item_instance)
			
			# 5. 刷新奖池
			EventBus.game_event.emit(&"pool_draw_completed", ContextProxy.new({"pool_id": ctx.pool_id}))
	})
	
	EventBus.game_event.emit(&"enter_selection_mode", selection_data)
