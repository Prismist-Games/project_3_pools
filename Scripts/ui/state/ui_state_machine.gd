class_name UIStateMachine
extends Node

## UI 状态机核心。
##
## 管理 UI 状态的注册、转换和生命周期。
## 作为 Game2D 场景的子节点使用。

signal state_changed(from_state: StringName, to_state: StringName)

## 当前激活的状态（UIState 实例）
var current_state: RefCounted = null

## 正在切换中的目标状态名
var pending_state_name: StringName = &""

## 已注册的状态字典: StringName -> UIState
var _states: Dictionary = {}

## 状态历史（用于调试）
var _history: Array[StringName] = []
const MAX_HISTORY_SIZE: int = 10

func _ready() -> void:
	set_process(false) # 默认关闭，只有需要 process 的状态才开启

func _process(delta: float) -> void:
	if current_state and current_state.has_method("process"):
		current_state.process(delta)

## 注册一个状态
func register_state(state_name: StringName, state: RefCounted) -> void:
	state.machine = self
	state.state_name = state_name
	_states[state_name] = state

## 获取已注册的状态
func get_state(state_name: StringName) -> RefCounted:
	return _states.get(state_name)

## 检查当前是否处于指定状态
func is_in_state(state_name: StringName) -> bool:
	return current_state != null and current_state.state_name == state_name

## 获取当前状态实例
func get_current_state() -> RefCounted:
	return current_state

## 获取当前状态名
func get_current_state_name() -> StringName:
	if current_state:
		return current_state.state_name
	return &""

## 转换到目标状态
## 返回 true 表示转换成功
func transition_to(state_name: StringName, payload: Dictionary = {}) -> bool:
	if not _states.has(state_name):
		push_error("[UIStateMachine] 未注册的状态: %s" % state_name)
		return false
	
	var next_state: RefCounted = _states[state_name]
	
	# 检查转换守卫
	if current_state and current_state.has_method("can_transition_to"):
		if not current_state.can_transition_to(state_name):
			push_warning("[UIStateMachine] 转换被拒绝: %s -> %s" % [current_state.state_name, state_name])
			return false
	
	pending_state_name = state_name
	var from_state_name: StringName = &""
	
	# 退出当前状态
	if current_state:
		from_state_name = current_state.state_name
		if current_state.has_method("exit"):
			current_state.exit()
	
	# 记录历史
	if from_state_name != &"":
		_history.append(from_state_name)
		if _history.size() > MAX_HISTORY_SIZE:
			_history.pop_front()
	
	# 进入新状态
	current_state = next_state
	if current_state.has_method("enter"):
		current_state.enter(payload)
	
	# 发出信号
	state_changed.emit(from_state_name, state_name)
	
	# 同步更新 GameManager.current_ui_mode（供技能系统等使用）
	GameManager.current_ui_mode = get_mode_from_state(state_name)
	
	# 转换完成，清除挂起状态
	pending_state_name = &""
	
	# 调试日志
	var from_str = str(from_state_name) if from_state_name != &"" else "(none)"
	print("[UIStateMachine] %s -> %s" % [from_str, state_name])
	
	return true

## 强制设置状态（跳过守卫检查，仅用于初始化）
func force_set_state(state_name: StringName, payload: Dictionary = {}) -> void:
	if not _states.has(state_name):
		push_error("[UIStateMachine] 未注册的状态: %s" % state_name)
		return
	
	if current_state and current_state.has_method("exit"):
		current_state.exit()
	
	current_state = _states[state_name]
	if current_state.has_method("enter"):
		current_state.enter(payload)
	
	# 同步更新 GameManager.current_ui_mode
	GameManager.current_ui_mode = get_mode_from_state(state_name)

## 转发输入事件到当前状态
func handle_input(event: InputEvent) -> bool:
	if current_state and current_state.has_method("handle_input"):
		return current_state.handle_input(event)
	return false

## 根据当前状态获取对应的 UIMode
func get_ui_mode() -> Constants.UIMode:
	if not current_state:
		return Constants.UIMode.NORMAL
	return get_mode_from_state(current_state.state_name)

## 静态映射：状态名 -> UIMode
func get_mode_from_state(state_name: StringName) -> Constants.UIMode:
	match state_name:
		&"Submitting":
			return Constants.UIMode.SUBMIT
		&"EraSubmitting":
			return Constants.UIMode.ERA_SUBMIT
		&"Recycling":
			return Constants.UIMode.RECYCLE
		&"TradeIn":
			return Constants.UIMode.REPLACE
		&"PreciseSelection", &"TargetedSelection":
			return Constants.UIMode.LOCKED
		_:
			return Constants.UIMode.NORMAL
