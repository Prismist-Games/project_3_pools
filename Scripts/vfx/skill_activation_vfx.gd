extends AnimatedSprite2D

## 技能发动时的特效表现
## 对应三种状态：Instant(瞬时), Pending(等待), Activate(激活)

func _ready() -> void:
	# 默认只是播放动画，不做特殊处理
	pass

## 瞬时触发：变黄 -> 停留 -> 消失
func play_instant() -> void:
	play("default")
	# 变成高亮黄色
	modulate = Color(1.5, 1.3, 0.2, 1.0)
	
	# 停留一会儿
	var timer = get_tree().create_timer(1.0)
	await timer.timeout
	
	# 淡出并销毁
	_fade_out()

## 开始等待：原色 -> 循环播放
func play_pending() -> void:
	play("default")
	modulate = Color(1, 1, 1, 1) # 原色

## 激活（从等待状态）：变黄 -> 停留 -> 消失
func activate() -> void:
	# 渐变为黄色
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1.5, 1.3, 0.2, 1.0), 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	await tween.finished
	
	# 停留一会儿
	await get_tree().create_timer(0.8).timeout
	
	# 淡出并销毁
	_fade_out()

func _fade_out() -> void:
	if not is_inside_tree():
		return
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)
