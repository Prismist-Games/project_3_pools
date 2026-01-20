extends SkillEffect
class_name HardOrderExpertSkillEffect

## 【困难订单专家】
## 在提交模式下，如果选中物品满足的订单有史诗及以上品质要求，进入待命状态。
## 完成该订单时额外获得金币。

@export var rarity_threshold: int = Constants.Rarity.EPIC
@export var bonus_gold: int = 10

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
	
	# 检查是否有满足条件的订单（需求中有史诗及以上品质）
	for order in OrderSystem.current_orders:
		if order == null:
			continue
		
		# 检查订单需求中是否有史诗及以上品质要求
		var has_hard_requirement = false
		for req in order.requirements:
			var min_rarity = req.get("min_rarity", 0)
			if min_rarity >= rarity_threshold:
				has_hard_requirement = true
				break
		
		if has_hard_requirement:
			# 检查选中物品是否能满足该订单
			if order.validate_selection(selected_items).valid:
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
	
	if ctx.order_data == null:
		return
	
	# 检查订单需求中是否有史诗及以上品质要求
	var has_hard_requirement = false
	for req in ctx.order_data.requirements:
		var min_rarity = req.get("min_rarity", 0)
		if min_rarity >= rarity_threshold:
			has_hard_requirement = true
			break
			
	if has_hard_requirement:
		triggered.emit(TRIGGER_ACTIVATE)
		ctx.reward_gold += bonus_gold


func get_visual_state() -> String:
	if _check_pending_condition():
		return TRIGGER_PENDING
	return ""
