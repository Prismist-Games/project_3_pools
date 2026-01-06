@tool
extends Node2D

@onready var background_wall: Sprite2D = $Slot_background_wall
@onready var background_side: Sprite2D = $Slot_background_side
@onready var background_floor: Sprite2D = $Slot_background_floor
@export var color: Color = Color.WHITE
	#set(value):
		#color = value
		#background_wall.modulate = color
		#background_side.modulate = color
		#background_floor.modulate = color


func _ready() -> void:
	pass
