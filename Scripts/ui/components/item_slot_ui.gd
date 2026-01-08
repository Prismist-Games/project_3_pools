class_name ItemSlotUI
extends BaseSlotUI

@onready var icon_display: Sprite2D = find_child("Item_example", true)
@onready var item_shadow: Sprite2D = find_child("Item_shadow", true)
@onready var affix_display: Sprite2D = find_child("Item_affix", true)
@onready var led_display: Sprite2D = find_child("Slot_led", true)
@onready var status_icon: Sprite2D = find_child("Item_status", true)
@onready var backgrounds: Node2D = find_child("Item Slot_backgrounds", true)

var slot_index: int = -1
var is_vfx_target: bool = false # 标记是否为飞行目标，防止动画中背景色提前刷新

func setup(index: int) -> void:
	slot_index = index
	# 背包格初始状态是开启的
	if anim_player.has_animation("lid_open"):
		anim_player.play("lid_open")

func get_icon_global_position() -> Vector2:
	return icon_display.global_position

func get_icon_global_scale() -> Vector2:
	return icon_display.global_scale

func hide_icon() -> void:
	icon_display.visible = false
	if item_shadow: item_shadow.visible = false

func show_icon() -> void:
	icon_display.visible = true
	if item_shadow: item_shadow.visible = true

func update_display(item: ItemInstance) -> void:
	if is_vfx_target: return # 飞行中锁定视觉，落地后再更新
	
	if not item:
		icon_display.texture = null
		if item_shadow: item_shadow.visible = false
		affix_display.visible = false
		status_icon.visible = false
		led_display.modulate = Color(0.5, 0.5, 0.5, 0.5) # Grayed out
		if backgrounds:
			backgrounds.color = Constants.COLOR_BG_SLOT_EMPTY
		return
	
	icon_display.texture = item.item_data.icon
	if item_shadow: item_shadow.visible = true
	
	# Affix display logic based on item properties
	affix_display.visible = item.sterile
	# Update LED color based on rarity
	# led_display.modulate = Constants.get_rarity_border_color(item.rarity)
	
	if backgrounds:
		backgrounds.color = Constants.get_rarity_border_color(item.rarity)
	
	# 更新状态角标逻辑
	_update_status_badge(item)

func _update_status_badge(item: ItemInstance) -> void:
	if not status_icon: return
	
	var badge_state = 0 # 0: 隐藏, 1: 白色勾 (需求但品质不够), 2: 绿色勾 (满足需求)
	
	for order in OrderSystem.current_orders:
		for req in order.requirements:
			if req.get("item_id", &"") == item.item_data.id:
				if item.rarity >= req.get("min_rarity", 0):
					badge_state = 2 # 只要有一个订单能满足，就是最高优先级绿色
					break
				else:
					if badge_state < 1:
						badge_state = 1
		if badge_state == 2: break
	
	match badge_state:
		0:
			status_icon.visible = false
		1:
			status_icon.visible = true
			status_icon.texture = preload("res://assets/sprites/icons/tick_white.png")
		2:
			status_icon.visible = true
			status_icon.texture = preload("res://assets/sprites/icons/tick_green.png")
