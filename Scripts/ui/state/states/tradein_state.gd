extends "res://scripts/ui/state/ui_state.gd"

## TradeInState - 以旧换新（词缀触发）
##
## 触发: 玩家点击带 Trade-in 词缀的奖池
## 效果: 奖池门打开但为空，等待玩家选择背包物品
## 交互流程:
##   1. 玩家点击 item slot 选择物品 → 物品飞入 lottery slot → 门关上 → shake
##   2. 执行置换回调，产出新物品
##   3. 进入正常揭示流程（开门 → 出东西）
## 取消: 右键取消 → 关门，回到 Idle

## 引用到主控制器
var controller: Node = null

## 来源奖池索引
var pool_index: int = -1

## 置换逻辑回调 (来自 AffixEffect)
var on_trade_callback: Callable

## 是否已完成选择（防止重复点击）
var _is_selecting: bool = false

## 是否正在播放动画
var _is_animating: bool = false

func enter(payload: Dictionary = {}) -> void:
	pool_index = payload.get("pool_index", -1)
	on_trade_callback = payload.get("callback", Callable())
	_is_selecting = false
	_is_animating = false
	
	if controller:
		# controller.lock_ui("trade_in") - REMOVED: Managed by UIMode.REPLACE
		if controller.has_method("unlock_ui"):
			controller.unlock_ui("trade_in") # Force unlock just in case
			
		controller.last_clicked_pool_idx = pool_index
		controller.pending_source_pool_idx = pool_index
	
	# 打开奖池门，但里面是空的（等待选择）
	_open_empty_slot()

func exit() -> void:
	if controller:
		# controller.unlock_ui("trade_in") - REMOVED
		pass
	
	pool_index = -1
	on_trade_callback = Callable()
	_is_selecting = false
	_is_animating = false

func can_transition_to(next_state: StringName) -> bool:
	# 动画播放中不允许转换
	if _is_animating:
		return false
	# 允许转换到 Idle（取消/完成）、Replacing（背包满）或 Drawing
	if next_state in [&"Idle", &"Drawing", &"Replacing"]:
		return true
	return false

## 打开奖池门（空的，等待选择）
func _open_empty_slot() -> void:
	if not controller or pool_index == -1:
		return
	
	# 确保在 DrawingState 退出逻辑之后执行
	await controller.get_tree().process_frame
	
	var slot = _get_lottery_slot()
	if slot and slot.has_method("open_lid_for_trade_in"):
		slot.open_lid_for_trade_in()
	elif slot and slot.has_method("open_lid"):
		slot.open_lid()

## 关闭奖池门（取消时调用）
func _close_slot() -> void:
	if not controller or pool_index == -1:
		return
	
	var slot = _get_lottery_slot()
	if slot and slot.has_method("close_lid"):
		await slot.close_lid()

## 获取当前奖池槽位节点
func _get_lottery_slot() -> Control:
	if not controller or pool_index == -1:
		return null
	return controller.lottery_slots_grid.get_node_or_null("Lottery Slot_root_" + str(pool_index))

## 被 InventoryController 重定向的点击事件
func select_slot(index: int) -> void:
	if _is_selecting or _is_animating:
		return
	
	var item = InventorySystem.inventory[index]
	if item == null:
		return
	
	# 已损坏的物品不能参与以旧换新，只能回收
	if item.is_expired:
		return
	
	_is_selecting = true
	_is_animating = true
	
	# 执行飞入动画和置换逻辑
	await _execute_trade_in_sequence(index, item)

## 执行完整的以旧换新序列
func _execute_trade_in_sequence(slot_index: int, item: ItemInstance) -> void:
	var lottery_slot = _get_lottery_slot()
	var item_slot = controller.inventory_controller.get_slot_node(slot_index)
	
	if not lottery_slot or not item_slot:
		push_error("[TradeInState] Error: missing nodes. PoolIdx: %s, ItemSlot: %s" % [pool_index, slot_index])
		_is_animating = false
		_is_selecting = false
		return
	
	# 1. 物品从 item slot 飞入 lottery slot
	# 立即收回取消按钮，防止中途取消
	if controller.cancel_button_controller:
		controller.cancel_button_controller.hide_cancel_button_silent()

	var start_pos = controller.inventory_controller.get_slot_global_position(slot_index)
	var start_scale = controller.inventory_controller.get_slot_global_scale(slot_index)
	var target_pos = lottery_slot.get_main_icon_global_position()
	var target_scale = lottery_slot.get_main_icon_global_scale()
	
	# 隐藏原槽位图标
	item_slot.hide_icon()
	item_slot.is_vfx_target = true
	
	# 创建飞行精灵
	var fly_sprite = _create_fly_sprite(item, start_pos, start_scale)
	if fly_sprite:
		var tween = controller.create_tween()
		tween.set_parallel(true)
		tween.tween_property(fly_sprite, "global_position", target_pos, 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(fly_sprite, "scale", target_scale, 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		
		await tween.finished
		
		# --- 无缝切换逻辑 ---
		# 在销毁精灵前，先让奖池内部显示该物品
		if lottery_slot.has_method("update_queue_display"):
			lottery_slot.update_queue_display([item])
			lottery_slot.show_main_icon()
		
		fly_sprite.queue_free()

	# 2. 关门 + shake
	# 此时物品已经在盖子下面了，关门动作会自然遮住它
	if lottery_slot.has_method("close_lid"):
		await lottery_slot.close_lid()
		
	if lottery_slot.has_method("play_shake"):
		lottery_slot.play_shake()
		await controller.get_tree().create_timer(0.3).timeout # 等待震动完成
	
	# 恢复背包槽位状态
	item_slot.is_vfx_target = false
	
	# 3. 准备置换产出
	if controller.vfx_manager:
		controller.vfx_manager.is_paused = true # 确保产出的物品先别飞
	
	# 关键修复：防止角标在揭示序列之前显示
	if lottery_slot:
		lottery_slot._is_reveal_in_progress = true
	
	var captured_items: Array[ItemInstance] = []
	var capture_fn = func(new_item: ItemInstance):
		captured_items.append(new_item)
	EventBus.item_obtained.connect(capture_fn)
	
	# 4. 执行置换回调
	if on_trade_callback.is_valid():
		on_trade_callback.call(item)
	EventBus.item_obtained.disconnect(capture_fn)
	
	# ERA_4: 抽奖后递减保质期
	ShelfLifeEffect.trigger_shelf_life_decrement()
	
	# 5. --- 复用标准揭示序列 ---
	# 震动结束，现在开始像正常抽奖一样“开门出货”
	var display_items: Array = captured_items
	if display_items.is_empty():
		display_items = InventorySystem.pending_items.duplicate()
	
	if not display_items.is_empty():
		var first_item = display_items[0]
		# 强制触发一次角标更新（内部会等待揭示结束后显示）
		if controller.pool_controller and first_item is ItemInstance:
			if lottery_slot.has_method("update_status_badge"):
				lottery_slot.update_status_badge(controller.pool_controller._calculate_badge_state(first_item))
			if lottery_slot.has_method("set_upgradeable_badge"):
				lottery_slot.set_upgradeable_badge(controller.pool_controller._calculate_upgradeable_state(first_item))
		
		# 关键修复：不要手动设置 is_drawing = true，否则 play_reveal_sequence 会跳过动画
		await lottery_slot.play_reveal_sequence(display_items)
		
		# [Reveal Phase End] 更新抽奖栏订单角标
		if controller.pool_controller:
			controller.pool_controller.refresh_all_order_hints(true)
	else:
		# 没有物品显示，手动重置标志
		lottery_slot._is_reveal_in_progress = false
	
	# 6. 开启 VFX 队列，让新物品从奖池飞向背包
	if controller.vfx_manager:
		controller.vfx_manager.resume_process()
	
	# 7. 关键同步：如果物品是直接进入背包（非替换模式），需要等待飞行 VFX 完成后再执行刷新
	# 否则会产生“一边飞一边关门刷新”的冲突
	if InventorySystem.pending_items.is_empty():
		if controller.vfx_manager and controller.vfx_manager.is_busy():
			await controller.vfx_manager.queue_finished
	
	_is_animating = false
	
	# 8. 根据结果转换状态（会自动触发全局推挤刷新）
	if not InventorySystem.pending_items.is_empty():
		machine.transition_to(&"Replacing", {"source_pool_index": pool_index})
	else:
		_close_and_refresh()
		machine.transition_to(&"Idle")

## 创建飞行精灵
func _create_fly_sprite(item: ItemInstance, start_pos: Vector2, start_scale: Vector2) -> Sprite2D:
	if not controller or not controller.vfx_layer:
		return null
	
	var sprite = Sprite2D.new()
	sprite.texture = item.item_data.icon
	sprite.global_position = start_pos
	sprite.scale = start_scale
	sprite.z_index = 100
	controller.vfx_layer.add_child(sprite)
	
	return sprite

func handle_input(_event: InputEvent) -> bool:
	# 动画中不响应输入
	if _is_animating:
		return true
	
	# 取消操作已迁移到 CancelButtonController
	return false


## 公开取消方法，供 CancelButtonController 调用
func cancel() -> void:
	_cancel_trade_in()

## 取消以旧换新
func _cancel_trade_in() -> void:
	if _is_animating:
		return
	
	_is_animating = true
	await _close_slot()
	_is_animating = false
	
	machine.transition_to(&"Idle")

## 关闭奖池盖并刷新（完成置换后调用）
func _close_and_refresh() -> void:
	if not controller or pool_index == -1:
		return
	
	# 重置 lottery slot 的 is_drawing 状态
	var slot = _get_lottery_slot()
	if slot:
		slot.is_drawing = false
	
	# 重置追踪变量
	controller.last_clicked_pool_idx = -1
	controller.pending_source_pool_idx = -1
	
	# 让所有三个 slot 同时播放推挤刷新动画
	if controller.pool_controller and controller.pool_controller.has_method("play_all_refresh_animations"):
		# 先标记动画中
		controller.pool_controller._is_animating_refresh = true
		# 刷新奖池数据
		PoolSystem.refresh_pools()
		# 播放动画（异步）
		controller.pool_controller.play_all_refresh_animations(
			PoolSystem.current_pools,
			pool_index
		)
	else:
		# 兜底逻辑
		if slot and slot.has_method("play_close_sequence"):
			slot.play_close_sequence()
		PoolSystem.refresh_pools()
