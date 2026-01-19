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


# --- 视觉反馈信号 ---

## 触发类型：瞬时触发（变黄 -> 消失）
const TRIGGER_INSTANT = "instant"
## 触发类型：即将触发（原色出现 -> 等待）
const TRIGGER_PENDING = "pending"
## 触发类型：激活（原色/存在的特效 -> 变黄 -> 消失）
const TRIGGER_ACTIVATE = "activate"

## 技能效果触发信号：用于通知 UI 播放特效
signal triggered(type: String)


## 获取当前视觉状态（用于 UI 初始化时恢复状态）
## 返回：TRIGGER_PENDING / TRIGGER_INSTANT / TRIGGER_ACTIVATE，或 ""（无状态）
func get_visual_state() -> String:
	return ""
