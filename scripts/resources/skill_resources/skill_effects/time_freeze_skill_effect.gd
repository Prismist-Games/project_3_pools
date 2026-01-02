extends SkillEffect
class_name TimeFreezeSkillEffect

## 【时间冻结】
## 刷新单个订单时，20% 概率不消耗该订单的剩余刷新次数。

@export var chance: float = 0.20


func on_event(event_id: StringName, context: RefCounted) -> void:
	if event_id != &"order_refresh_requested":
		return
		
	if context == null: return
	
	if randf() < chance:
		context.get("data")["consume_refresh"] = false

