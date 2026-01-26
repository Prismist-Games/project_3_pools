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
	# 关键修复：如果正在跳转到 TradeIn、PreciseSelection 或 TargetedSelection，不要刷新奖池，因为这些流程还在进行中
	if machine and machine.pending_state_name in [&"TradeIn", &"PreciseSelection", &"TargetedSelection"]:
		if controller:
			controller.unlock_ui("draw")
		pool_index = -1
		is_draw_complete = false
		return

	# 关键修复：统一在退出时根据情况处理奖池关盖
	# 如果 pending_items 为空，说明这是一次完整的"抽奖并直接放入口袋"或者抽奖失败的流程
	# 如果不为空，说明正在跳转到 Replacing 状态，不应在此处关盖
	if controller and pool_index != -1 and InventorySystem.pending_items.is_empty():
		# 让所有三个 slot 同时播放推挤刷新动画
		if controller.pool_controller and controller.pool_controller.has_method("play_all_refresh_animations"):
			# 先标记动画中（防止 pools_refreshed 信号触发重复刷新）
			controller.pool_controller._is_animating_refresh = true
			# 刷新奖池数据（这会触发 pools_refreshed 信号，但被标记阻止）
			PoolSystem.refresh_pools()
			# 异步执行动画，不阻塞 exit
			controller.pool_controller.play_all_refresh_animations(
				PoolSystem.current_pools,
				pool_index
			)
		else:
			# 兜底：仅关闭被点击的 slot
			PoolSystem.refresh_pools()
			var slot = controller.lottery_slots_grid.get_node_or_null("Lottery Slot_root_" + str(pool_index))
			if slot:
				if slot.has_method("play_close_sequence"):
					slot.play_close_sequence()
				else:
					slot.close_lid()
		
		controller.last_clicked_pool_idx = -1
		controller.pending_source_pool_idx = -1
		
	if controller:
		controller.unlock_ui("draw")
		controller.set_updates_suppressed(false)
	pool_index = -1
	is_draw_complete = false

func can_transition_to(next_state: StringName) -> bool:
	# 显式允许：转换到 Modal、TradeIn、PreciseSelection 或 TargetedSelection（词缀触发）
	if next_state in [&"Modal", &"TradeIn", &"PreciseSelection", &"TargetedSelection"]:
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
	controller.set_updates_suppressed(true) # 暂停立即UI刷新，转交给VFX Landing
	
	# 清除选中状态，因为抽奖操作与整理操作是不同的上下文
	if InventorySystem.selected_slot_index != -1:
		InventorySystem.selected_slot_index = -1
	
	# 关键修复：在此处暂停 VFX 队列，防止物品在盖子还没开时就飞走
	if controller.vfx_manager:
		controller.vfx_manager.is_paused = true
	
	# 关键修复：在抽奖之前设置揭示标志，防止角标在揭示完成前显示
	slot._is_reveal_in_progress = true
	
	# 临时捕获所有获得的物品（包括直接进背包的）
	var captured_items: Array[ItemInstance] = []
	var capture_fn = func(item: ItemInstance):
		captured_items.append(item)
	
	EventBus.item_obtained.connect(capture_fn)
	
	# Start buffering skill feedback to prevent spoilers before reveal
	SkillSystem.start_buffering()
	
	var success = PoolSystem.draw_from_pool(pool_index)
	EventBus.item_obtained.disconnect(capture_fn)
	
	if not success:
		# Flush immediately on failure (though unlikely to have triggered skills)
		SkillSystem.stop_and_flush_buffering()
		
		# 如果抽奖失败，恢复队列（虽然此时队列应该是空的）
		if controller.vfx_manager:
			controller.vfx_manager.is_paused = false
		
		# 重置揭示标志
		slot._is_reveal_in_progress = false
		
		# 触发金币不足音效信号
		EventBus.game_event.emit(&"gold_insufficient", null)
		
		# 抖动反馈
		slot.play_shake()
		controller.last_clicked_pool_idx = -1
		controller.unlock_ui("draw")
		controller.set_updates_suppressed(false)
		
		# 关键：清除 pool_index，防止 exit() 刷新奖池
		pool_index = -1
		
		mark_complete()
		machine.transition_to(&"Idle")
		return
	
	# 关键检查：如果词缀触发了状态转换（如 TradeIn），则不继续执行揭示序列
	# 此时状态机已经不在 Drawing 状态了
	if machine.get_current_state_name() != &"Drawing":
		# Flush on transition interruption to ensure feedback is shown
		SkillSystem.stop_and_flush_buffering()
		
		# 词缀已处理流程（如 TradeIn），解锁 UI 并退出
		controller.unlock_ui("draw")
		controller.set_updates_suppressed(false)
		
		# [修复] 只有在非选择模式下才重置揭示标志，防止打断 PreciseSelection/TargetedSelection 初始化时的 reveal 状态
		var next_state = machine.get_current_state_name()
		if next_state not in [&"PreciseSelection", &"TargetedSelection"]:
			slot._is_reveal_in_progress = false # 重置揭示标志
			
		if controller.vfx_manager:
			controller.vfx_manager.is_paused = false
		return
	
	# 如果没有任何物品进入背包（比如全部进入了待定队列，或者被词缀拦截进入了 modal）
	# 我们需要在这里手动处理解锁，否则 UI 会卡死
	# 无论如何，一定要播放揭示动画（打开盖子）
	# 关键修复：总是优先显示 captured_items (本次抽奖产生的所有物品)，
	# 而不是 pending_items。因为已进入背包的物品也需要先在 Slot 里显示出来，
	# 然后通过 VFX 队列模拟飞入背包的过程。
	var display_items = captured_items
	# 我们仍然开启盖子以显示内部或仅仅作为状态转换的视觉停留
	await slot.play_reveal_sequence(display_items)

	# Reveal finished, flush buffered skill feedback
	SkillSystem.stop_and_flush_buffering()

	# [Reveal Phase End] 更新抽奖栏订单角标
	if controller.pool_controller:
		# 强制刷新即使是在 drawing 状态，以便显示 "Owned" 或更新 Check 状态
		# 这里的刷新时机对应用户期望的“物品黑色覆盖被揭开的时刻”（即 reveal 动画刚播完）
		controller.pool_controller.refresh_all_order_hints(true)
	
	# 盖子已经全开了，现在恢复 VFX 队列让物品飞出来
	if controller.vfx_manager:
		controller.vfx_manager.resume_process()
	
	# 检查是否需要进入 Replacing 状态
	if not InventorySystem.pending_items.is_empty():
		# 背包满了，有物品在等待处理
		mark_complete()
		machine.transition_to(&"Replacing", {"source_pool_index": pool_index})
	else:
		# 标记完成即可，具体解锁和归位由 exit() 或 _on_vfx_queue_finished 触发的 transition 处理
		mark_complete()
		
		# 检查是否还有正在播放的 VFX
		if not (controller._is_vfx_processing or controller.vfx_manager.is_busy()):
			# 没有任何异步任务在运行，直接归位
			machine.transition_to(&"Idle")
