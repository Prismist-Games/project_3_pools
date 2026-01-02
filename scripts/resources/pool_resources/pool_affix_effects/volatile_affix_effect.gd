extends PoolAffixEffect
class_name VolatileAffixEffect

## 【波动的】
## 只允许普通/传说，并把传说概率设为 legendary_rate。

@export_range(0.0, 1.0, 0.01) var legendary_rate: float = 0.6


func on_event(event_id: StringName, context: RefCounted) -> void:
	if event_id != &"draw_requested":
		return
	var ctx: DrawContext = context as DrawContext
	if ctx == null:
		return
	var r: float = clampf(legendary_rate, 0.0, 1.0)
	ctx.rarity_weights = PackedFloat32Array([1.0 - r, 0.0, 0.0, 0.0, r])


