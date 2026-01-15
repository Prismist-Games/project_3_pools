extends SkillEffect
class_name ConsolationPrizeSkillEffect

## 【安慰奖】
## 连续 5 次抽到普通品质物品后，下次抽奖必定稀有以上。
## 稀碎(3个物品)计数为+3

@export var threshold: int = 5


func on_event(event_id: StringName, context: RefCounted) -> void:
	match event_id:
		&"draw_requested":
			_handle_draw_requested(context as DrawContext)
		&"item_obtained":
			_handle_item_obtained(context as ItemInstance)


func _handle_draw_requested(ctx: DrawContext) -> void:
	# 对标准抽奖流程生效
	if ctx == null: return
	
	if SkillSystem.skill_state.next_draw_guaranteed_rare:
		ctx.min_rarity = Constants.Rarity.RARE
		# 不在这里清除标记，因为可能被 skip_draw 跳过


func _handle_item_obtained(item: ItemInstance) -> void:
	if item == null: return
	
	var state = SkillSystem.skill_state
	
	# 如果标记激活，先升级品质
	if state.next_draw_guaranteed_rare:
		state.next_draw_guaranteed_rare = false
		if item.rarity < Constants.Rarity.RARE:
			triggered.emit(TRIGGER_ACTIVATE)
			item.rarity = Constants.Rarity.RARE
		else:
			# Even if naturally rare or better, we consider the skill "effect" consumed and active contextually
			# But strictly speaking if it didn't change anything, maybe we don't flash? 
			# Let's flash to show "Protection Used" or just "Skill Active".
			triggered.emit(TRIGGER_ACTIVATE)
			
		# 当触发安慰奖后重置计数
		state.consecutive_commons = 0
		return
	
	# 计数逻辑：每个普通物品+1
	if item.rarity == Constants.Rarity.COMMON:
		state.consecutive_commons += 1
		# 检查是否达到阈值
		if state.consecutive_commons >= threshold:
			state.next_draw_guaranteed_rare = true
			triggered.emit(TRIGGER_PENDING)
			state.consecutive_commons = 0
	else:
		# 非普通物品重置计数
		state.consecutive_commons = 0
