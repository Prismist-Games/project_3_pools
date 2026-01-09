extends "res://scripts/ui/state/ui_state.gd"

## TradeInState - 以旧换新（词缀触发）
##
## 触发: DrawingState 中抽到 Trade-in 词缀池揭示后进入
## 效果: 奖池、订单、模式切换均锁定，仅背包可交互
## 交互: 点击背包物品 -> 回收该物品，获得同品质随机新物品

## 将要获得的新物品（由词缀逻辑预生成）
var pending_new_item: Variant = null

## 来源奖池索引
var source_pool_index: int = -1

func enter(payload: Dictionary = {}) -> void:
	pending_new_item = payload.get("new_item")
	source_pool_index = payload.get("source_pool_index", -1)
	GameManager.current_ui_mode = Constants.UIMode.REPLACE

func exit() -> void:
	pending_new_item = null
	source_pool_index = -1
	if GameManager.current_ui_mode == Constants.UIMode.REPLACE:
		GameManager.current_ui_mode = Constants.UIMode.NORMAL

func can_transition_to(next_state: StringName) -> bool:
	return next_state == &"Idle"

func handle_input(event: InputEvent) -> bool:
	# 右键取消（放弃本次 Trade-in）
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		machine.transition_to(&"Idle")
		return true
	return false
