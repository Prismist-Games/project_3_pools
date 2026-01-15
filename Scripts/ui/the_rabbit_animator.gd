class_name TheRabbitAnimator
extends Node

## [兔子吉祥物动画控制器]


@export_group("Animation System")
@export var anim_tree: AnimationTree

const STATE_RABBIT_IDLE = &"RabbitIdle"
const STATE_RABBIT_SHOCKED = &"RabbitShocked"
const STATE_RABBIT_IMPATIENT = &"RabbitImpatient"
const STATE_RABBIT_NOSE_POKING = &"RabbitNosePoking"
const STATE_RABBIT_DRAWING = &"RabbitDrawing"
const STATE_RABBIT_RECYCLE_HIT = &"RabbitRecycleHit"

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


@export_group("Eye Interaction", "idle_eye_")
@export var idle_eye_max_offset: float = 8.0
@export var idle_eye_follow_speed: float = 10.0


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


const EYE_PROCEDURAL_SHADER = preload("res://assets/shaders/eye_procedural.gdshader")

var _rabbit_root: Node2D
var _left_arm: Sprite2D
var _left_ear: Sprite2D
var _right_ear: Sprite2D
var _mustache_left: Sprite2D
var _mustache_right: Sprite2D
var _left_eye_fill: Sprite2D
var _right_eye_fill: Sprite2D
var _left_foot: Sprite2D

var _left_eye_mat: ShaderMaterial
var _right_eye_mat: ShaderMaterial

var _playback: AnimationNodeStateMachinePlayback
var _current_state_name: StringName = STATE_RABBIT_IDLE
var _is_in_triggered_animation: bool = false
var _is_test_override: bool = false

var _current_lottery_hover_pos: Vector2 = Vector2.ZERO
var _has_hovered_lottery: bool = false

var _init_trans: Dictionary = {}

func _ready() -> void:
	_find_required_nodes()
	_cache_initial_transforms()
	_init_animation_tree()
	_connect_to_ui_state()
	
	if GameManager:
		GameManager.gold_changed.connect(_on_gold_changed)
	
	add_to_group("debug_animator")

func _connect_to_ui_state() -> void:
	# 尝试连接 UI 状态机
	var ui_root = get_tree().get_first_node_in_group("game_2d_ui")
	if ui_root:
		var sm = ui_root.get_node_or_null("UIStateMachine")
		if sm:
			sm.state_changed.connect(_on_ui_state_changed)
			print("[RabbitAnimator] UI 状态机连接成功")
		else:
			print("[RabbitAnimator] 未找到 UIStateMachine 节点")
	
	# 连接奖池悬停信号（通过 EventBus）
	EventBus.game_event.connect(_on_bus_game_event)

func _on_ui_state_changed(_from: StringName, to: StringName) -> void:
	match to:
		&"Idle": _transition_to_state(STATE_RABBIT_IDLE)
		&"Drawing": _transition_to_state(STATE_RABBIT_DRAWING)
		&"Submitting": _transition_to_state(STATE_RABBIT_NOSE_POKING)
		&"Recycling": _transition_to_state(STATE_RABBIT_RECYCLE_HIT)
		&"Replacing": _transition_to_state(STATE_RABBIT_IMPATIENT)
		&"PreciseSelection", &"TargetedSelection": _transition_to_state(STATE_RABBIT_DRAWING)

func _on_bus_game_event(event_id: StringName, payload: Variant) -> void:
	if event_id == &"lottery_slot_hovered":
		_has_hovered_lottery = true
		if payload is RefCounted:
			var ctx = payload as RefCounted
			if "get_value" in ctx:
				_current_lottery_hover_pos = ctx.get_value(&"global_position", Vector2.ZERO)
		else:
			_current_lottery_hover_pos = Vector2.ZERO
	elif event_id == &"lottery_slot_unhovered":
		_has_hovered_lottery = false

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

func _cache_initial_transforms() -> void:
	var nodes = {
		"arm_l": _left_arm, "ear_l": _left_ear, "ear_r": _right_ear,
		"mus_l": _mustache_left, "mus_r": _mustache_right,
		"foot_l": _left_foot
	}
	for key in nodes:
		var node = nodes[key]
		if node: _init_trans[key] = {"pos": node.position, "rot": node.rotation, "scale": node.scale}
	
	_init_eye_materials()

func _init_eye_materials() -> void:
	if _left_eye_fill:
		_left_eye_mat = ShaderMaterial.new()
		_left_eye_mat.shader = EYE_PROCEDURAL_SHADER
		_update_shader_params(_left_eye_mat, true)
		_left_eye_fill.material = _left_eye_mat
		_left_eye_fill.scale = Vector2(eye_socket_scale, eye_socket_scale)
		if eye_socket_texture:
			_left_eye_fill.texture = eye_socket_texture
			
	if _right_eye_fill:
		_right_eye_mat = ShaderMaterial.new()
		_right_eye_mat.shader = EYE_PROCEDURAL_SHADER
		_update_shader_params(_right_eye_mat, false)
		_right_eye_fill.material = _right_eye_mat
		_right_eye_fill.scale = Vector2(eye_socket_scale, eye_socket_scale)
		if eye_socket_texture:
			_right_eye_fill.texture = eye_socket_texture

func _update_shader_params(mat: ShaderMaterial, _is_left: bool) -> void:
	mat.set_shader_parameter("outline_thickness", eye_outline_thickness)
	mat.set_shader_parameter("outline_color", eye_outline_color)
	mat.set_shader_parameter("pupil_offset", eye_pupil_initial_offset)
	mat.set_shader_parameter("pupil_scale", eye_pupil_initial_size)
	mat.set_shader_parameter("pupil_color", eye_pupil_color)
	mat.set_shader_parameter("pupil_outline_color", eye_pupil_outline_color)
	mat.set_shader_parameter("pupil_outline_thickness", eye_pupil_outline_thickness)
	if eye_pupil_texture:
		mat.set_shader_parameter("pupil_texture", eye_pupil_texture)
		mat.set_shader_parameter("use_pupil_texture", true)
	else:
		mat.set_shader_parameter("use_pupil_texture", false)

func _init_animation_tree() -> void:
	if anim_tree:
		anim_tree.active = true
		_playback = anim_tree.get("parameters/playback")

func _on_gold_changed(_new_gold: int) -> void:
	pass

func _transition_to_state(new_state: StringName) -> void:
	if _current_state_name == new_state: return
	_current_state_name = new_state
	_enter_state(new_state)
	if _playback: _playback.travel(new_state)

func _enter_state(state: StringName) -> void:
	match state:
		STATE_RABBIT_IMPATIENT:
			blink_to_impatient()
		STATE_RABBIT_IDLE:
			blink_to_normal()

## 供 AnimationPlayer 调用：切换到不耐烦眯眯眼
func blink_to_impatient() -> void:
	_animate_eye_shape_transition(true)

## 供 AnimationPlayer 调用：恢复正常眼眶
func blink_to_normal() -> void:
	_animate_eye_shape_transition(false)

func _animate_eye_shape_transition(to_impatient: bool) -> void:
	var target_texture = impatient_eye_target_texture if to_impatient and impatient_eye_target_texture else eye_socket_texture
	if not target_texture: return
	
	for eye in [_left_eye_fill, _right_eye_fill]:
		if not eye: continue
		var tween = create_tween()
		tween.tween_property(eye, "scale:y", 0.0, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_callback(func(): eye.texture = target_texture)
		tween.tween_property(eye, "scale:y", eye_socket_scale, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if _playback:
		var tree_state = _playback.get_current_node()
		if tree_state != _current_state_name:
			_current_state_name = tree_state
			_enter_state(tree_state)
	
	_update_eye_behavior(delta)

func _update_eye_behavior(_delta: float) -> void:
	if _current_state_name == STATE_RABBIT_SHOCKED: return
	if _current_state_name == STATE_RABBIT_IMPATIENT:
		_set_eye_pupil_offset(impatient_eye_pupil_offset)
		return
	
	var target_pos = _current_lottery_hover_pos if (_current_state_name == STATE_RABBIT_DRAWING and _has_hovered_lottery) else _rabbit_root.get_global_mouse_position()
	_apply_eye_look_at(target_pos)

func _apply_eye_look_at(global_target: Vector2) -> void:
	for mat in [_left_eye_mat, _right_eye_mat]:
		if not mat: continue
		var eye_fill = _left_eye_fill if mat == _left_eye_mat else _right_eye_fill
		var dir = (global_target - eye_fill.global_position).normalized()
		var dist_factor = min((global_target - eye_fill.global_position).length() / 500.0, 1.0)
		var offset = dir * dist_factor * idle_eye_max_offset * 0.01
		mat.set_shader_parameter("pupil_offset", eye_pupil_initial_offset + offset)

func _set_eye_pupil_offset(offset: Vector2) -> void:
	if _left_eye_mat: _left_eye_mat.set_shader_parameter("pupil_offset", offset)
	if _right_eye_mat: _right_eye_mat.set_shader_parameter("pupil_offset", offset)

func play_shocked_animation() -> void:
	_transition_to_state(STATE_RABBIT_SHOCKED)

func trigger_shock_impact() -> void:
	pass

func _end_triggered_animation() -> void:
	_on_gold_changed(GameManager.gold if GameManager else 100)

func reset_to_idle() -> void:
	_transition_to_state(STATE_RABBIT_IDLE)
