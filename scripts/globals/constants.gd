extends Node

## 全局常量与枚举定义。
##
## 说明：
## - 该脚本会作为 Autoload 单例使用（`Constants`）。
## - 仅放“静态定义/纯函数”，避免持有可变游戏状态。

enum Rarity {
	COMMON,
	UNCOMMON,
	RARE,
	EPIC,
	LEGENDARY,
	MYTHIC,
}

# enum AffixType {
# 	NONE,
# 	TRADE_IN, ## 以旧换新
# 	HARDENED, ## 硬化的（更高品质 + 绝育）
# 	PURIFIED, ## 提纯的（保底稀有及以上）
# 	VOLATILE, ## 波动的（仅普通/传说，传说更高）
# 	FRAGMENTED, ## 稀碎的（一次 3 个，必定普通）
# 	PRECISE, ## 精准的（二选一）
# 	TARGETED, ## 有的放矢（指定类型）
# }

const SKILL_SLOTS: int = 3
const MAINLINE_STAGES: int = 5

const POOL_TYPE_FRUIT: StringName = &"Fruit"
const POOL_TYPE_MEDICINE: StringName = &"Medicine"
const POOL_TYPE_STATIONERY: StringName = &"Stationery"
const POOL_TYPE_KITCHENWARE: StringName = &"Kitchenware"
const POOL_TYPE_ELECTRONICS: StringName = &"Electronics"
const POOL_TYPE_MAINLINE: StringName = &"Mainline"

const NORMAL_POOL_TYPES: Array[String] = [
	"Fruit",
	"Medicine",
	"Stationery",
	"Kitchenware",
	"Electronics",
]

const MAINLINE_ITEM_STAGE_1: StringName = &"mainline_fruit"
const MAINLINE_ITEM_STAGE_2: StringName = &"mainline_medicine"
const MAINLINE_ITEM_STAGE_3: StringName = &"mainline_magic_pen"
const MAINLINE_ITEM_STAGE_4: StringName = &"mainline_kitchenware"
const MAINLINE_ITEM_STAGE_5: StringName = &"mainline_tesla"

static func mainline_item_id_for_stage(stage: int) -> StringName:
	match stage:
		1:
			return MAINLINE_ITEM_STAGE_1
		2:
			return MAINLINE_ITEM_STAGE_2
		3:
			return MAINLINE_ITEM_STAGE_3
		4:
			return MAINLINE_ITEM_STAGE_4
		5:
			return MAINLINE_ITEM_STAGE_5
		_:
			return &""

static func rarity_id(rarity: int) -> StringName:
	match rarity:
		Rarity.COMMON:
			return &"common"
		Rarity.UNCOMMON:
			return &"uncommon"
		Rarity.RARE:
			return &"rare"
		Rarity.EPIC:
			return &"epic"
		Rarity.LEGENDARY:
			return &"legendary"
		Rarity.MYTHIC:
			return &"mythic"
		_:
			return &"unknown"


static func rarity_display_name(rarity: int) -> String:
	match rarity:
		Rarity.COMMON:
			return "普通"
		Rarity.UNCOMMON:
			return "优秀"
		Rarity.RARE:
			return "稀有"
		Rarity.EPIC:
			return "史诗"
		Rarity.LEGENDARY:
			return "传说"
		Rarity.MYTHIC:
			return "神话"
		_:
			return "未知"


static func rarity_salvage_value(rarity: int) -> int:
	match rarity:
		Rarity.COMMON:
			return 0
		Rarity.UNCOMMON:
			return 0
		Rarity.RARE:
			return 1
		Rarity.EPIC:
			return 2
		Rarity.LEGENDARY:
			return 4
		Rarity.MYTHIC:
			return 10
		_:
			return 0


static func rarity_bonus(rarity: int) -> float:
	match rarity:
		Rarity.COMMON:
			return 0.0
		Rarity.UNCOMMON:
			return 0.1
		Rarity.RARE:
			return 0.2
		Rarity.EPIC:
			return 0.4
		Rarity.LEGENDARY:
			return 1.0
		Rarity.MYTHIC:
			return 3.0
		_:
			return 0.0


static func is_normal_pool_type(pool_type: StringName) -> bool:
	return pool_type != POOL_TYPE_MAINLINE and NORMAL_POOL_TYPES.has(String(pool_type))


static func pick_weighted_index(weights: PackedFloat32Array, rng: RandomNumberGenerator) -> int:
	## 从权重数组中抽取一个 index。
	var total: float = 0.0
	for w: float in weights:
		total += maxf(w, 0.0)
	if total <= 0.0:
		return 0

	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for i: int in weights.size():
		acc += maxf(weights[i], 0.0)
		if roll <= acc:
			return i
	return max(weights.size() - 1, 0)