extends PoolAffixEffect
class_name PurifiedAffixEffect

## 【提纯的】
## 1. 保底机制: 必定获得稀有(Rare)或更高品质。
## (参考概率: Rare 67%, Epic 30%, Legendary 3%)
## 2. 消耗: 3 金币


func on_event(event_id: StringName, context: RefCounted) -> void:
	if event_id != &"draw_requested":
		return
	var ctx: DrawContext = context as DrawContext
	if ctx == null:
		return
	
	# 价格由 .tres 配置的 base_gold_cost 控制，不再在此处覆盖
	
	# 修改权重：固定为 稀有67%, 史诗30%, 传说3%
	ctx.rarity_weights = PackedFloat32Array([
		0.0, # COMMON
		0.0, # UNCOMMON
		0.67, # RARE
		0.30, # EPIC
		0.03 # LEGENDARY
	])

