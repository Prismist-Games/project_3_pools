extends SkillEffect
class_name PovertyReliefSkillEffect

## 【贫困救济】
## 提交订单时，GameManager.gold < 5，奖励 +10。

@export var gold_threshold: int = 5
@export var bonus_gold: int = 10


func on_event(event_id: StringName, context: RefCounted) -> void:
	if event_id != &"order_completed":
		return
		
	var ctx = context as OrderCompletedContext
	if ctx == null: return
	
	if GameManager.gold < gold_threshold:
		ctx.reward_gold += bonus_gold






