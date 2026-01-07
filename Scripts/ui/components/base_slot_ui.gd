class_name BaseSlotUI
extends Control

@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var lid: CanvasItem = find_child("*lid", true)

var is_locked: bool = false:
	set(value):
		if is_locked == value: return
		is_locked = value
		_update_lid_state()

func _ready() -> void:
	_update_lid_state()

func _update_lid_state() -> void:
	if not anim_player: return
	
	if is_locked:
		if anim_player.has_animation("lid_close"):
			anim_player.play("lid_close")
	else:
		if anim_player.has_animation("lid_open"):
			anim_player.play("lid_open")

func play_shake() -> void:
	if anim_player and anim_player.has_animation("shake"):
		anim_player.play("shake")
	elif anim_player and anim_player.has_animation("lid_shake"):
		anim_player.play("lid_shake")
