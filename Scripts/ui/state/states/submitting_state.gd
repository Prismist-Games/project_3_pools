extends "res://scripts/ui/state/ui_state.gd"

## SubmittingState - 普通提交模式（积分订单）
##
## 触发: IdleState 下点击 Submit 开关或点击普通订单
## 效果: 奖池锁定，背包多选，普通订单可交互
## 特性: 共享物品机制（一物多满足）

var controller: Node = null


func _get_tree_safe() -> SceneTree:
	if is_instance_valid(controller) and controller.is_inside_tree():
		return controller.get_tree()
	return null

func enter(_payload: Dictionary = {}) -> void:
	InventorySystem.interaction_mode = InventorySystem.InteractionMode.MULTI_SELECT
	InventorySystem.selected_indices_for_order = []

func exit() -> void:
	InventorySystem.interaction_mode = InventorySystem.InteractionMode.NORMAL
	InventorySystem.selected_indices_for_order = []
	if controller:
		controller.unlock_ui("submit")

func can_transition_to(next_state: StringName) -> bool:
	return next_state in [&"Idle", &"SkillSelection", &"Modal"]

func handle_input(_event: InputEvent) -> bool:
	return false

func cancel() -> void:
	machine.transition_to(&"Idle")

## 执行普通订单提交
func submit_order() -> void:
	if not controller:
		push_error("[SubmittingState] controller 未设置")
		return
	
	controller.lock_ui("submit")
	
	var indices = InventorySystem.multi_selected_indices.duplicate()
	InventorySystem.selected_indices_for_order = []
	
	# 使用新的普通提交预检查
	var will_submit_orders = OrderSystem.preview_normal_submit(indices)
	
	if will_submit_orders.is_empty():
		EventBus.game_event.emit(&"order_submission_failed", null)
		controller.unlock_ui("submit")
		return
	
	InventorySystem.multi_selected_indices = []
	
	# 播放关盖动画（仅物品槽，订单槽在二选一时关盖）
	var max_close_duration: float = 0.0
	
	var submitting_item_slots: Array[Control] = []
	if controller.inventory_controller:
		for idx in indices:
			var slot = controller.inventory_controller.get_slot_node(idx)
			if slot:
				submitting_item_slots.append(slot)
	
	for slot in submitting_item_slots:
		if slot.has_method("play_submit_close"):
			var dur = slot.play_submit_close()
			if dur > max_close_duration:
				max_close_duration = dur
	
	var tree := _get_tree_safe()
	if not tree: return
	if max_close_duration > 0.0:
		await tree.create_timer(max_close_duration).timeout
	else:
		await tree.process_frame
	
	# 执行普通提交（不再自动生成新订单，返回被满足的订单索引）
	var satisfied_order_indices: Array[int] = OrderSystem.submit_normal(indices)
	
	if not satisfied_order_indices.is_empty():
		tree = _get_tree_safe()
		if not tree: return
		await tree.process_frame
		
		# 打开物品槽盖子
		var max_open_duration: float = 0.0
		
		for slot in submitting_item_slots:
			if is_instance_valid(slot) and slot.has_method("play_submit_open"):
				var dur = slot.play_submit_open()
				if dur > max_open_duration:
					max_open_duration = dur
		
		if max_open_duration > 0.0:
			tree = _get_tree_safe()
			if not tree: return
			await tree.create_timer(max_open_duration).timeout
		
		# 先过渡到 Idle（解除提交模式锁定），再进行二选一
		if machine.get_current_state_name() == &"Submitting":
			machine.transition_to(&"Idle")
		
		# 依次为每个被满足的订单执行二选一流程
		# satisfied_order_indices 是降序排列的，为了更直观的 UX 改为升序
		satisfied_order_indices.sort()
		var typed_indices: Array[int] = []
		typed_indices.assign(satisfied_order_indices)
		
		if is_instance_valid(controller):
			await controller.play_batch_order_pick_flow(typed_indices, typed_indices.size())
		
		# 刷新背包角标
		if is_instance_valid(controller) and controller.inventory_controller:
			controller.inventory_controller.update_all_slots(InventorySystem.inventory)
	
	if is_instance_valid(controller):
		controller.unlock_ui("submit")
