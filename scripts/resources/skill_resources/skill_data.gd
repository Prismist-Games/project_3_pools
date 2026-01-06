extends Resource
class_name SkillData

@export var id: String = ""
@export var name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D = null

## 可插拔技能效果模块列表。
## 新增/修改技能行为时，优先通过添加/替换这里的 Effect 资源实现，避免改核心逻辑。
@export var effects: Array[SkillEffect] = []