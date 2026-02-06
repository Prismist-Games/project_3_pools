extends Node

## 订单系统：管理订单生成、刷新、提交。
##
## 架构：current_orders = [普通0, 普通1, 普通2, 普通3, 主线0, 主线1]
## 索引 0-3: 普通积分订单
## 索引 4-5: 时代主线订单

var current_orders: Array[OrderData] = []

## 主线订单在 current_orders 中的起始索引
const MAINLINE_START_INDEX: int = 4
const MAINLINE_COUNT: int = 2

func _ready() -> void:
	if not GameManager.is_node_ready():
		await GameManager.ready
	if not UnlockManager.is_node_ready():
		await UnlockManager.ready
	
	call_deferred("initialize_orders")
	EventBus.game_event.connect(_on_game_event)


func _on_game_event(event_id: StringName, _payload: RefCounted) -> void:
	if event_id == &"add_order_refreshes":
		_add_refresh_to_all_orders()


# --- Optimization: Requirement Cache ---
var _cached_max_required_items: Dictionary = {} # {item_id: max_required_rarity}
var _cached_min_required_items: Dictionary = {} # {item_id: min_required_rarity}
var _cache_dirty: bool = true

func get_max_required_items() -> Dictionary:
	if _cache_dirty:
		_rebuild_cache()
	return _cached_max_required_items

func get_min_required_items() -> Dictionary:
	if _cache_dirty:
		_rebuild_cache()
	return _cached_min_required_items

func _rebuild_cache() -> void:
	_cached_max_required_items.clear()
	_cached_min_required_items.clear()
	for order in current_orders:
		for req in order.requirements:
			var id = req.get("item_id", &"")
			var rarity = req.get("min_rarity", 0)
			if id != &"":
				if id in _cached_max_required_items:
					_cached_max_required_items[id] = maxi(_cached_max_required_items[id], rarity)
					_cached_min_required_items[id] = mini(_cached_min_required_items[id], rarity)
				else:
					_cached_max_required_items[id] = rarity
					_cached_min_required_items[id] = rarity
	_cache_dirty = false

func _mark_cache_dirty() -> void:
	_cache_dirty = true
# ---------------------------------------


## 初始化订单
func initialize_orders() -> void:
	current_orders.clear()
	
	var count = UnlockManager.order_limit
		
	# 1. 生成普通积分订单
	for i in range(count):
		current_orders.append(_generate_normal_order())
		
	# 2. 生成 2 个独立主线订单（确保不重叠物品）
	var mainline_orders = _generate_mainline_order_pair()
	current_orders.append(mainline_orders[0])
	current_orders.append(mainline_orders[1])
	
	_mark_cache_dirty()
	EventBus.orders_updated.emit(current_orders)


func refresh_order(index: int) -> OrderData:
	if index < 0 or index >= current_orders.size():
		return null
	
	if not UnlockManager.is_unlocked(UnlockManager.Feature.ORDER_REFRESH):
		return current_orders[index]

	var order = current_orders[index]
	if order.refresh_count <= 0:
		return order
		
	var ctx = ContextProxy.new({"consume_refresh": true, "index": index})
	EventBus.game_event.emit(&"order_refresh_logic_check", ctx)
	
	if order.is_mainline:
		# 主线订单刷新：重新生成一对（确保互不重叠）
		_refresh_mainline_orders()
	else:
		if ctx.get_value("consume_refresh"):
			order.refresh_count -= 1
		current_orders[index] = _generate_normal_order(order.refresh_count)
		
	_mark_cache_dirty()
	EventBus.orders_updated.emit(current_orders)
	return current_orders[index]


## 为所有普通订单增加刷新次数（由谈判专家技能触发）
func _add_refresh_to_all_orders() -> void:
	for order in current_orders:
		if order != null and not order.is_mainline:
			order.refresh_count += 1
	_mark_cache_dirty()
	EventBus.orders_updated.emit(current_orders)


## 刷新所有普通订单（保留主线订单）
func refresh_all_normal_orders() -> void:
	for i in range(current_orders.size()):
		var order = current_orders[i]
		if order != null and not order.is_mainline:
			current_orders[i] = _generate_normal_order()
	_mark_cache_dirty()
	EventBus.orders_updated.emit(current_orders)


## 仅刷新两个主线订单（时代完成后调用）
func refresh_mainline_orders() -> void:
	_refresh_mainline_orders()
	_mark_cache_dirty()
	EventBus.orders_updated.emit(current_orders)


func _refresh_mainline_orders() -> void:
	var pair = _generate_mainline_order_pair()
	for i in range(MAINLINE_COUNT):
		var idx = MAINLINE_START_INDEX + i
		if idx < current_orders.size():
			current_orders[idx] = pair[i]


# ===========================================================================
# 普通提交（积分订单，共享物品机制）
# ===========================================================================

## 预检查哪些积分订单会被提交（供 UI 使用）
func preview_normal_submit(selected_indices: Array[int]) -> Array[OrderData]:
	var inventory = InventorySystem.inventory
	var selected_items: Array[ItemInstance] = []
	for idx in selected_indices:
		if idx >= 0 and idx < inventory.size() and inventory[idx] != null:
			selected_items.append(inventory[idx])
	
	if selected_items.is_empty():
		return []
	
	# 只检查普通（非主线）订单
	var satisfied_orders: Array[OrderData] = []
	for order in current_orders:
		if order.is_mainline:
			continue
		if order.validate_selection(selected_items).valid:
			satisfied_orders.append(order)
			
	if satisfied_orders.is_empty():
		return []
	
	# 全局检查：确保每个选中物品都属于至少一个可满足订单的需求
	for item in selected_items:
		if item == null:
			continue
		var is_needed_by_any_order = false
		for order in satisfied_orders:
			for req in order.requirements:
				var item_id = req.get("item_id", &"")
				var min_rarity = req.get("min_rarity", 0)
				if item.item_data.id == item_id and item.rarity >= min_rarity:
					is_needed_by_any_order = true
					break
			if is_needed_by_any_order:
				break
		if not is_needed_by_any_order:
			return []
	
	return satisfied_orders


## 执行普通提交（积分订单，共享物品）
func submit_normal(selected_indices: Array[int]) -> bool:
	var inventory = InventorySystem.inventory
	var selected_items: Array[ItemInstance] = []
	for idx in selected_indices:
		if idx >= 0 and idx < inventory.size() and inventory[idx] != null:
			selected_items.append(inventory[idx])
	
	if selected_items.is_empty():
		return false
	
	var satisfied_orders: Array[OrderData] = []
	var satisfied_indices: Array[int] = []
	for i in range(current_orders.size()):
		var order = current_orders[i]
		if order.is_mainline:
			continue
		if order.validate_selection(selected_items).valid:
			satisfied_orders.append(order)
			satisfied_indices.append(i)
			
	if satisfied_indices.is_empty():
		return false
	
	# 全局检查
	for item in selected_items:
		if item == null:
			continue
		var is_needed_by_any_order = false
		for order in satisfied_orders:
			for req in order.requirements:
				var item_id = req.get("item_id", &"")
				var min_rarity = req.get("min_rarity", 0)
				if item.item_data.id == item_id and item.rarity >= min_rarity:
					is_needed_by_any_order = true
					break
			if is_needed_by_any_order:
				break
		if not is_needed_by_any_order:
			return false
	
	satisfied_indices.sort()
	satisfied_indices.reverse()
	
	for idx in satisfied_indices:
		var order = current_orders[idx]
		var validation = order.validate_selection(selected_items)
		if not validation.valid:
			push_warning("OrderSystem: Normal order validation failed unexpectedly at index %d" % idx)
			continue
		
		_execute_normal_submission(order, selected_items, validation.total_submitted_bonus)
		current_orders[idx] = _generate_normal_order()
			
	# 统一消耗选中的物品
	InventorySystem.remove_items(selected_items)
	
	var submitted_orders_count = satisfied_indices.size()
	if submitted_orders_count >= 2:
		var context = ContextProxy.new({"count": submitted_orders_count})
		EventBus.game_event.emit(&"multi_orders_completed", context)

	_mark_cache_dirty()
	EventBus.orders_updated.emit(current_orders)
	return true


func _execute_normal_submission(order: OrderData, items_to_consume: Array[ItemInstance], total_submitted_bonus: float) -> void:
	var context = OrderCompletedContext.new()
	context.reward_coupon = roundi(order.reward_coupon * (1.0 + total_submitted_bonus))
	context.submitted_items = items_to_consume
	context.order_data = order
	
	EventBus.order_completed.emit(context)
	EventBus.game_event.emit(&"order_completed", context)
	
	# 普通订单奖励积分
	GameManager.add_coupon(context.reward_coupon)


# ===========================================================================
# 时代提交（主线订单，独占物品机制）
# ===========================================================================

## 预检查哪个时代订单会被提交
func preview_era_submit(selected_indices: Array[int]) -> Array[OrderData]:
	var inventory = InventorySystem.inventory
	var selected_items: Array[ItemInstance] = []
	for idx in selected_indices:
		if idx >= 0 and idx < inventory.size() and inventory[idx] != null:
			selected_items.append(inventory[idx])
	
	if selected_items.is_empty():
		return []
	
	# 只检查主线订单，使用独占验证
	var satisfied_orders: Array[OrderData] = []
	for order in current_orders:
		if not order.is_mainline:
			continue
		if order.validate_selection_exclusive(selected_items).valid:
			satisfied_orders.append(order)
	
	# 时代提交不共享：最多只能满足一个主线订单
	if satisfied_orders.size() > 1:
		satisfied_orders = [satisfied_orders[0]]
	
	return satisfied_orders


## 执行时代提交（主线订单，独占物品）
func submit_era(selected_indices: Array[int]) -> bool:
	var inventory = InventorySystem.inventory
	var selected_items: Array[ItemInstance] = []
	for idx in selected_indices:
		if idx >= 0 and idx < inventory.size() and inventory[idx] != null:
			selected_items.append(inventory[idx])
	
	if selected_items.is_empty():
		return false
	
	# 找到第一个可满足的主线订单（独占验证）
	var target_order: OrderData = null
	for i in range(current_orders.size()):
		var order = current_orders[i]
		if not order.is_mainline:
			continue
		var check = order.validate_selection_exclusive(selected_items)
		if check.valid:
			target_order = order
			break
	
	if target_order == null:
		return false
	
	var validation = target_order.validate_selection_exclusive(selected_items)
	
	# 消耗被独占验证确认使用的物品
	var consumed: Array[ItemInstance] = []
	consumed.assign(validation.consumed_items)
	InventorySystem.remove_items(consumed)
	
	# 执行主线完成逻辑
	_execute_era_submission(target_order, consumed)
	
	_mark_cache_dirty()
	EventBus.orders_updated.emit(current_orders)
	return true


func _execute_era_submission(order: OrderData, items_consumed: Array[ItemInstance]) -> void:
	var context = OrderCompletedContext.new()
	context.reward_coupon = 0 # 主线订单不给积分
	context.submitted_items = items_consumed
	context.order_data = order
	
	EventBus.order_completed.emit(context)
	EventBus.game_event.emit(&"order_completed", context)
	
	_on_mainline_completed()


func _on_mainline_completed() -> void:
	# 1. 刷新两个主线订单（难度由下一时代配置决定）
	refresh_mainline_orders()
	
	# 2. 不刷新普通积分订单（保留现有）
	# 3. 不清空背包（保留物品）
	# 4. 重置金币由 EraManager 处理
	
	# 如果是最后一个时代，直接触发游戏结束
	if EraManager.current_era_index >= 3:
		EraManager.advance_to_next_era()
	else:
		# 请求技能选择弹窗
		EventBus.modal_requested.emit(&"skill_selection", null)


# ===========================================================================
# 兼容旧接口（保留 submit_order 和 preview_submit 用于过渡）
# ===========================================================================

func preview_submit(selected_indices: Array[int]) -> Array[OrderData]:
	return preview_normal_submit(selected_indices)

func submit_order(index: int, selected_indices: Array[int] = []) -> bool:
	if index == -1:
		return submit_normal(selected_indices)
	return false


# ===========================================================================
# 订单生成
# ===========================================================================

func _generate_normal_order(force_refresh_count: int = -1) -> OrderData:
	var order = OrderData.new()
	var rng = GameManager.rng
	
	var count_weights = PackedFloat32Array([0.20, 0.65, 0.15])
	if EraManager.current_config:
		count_weights = EraManager.current_config.get_count_weights()
		
	var count_index = Constants.pick_weighted_index(count_weights, rng)
	var original_requirement_count = count_index + 2

	var corners_ctx = ContextProxy.new({"requirement_count": original_requirement_count})
	EventBus.game_event.emit(&"order_requirement_count_generating", corners_ctx)
	var actual_requirement_count: int = corners_ctx.get_value("requirement_count")
	actual_requirement_count = maxi(1, actual_requirement_count)
	
	var normal_items = GameManager.get_all_normal_items()
	if normal_items.is_empty():
		push_error("OrderSystem: No normal items found! Cannot generate order.")
		return order

	var order_rarity_weights = PackedFloat32Array([0.40, 0.35, 0.20, 0.05, 0.0, 0.0])
	if EraManager.current_config:
		order_rarity_weights = EraManager.current_config.get_rarity_weights()
	
	var total_requirement_bonus: float = 0.0
	var used_item_ids: Array[StringName] = []
	
	for i in range(actual_requirement_count):
		var available_items: Array[ItemData] = []
		for item in normal_items:
			if item.id not in used_item_ids:
				available_items.append(item)
		
		if available_items.is_empty():
			break
		
		var item_data = available_items.pick_random()
		used_item_ids.append(item_data.id)
		var count = 1
		var min_rarity = Constants.pick_weighted_index(order_rarity_weights, rng) as Constants.Rarity
		total_requirement_bonus += Constants.rarity_bonus(min_rarity) * count
			
		order.requirements.append({
			"item_id": item_data.id,
			"min_rarity": min_rarity,
			"count": count
		})

	var base_rewards = {
		2: 3,
		3: 5,
		4: 7
	}
	
	var base_coupon = base_rewards.get(original_requirement_count, 7)
	order.reward_coupon = roundi(base_coupon * (1.0 + total_requirement_bonus))

	if force_refresh_count >= 0:
		order.refresh_count = force_refresh_count
	else:
		order.refresh_count = 2
		if GameManager.game_config != null:
			order.refresh_count = GameManager.game_config.order_refreshes_per_order
		
	return order


## 生成一对主线订单（确保它们不会要求相同的物品）
func _generate_mainline_order_pair() -> Array[OrderData]:
	var order_a = OrderData.new()
	order_a.is_mainline = true
	var order_b = OrderData.new()
	order_b.is_mainline = true
	var rng = GameManager.rng
	
	var normal_items = GameManager.get_all_normal_items()
	if normal_items.is_empty():
		push_error("OrderSystem: No items found for mainline orders!")
		return [order_a, order_b]

	# 获取时代配置中的主线品质要求
	var cfg = EraManager.current_config
	var mainline_rarities: Array[int] = [Constants.Rarity.RARE, Constants.Rarity.EPIC]
	var req_count: int = 2
	if cfg:
		mainline_rarities = cfg.mainline_rarities.duplicate()
		req_count = cfg.mainline_requirement_count

	# 按种类分组
	var items_by_type: Dictionary = {}
	for item in normal_items:
		var type_key = item.item_type
		if not items_by_type.has(type_key):
			items_by_type[type_key] = []
		items_by_type[type_key].append(item)
	
	var available_types = items_by_type.keys()
	available_types.shuffle()
	
	# 两个主线订单总共需要 req_count * 2 个不同的物品
	# 优先从不同种类中选取
	var all_used_item_ids: Array[StringName] = []
	
	# 生成订单 A
	_fill_mainline_order(order_a, items_by_type, available_types, all_used_item_ids, mainline_rarities, req_count, rng)
	
	# 生成订单 B（排除订单 A 已用的物品）
	_fill_mainline_order(order_b, items_by_type, available_types, all_used_item_ids, mainline_rarities, req_count, rng)
	
	order_a.reward_coupon = 0
	order_a.refresh_count = 0
	order_b.reward_coupon = 0
	order_b.refresh_count = 0
	
	return [order_a, order_b]


func _fill_mainline_order(
	order: OrderData,
	items_by_type: Dictionary,
	available_types: Array,
	used_item_ids: Array[StringName],
	rarities: Array[int],
	req_count: int,
	rng: RandomNumberGenerator
) -> void:
	var added: int = 0
	
	# 先尝试从不同种类中选取
	for type_key in available_types:
		if added >= req_count:
			break
		var items_in_type: Array = items_by_type[type_key]
		var valid_items: Array = []
		for item in items_in_type:
			if item.id not in used_item_ids:
				valid_items.append(item)
		
		if valid_items.is_empty():
			continue
		
		var item_data = valid_items[rng.randi() % valid_items.size()]
		used_item_ids.append(item_data.id)
		
		var required_rarity = rarities[added] if added < rarities.size() else Constants.Rarity.EPIC
		order.requirements.append({
			"item_id": item_data.id,
			"min_rarity": required_rarity,
			"count": 1
		})
		added += 1
	
	# 如果种类不够（极少见），从剩余物品中补充
	if added < req_count:
		var all_items = []
		for type_key in items_by_type:
			all_items.append_array(items_by_type[type_key])
		all_items.shuffle()
		
		for item in all_items:
			if added >= req_count:
				break
			if item.id not in used_item_ids:
				used_item_ids.append(item.id)
				var required_rarity = rarities[added] if added < rarities.size() else Constants.Rarity.EPIC
				order.requirements.append({
					"item_id": item.id,
					"min_rarity": required_rarity,
					"count": 1
				})
				added += 1


## 获取所有主线订单
func get_mainline_orders() -> Array[OrderData]:
	var result: Array[OrderData] = []
	for order in current_orders:
		if order.is_mainline:
			result.append(order)
	return result


## 获取所有普通订单
func get_normal_orders() -> Array[OrderData]:
	var result: Array[OrderData] = []
	for order in current_orders:
		if not order.is_mainline:
			result.append(order)
	return result
