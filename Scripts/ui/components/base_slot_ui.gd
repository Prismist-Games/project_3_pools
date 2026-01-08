class_name BaseSlotUI
extends Control

@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var lid: CanvasItem = find_child("*lid", true)

var is_locked: bool = false # 仅作为逻辑开关，不再关联盖子动画

func _ready() -> void:
	pass

func play_shake() -> void:
	if anim_player and anim_player.has_animation("shake"):
		anim_player.play("shake")
	elif anim_player and anim_player.has_animation("lid_shake"):
		anim_player.play("lid_shake")
