extends SkillEffect
class_name AlchemySkillEffect

## 【炼金术】
## 回收稀有及以上品质物品时，15% 概率获得 20 金币。

@export var rarity_threshold: int = Constants.Rarity.RARE
@export var chance: float = 0.25
@export var bonus_gold: int = 5


func on_event(event_id: StringName, context: RefCounted) -> void:
	if event_id != &"recycle_requested":
		return
		
	var ctx = context as RecycleContext
	if ctx == null: return
	
	if ctx.item.rarity >= rarity_threshold:
		if randf() < chance:
			triggered.emit(TRIGGER_INSTANT)
			ctx.reward_gold += bonus_gold
