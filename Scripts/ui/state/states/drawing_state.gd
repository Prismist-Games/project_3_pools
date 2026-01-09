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
	
	controller.last_clicked_pool_idx = pool_index
	controller.pending_source_pool_idx = pool_index
	
	controller.lock_ui("draw")
	
	var success = PoolSystem.draw_from_pool(pool_index)
	if not success:
		# 如果抽奖失败（如金币不足），立即解锁并播放抖动反馈
		var slot = controller.lottery_slots_grid.get_node("Lottery Slot_root_" + str(pool_index))
		slot.play_shake()
		controller.last_clicked_pool_idx = -1
		controller.unlock_ui("draw")
		mark_complete()
		# 返回 Idle 状态
		machine.transition_to(&"Idle")
		return
	
	# 如果没有任何物品进入背包（比如全部进入了待定队列），则 VFX 队列不会启动
	# 我们需要在这里手动处理揭示并解锁，否则 UI 会卡死
	if not controller._is_vfx_processing:
		if not InventorySystem.pending_items.is_empty():
			var slot = controller.lottery_slots_grid.get_node("Lottery Slot_root_" + str(pool_index))
			# 收集所有 pending items
			var items = InventorySystem.pending_items.duplicate()
			# 原地播放揭示动画，但不关盖，也不重置 is_drawing
			await slot.play_reveal_sequence(items)
			
			# 虽然没飞走，但揭示完了，解锁 UI 让玩家处理背包
			controller.unlock_ui("draw")
			mark_complete()
			# 转换到 Replacing 状态
			machine.transition_to(&"Replacing", {"source_pool_index": pool_index})
			# 注意：此处不调用 PoolSystem.refresh_pools()，也不重置 last_clicked_pool_idx
			# 必须等待物品真正飞走进入背包
