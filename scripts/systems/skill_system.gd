extends Node
## 注意：该脚本建议以 Autoload（单例名：SkillSystem）方式使用，
## 因此不声明 `class_name SkillSystem`，避免与 Autoload 全局名冲突。

## SkillSystem：把 EventBus 的事件分发给当前技能的 effects（SkillEffect）。
##
## 设计目标：
## - 技能逻辑“模块化”：新增/修改技能只改 SkillData.tres / SkillEffect 脚本，不改本系统。
## - 事件“可扩展”：除监听明确的 typed signal 外，也监听 `EventBus.game_event`（新事件无需改本系统）。

var _active_effects: Array[SkillEffect] = []

## 技能状态（跨回合或跨操作的临时状态）
var skill_state: Dictionary = {
	"consecutive_commons": 0,      ## 连续抽到普通物品次数 (安慰奖)
	"next_draw_guaranteed_rare": false, ## 下一次必定稀有 (时来运转/安慰奖)
	"next_draw_extra_item": false  ## 下一次多给一个 (自动补货)
}


func _ready() -> void:
	_rebuild_effects(GameManager.current_skills)

	if not GameManager.skills_changed.is_connected(_on_skills_changed):
		GameManager.skills_changed.connect(_on_skills_changed)

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
	## Autoload 理论上不会释放；这里仍做断连以保持规范与可测试性。
	if GameManager.skills_changed.is_connected(_on_skills_changed):
		GameManager.skills_changed.disconnect(_on_skills_changed)
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


func _on_skills_changed(skills: Array) -> void:
	_rebuild_effects(skills)


func _rebuild_effects(skills: Array) -> void:
	_active_effects.clear()
	for s: Variant in skills:
		var skill_data: SkillData = s as SkillData
		if skill_data == null:
			continue
		for eff: SkillEffect in skill_data.effects:
			if eff == null:
				continue
			_active_effects.append(eff)


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


func _on_game_event(event_id: StringName, context: RefCounted) -> void:
	_dispatch(event_id, context)
