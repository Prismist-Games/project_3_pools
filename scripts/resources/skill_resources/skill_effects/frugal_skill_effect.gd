extends SkillEffect
class_name FrugalSkillEffect

## 【精打细算】
## 当前金币 < 10 时，抽奖金币消耗 -2（最低为 1）。

@export var gold_threshold: int = 10
@export var discount_amount: int = 2


func on_event(event_id: StringName, context: RefCounted) -> void:
	if event_id != &"draw_requested":
		return
		
	var ctx = context as DrawContext
	if ctx == null: return
	
	if GameManager.gold < gold_threshold and ctx.pool_type != Constants.POOL_TYPE_MAINLINE:
		ctx.gold_cost = maxi(1, ctx.gold_cost - discount_amount)

