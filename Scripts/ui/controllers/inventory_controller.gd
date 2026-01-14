class_name InventoryController
extends UIController

## Controller for Inventory Slots and Interactions

## 鼠标悬停信号 (用于高亮订单图标)
signal slot_hovered(slot_index: int, item_id: StringName)
signal slot_unhovered(slot_index: int)

## 当前被hover的slot索引 (-1表示无)
var _hovered_slot_index: int = -1

## 当前被按下的slot索引 (-1表示无，用于处理鼠标移出后松开的情况)
var _pressed_slot_index: int = -1

var item_slots_grid: GridContainer
var _slots: Array[Control] = []

func setup(grid: GridContainer) -> void:
	item_slots_grid = grid
	_init_slots()
	_connect_signals()

func _init_slots() -> void:
	_slots.clear()
	_slots.resize(10)
	
	for i in range(10):
		var slot = item_slots_grid.get_node_or_null("Item Slot_root_" + str(i))
		_slots[i] = slot
		
		if slot and slot.has_method("setup"):
			slot.setup(i)
			var input_area = slot.get_node("Input Area")
			if input_area:
				# Disconnect first to avoid duplicates if re-initializing
				if input_area.gui_input.is_connected(_on_slot_input):
					input_area.gui_input.disconnect(_on_slot_input)
				if input_area.mouse_entered.is_connected(_on_slot_mouse_entered):
					input_area.mouse_entered.disconnect(_on_slot_mouse_entered)
				if input_area.mouse_exited.is_connected(_on_slot_mouse_exited):
					input_area.mouse_exited.disconnect(_on_slot_mouse_exited)
					
				input_area.gui_input.connect(_on_slot_input.bind(i))
				input_area.mouse_entered.connect(_on_slot_mouse_entered.bind(i))
				input_area.mouse_exited.connect(_on_slot_mouse_exited.bind(i))

func _connect_signals() -> void:
	# Inventory signals are mainly handled by Game2DUI routing for now
	pass

func update_all_slots(inventory: Array) -> void:
	for i in range(10):
		var slot = get_slot_node(i)
		var item = inventory[i] if i < inventory.size() else null
		if slot:
			slot.update_display(item)
			if item:
				var badge = _calculate_badge_state(item)
				if slot.has_method("update_status_badge"):
					slot.update_status_badge(badge)

func update_slot(index: int, item: ItemInstance) -> void:
	var slot = get_slot_node(index)
	if slot:
		slot.update_display(item)
		if item:
			var badge = _calculate_badge_state(item)
			if slot.has_method("update_status_badge"):
				slot.update_status_badge(badge)

func _calculate_badge_state(item: ItemInstance) -> int:
	var badge_state = 0
	# Access OrderSystem directly (Controller knows about Systems)
	for order in OrderSystem.current_orders:
		for req in order.requirements:
			if req.get("item_id", &"") == item.item_data.id:
				if item.rarity >= req.get("min_rarity", 0):
					badge_state = 2
					return 2 # Highest priority
				else:
					if badge_state < 1:
						badge_state = 1
	return badge_state

func update_selection(index: int) -> void:
	for i in range(10):
		var slot = get_slot_node(i)
		var should_be_selected = (i == index)
		if slot and slot._is_selected != should_be_selected:
			slot.set_selected(should_be_selected)
			# Re-apply badge if deselected
			if not should_be_selected and InventorySystem.inventory.size() > i:
				var item = InventorySystem.inventory[i]
				if item:
					var badge = _calculate_badge_state(item)
					if slot.has_method("update_status_badge"):
						slot.update_status_badge(badge)

func update_multi_selection(indices: Array[int]) -> void:
	for i in range(10):
		var slot = get_slot_node(i)
		if slot:
			if i in indices:
				slot.set_selected(true)
			else:
				if slot._is_selected:
					slot.set_selected(false)
					# Re-apply badge
					if InventorySystem.inventory.size() > i:
						var item = InventorySystem.inventory[i]
						if item:
							var badge = _calculate_badge_state(item)
							if slot.has_method("update_status_badge"):
								slot.update_status_badge(badge)

func set_slots_locked(locked: bool) -> void:
	for i in range(10):
		var slot = get_slot_node(i)
		if slot:
			slot.is_locked = locked

func highlight_items_by_id(item_id: StringName) -> void:
	for i in range(10):
		var slot = get_slot_node(i)
		if not slot: continue
		
		var item = InventorySystem.inventory[i] if i < InventorySystem.inventory.size() else null
		if item and item.item_data.id == item_id:
			if slot.has_method("set_highlight"):
				slot.set_highlight(true)
		else:
			if slot.has_method("set_highlight"):
				slot.set_highlight(false)

func clear_highlights() -> void:
	for slot in _slots:
		if slot and slot.has_method("set_highlight"):
			slot.set_highlight(false)

# --- Helpers ---

func get_slot_node(index: int) -> Control:
	if index < 0 or index >= _slots.size(): return null
	return _slots[index]

func _get_slot_node(index: int) -> Control: # Backward compatibility
	return get_slot_node(index)

func get_slot_global_position(index: int) -> Vector2:
	var slot = get_slot_node(index)
	if slot and slot.has_method("get_icon_global_position"):
		return slot.get_icon_global_position()
	return Vector2.ZERO

func get_slot_global_scale(index: int) -> Vector2:
	var slot = get_slot_node(index)
	if slot and slot.has_method("get_icon_global_scale"):
		return slot.get_icon_global_scale()
	return Vector2.ONE

# --- Input Handlers ---

func _on_slot_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var slot = get_slot_node(index) as ItemSlotUI
			
			if event.pressed:
				# 鼠标按下：icon缩小
				_pressed_slot_index = index
				if slot and slot.has_method("handle_mouse_press"):
					slot.handle_mouse_press()
			else:
				# 鼠标松开：确认点击行为
				# Delegate to state machine via Game2DUI or access directly
				if game_ui and game_ui.state_machine:
					var current_state = game_ui.state_machine.get_current_state()
					if current_state and current_state.has_method("select_slot"):
						current_state.select_slot(index)
						_pressed_slot_index = -1
						if slot and slot.has_method("handle_mouse_release"):
							slot.handle_mouse_release()
						return
					
				InventorySystem.handle_slot_click(index)
				_pressed_slot_index = -1
				if slot and slot.has_method("handle_mouse_release"):
					slot.handle_mouse_release()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# 右键取消逻辑已移至 Game2DUI._input 全局处理
			pass

func _on_slot_mouse_entered(index: int) -> void:
	_hovered_slot_index = index
	
	# 通知slot被hover
	var slot = get_slot_node(index)
	if slot and slot.has_method("on_mouse_enter"):
		slot.on_mouse_enter()
	
	# 更新hover可操作状态
	_update_slot_hover_action_state(index)
	
	# Preview logic (delegated back to Game2DUI or SwitchController later)
	if game_ui and game_ui.has_method("_on_item_slot_mouse_entered"):
		game_ui._on_item_slot_mouse_entered(index)
	
	# 发射 hover 信号用于高亮订单图标
	var item = InventorySystem.inventory[index] if index < InventorySystem.inventory.size() else null
	if item and not item.is_expired: # ERA_4: 过期物品不触发订单高亮
		slot_hovered.emit(index, item.item_data.id)
	else:
		slot_hovered.emit(index, &"")


func _on_slot_mouse_exited(index: int) -> void:
	_hovered_slot_index = -1
	
	# 通知slot不再被hover（会自动清除hover视觉效果）
	var slot = get_slot_node(index)
	if slot and slot.has_method("on_mouse_exit"):
		slot.on_mouse_exit()
	
	if game_ui and game_ui.has_method("_on_item_slot_mouse_exited"):
		game_ui._on_item_slot_mouse_exited(index)
	
	# 发射 unhover 信号
	slot_unhovered.emit(index)


## 更新指定slot的hover可操作状态
func _update_slot_hover_action_state(index: int) -> void:
	var slot = get_slot_node(index) as ItemSlotUI
	if not slot:
		return
	
	# 只有真的在hover才继续，否则确保状态清除
	if not slot.is_hovered():
		slot.set_hover_action_state(ItemSlotUI.HoverType.NONE)
		return
	
	var target_item = InventorySystem.inventory[index] if index < InventorySystem.inventory.size() else null
	var pending = InventorySystem.pending_item
	var has_pending = pending != null
	var selected_idx = InventorySystem.selected_slot_index
	var has_selection = selected_idx != -1
	var ui_mode = Constants.UIMode.NORMAL
	
	if game_ui and game_ui.state_machine:
		ui_mode = game_ui.state_machine.get_ui_mode()
	
	# 默认无状态
	var hover_type = ItemSlotUI.HoverType.NONE
	
	# 1. 回收模式下 hover item slot -> 可回收
	if ui_mode == Constants.UIMode.RECYCLE and target_item != null:
		hover_type = ItemSlotUI.HoverType.RECYCLABLE
	
	# 2. pending时 hover 在有东西的 item_slot -> 可回收 (如果不能合成)
	elif has_pending and target_item != null:
		if InventorySystem.can_merge(pending, target_item):
			# 可合成
			hover_type = ItemSlotUI.HoverType.MERGEABLE
		else:
			# 不能合成，替换 = 回收
			hover_type = ItemSlotUI.HoverType.RECYCLABLE
	
	# 3. 选中item物品时 hover 在可合成的另一个 item slot 上 -> 可合成
	elif has_selection and selected_idx != index and target_item != null:
		var selected_item = InventorySystem.inventory[selected_idx] if selected_idx < InventorySystem.inventory.size() else null
		if selected_item and InventorySystem.can_merge(selected_item, target_item):
			hover_type = ItemSlotUI.HoverType.MERGEABLE
	
	slot.set_hover_action_state(hover_type)


## 刷新当前被hover的slot的状态（当游戏状态变化时调用）
func refresh_hovered_slot_state() -> void:
	if _hovered_slot_index >= 0:
		_update_slot_hover_action_state(_hovered_slot_index)


## 获取当前被hover的slot索引
func get_hovered_slot_index() -> int:
	return _hovered_slot_index

## 处理全局鼠标松开事件（用于处理鼠标移出区域后松开的情况）
func handle_global_mouse_release() -> void:
	if _pressed_slot_index >= 0:
		var slot = get_slot_node(_pressed_slot_index) as ItemSlotUI
		if slot and slot.has_method("handle_mouse_release"):
			slot.handle_mouse_release()
		_pressed_slot_index = -1
