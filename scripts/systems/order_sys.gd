extends Node
class_name OrderSystem

## 订单系统：管理订单生成、刷新、提交。

var current_orders: Array[OrderData] = []

func _ready() -> void:
	# 等待 GameManager 初始化完成
	if not GameManager.is_node_ready():
		await GameManager.ready
	
	# 初始生成订单
	refresh_all_orders()


func refresh_all_orders() -> void:
	current_orders.clear()
	var count = 4
	if GameManager.game_config != null:
		count = GameManager.game_config.normal_orders_count
		
	for i in range(count):
		current_orders.append(_generate_normal_order())
	
	_check_and_add_mainline_order()
	EventBus.orders_updated.emit(current_orders)


func refresh_order(index: int) -> void:
	if index < 0 or index >= current_orders.size():
		return
		
	var order = current_orders[index]
	if order.refresh_count <= 0:
		return
		
	# 技能检测上下文
	var ctx = { "consume_refresh": true }
	EventBus.game_event.emit(&"order_refresh_requested", ctx)
	
	if ctx.consume_refresh:
		order.refresh_count -= 1
	
	if order.is_mainline:
		current_orders[index] = _generate_mainline_order()
	else:
		current_orders[index] = _generate_normal_order()
		
	EventBus.orders_updated.emit(current_orders)


func submit_order(index: int) -> bool:
	if index < 0 or index >= current_orders.size():
		return false
		
	var order = current_orders[index]
	var inventory = GameManager.inventory
	
	if not order.can_fulfill(inventory):
		return false
		
	var items_to_consume = order.get_fulfillment_items(inventory)
	GameManager.remove_items(items_to_consume)
	
	# 创建上下文，允许技能修改奖励
	var context = OrderCompletedContext.new()
	context.reward_gold = order.reward_gold
	context.reward_tickets = order.reward_tickets
	context.submitted_items = items_to_consume
	context.meta["is_mainline"] = order.is_mainline
	
	EventBus.order_completed.emit(context)
	
	# 发放奖励
	GameManager.add_gold(context.reward_gold)
	GameManager.add_tickets(context.reward_tickets)
	
	# 如果是主线，进阶
	if order.is_mainline:
		GameManager.mainline_stage += 1
		# 触发技能选择
		EventBus.modal_requested.emit(&"skill_select", null)
	
	# 替换已完成的订单
	if order.is_mainline:
		_check_and_add_mainline_order()
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


func _generate_normal_order() -> OrderData:
	var order = OrderData.new()
	var rng = GameManager.rng
	
	var req_types = rng.randi_range(1, 2)
	var total_items = 0
	
	for i in range(req_types):
		var item_data = GameManager.all_items.pick_random()
		var count = rng.randi_range(1, 2)
		
		# 技能：偷工减料
		var ctx = { "item_count": count }
		EventBus.game_event.emit(&"order_requirement_generating", ctx)
		count = ctx.item_count
			
		order.requirements.append({
			"item_id": item_data.id,
			"min_rarity": Constants.Rarity.COMMON,
			"count": count
		})
		total_items += count
		
	order.reward_gold = total_items * 5
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
		
		# 随机一个史诗填充
		var epic_item = GameManager.all_items.pick_random()
		order.requirements.append({
			"item_id": epic_item.id,
			"min_rarity": Constants.Rarity.EPIC,
			"count": 1
		})
		
	order.reward_gold = 50
	order.reward_tickets = 20
	order.refresh_count = 0
	return order

