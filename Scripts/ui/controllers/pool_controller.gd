class_name PoolController
extends UIController

## Controller for Pool/Lottery Slots

var lottery_slots_grid: HBoxContainer
var _slots: Array[Control] = []

## 是否正在播放刷新动画（此时应跳过 update_pools_display）
var _is_animating_refresh: bool = false

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
	# 如果正在播放刷新动画，跳过此次更新（由动画函数负责）
	if _is_animating_refresh:
		return
	
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

## 让所有 slot 同时播放推挤刷新动画
## [param pools]: 新的奖池数据数组
## [param clicked_slot_idx]: 被点击的 slot 索引（该 slot 需要先关盖）
## 注意：调用方应在调用 PoolSystem.refresh_pools() 之前设置 _is_animating_refresh = true
func play_all_refresh_animations(pools: Array, clicked_slot_idx: int = -1) -> void:
	# 确保标记已设置（兜底，调用方应该已经设置了）
	_is_animating_refresh = true
	
	# 1. 先让被点击的 slot 关盖
	if clicked_slot_idx >= 0 and clicked_slot_idx < _slots.size():
		var clicked_slot = _get_slot_node(clicked_slot_idx)
		if clicked_slot and clicked_slot.has_method("close_lid"):
			await clicked_slot.close_lid()
			clicked_slot.is_drawing = false
			# 重置物品显示
			if clicked_slot.backgrounds:
				clicked_slot.backgrounds.color = Constants.COLOR_BG_SLOT_EMPTY
			clicked_slot.item_main.visible = false
			clicked_slot.item_main_shadow.visible = false
			clicked_slot.item_queue_1.visible = false
			clicked_slot.item_queue_1_shadow.visible = false
			clicked_slot.item_queue_2.visible = false
			clicked_slot.item_queue_2_shadow.visible = false
	
	# 2. 对所有 slot 并行播放推挤刷新动画
	# 使用 Dictionary 作为共享引用容器（lambda 捕获值副本问题）
	var state := {"pending": 0}
	
	for i in range(3):
		var slot = _get_slot_node(i)
		if slot and i < pools.size() and slot.has_method("refresh_slot_data"):
			state.pending += 1
			# 先更新 order hints（仅更新 Pseudo 节点，避免动画前 True 节点瞬间跳变）
			var hints = _calculate_order_hints(pools[i].item_type)
			if slot.has_method("update_order_hints"):
				slot.update_order_hints(hints.display_items, hints.satisfied_map, true)
			# 启动协程并在完成时递减计数器
			_start_slot_refresh(slot, pools[i], state)
	
	# 等待所有动画完成
	while state.pending > 0:
		await get_tree().process_frame
	
	# 动画完成，清除标志
	_is_animating_refresh = false

## 刷新所有奖池的订单 Hints（当订单改变时调用）
func refresh_all_order_hints(animate: bool = true) -> void:
	for i in range(_slots.size()):
		var slot = _get_slot_node(i)
		# 仅更新可见且未在抽奖状态的格子
		if not slot or not slot.visible or slot.is_drawing:
			continue
			
		var current_pool = PoolSystem.current_pools[i] if i < PoolSystem.current_pools.size() else null
		if not current_pool: continue
		
		var hints = _calculate_order_hints(current_pool.item_type)
		
		# 判断图标内容是否真的变了（如果只是角标状态变化，不触发推挤）
		var needs_push := false
		if animate and slot.has_method("is_hint_content_equal"):
			needs_push = not slot.is_hint_content_equal(hints.display_items)
		
		if needs_push and slot.has_method("refresh_hints_animated"):
			slot.refresh_hints_animated(hints.display_items, hints.satisfied_map)
		elif slot.has_method("update_order_hints"):
			slot.update_order_hints(hints.display_items, hints.satisfied_map)

## 辅助函数：启动单个 slot 的刷新动画并在完成后更新状态
func _start_slot_refresh(slot: Control, pool_data: Variant, state: Dictionary) -> void:
	await slot.refresh_slot_data(pool_data, false)
	state.pending -= 1

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
