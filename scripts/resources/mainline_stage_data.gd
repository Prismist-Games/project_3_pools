extends Resource
class_name MainlineStageData

## 主线阶段定义（.tres 实例化）。
##
## 说明：
## - 通过在 `res://data/general/mainline/stages/` 放置多个 MainlineStageData.tres，
##   即可新增/调整主线阶段，无需修改游戏逻辑代码。

@export var stage: int = 1
@export var stage_name: String = ""

@export_group("Goals")
## 该阶段的主线神话道具（通常 is_mainline=true 的 ItemData）
@export var mainline_item: ItemData = null
## 要求的辅助物品稀有度（主线订单中除神话道具外的另一个要求）
@export var required_secondary_rarity: Constants.Rarity = Constants.Rarity.COMMON

@export_group("Mainline Pool")
## 主线池填充物的稀有度（阶段 1 为普通，阶段 2 为优秀...）
@export var filler_rarity: Constants.Rarity = Constants.Rarity.COMMON

@export_group("Unlocks")
## 解锁的奖池类型
@export var unlocked_pool_types: Array[StringName] = []
## 是否解锁合成
@export var has_merge: bool = false
## 合成上限（含）
@export var merge_limit: Constants.Rarity = Constants.Rarity.COMMON
## 是否解锁奖池词缀
@export var has_pool_affixes: bool = false
## 是否解锁订单刷新
@export var has_order_refresh: bool = false

@export_group("Parameters")
@export var inventory_size: int = 6
@export var order_count: int = 2
@export var items_per_pool: int = 3

@export_group("Rarity Weights")
@export var weight_common: float = 100.0
@export var weight_uncommon: float = 0.0
@export var weight_rare: float = 0.0
@export var weight_epic: float = 0.0
@export var weight_legendary: float = 0.0

@export_group("Skills")
## 本阶段新解锁的技能 ID 列表
@export var newly_unlocked_skill_ids: Array[String] = []

func get_weights() -> PackedFloat32Array:
	return PackedFloat32Array([
		weight_common,
		weight_uncommon,
		weight_rare,
		weight_epic,
		weight_legendary,
		0.0 # Mythic 通常不直接掉落，除非主线池
	])


