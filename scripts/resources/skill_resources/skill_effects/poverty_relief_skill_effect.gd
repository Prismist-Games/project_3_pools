extends SkillEffect
class_name PovertyReliefSkillEffect

## 【贫困救济】
## 提交订单时，GameManager.gold <= 10，额外获得 +3 金币。
## VFX: 金币<=10时白色(Pending)，完成订单时若触发变黄色(Activate)

@export var gold_threshold: int = 10
@export var bonus_gold: int = 3

## 当前是否处于激活状态
var _is_pending: bool = false


func on_event(event_id: StringName, context: RefCounted) -> void:
	match event_id:
		&"gold_changed":
			_handle_gold_changed()
		&"order_completed":
			_handle_order_completed(context as OrderCompletedContext)


func _handle_gold_changed() -> void:
	var was_pending = _is_pending
	_is_pending = GameManager.gold <= gold_threshold
	
	# 状态变化时发送信号
	if _is_pending and not was_pending:
		triggered.emit(TRIGGER_PENDING)
	elif not _is_pending and was_pending:
		triggered.emit(TRIGGER_DEACTIVATE)


func _handle_order_completed(ctx: OrderCompletedContext) -> void:
	if ctx == null: return
	
	if GameManager.gold <= gold_threshold:
		triggered.emit(TRIGGER_ACTIVATE)
		GameManager.add_gold(bonus_gold)


func get_visual_state() -> String:
	if _is_pending:
		return TRIGGER_PENDING
	return ""
