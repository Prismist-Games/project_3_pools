extends TextureRect

## 技能图标显示组件。

@onready var tooltip_node: Control = %Tooltip # 如果有的话

func setup(skill: SkillData) -> void:
	if skill.icon:
		self.texture = skill.icon
	
	# 注意：根据需求，tooltip 不再放在 skill_icon 上，而是由父级控制器放在 Input Area 上
	self.tooltip_text = ""






