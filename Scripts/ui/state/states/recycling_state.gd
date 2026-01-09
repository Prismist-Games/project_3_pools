extends "res://scripts/ui/state/ui_state.gd"

## RecyclingState -  回收模式（批量）
##
## 触发: IdleState 下无选中且无 Pending 时点击 Recycle 开关
## 效果: 奖池锁定，订单锁定，背包多选

## 引用到主控制器
var controller: Node = null

# Controller sub-references
# 这些应该通过 controller 访问，或者直接注入
# 暂时为了兼容保留通过 controller 访问

func enter(_payload: Dictionary = {}) -> void:
	# UI State Machine is now the source of truth for UI Mode
	InventorySystem.interaction_mode = InventorySystem.InteractionMode.MULTI_SELECT
	InventorySystem.multi_selected_indices.clear()

func exit() -> void:
	InventorySystem.interaction_mode = InventorySystem.InteractionMode.NORMAL
	InventorySystem.multi_selected_indices.clear()

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
		
	# 找到 Switch_item_root 作为终点 (using SwitchController now available on controller as coordinator)
	var end_pos = Vector2.ZERO
	if controller.switch_controller:
		end_pos = controller.switch_controller.get_recycle_bin_pos()
	else:
		# Fallback
		var switch_item_root = controller.recycle_switch.find_child("Switch_item_root", true)
		if switch_item_root: end_pos = switch_item_root.global_position
	
	# 收集要回收的物品信息用于动画
	var recycle_tasks: Array[Dictionary] = []
	for idx in indices:
		var item = InventorySystem.inventory[idx]
		if item:
			# Use InventoryController helper
			var slot_pos = Vector2.ZERO
			var slot_scale = Vector2.ONE
			if controller.inventory_controller:
				slot_pos = controller.inventory_controller.get_slot_global_position(idx)
				slot_scale = controller.inventory_controller.get_slot_global_scale(idx)
			else:
				var slot = controller.item_slots_grid.get_node("Item Slot_root_" + str(idx))
				slot_pos = slot.get_icon_global_position()
				slot_scale = slot.get_icon_global_scale()
				
			recycle_tasks.append({
				"type": "fly_to_recycle",
				"item": item,
				"start_pos": slot_pos,
				"start_scale": slot_scale,
				"target_pos": end_pos
			})
	
	# 设置最后一个任务的处理回调：复位开关
	if not recycle_tasks.is_empty():
		recycle_tasks.back()["on_complete"] = func():
			# 等待一小段时间后手柄下落
			await controller.get_tree().create_timer(0.2).timeout
			if controller.switch_controller:
				controller.switch_controller.hide_recycle_preview()
			else:
				controller._tween_switch(controller.recycle_switch, controller.SwitchController.SWITCH_OFF_Y) # 可能会报错如果常量访问不到
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
