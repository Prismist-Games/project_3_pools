class_name TheRabbitAnimator
extends Node

## 兔子吉祥物动画控制器
## 实现类似招财猫/玩具猴子的循环摆动动画（不含整体晃动）
## 包含眼珠跟随鼠标功能

# 动画参数
@export_group("左臂摇摆 (招手)")
@export var left_arm_swing_amplitude_degrees: float = 8.0 # 减小幅度防止穿帮
@export var left_arm_swing_speed: float = 2.5
@export var left_arm_pivot_offset: Vector2 = Vector2(0, 50)

@export_group("耳朵抖动")
@export var ear_rotation_amplitude_degrees: float = 1.0 # 进一步减小幅度防止头部穿帮
@export var ear_rotation_speed: float = 3.0
@export var ear_phase_offset: float = 0.5 # 左右耳相位差

@export_group("胡须轻摆")
@export var mustache_rotation_amplitude_degrees: float = 3.0
@export var mustache_rotation_speed: float = 4.0

@export_group("眼珠注视")
@export var max_eye_offset: float = 8.0 # 眼珠移动最大半径, 增大以提升可见度
@export var eye_follow_speed: float = 10.0 # 眼珠跟随平滑速度

# 节点引用 (通过 @onready 缓存)
@onready var _rabbit_root: Node2D = get_parent() as Node2D
@onready var _left_arm: Sprite2D = _rabbit_root.get_node_or_null("TheRabbitLeftArm")
@onready var _left_ear: Sprite2D = _rabbit_root.get_node_or_null("TheRabbitLeftEar")
@onready var _right_ear: Sprite2D = _rabbit_root.get_node_or_null("TheRabbitRightEar")
@onready var _mustache_left: Sprite2D = _rabbit_root.get_node_or_null("TheRabbitMustacheLeft")
@onready var _mustache_right: Sprite2D = _rabbit_root.get_node_or_null("TheRabbitMustacheRight")
# 眼珠引用 (注意层级：EyeballFill 是 EyeFill 的子节点)
@onready var _left_eyeball: Sprite2D = _rabbit_root.get_node_or_null("TheRabbitLeftEyeFill/TheRabbitLeftEyeballFill")
@onready var _right_eyeball: Sprite2D = _rabbit_root.get_node_or_null("TheRabbitRightEyeFill/TheRabbitRightEyeballFill")

# 初始状态缓存
var _left_arm_initial_rotation: float = 0.0
var _left_ear_initial_rotation: float = 0.0
var _right_ear_initial_rotation: float = 0.0
var _mustache_left_initial_rotation: float = 0.0
var _mustache_right_initial_rotation: float = 0.0
# 眼珠初始位置
var _left_eyeball_initial_pos: Vector2 = Vector2.ZERO
var _right_eyeball_initial_pos: Vector2 = Vector2.ZERO

# 内部计时器
var _elapsed_time: float = 0.0

func _ready() -> void:
	_cache_initial_states()

func _cache_initial_states() -> void:
	if _left_arm:
		_left_arm_initial_rotation = _left_arm.rotation
	if _left_ear:
		_left_ear_initial_rotation = _left_ear.rotation
	if _right_ear:
		_right_ear_initial_rotation = _right_ear.rotation
	if _mustache_left:
		_mustache_left_initial_rotation = _mustache_left.rotation
	if _mustache_right:
		_mustache_right_initial_rotation = _mustache_right.rotation
	
	if _left_eyeball:
		_left_eyeball_initial_pos = _left_eyeball.position
	if _right_eyeball:
		_right_eyeball_initial_pos = _right_eyeball.position

func _process(delta: float) -> void:
	_elapsed_time += delta
	_animate_left_arm()
	_animate_ears()
	_animate_mustache()
	_animate_eyes(delta)

func _animate_left_arm() -> void:
	if not _left_arm:
		return
	var swing_angle: float = sin(_elapsed_time * left_arm_swing_speed) * deg_to_rad(left_arm_swing_amplitude_degrees)
	_left_arm.rotation = _left_arm_initial_rotation + swing_angle

func _animate_ears() -> void:
	if _left_ear:
		var left_ear_angle: float = sin(_elapsed_time * ear_rotation_speed) * deg_to_rad(ear_rotation_amplitude_degrees)
		_left_ear.rotation = _left_ear_initial_rotation + left_ear_angle
	if _right_ear:
		var right_ear_angle: float = sin(_elapsed_time * ear_rotation_speed + ear_phase_offset * TAU) * deg_to_rad(ear_rotation_amplitude_degrees)
		_right_ear.rotation = _right_ear_initial_rotation + right_ear_angle

func _animate_mustache() -> void:
	if _mustache_left:
		var left_angle: float = sin(_elapsed_time * mustache_rotation_speed) * deg_to_rad(mustache_rotation_amplitude_degrees)
		_mustache_left.rotation = _mustache_left_initial_rotation + left_angle
	if _mustache_right:
		var right_angle: float = sin(_elapsed_time * mustache_rotation_speed + PI) * deg_to_rad(mustache_rotation_amplitude_degrees)
		_mustache_right.rotation = _mustache_right_initial_rotation + right_angle

func _animate_eyes(delta: float) -> void:
	var mouse_pos: Vector2 = _rabbit_root.get_global_mouse_position()
	
	if _left_eyeball:
		_update_eye_position(_left_eyeball, _left_eyeball_initial_pos, mouse_pos, delta)
	
	if _right_eyeball:
		_update_eye_position(_right_eyeball, _right_eyeball_initial_pos, mouse_pos, delta)

func _update_eye_position(eye: Sprite2D, initial_pos: Vector2, target_pos_global: Vector2, delta: float) -> void:
	# 将目标点(鼠标)转换为相对于眼珠父节点的局部坐标
	var target_local: Vector2 = eye.get_parent().to_local(target_pos_global)
	var direction: Vector2 = target_local - initial_pos
	
	# 限制移动范围
	if direction.length() > max_eye_offset:
		direction = direction.normalized() * max_eye_offset
		
	var target_eye_pos: Vector2 = initial_pos + direction
	
	# 平滑移动
	eye.position = eye.position.lerp(target_eye_pos, eye_follow_speed * delta)
