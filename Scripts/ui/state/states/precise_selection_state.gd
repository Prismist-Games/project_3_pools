extends "res://scripts/ui/state/ui_state.gd"

## PreciseSelectionState - 精准选择（二选一）
##
## 触发: 抽中精准词缀奖池，揭示两个选项后进入
## 效果: 借用 lottery_slot[0] 和 [1] 显示选项
## 强制性: 不允许右键取消

## 可选物品列表
var options: Array = []

## 选中的物品索引
var selected_index: int = -1

func enter(payload: Dictionary = {}) -> void:
	options = payload.get("options", [])
	selected_index = -1

func exit() -> void:
	options.clear()
	selected_index = -1

func can_transition_to(next_state: StringName) -> bool:
	# 必须完成选择才能退出（不允许取消）
	if next_state == &"Idle" or next_state == &"Replacing":
		return selected_index != -1
	return false

## 记录选择结果
func select_option(index: int) -> void:
	if index >= 0 and index < options.size():
		selected_index = index

func handle_input(event: InputEvent) -> bool:
	# 拦截右键，阻止取消
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		return true # 消费事件，阻止传递
	return false
