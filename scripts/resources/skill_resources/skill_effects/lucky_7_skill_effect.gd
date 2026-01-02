extends SkillEffect
class_name Lucky7SkillEffect

## 【幸运 7】
## 当前金币数量尾数为 last_digit 时，抽到传说的概率乘以 legendary_multiplier。

@export var last_digit: int = 7
@export var legendary_multiplier: float = 2.0


func on_event(event_id: StringName, context: RefCounted) -> void:
	if event_id != &"draw_requested":
		return
	var ctx: DrawContext = context as DrawContext
	if ctx == null:
		return
	if GameManager.gold % 10 != last_digit:
		return
	ctx.multiply_rarity_weight(Constants.Rarity.LEGENDARY, legendary_multiplier)
