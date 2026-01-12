class_name TheRabbitAnimator
extends Node

## 兔子吉祥物动画控制器
## 重构：以 AnimationTree 为核心的状态机架构
##
## [使用说明]
## 1. 在 'The Rabbit' 下添加 AnimationPlayer 和 AnimationTree 节点
## 2. AnimationTree 使用 AnimationNodeStateMachine，创建 "Idle" 和 "Shocked" 两个状态
## 3. 在 Inspector 中将 AnimationTree 赋值给本脚本的 'anim_tree' 变量
## 4. 勾选 'use_procedural_fallback' 可保留旧的纯代码动画作为过渡，直到你制作好动画片段

# ==========================================
# 核心配置
# ==========================================
@export_group("Animation System")
@export var anim_tree: AnimationTree
@export var use_procedural_fallback: bool = true ## 如果没有制作动画片段，开启此项使用代码模拟

# 状态名常量 (需与 AnimationTree 中的 Node Name 一致)
const STATE_IDLE = &"Idle"
const STATE_SHOCKED = &"Shocked"

# ==========================================
# 待机参数 (Idle)
# ==========================================
@export_category("Idle Config")
@export_group("Procedural Motion", "idle_")
@export var idle_arm_swing_amp: float = 8.0
@export var idle_arm_swing_speed: float = 2.5
@export var idle_ear_vib_amp: float = 1.0
@export var idle_ear_vib_speed: float = 3.0
@export var idle_mustache_amp: float = 3.0
@export var idle_mustache_speed: float = 4.0

@export_group("Eye Interaction", "idle_eye_")
@export var idle_eye_max_offset: float = 8.0
@export var idle_eye_follow_speed: float = 10.0

# ==========================================
# 震惊参数 (Shocked)
# ==========================================
@export_category("Shocked Config")
@export_group("Procedural Override", "shock_")
@export var shock_eye_shake: float = 1.5
@export var shock_eye_center_speed: float = 0.2
@export var shock_eye_center_offset: Vector2 = Vector2.ZERO

@export_group("Mustache Deformation", "shock_mustache_")
@export var shock_mustache_l_angle: float = -35.0
@export var shock_mustache_l_offset: Vector2 = Vector2(-15, 5)
@export var shock_mustache_r_angle: float = 35.0
@export var shock_mustache_r_offset: Vector2 = Vector2(15, 5)

@export_group("Visual Style", "shock_style_")
@export var shock_eye_fill_color: Color = Color(0.9, 0.9, 0.92, 1.0)
@export var shock_eye_outline_color: Color = Color(0.1, 0.1, 0.1, 1.0)
@export var shock_eye_outline_width: float = 0.1

@export_group("VFX", "shock_vfx_")
@export var shock_vfx_scale: float = 1.5
@export var shock_vfx_duration: float = 0.5
@export var shock_body_shake_dist: float = 10.0
@export var shock_body_shake_count: int = 5

# ==========================================
# 内部引用
# ==========================================
# 资源
const SHOCKED_EYES_SHADER = preload("res://assets/shaders/shocked_eyes.gdshader")
const SHOCKWAVE_SHADER = preload("res://assets/shaders/shockwave.gdshader")

# 节点
@onready var _rabbit_root: Node2D = get_parent() as Node2D
@onready var _left_arm: Sprite2D = _rabbit_root.get_node_or_null("TheRabbitLeftArm")
@onready var _left_ear: Sprite2D = _rabbit_root.get_node_or_null("TheRabbitLeftEar")
@onready var _right_ear: Sprite2D = _rabbit_root.get_node_or_null("TheRabbitRightEar")
@onready var _mustache_left: Sprite2D = _rabbit_root.get_node_or_null("TheRabbitMustacheLeft")
@onready var _mustache_right: Sprite2D = _rabbit_root.get_node_or_null("TheRabbitMustacheRight")
@onready var _left_eyeball: Sprite2D = _rabbit_root.get_node_or_null("TheRabbitLeftEyeFill/TheRabbitLeftEyeballFill")
@onready var _right_eyeball: Sprite2D = _rabbit_root.get_node_or_null("TheRabbitRightEyeFill/TheRabbitRightEyeballFill")

# 动态特效节点
var _shocked_eye_sprite_l: Sprite2D
var _shocked_eye_sprite_r: Sprite2D
var _shockwave_node: ColorRect

# 状态管理
var _playback: AnimationNodeStateMachinePlayback
var _current_state_name: StringName = STATE_IDLE
var _elapsed_time: float = 0.0

# 初始值缓存 (用于 fallback 和 相对计算)
var _init_trans: Dictionary = {}

# Fallback Tween
var _fallback_tween: Tween

func _ready() -> void:
	_cache_initial_transforms()
	_setup_vfx_nodes()
	_init_animation_tree()
	
	add_to_group("debug_animator")

func _cache_initial_transforms() -> void:
	var nodes = {
		"arm_l": _left_arm, "ear_l": _left_ear, "ear_r": _right_ear,
		"mus_l": _mustache_left, "mus_r": _mustache_right,
		"eye_l": _left_eyeball, "eye_r": _right_eyeball
	}
	
	for key in nodes:
		var node = nodes[key]
		if node:
			_init_trans[key] = {
				"pos": node.position,
				"rot": node.rotation,
				"scale": node.scale
			}

func _setup_vfx_nodes() -> void:
	if _left_eyeball: _shocked_eye_sprite_l = _create_shock_eye(_left_eyeball)
	if _right_eyeball: _shocked_eye_sprite_r = _create_shock_eye(_right_eyeball)
	
	_shockwave_node = ColorRect.new()
	_shockwave_node.name = "Shockwave"
	_shockwave_node.size = Vector2(400, 400)
	_shockwave_node.position = Vector2(-200, -200)
	_shockwave_node.pivot_offset = Vector2(200, 200)
	_shockwave_node.color = Color(0, 0, 0, 0) # Alpha handled by shader/modulate
	
	var mat = ShaderMaterial.new()
	mat.shader = SHOCKWAVE_SHADER
	_shockwave_node.material = mat
	_rabbit_root.add_child(_shockwave_node)
	_shockwave_node.hide()

func _create_shock_eye(original: Sprite2D) -> Sprite2D:
	var s = Sprite2D.new()
	s.texture = original.texture
	s.scale = original.scale
	s.position = original.position
	s.offset = original.offset
	s.name = original.name + "_ShockFX"
	s.visible = false
	
	var m = ShaderMaterial.new()
	m.shader = SHOCKED_EYES_SHADER
	_update_shock_shader_params(m)
	s.material = m
	
	original.get_parent().add_child(s)
	return s

func _update_shock_shader_params(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("fill_color", shock_eye_fill_color)
	mat.set_shader_parameter("outline_color", shock_eye_outline_color)
	mat.set_shader_parameter("outline_thickness", shock_eye_outline_width)

func _init_animation_tree() -> void:
	if anim_tree:
		anim_tree.active = true
		_playback = anim_tree.get("parameters/playback")
	else:
		if not use_procedural_fallback:
			push_warning("RabbitAnimator: No AnimationTree assigned and fallback disabled.")

# ==========================================
# 状态机逻辑
# ==========================================

func _process(delta: float) -> void:
	_elapsed_time += delta
	
	# 1. 确定当前状态
	var target_state = STATE_IDLE
	if _playback:
		target_state = _playback.get_current_node()
	
	# Fallback 模式下，状态由 _fallback_tween 隐式控制，不需要读取 AnimationTree
	if use_procedural_fallback and (_fallback_tween and _fallback_tween.is_valid()):
		# 正在播放 Fallback 动画中，在这里我们假设状态已经被 play_shocked_animation 置为 Shocked
		# 如果需要更精确的状态同步，可以在 Tween callback 里设置 _current_state_name
		pass
	elif _playback:
		_current_state_name = target_state
	
	# 2. 执行状态逻辑 (Overlay Logic)
	# 即使有 AnimationTree 负责身体动作，眼球和特效逻辑依然在这里执行 (Micro-Animation)
	match _current_state_name:
		STATE_IDLE:
			_process_state_idle(delta)
		STATE_SHOCKED:
			_process_state_shocked(delta)

func _process_state_idle(delta: float) -> void:
	# A. Procedural Overlay (Eye Tracking)
	_animate_eyes_look_at_mouse(delta)
	
	# B. Procedural Body (Fallback only)
	if use_procedural_fallback and (not anim_tree):
		_fallback_animate_idle_body()
	
	# C. Ensure Shock VFX hidden
	_toggle_shock_eyes(false)

func _process_state_shocked(delta: float) -> void:
	# A. Procedural Overlay (Shaking Eyes & Mustache Adjustment)
	_animate_eyes_shocked_shake()
	_animate_mustache_shocked_deform(delta) # 如果 AnimationTree 没有胡须轨道，这里负责移位
	
	# B. Procedural Body (Fallback only)
	# Fallback 的 Shock 动画是一次性 Tween，不由 _process 驱动循环

# ==========================================
# 行为实现 (Micro-Animations)
# ==========================================

func _animate_eyes_look_at_mouse(delta: float) -> void:
	var mouse_pos = _rabbit_root.get_global_mouse_position()
	if _left_eyeball: _lerp_eye_to(_left_eyeball, _init_trans["eye_l"].pos, mouse_pos, delta)
	if _right_eyeball: _lerp_eye_to(_right_eyeball, _init_trans["eye_r"].pos, mouse_pos, delta)

func _lerp_eye_to(eye: Sprite2D, init_pos: Vector2, target_global: Vector2, delta: float) -> void:
	var local_target = eye.get_parent().to_local(target_global)
	var dir = local_target - init_pos
	if dir.length() > idle_eye_max_offset:
		dir = dir.normalized() * idle_eye_max_offset
	eye.position = eye.position.lerp(init_pos + dir, idle_eye_follow_speed * delta)

func _animate_eyes_shocked_shake() -> void:
	var offset = Vector2(randf_range(-shock_eye_shake, shock_eye_shake), randf_range(-shock_eye_shake, shock_eye_shake))
	
	# 此时应该显示 ShockFX Sprite (瞳孔变色)
	# 基础归位位置 (Center + ConfigOffset)
	var center_l = _init_trans["eye_l"].pos + shock_eye_center_offset
	var center_r = _init_trans["eye_r"].pos + shock_eye_center_offset
	
	if _shocked_eye_sprite_l: _shocked_eye_sprite_l.position = center_l + offset
	if _shocked_eye_sprite_r: _shocked_eye_sprite_r.position = center_r + offset
	
	# 同时也把原始眼珠归位 (防止露馅)
	if _left_eyeball: _left_eyeball.position = center_l
	if _right_eyeball: _right_eyeball.position = center_r

func _animate_mustache_shocked_deform(delta: float) -> void:
	# AnimationTree 可能只控制了 Rotation，这里我们用代码叠加 Position 的形变，因为这比较特殊
	var lerp_speed = 10.0 * delta
	
	if _mustache_left:
		# Rotation 如果被 AnimationTree 控制了，这里 lerp 会冲突。
		# 但如果是 Fallback 模式或 Tree 没有轨道，这里生效。
		# 我们假设 AnimationTree 还没做这个细节，先保留代码控制。
		var target_rot = _init_trans["mus_l"].rot + deg_to_rad(shock_mustache_l_angle)
		var target_pos = _init_trans["mus_l"].pos + shock_mustache_l_offset
		_mustache_left.rotation = lerp_angle(_mustache_left.rotation, target_rot, lerp_speed)
		_mustache_left.position = _mustache_left.position.lerp(target_pos, lerp_speed)
		
	if _mustache_right:
		var target_rot = _init_trans["mus_r"].rot + deg_to_rad(shock_mustache_r_angle)
		var target_pos = _init_trans["mus_r"].pos + shock_mustache_r_offset
		_mustache_right.rotation = lerp_angle(_mustache_right.rotation, target_rot, lerp_speed)
		_mustache_right.position = _mustache_right.position.lerp(target_pos, lerp_speed)

# ==========================================
# Fallback Animations (Sine Waves)
# ==========================================
func _fallback_animate_idle_body() -> void:
	# Arm
	if _left_arm:
		var angle = sin(_elapsed_time * idle_arm_swing_speed) * deg_to_rad(idle_arm_swing_amp)
		_left_arm.rotation = _init_trans["arm_l"].rot + angle
	# Ears
	if _left_ear:
		var angle = sin(_elapsed_time * idle_ear_vib_speed) * deg_to_rad(idle_ear_vib_amp)
		_left_ear.rotation = _init_trans["ear_l"].rot + angle
	if _right_ear: # Phase offset handled by + PI/X logic
		var angle = sin(_elapsed_time * idle_ear_vib_speed + 1.0) * deg_to_rad(idle_ear_vib_amp)
		_right_ear.rotation = _init_trans["ear_r"].rot + angle
	# Mustache return to normal
	if _mustache_left:
		_mustache_left.position = _mustache_left.position.lerp(_init_trans["mus_l"].pos, 0.1)
		_mustache_left.rotation = lerp_angle(_mustache_left.rotation, _init_trans["mus_l"].rot, 0.1)
	if _mustache_right:
		_mustache_right.position = _mustache_right.position.lerp(_init_trans["mus_r"].pos, 0.1)
		_mustache_right.rotation = lerp_angle(_mustache_right.rotation, _init_trans["mus_r"].rot, 0.1)

# ==========================================
# Public API & Trigger Logic
# ==========================================

## 触发震惊动画
func play_shocked_animation() -> void:
	# 更新 Shader 参数
	if _shocked_eye_sprite_l: _update_shock_shader_params(_shocked_eye_sprite_l.material)
	if _shocked_eye_sprite_r: _update_shock_shader_params(_shocked_eye_sprite_r.material)
	
	if _playback and not use_procedural_fallback:
		# Mode A: AnimationTree
		_playback.travel(STATE_SHOCKED)
		# 注意：AnimationTree 需要在动画轨道中调用 `trigger_shock_impact` 方法来触发特效
		# 或者我们在这里手动延迟触发？更好的方式是动画回调。
		# 暂时为了兼容，我们这里不写 delay callback，而是期望 AnimationClip里有 Method Track 调用 `trigger_shock_impact`
		print("RabbitAnimator: Traveling to Shocked via AnimationTree")
	else:
		# Mode B: Procedural Fallback
		_run_fallback_shock_sequence()

## [Animation Track API] 触发重击特效
## 应该在 Shocked 动画的“砸地”帧通过 Method Track 调用此函数
func trigger_shock_impact() -> void:
	_toggle_shock_eyes(true)
	
	# 冲击波
	if _shockwave_node:
		if _left_arm: _shockwave_node.global_position = _left_arm.global_position + Vector2(0, 100)
		_shockwave_node.show()
		_shockwave_node.scale = Vector2(0.1, 0.1)
		_shockwave_node.modulate.a = 1.0
		
		var t = create_tween()
		t.set_parallel(true)
		t.tween_property(_shockwave_node, "scale", Vector2(shock_vfx_scale, shock_vfx_scale), shock_vfx_duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		t.tween_property(_shockwave_node, "modulate:a", 0.0, shock_vfx_duration).set_ease(Tween.EASE_IN)
		t.chain().tween_callback(_shockwave_node.hide)
	
	# 身体震动
	var t_shake = create_tween()
	var origin = _rabbit_root.position # World or Local? Assuming Rabbit Root is movable
	# 注意：如果 Rabbit Root 是 PhysicsBody 或受其他控制，这里 tween position 可能会有冲突。
	# 我们假设它是纯视觉对象。
	for i in range(shock_body_shake_count):
		var offset = Vector2(randf_range(-shock_body_shake_dist, shock_body_shake_dist), randf_range(0, shock_body_shake_dist))
		t_shake.tween_property(_rabbit_root, "position", origin + offset, 0.05)
		t_shake.tween_property(_rabbit_root, "position", origin, 0.05)

func _toggle_shock_eyes(enable: bool) -> void:
	if _left_eyeball: _left_eyeball.visible = !enable
	if _right_eyeball: _right_eyeball.visible = !enable
	if _shocked_eye_sprite_l: _shocked_eye_sprite_l.visible = enable
	if _shocked_eye_sprite_r: _shocked_eye_sprite_r.visible = enable

# ==========================================
# Legacy Fallback Sequence
# ==========================================
func _run_fallback_shock_sequence() -> void:
	if _fallback_tween and _fallback_tween.is_valid(): _fallback_tween.kill()
	
	_current_state_name = STATE_SHOCKED
	
	_fallback_tween = create_tween()
	_fallback_tween.set_parallel(true)
	
	# 1. Anticipation
	if _left_arm:
		_fallback_tween.tween_property(_left_arm, "rotation_degrees", -60.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Eyes Center
	var center_l = _init_trans["eye_l"].pos + shock_eye_center_offset
	var center_r = _init_trans["eye_r"].pos + shock_eye_center_offset
	if _left_eyeball:
		_fallback_tween.tween_property(_left_eyeball, "position", center_l, shock_eye_center_speed).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	if _right_eyeball:
		_fallback_tween.tween_property(_right_eyeball, "position", center_r, shock_eye_center_speed).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	
	_fallback_tween.chain()
	
	# 2. Slam
	if _left_arm:
		_fallback_tween.tween_property(_left_arm, "rotation_degrees", 20.0, 0.1).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	
	# **关键点**：Fallback 模式下手动调用 trigger_shock_impact
	_fallback_tween.tween_callback(self.trigger_shock_impact).set_delay(0.08)
	
	_fallback_tween.chain()
	
	# 3. Hold
	_fallback_tween.tween_interval(1.5)
	
	_fallback_tween.chain()
	
	# 4. Recover
	_fallback_tween.tween_callback(func(): _current_state_name = STATE_IDLE)
	if _left_arm:
		var t = create_tween() # Separate tween for recovery to avoid blocking
		t.tween_property(_left_arm, "rotation", _init_trans["arm_l"].rot, 0.5)

func test_shock() -> void:
	play_shocked_animation()
