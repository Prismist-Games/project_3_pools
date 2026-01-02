extends Node
class_name PoolSystem

## 奖池系统：管理奖池生成、抽奖逻辑。

var current_pools: Array[PoolConfig] = []
var max_pools: int = 3

func _ready() -> void:
	if not GameManager.is_node_ready():
		await GameManager.ready
	refresh_pools()
	EventBus.game_event.connect(_on_game_event)


func _on_game_event(event_id: StringName, payload: Variant) -> void:
	if event_id == &"pool_draw_completed":
		var pool_id = payload.get("pool_id")
		for i in range(current_pools.size()):
			if current_pools[i].id == pool_id:
				current_pools[i] = _generate_pool()
				EventBus.pools_refreshed.emit(current_pools)
				break


func refresh_pools() -> void:
	current_pools.clear()
	for i in range(max_pools):
		current_pools.append(_generate_pool())
	
	EventBus.pools_refreshed.emit(current_pools)


func draw_from_pool(index: int) -> bool:
	if index < 0 or index >= current_pools.size():
		return false
		
	var pool = current_pools[index]
	
	# 创建上下文
	var ctx = DrawContext.new()
	ctx.pool_id = pool.id
	ctx.pool_type = pool.pool_type
	ctx.affix_id = pool.get_affix_id()
	ctx.gold_cost = pool.gold_cost
	ctx.ticket_cost = pool.ticket_cost
	
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
		# 我们决定如果 skip_draw 为 true 且 cost > 0，则依然刷新奖池
		if ctx.gold_cost > 0 or ctx.ticket_cost > 0:
			current_pools[index] = _generate_pool()
			EventBus.pools_refreshed.emit(current_pools)
		return true

	# 3. 执行抽奖
	if ctx.pool_type == Constants.POOL_TYPE_MAINLINE:
		_do_mainline_draw(ctx)
	else:
		_do_normal_draw(ctx)

	# 4. 词缀后处理
	pool.dispatch_affix_event(&"draw_finished", ctx)
	
	# 5. 技能后处理
	EventBus.draw_finished.emit(ctx)
	
	# 抽完后刷新该奖池
	current_pools[index] = _generate_pool()
	EventBus.pools_refreshed.emit(current_pools)
	
	return true


func _do_normal_draw(ctx: DrawContext) -> void:
	for i in range(ctx.item_count):
		var rarity = ctx.force_rarity
		if rarity == -1:
			rarity = Constants.pick_weighted_index(ctx.rarity_weights, GameManager.rng)
			
		rarity = maxi(rarity, ctx.min_rarity)
		
		var items = GameManager.get_items_for_type(ctx.pool_type)
		if items.is_empty():
			items = GameManager.all_items
			
		var item_data = items.pick_random()
		var item_instance = ItemInstance.new(item_data, rarity, ctx.force_sterile)
		ctx.result_items.append(item_instance)
		
		GameManager.add_item(item_instance)
		EventBus.item_obtained.emit(item_instance)


func _do_mainline_draw(ctx: DrawContext) -> void:
	var rng = GameManager.rng
	var drop_rate = 0.3
	var filler_legendary_rate = 0.1
	if GameManager.game_config != null:
		drop_rate = GameManager.game_config.mainline_drop_rate
		filler_legendary_rate = GameManager.game_config.mainline_filler_legendary_rate
		
	# 掉落规则：30% 概率掉落当前阶段主线道具（神话）
	if rng.randf() < drop_rate:
		var stage = GameManager.mainline_stage
		var stage_data = GameManager.get_mainline_stage_data(stage)
		if stage_data != null:
			var item_instance = ItemInstance.new(stage_data.mainline_item, Constants.Rarity.MYTHIC, false)
			ctx.result_items.append(item_instance)
			GameManager.add_item(item_instance)
			EventBus.item_obtained.emit(item_instance)
			return

	# 70% 概率掉落填充物 (史诗或传说)
	var rarity = Constants.Rarity.EPIC
	if rng.randf() < filler_legendary_rate:
		rarity = Constants.Rarity.LEGENDARY
		
	var items = GameManager.all_items
	var item_data = items.pick_random()
	var filler_instance = ItemInstance.new(item_data, rarity, false)
	ctx.result_items.append(filler_instance)
	GameManager.add_item(filler_instance)
	EventBus.item_obtained.emit(filler_instance)


func _generate_pool() -> PoolConfig:
	var rng = GameManager.rng
	var pool: PoolConfig
	if GameManager.tickets >= 10 and GameManager.mainline_stage <= Constants.MAINLINE_STAGES:
		var mainline_chance = 0.5
		if GameManager.game_config != null:
			mainline_chance = GameManager.game_config.mainline_chance
		if rng.randf() < mainline_chance:
			pool = _generate_mainline_pool()
		else:
			pool = _generate_normal_pool()
	else:
		pool = _generate_normal_pool()
	
	# 分配唯一 ID，用于 Trade-in 等交互回调找到正确的奖池
	pool.id = StringName(str(Time.get_ticks_msec()) + "_" + str(rng.randi()))
	return pool


func _generate_mainline_pool() -> PoolConfig:
	var pool = PoolConfig.new()
	pool.pool_type = Constants.POOL_TYPE_MAINLINE
	pool.ticket_cost = 10
	if GameManager.game_config != null:
		pool.ticket_cost = GameManager.game_config.mainline_ticket_cost
	return pool


func _generate_normal_pool() -> PoolConfig:
	var pool = PoolConfig.new()
	pool.pool_type = Constants.NORMAL_POOL_TYPES.pick_random()
	pool.gold_cost = 5
	if GameManager.game_config != null:
		pool.gold_cost = GameManager.game_config.normal_draw_gold_cost
	return pool

