extends SkillEffect
class_name BigOrderExpertSkillEffect

## 【大订单专家】
## 完成需求物品数为 4 的订单时，额外获得 5 金币。
## VFX: 订单区域有4件需求订单时白色(Pending)

@export var count_threshold: int = 4
@export var bonus_gold: int = 5

## 当前是否处于激活状态
var _is_pending: bool = false


func initialize() -> void:
	_check_orders_for_big()


func on_event(event_id: StringName, context: RefCounted) -> void:
	match event_id:
		&"orders_updated":
			_check_orders_for_big()
		&"order_completed":
			_handle_order_completed(context as OrderCompletedContext)


func _check_orders_for_big() -> void:
	var was_pending = _is_pending
	_is_pending = false
	
	# 检查订单区域是否有4件需求的订单
	for order in OrderSystem.current_orders:
		if order == null or order.is_mainline:
			continue
		if order.requirements.size() >= count_threshold:
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
	
	if ctx.submitted_items.size() >= count_threshold:
		triggered.emit(TRIGGER_ACTIVATE)
		ctx.reward_gold += bonus_gold


func get_visual_state() -> String:
	if _is_pending:
		return TRIGGER_PENDING
	return ""
