extends Control

## 成品 UI 控制器：管理 Game2D 场景的逻辑接入与动画序列。
##
## 重构中: 逻辑已拆分为子控制器 (Inventory/Pool/Order/Switch Controller)

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

# --- 子控制器 ---
var inventory_controller: InventoryController
var pool_controller: PoolController
var order_controller: OrderController
var switch_controller: SwitchController

# --- 新架构: 状态机与 VFX 管理器 ---
## 状态机实例（UIStateMachine 类型）
var state_machine: Node = null
## VFX 队列管理器实例（VfxQueueManager 类型）
var vfx_manager: Node = null

# --- 旧架构: 状态与锁 ---
const DEBUG_CONSOLE_SCENE = preload("res://scenes/ui/debug_console.tscn")
var _debug_console: Control = null

var _ui_locks: Dictionary = {}
var last_clicked_pool_idx: int = -1
var pending_source_pool_idx: int = -1

# VFX 队列管理
var _is_vfx_processing: bool = false

func _ready() -> void:
	self.theme = game_theme
	add_to_group("game_2d_ui")
	
	# 1. 初始化子控制器
	_init_controllers()
	
	# 2. 初始化核心系统 (State Machine & VFX)
	_init_state_machine()
	_init_vfx_manager()
	
	# vfx_manager.controller = self # REMOVED: Phase 4 Decoupling
	
	# 3. 基础信号绑定
	GameManager.gold_changed.connect(_on_gold_changed)
	GameManager.tickets_changed.connect(_on_tickets_changed)
	
	InventorySystem.inventory_changed.connect(_on_inventory_changed)
	InventorySystem.pending_queue_changed.connect(_on_pending_queue_changed)
	InventorySystem.multi_selection_changed.connect(_on_multi_selection_changed)
	InventorySystem.selection_changed.connect(_on_selection_changed)
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
	
	# 4. 初始刷新
	_refresh_all()

func _init_controllers() -> void:
	inventory_controller = InventoryController.new()
	inventory_controller.name = "InventoryController"
	inventory_controller.game_ui = self
	add_child(inventory_controller)
	inventory_controller.setup(item_slots_grid)
	
	pool_controller = PoolController.new()
	pool_controller.name = "PoolController"
	pool_controller.game_ui = self
	add_child(pool_controller)
	pool_controller.setup(lottery_slots_grid)
	
	order_controller = OrderController.new()
	order_controller.name = "OrderController"
	order_controller.game_ui = self
	add_child(order_controller)
	order_controller.setup(quest_slots_grid, main_quest_slot)
	
	switch_controller = SwitchController.new()
	switch_controller.name = "SwitchController"
	switch_controller.game_ui = self
	add_child(switch_controller)
	switch_controller.setup(submit_switch, recycle_switch)

## 初始化状态机
func _init_state_machine() -> void:
	const UIStateInitializerScript = preload("res://scripts/ui/state/ui_state_initializer.gd")
	var initializer = UIStateInitializerScript.new()
	initializer.name = "UIStateInitializer"
	add_child(initializer)
	
	await get_tree().process_frame
	
	state_machine = get_node_or_null("UIStateMachine")
	if state_machine:
		state_machine.state_changed.connect(_on_state_changed)
		print("[Game2DUI] 状态机已初始化: %s" % state_machine.get_current_state_name())

## 初始化 VFX 管理器
func _init_vfx_manager() -> void:
	const VfxQueueManagerScript = preload("res://scripts/ui/vfx/vfx_queue_manager.gd")
	vfx_manager = VfxQueueManagerScript.new()
	vfx_manager.name = "VfxQueueManager"
	vfx_manager.vfx_layer = vfx_layer
	add_child(vfx_manager)
	
	vfx_manager.queue_started.connect(_on_vfx_queue_started)
	vfx_manager.queue_finished.connect(_on_vfx_queue_finished)

## 状态机状态变更回调
func _on_state_changed(from_state: StringName, to_state: StringName) -> void:
	print("[Game2DUI] 状态转换: %s -> %s" % [from_state, to_state])
	# State changed -> Mode might allow interaction or not, update display
	_update_ui_mode_display()
	_refresh_all() # Ensure visuals are correct for new state

## VFX 队列开始回调
func _on_vfx_queue_started() -> void:
	_is_vfx_processing = true

## VFX 队列完成回调
func _on_vfx_queue_finished() -> void:
	_is_vfx_processing = false
	
	if state_machine:
		var current_state = state_machine.get_current_state_name()
		if current_state == &"Drawing" or current_state == &"Replacing":
			# 如果动画播放完毕且没有待处理物品，则尝试返回 Idle 状态
			# 注意：具体的关盖和刷新逻辑已移至 DrawingState/ReplacingState 的 exit() 中
			if InventorySystem.pending_items.is_empty():
				state_machine.transition_to(&"Idle")

func _refresh_all() -> void:
	_on_gold_changed(GameManager.gold)
	_on_tickets_changed(GameManager.tickets)
	inventory_controller.update_all_slots(InventorySystem.inventory)
	_on_skills_changed(SkillSystem.current_skills)
	
	if PoolSystem.current_pools.is_empty():
		PoolSystem.refresh_pools()
	else:
		pool_controller.update_pools_display(PoolSystem.current_pools)
		
	order_controller.update_orders_display(OrderSystem.current_orders)
	_update_ui_mode_display()


# --- 控制台 ---
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		_toggle_debug_console()
		get_viewport().set_input_as_handled()

func _toggle_debug_console() -> void:
	if _debug_console == null:
		_debug_console = DEBUG_CONSOLE_SCENE.instantiate()
		var canvas_layer = CanvasLayer.new()
		canvas_layer.name = "DebugConsoleLayer"
		add_child(canvas_layer)
		canvas_layer.add_child(_debug_console)
	else:
		var layer = _debug_console.get_parent()
		if layer is CanvasLayer:
			layer.visible = not layer.visible
		else:
			_debug_console.visible = not _debug_console.visible

# --- 核心门控与模式 ---

func _update_ui_mode_display() -> void:
	if not state_machine: return
	
	var mode = state_machine.get_ui_mode()
	var has_pending = not InventorySystem.pending_items.is_empty()
	
	# 背包格锁定逻辑：UI 锁、有待定项、或者非正常模式均锁
	var inventory_locked = is_ui_locked() or has_pending
	inventory_controller.set_slots_locked(inventory_locked)
	
	# 奖池锁定逻辑：UI 锁、有待定项、或者非正常模式均锁
	var pool_locked = is_ui_locked() or has_pending or mode != Constants.UIMode.NORMAL
	pool_controller.set_slots_locked(pool_locked)
	
	switch_controller.update_switch_visuals(mode)

# --- 信号处理代理 ---
func _on_gold_changed(val: int) -> void:
	money_label.text = str(val)

func _on_tickets_changed(val: int) -> void:
	coupon_label.text = str(val)

func _on_inventory_changed(inventory: Array) -> void:
	inventory_controller.update_all_slots(inventory)

func _on_pending_queue_changed(items: Array[ItemInstance]) -> void:
	if items.is_empty():
		pool_controller.update_pending_display([], -1)
		pending_source_pool_idx = -1 # 保留本地状态
	else:
		pool_controller.update_pending_display(items, pending_source_pool_idx)
	_update_ui_mode_display()

func _on_skills_changed(skills: Array) -> void:
	# 暂时保留这里的逻辑，未拆分为 SkillController
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
	pool_controller.update_pools_display(pools)

func _on_orders_updated(orders: Array) -> void:
	order_controller.update_orders_display(orders)

func _on_multi_selection_changed(_indices: Array[int]) -> void:
	# 刷新订单状态
	_on_orders_updated(OrderSystem.current_orders)
	# 刷新格子选中
	inventory_controller.update_multi_selection(_indices)
	
	# 刷新回收开关数值
	var total_value = 0
	for idx in _indices:
		var item = InventorySystem.inventory[idx]
		if item: total_value += Constants.rarity_recycle_value(item.rarity)
	switch_controller.update_recycle_label(total_value)

func _on_item_slot_mouse_entered(index: int) -> void:
	if InventorySystem.pending_item != null:
		var target_item = InventorySystem.inventory[index]
		if target_item != null:
			if not InventorySystem.can_merge(InventorySystem.pending_item, target_item):
				var value = Constants.rarity_recycle_value(target_item.rarity)
				switch_controller.show_recycle_preview(value)

func _on_item_slot_mouse_exited(_index: int) -> void:
	if InventorySystem.pending_item != null:
		switch_controller.hide_recycle_preview()

func _on_recycle_switch_mouse_entered() -> void:
	if not state_machine or state_machine.get_ui_mode() != Constants.UIMode.NORMAL: return
	
	var selected_idx = InventorySystem.selected_slot_index
	var has_pending = not InventorySystem.pending_items.is_empty()
	
	if selected_idx != -1 or has_pending:
		var value = 0
		if has_pending:
			var item = InventorySystem.pending_items[0]
			if item: value = Constants.rarity_recycle_value(item.rarity)
		elif selected_idx != -1:
			var item = InventorySystem.inventory[selected_idx]
			if item: value = Constants.rarity_recycle_value(item.rarity)
		switch_controller.show_recycle_preview(value)

func _on_recycle_switch_mouse_exited() -> void:
	if not state_machine or state_machine.get_ui_mode() != Constants.UIMode.NORMAL: return
	if is_ui_locked(): return
	switch_controller.hide_recycle_preview()

func _on_selection_changed(index: int) -> void:
	inventory_controller.update_selection(index)

# --- Coordinator Action Handlers ---

func _handle_single_item_recycle(selected_idx: int) -> void:
	lock_ui("recycle")
	
	var recycle_tasks = []
	var has_pending = not InventorySystem.pending_items.is_empty()
	var target_pos = switch_controller.get_recycle_bin_pos()
	
	if has_pending:
		var item = InventorySystem.pending_items[0]
		if item:
			var snapshot = pool_controller.get_slot_snapshot(last_clicked_pool_idx)
			# 这里需要 Source Slot Node 引用给 VFX，暂时还要保留 LotterySlot 引用获取
			var pool_slot = lottery_slots_grid.get_node("Lottery Slot_root_" + str(last_clicked_pool_idx))
			
			recycle_tasks.append({
				"type": "fly_to_recycle",
				"item": item,
				"start_pos": snapshot.get("global_position", Vector2.ZERO),
				"start_scale": snapshot.get("global_scale", Vector2.ONE),
				"target_pos": target_pos,
				"source_lottery_slot": pool_slot,
				"on_complete": func(): _on_inventory_changed(InventorySystem.inventory)
			})
			
			# 关键修复：提前锁定视觉，防止数据变化导致图标提前消失
			if pool_slot.get("is_vfx_source") != null:
				pool_slot.is_vfx_source = true
			
			InventorySystem.recycle_item_instance(item)
			InventorySystem.pending_item = null
	elif selected_idx != -1:
		var item = InventorySystem.inventory[selected_idx]
		if item:
			var slot_pos = inventory_controller.get_slot_global_position(selected_idx)
			var slot_scale = inventory_controller.get_slot_global_scale(selected_idx)
			var slot_node = inventory_controller.get_slot_node(selected_idx)
			
			recycle_tasks.append({
				"type": "fly_to_recycle",
				"item": item,
				"start_pos": slot_pos,
				"start_scale": slot_scale,
				"target_pos": target_pos,
				"source_slot_node": slot_node,
				"on_complete": func(): _on_inventory_changed(InventorySystem.inventory)
			})
			
			# 关键修复：提前锁定视觉
			if slot_node.get("is_vfx_target") != null:
				slot_node.is_vfx_target = true
			
			InventorySystem.recycle_item(selected_idx)
	
	if vfx_manager:
		for task in recycle_tasks:
			vfx_manager.enqueue(task)
	
	if InventorySystem.pending_items.is_empty() and last_clicked_pool_idx != -1:
		var pool_slot = lottery_slots_grid.get_node("Lottery Slot_root_" + str(last_clicked_pool_idx))
		if pool_slot: pool_slot.close_lid()
		last_clicked_pool_idx = -1
		PoolSystem.refresh_pools()
	
	unlock_ui("recycle")

func _handle_cancel() -> void:
	# Revert to Idle via state machine
	if state_machine and state_machine.get_ui_mode() != Constants.UIMode.NORMAL:
		state_machine.transition_to(&"Idle")
		InventorySystem.multi_selected_indices.clear()
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

# --- VFX 触发 ---

func _on_item_moved(source_idx: int, target_idx: int) -> void:
	var item = InventorySystem.inventory[target_idx]
	if not item: return
	
	var source_node = inventory_controller.get_slot_node(source_idx)
	var target_node = inventory_controller.get_slot_node(target_idx)
	
	# 关键修复：立即使槽位进入 VFX 锁定状态，防止随后的 inventory_changed 刷新清空图标
	if source_node: source_node.is_vfx_target = true
	if target_node: target_node.is_vfx_target = true
	
	if vfx_manager:
		vfx_manager.enqueue({
			"type": "generic_fly",
			"item": item,
			"start_pos": inventory_controller.get_slot_global_position(source_idx),
			"end_pos": inventory_controller.get_slot_global_position(target_idx),
			"source_slot_node": source_node,
			"target_slot_node": target_node,
			"on_complete": func(): _on_inventory_changed(InventorySystem.inventory)
		})

func _on_item_added(_item: ItemInstance, index: int) -> void:
	if last_clicked_pool_idx != -1:
		var pool_slot = lottery_slots_grid.get_node("Lottery Slot_root_" + str(last_clicked_pool_idx))
		var target_slot_node = inventory_controller.get_slot_node(index)
		
		# 关键修复：立即使槽位进入 VFX 锁定状态
		if target_slot_node: target_slot_node.is_vfx_target = true
		if pool_slot: pool_slot.is_vfx_source = true
		
		# 临时隐藏目标，防止 VFX 前闪现
		if target_slot_node and target_slot_node.has_method("set_temp_hidden"):
			target_slot_node.hide_icon()
			target_slot_node.set_temp_hidden(true)
			
		var pending_count = InventorySystem.pending_items.size()
		var start_pos = pool_slot.get_main_icon_global_position()
		var start_scale = pool_slot.get_main_icon_global_scale()
		
		if pending_count == 1:
			if pool_slot.item_queue_1 and pool_slot.item_queue_1.visible:
				start_pos = pool_slot.item_queue_1.global_position
				start_scale = pool_slot.item_queue_1.global_scale
		elif pending_count == 0:
			if pool_slot.item_queue_2 and pool_slot.item_queue_2.visible:
				start_pos = pool_slot.item_queue_2.global_position
				start_scale = pool_slot.item_queue_2.global_scale
		
		var task = {
			"type": "fly_to_inventory",
			"item": _item,
			"start_pos": start_pos,
			"start_scale": start_scale,
			"target_pos": inventory_controller.get_slot_global_position(index),
			"target_scale": inventory_controller.get_slot_global_scale(index),
			"target_slot_node": target_slot_node,
			"source_lottery_slot": pool_slot,
			"on_complete": func(): _on_inventory_changed(InventorySystem.inventory)
		}
		
		if vfx_manager:
			vfx_manager.enqueue(task)

func _on_item_replaced(index: int, _new_item: ItemInstance, old_item: ItemInstance) -> void:
	if last_clicked_pool_idx != -1:
		var pool_slot = lottery_slots_grid.get_node("Lottery Slot_root_" + str(last_clicked_pool_idx))
		var target_pos = inventory_controller.get_slot_global_position(index)
		var target_scale = inventory_controller.get_slot_global_scale(index)
		var recycle_pos = switch_controller.get_recycle_bin_pos()
		var target_slot_node = inventory_controller.get_slot_node(index)
		
		# 关键修复：锁定
		if target_slot_node: target_slot_node.is_vfx_target = true
		if pool_slot: pool_slot.is_vfx_source = true
		
		if old_item and vfx_manager:
			vfx_manager.enqueue({
				"type": "fly_to_recycle",
				"item": old_item,
				"start_pos": target_pos,
				"start_scale": target_scale,
				"target_pos": recycle_pos,
				"source_slot_node": target_slot_node,
				"on_complete": func(): pass # No specific callback needed
			})
			
		var pending_count = InventorySystem.pending_items.size()
		var start_pos = pool_slot.get_main_icon_global_position()
		var start_scale = pool_slot.get_main_icon_global_scale()
		
		if pending_count == 1 and pool_slot.item_queue_1.visible:
			start_pos = pool_slot.item_queue_1.global_position
			start_scale = pool_slot.item_queue_1.global_scale
		elif pending_count == 0 and pool_slot.item_queue_2.visible:
			start_pos = pool_slot.item_queue_2.global_position
			start_scale = pool_slot.item_queue_2.global_scale
			
		var task = {
			"type": "fly_to_inventory",
			"item": _new_item,
			"start_pos": start_pos,
			"start_scale": start_scale,
			"target_pos": target_pos,
			"target_scale": target_scale,
			"target_slot_node": target_slot_node,
			"is_replace": true,
			"source_lottery_slot": pool_slot,
			"on_complete": func(): _on_inventory_changed(InventorySystem.inventory)
		}
		
		if vfx_manager:
			vfx_manager.enqueue(task)

func _on_item_merged(index: int, _new_item: ItemInstance, _target_item: ItemInstance) -> void:
	_on_item_replaced(index, _new_item, null)

func _on_item_swapped(idx1: int, idx2: int) -> void:
	# 由于信号是在 InventorySystem 数据交换后发出的：
	# inventory[idx1] 现在是原本在 idx2 的物品
	# inventory[idx2] 现在是原本在 idx1 的物品
	var item1 = InventorySystem.inventory[idx2] # 它是从 idx1 出发的物品
	var item2 = InventorySystem.inventory[idx1] # 它是从 idx2 出发的物品
	
	var node1 = inventory_controller.get_slot_node(idx1)
	var node2 = inventory_controller.get_slot_node(idx2)
	
	# 关键修复：立即使槽位进入 VFX 锁定状态
	if node1: node1.is_vfx_target = true
	if node2: node2.is_vfx_target = true
	
	if vfx_manager:
		vfx_manager.enqueue({
			"type": "swap",
			"item1": item1,
			"item2": item2,
			"pos1": inventory_controller.get_slot_global_position(idx1),
			"pos2": inventory_controller.get_slot_global_position(idx2),
			"slot1_node": node1,
			"slot2_node": node2,
			"idx1": idx1,
			"idx2": idx2,
			"on_complete": func(): _on_inventory_changed(InventorySystem.inventory)
		})

func _on_modal_requested(modal_id: StringName, payload: Variant) -> void:
	if not state_machine: return
	
	match modal_id:
		&"skill_select":
			var skills = SkillSystem.get_selectable_skills(3)
			if skills.is_empty(): return
			state_machine.transition_to(&"Modal", {
				"modal_type": &"skill_select",
				"options": skills,
				"on_select": func(idx):
					SkillSystem.add_skill(skills[idx])
			})
		&"precise_selection":
			state_machine.transition_to(&"PreciseSelection", payload)
		&"targeted_selection":
			state_machine.transition_to(&"Modal", {
				"modal_type": &"targeted_selection",
				"options": payload.get("items", []),
				"on_select": payload.get("callback", Callable())
			})

func _on_game_event(event_id: StringName, payload: Variant) -> void:
	if event_id == &"enter_selection_mode":
		if state_machine:
			var dict_payload = {}
			if payload is ContextProxy: dict_payload = payload.get_all()
			elif payload is Dictionary: dict_payload = payload
			if dict_payload.get("type") == "trade_in":
				state_machine.transition_to(&"TradeIn", dict_payload)
				
	elif event_id == &"order_refresh_requested":
		var index = payload.get_value("index", -1) if payload is ContextProxy else -1
		if index != -1 and not is_ui_locked():
			lock_ui("order_refresh")
			var order = OrderSystem.current_orders[index]
			if order.refresh_count <= 0:
				unlock_ui("order_refresh")
				return
			
			await order_controller.play_refresh_sequence(index)
			var new_order = OrderSystem.refresh_order(index)
			order_controller.update_orders_display(OrderSystem.current_orders)
			await order_controller.play_open_sequence(index)
			
			unlock_ui("order_refresh")
