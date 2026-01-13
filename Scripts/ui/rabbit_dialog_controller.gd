class_name RabbitDialogController
extends Node

## 兔子对话框控制器
##
## 负责管理兔子的对话气泡显示与动画：
## - 触发时：dialog box scale 从 0 到 1，然后 dialog label 的 visible_ratio 从 0 到 1
## - 结束时：dialog box scale 从 1 到 0

## 对话类型枚举
enum DialogType {
	SKILL_SELECT,       ## 选技能：请选择需要的技能（右键取消）
	SKILL_FULL,         ## 技能满：请选择需要替换的技能
	TARGETED,           ## 有的放矢：请选择想要的道具类型（右键取消）
	TRADE_IN,           ## 以旧换新：请选择要置换的道具
	PRECISE,            ## 精准的：请选择一个道具
	INVENTORY_FULL,     ## 背包满：请选择替换一样包内道具，或回收当前奖品
	RECYCLE,            ## 回收模式：请选择要回收的道具（右键取消）
	SUBMIT,             ## 提交模式：请选择要提交的道具（右键取消）
}

## 对话文本 KEY 映射
const DIALOG_KEYS: Dictionary = {
	DialogType.SKILL_SELECT: "DIALOG_SKILL_SELECT",
	DialogType.SKILL_FULL: "DIALOG_SKILL_FULL",
	DialogType.TARGETED: "DIALOG_TARGETED",
	DialogType.TRADE_IN: "DIALOG_TRADE_IN",
	DialogType.PRECISE: "DIALOG_PRECISE",
	DialogType.INVENTORY_FULL: "DIALOG_INVENTORY_FULL",
	DialogType.RECYCLE: "DIALOG_RECYCLE",
	DialogType.SUBMIT: "DIALOG_SUBMIT",
}

## 节点引用
var dialog_box: Sprite2D = null
var dialog_label: RichTextLabel = null

## 动画参数
@export var show_scale_duration: float = 0.25
@export var text_reveal_duration: float = 0.6
@export var hide_scale_duration: float = 0.2

## 当前状态
var _is_showing: bool = false
var _current_tween: Tween = null
var _current_dialog_type: DialogType = DialogType.SKILL_SELECT

## 初始化，由 Game2DUI 调用
func setup(box: Sprite2D, label: RichTextLabel) -> void:
	dialog_box = box
	dialog_label = label
	
	if dialog_box:
		# 初始状态：隐藏
		dialog_box.scale = Vector2.ZERO
		dialog_box.visible = false
	
	if dialog_label:
		dialog_label.visible_ratio = 0.0

## 显示对话框
func show_dialog(dialog_type: DialogType) -> void:
	if not dialog_box or not dialog_label:
		push_warning("[RabbitDialogController] 对话框节点未设置")
		return
	
	# 如果已经在显示，先取消当前动画
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()
	
	_is_showing = true
	_current_dialog_type = dialog_type
	
	# 设置文本
	var key = DIALOG_KEYS.get(dialog_type, "")
	dialog_label.text = key
	dialog_label.visible_ratio = 0.0
	
	# 确保对话框可见
	dialog_box.visible = true
	dialog_box.scale = Vector2.ZERO
	
	# 创建动画序列
	_current_tween = dialog_box.create_tween()
	_current_tween.set_ease(Tween.EASE_OUT)
	_current_tween.set_trans(Tween.TRANS_BACK)
	
	# 1. 对话框 scale 从 0 到 1
	_current_tween.tween_property(dialog_box, "scale", Vector2.ONE, show_scale_duration)
	
	# 2. 文字 visible_ratio 从 0 到 1
	_current_tween.tween_property(dialog_label, "visible_ratio", 1.0, text_reveal_duration) \
		.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)

## 隐藏对话框
func hide_dialog() -> void:
	if not dialog_box:
		return
	
	if not _is_showing:
		return
	
	# 取消当前动画
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()
	
	_is_showing = false
	
	# 创建隐藏动画
	_current_tween = dialog_box.create_tween()
	_current_tween.set_ease(Tween.EASE_IN)
	_current_tween.set_trans(Tween.TRANS_BACK)
	
	# scale 从 1 到 0
	_current_tween.tween_property(dialog_box, "scale", Vector2.ZERO, hide_scale_duration)
	_current_tween.tween_callback(func(): dialog_box.visible = false)

## 立即隐藏（无动画）
func hide_immediate() -> void:
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()
	
	_is_showing = false
	
	if dialog_box:
		dialog_box.scale = Vector2.ZERO
		dialog_box.visible = false
	
	if dialog_label:
		dialog_label.visible_ratio = 0.0

## 检查是否正在显示
func is_showing() -> bool:
	return _is_showing

## 获取当前对话类型
func get_current_type() -> DialogType:
	return _current_dialog_type

## 状态名到对话类型的映射辅助函数
static func state_to_dialog_type(state_name: StringName) -> DialogType:
	match state_name:
		&"SkillSelection":
			return DialogType.SKILL_SELECT
		&"TargetedSelection":
			return DialogType.TARGETED
		&"TradeIn":
			return DialogType.TRADE_IN
		&"PreciseSelection":
			return DialogType.PRECISE
		&"Replacing":
			return DialogType.INVENTORY_FULL
		&"Recycling":
			return DialogType.RECYCLE
		&"Submitting":
			return DialogType.SUBMIT
		_:
			return DialogType.SKILL_SELECT

## 更新当前对话文本（用于状态内阶段变化）
func update_dialog_text(dialog_type: DialogType) -> void:
	if not _is_showing or not dialog_label:
		return
	
	_current_dialog_type = dialog_type
	var key = DIALOG_KEYS.get(dialog_type, "")
	
	# 如果正在播放动画，取消当前动画
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()
	
	# 立即设置新文本并重新播放显示动画
	dialog_label.text = key
	dialog_label.visible_ratio = 0.0
	
	_current_tween = dialog_label.create_tween()
	_current_tween.tween_property(dialog_label, "visible_ratio", 1.0, text_reveal_duration) \
		.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
