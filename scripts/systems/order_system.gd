extends Node

## 订单系统：管理订单生成、刷新、提交。

var current_orders: Array[OrderData] = []

func _ready() -> void:
	# 等待 GameManager 和 UnlockManager 初始化完成
	if not GameManager.is_node_ready():
		await GameManager.ready
	if not UnlockManager.is_node_ready():
		await UnlockManager.ready
	
	# 初始生成订单
	call_deferred("refresh_all_orders")
	
	EventBus.game_event.connect(_on_game_event)


func _on_game_event(event_id: StringName, _payload: RefCounted) -> void:
	if event_id == &"add_order_refreshes":
		_add_refreshes_to_all_orders(1)


func _add_refreshes_to_all_orders(amount: int) -> void:
	for order in current_orders:
		order.refresh_count += amount
	EventBus.orders_updated.emit(current_orders)


func refresh_all_orders() -> void:
	current_orders.clear()
	
	# 使用 UnlockManager 控制订单数量
	var count = UnlockManager.order_limit
		
	# 1. 生成 1 个主线订单
	current_orders.append(_generate_mainline_order())
	
	# 2. 生成 (count - 1) 个普通订单
	for i in range(count - 1):
		current_orders.append(_generate_normal_order())
	
	EventBus.orders_updated.emit(current_orders)


func refresh_order(index: int) -> OrderData:
	if index < 0 or index >= current_orders.size():
		return null
	
	# 检查订单刷新是否已解锁
	if not UnlockManager.is_unlocked(UnlockManager.Feature.ORDER_REFRESH):
		return current_orders[index]

	var order = current_orders[index]
	if order.refresh_count <= 0:
		return order
		
	# 技能检测上下文
	var ctx = ContextProxy.new({"consume_refresh": true, "index": index})
	# EventBus.game_event.emit(&"order_refresh_requested", ctx) # 这里的 emit 导致了循环调用，因为 UI 层监听同名事件来触发动画
	EventBus.game_event.emit(&"order_refresh_logic_check", ctx) # 改名避免冲突
	
	if order.is_mainline:
		current_orders[index] = _generate_mainline_order() # 主线不减少刷新次数? 或者减少? 暂时保持原样
	else:
		if ctx.get_value("consume_refresh"):
			order.refresh_count -= 1
		current_orders[index] = _generate_normal_order(order.refresh_count)
		
	EventBus.orders_updated.emit(current_orders)
	return current_orders[index]


func submit_order(index: int, selected_indices: Array[int] = []) -> bool:
	if index != -1:
		return _submit_single_order(index, selected_indices)
	else:
		return _submit_all_satisfied(selected_indices)


func _submit_single_order(index: int, selected_indices: Array[int]) -> bool:
	if index < 0 or index >= current_orders.size():
		return false
		
	var order = current_orders[index]
	var inventory = InventorySystem.inventory
	
	var selected_items: Array[ItemInstance] = []
	for idx in selected_indices:
		if idx >= 0 and idx < inventory.size() and inventory[idx] != null:
			selected_items.append(inventory[idx])
			
	var validation = order.validate_selection(selected_items)
	if not validation.valid:
		return false
		
	# 执行提交核心逻辑
	_execute_submission(order, selected_items, validation.total_overflow_bonus)
	
	# 消耗物品
	InventorySystem.remove_items(selected_items)
	
	# 替换订单
	if order.is_mainline:
		current_orders[index] = _generate_mainline_order()
	else:
		current_orders[index] = _generate_normal_order()
		
	EventBus.orders_updated.emit(current_orders)
	return true


func _submit_all_satisfied(selected_indices: Array[int]) -> bool:
	var inventory = InventorySystem.inventory
	var selected_items: Array[ItemInstance] = []
	for idx in selected_indices:
		if idx >= 0 and idx < inventory.size() and inventory[idx] != null:
			selected_items.append(inventory[idx])
	
	if selected_items.is_empty():
		return false
		
	var satisfied_indices: Array[int] = []
	for i in range(current_orders.size()):
		var order = current_orders[i]
		if order.validate_selection(selected_items).valid:
			satisfied_indices.append(i)
			
	if satisfied_indices.is_empty():
		return false
		
	# 按索引倒序排列，方便替换
	satisfied_indices.sort()
	satisfied_indices.reverse()
	
	for idx in satisfied_indices:
		var order = current_orders[idx]
		var validation = order.validate_selection(selected_items)
		# 提交
		_execute_submission(order, selected_items, validation.total_overflow_bonus)
		
		# 替换
		if order.is_mainline:
			current_orders[idx] = _generate_mainline_order()
		else:
			current_orders[idx] = _generate_normal_order()
			
	# 最后统一消耗选中的物品
	InventorySystem.remove_items(selected_items)
	
	EventBus.orders_updated.emit(current_orders)
	return true


func _execute_submission(order: OrderData, items_to_consume: Array[ItemInstance], total_rarity_bonus: float) -> void:
	# 创建上下文，允许技能修改奖励
	var context = OrderCompletedContext.new()
	# 基础奖励 * (1 + 溢出加成)
	context.reward_gold = roundi(order.reward_gold * (1.0 + total_rarity_bonus))
	context.submitted_items = items_to_consume
	
	# 发出信号让技能系统进一步修改
	EventBus.order_completed.emit(context)
	
	# 发放奖励
	GameManager.add_gold(context.reward_gold)


func _generate_normal_order(force_refresh_count: int = -1) -> OrderData:
	var order = OrderData.new()
	var rng = GameManager.rng
	
	# 1. 决定需求项总数 (由 UnlockManager 控制范围)
	# 注意：这里的数量是需求项的数量，每个需求项需要 1 个物品
	var target_requirement_count: int = rng.randi_range(UnlockManager.order_item_req_min, UnlockManager.order_item_req_max)
	
	var normal_items = GameManager.get_all_normal_items()
	var total_rarity_score: int = 0
	
	# 生成指定数量的需求项
	for i in range(target_requirement_count):
		var item_data = normal_items.pick_random()
		var count = 1 # 每个需求项固定需要 1 个物品（validate_selection 不检查数量）
		
		# 技能：偷工减料（保留接口，虽然当前实现下 count 固定为 1）
		var ctx = ContextProxy.new({"item_count": count})
		EventBus.game_event.emit(&"order_requirement_generating", ctx)
		count = ctx.get_value("item_count")
		
		if count <= 0: count = 1 # 保底
		
		# 2. 决定品质要求
		var min_rarity = Constants.Rarity.COMMON
		if GameManager.game_config != null:
			# 如果没有 stage_data，使用基础权重
			var cfg = GameManager.game_config
			var weights = PackedFloat32Array([
				cfg.weight_common,
				cfg.weight_uncommon,
				cfg.weight_rare,
				cfg.weight_epic,
				cfg.weight_legendary
			])
			min_rarity = Constants.pick_weighted_index(weights, rng) as Constants.Rarity
		
		total_rarity_score += min_rarity * count
			
		order.requirements.append({
			"item_id": item_data.id,
			"min_rarity": min_rarity,
			"count": count
		})

	
	# 3. 设定基础奖励：根据总物品数和品质深度加成
	# 每个品质等级提升 25% 基础奖励
	var reward_multiplier = 1.0 + (total_rarity_score * 0.25)
	
	# 简化奖励逻辑，不再区分金币/奖券，统一为金币
	var base_rewards = {
		1: 3,
		2: 5,
		3: 10,
		4: 15,
		5: 20,
		6: 25
	}
	
	var base_gold = base_rewards.get(target_requirement_count, 5)
	order.reward_gold = roundi(base_gold * reward_multiplier)

	
	if force_refresh_count >= 0:
		order.refresh_count = force_refresh_count
	else:
		order.refresh_count = 2
		if GameManager.game_config != null:
			order.refresh_count = GameManager.game_config.order_refreshes_per_order
		
	return order


func _generate_mainline_order() -> OrderData:
	var order = OrderData.new()
	order.is_mainline = true
	var _rng = GameManager.rng
	
	var normal_items = GameManager.get_all_normal_items()
	# 主线需求：2个随机史诗品质的物品
	for i in range(2):
		var item_data = normal_items.pick_random()
		order.requirements.append({
			"item_id": item_data.id,
			"min_rarity": Constants.Rarity.EPIC,
			"count": 1
		})
	
	# 主线奖励：高额金币 (例如 100)
	order.reward_gold = 100
	order.refresh_count = 0 # 主线通常不可刷新，或者跟随普通逻辑
	
	return order
