class_name CancelButtonController
extends Node

## 全局取消按钮控制器
##
## 管理 The Rabbit/QuestSystem/Cancel 节点的显隐和交互逻辑。
## 取代右键取消操作，统一通过左键点击 Cancel 按钮来取消当前可取消状态。

signal cancel_pressed

## 节点引用
var _cancel_root: Node2D = null
var _cancel_button: Sprite2D = null
var _cancel_dialog: Sprite2D = null
var _cancel_dialog_label: RichTextLabel = null
var _cancel_input_area: Control = null

## 主控制器引用
var game_ui: Node = null

## 动画状态
var _is_visible: bool = false
var _is_button_mode: bool = false # true=button模式, false=dialog模式
var _is_animating: bool = false
var _is_pressed: bool = false
var _is_hovered: bool = false

## 对话显示计时器
var _dialog_hide_timer: SceneTreeTimer = null

## 随机对话文本
const DIALOG_TEXTS: Array[String] = [
	"CANCEL_DIALOG_1",
	"CANCEL_DIALOG_2",
	"CANCEL_DIALOG_3",
	"CANCEL_DIALOG_4",
	"CANCEL_DIALOG_5",
]

## 动画配置
const SCALE_ANIMATION_DURATION: float = 0.25
const PRESS_SCALE_FACTOR: float = 0.9
const HOVER_BRIGHTNESS: float = 1.3
const DIALOG_DISPLAY_DURATION: float = 2.0
const DIALOG_VISIBLE_RATIO_DURATION: float = 0.4


func setup(cancel_root: Node2D) -> void:
	_cancel_root = cancel_root
	if not _cancel_root:
		push_error("[CancelButtonController] Cancel 根节点未找到")
		return
	
	_cancel_button = _cancel_root.get_node_or_null("Cancel_button") as Sprite2D
	_cancel_dialog = _cancel_root.get_node_or_null("Cancel_dialog") as Sprite2D
	
	if _cancel_button:
		_cancel_input_area = _cancel_button.get_node_or_null("Input Area") as Control
	
	if _cancel_dialog:
		_cancel_dialog_label = _cancel_dialog.get_node_or_null("Cancel Dialog_label") as RichTextLabel
	
	# 初始状态：隐藏
	_cancel_root.scale = Vector2.ZERO
	_is_visible = false
	
	# 初始化子节点状态
	if _cancel_button:
		_cancel_button.visible = false
	if _cancel_dialog:
		_cancel_dialog.visible = true # dialog 在隐藏时是默认可见的（但 root scale=0）
	
	# 连接输入信号
	_connect_input_signals()


func _connect_input_signals() -> void:
	if not _cancel_input_area:
		return
	
	if not _cancel_input_area.gui_input.is_connected(_on_input_area_input):
		_cancel_input_area.gui_input.connect(_on_input_area_input)
	if not _cancel_input_area.mouse_entered.is_connected(_on_input_area_mouse_entered):
		_cancel_input_area.mouse_entered.connect(_on_input_area_mouse_entered)
	if not _cancel_input_area.mouse_exited.is_connected(_on_input_area_mouse_exited):
		_cancel_input_area.mouse_exited.connect(_on_input_area_mouse_exited)


## 进入可取消状态时调用：显示 Cancel 按钮
func show_cancel_button() -> void:
	if _is_animating:
		# 如果正在隐藏动画中，直接终止并重新显示
		pass
	
	# 取消对话隐藏计时器（如果有）
	_cancel_dialog_hide_timer()
	
	_is_button_mode = true
	_is_visible = true
	
	# 设置按钮可见，对话不可见
	if _cancel_button:
		_cancel_button.visible = true
		_cancel_button.modulate = Color.WHITE
	if _cancel_dialog:
		_cancel_dialog.visible = false
	if _cancel_input_area:
		_cancel_input_area.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# 播放 scale 从 0 到 1 的动画
	_play_scale_animation(Vector2.ONE)


## 退出可取消状态时调用（非用户点击）：静默隐藏 Cancel 按钮
func hide_cancel_button_silent() -> void:
	if not _is_visible:
		return
	
	# 如果当前正在播放主动取消的对话序列，则不进行静默隐藏，让对话自然播完
	if _is_animating and not _is_button_mode:
		return
		
	_cancel_dialog_hide_timer()
	
	_is_button_mode = false
	_is_visible = false
	
	# 重置视觉状态
	_reset_button_visual_state()
	
	# 播放 scale 从 1 到 0 的动画
	_play_scale_animation(Vector2.ZERO)


## 用户点击取消后调用：播放完整的取消+对话流程
func trigger_cancel() -> void:
	if _is_animating or not _is_visible:
		return
	
	# 标记进入取消序列模式，防止被 hide_cancel_button_silent 打断
	_is_animating = true
	_is_button_mode = false
	
	# 发出取消信号
	cancel_pressed.emit()
	
	# 播放取消流程动画
	_play_cancel_sequence()


## 播放完整的取消序列动画
func _play_cancel_sequence() -> void:
	# 注意：_is_animating 和 _is_button_mode 已在 trigger_cancel 中设置
	# 禁用输入区域
	if _cancel_input_area:
		_cancel_input_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# 1. Cancel 按钮 scale 从 1 到 0
	_cancel_root.scale = Vector2.ONE
	var tween1 = game_ui.create_tween() if game_ui else _cancel_root.create_tween()
	tween1.tween_property(_cancel_root, "scale", Vector2.ZERO, SCALE_ANIMATION_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	await tween1.finished
	
	# 2. 切换到 dialog 模式
	if _cancel_button:
		_cancel_button.visible = false
	if _cancel_dialog:
		_cancel_dialog.visible = true
	
	# 设置随机对话文本
	if _cancel_dialog_label:
		var key = DIALOG_TEXTS[randi() % DIALOG_TEXTS.size()]
		_cancel_dialog_label.text = tr(key)
		_cancel_dialog_label.visible_ratio = 0.0
	
	# 3. Dialog scale 从 0 到 1，同时 visible_ratio 从 0 到 1
	var tween2 = game_ui.create_tween() if game_ui else _cancel_root.create_tween()
	tween2.set_parallel(true)
	tween2.tween_property(_cancel_root, "scale", Vector2.ONE, SCALE_ANIMATION_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _cancel_dialog_label:
		tween2.tween_property(_cancel_dialog_label, "visible_ratio", 1.0, DIALOG_VISIBLE_RATIO_DURATION) \
			.set_delay(SCALE_ANIMATION_DURATION * 0.5)
	await tween2.finished
	
	_is_animating = false
	
	# 4. 等待数秒后 scale 从 1 到 0
	_dialog_hide_timer = game_ui.get_tree().create_timer(DIALOG_DISPLAY_DURATION) if game_ui else _cancel_root.get_tree().create_timer(DIALOG_DISPLAY_DURATION)
	await _dialog_hide_timer.timeout
	_dialog_hide_timer = null
	
	# 如果在等待期间又进入了按钮模式，则不播放隐藏动画
	if _is_button_mode:
		return
	
	_is_visible = false
	_play_scale_animation(Vector2.ZERO)


## 播放 scale 动画
func _play_scale_animation(target_scale: Vector2) -> void:
	if not _cancel_root:
		return
	
	_is_animating = true
	var tween = game_ui.create_tween() if game_ui else _cancel_root.create_tween()
	
	if target_scale == Vector2.ZERO:
		tween.tween_property(_cancel_root, "scale", target_scale, SCALE_ANIMATION_DURATION) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	else:
		tween.tween_property(_cancel_root, "scale", target_scale, SCALE_ANIMATION_DURATION) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	tween.tween_callback(func():
		_is_animating = false
	)


## 重置按钮视觉状态
func _reset_button_visual_state() -> void:
	_is_pressed = false
	_is_hovered = false
	if _cancel_button:
		_cancel_button.modulate = Color.WHITE
		_cancel_button.scale = Vector2.ONE


## 取消对话隐藏计时器
func _cancel_dialog_hide_timer() -> void:
	_dialog_hide_timer = null # SceneTreeTimer 无法手动取消，只能置空引用


## 输入区域事件处理
func _on_input_area_input(event: InputEvent) -> void:
	if not _is_button_mode or _is_animating:
		return
	
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	
	if event.pressed:
		# 按下：scale 缩小
		_is_pressed = true
		_play_button_press_animation()
	else:
		# 松开：scale 复位并触发取消
		if _is_pressed:
			_is_pressed = false
			_play_button_release_animation()
			trigger_cancel()


## Hover 进入
func _on_input_area_mouse_entered() -> void:
	if not _is_button_mode or _is_animating:
		return
	
	_is_hovered = true
	_update_hover_visual()


## Hover 离开
func _on_input_area_mouse_exited() -> void:
	if not _is_button_mode:
		return
	
	_is_hovered = false
	_is_pressed = false # 如果鼠标移出，也清除按下状态
	_update_hover_visual()
	
	# 如果在按下状态下移出，复位 scale
	if _cancel_button and _cancel_button.scale != Vector2.ONE:
		var tween = game_ui.create_tween() if game_ui else _cancel_button.create_tween()
		tween.tween_property(_cancel_button, "scale", Vector2.ONE, 0.1) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## 更新 Hover 高亮
func _update_hover_visual() -> void:
	if not _cancel_button:
		return
	
	var target_modulate = Color(HOVER_BRIGHTNESS, HOVER_BRIGHTNESS, HOVER_BRIGHTNESS, 1.0) if _is_hovered else Color.WHITE
	var tween = game_ui.create_tween() if game_ui else _cancel_button.create_tween()
	tween.tween_property(_cancel_button, "modulate", target_modulate, 0.1)


## 播放按钮按下动画
func _play_button_press_animation() -> void:
	if not _cancel_button:
		return
	
	var tween = game_ui.create_tween() if game_ui else _cancel_button.create_tween()
	tween.tween_property(_cancel_button, "scale", Vector2.ONE * PRESS_SCALE_FACTOR, 0.1) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## 播放按钮松开动画
func _play_button_release_animation() -> void:
	if not _cancel_button:
		return
	
	var tween = game_ui.create_tween() if game_ui else _cancel_button.create_tween()
	tween.tween_property(_cancel_button, "scale", Vector2.ONE * 1.05, 0.1) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_cancel_button, "scale", Vector2.ONE, 0.1) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## 检查当前是否处于按钮可见状态
func is_cancel_visible() -> bool:
	return _is_visible and _is_button_mode
