extends Node
## 注意：该脚本建议以 Autoload（单例名：SkillSystem）方式使用，
## 因此不声明 `class_name SkillSystem`，避免与 Autoload 全局名冲突。

## SkillSystem：把 EventBus 的事件分发给当前技能的 effects（SkillEffect）。
##
## 设计目标：
## - 技能逻辑“模块化”：新增/修改技能只改 SkillData.tres / SkillEffect 脚本，不改本系统。
## - 事件“可扩展”：除监听明确的 typed signal 外，也监听 `EventBus.game_event`（新事件无需改本系统）。

# --- 信号 ---
signal skills_changed(skills: Array[SkillData])

var _active_effects: Array[SkillEffect] = []

# --- 状态 ---
var current_skills: Array[SkillData] = []:
	set(v):
		current_skills = v
		_rebuild_effects(current_skills)
		skills_changed.emit(current_skills)

## 技能状态（跨回合或跨操作的临时状态）
var skill_state: Dictionary = {
	"consecutive_commons": 0, ## 连续抽到普通物品次数 (安慰奖)
	"next_draw_guaranteed_rare": false, ## 下一次必定稀有 (时来运转/安慰奖共享)
	"next_draw_extra_item": false, ## 下一次多给一个 (自动补货)
	"consolation_prize_active": false, ## 安慰奖独立激活标记
	"good_luck_active": false ## 时来运转独立激活标记
}


func _ready() -> void:
	# 初始重建一次 (虽然 current_skills 默认为空)
	_rebuild_effects(current_skills)

	## typed signals（兼容现有约定）
	if not EventBus.draw_requested.is_connected(_on_draw_requested):
		EventBus.draw_requested.connect(_on_draw_requested)
	if not EventBus.draw_finished.is_connected(_on_draw_finished):
		EventBus.draw_finished.connect(_on_draw_finished)
	if not EventBus.order_completed.is_connected(_on_order_completed):
		EventBus.order_completed.connect(_on_order_completed)
	if not EventBus.item_obtained.is_connected(_on_item_obtained):
		EventBus.item_obtained.connect(_on_item_obtained)

	## 可扩展事件
	if not EventBus.game_event.is_connected(_on_game_event):
		EventBus.game_event.connect(_on_game_event)


func _exit_tree() -> void:
	if EventBus.draw_requested.is_connected(_on_draw_requested):
		EventBus.draw_requested.disconnect(_on_draw_requested)
	if EventBus.draw_finished.is_connected(_on_draw_finished):
		EventBus.draw_finished.disconnect(_on_draw_finished)
	if EventBus.order_completed.is_connected(_on_order_completed):
		EventBus.order_completed.disconnect(_on_order_completed)
	if EventBus.item_obtained.is_connected(_on_item_obtained):
		EventBus.item_obtained.disconnect(_on_item_obtained)
	if EventBus.game_event.is_connected(_on_game_event):
		EventBus.game_event.disconnect(_on_game_event)


# --- 技能管理API ---

func has_skill(skill_id: String) -> bool:
	for skill in current_skills:
		if skill.id == skill_id:
			return true
	return false

func add_skill(skill: SkillData) -> bool:
	if current_skills.size() < Constants.SKILL_SLOTS:
		# 注意：这里直接修改数组不会触发 setter，需要重新赋值或手动 emit
		current_skills.append(skill)
		_rebuild_effects(current_skills)
		skills_changed.emit(current_skills)
		
		# 发出技能槽位升起信号（用于音效）
		EventBus.game_event.emit(&"skill_slot_raised", null)
		
		return true
	return false

func replace_skill(index: int, new_skill: SkillData) -> void:
	if index >= 0 and index < current_skills.size():
		current_skills[index] = new_skill
		_rebuild_effects(current_skills)
		skills_changed.emit(current_skills)
		
		# 发出技能槽位升起信号（用于音效）
		EventBus.game_event.emit(&"skill_slot_raised", null)

func get_selectable_skills(count: int = 3) -> Array[SkillData]:
	# 依赖 GameManager.all_skills 数据源
	var all_skills = GameManager.all_skills
	var available: Array[SkillData] = []
	for skill in all_skills:
		# 只要当前未拥有的技能才可供选择
		if not has_skill(skill.id):
			available.append(skill)
	
	available.shuffle()
	return available.slice(0, count)


var _effect_subscriptions: Dictionary = {} # Mapping: SkillEffect -> Callable

func _rebuild_effects(skills: Array) -> void:
	print("[SkillSystem] Rebuilding effects for ", skills.size(), " skills")
	
	# Clean up old connections
	for eff: SkillEffect in _active_effects:
		if eff in _effect_subscriptions:
			if eff.triggered.is_connected(_effect_subscriptions[eff]):
				eff.triggered.disconnect(_effect_subscriptions[eff])
			_effect_subscriptions.erase(eff)
	
	_active_effects.clear()
	
	# Build new list and connections
	for s: Variant in skills:
		var skill_data: SkillData = s as SkillData
		if skill_data == null:
			continue
		
		print("[SkillSystem] Processing skill: ", skill_data.id, " with ", skill_data.effects.size(), " effects")
		
		for eff: SkillEffect in skill_data.effects:
			if eff == null:
				print("[SkillSystem] Warning: null effect in skill ", skill_data.id)
				continue
			
			_active_effects.append(eff)
			
			# Connect signal with skill_id bound
			var callback = _on_effect_triggered.bind(skill_data.id)
			if not eff.triggered.is_connected(callback):
				eff.triggered.connect(callback)
				_effect_subscriptions[eff] = callback
				print("[SkillSystem] Connected signal for effect in skill: ", skill_data.id)
			else:
				print("[SkillSystem] Signal already connected for skill: ", skill_data.id)


func _dispatch(event_id: StringName, context: RefCounted) -> void:
	for eff: SkillEffect in _active_effects:
		if eff == null:
			continue
		eff.on_event(event_id, context)


func _on_draw_requested(context: RefCounted) -> void:
	_dispatch(&"draw_requested", context)


func _on_draw_finished(context: RefCounted) -> void:
	_dispatch(&"draw_finished", context)


func _on_order_completed(context: RefCounted) -> void:
	_dispatch(&"order_completed", context)


func _on_item_obtained(item: RefCounted) -> void:
	_dispatch(&"item_obtained", item)


func _on_effect_triggered(type: String, skill_id: String) -> void:
	# Dispatch generic game event for UI to pick up
	# Wrap in RefCounted to satisfy signal signature
	var ctx = SkillFeedbackContext.new()
	ctx.skill_id = skill_id
	ctx.type = type
	
	print("[SkillSystem] Emitting skill feedback for skill_id: ", skill_id, " type: ", type)
	
	# 核心视觉与逻辑事件
	EventBus.game_event.emit(&"skill_visual_feedback", ctx)
	EventBus.game_event.emit(&"skill_triggered", ctx)

	# --- 信号派发 (单次触发模式) ---
	match type:
		SkillEffect.TRIGGER_PENDING:
			# 技能进入待命状态（如充能开始）
			EventBus.game_event.emit(&"skill_pending", ctx)
				
		SkillEffect.TRIGGER_ACTIVATE, SkillEffect.TRIGGER_INSTANT:
			# 技能正式生效或瞬间触发
			EventBus.game_event.emit(&"skill_activated", ctx)


func _on_game_event(event_id: StringName, context: RefCounted) -> void:
	_dispatch(event_id, context)


# Helper class for wrapping feedback data
class SkillFeedbackContext extends RefCounted:
	var skill_id: String = ""

	var type: String = ""
