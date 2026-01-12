extends "res://scripts/ui/state/ui_state.gd"

## TargetedSelectionState - 有的放矢选择状态
##
## 流程:
## 1. 点击带有"有的放矢"词缀的奖池后进入
## 2. "5 Choose 1" 面板从 y=4880 升起到 y=2384
## 3. 显示该奖池主题的 5 种物品图标
## 4. 玩家点击选择一种 -> 面板落下 -> 执行抽奖（物品种类锁定）
## 5. 玩家右键取消 -> 面板落下 -> 返回 Idle，退还金币

## 主控制器引用
var controller: Node = null

## 来源奖池索引
var source_pool_index: int = -1

## 奖池物品类型（用于过滤可选物品）
var pool_item_type: int = -1

## 可选的物品数据列表（最多 5 个）
var available_items: Array[ItemData] = []

## 选择结果回调
var on_select_callback: Callable = Callable()

## 是否已经操作（用于拦截重复输入）
var _has_acted: bool = false

## 是否真正确认了选择（用于决定退出时是否刷新奖池）
var _is_selection_confirmed: bool = false

## "5 Choose 1" 面板节点引用
var _panel: Sprite2D = null

## 5 个图标节点引用
var _icon_nodes: Array[Sprite2D] = []

## 5 个输入区域引用
var _input_areas: Array[Control] = []

## 动画常量
const PANEL_HIDDEN_Y: float = 4880.0
const PANEL_VISIBLE_Y: float = 2384.0
const ANIMATION_DURATION: float = 0.4

func enter(payload: Dictionary = {}) -> void:
	source_pool_index = payload.get("source_pool_index", -1)
	pool_item_type = payload.get("pool_item_type", -1)
	on_select_callback = payload.get("callback", Callable())
	_has_acted = false
	_is_selection_confirmed = false
	
	if not controller:
		push_error("[TargetedSelectionState] controller 未设置")
		return
	
	# 获取节点引用
	_panel = controller.targeted_panel
	if not _panel:
		push_error("[TargetedSelectionState] 未找到 5 Choose 1 面板节点")
		return
	
	_cache_icon_nodes()
	
	# 锁定 UI
	controller.lock_ui("targeted_selection")
	
	# 获取该奖池类型的所有物品
	available_items.assign(GameManager.get_items_for_type(pool_item_type))
	if available_items.is_empty():
		available_items.assign(GameManager.all_items.slice(0, 5))
	
	# 设置图标显示
	_setup_icons()
	
	# 连接输入信号
	_connect_input_signals()
	
	# 播放升起动画
	_play_panel_rise()

func exit() -> void:
	# 断开输入信号
	_disconnect_input_signals()
	
	# 清除订单图标高亮
	if controller and controller.quest_icon_highlighter:
		controller.quest_icon_highlighter.clear_all_highlights()
	
	# 如果是转向 Replacing 状态，不执行刷新（刷新由 Replacing.exit() 负责）
	if machine and machine.pending_state_name == &"Replacing":
		_has_acted = false
		_is_selection_confirmed = false
		available_items.clear()
		pool_item_type = -1
		on_select_callback = Callable()
		# 注意：保留 source_pool_index，Replacing 可能需要
		
		if controller:
			controller.unlock_ui("targeted_selection")
		return
	
	# 正常退出流程：只有在确认选择后才刷新奖池
	if controller and source_pool_index != -1 and _is_selection_confirmed:
		# 1. 关闭 lottery slot 并刷新奖池
		if controller.pool_controller and controller.pool_controller.has_method("play_all_refresh_animations"):
			controller.pool_controller._is_animating_refresh = true
			PoolSystem.refresh_pools()
			controller.pool_controller.play_all_refresh_animations(
				PoolSystem.current_pools,
				source_pool_index
			)
		else:
			PoolSystem.refresh_pools()
		
		controller.last_clicked_pool_idx = -1
		controller.pending_source_pool_idx = -1
	
	# 清理状态
	_has_acted = false
	_is_selection_confirmed = false
	available_items.clear()
	source_pool_index = -1
	pool_item_type = -1
	on_select_callback = Callable()
	
	if controller:
		controller.unlock_ui("targeted_selection")

func can_transition_to(_next_state: StringName) -> bool:
	return true

func handle_input(event: InputEvent) -> bool:
	# 右键取消
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if not _has_acted:
			_cancel_selection()
		return true
	return false

## 玩家选择了某个物品
func select_item(index: int) -> void:
	if _has_acted:
		return
	
	if index < 0 or index >= available_items.size():
		return
	
	_has_acted = true
	var selected_data: ItemData = available_items[index]
	
	# 关键：设置 last_clicked_pool_idx 使 VFX 能从正确的 slot 飞出
	controller.last_clicked_pool_idx = source_pool_index
	controller.pending_source_pool_idx = source_pool_index
	
	# 暂停 VFX 队列，防止物品在盖子还没开时就飞走
	if controller.vfx_manager:
		controller.vfx_manager.is_paused = true
	
	# 1. 播放弹窗落下动画
	await _play_panel_fall()
	
	# 2. 执行回调生成物品实例
	var item_instance: ItemInstance = null
	if on_select_callback.is_valid():
		item_instance = on_select_callback.call(selected_data)
	
	if not item_instance:
		_has_acted = false
		if controller.vfx_manager:
			controller.vfx_manager.is_paused = false
		return
	
	# 标记确认选择，退出时将刷新
	_is_selection_confirmed = true
	
	# 3. 获取 lottery slot 并播放开盖动画，展示生成的物品
	var slot = _get_lottery_slot(source_pool_index)
	if slot:
		await slot.play_reveal_sequence([item_instance])
	
	# 4. 正式入库：仅发出信号，由 InventorySystem 全局监听并处理添加
	# 这保证了物品只被添加一次，且能正常触发技能等系统
	EventBus.item_obtained.emit(item_instance)
	
	# 5. 恢复 VFX 队列让物品飞出来
	if controller.vfx_manager:
		controller.vfx_manager.resume_process()
	
	# 6. 检查是否需要进入 Replacing 状态
	if not InventorySystem.pending_items.is_empty():
		# 背包满了，进入 Replacing 状态
		machine.transition_to(&"Replacing", {"source_pool_index": source_pool_index})
	else:
		# 等待 VFX 完成后返回 Idle（由 _on_vfx_queue_finished 触发）
		if not (controller._is_vfx_processing or controller.vfx_manager.is_busy()):
			machine.transition_to(&"Idle")

## 取消选择（右键）
func _cancel_selection() -> void:
	if _has_acted:
		return
	
	_has_acted = true
	_is_selection_confirmed = false # 明确标记为未确认，不触发刷新
	
	# 退还金币（通过词缀的 base_gold_cost）
	var pool = PoolSystem.current_pools[source_pool_index] if source_pool_index >= 0 and source_pool_index < PoolSystem.current_pools.size() else null
	if pool and pool.affix:
		GameManager.add_gold(pool.affix.base_gold_cost)
	
	# 播放落下动画
	await _play_panel_fall()
	
	# 返回 Idle
	machine.transition_to(&"Idle")

## 缓存图标节点引用
func _cache_icon_nodes() -> void:
	_icon_nodes.clear()
	_input_areas.clear()
	
	var grid = _panel.get_node_or_null("Item Choice Grid")
	if not grid:
		return
	
	for i in range(5):
		var root = grid.get_node_or_null("Item Choice Root_" + str(i))
		if root:
			var icon = root.get_node_or_null("Item_icon") as Sprite2D
			var input_area = root.get_node_or_null("Input Area") as Control
			_icon_nodes.append(icon)
			_input_areas.append(input_area)

## 设置图标显示
func _setup_icons() -> void:
	for i in range(_icon_nodes.size()):
		var icon = _icon_nodes[i]
		var input_area = _input_areas[i]
		
		if i < available_items.size():
			var item_data = available_items[i]
			if icon:
				icon.texture = item_data.icon
				icon.visible = true
			if input_area:
				input_area.visible = true
		else:
			if icon:
				icon.visible = false
			if input_area:
				input_area.visible = false

## 连接输入区域信号
func _connect_input_signals() -> void:
	for i in range(_input_areas.size()):
		var input_area = _input_areas[i]
		if input_area:
			if not input_area.gui_input.is_connected(_on_icon_input):
				input_area.gui_input.connect(_on_icon_input.bind(i))
			# 连接 hover 信号用于高亮订单图标
			if not input_area.mouse_entered.is_connected(_on_icon_mouse_entered):
				input_area.mouse_entered.connect(_on_icon_mouse_entered.bind(i))
			if not input_area.mouse_exited.is_connected(_on_icon_mouse_exited):
				input_area.mouse_exited.connect(_on_icon_mouse_exited.bind(i))

## 断开输入区域信号
func _disconnect_input_signals() -> void:
	for i in range(_input_areas.size()):
		var input_area = _input_areas[i]
		if input_area:
			if input_area.gui_input.is_connected(_on_icon_input):
				input_area.gui_input.disconnect(_on_icon_input.bind(i))
			if input_area.mouse_entered.is_connected(_on_icon_mouse_entered):
				input_area.mouse_entered.disconnect(_on_icon_mouse_entered.bind(i))
			if input_area.mouse_exited.is_connected(_on_icon_mouse_exited):
				input_area.mouse_exited.disconnect(_on_icon_mouse_exited.bind(i))

## 图标输入处理
func _on_icon_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		select_item(index)

## 图标 hover 进入 (用于高亮订单图标)
func _on_icon_mouse_entered(index: int) -> void:
	if index < 0 or index >= available_items.size():
		return
	
	var item_data = available_items[index]
	if controller and controller.quest_icon_highlighter:
		controller.quest_icon_highlighter.highlight_by_item_id(item_data.id)

## 图标 hover 离开
func _on_icon_mouse_exited(_index: int) -> void:
	if controller and controller.quest_icon_highlighter:
		controller.quest_icon_highlighter.clear_all_highlights()

## 播放面板升起动画
func _play_panel_rise() -> void:
	if not _panel:
		return
	
	_panel.position.y = PANEL_HIDDEN_Y
	_panel.visible = true
	
	var tween = controller.create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(_panel, "position:y", PANEL_VISIBLE_Y, ANIMATION_DURATION)
	await tween.finished

## 播放面板落下动画
func _play_panel_fall() -> void:
	if not _panel:
		return
	
	var tween = controller.create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(_panel, "position:y", PANEL_HIDDEN_Y, ANIMATION_DURATION)
	await tween.finished
	
	_panel.visible = false

## 辅助：获取 LotterySlot 节点
func _get_lottery_slot(index: int) -> Control:
	if not controller or not controller.lottery_slots_grid:
		return null
	return controller.lottery_slots_grid.get_node_or_null("Lottery Slot_root_" + str(index))
