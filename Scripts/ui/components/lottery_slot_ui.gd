class_name LotterySlotUI
extends BaseSlotUI

## 鼠标悬停信号 (用于高亮订单需求图标)
signal hovered(pool_index: int, pool_item_type: int)
signal unhovered(pool_index: int)
signal item_hovered(item_id: StringName) # NEW: 针对抽奖结果中具体物品的高亮
signal badge_refresh_requested(slot_index: int, item: ItemInstance) # NEW: 请求刷新角标状态

## =====================================================================
## True Nodes (当前显示内容)
## =====================================================================
@onready var pool_name_label: RichTextLabel = find_child("Lottery Pool Name_label", true)
@onready var lid_icon: Sprite2D = find_child("Lottery Slot_lid_icon", true)
@onready var lid_sprite: Sprite2D = find_child("Lottery Slot_lid", true)
@onready var price_label: RichTextLabel = find_child("Price Label", true)
@onready var price_icon: Sprite2D = find_child("Price Icon", true)
@onready var affix_label: RichTextLabel = find_child("Affix Label", true)
@onready var description_label: RichTextLabel = find_child("Description Label", true)
@onready var items_grid: VBoxContainer = find_child("Lottery Required Items Icon Grid", true)

## =====================================================================
## Pseudo Nodes (下一轮预告，用于推挤动画)
## =====================================================================
@onready var lid_pseudo: Sprite2D = $"Lottery Slot_mask/Lottery Slot_lid/Lottery Slot_lid_psudo"
@onready var lid_icon_pseudo: Sprite2D = lid_pseudo.get_node("Lottery Slot_lid_icon") if lid_pseudo else null
@onready var pool_name_label_pseudo: RichTextLabel = lid_pseudo.get_node("Lottery Pool Name_label") if lid_pseudo else null
@onready var affix_label_pseudo: RichTextLabel = $"Lottery Slot_top_screen/Lottery Slot_top_screen_fill/Affix Label/Affix Label_psudo"
@onready var price_label_pseudo: RichTextLabel = $"Lottery Slot_top_screen/Lottery Slot_top_screen_fill/Price Label/Price Label_psudo"
@onready var items_grid_pseudo: VBoxContainer = $"Lottery Slot_right_screen/Lottery Slot_right_screen_fill/Lottery Required Items Icon Grid_psudo"
@onready var description_label_pseudo: RichTextLabel = $"Lottery Slot_description_screen/Lottery Slot_description_screen_fill/Description Label/Description Label_psudo"

## =====================================================================
## Item Display Nodes
## =====================================================================
@onready var item_main: Sprite2D = find_child("Item_main", true)
@onready var item_main_shadow: Sprite2D = item_main.get_node("Item_shadow") if item_main else null
@onready var item_main_hover_icon: Sprite2D = item_main.get_node_or_null("Item_hover_icon") if item_main else null
@onready var item_queue_1: Sprite2D = find_child("Item_queue_1", true)
@onready var item_queue_1_shadow: Sprite2D = item_queue_1.get_node("Item_shadow") if item_queue_1 else null
@onready var item_queue_2: Sprite2D = find_child("Item_queue_2", true)
@onready var item_queue_2_shadow: Sprite2D = item_queue_2.get_node("Item_shadow") if item_queue_2 else null

## 角标节点引用
@onready var status_badge: Sprite2D = find_child("Item_status_LR", true)
@onready var upgradeable_badge: Sprite2D = find_child("Item_upgradeable_UR", true)

## 角标动画 Tween 引用
var _status_badge_tween: Tween = null
var _upgradeable_badge_tween: Tween = null

## 角标当前状态
var _status_badge_visible: bool = false
var _upgradeable_badge_visible: bool = false

## 角标动画配置
const BADGE_SHOW_ROTATION: float = 0.0
const BADGE_HIDE_ROTATION_RIGHT: float = deg_to_rad(90.0)
const BADGE_HIDE_ROTATION_LEFT: float = deg_to_rad(-90.0)
const BADGE_ANIMATION_DURATION: float = 1.0

@onready var backgrounds: Node2D = find_child("Lottery Slot_backgrounds", true)

## Hover 图标素材（占位）
var _recycle_hover_texture: Texture2D = preload("res://assets/sprites/the_machine_switch/Recycle_icon.png")
var _merge_hover_texture: Texture2D = preload("res://assets/sprites/icons/upgrade.png")

## Hover 状态类型 (与 ItemSlotUI 保持一致)
enum HoverType {NONE, RECYCLABLE, MERGEABLE}
var _current_hover_type: HoverType = HoverType.NONE
var _is_hovered: bool = false
var _is_mouse_pressed: bool = false # 跟踪鼠标是否按下
var _item_icon_press_scale_tween: Tween = null # item icon按下缩放的tween
var _item_icon_original_scale: Vector2 = Vector2.ONE # item icon的原始缩放

## =====================================================================
## 状态变量
## =====================================================================
var pool_index: int = -1
var is_drawing: bool = false
var is_vfx_source: bool = false # 标记是否为飞行起点，防止动画开始前被 update_pending_display 刷新掉
var _pending_pool_data: Variant = null # 挂起的新奖池数据，等待关盖后应用
var _pending_hints: Dictionary = {} # 暂存的新 hints 数据
var _initial_transforms: Dictionary = {}

## 当前奖池物品类型 (用于 hover 高亮)
var current_pool_item_type: int = -1

## 标记：是否处于以旧换新等待物品投入状态
var is_waiting_for_trade_in: bool = false
var _top_item_id: StringName = &"" # 当前排在首位的物品 ID

## =====================================================================
## Push-Away 动画配置
## =====================================================================
const PUSH_VERTICAL_OFFSET: float = 550.0 # 盖子垂直推挤距离
const PUSH_LABEL_OFFSET: float = 125.0 # 标签垂直推挤距离
const PUSH_HORIZONTAL_OFFSET: float = 155.0 # 水平推挤距离 (图标格)
const PUSH_DESC_OFFSET: float = 783.0 # 描述标签水平推挤距离
const PUSH_DURATION: float = 0.4 # 推挤动画时长

## 记录所有 Push-Away 节点的初始位置
var _push_initial_positions: Dictionary = {}

## 记录当前显示的提示物品 ID 列表（用于判断是否需要推挤动画）
var _current_hint_ids: Array[StringName] = []

# 队列物品显示配置（可在编辑器中调整）
@export var queue_1_offset: Vector2 = Vector2(-116, 7)
@export var queue_1_scale: float = 0.75
@export var queue_2_offset: Vector2 = Vector2(-207, -19)
@export var queue_2_scale: float = 0.75

func _ready() -> void:
	# 记录初始 transform 以便动画复位
	_initial_transforms[item_main] = {"pos": item_main.position, "scale": item_main.scale}
	_initial_transforms[item_queue_1] = {"pos": item_queue_1.position, "scale": item_queue_1.scale}
	_initial_transforms[item_queue_2] = {"pos": item_queue_2.position, "scale": item_queue_2.scale}
	
	# 记录item icon的原始缩放（使用_initial_transforms中的值，通常是Vector2.ONE）
	if item_main and _initial_transforms.has(item_main):
		_item_icon_original_scale = _initial_transforms[item_main]["scale"]
	elif item_main:
		_item_icon_original_scale = item_main.scale
	
	# 关键修复 2：将材质唯一化
	if item_main and item_main.material:
		item_main.material = item_main.material.duplicate()
	
	# 记录 Push-Away 节点的初始位置
	_store_push_initial_positions()
	
	# 初始化角标为隐藏状态
	_init_badges()

func _store_push_initial_positions() -> void:
	## 存储所有参与推挤动画的节点的初始位置
	# 垂直推挤组 (盖子、词缀、价格)
	if lid_sprite:
		_push_initial_positions["lid_true"] = lid_sprite.position
	if lid_pseudo:
		_push_initial_positions["lid_pseudo"] = lid_pseudo.position
	if affix_label:
		_push_initial_positions["affix_true"] = affix_label.position
	if affix_label_pseudo:
		_push_initial_positions["affix_pseudo"] = affix_label_pseudo.position
	if price_label:
		_push_initial_positions["price_true"] = price_label.position
	if price_label_pseudo:
		_push_initial_positions["price_pseudo"] = price_label_pseudo.position
	
	# 水平推挤组 (需求图标、描述)
	if items_grid:
		_push_initial_positions["grid_true"] = items_grid.position
	if items_grid_pseudo:
		_push_initial_positions["grid_pseudo"] = items_grid_pseudo.position
	if description_label:
		_push_initial_positions["desc_true"] = description_label.position
	if description_label_pseudo:
		_push_initial_positions["desc_pseudo"] = description_label_pseudo.position

func setup(index: int) -> void:
	pool_index = index
	var input_area = find_child("Input Area", true)
	if input_area:
		input_area.mouse_entered.connect(_on_mouse_entered)
		input_area.mouse_exited.connect(_on_mouse_exited)

	# 奖池初始状态必须是瞬间关上的 (瞬间完成，不播放动画过程)
	if anim_player.has_animation("lid_close"):
		anim_player.play("lid_close")
		anim_player.advance(0)
		anim_player.seek(anim_player.get_animation("lid_close").length, true)

func _on_mouse_entered() -> void:
	_is_hovered = true
	
	# 始终发射 hover 信号 (用于高亮订单图标，不受 is_locked/is_drawing 限制)
	if current_pool_item_type > 0:
		hovered.emit(pool_index, current_pool_item_type)
	
	# 如果正在抽奖展示且有具体物品，发射物品高亮信号
	if is_drawing and _top_item_id != &"":
		item_hovered.emit(_top_item_id)
		
	if is_locked or is_drawing: return
	
	# 盖子微开
	create_tween().tween_property(lid_sprite, "position:y", -20, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	EventBus.game_event.emit(&"lottery_slot_hovered", ContextProxy.new({"global_position": global_position}))

func _on_mouse_exited() -> void:
	_is_hovered = false
	
	# 清除hover视觉效果
	set_hover_action_state(HoverType.NONE)
	
	# 始终发射 unhover 信号
	unhovered.emit(pool_index)
	
	if is_locked or is_drawing: return
	
	# 如果鼠标按下后移出，lid应该保持复位状态（不恢复hover效果）
	if _is_mouse_pressed:
		return
	
	# 恢复原位 (如果没在播放打开动画)
	if not anim_player.is_playing() or anim_player.current_animation != "lid_open":
		create_tween().tween_property(lid_sprite, "position:y", 0, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	EventBus.game_event.emit(&"lottery_slot_unhovered", null)

func get_main_icon_global_position() -> Vector2:
	return item_main.global_position

func get_main_icon_global_scale() -> Vector2:
	return item_main.global_scale

func hide_main_icon() -> void:
	item_main.visible = false
	# 同时隐藏所有角标（不播放动画）
	if status_badge:
		status_badge.rotation = BADGE_HIDE_ROTATION_RIGHT
		_status_badge_visible = false
	if upgradeable_badge:
		upgradeable_badge.rotation = BADGE_HIDE_ROTATION_LEFT
		_upgradeable_badge_visible = false

func show_main_icon() -> void:
	item_main.visible = true

func update_pool_info(pool: Variant) -> void:
	if not pool:
		visible = false
		return
	
	visible = true
	
	# 如果正在以旧换新等待中，或者是抽奖动画中，不要立即更新视觉
	if is_waiting_for_trade_in or is_drawing:
		_pending_pool_data = pool
		return
	
	_apply_pool_display(pool)

func _apply_pool_display(pool: Variant) -> void:
	# 使用统一的视觉更新函数，直接更新 True 节点
	_update_visuals(pool, false)
	
	# 重置背景颜色和物品显示 (For refresh)
	if backgrounds:
		backgrounds.color = Constants.COLOR_BG_SLOT_EMPTY
	item_main.visible = false
	item_main_shadow.visible = false
	item_queue_1.visible = false
	item_queue_1_shadow.visible = false
	item_queue_2.visible = false
	item_queue_2_shadow.visible = false

func update_order_hints(display_items: Array[ItemData], satisfied_map: Dictionary, is_pseudo_only: bool = false) -> void:
	if is_pseudo_only:
		# 暂存数据，仅更新 Pseudo 节点，保持 True 节点现状直到推挤完成
		_pending_hints = {"items": display_items, "map": satisfied_map}
		_update_grid_icons(items_grid_pseudo, display_items, satisfied_map)
	else:
		# 同时更新 True 和 Pseudo 节点的图标格（用于非动画刷新/初始化）
		_update_grid_icons(items_grid, display_items, satisfied_map)
		_update_grid_icons(items_grid_pseudo, display_items, satisfied_map)

func _update_grid_icons(grid: VBoxContainer, display_items: Array[ItemData], satisfied_map: Dictionary) -> void:
	if not grid:
		return
	
	# 如果更新的是真节点，记录当前物品 ID 列表
	if grid == items_grid:
		_current_hint_ids.clear()
		for item in display_items:
			_current_hint_ids.append(item.id)
	
	# 填充图标格
	for i in range(5):
		var icon_node = grid.get_node_or_null("Item Icon_" + str(i))
		if not icon_node: continue
		
		if i < display_items.size():
			icon_node.visible = true
			var item_data = display_items[i]
			icon_node.texture = item_data.icon
			
			# 更新满足状态图标
			# status: 0=没有物品, 1=有但品质不够(白色勾), 2=完全满足(不显示)
			var status_icon = icon_node.get_node_or_null("Item Icon_status")
			if status_icon:
				var status = satisfied_map.get(item_data.id, 0)
				if status == 1:
					# 有物品但品质不够，显示白色勾
					status_icon.texture = preload("res://assets/sprites/icons/tick_white.png")
					status_icon.visible = true
				else:
					# 状态0（没有）或状态2（完全满足），都不显示角标
					status_icon.visible = false
		else:
			icon_node.visible = false

func play_reveal_sequence(items: Array, skip_pop_anim: bool = false, skip_shuffle: bool = false) -> void:
	# 进入揭示流程，清除等待标记
	is_waiting_for_trade_in = false
	
	# 如果已经在展示中（is_drawing = true），说明之前已经 reveal 过了，直接更新显示即可
	if is_drawing:
		update_queue_display(items)
		return
	
	is_drawing = true

	# 1. 盖子全开
	if anim_player.has_animation("lid_open"):
		anim_player.play("lid_open")
	
	# 临时隐藏/重置图标
	if not skip_pop_anim:
		item_main.scale = Vector2.ZERO
		item_queue_1.scale = Vector2.ZERO
		item_queue_2.scale = Vector2.ZERO
	else:
		item_main.scale = Vector2.ONE
		item_queue_1.scale = Vector2(queue_1_scale, queue_1_scale)
		item_queue_2.scale = Vector2(queue_2_scale, queue_2_scale)
	
	update_queue_display(items)
	
	if not items.is_empty() and not skip_pop_anim:
		var tw = create_tween().set_parallel(true)
		tw.tween_property(item_main, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if items.size() > 1:
			tw.tween_property(item_queue_1, "scale", Vector2(queue_1_scale, queue_1_scale), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if items.size() > 2:
			tw.tween_property(item_queue_2, "scale", Vector2(queue_2_scale, queue_2_scale), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 2. 背景颜色洗牌感
	if not skip_shuffle:
		var shuffle_timer = 0.0
		var duration = 0.5
		var interval = 0.05
		while shuffle_timer < duration:
			if backgrounds:
				backgrounds.color = Constants.get_rarity_border_color(randi() % 5)
			await get_tree().create_timer(interval).timeout
			shuffle_timer += interval
	
	# 3. 定格最终品质
	if not items.is_empty() and backgrounds:
		backgrounds.color = Constants.get_rarity_border_color(items[0].rarity)
	elif backgrounds:
		backgrounds.color = Constants.COLOR_BG_SLOT_EMPTY
	
	if not skip_shuffle:
		await get_tree().create_timer(0.3).timeout # 最终揭示后的停留

## 播放关盖序列（仅关盖和重置显示，刷新动画由 PoolController 统一处理）
func play_close_sequence() -> void:
	await close_lid()
	
	is_drawing = false
	_pending_pool_data = null # 清除挂起数据，由 controller 统一刷新
	
	# 关盖后，确保背景色和物品显示重置
	if backgrounds:
		backgrounds.color = Constants.COLOR_BG_SLOT_EMPTY
	item_main.visible = false
	item_main_shadow.visible = false
	item_queue_1.visible = false
	item_queue_1_shadow.visible = false
	item_queue_2.visible = false
	item_queue_2_shadow.visible = false

func play_draw_anim() -> void:
	# 这个函数现在被 play_reveal_sequence 替代逻辑
	pass

func update_pending_display(pending_list: Array) -> void:
	if pending_list.is_empty():
		# 如果当前正在飞行（作为起始点），不要立即清空，否则会导致图标瞬间消失
		if is_vfx_source:
			return
			
		is_drawing = false
		_top_item_id = &""
		
		# 关键修复 1：重置 hover 状态
		_disable_hover_visuals()
		_current_hover_type = HoverType.NONE
		
		if backgrounds:
			backgrounds.color = Constants.COLOR_BG_SLOT_EMPTY
		# 清空所有显示
		item_main.texture = null
		item_main.visible = false
		item_main_shadow.visible = false
		item_queue_1.texture = null
		item_queue_1.visible = false
		item_queue_1_shadow.visible = false
		item_queue_2.texture = null
		item_queue_2.visible = false
		item_queue_2_shadow.visible = false
		
		# 隐藏所有角标
		_hide_all_badges()
		return
	
	# 队列不为空时，始终更新显示（即使 is_vfx_source = true）
	# 因为队列的变化反映了真实的待定状态，必须及时更新以避免显示错误的物品
	
	if backgrounds:
		backgrounds.color = Constants.get_rarity_border_color(pending_list[0].rarity)
	
	# 更新当前排在首位的物品 ID (用于 hover 高亮)
	var top_item = pending_list[0]
	_top_item_id = top_item.item_data.id if top_item is ItemInstance else top_item.get("id", &"")
	
	# 设置主要物品（update_queue_display 内部会处理显示/隐藏）
	# 关键保护：如果当前槽位是 VFX 起点，跳过真正的图标显示更新，避免干扰飞行中的 VFX
	# 但我们已经记录了 top_item_id 并更新了背景色，确保逻辑一致
	if is_vfx_source:
		# 即使处于 VFX 状态，也要尝试静默更新队列信息（除了 main 以外的）
		# 但为了稳妥，我们让 play_queue_advance_anim 负责这部分的物理表现
		return
		
	update_queue_display(pending_list)

func update_queue_display(items: Array) -> void:
	# 硬编码位置偏移: Main (0, -26), Queue1 (+25, -30), Queue2 (+45, -34)
	var base_pos = item_main.position
	if _initial_transforms.is_empty():
		base_pos = Vector2(0, -26)
	else:
		base_pos = _initial_transforms[item_main]["pos"]
	
	# item_main 永远显示 items[0]
	if items.size() > 0:
		var top_item = items[0]
		
		item_main.texture = top_item.item_data.icon if top_item is ItemInstance else top_item.get("icon")
		item_main.visible = true
		item_main_shadow.visible = true
		item_main.z_index = 0
		# 不在这里重置scale，让动画完全控制scale
		# 只有在没有正在交互且没有正在运行的动画时才重置
		if not _is_mouse_pressed and not (_item_icon_press_scale_tween and _item_icon_press_scale_tween.is_valid() and _item_icon_press_scale_tween.is_running()):
			# 如果scale异常（接近0），才重置
			if item_main.scale.length() < 0.1:
				item_main.scale = _item_icon_original_scale
	else:
		_top_item_id = &""
		item_main.texture = null
		item_main.visible = false
		item_main_shadow.visible = false
		
	# queue_1 显示 items[1]
	if items.size() > 1:
		var q1_item = items[1]
		item_queue_1.texture = q1_item.item_data.icon if q1_item is ItemInstance else q1_item.get("icon")
		item_queue_1.visible = true
		item_queue_1_shadow.visible = true
		item_queue_1.position = base_pos + queue_1_offset
		item_queue_1.scale = Vector2(queue_1_scale, queue_1_scale)
		item_queue_1.z_index = 0
	else:
		item_queue_1.texture = null
		item_queue_1.visible = false
		item_queue_1_shadow.visible = false
	
	# queue_2 显示 items[2]
	if items.size() > 2:
		var q2_item = items[2]
		item_queue_2.texture = q2_item.item_data.icon if q2_item is ItemInstance else q2_item.get("icon")
		item_queue_2.visible = true
		item_queue_2_shadow.visible = true
		item_queue_2.position = base_pos + queue_2_offset
		item_queue_2.scale = Vector2(queue_2_scale, queue_2_scale)
		item_queue_2.z_index = 0
	else:
		item_queue_2.texture = null
		item_queue_2.visible = false
		item_queue_2_shadow.visible = false
	
func play_queue_advance_anim() -> void:
	# 如果队列1不可见，说明队列为空，无需动画
	if not item_queue_1.visible:
		return
	
	var duration = 0.3
	
	# 捕获动画前的 texture 和状态（防止动画期间数据变化导致的竞态条件）
	var q1_texture = item_queue_1.texture
	var q2_texture = item_queue_2.texture if item_queue_2.visible else null
	var had_q2 = item_queue_2.visible
	
	# 创建 Tween（此时已确保至少有 queue1 的动画）
	var tw = create_tween().set_parallel(true)
	
	var q1_pos = item_queue_1.position
	var main_pos = item_main.position
	var q1_scale = item_queue_1.scale
	var main_scale = item_main.scale
	
	# 让 queue1 移动到 main 的位置和缩放
	tw.tween_property(item_queue_1, "position", main_pos, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(item_queue_1, "scale", main_scale, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	if had_q2:
		tw.tween_property(item_queue_2, "position", q1_pos, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(item_queue_2, "scale", q1_scale, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	await tw.finished
	
	# 动画结束后：手动执行"前进"操作
	# 1. main <- queue_1 的 texture
	# 2. queue_1 <- queue_2 的 texture (如果有)
	# 3. queue_2 隐藏
	
	# 恢复各节点到初始位置/缩放
	_reset_item_transforms()
	item_queue_1.position = _initial_transforms[item_queue_1]["pos"]
	item_queue_1.scale = _initial_transforms[item_queue_1]["scale"]
	item_queue_2.position = _initial_transforms[item_queue_2]["pos"]
	item_queue_2.scale = _initial_transforms[item_queue_2]["scale"]
	
	# 更新 texture（基于动画开始时捕获的状态）
	item_main.texture = q1_texture
	item_main.visible = q1_texture != null
	item_main_shadow.visible = q1_texture != null
	
	# 【优化】前进完成后，如果还有物品，请求刷新角标
	if q1_texture != null:
		# 我们需要找到对应的 ItemInstance 以传递给信号
		# 注意：此时 InventorySystem 可能已经 pop 了，所以我们依赖传入的 texture 或者外部刷新
		# 为了保险，直接发信号，让 Controller 处理
		badge_refresh_requested.emit(pool_index, null)
	
	if had_q2:
		item_queue_1.texture = q2_texture
		item_queue_1.visible = q2_texture != null
		item_queue_1_shadow.visible = q2_texture != null
	else:
		item_queue_1.texture = null
		item_queue_1.visible = false
		item_queue_1_shadow.visible = false
	
	# queue_2 总是被前移或清空
	item_queue_2.texture = null
	item_queue_2.visible = false
	item_queue_2_shadow.visible = false
	
	# 更新背景颜色 (如果 main 仍有物品，保持当前颜色；否则重置)
	if not item_main.visible and backgrounds:
		backgrounds.color = Constants.COLOR_BG_SLOT_EMPTY
		
	# 如果所有物品都没了，隐藏角标
	if not item_main.visible:
		_hide_all_badges()


func open_lid() -> void:
	if anim_player.has_animation("lid_open"):
		anim_player.play("lid_open")

## 为以旧换新打开盖子（空槽状态，等待物品飞入）
func open_lid_for_trade_in() -> void:
	is_waiting_for_trade_in = true
	
	# 确保内部显示为空
	item_main.visible = false
	item_main_shadow.visible = false
	item_queue_1.visible = false
	item_queue_1_shadow.visible = false
	item_queue_2.visible = false
	item_queue_2_shadow.visible = false
	
	# 背景保持空槽颜色
	if backgrounds:
		backgrounds.color = Constants.COLOR_BG_SLOT_EMPTY
	
	# 打开盖子
	if anim_player.has_animation("lid_open"):
		anim_player.play("lid_open")

func close_lid() -> void:
	is_waiting_for_trade_in = false
	if anim_player.has_animation("lid_close"):
		anim_player.play("lid_close")
		if anim_player.is_playing():
			await anim_player.animation_finished

## 播放抖动动画（用于以旧换新投入后的反馈）
func play_shake() -> void:
	var original_pos = position
	var shake_amount = 8.0
	var shake_duration = 0.08
	var shake_count = 3
	
	var tween = create_tween()
	for i in range(shake_count):
		var direction = 1 if i % 2 == 0 else -1
		tween.tween_property(self, "position:x", original_pos.x + shake_amount * direction, shake_duration)
	tween.tween_property(self, "position:x", original_pos.x, shake_duration)

func _reset_item_transforms() -> void:
	if _initial_transforms.is_empty(): return
	
	# 只恢复 Main 的 transform，Queue 的由 update_queue_display 控制
	item_main.position = _initial_transforms[item_main]["pos"]
	item_main.scale = _initial_transforms[item_main]["scale"]

## =====================================================================
## Push-Away 刷新系统
## =====================================================================

## 刷新奖池显示数据（核心入口）
## [param new_pool_data]: 新的奖池配置
## [param is_instant]: true = 游戏初始化时瞬间设置，false = 运行时带动画刷新
func refresh_slot_data(new_pool_data: Variant, is_instant: bool = false) -> void:
	if is_instant:
		# 游戏初始化时直接设置 True Nodes
		_update_visuals(new_pool_data, false) # false = targeting true nodes
	else:
		# 运行时刷新：设置 Pseudo Nodes 并播放动画
		_update_visuals(new_pool_data, true) # true = targeting pseudo nodes
		
		# 检查是否跳过盖子位移动画 (PreciseSelection 需求)
		var skip_lid := false
		if new_pool_data is Dictionary and new_pool_data.get("skip_lid_animation", false):
			skip_lid = true
			
		await _play_push_away_animation(skip_lid)
		
		# 动画结束后，将数据同步到 True Nodes 并复位
		_update_visuals(new_pool_data, false)
		
		# 同步暂存的 hints 到 True 节点
		if not _pending_hints.is_empty():
			_update_grid_icons(items_grid, _pending_hints.items, _pending_hints.map)
			_pending_hints.clear()
			
		_reset_push_positions()

## 更新视觉元素
## [param pool]: 奖池配置数据
## [param target_pseudo]: true = 更新 Pseudo 节点，false = 更新 True 节点
func _update_visuals(pool: Variant, target_pseudo: bool) -> void:
	if not pool:
		return
	
	# 选择目标节点
	var target_lid_sprite: Sprite2D = lid_pseudo if target_pseudo else lid_sprite
	var target_lid_icon: Sprite2D = lid_icon_pseudo if target_pseudo else lid_icon
	var target_pool_name: RichTextLabel = pool_name_label_pseudo if target_pseudo else pool_name_label
	var target_affix: RichTextLabel = affix_label_pseudo if target_pseudo else affix_label
	var target_price: RichTextLabel = price_label_pseudo if target_pseudo else price_label
	var target_desc: RichTextLabel = description_label_pseudo if target_pseudo else description_label
	var target_grid: VBoxContainer = items_grid_pseudo if target_pseudo else items_grid
	
	# 更新盖子图标和颜色 (仅当 pool 提供明确的 item_type 时才更新)
	var has_item_type = ("item_type" in pool) or (pool is Dictionary and pool.has("item_type"))
	if has_item_type:
		var item_type = pool.item_type if "item_type" in pool else pool.get("item_type")
		
		# 记录当前奖池物品类型 (用于 hover 高亮，仅更新 True 节点时记录)
		if not target_pseudo:
			current_pool_item_type = item_type
		
		var theme_color := Color("#199C80") # 普通门颜色为机器色
		
		if target_lid_sprite:
			target_lid_sprite.self_modulate = theme_color
		if target_lid_icon:
			target_lid_icon.texture = Constants.type_to_icon(item_type)
			target_lid_icon.self_modulate = theme_color
	
	# 更新奖池名称
	if target_pool_name and has_item_type:
		var item_type = pool.item_type if "item_type" in pool else pool.get("item_type")
		target_pool_name.text = tr(Constants.type_to_display_name(item_type)) + " " + tr("POOL_SUFFIX")
		target_pool_name.visible = true
	
	# 更新价格 (始终保持可见)
	if target_price:
		var cost_text = ""
		if pool is Dictionary and pool.has("price_text"):
			cost_text = pool.price_text
		else:
			var cost_gold: int = pool.get("gold_cost") if "gold_cost" in pool else 0
			cost_text = str(cost_gold)
		
		target_price.text = cost_text
		target_price.visible = true # 强制保持可见，即使文本为空
	
	# Price Icon 逻辑 (始终保持可见)
	if not target_pseudo and price_icon:
		price_icon.texture = preload("res://assets/sprites/icons/money.png")
		price_icon.visible = true # 强制保持可见
	
	# 更新词缀
	if target_affix:
		if pool is Dictionary and pool.has("affix_name"):
			target_affix.text = pool.affix_name
		elif "affix_data" in pool and pool.affix_data:
			target_affix.text = pool.affix_data.name
		else:
			target_affix.text = ""
	
	# 更新描述
	if target_desc:
		if pool is Dictionary and pool.has("description_text"):
			target_desc.text = pool.description_text
		elif "affix_data" in pool and pool.affix_data:
			target_desc.text = pool.affix_data.description
		else:
			target_desc.text = ""
	
	# 更新需求图标 (如果是清空模式)
	if target_grid and pool is Dictionary and pool.get("clear_hints", false):
		# 关键：清空模式下必须同时清除暂存数据，防止动画结束后被还原
		_pending_hints.clear()
		_current_hint_ids.clear()
		
		for i in range(5):
			var icon_node = target_grid.get_node_or_null("Item Icon_" + str(i))
			if icon_node:
				icon_node.visible = false
				var status_icon = icon_node.get_node_or_null("Item Icon_status")
				if status_icon: status_icon.visible = false

## 仅刷新订单需求图标（局部动画）
func refresh_hints_animated(display_items: Array[ItemData], satisfied_map: Dictionary) -> void:
	if not items_grid or not items_grid_pseudo:
		return
	
	# 如果没有存储初始位置，直接更新不做动画
	if not _push_initial_positions.has("grid_true"):
		_update_grid_icons(items_grid, display_items, satisfied_map)
		return
	
	# 1. 更新 Pseudo 节点
	_update_grid_icons(items_grid_pseudo, display_items, satisfied_map)
	
	# 2. 播放局部水平推挤动画
	var tw := create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	
	var grid_true_start: Vector2 = _push_initial_positions["grid_true"]
	# True 向右移出
	tw.tween_property(items_grid, "position:x", grid_true_start.x + PUSH_HORIZONTAL_OFFSET, PUSH_DURATION)
	# Pseudo 从左侧移入到 True 的起始位置
	tw.tween_property(items_grid_pseudo, "position:x", grid_true_start.x, PUSH_DURATION)
	
	await tw.finished
	
	# 3. 动画结束后同步到 True 节点并复位位置
	_update_grid_icons(items_grid, display_items, satisfied_map)
	items_grid.position = _push_initial_positions["grid_true"]
	items_grid_pseudo.position = _push_initial_positions["grid_pseudo"]


## 检查传入的物品列表 ID 是否与当前显示的一致
func is_hint_content_equal(new_items: Array[ItemData]) -> bool:
	if _current_hint_ids.size() != new_items.size():
		return false
	
	for i in range(new_items.size()):
		if _current_hint_ids[i] != new_items[i].id:
			return false
	return true

## 播放推挤动画
## [param skip_lid]: 是否跳过盖子的位移动画
## 注意：场景中有两种节点关系：
## - 父子关系 (lid, affix, price, description)：Pseudo 是 True 的子节点，只需移动父节点
## - 兄弟关系 (items_grid)：两者是同级节点，需要分别动画
func _play_push_away_animation(skip_lid: bool = false) -> void:
	# 提前检测：如果所有推挤节点都无效，直接返回，避免创建空 Tween
	var can_animate := (
		(lid_sprite and _push_initial_positions.has("lid_true")) or
		(affix_label and _push_initial_positions.has("affix_true")) or
		(price_label and _push_initial_positions.has("price_true")) or
		(items_grid and items_grid_pseudo and _push_initial_positions.has("grid_true")) or
		(description_label and _push_initial_positions.has("desc_true"))
	)
	
	if not can_animate:
		push_warning("[LotterySlotUI] _play_push_away_animation: No valid nodes for animation, skipping")
		return
	var tw := create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	
	# ============ 垂直推挤组 (向下移出，从上移入) ============
	# 这些都是父子关系：只移动 TRUE 节点，PSEUDO 作为子节点会自动跟随进入视野
	
	# 盖子 (父子关系)
	if not skip_lid and lid_sprite and _push_initial_positions.has("lid_true"):
		var lid_true_start: Vector2 = _push_initial_positions["lid_true"]
		tw.tween_property(lid_sprite, "position:y", lid_true_start.y + PUSH_VERTICAL_OFFSET, PUSH_DURATION)
	
	# 词缀标签 (父子关系)
	if affix_label and _push_initial_positions.has("affix_true"):
		var affix_true_start: Vector2 = _push_initial_positions["affix_true"]
		tw.tween_property(affix_label, "position:y", affix_true_start.y + PUSH_LABEL_OFFSET, PUSH_DURATION)
	
	# 价格标签 (父子关系)
	if price_label and _push_initial_positions.has("price_true"):
		var price_true_start: Vector2 = _push_initial_positions["price_true"]
		tw.tween_property(price_label, "position:y", price_true_start.y + PUSH_LABEL_OFFSET, PUSH_DURATION)
	
	# ============ 水平推挤组 (向右移出，从左移入) ============
	
	# 需求图标格 (兄弟关系：两者都是 Lottery Slot_right_screen_fill 的子节点)
	if items_grid and items_grid_pseudo and _push_initial_positions.has("grid_true"):
		var grid_true_start: Vector2 = _push_initial_positions["grid_true"]
		# True 向右移出
		tw.tween_property(items_grid, "position:x", grid_true_start.x + PUSH_HORIZONTAL_OFFSET, PUSH_DURATION)
		# Pseudo 从左侧移入到 True 的起始位置
		tw.tween_property(items_grid_pseudo, "position:x", grid_true_start.x, PUSH_DURATION)
	
	# 描述标签 (父子关系)
	if description_label and _push_initial_positions.has("desc_true"):
		var desc_true_start: Vector2 = _push_initial_positions["desc_true"]
		tw.tween_property(description_label, "position:x", desc_true_start.x + PUSH_DESC_OFFSET, PUSH_DURATION)
	
	await tw.finished


## 重置所有 Push-Away 节点到初始位置
## 注意：父子关系的节点只需重置父节点，子节点会自动回到相对位置
func _reset_push_positions() -> void:
	# 垂直组 (父子关系，只重置 True 节点)
	if lid_sprite and _push_initial_positions.has("lid_true"):
		lid_sprite.position = _push_initial_positions["lid_true"]
	if affix_label and _push_initial_positions.has("affix_true"):
		affix_label.position = _push_initial_positions["affix_true"]
	if price_label and _push_initial_positions.has("price_true"):
		price_label.position = _push_initial_positions["price_true"]
	
	# 水平组 - 兄弟关系 (需要重置两者)
	if items_grid and _push_initial_positions.has("grid_true"):
		items_grid.position = _push_initial_positions["grid_true"]
	if items_grid_pseudo and _push_initial_positions.has("grid_pseudo"):
		items_grid_pseudo.position = _push_initial_positions["grid_pseudo"]
	
	# 水平组 - 父子关系 (只重置 True 节点)
	if description_label and _push_initial_positions.has("desc_true"):
		description_label.position = _push_initial_positions["desc_true"]

## =====================================================================
## 角标动画系统 (与 ItemSlotUI 保持一致)
## =====================================================================

## 初始化所有角标到隐藏状态
func _init_badges() -> void:
	# Status 角标 (LR - Lower Right，隐藏位 90°)
	if status_badge:
		status_badge.rotation = BADGE_HIDE_ROTATION_RIGHT
		_status_badge_visible = false
	
	# Upgradeable 角标 (UR - Upper Right，隐藏位 -90°)
	if upgradeable_badge:
		upgradeable_badge.rotation = BADGE_HIDE_ROTATION_LEFT
		_upgradeable_badge_visible = false


## 播放右侧角标动画
func _animate_badge_right(badge: Sprite2D, should_show: bool, tween_ref: Tween) -> Tween:
	if not badge:
		return null
	
	if tween_ref and tween_ref.is_valid():
		tween_ref.kill()
	
	var target_rotation = BADGE_SHOW_ROTATION if should_show else BADGE_HIDE_ROTATION_RIGHT
	var new_tween = create_tween()
	new_tween.tween_property(badge, "rotation", target_rotation, BADGE_ANIMATION_DURATION) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	
	return new_tween


## 播放左侧角标动画 (UR 隐藏位是 -90°, 在 ItemSlotUI 中也被归为 left 逻辑)
func _animate_badge_left(badge: Sprite2D, should_show: bool, tween_ref: Tween) -> Tween:
	if not badge:
		return null
	
	if tween_ref and tween_ref.is_valid():
		tween_ref.kill()
	
	var target_rotation = BADGE_SHOW_ROTATION if should_show else BADGE_HIDE_ROTATION_LEFT
	var new_tween = create_tween()
	new_tween.tween_property(badge, "rotation", target_rotation, BADGE_ANIMATION_DURATION) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	
	return new_tween


## 更新 status 角标（订单满足状态）
## badge_state: 0=隐藏, 1=白色勾, 2=绿色勾
func update_status_badge(badge_state: int) -> void:
	if not status_badge: return
	
	# 【优化】如果正在播放开盖动画，等待动画结束再显示角标
	if anim_player.is_playing() and anim_player.current_animation == "lid_open":
		await anim_player.animation_finished
	
	# 再次检查，防止动画期间状态已变
	if not status_badge: return
	
	var should_show = badge_state > 0
	
	# 更新纹理
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
func set_upgradeable_badge(should_show: bool) -> void:
	if not upgradeable_badge: return
	
	# 【优化】如果正在播放开盖动画，等待动画结束再显示角标
	if anim_player.is_playing() and anim_player.current_animation == "lid_open":
		await anim_player.animation_finished
	
	# 再次检查
	if not upgradeable_badge: return
	
	# 只在状态变化时播放动画
	if should_show != _upgradeable_badge_visible:
		_upgradeable_badge_visible = should_show
		_upgradeable_badge_tween = _animate_badge_left(upgradeable_badge, should_show, _upgradeable_badge_tween)


## 隐藏所有角标
func _hide_all_badges() -> void:
	if _status_badge_visible:
		_status_badge_visible = false
		_status_badge_tween = _animate_badge_right(status_badge, false, _status_badge_tween)
	
	if _upgradeable_badge_visible:
		_upgradeable_badge_visible = false
		_upgradeable_badge_tween = _animate_badge_left(upgradeable_badge, false, _upgradeable_badge_tween)


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
	if item_main and item_main.material:
		var mat = item_main.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("is_enabled", true)
			# 可以根据类型设置不同的剪影颜色
			if hover_type == HoverType.RECYCLABLE:
				mat.set_shader_parameter("silhouette_color", Color(0.8, 0.3, 0.3, 1.0)) # 红色调
			elif hover_type == HoverType.MERGEABLE:
				mat.set_shader_parameter("silhouette_color", Color(0.3, 0.8, 0.3, 1.0)) # 绿色调
	
	# 2. 显示hover图标
	if item_main_hover_icon:
		item_main_hover_icon.visible = true
		if hover_type == HoverType.RECYCLABLE:
			item_main_hover_icon.texture = _recycle_hover_texture
		elif hover_type == HoverType.MERGEABLE:
			item_main_hover_icon.texture = _merge_hover_texture


## 禁用hover视觉效果
func _disable_hover_visuals() -> void:
	# 1. 禁用shader剪影效果
	if item_main and item_main.material:
		var mat = item_main.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("is_enabled", false)
	
	# 2. 隐藏hover图标
	if item_main_hover_icon:
		item_main_hover_icon.visible = false


## 检查当前是否被hover
func is_hovered() -> bool:
	return _is_hovered

## 设置高亮效果（用于选择状态下的hover变亮）
func set_highlight(active: bool) -> void:
	if backgrounds:
		if active:
			backgrounds.modulate = Color(1.2, 1.2, 1.2, 1.0)
		else:
			backgrounds.modulate = Color.WHITE

## 处理鼠标按下：让lid复位，item icon缩小
func handle_mouse_press() -> void:
	# 即使slot被锁定，也允许缩放动画（视觉反馈）
	# 但lid复位只在非锁定且非drawing状态下执行
	_is_mouse_pressed = true
	
	# lid复位到原位置（仅在非锁定且非drawing状态下，drawing状态下盖子已经打开）
	if not is_locked and not is_drawing:
		create_tween().tween_property(lid_sprite, "position:y", 0, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# item icon缩小（如果有显示，包括pending状态下的is_drawing）
	if item_main and item_main.visible and item_main.texture:
		# 停止之前的缩放动画
		if _item_icon_press_scale_tween and _item_icon_press_scale_tween.is_valid():
			_item_icon_press_scale_tween.kill()
		
		# 使用当前的scale作为基准（适应pending状态下可能不同的scale值）
		var current_scale = item_main.scale
		# 如果当前scale接近0或异常，使用原始scale
		if current_scale.length() < 0.1:
			current_scale = _item_icon_original_scale
		
		# 确保使用有效的scale值
		if current_scale.length() < 0.1:
			current_scale = Vector2.ONE
		
		# icon缩小到0.9倍
		var target_scale = current_scale * 0.9
		_item_icon_press_scale_tween = create_tween()
		_item_icon_press_scale_tween.tween_property(item_main, "scale", target_scale, 0.1) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## 处理鼠标松开：重置按下状态，item icon恢复并放大
func handle_mouse_release() -> void:
	_is_mouse_pressed = false
	
	# item icon恢复并放大（如果有显示）
	if item_main and item_main.visible and item_main.texture:
		# 停止之前的缩放动画
		if _item_icon_press_scale_tween and _item_icon_press_scale_tween.is_valid():
			_item_icon_press_scale_tween.kill()
		
		# 使用原始scale作为目标（pending状态下应该恢复到Vector2.ONE）
		var target_scale = _item_icon_original_scale
		
		# icon恢复到原始大小并稍微放大（弹回效果）
		_item_icon_press_scale_tween = create_tween()
		_item_icon_press_scale_tween.tween_property(item_main, "scale", target_scale * 1.05, 0.1) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_item_icon_press_scale_tween.tween_property(item_main, "scale", target_scale, 0.1) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# 如果仍在hover状态，恢复hover效果
	if _is_hovered and not is_locked and not is_drawing:
		create_tween().tween_property(lid_sprite, "position:y", -20, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
