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
		&"item_landed_from_draw":
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
	
	# 1. 检测是否应该消耗激活状态 (Consolation Prize Active)
	if state.consolation_prize_active:
		# 只有当获得的物品確實是稀有及以上时，才视为消耗了这次保底机会
		# (如果是稀碎奖池的后续普通物品，则不消耗，也不升级，保留给下一次真正的抽奖)
		if item.rarity >= Constants.Rarity.RARE:
			state.consolation_prize_active = false
			# 只有在没有其他技能(如时来运转)共享此标记时才清除
			if not state.good_luck_active:
				state.next_draw_guaranteed_rare = false
			
			triggered.emit(TRIGGER_ACTIVATE)
			state.consecutive_commons = 0
			return
		else:
			# [Bug Fix] 如果在激活状态下收到了普通物品 (例如稀碎奖池的第2/3个物品)
			# 玩家期望即使是同一批次的物品也能享受到刚刚触发的保底效果
			# 因此，我们在这里立即升级物品并消耗保底
			state.consolation_prize_active = false
			if not state.good_luck_active:
				state.next_draw_guaranteed_rare = false
			
			item.rarity = Constants.Rarity.RARE
			triggered.emit(TRIGGER_ACTIVATE)
			state.consecutive_commons = 0
			return

	# 2. 计数逻辑：每个普通物品+1
	if item.rarity == Constants.Rarity.COMMON:
		state.consecutive_commons += 1
		# 检查是否达到阈值
		if state.consecutive_commons >= threshold:
			state.next_draw_guaranteed_rare = true
			state.consolation_prize_active = true
			triggered.emit(TRIGGER_PENDING)
			state.consecutive_commons = 0
	else:
		# 非普通物品重置计数
		state.consecutive_commons = 0


func get_visual_state() -> String:
	if SkillSystem.skill_state.consolation_prize_active:
		return TRIGGER_PENDING
	return ""

