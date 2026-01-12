class_name OrderController
extends UIController

## Controller for Order/Quest Slots

var quest_slots_grid: VBoxContainer
var main_quest_slot: Control
var _slots: Array[Control] = [] # Stores normal quest slots (index 1 to 4)

func setup(grid: VBoxContainer, main_slot: Control) -> void:
	quest_slots_grid = grid
	main_quest_slot = main_slot
	_init_slots()

func _init_slots() -> void:
	_slots.clear()
	_slots.resize(5) # 0 unused, 1-4 used
	
	for i in range(1, 5):
		var slot = quest_slots_grid.get_node_or_null("Quest Slot_root_" + str(i))
		_slots[i] = slot
		
		if slot and slot.has_method("setup"):
			slot.setup(i)
			var input_area = slot.get_node("Input Area")
			if input_area:
				if input_area.gui_input.is_connected(_on_slot_input):
					input_area.gui_input.disconnect(_on_slot_input)
				input_area.gui_input.connect(_on_slot_input.bind(i))
	
	if main_quest_slot and main_quest_slot.has_method("setup"):
		main_quest_slot.setup(0)
		var input_area = main_quest_slot.get_node("Input Area")
		if input_area:
			if input_area.gui_input.is_connected(_on_slot_input):
				input_area.gui_input.disconnect(_on_slot_input)
			input_area.gui_input.connect(_on_slot_input.bind(-1))

func update_orders_display(orders: Array) -> void:
	var is_submit = false
	if game_ui and game_ui.state_machine:
		is_submit = (game_ui.state_machine.get_ui_mode() == Constants.UIMode.SUBMIT)

	for i in range(1, 5):
		var slot = _get_slot_node(i)
		var order = orders[i - 1] if (i - 1) < orders.size() else null
		
		if slot:
			# Propagate state to View Component
			if slot.has_method("set_submit_mode"):
				slot.set_submit_mode(is_submit)
				
			var req_states = []
			if order:
				req_states = _calculate_req_states(order, is_submit)
				
			if slot.has_method("update_order_display"):
				slot.update_order_display(order, req_states)
				
			if slot.is_locked and not game_ui.is_ui_locked():
				slot.is_locked = false

	var mainline_order = null
	for order in orders:
		if order.is_mainline:
			mainline_order = order
			break
	
	if main_quest_slot:
		if main_quest_slot.has_method("set_submit_mode"):
			main_quest_slot.set_submit_mode(is_submit)
			
		var req_states = []
		if mainline_order:
			req_states = _calculate_req_states(mainline_order, is_submit)
			
		if main_quest_slot.has_method("update_order_display"):
			main_quest_slot.update_order_display(mainline_order, req_states)
			
		if main_quest_slot.is_locked and not game_ui.is_ui_locked():
			main_quest_slot.is_locked = false

func _calculate_req_states(order: OrderData, is_submit_mode: bool) -> Array:
	var states = []
	var selected_indices = InventorySystem.multi_selected_indices
	
	for req in order.requirements:
		var item_id = req.get("item_id", &"")
		# 1. Owned Max Rarity
		var owned_max_rarity = InventorySystem.get_max_rarity_for_item(item_id)
		
		# 2. Is Selected (for submit mode)
		var is_selected = false
		if is_submit_mode:
			for idx in selected_indices:
				var item = InventorySystem.inventory[idx]
				if item and item.item_data.id == item_id:
					is_selected = true
					break
		
		states.append({
			"owned_max_rarity": owned_max_rarity,
			"is_selected": is_selected
		})
	return states

func play_refresh_sequence(index: int) -> void:
	if index == -1: return
	
	var slot = _get_slot_node(index + 1)
	if not slot: return
	
	if slot.anim_player.has_animation("lid_close"):
		slot.anim_player.play("lid_close")
		await slot.anim_player.animation_finished

func play_open_sequence(index: int) -> void:
	var slot = _get_slot_node(index + 1)
	if slot and slot.anim_player.has_animation("lid_open"):
		slot.anim_player.play("lid_open")
		await slot.anim_player.animation_finished

# --- Helpers ---

func _get_slot_node(index: int) -> Control:
	if index == -1: return main_quest_slot
	if index < 1 or index >= _slots.size(): return null
	return _slots[index]

# --- Input ---

func _on_slot_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if game_ui.state_machine and game_ui.state_machine.get_ui_mode() == Constants.UIMode.SUBMIT:
				var order_idx = index - 1 if index != -1 else -1
				_handle_smart_select_for_order(order_idx)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# 右键取消逻辑已移至 Game2DUI._input 全局处理
			pass

func _handle_smart_select_for_order(order_index: int) -> void:
	var order: OrderData = null
	
	if order_index == -1:
		for o in OrderSystem.current_orders:
			if o.is_mainline:
				order = o
				break
	else:
		if order_index >= 0 and order_index < OrderSystem.current_orders.size():
			order = OrderSystem.current_orders[order_index]
	
	if not order: return
	
	var target_indices: Array[int] = order.find_smart_selection(InventorySystem.inventory)
	
	var changed = false
	for idx in target_indices:
		if idx not in InventorySystem.multi_selected_indices:
			InventorySystem.multi_selected_indices.append(idx)
			changed = true
	
	if changed:
		InventorySystem.multi_selection_changed.emit(InventorySystem.multi_selected_indices)
