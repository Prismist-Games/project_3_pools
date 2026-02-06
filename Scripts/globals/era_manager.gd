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
	else:
		# 所有时代已完成，触发游戏结束
		EventBus.game_event.emit(&"game_ended", null)


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
	
	# 不刷新普通积分订单（保留现有）
	# 仅在 OrderSystem 中刷新主线订单
	
	# 刷新奖池
	if PoolSystem.is_node_ready():
		PoolSystem.refresh_pools()
	
	# 调用所有效果的 on_era_start
	for effect in cfg.effects:
		if effect != null and effect.has_method("on_era_start"):
			effect.on_era_start()
