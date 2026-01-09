extends Node

## UI 状态机初始化器。
##
## 作为 Game2D 场景的子节点，负责创建和注册所有 UI 状态。
## 将状态机与 game_2d_ui.gd 解耦。

const UIStateMachineScript = preload("res://scripts/ui/state/ui_state_machine.gd")

const IdleState = preload("res://scripts/ui/state/states/idle_state.gd")
const DrawingState = preload("res://scripts/ui/state/states/drawing_state.gd")
const ReplacingState = preload("res://scripts/ui/state/states/replacing_state.gd")
const PreciseSelectionState = preload("res://scripts/ui/state/states/precise_selection_state.gd")
const SubmittingState = preload("res://scripts/ui/state/states/submitting_state.gd")
const RecyclingState = preload("res://scripts/ui/state/states/recycling_state.gd")
const TradeInState = preload("res://scripts/ui/state/states/tradein_state.gd")
const ModalState = preload("res://scripts/ui/state/states/modal_state.gd")

var state_machine: Node = null

func _ready() -> void:
	# 动态查找或创建状态机节点
	state_machine = get_parent().get_node_or_null("UIStateMachine")
	if not state_machine:
		state_machine = UIStateMachineScript.new()
		state_machine.name = "UIStateMachine"
		get_parent().add_child(state_machine)
	
	_register_states()
	
	# 设置初始状态
	state_machine.force_set_state(&"Idle")

func _register_states() -> void:
	state_machine.register_state(&"Idle", IdleState.new())
	state_machine.register_state(&"Drawing", DrawingState.new())
	state_machine.register_state(&"Replacing", ReplacingState.new())
	state_machine.register_state(&"PreciseSelection", PreciseSelectionState.new())
	state_machine.register_state(&"Submitting", SubmittingState.new())
	state_machine.register_state(&"Recycling", RecyclingState.new())
	state_machine.register_state(&"TradeIn", TradeInState.new())
	state_machine.register_state(&"Modal", ModalState.new())
	
	print("[UIStateInitializer] 已注册 %d 个状态" % state_machine._states.size())
