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
	
	# 捕获当前上下文数据（供闭包使用）
	var rarity_weights = ctx.rarity_weights.duplicate()
	var pool_index: int = ctx.meta.get("pool_index", -1)
	var item_type = ctx.item_type
	
	# 发出信号显示选择弹窗（使用 "5 Choose 1" 面板）
	EventBus.modal_requested.emit(&"targeted_selection", {
		"source_pool_index": pool_index,
		"pool_item_type": item_type,
		"callback": func(selected_data: ItemData):
			if selected_data != null:
				var rarity = Constants.pick_weighted_index(rarity_weights, GameManager.rng)
				return ItemInstance.new(selected_data, rarity)
			return null
	})



