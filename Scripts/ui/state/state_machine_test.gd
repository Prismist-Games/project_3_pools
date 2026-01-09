extends Node

## 状态机集成测试脚本
##
## 按键触发不同的状态转换进行测试：
## - 1: Idle
## - 2: Submitting
## - 3: Recycling
## - 4: Drawing (with pool_index)
## - 5: Replacing (with source_pool_index)
## - ESC: 返回 Idle

var state_machine: Node = null

func _ready() -> void:
	# 获取状态机引用
	await get_tree().create_timer(0.5).timeout
	var game_2d_ui = get_tree().get_first_node_in_group("game_2d_ui")
	if game_2d_ui:
		state_machine = game_2d_ui.state_machine
		if state_machine:
			print("[StateTest] 状态机测试已就绪。按 1-5 测试状态转换。")
		else:
			push_error("[StateTest] 未找到状态机")
	else:
		push_error("[StateTest] 未找到 game_2d_ui")

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	
	if not state_machine:
		return
	
	match event.keycode:
		KEY_1:
			print("[StateTest] 转换到 Idle")
			state_machine.transition_to(&"Idle")
		KEY_2:
			print("[StateTest] 转换到 Submitting")
			state_machine.transition_to(&"Submitting")
		KEY_3:
			print("[StateTest] 转换到 Recycling")
			state_machine.transition_to(&"Recycling")
		KEY_4:
			print("[StateTest] 转换到 Drawing")
			state_machine.transition_to(&"Drawing", {"pool_index": 0})
		KEY_5:
			print("[StateTest] 转换到 Replacing")
			state_machine.transition_to(&"Replacing", {"source_pool_index": 0})
		KEY_ESCAPE:
			print("[StateTest] 返回 Idle")
			state_machine.transition_to(&"Idle")
