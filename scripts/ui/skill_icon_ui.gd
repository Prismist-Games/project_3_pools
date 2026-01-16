extends TextureRect

## 技能图标显示组件。

const EFFECT_SCENE = preload("res://scenes/animated_sprites/skill_activation_effect.tscn")

var skill_data: SkillData
var _pending_effect: Node2D


func _ready() -> void:
	print("[SkillIconUI] _ready called, connecting to EventBus")
	EventBus.game_event.connect(_on_game_event)
	print("[SkillIconUI] Connection established")

func setup(skill: SkillData) -> void:
	skill_data = skill
	print("[SkillIconUI] setup() called with skill: ", skill.id if skill else "null")
	
	if skill.icon:
		self.texture = skill.icon
	
	# 注意：根据需求，tooltip 不再放在 skill_icon 上，而是由父级控制器放在 Input Area 上
	self.tooltip_text = ""


func _on_game_event(event_id: StringName, context: RefCounted) -> void:
	print("[SkillIconUI] _on_game_event called with event_id: ", event_id)
	
	if event_id != &"skill_visual_feedback":
		return
	
	print("[SkillIconUI] Event is skill_visual_feedback")
	
	# context is SkillSystem.SkillFeedbackContext (RefCounted)
	# Use unsafe access or get script property
	if not context or not skill_data:
		print("[SkillIconUI] Validation failed - context: ", context != null, " skill_data: ", skill_data != null)
		return
		
	var skill_id = context.get("skill_id")
	
	print("[SkillIconUI] Received feedback for skill_id: ", skill_id, " | My skill_id: ", skill_data.id if skill_data else "null")
	
	if skill_id != skill_data.id:
		return
		
	var type = context.get("type")
	if type == null:
		type = SkillEffect.TRIGGER_INSTANT
	
	print("[SkillIconUI] Playing feedback type: ", type)
	_play_feedback(type)

func _play_feedback(type: String) -> void:
	var effect = null
	
	if type == SkillEffect.TRIGGER_ACTIVATE:
		if is_instance_valid(_pending_effect):
			effect = _pending_effect
			_pending_effect = null # Clear ref so we don't track it anymore
			if effect.has_method("activate"):
				effect.activate()
			return
		else:
			# Fallback if no pending effect exists
			type = SkillEffect.TRIGGER_INSTANT
	
	# Spawn new if needed
	if effect == null:
		effect = EFFECT_SCENE.instantiate()
		add_child(effect)
		# Center it
		effect.position = size / 2
	
	# Dispatch behavior
	if type == SkillEffect.TRIGGER_INSTANT:
		if effect.has_method("play_instant"):
			effect.play_instant()
			
	elif type == SkillEffect.TRIGGER_PENDING:
		# Remove old pending if exists?
		if is_instance_valid(_pending_effect) and _pending_effect != effect:
			_pending_effect.queue_free()
			
		_pending_effect = effect
		if effect.has_method("play_pending"):
			effect.play_pending()
