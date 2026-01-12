class_name InventoryController
extends UIController

## Controller for Inventory Slots and Interactions

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
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Delegate to state machine via Game2DUI or access directly
			if game_ui and game_ui.state_machine:
				var current_state = game_ui.state_machine.get_current_state()
				if current_state and current_state.has_method("select_slot"):
					current_state.select_slot(index)
					return
					
			InventorySystem.handle_slot_click(index)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# 右键取消逻辑已移至 Game2DUI._input 全局处理
			pass

func _on_slot_mouse_entered(index: int) -> void:
	# Preview logic (delegated back to Game2DUI or SwitchController later)
	if game_ui and game_ui.has_method("_on_item_slot_mouse_entered"):
		game_ui._on_item_slot_mouse_entered(index)

func _on_slot_mouse_exited(index: int) -> void:
	if game_ui and game_ui.has_method("_on_item_slot_mouse_exited"):
		game_ui._on_item_slot_mouse_exited(index)
