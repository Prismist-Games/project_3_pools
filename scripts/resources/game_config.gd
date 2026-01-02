extends Resource
class_name GameConfig

## 平衡性与概率配置（res://data/general/game_config.tres）。

@export var starting_gold: int = 15
@export var starting_tickets: int = 0

@export var normal_draw_gold_cost: int = 5

## 稀有度权重（总和不要求为 100，会做归一化）
@export var weight_common: float = 40.0
@export var weight_uncommon: float = 30.0
@export var weight_rare: float = 19.0
@export var weight_epic: float = 10.0
@export var weight_legendary: float = 1.0

## 主线奖池
@export var mainline_chance: float = 0.5
@export var mainline_ticket_cost: int = 10
@export var mainline_drop_rate: float = 0.3
@export var mainline_filler_legendary_rate: float = 0.1

## 词缀参数
@export var volatile_legendary_rate: float = 0.6
@export var hardened_high_rarity_multiplier: float = 1.2

## 订单基础
@export var normal_orders_count: int = 4
@export var order_refreshes_per_order: int = 2

## 技能（概率/数值参数，供 SkillSystem 使用）
@export var skill_poverty_relief_gold_bonus: int = 10 ## 【贫困救济】
@export var skill_lucky7_legendary_multiplier: float = 2.0 ## 【幸运 7】
@export var skill_frugal_cost_reduction: int = 2 ## 【精打细算】
@export var skill_frugal_min_cost: int = 1
@export var skill_alchemy_ticket_chance: float = 0.15 ## 【炼金术】
@export var skill_alchemy_ticket_reward: int = 5
@export var skill_vip_discount_gold: int = 1 ## 【贵宾折扣】
@export var skill_negotiation_refresh_reward: int = 1 ## 【谈判专家】
@export var skill_consolation_common_streak: int = 5 ## 【安慰奖】
@export var skill_order_reduce_chance: float = 0.2 ## 【偷工减料】
@export var skill_time_freeze_chance: float = 0.2 ## 【时间冻结】
@export var skill_same_type_reward_multiplier: float = 2.0 ## 【强迫症】
@export var skill_auto_restock_extra_item_count: int = 1 ## 【自动补货】
@export var skill_big_order_ticket_bonus: int = 10 ## 【大订单专家】
@export var skill_hard_order_ticket_bonus: int = 15 ## 【困难订单专家】


