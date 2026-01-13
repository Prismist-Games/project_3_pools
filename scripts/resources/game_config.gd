extends Resource
class_name GameConfig

const EraConfig = preload("era_config.gd")

# --- 基础经济配置 ---
@export_group("Paths")
@export_dir var items_dir: String = "res://data/items"
@export_dir var skills_dir: String = "res://data/skills"
@export_dir var pool_affixes_dir: String = "res://data/pool_affixes"

@export_group("Economy", "starting_")
@export var starting_gold: int = 15
@export var normal_draw_gold_cost: int = 5
@export var inventory_size: int = 10

# --- 调试与关卡 ---
@export_group("Debug")
## 如果大于 0，游戏启动时将强制进入该阶段（用于调试）
@export var debug_stage: int = 0

# --- 抽奖权重 (归一化处理) ---
@export_group("Rarity Weights", "weight_")
@export var weight_common: float = 40.0
@export var weight_uncommon: float = 30.0
@export var weight_rare: float = 19.0
@export var weight_epic: float = 10.0
@export var weight_legendary: float = 1.0


# --- 订单系统 ---
@export_group("Orders")
@export var normal_orders_count: int = 4
@export var order_refreshes_per_order: int = 2

# --- 时代系统 ---
@export_group("Eras")
@export var era_configs: Array[EraConfig] = []