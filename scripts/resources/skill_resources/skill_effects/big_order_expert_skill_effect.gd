extends SkillEffect
class_name BigOrderExpertSkillEffect

## 【大订单专家】
## 完成需求物品数为 4 的订单时，额外获得 10 张奖券。

@export var count_threshold: int = 4
@export var bonus_tickets: int = 10


func on_event(event_id: StringName, context: RefCounted) -> void:
	if event_id != &"order_completed":
		return
		
	var ctx = context as OrderCompletedContext
	if ctx == null: return
	
	if ctx.submitted_items.size() >= count_threshold:
		ctx.reward_tickets += bonus_tickets


