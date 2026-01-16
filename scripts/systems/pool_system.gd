extends Node

## 奖池系统：管理奖池生成、抽奖逻辑。

var current_pools: Array[PoolConfig] = []
var max_pools: int = 3

func _ready() -> void:
	if not GameManager.is_node_ready():
		await GameManager.ready
	# call_deferred("refresh_pools")
	# 奖池刷新的时机改为在 UI 动画序列结束后手动触发，不再自动连接
	# EventBus.item_obtained.connect(func(_item): call_deferred("refresh_pools"))


func refresh_pools() -> void:
	current_pools.clear()
	var excluded_types: Array[Constants.ItemType] = []
	var excluded_affixes: Array[RefCounted] = [] # PoolAffixData
	
	for i in range(max_pools):
		var pool = _generate_pool(excluded_types, excluded_affixes)
		current_pools.append(pool)
		
		# 记录已使用的类型和词缀
		excluded_types.append(pool.item_type)
		if pool.affix_data != null:
			excluded_affixes.append(pool.affix_data)
	
	EventBus.pools_refreshed.emit(current_pools)


func draw_from_pool(index: int) -> bool:
	if index < 0 or index >= current_pools.size():
		return false
		
	var pool = current_pools[index]
	
	# 创建上下文
	var ctx = DrawContext.new()
	ctx.pool_id = pool.id
	ctx.item_type = pool.item_type
	ctx.gold_cost = pool.gold_cost
	ctx.meta["pool_index"] = index # 传递奖池索引给词缀效果
	
	# 填充默认权重
	if GameManager.game_config != null:
		var cfg = GameManager.game_config
		ctx.rarity_weights = PackedFloat32Array([
			cfg.weight_common,
			cfg.weight_uncommon,
			cfg.weight_rare,
			cfg.weight_epic,
			cfg.weight_legendary
		])
	else:
		ctx.ensure_default_rarity_weights()
	
	# 1. 技能预处理（先于词缀，让技能如时来运转能设置 min_rarity）
	EventBus.draw_requested.emit(ctx)
	
	# 2. 词缀预处理（后于技能，能使用技能设置的参数）
	pool.dispatch_affix_event(&"draw_requested", ctx)
	
	# 检查资源
	if ctx.gold_cost > 0:
		if not GameManager.spend_gold(ctx.gold_cost):
			return false
			
	# 如果被词缀或技能标记为跳过（通常是进入了某种交互流程）
	if ctx.skip_draw:
		# 注意：此时 gold 可能已经扣除（由词缀决定是否在 draw_requested 中修改 cost）
		# 此时不再立即刷新，而是等待词缀逻辑最终触发 item_obtained
		return true

	# 3. 执行抽奖
	_do_normal_draw(ctx)

	# 4. 词缀后处理
	pool.dispatch_affix_event(&"draw_finished", ctx)
	
	# 5. 技能后处理
	EventBus.draw_finished.emit(ctx)
	
	return true


func _do_normal_draw(ctx: DrawContext) -> void:
	for i in range(ctx.item_count):
		var rarity = ctx.force_rarity
		if rarity == -1:
			rarity = Constants.pick_weighted_index(ctx.rarity_weights, GameManager.rng)
		
		# min_rarity 只对第一个物品生效（用于时来运转+稀碎场景）
		if i == 0:
			rarity = maxi(rarity, ctx.min_rarity)
		
		var items = GameManager.get_items_for_type(ctx.item_type)
		if items.is_empty():
			items = GameManager.get_all_normal_items()
			
		if items.is_empty():
			push_error("PoolSystem: No items found to draw! (Type: %s)" % ctx.item_type)
			return

		var item_data = items.pick_random()
		var item_instance = ItemInstance.new(item_data, rarity, ctx.force_sterile)
		ctx.result_items.append(item_instance)
		
		EventBus.item_obtained.emit(item_instance)
	
	# ERA_4: 抽奖后递减保质期（通过效果系统）
	var cfg = EraManager.current_config if EraManager else null
	if cfg:
		var shelf_life_effect = cfg.get_effect_of_type("ShelfLifeEffect")
		if shelf_life_effect:
			shelf_life_effect.decrement_all_shelf_lives(InventorySystem)


func _generate_pool(excluded_types: Array[Constants.ItemType] = [], excluded_affixes: Array[RefCounted] = []) -> PoolConfig:
	var rng = GameManager.rng
	var pool: PoolConfig = _generate_normal_pool(excluded_types, excluded_affixes)
	
	# 分配唯一 ID
	pool.id = StringName(str(Time.get_ticks_msec()) + "_" + str(rng.randi()))
	return pool


func _generate_normal_pool(excluded_types: Array[Constants.ItemType] = [], excluded_affixes: Array[RefCounted] = []) -> PoolConfig:
	var pool = PoolConfig.new()
	
	# 1. 随机选择物品类型，排除已使用的类型
	var available_types: Array[Constants.ItemType] = []
	var source_types: Array[Constants.ItemType] = UnlockManager.get_unlocked_item_types()
		
	for t in source_types:
		if t not in excluded_types:
			available_types.append(t)
	
	if available_types.is_empty():
		# 如果所有解锁类型都被占用了（理论上不应该，因为 max_pools=3, types=5），则随便选一个非空类型
		pool.item_type = source_types.pick_random() if not source_types.is_empty() else Constants.ItemType.TRIANGLE
	else:
		pool.item_type = available_types.pick_random()
	
	# 2. 随机选择词缀 (开局即拥有)
	_assign_random_affix(pool, excluded_affixes)
	
	# 3. 计算费用
	var initial_cost = 5
	if GameManager.game_config != null:
		initial_cost = GameManager.game_config.normal_draw_gold_cost
	
	# ERA_2: 价格波动（通过效果系统）
	var cfg = EraManager.current_config
	if cfg:
		var price_effect = cfg.get_effect_of_type("PriceFluctuationEffect")
		if price_effect:
			price_effect.apply_to_pool(pool, GameManager.rng)
			return pool
	
	# 默认逻辑
	if pool.affix_data != null:
		pool.gold_cost = pool.affix_data.base_gold_cost
	else:
		pool.gold_cost = initial_cost
			
	return pool


func _assign_random_affix(pool: PoolConfig, excluded_affixes: Array[RefCounted] = []) -> void:
	var all_affixes = GameManager.all_pool_affixes
	var available_affixes: Array = []
	
	for aff in all_affixes:
		if aff not in excluded_affixes and UnlockManager.is_pool_affix_enabled(aff.id):
			available_affixes.append(aff)
			
	if not available_affixes.is_empty():
		pool.affix_data = available_affixes.pick_random()
