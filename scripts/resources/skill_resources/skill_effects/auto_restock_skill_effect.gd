extends SkillEffect
class_name AutoRestockSkillEffect

## 【自动补货】
## 完成任意订单后，下次抽奖的第一个物品会被复制一份（同物品、同品质）。

func on_event(event_id: StringName, context: RefCounted) -> void:
	match event_id:
		&"order_completed":
			_handle_order_completed()
		&"item_obtained":
			_handle_item_obtained(context as ItemInstance)


func _handle_order_completed() -> void:
	SkillSystem.skill_state.next_draw_extra_item = true


func _handle_item_obtained(item: ItemInstance) -> void:
	if item == null: return
	
	var state = SkillSystem.skill_state
	
	if state.next_draw_extra_item:
		state.next_draw_extra_item = false
		
		# 使用延迟执行，确保其他技能（如时来运转）先处理完物品
		# 这样复制的物品会是升级后的品质
		_deferred_clone.call_deferred(item)


func _deferred_clone(item: ItemInstance) -> void:
	# 复制该物品（同物品、同品质 - 此时物品已被其他技能如时来运转升级）
	var cloned_item = ItemInstance.new(item.item_data, item.rarity, item.sterile, item.shelf_life)
	
	# 将复制的物品加入待定队列
	InventorySystem.pending_item = cloned_item
	
	# 通知技能系统物品获得（触发其他技能如安慰奖的计数）
	EventBus.item_obtained.emit(cloned_item)
