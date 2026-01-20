extends Control

@onready var button_zh: TextureButton = $Button_ZH
@onready var button_en: TextureButton = $Button_EN
@onready var credit_button: TextureButton = $"Credit Button"
@onready var back_button: TextureButton = $"Back Button"
@onready var color_rect: ColorRect = $ColorRect
@onready var the_rabbit: Node2D = $"The Rabbit"
@onready var camera: Camera2D = $Camera2D

var target_scene_path: String = "res://scenes/Game2D.tscn"
var loading_started: bool = false
var load_done: bool = false
var rabbit_anim_done: bool = false
var transition_started: bool = false

func _ready() -> void:
	# 确保按钮中心缩放
	button_zh.pivot_offset = button_zh.size / 2
	button_en.pivot_offset = button_en.size / 2
	
	button_zh.pressed.connect(_on_language_selected.bind("zh"))
	button_en.pressed.connect(_on_language_selected.bind("en"))
	credit_button.pressed.connect(_on_credit_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)

func _on_language_selected(locale: String) -> void:
	if loading_started:
		return
	loading_started = true
	
	TranslationServer.set_locale(locale)
	
	# 1. 按钮缩放至0
	var tween_buttons: Tween = create_tween().set_parallel(true)
	tween_buttons.tween_property(button_zh, "scale", Vector2.ZERO, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween_buttons.tween_property(button_en, "scale", Vector2.ZERO, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween_buttons.tween_property(credit_button, "scale", Vector2.ZERO, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween_buttons.tween_property(back_button, "scale", Vector2.ZERO, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	
	# 2. 开始后台加载
	ResourceLoader.load_threaded_request(target_scene_path)
	
	# 等待按钮动画播完
	await tween_buttons.finished
	
	# 3. 播放小兔子动画 (5秒)
	var tween_rabbit: Tween = create_tween().set_parallel(true)
	tween_rabbit.tween_property(the_rabbit, "scale", Vector2(1.1, 1.1), 3.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween_rabbit.tween_property(the_rabbit, "position", Vector2(1401, 1979), 3.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	
	# 必须等待兔子动画播完
	await tween_rabbit.finished
	rabbit_anim_done = true
	
	# 播完后尝试转场（如果此时加载也完成了，就会直接开始）
	_check_and_start_transition()

func _process(_delta: float) -> void:
	if loading_started and not load_done:
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(target_scene_path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			load_done = true
			# 每次加载状态更新，尝试转场
			_check_and_start_transition()

func _check_and_start_transition() -> void:
	# 只有加载完成 且 兔子动画走完 且 还没开始转场，才执行转场
	if load_done and rabbit_anim_done and not transition_started:
		_start_transition_sequence()

func _start_transition_sequence() -> void:
	transition_started = true
	
	# 在遮罩消失前，先把 Game2D 实例化并加到层级底层
	var packed_scene: PackedScene = ResourceLoader.load_threaded_get(target_scene_path)
	var game_scene = packed_scene.instantiate()
	
	# 将新场景移到 Menu 后面
	get_tree().root.add_child(game_scene)
	get_tree().root.move_child(game_scene, 0)
	
	# 设置为当前场景
	get_tree().current_scene = game_scene
	
	# 6. 开始缩小遮罩，透出后面的 Game2D
	var tween_transition: Tween = create_tween().set_parallel(true)
	tween_transition.tween_property(color_rect, "scale", Vector2.ZERO, 1.0).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
	tween_transition.tween_property(the_rabbit, "modulate:a", 0.0, 0.2).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT).set_delay(0.6)
	
	# 7. 动画结束，发出信号并移除菜单
	tween_transition.finished.connect(func():
		EventBus.menu_transition_finished.emit()
		queue_free()
	)


func _on_credit_button_pressed() -> void:
	var tween_credit: Tween = create_tween()
	tween_credit.tween_property(camera, "position:y", 5059.0, 1.0).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


func _on_back_button_pressed() -> void:
	var tween_back: Tween = create_tween()
	tween_back.tween_property(camera, "position:y", 1689.0, 1.0).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
