extends SkillEffect
class_name AutoRestockSkillEffect

## 【自动补货】
## 完成任意订单后，下次抽奖的第一个物品会被复制一份（同物品、同品质）。

## 注意：精准/有的放矢等词缀不会发出 item_obtained，所以我们也监听 item_added
## 这里使用一个标记来防止同一物品被复制两次（item_obtained 和 item_added 可能都触发）
var _last_cloned_item: ItemInstance = null

func on_event(event_id: StringName, context: RefCounted) -> void:
	match event_id:
		&"order_completed":
			_handle_order_completed()
		&"item_obtained":
			_handle_item_for_clone(context as ItemInstance)


func _ready_check() -> void:
	# 监听 InventorySystem.item_added 信号（用于精准等不发 item_obtained 的场景）
	if not InventorySystem.item_added.is_connected(_on_item_added):
		InventorySystem.item_added.connect(_on_item_added)


func _on_item_added(item: ItemInstance, _index: int) -> void:
	_handle_item_for_clone(item)


func _handle_order_completed() -> void:
	SkillSystem.skill_state.next_draw_extra_item = true
	triggered.emit(TRIGGER_PENDING)
	
	_last_cloned_item = null
	
	# 确保连接了 item_added 信号
	_ready_check()


func _handle_item_for_clone(item: ItemInstance) -> void:
	if item == null: return
	
	var state = SkillSystem.skill_state
	
	if state.next_draw_extra_item:
		# 防止同一物品被复制两次
		if item == _last_cloned_item:
			return
			
		state.next_draw_extra_item = false
		_last_cloned_item = item
		
		triggered.emit(TRIGGER_ACTIVATE)
		
		# 立即创建克隆物品（捕获当前品质）
		var cloned_item = ItemInstance.new(item.item_data, item.rarity, item.sterile, item.shelf_life)
		_deferred_add_to_queue.call_deferred(cloned_item)


func _deferred_add_to_queue(cloned_item: ItemInstance) -> void:
	# 将复制的物品加入待定队列
	InventorySystem.pending_item = cloned_item
	
	# 尝试自动将物品添加到背包（会自动处理飞行动画等）
	InventorySystem.try_auto_add_pending()
