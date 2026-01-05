extends PoolAffixEffect
class_name FragmentedAffixEffect

## 【稀碎的】
## 1. 数量加成: 一次抽奖获得 3 个物品。
## 2. 品质锁定: 所有物品必定为 普通(Common)。
## 3. 消耗: 1 金币


func on_event(event_id: StringName, context: RefCounted) -> void:
	if event_id != &"draw_requested":
		return
	var ctx: DrawContext = context as DrawContext
	if ctx == null:
		return
	
	# 修改消耗
	ctx.gold_cost = 1
	
	# 修改数量
	ctx.item_count = 3
	
	# 强制普通品质
	ctx.force_rarity = Constants.Rarity.COMMON




