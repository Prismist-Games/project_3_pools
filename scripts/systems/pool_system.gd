extends Node
class_name PoolSystem

## 奖池系统：管理奖池生成、抽奖逻辑。

var current_pools: Array[PoolConfig] = []
var max_pools: int = 3

func _ready() -> void:
	if not GameManager.is_node_ready():
		await GameManager.ready
	call_deferred("refresh_pools")
	# 奖池刷新的时机改为在玩家获取新物品时
	EventBus.item_obtained.connect(func(_item): call_deferred("refresh_pools"))


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
	ctx.affix_id = pool.get_affix_id()
	ctx.gold_cost = pool.gold_cost
	ctx.ticket_cost = pool.ticket_cost
	
	# 填充默认权重
	var stage_data = GameManager.current_stage_data
	if stage_data != null:
		ctx.rarity_weights = stage_data.get_weights()
	elif GameManager.game_config != null:
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
	
	# 1. 词缀预处理
	pool.dispatch_affix_event(&"draw_requested", ctx)
	
	# 2. 技能预处理
	EventBus.draw_requested.emit(ctx)
	
	# 检查资源
	if ctx.gold_cost > 0:
		if not GameManager.spend_gold(ctx.gold_cost):
			return false
	if ctx.ticket_cost > 0:
		if not GameManager.spend_tickets(ctx.ticket_cost):
			return false
			
	# 如果被词缀或技能标记为跳过（通常是进入了某种交互流程）
	if ctx.skip_draw:
		# 注意：此时 gold/tickets 可能已经扣除（由词缀决定是否在 draw_requested 中修改 cost）
		# 此时不再立即刷新，而是等待词缀逻辑最终触发 item_obtained
		return true

	# 3. 执行抽奖
	if ctx.item_type == Constants.ItemType.MAINLINE:
		_do_mainline_draw(ctx)
	else:
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
			
		rarity = maxi(rarity, ctx.min_rarity)
		
		var items = GameManager.get_items_for_type(ctx.item_type)
		if items.is_empty():
			items = GameManager.get_all_normal_items()
			
		var item_data = items.pick_random()
		var item_instance = ItemInstance.new(item_data, rarity, ctx.force_sterile)
		ctx.result_items.append(item_instance)
		
		EventBus.item_obtained.emit(item_instance)


func _do_mainline_draw(ctx: DrawContext) -> void:
	var rng = GameManager.rng
	var stage = GameManager.mainline_stage
	var stage_data = GameManager.get_mainline_stage_data(stage)
	
	var drop_rate = 0.3
	if GameManager.game_config != null:
		drop_rate = GameManager.game_config.mainline_drop_rate
		
	for i in range(ctx.item_count):
		var item_instance: ItemInstance = null
		
		# 一次抽奖（即便产出多个）通常只允许一个主线道具，其余为填充物
		var should_drop_mainline = (i == 0) and (rng.randf() < drop_rate)
		
		if should_drop_mainline and stage_data != null and stage_data.mainline_item != null:
			item_instance = ItemInstance.new(stage_data.mainline_item, Constants.Rarity.MYTHIC, false)
		else:
			# 掉落填充物逻辑
			var rarity = Constants.Rarity.EPIC
			if stage_data != null:
				rarity = stage_data.filler_rarity
				# 如果是阶段 5，且不是神话，有概率出传说
				if stage == 5 and rng.randf() < 0.1:
					rarity = Constants.Rarity.LEGENDARY
			
			var items = GameManager.get_all_normal_items()
			if not items.is_empty():
				var item_data = items.pick_random()
				item_instance = ItemInstance.new(item_data, rarity, false)
		
		if item_instance:
			ctx.result_items.append(item_instance)
			EventBus.item_obtained.emit(item_instance)


func _generate_pool(excluded_types: Array[Constants.ItemType] = [], excluded_affixes: Array[RefCounted] = []) -> PoolConfig:
	var rng = GameManager.rng
	var pool: PoolConfig
	
	# 检查是否可以生成核心奖池 (核心池类型唯一)
	var can_mainline = Constants.ItemType.MAINLINE not in excluded_types
	
	if can_mainline and GameManager.tickets >= 10 and GameManager.mainline_stage <= Constants.MAINLINE_STAGES:
		var mainline_chance = 0.5
		if GameManager.game_config != null:
			mainline_chance = GameManager.game_config.mainline_chance
		if rng.randf() < mainline_chance:
			pool = _generate_mainline_pool()
		else:
			pool = _generate_normal_pool(excluded_types, excluded_affixes)
	else:
		pool = _generate_normal_pool(excluded_types, excluded_affixes)
	
	# 分配唯一 ID
	pool.id = StringName(str(Time.get_ticks_msec()) + "_" + str(rng.randi()))
	return pool


func _generate_mainline_pool() -> PoolConfig:
	var pool = PoolConfig.new()
	pool.item_type = Constants.ItemType.MAINLINE
	pool.ticket_cost = 10
	if GameManager.game_config != null:
		pool.ticket_cost = GameManager.game_config.mainline_ticket_cost
	return pool


func _generate_normal_pool(excluded_types: Array[Constants.ItemType] = [], excluded_affixes: Array[RefCounted] = []) -> PoolConfig:
	var pool = PoolConfig.new()
	var stage_data = GameManager.current_stage_data
	
	# 1. 随机选择物品类型，排除已使用的类型
	var available_types: Array[Constants.ItemType] = []
	var source_types: Array[Constants.ItemType] = []
	
	if stage_data != null and not stage_data.unlocked_item_types.is_empty():
		source_types = stage_data.unlocked_item_types
	else:
		source_types = Constants.get_normal_item_types()
		
	for t in source_types:
		if t not in excluded_types:
			available_types.append(t)
	
	if available_types.is_empty():
		# 如果所有解锁类型都被占用了（理论上不应该，因为 max_pools=3, types=5），则随便选一个非空类型
		pool.item_type = source_types.pick_random() if not source_types.is_empty() else Constants.ItemType.FRUIT
	else:
		pool.item_type = available_types.pick_random()
	
	# 2. 随机选择词缀，排除已使用的词缀
	if stage_data != null and stage_data.has_pool_affixes:
		_assign_random_affix(pool, excluded_affixes)
	
	# 3. 计算费用
	var initial_cost = 5
	if GameManager.game_config != null:
		initial_cost = GameManager.game_config.normal_draw_gold_cost
	
	if pool.affix_data != null:
		pool.gold_cost = pool.affix_data.base_gold_cost
	else:
		pool.gold_cost = initial_cost
			
	return pool


func _assign_random_affix(pool: PoolConfig, excluded_affixes: Array[RefCounted] = []) -> void:
	var all_affixes = GameManager.all_pool_affixes
	var available_affixes: Array = []
	
	for aff in all_affixes:
		if aff not in excluded_affixes:
			available_affixes.append(aff)
			
	if not available_affixes.is_empty():
		pool.affix_data = available_affixes.pick_random()
