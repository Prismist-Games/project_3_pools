extends PoolAffixEffect
class_name TradeInAffixEffect

## 【以旧换新的】
## 1. 玩家点击奖池 -> 进入 "选择消耗品" 模式（门开，槽空）。
## 2. 玩家点击背包中任意一个 非主线 物品 -> 物品飞入奖池 -> 门关 -> shake。
## 3. 执行置换: 移除该物品，从奖池中随机抽取一个 同品质 的新物品。
## 4. 小概率 (5%) 升级品质。
## 5. 消耗: 1 金币
## 6. 进入正常揭示流程（开门 → 出东西）。

@export var cost: int = 1


func on_event(event_id: StringName, context: RefCounted) -> void:
	if event_id != &"draw_requested":
		return
	var ctx: DrawContext = context as DrawContext
	if ctx == null:
		return
	
	# 检查金币是否足够（在设置 skip_draw 之前）
	if GameManager.gold < cost:
		# 不设置 skip_draw，让 PoolSystem 正常检查金币并失败（触发抖动）
		return
	
	# 标记跳过标准逻辑，且先不扣费（置换成功后再扣）
	ctx.skip_draw = true
	ctx.gold_cost = 0
	
	# 从 meta 中获取 pool_index（由 PoolSystem 设置）
	var pool_index: int = ctx.meta.get("pool_index", -1)
	
	# 进入选择模式
	var selection_data = ContextProxy.new({
		"type": "trade_in",
		"pool_index": pool_index,
		"item_type": ctx.item_type,
		"force_sterile": ctx.force_sterile, # 传递绝育标记
		"callback": func(item_to_trade: ItemInstance):
			if item_to_trade == null:
				return
				
			# 1. 检查金币 (不应该发生，因为点击奖池时已检查)
			if not GameManager.spend_gold(cost):
				push_warning("Trade-in: Insufficient gold (should be checked before)")
				return
				
			# 2. 决定新物品品质 (5% 概率升级)
			var rarity = item_to_trade.rarity
			if GameManager.rng.randf() < 0.05:
				rarity = min(rarity + 1, Constants.Rarity.MYTHIC)
				
			# 3. 从奖池中随机获取新物品数据 (确保产出物品与投入的不同)
			var pool_items: Array[ItemData] = GameManager.get_items_for_type(ctx.item_type)
			if pool_items.is_empty():
				pool_items = GameManager.all_items
			
			# 过滤掉当前交换的物品 (按ID过滤,确保不会换出同种类物品)
			var traded_item_id: StringName = item_to_trade.item_data.id
			var filtered_items: Array = pool_items.filter(func(d: ItemData): return d.id != traded_item_id)
			
			# 如果过滤后为空（说明池子里只有这一个物品种类），尝试从全局普通物品中选取
			if filtered_items.is_empty():
				var all_normal: Array[ItemData] = GameManager.get_all_normal_items()
				filtered_items = all_normal.filter(func(d: ItemData): return d.id != traded_item_id)
			
			if filtered_items.is_empty():
				push_error("Trade-in error: No items found to replace " + str(item_to_trade.item_data.id))
				return
			
			var new_item_data = filtered_items.pick_random()
			# 保持绝育状态: 如果投入的物品是绝育的，或者当前奖池强制绝育
			var should_be_sterile = ctx.force_sterile or item_to_trade.sterile
			var new_item_instance = ItemInstance.new(new_item_data, rarity, should_be_sterile)
			
			# 4. 执行置换：移除旧物品
			InventorySystem.remove_items([item_to_trade])
			
			# 5. 发出 item_obtained 信号
			EventBus.item_obtained.emit(new_item_instance)
	})
	
	EventBus.game_event.emit(&"enter_selection_mode", selection_data)
