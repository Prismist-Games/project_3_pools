extends "res://scripts/ui/state/ui_state.gd"

## RecyclingState - 回收模式（批量）
##
## 触发: IdleState 下无选中且无 Pending 时点击 Recycle 开关
## 效果: 奖池锁定，订单锁定，背包多选

func enter(_payload: Dictionary = {}) -> void:
	GameManager.current_ui_mode = Constants.UIMode.RECYCLE
	InventorySystem.multi_selected_indices.clear()

func exit() -> void:
	InventorySystem.multi_selected_indices.clear()
	if GameManager.current_ui_mode == Constants.UIMode.RECYCLE:
		GameManager.current_ui_mode = Constants.UIMode.NORMAL

func can_transition_to(next_state: StringName) -> bool:
	return next_state == &"Idle"

func handle_input(event: InputEvent) -> bool:
	# 右键取消
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		machine.transition_to(&"Idle")
		return true
	return false
