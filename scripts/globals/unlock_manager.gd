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
signal order_limit_changed(limit: int)
signal order_item_req_range_changed(min_val: int, max_val: int)
signal pool_affix_enabled_changed(affix_id: StringName, enabled: bool)

## 功能 ID 枚举
enum Feature {
	MERGE, ## 合成功能
	POOL_AFFIXES, ## 奖池词缀
	ORDER_REFRESH, ## 订单刷新
	ITEM_TYPE_MEDICINE, ## 物品类型: 药品
	ITEM_TYPE_STATIONERY, ## 物品类型: 文具
	ITEM_TYPE_CONVENIENCE, ## 物品类型: 便利
	ITEM_TYPE_ENTERTAINMENT, ## 物品类型: 娱乐
}

## 功能 ID 到显示名称的映射
const FEATURE_DISPLAY_NAMES: Dictionary = {
	Feature.MERGE: "合成",
	Feature.POOL_AFFIXES: "奖池词缀",
	Feature.ORDER_REFRESH: "订单刷新",
	Feature.ITEM_TYPE_MEDICINE: "药品",
	Feature.ITEM_TYPE_STATIONERY: "文具",
	Feature.ITEM_TYPE_CONVENIENCE: "便利",
	Feature.ITEM_TYPE_ENTERTAINMENT: "娱乐",
}

## 内部状态 (默认全锁)
var _unlocked: Dictionary = {}
var _disabled_pool_affixes: Dictionary = {} # id (StringName) -> bool (true if disabled)

## 合成品质上限 (直接设为最高：史诗 -> 传说)
var merge_limit: Constants.Rarity = Constants.Rarity.MYTHIC:
	set(v):
		merge_limit = v
		merge_limit_changed.emit(merge_limit)

## 背包槽位上限 (直接设为 10)
var inventory_size: int = 10:
	set(v):
		inventory_size = v
		inventory_size_changed.emit(inventory_size)
		# 同步到 InventorySystem
		if InventorySystem:
			InventorySystem.resize_inventory(inventory_size)

## 订单总数上限 (设为 4)
var order_limit: int = 4:
	set(v):
		order_limit = v
		order_limit_changed.emit(order_limit)

## 单个订单需求物品数量范围
var order_item_req_min: int = 2:
	set(v):
		order_item_req_min = v
		if order_item_req_min > order_item_req_max:
			order_item_req_max = order_item_req_min
		order_item_req_range_changed.emit(order_item_req_min, order_item_req_max)

var order_item_req_max: int = 4:
	set(v):
		order_item_req_max = v
		if order_item_req_max < order_item_req_min:
			order_item_req_min = order_item_req_max
		order_item_req_range_changed.emit(order_item_req_min, order_item_req_max)


func _ready() -> void:
	# 默认解锁"水果"类型 (通过不设置 ITEM_TYPE_FRUIT 枚举实现始终可用)
	# 初始化默认解锁状态（可根据需要调整）
	_apply_default_unlocks()


func _apply_default_unlocks() -> void:
	## 默认解锁配置（相当于旧 Stage 1 的状态）
	# 暂时全部锁定，由调试控制台手动开启
	pass


# --- 查询 API ---

func is_unlocked(_feature: Feature) -> bool:
	return true # 强制全部解锁


func get_feature_display_name(feature: Feature) -> String:
	return FEATURE_DISPLAY_NAMES.get(feature, "未知")


func is_item_type_unlocked(_item_type: Constants.ItemType) -> bool:
	## 强制全部解锁
	return true


func get_unlocked_item_types() -> Array[Constants.ItemType]:
	## 获取所有普通物品类型
	return Constants.get_normal_item_types()


func is_pool_affix_enabled(affix_id: StringName) -> bool:
	return not _disabled_pool_affixes.get(affix_id, false)


func set_pool_affix_enabled(affix_id: StringName, enabled: bool) -> void:
	_disabled_pool_affixes[affix_id] = not enabled
	pool_affix_enabled_changed.emit(affix_id, enabled)


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
		Feature.ITEM_TYPE_CONVENIENCE: return &"item_type_convenience"
		Feature.ITEM_TYPE_ENTERTAINMENT: return &"item_type_entertainment"
		_: return &"unknown"
