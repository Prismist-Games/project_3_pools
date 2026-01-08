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

func play_reveal_sequence(items: Array) -> void:
	if items.is_empty(): return
	var item = items[0]

	# 如果已经在展示中（is_drawing = true），说明之前已经 reveal 过了，直接更新显示即可
	if is_drawing:
		update_queue_display(items)
		return
	
	is_drawing = true

	# 1. 盖子全开
	if anim_player.has_animation("lid_open"):
		anim_player.play("lid_open")
	
	# 2. 背景颜色洗牌感
	var shuffle_timer = 0.0
	var duration = 0.5
	var interval = 0.05
	
	# 临时显示图标
	# 临时显示图标 (支持多物品)
	item_main.scale = Vector2.ZERO
	item_queue_1.scale = Vector2.ZERO
	item_queue_2.scale = Vector2.ZERO
	
	update_queue_display(items)
	
	var tw = create_tween().set_parallel(true)
	tw.tween_property(item_main, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if items.size() > 1:
		tw.tween_property(item_queue_1, "scale", Vector2(0.8, 0.8), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if items.size() > 2:
		tw.tween_property(item_queue_2, "scale", Vector2(0.6, 0.6), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
	# 假设 item_main 的默认位置是 (0, -26). 
	# 我们基于 item_main 的位置来计算
	var base_pos = item_main.position # 当 _ready 时记录的或者当前的?
	# 如果正在做动画，item_main.position 可能会变。
	# 我们应该使用 _initial_transforms[item_main]["pos"]
	if _initial_transforms.is_empty():
		# Fallback if _ready hasn't run yet (unlikely)
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
		# 使用可配置的偏移量和缩放
		item_queue_1.position = base_pos + queue_1_offset
		item_queue_1.scale = Vector2(queue_1_scale, queue_1_scale)
		item_queue_1.z_index = 0
		printerr("[LotterySlot] Queue1 显示: ", items[1].item_data.id, " at ", item_queue_1.position, " scale: ", item_queue_1.scale)
	else:
		item_queue_1.visible = false
		item_queue_1_shadow.visible = false
	
	# queue_2 显示 items[2]
	if items.size() > 2:
		item_queue_2.texture = items[2].item_data.icon
		item_queue_2.visible = true
		item_queue_2_shadow.visible = true
		# 使用可配置的偏移量和缩放
		item_queue_2.position = base_pos + queue_2_offset
		item_queue_2.scale = Vector2(queue_2_scale, queue_2_scale)
		item_queue_2.z_index = 0
		printerr("[LotterySlot] Queue2 显示: ", items[2].item_data.id, " at ", item_queue_2.position, " scale: ", item_queue_2.scale)
	else:
		item_queue_2.visible = false
		item_queue_2_shadow.visible = false
	
	printerr("[LotterySlot] update_queue_display 完成，items数量: ", items.size())

# 播放队列推进动画：queue1 -> main, queue2 -> queue1
func play_queue_advance_anim() -> void:
	# 前进动画：
	# 1. Main 已经飞走（在 Game2DUI 处理），这里只需要把 queue1 移到 Main，queue2 移到 queue1
	# 实际上，fly 动画还在播。Game2DUI 会在 fly 之后才 update_display。
	# 我们希望“飞出的同时”，后面的往前顶。
	var duration = 0.3
	var tw = create_tween().set_parallel(true)
	
	if item_queue_1.visible:
		# Queue1 -> Main
		# 记录原始位置，为了动画结束后恢复（因为这是 slot 的固定位置）
		var q1_pos = item_queue_1.position
		var main_pos = item_main.position
		var q1_scale = item_queue_1.scale
		var main_scale = item_main.scale
		
		# 我们不改变 slot 的布局结构，而是让图标视觉移动。
		# 但最好的做法可能是：移动之后，交换 texture，瞬间复位。
		# 比如：tween item_queue_1.position to item_main.position
		# 结束后：item_main.texture = item_queue_1.texture, item_queue_1 复位且隐藏(或显示下一个)。
		# 由于我们不知道下一个是什么（logic layer 状态），我们只能做纯视觉的“推”。
		# 然而，Game2DUI 在 fly 完后会调用 update_pending_display，那时会瞬间重置。
		# 所以这里的动画只需要负责“看起来移动了”。
		
		# 让 queue1 移动到 main 的位置和缩放
		tw.tween_property(item_queue_1, "position", main_pos, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(item_queue_1, "scale", main_scale, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		
		if item_queue_2.visible:
			tw.tween_property(item_queue_2, "position", q1_pos, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(item_queue_2, "scale", q1_scale, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		
		await tw.finished
		
		# 动画结束后，手动复位位置（内容更新由外部 update_pending_display 负责）
		item_queue_1.position = q1_pos
		item_queue_1.scale = q1_scale
		item_queue_2.position = item_queue_1.position # q1_pos is queue1 slot pos
		# wait. item_queue_2 pos should reset to queue 2 pos? No, queue 2 moved to queue 1.
		# The layout positions should be constant.
		# recover original transforms
		# 这是一个 tricky part。最简单的方式是：直接复位 transform。内容更新会在之后瞬间发生。
		_reset_item_transforms()
		
		# 关键修复：动画结束后，立即同步当前 pending_items 的显示
		# 这确保 texture 与逻辑状态一致
		if not InventorySystem.pending_items.is_empty():
			update_queue_display(InventorySystem.pending_items)

func _reset_item_transforms() -> void:
	if _initial_transforms.is_empty(): return
	
	# 只恢复 Main 的 transform，Queue 的由 update_queue_display 控制
	item_main.position = _initial_transforms[item_main]["pos"]
	item_main.scale = _initial_transforms[item_main]["scale"]
	
	# Queue 的 position 由 update_queue_display 设置，这里只恢复 scale（为下次动画准备）
	# 实际上，在 update_queue_display 中我们已经设置了正确的 scale，
	# 所以这里不需要特别处理
