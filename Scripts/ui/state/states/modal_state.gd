extends "res://scripts/ui/state/ui_state.gd"

## ModalState - 弹窗模式
##
## 触发: 技能选择 / Targeted 词缀选择类型
## 效果: 全 UI 锁定，仅弹窗内可交互

## 弹窗类型标识
var modal_type: StringName = &""

## 弹窗选项数据
var options: Array = []

## 选择结果回调
var on_select: Callable

## 选择完成后返回的状态
var return_state: StringName = &"Idle"

## 选择完成后传递的 payload
var return_payload: Dictionary = {}

func enter(payload: Dictionary = {}) -> void:
	modal_type = payload.get("modal_type", &"")
	options = payload.get("options", [])
	on_select = payload.get("on_select", Callable())
	return_state = payload.get("return_state", &"Idle")
	return_payload = payload.get("return_payload", {})

func exit() -> void:
	modal_type = &""
	options.clear()
	on_select = Callable()
	return_state = &"Idle"
	return_payload = {}

func can_transition_to(next_state: StringName) -> bool:
	# 只能转换到预设的返回状态
	return next_state == return_state or next_state == &"Idle" or next_state == &"Drawing"

## 处理选择结果
func select_option(index: int) -> void:
	if on_select.is_valid():
		on_select.call(index)
	
	# 转换到返回状态
	machine.transition_to(return_state, return_payload)

func handle_input(event: InputEvent) -> bool:
	# 技能选择允许右键取消，Targeted 选择不允许
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if modal_type == &"skill_select":
			machine.transition_to(&"Idle")
			return true
		elif modal_type == &"targeted_selection":
			return true # 消费事件但不取消
	return false
