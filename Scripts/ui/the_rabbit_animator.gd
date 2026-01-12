class_name TheRabbitAnimator
extends Node

## [兔子吉祥物动画控制器]


@export_group("Animation System")
@export var anim_tree: AnimationTree
@export var use_procedural_fallback: bool = true

const STATE_IDLE = &"Idle"
const STATE_SHOCKED = &"Shocked"
const STATE_IMPATIENT = &"Impatient"

# ==========================================
# 全局眼部设置
# ==========================================
@export_category("Eye Appearance (Global)")
@export_group("Socket Shape", "eye_")
@export var eye_socket_texture: Texture2D ## 眼眶形状纹理（留空=使用原节点纹理）
@export var eye_socket_scale: float = 1.0 ## 眼眶缩放

@export_group("Outline", "eye_outline_")
@export var eye_outline_color: Color = Color(1.0, 0.44, 0.35, 1.0) ## 描边颜色
@export var eye_outline_thickness: float = 0.04 ## 描边粗细

@export_group("Pupil", "eye_pupil_")
@export var eye_pupil_texture: Texture2D ## 瞳孔形状纹理（留空=使用纯色圆形）
@export var eye_pupil_initial_size: float = 1.0 ## 瞳孔初始大小
@export var eye_pupil_initial_offset: Vector2 = Vector2.ZERO ## 瞳孔初始位置偏移 (Shader 坐标系)
@export var eye_pupil_color: Color = Color.BLACK ## 瞳孔颜色（仅纯色模式）
@export var eye_pupil_outline_color: Color = Color.BLACK ## 瞳孔描边颜色
@export var eye_pupil_outline_thickness: float = 0.0 ## 瞳孔描边粗细

# ==========================================
# 待机动画
# ==========================================
@export_category("Idle Config")
@export_group("Procedural Motion", "idle_")
@export var idle_arm_swing_amp: float = 8.0
@export var idle_arm_swing_speed: float = 2.5
@export var idle_ear_vib_amp: float = 1.0
@export var idle_ear_vib_speed: float = 3.0

@export_group("Eye Interaction", "idle_eye_")
@export var idle_eye_max_offset: float = 8.0
@export var idle_eye_follow_speed: float = 10.0

# ==========================================
# 震惊动画
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
# 不耐烦动画
# ==========================================
@export_category("Impatient Config")
@export_group("Trigger", "impatient_")
@export var impatient_gold_threshold: int = 10
@export var test_deform_on_start: bool = false ## DEBUG: 启动时立即测试变形

@export_group("Eye Style", "impatient_eye_")
@export var impatient_eye_target_texture: Texture2D ## 眯眼时的眼眶形状纹理
@export var impatient_eye_pupil_scale: float = 0.25 ## 眯眼时的瞳孔缩放
@export var impatient_eye_pupil_offset: Vector2 = Vector2.ZERO ## 眯眼时的瞳孔基准偏移 (建议 -0.05 到 0.05)

@export_group("Foot Tap", "impatient_foot_")
@export var impatient_foot_tap_speed: float = 8.0
@export var impatient_foot_tap_angle: float = 15.0
@export var impatient_foot_tap_y_offset: float = 12.0

@export_group("Body Language", "impatient_body_")
@export var impatient_arm_angle: float = -20.0
@export var impatient_mustache_droop: float = 15.0

const EYE_PROCEDURAL_SHADER = preload("res://assets/shaders/eye_procedural.gdshader")
const SHOCKWAVE_SHADER = preload("res://assets/shaders/shockwave.gdshader")

var _rabbit_root: Node2D
var _left_arm: Sprite2D
var _left_ear: Sprite2D
var _right_ear: Sprite2D
var _mustache_left: Sprite2D
var _mustache_right: Sprite2D
var _left_eye_fill: Sprite2D
var _right_eye_fill: Sprite2D
var _left_eyeball: Sprite2D
var _right_eyeball: Sprite2D
var _left_foot: Sprite2D

var _shockwave_node: ColorRect

var _left_eye_mat: ShaderMaterial
var _right_eye_mat: ShaderMaterial

var _playback: AnimationNodeStateMachinePlayback
var _current_state_name: StringName = STATE_IDLE
var _elapsed_time: float = 0.0
var _is_in_triggered_animation: bool = false
var _is_test_override: bool = false

var _init_trans: Dictionary = {}
var _fallback_tween: Tween

func _ready() -> void:
	_find_required_nodes()
	_cache_initial_transforms()
	_setup_vfx_nodes()
	_init_animation_tree()
	
	if GameManager:
		GameManager.gold_changed.connect(_on_gold_changed)
	
	add_to_group("debug_animator")
	
	if test_deform_on_start:
		await get_tree().create_timer(1.0).timeout
		test_impatient()

func _find_required_nodes() -> void:
	var p = get_parent()
	_rabbit_root = p
	print("[RabbitAnimator] Parent node: ", p.name if p else "NULL")
	
	_left_arm = p.find_child("TheRabbitLeftArm", true, false)
	_left_ear = p.find_child("TheRabbitLeftEar", true, false)
	_right_ear = p.find_child("TheRabbitRightEar", true, false)
	_mustache_left = p.find_child("TheRabbitMustacheLeft", true, false)
	_mustache_right = p.find_child("TheRabbitMustacheRight", true, false)
	_left_eye_fill = p.find_child("TheRabbitLeftEyeFill", true, false)
	_right_eye_fill = p.find_child("TheRabbitRightEyeFill", true, false)
	_left_foot = p.find_child("TheRabbitLeftFoot", true, false)
	
	print("[RabbitAnimator] Left Eye Fill found: ", _left_eye_fill != null)
	print("[RabbitAnimator] Right Eye Fill found: ", _right_eye_fill != null)
	
	if _left_eye_fill:
		_left_eyeball = _left_eye_fill.find_child("TheRabbitLeftEyeballFill", true, false)
	if _right_eye_fill:
		_right_eyeball = _right_eye_fill.find_child("TheRabbitRightEyeballFill", true, false)

func _cache_initial_transforms() -> void:
	var nodes = {
		"arm_l": _left_arm, "ear_l": _left_ear, "ear_r": _right_ear,
		"mus_l": _mustache_left, "mus_r": _mustache_right,
		"eye_l": _left_eyeball, "eye_r": _right_eyeball,
		"foot_l": _left_foot
	}
	for key in nodes:
		var node = nodes[key]
		if node: _init_trans[key] = {"pos": node.position, "rot": node.rotation, "scale": node.scale}

func _setup_vfx_nodes() -> void:
	# 核心：给眼眶应用程序化 Shader
	if _left_eye_fill:
		_left_eye_mat = ShaderMaterial.new()
		_left_eye_mat.shader = EYE_PROCEDURAL_SHADER
		
		_left_eye_mat.set_shader_parameter("outline_thickness", eye_outline_thickness)
		_left_eye_mat.set_shader_parameter("outline_color", eye_outline_color)
		_left_eye_mat.set_shader_parameter("pupil_offset", eye_pupil_initial_offset)
		_left_eye_mat.set_shader_parameter("pupil_scale", eye_pupil_initial_size)
		if eye_pupil_texture:
			_left_eye_mat.set_shader_parameter("pupil_texture", eye_pupil_texture)
			_left_eye_mat.set_shader_parameter("use_pupil_texture", true)
		else:
			_left_eye_mat.set_shader_parameter("use_pupil_texture", false)
		_left_eye_mat.set_shader_parameter("pupil_color", eye_pupil_color)
		_left_eye_mat.set_shader_parameter("pupil_outline_color", eye_pupil_outline_color)
		_left_eye_mat.set_shader_parameter("pupil_outline_thickness", eye_pupil_outline_thickness)
		
		_left_eye_fill.scale = Vector2(eye_socket_scale, eye_socket_scale)
		if eye_socket_texture:
			_left_eye_fill.texture = eye_socket_texture
		
		_left_eye_fill.material = _left_eye_mat
		if _left_eyeball: _left_eyeball.hide()
		for child in _left_eye_fill.get_children():
			if "Outline" in child.name: child.hide()
			
	if _right_eye_fill:
		_right_eye_mat = ShaderMaterial.new()
		_right_eye_mat.shader = EYE_PROCEDURAL_SHADER
		
		_right_eye_mat.set_shader_parameter("outline_thickness", eye_outline_thickness)
		_right_eye_mat.set_shader_parameter("outline_color", eye_outline_color)
		_right_eye_mat.set_shader_parameter("pupil_offset", eye_pupil_initial_offset)
		_right_eye_mat.set_shader_parameter("pupil_scale", eye_pupil_initial_size)
		if eye_pupil_texture:
			_right_eye_mat.set_shader_parameter("pupil_texture", eye_pupil_texture)
			_right_eye_mat.set_shader_parameter("use_pupil_texture", true)
		else:
			_right_eye_mat.set_shader_parameter("use_pupil_texture", false)
		_right_eye_mat.set_shader_parameter("pupil_color", eye_pupil_color)
		_right_eye_mat.set_shader_parameter("pupil_outline_color", eye_pupil_outline_color)
		_right_eye_mat.set_shader_parameter("pupil_outline_thickness", eye_pupil_outline_thickness)
		
		_right_eye_fill.scale = Vector2(eye_socket_scale, eye_socket_scale)
		if eye_socket_texture:
			_right_eye_fill.texture = eye_socket_texture
		
		_right_eye_fill.material = _right_eye_mat
		if _right_eyeball: _right_eyeball.hide()
		for child in _right_eye_fill.get_children():
			if "Outline" in child.name: child.hide()
	
	_shockwave_node = ColorRect.new()
	_shockwave_node.name = "Shockwave"
	_shockwave_node.size = Vector2(400, 400)
	_shockwave_node.position = Vector2(-200, -200)
	_shockwave_node.pivot_offset = Vector2(200, 200)
	_shockwave_node.color = Color(0, 0, 0, 0)
	var mat = ShaderMaterial.new()
	mat.shader = SHOCKWAVE_SHADER
	_shockwave_node.material = mat
	_rabbit_root.add_child.call_deferred(_shockwave_node)
	_shockwave_node.hide()

func _init_animation_tree() -> void:
	if anim_tree:
		anim_tree.active = true
		_playback = anim_tree.get("parameters/playback")

func _on_gold_changed(new_gold: int) -> void:
	if _is_in_triggered_animation or _is_test_override: return
	if new_gold < impatient_gold_threshold: _transition_to_state(STATE_IMPATIENT)
	else: _transition_to_state(STATE_IDLE)

func _transition_to_state(new_state: StringName) -> void:
	if _current_state_name == new_state: return
	_exit_state(_current_state_name)
	_current_state_name = new_state
	_enter_state(new_state)
	if _playback and not use_procedural_fallback: _playback.travel(new_state)

func _exit_state(state: StringName) -> void:
	match state:
		STATE_SHOCKED:
			# 恢复原始眼部视觉
			_update_eye_style_globals()
		STATE_IMPATIENT:
			# 眨眼动画恢复眼眶形状
			_animate_eye_shape_transition(false)
			# 恢复瞳孔大小
			if _left_eye_mat:
				create_tween().tween_method(func(v): _left_eye_mat.set_shader_parameter("pupil_scale", v), impatient_eye_pupil_scale, eye_pupil_initial_size, 0.3)
			if _right_eye_mat:
				create_tween().tween_method(func(v): _right_eye_mat.set_shader_parameter("pupil_scale", v), impatient_eye_pupil_scale, eye_pupil_initial_size, 0.3)

func _enter_state(state: StringName) -> void:
	match state:
		STATE_SHOCKED:
			# 设置震惊时的视觉样式
			if _left_eye_mat:
				_left_eye_mat.set_shader_parameter("outline_color", shock_eye_outline_color)
				_left_eye_mat.set_shader_parameter("outline_thickness", shock_eye_outline_width)
				_left_eye_mat.set_shader_parameter("pupil_scale", 0.0)
			if _right_eye_mat:
				_right_eye_mat.set_shader_parameter("outline_color", shock_eye_outline_color)
				_right_eye_mat.set_shader_parameter("outline_thickness", shock_eye_outline_width)
				_right_eye_mat.set_shader_parameter("pupil_scale", 0.0)
		STATE_IMPATIENT:
			# 眨眼动画切换到不耐烦眼眶形状
			_animate_eye_shape_transition(true)
			# 缩小瞳孔
			if _left_eye_mat:
				create_tween().tween_method(func(v): _left_eye_mat.set_shader_parameter("pupil_scale", v), eye_pupil_initial_size, impatient_eye_pupil_scale, 0.3)
			if _right_eye_mat:
				create_tween().tween_method(func(v): _right_eye_mat.set_shader_parameter("pupil_scale", v), eye_pupil_initial_size, impatient_eye_pupil_scale, 0.3)


func _update_eye_style_globals() -> void:
	if _left_eye_mat:
		_left_eye_mat.set_shader_parameter("outline_color", eye_outline_color)
		_left_eye_mat.set_shader_parameter("outline_thickness", eye_outline_thickness)
		_left_eye_mat.set_shader_parameter("pupil_scale", eye_pupil_initial_size)
	if _right_eye_mat:
		_right_eye_mat.set_shader_parameter("outline_color", eye_outline_color)
		_right_eye_mat.set_shader_parameter("outline_thickness", eye_outline_thickness)
		_right_eye_mat.set_shader_parameter("pupil_scale", eye_pupil_initial_size)

func _animate_eye_shape_transition(to_impatient: bool) -> void:
	"""眨眼动画: 先缩小, 切换纹理, 再放大"""
	var target_texture: Texture2D
	if to_impatient and impatient_eye_target_texture:
		target_texture = impatient_eye_target_texture
	else:
		target_texture = eye_socket_texture if eye_socket_texture else null
	
	if not target_texture:
		return
	
	var blink_duration := 0.15 # 单向动画时长
	var min_scale_y := 0.05 # 最小Y轴缩放(几乎闭合)
	
	# 左眼动画
	if _left_eye_fill:
		var original_scale := _left_eye_fill.scale
		var tween_l := create_tween()
		# 阶段1: 缩小 (闭眼)
		tween_l.tween_property(_left_eye_fill, "scale:y", original_scale.y * min_scale_y, blink_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		# 阶段2: 切换纹理
		tween_l.tween_callback(func(): _left_eye_fill.texture = target_texture)
		# 阶段3: 放大 (睁眼)
		tween_l.tween_property(_left_eye_fill, "scale:y", original_scale.y, blink_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# 右眼动画
	if _right_eye_fill:
		var original_scale := _right_eye_fill.scale
		var tween_r := create_tween()
		# 阶段1: 缩小 (闭眼)
		tween_r.tween_property(_right_eye_fill, "scale:y", original_scale.y * min_scale_y, blink_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		# 阶段2: 切换纹理
		tween_r.tween_callback(func(): _right_eye_fill.texture = target_texture)
		# 阶段3: 放大 (睁眼)
		tween_r.tween_property(_right_eye_fill, "scale:y", original_scale.y, blink_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_elapsed_time += delta
	
	if _playback and not use_procedural_fallback and not _is_in_triggered_animation and not _is_test_override:
		var tree_state = _playback.get_current_node()
		if tree_state != _current_state_name:
			_exit_state(_current_state_name)
			_current_state_name = tree_state
			_enter_state(tree_state)
	
	match _current_state_name:
		STATE_IDLE: _process_state_idle(delta)
		STATE_SHOCKED: _process_state_shocked(delta)
		STATE_IMPATIENT: _process_state_impatient(delta)

func _process_state_idle(delta: float) -> void:
	_animate_eyes_follow(delta)
	if use_procedural_fallback and (not anim_tree): _fallback_animate_idle_body()

func _process_state_shocked(_delta: float) -> void:
	_animate_eyes_shocked_shake()
	_animate_mustache_shocked_deform(_delta)

func _process_state_impatient(delta: float) -> void:
	# 不再跟随鼠标，仅使用静态偏移
	_set_eye_pupil_offset(impatient_eye_pupil_offset)
	if use_procedural_fallback and (not anim_tree): _fallback_animate_impatient_body(delta)

func _set_eye_pupil_offset(offset: Vector2) -> void:
	if _left_eye_mat: _left_eye_mat.set_shader_parameter("pupil_offset", offset)
	if _right_eye_mat: _right_eye_mat.set_shader_parameter("pupil_offset", offset)

func _animate_eyes_follow(_delta: float) -> void:
	var m_pos = _rabbit_root.get_global_mouse_position()
	
	# 计算眼神跟随
	if _left_eye_fill and _left_eye_mat:
		var eye_center = _left_eye_fill.global_position
		var dir = (m_pos - eye_center).normalized()
		var distance = min((m_pos - eye_center).length() / 100.0, 1.0)
		var follow_offset = dir * distance * idle_eye_max_offset * 0.01
		_left_eye_mat.set_shader_parameter("pupil_offset", eye_pupil_initial_offset + follow_offset)
	
	if _right_eye_fill and _right_eye_mat:
		var eye_center = _right_eye_fill.global_position
		var dir = (m_pos - eye_center).normalized()
		var distance = min((m_pos - eye_center).length() / 100.0, 1.0)
		var follow_offset = dir * distance * idle_eye_max_offset * 0.01
		_right_eye_mat.set_shader_parameter("pupil_offset", eye_pupil_initial_offset + follow_offset)

func _animate_eyes_shocked_shake() -> void:
	var off = Vector2(randf_range(-shock_eye_shake, shock_eye_shake), randf_range(-shock_eye_shake, shock_eye_shake))
	if _left_eye_fill: _left_eye_fill.position = off
	if _right_eye_fill: _right_eye_fill.position = off

func _animate_mustache_shocked_deform(delta: float) -> void:
	var spd = 10.0 * delta
	if _mustache_left:
		_mustache_left.rotation = lerp_angle(_mustache_left.rotation, _init_trans["mus_l"].rot + deg_to_rad(shock_mustache_l_angle), spd)
		_mustache_left.position = _mustache_left.position.lerp(_init_trans["mus_l"].pos + shock_mustache_l_offset, spd)
	if _mustache_right:
		_mustache_right.rotation = lerp_angle(_mustache_right.rotation, _init_trans["mus_r"].rot + deg_to_rad(shock_mustache_r_angle), spd)
		_mustache_right.position = _mustache_right.position.lerp(_init_trans["mus_r"].pos + shock_mustache_r_offset, spd)

func _fallback_animate_idle_body() -> void:
	if _left_arm: _left_arm.rotation = _init_trans["arm_l"].rot + sin(_elapsed_time * idle_arm_swing_speed) * deg_to_rad(idle_arm_swing_amp)
	if _left_ear: _left_ear.rotation = _init_trans["ear_l"].rot + sin(_elapsed_time * idle_ear_vib_speed) * deg_to_rad(idle_ear_vib_amp)
	if _right_ear: _right_ear.rotation = _init_trans["ear_r"].rot + sin(_elapsed_time * idle_ear_vib_speed + 1.0) * deg_to_rad(idle_ear_vib_amp)
	if _mustache_left:
		_mustache_left.position = _mustache_left.position.lerp(_init_trans["mus_l"].pos, 0.1)
		_mustache_left.rotation = lerp_angle(_mustache_left.rotation, _init_trans["mus_l"].rot, 0.1)
	if _mustache_right:
		_mustache_right.position = _mustache_right.position.lerp(_init_trans["mus_r"].pos, 0.1)
		_mustache_right.rotation = lerp_angle(_mustache_right.rotation, _init_trans["mus_r"].rot, 0.1)
	if _left_foot:
		_left_foot.position = _left_foot.position.lerp(_init_trans["foot_l"].pos, 0.1)
		_left_foot.rotation = lerp_angle(_left_foot.rotation, _init_trans["foot_l"].rot, 0.1)

func _fallback_animate_impatient_body(delta: float) -> void:
	var spd = 10.0 * delta
	if _mustache_left: _mustache_left.rotation = lerp_angle(_mustache_left.rotation, _init_trans["mus_l"].rot + deg_to_rad(impatient_mustache_droop), spd)
	if _mustache_right: _mustache_right.rotation = lerp_angle(_mustache_right.rotation, _init_trans["mus_r"].rot + deg_to_rad(-impatient_mustache_droop), spd)
	if _left_arm: _left_arm.rotation = lerp_angle(_left_arm.rotation, _init_trans["arm_l"].rot + deg_to_rad(impatient_arm_angle), spd)
	if _left_foot:
		var phase = abs(sin(_elapsed_time * impatient_foot_tap_speed))
		_left_foot.rotation = _init_trans["foot_l"].rot + deg_to_rad(-impatient_foot_tap_angle * phase)
		_left_foot.position.y = _init_trans["foot_l"].pos.y - impatient_foot_tap_y_offset * phase


func play_shocked_animation() -> void:
	_is_in_triggered_animation = true
	_is_test_override = false
	_transition_to_state(STATE_SHOCKED)
	if _playback and not use_procedural_fallback: _playback.travel(STATE_SHOCKED)
	else: _run_fallback_shock_sequence()

func trigger_shock_impact() -> void:
	if _shockwave_node:
		_shockwave_node.global_position = _left_arm.global_position + Vector2(0, 100) if _left_arm else Vector2.ZERO
		_shockwave_node.show()
		_shockwave_node.scale = Vector2(1, 1)
		_shockwave_node.modulate.a = 1.0
		var t = create_tween().set_parallel(true)
		t.tween_property(_shockwave_node, "scale", Vector2(shock_vfx_scale, shock_vfx_scale), shock_vfx_duration).set_trans(Tween.TRANS_EXPO)
		t.tween_property(_shockwave_node, "modulate:a", 0.0, shock_vfx_duration)
		t.chain().tween_callback(_shockwave_node.hide)
	var t_s = create_tween()
	var o = _rabbit_root.position
	for i in range(shock_body_shake_count):
		t_s.tween_property(_rabbit_root, "position", o + Vector2(randf_range(-10, 10), randf_range(0, 10)), 0.05)
		t_s.tween_property(_rabbit_root, "position", o, 0.05)

func _run_fallback_shock_sequence() -> void:
	if _fallback_tween and _fallback_tween.is_valid(): _fallback_tween.kill()
	_fallback_tween = create_tween().set_parallel(true)
	if _left_arm: _fallback_tween.tween_property(_left_arm, "rotation_degrees", -60.0, 0.2).set_trans(Tween.TRANS_CUBIC)
	if _left_eyeball: _fallback_tween.tween_property(_left_eyeball, "position", _init_trans["eye_l"].pos + shock_eye_center_offset, 0.2)
	if _right_eyeball: _fallback_tween.tween_property(_right_eyeball, "position", _init_trans["eye_r"].pos + shock_eye_center_offset, 0.2)
	_fallback_tween.chain()
	if _left_arm: _fallback_tween.tween_property(_left_arm, "rotation_degrees", 20.0, 0.1).set_trans(Tween.TRANS_BOUNCE)
	_fallback_tween.tween_callback(self.trigger_shock_impact).set_delay(0.08)
	_fallback_tween.chain().tween_interval(1.5).chain().tween_callback(_end_triggered_animation)

func _end_triggered_animation() -> void:
	_is_in_triggered_animation = false
	_is_test_override = false
	_on_gold_changed(GameManager.gold if GameManager else 100)

func test_shock() -> void:
	play_shocked_animation()

func test_impatient() -> void:
	_is_test_override = true
	_transition_to_state(STATE_IMPATIENT)

func reset_to_idle() -> void:
	_is_test_override = false
	_is_in_triggered_animation = false
	_transition_to_state(STATE_IDLE)
