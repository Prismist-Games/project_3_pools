extends Resource
class_name SoundBankEntry

## 音效条目资源
## 用于在 SoundBank 中定义单个音效的映射

@export var id: StringName
@export var stream: AudioStream
@export_range(-40.0, 6.0) var volume_db: float = 0.0
@export_range(0.0, 0.5) var pitch_variance: float = 0.05
