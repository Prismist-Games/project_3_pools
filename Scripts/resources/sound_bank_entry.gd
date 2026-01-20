@tool
extends Resource
class_name SoundBankEntry

## 音效条目资源
## 用于在 SoundBank 中定义单个音效的映射

@export var id: StringName
@export var stream: AudioStream

@export_range(-40.0, 6.0) var volume_db: float = 0.0

@export var play_delay: float = 0.0 ## 触发后的延迟播放时间（秒）
@export var target_duration: float = 0.0 ## 目标播放时长（0 = 使用原始时长，> 0 = 自动调整 pitch_scale 匹配此时长）

var bus: String = "SFX" ## 音频总线（动态从 AudioServer 获取）
@export_range(1, 32) var max_polyphony: int = 8 ## 同一音效最大同时播放数量（防止音效叠加过多）

## 动态生成属性列表，让 bus 显示为下拉菜单，选项从 AudioServer 获取
func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	
	# 获取所有可用的 Audio Bus
	var bus_count = AudioServer.get_bus_count()
	var bus_names: PackedStringArray = []
	for i in range(bus_count):
		bus_names.append(AudioServer.get_bus_name(i))
	
	# 创建枚举字符串 "Bus1,Bus2,Bus3"
	var enum_string = ",".join(bus_names)
	
	# 添加 bus 属性，使用 PROPERTY_HINT_ENUM
	properties.append({
		"name": "bus",
		"type": TYPE_STRING,
		"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_STORAGE,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": enum_string
	})
	
	return properties
