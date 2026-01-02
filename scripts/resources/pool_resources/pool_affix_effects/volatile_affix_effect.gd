extends PoolAffixEffect
class_name VolatileAffixEffect

## 【波动的】
## 只能获得 普通(Common) 或 传说(Legendary)。
## 参考概率: Common 92%, Legendary 8%

@export_range(0.0, 1.0, 0.01) var legendary_rate: float = 0.08


func on_event(event_id: StringName, context: RefCounted) -> void:
	if event_id != &"draw_requested":
		return
	var ctx: DrawContext = context as DrawContext
	if ctx == null:
		return
	
	# 修改消耗
	ctx.gold_cost = 1
	
	# 修改权重
	var r: float = clampf(legendary_rate, 0.0, 1.0)
	ctx.rarity_weights = PackedFloat32Array([1.0 - r, 0.0, 0.0, 0.0, r])
