extends Control

## 成品 UI 控制器：管理 Game2D 场景的逻辑接入与动画序列。

# --- 节点引用 (根据 game2d-uiux-integration-spec.md) ---
@onready var money_label: RichTextLabel = find_child("Money_label", true)
@onready var coupon_label: RichTextLabel = find_child("Coupon_label", true)
@onready var game_theme: Theme = preload("res://data/game_theme.tres")

@onready var item_slots_grid: GridContainer = find_child("Item Slots Grid", true)
@onready var lottery_slots_grid: HBoxContainer = find_child("Lottery Slots Grid", true)
@onready var quest_slots_grid: VBoxContainer = find_child("Quest Slots Grid", true)
@onready var main_quest_slot: Control = find_child("Main Quest Slot_root", true)

@onready var submit_switch: Node2D = find_child("TheMachineSwitch_Submit", true)
@onready var recycle_switch: Node2D = find_child("TheMachineSwitch_Recycle", true)

@onready var vfx_layer: Node2D = get_node_or_null("VfxLayer")

# --- 状态与锁 ---
var _ui_locks: Dictionary = {}
var last_clicked_pool_idx: int = -1
var pending_source_pool_idx: int = -1

# VFX 队列管理
var _vfx_queue: Array[Dictionary] = []
var _is_vfx_processing: bool = false
var _active_modal_callback: Callable

func _ready() -> void:
	self.theme = game_theme
	# 1. 基础信号绑定
	GameManager.gold_changed.connect(_on_gold_changed)
	GameManager.tickets_changed.connect(_on_tickets_changed)
	GameManager.ui_mode_changed.connect(_on_ui_mode_changed)
	
	InventorySystem.inventory_changed.connect(_on_inventory_changed)
	InventorySystem.pending_queue_changed.connect(_on_pending_queue_changed)
	InventorySystem.multi_selection_changed.connect(_on_multi_selection_changed)
	InventorySystem.item_moved.connect(_on_item_moved)
	InventorySystem.item_swapped.connect(_on_item_swapped)
	InventorySystem.item_added.connect(_on_item_added)
	InventorySystem.item_replaced.connect(_on_item_replaced)
	InventorySystem.item_merged.connect(_on_item_merged)
	
	SkillSystem.skills_changed.connect(_on_skills_changed)
	
	EventBus.pools_refreshed.connect(_on_pools_refreshed)
	EventBus.orders_updated.connect(_on_orders_updated)
	EventBus.modal_requested.connect(_on_modal_requested)
	EventBus.game_event.connect(_on_game_event)
	
	# 2. 组件初始化
	_init_slots()
	_init_switches()
	
	# 3. 初始刷新
	_refresh_all()

func _init_slots() -> void:
	# 背包格子
	for i in range(10):
		var slot = item_slots_grid.get_node_or_null("Item Slot_root_" + str(i))
		if slot and slot.has_method("setup"):
			slot.setup(i)
			slot.get_node("Input Area").gui_input.connect(_on_item_slot_input.bind(i))
	
	# 奖池格子
	for i in range(3):
		var slot = lottery_slots_grid.get_node_or_null("Lottery Slot_root_" + str(i))
		if slot and slot.has_method("setup"):
			slot.setup(i)
			slot.get_node("Input Area").gui_input.connect(_on_lottery_slot_input.bind(i))

	# 订单格子
	for i in range(1, 5):
		var slot = quest_slots_grid.get_node_or_null("Quest Slot_root_" + str(i))
		if slot and slot.has_method("setup"):
			slot.setup(i)
			slot.get_node("Input Area").gui_input.connect(_on_order_slot_input.bind(i))
	
	if main_quest_slot and main_quest_slot.has_method("setup"):
		main_quest_slot.setup(0)

func _init_switches() -> void:
	submit_switch.get_node("Input Area").gui_input.connect(_on_submit_switch_input)
	recycle_switch.get_node("Input Area").gui_input.connect(_on_recycle_switch_input)

func _refresh_all() -> void:
	_on_gold_changed(GameManager.gold)
	_on_tickets_changed(GameManager.tickets)
	_on_inventory_changed(InventorySystem.inventory)
	_on_skills_changed(SkillSystem.current_skills)
	
	# 如果还没有初始化池子数据，则刷新一次
	if PoolSystem.current_pools.is_empty():
		PoolSystem.refresh_pools()
	else:
		_on_pools_refreshed(PoolSystem.current_pools)
		
	_on_orders_updated(OrderSystem.current_orders)
	_update_ui_mode_display()

# --- 核心门控与模式 ---
func _on_ui_mode_changed(_mode: Constants.UIMode) -> void:
	_update_ui_mode_display()
	_refresh_all()

func _update_ui_mode_display() -> void:
	var mode = GameManager.current_ui_mode
	var has_pending = not InventorySystem.pending_items.is_empty()
	var is_locked = is_ui_locked() or has_pending
	
	# 驱动背包 Lid
	for i in range(10):
		var slot = item_slots_grid.get_node("Item Slot_root_" + str(i))
		slot.is_locked = is_locked
	
	# 驱动奖池 Lid (防止在飞行/抽奖时点击其他池子)
	for i in range(3):
		var slot = lottery_slots_grid.get_node("Lottery Slot_root_" + str(i))
		slot.is_locked = is_locked
	
	_update_switch_visuals(mode)

const SWITCH_ON_Y = 50.0
const SWITCH_OFF_Y = -112.5

func _update_switch_visuals(mode: Constants.UIMode) -> void:
	var submit_target = SWITCH_ON_Y if mode == Constants.UIMode.SUBMIT else SWITCH_OFF_Y
	var recycle_target = SWITCH_ON_Y if mode == Constants.UIMode.RECYCLE else SWITCH_OFF_Y
	
	_tween_switch(submit_switch, submit_target)
	_tween_switch(recycle_switch, recycle_target)

func _tween_switch(switch_node: Node2D, target_y: float) -> void:
	if not switch_node: return
	var handle = switch_node.get_node_or_null("Switch_handle")
	if not handle: return
	if handle.position.y == target_y: return
	create_tween().tween_property(handle, "position:y", target_y, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# --- 信号处理 ---
func _on_gold_changed(val: int) -> void:
	money_label.text = str(val)

func _on_tickets_changed(val: int) -> void:
	coupon_label.text = str(val)

func _on_inventory_changed(inventory: Array) -> void:
	for i in range(10):
		var slot = item_slots_grid.get_node("Item Slot_root_" + str(i))
		var item = inventory[i] if i < inventory.size() else null
		slot.update_display(item)

func _on_pending_queue_changed(items: Array[ItemInstance]) -> void:
	if items.is_empty():
		for i in range(3):
			var slot = lottery_slots_grid.get_node("Lottery Slot_root_" + str(i))
			slot.update_pending_display([])
		pending_source_pool_idx = -1
		_update_ui_mode_display()
		return
	
	if pending_source_pool_idx != -1:
		var slot = lottery_slots_grid.get_node("Lottery Slot_root_" + str(pending_source_pool_idx))
		slot.update_pending_display(items)
	
	_update_ui_mode_display()

func _on_skills_changed(skills: Array) -> void:
	for i in range(3):
		var slot = find_child("TheMachineSlot " + str(i + 1), true)
		if slot:
			var label: RichTextLabel = slot.get_node("Skill Label")
			var icon: Sprite2D = label.get_node("Skill Icon")
			if i < skills.size():
				var skill = skills[i]
				label.text = skill.name
				icon.texture = skill.icon
				slot.visible = true
			else:
				slot.visible = false

func _on_pools_refreshed(pools: Array) -> void:
	for i in range(3):
		var slot = lottery_slots_grid.get_node("Lottery Slot_root_" + str(i))
		if i < pools.size():
			slot.update_pool_info(pools[i])
			slot.visible = true
		else:
			slot.visible = false

func _on_orders_updated(orders: Array) -> void:
	for i in range(1, 5):
		var slot: QuestSlotUI = quest_slots_grid.get_node("Quest Slot_root_" + str(i))
		var order = orders[i - 1] if (i - 1) < orders.size() else null
		slot.update_order_display(order)
		if not is_ui_locked() and slot.is_locked:
			slot.is_locked = false
	
	for order in orders:
		if order.is_mainline:
			main_quest_slot.update_order_display(order)
			if not is_ui_locked(): main_quest_slot.is_locked = false
			break
	
	# 刷新所有背包格子的角标，因为需求可能变了
	for i in range(10):
		var slot = item_slots_grid.get_node("Item Slot_root_" + str(i))
		var item = InventorySystem.inventory[i] if i < InventorySystem.inventory.size() else null
		slot.update_display(item)

func _on_multi_selection_changed(_indices: Array[int]) -> void:
	# 刷新订单显示以更新需求物品的勾选状态 (Item_status)
	_on_orders_updated(OrderSystem.current_orders)

# --- 输入处理 ---
func _on_item_slot_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			InventorySystem.handle_slot_click(index)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_cancel()

func _on_lottery_slot_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _active_modal_callback.is_valid():
				_active_modal_callback.call(index)
				return
			if not is_ui_locked() and InventorySystem.pending_items.is_empty():
				_handle_draw(index)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_cancel()

func _on_order_slot_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if GameManager.current_ui_mode == Constants.UIMode.SUBMIT:
				_handle_order_selection(index - 1)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_cancel()

func _on_submit_switch_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if GameManager.current_ui_mode == Constants.UIMode.NORMAL:
			GameManager.current_ui_mode = Constants.UIMode.SUBMIT
		elif GameManager.current_ui_mode == Constants.UIMode.SUBMIT:
			await _handle_order_submit()

func _on_recycle_switch_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if GameManager.current_ui_mode == Constants.UIMode.NORMAL:
			GameManager.current_ui_mode = Constants.UIMode.RECYCLE
		elif GameManager.current_ui_mode == Constants.UIMode.RECYCLE:
			_handle_recycle_confirm()

# --- 动作实现 ---
func _handle_draw(index: int) -> void:
	if is_ui_locked() or not InventorySystem.pending_items.is_empty(): return
	
	last_clicked_pool_idx = index
	pending_source_pool_idx = index
	
	lock_ui("draw")
	
	var success = PoolSystem.draw_from_pool(index)
	if not success:
		# 如果抽奖失败（如金币不足），立即解锁并播放抖动反馈
		var slot = lottery_slots_grid.get_node("Lottery Slot_root_" + str(index))
		slot.play_shake()
		last_clicked_pool_idx = -1
		unlock_ui("draw")
		return
	
	# 如果没有任何物品进入背包（比如全部进入了待定队列），则 VFX 队列不会启动
	# 我们需要在这里手动处理揭示并解锁，否则 UI 会卡死
	if not _is_vfx_processing:
		if not InventorySystem.pending_items.is_empty():
			var slot = lottery_slots_grid.get_node("Lottery Slot_root_" + str(index))
			# 原地播放揭示动画，但不关盖，也不重置 is_drawing
			await slot.play_reveal_sequence(InventorySystem.pending_items[0])
		
		# 虽然没飞走，但揭示完了，解锁 UI 让玩家处理背包
		unlock_ui("draw")
		# 注意：此处不调用 PoolSystem.refresh_pools()，也不重置 last_clicked_pool_idx
		# 必须等待物品真正飞走进入背包
# 必须等待物品真正飞走进入背包
		
func _on_item_obtained_vfx(pool_idx: int, target_idx: int, is_replace: bool = false, source_snapshot: Dictionary = {}) -> void:
	if pool_idx == -1: return
	
	var pool_slot = lottery_slots_grid.get_node("Lottery Slot_root_" + str(pool_idx))
	var target_slot = item_slots_grid.get_node("Item Slot_root_" + str(target_idx))
	var item = InventorySystem.inventory[target_idx]
	if not item: return
	
	lock_ui("draw_vfx")
	
	# 1. 在奖池揭示
	# 锁定目标格，防止它在飞行中变色
	target_slot.is_vfx_target = true
	# 如果是替换操作，不隐藏旧图标，让它保留在原地直到新物品飞到覆盖
	if not is_replace:
		target_slot.hide_icon()
	
	# 如果是从 pending 来的（即手动点击触发的），不需要再播放揭示动画，因为物品已经在那了
	# 只有在自动入包（pool_idx 取自 last_clicked, 且不是 pending? Wait. 自动入包也是刚刚抽的）
	# 核心在于：自动入包时，物品已经在 lottery slot 那个位置被 reveal 过了?
	# 不，自动入包时，逻辑很快，reveal 动画还没播。
	# 手动处理 pending 时，物品已经在 display 上显示了。
	# 我们通过传入参数 source_pos 来判断是否需要 skip reveal 吗？
	# 或者简单通过任务中的标记。
	# 如果是 REPLACE/MERGE，通常意味着是手动操作（因为 auto-add 只针对空位）。
	# 如果是 auto-add，is_replace 是 false。
	# 但是 auto-add 也会触发 _on_item_added。
	# 关键 distinction: 是 "Fly from Pending Wait" 还是 "Fly from Draw Reveal"。
	# 如果 last_clicked_pool_idx 存在，说明我们知道来源。
	# 如果 pending_items 不为空，说明之前停过。
	# 现有的逻辑：_on_item_obtained_vfx 总是在 _process_vfx_queue 里调用。
	# _process_vfx_queue 由 added/replaced/merged 触发。
	# 如果是 auto-add，item_added 触发。
	# 我们在入队时，可以尝试获取 Lottery Slot 当前的 Item Main 的位置。
	
	# 2. 飞入背包
	var start_pos = pool_slot.get_main_icon_global_position()
	var start_scale = pool_slot.get_main_icon_global_scale()
	var end_pos = target_slot.get_icon_global_position()
	var end_scale = target_slot.get_icon_global_scale()
	
	if not source_snapshot.is_empty():
		start_pos = source_snapshot.get("global_position", start_pos)
		start_scale = source_snapshot.get("global_scale", start_scale)
		# 如果我们有 snapshot，说明物品已经存在（Pending 状态），不需要播 reveal 
		# (或者 reveal 已经播过了，现在是待机状态)
		# 只有 auto-add（snapshot 为空）需要播 reveal
	else:
		await pool_slot.play_reveal_sequence(item)
	
	pool_slot.hide_main_icon()
	
	target_slot.hide_icon() # 再次确保隐藏，防止 inventory_changed 信号竞争
	
	# 确保飞行层可见
	if vfx_layer:
		vfx_layer.visible = true
	
	await spawn_fly_item(item.item_data.icon, start_pos, end_pos, start_scale, end_scale)
	
	# 3. 落地：释放锁定并显示背包格图标
	target_slot.is_vfx_target = false
	target_slot.show_icon()
	target_slot.update_display(item) # 落地后手动触发一次外观刷新
	
	# 4. 奖池关盖 (关盖后不在此处刷新池子，由 _process_vfx_queue 统一处理)
	await pool_slot.play_close_sequence()
	
	unlock_ui("draw_vfx")
	unlock_ui("draw")

func _handle_order_selection(index: int) -> void:
	GameManager.order_selection_index = index
	var order = OrderSystem.current_orders[index]
	InventorySystem.selected_indices_for_order = order.find_smart_selection(InventorySystem.inventory)
	_refresh_all()

func _handle_order_submit() -> void:
	if GameManager.order_selection_index == -1: return
	var slot = quest_slots_grid.get_node("Quest Slot_root_" + str(GameManager.order_selection_index + 1))
	lock_ui("submit")
	if slot.anim_player.has_animation("lid_close"):
		slot.anim_player.play("lid_close")
		await slot.anim_player.animation_finished
	var success = OrderSystem.submit_order(GameManager.order_selection_index, InventorySystem.multi_selected_indices)
	if success:
		GameManager.current_ui_mode = Constants.UIMode.NORMAL
	else:
		if slot.anim_player.has_animation("lid_open"):
			slot.anim_player.play("lid_open")
	unlock_ui("submit")

func _handle_recycle_confirm() -> void:
	lock_ui("recycle")
	var indices = InventorySystem.multi_selected_indices.duplicate()
	indices.sort()
	indices.reverse()
	for idx in indices:
		InventorySystem.recycle_item(idx)
	InventorySystem.multi_selected_indices.clear()
	GameManager.current_ui_mode = Constants.UIMode.NORMAL
	unlock_ui("recycle")

func _handle_cancel() -> void:
	if GameManager.current_ui_mode != Constants.UIMode.NORMAL:
		GameManager.current_ui_mode = Constants.UIMode.NORMAL
		InventorySystem.multi_selected_indices.clear()
		GameManager.order_selection_index = -1
		_refresh_all()

# --- 锁管理 ---
func lock_ui(reason: String) -> void:
	_ui_locks[reason] = true
	_update_ui_mode_display()

func unlock_ui(reason: String) -> void:
	_ui_locks.erase(reason)
	_update_ui_mode_display()

func is_ui_locked() -> bool:
	return not _ui_locks.is_empty()

func _on_item_moved(source_idx: int, target_idx: int) -> void:
	var source_slot = item_slots_grid.get_node("Item Slot_root_" + str(source_idx))
	var target_slot = item_slots_grid.get_node("Item Slot_root_" + str(target_idx))
	var item = InventorySystem.inventory[target_idx]
	if not item: return
	
	lock_ui("move_anim")
	target_slot.is_vfx_target = true # 锁定目标，防止闪现
	
	var start_pos = source_slot.get_icon_global_position()
	var end_pos = target_slot.get_icon_global_position()
	var start_scale = source_slot.get_icon_global_scale()
	var end_scale = target_slot.get_icon_global_scale()
	
	source_slot.hide_icon()
	target_slot.hide_icon()
	
	await spawn_fly_item(item.item_data.icon, start_pos, end_pos, start_scale, end_scale)
	
	target_slot.is_vfx_target = false
	target_slot.show_icon()
	_on_inventory_changed(InventorySystem.inventory)
	unlock_ui("move_anim")

func _on_item_added(_item: ItemInstance, index: int) -> void:
	if last_clicked_pool_idx != -1:
		# 立即锁定目标格，防止在飞入前因为 inventory_changed 信号闪现
		var target_slot = item_slots_grid.get_node("Item Slot_root_" + str(index))
		target_slot.is_vfx_target = true
		target_slot.hide_icon()
		
		var snapshot = _capture_lottery_slot_snapshot(last_clicked_pool_idx)
		_vfx_queue.append({"pool_idx": last_clicked_pool_idx, "target_idx": index, "is_replace": false, "snapshot": snapshot})
		if not _is_vfx_processing:
			_process_vfx_queue()

func _on_item_replaced(index: int, _new_item: ItemInstance, _old_item: ItemInstance) -> void:
	# 替换发生时，也需要飞行动画
	# 区别在于起始时不要隐藏旧图标
	if last_clicked_pool_idx != -1:
		var target_slot = item_slots_grid.get_node("Item Slot_root_" + str(index))
		target_slot.is_vfx_target = true
		# 注意：这里不调研 hide_icon()，让旧物品保持显示
		
		var snapshot = _capture_lottery_slot_snapshot(last_clicked_pool_idx)
		_vfx_queue.append({"pool_idx": last_clicked_pool_idx, "target_idx": index, "is_replace": true, "snapshot": snapshot})
		if not _is_vfx_processing:
			_process_vfx_queue()

func _on_item_merged(index: int, _new_item: ItemInstance, _target_item: ItemInstance) -> void:
	# 合并时，逻辑类似替换：旧物品（target_item）在原地，新物品飞入变成 new_item
	if last_clicked_pool_idx != -1:
		var target_slot = item_slots_grid.get_node("Item Slot_root_" + str(index))
		target_slot.is_vfx_target = true
		
		var snapshot = _capture_lottery_slot_snapshot(last_clicked_pool_idx)
		_vfx_queue.append({"pool_idx": last_clicked_pool_idx, "target_idx": index, "is_replace": true, "snapshot": snapshot})
		if not _is_vfx_processing:
			_process_vfx_queue()

func _process_vfx_queue() -> void:
	_is_vfx_processing = true
	while not _vfx_queue.is_empty():
		var task = _vfx_queue.pop_front()
		await _on_item_obtained_vfx(task.pool_idx, task.target_idx, task.get("is_replace", false), task.get("snapshot", {}))
	
	_is_vfx_processing = false
	last_clicked_pool_idx = -1
	# 全部飞完后再刷新池子
	PoolSystem.refresh_pools()

func _capture_lottery_slot_snapshot(pool_idx: int) -> Dictionary:
	var slot = lottery_slots_grid.get_node_or_null("Lottery Slot_root_" + str(pool_idx))
	if not slot: return {}
	
	# 我们假设主要物品在 item_main
	# 如果是从 queue 里飞出去的呢？目前简化处理，Pending 物品总是先显示在 item_main (通过 update_pending_display)
	# 如果是一次性产出多个，我们可能需要更精确的定位。
	# 但 InventorySystem 的 items 是一一个个加进来的。
	# 当 pending_items[0] 移走时，PENDING 队列变了，LOTTERY UI 会刷新。
	# 所以每次 item_added 时，item_main 显示的应该就是我们要飞的那个。
	
	if not slot.item_main.visible: return {}
	
	return {
		"global_position": slot.get_main_icon_global_position(),
		"global_scale": slot.get_main_icon_global_scale()
	}

func _on_item_swapped(idx1: int, idx2: int) -> void:
	var slot1 = item_slots_grid.get_node("Item Slot_root_" + str(idx1))
	var slot2 = item_slots_grid.get_node("Item Slot_root_" + str(idx2))
	var item1 = InventorySystem.inventory[idx1]
	var item2 = InventorySystem.inventory[idx2]
	
	lock_ui("swap_anim")
	slot1.is_vfx_target = true
	slot2.is_vfx_target = true
	
	var pos1 = slot1.get_icon_global_position()
	var pos2 = slot2.get_icon_global_position()
	var scale1 = slot1.get_icon_global_scale()
	var scale2 = slot2.get_icon_global_scale()
	
	slot1.hide_icon()
	slot2.hide_icon()
	
	var fly1 = spawn_fly_item(item1.item_data.icon, pos2, pos1, scale2, scale1)
	var _fly2 = spawn_fly_item(item2.item_data.icon, pos1, pos2, scale1, scale2)
	
	await fly1
	await _fly2
	
	slot1.is_vfx_target = false
	slot2.is_vfx_target = false
	slot1.show_icon()
	slot2.show_icon()
	_on_inventory_changed(InventorySystem.inventory)
	unlock_ui("swap_anim")

func spawn_fly_item(texture: Texture2D, start_pos: Vector2, end_pos: Vector2, start_scale: Vector2, end_scale: Vector2) -> Signal:
	if not vfx_layer: return get_tree().process_frame
	var proxy = Sprite2D.new()
	proxy.texture = texture
	proxy.top_level = true # 关键：让它忽略父节点缩放和偏移，直接使用全局坐标绘制
	proxy.z_index = 999 # 确保在所有 UI 之上
	vfx_layer.add_child(proxy)
	proxy.global_position = start_pos
	proxy.global_scale = start_scale
	var tween = create_tween().set_parallel(true)
	tween.tween_property(proxy, "global_position", end_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(proxy, "global_scale", end_scale, 0.4)
	tween.chain().tween_callback(proxy.queue_free)
	return tween.finished

func _on_modal_requested(modal_id: StringName, payload: Variant) -> void:
	match modal_id:
		&"skill_select": _handle_skill_selection_projection()
		&"precise_selection": _handle_precise_selection_projection(payload)

func _handle_skill_selection_projection() -> void:
	var skills = SkillSystem.get_selectable_skills(3)
	if skills.is_empty(): return
	lock_ui("skill_select")
	for i in range(3):
		var slot = lottery_slots_grid.get_node("Lottery Slot_root_" + str(i))
		if i < skills.size():
			var skill = skills[i]
			slot.pool_name_label.text = skill.name
			slot.item_main.texture = skill.icon
			slot.price_label.text = "CHOOSE"
			slot.affix_label.text = ""
			slot.description_label.text = skill.description
			slot.visible = true
		else: slot.visible = false
	_active_modal_callback = func(idx):
		SkillSystem.add_skill(skills[idx])
		_exit_modal_projection()

func _handle_precise_selection_projection(payload: Variant) -> void:
	var items = payload.get("items", [])
	var callback = payload.get("callback")
	if items.is_empty(): return
	lock_ui("precise_selection")
	for i in range(3):
		var slot = lottery_slots_grid.get_node("Lottery Slot_root_" + str(i))
		if i < items.size():
			var item = items[i]
			slot.pool_name_label.text = item.get_display_name()
			slot.item_main.texture = item.item_data.icon
			slot.price_label.text = "SELECT"
			slot.visible = true
		else:
			slot.pool_name_label.text = "CANCEL"
			slot.item_main.texture = null
			slot.price_label.text = ""
	_active_modal_callback = func(idx):
		if idx < items.size() and callback.is_valid(): callback.call(items[idx])
		_exit_modal_projection()

func _exit_modal_projection() -> void:
	_active_modal_callback = Callable()
	unlock_ui("skill_select")
	unlock_ui("precise_selection")
	PoolSystem.refresh_pools()

func _on_game_event(event_id: StringName, payload: Variant) -> void:
	if event_id == &"order_refresh_requested":
		var index = payload.get_value("index", -1) if payload is ContextProxy else -1
		if index != -1:
			var slot = quest_slots_grid.get_node_or_null("Quest Slot_root_" + str(index + 1))
			if slot:
				lock_ui("order_refresh")
				await slot.play_refresh_anim()
				unlock_ui("order_refresh")
