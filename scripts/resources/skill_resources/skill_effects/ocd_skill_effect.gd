extends SkillEffect
class_name OcdSkillEffect

## 【强迫症】
## 在提交模式下，如果选中物品全部同类型且能满足某订单，进入待命状态。
## 完成该订单时奖励翻倍。

@export var multiplier: float = 2.0

var _is_pending: bool = false


func initialize() -> void:
	# 监听选中物品变化
	if not InventorySystem.multi_selection_changed.is_connected(_on_selection_changed):
		InventorySystem.multi_selection_changed.connect(_on_selection_changed)
	
	# 监听 UI 模式变化
	if not GameManager.ui_mode_changed.is_connected(_on_ui_mode_changed):
		GameManager.ui_mode_changed.connect(_on_ui_mode_changed)
	
	# 初始化状态
	_is_pending = _check_pending_condition()


func on_event(event_id: StringName, context: RefCounted) -> void:
	if event_id == &"order_completed":
		_handle_order_completed(context as OrderCompletedContext)


func _on_selection_changed(_indices: Array[int]) -> void:
	_check_and_update_pending_state()


func _on_ui_mode_changed(_mode: int) -> void:
	_check_and_update_pending_state()


func _check_pending_condition() -> bool:
	# 必须在提交模式
	if GameManager.current_ui_mode != Constants.UIMode.SUBMIT:
		return false
	
	# 获取当前选中的物品
	var selected_indices = InventorySystem.multi_selected_indices
	if selected_indices.is_empty():
		return false
	
	var selected_items: Array[ItemInstance] = []
	for idx in selected_indices:
		if idx >= 0 and idx < InventorySystem.inventory.size():
			var item = InventorySystem.inventory[idx]
			if item != null:
				selected_items.append(item)
	
	if selected_items.is_empty():
		return false
	
	# 检查是否有满足条件的订单：该订单所需的物品全部同类型
	for order in OrderSystem.current_orders:
		if order == null:
			continue
		
		# 检查选中物品是否能满足该订单
		if not order.validate_selection(selected_items).valid:
			continue
		
		# 找出这个订单需要的物品（从选中物品中）
		var items_for_this_order: Array[ItemInstance] = []
		for req in order.requirements:
			var item_id = req.get("item_id", &"")
			var min_rarity = req.get("min_rarity", 0)
			
			# 找到满足这个需求的物品
			for item in selected_items:
				if item.item_data.id == item_id and item.rarity >= min_rarity:
					if item not in items_for_this_order:
						items_for_this_order.append(item)
					break
		
		# 检查这些物品是否全部同类型（至少2个物品才有意义）
		if items_for_this_order.size() >= 2:
			var first_type = items_for_this_order[0].item_data.item_type
			var all_same_type = true
			for item in items_for_this_order:
				if item.item_data.item_type != first_type:
					all_same_type = false
					break
			
			if all_same_type:
				return true
	
	return false


func _check_and_update_pending_state() -> void:
	var should_be_pending = _check_pending_condition()
	
	if should_be_pending and not _is_pending:
		_is_pending = true
		triggered.emit(TRIGGER_PENDING)
	elif not should_be_pending and _is_pending:
		_is_pending = false
		triggered.emit(TRIGGER_CANCEL)


func _handle_order_completed(ctx: OrderCompletedContext) -> void:
	if ctx == null:
		return
	
	# 检查提交的物品是否全部同类型（单个物品不触发翻倍）
	if ctx.submitted_items.size() < 2:
		return
	
	var first_type = ctx.submitted_items[0].item_data.item_type
	var all_same_type = true
	for i in range(1, ctx.submitted_items.size()):
		if ctx.submitted_items[i].item_data.item_type != first_type:
			all_same_type = false
			break
	
	if all_same_type:
		triggered.emit(TRIGGER_ACTIVATE)
		ctx.reward_gold = roundi(ctx.reward_gold * multiplier)


func get_visual_state() -> String:
	if _check_pending_condition():
		return TRIGGER_PENDING
	return ""
