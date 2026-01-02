extends Resource
class_name SkillEffect

## 技能效果模块（可插拔）。
##
## 设计目标：
## - SkillSystem 不关心具体技能逻辑，只负责把事件分发给 effects。
## - 新增技能：新增 SkillData.tres + 绑定一个/多个 SkillEffect（可新写脚本类），无需改 SkillSystem/核心逻辑。

## 通用事件入口（推荐使用）。
## event_id 示例：&"draw_requested"、&"draw_finished"、&"order_completed" 等。
func on_event(_event_id: StringName, _context: RefCounted) -> void:
	pass


