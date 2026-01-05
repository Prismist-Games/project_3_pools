extends SkillEffect
class_name NegotiatorSkillEffect

## 【谈判专家】
## 抽到史诗或以上品质物品时，所有订单刷新次数 +1。

@export var rarity_threshold: int = Constants.Rarity.EPIC
@export var refresh_bonus: int = 1


func on_event(event_id: StringName, context: RefCounted) -> void:
	if event_id != &"item_obtained":
		return
		
	var item = context as ItemInstance
	if item == null: return
	
	if item.rarity >= rarity_threshold:
		EventBus.game_event.emit(&"add_order_refreshes", null)




