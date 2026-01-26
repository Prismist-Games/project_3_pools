extends SkillEffect
class_name NegotiatorSkillEffect

## 【谈判专家】
## 抽到或合成史诗及以上品质物品时，所有订单刷新次数 +1。

@export var rarity_threshold: int = Constants.Rarity.EPIC
@export var refresh_bonus: int = 1


func on_event(event_id: StringName, context: RefCounted) -> void:
	match event_id:
		&"item_obtained", &"item_merged":
			_handle_item_check(context as ItemInstance)


func _handle_item_check(item: ItemInstance) -> void:
	if item == null: return
	
	if item.rarity >= rarity_threshold:
		triggered.emit(TRIGGER_INSTANT)
		EventBus.game_event.emit(&"add_order_refreshes", null)

