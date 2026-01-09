extends Control

## 成品 UI 控制器：管理 Game2D 场景的逻辑接入与动画序列。
##
## 重构中: 状态管理正在迁移到 UIStateMachine，VFX 队列正在迁移到 VfxQueueManager。

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

# --- 新架构: 状态机与 VFX 管理器 ---
## 状态机实例（UIStateMachine 类型，使用 Node 避免循环依赖）
var state_machine: Node = null
## VFX 队列管理器实例（VfxQueueManager 类型，使用 Node 避免循环依赖）
var vfx_manager: Node = null

# --- 旧架构: 状态与锁 (迁移中) ---
const DEBUG_CONSOLE_SCENE = preload("res://scenes/ui/debug_console.tscn")
var _debug_console: Control = null

var _ui_locks: Dictionary = {}
var last_clicked_pool_idx: int = -1
var pending_source_pool_idx: int = -1

# VFX 队列管理 (迁移中)
var _vfx_queue: Array[Dictionary] = []
var _is_vfx_processing: bool = false
var _vfx_scheduled: bool = false
var _active_modal_callback: Callable
var _precise_opened_slots: Array[int] = [] # 记录精准选择打开的槽位索引

func _ready() -> void:
	self.theme = game_theme
	add_to_group("game_2d_ui") # 用于测试脚本访问
	
	# 0. 初始化新架构组件
	_init_state_machine()
	_init_vfx_manager()
	
	# 1. 基础信号绑定
	GameManager.gold_changed.connect(_on_gold_changed)
	GameManager.tickets_changed.connect(_on_tickets_changed)
	GameManager.ui_mode_changed.connect(_on_ui_mode_changed)
	
	InventorySystem.inventory_changed.connect(_on_inventory_changed)
	InventorySystem.pending_queue_changed.connect(_on_pending_queue_changed)
	InventorySystem.multi_selection_changed.connect(_on_multi_selection_changed)
	InventorySystem.selection_changed.connect(_on_selection_changed) # 单选信号
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

## 初始化状态机
func _init_state_machine() -> void:
	const UIStateInitializerScript = preload("res://scripts/ui/state/ui_state_initializer.gd")
	var initializer = UIStateInitializerScript.new()
	initializer.name = "UIStateInitializer"
	add_child(initializer)
	
	# 等待下一帧确保状态机已创建
	await get_tree().process_frame
	
	# 获取状态机引用
	state_machine = get_node_or_null("UIStateMachine")
	if state_machine:
		state_machine.state_changed.connect(_on_state_changed)
		print("[Game2DUI] 状态机已初始化: %s" % state_machine.get_current_state_name())
	else:
		push_error("[Game2DUI] 状态机初始化失败")

## 初始化 VFX 管理器
func _init_vfx_manager() -> void:
	const VfxQueueManagerScript = preload("res://scripts/ui/vfx/vfx_queue_manager.gd")
	vfx_manager = VfxQueueManagerScript.new()
	vfx_manager.name = "VfxQueueManager"
	vfx_manager.vfx_layer = vfx_layer
	add_child(vfx_manager)
	
	# 连接 VFX 队列信号
	vfx_manager.queue_started.connect(_on_vfx_queue_started)
	vfx_manager.queue_finished.connect(_on_vfx_queue_finished)
	print("[Game2DUI] VFX 管理器已初始化")

## 状态机状态变更回调
func _on_state_changed(from_state: StringName, to_state: StringName) -> void:
	print("[Game2DUI] 状态转换: %s -> %s" % [from_state, to_state])
	# TODO: 根据状态更新 UI 锁定状态

## VFX 队列开始回调
func _on_vfx_queue_started() -> void:
	_is_vfx_processing = true

## VFX 队列完成回调
func _on_vfx_queue_finished() -> void:
	_is_vfx_processing = false

func _init_slots() -> void:
	# 背包格子
	for i in range(10):
		var slot = item_slots_grid.get_node_or_null("Item Slot_root_" + str(i))
		if slot and slot.has_method("setup"):
			slot.setup(i)
			slot.get_node("Input Area").gui_input.connect(_on_item_slot_input.bind(i))
			# 绑定 Mouse Entered/Exited 用于 Pending 替换时的 Recycle 预览
			var input_area = slot.get_node("Input Area")
			input_area.mouse_entered.connect(_on_item_slot_mouse_entered.bind(i))
			input_area.mouse_exited.connect(_on_item_slot_mouse_exited.bind(i))
	
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
		main_quest_slot.get_node("Input Area").gui_input.connect(_on_order_slot_input.bind(-1)) # 绑定主线订单点击，使用-1作为特殊标记

func _init_switches() -> void:
	submit_switch.get_node("Input Area").gui_input.connect(_on_submit_switch_input)
	recycle_switch.get_node("Input Area").gui_input.connect(_on_recycle_switch_input)
	
	# 初始化开关标签文本
	if recycle_switch:
		var label = recycle_switch.find_child("Switch_on_label", true)
		if label: label.text = "0"
		
		# 绑定鼠标进入/离开事件以支持 Hover 回收预览
		var input_area = recycle_switch.get_node("Input Area")
		input_area.mouse_entered.connect(_on_recycle_switch_mouse_entered)
		input_area.mouse_exited.connect(_on_recycle_switch_mouse_exited)

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


# --- 控制台 ---
func _input(event: InputEvent) -> void:
	# F12 打开/关闭调试控制台
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		_toggle_debug_console()
		get_viewport().set_input_as_handled()


func _toggle_debug_console() -> void:
	if _debug_console == null:
		_debug_console = DEBUG_CONSOLE_SCENE.instantiate()
		
		# 为防止受场景 Camera2D 缩放/位移影响，将其放入 CanvasLayer
		var canvas_layer = CanvasLayer.new()
		canvas_layer.name = "DebugConsoleLayer"
		add_child(canvas_layer)
		canvas_layer.add_child(_debug_console)
	else:
		# 切换显示状态
		var layer = _debug_console.get_parent()
		if layer is CanvasLayer:
			layer.visible = not layer.visible
		else:
			_debug_console.visible = not _debug_console.visible

# --- 核心门控与模式 ---
func _on_ui_mode_changed(mode: Constants.UIMode) -> void:
	# 将 GameManager UI 模式同步到状态机
	_sync_ui_mode_to_state(mode)
	
	_update_ui_mode_display()
	_refresh_all()

## 将 GameManager UI 模式同步到状态机状态
func _sync_ui_mode_to_state(mode: Constants.UIMode) -> void:
	if not state_machine:
		return
	
	# 映射 UIMode -> 状态名
	var target_state: StringName = &""
	match mode:
		Constants.UIMode.NORMAL:
			target_state = &"Idle"
		Constants.UIMode.SUBMIT:
			target_state = &"Submitting"
		Constants.UIMode.RECYCLE:
			target_state = &"Recycling"
		Constants.UIMode.REPLACE:
			target_state = &"TradeIn"
		_:
			push_warning("[Game2DUI] 未知 UI 模式: %d" % mode)
			return
	
	# 避免重复转换
	if state_machine.is_in_state(target_state):
		return
	
	# 执行状态转换
	state_machine.transition_to(target_state)

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

const SWITCH_ON_Y = -213.5
const SWITCH_OFF_Y = 52.5

func _update_switch_visuals(mode: Constants.UIMode) -> void:
	var submit_target = SWITCH_ON_Y if mode == Constants.UIMode.SUBMIT else SWITCH_OFF_Y
	var recycle_target = SWITCH_ON_Y if mode == Constants.UIMode.RECYCLE else SWITCH_OFF_Y
	
	_tween_switch(submit_switch, submit_target)
	_tween_switch(recycle_switch, recycle_target)

func _tween_switch(switch_node: Node2D, target_y: float) -> void:
	if not switch_node: return
	var handle = switch_node.get_node_or_null("Switch_handle")
	if not handle: return
	
	if abs(handle.position.y - target_y) < 0.1: return
	
	var start_y = handle.position.y
	var tween = create_tween()
	
	# 使用 tween_method 手动每帧更新位置，并强制触发背景跟随逻辑
	# 这解决了使用 tween_property 时 NOTIFICATION_TRANSFORM_CHANGED 触发不及时导致背景移动滞后的问题
	tween.tween_method(func(val: float):
		handle.position.y = val
		if handle.has_method("_update_background_positions"):
			handle.call("_update_background_positions")
	, start_y, target_y, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

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
	
	# 更新主线订单
	var mainline_order = null
	for order in orders:
		if order.is_mainline:
			mainline_order = order
			break
	
	main_quest_slot.update_order_display(mainline_order)
	if not is_ui_locked() and main_quest_slot.is_locked:
		main_quest_slot.is_locked = false
	
	# 刷新所有背包格子的角标，因为需求可能变了
	for i in range(10):
		var slot = item_slots_grid.get_node("Item Slot_root_" + str(i))
		var item = InventorySystem.inventory[i] if i < InventorySystem.inventory.size() else null
		slot.update_display(item)

func _on_multi_selection_changed(_indices: Array[int]) -> void:
	# 刷新订单显示以更新需求物品的勾选状态 (Item_status)
	_on_orders_updated(OrderSystem.current_orders)
	
	# 更新格子选中状态
	for i in range(10):
		var slot = item_slots_grid.get_node("Item Slot_root_" + str(i))
		if i in InventorySystem.multi_selected_indices:
			slot.set_selected(true)
		else:
			slot.set_selected(false)
			
	_update_recycle_switch_label()

func _on_item_slot_mouse_entered(index: int) -> void:
	# Pending 状态下 hover 到物品栏：如果不能合并（会替换），预览回收价格
	if InventorySystem.pending_item != null:
		var target_item = InventorySystem.inventory[index]
		if target_item != null:
			# 如果不能合并，则意味着替换（回收旧物品）
			if not InventorySystem.can_merge(InventorySystem.pending_item, target_item):
				var value = Constants.rarity_recycle_value(target_item.rarity)
				var label = recycle_switch.find_child("Switch_on_label", true)
				if label: label.text = str(value)
				_tween_switch(recycle_switch, SWITCH_ON_Y)

func _on_item_slot_mouse_exited(_index: int) -> void:
	# 鼠标离开格子时，如果处于 Pending 状态且 Recycle Switch 已抬起，恢复
	if InventorySystem.pending_item != null:
		_tween_switch(recycle_switch, SWITCH_OFF_Y)

func _on_selection_changed(index: int) -> void:
	# 普通模式下的单选高亮动画
	# 优化：只更新状态发生变化的格子，不要对所有格子都调用 set_selected
	for i in range(10):
		var slot = item_slots_grid.get_node("Item Slot_root_" + str(i))
		var should_be_selected = (i == index)
		
		# 只在实际需要改变状态的格子上调用
		# 守卫已经在 ItemSlotUI.set_selected 内部了，但为了进一步减少开销，这里也做判断
		if slot._is_selected != should_be_selected:
			slot.set_selected(should_be_selected)

func _update_recycle_switch_label() -> void:
	var total_value = 0
	for idx in InventorySystem.multi_selected_indices:
		var item = InventorySystem.inventory[idx]
		if item:
			total_value += Constants.rarity_recycle_value(item.rarity)
	
	if recycle_switch:
		var label = recycle_switch.find_child("Switch_on_label", true)
		if label:
			label.text = str(total_value)

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
			# 在 RECYCLE 或 SUBMIT 模式下禁止抽奖
			if GameManager.current_ui_mode != Constants.UIMode.NORMAL:
				return
				
			if _active_modal_callback.is_valid():
				_active_modal_callback.call(index)
				return
			if not is_ui_locked() and InventorySystem.pending_items.is_empty():
				_handle_draw(index)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# precise_selection 模式下不允许右键取消（强制二选一）
			if _ui_locks.has("precise_selection"):
				return
			_handle_cancel()

func _on_order_slot_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if GameManager.current_ui_mode == Constants.UIMode.SUBMIT:
				_handle_smart_select_for_order(index - 1)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_cancel()

func _on_submit_switch_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if GameManager.current_ui_mode == Constants.UIMode.NORMAL:
			GameManager.current_ui_mode = Constants.UIMode.SUBMIT
			InventorySystem.multi_selected_indices.clear()
		elif GameManager.current_ui_mode == Constants.UIMode.SUBMIT:
			await _handle_order_submit()

func _on_recycle_switch_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if GameManager.current_ui_mode == Constants.UIMode.NORMAL:
			# 检查是否有选中的格子（单选）或 Pending 物品
			var selected_idx = InventorySystem.selected_slot_index
			var has_pending = not InventorySystem.pending_items.is_empty()
			
			if selected_idx != -1 or has_pending:
				_handle_single_item_recycle(selected_idx)
			else:
				# 否则进入多选模式
				GameManager.current_ui_mode = Constants.UIMode.RECYCLE
				InventorySystem.multi_selected_indices.clear()
				_update_recycle_switch_label() # 进入模式时立即刷新标签
		elif GameManager.current_ui_mode == Constants.UIMode.RECYCLE:
			_handle_recycle_confirm()

func _on_recycle_switch_mouse_entered() -> void:
	if GameManager.current_ui_mode != Constants.UIMode.NORMAL: return
	
	var selected_idx = InventorySystem.selected_slot_index
	var has_pending = not InventorySystem.pending_items.is_empty()
	
	if selected_idx != -1 or has_pending:
		# 打开盖子并显示回收金额
		var value = 0
		if has_pending:
			var item = InventorySystem.pending_items[0] # 预览第一个 pending item
			if item: value = Constants.rarity_recycle_value(item.rarity)
		elif selected_idx != -1:
			var item = InventorySystem.inventory[selected_idx]
			if item: value = Constants.rarity_recycle_value(item.rarity)
		
		# 更新 label
		var label = recycle_switch.find_child("Switch_on_label", true)
		if label: label.text = str(value)
		
		# 播放打开动画 (移动到 ON 位置)
		_tween_switch(recycle_switch, SWITCH_ON_Y)

func _on_recycle_switch_mouse_exited() -> void:
	if GameManager.current_ui_mode != Constants.UIMode.NORMAL: return
	# 如果 UI 正在执行回收动画，不要干扰
	if is_ui_locked(): return
	
	# 鼠标离开时，如果不是在 Recycle 模式，则关闭盖子
	_tween_switch(recycle_switch, SWITCH_OFF_Y)

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
			# 收集所有 pending items
			var items = InventorySystem.pending_items.duplicate()
			# 原地播放揭示动画，但不关盖，也不重置 is_drawing
			await slot.play_reveal_sequence(items)
		
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
	
	# 1. 在奖池揭示 (仅当没有 snapshot 且需要揭示时)

	
	# 锁定目标格，防止它在飞行中变色
	target_slot.is_vfx_target = true
	# 如果是替换操作，不隐藏旧图标，让它保留在原地直到新物品飞到覆盖
	if not is_replace:
		target_slot.hide_icon()
	
	# 2. 飞入背包
	var start_pos = pool_slot.get_main_icon_global_position()
	var start_scale = pool_slot.get_main_icon_global_scale()
	var end_pos = target_slot.get_icon_global_position()
	var end_scale = target_slot.get_icon_global_scale()
	
	if not source_snapshot.is_empty() or is_replace:
		start_pos = source_snapshot.get("global_position", start_pos)
		start_scale = source_snapshot.get("global_scale", start_scale)
		# 有 snapshot 或是替换操作（UI已展示），不播 reveal
	else:
		# 没有 snapshot，说明是新的抽奖（Auto-add）或连续批次的后续。
		# 尝试收集此 batch 的所有 items 用于 reveal/update
		# 包含：1. 当前 VFX 队列里的待飞物品 (已进背包)
		var batch_items = [item]
		for task in _vfx_queue:
			if task.pool_idx == pool_idx:
				var task_item = InventorySystem.inventory[task.target_idx] if task.target_idx < InventorySystem.inventory.size() else null
				if task_item:
					batch_items.append(task_item)
		
		# 包含：2. 还在 Pending 队列里的物品 (未进背包)
		# 注意：pending_items 里的顺序已经是 [next, next_next...]
		for pending_item in InventorySystem.pending_items:
			batch_items.append(pending_item)
			if batch_items.size() >= 3: break
			
		if batch_items.size() > 3:
			batch_items.resize(3)
			
		# 检查当前盖子状态
		# 如果盖子是关的，或者没有显示任何内容 -> 播放完整的 Reveal 动画 (开盖 + 揭示)
		# 如果盖子是开的 -> 认为是批次中的后续物品 -> 直接更新显示 (瞬间更新 Main/Q1/Q2) 并跳过 Reveal 动画
		# 哪怕是 reveal 动画，我们也是调用 update_queue_display。
		# 唯一的区别是：是否播放 "Lid Open" 和 "Shuffle" 动画。
		
		# 我们很难直接访问 anim_player 的当前状态（没有暴露 is_playing() 等）。
		# 但我们可以通过 is_drawing 标志？不，is_drawing 在 reveal 后会被重置吗？
		# 之前代码里 reveal 完不关盖，不重置 is_drawing?
		# 让我们在 LotterySlotUI 里加个 check。
		# 或者简单地：如果之前已经揭示过了（batch_items.size > 1 ? 不一定，也许只剩1个了）
		
		# 更好的判定：如果 vfx_queue 里还有任务，说明是连续的。
		# 但是对于第一个任务，它怎么知道？
		# 我们可以简单地总是调用 play_reveal_sequence，但在 SlotUI 内部做“如果开着就不播开门动画”的优化。
		# 同时，如果开着，我们也不想播 shuffle 动画（洗牌）。我们只想更新显示。
		
		# 让我们加一个 skip_anim 参数给 play_reveal_sequence?
		# 还是依靠 SlotUI 自己的状态判断？
		# 如果是批次中的第二个物品，此时 UI 上 Main=Item2。
		# 调用 play_reveal([Item2, Item3])。
		# 这会重置 Main 为 Item2。
		
		await pool_slot.play_reveal_sequence(batch_items)
	
	target_slot.hide_icon() # 再次确保隐藏
	# 确保飞行层可见
	if vfx_layer:
		vfx_layer.visible = true
	
	# 在飞行的同时，播放队列推进动画
	# 注意：如果是从 pending 来的（有 snapshot），说明 UI 已经通过信号更新到下一项了，
	# 此时不要 hide_main_icon 也不要 advance 队列，否则会把下一项隐藏掉。
	if source_snapshot.is_empty():
		pool_slot.hide_main_icon()
		pool_slot.play_queue_advance_anim()
	
	await spawn_fly_item(item.item_data.icon, start_pos, end_pos, start_scale, end_scale)
	
	# 3. 落地：释放锁定并显示背包格图标
	target_slot.is_vfx_target = false
	target_slot.show_icon()
	target_slot.update_display(item)
	
	# 4. 奖池关盖检查
	# 只有当这是队列中最后一个属于该池子的任务时，才关盖。
	if not _has_more_tasks_for_pool(pool_idx):
		await pool_slot.play_close_sequence()
	
	unlock_ui("draw_vfx")
	unlock_ui("draw")

func _handle_smart_select_for_order(order_index: int) -> void:
	var order: OrderData = null
	
	if order_index == -1:
		# 主线订单：在 current_orders 中查找
		for o in OrderSystem.current_orders:
			if o.is_mainline:
				order = o
				break
	else:
		# 普通订单：直接索引访问
		if order_index >= 0 and order_index < OrderSystem.current_orders.size():
			order = OrderSystem.current_orders[order_index]
	
	if not order: return
	
	# 智能选择：找出所有符合该订单要求的物品索引
	var target_indices: Array[int] = order.find_smart_selection(InventorySystem.inventory)
	
	# 合并到当前选择中（如果已全选则反选？或者只是添加？通常是添加方便操作）
	# 这里实现为：如果有新的被选中，则添加；如果点击的订单对应的物品全都被选中了，则尝试取消？
	# 简单点：直接覆盖选中，或者添加。用户说"快捷多选中"，倾向于添加。
	# 但为了方便单一订单提交，也许"设置选中"更好？
	# "点击quest_slot就会快捷多选中背包里有且订单需要的物品" -> 听起来是 Select Matching
	
	var changed = false
	for idx in target_indices:
		if idx not in InventorySystem.multi_selected_indices:
			InventorySystem.multi_selected_indices.append(idx)
			changed = true
	
	if changed:
		InventorySystem.multi_selection_changed.emit(InventorySystem.multi_selected_indices)

func _handle_order_submit() -> void:
	lock_ui("submit")
	
	# 1. 预检查哪些订单会被满足
	var selected_items: Array[ItemInstance] = []
	for idx in InventorySystem.multi_selected_indices:
		if idx >= 0 and idx < InventorySystem.inventory.size() and InventorySystem.inventory[idx] != null:
			selected_items.append(InventorySystem.inventory[idx])
	
	if selected_items.is_empty():
		unlock_ui("submit")
		return
	
	# 找出所有会被满足的订单及其对应的UI槽位
	var satisfying_slots: Array[Control] = []
	for i in range(OrderSystem.current_orders.size()):
		var order = OrderSystem.current_orders[i]
		if order.validate_selection(selected_items).valid:
			var slot: Control = null
			
			if order.is_mainline:
				slot = main_quest_slot
			else:
				# 普通订单：假设前4个非主线订单对应UI的1-4槽位
				# 这里简化处理：遍历UI槽位，根据当前显示的订单匹配
				for ui_idx in range(1, 5):
					var ui_slot = quest_slots_grid.get_node_or_null("Quest Slot_root_" + str(ui_idx))
					if ui_slot:
						# 检查这个UI槽位当前显示的是否是这个order
						var displayed_order_idx = ui_idx - 1
						if displayed_order_idx < OrderSystem.current_orders.size():
							if OrderSystem.current_orders[displayed_order_idx] == order:
								slot = ui_slot
								break
			
			if slot:
				satisfying_slots.append(slot)
	
	if satisfying_slots.is_empty():
		# 提交失败，没有任何订单被满足
		unlock_ui("submit")
		return
	
	# 2. 播放所有满足订单的 lid_close 动画
	var close_tasks: Array = []
	for slot in satisfying_slots:
		if slot.has_node("AnimationPlayer"):
			var anim_player = slot.get_node("AnimationPlayer")
			if anim_player.has_animation("lid_close"):
				anim_player.play("lid_close")
				close_tasks.append(anim_player.animation_finished)
	
	# 等待所有关闭动画完成
	for task in close_tasks:
		await task
	
	# 3. 执行提交
	var success = OrderSystem.submit_order(-1, InventorySystem.multi_selected_indices)
	
	if success:
		# 提交成功后退出模式
		GameManager.current_ui_mode = Constants.UIMode.NORMAL
		InventorySystem.multi_selected_indices.clear()
		
		# 等待订单更新和数据同步
		await get_tree().process_frame
		
		# 播放 lid_open 动画
		for slot in satisfying_slots:
			if slot.has_node("AnimationPlayer"):
				var anim_player = slot.get_node("AnimationPlayer")
				if anim_player.has_animation("lid_open"):
					anim_player.play("lid_open")
	
	unlock_ui("submit")

func _handle_recycle_confirm() -> void:
	lock_ui("recycle")
	
	# 收集要回收的物品信息用于动画
	var recycle_tasks = []
	for idx in InventorySystem.multi_selected_indices:
		var item = InventorySystem.inventory[idx]
		if item:
			var slot = item_slots_grid.get_node("Item Slot_root_" + str(idx))
			recycle_tasks.append({
				"item": item,
				"start_pos": slot.get_icon_global_position(),
				"start_scale": slot.get_icon_global_scale()
			})
	
	# 执行回收数据逻辑
	var indices = InventorySystem.multi_selected_indices.duplicate()
	indices.sort()
	indices.reverse()
	for idx in indices:
		InventorySystem.recycle_item(idx)
	InventorySystem.multi_selected_indices.clear()
	GameManager.current_ui_mode = Constants.UIMode.NORMAL
	
	# 播放飞入回收箱动画
	await _play_recycle_fly_anim(recycle_tasks)
	
	unlock_ui("recycle")

func _handle_single_item_recycle(selected_idx: int) -> void:
	lock_ui("recycle")
	
	var recycle_tasks = []
	var item: ItemInstance = null
	
	if selected_idx != -1:
		# 场景1: 背包中的选中物品
		item = InventorySystem.inventory[selected_idx]
		if item:
			var slot = item_slots_grid.get_node("Item Slot_root_" + str(selected_idx))
			recycle_tasks.append({
				"item": item,
				"start_pos": slot.get_icon_global_position(),
				"start_scale": slot.get_icon_global_scale()
			})
			InventorySystem.recycle_item(selected_idx)
			InventorySystem.selected_slot_index = -1
	else:
		# 场景2: Pending 物品
		if not InventorySystem.pending_items.is_empty():
			item = InventorySystem.pending_item
			# 找到源头奖池以确定起始位置
			var pool_idx = pending_source_pool_idx
			if pool_idx != -1:
				var slot = lottery_slots_grid.get_node("Lottery Slot_root_" + str(pool_idx))
				recycle_tasks.append({
					"item": item,
					"start_pos": slot.get_main_icon_global_position(),
					"start_scale": slot.get_main_icon_global_scale()
				})
			
			# 回收 Pending 物品 (需要 InventorySystem 支持或手动处理)
			InventorySystem.recycle_item_instance(item)
			InventorySystem.pending_item = null # 这会触发 pending_queue_changed
	
	# 播放飞入回收箱动画
	await _play_recycle_fly_anim(recycle_tasks)
	
	# 如果回收的是 Pending 物品，且队列清空，需要关闭奖池盖子并刷新
	if InventorySystem.pending_items.is_empty() and last_clicked_pool_idx != -1:
		var pool_slot = lottery_slots_grid.get_node("Lottery Slot_root_" + str(last_clicked_pool_idx))
		# 关闭奖池盖子
		if pool_slot:
			await pool_slot.play_close_sequence()
		
		last_clicked_pool_idx = -1
		PoolSystem.refresh_pools()
	
	unlock_ui("recycle")

func _play_recycle_fly_anim(tasks: Array) -> void:
	if tasks.is_empty():
		_tween_switch(recycle_switch, SWITCH_OFF_Y)
		return
		
	# 找到 Switch_item_root 作为终点
	var switch_item_root = recycle_switch.find_child("Switch_item_root", true)
	if not switch_item_root:
		_tween_switch(recycle_switch, SWITCH_OFF_Y)
		return
		
	var end_pos = switch_item_root.global_position
	
	# 收集所有飞行信号以确保全部完成
	var fly_signals: Array[Signal] = []
	for task in tasks:
		var sig = spawn_fly_item(task.item.item_data.icon, task.start_pos, end_pos, task.start_scale, Vector2(0.5, 0.5))
		fly_signals.append(sig)
	
	# 等待所有物品飞行到达
	for sig in fly_signals:
		await sig
	
	# 显示 switch item (可选，作为吞噬反馈)
	switch_item_root.visible = true
	var item_example = switch_item_root.get_node_or_null("Item_example")
	if item_example and not tasks.is_empty():
		item_example.texture = tasks[0].item.item_data.icon
	
	# 等待一小段时间后手柄下落
	await get_tree().create_timer(0.1).timeout
	
	# 手柄下落
	_tween_switch(recycle_switch, SWITCH_OFF_Y)
	
	# 等待手柄落下
	await get_tree().create_timer(0.2).timeout
	
	# 隐藏 switch item
	switch_item_root.visible = false

func _handle_cancel() -> void:
	if GameManager.current_ui_mode != Constants.UIMode.NORMAL:
		GameManager.current_ui_mode = Constants.UIMode.NORMAL
		InventorySystem.multi_selected_indices.clear()
		# GameManager.order_selection_index = -1 # Removed
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
		
		# Auto-add 时 snapshot 为空（由 VFX 逻辑推演）
		var snapshot = {}
		if not InventorySystem.pending_items.is_empty():
			snapshot = _capture_lottery_slot_snapshot(last_clicked_pool_idx)
			
		_vfx_queue.append({"pool_idx": last_clicked_pool_idx, "target_idx": index, "is_replace": false, "snapshot": snapshot})
		
		# 只有当既没有在该帧调度过，也没有正在处理时，才调度一次 deferred call
		if not _is_vfx_processing and not _vfx_scheduled:
			_vfx_scheduled = true
			call_deferred("_process_vfx_queue")

func _on_item_replaced(index: int, _new_item: ItemInstance, old_item: ItemInstance) -> void:
	# 替换发生时，也需要飞行动画
	# 区别在于起始时不要隐藏旧图标
	if last_clicked_pool_idx != -1:
		var target_slot = item_slots_grid.get_node("Item Slot_root_" + str(index))
		target_slot.is_vfx_target = true
		# 注意：这里不调用 hide_icon()，让旧物品保持显示
		
		var snapshot = {}
		if not InventorySystem.pending_items.is_empty():
			snapshot = _capture_lottery_slot_snapshot(last_clicked_pool_idx)
		
		# 被替换物品飞入回收箱 (fire-and-forget，不阻塞主流程)
		if old_item:
			var switch_item_root = recycle_switch.find_child("Switch_item_root", true)
			if switch_item_root:
				var end_pos = switch_item_root.global_position
				var start_pos = target_slot.get_icon_global_position()
				var start_scale = target_slot.get_icon_global_scale()
				spawn_fly_item(old_item.item_data.icon, start_pos, end_pos, start_scale, Vector2(0.5, 0.5))
			
		_vfx_queue.append({"pool_idx": last_clicked_pool_idx, "target_idx": index, "is_replace": true, "snapshot": snapshot})
		
		if not _is_vfx_processing and not _vfx_scheduled:
			_vfx_scheduled = true
			call_deferred("_process_vfx_queue")

func _on_item_merged(index: int, _new_item: ItemInstance, _target_item: ItemInstance) -> void:
	# 合并时，逻辑类似替换：旧物品（target_item）在原地，新物品飞入变成 new_item
	if last_clicked_pool_idx != -1:
		var target_slot = item_slots_grid.get_node("Item Slot_root_" + str(index))
		target_slot.is_vfx_target = true
		
		var snapshot = {}
		if not InventorySystem.pending_items.is_empty():
			snapshot = _capture_lottery_slot_snapshot(last_clicked_pool_idx)
			
		_vfx_queue.append({"pool_idx": last_clicked_pool_idx, "target_idx": index, "is_replace": true, "snapshot": snapshot})
		
		if not _is_vfx_processing and not _vfx_scheduled:
			_vfx_scheduled = true
			call_deferred("_process_vfx_queue")

func _process_vfx_queue() -> void:
	_vfx_scheduled = false # 清除调度标志，开始处理
	if _is_vfx_processing: return # 双重保险
	
	_is_vfx_processing = true
	while not _vfx_queue.is_empty():
		var task = _vfx_queue.pop_front()
		await _on_item_obtained_vfx(task.pool_idx, task.target_idx, task.get("is_replace", false), task.get("snapshot", {}))
	
	_is_vfx_processing = false
	
	# 如果是精准选择模式，VFX完成后关闭所有打开的槽位
	if not _precise_opened_slots.is_empty():
		var close_tasks: Array = []
		for slot_idx in _precise_opened_slots:
			var slot = lottery_slots_grid.get_node("Lottery Slot_root_" + str(slot_idx))
			if slot.anim_player.has_animation("lid_close"):
				slot.anim_player.play("lid_close")
				close_tasks.append(slot.anim_player.animation_finished)
		
		for task in close_tasks:
			await task
		
		_precise_opened_slots.clear()
		unlock_ui("precise_selection")
	
	# 只有当全部待办（包括 pending list）都处理完了，才刷新奖池并重置点击状态
	if InventorySystem.pending_items.is_empty():
		last_clicked_pool_idx = -1
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
	
	# 关键修复：交换时使用统一的基础缩放 (0.65 左右)，而不是当前可能处于选中状态的 1.2x 缩放
	# 这能防止被交换的物品因为获取了“选中态”缩放而产生的视觉抖动/放大
	var base_scale = Vector2(0.65, 0.65) # 对应 Item Slot_item_root 的设计缩放
	
	slot1.hide_icon()
	slot2.hide_icon()
	
	var fly1 = spawn_fly_item(item1.item_data.icon, pos2, pos1, base_scale, base_scale)
	var _fly2 = spawn_fly_item(item2.item_data.icon, pos1, pos2, base_scale, base_scale)
	
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
	
	# 记录打开的槽位
	_precise_opened_slots.clear()
	
	# 显示2个物品槽位，第3个保持关闭
	for i in range(3):
		var slot = lottery_slots_grid.get_node("Lottery Slot_root_" + str(i))
		if i < items.size():
			var item = items[i]
			# 隐藏原有的奖池名字和价格标签
			slot.pool_name_label.visible = false
			slot.price_label.visible = false
			slot.price_icon.visible = false
			slot.affix_label.visible = false
			slot.description_label.visible = false
			
			# 设置物品图标
			slot.item_main.texture = item.item_data.icon
			slot.item_main.visible = true
			slot.item_main_shadow.visible = true
			
			# 设置背景颜色
			if slot.backgrounds:
				slot.backgrounds.color = Constants.get_rarity_border_color(item.rarity)
			
			slot.visible = true
			
			# 播放打开盖子动画并标记为 drawing 状态
			if slot.anim_player.has_animation("lid_open"):
				slot.anim_player.play("lid_open")
			# 设置 is_drawing 防止 VFX 流程重复播放开盖动画
			slot.is_drawing = true
			
			# 记录打开的槽位索引
			_precise_opened_slots.append(i)
		else:
			# 第3个slot保持可见但关闭状态
			slot.visible = true
	
	# 设置回调 - 精准的奖池不允许取消，只能选择其中一个
	# 记录选中的槽位索引，供飞行动画使用
	_active_modal_callback = func(idx):
		if idx < items.size() and callback.is_valid():
			# 立即禁用回调，防止重复选择
			_active_modal_callback = Callable()
			# 设置 pending_source_pool_idx 为被选中的槽位，让飞行动画从正确位置开始
			pending_source_pool_idx = idx
			last_clicked_pool_idx = idx
			callback.call(items[idx])
			# 注意：不在这里调用 _exit_modal_projection，而是在 VFX 完成后

func _exit_modal_projection(skip_close_anim: bool = false) -> void:
	_active_modal_callback = Callable()
	
	var was_precise = _ui_locks.has("precise_selection")
	
	unlock_ui("skill_select")
	unlock_ui("precise_selection")
	
	# 如果是 precise_selection 且有物品要飞入背包，跳过关盖和刷新
	# 让 VFX 队列处理完后自动关盖刷新
	if skip_close_anim or was_precise:
		return
	
	# skill_select 等其他 modal 走原有逻辑
	var close_tasks: Array = []
	for i in range(3):
		var slot = lottery_slots_grid.get_node("Lottery Slot_root_" + str(i))
		if slot.visible and slot.anim_player.has_animation("lid_close"):
			slot.anim_player.play("lid_close")
			close_tasks.append(slot.anim_player.animation_finished)
	
	for task in close_tasks:
		await task
	
	PoolSystem.refresh_pools()

func _on_game_event(event_id: StringName, payload: Variant) -> void:
	if event_id == &"order_refresh_requested":
		var index = payload.get_value("index", -1) if payload is ContextProxy else -1
		if index != -1:
			var slot = quest_slots_grid.get_node_or_null("Quest Slot_root_" + str(index + 1))
			# 检查是否已有锁，防止重复进入（防抖）
			if slot and not is_ui_locked():
				lock_ui("order_refresh")
				
				# 获取订单数据以检查刷新次数
				var order = OrderSystem.current_orders[index]
				if order.refresh_count <= 0:
					unlock_ui("order_refresh")
					return
				
				# 阶段一：关闭
				if slot.anim_player.has_animation("lid_close"):
					slot.anim_player.play("lid_close")
					await slot.anim_player.animation_finished
				
				# 阶段二：更新逻辑 (触发 OrderSystem 刷新)
				var new_order = OrderSystem.refresh_order(index)
				# 强制刷新 UI (虽然 OrderSystem 可能会发出 signals，但为了对齐动画时机，可以再次显式调用)
				slot.update_order_display(new_order)
				
				# 阶段三：打开
				if slot.anim_player.has_animation("lid_open"):
					slot.anim_player.play("lid_open")
					await slot.anim_player.animation_finished
					
				unlock_ui("order_refresh")

func _has_more_tasks_for_pool(pool_idx: int) -> bool:
	for task in _vfx_queue:
		if task.pool_idx == pool_idx:
			return true
	
	if not InventorySystem.pending_items.is_empty():
		return true
		
	return false
