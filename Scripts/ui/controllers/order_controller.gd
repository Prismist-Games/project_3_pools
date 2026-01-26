class_name OrderController
extends UIController

## Controller for Order/Quest Slots

var quest_slots_grid: VBoxContainer
var main_quest_slot: Control
var _slots: Array[Control] = [] # Stores normal quest slots (index 1 to 4)

## 当前被hover的slot索引 (-100表示无, -1表示主线)
var _hovered_slot_index: int = -100

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
				
				if not input_area.mouse_entered.is_connected(_on_slot_mouse_entered):
					input_area.mouse_entered.connect(_on_slot_mouse_entered.bind(i))
				if not input_area.mouse_exited.is_connected(_on_slot_mouse_exited):
					input_area.mouse_exited.connect(_on_slot_mouse_exited.bind(i))
	
	if main_quest_slot and main_quest_slot.has_method("setup"):
		main_quest_slot.setup(0)
		var input_area = main_quest_slot.get_node("Input Area")
		if input_area:
			if input_area.gui_input.is_connected(_on_slot_input):
				input_area.gui_input.disconnect(_on_slot_input)
			input_area.gui_input.connect(_on_slot_input.bind(-1))
			
			if not input_area.mouse_entered.is_connected(_on_slot_mouse_entered):
				input_area.mouse_entered.connect(_on_slot_mouse_entered.bind(-1))
			if not input_area.mouse_exited.is_connected(_on_slot_mouse_exited):
				input_area.mouse_exited.connect(_on_slot_mouse_exited.bind(-1))

func update_orders_display(orders: Array) -> void:
	var is_submit = false
	if game_ui and game_ui.state_machine:
		is_submit = (game_ui.state_machine.get_ui_mode() == Constants.UIMode.SUBMIT)

	for i in range(1, 5):
		var slot = _get_slot_node(i)
		var order_candidate = orders[i - 1] if (i - 1) < orders.size() else null
		# 确保普通槽位不显示主线订单 (防御性编程)
		var order = order_candidate if (order_candidate and not order_candidate.is_mainline) else null
		
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
			main_quest_slot.visible = true
			if main_quest_slot.has_method("update_order_display"):
				main_quest_slot.update_order_display(mainline_order, req_states)
		else:
			main_quest_slot.visible = false
			
		if main_quest_slot.is_locked and not game_ui.is_ui_locked():
			main_quest_slot.is_locked = false

func _calculate_req_states(order: OrderData, is_submit_mode: bool) -> Array:
	var states = []
	var selected_indices = InventorySystem.multi_selected_indices
	
	# Optimization: Pre-calculate selected items map to avoid nested loops O(N*M) -> O(N+M)
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
		
		# 1. Owned Max Rarity
		var owned_max_rarity = InventorySystem.get_max_rarity_for_item(item_id)
		
		# 2. Is Selected (for submit mode)
		var is_selected = false
		var is_quality_met = false
		
		if is_submit_mode and selected_items_map.has(item_id):
			is_selected = true
			# Check if any selected item meets quality requirement
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
	if index == -1: return
	
	var slot = _get_slot_node(index + 1)
	if not slot: return
	
	# 设置按钮保持按下
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
	
	# 动画完全结束后，设置按钮弹起
	if slot.has_method("set_refresh_visual"):
		slot.set_refresh_visual(false)


## 批量播放所有普通订单的刷新动画（用于时代切换）
func play_refresh_all_normal_sequence() -> void:
	# 1. 同时关闭所有普通订单的盖子
	var close_tasks: Array = []
	for i in range(1, 5):
		var slot = _get_slot_node(i)
		if slot and slot.anim_player.has_animation("lid_close"):
			slot.anim_player.play("lid_close")
			close_tasks.append(slot.anim_player)
	
	# 等待所有关盖动画完成
	if not close_tasks.is_empty():
		EventBus.game_event.emit(&"order_lid_closed", null)
		for ap in close_tasks:
			if ap.is_playing():
				await ap.animation_finished
	
	# 2. 更新显示数据
	update_orders_display(OrderSystem.current_orders)
	
	# 3. 同时打开所有普通订单的盖子
	var open_tasks: Array = []
	for i in range(1, 5):
		var slot = _get_slot_node(i)
		if slot and slot.anim_player.has_animation("lid_open"):
			slot.anim_player.play("lid_open")
			open_tasks.append(slot.anim_player)
	
	# 等待所有开盖动画完成
	if not open_tasks.is_empty():
		EventBus.game_event.emit(&"order_lid_opened", null)
		for ap in open_tasks:
			if ap.is_playing():
				await ap.animation_finished

# --- Helpers ---

func get_slot_node(index: int) -> Control:
	if index == -1: return main_quest_slot
	if index < 1 or index >= _slots.size(): return null
	return _slots[index]

func set_slots_locked(locked: bool) -> void:
	for i in range(1, 5):
		var slot = _get_slot_node(i)
		if slot and slot.has_method("set_locked"):
			slot.set_locked(locked)
	if main_quest_slot and main_quest_slot.has_method("set_locked"):
		main_quest_slot.set_locked(locked)

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
			# 核心判定：松开时是否仍在该区域内
			if _hovered_slot_index != index:
				return
				
			# 检查 UI 锁定
			if game_ui and game_ui.is_ui_locked():
				return
			
			if game_ui.state_machine:
				var current_mode = game_ui.state_machine.get_ui_mode()
				var order_idx = index - 1 if index != -1 else -1
				
				if current_mode == Constants.UIMode.SUBMIT:
					_handle_smart_select_for_order(order_idx)
				elif current_mode == Constants.UIMode.NORMAL:
					_handle_click_in_normal_mode(index)
		elif event.pressed:
			# 可以在这里处理按下时的视觉反馈
			pass

func _handle_click_in_normal_mode(index: int) -> void:
	# 1. 获取对应的订单数据
	var order = _get_order_by_slot_index(index)
	if not order: return
	
	# 2. 检查是否可满足 (Smart Select 能找到足够的物品)
	var smart_indices = order.find_smart_selection(InventorySystem.inventory)
	
	# 临时构建选中物品列表进行校验
	var temp_items = []
	for idx in smart_indices:
		temp_items.append(InventorySystem.inventory[idx])
	
	var validation = order.validate_selection(temp_items)
	
	if validation.valid:
		# 3. 切换到提交模式
		if game_ui.state_machine and game_ui.state_machine.has_method("transition_to"):
			# 先清除任何现有的选择（确保干净的状态）
			InventorySystem.multi_selected_indices.clear()
			InventorySystem.multi_selection_changed.emit([])
			if InventorySystem.selected_slot_index != -1:
				InventorySystem.selected_slot_index = -1
			
			game_ui.state_machine.transition_to(&"Submitting")
			
			# 4. 执行智能选择
			var order_idx = index - 1 if index != -1 else -1
			_handle_smart_select_for_order(order_idx)

func _get_order_by_slot_index(index: int) -> OrderData:
	if index == -1:
		for o in OrderSystem.current_orders:
			if o.is_mainline: return o
		return null
	
	var order_idx = index - 1
	if order_idx >= 0 and order_idx < OrderSystem.current_orders.size():
		var o = OrderSystem.current_orders[order_idx]
		if not o.is_mainline: return o
	return null

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
