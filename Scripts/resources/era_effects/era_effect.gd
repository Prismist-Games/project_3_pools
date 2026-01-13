extends Resource
class_name EraEffect

## 时代全局效果基类
## 每个时代可以有多个效果，通过继承此类实现具体逻辑

## 效果名称
@export var effect_name: String = ""

## 在时代开始时调用（用于初始化）
func on_era_start() -> void:
	pass

## 在时代结束时调用（用于清理）
func on_era_end() -> void:
	pass

## 获取效果描述（用于 UI 显示）
func get_description() -> String:
	return effect_name
