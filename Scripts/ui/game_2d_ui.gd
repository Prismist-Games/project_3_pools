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

# VFX 队列管理 (已迁移)
var _is_vfx_processing: bool = false

func _ready() -> void:
	self.theme = game_theme
	add_to_group("game_2d_ui") # 用于测试脚本访问
	
	# 初始化状态机 (确保在 VFX 管理器之前，因为 VFX 管理器可能发出信号)
	_init_state_machine()
	_init_vfx_manager()
	
	if vfx_manager:
		vfx_manager.controller = self
	
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
	
	# 如果当前处于 Drawing 状态且动画已结束，转换回 Idle
	if state_machine and state_machine.is_in_state(&"Drawing"):
		var ds = state_machine.get_state(&"Drawing")
		if ds and ds.pool_index != -1:
			var slot = lottery_slots_grid.get_node_or_null("Lottery Slot_root_" + str(ds.pool_index))
			if slot and slot.has_method("play_close_sequence"):
				# 先等待盖子关上
				await slot.play_close_sequence()
			
			# 盖子关上后再刷新逻辑数据
			PoolSystem.refresh_pools()
		
		state_machine.transition_to(&"Idle")

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
			# 优先检查状态机是否接管了点击（如 TradeIn 状态）
			if state_machine:
				var current_state = state_machine.get_current_state()
				if current_state and current_state.has_method("select_slot"):
					current_state.select_slot(index)
					return
					
			InventorySystem.handle_slot_click(index)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if state_machine and state_machine.get_current_state().handle_input(event):
				return
			_handle_cancel()

func _on_lottery_slot_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# 检查当前状态是否接管了点击逻辑（如 PreciseSelection 或 Modal/SkillSelect）
			if state_machine:
				var state_name = state_machine.get_current_state_name()
				if state_name == &"PreciseSelection" or state_name == &"Modal":
					var current_state = state_machine.get_current_state()
					if current_state and current_state.has_method("select_option"):
						current_state.select_option(index)
						return

			# 在 RECYCLE 或 SUBMIT 模式下禁止抽奖
			if GameManager.current_ui_mode != Constants.UIMode.NORMAL:
				return
				
			if not is_ui_locked() and InventorySystem.pending_items.is_empty():
				# 转换到 Drawing 状态并执行抽奖
				if state_machine:
					state_machine.transition_to(&"Drawing", {"pool_index": index})
					var drawing_state = state_machine.get_state(&"Drawing")
					if drawing_state:
						await drawing_state.draw()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# 状态机会处理 handle_input，这里只需处理通用的取消逻辑
			# Drawing 或 PreciseSelection 状态可能会在自己的 handle_input 中消费掉
			if state_machine and state_machine.get_current_state().handle_input(event):
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
			# 调用状态类的提交方法
			var submitting_state = state_machine.get_state(&"Submitting") if state_machine else null
			if submitting_state:
				await submitting_state.submit_order()

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
			# 调用状态类的回收方法
			var recycling_state = state_machine.get_state(&"Recycling") if state_machine else null
			if recycling_state:
				await recycling_state.recycle_confirm()

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

# --- 信号与回调 ---

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


# 辅助函数


func _handle_single_item_recycle(selected_idx: int) -> void:
	lock_ui("recycle")
	
	var recycle_tasks = []
	var has_pending = not InventorySystem.pending_items.is_empty()
	
	if has_pending:
		# 回收 Pending 物品
		var item = InventorySystem.pending_items[0]
		if item:
			var slot = lottery_slots_grid.get_node("Lottery Slot_root_" + str(last_clicked_pool_idx))
			recycle_tasks.append({
				"type": "fly_to_recycle",
				"item": item,
				"start_pos": slot.get_main_icon_global_position(),
				"start_scale": slot.get_main_icon_global_scale(),
				"target_pos": recycle_switch.find_child("Switch_item_root", true).global_position,
				"source_lottery_slot": slot
			})
			InventorySystem.recycle_item_instance(item)
			InventorySystem.pending_item = null
	elif selected_idx != -1:
		var item = InventorySystem.inventory[selected_idx]
		if item:
			var slot = item_slots_grid.get_node("Item Slot_root_" + str(selected_idx))
			recycle_tasks.append({
				"type": "fly_to_recycle",
				"item": item,
				"start_pos": slot.get_icon_global_position(),
				"start_scale": slot.get_icon_global_scale(),
				"target_pos": recycle_switch.find_child("Switch_item_root", true).global_position
			})
			InventorySystem.recycle_item(selected_idx)
	
	# 提交 VFX 任务
	if vfx_manager:
		for task in recycle_tasks:
			vfx_manager.enqueue(task)
	
	# 如果回收的是 Pending 物品，且队列清空，需要关闭奖池盖子并刷新
	if InventorySystem.pending_items.is_empty() and last_clicked_pool_idx != -1:
		var pool_slot = lottery_slots_grid.get_node("Lottery Slot_root_" + str(last_clicked_pool_idx))
		if pool_slot:
			pool_slot.close_lid()
		last_clicked_pool_idx = -1
		PoolSystem.refresh_pools()
	
	unlock_ui("recycle")


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
	
	if vfx_manager:
		vfx_manager.enqueue({
			"type": "generic_fly",
			"item": item,
			"start_pos": source_slot.get_icon_global_position(),
			"end_pos": target_slot.get_icon_global_position(),
			"source_slot": source_idx,
			"target_slot": target_idx
		})


func _on_item_added(_item: ItemInstance, index: int) -> void:
	# 如果处于 draw 状态且有 source pool，执行飞入动画前置逻辑
	if last_clicked_pool_idx != -1:
		var pool_slot = lottery_slots_grid.get_node("Lottery Slot_root_" + str(last_clicked_pool_idx))
		var target_slot = item_slots_grid.get_node("Item Slot_root_" + str(index))
		
		# 关键修复: 在生成 VFX 任务时立即隐藏目标槽位图标，并锁定显示更新，防止物品瞬移出现
		if target_slot and target_slot.has_method("set_temp_hidden"):
			target_slot.hide_icon()
			target_slot.set_temp_hidden(true)
		
		# 多物品支持：根据 pending_items 的剩余数量确定飞行起点
		# pending_items 在物品添加到背包后会减少，所以当前剩余数量就是"还没飞的物品数"
		# 例如：3个物品抽奖，第1个添加时 pending=2，应从 main 飞；第2个添加时 pending=1，应从 queue1 飞
		var pending_count = InventorySystem.pending_items.size()
		var start_pos: Vector2
		var start_scale: Vector2
		
		if pending_count >= 2:
			# 还有2个或更多在队列，说明当前这个是第一个飞的，从 main 位置飞
			start_pos = pool_slot.get_main_icon_global_position()
			start_scale = pool_slot.get_main_icon_global_scale()
		elif pending_count == 1:
			# 还有1个在队列，说明当前这个是第二个飞的，从 queue_1 位置飞
			if pool_slot.item_queue_1 and pool_slot.item_queue_1.visible:
				start_pos = pool_slot.item_queue_1.global_position
				start_scale = pool_slot.item_queue_1.global_scale
			else:
				start_pos = pool_slot.get_main_icon_global_position()
				start_scale = pool_slot.get_main_icon_global_scale()
		else:
			# pending 为空，说明是最后一个或唯一一个，从 queue_2 或 main 飞
			if pool_slot.item_queue_2 and pool_slot.item_queue_2.visible:
				start_pos = pool_slot.item_queue_2.global_position
				start_scale = pool_slot.item_queue_2.global_scale
			else:
				start_pos = pool_slot.get_main_icon_global_position()
				start_scale = pool_slot.get_main_icon_global_scale()
			
		var task = {
			"type": "fly_to_inventory",
			"item": _item,
			"start_pos": start_pos,
			"start_scale": start_scale,
			"target_pos": target_slot.get_icon_global_position(),
			"target_scale": target_slot.get_icon_global_scale(),
			"target_slot": index,
			"source_lottery_slot": pool_slot
		}
		
		if vfx_manager:
			vfx_manager.enqueue(task)

func _on_item_replaced(index: int, _new_item: ItemInstance, old_item: ItemInstance) -> void:
	if last_clicked_pool_idx != -1:
		var pool_slot = lottery_slots_grid.get_node("Lottery Slot_root_" + str(last_clicked_pool_idx))
		var target_slot = item_slots_grid.get_node("Item Slot_root_" + str(index))
		
		# 旧物品飞入回收箱
		if old_item and vfx_manager:
			vfx_manager.enqueue({
				"type": "fly_to_recycle",
				"item": old_item,
				"start_pos": target_slot.get_icon_global_position(),
				"start_scale": target_slot.get_icon_global_scale(),
				"target_pos": recycle_switch.find_child("Switch_item_root", true).global_position
			})
		
		# 多物品支持：根据队列位置确定起点
		var pending_count = InventorySystem.pending_items.size()
		var start_pos: Vector2
		var start_scale: Vector2
		
		if pending_count >= 2:
			start_pos = pool_slot.get_main_icon_global_position()
			start_scale = pool_slot.get_main_icon_global_scale()
		elif pending_count == 1:
			if pool_slot.item_queue_1 and pool_slot.item_queue_1.visible:
				start_pos = pool_slot.item_queue_1.global_position
				start_scale = pool_slot.item_queue_1.global_scale
			else:
				start_pos = pool_slot.get_main_icon_global_position()
				start_scale = pool_slot.get_main_icon_global_scale()
		else:
			if pool_slot.item_queue_2 and pool_slot.item_queue_2.visible:
				start_pos = pool_slot.item_queue_2.global_position
				start_scale = pool_slot.item_queue_2.global_scale
			else:
				start_pos = pool_slot.get_main_icon_global_position()
				start_scale = pool_slot.get_main_icon_global_scale()
			
		var task = {
			"type": "fly_to_inventory",
			"item": _new_item,
			"start_pos": start_pos,
			"start_scale": start_scale,
			"target_pos": target_slot.get_icon_global_position(),
			"target_scale": target_slot.get_icon_global_scale(),
			"target_slot": index,
			"is_replace": true,
			"source_lottery_slot": pool_slot
		}
		
		if vfx_manager:
			vfx_manager.enqueue(task)

func _on_item_merged(index: int, _new_item: ItemInstance, _target_item: ItemInstance) -> void:
	if last_clicked_pool_idx != -1:
		var pool_slot = lottery_slots_grid.get_node("Lottery Slot_root_" + str(last_clicked_pool_idx))
		var target_slot = item_slots_grid.get_node("Item Slot_root_" + str(index))
		
		# 多物品支持：根据队列位置确定起点
		var pending_count = InventorySystem.pending_items.size()
		var start_pos: Vector2
		var start_scale: Vector2
		
		if pending_count >= 2:
			start_pos = pool_slot.get_main_icon_global_position()
			start_scale = pool_slot.get_main_icon_global_scale()
		elif pending_count == 1:
			if pool_slot.item_queue_1 and pool_slot.item_queue_1.visible:
				start_pos = pool_slot.item_queue_1.global_position
				start_scale = pool_slot.item_queue_1.global_scale
			else:
				start_pos = pool_slot.get_main_icon_global_position()
				start_scale = pool_slot.get_main_icon_global_scale()
		else:
			if pool_slot.item_queue_2 and pool_slot.item_queue_2.visible:
				start_pos = pool_slot.item_queue_2.global_position
				start_scale = pool_slot.item_queue_2.global_scale
			else:
				start_pos = pool_slot.get_main_icon_global_position()
				start_scale = pool_slot.get_main_icon_global_scale()
			
		var task = {
			"type": "fly_to_inventory",
			"item": _new_item,
			"start_pos": start_pos,
			"start_scale": start_scale,
			"target_pos": target_slot.get_icon_global_position(),
			"target_scale": target_slot.get_icon_global_scale(),
			"target_slot": index,
			"is_replace": true,
			"source_lottery_slot": pool_slot
		}
		
		if vfx_manager:
			vfx_manager.enqueue(task)


# 截图函数 (保留供状态类使用)
func _capture_lottery_slot_snapshot(pool_idx: int) -> Dictionary:
	var slot = lottery_slots_grid.get_node_or_null("Lottery Slot_root_" + str(pool_idx))
	if not slot: return {}
	
	if not slot.item_main.visible: return {}
	
	return {
		"global_position": slot.get_main_icon_global_position(),
		"global_scale": slot.get_main_icon_global_scale()
	}

func _on_item_swapped(idx1: int, idx2: int) -> void:
	# 重要：此时 InventorySystem.inventory 已经交换完毕。
	# 所以 inventory[idx1] 里的其实是交换过来的 item2, inventory[idx2] 里的其实是 item1.
	var item_now_at_1 = InventorySystem.inventory[idx1]
	var item_now_at_2 = InventorySystem.inventory[idx2]
	var slot1 = item_slots_grid.get_node("Item Slot_root_" + str(idx1))
	var slot2 = item_slots_grid.get_node("Item Slot_root_" + str(idx2))
	
	if vfx_manager:
		# 我们希望表现的是：
		# 原本在 idx2 的物品（现在是 item_now_at_1）从 pos2 飞向 pos1
		# 原本在 idx1 的物品（现在是 item_now_at_2）从 pos1 飞向 pos2
		vfx_manager.enqueue({
			"type": "swap",
			"item1": item_now_at_1,
			"item2": item_now_at_2,
			"pos1": slot2.get_icon_global_position(), # item1 的起点是原本的位置2
			"pos2": slot1.get_icon_global_position(), # item2 的起点是原本的位置1
			"idx1": idx1, # item1 最终降落的目标槽位
			"idx2": idx2 # item2 最终降落的目标槽位
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
		# 处理以旧换新等模式
		if state_machine:
			var dict_payload = {}
			if payload is ContextProxy:
				dict_payload = payload.get_all()
			elif payload is Dictionary:
				dict_payload = payload
				
			if dict_payload.get("type") == "trade_in":
				state_machine.transition_to(&"TradeIn", dict_payload)
				
	elif event_id == &"order_refresh_requested":
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

func _has_more_tasks_for_pool(_pool_idx: int) -> bool:
	# 如果 vfx_manager 还在演，或者还有 pending 物品，认为还有任务
	if vfx_manager and vfx_manager.is_busy():
		return true
	
	if not InventorySystem.pending_items.is_empty():
		return true
		
	return false
