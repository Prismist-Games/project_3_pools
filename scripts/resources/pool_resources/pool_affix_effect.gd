extends Resource
class_name PoolAffixEffect

## 奖池词缀效果模块（可插拔）。
##
## 设计目标：
## - PoolSystem（或任何抽奖逻辑）只需在关键时机调用 `PoolConfig.dispatch_affix_event(...)`。
## - 新增词缀：新增 AffixData.tres + 绑定一个/多个 AffixEffect（可新写脚本类），无需改抽奖核心逻辑。

func on_event(_event_id: StringName, _context: RefCounted) -> void:
	pass