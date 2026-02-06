class_name OrderController
extends UIController

## Controller for Order/Quest Slots
##
## 索引规范：
## 1-4: 普通积分订单槽位 (对应 current_orders[0..3])
## -1: 主线订单槽位 0 (对应 current_orders[MAINLINE_START_INDEX])
## -2: 主线订单槽位 1 (对应 current_orders[MAINLINE_START_INDEX + 1])

var quest_slots_grid: VBoxContainer
var main_quest_slots: Array[Control] = [] # 两个主线槽位 [slot_0, slot_1]
var _slots: Array[Control] = [] # 普通槽位 (index 1 to 4)

## 当前被hover的slot索引 (-100表示无, -1/-2表示主线)
var _hovered_slot_index: int = -100

func setup(grid: VBoxContainer, main_slots: Array) -> void:
	quest_slots_grid = grid
	main_quest_slots.clear()
	for slot in main_slots:
		main_quest_slots.append(slot)
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
				
				if not input_area.mouse_entered.is_connected(_on_slot_mouse_entered):
					input_area.mouse_entered.connect(_on_slot_mouse_entered.bind(i))
				if not input_area.mouse_exited.is_connected(_on_slot_mouse_exited):
					input_area.mouse_exited.connect(_on_slot_mouse_exited.bind(i))
	
	# 设置两个主线槽位
	for idx in range(main_quest_slots.size()):
		var main_slot = main_quest_slots[idx]
		if main_slot and main_slot.has_method("setup"):
			main_slot.setup(0)
			var input_area = main_slot.get_node("Input Area")
			if input_area:
				var slot_id = -(idx + 1) # -1 for slot 0, -2 for slot 1
				if input_area.gui_input.is_connected(_on_slot_input):
					input_area.gui_input.disconnect(_on_slot_input)
				input_area.gui_input.connect(_on_slot_input.bind(slot_id))
				
				if not input_area.mouse_entered.is_connected(_on_slot_mouse_entered):
					input_area.mouse_entered.connect(_on_slot_mouse_entered.bind(slot_id))
				if not input_area.mouse_exited.is_connected(_on_slot_mouse_exited):
					input_area.mouse_exited.connect(_on_slot_mouse_exited.bind(slot_id))


func update_orders_display(orders: Array) -> void:
	var is_submit = false
	var is_era_submit = false
	if game_ui and game_ui.state_machine:
		var mode = game_ui.state_machine.get_ui_mode()
		is_submit = (mode == Constants.UIMode.SUBMIT)
		is_era_submit = (mode == Constants.UIMode.ERA_SUBMIT)

	# 更新普通订单 (索引 0-3 in current_orders)
	for i in range(1, 5):
		var slot = _get_slot_node(i)
		var order_candidate = orders[i - 1] if (i - 1) < orders.size() else null
		var order = order_candidate if (order_candidate and not order_candidate.is_mainline) else null
		
		if slot:
			if slot.has_method("set_submit_mode"):
				slot.set_submit_mode(is_submit)
			if slot.has_method("set_era_submit_mode"):
				slot.set_era_submit_mode(is_era_submit)
				
			var req_states = []
			if order:
				req_states = _calculate_req_states(order, is_submit or is_era_submit)
				
			if slot.has_method("update_order_display"):
				slot.update_order_display(order, req_states)
				
			if slot.is_locked and not game_ui.is_ui_locked():
				slot.is_locked = false

	# 更新主线订单 (索引 MAINLINE_START_INDEX 开始)
	var mainline_orders: Array[OrderData] = []
	for order in orders:
		if order.is_mainline:
			mainline_orders.append(order)
	
	for idx in range(main_quest_slots.size()):
		var main_slot = main_quest_slots[idx]
		if not main_slot:
			continue
			
		var mainline_order = mainline_orders[idx] if idx < mainline_orders.size() else null
		
		if main_slot.has_method("set_submit_mode"):
			main_slot.set_submit_mode(is_submit)
		if main_slot.has_method("set_era_submit_mode"):
			main_slot.set_era_submit_mode(is_era_submit)
			
		var req_states = []
		if mainline_order:
			req_states = _calculate_req_states(mainline_order, is_submit or is_era_submit)
			main_slot.visible = true
			if main_slot.has_method("update_order_display"):
				main_slot.update_order_display(mainline_order, req_states)
		else:
			main_slot.visible = false
			
		if main_slot.is_locked and not game_ui.is_ui_locked():
			main_slot.is_locked = false


func _calculate_req_states(order: OrderData, is_submit_mode: bool) -> Array:
	var states = []
	var selected_indices = InventorySystem.multi_selected_indices
	
	var selected_items_map: Dictionary = {} # item_id -> Array[ItemInstance]
	if is_submit_mode:
		for idx in selected_indices:
			var item = InventorySystem.inventory[idx]
			if item and not item.is_expired:
				if not selected_items_map.has(item.item_data.id):
					selected_items_map[item.item_data.id] = []
				selected_items_map[item.item_data.id].append(item)
	
	for req in order.requirements:
		var item_id = req.get("item_id", &"")
		var min_rarity = req.get("min_rarity", 0)
		
		var owned_max_rarity = InventorySystem.get_max_rarity_for_item(item_id)
		
		var is_selected = false
		var is_quality_met = false
		
		if is_submit_mode and selected_items_map.has(item_id):
			is_selected = true
			for item in selected_items_map[item_id]:
				if item.rarity >= min_rarity:
					is_quality_met = true
					break
		
		states.append({
			"owned_max_rarity": owned_max_rarity,
			"is_selected": is_selected,
			"is_quality_met": is_quality_met
		})
	return states


func play_refresh_sequence(index: int) -> void:
	if index < 0: return
	
	var slot = _get_slot_node(index + 1)
	if not slot: return
	
	if slot.has_method("set_refresh_visual"):
		slot.set_refresh_visual(true)
	
	if slot.anim_player.has_animation("lid_close"):
		EventBus.game_event.emit(&"order_lid_closed", null)
		slot.anim_player.play("lid_close")
		await slot.anim_player.animation_finished


func play_open_sequence(index: int) -> void:
	var slot = _get_slot_node(index + 1)
	if not slot: return
	
	if slot.anim_player.has_animation("lid_open"):
		EventBus.game_event.emit(&"order_lid_opened", null)
		slot.anim_player.play("lid_open")
		await slot.anim_player.animation_finished
	
	if slot.has_method("set_refresh_visual"):
		slot.set_refresh_visual(false)


## 批量播放所有普通订单的刷新动画（用于时代切换）
func play_refresh_all_normal_sequence() -> void:
	var close_tasks: Array = []
	for i in range(1, 5):
		var slot = _get_slot_node(i)
		if slot and slot.anim_player.has_animation("lid_close"):
			slot.anim_player.play("lid_close")
			close_tasks.append(slot.anim_player)
	
	if not close_tasks.is_empty():
		EventBus.game_event.emit(&"order_lid_closed", null)
		for ap in close_tasks:
			if ap.is_playing():
				await ap.animation_finished
	
	update_orders_display(OrderSystem.current_orders)
	
	var open_tasks: Array = []
	for i in range(1, 5):
		var slot = _get_slot_node(i)
		if slot and slot.anim_player.has_animation("lid_open"):
			slot.anim_player.play("lid_open")
			open_tasks.append(slot.anim_player)
	
	if not open_tasks.is_empty():
		EventBus.game_event.emit(&"order_lid_opened", null)
		for ap in open_tasks:
			if ap.is_playing():
				await ap.animation_finished

# --- Helpers ---

## 根据索引获取槽位节点
## 正数 (1-4): 普通槽位
## -1: 主线槽位 0
## -2: 主线槽位 1
func get_slot_node(index: int) -> Control:
	if index == -1:
		return main_quest_slots[0] if main_quest_slots.size() > 0 else null
	if index == -2:
		return main_quest_slots[1] if main_quest_slots.size() > 1 else null
	if index < 1 or index >= _slots.size():
		return null
	return _slots[index]


func set_slots_locked(locked: bool) -> void:
	for i in range(1, 5):
		var slot = _get_slot_node(i)
		if slot and slot.has_method("set_locked"):
			slot.set_locked(locked)
	for main_slot in main_quest_slots:
		if main_slot and main_slot.has_method("set_locked"):
			main_slot.set_locked(locked)


func _get_slot_node(index: int) -> Control:
	return get_slot_node(index)


func _on_slot_mouse_entered(index: int) -> void:
	_hovered_slot_index = index

func _on_slot_mouse_exited(_index: int) -> void:
	_hovered_slot_index = -100

# --- Input ---

func _on_slot_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			if _hovered_slot_index != index:
				return
				
			if game_ui and game_ui.is_ui_locked():
				return
			
			if game_ui.state_machine:
				var current_mode = game_ui.state_machine.get_ui_mode()
				var is_mainline_slot = (index < 0)
				
				if current_mode == Constants.UIMode.SUBMIT:
					# 普通提交模式：只处理普通订单点击（智能选择）
					if not is_mainline_slot:
						var order_idx = index - 1
						_handle_smart_select_for_order(order_idx)
				elif current_mode == Constants.UIMode.ERA_SUBMIT:
					# 时代提交模式：只处理主线订单点击
					if is_mainline_slot:
						var mainline_idx = -(index + 1) # -1 -> 0, -2 -> 1
						_handle_smart_select_for_mainline(mainline_idx)
				elif current_mode == Constants.UIMode.NORMAL:
					_handle_click_in_normal_mode(index)
		elif event.pressed:
			pass


func _handle_click_in_normal_mode(index: int) -> void:
	var order = _get_order_by_slot_index(index)
	if not order: return
	
	var is_mainline_slot = (index < 0)
	
	if is_mainline_slot:
		# 主线订单点击 -> 进入时代提交模式
		var smart_indices = order.find_smart_selection_exclusive(InventorySystem.inventory)
		var temp_items: Array[ItemInstance] = []
		for idx in smart_indices:
			temp_items.append(InventorySystem.inventory[idx])
		var validation = order.validate_selection_exclusive(temp_items)
		
		if validation.valid:
			InventorySystem.selected_indices_for_order = []
			if InventorySystem.selected_slot_index != -1:
				InventorySystem.selected_slot_index = -1
			
			game_ui.state_machine.transition_to(&"EraSubmitting")
			
			var mainline_idx = -(index + 1) # -1 -> 0, -2 -> 1
			_handle_smart_select_for_mainline(mainline_idx)
	else:
		# 普通订单点击 -> 进入普通提交模式
		var smart_indices = order.find_smart_selection(InventorySystem.inventory)
		var temp_items = []
		for idx in smart_indices:
			temp_items.append(InventorySystem.inventory[idx])
		var validation = order.validate_selection(temp_items)
		
		if validation.valid:
			InventorySystem.selected_indices_for_order = []
			if InventorySystem.selected_slot_index != -1:
				InventorySystem.selected_slot_index = -1
			
			game_ui.state_machine.transition_to(&"Submitting")
			
			var order_idx = index - 1
			_handle_smart_select_for_order(order_idx)


func _get_order_by_slot_index(index: int) -> OrderData:
	if index < 0:
		# 主线槽位
		var mainline_idx = -(index + 1) # -1 -> 0, -2 -> 1
		var mainline_orders = OrderSystem.get_mainline_orders()
		if mainline_idx >= 0 and mainline_idx < mainline_orders.size():
			return mainline_orders[mainline_idx]
		return null
	
	var order_idx = index - 1
	if order_idx >= 0 and order_idx < OrderSystem.current_orders.size():
		var o = OrderSystem.current_orders[order_idx]
		if not o.is_mainline: return o
	return null


func _handle_smart_select_for_order(order_index: int) -> void:
	if order_index < 0 or order_index >= OrderSystem.current_orders.size():
		return
	
	var order = OrderSystem.current_orders[order_index]
	if not order or order.is_mainline: return
	
	var target_indices: Array[int] = order.find_smart_selection(InventorySystem.inventory)
	
	var changed = false
	for idx in target_indices:
		if idx not in InventorySystem.multi_selected_indices:
			InventorySystem.multi_selected_indices.append(idx)
			changed = true
	
	if changed:
		InventorySystem.multi_selection_changed.emit(InventorySystem.multi_selected_indices)


func _handle_smart_select_for_mainline(mainline_idx: int) -> void:
	var mainline_orders = OrderSystem.get_mainline_orders()
	if mainline_idx < 0 or mainline_idx >= mainline_orders.size():
		return
	
	var order = mainline_orders[mainline_idx]
	if not order: return
	
	# 使用独占模式选择
	var target_indices: Array[int] = order.find_smart_selection_exclusive(InventorySystem.inventory)
	
	var changed = false
	for idx in target_indices:
		if idx not in InventorySystem.multi_selected_indices:
			InventorySystem.multi_selected_indices.append(idx)
			changed = true
	
	if changed:
		InventorySystem.multi_selection_changed.emit(InventorySystem.multi_selected_indices)
