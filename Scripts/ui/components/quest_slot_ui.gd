class_name QuestSlotUI
extends BaseSlotUI

@onready var reward_label: RichTextLabel = find_child("Quest Reward Label", true)
@onready var reward_icon: TextureRect = find_child("Quest Reward Icon", true)
@onready var items_grid: HBoxContainer = find_child("Quest Slot Items Grid", true)
@onready var backgrounds: Node2D = find_child("Quest Slot_background", true)
@onready var refresh_label: RichTextLabel = find_child("Refresh Count Label", true)

var order_index: int = -1

func setup(index: int) -> void:
	order_index = index

func play_refresh_anim() -> Signal:
	if anim_player.has_animation("lid_close"):
		anim_player.play("lid_close")
		await anim_player.animation_finished
		# Logic to change content happens here in parent
		if anim_player.has_animation("lid_open"):
			anim_player.play("lid_open")
			return anim_player.animation_finished
	return get_tree().process_frame

func update_order_display(order_data: OrderData) -> void:
	if not order_data:
		visible = false
		return
	
	visible = true
	# Update reward display
	var reward_text = ""
	if order_data.reward_gold > 0:
		reward_text += str(order_data.reward_gold)
	if order_data.reward_tickets > 0:
		reward_text += " [s]%d[/s]" % order_data.reward_tickets
	
	if reward_label:
		reward_label.text = reward_text
	
	if backgrounds:
		if order_data.is_mainline:
			backgrounds.self_modulate = Color("#FBB03B") # Gold/Orange for mainline
		elif reward_icon:
			if order_data.reward_tickets > 0:
				backgrounds.self_modulate = Color("#5290EC") # Blue
			else:
				backgrounds.self_modulate = Color("#69d956") # Green
	else:
		# 尝试查找主线背景
		var mainline_bg = find_child("Main Quest Slot_background", true)
		if mainline_bg:
			mainline_bg.self_modulate = Color("#FBB03B")
	
	if refresh_label:
		refresh_label.text = str(order_data.refresh_count)
	
	_update_requirements(order_data.requirements)

func _update_requirements(reqs: Array[Dictionary]) -> void:
	var is_submit_mode = GameManager.current_ui_mode == Constants.UIMode.SUBMIT
	var selected_indices = InventorySystem.multi_selected_indices
	
	# 适配不同名字的 Grid (Quest Slot Items Grid 或 Main Quest Slot Items Grid)
	var grid = items_grid
	var item_root_prefix = "Quest Slot Item_root_"
	if not grid:
		grid = find_child("Main Quest Slot Items Grid", true)
		item_root_prefix = "Main Quest Slot Item_root_"
	
	if not grid: return

	for i in range(4):
		var req_node = grid.get_node_or_null(item_root_prefix + str(i))
		if not req_node: continue
		
		if i < reqs.size():
			req_node.visible = true
			var req = reqs[i]
			var item_id = req.get("item_id", &"")
			var item_data = GameManager.get_item_data(item_id)
			
			var icon = req_node.find_child("Item_icon", true)
			if icon and item_data:
				icon.texture = item_data.icon
			
			# 更新状态图标（多选时的高亮/勾选）
			var status_sprite = req_node.find_child("Item_status", true)
			if status_sprite:
				var is_satisfied = false
				if is_submit_mode:
					for idx in selected_indices:
						var item = InventorySystem.inventory[idx]
						if item and item.item_data.id == item_id:
							is_satisfied = true
							break
				
				status_sprite.visible = is_submit_mode
				status_sprite.texture = preload("res://assets/sprites/icons/tick_green.png") if is_satisfied else preload("res://assets/sprites/icons/tick_empty.png")

			var beam = req_node.find_child("Item_rarity_beam", true)
			if beam:
				beam.self_modulate = Constants.get_rarity_border_color(req.get("min_rarity", 0))
		else:
			req_node.visible = false

func update_submission_status(status_array: Array) -> void:
	for i in range(4):
		var req_node = items_grid.get_node_or_null("Quest Slot Item_root_" + str(i))
		if not req_node: continue
		
		var status_sprite = req_node.find_child("Item_status", true)
		if not status_sprite: continue
		
		if i < status_array.size():
			status_sprite.visible = true
			# status_sprite.texture = ... (tick if status_array[i] else cross)
		else:
			status_sprite.visible = false
