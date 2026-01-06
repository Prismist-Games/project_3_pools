extends Node

## GameManager (Autoload)
## 核心游戏状态管理器，负责持有数值、主线进度及全局资源引用。
## 
## 修改记录:
## - [Refactor] 背包/选中状态已移动至 InventorySystem。
## - [Refactor] 技能状态已移动至 SkillSystem。

# --- 信号 ---
signal gold_changed(amount: int)
signal tickets_changed(amount: int)
signal mainline_stage_changed(stage: int)
signal order_selection_changed(index: int)
signal ui_mode_changed(mode: int)

# --- 核心数值 ---
var gold: int = 0:
	set(v):
		gold = v
		gold_changed.emit(gold)

var tickets: int = 0:
	set(v):
		tickets = v
		tickets_changed.emit(tickets)

var mainline_stage: int = 1:
	set(v):
		mainline_stage = v
		_update_current_stage_data()
		mainline_stage_changed.emit(mainline_stage)

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
var current_stage_data: MainlineStageData

var all_items: Array[ItemData] = []
var all_skills: Array[SkillData] = []
var all_pool_affixes: Array[PoolAffixData] = []
var all_stages: Array[MainlineStageData] = []

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
	# 加载所有主线阶段数据
	all_stages.assign(_load_all_from_dir(game_config.mainline_stages_dir, "MainlineStageData"))
	all_stages.sort_custom(func(a, b): return a.stage < b.stage)

func _initialize_game_state() -> void:
	gold = game_config.starting_gold
	tickets = game_config.starting_tickets
	
	# 初始化背包空间 (委托给 InventorySystem)
	# 注意：GameManager 初始化时 InventorySystem 可能尚未 _ready，但作为 Autoload 节点已存在。
	InventorySystem.initialize_inventory(game_config.inventory_size)
	
	# 设置初始主线进度
	if game_config.debug_stage > 0:
		mainline_stage = game_config.debug_stage
	else:
		mainline_stage = 1
	
	_update_current_stage_data()

func _update_current_stage_data() -> void:
	current_stage_data = get_mainline_stage_data(mainline_stage)
	if current_stage_data:
		# 根据当前阶段调整背包大小 (委托给 InventorySystem)
		InventorySystem.resize_inventory(current_stage_data.inventory_size)

# --- 经济与状态方法 ---

func add_gold(amount: int) -> void:
	gold += amount

func spend_gold(amount: int) -> bool:
	if gold >= amount:
		gold -= amount
		return true
	return false

func add_tickets(amount: int) -> void:
	tickets += amount

func spend_tickets(amount: int) -> bool:
	if tickets >= amount:
		tickets -= amount
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

func get_mainline_stage_data(stage_idx: int) -> MainlineStageData:
	for s in all_stages:
		if s.stage == stage_idx:
			return s
	return null


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
