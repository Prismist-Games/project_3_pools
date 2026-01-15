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
	
	# 检查金币是否足够（在设置 skip_draw 之前）
	if GameManager.gold < ctx.gold_cost:
		# 不设置 skip_draw，让 PoolSystem 正常检查金币并失败（触发抖动）
		return
	
	# 标记跳过标准抽奖逻辑
	ctx.skip_draw = true
	
	# 生成两个候选物品
	var items: Array[ItemInstance] = []
	
	# 获取候选池
	var pool_items: Array[ItemData] = GameManager.get_items_for_type(ctx.item_type)
	if pool_items.is_empty():
		pool_items = GameManager.get_all_normal_items()
	if pool_items.is_empty():
		pool_items = GameManager.all_items
		
	# 确保不出现重复物品 (尽可能选择不同的 item_data)
	var selected_data: Array[ItemData] = []
	
	if pool_items.size() >= 2:
		# 如果池中物品足够，随机选出 2 个不重复的
		var shuffled_items = pool_items.duplicate()
		shuffled_items.shuffle()
		selected_data.append(shuffled_items[0])
		selected_data.append(shuffled_items[1])
	else:
		# 物品不足 2 个，只能重复
		for i in range(2):
			selected_data.append(pool_items.pick_random())
			
	for i in range(2):
		var rarity = Constants.pick_weighted_index(ctx.rarity_weights, GameManager.rng)
		# 应用最低稀有度限制（如时来运转设置的 min_rarity）
		rarity = maxi(rarity, ctx.min_rarity)
		var item_data = selected_data[i]
		items.append(ItemInstance.new(item_data, rarity))
	
	# 传递给 PreciseSelectionState 处理二选一交互
	EventBus.modal_requested.emit(&"precise_selection", {
		"items": items,
		"source_pool_index": ctx.meta.get("pool_index", -1)
	})
