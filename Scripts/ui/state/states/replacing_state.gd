extends "res://scripts/ui/state/ui_state.gd"

## ReplacingState - 待处理/替换新物品
##
## 触发: 抽奖后背包已满，物品进入 pending_items
## 效果: 奖池锁定，Submit 开关禁用，Recycle 开关可用
## 背包交互: 点击有物品格回收旧物并放入新物；空格自动放入

## 来源奖池索引（用于动画起点）
var source_pool_index: int = -1

func enter(payload: Dictionary = {}) -> void:
	source_pool_index = payload.get("source_pool_index", -1)

func exit() -> void:
	source_pool_index = -1

func can_transition_to(next_state: StringName) -> bool:
	# 只有 pending 清空才能回到 Idle
	if next_state == &"Idle":
		return InventorySystem.pending_items.is_empty()
	return true
