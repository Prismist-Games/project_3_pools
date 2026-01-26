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
var _active_sounds: Dictionary = {} # StringName -> Array[AudioStreamPlayer] (追踪每个音效的活跃播放器)

# --- BGM ---
var _bgm_player_a: AudioStreamPlayer
var _bgm_player_b: AudioStreamPlayer
var _active_bgm_player: AudioStreamPlayer
var _bgm_registry: Dictionary = {} # StringName -> AudioStream

# --- Rarity Reveal 音效控制 ---
var _current_rarity_reveal_player: AudioStreamPlayer = null
var _rarity_complete_player: AudioStreamPlayer = null # 专用播放器，不会被抢占


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
	
	# 创建专用的 rarity complete 播放器（不会被池抢占）
	_rarity_complete_player = AudioStreamPlayer.new()
	_rarity_complete_player.bus = &"SFX"
	add_child(_rarity_complete_player)


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
	
	# 如果音效库配置了自动扫描路径，先执行扫描以加载条目
	if bank.has_method("load_from_dir") and not bank.scan_path.is_empty():
		bank.load_from_dir()
		
	for entry in bank.entries:
		if entry.id != &"":
			_sfx_registry[entry.id] = entry

## 播放音效
func play_sfx(sfx_id: StringName, override_pitch: float = 0.0) -> void:
	if not _sfx_registry.has(sfx_id):
		return
	
	var entry: SoundBankEntry = _sfx_registry[sfx_id]
	if not entry.stream: return
	
	# 如果有延迟设置，启动延迟处理
	if entry.play_delay > 0.0:
		get_tree().create_timer(entry.play_delay).timeout.connect(
			func(): _internal_do_play_sfx(sfx_id, entry, override_pitch)
		)
	else:
		_internal_do_play_sfx(sfx_id, entry, override_pitch)

## 内部实际执行播放的逻辑
func _internal_do_play_sfx(sfx_id: StringName, entry: SoundBankEntry, override_pitch: float) -> void:
	# 限制最大同时播放数量
	if not _active_sounds.has(sfx_id): _active_sounds[sfx_id] = []
	var active_players: Array = _active_sounds[sfx_id]
	active_players = active_players.filter(func(p): return p.playing)
	_active_sounds[sfx_id] = active_players
	if active_players.size() >= entry.max_polyphony:
		var oldest = active_players[0] as AudioStreamPlayer
		oldest.stop()
		active_players.remove_at(0)
	
	var player = _get_idle_sfx_player()
	player.stream = entry.stream
	player.volume_db = entry.volume_db
	player.bus = entry.bus
	
	# --- 计算最终音高 ---
	var final_pitch: float = 1.0
	
	if override_pitch > 0:
		final_pitch = override_pitch
	elif entry.target_duration > 0.0:
		var original_length = entry.stream.get_length()
		if original_length > 0.0:
			final_pitch = original_length / entry.target_duration
	
	# 最后加上随机偏移
	# Pitch variance removed as requested
	player.pitch_scale = final_pitch
	
	player.play()
	active_players.append(player)

## 播放音效并匹配指定时长
func play_sfx_timed(sfx_id: StringName, target_duration: float) -> void:
	if not _sfx_registry.has(sfx_id): return
	var entry: SoundBankEntry = _sfx_registry[sfx_id]
	if not entry.stream: return
	
	var player = _get_idle_sfx_player()
	player.stream = entry.stream
	player.volume_db = entry.volume_db
	player.bus = entry.bus
	
	var original_length = entry.stream.get_length()
	if original_length > 0 and target_duration > 0:
		var base_p = original_length / target_duration
		player.pitch_scale = base_p
	else:
		player.pitch_scale = 1.0
	
	player.play()

## 播放音效并通过 Pitch Shift Bus 调整音调
## 播放音效并直接设置音调 (修复 WebGL 不支持 Bus Effect Pitch Shift 的问题)
func play_sfx_with_pitch(sfx_id: StringName, pitch_scale: float) -> void:
	if not _sfx_registry.has(sfx_id):
		return
	
	var entry: SoundBankEntry = _sfx_registry[sfx_id]
	if not entry.stream:
		return
	
	var player = _get_idle_sfx_player()
	player.stream = entry.stream
	player.volume_db = entry.volume_db
	
	# 直接使用 entries 中定义的 Bus，不再强制使用 RarityReveal Bus
	player.bus = entry.bus
	# 直接设置 pitch_scale (改变播放速度和音调)，这种方式在 WebGL 上更稳定
	player.pitch_scale = pitch_scale
	
	player.play()
	
	# 记录最后一个播放器（用于完成音效等待）
	_current_rarity_reveal_player = player

## 根据品质播放揭示完成音效
## 可配置不同品质的完成音效 ID：rarity_complete_common, rarity_complete_rare, 等等
func play_rarity_reveal_complete(rarity: int) -> AudioStreamPlayer:
	# 等待最后一个 rarity reveal 音效播放完成
	if _current_rarity_reveal_player and is_instance_valid(_current_rarity_reveal_player):
		if _current_rarity_reveal_player.playing:
			# 等待播放器自然播放完成
			await _current_rarity_reveal_player.finished
		_current_rarity_reveal_player = null
	
	var sfx_id: StringName
	
	match rarity:
		Constants.Rarity.COMMON:
			sfx_id = &"rarity_complete_common"
		Constants.Rarity.UNCOMMON:
			sfx_id = &"rarity_complete_uncommon"
		Constants.Rarity.RARE:
			sfx_id = &"rarity_complete_rare"
		Constants.Rarity.EPIC:
			sfx_id = &"rarity_complete_epic"
		Constants.Rarity.LEGENDARY:
			sfx_id = &"rarity_complete_legendary"
		Constants.Rarity.MYTHIC:
			sfx_id = &"rarity_complete_mythic"
		_:
			sfx_id = &"rarity_complete_common" # 默认
	
	# 使用专用播放器播放完成音效（不会被池抢占）
	if not _sfx_registry.has(sfx_id):
		return null
	
	var entry: SoundBankEntry = _sfx_registry[sfx_id]
	if not entry.stream:
		return null
	
	# 如果上一个完成音效还在播放，让它继续（不强制停止）
	# 使用专用播放器确保不会被其他音效抢占
	_rarity_complete_player.stream = entry.stream
	_rarity_complete_player.volume_db = entry.volume_db
	_rarity_complete_player.bus = entry.bus
	_rarity_complete_player.pitch_scale = 1.0
	_rarity_complete_player.play()
	
	return _rarity_complete_player


## 播放循环音效（返回播放器引用以便后续控制）
## 使用专用的 "RarityReveal" Bus 来支持 Pitch Shift 效果
func play_sfx_looping(sfx_id: StringName, initial_pitch: float = 1.0) -> AudioStreamPlayer:
	if not _sfx_registry.has(sfx_id):
		return null
	
	var entry: SoundBankEntry = _sfx_registry[sfx_id]
	if not entry.stream:
		return null
	
	var player = _get_idle_sfx_player()
	player.stream = entry.stream
	player.volume_db = entry.volume_db
	
	# 使用专门的 "RarityReveal" Bus（需要在项目中配置 Pitch Shift 效果）
	player.bus = &"RarityReveal"
	player.pitch_scale = 1.0 # 保持为 1.0，通过 Bus 效果调整音调
	
	# 初始化 Bus 的 Pitch Shift 效果
	_set_bus_pitch_shift(&"RarityReveal", initial_pitch)
	
	player.play()
	return player

## 调整 Bus 的 Pitch Shift 效果（带平滑过渡）
func set_sfx_pitch(player: AudioStreamPlayer, target_pitch: float, duration: float = 0.1) -> void:
	if not player or not is_instance_valid(player):
		return
	
	# 确认使用的是 RarityReveal Bus
	if player.bus != &"RarityReveal":
		push_warning("AudioManager: set_sfx_pitch called on player not using RarityReveal bus")
		return
	
	# 通过 Bus 的 Pitch Shift 效果调整音调
	if duration <= 0:
		_set_bus_pitch_shift(&"RarityReveal", target_pitch)
	else:
		# 平滑过渡音调
		var bus_idx = AudioServer.get_bus_index(&"RarityReveal")
		if bus_idx < 0:
			return
			
		var effect_idx = _get_pitch_shift_effect_index(bus_idx)
		if effect_idx < 0:
			return
		
		var effect = AudioServer.get_bus_effect(bus_idx, effect_idx)
		if effect is AudioEffectPitchShift:
			var current_pitch = effect.pitch_scale
			var tween = create_tween()
			tween.tween_method(
				func(p: float): _set_bus_pitch_shift(&"RarityReveal", p),
				current_pitch,
				target_pitch,
				duration
			).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## 停止循环音效（带淡出）
func stop_sfx_looping(player: AudioStreamPlayer, fade_duration: float = 0.2) -> void:
	if not player or not is_instance_valid(player) or not player.playing:
		return
	
	if fade_duration <= 0:
		player.stop()
	else:
		var original_volume = player.volume_db
		var tween = create_tween()
		tween.tween_property(player, "volume_db", -80.0, fade_duration)
		tween.tween_callback(func():
			player.stop()
			player.volume_db = original_volume # 恢复原始音量供下次使用
		)

## 内部方法：设置指定 Bus 的 Pitch Shift 效果
func _set_bus_pitch_shift(bus_name: StringName, pitch_scale: float) -> void:
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx < 0:
		push_warning("AudioManager: Bus '%s' not found" % bus_name)
		return
	
	var effect_idx = _get_pitch_shift_effect_index(bus_idx)
	if effect_idx < 0:
		push_warning("AudioManager: No PitchShift effect found on bus '%s'" % bus_name)
		return
	
	var effect = AudioServer.get_bus_effect(bus_idx, effect_idx)
	if effect is AudioEffectPitchShift:
		effect.pitch_scale = pitch_scale

## 内部方法：获取 Bus 上的 Pitch Shift 效果索引
func _get_pitch_shift_effect_index(bus_idx: int) -> int:
	var effect_count = AudioServer.get_bus_effect_count(bus_idx)
	for i in range(effect_count):
		var effect = AudioServer.get_bus_effect(bus_idx, i)
		if effect is AudioEffectPitchShift:
			return i
	return -1


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
	else:
		# 调试提示：如果收到了信号但没声音，通常是因为 SoundBank 里没配
		print("[AudioDebug] Received event: %s (but no SFX registered)" % event_id)
		pass

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
