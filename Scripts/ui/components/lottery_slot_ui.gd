class_name LotterySlotUI
extends BaseSlotUI

@onready var pool_name_label: RichTextLabel = find_child("Lottery Pool Name_label", true)
@onready var price_label: RichTextLabel = find_child("Price Label", true)
@onready var price_icon: Sprite2D = find_child("Price Icon", true)
@onready var affix_label: RichTextLabel = find_child("Affix Label", true)
@onready var description_label: RichTextLabel = find_child("Description Label", true)
@onready var items_grid: VBoxContainer = find_child("Lottery Required Items Icon Grid", true)

@onready var item_main: Sprite2D = find_child("Item_main", true)
@onready var item_queue_1: Sprite2D = find_child("Item_queue_1", true)
@onready var item_queue_2: Sprite2D = find_child("Item_queue_2", true)

var pool_index: int = -1

func setup(index: int) -> void:
	pool_index = index

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
	else:
		affix_label.text = "标准"
		description_label.text = "标准奖池，产出指定类型的随机物品。"
	
	# 更新该类型的需求物品列表
	var items = GameManager.get_items_for_type(pool.item_type)
	_update_required_items(items)

func _update_required_items(items: Array) -> void:
	for i in range(5):
		var icon_node = items_grid.get_node_or_null("Item Icon_" + str(i))
		if not icon_node: continue
		
		if i < items.size():
			icon_node.visible = true
			var item_data = items[i]
			icon_node.texture = item_data.icon
			
			# 更新满足状态图标
			var status_icon = icon_node.get_node_or_null("Item Icon_status")
			if status_icon:
				var is_satisfied = InventorySystem.has_item_data(item_data)
				status_icon.texture = preload("res://assets/sprites/icons/tick_green.png") if is_satisfied else preload("res://assets/sprites/icons/cross.png")
				status_icon.visible = true
		else:
			icon_node.visible = false

func play_draw_anim() -> Signal:
	if anim_player.has_animation("draw"):
		anim_player.play("draw")
		return anim_player.animation_finished
	# Fallback: simple shake
	play_shake()
	return get_tree().create_timer(0.5).timeout

func update_pending_display(pending_list: Array) -> void:
	item_main.texture = null
	item_queue_1.texture = null
	item_queue_2.texture = null
	
	if pending_list.size() > 0:
		item_main.texture = pending_list[0].item_data.icon
	if pending_list.size() > 1:
		item_queue_1.texture = pending_list[1].item_data.icon
	if pending_list.size() > 2:
		item_queue_2.texture = pending_list[2].item_data.icon
