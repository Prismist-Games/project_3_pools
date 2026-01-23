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


@export_group("Blink Settings", "blink_")
@export var blink_interval_min: float = 2.0 ## 自动眨眼最小间隔 (秒)
@export var blink_interval_max: float = 5.0 ## 自动眨眼最大间隔 (秒)
@export var blink_duration: float = 0.1 ## 单次眨眼闭合时间
@export var auto_blink_enabled: bool = true ## 是否默认开启自动眨眼


var _blink_timer: float = 0.0


# ==========================================
# 不耐烦动画
# ==========================================
@export_category("Impatient Config")
@export_group("Trigger", "impatient_")
@export var impatient_gold_threshold: int = 10


var _left_eye_fill: Sprite2D
var _right_eye_fill: Sprite2D


var _playback: AnimationNodeStateMachinePlayback
var _current_state_name: StringName = STATE_RABBIT_IDLE


# AnimationTree 条件变量（持续状态）
var _cond_is_submitting: bool = false
var _cond_is_low_gold: bool = false


# AnimationTree 触发器（一次性）
var _trig_order_success: bool = false
var _trig_exit_submitting: bool = false
var _trig_pool_clicked: bool = false
var _trig_recycle_lid_closed: bool = false

var _has_recycled_items: bool = false # 追踪回收周期内是否有物品成功回收
var _era_nodes: Array[Node2D] = []

# ... existing code ...

func _ready() -> void:
	_find_required_nodes()
	_cache_initial_transforms()
	_init_animation_tree()
	
	_connect_to_ui_state()

	if GameManager:
		GameManager.gold_changed.connect(_on_gold_changed)
		# 初始化金币状态
		_on_gold_changed(GameManager.gold)
	
	if EraManager:
		EraManager.era_changed.connect(_update_era_visuals)
		_update_era_visuals(EraManager.current_era_index)
	
	EventBus.order_completed.connect(func(_ctx):
		_trig_order_success = true
		if anim_tree:
			anim_tree.set("parameters/conditions/order_success", true)
		print("[RabbitAnimator] Trigger: order_success")
	)
	EventBus.draw_requested.connect(func(_ctx):
		_trig_pool_clicked = true
		if anim_tree:
			anim_tree.set("parameters/conditions/pool_clicked", true)
		print("[RabbitAnimator] Trigger: pool_clicked")
	)
	EventBus.item_recycled.connect(func(_idx, _item):
		_has_recycled_items = true
	)
	EventBus.game_event.connect(_on_game_event)
	

	_reset_blink_timer()

func _connect_to_ui_state() -> void:
	# 等待一帧，确保 Game2DUI._init_state_machine() 完成 UIStateMachine 的添加
	await get_tree().process_frame
	
	var ui_root = get_tree().get_first_node_in_group("game_2d_ui")
	if ui_root:
		var sm = ui_root.get_node_or_null("UIStateMachine")
		if sm:
			sm.state_changed.connect(_on_ui_state_changed)
			print("[RabbitAnimator] UI 状态机连接成功")
		else:
			push_warning("[RabbitAnimator] UIStateMachine 未找到，Submitting 状态将无法触发动画")
		
		# 连接 PoolController 的 hover 信号
		var pc = ui_root.get("pool_controller")
		if pc:
			pc.slot_hovered.connect(_on_pool_hovered)
			pc.slot_unhovered.connect(_on_pool_unhovered)
			print("[RabbitAnimator] PoolController 信号连接成功")

func _on_ui_state_changed(_from: StringName, to: StringName) -> void:
	# 更新状态条件
	var was_submitting = _cond_is_submitting
	_cond_is_submitting = (to == &"Submitting")
	
	# 立即更新 AnimationTree
	if anim_tree:
		anim_tree.set("parameters/conditions/is_submitting", _cond_is_submitting)
	
	# 检测退出提交状态
	if was_submitting and not _cond_is_submitting:
		_trig_exit_submitting = true
		if anim_tree:
			anim_tree.set("parameters/conditions/exit_submitting", true)
		print("[RabbitAnimator] Trigger: exit_submitting")

func _on_gold_changed(new_gold: int) -> void:
	var was_low = _cond_is_low_gold
	_cond_is_low_gold = (new_gold <= impatient_gold_threshold)
	
	# 立即更新 AnimationTree
	if anim_tree:
		anim_tree.set("parameters/conditions/is_low_gold", _cond_is_low_gold)
		
		# 如果金币从低变高，且当前在不耐烦状态，则切回普通空闲
		if was_low and not _cond_is_low_gold and _current_state_name == STATE_RABBIT_IMPATIENT:
			reset_to_idle()

func _on_game_event(event_id: StringName, _payload: Variant) -> void:
	if event_id == &"recycle_lid_closed":
		# 只有在本次回收周期中有物品由于操作被成功回收（发出 item_recycled 信号）时，才触发“敲击机器”动画
		if _has_recycled_items:
			_has_recycled_items = false
			_trig_recycle_lid_closed = true
			
			if anim_tree:
				anim_tree.set("parameters/conditions/recycle_lid_closed", true)
			
			if _playback:
				_playback.travel(STATE_RABBIT_KNOCK_MACHINE)
				
			print("[RabbitAnimator] Trigger: recycle_lid_closed (KNOCK_MACHINE)")
		else:
			# 如果只是正常的开关盖子（无回收行为），则不重置 _has_recycled_items 
			# 以免由于动画冲突导致在该周期内应有的回收反馈丢失
			pass


func _find_required_nodes() -> void:
	var p = get_parent()
	
	_left_eye_fill = p.find_child("TheRabbitLeftEyeFill", true, false)
	_right_eye_fill = p.find_child("TheRabbitRightEyeFill", true, false)
	
	
	# print("[RabbitAnimator] Left Eye Fill found: ", _left_eye_fill != null)
	# print("[RabbitAnimator] Right Eye Fill found: ", _right_eye_fill != null)

	# 时代视觉组件 (在 WandFaceFill 下)
	var wand_fill = p.find_child("TheRabbitWandFaceFill", true, false)
	if wand_fill:
		for i in range(1, 5):
			# 优先尝试 PascalCase (Era_X)，回退到 snake_case (era_x)
			var node = wand_fill.get_node_or_null("Era_" + str(i))
			if not node:
				node = wand_fill.get_node_or_null("era_" + str(i))
			
			if node:
				_era_nodes.append(node)
		print("[RabbitAnimator] Era visual nodes found: ", _era_nodes.size())

func _cache_initial_transforms() -> void:
	_init_eye_materials()

func _init_eye_materials() -> void:
	# 确保材质实例独立 (Resource Local To Scene)
	if _left_eye_fill and _left_eye_fill.material:
		_left_eye_fill.material = _left_eye_fill.material.duplicate()
	if _right_eye_fill and _right_eye_fill.material:
		_right_eye_fill.material = _right_eye_fill.material.duplicate()


func _init_animation_tree() -> void:
	if anim_tree:
		anim_tree.active = true
		_playback = anim_tree.get("parameters/playback")

func _enter_state(state: StringName) -> void:
	# 重置所有 Trigger (状态切换完成,单次触发已消费)
	_reset_all_triggers()
	
	# 状态特定逻辑
	match state:
		STATE_RABBIT_IMPATIENT:
			squint_eyes()
		STATE_RABBIT_IDLE:
			set_auto_blink(true)
			restore_eyes()
		STATE_RABBIT_SHOCKED:
			set_auto_blink(false)
			restore_eyes()

## 重置所有 Trigger (在状态切换时调用)
func _reset_all_triggers() -> void:
	_trig_order_success = false
	_trig_exit_submitting = false
	_trig_pool_clicked = false
	_trig_recycle_lid_closed = false
	
	if anim_tree:
		anim_tree.set("parameters/conditions/order_success", false)
		anim_tree.set("parameters/conditions/exit_submitting", false)
		anim_tree.set("parameters/conditions/pool_clicked", false)
		anim_tree.set("parameters/conditions/recycle_lid_closed", false)


## 开启/停止自动眨眼
func set_auto_blink(enabled: bool) -> void:
	auto_blink_enabled = enabled
	if enabled:
		_reset_blink_timer()

## 执行一次纯粹的眨眼 (不改变形状)
func blink_once() -> void:
	# 眨眼动作：从当前 squash 变到 0 再变回
	for eye in [_left_eye_fill, _right_eye_fill]:
		if not eye or not eye.material: continue
		var current_squash = eye.material.get_shader_parameter("eye_ver_squash")
		var tween = create_tween()
		tween.tween_property(eye.material, "shader_parameter/eye_ver_squash", 0.0, blink_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(eye.material, "shader_parameter/eye_ver_squash", current_squash, blink_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## 供 AnimationPlayer 调用：切换到不耐烦眯眯眼
func squint_eyes() -> void:
	# 眯眼逻辑：通过 shader 参数实现垂直压缩，确保描边均匀
	_run_blink_sequence_shader(0.25)

## 供 AnimationPlayer 调用：恢复正常眼眶
func restore_eyes() -> void:
	# 恢复逻辑：将 shader 参数恢复到 1.0
	_run_blink_sequence_shader(1.0)

## 核心眨眼序列动画 (Shader 版本)
func _run_blink_sequence_shader(target_squash: float) -> void:
	for eye in [_left_eye_fill, _right_eye_fill]:
		if not eye or not eye.material: continue
		var tween = create_tween()
		# 闭眼 (压缩到 0)
		tween.tween_property(eye.material, "shader_parameter/eye_ver_squash", 0.0, blink_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		# 睁眼 (恢复到目标压缩值)
		tween.tween_property(eye.material, "shader_parameter/eye_ver_squash", target_squash, blink_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _reset_blink_timer() -> void:
	_blink_timer = randf_range(blink_interval_min, blink_interval_max)


func _process(delta: float) -> void:
	# 自动眨眼逻辑
	if auto_blink_enabled:
		_blink_timer -= delta
		if _blink_timer <= 0:
			blink_once()
			_reset_blink_timer()

	if _playback:
		var tree_state = _playback.get_current_node()
		if tree_state != _current_state_name:
			print("[RabbitAnimator] State Changed: %s -> %s" % [_current_state_name, tree_state])
			_current_state_name = tree_state
			_enter_state(tree_state)
	

	# AnimationTree 参数更新已完全信号驱动,_process 中不再需要同步


func play_shocked_animation() -> void:
	if _playback: _playback.travel(STATE_RABBIT_SHOCKED)


func reset_to_idle() -> void:
	if _playback: _playback.travel(STATE_RABBIT_IDLE)


# --- 奖池悬浮交互 ---

# 奖池悬浮时：让兔子眼睛直视前方
func _on_pool_hovered(_idx: int, _type: int) -> void:
	pass

## 鼠标离开奖池：恢复默认状态
func _on_pool_unhovered(_idx: int) -> void:
	pass

# --- 时代视觉更新 ---

func _update_era_visuals(era_index: int) -> void:
	if _era_nodes.is_empty():
		return
		
	for i in range(_era_nodes.size()):
		if _era_nodes[i]:
			_era_nodes[i].visible = (i == era_index)
	
	print("[RabbitAnimator] Era visuals updated to Index: ", era_index)
