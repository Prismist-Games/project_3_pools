extends Node

## GameManager (Autoload)
## 核心游戏状态管理器，负责持有数值、背包、主线进度及全局资源引用。

# --- 信号 ---
signal gold_changed(amount: int)
signal tickets_changed(amount: int)
signal mainline_stage_changed(stage: int)
signal inventory_changed(inventory: Array[ItemInstance])
signal skills_changed(skills: Array[SkillData])
signal pending_queue_changed(queue: Array[ItemInstance])
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

# --- 背包与状态 ---
var inventory: Array[ItemInstance] = []
var current_skills: Array[SkillData] = []:
	set(v):
		current_skills = v
		skills_changed.emit(current_skills)
var pending_items: Array[ItemInstance] = []

## pending_item 代表当前正在处理的（浮动在鼠标上或等待放置的）物品
## 其 getter/setter 会自动维护一个待处理队列 (pending_items)
var pending_item: ItemInstance:
	get:
		return pending_items[0] if not pending_items.is_empty() else null
	set(v):
		if v == null:
			if not pending_items.is_empty():
				pending_items.pop_front()
				pending_queue_changed.emit(pending_items)
		else:
			if not v in pending_items:
				pending_items.append(v)
				pending_queue_changed.emit(pending_items)

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
	
	# 初始化背包空间
	inventory.clear()
	inventory.resize(game_config.inventory_size)
	inventory.fill(null)
	
	# 设置初始主线进度
	if game_config.debug_stage > 0:
		mainline_stage = game_config.debug_stage
	else:
		mainline_stage = 1
	
	_update_current_stage_data()

func _update_current_stage_data() -> void:
	current_stage_data = get_mainline_stage_data(mainline_stage)
	if current_stage_data:
		# 根据当前阶段调整背包大小
		if inventory.size() != current_stage_data.inventory_size:
			var old_size = inventory.size()
			inventory.resize(current_stage_data.inventory_size)
			# 如果扩容，填充 null
			if current_stage_data.inventory_size > old_size:
				for i in range(old_size, current_stage_data.inventory_size):
					inventory[i] = null
			inventory_changed.emit(inventory)

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

func has_skill(skill_id: String) -> bool:
	for skill in current_skills:
		if skill.id == skill_id:
			return true
	return false

func get_selectable_skills(count: int = 3) -> Array[SkillData]:
	var available: Array[SkillData] = []
	for skill in all_skills:
		# 只有满足解锁阶段，且当前未拥有的技能才可供选择
		if skill.unlock_stage <= mainline_stage and not has_skill(skill.id):
			available.append(skill)
	
	available.shuffle()
	return available.slice(0, count)

func add_skill(skill: SkillData) -> bool:
	if current_skills.size() < Constants.SKILL_SLOTS:
		current_skills.append(skill)
		skills_changed.emit(current_skills)
		return true
	return false

func replace_skill(index: int, new_skill: SkillData) -> void:
	if index >= 0 and index < current_skills.size():
		current_skills[index] = new_skill
		skills_changed.emit(current_skills)

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

func remove_items(items_to_remove: Array[ItemInstance]) -> void:
	var changed = false
	for i in range(inventory.size()):
		if inventory[i] in items_to_remove:
			inventory[i] = null
			changed = true
	if changed:
		inventory_changed.emit(inventory)

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
