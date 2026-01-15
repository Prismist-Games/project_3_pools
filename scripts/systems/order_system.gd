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
	call_deferred("initialize_orders")
	
	EventBus.game_event.connect(_on_game_event)


func _on_game_event(event_id: StringName, _payload: RefCounted) -> void:
	if event_id == &"add_order_refreshes":
		_add_refresh_to_all_orders()


## 初始化订单 (仅限系统初始化时使用，不再对玩家开放“全部刷新”功能)
func initialize_orders() -> void:
	current_orders.clear()
	
	# 使用 UnlockManager 控制订单数量
	var count = UnlockManager.order_limit
		
	# 1. 生成 count 个普通订单 (对应下方 4 个槽位)
	for i in range(count):
		current_orders.append(_generate_normal_order())
		
	# 2. 生成 1 个额外的主线订单
	current_orders.append(_generate_mainline_order())
	
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


## 为所有普通订单增加刷新次数（由谈判专家技能触发）
func _add_refresh_to_all_orders() -> void:
	for order in current_orders:
		if order != null and not order.is_mainline:
			order.refresh_count += 1
	EventBus.orders_updated.emit(current_orders)


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
	_execute_submission(order, selected_items, validation.total_submitted_bonus)
	
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
		_execute_submission(order, selected_items, validation.total_submitted_bonus)
		
		# 替换
		if order.is_mainline:
			current_orders[idx] = _generate_mainline_order()
		else:
			current_orders[idx] = _generate_normal_order()
			
	# 最后统一消耗选中的物品
	InventorySystem.remove_items(selected_items)
	
	EventBus.orders_updated.emit(current_orders)
	return true


func _execute_submission(order: OrderData, items_to_consume: Array[ItemInstance], total_submitted_bonus: float) -> void:
	# 创建上下文，允许技能修改奖励
	var context = OrderCompletedContext.new()
	# 最终奖励 = 显示奖励 * (1 + 提交物品品质加成之和)
	context.reward_gold = roundi(order.reward_gold * (1.0 + total_submitted_bonus))
	context.submitted_items = items_to_consume
	
	# 发出信号让技能系统进一步修改
	EventBus.order_completed.emit(context)
	
	# 主线订单没有金币奖励，只有普通订单才发放金币
	if not order.is_mainline:
		GameManager.add_gold(context.reward_gold)
	
	# 主线订单完成后触发时代切换流程
	if order.is_mainline:
		_on_mainline_completed()


func _on_mainline_completed() -> void:
	# 刷新所有普通订单
	for i in range(current_orders.size()):
		var order = current_orders[i]
		if order != null and not order.is_mainline:
			current_orders[i] = _generate_normal_order()
	
	EventBus.orders_updated.emit(current_orders)
	
	# 请求技能选择弹窗（复用奖池3选1 UI）
	EventBus.modal_requested.emit(&"skill_selection", null)


func _generate_normal_order(force_refresh_count: int = -1) -> OrderData:
	var order = OrderData.new()
	var rng = GameManager.rng
	
	# 1. 决定需求项总数 (按概率分布: 20%=2个, 65%=3个, 15%=4个)
	var count_roll: float = rng.randf()
	var original_requirement_count: int
	if count_roll < 0.20:
		original_requirement_count = 2
	elif count_roll < 0.85: # 0.20 + 0.65
		original_requirement_count = 3
	else:
		original_requirement_count = 4
	
	# 技能：偷工减料 - 减少需求数量但奖励按原数量计算
	var corners_ctx = ContextProxy.new({"requirement_count": original_requirement_count})
	EventBus.game_event.emit(&"order_requirement_count_generating", corners_ctx)
	var actual_requirement_count: int = corners_ctx.get_value("requirement_count")
	actual_requirement_count = maxi(1, actual_requirement_count) # 保底至少1个
	
	var normal_items = GameManager.get_all_normal_items()
	if normal_items.is_empty():
		push_error("OrderSystem: No normal items found! Cannot generate order.")
		return order

	# 订单需求品质权重 (普通40%, 优秀35%, 稀有20%, 史诗5%, 传说0%)
	var order_rarity_weights = PackedFloat32Array([0.40, 0.35, 0.20, 0.05, 0.0])
	
	# 累计需求品质加成（加算）- 基于原始数量计算
	var total_requirement_bonus: float = 0.0
	
	# 已使用的物品ID，用于避免同一订单内重复
	var used_item_ids: Array[StringName] = []
	
	# 生成指定数量的需求项（使用实际数量，但奖励按原始数量算）
	for i in range(actual_requirement_count):
		# 过滤掉已经使用的物品
		var available_items: Array[ItemData] = []
		for item in normal_items:
			if item.id not in used_item_ids:
				available_items.append(item)
		
		# 如果没有可用物品了，跳过（理论上不会发生，因为物品数量 > 最大需求数量）
		if available_items.is_empty():
			break
		
		var item_data = available_items.pick_random()
		used_item_ids.append(item_data.id)
		
		var count = 1 # 每个需求项固定需要 1 个物品
		
		# 2. 决定品质要求（使用订单专用权重，不使用全局抽奖权重）
		var min_rarity = Constants.pick_weighted_index(order_rarity_weights, rng) as Constants.Rarity
		
		# 累加该需求的品质加成（使用 Constants.rarity_bonus）
		# 例如：Epic = 0.4，两个 Epic 就是 0.4 + 0.4 = 0.8
		total_requirement_bonus += Constants.rarity_bonus(min_rarity) * count
			
		order.requirements.append({
			"item_id": item_data.id,
			"min_rarity": min_rarity,
			"count": count
		})

	
	# 3. 设定基础奖励：根据原始需求数量计算 (2=5, 3=7, 4=10)
	var base_rewards = {
		2: 5,
		3: 7,
		4: 10
	}
	
	# 显示奖励 = 基础奖励 * (1 + 需求品质加成之和)
	# 注意：使用 original_requirement_count 计算奖励，而不是 actual_requirement_count
	var base_gold = base_rewards.get(original_requirement_count, 7)
	order.reward_gold = roundi(base_gold * (1.0 + total_requirement_bonus))

	
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
	var rng = GameManager.rng
	
	var normal_items = GameManager.get_all_normal_items()
	if normal_items.is_empty():
		push_error("OrderSystem: No items found for mainline order!")
		return order

	# 主线需求：2个随机史诗品质的物品，必须来自不同种类且名称不同
	
	# 按种类分组
	var items_by_category: Dictionary = {} # category_id -> Array[ItemData]
	for item in normal_items:
		var cat_id = item.category.id if item.category else &"unknown"
		if not items_by_category.has(cat_id):
			items_by_category[cat_id] = []
		items_by_category[cat_id].append(item)
	
	# 获取所有有物品的种类
	var available_categories = items_by_category.keys()
	available_categories.shuffle()
	
	# 确保至少有2个不同种类
	if available_categories.size() < 2:
		push_error("OrderSystem: Not enough categories for mainline order (need 2, have %d)" % available_categories.size())
		# Fallback: 从现有物品中随机选2个不同名称的
		var shuffled_items = normal_items.duplicate()
		shuffled_items.shuffle()
		var used_names: Array[StringName] = []
		for item in shuffled_items:
			if item.id not in used_names:
				order.requirements.append({
					"item_id": item.id,
					"min_rarity": Constants.Rarity.EPIC,
					"count": 1
				})
				used_names.append(item.id)
				if used_names.size() >= 2:
					break
		order.reward_gold = 100
		order.refresh_count = 0
		return order
	
	# 从前2个种类中各选1个物品
	var used_item_ids: Array[StringName] = []
	for i in range(2):
		var cat_id = available_categories[i]
		var items_in_cat: Array = items_by_category[cat_id]
		
		# 从该种类中随机选一个（避免重复名称，虽然跨种类应该不会有同名）
		var valid_items: Array = []
		for item in items_in_cat:
			if item.id not in used_item_ids:
				valid_items.append(item)
		
		if valid_items.is_empty():
			continue
		
		var item_data = valid_items[rng.randi() % valid_items.size()]
		used_item_ids.append(item_data.id)
		
		order.requirements.append({
			"item_id": item_data.id,
			"min_rarity": Constants.Rarity.EPIC,
			"count": 1
		})
	
	# 主线奖励：高额金币 (例如 100)
	order.reward_gold = 100
	order.refresh_count = 0 # 主线通常不可刷新，或者跟随普通逻辑
	
	return order
