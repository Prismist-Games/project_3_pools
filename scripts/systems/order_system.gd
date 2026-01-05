extends Node
class_name OrderSystem

## 订单系统：管理订单生成、刷新、提交。

var current_orders: Array[OrderData] = []

func _ready() -> void:
	# 等待 GameManager 初始化完成
	if not GameManager.is_node_ready():
		await GameManager.ready
	
	# 初始生成订单
	call_deferred("refresh_all_orders")
	
	EventBus.game_event.connect(_on_game_event)


func _on_game_event(event_id: StringName, _payload: RefCounted) -> void:
	if event_id == &"add_order_refreshes":
		_add_refreshes_to_all_orders(1)


func _add_refreshes_to_all_orders(amount: int) -> void:
	for order in current_orders:
		if not order.is_mainline:
			order.refresh_count += amount
	EventBus.orders_updated.emit(current_orders)


func refresh_all_orders() -> void:
	current_orders.clear()
	var stage_data = GameManager.current_stage_data
	var count = 4
	if stage_data != null:
		count = stage_data.order_count
	elif GameManager.game_config != null:
		count = GameManager.game_config.normal_orders_count
		
	for i in range(count):
		current_orders.append(_generate_normal_order())
	
	_check_and_add_mainline_order()
	EventBus.orders_updated.emit(current_orders)


func refresh_order(index: int) -> void:
	if index < 0 or index >= current_orders.size():
		return
		
	var stage_data = GameManager.current_stage_data
	if stage_data != null and not stage_data.has_order_refresh:
		return

	var order = current_orders[index]
	if order.refresh_count <= 0:
		return
		
	# 技能检测上下文
	var ctx = ContextProxy.new({ "consume_refresh": true })
	EventBus.game_event.emit(&"order_refresh_requested", ctx)
	
	if ctx.get_value("consume_refresh"):
		order.refresh_count -= 1
	
	if order.is_mainline:
		current_orders[index] = _generate_mainline_order()
	else:
		current_orders[index] = _generate_normal_order(order.refresh_count)
		
	EventBus.orders_updated.emit(current_orders)


func submit_order(index: int) -> bool:
	if index < 0 or index >= current_orders.size():
		return false
		
	var order = current_orders[index]
	var inventory = GameManager.inventory
	
	if not order.can_fulfill(inventory):
		return false
		
	var items_to_consume = order.get_fulfillment_items(inventory)
	
	# 计算稀有度加成（取平均加成或累加？文档说是 (1 + 提交物品稀有度加成)，通常指累加或平均。
	# 这里按平均加成处理，或者按每个物品的加成系数乘基础奖励的分配。
	# 更简单且符合直觉的解释：bonus = sum(Constants.rarity_bonus(it.rarity))
	var total_rarity_bonus: float = 0.0
	for it in items_to_consume:
		total_rarity_bonus += Constants.get_script().rarity_bonus(it.rarity)
	
	GameManager.remove_items(items_to_consume)
	
	# 创建上下文，允许技能修改奖励
	var context = OrderCompletedContext.new()
	context.reward_gold = roundi(order.reward_gold * (1.0 + total_rarity_bonus))
	context.reward_tickets = roundi(order.reward_tickets * (1.0 + total_rarity_bonus))
	context.submitted_items = items_to_consume
	context.meta["is_mainline"] = order.is_mainline
	
	# 技能倍率和额外加成通常在技能系统中修改 context.reward_gold/tickets
	EventBus.order_completed.emit(context)
	
	# 发放奖励
	GameManager.add_gold(context.reward_gold)
	GameManager.add_tickets(context.reward_tickets)
	
	# 如果是主线，进阶
	if order.is_mainline:
		GameManager.mainline_stage += 1
		# 触发技能选择（如果未到最后一关）
		if GameManager.mainline_stage <= Constants.MAINLINE_STAGES:
			EventBus.modal_requested.emit(&"skill_select", null)
	
	# 替换已完成的订单
	if order.is_mainline:
		_check_and_add_mainline_order()
		# 如果主线订单被成功提交且没有立即补充（比如因为条件不足），移除它
		# 但通常 _check_and_add_mainline_order 会处理补充逻辑
		if current_orders.size() > index and current_orders[index] == order:
			current_orders.remove_at(index)
	else:
		current_orders[index] = _generate_normal_order()
		
	EventBus.orders_updated.emit(current_orders)
	return true


func _check_and_add_mainline_order() -> void:
	var has_mainline = false
	for o in current_orders:
		if o.is_mainline:
			has_mainline = true
			break
			
	if not has_mainline and _should_generate_mainline_order():
		current_orders.append(_generate_mainline_order())


func _should_generate_mainline_order() -> bool:
	return GameManager.tickets >= 10 and GameManager.mainline_stage <= Constants.MAINLINE_STAGES


func _generate_normal_order(force_refresh_count: int = -1) -> OrderData:
	var order = OrderData.new()
	var rng = GameManager.rng
	var stage = GameManager.mainline_stage
	
	# 根据阶段决定需求总数
	var target_total_items: int = 2
	if stage >= 2 and stage <= 3:
		target_total_items = 3
	elif stage >= 4:
		target_total_items = rng.randi_range(3, 4)
	
	var current_total: int = 0
	var normal_items = GameManager.get_all_normal_items()
	while current_total < target_total_items:
		var item_data = normal_items.pick_random()
		var count = rng.randi_range(1, target_total_items - current_total)
		
		# 技能：偷工减料
		var ctx = ContextProxy.new({ "item_count": count })
		EventBus.game_event.emit(&"order_requirement_generating", ctx)
		count = ctx.get_value("item_count")
		
		if count <= 0: count = 1 # 保底
			
		order.requirements.append({
			"item_id": item_data.id,
			"min_rarity": Constants.Rarity.COMMON,
			"count": count
		})
		current_total += count
	
	# 设定基础奖励
	var is_gold_reward = rng.randf() < 0.5
	match target_total_items:
		2:
			if is_gold_reward: order.reward_gold = 5
			else: order.reward_tickets = 10
		3:
			if is_gold_reward: order.reward_gold = 10
			else: order.reward_tickets = 20
		4:
			if is_gold_reward: order.reward_gold = 15
			else: order.reward_tickets = 30
		_:
			order.reward_gold = 5
	
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
	
	var stage = GameManager.mainline_stage
	var stage_data = GameManager.get_mainline_stage_data(stage)
	
	if stage_data != null:
		order.requirements.append({
			"item_id": stage_data.mainline_item.id,
			"min_rarity": Constants.Rarity.MYTHIC,
			"count": 1
		})
		
		# 根据阶段数据决定副物品需求
		var secondary_item = GameManager.get_all_normal_items().pick_random()
		order.requirements.append({
			"item_id": secondary_item.id,
			"min_rarity": stage_data.required_secondary_rarity,
			"count": 1
		})
		
	order.reward_gold = 50
	order.reward_tickets = 20
	order.refresh_count = 0
	return order
