extends SkillEffect
class_name OcdSkillEffect

## 【强迫症】
## 提交订单时若所有物品同一类型，奖励翻倍。
## VFX: 订单区域有可满足的同类型订单时白色(Pending)

@export var multiplier: float = 2.0

## 当前是否处于激活状态
var _is_pending: bool = false


func initialize() -> void:
	_check_orders_for_same_type()


func on_event(event_id: StringName, context: RefCounted) -> void:
	match event_id:
		&"orders_updated":
			_check_orders_for_same_type()
		&"order_completed":
			_handle_order_completed(context as OrderCompletedContext)


func _check_orders_for_same_type() -> void:
	var was_pending = _is_pending
	_is_pending = false
	
	# 检查订单区域是否有需求物品类型一致的订单
	for order in OrderSystem.current_orders:
		if order == null or order.is_mainline:
			continue
		if order.requirements.size() < 2:
			continue
		
		# 检查该订单的所有需求是否类型一致
		var first_type = -1
		var all_same = true
		for req in order.requirements:
			var item_id = req.get("item_id", &"")
			var item_data = GameManager.get_item_data(item_id)
			if item_data == null:
				continue
			if first_type == -1:
				first_type = item_data.item_type
			elif item_data.item_type != first_type:
				all_same = false
				break
		
		if all_same and first_type != -1:
			_is_pending = true
			break
	
	# 状态变化时发送信号
	if _is_pending and not was_pending:
		triggered.emit(TRIGGER_PENDING)
	elif not _is_pending and was_pending:
		triggered.emit(TRIGGER_DEACTIVATE)


func _handle_order_completed(ctx: OrderCompletedContext) -> void:
	if ctx == null: return
	# 只处理普通订单，不处理主线订单
	if ctx.order_data != null and ctx.order_data.is_mainline: return
	
	if ctx.submitted_items.size() > 1:
		var first_type = ctx.submitted_items[0].item_data.item_type
		var consistent = true
		for i in range(1, ctx.submitted_items.size()):
			if ctx.submitted_items[i].item_data.item_type != first_type:
				consistent = false
				break
		if consistent:
			triggered.emit(TRIGGER_ACTIVATE)
			ctx.reward_gold = int(ctx.reward_gold * multiplier)


func get_visual_state() -> String:
	if _is_pending:
		return TRIGGER_PENDING
	return ""
