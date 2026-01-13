extends Node

## GameManager (Autoload)
## 核心游戏状态管理器，负责持有数值、主线进度及全局资源引用。
## 
## 修改记录:
## - [Refactor] 背包/选中状态已移动至 InventorySystem。
## - [Refactor] 技能状态已移动至 SkillSystem。

# --- 信号 ---
signal gold_changed(amount: int)
signal order_selection_changed(index: int)
signal ui_mode_changed(mode: int)

# --- 核心数值 ---
var gold: int = 0:
	set(v):
		gold = v
		gold_changed.emit(gold)


# --- UI 状态 ---
var current_ui_mode: Constants.UIMode = Constants.UIMode.NORMAL:
	set(v):
		current_ui_mode = v
		ui_mode_changed.emit(current_ui_mode)

# --- UI 辅助状态 ---
var multi_selected_indices: Array[int] = []
## selected_indices_for_order 是 multi_selected_indices 的别名，兼容部分系统逻辑
var selected_indices_for_order: Array[int]:
	get: return multi_selected_indices
	set(v): multi_selected_indices = v

var order_selection_index: int = -1:
	set(v):
		order_selection_index = v
		order_selection_changed.emit(order_selection_index)

var selected_slot_index: int = -1

# --- 资源引用 ---
var game_config: GameConfig

var all_items: Array[ItemData] = []
var all_skills: Array[SkillData] = []
var all_pool_affixes: Array[PoolAffixData] = []

var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# --- 初始化 ---

func _ready() -> void:
	rng.randomize()
	_load_resources()
	_initialize_game_state()

func _load_resources() -> void:
	# 加载核心配置
	game_config = load("res://data/general/game_config.tres")
	if not game_config:
		push_error("GameManager: 无法加载 GameConfig (res://data/general/game_config.tres)!")
		return

	# 加载所有物品资源
	all_items.assign(_load_all_from_dir(game_config.items_dir, "ItemData"))
	# 加载所有技能资源
	all_skills.assign(_load_all_from_dir(game_config.skills_dir, "SkillData"))
	# 加载所有奖池词缀资源
	all_pool_affixes.assign(_load_all_from_dir(game_config.pool_affixes_dir, "PoolAffixData"))

func _initialize_game_state() -> void:
	gold = game_config.starting_gold
	
	# 初始化背包空间 (直接设为 10)
	InventorySystem.initialize_inventory(10)

# --- 经济与状态方法 ---

func add_gold(amount: int) -> void:
	gold += amount

func spend_gold(amount: int) -> bool:
	if gold >= amount:
		gold -= amount
		return true
	return false


# --- 数据查询方法 ---

func get_item_data(item_id: String) -> ItemData:
	for item in all_items:
		if item.id == item_id:
			return item
	return null

func get_items_for_type(type: Constants.ItemType) -> Array[ItemData]:
	var result: Array[ItemData] = []
	for item in all_items:
		if item.item_type == type:
			result.append(item)
	return result

func get_all_normal_items() -> Array[ItemData]:
	var result: Array[ItemData] = []
	for item in all_items:
		if Constants.is_normal_type(item.item_type):
			result.append(item)
	return result


# --- 内部工具 ---

func _load_all_from_dir(path: String, _type_name: String) -> Array:
	var result = []
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres"):
				var full_path = path.path_join(file_name)
				var res = load(full_path)
				if res:
					result.append(res)
			file_name = dir.get_next()
	return result
