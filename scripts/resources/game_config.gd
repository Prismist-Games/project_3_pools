extends Resource
class_name GameConfig

# --- 基础经济配置 ---
@export_group("Economy", "starting_")
@export var starting_gold: int = 15
@export var starting_tickets: int = 0
@export var normal_draw_gold_cost: int = 5

# --- 抽奖权重 (归一化处理) ---
@export_group("Rarity Weights", "weight_")
@export var weight_common: float = 40.0
@export var weight_uncommon: float = 30.0
@export var weight_rare: float = 19.0
@export var weight_epic: float = 10.0
@export var weight_legendary: float = 1.0

# --- 主线任务相关 ---
@export_group("Mainline")
@export var mainline_chance: float = 0.5
@export var mainline_ticket_cost: int = 10
@export_range(0, 1) var mainline_drop_rate: float = 0.3
@export_range(0, 1) var mainline_filler_legendary_rate: float = 0.1

# --- 订单系统 ---
@export_group("Orders")
@export var normal_orders_count: int = 4
@export var order_refreshes_per_order: int = 2