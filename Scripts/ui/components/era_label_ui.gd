extends Label

## 时代名称显示组件
## 监听 EraManager 的时代切换并更新显示

func _ready() -> void:
	if EraManager:
		EraManager.era_changed.connect(_on_era_changed)
		# 初始显示
		_update_display()


func _on_era_changed(_era_index: int) -> void:
	_update_display()


func _update_display() -> void:
	if not EraManager or not EraManager.current_config:
		text = ""
		return
	
	var cfg = EraManager.current_config
	text = cfg.era_name
