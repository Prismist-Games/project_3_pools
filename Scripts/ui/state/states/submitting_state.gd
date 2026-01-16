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
	InventorySystem.selected_indices_for_order = []

func exit() -> void:
	InventorySystem.interaction_mode = InventorySystem.InteractionMode.NORMAL
	InventorySystem.selected_indices_for_order = []
	if controller:
		controller.unlock_ui("submit")

func can_transition_to(next_state: StringName) -> bool:
	# 可以取消回 Idle，或者提交成功后回 Idle
	# 同时允许在提交主线任务后跳转到技能选择或模态窗口
	return next_state in [&"Idle", &"SkillSelection", &"Modal"]

func handle_input(_event: InputEvent) -> bool:
	# 取消操作已迁移到 CancelButtonController
	return false


## 公开取消方法，供 CancelButtonController 调用
func cancel() -> void:
	machine.transition_to(&"Idle")

## 执行订单提交（从 game_2d_ui.gd 迁移）
func submit_order() -> void:
	if not controller:
		push_error("[SubmittingState] controller 未设置")
		return
	
	controller.lock_ui("submit")
	
	# 1. 预检查哪些订单会被满足
	var indices = InventorySystem.multi_selected_indices.duplicate()
	InventorySystem.selected_indices_for_order = [] # 立即清空，防止动画期间重复触发，且更新 UI 状态
	
	var selected_items: Array[ItemInstance] = []
	for idx in indices:
		if idx >= 0 and idx < InventorySystem.inventory.size() and InventorySystem.inventory[idx] != null:
			selected_items.append(InventorySystem.inventory[idx])
	
	if selected_items.is_empty():
		controller.unlock_ui("submit")
		return
	
	# 找出所有会被满足的订单及其对应的UI槽位
	var satisfying_slots: Array[Control] = []
	var satisfied_order_count: int = 0
	
	for i in range(OrderSystem.current_orders.size()):
		var order = OrderSystem.current_orders[i]
		if order.validate_selection(selected_items).valid:
			satisfied_order_count += 1
			var slot: Control = null
			
			# 通过 OrderController 查找对应的 UI 槽位
			if controller.order_controller:
				# 检查是否是主线任务
				if order.is_mainline:
					slot = controller.order_controller.main_quest_slot
				else:
					# 普通订单：在 quest_slots_grid 中查找
					for child in controller.order_controller.quest_slots_grid.get_children():
						if child.has_method("get_order") and child.get_order() == order:
							slot = child
							break
					
					# 如果还没找到，尝试备选方案
					if not slot:
						for ui_idx in range(1, 5):
							var ui_slot = controller.order_controller.quest_slots_grid.get_node_or_null("Quest Slot_root_" + str(ui_idx))
							if ui_slot:
								# 这里假设顺序匹配，虽然不够严谨但作为保底
								var displayed_order_idx = ui_idx - 1
								if displayed_order_idx < OrderSystem.current_orders.size():
									if OrderSystem.current_orders[displayed_order_idx] == order:
										slot = ui_slot
										break
			
			if slot:
				satisfying_slots.append(slot)
	
	if satisfied_order_count == 0:
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
	var success = OrderSystem.submit_order(-1, indices)
	
	if success:
		# 播放开盖动画逻辑：无论是否跳转状态，只要提交成功就应该开盖
		# 延迟一帧确保数据已经同步到 UI 节点上
		await controller.get_tree().process_frame
		
		for slot in satisfying_slots:
			if is_instance_valid(slot) and slot.has_node("AnimationPlayer"):
				var anim_player = slot.get_node("AnimationPlayer")
				if anim_player.has_animation("lid_open"):
					anim_player.play("lid_open")
		
		# 检查是否已经发生了自动状态转换（如主线触发的技能选择）
		if machine.get_current_state_name() == &"Submitting":
			# 只有还在提交模式时，才手动切回 Idle
			machine.transition_to(&"Idle")
	
	controller.unlock_ui("submit")
