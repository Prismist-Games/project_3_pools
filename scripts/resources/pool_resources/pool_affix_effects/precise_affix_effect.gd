extends PoolAffixEffect
class_name PreciseAffixEffect

## 【精准的】
## 1. 玩家点击奖池 -> 扣除金币。
## 2. 系统随机生成 2 个不同的候选物品。
## 3. 弹出 "二选一" 窗口。
## 4. 玩家选择其中一个获得，另一个丢弃。
## 5. 消耗: 2 金币


func on_event(event_id: StringName, context: RefCounted) -> void:
	if event_id != &"draw_requested":
		return
	var ctx: DrawContext = context as DrawContext
	if ctx == null:
		return
	
	# 标记跳过标准抽奖逻辑
	ctx.skip_draw = true
	
	# 生成两个候选物品
	var items: Array[ItemInstance] = []
	for i in range(2):
		var rarity = Constants.pick_weighted_index(ctx.rarity_weights, GameManager.rng)
		var pool_items = GameManager.get_items_for_type(ctx.item_type)
		if pool_items.is_empty():
			pool_items = GameManager.all_items
		var item_data = pool_items.pick_random()
		items.append(ItemInstance.new(item_data, rarity))
	
	# 传递给 PreciseSelectionState 处理二选一交互
	EventBus.modal_requested.emit(&"precise_selection", {
		"items": items,
		"source_pool_index": ctx.meta.get("pool_index", -1)
	})



