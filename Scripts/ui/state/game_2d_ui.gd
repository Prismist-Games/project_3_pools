extends Control

## 成品 UI 控制器：管理 Game2D 场景的逻辑接入与动画序列。
##
## 重构中: 逻辑已拆分为子控制器 (Inventory/Pool/Order/Switch Controller)

# --- 节点引用 (根据 game2d-uiux-integration-spec.md) ---
@onready var money_label: RichTextLabel = find_child("Money_label", true)

@onready var game_theme: Theme = preload("res://data/game_theme.tres")

@onready var item_slots_grid: GridContainer = find_child("Item Slots Grid", true)
@onready var lottery_slots_grid: HBoxContainer = find_child("Lottery Slots Grid", true)
@onready var quest_slots_grid: VBoxContainer = find_child("Quest Slots Grid", true)
@onready var main_quest_slot: Control = find_child("Main Quest Slot_root", true)

@onready var submit_switch: Node2D = find_child("TheMachineSwitch_Submit", true)
@onready var recycle_switch: Node2D = find_child("TheMachineSwitch_Recycle", true)

@onready var vfx_layer: Node2D = get_node_or_null("VfxLayer")

# "有的放矢"选择面板
@onready var targeted_panel: Sprite2D = find_child("5 Choose 1", true)

# 技能槽位节点引用
@onready var skill_slot_0: Node2D = find_child("TheMachineSlot_0", true)
@onready var skill_slot_1: Node2D = find_child("TheMachineSlot_1", true)
@onready var skill_slot_2: Node2D = find_child("TheMachineSlot_2", true)

# 时代显示组件引用 (待手动添加后通过 find_child 自动获取)
var era_label: Control = null

# 兔子对话框节点引用
@onready var rabbit_dialog_box: Sprite2D = find_child("Dialog Box", true)
@onready var rabbit_dialog_label: RichTextLabel = find_child("Dialog Label", true)

@onready var language_switch: Button = get_node_or_null("Language Switch")

# --- ERA_3 DLC 面板节点引用 ---
@onready var dlc_panel: Node2D = find_child("The Machine DLC", true)
@onready var dlc_item_slots_grid: GridContainer = find_child("Additional Item Slots Grid", true)
@onready var dlc_label: RichTextLabel = find_child("DLC Label", true)

# --- 子控制器 ---
const QuestIconHighlighterScript = preload("res://scripts/ui/controllers/quest_icon_highlighter.gd")

var inventory_controller: InventoryController
var pool_controller: PoolController
var order_controller: OrderController
var switch_controller: SwitchController
var skill_slot_controller: SkillSlotController
var rabbit_dialog_controller: RabbitDialogController
var quest_icon_highlighter: RefCounted # QuestIconHighlighter

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
var _last_merge_target_idx: int = -1 # 跟踪最近一次合并的目标索引，用于在 item_moved 信号中识别合并状态
var _is_mouse_on_recycle_switch: bool = false # 跟踪鼠标是否在回收开关上

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
	EventBus.item_recycled.connect(_on_item_recycled)
	
	# ERA_3: 监听时代切换，控制 DLC 面板显示
	EraManager.era_changed.connect(_on_era_changed)
	
	# 4. 初始刷新
	_refresh_all()
	
	# 5. 初始化 DLC 面板状态（根据当前时代）
	_update_dlc_panel_visibility()
	
	if language_switch:
		language_switch.pressed.connect(_on_language_switch_pressed)

func _on_language_switch_pressed() -> void:
	var current_locale = TranslationServer.get_locale()
	var new_locale = "en" if current_locale.begins_with("zh") else "zh"
	TranslationServer.set_locale(new_locale)
	
	# Godot 会自动发出 NOTIFICATION_TRANSLATION_CHANGED
	# 我们在 _notification 中处理强制刷新
	print("[Game2DUI] 语言切换至: %s" % new_locale)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		# 强制刷新所有 UI 文本
		if is_node_ready():
			_refresh_all()
			
			# 如果当前有兔子对话，也需要刷新
			if rabbit_dialog_controller and rabbit_dialog_controller.is_showing():
				rabbit_dialog_controller.update_dialog_text(rabbit_dialog_controller.get_current_type())
	# 5. 获取时代显示标签 (如果已手动添加到场景)
	era_label = find_child("EraLabel", true)


func _init_controllers() -> void:
	inventory_controller = InventoryController.new()
	inventory_controller.name = "InventoryController"
	inventory_controller.game_ui = self
	add_child(inventory_controller)
	inventory_controller.setup(item_slots_grid)
	
	# ERA_3: 设置 DLC 额外槽位
	if dlc_item_slots_grid:
		inventory_controller.setup_dlc_grid(dlc_item_slots_grid)
	
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
	
	skill_slot_controller = SkillSlotController.new()
	skill_slot_controller.name = "SkillSlotController"
	skill_slot_controller.game_ui = self
	add_child(skill_slot_controller)
	var skill_slots: Array[Node2D] = [skill_slot_0, skill_slot_1, skill_slot_2]
	skill_slot_controller.setup(skill_slots)
	
	rabbit_dialog_controller = RabbitDialogController.new()
	rabbit_dialog_controller.name = "RabbitDialogController"
	add_child(rabbit_dialog_controller)
	rabbit_dialog_controller.setup(rabbit_dialog_box, rabbit_dialog_label)
	
	# 初始化订单图标高亮管理器
	quest_icon_highlighter = QuestIconHighlighterScript.new()
	quest_icon_highlighter.order_controller = order_controller
	quest_icon_highlighter.game_ui = self
	
	# 连接 hover 信号
	pool_controller.slot_hovered.connect(_on_pool_slot_hovered)
	pool_controller.slot_unhovered.connect(_on_pool_slot_unhovered)
	pool_controller.slot_item_hovered.connect(_on_pool_item_hovered)
	
	inventory_controller.slot_hovered.connect(_on_item_slot_hovered)
	inventory_controller.slot_unhovered.connect(_on_item_slot_unhovered)

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
		_update_ui_mode_display() # 初始同步
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
	vfx_manager.task_started.connect(func(_t): _update_ui_mode_display())
	vfx_manager.task_finished.connect(func(_t): _update_ui_mode_display())

## 状态机状态变更回调
func _on_state_changed(from_state: StringName, to_state: StringName) -> void:
	print("[Game2DUI] 状态转换: %s -> %s" % [from_state, to_state])
	
	# 处理兔子对话框
	_handle_rabbit_dialog(from_state, to_state)
	
	# State changed -> Mode might allow interaction or not, update display
	_update_ui_mode_display()
	_refresh_all() # Ensure visuals are correct for new state
	
	# 刷新当前hover的slot的状态（模式变化可能影响显示）
	_refresh_all_hovered_slot_states()

## 处理兔子对话框的显示与隐藏
func _handle_rabbit_dialog(from_state: StringName, to_state: StringName) -> void:
	if not rabbit_dialog_controller:
		return
	
	# 定义需要显示对话的状态
	const DIALOG_STATES: Array[StringName] = [
		&"SkillSelection",
		&"TargetedSelection",
		&"TradeIn",
		&"PreciseSelection",
		&"Replacing",
		&"Recycling",
		&"Submitting",
	]
	
	var was_dialog_state = from_state in DIALOG_STATES
	var is_dialog_state = to_state in DIALOG_STATES
	
	# 如果离开对话状态，隐藏对话框
	if was_dialog_state and not is_dialog_state:
		rabbit_dialog_controller.hide_dialog()
	# 如果进入对话状态，显示对话框
	elif is_dialog_state:
		var dialog_type = RabbitDialogController.state_to_dialog_type(to_state)
		rabbit_dialog_controller.show_dialog(dialog_type)

## VFX 队列开始回调
func _on_vfx_queue_started() -> void:
	_is_vfx_processing = true

## VFX 队列完成回调
func _on_vfx_queue_finished() -> void:
	_is_vfx_processing = false
	
	if state_machine:
		var current_state = state_machine.get_current_state_name()
		if current_state in [&"Drawing", &"Replacing", &"Recycling", &"PreciseSelection", &"TargetedSelection"]:
			# 如果动画播放完毕且没有待处理物品，则尝试返回 Idle 状态
			# 注意：具体的关盖和刷新逻辑已移至各状态的 exit() 或同步函数中
			if InventorySystem.pending_items.is_empty():
				state_machine.transition_to(&"Idle")
			else:
				# 如果还有待处理物品且鼠标仍在回收开关上，重新打开盖子
				if _is_mouse_on_recycle_switch:
					var item = InventorySystem.pending_items[0]
					if item:
						var value = Constants.rarity_recycle_value(item.rarity)
						switch_controller.show_recycle_preview(value)

func _refresh_all() -> void:
	_on_gold_changed(GameManager.gold)

	inventory_controller.update_all_slots(InventorySystem.inventory)
	_on_skills_changed(SkillSystem.current_skills)
	
	if PoolSystem.current_pools.is_empty():
		PoolSystem.refresh_pools()
	else:
		pool_controller.update_pools_display(PoolSystem.current_pools)
		
	order_controller.update_orders_display(OrderSystem.current_orders)
	_update_ui_mode_display()
	
	# 确保"有的放矢"面板初始隐藏（只设置 x 值，不触碰 y 值）
	if targeted_panel:
		var is_in_targeted = state_machine and state_machine.get_current_state_name() == &"TargetedSelection"
		if not is_in_targeted:
			# 只设置 x 值到隐藏位置，保留 y 值不变
			targeted_panel.position = Vector2(7500.0, targeted_panel.position.y)
			targeted_panel.visible = false


# --- 控制台 ---
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		_toggle_debug_console()
		get_viewport().set_input_as_handled()
		return
		
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_cancel_input(event)
		return
	
	# 处理lottery slot和item slot的全局鼠标松开事件（防止鼠标移出区域后松开无法触发）
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if pool_controller and pool_controller.has_method("handle_global_mouse_release"):
			pool_controller.handle_global_mouse_release()
		if inventory_controller and inventory_controller.has_method("handle_global_mouse_release"):
			inventory_controller.handle_global_mouse_release()


func _handle_cancel_input(event: InputEvent) -> void:
	# 1. 优先让状态机处理（如提交、回收、技能选择等专用状态）
	if state_machine and state_machine.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	
	# 2. 状态机未处理（通常在 Idle 状态），执行通用取消逻辑
	_handle_cancel()
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
	
	# 回收盖子展示逻辑：处于回收模式，或者有回收动画正在飞行中，或者正在执行回收锁
	var recycle_active = (mode == Constants.UIMode.RECYCLE) or _ui_locks.has("recycle")
	if vfx_manager and vfx_manager.has_active_recycle_tasks():
		recycle_active = true
	
	if recycle_active:
		# 注意：这里需要一个能手动设置开关状态但不改变模式的方法
		# 但 SwitchController 的 update_switch_visuals 是基于 mode 输入的
		# 我们需要绕过或模拟这个 mode
		switch_controller.update_recycle_visuals(true)
		# Submit 开关仍然根据 mode 走
		switch_controller.update_submit_visuals(mode == Constants.UIMode.SUBMIT)
	else:
		switch_controller.update_switch_visuals(mode)

# --- 信号处理代理 ---
func _on_gold_changed(val: int) -> void:
	money_label.text = str(val)


func _on_inventory_changed(inventory: Array) -> void:
	inventory_controller.update_all_slots(inventory)
	_update_dlc_label() # ERA_3: 背包变化时更新种类计数

func _on_pending_queue_changed(items: Array[ItemInstance]) -> void:
	if items.is_empty():
		pool_controller.update_pending_display([], -1)
		pending_source_pool_idx = -1 # 保留本地状态
	else:
		pool_controller.update_pending_display(items, pending_source_pool_idx)
	_update_ui_mode_display()
	
	# 刷新当前hover的slot的状态
	_refresh_all_hovered_slot_states()
	
	# 刷新 upgradeable 角标（pending 物品可能与背包物品配对）
	if inventory_controller:
		inventory_controller.refresh_upgradeable_badges()

func _on_skills_changed(skills: Array) -> void:
	if skill_slot_controller:
		skill_slot_controller.refresh_slots(skills)

func _on_pools_refreshed(pools: Array) -> void:
	pool_controller.update_pools_display(pools)

func _on_orders_updated(orders: Array) -> void:
	order_controller.update_orders_display(orders)
	# 同步更新奖池显示中的需求图标，并带有推挤动画
	if pool_controller:
		pool_controller.refresh_all_order_hints(true)

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
	_is_mouse_on_recycle_switch = true
	
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
	_is_mouse_on_recycle_switch = false
	_update_ui_mode_display()

func _on_selection_changed(index: int) -> void:
	inventory_controller.update_selection(index)
	
	# 刷新当前hover的slot的状态
	_refresh_all_hovered_slot_states()

# --- Coordinator Action Handlers ---

func _handle_single_item_recycle(selected_idx: int) -> void:
	lock_ui("recycle")
	
	var recycle_tasks = []
	var has_pending = not InventorySystem.pending_items.is_empty()
	var target_pos = switch_controller.get_recycle_bin_pos()
	var recycle_icon_node = switch_controller.get_recycle_icon_node()
	
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
				"recycle_icon_node": recycle_icon_node,
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
				"recycle_icon_node": recycle_icon_node,
				"on_complete": func(): _on_inventory_changed(InventorySystem.inventory)
			})
			
			# 关键修复：提前锁定视觉
			if slot_node.get("is_vfx_target") != null:
				slot_node.is_vfx_target = true
			
			InventorySystem.recycle_item(selected_idx)
	
	if vfx_manager:
		for task in recycle_tasks:
			vfx_manager.enqueue(task)
	
	unlock_ui("recycle")

func _handle_cancel() -> void:
	# 1. 如果处于非 NORMAL 模式，强制回退到 Idle
	if state_machine and state_machine.get_ui_mode() != Constants.UIMode.NORMAL:
		state_machine.transition_to(&"Idle")
	
	# 2. 清除所有选择状态
	var changed = false
	if InventorySystem.selected_slot_index != -1:
		InventorySystem.selected_slot_index = -1
		changed = true
	
	if not InventorySystem.multi_selected_indices.is_empty():
		InventorySystem.multi_selected_indices.clear()
		changed = true
	
	if changed:
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
	
	var is_merge = (_last_merge_target_idx == target_idx)
	_last_merge_target_idx = -1
	
	if vfx_manager:
		vfx_manager.enqueue({
			"type": "generic_fly",
			"item": item,
			"start_pos": inventory_controller.get_slot_global_position(source_idx),
			"end_pos": inventory_controller.get_slot_global_position(target_idx),
			"source_slot_node": source_node,
			"target_slot_node": target_node,
			"is_merge": is_merge,
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
		
		var start_pos = pool_slot.get_main_icon_global_position()
		var start_scale = pool_slot.get_main_icon_global_scale()
		
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
		var recycle_icon_node = switch_controller.get_recycle_icon_node()
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
				"recycle_icon_node": recycle_icon_node,
				"on_complete": func(): pass # No specific callback needed
			})
		
		var start_pos = pool_slot.get_main_icon_global_position()
		var start_scale = pool_slot.get_main_icon_global_scale()
		
		# 安全检查：如果起点位置无效（例如队列已空或槽位处于特殊状态），则跳过飞行动画
		if start_pos == Vector2.ZERO or not is_instance_valid(pool_slot):
			# 直接更新 UI，不播放动画
			if target_slot_node: target_slot_node.is_vfx_target = false
			if pool_slot: pool_slot.is_vfx_source = false
			_on_inventory_changed(InventorySystem.inventory)
			_update_ui_mode_display()
			return
			
		var task = {
			"type": "fly_to_inventory",
			"item": _new_item,
			"start_pos": start_pos,
			"start_scale": start_scale,
			"target_pos": target_pos,
			"target_scale": target_scale,
			"target_slot_node": target_slot_node,
			"is_replace": true,
			"is_merge": old_item == null, # 如果 old_item 是 null，说明是从 _on_item_merged 调过来的，也就是合并
			"source_lottery_slot": pool_slot,
			"on_complete": func(): _on_inventory_changed(InventorySystem.inventory)
		}
		
		if vfx_manager:
			vfx_manager.enqueue(task)
			_update_ui_mode_display()
		
func _on_item_merged(index: int, _new_item: ItemInstance, _target_item: ItemInstance) -> void:
	# 记录合并目标，供随后的信号（如 item_moved）使用
	_last_merge_target_idx = index
	
	# 如果有待定项，说明是从奖池发起的合并，需要触发 pool -> inventory 的飞行
	if not InventorySystem.pending_items.is_empty():
		_on_item_replaced(index, _new_item, null)
		# 奖池发起的合并不会触发 item_moved，所以直接重置标记，防止污染后续可能的移动操作
		_last_merge_target_idx = -1
	# 如果是背包内部合并，不需要在这里触发动画，因为随后会收到 item_moved 信号并由其触发 generic_fly

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
	
	# 清除选中状态，因为进入模态窗口是与整理操作无关的新上下文
	if InventorySystem.selected_slot_index != -1:
		InventorySystem.selected_slot_index = -1
	
	match modal_id:
		&"skill_selection":
			# 主线订单完成后的时代切换技能选择
			state_machine.transition_to(&"SkillSelection")
		&"skill_select":
			# 使用新的 SkillSelectionState 处理技能三选一
			state_machine.transition_to(&"SkillSelection")
		&"precise_selection":
			state_machine.transition_to(&"PreciseSelection", payload)
		&"targeted_selection":
			# 有的放矢：转到专用状态，使用 "5 Choose 1" 面板
			state_machine.transition_to(&"TargetedSelection", {
				"source_pool_index": payload.get("source_pool_index", last_clicked_pool_idx),
				"pool_item_type": payload.get("pool_item_type", -1),
				"callback": payload.get("callback", Callable())
			})

func _on_game_event(event_id: StringName, payload: Variant) -> void:
	if event_id == &"enter_selection_mode":
		if state_machine:
			var dict_payload = {}
			if payload is ContextProxy: dict_payload = payload.get_all()
			elif payload is Dictionary: dict_payload = payload
			if dict_payload.get("type") == "trade_in":
				# 传递 pool_index 和 callback 给 TradeInState
				var trade_in_payload = {
					"pool_index": dict_payload.get("pool_index", last_clicked_pool_idx),
					"callback": dict_payload.get("callback", Callable())
				}
				state_machine.transition_to(&"TradeIn", trade_in_payload)
				
	elif event_id == &"order_refresh_requested":
		var index = payload.get_value("index", -1) if payload is ContextProxy else -1
		if index != -1 and not is_ui_locked():
			lock_ui("order_refresh")
			var order = OrderSystem.current_orders[index]
			if order.refresh_count <= 0:
				unlock_ui("order_refresh")
				return
			
			await order_controller.play_refresh_sequence(index)
			var _new_order = OrderSystem.refresh_order(index)
			order_controller.update_orders_display(OrderSystem.current_orders)
			await order_controller.play_open_sequence(index)
			
			unlock_ui("order_refresh")

# --- 订单图标高亮 (Hover) ---

func _on_pool_slot_hovered(_pool_index: int, item_type: int) -> void:
	# 高亮订单需求
	if quest_icon_highlighter:
		quest_icon_highlighter.highlight_by_pool_type(item_type)

func _on_pool_slot_unhovered(_pool_index: int) -> void:
	# 取消高亮
	if quest_icon_highlighter:
		quest_icon_highlighter.clear_all_highlights()
	inventory_controller.clear_highlights()

func _on_pool_item_hovered(item_id: StringName) -> void:
	# 高亮背包中同名物品
	inventory_controller.highlight_items_by_id(item_id)

func _on_item_slot_hovered(_index: int, item_id: StringName) -> void:
	# 1. 高亮订单
	if quest_icon_highlighter:
		quest_icon_highlighter.highlight_by_item_id(item_id)
	
	# 2. 高亮背包中所有同名物品
	if item_id != &"":
		inventory_controller.highlight_items_by_id(item_id)

func _on_item_slot_unhovered(_index: int) -> void:
	if quest_icon_highlighter:
		quest_icon_highlighter.clear_all_highlights()
	inventory_controller.clear_highlights()


## 刷新所有当前被hover的slot的状态（当游戏状态变化时调用）
func _refresh_all_hovered_slot_states() -> void:
	# 刷新inventory slot的hover状态
	if inventory_controller:
		inventory_controller.refresh_hovered_slot_state()
	
	# 刷新lottery slot的hover状态
	if pool_controller:
		pool_controller.refresh_hovered_slot_state()
	
	# 刷新recycle switch相关的hover状态
	if switch_controller and switch_controller.is_recycle_hovered():
		switch_controller._update_recyclable_item_hover_state(true)

func _on_item_recycled(slot_index: int, item: ItemInstance) -> void:
	"""处理批量回收时的单个物品回收动画（ERA_3 种类替换场景）"""
	if not vfx_manager:
		return
		
	var slot_node = inventory_controller.get_slot_node(slot_index)
	if not slot_node:
		return
		
	var start_pos = inventory_controller.get_slot_global_position(slot_index)
	var start_scale = inventory_controller.get_slot_global_scale(slot_index)
	var recycle_pos = switch_controller.get_recycle_bin_pos()
	var recycle_icon_node = switch_controller.get_recycle_icon_node()
	
	vfx_manager.enqueue({
		"type": "fly_to_recycle",
		"item": item,
		"start_pos": start_pos,
		"start_scale": start_scale,
		"target_pos": recycle_pos,
		"source_slot_node": slot_node,
		"recycle_icon_node": recycle_icon_node,
		"on_complete": func(): pass
	})


# --- ERA_3: DLC 面板管理 ---

func _on_era_changed(_era_index: int) -> void:
	_update_dlc_panel_visibility()
	_update_dlc_label()


## 根据当前时代更新 DLC 面板的可见性
func _update_dlc_panel_visibility() -> void:
	if not dlc_panel:
		return
	
	var cfg = EraManager.current_config if EraManager else null
	var has_type_limit = cfg and cfg.has_item_type_limit()
	
	# 第三时代（有种类限制效果）时显示 DLC 面板
	dlc_panel.visible = has_type_limit
	
	# 同步更新 InventoryController 的额外槽位
	if inventory_controller:
		inventory_controller.set_dlc_slots_enabled(has_type_limit)
	
	# 更新 DLC Label
	if has_type_limit:
		_update_dlc_label()


## 更新 DLC Label 显示当前种类数量
func _update_dlc_label() -> void:
	if not dlc_label:
		return
	
	var cfg = EraManager.current_config if EraManager else null
	if not cfg:
		return
	
	var type_limit_effect = cfg.get_effect_of_type("ItemTypeLimitEffect")
	if not type_limit_effect:
		return
	
	var current_types = InventorySystem.get_unique_item_names().size()
	var max_types = type_limit_effect.max_item_types
	
	dlc_label.text = tr("DLC_TYPE_COUNT") % [current_types, max_types]
