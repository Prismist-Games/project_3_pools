extends "res://scripts/ui/state/ui_state.gd"

## DrawingState - 抽奖中
##
## 触发: IdleState 下点击任意奖池
## 效果: 全 UI 锁定，等待动画完成
## 分支: 根据词缀类型转移到不同状态

## 当前抽奖的奖池索引
var pool_index: int = -1

## 抽奖是否完成（用于守卫转换）
var is_draw_complete: bool = false

func enter(payload: Dictionary = {}) -> void:
	pool_index = payload.get("pool_index", -1)
	is_draw_complete = false

func exit() -> void:
	pool_index = -1
	is_draw_complete = false

func can_transition_to(next_state: StringName) -> bool:
	# 必须等待抽奖完成才能转换
	# 例外：Modal 状态（Targeted 词缀需要弹窗选择）
	if next_state == &"Modal":
		return true
	return is_draw_complete

## 标记抽奖完成，允许状态转换
func mark_complete() -> void:
	is_draw_complete = true
