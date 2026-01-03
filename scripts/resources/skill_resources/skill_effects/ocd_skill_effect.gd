extends SkillEffect
class_name OcdSkillEffect

## 【强迫症】
## 提交订单时若所有物品同一类型，奖励翻倍。

@export var multiplier: float = 2.0


func on_event(event_id: StringName, context: RefCounted) -> void:
	if event_id != &"order_completed":
		return
		
	var ctx = context as OrderCompletedContext
	if ctx == null: return
	
	if ctx.submitted_items.size() > 1:
		var first_type = ctx.submitted_items[0].item_data.type
		var consistent = true
		for i in range(1, ctx.submitted_items.size()):
			if ctx.submitted_items[i].item_data.type != first_type:
				consistent = false
				break
		if consistent:
			ctx.reward_gold *= multiplier
			ctx.reward_tickets *= multiplier


