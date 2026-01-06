extends Node

## UnlockManager (Autoload)
## 管理所有可渐进解锁的游戏功能状态。
##
## 设计目标：
## - 替代 mainline_stage 作为功能解锁的单一数据源
## - 支持调试控制台手动控制
## - 未来可接入任意触发机制（成就、付费等）

signal unlock_changed(feature_id: StringName, unlocked: bool)
signal merge_limit_changed(limit: Constants.Rarity)
signal inventory_size_changed(size: int)

## 功能 ID 枚举
enum Feature {
	MERGE, ## 合成功能
	POOL_AFFIXES, ## 奖池词缀
	ORDER_REFRESH, ## 订单刷新
	ITEM_TYPE_MEDICINE, ## 物品类型: 药品
	ITEM_TYPE_STATIONERY, ## 物品类型: 文具
	ITEM_TYPE_KITCHENWARE, ## 物品类型: 厨具
	ITEM_TYPE_ELECTRONICS, ## 物品类型: 电器
}

## 功能 ID 到显示名称的映射
const FEATURE_DISPLAY_NAMES: Dictionary = {
	Feature.MERGE: "合成",
	Feature.POOL_AFFIXES: "奖池词缀",
	Feature.ORDER_REFRESH: "订单刷新",
	Feature.ITEM_TYPE_MEDICINE: "药品",
	Feature.ITEM_TYPE_STATIONERY: "文具",
	Feature.ITEM_TYPE_KITCHENWARE: "厨具",
	Feature.ITEM_TYPE_ELECTRONICS: "电器",
}

## 内部状态 (默认全锁)
var _unlocked: Dictionary = {}

## 合成品质上限 (非 bool，特殊处理)
var merge_limit: Constants.Rarity = Constants.Rarity.UNCOMMON:
	set(v):
		merge_limit = v
		merge_limit_changed.emit(merge_limit)

## 背包槽位上限
var inventory_size: int = 6:
	set(v):
		inventory_size = v
		inventory_size_changed.emit(inventory_size)
		# 同步到 InventorySystem
		if InventorySystem:
			InventorySystem.resize_inventory(inventory_size)


func _ready() -> void:
	# 默认解锁"水果"类型 (通过不设置 ITEM_TYPE_FRUIT 枚举实现始终可用)
	# 初始化默认解锁状态（可根据需要调整）
	_apply_default_unlocks()


func _apply_default_unlocks() -> void:
	## 默认解锁配置（相当于旧 Stage 1 的状态）
	# 暂时全部锁定，由调试控制台手动开启
	pass


# --- 查询 API ---

func is_unlocked(feature: Feature) -> bool:
	return _unlocked.get(feature, false)


func get_feature_display_name(feature: Feature) -> String:
	return FEATURE_DISPLAY_NAMES.get(feature, "未知")


func is_item_type_unlocked(item_type: Constants.ItemType) -> bool:
	## 检查指定物品类型是否已解锁
	## FRUIT 始终解锁；MAINLINE/NONE 不在此系统管理
	match item_type:
		Constants.ItemType.FRUIT:
			return true
		Constants.ItemType.MEDICINE:
			return is_unlocked(Feature.ITEM_TYPE_MEDICINE)
		Constants.ItemType.STATIONERY:
			return is_unlocked(Feature.ITEM_TYPE_STATIONERY)
		Constants.ItemType.KITCHENWARE:
			return is_unlocked(Feature.ITEM_TYPE_KITCHENWARE)
		Constants.ItemType.ELECTRONICS:
			return is_unlocked(Feature.ITEM_TYPE_ELECTRONICS)
		_:
			return false


func get_unlocked_item_types() -> Array[Constants.ItemType]:
	## 获取当前已解锁的所有物品类型
	var result: Array[Constants.ItemType] = [Constants.ItemType.FRUIT]
	
	if is_unlocked(Feature.ITEM_TYPE_MEDICINE):
		result.append(Constants.ItemType.MEDICINE)
	if is_unlocked(Feature.ITEM_TYPE_STATIONERY):
		result.append(Constants.ItemType.STATIONERY)
	if is_unlocked(Feature.ITEM_TYPE_KITCHENWARE):
		result.append(Constants.ItemType.KITCHENWARE)
	if is_unlocked(Feature.ITEM_TYPE_ELECTRONICS):
		result.append(Constants.ItemType.ELECTRONICS)
	
	return result


# --- 修改 API ---

func unlock(feature: Feature) -> void:
	if not is_unlocked(feature):
		_unlocked[feature] = true
		unlock_changed.emit(_feature_to_id(feature), true)


func lock(feature: Feature) -> void:
	if is_unlocked(feature):
		_unlocked[feature] = false
		unlock_changed.emit(_feature_to_id(feature), false)


func set_unlocked(feature: Feature, unlocked: bool) -> void:
	if unlocked:
		unlock(feature)
	else:
		lock(feature)


func unlock_all() -> void:
	## 解锁所有功能（调试用）
	for feature in Feature.values():
		unlock(feature)


func lock_all() -> void:
	## 锁定所有功能（调试用）
	for feature in Feature.values():
		lock(feature)


# --- 内部工具 ---

func _feature_to_id(feature: Feature) -> StringName:
	match feature:
		Feature.MERGE: return &"merge"
		Feature.POOL_AFFIXES: return &"pool_affixes"
		Feature.ORDER_REFRESH: return &"order_refresh"
		Feature.ITEM_TYPE_MEDICINE: return &"item_type_medicine"
		Feature.ITEM_TYPE_STATIONERY: return &"item_type_stationery"
		Feature.ITEM_TYPE_KITCHENWARE: return &"item_type_kitchenware"
		Feature.ITEM_TYPE_ELECTRONICS: return &"item_type_electronics"
		_: return &"unknown"
