class_name ItemSlotUI
extends BaseSlotUI

@onready var icon_display: Sprite2D = find_child("Item_example", true)
@onready var item_shadow: Sprite2D = find_child("Item_shadow", true)
@onready var affix_display: Sprite2D = find_child("Item_affix", true)
@onready var led_display: Sprite2D = find_child("Slot_led", true)
@onready var status_icon: Sprite2D = find_child("Item_status", true)
@onready var backgrounds: Node2D = find_child("Item Slot_backgrounds", true)
var shelf_life_label: Label = null

var slot_index: int = -1
var is_vfx_target: bool = false # 标记是否为飞行目标，防止动画中背景色提前刷新
var _selection_tween: Tween = null
var _is_selected: bool = false
var _icon_original_position: Vector2 = Vector2.ZERO
var _icon_original_scale: Vector2 = Vector2.ONE

func _ready() -> void:
	super._ready()
	
	# 自动查找或创建保质期标签
	shelf_life_label = find_child("ShelfLifeLabel", true)
	if not shelf_life_label:
		_create_shelf_life_label()
		
	# 关键修复：在一开始就记录图标的初始状态，不再动态捕获，防止缩放累加
	if icon_display:
		_icon_original_position = icon_display.position
		_icon_original_scale = icon_display.scale

func setup(index: int) -> void:
	slot_index = index
	# 背包格初始状态是开启的
	if anim_player.has_animation("lid_open"):
		anim_player.play("lid_open")
	
	# 如果 ready 没跑或者是动态生成的，这里保个底
	if icon_display and _icon_original_scale == Vector2.ONE:
		_icon_original_position = icon_display.position
		_icon_original_scale = icon_display.scale

func get_icon_global_position() -> Vector2:
	return icon_display.global_position

func get_icon_global_scale() -> Vector2:
	return icon_display.global_scale

func hide_icon() -> void:
	icon_display.visible = false
	if item_shadow: item_shadow.visible = false
	if status_icon: status_icon.visible = false

func show_icon() -> void:
	icon_display.visible = true
	if item_shadow:
		item_shadow.visible = not _is_selected
	# 注意：status_icon 的具体显示由 update_status_badge 的逻辑状态决定
	# 这里只是确保它不会在 hide_icon 后保持幽灵显示
	# 在落地刷新时，update_display 会触发 controller 重新设置 badge 状态

## 临时隐藏标记（用于防止 update_display 在 VFX 前刷新出来）
var _temp_hide_until_vfx: bool = false

func set_temp_hidden(is_hidden: bool) -> void:
	_temp_hide_until_vfx = is_hidden
	if is_hidden:
		hide_icon()

func update_display(item: ItemInstance) -> void:
	if is_vfx_target: return # 飞行中锁定视觉，落地后再更新
	
	# 如果处于临时隐藏状态，且确实有物品（为了防止误隐藏空槽），则不更新显示
	if _temp_hide_until_vfx:
		if item:
			return
		else:
			# 如果物品没了，理应解除隐藏状态
			_temp_hide_until_vfx = false
	
	if not item:
		icon_display.texture = null
		if item_shadow: item_shadow.visible = false
		affix_display.visible = false
		status_icon.visible = false
		if shelf_life_label: shelf_life_label.visible = false
		led_display.modulate = Color(0.5, 0.5, 0.5, 0.5) # Grayed out
		
		# 背景颜色渐变到空槽颜色
		if backgrounds:
			_animate_background_color(Constants.COLOR_BG_SLOT_EMPTY)
			
		# 确保图标彻底隐藏
		hide_icon()
		
		# 强制清理选中视觉，因为物品没了
		if _is_selected:
			set_selected(false)
		return
	
	icon_display.texture = item.item_data.icon
	if item_shadow:
		item_shadow.visible = not _is_selected # 选中时不显示阴影
	
	# Affix display logic based on item properties
	affix_display.visible = item.sterile
	
	# ERA_4: 过期物品视觉标识
	if item.is_expired:
		# 降低亮度和饱和度，显示过期状态
		if icon_display:
			icon_display.modulate = Color(0.5, 0.5, 0.5, 1.0) # 暗灰色调
		# 可选：在 status_icon 上显示过期标记
		# （暂时不显示，因为 update_status_badge 会覆盖）
	else:
		# 正常显示
		if icon_display:
			icon_display.modulate = Color.WHITE
	
	# ERA_4: 保质期数值显示
	_update_shelf_life_label(item)
	
	# 背景颜色渐变到稀有度颜色
	if backgrounds:
		_animate_background_color(Constants.get_rarity_border_color(item.rarity))
	
	# 确保图标显示（如果不在 VFX 隐藏中）
	show_icon()

func _animate_background_color(target_color: Color) -> void:
	if not backgrounds: return
	
	# 如果颜色已经是目标颜色，不需要动画
	if backgrounds.color.is_equal_approx(target_color):
		return
	
	# 创建颜色渐变动画
	var t = create_tween()
	t.tween_property(backgrounds, "color", target_color, 0.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func set_selected(selected: bool) -> void:
	# 关键修复：如果状态没变，直接返回。防止全员刷新的信号导致所有格子抖动
	if _is_selected == selected:
		return
		
	_is_selected = selected
	
	_animate_selection(selected)
	
	if not selected:
		if backgrounds:
			backgrounds.modulate = Color.WHITE

func set_highlight(active: bool) -> void:
	if active:
		modulate = Color(1.2, 1.2, 1.2, 1.0)
	else:
		modulate = Color.WHITE

func _animate_selection(active: bool) -> void:
	if not icon_display: return
	
	if active:
		if _selection_tween and _selection_tween.is_valid():
			return # 已经在播放
		
		# 使用已记录的稳定原始比例进行放大，倍数固定
		# 哪怕之前动画没播完，1.2 * 稳定原始值 也是一个固定的终点
		
		# 保存当前全局位置
		var saved_global_pos = icon_display.global_position
		
		# 设置 top_level = true 让图标脱离父节点裁剪，独立渲染
		icon_display.top_level = true
		icon_display.z_index = 100
		
		# 恢复全局位置
		icon_display.global_position = saved_global_pos
		
		# 隐藏阴影
		if item_shadow:
			item_shadow.visible = false
		
		# 1. 凸出效果
		var t_scale = create_tween()
		t_scale.tween_property(icon_display, "scale", _icon_original_scale * 1.2, 0.2) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		
		# 2. 上下浮动 (循环) - 使用全局坐标
		var base_y = saved_global_pos.y
		var float_up = base_y - 15.0
		var float_down = base_y + 15.0
		
		_selection_tween = create_tween().set_loops()
		_selection_tween.tween_property(icon_display, "global_position:y", float_up, 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_selection_tween.tween_property(icon_display, "global_position:y", float_down, 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			
	else:
		if _selection_tween:
			_selection_tween.kill()
			_selection_tween = null
		
		# 复位图标
		if icon_display and icon_display.top_level:
			# 立即设置位置和缩放（无动画），避免 top_level 切换时抽搐
			icon_display.scale = _icon_original_scale
			
			# 关闭 top_level 并恢复局部位置
			icon_display.top_level = false
			icon_display.z_index = 0
			icon_display.position = _icon_original_position
		
		# 恢复阴影
		if item_shadow:
			item_shadow.visible = icon_display.texture != null

func update_status_badge(badge_state: int) -> void:
	if is_vfx_target: return # 飞行中锁定状态图标，防止提前出现
	if not status_icon: return
	
	match badge_state:
		0:
			status_icon.visible = false
		1:
			status_icon.visible = true
			status_icon.texture = preload("res://assets/sprites/icons/tick_white.png")
		2:
			status_icon.visible = true
			status_icon.texture = preload("res://assets/sprites/icons/tick_green.png")


func _update_shelf_life_label(item: ItemInstance) -> void:
	if not shelf_life_label:
		return
	
	# 检查当前时代是否有保质期效果
	var cfg = EraManager.current_config if EraManager else null
	if not cfg or not cfg.has_shelf_life():
		shelf_life_label.visible = false
		return
	
	# 显示保质期
	if item.shelf_life >= 0:
		shelf_life_label.visible = true
		shelf_life_label.text = str(item.shelf_life)
		
		# 根据保质期剩余量改变颜色
		if item.is_expired:
			shelf_life_label.modulate = Color(1.0, 0.3, 0.3) # 红色：过期
		elif item.shelf_life <= 5:
			shelf_life_label.modulate = Color(1.0, 0.7, 0.3) # 橙色：警告
		else:
			shelf_life_label.modulate = Color.WHITE # 白色：正常
	else:
		shelf_life_label.visible = false


func _create_shelf_life_label() -> void:
	# 在代码中动态创建标签，以解决 .tscn 难以手动修改的问题
	shelf_life_label = Label.new()
	shelf_life_label.name = "ShelfLifeLabel"
	add_child(shelf_life_label)
	
	# 设置样式
	shelf_life_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shelf_life_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	# 设置字体大小
	var font_size = 40
	shelf_life_label.add_theme_font_size_override("font_size", font_size)
	
	# 设置描边以提高可读性
	shelf_life_label.add_theme_constant_override("outline_size", 8)
	shelf_life_label.add_theme_color_override("font_outline_color", Color.BLACK)
	
	# 设置位置 (根据项目 Sprite2D 坐标系统调整)
	# 假设图标中心在 (0,0)，我们将标签放在右下角
	shelf_life_label.position = Vector2(50, 50)
	
	# 初始隐藏
	shelf_life_label.visible = false
