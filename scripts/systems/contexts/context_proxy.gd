extends RefCounted
class_name ContextProxy

## 用于在信号中传递可修改的简单键值对。
## 解决 Dictionary 不是 RefCounted 导致无法在某些信号中传递的问题。

var data: Dictionary = {}

func _init(initial_data: Dictionary = {}) -> void:
	data = initial_data

func get_value(key: StringName, default: Variant = null) -> Variant:
	return data.get(key, default)

func set_value(key: StringName, value: Variant) -> void:
	data[key] = value

func has_key(key: StringName) -> bool:
	return data.has(key)

func get_all() -> Dictionary:
	return data






