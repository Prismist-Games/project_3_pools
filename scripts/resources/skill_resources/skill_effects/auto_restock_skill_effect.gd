extends SkillEffect
class_name AutoRestockSkillEffect

## 【自动补货】
## 完成任意订单后，下次抽奖额外获得 1 个物品。

@export var extra_items: int = 1


func on_event(event_id: StringName, context: RefCounted) -> void:
	match event_id:
		&"order_completed":
			_handle_order_completed()
		&"draw_requested":
			_handle_draw_requested(context as DrawContext)


func _handle_order_completed() -> void:
	var skill_sys = Engine.get_main_loop().root.get_node("/root/SkillSystem")
	skill_sys.skill_state.next_draw_extra_item = true


func _handle_draw_requested(ctx: DrawContext) -> void:
	if ctx == null: return
	
	var skill_sys = Engine.get_main_loop().root.get_node("/root/SkillSystem")
	var state = skill_sys.skill_state
	
	if state.next_draw_extra_item:
		ctx.item_count += extra_items
		state.next_draw_extra_item = false


