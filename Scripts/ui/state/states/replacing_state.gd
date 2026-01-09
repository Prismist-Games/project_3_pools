extends "res://scripts/ui/state/ui_state.gd"

## ReplacingState - 待处理/替换新物品
##
## 触发: DrawingState 完成后，背包满导致物品进入 pending 队列
## 效果: 奖池锁定，Submit 开关锁定，Recycle 开关可用，背包可交互
## 退出: 当 pending_items 清空时返回 Drawing 或 Idle

## 引用到主控制器
var controller: Node = null

## 新物品来源的奖池索引
var source_pool_index: int = -1

func enter(payload: Dictionary = {}) -> void:
	source_pool_index = payload.get("source_pool_index", -1)
	# Replacing 状态不修改 GameManager.current_ui_mode
	# 因为这是一个特殊状态，UI 显示仍然是 NORMAL

func exit() -> void:
	source_pool_index = -1
	# 清理完成，关闭奖池盖并刷新
	if controller and source_pool_index != -1:
		_close_pool_and_refresh()

func can_transition_to(next_state: StringName) -> bool:
	# 必须等待 pending_items 清空才能转换
	# 例外：可以转到 Drawing（继续抽奖）或 Idle（取消）
	if next_state in [&"Idle", &"Drawing"]:
		return InventorySystem.pending_items.is_empty()
	return false

func handle_input(event: InputEvent) -> bool:
	# Replacing 状态下右键取消会清空 pending 并返回 Idle
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if not InventorySystem.pending_items.is_empty():
			InventorySystem.pending_items.clear()
			machine.transition_to(&"Idle")
			return true
	return false

## 关闭奖池盖并刷新
func _close_pool_and_refresh() -> void:
	if controller and source_pool_index >= 0 and source_pool_index < 3:
		var pool_slot = controller.lottery_slots_grid.get_node_or_null("Lottery Slot_root_" + str(source_pool_index))
		if pool_slot:
			pool_slot.close_lid()
		
		# 重置追踪变量
		controller.last_clicked_pool_idx = -1
		controller.pending_source_pool_idx = -1
		
		# 刷新奖池
		PoolSystem.refresh_pools()
