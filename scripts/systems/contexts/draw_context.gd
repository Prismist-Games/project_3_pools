extends RefCounted
class_name DrawContext

## 抽奖上下文（可被 Skill/Affix 原地改写）。
##
## 约定：
## - System 创建 ctx -> emit `EventBus.draw_requested(ctx)`（或 `game_event`）-> 读取被改写后的 ctx 执行抽奖。

var pool_id: StringName = &""
var pool_type: StringName = &""
var affix_id: StringName = &""

var gold_cost: int = 0
var ticket_cost: int = 0

## 权重数组：仅覆盖 COMMON~LEGENDARY（不含 MYTHIC）。
## index 对应 Constants.Rarity：COMMON(0)~LEGENDARY(4)
var rarity_weights: PackedFloat32Array = PackedFloat32Array()

## 最低允许稀有度（默认普通）
var min_rarity: int = Constants.Rarity.COMMON

## 强制稀有度（-1 表示不强制；否则用 Constants.Rarity.*）
var force_rarity: int = -1

## 产出物品数量（如 Fragmented: 3）
var item_count: int = 1

## 强制绝育（如 Hardened：true）
var force_sterile: bool = false

## 运行时结果（由抽奖系统填充）
var result_items: Array[ItemInstance] = []

## 扩展数据槽（尽量只塞简单值，避免塞 Node 引用）
var meta: Dictionary = {}


func ensure_default_rarity_weights() -> void:
	## 当外部未设置时，提供一个“全普通”的默认权重，避免 effect 操作越界。
	if rarity_weights.size() >= 5:
		return
	rarity_weights = PackedFloat32Array([1.0, 0.0, 0.0, 0.0, 0.0])


func set_rarity_weight(rarity: int, weight: float) -> void:
	ensure_default_rarity_weights()
	if rarity < Constants.Rarity.COMMON or rarity > Constants.Rarity.LEGENDARY:
		return
	rarity_weights[rarity] = maxf(weight, 0.0)


func multiply_rarity_weight(rarity: int, multiplier: float) -> void:
	ensure_default_rarity_weights()
	if rarity < Constants.Rarity.COMMON or rarity > Constants.Rarity.LEGENDARY:
		return
	rarity_weights[rarity] = maxf(rarity_weights[rarity] * multiplier, 0.0)


