class_name LotterySlotUI
extends BaseSlotUI

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
@onready var item_main_shadow: Sprite2D = item_main.get_node("Item_shadow")
@onready var item_queue_1: Sprite2D = find_child("Item_queue_1", true)
@onready var item_queue_1_shadow: Sprite2D = item_queue_1.get_node("Item_shadow")
@onready var item_queue_2: Sprite2D = find_child("Item_queue_2", true)
@onready var item_queue_2_shadow: Sprite2D = item_queue_2.get_node("Item_shadow")

@onready var backgrounds: Node2D = find_child("Lottery Slot_backgrounds", true)

## =====================================================================
## 状态变量
## =====================================================================
var pool_index: int = -1
var is_drawing: bool = false
var is_vfx_source: bool = false # 标记是否为飞行起点，防止动画开始前被 update_pending_display 刷新掉
var _pending_pool_data: Variant = null # 挂起的新奖池数据，等待关盖后应用
var _pending_hints: Dictionary = {} # 暂存的新 hints 数据
var _initial_transforms: Dictionary = {}

## 标记：是否处于以旧换新等待物品投入状态
var is_waiting_for_trade_in: bool = false

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
	
	# 记录 Push-Away 节点的初始位置
	_store_push_initial_positions()

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
	if is_locked or is_drawing: return
	
	# 盖子微开
	create_tween().tween_property(lid_sprite, "position:y", -20, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	EventBus.game_event.emit(&"lottery_slot_hovered", self)

func _on_mouse_exited() -> void:
	if is_locked or is_drawing: return
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
			
			# 更新满足状态图标 (仅显示勾，不显示叉)
			var status_icon = icon_node.get_node_or_null("Item Icon_status")
			if status_icon:
				var is_satisfied = satisfied_map.get(item_data.id, false)
				if is_satisfied:
					status_icon.texture = preload("res://assets/sprites/icons/tick_green.png")
					status_icon.visible = true
				else:
					status_icon.visible = false
		else:
			icon_node.visible = false

func play_reveal_sequence(items: Array) -> void:
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
	
	# 2. 背景颜色洗牌感 (即便 items 为空也播放视觉洗牌)
	var shuffle_timer = 0.0
	var duration = 0.5
	var interval = 0.05
	
	# 临时隐藏/重置图标
	item_main.scale = Vector2.ZERO
	item_queue_1.scale = Vector2.ZERO
	item_queue_2.scale = Vector2.ZERO
	
	update_queue_display(items)
	
	if not items.is_empty():
		var tw = create_tween().set_parallel(true)
		tw.tween_property(item_main, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if items.size() > 1:
			tw.tween_property(item_queue_1, "scale", Vector2(queue_1_scale, queue_1_scale), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if items.size() > 2:
			tw.tween_property(item_queue_2, "scale", Vector2(queue_2_scale, queue_2_scale), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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
	if is_vfx_source: return # 正在从这里飞出物品，由 VFXManager 控制显示，防止逻辑更新导致提前消失
	if pending_list.is_empty():
		is_drawing = false # 只有队列空了才重置
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
		return
	
	# 设置背景颜色 (根据第一个物品的稀有度，与 ItemSlot 保持一致)
	if backgrounds:
		backgrounds.color = Constants.get_rarity_border_color(pending_list[0].rarity)
	
	# 设置主要物品（update_queue_display 内部会处理显示/隐藏）
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
		item_main.texture = items[0].item_data.icon
		item_main.visible = true
		item_main_shadow.visible = true
		item_main.z_index = 0
	else:
		item_main.visible = false
		item_main_shadow.visible = false
		
	# queue_1 显示 items[1]
	if items.size() > 1:
		item_queue_1.texture = items[1].item_data.icon
		item_queue_1.visible = true
		item_queue_1_shadow.visible = true
		item_queue_1.position = base_pos + queue_1_offset
		item_queue_1.scale = Vector2(queue_1_scale, queue_1_scale)
		item_queue_1.z_index = 0
	else:
		item_queue_1.visible = false
		item_queue_1_shadow.visible = false
	
	# queue_2 显示 items[2]
	if items.size() > 2:
		item_queue_2.texture = items[2].item_data.icon
		item_queue_2.visible = true
		item_queue_2_shadow.visible = true
		item_queue_2.position = base_pos + queue_2_offset
		item_queue_2.scale = Vector2(queue_2_scale, queue_2_scale)
		item_queue_2.z_index = 0
	else:
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
		var theme_color := Color("#199C80") # 普通门颜色
		if item_type == Constants.ItemType.MAINLINE:
			theme_color = Color("#FF6E54") # 核心门颜色
		
		if target_lid_sprite:
			target_lid_sprite.self_modulate = theme_color
		if target_lid_icon:
			target_lid_icon.texture = Constants.type_to_icon(item_type)
			target_lid_icon.self_modulate = theme_color
	
	# 更新奖池名称
	if target_pool_name and has_item_type:
		var item_type = pool.item_type if "item_type" in pool else pool.get("item_type")
		target_pool_name.text = Constants.type_to_display_name(item_type) + "池"
		target_pool_name.visible = true
	
	# 更新价格 (始终保持可见)
	if target_price:
		var cost_text = ""
		if pool is Dictionary and pool.has("price_text"):
			cost_text = pool.price_text
		else:
			var cost_gold: int = pool.get("gold_cost") if "gold_cost" in pool else 0
			var cost_tickets: int = pool.get("ticket_cost") if "ticket_cost" in pool else 0
			cost_text = str(cost_tickets) if cost_tickets > 0 else str(cost_gold)
		
		target_price.text = cost_text
		target_price.visible = true # 强制保持可见，即使文本为空
	
	# Price Icon 逻辑 (始终保持可见)
	if not target_pseudo and price_icon:
		var has_tickets = pool.get("ticket_cost") > 0 if "ticket_cost" in pool else false
		if has_tickets:
			price_icon.texture = preload("res://assets/sprites/icons/coupon.png")
		else:
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
