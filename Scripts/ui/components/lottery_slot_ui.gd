class_name LotterySlotUI
extends BaseSlotUI

@onready var pool_name_label: RichTextLabel = find_child("Lottery Pool Name_label", true)
@onready var lid_icon: Sprite2D = find_child("Lottery Slot_lid_icon", true)
@onready var lid_sprite: Sprite2D = find_child("Lottery Slot_lid", true)
@onready var price_label: RichTextLabel = find_child("Price Label", true)
@onready var price_icon: Sprite2D = find_child("Price Icon", true)
@onready var affix_label: RichTextLabel = find_child("Affix Label", true)
@onready var description_label: RichTextLabel = find_child("Description Label", true)
@onready var items_grid: VBoxContainer = find_child("Lottery Required Items Icon Grid", true)

@onready var item_main: Sprite2D = find_child("Item_main", true)
@onready var item_main_shadow: Sprite2D = item_main.get_node("Item_shadow")
@onready var item_queue_1: Sprite2D = find_child("Item_queue_1", true)
@onready var item_queue_1_shadow: Sprite2D = item_queue_1.get_node("Item_shadow")
@onready var item_queue_2: Sprite2D = find_child("Item_queue_2", true)
@onready var item_queue_2_shadow: Sprite2D = item_queue_2.get_node("Item_shadow")

@onready var backgrounds: Node2D = find_child("Lottery Slot_backgrounds", true)

var pool_index: int = -1
var is_drawing: bool = false
var _pending_pool_data: Variant = null # 挂起的新奖池数据，等待关盖后应用
var _initial_transforms: Dictionary = {}

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

func _on_mouse_exited() -> void:
	if is_locked or is_drawing: return
	# 恢复原位 (如果没在播放打开动画)
	if not anim_player.is_playing() or anim_player.current_animation != "lid_open":
		create_tween().tween_property(lid_sprite, "position:y", 0, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

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
	
	# 如果正在抽奖动画中，不要立即更新视觉，先存起来
	if is_drawing:
		_pending_pool_data = pool
		return
	
	_apply_pool_display(pool)

func _apply_pool_display(pool: Variant) -> void:
	# 更新 Lid 图标和颜色
	if lid_icon:
		lid_icon.texture = Constants.type_to_icon(pool.item_type)
	
	if lid_sprite:
		var theme_color = Color("#199C80") # 普通门颜色
		if pool.item_type == Constants.ItemType.MAINLINE:
			theme_color = Color("#FF6E54") # 核心门颜色
		
		lid_sprite.self_modulate = theme_color
		if lid_icon:
			lid_icon.self_modulate = theme_color
	
	# 从类型获取显示名称
	pool_name_label.text = Constants.type_to_display_name(pool.item_type) + "池"
	pool_name_label.visible = true # 确保可见
	
	var cost_gold = pool.gold_cost
	var cost_tickets = pool.ticket_cost
	
	if cost_tickets > 0:
		price_label.text = str(cost_tickets)
		price_icon.texture = preload("res://assets/sprites/icons/coupon.png")
	else:
		price_label.text = str(cost_gold)
		price_icon.texture = preload("res://assets/sprites/icons/money.png")
	
	# 确保价格标签可见
	price_label.visible = true
	price_icon.visible = true
	
	if pool.affix_data:
		affix_label.text = pool.affix_data.name
		description_label.text = pool.affix_data.description
		affix_label.visible = true
		description_label.visible = true
	else:
		affix_label.text = ""
		description_label.text = ""
		affix_label.visible = false
		description_label.visible = false
	
	# Note: controller calls update_order_hints next
	
	# 重置背景颜色和物品显示 (For refresh)
	if backgrounds:
		backgrounds.color = Constants.COLOR_BG_SLOT_EMPTY
	item_main.visible = false
	item_main_shadow.visible = false
	item_queue_1.visible = false
	item_queue_1_shadow.visible = false
	item_queue_2.visible = false
	item_queue_2_shadow.visible = false

func update_order_hints(display_items: Array[ItemData], satisfied_map: Dictionary) -> void:
	# 填充图标格
	for i in range(5):
		var icon_node = items_grid.get_node_or_null("Item Icon_" + str(i))
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

## 播放关盖序列（带逻辑重置）
func play_close_sequence() -> void:
	await close_lid()
	
	is_drawing = false
	
	# 关盖后，确保背景色和物品显示重置
	# 注意：Controller 现在应确保 pending items 已经清空，或者我们这里只视觉重置
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
	var duration = 0.3
	var tw = create_tween().set_parallel(true)
	
	if item_queue_1.visible:
		var q1_pos = item_queue_1.position
		var main_pos = item_main.position
		var q1_scale = item_queue_1.scale
		var main_scale = item_main.scale
		
		# 让 queue1 移动到 main 的位置和缩放
		tw.tween_property(item_queue_1, "position", main_pos, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(item_queue_1, "scale", main_scale, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		
		if item_queue_2.visible:
			tw.tween_property(item_queue_2, "position", q1_pos, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(item_queue_2, "scale", q1_scale, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		
		await tw.finished
		
		# 复位位置
		item_queue_1.position = q1_pos
		item_queue_1.scale = q1_scale
		item_queue_2.position = item_queue_1.position
		_reset_item_transforms()
		
		# 关键修复：动画结束后，立即同步当前 pending_items 的显示
		# 这确保 texture 与逻辑状态一致
		# BUT we need to know what to update from...
		# Rely on Controller to call update_pending_display??
		# Or rely on global InventorySystem.pending_items? 
		# If we want to be pure, we should emit signal "anim_finished" and let controller update.
		# For now, practical approach:
		if not InventorySystem.pending_items.is_empty():
			update_queue_display(InventorySystem.pending_items)

func open_lid() -> void:
	if anim_player.has_animation("lid_open"):
		anim_player.play("lid_open")

func close_lid() -> void:
	if anim_player.has_animation("lid_close"):
		anim_player.play("lid_close")
		if anim_player.is_playing():
			await anim_player.animation_finished

func _reset_item_transforms() -> void:
	if _initial_transforms.is_empty(): return
	
	# 只恢复 Main 的 transform，Queue 的由 update_queue_display 控制
	item_main.position = _initial_transforms[item_main]["pos"]
	item_main.scale = _initial_transforms[item_main]["scale"]
