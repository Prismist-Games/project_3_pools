extends SkillEffect
class_name BigOrderExpertSkillEffect

## 【大订单专家】
## 单次同时成功提交 2 个及以上订单时，下次抽取必定获得 史诗(Epic) 品质及以上的物品。
## VFX: 触发buff后显示白色(Pending)，抽取时变黄色(Activate)

@export var order_count_threshold: int = 2
@export var guaranteed_rarity: int = Constants.Rarity.EPIC

## 标记：下一次抽奖是否保底史诗
var _is_buff_active: bool = false


func on_event(event_id: StringName, context: RefCounted) -> void:
	match event_id:
		&"multi_orders_completed":
			_handle_multi_orders(context as ContextProxy)
		&"draw_requested":
			_handle_draw_requested(context as DrawContext)
		&"item_landed_from_draw":
			_handle_item_obtained(context as ItemInstance)


func _handle_multi_orders(ctx: ContextProxy) -> void:
	if ctx == null: return
	
	var count = ctx.get_value("count")
	if count >= order_count_threshold:
		var was_active = _is_buff_active
		_is_buff_active = true
		
		# 触发视觉特效 (获得Buff)
		if not was_active:
			triggered.emit(TRIGGER_PENDING)


func _handle_draw_requested(ctx: DrawContext) -> void:
	if ctx == null: return
	
	if _is_buff_active:
		# 强制提升最低品质到史诗
		# 注意：如果不希望覆盖神话等更高保底，可以使用 maxi
		ctx.min_rarity = maxi(ctx.min_rarity, guaranteed_rarity)


func _handle_item_obtained(item: ItemInstance) -> void:
	if not _is_buff_active: return
	
	if item == null: return
	
	# 只要抽到了东西（且我们处于激活状态），就视为消耗了Buff
	# 为了防止在 Rare 保底逻辑中被提前截胡（比如时来运转），我们在 Draw 阶段已经修改了 min_rarity
	# 这里只负责消耗状态和播放特效
	
	_is_buff_active = false
	triggered.emit(TRIGGER_ACTIVATE)


func get_visual_state() -> String:
	if _is_buff_active:
		return TRIGGER_PENDING
	return ""
