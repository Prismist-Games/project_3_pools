extends PoolAffixEffect
class_name HardenedAffixEffect

## 【硬化的】
## 1. 概率提升: 只有稀有(Rare)及以上品质。
## 2. 副作用: 获得的物品带有 sterile: true 标记（绝育），无法参与合成。
## 3. 消耗: 2 金币


func on_event(event_id: StringName, context: RefCounted) -> void:
	if event_id != &"draw_requested":
		return
	var ctx: DrawContext = context as DrawContext
	if ctx == null:
		return
	
	# 修改消耗
	ctx.gold_cost = 2
	
	# 强制绝育
	ctx.force_sterile = true
	
	# 概率提升：移除普通和优秀，提升稀有及以上
	ctx.ensure_default_rarity_weights()
	ctx.rarity_weights[Constants.Rarity.COMMON] = 0.0
	ctx.rarity_weights[Constants.Rarity.UNCOMMON] = 0.0
	
	# 如果所有权重都为0（虽然不太可能，但防御性编程），设置一个默认权重
	var total_weight: float = 0.0
	for w: float in ctx.rarity_weights:
		total_weight += w
	if total_weight <= 0.0:
		ctx.rarity_weights[Constants.Rarity.RARE] = 1.0
