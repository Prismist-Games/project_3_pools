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

func setup(index: int) -> void:
	pool_index = index
	var input_area = find_child("Input Area", true)
	if input_area:
		input_area.mouse_entered.connect(_on_mouse_entered)
		input_area.mouse_exited.connect(_on_mouse_exited)
		
		# 可选优化：在非 NORMAL 模式下禁用鼠标指针样式
		GameManager.ui_mode_changed.connect(func(_mode):
			if GameManager.current_ui_mode == Constants.UIMode.NORMAL:
				input_area.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			else:
				input_area.mouse_default_cursor_shape = Control.CURSOR_ARROW
		)
	
	# 奖池初始状态必须是瞬间关上的 (瞬间完成，不播放动画过程)
	if anim_player.has_animation("lid_close"):
		anim_player.play("lid_close")
		anim_player.advance(0)
		anim_player.seek(anim_player.get_animation("lid_close").length, true)

func _on_mouse_entered() -> void:
	if is_locked or not InventorySystem.pending_items.is_empty() or is_drawing: return
	
	# 非 NORMAL 模式下禁止 Hover 效果
	if GameManager.current_ui_mode != Constants.UIMode.NORMAL:
		return
		
	# 盖子微开
	create_tween().tween_property(lid_sprite, "position:y", -20, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _on_mouse_exited() -> void:
	# 即使处于非 NORMAL 模式，也可能需要恢复位置（防止模式切换时状态残留），所以这里只做基础检查
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
	
	var cost_gold = pool.gold_cost
	var cost_tickets = pool.ticket_cost
	
	if cost_tickets > 0:
		price_label.text = str(cost_tickets)
		price_icon.texture = preload("res://assets/sprites/icons/coupon.png")
	else:
		price_label.text = str(cost_gold)
		price_icon.texture = preload("res://assets/sprites/icons/money.png")
	
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
	
	# 更新右侧屏幕显示：当前订单需求中属于该池子类型的物品
	_update_required_items_from_orders(pool.item_type)
	
	# 重置背景颜色和物品显示 (如果当前没有待处理物品)
	if InventorySystem.pending_items.is_empty():
		if backgrounds:
			backgrounds.color = Constants.COLOR_BG_SLOT_EMPTY
		item_main.visible = false
		item_main_shadow.visible = false
		item_queue_1.visible = false
		item_queue_1_shadow.visible = false
		item_queue_2.visible = false
		item_queue_2_shadow.visible = false

func _update_required_items_from_orders(pool_type: Constants.ItemType) -> void:
	# 1. 收集所有订单需求的物品 ID
	var required_ids: Dictionary = {} # 使用字典去重
	for order in OrderSystem.current_orders:
		for req in order.requirements:
			var id = req.get("item_id", &"")
			if id != &"":
				required_ids[id] = true
	
	# 2. 获取该池子类型下的所有物品，并过滤出被订单要求的
	var pool_items = GameManager.get_items_for_type(pool_type)
	var display_items: Array[ItemData] = []
	for item_data in pool_items:
		if item_data.id in required_ids:
			display_items.append(item_data)
	
	# 3. 填充图标格
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
				var is_satisfied = InventorySystem.has_item_data(item_data)
				if is_satisfied:
					status_icon.texture = preload("res://assets/sprites/icons/tick_green.png")
					status_icon.visible = true
				else:
					status_icon.visible = false
		else:
			icon_node.visible = false

func play_reveal_sequence(item: ItemInstance) -> void:
	is_drawing = true
	# 1. 盖子全开
	if anim_player.has_animation("lid_open"):
		anim_player.play("lid_open")
	
	# 2. 背景颜色洗牌感
	var shuffle_timer = 0.0
	var duration = 0.5
	var interval = 0.05
	
	# 临时显示图标
	item_main.texture = item.item_data.icon
	item_main.visible = true
	item_main_shadow.visible = true
	item_main.scale = Vector2.ZERO
	create_tween().tween_property(item_main, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	while shuffle_timer < duration:
		if backgrounds:
			backgrounds.color = Constants.get_rarity_border_color(randi() % 5)
		await get_tree().create_timer(interval).timeout
		shuffle_timer += interval
	
	# 3. 定格最终品质
	if backgrounds:
		backgrounds.color = Constants.get_rarity_border_color(item.rarity)
	
	await get_tree().create_timer(0.3).timeout # 最终揭示后的停留

func play_close_sequence() -> void:
	if anim_player.has_animation("lid_close"):
		anim_player.play("lid_close")
		await anim_player.animation_finished
	
	is_drawing = false
	
	# 如果有挂起的数据，现在应用它 (门已经关上了，玩家看不见内容替换)
	if _pending_pool_data:
		_apply_pool_display(_pending_pool_data)
		_pending_pool_data = null
	
	# 关盖后，确保背景色重置 (如果已经没有 pending 了)
	if InventorySystem.pending_items.is_empty():
		if backgrounds:
			backgrounds.color = Constants.COLOR_BG_SLOT_EMPTY
		item_main.visible = false
		item_main_shadow.visible = false

func play_draw_anim() -> void:
	# 这个函数现在被 play_reveal_sequence 替代逻辑
	pass

func update_pending_display(pending_list: Array) -> void:
	# 只要更新了待处理显示，就说明抽奖揭示阶段已结束
	is_drawing = false
	
	# 重置显示
	item_main.texture = null
	item_main.visible = false
	item_main_shadow.visible = false
	
	item_queue_1.texture = null
	item_queue_1.visible = false
	item_queue_1_shadow.visible = false
	
	item_queue_2.texture = null
	item_queue_2.visible = false
	item_queue_2_shadow.visible = false
	
	if pending_list.is_empty():
		if backgrounds:
			backgrounds.color = Constants.COLOR_BG_SLOT_EMPTY
		return
	
	# 设置背景颜色 (根据第一个物品的稀有度，与 ItemSlot 保持一致)
	if backgrounds:
		backgrounds.color = Constants.get_rarity_border_color(pending_list[0].rarity)
	
	# 设置主要物品
	if pending_list.size() > 0:
		item_main.texture = pending_list[0].item_data.icon
		item_main.visible = true
		item_main_shadow.visible = true
		
	# 设置队列物品 1
	if pending_list.size() > 1:
		item_queue_1.texture = pending_list[1].item_data.icon
		item_queue_1.visible = true
		item_queue_1_shadow.visible = true
		
	# 设置队列物品 2
	if pending_list.size() > 2:
		item_queue_2.texture = pending_list[2].item_data.icon
		item_queue_2.visible = true
		item_queue_2_shadow.visible = true
