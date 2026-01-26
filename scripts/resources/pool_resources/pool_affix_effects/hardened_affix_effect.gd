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
	
	# 价格由 .tres 配置的 base_gold_cost 控制，不再在此处覆盖
	
	# 强制绝育
	ctx.force_sterile = true
	
	# 概率提升：固定为 稀有67%, 史诗30%, 传说3%
	ctx.rarity_weights = PackedFloat32Array([
		0.0, # COMMON
		0.0, # UNCOMMON
		0.67, # RARE
		0.30, # EPIC
		0.03 # LEGENDARY
	])

