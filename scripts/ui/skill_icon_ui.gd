extends TextureRect

## 技能图标显示组件。

@onready var tooltip_node: Control = %Tooltip # 如果有的话

func setup(skill: SkillData) -> void:
	if skill.icon:
		self.texture = skill.icon
	
	self.tooltip_text = "%s: %s" % [skill.name, skill.description]




