extends Resource
class_name SoundBankEntry

## 音效条目资源
## 用于在 SoundBank 中定义单个音效的映射

@export var id: StringName
@export var stream: AudioStream

@export_group("音量与音高")
@export_range(-40.0, 6.0) var volume_db: float = 0.0
@export_range(0.0, 0.5) var pitch_variance: float = 0.05 ## 随机音高偏移范围
@export var target_duration: float = 0.0 ## 目标播放时长（0 = 使用原始时长，> 0 = 自动调整 pitch_scale 匹配此时长）

@export_group("高级设置")
@export var bus: StringName = &"SFX" ## 音频总线（如 "SFX", "UI", "Ambient"）
@export_range(1, 32) var max_polyphony: int = 8 ## 同一音效最大同时播放数量（防止音效叠加过多）
