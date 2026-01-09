extends "res://scripts/ui/state/ui_state.gd"

## TradeInState - 以旧换新（词缀触发）
##
## 触发: DrawingState 中抽到 Trade-in 词缀池揭示后进入
## 效果: 奖池、订单、模式切换均锁定，仅背包可交互
## 交互: 点击背包物品 -> 回收该物品，获得同品质随机新物品

## 引用到主控制器
var controller: Node = null

## 来源奖池 ID
var pool_id: StringName = &""

## 置换逻辑回调 (来自 AffixEffect)
var on_trade_callback: Callable

func enter(payload: Dictionary = {}) -> void:
	pool_id = payload.get("pool_id", &"")
	on_trade_callback = payload.get("callback", Callable())
	
	if controller:
		controller.lock_ui("trade_in")
	
	# 进入 REPLACE 视觉模式 (高亮背包) - state machine now reflects 'TradeIn' state
	pass

func exit() -> void:
	if controller:
		controller.unlock_ui("trade_in")
		
	pool_id = &""
	on_trade_callback = Callable()

func can_transition_to(_next_state: StringName) -> bool:
	return true

## 被 game_2d_ui.gd 重定向的点击事件
func select_slot(index: int) -> void:
	var item = InventorySystem.inventory[index]
	if item == null:
		return
		
	# 主线物品不可置换
	if item.item_data.is_mainline:
		return
		
	# 执行置换回调
	if on_trade_callback.is_valid():
		on_trade_callback.call(item)
		
	# 置换后返回 Idle
	machine.transition_to(&"Idle")

func handle_input(event: InputEvent) -> bool:
	# 右键取消（放弃本次 Trade-in）
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		machine.transition_to(&"Idle")
		return true
	return false
