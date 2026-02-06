extends "res://scripts/ui/state/ui_state.gd"

## EraSubmittingState - 时代提交模式（主线订单）
##
## 触发: IdleState 下点击主线订单
## 效果: 奖池锁定，背包多选，主线订单可交互
## 特性: 独占物品机制（不共享）

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
		controller.unlock_ui("era_submit")

func can_transition_to(next_state: StringName) -> bool:
	return next_state in [&"Idle", &"SkillSelection", &"Modal"]

func handle_input(_event: InputEvent) -> bool:
	return false

func cancel() -> void:
	machine.transition_to(&"Idle")

## 执行时代订单提交
func submit_order() -> void:
	if not controller:
		push_error("[EraSubmittingState] controller 未设置")
		return
	
	controller.lock_ui("era_submit")
	
	var indices = InventorySystem.multi_selected_indices.duplicate()
	InventorySystem.selected_indices_for_order = []
	
	# 预检查哪个主线订单可被满足
	var will_submit_orders = OrderSystem.preview_era_submit(indices)
	
	if will_submit_orders.is_empty():
		EventBus.game_event.emit(&"order_submission_failed", null)
		controller.unlock_ui("era_submit")
		return
	
	# 找到对应的主线 UI 槽位
	var satisfying_slots: Array[Control] = []
	if controller.order_controller:
		var mainline_orders = OrderSystem.get_mainline_orders()
		for order in will_submit_orders:
			for i in range(mainline_orders.size()):
				if mainline_orders[i] == order:
					var slot = controller.order_controller.get_slot_node(-(i + 1))
					if slot:
						satisfying_slots.append(slot)
					break
	
	InventorySystem.multi_selected_indices = []
	
	# 播放关盖动画
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
	
	for slot in satisfying_slots:
		if slot.has_node("AnimationPlayer"):
			var anim_player = slot.get_node("AnimationPlayer")
			if anim_player.has_animation("lid_close"):
				anim_player.play("lid_close")
				var dur = anim_player.get_animation("lid_close").length
				if dur > max_close_duration:
					max_close_duration = dur
	
	var tree := _get_tree_safe()
	if not tree: return
	if max_close_duration > 0.0:
		await tree.create_timer(max_close_duration).timeout
	else:
		await tree.process_frame
	
	# 执行时代提交
	var success = OrderSystem.submit_era(indices)
	
	if success:
		tree = _get_tree_safe()
		if not tree: return
		await tree.process_frame
		
		var max_open_duration: float = 0.0
		
		for slot in submitting_item_slots:
			if is_instance_valid(slot) and slot.has_method("play_submit_open"):
				var dur = slot.play_submit_open()
				if dur > max_open_duration:
					max_open_duration = dur
		
		for slot in satisfying_slots:
			if is_instance_valid(slot) and slot.has_node("AnimationPlayer"):
				var anim_player = slot.get_node("AnimationPlayer")
				if anim_player.has_animation("lid_open"):
					anim_player.play("lid_open")
					var dur = anim_player.get_animation("lid_open").length
					if dur > max_open_duration:
						max_open_duration = dur
		
		if max_open_duration > 0.0:
			tree = _get_tree_safe()
			if not tree: return
			await tree.create_timer(max_open_duration).timeout
		
		# 时代提交成功后，状态可能已自动跳转（如到技能选择）
		if machine.get_current_state_name() == &"EraSubmitting":
			machine.transition_to(&"Idle")
	
	if is_instance_valid(controller):
		controller.unlock_ui("era_submit")
