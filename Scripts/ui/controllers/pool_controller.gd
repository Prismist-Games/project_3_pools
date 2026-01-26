class_name PoolController
extends UIController

## Controller for Pool/Lottery Slots

## 鼠标悬停信号 (用于外部监听)
signal slot_hovered(pool_index: int, pool_item_type: int)
signal slot_unhovered(pool_index: int)
signal slot_item_hovered(item_id: StringName)

var lottery_slots_grid: HBoxContainer
var _slots: Array[Control] = []

## 是否正在播放刷新动画（此时应跳过 update_pools_display）
var _is_animating_refresh: bool = false

## 当前被hover的slot索引 (-1表示无)
var _hovered_slot_index: int = -1

## 当前被按下的slot索引 (-1表示无，用于处理鼠标移出后松开的情况)
var _pressed_slot_index: int = -1

## 本地输入锁 (防止快速点击导致的逻辑重入)
var _local_input_lock: bool = false

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
			
			# 连接 hover 信号 (用于高亮订单图标)
			if slot.has_signal("hovered") and not slot.hovered.is_connected(_on_slot_hovered):
				slot.hovered.connect(_on_slot_hovered)
			if slot.has_signal("unhovered") and not slot.unhovered.is_connected(_on_slot_unhovered):
				slot.unhovered.connect(_on_slot_unhovered)
			if slot.has_signal("item_hovered") and not slot.item_hovered.is_connected(_on_slot_item_hovered):
				slot.item_hovered.connect(_on_slot_item_hovered)
			
			# 连接角标刷新信号 (用于 Fragmented 队列前进后的自动刷新)
			if slot.has_signal("badge_refresh_requested") and not slot.badge_refresh_requested.is_connected(_on_badge_refresh_requested):
				slot.badge_refresh_requested.connect(_on_badge_refresh_requested)

func update_pools_display(pools: Array) -> void:
	# 如果正在播放刷新动画，跳过此次更新（由动画函数负责）
	if _is_animating_refresh:
		return
	
	for i in range(3):
		var slot = get_slot_node(i)
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
	
	# 关键修复：刷新动画期间锁定 UI (移动到最前，防止关盖动画期间出现输入空窗期)
	if game_ui and game_ui.has_method("lock_ui"):
		game_ui.lock_ui("pool_refresh")
	
	# 1. 先让被点击的 slot 关盖 (不再强制检查 is_drawing，因为物品飞走后该状态可能已被重置)
	if clicked_slot_idx >= 0 and clicked_slot_idx < _slots.size():
		var clicked_slot = get_slot_node(clicked_slot_idx)
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
		var slot = get_slot_node(i)
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
	
	# 解锁 UI
	if game_ui and game_ui.has_method("unlock_ui"):
		game_ui.unlock_ui("pool_refresh")

## 刷新所有奖池的订单 Hints（当订单改变时调用）
func refresh_all_order_hints(animate: bool = true) -> void:
	for i in range(_slots.size()):
		var slot = get_slot_node(i)
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
	# 1. 收集所有订单需求的物品 ID 和对应的最低品质要求
	# Optimization: Use cached requirements from OrderSystem
	var required_items: Dictionary = OrderSystem.get_max_required_items()
	
	# 2. 获取该池子类型下的所有物品，并过滤出被订单要求的
	var pool_items = GameManager.get_items_for_type(pool_type)
	var display_items: Array[ItemData] = []
	var satisfied_map: Dictionary = {} # {item_id: status} status: 0=没有, 1=有但品质不够, 2=完全满足
	
	for item_data in pool_items:
		if item_data.id in required_items:
			var min_rarity = required_items[item_data.id]
			var has_item = InventorySystem.has_item_data(item_data)
			
			if not has_item:
				# 没有该物品
				display_items.append(item_data)
				satisfied_map[item_data.id] = 0
			else:
				# 有该物品，检查品质
				var max_rarity = InventorySystem.get_max_rarity_for_item(item_data.id)
				if max_rarity >= min_rarity:
					# 品质满足，不显示（完全满足）
					# 不添加到 display_items
					pass
				else:
					# 有物品但品质不够，显示白色勾
					display_items.append(item_data)
					satisfied_map[item_data.id] = 1
			
	return {"display_items": display_items, "satisfied_map": satisfied_map}

func update_pending_display(items: Array[ItemInstance], source_pool_idx: int) -> void:
	if items.is_empty():
		# Optimization: Only clear the specific slot that had pending items
		if source_pool_idx >= 0 and source_pool_idx < _slots.size():
			var slot = get_slot_node(source_pool_idx)
			if slot and slot.has_method("update_pending_display"):
				slot.update_pending_display([])
		return
	
	if source_pool_idx != -1:
		var slot = get_slot_node(source_pool_idx)
		if slot.has_method("update_pending_display"):
			slot.update_pending_display(items)
			
			# 更新角标
			if not items.is_empty():
				var top_item = items[0]
				if top_item is ItemInstance:
					var badge = _calculate_badge_state(top_item)
					if slot.has_method("update_status_badge"):
						slot.update_status_badge(badge)
					
					var is_upgradeable = _calculate_upgradeable_state(top_item)
					if slot.has_method("set_upgradeable_badge"):
						slot.set_upgradeable_badge(is_upgradeable)
				else:
					# 如果是基础奖池数据（非 ItemInstance），则隐藏角标
					if slot.has_method("update_status_badge"):
						slot.update_status_badge(0)
					if slot.has_method("set_upgradeable_badge"):
						slot.set_upgradeable_badge(false)


func set_slots_locked(locked: bool) -> void:
	for i in range(3):
		var slot = get_slot_node(i)
		if slot:
			slot.is_locked = locked

# --- Helpers ---

func get_slot_snapshot(index: int) -> Dictionary:
	var slot = get_slot_node(index)
	if not slot: return {}
	
	return {
		"global_position": slot.get_main_icon_global_position(),
		"global_scale": slot.get_main_icon_global_scale()
	}

func get_slot_node(index: int) -> Control:
	if index < 0 or index >= _slots.size(): return null
	return _slots[index]

func _get_slot_node(index: int) -> Control: # Backward compatibility
	return get_slot_node(index)

func _calculate_badge_state(item: ItemInstance) -> int:
	if item.is_expired: return 0
	# 与 InventoryController 保持一致的逻辑
	if not OrderSystem: return 0
	
	# Optimization: Use cached requirements
	var required_items = OrderSystem.get_min_required_items()
	if not required_items.has(item.item_data.id):
		return 0
		
	var min_required = required_items[item.item_data.id]
	
	if min_required == -1:
		return 0
	
	# 只要满足任一订单（该物品的最低需求品质），显示绿勾
	if item.rarity >= min_required:
		return 2
	return 1

func _calculate_upgradeable_state(item: ItemInstance) -> bool:
	if not item or not InventorySystem: return false
	
	# 检查合成功能是否解锁
	if not UnlockManager.is_unlocked(UnlockManager.Feature.MERGE):
		return false
	
	# 跳过绝育物品和已达到最高品质的物品
	if item.sterile:
		return false
	if item.rarity >= Constants.Rarity.MYTHIC:
		return false
	if item.rarity >= UnlockManager.merge_limit:
		return false
	
	# 在背包中找同名同品质的物品
	for inv_item in InventorySystem.inventory:
		if inv_item == null:
			continue
		# 【修复】关键：排除自匹配。
		# 在批量抽奖（如“稀碎的”）中，物品可能已在数据层进入背包。
		# 我们必须确保是找到了“另一个”同名物品，而不是匹配到了由于数据提前同步而在背包里存在的“自己”。
		# 【修复】关键：排除自匹配。
		# 在批量抽奖（如“稀碎的”）中，物品可能已在数据层进入背包。
		# 我们必须确保是找到了“另一个”同名物品，而不是匹配到了由于数据提前同步而在背包里存在的“自己”。
		# 使用 get_instance_id() 进行更稳健的比较 (防止对象引用的潜在不一致)
		if inv_item == item or inv_item.get_instance_id() == item.get_instance_id():
			continue
			
		if inv_item.sterile:
			continue
		if inv_item.rarity >= Constants.Rarity.MYTHIC:
			continue
		if inv_item.rarity >= UnlockManager.merge_limit:
			continue
		# 过期物品不可合成
		if inv_item.is_expired:
			continue
		# 匹配同名同品质
		if inv_item.item_data.id == item.item_data.id and inv_item.rarity == item.rarity:
			return true
	
	return false

# --- Input Handlers ---

func _on_slot_input(event: InputEvent, index: int) -> void:
	if _local_input_lock: return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var slot = get_slot_node(index) as LotterySlotUI
			
			# [Fix] Check if interaction is allowed (Reveal gating / Drawing state restrictions)
			if not _is_slot_interaction_allowed(slot, index):
				return

			if event.pressed:
				# 1. 核心门控：UI 锁定中禁止一切点击
				# 允许在确认选择的状态下点击 (如 PreciseSelection, Modal)
				if game_ui and game_ui.is_ui_locked():
					var state_name = game_ui.state_machine.get_current_state_name()
					var is_selection_mode = state_name == &"PreciseSelection" or state_name == &"Modal"
					if not is_selection_mode:
						return
				
				# 2. 状态门控
				if game_ui and game_ui.state_machine:
					var state_name = game_ui.state_machine.get_current_state_name()
					
					# 精准选择模式下屏蔽 Slot 2
					if state_name == &"PreciseSelection" and index >= 2:
						return
					
					# 如果是技能选择或其他模态，仅允许处理逻辑内的点击 (由下面 release 逻辑处理)
					# 这里 press 阶段仅做视觉同步
				
				# 鼠标按下：让lid复位
				_pressed_slot_index = index
				if slot and slot.has_method("handle_mouse_press"):
					slot.handle_mouse_press()
			else:
				# 鼠标松开：确认行为
				# 1. 核心门控：UI 锁定中禁止确认选择
				# 允许在确认选择的状态下松开 (如 PreciseSelection, Modal)
				if game_ui and game_ui.is_ui_locked():
					var state_name = game_ui.state_machine.get_current_state_name()
					var is_selection_mode = state_name == &"PreciseSelection" or state_name == &"Modal"
					if not is_selection_mode:
						_pressed_slot_index = -1
						if slot and slot.has_method("handle_mouse_release"):
							slot.handle_mouse_release()
						return
				
				# 2. 核心判定：松开时是否仍在该格子区域内 (Unity style release-over-button)
				if _hovered_slot_index != index:
					_pressed_slot_index = -1
					if slot and slot.has_method("handle_mouse_release"):
						slot.handle_mouse_release()
					return
				
				# 3. 状态机逻辑处理
				if game_ui and game_ui.state_machine:
					var state_name = game_ui.state_machine.get_current_state_name()
					
					# If in specialized selection states
					if state_name == &"PreciseSelection" or state_name == &"Modal":
						var current_state = game_ui.state_machine.get_current_state()
						if current_state and current_state.has_method("select_option"):
							current_state.select_option(index)
							_pressed_slot_index = -1
							if slot and slot.has_method("handle_mouse_release"):
								slot.handle_mouse_release()
							return
					
					# Check UI mode via UIStateMachine
					if game_ui.state_machine.get_ui_mode() != Constants.UIMode.NORMAL:
						_pressed_slot_index = -1
						if slot and slot.has_method("handle_mouse_release"):
							slot.handle_mouse_release()
						return
					
				elif GameManager.current_ui_mode != Constants.UIMode.NORMAL:
					# Fallback
					_pressed_slot_index = -1
					if slot and slot.has_method("handle_mouse_release"):
						slot.handle_mouse_release()
					return
				
				# 检查是否有pending物品且当前slot有pending物品显示
				var has_pending = not InventorySystem.pending_items.is_empty()
				var is_pending_slot = has_pending and slot and slot.is_drawing and slot._top_item_id != &""
				
				# 如果hover在pending物品上，松开左键回收
				if is_pending_slot:
					# 记录当前点击的奖池索引
					game_ui.last_clicked_pool_idx = index
					game_ui.pending_source_pool_idx = index
					# 触发回收
					game_ui._handle_single_item_recycle(-1)
					_pressed_slot_index = -1
					if slot and slot.has_method("handle_mouse_release"):
						slot.handle_mouse_release()
					return
					
				if not game_ui.is_ui_locked() and not _is_animating_refresh and not game_ui._is_vfx_processing and InventorySystem.pending_items.is_empty():
					# 记录当前点击的奖池索引，用于后续 pending 物品的定位
					game_ui.last_clicked_pool_idx = index
					game_ui.pending_source_pool_idx = index
					
					# Draw logic
					if game_ui.state_machine:
						# 关键修复：设置本地输入锁，防止快速点击导致的多重触发或盖子状态异常
						_local_input_lock = true
						
						game_ui.state_machine.transition_to(&"Drawing", {"pool_index": index})
						var drawing_state = game_ui.state_machine.get_state(&"Drawing")
						if drawing_state and drawing_state.has_method("draw"):
							await drawing_state.draw()
							
						_local_input_lock = false
				
				# 松开后重置按下状态
				_pressed_slot_index = -1
				if slot and slot.has_method("handle_mouse_release"):
					slot.handle_mouse_release()

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# 右键不再有任何作用（不再能直接回收lottery slot道具）
			pass

func _on_slot_hovered(pool_index: int, pool_item_type: int) -> void:
	_hovered_slot_index = pool_index
	
	# 更新hover可操作状态
	_update_slot_hover_action_state(pool_index)
	
	slot_hovered.emit(pool_index, pool_item_type)


func _on_slot_unhovered(pool_index: int) -> void:
	_hovered_slot_index = -1
	
	# 清除hover视觉效果
	var slot = get_slot_node(pool_index) as LotterySlotUI
	if slot:
		slot.set_hover_action_state(LotterySlotUI.HoverType.NONE)
	
	# 如果之前hover在pending物品所在的slot上，关闭recycle switch预览
	var has_pending = not InventorySystem.pending_items.is_empty()
	if has_pending and game_ui and pool_index == game_ui.pending_source_pool_idx:
		if game_ui.switch_controller:
			# 检查鼠标是否在recycle switch上，如果不在则关闭预览
			if not game_ui.switch_controller.is_recycle_hovered():
				game_ui.switch_controller.hide_recycle_preview()
	
	slot_unhovered.emit(pool_index)


func _on_slot_item_hovered(item_id: StringName) -> void:
	slot_item_hovered.emit(item_id)


func _on_badge_refresh_requested(index: int, item: ItemInstance) -> void:
	var slot = get_slot_node(index)
	if not slot: return
	
	# 如果传入了具体物品，或者这是一个通用的刷新请求
	var target_item = item
	
	# 【修复】只有当没有指定物品且不是显式要求“清空”时，才尝试自动获取
	# 注意：如果 play_queue_advance_anim 传了 null，说明真的没东西了，不该去 pending_items 里抓东西
	if target_item and target_item is ItemInstance:
		# 更新角标
		# print("[PoolController] Badge refresh for item: ", target_item.item_data.id, " Rarity: ", target_item.rarity)
		var badge = _calculate_badge_state(target_item)
		if slot.has_method("update_status_badge"):
			slot.update_status_badge(badge)
		
		var is_upgradeable = _calculate_upgradeable_state(target_item)
		# print("[PoolController] Upgradeable state: ", is_upgradeable)
		if slot.has_method("set_upgradeable_badge"):
			slot.set_upgradeable_badge(is_upgradeable)
	else:
		# 没物品了，或者显式要求隐藏（item is null）
		if slot.has_method("update_status_badge"):
			slot.update_status_badge(0)
		if slot.has_method("set_upgradeable_badge"):
			slot.set_upgradeable_badge(false)


## 更新指定lottery slot的hover可操作状态
func _update_slot_hover_action_state(pool_index: int) -> void:
	var slot = get_slot_node(pool_index) as LotterySlotUI
	if not slot:
		return
	
	var has_pending = not InventorySystem.pending_items.is_empty()
	
	# 默认无状态
	var hover_type = LotterySlotUI.HoverType.NONE
	
	# pending时 hover 在已抽出物品（is_drawing）的 lottery slot -> 可回收
	# 这里判断slot是否有物品显示（is_drawing 且有 _top_item_id）
	# [修复] 如果物品还在揭示过程中，不允许回收操作（防止剧透和误操作）
	var is_revealing = slot.get("_is_reveal_in_progress") if slot.get("_is_reveal_in_progress") != null else false
	
	if has_pending and slot.is_drawing and slot._top_item_id != &"" and not is_revealing:
		# 在pending状态下hover lottery slot中的物品，显示可回收
		hover_type = LotterySlotUI.HoverType.RECYCLABLE
		
		# 打开recycle switch并显示预览（和hover在recycle switch上表现一致）
		if game_ui and game_ui.switch_controller:
			var item = InventorySystem.pending_items[0]
			if item:
				var value = Constants.rarity_recycle_value(item.rarity)
				game_ui.switch_controller.show_recycle_preview(value)
	
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
		var slot = get_slot_node(_pressed_slot_index) as LotterySlotUI
		if slot and slot.has_method("handle_mouse_release"):
			slot.handle_mouse_release()
		_pressed_slot_index = -1
func _is_slot_interaction_allowed(slot: LotterySlotUI, index: int) -> bool:
	if not slot:
		return false
		
	# 1. Block input if slot is revealing
	if slot.get("_is_reveal_in_progress"):
		return false
		
	# 2. Block interaction with drawn items (Lid Open) unless in specific states
	if slot.is_drawing:
		var state_name = &""
		if game_ui and game_ui.state_machine:
			state_name = game_ui.state_machine.get_current_state_name()
		
		# Allow: Precise Selection (only first 2 slots)
		if state_name == &"PreciseSelection" and index < 2:
			return true
			
		# Allow: Skill Selection (All slots allowed)
		if state_name == &"SkillSelection":
			return true
			
		# Allow: Generic Modal Selection
		if state_name == &"Modal":
			return true
			
		# Allow: Pending Items (Replacing/Recycling logic)
		# Check if this specific slot contains the pending item
		if not InventorySystem.pending_items.is_empty() and slot._top_item_id != &"":
			return true
			
		# Otherwise, block interaction with drawn items
		return false
		
	return true
