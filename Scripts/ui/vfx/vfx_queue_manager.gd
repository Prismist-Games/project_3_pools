class_name VfxQueueManager
extends Node

## VFX 队列管理器。
##
## 负责管理物品飞行动画的任务队列，确保动画按顺序执行。
## 从 game_2d_ui.gd 中提取的核心 VFX 逻辑。

signal queue_started
signal queue_finished
signal task_started(task: Dictionary)
signal task_finished(task: Dictionary)

## VFX 任务队列
var _queue: Array[Dictionary] = []

## 是否正在处理队列
var _is_processing: bool = false

## 是否已调度处理（防止重复调度）
var _is_scheduled: bool = false

## VFX 层节点引用（用于创建飞行动画）
var vfx_layer: Node2D = null

## 检查队列是否繁忙
func is_busy() -> bool:
	return _is_processing or not _queue.is_empty()

## 入队一个 VFX 任务
## task 结构:
## {
##   "type": "fly_to_inventory" | "fly_to_recycle" | "merge" | ...
##   "item": ItemInstance,
##   "start_pos": Vector2,
##   "start_scale": Vector2,
##   "target_slot": int,  # 目标背包格索引
##   "on_complete": Callable,  # 可选回调
## }
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
	if _is_scheduled or _is_processing:
		return
	
	_is_scheduled = true
	# 延迟一帧开始处理，确保调用方逻辑完成
	call_deferred("_process_queue")

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
		var task = _queue.pop_front()
		task_started.emit(task)
		
		# 根据任务类型执行对应动画
		match task.get("type", ""):
			"fly_to_inventory":
				await _execute_fly_to_inventory(task)
			"fly_to_recycle":
				await _execute_fly_to_recycle(task)
			"merge":
				await _execute_merge(task)
			_:
				push_warning("[VfxQueueManager] 未知任务类型: %s" % task.get("type"))
		
		task_finished.emit(task)
		
		# 调用完成回调
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
	var target_slot: int = task.get("target_slot", -1)
	
	if not item or target_slot < 0:
		return
	
	# 创建飞行精灵
	var fly_sprite = _create_fly_sprite(item, start_pos, start_scale)
	if not fly_sprite:
		return
	
	# 获取目标位置（需要外部提供获取方法）
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
	
	# 飞向回收箱并缩小
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(fly_sprite, "global_position", target_pos, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(fly_sprite, "scale", Vector2.ZERO, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	await tween.finished
	fly_sprite.queue_free()

## 执行合成动画
func _execute_merge(_task: Dictionary) -> void:
	# TODO: 实现合成动画
	await get_tree().create_timer(0.2).timeout

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
