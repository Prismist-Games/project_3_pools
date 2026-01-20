extends SkillEffect
class_name Lucky7SkillEffect

## 【幸运 7】
## 金币个位数为 7 时进入待命状态，抽奖时传说概率翻倍。

@export var last_digit: int = 7
@export var legendary_multiplier: float = 2.0

var _is_pending: bool = false


func initialize() -> void:
	# 监听金币变化信号
	if not GameManager.gold_changed.is_connected(_on_gold_changed):
		GameManager.gold_changed.connect(_on_gold_changed)
	
	# 初始化状态检查（不发信号，只更新内部状态）
	_is_pending = (GameManager.gold % 10) == last_digit


func on_event(event_id: StringName, context: RefCounted) -> void:
	if event_id == &"draw_requested":
		_handle_draw_requested(context as DrawContext)


func _on_gold_changed(_amount: int) -> void:
	# 金币数量变化时检查状态
	_check_and_update_pending_state()


func _check_and_update_pending_state() -> void:
	var should_be_pending = (GameManager.gold % 10) == last_digit
	
	if should_be_pending and not _is_pending:
		# 进入待命状态
		_is_pending = true
		triggered.emit(TRIGGER_PENDING)
	elif not should_be_pending and _is_pending:
		# 退出待命状态，静默清除 UI 高亮（不播放激活动画）
		_is_pending = false
		triggered.emit(TRIGGER_CANCEL)


func _handle_draw_requested(ctx: DrawContext) -> void:
	if ctx == null:
		return
	
	# 只有在待命状态下才触发激活
	if _is_pending:
		triggered.emit(TRIGGER_ACTIVATE)
		ctx.multiply_rarity_weight(Constants.Rarity.LEGENDARY, legendary_multiplier)


func get_visual_state() -> String:
	if (GameManager.gold % 10) == last_digit:
		return TRIGGER_PENDING
	return ""
