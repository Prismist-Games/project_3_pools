extends "res://scripts/ui/state/ui_state.gd"

## IdleState - 整理模式（默认状态）
##
## 触发: 游戏启动默认 / 从其他状态取消退出
## 效果: 背包、奖池、模式开关均可交互

func enter(_payload: Dictionary = {}) -> void:
	# 确保 UI 模式同步
	if GameManager.current_ui_mode != Constants.UIMode.NORMAL:
		GameManager.current_ui_mode = Constants.UIMode.NORMAL
	
	# 清理可能残留的选择状态
	InventorySystem.multi_selected_indices.clear()

func can_transition_to(_next_state: StringName) -> bool:
	# Idle 状态可以转换到任何状态
	return true
