extends Node

## AudioManager (Autoload)
## 核心音频管理器，负责 SFX 池化播放、音高随机化及 BGM 交叉淡入。

signal bgm_changed(bgm_id: StringName)

# --- 音量控制 ---
@export_range(0.0, 1.0) var master_volume: float = 1.0:
	set(v):
		master_volume = clamp(v, 0.0, 1.0)
		# 实际项目中这里可以操作 AudioServer.set_bus_volume_db
		_update_bus_volumes()

@export_range(0.0, 1.0) var sfx_volume: float = 1.0:
	set(v):
		sfx_volume = clamp(v, 0.0, 1.0)
		_update_bus_volumes()

@export_range(0.0, 1.0) var bgm_volume: float = 1.0:
	set(v):
		bgm_volume = clamp(v, 0.0, 1.0)
		_update_bus_volumes()

# --- SFX 池 ---
const SFX_POOL_SIZE: int = 12
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_registry: Dictionary = {} # StringName -> SoundBankEntry

# --- BGM ---
var _bgm_player_a: AudioStreamPlayer
var _bgm_player_b: AudioStreamPlayer
var _active_bgm_player: AudioStreamPlayer
var _bgm_registry: Dictionary = {} # StringName -> AudioStream

func _ready() -> void:
	_setup_sfx_pool()
	_setup_bgm_players()
	_connect_signals()

func _connect_signals() -> void:
	if EventBus.has_signal("game_event"):
		EventBus.game_event.connect(_on_game_event)

func _setup_sfx_pool() -> void:
	for i in range(SFX_POOL_SIZE):
		var player = AudioStreamPlayer.new()
		player.bus = &"SFX"
		add_child(player)
		_sfx_pool.append(player)

func _setup_bgm_players() -> void:
	_bgm_player_a = AudioStreamPlayer.new()
	_bgm_player_a.bus = &"Music"
	add_child(_bgm_player_a)
	
	_bgm_player_b = AudioStreamPlayer.new()
	_bgm_player_b.bus = &"Music"
	add_child(_bgm_player_b)
	
	_active_bgm_player = _bgm_player_a

# --- 公开方法 ---

## 注册音效库
func load_sound_bank(bank: SoundBank) -> void:
	if not bank: return
	for entry in bank.entries:
		if entry.id != &"":
			_sfx_registry[entry.id] = entry

## 播放音效
func play_sfx(sfx_id: StringName, override_pitch: float = 0.0) -> void:
	if not _sfx_registry.has(sfx_id):
		# 可以在这里根据需要决定是否 push_warning
		return
	
	var entry: SoundBankEntry = _sfx_registry[sfx_id]
	if not entry.stream: return
	
	var player = _get_idle_sfx_player()
	
	player.stream = entry.stream
	player.volume_db = entry.volume_db
	
	# 音高随机化
	if override_pitch > 0:
		player.pitch_scale = override_pitch
	else:
		var variance = entry.pitch_variance
		player.pitch_scale = 1.0 + randf_range(-variance, variance)
		
	player.play()

## 注册 BGM
func register_bgm(bgm_id: StringName, stream: AudioStream) -> void:
	_bgm_registry[bgm_id] = stream

## 播放背景音乐 (通过 ID)
func play_bgm_by_id(bgm_id: StringName, fade_duration: float = 1.0) -> void:
	if _bgm_registry.has(bgm_id):
		play_bgm(_bgm_registry[bgm_id], fade_duration)
		bgm_changed.emit(bgm_id)
	else:
		push_warning("AudioManager: BGM ID 未找到: ", bgm_id)

## 播放背景音乐 (支持平滑切换)
func play_bgm(bgm_stream: AudioStream, fade_duration: float = 1.0) -> void:
	if not bgm_stream: return
	
	var next_player = _bgm_player_b if _active_bgm_player == _bgm_player_a else _bgm_player_a
	next_player.stream = bgm_stream
	next_player.volume_db = -80.0
	next_player.play()
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(_active_bgm_player, "volume_db", -80.0, fade_duration)
	tween.tween_property(next_player, "volume_db", 0.0, fade_duration)
	
	await tween.finished
	_active_bgm_player.stop()
	_active_bgm_player = next_player

# --- 信号回调 ---

func _on_game_event(event_id: StringName, _context: RefCounted) -> void:
	# 自动尝试播放与事件同名的音效
	if _sfx_registry.has(event_id):
		play_sfx(event_id)

# --- 内部工具 ---

func _get_idle_sfx_player() -> AudioStreamPlayer:
	# 寻找当前不在播放的播放器
	for player in _sfx_pool:
		if not player.playing:
			return player
	# 如果全都在播放，强制抢占第一个（最老的）
	return _sfx_pool[0]

func _update_bus_volumes() -> void:
	# 这里后续可以连接到 AudioServer 
	# 目前先简单占位
	pass
