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

## 基础格子数量（The Machine 主面板）
const BASE_SLOT_COUNT: int = 10
## DLC 额外格子数量
const DLC_SLOT_COUNT: int = 5

var item_slots_grid: GridContainer
var _dlc_slots_grid: GridContainer = null
var _slots: Array[Control] = []
var _dlc_enabled: bool = false

func setup(grid: GridContainer) -> void:
	item_slots_grid = grid
	_init_slots()
	_connect_signals()


## 设置 DLC 额外槽位的 Grid 引用（由 Game2DUI 调用）
func setup_dlc_grid(dlc_grid: GridContainer) -> void:
	_dlc_slots_grid = dlc_grid
	_init_dlc_slots()


func _init_slots() -> void:
	_slots.clear()
	_slots.resize(BASE_SLOT_COUNT)
	
	for i in range(BASE_SLOT_COUNT):
		var slot = item_slots_grid.get_node_or_null("Item Slot_root_" + str(i))
		_slots[i] = slot
		_setup_slot(slot, i)


## 初始化 DLC 额外槽位
func _init_dlc_slots() -> void:
	if not _dlc_slots_grid:
		return
	
	# 扩展 _slots 数组以容纳 DLC 槽位
	_slots.resize(BASE_SLOT_COUNT + DLC_SLOT_COUNT)
	
	for i in range(DLC_SLOT_COUNT):
		var slot = _dlc_slots_grid.get_node_or_null("Item Slot_root_" + str(i))
		var global_index = BASE_SLOT_COUNT + i
		_slots[global_index] = slot
		_setup_slot(slot, global_index)


## 通用槽位设置逻辑
func _setup_slot(slot: Control, index: int) -> void:
	if not slot:
		return
	
	if slot.has_method("setup"):
		slot.setup(index)
	
	var input_area = slot.get_node_or_null("Input Area")
	if input_area:
		# Disconnect first to avoid duplicates if re-initializing
		if input_area.gui_input.is_connected(_on_slot_input):
			input_area.gui_input.disconnect(_on_slot_input)
		if input_area.mouse_entered.is_connected(_on_slot_mouse_entered):
			input_area.mouse_entered.disconnect(_on_slot_mouse_entered)
		if input_area.mouse_exited.is_connected(_on_slot_mouse_exited):
			input_area.mouse_exited.disconnect(_on_slot_mouse_exited)
			
		input_area.gui_input.connect(_on_slot_input.bind(index))
		input_area.mouse_entered.connect(_on_slot_mouse_entered.bind(index))
		input_area.mouse_exited.connect(_on_slot_mouse_exited.bind(index))

func _connect_signals() -> void:
	# Inventory signals are mainly handled by Game2DUI routing for now
	pass


## 启用/禁用 DLC 额外槽位
func set_dlc_slots_enabled(enabled: bool) -> void:
	_dlc_enabled = enabled


## 获取当前有效的槽位数量
func get_active_slot_count() -> int:
	if _dlc_enabled:
		return BASE_SLOT_COUNT + DLC_SLOT_COUNT
	return BASE_SLOT_COUNT


func update_all_slots(inventory: Array, external_candidates: Array = []) -> void:
	var slot_count = get_active_slot_count()
	
	# 先计算所有可合成的配对
	var upgradeable_indices = _calculate_upgradeable_indices(inventory)
	
	# 如果有 pending 物品，也考虑与 pending 可合成的背包物品
	if InventorySystem and InventorySystem.pending_item:
		var pending_upgradeable = _calculate_pending_upgradeable_indices(InventorySystem.pending_item, inventory)
		for idx in pending_upgradeable:
			if idx not in upgradeable_indices:
				upgradeable_indices.append(idx)
	
	# 如果有外部候选物品（如 PreciseSelection 的选项），也考虑它们
	for candidate in external_candidates:
		if candidate is ItemInstance:
			var candidate_upgradeable = _calculate_pending_upgradeable_indices(candidate, inventory)
			for idx in candidate_upgradeable:
				if idx not in upgradeable_indices:
					upgradeable_indices.append(idx)
	
	for i in range(slot_count):
		var slot = get_slot_node(i)
		var item = inventory[i] if i < inventory.size() else null
		if slot:
			slot.update_display(item)
			if item:
				var badge = _calculate_badge_state(item)
				if slot.has_method("update_status_badge"):
					slot.update_status_badge(badge)
				
				# 更新 upgradeable 角标
				if slot.has_method("set_upgradeable_badge"):
					slot.set_upgradeable_badge(i in upgradeable_indices)
			else:
				# 物品为空时，确保 upgradeable 角标隐藏
				if slot.has_method("set_upgradeable_badge"):
					slot.set_upgradeable_badge(false)

func update_slot(index: int, item: ItemInstance) -> void:
	var slot = get_slot_node(index)
	if slot:
		slot.update_display(item)
		if item:
			var badge = _calculate_badge_state(item)
			if slot.has_method("update_status_badge"):
				slot.update_status_badge(badge)
	
	# 物品变化可能影响其他槽位的 upgradeable 状态，刷新全部
	refresh_upgradeable_badges()

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


## 计算背包中所有可合成的物品索引（配对）
func _calculate_upgradeable_indices(inventory: Array) -> Array[int]:
	var result: Array[int] = []
	
	# 检查合成功能是否解锁
	if not UnlockManager.is_unlocked(UnlockManager.Feature.MERGE):
		return result
	
	# 按 (item_id, rarity) 分组，记录每个组合的索引列表
	var groups: Dictionary = {}
	
	for i in range(inventory.size()):
		var item = inventory[i]
		if item == null:
			continue
		
		# 跳过绝育物品和已达到最高品质的物品
		if item.sterile:
			continue
		if item.rarity >= Constants.Rarity.MYTHIC:
			continue
		if item.rarity >= UnlockManager.merge_limit:
			continue
		
		var key = str(item.item_data.id) + "_" + str(item.rarity)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(i)
	
	# 找出有 2 个或更多物品的组，它们可以合成
	for key in groups:
		var indices = groups[key]
		if indices.size() >= 2:
			for idx in indices:
				if idx not in result:
					result.append(idx)
	
	return result


## 计算 pending 物品与背包中可合成的物品索引
func _calculate_pending_upgradeable_indices(pending_item: ItemInstance, inventory: Array) -> Array[int]:
	var result: Array[int] = []
	
	if pending_item == null:
		return result
	
	# 检查合成功能是否解锁
	if not UnlockManager.is_unlocked(UnlockManager.Feature.MERGE):
		return result
	
	# pending 物品本身不能合成
	if pending_item.sterile:
		return result
	if pending_item.rarity >= Constants.Rarity.MYTHIC:
		return result
	if pending_item.rarity >= UnlockManager.merge_limit:
		return result
	
	# 在背包中找同名同品质的物品
	for i in range(inventory.size()):
		var item = inventory[i]
		if item == null:
			continue
		# 背包物品也需要检查是否可合成
		if item.sterile:
			continue
		if item.rarity >= Constants.Rarity.MYTHIC:
			continue
		if item.rarity >= UnlockManager.merge_limit:
			continue
		# 匹配同名同品质
		if item.item_data.id == pending_item.item_data.id and item.rarity == pending_item.rarity:
			result.append(i)
	
	return result

func update_selection(index: int) -> void:
	var slot_count = get_active_slot_count()
	for i in range(slot_count):
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
	var slot_count = get_active_slot_count()
	for i in range(slot_count):
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
	var slot_count = get_active_slot_count()
	for i in range(slot_count):
		var slot = get_slot_node(i)
		if slot:
			slot.is_locked = locked

func highlight_items_by_id(item_id: StringName) -> void:
	var slot_count = get_active_slot_count()
	for i in range(slot_count):
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


## 刷新所有槽位的 upgradeable 角标（考虑 pending 状态）
func refresh_upgradeable_badges(external_candidates: Array = []) -> void:
	var inventory = InventorySystem.inventory
	var slot_count = get_active_slot_count()
	
	# 计算背包内部的可合成配对
	var upgradeable_indices = _calculate_upgradeable_indices(inventory)
	
	# 如果有 pending 物品，计算与 pending 可合成的物品
	var pending = InventorySystem.pending_item
	if pending:
		var pending_upgradeable = _calculate_pending_upgradeable_indices(pending, inventory)
		for idx in pending_upgradeable:
			if idx not in upgradeable_indices:
				upgradeable_indices.append(idx)
	
	# 如果有外部候选物品，也考虑它们
	for candidate in external_candidates:
		if candidate is ItemInstance:
			var candidate_upgradeable = _calculate_pending_upgradeable_indices(candidate, inventory)
			for idx in candidate_upgradeable:
				if idx not in upgradeable_indices:
					upgradeable_indices.append(idx)
	
	# 更新所有槽位的 upgradeable 角标
	for i in range(slot_count):
		var slot = get_slot_node(i)
		if slot and slot.has_method("set_upgradeable_badge"):
			var item = inventory[i] if i < inventory.size() else null
			if item:
				slot.set_upgradeable_badge(i in upgradeable_indices)
			else:
				slot.set_upgradeable_badge(false)

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
