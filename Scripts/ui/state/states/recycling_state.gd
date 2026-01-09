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
	
	# 收集要回收的物品信息用于动画
	var recycle_tasks = []
	for idx in InventorySystem.multi_selected_indices:
		var item = InventorySystem.inventory[idx]
		if item:
			var slot = controller.item_slots_grid.get_node("Item Slot_root_" + str(idx))
			recycle_tasks.append({
				"item": item,
				"start_pos": slot.get_icon_global_position(),
				"start_scale": slot.get_icon_global_scale()
			})
	
	# 执行回收数据逻辑
	var indices = InventorySystem.multi_selected_indices.duplicate()
	indices.sort()
	indices.reverse()
	for idx in indices:
		InventorySystem.recycle_item(idx)
	
	# 切换回 Idle 状态
	machine.transition_to(&"Idle")
	
	# 播放飞入回收箱动画
	await _play_recycle_fly_anim(recycle_tasks)
	
	controller.unlock_ui("recycle")

## 播放回收飞行动画
func _play_recycle_fly_anim(tasks: Array) -> void:
	if tasks.is_empty():
		controller._tween_switch(controller.recycle_switch, controller.SWITCH_OFF_Y)
		return
		
	# 找到 Switch_item_root 作为终点
	var switch_item_root = controller.recycle_switch.find_child("Switch_item_root", true)
	if not switch_item_root:
		controller._tween_switch(controller.recycle_switch, controller.SWITCH_OFF_Y)
		return
		
	var end_pos = switch_item_root.global_position
	
	# 收集所有飞行信号以确保全部完成
	var fly_signals: Array[Signal] = []
	for task in tasks:
		var sig = controller.spawn_fly_item(task.item.item_data.icon, task.start_pos, end_pos, task.start_scale, Vector2(0.5, 0.5))
		fly_signals.append(sig)
	
	# 等待所有物品飞行到达
	for sig in fly_signals:
		await sig
	
	# 显示 switch item (可选，作为吞噬反馈)
	switch_item_root.visible = true
	var item_example = switch_item_root.get_node_or_null("Item_example")
	if item_example and not tasks.is_empty():
		item_example.texture = tasks[0].item.item_data.icon
	
	# 等待一小段时间后手柄下落
	await controller.get_tree().create_timer(0.1).timeout
	
	# 手柄下落
	controller._tween_switch(controller.recycle_switch, controller.SWITCH_OFF_Y)
	
	# 等待手柄落下
	await controller.get_tree().create_timer(0.2).timeout
	
	# 隐藏 switch item
	switch_item_root.visible = false
