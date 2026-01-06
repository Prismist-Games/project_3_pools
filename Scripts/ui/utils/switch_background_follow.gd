@tool
extends Node2D

@export var background_up: Sprite2D
@export var background_up_offset: float
@export var background_down: Sprite2D
@export var background_down_offset: float

func _ready() -> void:
	# 开启变换通知，只有当位置/旋转/缩放发生变化时才会触发 NOTIFICATION_TRANSFORM_CHANGED
	set_notify_transform(true)
	# 初始化时更新一次位置
	_update_background_positions()

func _notification(what: int) -> void:
	# 当变换（Transform）发生改变时触发
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_update_background_positions()

func _update_background_positions() -> void:
	# 检查节点是否有效，防止报错
	if is_instance_valid(background_up):
		background_up.position.y = position.y - background_up_offset
	
	if is_instance_valid(background_down):
		background_down.position.y = position.y - background_down_offset
