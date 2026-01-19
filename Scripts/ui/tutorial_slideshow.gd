extends CanvasLayer

## 教程幻灯片组件
##
## 显示中英双语教程图片，支持翻页和关闭。
## 作为 Packed Scene 可复用，可通过 show_tutorial() 显示。

## 教程关闭信号
signal tutorial_closed

## 当前幻灯片索引 (1-5)
var current_slide_index: int = 1

## 总幻灯片数量
const TOTAL_SLIDES: int = 5

## 淡入淡出动画时长（秒）
const FADE_DURATION: float = 0.3

## 节点引用
@onready var background: ColorRect = $Background
@onready var slide_image: TextureRect = $Background/SlideImage
@onready var prev_button: Button = $Background/ButtonContainer/PrevButton
@onready var next_button: Button = $Background/ButtonContainer/NextButton
@onready var close_button: Button = $Background/CloseButton

## 是否正在显示
var _is_showing: bool = false


func _ready() -> void:
	# 初始隐藏
	background.modulate.a = 0.0
	visible = false
	
	# 连接按钮信号
	prev_button.pressed.connect(_on_prev_pressed)
	next_button.pressed.connect(_on_next_pressed)
	close_button.pressed.connect(_on_close_pressed)
	
	# 监听语言变更
	if LocaleManager:
		LocaleManager.locale_changed.connect(_on_locale_changed)


## 显示教程（带淡入动画）
func show_tutorial() -> void:
	if _is_showing:
		return
	
	_is_showing = true
	current_slide_index = 1
	_update_slide()
	_update_button_states()
	
	visible = true
	var tween = create_tween()
	tween.tween_property(background, "modulate:a", 1.0, FADE_DURATION)


## 隐藏教程（带淡出动画）
func hide_tutorial() -> void:
	if not _is_showing:
		return
	
	_is_showing = false
	var tween = create_tween()
	tween.tween_property(background, "modulate:a", 0.0, FADE_DURATION)
	tween.tween_callback(func(): visible = false)
	tween.tween_callback(func(): tutorial_closed.emit())


## 是否正在显示
func is_showing() -> bool:
	return _is_showing


## 上一页按钮回调
func _on_prev_pressed() -> void:
	if current_slide_index <= 1:
		return
	
	_transition_to_slide(current_slide_index - 1)


## 下一页按钮回调
func _on_next_pressed() -> void:
	if current_slide_index >= TOTAL_SLIDES:
		return
	
	_transition_to_slide(current_slide_index + 1)


## 关闭按钮回调
func _on_close_pressed() -> void:
	hide_tutorial()


## 语言变更回调
func _on_locale_changed(_new_locale: String) -> void:
	if _is_showing:
		_update_slide()


## 带过渡动画切换到指定页（快门式切换）
func _transition_to_slide(new_index: int) -> void:
	var tween = create_tween()
	
	# 瞬间变黑（快门关闭）
	tween.tween_property(slide_image, "modulate:a", 0.0, 0.05)
	
	# 短暂黑屏停顿（模拟胶片切换）
	tween.tween_interval(0.08)
	
	# 切换图片（黑屏期间）
	tween.tween_callback(func():
		current_slide_index = new_index
		_update_slide()
		_update_button_states()
	)
	
	# 瞬间显示新图片（快门打开）
	tween.tween_property(slide_image, "modulate:a", 1.0, 0.05)


## 更新当前幻灯片图片
func _update_slide() -> void:
	var texture = LocaleManager.get_tutorial_slide_texture(current_slide_index)
	if texture:
		slide_image.texture = texture


## 更新按钮状态
func _update_button_states() -> void:
	# 第1页禁用"上一页"
	prev_button.disabled = (current_slide_index <= 1)
	
	# 第5页禁用"下一页"
	next_button.disabled = (current_slide_index >= TOTAL_SLIDES)
