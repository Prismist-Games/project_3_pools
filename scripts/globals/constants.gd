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

enum ItemType {
	NONE,
	ANTIQUE,
	MEDICINE,
	STATIONERY,
	CONVENIENCE,
	ENTERTAINMENT,
	MAINLINE,
}

const SKILL_SLOTS: int = 3
const MAINLINE_STAGES: int = 5

## 获取所有普通物品类型
func get_normal_item_types() -> Array[ItemType]:
	return [
		ItemType.ANTIQUE,
		ItemType.MEDICINE,
		ItemType.STATIONERY,
		ItemType.CONVENIENCE,
		ItemType.ENTERTAINMENT
	]

func is_normal_type(type: ItemType) -> bool:
	return type != ItemType.NONE and type != ItemType.MAINLINE

func type_to_string(type: ItemType) -> StringName:
	match type:
		ItemType.ANTIQUE: return &"Antique"
		ItemType.MEDICINE: return &"Medicine"
		ItemType.STATIONERY: return &"Stationery"
		ItemType.CONVENIENCE: return &"Convenience"
		ItemType.ENTERTAINMENT: return &"Entertainment"
		ItemType.MAINLINE: return &"Mainline"
		_: return &"None"

func type_to_display_name(type: ItemType) -> String:
	match type:
		ItemType.ANTIQUE: return "古董"
		ItemType.MEDICINE: return "药品"
		ItemType.STATIONERY: return "文具"
		ItemType.CONVENIENCE: return "便利"
		ItemType.ENTERTAINMENT: return "娱乐"
		ItemType.MAINLINE: return "核心"
		_: return "其他"

func type_to_icon(type: ItemType) -> Texture2D:
	match type:
		ItemType.ANTIQUE: return preload("res://assets/sprites/icons/category_antique.png")
		ItemType.MEDICINE: return preload("res://assets/sprites/icons/category_medicine.png")
		ItemType.STATIONERY: return preload("res://assets/sprites/icons/category_office.png")
		ItemType.CONVENIENCE: return preload("res://assets/sprites/icons/category_convenience.png")
		ItemType.ENTERTAINMENT: return preload("res://assets/sprites/icons/category_entertainment.png")
		ItemType.MAINLINE:
			# 核心池图标随阶段变化
			var stage = 1
			if Engine.has_singleton("GameManager"):
				stage = GameManager.mainline_stage
			
			match stage:
				1: return preload("res://assets/sprites/icons/artifact_antique.png")
				2: return preload("res://assets/sprites/icons/artifact_medicine.png")
				3: return preload("res://assets/sprites/icons/artifact_stationary.png")
				4: return preload("res://assets/sprites/icons/artifact_convenience.png")
				5: return preload("res://assets/sprites/icons/artifact_entertainment.png")
				_: return null
		_: return null

const MAINLINE_ITEM_STAGE_1: StringName = &"mainline_antique"
const MAINLINE_ITEM_STAGE_2: StringName = &"mainline_medicine"
const MAINLINE_ITEM_STAGE_3: StringName = &"mainline_stationery"
const MAINLINE_ITEM_STAGE_4: StringName = &"mainline_convenience"
const MAINLINE_ITEM_STAGE_5: StringName = &"mainline_entertainment"

func mainline_item_id_for_stage(stage: int) -> StringName:
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

func rarity_id(rarity: int) -> StringName:
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


func rarity_display_name(rarity: int) -> String:
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


func rarity_recycle_value(rarity: int) -> int:
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


func rarity_bonus(rarity: int) -> float:
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


enum UIMode {
	NORMAL, ## 整理模式
	SUBMIT, ## 提交模式
	RECYCLE, ## 回收模式
	REPLACE ## 以旧换新模式
}

## UX 规范颜色 (针对白色背景优化)
const COLOR_TEXT_MAIN = Color("#0f172a") # 深蓝色文字 (Slate-900)
const COLOR_BG_SLOT_EMPTY = Color("#f1f5f9") # 极浅灰色背景 (Slate-100)
const COLOR_BORDER_SELECTED = Color("#2563eb") # 鲜蓝色边框
const COLOR_RECYCLE_ACTION = Color("#ef4444") # 鲜红色边框

func get_rarity_border_color(rarity: int) -> Color:
	match rarity:
		Rarity.COMMON: return Color("#94a3b8") # Slate-400
		Rarity.UNCOMMON: return Color("#22c55e") # Green-500
		Rarity.RARE: return Color("#3b82f6") # Blue-500
		Rarity.EPIC: return Color("#a855f7") # Purple-500
		Rarity.LEGENDARY: return Color("#f97316") # Orange-500
		Rarity.MYTHIC: return Color("#e11d48") # Rose-600
		_: return Color.BLACK

func get_rarity_bg_color(rarity: int) -> Color:
	# 在白色背景上，背景色需要稍微加深一点以便区分
	match rarity:
		Rarity.COMMON: return Color("#f1f5f9") # Slate-100
		Rarity.UNCOMMON: return Color("#dcfce7") # Green-100
		Rarity.RARE: return Color("#dbeafe") # Blue-100
		Rarity.EPIC: return Color("#f3e8ff") # Purple-100
		Rarity.LEGENDARY: return Color("#ffedd5") # Orange-100
		Rarity.MYTHIC: return Color("#ffe4e6") # Rose-100
		_: return Color.WHITE


func pick_weighted_index(weights: PackedFloat32Array, rng: RandomNumberGenerator) -> int:
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
