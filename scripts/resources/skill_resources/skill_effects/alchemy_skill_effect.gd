extends SkillEffect
class_name AlchemySkillEffect

## 【炼金术】
## 回收稀有及以上品质物品时，15% 概率获得 5 张奖券。

@export var rarity_threshold: int = Constants.Rarity.RARE
@export var chance: float = 0.15
@export var bonus_tickets: int = 5


func on_event(event_id: StringName, context: RefCounted) -> void:
	if event_id != &"salvage_requested":
		return
		
	var ctx = context as SalvageContext
	if ctx == null: return
	
	if ctx.item.rarity >= rarity_threshold:
		if randf() < chance:
			ctx.reward_tickets += bonus_tickets






