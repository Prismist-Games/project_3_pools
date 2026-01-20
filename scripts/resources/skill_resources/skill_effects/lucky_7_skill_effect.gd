extends SkillEffect
class_name Lucky7SkillEffect

## 【幸运 7】
## 当前金币数量尾数为 last_digit 时，抽到传说的概率乘以 legendary_multiplier。
## VFX: 金币尾数=7时白色(Pending)，抽取物品时变黄色(Activate)

@export var last_digit: int = 7
@export var legendary_multiplier: float = 2.0

## 当前是否处于激活状态
var _is_pending: bool = false


func on_event(event_id: StringName, context: RefCounted) -> void:
	match event_id:
		&"gold_changed":
			_handle_gold_changed()
		&"draw_requested":
			_handle_draw_requested(context as DrawContext)
		&"item_obtained":
			_handle_item_obtained()


func _handle_gold_changed() -> void:
	var was_pending = _is_pending
	_is_pending = GameManager.gold % 10 == last_digit
	
	# 状态变化时发送信号
	if _is_pending and not was_pending:
		triggered.emit(TRIGGER_PENDING)
	elif not _is_pending and was_pending:
		# 从激活状态变为非激活状态（金币变化导致）
		triggered.emit(TRIGGER_DEACTIVATE)


func _handle_draw_requested(ctx: DrawContext) -> void:
	if ctx == null: return
	
	if GameManager.gold % 10 != last_digit:
		return
	
	# 应用传说概率翻倍
	ctx.multiply_rarity_weight(Constants.Rarity.LEGENDARY, legendary_multiplier)


func _handle_item_obtained() -> void:
	# 如果处于激活状态，消耗并显示黄色VFX
	if _is_pending:
		triggered.emit(TRIGGER_ACTIVATE)
		# 注意：_is_pending 状态将在下次 gold_changed 时更新


func get_visual_state() -> String:
	if _is_pending:
		return TRIGGER_PENDING
	return ""
