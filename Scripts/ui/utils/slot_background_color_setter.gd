@tool
extends Node2D

@onready var background_wall: Sprite2D = $Slot_background_wall
@onready var background_side: Sprite2D = $Slot_background_side
@onready var background_floor: Sprite2D = $Slot_background_floor

@export var color: Color = Color.WHITE:
	set(value):
		color = value
		_update_colors()

func _ready() -> void:
	_update_colors()

func _update_colors() -> void:
	# 检查节点是否有效，防止在 _ready 之前（此时 @onready 变量尚未赋值）调用 setter 导致空引用报错
	if is_instance_valid(background_wall):
		background_wall.modulate = color
	if is_instance_valid(background_side):
		background_side.modulate = color
	if is_instance_valid(background_floor):
		background_floor.modulate = color
