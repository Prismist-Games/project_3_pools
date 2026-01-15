extends SkillEffect
class_name GoodLuckNextSkillEffect

## 【时来运转】
## 完成任意订单后，下次抽奖必定稀有以上。
## 实现方式：在 item_obtained 时检查并升级品质

func on_event(event_id: StringName, context: RefCounted) -> void:
	match event_id:
		&"order_completed":
			_handle_order_completed()
		&"draw_requested":
			_handle_draw_requested(context as DrawContext)
		&"item_obtained":
			_handle_item_obtained(context as ItemInstance)


func _handle_order_completed() -> void:
	SkillSystem.skill_state.next_draw_guaranteed_rare = true
	triggered.emit(TRIGGER_PENDING)


func _handle_draw_requested(ctx: DrawContext) -> void:
	# 对标准抽奖流程生效
	if ctx == null: return
	
	if SkillSystem.skill_state.next_draw_guaranteed_rare:
		ctx.min_rarity = Constants.Rarity.RARE
		# 注意：不在这里清除标记，因为可能被 skip_draw 跳过


func _handle_item_obtained(item: ItemInstance) -> void:
	# 对特殊词缀(精准/有的放矢/以旧换新)生效
	if item == null: return
	
	if SkillSystem.skill_state.next_draw_guaranteed_rare:
		SkillSystem.skill_state.next_draw_guaranteed_rare = false
		triggered.emit(TRIGGER_ACTIVATE)
		# 如果品质低于稀有，升级到稀有
		if item.rarity < Constants.Rarity.RARE:
			item.rarity = Constants.Rarity.RARE
