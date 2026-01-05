extends SkillEffect
class_name VipDiscountSkillEffect

## 【贵宾折扣】
## 奖池带有交互词缀 (precise / targeted)，消耗 -1 (最低为 0)。

@export var discount_amount: int = 1


func on_event(event_id: StringName, context: RefCounted) -> void:
	if event_id != &"draw_requested":
		return
		
	var ctx = context as DrawContext
	if ctx == null: return
	
	if ctx.affix_id == &"precise" or ctx.affix_id == &"targeted":
		ctx.gold_cost = maxi(0, ctx.gold_cost - discount_amount)



