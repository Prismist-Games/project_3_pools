extends "res://scripts/ui/state/ui_state.gd"

## SubmittingState - 提交模式
##
## 触发: IdleState 下点击 Submit 开关
## 效果: 奖池锁定，背包多选，订单可交互

func enter(_payload: Dictionary = {}) -> void:
	GameManager.current_ui_mode = Constants.UIMode.SUBMIT
	InventorySystem.multi_selected_indices.clear()

func exit() -> void:
	InventorySystem.multi_selected_indices.clear()
	if GameManager.current_ui_mode == Constants.UIMode.SUBMIT:
		GameManager.current_ui_mode = Constants.UIMode.NORMAL

func can_transition_to(next_state: StringName) -> bool:
	# 可以取消回 Idle，或者提交成功后回 Idle
	return next_state == &"Idle"

func handle_input(event: InputEvent) -> bool:
	# 右键取消
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		machine.transition_to(&"Idle")
		return true
	return false
