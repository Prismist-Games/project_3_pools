extends "res://scripts/ui/state/ui_state.gd"

## RecyclingState -  回收模式（批量）
##
## 触发: IdleState 下无选中且无 Pending 时点击 Recycle 开关
## 效果: 奖池锁定，订单锁定，背包多选

## 引用到主控制器
var controller: Node = null

func enter(_payload: Dictionary = {}) -> void:
	GameManager.current_ui_mode = Constants.UIMode.RECYCLE
	InventorySystem.multi_selected_indices.clear()

func exit() -> void:
	InventorySystem.multi_selected_indices.clear()
	if GameManager.current_ui_mode == Constants.UIMode.RECYCLE:
		GameManager.current_ui_mode = Constants.UIMode.NORMAL

func can_transition_to(next_state: StringName) -> bool:
	return next_state == &"Idle"

func handle_input(event: InputEvent) -> bool:
	# 右键取消
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		machine.transition_to(&"Idle")
		return true
	return false

## 执行批量回收（从 game_2d_ui.gd 迁移）
func recycle_confirm() -> void:
	if not controller:
		push_error("[RecyclingState] controller 未设置")
		return
	
	controller.lock_ui("recycle")
	
	# 收集要回收的物品索引
	var indices = InventorySystem.multi_selected_indices.duplicate()
	if indices.is_empty():
		controller.unlock_ui("recycle")
		machine.transition_to(&"Idle")
		return
		
	# 找到 Switch_item_root 作为终点
	var switch_item_root = controller.recycle_switch.find_child("Switch_item_root", true)
	var end_pos = switch_item_root.global_position if switch_item_root else Vector2.ZERO
	
	# 收集要回收的物品信息用于动画
	var recycle_tasks: Array[Dictionary] = []
	for idx in indices:
		var item = InventorySystem.inventory[idx]
		if item:
			var slot = controller.item_slots_grid.get_node("Item Slot_root_" + str(idx))
			recycle_tasks.append({
				"type": "fly_to_recycle",
				"item": item,
				"start_pos": slot.get_icon_global_position(),
				"start_scale": slot.get_icon_global_scale(),
				"target_pos": end_pos
			})
	
	# 设置最后一个任务的处理回调：复位开关
	if not recycle_tasks.is_empty():
		recycle_tasks.back()["on_complete"] = func():
			# 等待一小段时间后手柄下落
			await controller.get_tree().create_timer(0.2).timeout
			controller._tween_switch(controller.recycle_switch, controller.SWITCH_OFF_Y)
			controller.unlock_ui("recycle")

	# 执行回收数据逻辑 (从大到小移除)
	indices.sort()
	indices.reverse()
	for idx in indices:
		InventorySystem.recycle_item(idx)
	
	# 提交 VFX 任务
	if controller.vfx_manager:
		controller.vfx_manager.enqueue_batch(recycle_tasks)
	
	# 切换回 Idle 状态
	machine.transition_to(&"Idle")
