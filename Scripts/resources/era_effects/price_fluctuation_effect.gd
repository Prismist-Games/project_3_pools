extends Resource
class_name PriceFluctuationEffect

## ERA_2: 奖池价格波动效果
## 每次刷新奖池时，价格在指定范围内随机变化

@export var effect_name: String = "价格波动"
@export var price_min: int = 1
@export var price_max: int = 4

## 应用价格波动到奖池
func apply_to_pool(pool: PoolConfig, rng: RandomNumberGenerator) -> void:
	pool.gold_cost = rng.randi_range(price_min, price_max)

func get_description() -> String:
	return "%s：奖池价格在 %d~%d 金币之间随机" % [effect_name, price_min, price_max]
