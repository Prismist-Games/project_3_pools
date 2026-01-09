extends "res://scripts/ui/state/ui_state.gd"

## DrawingState - 抽奖中
##
## 触发: IdleState 下点击任意奖池
## 效果: 全 UI 锁定，等待动画完成
## 分支: 根据词缀类型转移到不同状态

## 引用到主控制器
var controller: Node = null

## 当前抽奖的奖池索引
var pool_index: int = -1

## 抽奖是否完成（用于守卫转换）
var is_draw_complete: bool = false

func enter(payload: Dictionary = {}) -> void:
	pool_index = payload.get("pool_index", -1)
	is_draw_complete = false

func exit() -> void:
	if controller:
		controller.unlock_ui("draw")
	pool_index = -1
	is_draw_complete = false

func can_transition_to(next_state: StringName) -> bool:
	# 显式允许：转换到 Modal
	if next_state == &"Modal":
		return true
		
	# 如果锁定已被释放，或者标记已完成，则允许转换
	if is_draw_complete:
		return true
		
	# 兜底：如果 controller 已经解锁了，说明逻辑上已经走完了
	if controller and not controller.is_ui_locked():
		return true
		
	return false

## 标记抽奖完成，允许状态转换
func mark_complete() -> void:
	is_draw_complete = true

## 执行抽奖（从 game_2d_ui.gd 迁移）
func draw() -> void:
	if not controller:
		push_error("[DrawingState] controller 未设置")
		return
	
	if controller.is_ui_locked() or not InventorySystem.pending_items.is_empty():
		return
	
	var slot = controller.lottery_slots_grid.get_node("Lottery Slot_root_" + str(pool_index))
	
	controller.last_clicked_pool_idx = pool_index
	controller.pending_source_pool_idx = pool_index
	
	controller.lock_ui("draw")
	
	# 关键修复：在此处暂停 VFX 队列，防止物品在盖子还没开时就飞走
	if controller.vfx_manager:
		controller.vfx_manager.is_paused = true
	
	# 临时捕获所有获得的物品（包括直接进背包的）
	var captured_items: Array[ItemInstance] = []
	var capture_fn = func(item: ItemInstance):
		captured_items.append(item)
	
	EventBus.item_obtained.connect(capture_fn)
	var success = PoolSystem.draw_from_pool(pool_index)
	EventBus.item_obtained.disconnect(capture_fn)
	
	if not success:
		# 如果抽奖失败，恢复队列（虽然此时队列应该是空的）
		if controller.vfx_manager:
			controller.vfx_manager.is_paused = false
		
		# 抖动反馈
		slot.play_shake()
		controller.last_clicked_pool_idx = -1
		controller.unlock_ui("draw")
		mark_complete()
		machine.transition_to(&"Idle")
		return
	
	# 如果没有任何物品进入背包（比如全部进入了待定队列，或者被词缀拦截进入了 modal）
	# 我们需要在这里手动处理解锁，否则 UI 会卡死
	# 无论如何，一定要播放揭示动画（打开盖子）
	var display_items = InventorySystem.pending_items.duplicate()
	if display_items.is_empty():
		display_items = captured_items
	
	# 如果 pending 为空，说明物品可能已经进背包了（VFX 正在播，但由于我们暂停了，它们还没动）
	# 我们仍然开启盖子以显示内部或仅仅作为状态转换的视觉停留
	await slot.play_reveal_sequence(display_items)
	
	# 盖子已经全开了，现在恢复 VFX 队列让物品飞出来
	if controller.vfx_manager:
		controller.vfx_manager.resume_process()
	
	# 检查是否需要进入 Replacing 状态
	if not InventorySystem.pending_items.is_empty():
		# 背包满了，有物品在等待处理
		mark_complete()
		machine.transition_to(&"Replacing", {"source_pool_index": pool_index})
	else:
		# 检查是否还有正在播放的 VFX
		if controller._is_vfx_processing or controller.vfx_manager.is_busy():
			# 标记完成即可，具体解锁和归位由游戏主控制器的 _on_vfx_queue_finished 处理
			mark_complete()
		else:
			# 没有任何异步任务在运行，直接归位
			mark_complete()
			
			if slot.has_method("play_close_sequence"):
				await slot.play_close_sequence()
			
			# 盖子关上后再刷新逻辑数据
			PoolSystem.refresh_pools()
			
			machine.transition_to(&"Idle")
