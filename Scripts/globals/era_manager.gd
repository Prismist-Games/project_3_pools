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
	
	# 监听技能选择完成信号（通过 game_event）
	EventBus.game_event.connect(_on_game_event)
	
	# 启动第一个时代
	call_deferred("start_era", 0)


func _on_game_event(event_id: StringName, _payload: RefCounted) -> void:
	# 技能选择完成后切换到下一个时代
	if event_id == &"skill_selected":
		advance_to_next_era()


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


func _apply_era_reset() -> void:
	var cfg = current_config
	if cfg == null:
		push_error("EraManager: 无法加载时代 %d 的配置!" % current_era_index)
		return
	
	# 重置金币
	GameManager.gold = cfg.starting_gold
	
	# 重置背包大小和清空背包
	UnlockManager.inventory_size = cfg.inventory_size
	InventorySystem.initialize_inventory(cfg.inventory_size)
	
	# 刷新奖池 (ERA_2 价格波动等效果需要数据更新)
	if PoolSystem.is_node_ready():
		PoolSystem.refresh_pools()
	
	# 调用所有效果的 on_era_start
	for effect in cfg.effects:
		if effect != null and effect.has_method("on_era_start"):
			effect.on_era_start()
