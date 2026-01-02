extends Resource
class_name PoolConfig

## 奖池配置（可作为静态预设，也可用于运行时 PoolState 的模板）。

const AffixData = preload("pool_affix_data.gd")
const AffixEffect = preload("pool_affix_effect.gd")

## 唯一标识（用于配置/调试；允许为空，表示“未命名模板”）。
@export var id: StringName = &""

@export var pool_type: StringName = &""
## 旧字段：保留兼容（对应 Constants.AffixType）。
@export var affix: int = 0

## 新字段：词缀数据（推荐使用，扩展无需改 enum/核心逻辑）。
@export var affix_data: AffixData = null

@export var gold_cost: int = 5
@export var ticket_cost: int = 0


func get_affix_id() -> StringName:
	if affix_data != null and affix_data.id != &"":
		return affix_data.id
	## 兼容旧 enum（仅对内置词缀做映射；扩展词缀请使用 affix_data.id）
	match affix:
		Constants.AffixType.TRADE_IN:
			return &"trade_in"
		Constants.AffixType.HARDENED:
			return &"hardened"
		Constants.AffixType.PURIFIED:
			return &"purified"
		Constants.AffixType.VOLATILE:
			return &"volatile"
		Constants.AffixType.FRAGMENTED:
			return &"fragmented"
		Constants.AffixType.PRECISE:
			return &"precise"
		Constants.AffixType.TARGETED:
			return &"targeted"
		_:
			return &""


func get_affix_effects() -> Array[AffixEffect]:
	if affix_data == null:
		return []
	return affix_data.effects


func dispatch_affix_event(event_id: StringName, context: RefCounted) -> void:
	for eff: AffixEffect in get_affix_effects():
		if eff == null:
			continue
		eff.on_event(event_id, context)

