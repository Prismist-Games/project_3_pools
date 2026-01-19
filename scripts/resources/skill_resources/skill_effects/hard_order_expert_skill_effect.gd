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
	
	# 检查订单数据是否存在
	if ctx.order_data == null:
		return
	
	# 检查订单需求中是否有史诗及以上品质要求
	var has_hard_requirement = false
	for req in ctx.order_data.requirements:
		var min_rarity = req.get("min_rarity", 0)
		if min_rarity >= rarity_threshold:
			has_hard_requirement = true
			break
			
	if has_hard_requirement:
		triggered.emit(TRIGGER_INSTANT)
		ctx.reward_gold += bonus_gold
