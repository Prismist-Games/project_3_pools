extends SkillEffect
class_name ConsolationPrizeSkillEffect

## 【安慰奖】
## 连续 5 次抽到普通品质物品后，下次抽奖必定稀有以上。

@export var threshold: int = 5


func on_event(event_id: StringName, context: RefCounted) -> void:
	match event_id:
		&"item_obtained":
			_handle_item_obtained(context)
		&"draw_requested":
			_handle_draw_requested(context as DrawContext)


func _handle_item_obtained(item_instance: RefCounted) -> void:
	var item = item_instance as ItemInstance
	if item == null: return
	
	var skill_sys = Engine.get_main_loop().root.get_node("/root/SkillSystem")
	var state = skill_sys.skill_state
	
	if item.rarity == Constants.Rarity.COMMON:
		state.consecutive_commons += 1
	else:
		state.consecutive_commons = 0
		
	if state.consecutive_commons >= threshold:
		state.next_draw_guaranteed_rare = true
		state.consecutive_commons = 0


func _handle_draw_requested(ctx: DrawContext) -> void:
	if ctx == null: return
	
	var skill_sys = Engine.get_main_loop().root.get_node("/root/SkillSystem")
	var state = skill_sys.skill_state
	
	if state.next_draw_guaranteed_rare:
		ctx.min_rarity = Constants.Rarity.RARE
		state.next_draw_guaranteed_rare = false



