extends SkillEffect
class_name Lucky7SkillEffect

## 【幸运 7】
## 当前金币数量为 lucky_number 的倍数或尾数为 lucky_number 时，
## 抽到史诗和传说的概率乘以 rarity_multiplier。
## VFX: 条件满足时白色(Pending)，抽取物品时变黄色(Activate)

@export var lucky_number: int = 7
@export var rarity_multiplier: float = 2.0

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
	_is_pending = _check_lucky_condition(GameManager.gold)
	
	# 状态变化时发送信号
	if _is_pending and not was_pending:
		triggered.emit(TRIGGER_PENDING)
	elif not _is_pending and was_pending:
		# 从激活状态变为非激活状态（金币变化导致）
		triggered.emit(TRIGGER_DEACTIVATE)


func _handle_draw_requested(ctx: DrawContext) -> void:
	if ctx == null: return
	
	if not _check_lucky_condition(GameManager.gold):
		return
	
	# 应用史诗和传说概率翻倍
	ctx.multiply_rarity_weight(Constants.Rarity.EPIC, rarity_multiplier)
	ctx.multiply_rarity_weight(Constants.Rarity.LEGENDARY, rarity_multiplier)


func _handle_item_obtained() -> void:
	# 如果处于激活状态，消耗并显示黄色VFX
	if _is_pending:
		triggered.emit(TRIGGER_ACTIVATE)
		# 注意：_is_pending 状态将在下次 gold_changed 时更新


func get_visual_state() -> String:
	if _is_pending:
		return TRIGGER_PENDING
	return ""


## 检查是否满足幸运条件：7的倍数或尾数为7
func _check_lucky_condition(gold: int) -> bool:
	return gold % lucky_number == 0 or gold % 10 == lucky_number
