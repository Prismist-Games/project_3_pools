extends Node

## EraManager (Autoload)
## 管理游戏时代状态、时代切换和时代效果应用。

signal era_changed(era_index: int)

var current_era_index: int = 0

var current_config: EraConfig:
	get:
		return _get_era_config(current_era_index)


func _ready() -> void:
	# 等待 GameManager 初始化完成
	if not GameManager.is_node_ready():
		await GameManager.ready
	
	# 启动第一个时代
	call_deferred("start_era", 0)


func _get_era_config(index: int) -> EraConfig:
	if GameManager.game_config == null:
		return null
	var configs = GameManager.game_config.era_configs
	if index >= 0 and index < configs.size():
		return configs[index]
	return null


func start_era(index: int) -> void:
	current_era_index = index
	_apply_era_reset()
	era_changed.emit(current_era_index)


func advance_to_next_era() -> void:
	var max_era_index = 3 # 0-based, so 4 eras total
	if current_era_index < max_era_index:
		start_era(current_era_index + 1)
	else:
		# 所有时代已完成，触发游戏结束
		EventBus.game_event.emit(&"game_ended", null)


## 为所有现有物品初始化保质期（进入变质时代时调用）
func _initialize_shelf_life_for_existing_items(shelf_life_effect: Resource) -> void:
	if not InventorySystem or not InventorySystem.is_node_ready():
		return
	
	var initialized_count: int = 0
	for item in InventorySystem.inventory:
		if item != null and item.shelf_life == -1:
			# 从上个时代带入的物品，赋予初始保质期
			item.shelf_life = shelf_life_effect.default_shelf_life
			initialized_count += 1
	
	# 如果有物品被初始化，刷新背包 UI
	if initialized_count > 0:
		InventorySystem.inventory_changed.emit(InventorySystem.inventory)
		print("EraManager: 已为 %d 个现有物品初始化保质期 (%d 回合)" % [initialized_count, shelf_life_effect.default_shelf_life])


func _apply_era_reset() -> void:
	var cfg = current_config
	if cfg == null:
		push_error("EraManager: 无法加载时代 %d 的配置!" % current_era_index)
		return
	
	# 重置金币到固定数量
	GameManager.gold = cfg.starting_gold
	
	# 不清空背包（保留物品），仅在需要时调整背包大小
	UnlockManager.inventory_size = cfg.inventory_size
	if InventorySystem.inventory.size() != cfg.inventory_size:
		InventorySystem.resize_inventory(cfg.inventory_size)
	
	# ERA_4: 如果进入保质期时代，为所有现有物品初始化保质期
	var shelf_life_effect = cfg.get_effect_of_type("ShelfLifeEffect")
	if shelf_life_effect:
		_initialize_shelf_life_for_existing_items(shelf_life_effect)
	
	# 不刷新普通积分订单（保留现有）
	# 仅在 OrderSystem 中刷新主线订单
	
	# 刷新奖池
	if PoolSystem.is_node_ready():
		PoolSystem.refresh_pools()
	
	# 调用所有效果的 on_era_start
	for effect in cfg.effects:
		if effect != null and effect.has_method("on_era_start"):
			effect.on_era_start()
