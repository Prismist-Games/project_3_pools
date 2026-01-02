extends PoolAffixEffect
class_name TradeInAffixEffect

## 【以旧换新的】
## 1. 玩家点击奖池 -> 进入 "选择消耗品" 模式。
## 2. 玩家点击背包中任意一个 非主线 物品。
## 3. 执行置换: 移除该物品，从奖池中随机抽取一个 同品质 的新物品放入背包。
## 4. 小概率 (5%) 升级品质。
## 5. 消耗: 1 金币


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
	EventBus.game_event.emit(&"enter_selection_mode", {
		"type": "trade_in",
		"pool_type": ctx.pool_type,
		"callback": func(item_to_trade: ItemInstance):
			if item_to_trade == null:
				return
				
			# 检查金币 (trade_in 消耗 1)
			if not GameManager.spend_gold(1):
				# 这里可能需要 UI 提示金币不足
				return
				
			# 执行置换
			var rarity = item_to_trade.rarity
			
			# 5% 概率升级品质
			if GameManager.rng.randf() < 0.05:
				rarity = min(rarity + 1, Constants.Rarity.LEGENDARY)
				
			# 从奖池中抽取同品质物品
			var pool_items = GameManager.get_items_for_type(ctx.pool_type)
			if pool_items.is_empty():
				pool_items = GameManager.all_items
			
			var new_item_data = pool_items.pick_random()
			var new_item_instance = ItemInstance.new(new_item_data, rarity)
			
			# 移除旧物品，添加新物品
			GameManager.remove_items([item_to_trade])
			GameManager.add_item(new_item_instance)
			
			EventBus.item_obtained.emit(new_item_instance)
			
			# 刷新奖池（因为我们使用了这次机会）
			# 注意：这里的 ctx 是 draw_from_pool 里的局部变量，
			# 我们需要确保 PoolSystem 知道这次交互完成了并刷新。
			# 实际上，在 draw_from_pool 中我们设置了 skip_draw，
			# 如果我们想要在 trade_in 成功后刷新，我们需要通知 PoolSystem。
			EventBus.game_event.emit(&"pool_draw_completed", {"pool_id": ctx.pool_id})
	})

