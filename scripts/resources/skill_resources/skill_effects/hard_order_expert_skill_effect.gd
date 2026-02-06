extends SkillEffect
class_name HardOrderExpertSkillEffect

## 【困难订单专家】
## 完成订单时若提交了史诗以上品质的物品，额外获得 2 金币。
## VFX: 订单区域有紫色需求订单时白色(Pending)

@export var rarity_threshold: int = Constants.Rarity.EPIC
@export var bonus_gold: int = 2

## 当前是否处于激活状态
var _is_pending: bool = false


func initialize() -> void:
	_check_orders_for_hard()


func on_event(event_id: StringName, context: RefCounted) -> void:
	match event_id:
		&"orders_updated":
			_check_orders_for_hard()
		&"order_completed":
			_handle_order_completed(context as OrderCompletedContext)


func _check_orders_for_hard() -> void:
	var was_pending = _is_pending
	_is_pending = false
	
	# 检查订单区域是否有紫色需求的订单（不包括主线订单）
	for order in OrderSystem.current_orders:
		if order == null or order.is_mainline:
			continue
		for req in order.requirements:
			var min_rarity = req.get("min_rarity", 0)
			if min_rarity >= rarity_threshold:
				_is_pending = true
				break
		if _is_pending:
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
	
	var has_hard = false
	for item in ctx.submitted_items:
		if item.rarity >= rarity_threshold:
			has_hard = true
			break
	if has_hard:
		triggered.emit(TRIGGER_ACTIVATE)
		GameManager.add_gold(bonus_gold)


func get_visual_state() -> String:
	if _is_pending:
		return TRIGGER_PENDING
	return ""
