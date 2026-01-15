extends SkillEffect
class_name HardOrderExpertSkillEffect

## 【困难订单专家】
## 完成需要史诗以上品质物品的订单时，额外获得 60 金币。

@export var rarity_threshold: int = Constants.Rarity.EPIC
@export var bonus_gold: int = 10


func on_event(event_id: StringName, context: RefCounted) -> void:
	if event_id != &"order_completed":
		return
		
	var ctx = context as OrderCompletedContext
	if ctx == null: return
	
	var has_hard = false
	for item in ctx.submitted_items:
		if item.rarity >= rarity_threshold:
			has_hard = true
			break
	if has_hard:
		triggered.emit(TRIGGER_INSTANT)
		ctx.reward_gold += bonus_gold
