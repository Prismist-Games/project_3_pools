extends SkillEffect
class_name BigOrderExpertSkillEffect

## 【大订单专家】
## 完成需求物品数为 4 的订单时，额外获得 40 金币。

@export var count_threshold: int = 4
@export var bonus_gold: int = 40


func on_event(event_id: StringName, context: RefCounted) -> void:
	if event_id != &"order_completed":
		return
		
	var ctx = context as OrderCompletedContext
	if ctx == null: return
	
	if ctx.submitted_items.size() >= count_threshold:
		ctx.reward_gold += bonus_gold
