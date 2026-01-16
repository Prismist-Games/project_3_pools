class_name ItemSlotUI
extends BaseSlotUI

## 鼠标悬停状态信号
signal hover_state_changed(slot_index: int, is_hovered: bool)

@onready var icon_display: Sprite2D = find_child("Item_icon", true)
@onready var item_shadow: Sprite2D = find_child("Item_shadow", true)
@onready var affix_display: Sprite2D = find_child("Item_affix", true)
@onready var led_display: Sprite2D = find_child("Slot_led", true)
@onready var backgrounds: Node2D = find_child("Item Slot_backgrounds", true)
@onready var hover_icon: Sprite2D = find_child("Item_hover_icon", true)
@onready var rarity_display: Sprite2D = find_child("Item_rarity", true)

## 角标节点引用 (LR=Lower Right, UR=Upper Right, LL=Lower Left/Upper Left)
@onready var status_badge: Sprite2D = find_child("Item_status_LR", true)
@onready var upgradeable_badge: Sprite2D = find_child("Item_upgradeable_UR", true)
@onready var freshness_badge: Sprite2D = find_child("Item_freshness_UL", true)
@onready var freshness_label: RichTextLabel = null


## 角标动画 Tween 引用
var _status_badge_tween: Tween = null
var _upgradeable_badge_tween: Tween = null
var _freshness_badge_tween: Tween = null

## 角标当前状态 (用于避免重复动画)
var _status_badge_visible: bool = false
var _upgradeable_badge_visible: bool = false
var _freshness_badge_visible: bool = false

## 角标动画配置
const BADGE_SHOW_ROTATION: float = 0.0
const BADGE_HIDE_ROTATION_RIGHT: float = deg_to_rad(90.0) # 右侧角标隐藏位 90°
const BADGE_HIDE_ROTATION_LEFT: float = deg_to_rad(-90.0) # 左侧角标隐藏位 -90°
const BADGE_ANIMATION_DURATION: float = 1.0

## Hover 图标素材
var _recycle_hover_texture: Texture2D = preload("res://assets/sprites/the_machine_switch/Recycle_icon.png")
var _merge_hover_texture: Texture2D = preload("res://assets/sprites/icons/upgrade_icon_hover.png")
var _trash_texture: Texture2D = preload("res://assets/sprites/icons/items/item_trash.png")

## Hover 状态类型
enum HoverType {NONE, RECYCLABLE, MERGEABLE}
var _current_hover_type: HoverType = HoverType.NONE
var _is_hovered: bool = false

var slot_index: int = -1
var is_vfx_target: bool = false # 标记是否为飞行目标，防止动画中背景色提前刷新
var _selection_tween: Tween = null
var _is_selected: bool = false
var _icon_original_position: Vector2 = Vector2.ZERO
var _icon_original_scale: Vector2 = Vector2.ONE
var _is_mouse_pressed: bool = false # 跟踪鼠标是否按下
var _press_scale_tween: Tween = null # 按下缩放的tween
var _current_item: ItemInstance = null # 当前物品实例，用于获取 rarity
var _rarity_rotation_tween: Tween = null # rarity 旋转动画
var _rarity_scale_tween: Tween = null # rarity 缩放动画
var _rarity_original_scale: Vector2 = Vector2.ONE # rarity 原始缩放

func _ready() -> void:
	super._ready()
	
	
	# 查找 freshness 角标内的 label
	if freshness_badge:
		freshness_label = freshness_badge.find_child("Item_freshness_label", true)
		
	# 关键修复 2：将材质唯一化，防止多个 Slot 共享同一个 Shader 实例
	if icon_display and icon_display.material:
		icon_display.material = icon_display.material.duplicate()
		
	# 关键修复：在一开始就记录图标的初始状态，不再动态捕获，防止缩放累加
	if icon_display:
		_icon_original_position = icon_display.position
		_icon_original_scale = icon_display.scale
	
	# 初始化 rarity 显示为隐藏
	if rarity_display:
		rarity_display.visible = false
		_rarity_original_scale = rarity_display.scale
		rarity_display.scale = Vector2.ZERO # 初始缩放为 0
	
	# 初始化角标为隐藏状态（旋转到隐藏位置）
	_init_badges()

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
	# 注意：角标的显示/隐藏由旋转动画控制，不在这里直接设置 visible

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
	
	# 关键修复 1：无论是否有物品，先重置 hover 视觉状态，防止残留
	_disable_hover_visuals()
	_current_hover_type = HoverType.NONE
	
	# 如果处于临时隐藏状态，且确实有物品（为了防止误隐藏空槽），则不更新显示
	if _temp_hide_until_vfx:
		if item:
			return
		else:
			# 如果物品没了，理应解除隐藏状态
			_temp_hide_until_vfx = false
	
	# 记录是否是新物品进入（用于判断是否播放 rarity 入场动画）
	var is_new_item_entering: bool = (item != null and _current_item != item)
	
	if not item:
		_current_item = null
		icon_display.texture = null
		if item_shadow: item_shadow.visible = false
		affix_display.visible = false
		led_display.modulate = Color(0.5, 0.5, 0.5, 0.5) # Grayed out
		
		# 重置绝育效果
		if icon_display and icon_display.material:
			var mat = icon_display.material as ShaderMaterial
			if mat:
				mat.set_shader_parameter("saturation", 1.0)
		
		# 背景颜色渐变到空槽颜色
		if backgrounds:
			_animate_background_color(Constants.COLOR_BG_SLOT_EMPTY)
			
		# 确保图标彻底隐藏
		hide_icon()
		
		# 隐藏所有角标
		_hide_all_badges()
		
		# 强制清理选中视觉，因为物品没了
		if _is_selected:
			set_selected(false)
		return
	
	_current_item = item
	
	if item_shadow:
		item_shadow.visible = not _is_selected # 选中时不显示阴影
	
	# 绝育的不再使用 item_affix 作为显示，而是使用 shader
	affix_display.visible = false
	if icon_display and icon_display.material:
		var mat = icon_display.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("saturation", 0.0 if item.sterile else 1.0)
	
	# ERA_4: 过期物品视觉标识
	if item.is_expired:
		# 仅当它是“原本就在这里的物品”且刚变成垃圾时，播放变化动画
		# 如果是新进来的（交换、移动、购买），或者是正在通过 VFX 飞行落地的，直接设置
		if not is_new_item_entering and icon_display.texture != _trash_texture and icon_display.texture != null:
			_play_trash_transformation_animation(_trash_texture)
		else:
			icon_display.texture = _trash_texture
			icon_display.modulate = Color.WHITE
	else:
		# 正常物品
		icon_display.texture = item.item_data.icon
		icon_display.modulate = Color.WHITE
	
	
	# 更新 freshness 角标
	update_freshness_badge(item.shelf_life)
	
	# 背景颜色渐变到稀有度颜色
	if backgrounds:
		_animate_background_color(Constants.get_rarity_border_color(item.rarity))
	
	# 确保图标显示（如果不在 VFX 隐藏中）
	show_icon()
	
	# 如果当前是选中状态，更新 rarity 显示
	if _is_selected:
		_update_rarity_display()
	elif is_new_item_entering:
		# 只有新物品进入 slot 时，才播放 rarity 从 scale 1 缩小到 0 的动画（衔接 VFX）
		_play_rarity_entry_animation()

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
	_update_rarity_display()
	
	if not selected:
		if backgrounds:
			backgrounds.modulate = Color.WHITE

func set_highlight(active: bool) -> void:
	if backgrounds:
		if active:
			backgrounds.modulate = Color(1.2, 1.2, 1.2, 1.0)
		else:
			backgrounds.modulate = Color.WHITE

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
		
		# 复位图标 - 平滑播放恢复动画
		if icon_display and icon_display.top_level:
			# 创建恢复动画 (Tween)
			var closing_tween = create_tween().set_parallel(true)
			closing_tween.tween_property(icon_display, "scale", _icon_original_scale, 0.2) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			
			# 计算目标全局位置：回到其原本在 Slot 中的位置
			# 使用 get_parent().global_position 是最健壮的，因为 top_level 不改变 parent 引用
			if icon_display.get_parent():
				var target_global_pos = icon_display.get_parent().to_global(_icon_original_position)
				closing_tween.tween_property(icon_display, "global_position", target_global_pos, 0.2) \
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			
			closing_tween.set_parallel(false)
			closing_tween.tween_callback(func():
				# Callback 中再次检查，防止在动画过程中 slot 状态发生改变
				if is_instance_valid(icon_display) and not _is_selected:
					icon_display.top_level = false
					icon_display.z_index = 0
					icon_display.position = _icon_original_position
					icon_display.scale = _icon_original_scale
					# 恢复阴影
					if item_shadow:
						item_shadow.visible = icon_display.texture != null
			)
		else:
			# 后备方案：如果没有处于 top_level 状态，直接同步复位比例和位置
			if icon_display:
				icon_display.scale = _icon_original_scale
				icon_display.position = _icon_original_position
			# 恢复阴影
			if item_shadow:
				item_shadow.visible = icon_display.texture != null

## 更新 rarity 显示（选中时显示并旋转，非选中时隐藏）
func _update_rarity_display() -> void:
	if not rarity_display:
		return
	
	if _is_selected and _current_item:
		# 设置颜色
		rarity_display.self_modulate = Constants.get_rarity_border_color(_current_item.rarity)
		
		# 显示并播放 scale 动画（从 0 到原始大小）
		rarity_display.visible = true
		if _rarity_scale_tween:
			_rarity_scale_tween.kill()
		_rarity_scale_tween = create_tween()
		_rarity_scale_tween.tween_property(rarity_display, "scale", _rarity_original_scale, 0.2) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		
		# 开始旋转动画（如果还没开始或已停止）
		if not _rarity_rotation_tween or not _rarity_rotation_tween.is_valid() or not _rarity_rotation_tween.is_running():
			# 停止旧的 tween
			if _rarity_rotation_tween:
				_rarity_rotation_tween.kill()
			_rarity_rotation_tween = create_tween()
			_rarity_rotation_tween.set_loops() # 无限循环
			# 使用 from(0.0) 确保每次循环都从 0 开始
			_rarity_rotation_tween.tween_property(rarity_display, "rotation", TAU, 3.0) \
				.from(0.0) \
				.set_trans(Tween.TRANS_LINEAR)
	else:
		# 停止旋转
		if _rarity_rotation_tween:
			_rarity_rotation_tween.kill()
			_rarity_rotation_tween = null
		
		# 播放 scale 动画（从当前到 0）然后隐藏
		if _rarity_scale_tween:
			_rarity_scale_tween.kill()
		_rarity_scale_tween = create_tween()
		_rarity_scale_tween.tween_property(rarity_display, "scale", Vector2.ZERO, 0.2) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		_rarity_scale_tween.tween_callback(func():
			rarity_display.visible = false
			rarity_display.rotation = 0.0
			_rarity_scale_tween = null
		)

## 播放物品进入 slot 时的 rarity 动画（从 scale 1 缩小到 0，衔接 VFX）
func _play_rarity_entry_animation() -> void:
	if not rarity_display or not _current_item:
		return
	
	# 设置颜色
	rarity_display.self_modulate = Constants.get_rarity_border_color(_current_item.rarity)
	
	# 显示并设置初始 scale 为 1（衔接 VFX 中的 scale）
	rarity_display.visible = true
	rarity_display.scale = _rarity_original_scale
	
	# 停止之前的动画
	if _rarity_scale_tween:
		_rarity_scale_tween.kill()
	
	# 播放缩小动画（从 1 到 0）
	_rarity_scale_tween = create_tween()
	_rarity_scale_tween.tween_property(rarity_display, "scale", Vector2.ZERO, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_rarity_scale_tween.tween_callback(func():
		rarity_display.visible = false
		rarity_display.rotation = 0.0
		_rarity_scale_tween = null
	)

## =====================================================================
## 角标动画系统
## =====================================================================

## 初始化所有角标到隐藏状态
## 旋转方向规则：LR 和 UL 隐藏位 90°，UR 和 LL 隐藏位 -90°
func _init_badges() -> void:
	# Status 角标 (LR - Lower Right，隐藏位 90°)
	if status_badge:
		status_badge.rotation = BADGE_HIDE_ROTATION_RIGHT
		_status_badge_visible = false
	
	# Upgradeable 角标 (UR - Upper Right，隐藏位 -90°)
	if upgradeable_badge:
		upgradeable_badge.rotation = BADGE_HIDE_ROTATION_LEFT
		_upgradeable_badge_visible = false
	
	# Freshness 角标 (UL - Upper Left，隐藏位 90°)
	if freshness_badge:
		freshness_badge.rotation = BADGE_HIDE_ROTATION_RIGHT
		_freshness_badge_visible = false


## 播放右侧角标动画（status, upgradeable）
func _animate_badge_right(badge: Sprite2D, should_show: bool, tween_ref: Tween) -> Tween:
	if not badge:
		return null
	
	# 杀掉之前的动画
	if tween_ref and tween_ref.is_valid():
		tween_ref.kill()
	
	var target_rotation = BADGE_SHOW_ROTATION if should_show else BADGE_HIDE_ROTATION_RIGHT
	var new_tween = create_tween()
	new_tween.tween_property(badge, "rotation", target_rotation, BADGE_ANIMATION_DURATION) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	
	return new_tween


## 播放左侧角标动画（freshness）
func _animate_badge_left(badge: Sprite2D, should_show: bool, tween_ref: Tween) -> Tween:
	if not badge:
		return null
	
	# 杀掉之前的动画
	if tween_ref and tween_ref.is_valid():
		tween_ref.kill()
	
	var target_rotation = BADGE_SHOW_ROTATION if should_show else BADGE_HIDE_ROTATION_LEFT
	var new_tween = create_tween()
	new_tween.tween_property(badge, "rotation", target_rotation, BADGE_ANIMATION_DURATION) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	
	return new_tween


## 更新 status 角标（订单满足状态）
## badge_state: 0=隐藏, 1=白色勾(拥有但不满足品质), 2=绿色勾(满足)
func update_status_badge(badge_state: int) -> void:
	if is_vfx_target: return # 飞行中锁定状态图标，防止提前出现
	if not status_badge: return
	
	var should_show = badge_state > 0
	
	# 更新纹理（不需要动画）
	if should_show:
		match badge_state:
			1:
				status_badge.texture = preload("res://assets/sprites/icons/tick_white.png")
			2:
				status_badge.texture = preload("res://assets/sprites/icons/tick_green.png")
	
	# 只在状态变化时播放动画
	if should_show != _status_badge_visible:
		_status_badge_visible = should_show
		_status_badge_tween = _animate_badge_right(status_badge, should_show, _status_badge_tween)


## 更新 upgradeable 角标（可合成提示）
## UR - Upper Right，隐藏位 -90°
func set_upgradeable_badge(should_show: bool) -> void:
	if is_vfx_target: return
	if not upgradeable_badge: return
	
	# 只在状态变化时播放动画
	if should_show != _upgradeable_badge_visible:
		_upgradeable_badge_visible = should_show
		_upgradeable_badge_tween = _animate_badge_left(upgradeable_badge, should_show, _upgradeable_badge_tween)


## 更新 freshness 角标（新鲜度/保质期）
## UL - Upper Left，隐藏位 90°
## shelf_life: -1=不显示，>=0=显示数值
func update_freshness_badge(shelf_life: int) -> void:
	if is_vfx_target: return
	if not freshness_badge: return
	
	# 检查当前时代是否应该显示保质期角标（第三时代 index=2 开始）
	var should_show = false
	var cfg = EraManager.current_config if EraManager else null
	if cfg and cfg.has_shelf_life() and shelf_life > 0:
		should_show = true
	
	# 更新标签内容
	if freshness_label and should_show:
		freshness_label.text = str(shelf_life)
	
	# 只在状态变化时播放动画
	if should_show != _freshness_badge_visible:
		_freshness_badge_visible = should_show
		_freshness_badge_tween = _animate_badge_right(freshness_badge, should_show, _freshness_badge_tween)


## 隐藏所有角标（用于物品清空时）
func _hide_all_badges() -> void:
	# Status (LR) 隐藏位 90°
	if _status_badge_visible:
		_status_badge_visible = false
		_status_badge_tween = _animate_badge_right(status_badge, false, _status_badge_tween)
	
	# Upgradeable (UR) 隐藏位 -90°
	if _upgradeable_badge_visible:
		_upgradeable_badge_visible = false
		_upgradeable_badge_tween = _animate_badge_left(upgradeable_badge, false, _upgradeable_badge_tween)
	
	# Freshness (UL) 隐藏位 90°
	if _freshness_badge_visible:
		_freshness_badge_visible = false
		_freshness_badge_tween = _animate_badge_right(freshness_badge, false, _freshness_badge_tween)


## =====================================================================
## Hover 可操作状态视觉效果
## =====================================================================

## 设置hover时的可操作状态视觉
## [param hover_type]: HoverType.NONE / RECYCLABLE / MERGEABLE
func set_hover_action_state(hover_type: HoverType) -> void:
	_current_hover_type = hover_type
	
	if hover_type == HoverType.NONE:
		_disable_hover_visuals()
	else:
		_enable_hover_visuals(hover_type)


## 启用hover视觉效果
func _enable_hover_visuals(hover_type: HoverType) -> void:
	# 1. 启用shader剪影效果
	if icon_display and icon_display.material:
		var mat = icon_display.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("is_enabled", true)
			# 可以根据类型设置不同的剪影颜色
			if hover_type == HoverType.RECYCLABLE:
				mat.set_shader_parameter("silhouette_color", Color(0.8, 0.3, 0.3, 1.0)) # 红色调
			elif hover_type == HoverType.MERGEABLE:
				mat.set_shader_parameter("silhouette_color", Color(0.3, 0.8, 0.3, 1.0)) # 绿色调
	
	# 2. 显示hover图标
	if hover_icon:
		hover_icon.visible = true
		if hover_type == HoverType.RECYCLABLE:
			hover_icon.texture = _recycle_hover_texture
		elif hover_type == HoverType.MERGEABLE:
			hover_icon.texture = _merge_hover_texture


## 禁用hover视觉效果
func _disable_hover_visuals() -> void:
	# 1. 禁用shader剪影效果
	if icon_display and icon_display.material:
		var mat = icon_display.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("is_enabled", false)
	
	# 2. 隐藏hover图标
	if hover_icon:
		hover_icon.visible = false


## 通知slot被hover
func on_mouse_enter() -> void:
	_is_hovered = true
	hover_state_changed.emit(slot_index, true)


## 通知slot不再被hover
func on_mouse_exit() -> void:
	_is_hovered = false
	# 清除hover视觉效果
	set_hover_action_state(HoverType.NONE)
	hover_state_changed.emit(slot_index, false)


## 检查当前是否被hover
func is_hovered() -> bool:
	return _is_hovered

## 处理鼠标按下：icon缩小
func handle_mouse_press() -> void:
	# 即使slot被锁定，也允许缩放动画（视觉反馈）
	# 但如果没有icon或texture，则不处理
	if not icon_display or not icon_display.texture:
		return
	
	_is_mouse_pressed = true
	
	# 如果正在选中状态，不处理缩放（选中状态有自己的动画）
	if _is_selected:
		return
	
	# 停止之前的缩放动画
	if _press_scale_tween and _press_scale_tween.is_valid():
		_press_scale_tween.kill()
	
	# icon缩小到0.9倍
	_press_scale_tween = create_tween()
	_press_scale_tween.tween_property(icon_display, "scale", _icon_original_scale * 0.9, 0.1) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## 处理鼠标松开：icon恢复并放大
func handle_mouse_release() -> void:
	_is_mouse_pressed = false
	
	if not icon_display:
		return
	
	# 如果正在选中状态，不处理缩放（选中状态有自己的动画）
	if _is_selected:
		return
	
	# 停止之前的缩放动画
	if _press_scale_tween and _press_scale_tween.is_valid():
		_press_scale_tween.kill()
	
	# icon恢复到原始大小并稍微放大（弹回效果）
	_press_scale_tween = create_tween()
	_press_scale_tween.tween_property(icon_display, "scale", _icon_original_scale * 1.05, 0.1) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_press_scale_tween.tween_property(icon_display, "scale", _icon_original_scale, 0.1) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## 播放变成垃圾的动画
func _play_trash_transformation_animation(new_texture: Texture2D) -> void:
	if not icon_display: return
	
	# 停止可能存在的缩放动画
	if _press_scale_tween and _press_scale_tween.is_valid():
		_press_scale_tween.kill()
	
	var t = create_tween()
	# 1. 缩小到 0
	t.tween_property(icon_display, "scale", Vector2.ZERO, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# 2. 换图
	t.tween_callback(func():
		icon_display.texture = new_texture
		icon_display.modulate = Color.WHITE
		if item_shadow:
			item_shadow.visible = false # 垃圾图可能不需要阴影，或者之后再显示
	)
	# 3. 弹回原始大小 (elastic)
	t.tween_property(icon_display, "scale", _icon_original_scale, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	t.tween_callback(func():
		if item_shadow:
			item_shadow.visible = not _is_selected
	)
