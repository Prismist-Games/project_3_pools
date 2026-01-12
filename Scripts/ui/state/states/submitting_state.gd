extends "res://scripts/ui/state/ui_state.gd"

## SubmittingState - 提交模式
##
## 触发: IdleState 下点击 Submit 开关
## 效果: 奖池锁定，背包多选，订单可交互

## 引用到主控制器（用于访问 UI 节点）
var controller: Node = null

func enter(_payload: Dictionary = {}) -> void:
	# UI State Machine is now the source of truth
	InventorySystem.interaction_mode = InventorySystem.InteractionMode.MULTI_SELECT
	InventorySystem.multi_selected_indices.clear()

func exit() -> void:
	InventorySystem.interaction_mode = InventorySystem.InteractionMode.NORMAL
	InventorySystem.multi_selected_indices.clear()

func can_transition_to(next_state: StringName) -> bool:
	# 可以取消回 Idle，或者提交成功后回 Idle
	# 同时允许在提交主线任务后跳转到技能选择或模态窗口
	return next_state in [&"Idle", &"SkillSelection", &"Modal"]

func handle_input(event: InputEvent) -> bool:
	# 右键取消
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		machine.transition_to(&"Idle")
		return true
	return false

## 执行订单提交（从 game_2d_ui.gd 迁移）
func submit_order() -> void:
	if not controller:
		push_error("[SubmittingState] controller 未设置")
		return
	
	controller.lock_ui("submit")
	
	# 1. 预检查哪些订单会被满足
	var selected_items: Array[ItemInstance] = []
	for idx in InventorySystem.multi_selected_indices:
		if idx >= 0 and idx < InventorySystem.inventory.size() and InventorySystem.inventory[idx] != null:
			selected_items.append(InventorySystem.inventory[idx])
	
	if selected_items.is_empty():
		controller.unlock_ui("submit")
		return
	
	# 找出所有会被满足的订单及其对应的UI槽位
	var satisfying_slots: Array[Control] = []
	for i in range(OrderSystem.current_orders.size()):
		var order = OrderSystem.current_orders[i]
		if order.validate_selection(selected_items).valid:
			var slot: Control = null
			
			if order.is_mainline:
				slot = controller.main_quest_slot
			else:
				# 普通订单：假设前4个非主线订单对应UI的1-4槽位
				# Use OrderController mapping if possible, but keep fallback
				if controller.order_controller:
					# Better: Find which slot displays this order
					# controller.order_controller.quest_slots_grid children
					for child in controller.order_controller.quest_slots_grid.get_children():
						if child.has_method("get_order") and child.get_order() == order:
							slot = child
							break
				else:
					for ui_idx in range(1, 5):
						var ui_slot = controller.quest_slots_grid.get_node_or_null("Quest Slot_root_" + str(ui_idx))
						if ui_slot:
							# Assuming order matches index
							var displayed_order_idx = ui_idx - 1
							if displayed_order_idx < OrderSystem.current_orders.size():
								if OrderSystem.current_orders[displayed_order_idx] == order:
									slot = ui_slot
									break
			
			if slot:
				satisfying_slots.append(slot)
	
	if satisfying_slots.is_empty():
		# 提交失败，没有任何订单被满足
		controller.unlock_ui("submit")
		return
	
	# 2. 播放所有满足订单的 lid_close 动画
	var close_tasks: Array = []
	for slot in satisfying_slots:
		if slot.has_node("AnimationPlayer"):
			var anim_player = slot.get_node("AnimationPlayer")
			if anim_player.has_animation("lid_close"):
				anim_player.play("lid_close")
				close_tasks.append(anim_player.animation_finished)
	
	# 等待所有关闭动画完成 (Parallel wait simulation)
	if not close_tasks.is_empty():
		for task in close_tasks:
			await task
	
	# 3. 执行提交
	var success = OrderSystem.submit_order(-1, InventorySystem.multi_selected_indices)
	
	if success:
		# 关键修复：检查状态机是否已经转换到了其他状态（如主线任务完成触发的 SkillSelection）
		# 如果当前状态不再是 Submitting，说明已经发生了自动跳转，不应再强制转回 Idle
		if machine.get_current_state_name() != &"Submitting":
			controller.unlock_ui("submit")
			return
			
		# 提交成功后退出模式（通过状态机）
		machine.transition_to(&"Idle")
		
		# 等待订单更新和数据同步
		await controller.get_tree().process_frame
		
		# 播放 lid_open 动画
		for slot in satisfying_slots:
			if slot.has_node("AnimationPlayer"):
				var anim_player = slot.get_node("AnimationPlayer")
				if anim_player.has_animation("lid_open"):
					anim_player.play("lid_open")
	
	controller.unlock_ui("submit")
