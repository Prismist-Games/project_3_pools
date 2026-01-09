class_name PoolController
extends UIController

## Controller for Pool/Lottery Slots

var lottery_slots_grid: HBoxContainer
var _slots: Array[Control] = []

func setup(grid: HBoxContainer) -> void:
	lottery_slots_grid = grid
	_init_slots()

func _init_slots() -> void:
	_slots.clear()
	_slots.resize(3)
	
	for i in range(3):
		var slot = lottery_slots_grid.get_node_or_null("Lottery Slot_root_" + str(i))
		_slots[i] = slot
		
		if slot and slot.has_method("setup"):
			slot.setup(i)
			var input_area = slot.get_node("Input Area")
			if input_area:
				if input_area.gui_input.is_connected(_on_slot_input):
					input_area.gui_input.disconnect(_on_slot_input)
				input_area.gui_input.connect(_on_slot_input.bind(i))

func update_pools_display(pools: Array) -> void:
	for i in range(3):
		var slot = _get_slot_node(i)
		if i < pools.size():
			slot.update_pool_info(pools[i])
			var hints = _calculate_order_hints(pools[i].item_type)
			if slot.has_method("update_order_hints"):
				slot.update_order_hints(hints.display_items, hints.satisfied_map)
			slot.visible = true
		else:
			slot.visible = false

func _calculate_order_hints(pool_type: int) -> Dictionary:
	# 1. 收集所有订单需求的物品 ID
	var required_ids: Dictionary = {} # 使用字典去重
	for order in OrderSystem.current_orders:
		for req in order.requirements:
			var id = req.get("item_id", &"")
			if id != &"":
				required_ids[id] = true
	
	# 2. 获取该池子类型下的所有物品，并过滤出被订单要求的
	var pool_items = GameManager.get_items_for_type(pool_type)
	var display_items: Array[ItemData] = []
	var satisfied_map: Dictionary = {}
	
	for item_data in pool_items:
		if item_data.id in required_ids:
			display_items.append(item_data)
			satisfied_map[item_data.id] = InventorySystem.has_item_data(item_data)
			
	return {"display_items": display_items, "satisfied_map": satisfied_map}

func update_pending_display(items: Array[ItemInstance], source_pool_idx: int) -> void:
	if items.is_empty():
		for i in range(3):
			var slot = _get_slot_node(i)
			if slot.has_method("update_pending_display"):
				slot.update_pending_display([])
		return
	
	if source_pool_idx != -1:
		var slot = _get_slot_node(source_pool_idx)
		if slot.has_method("update_pending_display"):
			slot.update_pending_display(items)

func set_slots_locked(locked: bool) -> void:
	for i in range(3):
		var slot = _get_slot_node(i)
		if slot:
			slot.is_locked = locked

# --- Helpers ---

func get_slot_snapshot(index: int) -> Dictionary:
	var slot = _get_slot_node(index)
	if not slot: return {}
	
	return {
		"global_position": slot.get_main_icon_global_position(),
		"global_scale": slot.get_main_icon_global_scale()
	}

func _get_slot_node(index: int) -> Control:
	if index < 0 or index >= _slots.size(): return null
	return _slots[index]

# --- Input Handlers ---

func _on_slot_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Check logic via game_ui state machine
			if game_ui and game_ui.state_machine:
				var state_name = game_ui.state_machine.get_current_state_name()
				
				# If in specialized selection states
				if state_name == &"PreciseSelection" or state_name == &"Modal":
					var current_state = game_ui.state_machine.get_current_state()
					if current_state and current_state.has_method("select_option"):
						current_state.select_option(index)
						return
				
				# Check UI mode via UIStateMachine
				if game_ui.state_machine.get_ui_mode() != Constants.UIMode.NORMAL:
					return
				
			elif GameManager.current_ui_mode != Constants.UIMode.NORMAL:
				# Fallback
				return
				
			if not game_ui.is_ui_locked() and InventorySystem.pending_items.is_empty():
				# Draw logic
				if game_ui.state_machine:
					game_ui.state_machine.transition_to(&"Drawing", {"pool_index": index})
					var drawing_state = game_ui.state_machine.get_state(&"Drawing")
					if drawing_state and drawing_state.has_method("draw"):
						await drawing_state.draw()

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if game_ui:
				if game_ui.state_machine and game_ui.state_machine.get_current_state().handle_input(event):
					return
				game_ui._handle_cancel()
