extends Node
## 注意：该脚本以 Autoload（单例名：GameManager）方式使用，
## 因此不声明 `class_name GameManager`，避免与 Autoload 全局名冲突。

## 全局游戏状态管理（Autoload）。
##
## 规则：
## - 只管理“数据状态”，不要在 Setter 中直接写 UI 更新逻辑。
## - 状态变更通过信号广播，UI/Systems 监听后自行处理。

signal gold_changed(value: int)
signal tickets_changed(value: int)
signal mainline_stage_changed(stage: int)
signal skills_changed(skills: Array)
signal inventory_changed(items: Array)


const GAME_CONFIG_PATH: String = "res://data/general/game_config.tres"
const ITEMS_DIR: String = "res://data/items"
const SKILLS_DIR: String = "res://data/skills"
const MAINLINE_STAGES_DIR: String = "res://data/general/mainline/stages"

var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var game_config: Resource

var _gold: int = 15
var _tickets: int = 0
var _mainline_stage: int = 1

## 技能槽：保存 SkillData（Resource）实例。
var current_skills: Array = []

## 背包：保存 ItemInstance（RefCounted）实例。
var inventory: Array = []

## 运行时缓存：按 type（StringName）分组的 ItemData（Resource）。
var items_by_type: Dictionary = {}
var all_items: Array = []
var all_skills: Array = []

## 主线阶段配置（由 MainlineStageData.tres 组成）
var mainline_stages: Array[MainlineStageData] = []
var _mainline_stage_map: Dictionary = {} # stage(int) -> MainlineStageData

## 技能状态（供 SkillSystem 使用）
var consecutive_common_draws: int = 0
var next_draw_guaranteed_rare: bool = false
var next_draw_extra_item: bool = false


func _ready() -> void:
	rng.randomize()
	_load_game_config()
	_load_items()
	_load_skills()
	_load_mainline_stages()
	_emit_full_state()


var gold: int:
	get:
		return _gold
	set(value):
		_set_gold(value)


var tickets: int:
	get:
		return _tickets
	set(value):
		_set_tickets(value)


var mainline_stage: int:
	get:
		return _mainline_stage
	set(value):
		_set_mainline_stage(value)


func add_gold(amount: int) -> void:
	_set_gold(_gold + amount)


func spend_gold(amount: int) -> bool:
	if amount <= 0:
		return true
	if _gold < amount:
		return false
	_set_gold(_gold - amount)
	return true


func add_tickets(amount: int) -> void:
	_set_tickets(_tickets + amount)


func spend_tickets(amount: int) -> bool:
	if amount <= 0:
		return true
	if _tickets < amount:
		return false
	_set_tickets(_tickets - amount)
	return true


func add_item(item: RefCounted) -> void:
	inventory.append(item)
	inventory_changed.emit(inventory)


func remove_item_at(index: int) -> RefCounted:
	if index < 0 or index >= inventory.size():
		return null
	var removed: RefCounted = inventory.pop_at(index)
	inventory_changed.emit(inventory)
	return removed


func remove_items(items: Array) -> void:
	for it: Variant in items:
		inventory.erase(it)
	inventory_changed.emit(inventory)


func set_skills(skills: Array) -> void:
	current_skills = skills.duplicate()
	skills_changed.emit(current_skills)


func get_items_for_type(pool_type: StringName) -> Array:
	if not items_by_type.has(pool_type):
		return []
	return (items_by_type[pool_type] as Array).duplicate()


func _emit_full_state() -> void:
	gold_changed.emit(_gold)
	tickets_changed.emit(_tickets)
	mainline_stage_changed.emit(_mainline_stage)
	skills_changed.emit(current_skills)
	inventory_changed.emit(inventory)


func _set_gold(value: int) -> void:
	var clamped: int = maxi(value, 0)
	if clamped == _gold:
		return
	_gold = clamped
	gold_changed.emit(_gold)


func _set_tickets(value: int) -> void:
	var clamped: int = maxi(value, 0)
	if clamped == _tickets:
		return
	_tickets = clamped
	tickets_changed.emit(_tickets)


func _set_mainline_stage(value: int) -> void:
	var clamped: int = maxi(value, 1)
	if clamped == _mainline_stage:
		return
	_mainline_stage = clamped
	mainline_stage_changed.emit(_mainline_stage)


func _load_game_config() -> void:
	if ResourceLoader.exists(GAME_CONFIG_PATH):
		game_config = load(GAME_CONFIG_PATH)
		return
	push_warning("GameConfig 缺失：%s（将使用默认代码路径）" % GAME_CONFIG_PATH)
	game_config = null


func _load_items() -> void:
	all_items.clear()
	items_by_type.clear()
	_load_resources_from_dir(ITEMS_DIR, all_items, "_on_item_loaded")


func _load_skills() -> void:
	all_skills.clear()
	_load_resources_from_dir(SKILLS_DIR, all_skills, "_on_skill_loaded")


func _load_mainline_stages() -> void:
	mainline_stages.clear()
	_mainline_stage_map.clear()
	_load_resources_from_dir(MAINLINE_STAGES_DIR, mainline_stages, "_on_mainline_stage_loaded")
	mainline_stages.sort_custom(func(a: MainlineStageData, b: MainlineStageData) -> bool:
		return a.stage < b.stage
	)


func _load_resources_from_dir(dir_path: String, out_arr: Array, on_loaded_method: String) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		push_warning("目录不存在：%s" % dir_path)
		return

	dir.list_dir_begin()
	while true:
		var file_name: String = dir.get_next()
		if file_name.is_empty():
			break
		if dir.current_is_dir():
			continue
		if not file_name.ends_with(".tres"):
			continue
		var res_path: String = "%s/%s" % [dir_path, file_name]
		var res: Resource = load(res_path)
		if res == null:
			push_warning("资源加载失败：%s" % res_path)
			continue
		out_arr.append(res)
		if has_method(on_loaded_method):
			call(on_loaded_method, res)
	dir.list_dir_end()


func _on_item_loaded(item: Resource) -> void:
	## 约定：ItemData 必须包含 `type: StringName` 字段。
	if not "type" in item:
		push_warning("ItemData 缺少 type 字段：%s" % item)
		return
	var pool_type: StringName = item.get("type")
	if not items_by_type.has(pool_type):
		items_by_type[pool_type] = []
	(items_by_type[pool_type] as Array).append(item)


func _on_skill_loaded(_skill: Resource) -> void:
	pass


func _on_mainline_stage_loaded(stage_res: Resource) -> void:
	var stage_data: MainlineStageData = stage_res as MainlineStageData
	if stage_data == null:
		push_warning("MainlineStageData 类型不匹配：%s" % stage_res)
		return
	if stage_data.stage <= 0:
		push_warning("MainlineStageData.stage 非法：%s" % stage_data)
		return
	_mainline_stage_map[stage_data.stage] = stage_data


func get_mainline_stage_count() -> int:
	return mainline_stages.size()


func get_mainline_stage_data(stage: int) -> MainlineStageData:
	if _mainline_stage_map.has(stage):
		return _mainline_stage_map[stage] as MainlineStageData
	return null


func get_mainline_item_id_for_stage(stage: int) -> StringName:
	var stage_data: MainlineStageData = get_mainline_stage_data(stage)
	if stage_data == null or stage_data.mainline_item == null:
		return &""
	return stage_data.mainline_item.id


func has_skill(skill_id: String) -> bool:
	for skill in current_skills:
		if skill is SkillData and skill.id == skill_id:
			return true
	return false
