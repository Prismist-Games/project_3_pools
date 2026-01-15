extends SkillEffect
class_name CornersCuttingSkillEffect

## 【偷工减料】
## 刷新出新订单时，20% 概率使订单需求数量 -1（最低为 1）。
## 注意：奖励仍按原数量计算

@export var chance: float = 0.20
@export var reduction: int = 1


func on_event(event_id: StringName, context: RefCounted) -> void:
	if event_id != &"order_requirement_count_generating":
		return
		
	var ctx = context as ContextProxy
	if ctx == null: return
	
	if randf() < chance:
		var current_count = ctx.get_value("requirement_count", 1)
		if current_count > 1:
			ctx.set_value("requirement_count", maxi(1, current_count - reduction))
