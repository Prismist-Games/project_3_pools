extends SkillEffect
class_name OcdSkillEffect

## 【强迫症】
## 提交订单时若所有物品品质相同，奖励 x1.5。
## VFX: 物品栏中有满足某订单所有需求且品质均相同的物品组合时白色(Pending)

@export var multiplier: float = 1.5

## 当前是否处于激活状态
var _is_pending: bool = false


func initialize() -> void:
	_check_inventory_for_perfect_match()


func on_event(event_id: StringName, context: RefCounted) -> void:
	match event_id:
		&"orders_updated":
			# 只要列表变动（含库存变动触发的），都要检查
			_check_inventory_for_perfect_match()
		&"order_completed":
			_handle_order_completed(context as OrderCompletedContext)


## 检查是否有订单可以被“同一种品质”的物品完全满足
func _check_inventory_for_perfect_match() -> void:
	var was_pending = _is_pending
	_is_pending = false
	
	# 遍历所有普通订单
	for order in OrderSystem.current_orders:
		if order == null or order.is_mainline:
			continue
		# 只有多于1个物品的需求才有“强迫症”的意义（虽然单物品也可算同品质，但通常指整齐划一）
		# 这里不做严格限制，只需所有物品品质相同。如果订单只有1个需求，只要能满足自然就是同品质。
		# 但按照之前逻辑保留 size >= 1
		if order.requirements.is_empty():
			continue
			
		# 检查是否能用某种单一品质 R 完成该订单
		# 品质范围通常 0 (Common) 到 5 (Mythic)
		for r in range(6):
			if _can_fulfill_order_with_rarity(order, r):
				_is_pending = true
				break
		
		if _is_pending:
			break
	
	# 状态变化时发送信号
	if _is_pending and not was_pending:
		triggered.emit(TRIGGER_PENDING)
	elif not _is_pending and was_pending:
		triggered.emit(TRIGGER_DEACTIVATE)


## 辅助：检查特定订单能否仅用指定品质 R 的库存物品完成
func _can_fulfill_order_with_rarity(order: OrderData, rarity: int) -> bool:
	# 1. 统计背包里该品质 (rarity) 的物品数量
	var inventory_counts = {} # item_id -> count
	for item in InventorySystem.inventory:
		if item != null and item.rarity == rarity:
			# 注意：必须未过期且非特殊状态（假设 InventorySystem 会处理）
			# 这里只看存在性
			var id = item.item_data.id
			inventory_counts[id] = inventory_counts.get(id, 0) + 1
			
	# 2. 验证订单需求
	for req in order.requirements:
		var item_id = req.get("item_id", &"")
		var min_rarity = req.get("min_rarity", 0)
		var count = req.get("count", 1)
		
		# 关键：如果目标品质 R 低于需求品质，无法满足
		if rarity < min_rarity:
			return false
			
		if inventory_counts.get(item_id, 0) < count:
			return false
			
		inventory_counts[item_id] -= count
		
	return true


func _handle_order_completed(ctx: OrderCompletedContext) -> void:
	if ctx == null: return
	# 只处理普通订单，不处理主线订单
	if ctx.order_data != null and ctx.order_data.is_mainline: return
	
	# 检查提交的物品是否全部品质相同
	# 注意：对于单物品订单（如触发偷工减料后），单物品本身即满足“所有物品品质相同”，因此也会触发。
	if ctx.submitted_items.is_empty():
		return
		
	var first_rarity = ctx.submitted_items[0].rarity
	var consistent = true
	for i in range(1, ctx.submitted_items.size()):
		if ctx.submitted_items[i].rarity != first_rarity:
			consistent = false
			break
	
	if consistent:
		triggered.emit(TRIGGER_ACTIVATE)
		ctx.reward_coupon = int(ctx.reward_coupon * multiplier)


func get_visual_state() -> String:
	if _is_pending:
		return TRIGGER_PENDING
	return ""
