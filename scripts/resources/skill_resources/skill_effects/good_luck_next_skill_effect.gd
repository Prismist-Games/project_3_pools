extends SkillEffect
class_name GoodLuckNextSkillEffect

## 【时来运转】
## 完成任意订单后，下次抽奖必定稀有以上。

func on_event(event_id: StringName, context: RefCounted) -> void:
	match event_id:
		&"order_completed":
			_handle_order_completed()
		&"draw_requested":
			_handle_draw_requested(context as DrawContext)


func _handle_order_completed() -> void:
	var skill_sys = Engine.get_main_loop().root.get_node("/root/SkillSystem")
	skill_sys.skill_state.next_draw_guaranteed_rare = true


func _handle_draw_requested(ctx: DrawContext) -> void:
	if ctx == null: return
	
	var skill_sys = Engine.get_main_loop().root.get_node("/root/SkillSystem")
	var state = skill_sys.skill_state
	
	if state.next_draw_guaranteed_rare:
		ctx.min_rarity = Constants.Rarity.RARE
		state.next_draw_guaranteed_rare = false

