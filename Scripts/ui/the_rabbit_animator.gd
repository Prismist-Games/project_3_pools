class_name TheRabbitAnimator
extends Node

## [兔子吉祥物动画控制器]


@export_group("Animation System")
@export var anim_tree: AnimationTree

const STATE_RABBIT_IDLE = &"rabbit_idle"
const STATE_RABBIT_SHOCKED = &"rabbit_shocked"
const STATE_RABBIT_IMPATIENT = &"rabbit_impatient"
const STATE_RABBIT_NOSE_POKING = &"rabbit_nose_poking"
const STATE_RABBIT_EYES_ROLLING = &"rabbit_eyes_rolling"
const STATE_RABBIT_KNOCK_MACHINE = &"rabbit_knock_machine"

# ==========================================
# 全局眼部设置
# ==========================================
@export_category("Eye Appearance (Global)")
@export_group("Textures")
@export var eye_socket_texture: Texture2D ## 基础眼眶纹理 (Sprite.texture)
@export var eye_socket_scale: float = 1.0 ## 缩放比例 (Sprite.scale)

@export_group("Pupil Dynamics")
@export var eye_pupil_initial_offset: Vector2 = Vector2.ZERO ## 瞳孔基准偏移

@export_group("Eye Interaction", "idle_eye_")
@export var idle_eye_max_offset: float = 8.0 ## 眼球跟随最大范围


# ==========================================
# 不耐烦动画
# ==========================================
@export_category("Impatient Config")
@export_group("Trigger", "impatient_")
@export var impatient_gold_threshold: int = 10


@export_group("Eye Style", "impatient_eye_")
@export var impatient_eye_target_texture: Texture2D = preload("res://assets/sprites/the_rabbit/eye_shape_1.png") ## 眯眼时的眼眶形状纹理

@export var impatient_eye_pupil_offset: Vector2 = Vector2.ZERO ## 眯眼时的瞳孔基准偏移 (建议 -0.05 到 0.05)


var _rabbit_root: Node2D

var _left_eye_fill: Sprite2D
var _right_eye_fill: Sprite2D


var _left_eye_mat: ShaderMaterial
var _right_eye_mat: ShaderMaterial

var _playback: AnimationNodeStateMachinePlayback
var _current_state_name: StringName = STATE_RABBIT_IDLE

var _current_lottery_hover_pos: Vector2 = Vector2.ZERO
var _has_hovered_lottery: bool = false

# AnimationTree 条件变量（持续状态）
var _cond_is_submitting: bool = false
var _cond_is_low_gold: bool = false
var _cond_is_high_gold: bool = true # 与 is_low_gold 相反

# AnimationTree 触发器（一次性）
var _trig_order_success: bool = false
var _trig_exit_submitting: bool = false
var _trig_pool_clicked: bool = false
var _trig_recycle_lid_closed: bool = false


func _ready() -> void:
	_find_required_nodes()
	_cache_initial_transforms()
	_init_animation_tree()
	
	_connect_to_ui_state()
	
	if GameManager:
		GameManager.gold_changed.connect(_on_gold_changed)
		# 初始化金币状态
		_on_gold_changed(GameManager.gold)
	
	EventBus.order_completed.connect(func(_ctx):
		_trig_order_success = true
		print("[RabbitAnimator] Trigger: order_success")
	)
	EventBus.draw_requested.connect(func(_ctx):
		_trig_pool_clicked = true
		print("[RabbitAnimator] Trigger: pool_clicked")
	)
	EventBus.item_recycled.connect(func(_idx, _item):
		_trig_recycle_lid_closed = true
		print("[RabbitAnimator] Trigger: recycle_lid_closed")
	)
	
	add_to_group("debug_animator")

	# 连接奖池悬停信号（通过 EventBus）
	EventBus.game_event.connect(_on_bus_game_event)

func _connect_to_ui_state() -> void:
	var ui_root = get_tree().get_first_node_in_group("game_2d_ui")
	if ui_root:
		var sm = ui_root.get_node_or_null("UIStateMachine")
		if sm:
			sm.state_changed.connect(_on_ui_state_changed)
			print("[RabbitAnimator] UI 状态机连接成功")

func _on_ui_state_changed(_from: StringName, to: StringName) -> void:
	# 更新状态条件
	var was_submitting = _cond_is_submitting
	_cond_is_submitting = (to == &"Submitting")
	
	# 检测退出提交状态
	if was_submitting and not _cond_is_submitting:
		_trig_exit_submitting = true
		print("[RabbitAnimator] Trigger: exit_submitting")

func _on_gold_changed(new_gold: int) -> void:
	_cond_is_low_gold = (new_gold <= impatient_gold_threshold)
	_cond_is_high_gold = (new_gold > impatient_gold_threshold)


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
	
	_left_eye_fill = p.find_child("TheRabbitLeftEyeFill", true, false)
	_right_eye_fill = p.find_child("TheRabbitRightEyeFill", true, false)
	
	
	print("[RabbitAnimator] Left Eye Fill found: ", _left_eye_fill != null)
	print("[RabbitAnimator] Right Eye Fill found: ", _right_eye_fill != null)

func _cache_initial_transforms() -> void:
	_init_eye_materials()

func _init_eye_materials() -> void:
	# 直接使用 Sprite2D 上已配置的材质
	# 确保材质实例独立 (Resource Local To Scene)，以便独立控制瞳孔
	if _left_eye_fill:
		if _left_eye_fill.material is ShaderMaterial:
			_left_eye_mat = _left_eye_fill.material.duplicate()
			_left_eye_fill.material = _left_eye_mat
			_update_shader_params(_left_eye_mat, true)
		
		# 依然支持纹理/缩放设置
		_left_eye_fill.scale = Vector2(eye_socket_scale, eye_socket_scale)
		if eye_socket_texture:
			_left_eye_fill.texture = eye_socket_texture
			
	if _right_eye_fill:
		if _right_eye_fill.material is ShaderMaterial:
			_right_eye_mat = _right_eye_fill.material.duplicate()
			_right_eye_fill.material = _right_eye_mat
			_update_shader_params(_right_eye_mat, false)
			
		_right_eye_fill.scale = Vector2(eye_socket_scale, eye_socket_scale)
		if eye_socket_texture:
			_right_eye_fill.texture = eye_socket_texture

func _update_shader_params(mat: ShaderMaterial, _is_left: bool) -> void:
	# 只设置必须由脚本实时计算/偏移的参数
	mat.set_shader_parameter("pupil_offset", eye_pupil_initial_offset)

func _init_animation_tree() -> void:
	if anim_tree:
		anim_tree.active = true
		_playback = anim_tree.get("parameters/playback")


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
			print("[RabbitAnimator] State Changed: %s -> %s" % [_current_state_name, tree_state])
			_current_state_name = tree_state
			_enter_state(tree_state)
	
	_update_eye_behavior(delta)
	
	# 同步条件到 AnimationTree
	if anim_tree:
		# 持续状态
		anim_tree.set("parameters/conditions/is_submitting", _cond_is_submitting)
		anim_tree.set("parameters/conditions/is_low_gold", _cond_is_low_gold)
		anim_tree.set("parameters/conditions/is_high_gold", _cond_is_high_gold)
		
		# 处理 Trigger (单帧有效)
		if _trig_order_success:
			anim_tree.set("parameters/conditions/order_success", true)
			_trig_order_success = false
		else:
			anim_tree.set("parameters/conditions/order_success", false)
			
		if _trig_exit_submitting:
			anim_tree.set("parameters/conditions/exit_submitting", true)
			_trig_exit_submitting = false
		else:
			anim_tree.set("parameters/conditions/exit_submitting", false)
			
		if _trig_pool_clicked:
			anim_tree.set("parameters/conditions/pool_clicked", true)
			_trig_pool_clicked = false
		else:
			anim_tree.set("parameters/conditions/pool_clicked", false)
			
		if _trig_recycle_lid_closed:
			anim_tree.set("parameters/conditions/recycle_lid_closed", true)
			_trig_recycle_lid_closed = false
		else:
			anim_tree.set("parameters/conditions/recycle_lid_closed", false)


func _update_eye_behavior(_delta: float) -> void:
	if _current_state_name == STATE_RABBIT_SHOCKED: return
	if _current_state_name == STATE_RABBIT_IMPATIENT:
		_set_eye_pupil_offset(impatient_eye_pupil_offset)
		return
	
	var target_pos = _current_lottery_hover_pos if (_current_state_name == STATE_RABBIT_EYES_ROLLING and _has_hovered_lottery) else _rabbit_root.get_global_mouse_position()
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
	if _playback: _playback.travel(STATE_RABBIT_SHOCKED)


func reset_to_idle() -> void:
	if _playback: _playback.travel(STATE_RABBIT_IDLE)

func debug_travel_to_state(state_name: StringName) -> void:
	if _playback:
		_playback.travel(state_name)
		print("[RabbitAnimator] Debug travel to state: ", state_name)
