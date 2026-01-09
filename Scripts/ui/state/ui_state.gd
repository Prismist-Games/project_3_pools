class_name UIState
extends RefCounted

## UI 状态基类。
##
## 所有具体状态（IdleState, DrawingState 等）都继承自此类。
## 状态机持有当前状态的引用，并在转换时调用对应的生命周期方法。

## 状态机引用，由 UIStateMachine 在注册时设置
var machine: Node = null

## 状态名称，用于调试和日志
var state_name: StringName = &""

## 进入状态时调用
## payload: 可选的上下文数据，由触发转换的代码传入
func enter(_payload: Dictionary = {}) -> void:
	pass

## 退出状态时调用
func exit() -> void:
	pass

## 检查是否可以转换到目标状态
## 返回 false 可以阻止转换（例如动画未完成时）
func can_transition_to(_next_state: StringName) -> bool:
	return true

## 处理输入事件（可选覆盖）
## 返回 true 表示事件已被消费
func handle_input(_event: InputEvent) -> bool:
	return false

## 每帧更新（可选覆盖）
func process(_delta: float) -> void:
	pass
