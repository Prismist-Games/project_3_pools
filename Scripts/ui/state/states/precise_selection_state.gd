extends "res://scripts/ui/state/ui_state.gd"

## PreciseSelectionState - 精准选择（二选一）
##
## 流程:
## 1. 进入时 slot_0/slot_1 播放 reveal 动画展示两个选项，slot_2 保持关闭
## 2. 玩家点击 slot_0 或 slot_1 选择
## 3. 物品飞入背包 → 关门 → 三门刷新

## 引用到主控制器
var controller: Node = null

## 可选物品列表 (最多 2 个)
var options: Array[ItemInstance] = []

## 来源奖池索引 (用于 VFX 飞行起点)
var source_pool_index: int = -1

## 玩家选择的 slot 索引
var selected_slot_index: int = -1

## 是否已经做出了选择（防止重复点击）
var _has_made_selection: bool = false

## Hover 信号连接引用（用于清理）
var _hover_connections: Array[Dictionary] = []

func enter(payload: Dictionary = {}) -> void:
	options.assign(payload.get("items", []))
	source_pool_index = payload.get("source_pool_index", -1)
	selected_slot_index = -1
	_has_made_selection = false
	
	if not controller:
		push_error("[PreciseSelectionState] controller 未设置")
		return
	
	controller.lock_ui("precise_selection")
	
	# 开始展示流程 (异步)
	_setup_precise_display()

func exit() -> void:
	# 断开 hover 信号连接
	_disconnect_hover_signals()
	
	# 清除订单图标高亮
	if controller and controller.quest_icon_highlighter:
		controller.quest_icon_highlighter.clear_all_highlights()
	
	# 如果是转向 Replacing 状态，不执行刷新（刷新由 Replacing.exit() 负责）
	if machine and machine.pending_state_name == &"Replacing":
		# 只做基本清理
		_has_made_selection = false
		options.clear()
		source_pool_index = -1
		# 注意：不清除 selected_slot_index，Replacing 需要知道来源
		
		if controller:
			controller.unlock_ui("precise_selection")
		return
	
	# 正常退出流程：关闭所有打开的槽位并刷新
	if controller and selected_slot_index != -1:
		# 1. 手动关闭所有可能打开的槽位 (0 和 1)
		for i in range(2):
			var slot = _get_slot(i)
			if slot and slot.is_drawing:
				slot.play_close_sequence() # 异步关盖，不一定非要 await，因为下一步有统一刷新
		
		# 2. 调用统一的刷新动画
		if controller.pool_controller and controller.pool_controller.has_method("play_all_refresh_animations"):
			controller.pool_controller._is_animating_refresh = true
			PoolSystem.refresh_pools()
			# 使用 source_pool_index 作为主要刷新参考点
			controller.pool_controller.play_all_refresh_animations(
				PoolSystem.current_pools,
				source_pool_index
			)
		else:
			# 兜底：刷新奖池
			PoolSystem.refresh_pools()
		
		controller.last_clicked_pool_idx = -1
		controller.pending_source_pool_idx = -1
	
	_has_made_selection = false
	options.clear()
	source_pool_index = -1
	selected_slot_index = -1
	
	if controller:
		controller.unlock_ui("precise_selection")

func can_transition_to(_next_state: StringName) -> bool:
	return true

## 玩家选择其中一个选项
func select_option(index: int) -> void:
	if _has_made_selection:
		return
		
	# 仅允许点击 slot_0 或 slot_1
	if index < 0 or index >= options.size():
		return
	
	_has_made_selection = true
	selected_slot_index = index
	var item_instance = options[index]
	
	# 关键：设置 last_clicked_pool_idx 使 VFX 能从正确的 slot 飞出
	controller.last_clicked_pool_idx = index
	controller.pending_source_pool_idx = index
	
	# ERA_3: 检查种类限制
	var would_exceed = InventorySystem.would_exceed_type_limit(item_instance)
	
	if would_exceed:
		# 如果超出种类限制，直接进入待定队列，然后转到 Replacing 状态
		# 关闭另一扇盖子
		var other_index = 1 - index
		var other_slot = _get_slot(other_index)
		if other_slot:
			other_slot.close_lid()
		
		InventorySystem.pending_item = item_instance
		# ERA_4: 抽奖后递减保质期
		ShelfLifeEffect.trigger_shelf_life_decrement()
		machine.transition_to(&"Replacing", {"source_pool_index": index})
		return
	
	# 尝试添加到背包
	var added = InventorySystem.add_item_instance(item_instance)
	
	if not added:
		# 背包满，需要进入 Replacing 状态
		# 1. 先关闭另一扇二选一 slot 的盖子
		var other_index = 1 - index # 0 -> 1, 1 -> 0
		var other_slot = _get_slot(other_index)
		if other_slot:
			other_slot.close_lid()
		
		# 2. 将选中的物品加入 pending 队列（它会显示在当前选中的 slot 里）
		InventorySystem.pending_item = item_instance
		
		# ERA_4: 抽奖后递减保质期
		ShelfLifeEffect.trigger_shelf_life_decrement()
		
		# 3. 转换到 Replacing 状态
		machine.transition_to(&"Replacing", {"source_pool_index": index})
	else:
		# 添加成功，VFX 会自动触发飞行 (通过 item_added 信号)
		# 等待飞行完成后再关盖刷新 - 由 _on_vfx_queue_finished 处理
		# ERA_4: 抽奖后递减保质期
		ShelfLifeEffect.trigger_shelf_life_decrement()
		
		# 清除背包中的候选高亮
		if controller and controller.inventory_controller:
			controller.inventory_controller.refresh_upgradeable_badges([])

func handle_input(_event: InputEvent) -> bool:
	# 精准选择强制必须选一个，不可取消
	return false

## 展示二选一界面
func _setup_precise_display() -> void:
	if not controller:
		return
	
	# 关键修复：设置全局刷新标记，拦截由于金币变动触发的自动 Hint 刷新信号
	if controller.pool_controller:
		controller.pool_controller._is_animating_refresh = true
	
	# 构建二选一专用的 UI 配置
	var selection_ui_config = {
		"price_text": "",
		"affix_name": "AFFIX_CHOOSE_ONE",
		"description_text": "",
		"clear_hints": true,
		"skip_lid_animation": true # 关键：进入二选一时跳过盖子的推挤位移
	}
	
	# 1. 所有槽位并行更新数据和开门动画
	for i in range(3):
		var slot = _get_slot(i)
		if not slot: continue
		
		# 关键优化：使用 instant=true 立即更新标签数据，避免 Push-Away 带来的延迟
		if slot.has_method("refresh_slot_data"):
			slot.refresh_slot_data(selection_ui_config, true)
		
		# slot_0 和 slot_1 同时开始播放揭示动画 (开盖)
		if i < mini(options.size(), 2):
			var item = options[i]
			# 关键优化：增加 skip_shuffle=true 跳过洗牌，消除闪烁
			slot.play_reveal_sequence([item], false, true)
			# 清空默认的池类型，防止触发类型高亮
			slot.current_pool_item_type = -1
			
			# 【新增】设置角标状态
			if controller.pool_controller:
				if slot.has_method("update_status_badge"):
					slot.update_status_badge(controller.pool_controller._calculate_badge_state(item))
				if slot.has_method("set_upgradeable_badge"):
					slot.set_upgradeable_badge(controller.pool_controller._calculate_upgradeable_state(item))
			
			# 为该 slot 单独连接 hover 信号，高亮特定物品
			_connect_slot_hover(i, item.item_data.id)
		else:
			# slot_2 确保它是关着的
			if slot.lid_sprite:
				slot.lid_sprite.position.y = 0
			slot.current_pool_item_type = -1
	
	# 【优化】通知背包控制器，考虑当前的 options 进行角标高亮
	if controller and controller.inventory_controller:
		controller.inventory_controller.refresh_upgradeable_badges(options)
	
	# 立即解锁界面
	if controller.pool_controller:
		controller.pool_controller._is_animating_refresh = false

const PUSH_DURATION: float = 0.4

## 为特定 slot 连接 hover 信号
func _connect_slot_hover(slot_index: int, item_id: StringName) -> void:
	var slot = _get_slot(slot_index)
	if not slot:
		return
	
	var input_area = slot.get_node_or_null("Input Area")
	if not input_area:
		return
	
	# 创建闭包捕获 item_id 和 slot
	var on_entered = func():
		# 高亮订单图标
		if controller and controller.quest_icon_highlighter:
			controller.quest_icon_highlighter.highlight_by_item_id(item_id)
		# 变亮lottery slot（类似item slot的效果）
		if slot and slot.has_method("set_highlight"):
			slot.set_highlight(true)
	
	var on_exited = func():
		# 清除订单图标高亮
		if controller and controller.quest_icon_highlighter:
			controller.quest_icon_highlighter.clear_all_highlights()
		# 取消lottery slot变亮
		if slot and slot.has_method("set_highlight"):
			slot.set_highlight(false)
	
	# 连接信号
	input_area.mouse_entered.connect(on_entered)
	input_area.mouse_exited.connect(on_exited)
	
	# 记录连接以便清理
	_hover_connections.append({
		"input_area": input_area,
		"on_entered": on_entered,
		"on_exited": on_exited
	})

## 断开所有 hover 信号
func _disconnect_hover_signals() -> void:
	for conn in _hover_connections:
		var input_area = conn.input_area
		if is_instance_valid(input_area):
			if input_area.mouse_entered.is_connected(conn.on_entered):
				input_area.mouse_entered.disconnect(conn.on_entered)
			if input_area.mouse_exited.is_connected(conn.on_exited):
				input_area.mouse_exited.disconnect(conn.on_exited)
	
	_hover_connections.clear()

## 辅助：获取 LotterySlot 节点
func _get_slot(index: int) -> Control:
	if not controller or not controller.lottery_slots_grid:
		return null
	return controller.lottery_slots_grid.get_node_or_null("Lottery Slot_root_" + str(index))
