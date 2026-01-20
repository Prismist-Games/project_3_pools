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
	TRIANGLE,
	RECTANGLE,
	CIRCLE,
	STAR,
	TRAPEZOID
}

const SKILL_SLOTS: int = 3

## 获取所有普通物品类型
func get_normal_item_types() -> Array[ItemType]:
	return [
		ItemType.TRIANGLE,
		ItemType.RECTANGLE,
		ItemType.CIRCLE,
		ItemType.STAR,
		ItemType.TRAPEZOID
	]

func is_normal_type(type: ItemType) -> bool:
	return type != ItemType.NONE

func type_to_string(type: ItemType) -> StringName:
	match type:
		ItemType.TRIANGLE: return &"Triangle"
		ItemType.RECTANGLE: return &"Rectangle"
		ItemType.CIRCLE: return &"Circle"
		ItemType.STAR: return &"Star"
		ItemType.TRAPEZOID: return &"Trapezoid"
		_: return &"None"

func type_to_display_name(type: ItemType) -> String:
	match type:
		ItemType.TRIANGLE: return "TYPE_TRIANGLE"
		ItemType.RECTANGLE: return "TYPE_RECTANGLE"
		ItemType.CIRCLE: return "TYPE_CIRCLE"
		ItemType.STAR: return "TYPE_STAR"
		ItemType.TRAPEZOID: return "TYPE_TRAPEZOID"
		_: return "TYPE_NONE"

func type_to_icon(type: ItemType) -> Texture2D:
	match type:
		ItemType.TRIANGLE: return preload("res://assets/sprites/icons/category_triangle.png")
		ItemType.RECTANGLE: return preload("res://assets/sprites/icons/category_rectangle.png")
		ItemType.CIRCLE: return preload("res://assets/sprites/icons/category_circle.png")
		ItemType.STAR: return preload("res://assets/sprites/icons/category_star.png")
		ItemType.TRAPEZOID: return preload("res://assets/sprites/icons/category_trapezoid.png")
		_: return null

func type_to_silhouette_icon(type: ItemType) -> Texture2D:
	match type:
		ItemType.TRIANGLE: return preload("res://assets/sprites/icons/silhouette_triangle.png")
		ItemType.RECTANGLE: return preload("res://assets/sprites/icons/silhouette_rectangle.png")
		ItemType.CIRCLE: return preload("res://assets/sprites/icons/silhouette_circle.png")
		ItemType.STAR: return preload("res://assets/sprites/icons/silhouette_star.png")
		ItemType.TRAPEZOID: return preload("res://assets/sprites/icons/silhouette_trapezoid.png")
		_: return null


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
			return "RARITY_COMMON"
		Rarity.UNCOMMON:
			return "RARITY_UNCOMMON"
		Rarity.RARE:
			return "RARITY_RARE"
		Rarity.EPIC:
			return "RARITY_EPIC"
		Rarity.LEGENDARY:
			return "RARITY_LEGENDARY"
		Rarity.MYTHIC:
			return "RARITY_MYTHIC"
		_:
			return "RARITY_UNKNOWN"


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
	REPLACE, ## 以旧换新模式
	LOCKED ## 锁定模式 (精准选择/有的放矢)
}

## UX 规范颜色 (针对白色背景优化)
const COLOR_TEXT_MAIN = Color("#0f172a") # 深蓝色文字 (Slate-900)
const COLOR_BG_SLOT_EMPTY = Color("#199C80") # 机器色背景
const COLOR_BORDER_SELECTED = Color("#2563eb") # 鲜蓝色边框
const COLOR_RECYCLE_ACTION = Color("#ef4444") # 鲜红色边框

func get_rarity_border_color(rarity: int) -> Color:
	match rarity:
		Rarity.COMMON: return Color("#f0f0f0") # Grey-100
		Rarity.UNCOMMON: return Color("#62BA28") # Green-500
		Rarity.RARE: return Color("#56A5EC") # Blue-500
		Rarity.EPIC: return Color("#C85FE3") # Purple-500
		Rarity.LEGENDARY: return Color("#EC9B29") # Orange-500
		Rarity.MYTHIC: return Color("#E55140") # Rose-600
		_: return Color.BLACK

func get_rarity_bg_color(rarity: int) -> Color:
	# 在白色背景上，背景色需要稍微加深一点以便区分
	match rarity:
		Rarity.COMMON: return Color("#f0f0f0") # Grey-100
		Rarity.UNCOMMON: return Color("#62BA28") # Green-500
		Rarity.RARE: return Color("#56A5EC") # Blue-500
		Rarity.EPIC: return Color("#C85FE3") # Purple-500
		Rarity.LEGENDARY: return Color("#EC9B29") # Orange-500
		Rarity.MYTHIC: return Color("#E55140") # Rose-600
		_: return Color.BLACK


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


## 处理 Tooltip 中的 BBCode，将 60px 的图标缩小为 16px
func process_tooltip_text(text: String) -> String:
	# 替换所有 [img=60] 为 [img=16]
	# 增加容错：同时也替换 [img]...[/img] 中可能存在的尺寸标识，或者直接强制尺寸
	# 简单替换 CSV 中的标准格式即可满足用户需求
	return text.replace("[img=60]", "[img=16]")
