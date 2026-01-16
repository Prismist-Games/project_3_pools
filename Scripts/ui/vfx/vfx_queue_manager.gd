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

var _silhouette_shader: Shader = preload("res://assets/shaders/silhouette.gdshader")

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
		# 如果是合并，则不隐藏原本的图标，直到飞行物到达。
		# 如果是普通移入或替换，则隐藏原图标。
		if not task.get("is_merge", false):
			target_slot_node.hide_icon()
	
	# 如果有来源奖池槽位，处理推进动画
	var source_slot = task.get("source_lottery_slot")
	
	# 创建飞行精灵（从 lottery slot 飞出时播放 rarity 入场动画）
	var fly_sprite = _create_fly_sprite(item, start_pos, start_scale, source_slot != null)
	if not fly_sprite:
		if target_slot_node:
			target_slot_node.is_vfx_target = false
		return
	if source_slot and source_slot.has_method("hide_main_icon"):
		source_slot.hide_main_icon()
		if source_slot.has_method("play_queue_advance_anim"):
			source_slot.play_queue_advance_anim()
	
	# 获取目标位置
	var target_pos: Vector2 = task.get("target_pos", start_pos)
	var target_scale: Vector2 = task.get("target_scale", start_scale)
	
	# 执行飞行动画
	var rarity_sprite = fly_sprite.get_meta("rarity_sprite", null)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(fly_sprite, "global_position", target_pos, 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(fly_sprite, "global_scale", target_scale, 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# 同步 rarity 背景的动画
	if rarity_sprite:
		tween.tween_property(rarity_sprite, "global_position", target_pos, 0.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(rarity_sprite, "global_scale", target_scale, 0.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	await tween.finished
	
	# 还原插槽状态
	if target_slot_node:
		target_slot_node.is_vfx_target = false
		if target_slot_node.has_method("set_temp_hidden"):
			target_slot_node.set_temp_hidden(false)
	
	if source_slot and source_slot.get("is_vfx_source") != null:
		# 只有当队列中没有更多针对该槽位的任务时，才清除标志并刷新
		# 否则，保持锁定状态，直到最后一个飞行动画完成
		if not _has_more_tasks_for_source(source_slot):
			source_slot.is_vfx_source = false
			# 强制刷新待定队列显示，防止被 is_vfx_source 检查阻止
			if source_slot.has_method("update_pending_display") and InventorySystem:
				source_slot.update_pending_display(InventorySystem.pending_items)
	
	# 清理 rarity 相关资源
	var rarity_tween = fly_sprite.get_meta("rarity_tween", null)
	if rarity_tween:
		rarity_tween.kill()
	if rarity_sprite:
		rarity_sprite.queue_free()
	
	# 清理主精灵
	fly_sprite.queue_free()

## 执行飞入回收箱动画
func _execute_fly_to_recycle(task: Dictionary) -> void:
	var item = task.get("item")
	var start_pos: Vector2 = task.get("start_pos", Vector2.ZERO)
	var start_scale: Vector2 = task.get("start_scale", Vector2.ONE)
	var target_pos: Vector2 = task.get("target_pos", Vector2.ZERO)
	
	if not item:
		return
	
	# 来源槽位处理 (Lottery Slot or Inventory Slot)
	var source_lottery_slot = task.get("source_lottery_slot")
	
	# 创建飞行精灵（从 lottery slot 飞出时播放 rarity 入场动画）
	var fly_sprite = _create_fly_sprite(item, start_pos, start_scale, source_lottery_slot != null)
	if not fly_sprite:
		return
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
	
	# 获取回收箱图标节点（可选）
	var recycle_icon_node: Sprite2D = task.get("recycle_icon_node")
	
	# 飞向回收箱并适当缩小（不再缩小到 0，除非没有目标节点）
	var target_scale = Vector2(0.6, 0.6) if recycle_icon_node else Vector2.ZERO
	
	var rarity_sprite = fly_sprite.get_meta("rarity_sprite", null)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(fly_sprite, "global_position", target_pos, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(fly_sprite, "global_scale", target_scale, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# 同步 rarity 背景的动画
	if rarity_sprite:
		tween.tween_property(rarity_sprite, "global_position", target_pos, 0.3) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(rarity_sprite, "global_scale", target_scale, 0.3) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	await tween.finished
	
	# 如果有目标图标节点，更新它并让飞行物消失（通过透明度过渡更平滑）
	if recycle_icon_node:
		recycle_icon_node.texture = fly_sprite.texture
		recycle_icon_node.modulate.a = 1.0
		# 让飞行的 Sprite 瞬间消失
		fly_sprite.visible = false
	
	# 清理 rarity 相关资源
	var rarity_tween = fly_sprite.get_meta("rarity_tween", null)
	if rarity_tween:
		rarity_tween.kill()
	if rarity_sprite:
		rarity_sprite.queue_free()
	
	fly_sprite.queue_free()
	
	if source_slot_node:
		source_slot_node.is_vfx_target = false
	
	if source_lottery_slot:
		if source_lottery_slot.get("is_vfx_source") != null:
			if not _has_more_tasks_for_source(source_lottery_slot):
				source_lottery_slot.is_vfx_source = false

## 执行合成动画
func _execute_merge(_task: Dictionary) -> void:
	# TODO: 实现更精美的合成动画
	await get_tree().create_timer(0.2).timeout

## 执行通用飞行动画（例如物品移动）
func _execute_generic_fly(task: Dictionary) -> void:
	var item = task.get("item")
	var start_pos: Vector2 = task.get("start_pos")
	var end_pos: Vector2 = task.get("end_pos")
	var start_scale: Vector2 = task.get("start_scale", Vector2.ONE)
	var end_scale: Vector2 = task.get("end_scale", Vector2.ONE)
	var duration: float = task.get("duration", 0.4)
	
	# From Context
	var source_node = task.get("source_slot_node")
	var target_node = task.get("target_slot_node")
	
	if source_node:
		source_node.is_vfx_target = true
		source_node.hide_icon()
	if target_node:
		target_node.is_vfx_target = true
		# 如果是合并（由 _on_item_moved 传入），则不隐藏目标格图标
		if not task.get("is_merge", false):
			target_node.hide_icon()
		
	var sprite = _create_fly_sprite(item, start_pos, start_scale)
	var rarity_sprite = sprite.get_meta("rarity_sprite", null)
	var tween = create_tween().set_parallel(true)
	tween.tween_property(sprite, "global_position", end_pos, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "global_scale", end_scale, duration)
	
	# 同步 rarity 背景的动画
	if rarity_sprite:
		tween.tween_property(rarity_sprite, "global_position", end_pos, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(rarity_sprite, "global_scale", end_scale, duration)
	
	await tween.finished
	
	# 清理 rarity 相关资源
	var rarity_tween = sprite.get_meta("rarity_tween", null)
	if rarity_tween:
		rarity_tween.kill()
	if rarity_sprite:
		rarity_sprite.queue_free()
	
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
	
	# 获取起始比例，支持独立比例或统一比例
	var scale1: Vector2 = task.get("scale1", task.get("scale", Vector2(1.0, 1.0)))
	var scale2: Vector2 = task.get("scale2", task.get("scale", Vector2(1.0, 1.0)))
	
	# From Context
	var slot1 = task.get("slot1_node")
	var slot2 = task.get("slot2_node")
	
	if slot1:
		slot1.is_vfx_target = true
		slot1.hide_icon()
	if slot2:
		slot2.is_vfx_target = true
		slot2.hide_icon()
	
	var sprite1 = _create_fly_sprite(item1, pos1, scale1)
	var sprite2 = _create_fly_sprite(item2, pos2, scale2)
	
	var rarity_sprite1 = sprite1.get_meta("rarity_sprite", null)
	var rarity_sprite2 = sprite2.get_meta("rarity_sprite", null)
	
	var tween = create_tween().set_parallel(true)
	# 交换位置
	tween.tween_property(sprite1, "global_position", pos2, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(sprite2, "global_position", pos1, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	
	# 交换比例 (恢复到正常比例，这里简单假设 landing scale 为 1.0 对应的基准)
	# 如果有明确的 end_scale 也可以通过 task 传，但通常 Swap 是 Inventory 内操作，落地就是 1.0
	var landing_scale1 = task.get("end_scale1", Vector2.ONE)
	var landing_scale2 = task.get("end_scale2", Vector2.ONE)
	
	tween.tween_property(sprite1, "global_scale", landing_scale1, duration)
	tween.tween_property(sprite2, "global_scale", landing_scale2, duration)
	
	# 同步 rarity 背景的动画
	if rarity_sprite1:
		tween.tween_property(rarity_sprite1, "global_position", pos2, duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(rarity_sprite1, "global_scale", landing_scale1, duration)
	if rarity_sprite2:
		tween.tween_property(rarity_sprite2, "global_position", pos1, duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(rarity_sprite2, "global_scale", landing_scale2, duration)
	
	await tween.finished
	
	# 清理 rarity 相关资源
	var rarity_tween1 = sprite1.get_meta("rarity_tween", null)
	var rarity_tween2 = sprite2.get_meta("rarity_tween", null)
	if rarity_tween1:
		rarity_tween1.kill()
	if rarity_tween2:
		rarity_tween2.kill()
	if rarity_sprite1:
		rarity_sprite1.queue_free()
	if rarity_sprite2:
		rarity_sprite2.queue_free()
	
	sprite1.queue_free()
	sprite2.queue_free()
	
	if slot1:
		slot1.is_vfx_target = false
	if slot2:
		slot2.is_vfx_target = false

## 创建飞行精灵
## [param animate_rarity_entry]: 是否播放 rarity 背景的入场动画（从 lottery slot 飞出时为 true）
func _create_fly_sprite(item, start_pos: Vector2, start_scale: Vector2, animate_rarity_entry: bool = false) -> Sprite2D:
	if not vfx_layer:
		push_error("[VfxQueueManager] vfx_layer 未设置")
		return null
	
	# 创建主图标精灵
	var sprite = Sprite2D.new()
	if item.is_expired:
		sprite.texture = preload("res://assets/sprites/icons/items/item_trash.png")
	else:
		sprite.texture = item.item_data.icon
	sprite.global_position = start_pos
	sprite.global_scale = start_scale
	sprite.z_index = 100
	
	# 检查并应用绝育效果 (去色)
	var is_sterile: bool = false
	if item is ItemInstance:
		is_sterile = item.sterile
	elif item is Dictionary:
		is_sterile = item.get("sterile", false)
	elif "sterile" in item:
		is_sterile = item.sterile
		
	if is_sterile:
		var mat = ShaderMaterial.new()
		mat.shader = _silhouette_shader
		mat.set_shader_parameter("saturation", 0.0)
		# 确保不启用剪影模式（只用去色逻辑）
		mat.set_shader_parameter("is_enabled", false)
		sprite.material = mat
		
	vfx_layer.add_child(sprite)
	
	# 创建 rarity 背景（在图标后面）
	var rarity_sprite = Sprite2D.new()
	var rarity_texture = preload("res://assets/sprites/icons/item_rarity_glow.PNG")
	if rarity_texture:
		rarity_sprite.texture = rarity_texture
		rarity_sprite.self_modulate = Constants.get_rarity_border_color(item.rarity)
		rarity_sprite.global_position = start_pos
		rarity_sprite.z_index = 99 # 在图标后面
		
		# 根据来源决定是否播放入场动画
		if animate_rarity_entry:
			rarity_sprite.scale = Vector2.ZERO # 初始 scale 为 0 (局部) -> 入场动画还是用局部控制方便? NO, global consistent.
			rarity_sprite.global_scale = Vector2.ZERO
		else:
			rarity_sprite.global_scale = start_scale # 直接显示
		
		vfx_layer.add_child(rarity_sprite)
		
		# 如果需要入场动画，播放 scale 从 0 到 1 的动画
		if animate_rarity_entry:
			var scale_tween = create_tween()
			scale_tween.tween_property(rarity_sprite, "global_scale", start_scale, 0.05) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		
		# 开始旋转动画
		var rotation_tween = create_tween()
		rotation_tween.set_loops()
		# 使用 from(0.0) 确保每次循环都从 0 开始
		rotation_tween.tween_property(rarity_sprite, "rotation", TAU, 3.0) \
			.from(0.0) \
			.set_trans(Tween.TRANS_LINEAR)
		
		# 使用 metadata 存储引用，以便在删除时一起清理
		sprite.set_meta("rarity_sprite", rarity_sprite)
		sprite.set_meta("rarity_tween", rotation_tween)
	
	return sprite

## 检查队列中是否还有针对同一来源槽位的任务（用于平滑 state 切换）
func _has_more_tasks_for_source(source_node: Node) -> bool:
	for task in _queue:
		if task.get("source_lottery_slot") == source_node:
			return true
	return false
