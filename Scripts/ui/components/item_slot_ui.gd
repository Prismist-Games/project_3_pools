class_name ItemSlotUI
extends BaseSlotUI

@onready var icon_display: Sprite2D = find_child("Item_example", true)
@onready var affix_display: Sprite2D = find_child("Item_affix", true)
@onready var led_display: Sprite2D = find_child("Slot_led", true)
@onready var backgrounds: Node2D = find_child("Item Slot_backgrounds", true)

var slot_index: int = -1

func setup(index: int) -> void:
	slot_index = index

func get_icon_global_position() -> Vector2:
	return icon_display.global_position

func get_icon_global_scale() -> Vector2:
	return icon_display.global_scale

func hide_icon() -> void:
	icon_display.visible = false

func show_icon() -> void:
	icon_display.visible = true

func update_display(item: ItemInstance) -> void:
	if not item:
		icon_display.texture = null
		affix_display.visible = false
		led_display.modulate = Color(0.5, 0.5, 0.5, 0.5) # Grayed out
		if backgrounds and backgrounds.has_method("set_rarity"):
			backgrounds.set_rarity(-1) # Assuming -1 or similar for empty
		return
	
	icon_display.texture = item.item_data.icon
	# Affix display logic based on item properties
	affix_display.visible = item.sterile
	# Update LED color based on rarity
	led_display.modulate = Constants.get_rarity_border_color(item.rarity)
	
	if backgrounds and backgrounds.has_method("set_rarity"):
		backgrounds.set_rarity(item.rarity)
