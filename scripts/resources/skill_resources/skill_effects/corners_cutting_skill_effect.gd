extends SkillEffect
class_name CornersCuttingSkillEffect

## 【偷工减料】
## 刷新出新订单时，20% 概率使订单需求数量 -1（最低为 1）。

@export var chance: float = 0.20
@export var reduction: int = 1


func on_event(event_id: StringName, context: RefCounted) -> void:
	if event_id != &"order_requirement_generating":
		return
		
	if context == null: return
	
	if randf() < chance:
		var current_count = context.get("data").get("item_count", 0)
		if current_count > 1:
			context.get("data")["item_count"] = maxi(1, current_count - reduction)


