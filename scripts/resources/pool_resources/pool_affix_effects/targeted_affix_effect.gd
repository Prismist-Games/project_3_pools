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
	
	# 检查金币是否足够（在设置 skip_draw 之前）
	if GameManager.gold < ctx.gold_cost:
		# 不设置 skip_draw，让 PoolSystem 正常检查金币并失败（触发抖动）
		return
	
	# 标记跳过标准抽奖逻辑
	ctx.skip_draw = true
	
	# 捕获当前上下文数据（供闭包使用）
	var rarity_weights = ctx.rarity_weights.duplicate()
	var min_rarity = ctx.min_rarity # 捕获最低稀有度（如时来运转设置的）
	var pool_index: int = ctx.meta.get("pool_index", -1)
	var item_type = ctx.item_type
	var gold_cost: int = ctx.gold_cost # 捕获金币消耗，稍后手动扣除
	
	# 设置 ctx.gold_cost = 0，防止 PoolSystem 自动扣除
	ctx.gold_cost = 0
	
	# 发出信号显示选择弹窗（使用 "5 Choose 1" 面板）
	EventBus.modal_requested.emit(&"targeted_selection", {
		"source_pool_index": pool_index,
		"pool_item_type": item_type,
		"gold_cost": gold_cost,
		"callback": func(selected_data: ItemData):
			if selected_data != null:
				var rarity = Constants.pick_weighted_index(rarity_weights, GameManager.rng)
				# 应用最低稀有度限制
				rarity = maxi(rarity, min_rarity)
				return ItemInstance.new(selected_data, rarity)
			return null
	})
