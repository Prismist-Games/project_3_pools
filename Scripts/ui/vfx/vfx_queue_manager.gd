class_name VfxQueueManager
extends Node

## VFX 队列管理器。
##
## 负责管理物品飞行动画的任务队列，确保动画按顺序执行。
## 已经与 Game2DUI 解耦，所有需要的上下文 (Context) 必须通过 task 字典传入。
##
## Task Dictionary Keys:
## - target_slot_node: Control (Inventory Slot Node)
## - source_slot_node: Control (Inventory Slot Node)
## - source_lottery_slot: Control (Lottery Slot Node)
## - on_complete: Callable (Usually triggers inventory refresh)

signal queue_started
signal queue_finished
signal task_started(task: Dictionary)
signal task_finished(task: Dictionary)

## VFX 任务队列
var _queue: Array[Dictionary] = []

## 是否正在处理队列
var _is_processing: bool = false

## 是否正在处理回收类任务
var _is_processing_recycle: bool = false

## 是否已调度处理（防止重复调度）
var _is_scheduled: bool = false

## 暂停队列处理（用于等待特定 UI 动画，如开盖）
var is_paused: bool = false

## VFX 层节点引用（用于创建飞行动画）
var vfx_layer: Node2D = null

## 引用到主控制器 (已移除，通过 task 传参)
# var controller: Node = null

## 检查队列是否繁忙
func is_busy() -> bool:
	return _is_processing or not _queue.is_empty()


## 检查是否有处于激活状态的回收任务 (队列中或进行中)
func has_active_recycle_tasks() -> bool:
	if _is_processing_recycle:
		return true
	for task in _queue:
		if task.get("type") == "fly_to_recycle":
			return true
	return false

## 入队一个 VFX 任务
func enqueue(task: Dictionary) -> void:
	_queue.append(task)
	_schedule_process()

## 批量入队
func enqueue_batch(tasks: Array[Dictionary]) -> void:
	_queue.append_array(tasks)
	_schedule_process()

## 清空队列（用于紧急中断）
func clear() -> void:
	_queue.clear()
	_is_processing = false
	_is_scheduled = false

## 调度队列处理
func _schedule_process() -> void:
	if _is_scheduled or _is_processing or is_paused:
		return
	
	_is_scheduled = true
	# 延迟一帧开始处理，确保调用方逻辑完成
	call_deferred("_process_queue")

## 恢复队列处理
func resume_process() -> void:
	is_paused = false
	_schedule_process()

## 处理队列
func _process_queue() -> void:
	_is_scheduled = false
	
	if _queue.is_empty():
		return
	
	if _is_processing:
		return
	
	_is_processing = true
	queue_started.emit()
	
	while not _queue.is_empty():
		var task = _queue.front()
		
		# 检查是否为回收任务，如果是则尝试并行处理
		if task.get("type", "") == "fly_to_recycle":
			var parallel_tasks = []
			# 连续收集所有回收任务
			while not _queue.is_empty() and _queue.front().get("type", "") == "fly_to_recycle":
				parallel_tasks.append(_queue.pop_front())
			
			# 并行执行所有回收动画
			_is_processing_recycle = true
			# 使用 Dictionary 包装计数器，以便 lambda 能够修改它
			var counter = {"count": parallel_tasks.size()}
			for p_task in parallel_tasks:
				task_started.emit(p_task)
				# 启动并行支流协程
				var run_task = func(t, c):
					await _execute_fly_to_recycle(t)
					c["count"] -= 1
				run_task.call(p_task, counter)
			
			# 等待所有动画协程完成
			while counter["count"] > 0:
				await get_tree().process_frame
			
			_is_processing_recycle = false
			# 统一执行完成回调
			for p_task in parallel_tasks:
				task_finished.emit(p_task)
				var on_complete_fn = p_task.get("on_complete")
				if on_complete_fn is Callable and on_complete_fn.is_valid():
					on_complete_fn.call()
			continue
		
		_queue.pop_front() # 非并行任务出队
		task_started.emit(task)
		
		# 根据任务类型执行对应动画
		var task_type = task.get("type", "")
		_is_processing_recycle = (task_type == "fly_to_recycle")
		
		match task_type:
			"fly_to_inventory":
				await _execute_fly_to_inventory(task)
			"fly_to_recycle":
				await _execute_fly_to_recycle(task)
			"merge":
				await _execute_merge(task)
			"generic_fly":
				await _execute_generic_fly(task)
			"swap":
				await _execute_swap(task)
			_:
				push_warning("[VfxQueueManager] 未知任务类型: %s" % task_type)
		
		_is_processing_recycle = false
		task_finished.emit(task)
		
		# 调用完成回调 (通常是 controller._on_inventory_changed)
		var on_complete = task.get("on_complete")
		if on_complete is Callable and on_complete.is_valid():
			on_complete.call()
	
	_is_processing = false
	queue_finished.emit()

## 执行飞入背包动画
func _execute_fly_to_inventory(task: Dictionary) -> void:
	var item = task.get("item")
	var start_pos: Vector2 = task.get("start_pos", Vector2.ZERO)
	var start_scale: Vector2 = task.get("start_scale", Vector2.ONE)
	
	# 获取目标槽位节点 (From Context)
	var target_slot_node: Control = task.get("target_slot_node")
	
	if target_slot_node:
		target_slot_node.is_vfx_target = true
		# 统一隐藏原图标，腾出位置给飞行 sprite。
		# 此前替换模式（is_replace）不隐藏会导致新旧物品在飞行过程中重叠。
		target_slot_node.hide_icon()
	
	# 创建飞行精灵
	var fly_sprite = _create_fly_sprite(item, start_pos, start_scale)
	if not fly_sprite:
		if target_slot_node:
			target_slot_node.is_vfx_target = false
		return
	
	# 如果有来源奖池槽位，处理推进动画
	var source_slot = task.get("source_lottery_slot")
	if source_slot and source_slot.has_method("hide_main_icon"):
		source_slot.hide_main_icon()
		if source_slot.has_method("play_queue_advance_anim"):
			source_slot.play_queue_advance_anim()
	
	# 获取目标位置
	var target_pos: Vector2 = task.get("target_pos", start_pos)
	var target_scale: Vector2 = task.get("target_scale", start_scale)
	
	# 执行飞行动画
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(fly_sprite, "global_position", target_pos, 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(fly_sprite, "scale", target_scale, 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	await tween.finished
	
	# 还原插槽状态
	if target_slot_node:
		target_slot_node.is_vfx_target = false
		# 解除临时隐藏状态 (如果存在)
		if target_slot_node.has_method("set_temp_hidden"):
			target_slot_node.set_temp_hidden(false)
		
		# 不再手动调用 show_icon()，交给后续的 update_display 处理
	
	# 清理
	fly_sprite.queue_free()

## 执行飞入回收箱动画
func _execute_fly_to_recycle(task: Dictionary) -> void:
	var item = task.get("item")
	var start_pos: Vector2 = task.get("start_pos", Vector2.ZERO)
	var start_scale: Vector2 = task.get("start_scale", Vector2.ONE)
	var target_pos: Vector2 = task.get("target_pos", Vector2.ZERO)
	
	if not item:
		return
	
	var fly_sprite = _create_fly_sprite(item, start_pos, start_scale)
	if not fly_sprite:
		return
	
	# 来源槽位处理 (Lottery Slot or Inventory Slot)
	var source_lottery_slot = task.get("source_lottery_slot")
	if source_lottery_slot:
		if source_lottery_slot.get("is_vfx_source") != null:
			source_lottery_slot.is_vfx_source = true
		if source_lottery_slot.has_method("hide_main_icon"):
			source_lottery_slot.hide_main_icon()
		if source_lottery_slot.has_method("play_queue_advance_anim"):
			source_lottery_slot.play_queue_advance_anim()
			
	var source_slot_node = task.get("source_slot_node")
	if source_slot_node:
		source_slot_node.is_vfx_target = true
		source_slot_node.hide_icon()
	
	# 飞向回收箱并缩小
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(fly_sprite, "global_position", target_pos, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(fly_sprite, "scale", Vector2.ZERO, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	await tween.finished
	fly_sprite.queue_free()
	
	if source_slot_node:
		source_slot_node.is_vfx_target = false
		# 不再手动调用 show_icon()
	
	if source_lottery_slot:
		if source_lottery_slot.get("is_vfx_source") != null:
			source_lottery_slot.is_vfx_source = false
		# 只有当 item_main 还有 texture 时才显示，防止回收最后一个物品后闪现空图标
		if source_lottery_slot.has_method("show_main_icon") and source_lottery_slot.item_main.texture != null:
			source_lottery_slot.show_main_icon()

## 执行合成动画
func _execute_merge(_task: Dictionary) -> void:
	# TODO: 实现更精美的合成动画
	await get_tree().create_timer(0.2).timeout

## 执行通用飞行动画（例如物品移动）
func _execute_generic_fly(task: Dictionary) -> void:
	var item = task.get("item")
	var start_pos: Vector2 = task.get("start_pos")
	var end_pos: Vector2 = task.get("end_pos")
	var start_scale: Vector2 = task.get("start_scale", Vector2(0.65, 0.65))
	var end_scale: Vector2 = task.get("end_scale", Vector2(0.65, 0.65))
	var duration: float = task.get("duration", 0.4)
	
	# From Context
	var source_node = task.get("source_slot_node")
	var target_node = task.get("target_slot_node")
	
	if source_node:
		source_node.is_vfx_target = true
		source_node.hide_icon()
	if target_node:
		target_node.is_vfx_target = true
		target_node.hide_icon()
		
	var sprite = _create_fly_sprite(item, start_pos, start_scale)
	var tween = create_tween().set_parallel(true)
	tween.tween_property(sprite, "global_position", end_pos, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "scale", end_scale, duration)
	
	await tween.finished
	sprite.queue_free()
	
	if source_node:
		source_node.is_vfx_target = false
	if target_node:
		target_node.is_vfx_target = false
		# 不再手动调用 show_icon()

## 执行交换动画
func _execute_swap(task: Dictionary) -> void:
	var item1 = task.get("item1")
	var item2 = task.get("item2")
	var pos1: Vector2 = task.get("pos1")
	var pos2: Vector2 = task.get("pos2")
	var duration: float = task.get("duration", 0.4)
	var scale: Vector2 = task.get("scale", Vector2(0.65, 0.65))
	
	# From Context
	var slot1 = task.get("slot1_node")
	var slot2 = task.get("slot2_node")
	
	if slot1:
		slot1.is_vfx_target = true
		slot1.hide_icon()
	if slot2:
		slot2.is_vfx_target = true
		slot2.hide_icon()
	
	var sprite1 = _create_fly_sprite(item1, pos1, scale)
	var sprite2 = _create_fly_sprite(item2, pos2, scale)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(sprite1, "global_position", pos2, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(sprite2, "global_position", pos1, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	
	await tween.finished
	sprite1.queue_free()
	sprite2.queue_free()
	
	if slot1:
		slot1.is_vfx_target = false
	if slot2:
		slot2.is_vfx_target = false

## 创建飞行精灵
func _create_fly_sprite(item, start_pos: Vector2, start_scale: Vector2) -> Sprite2D:
	if not vfx_layer:
		push_error("[VfxQueueManager] vfx_layer 未设置")
		return null
	
	var sprite = Sprite2D.new()
	sprite.texture = item.item_data.icon
	sprite.global_position = start_pos
	sprite.scale = start_scale
	sprite.z_index = 100
	vfx_layer.add_child(sprite)
	
	return sprite
