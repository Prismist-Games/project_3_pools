extends PanelContainer

signal submit_requested(index: int)
signal refresh_requested(index: int)

@onready var requirements_container: HBoxContainer = %RequirementsContainer
@onready var requirements_label: Label = %RequirementsLabel
@onready var reward_label: Label = %RewardLabel
@onready var refresh_button: Button = %RefreshButton
@onready var submit_button: Button = %SubmitButton

const SLOT_SCENE = preload("res://scenes/ui/inventory_slot.tscn")

var _index: int = -1


func _ready() -> void:
	EventBus.game_event.connect(_on_game_event)


func _on_game_event(event_id: StringName, payload: Variant) -> void:
	if event_id == &"order_card_shake_requested":
		var data = payload
		if payload is ContextProxy:
			data = payload.data
		
		var target_idx = data.get("index")
		if target_idx == _index:
			_shake_card()


func _shake_card() -> void:
	var tween = create_tween()
	var original_pos = position
	for i in range(4):
		tween.tween_property(self, "position", original_pos + Vector2(10, 0), 0.05)
		tween.tween_property(self, "position", original_pos + Vector2(-10, 0), 0.05)
	tween.tween_property(self, "position", original_pos, 0.05)


func setup(order: OrderData, index: int) -> void:
	_index = index
	var dark_text = Constants.COLOR_TEXT_MAIN
	
	# 清理旧需求项
	for child in requirements_container.get_children():
		child.queue_free()
	
	var selected_items: Array[ItemInstance] = []
	if GameManager.current_ui_mode == Constants.UIMode.SUBMIT:
		for idx in InventorySystem.multi_selected_indices:
			if idx >= 0 and idx < InventorySystem.inventory.size() and InventorySystem.inventory[idx]:
				selected_items.append(InventorySystem.inventory[idx])
	
	var preview = order.calculate_preview_rewards(selected_items)
	
	# 实例化新需求项
	for i in range(order.requirements.size()):
		var req = order.requirements[i]
		var item_id = req.item_id
		var min_rarity = req.min_rarity
		
		# 获取 ItemData
		var item_data = GameManager.get_item_data(item_id)
		
		var slot = SLOT_SCENE.instantiate()
		requirements_container.add_child(slot)
		
		var is_fulfilled = i in preview.fulfilled_requirements
		
		# 调整格子的显示以适应订单卡片
		slot.custom_minimum_size = Vector2(70, 90)
		
		if slot.has_method("setup_preview"):
			slot.setup_preview(item_data, min_rarity, is_fulfilled)
	
	# 奖励预览
	var reward_text = tr("ORDER_REWARD")
	if preview.is_satisfied:
		reward_text += tr("ORDER_REWARD_PREVIEW") % [order.reward_gold, preview.gold]
		reward_label.add_theme_color_override("font_color", Color("#854d0e")) # 暖褐色
	else:
		reward_text += tr("ORDER_REWARD_GOLD") % order.reward_gold
		reward_label.add_theme_color_override("font_color", dark_text)
	
	reward_label.text = ("✅ " if preview.is_satisfied else "") + reward_text
	
	refresh_button.text = tr("ORDER_REFRESH") % order.refresh_count
	
	var stage_allows_refresh = UnlockManager.is_unlocked(UnlockManager.Feature.ORDER_REFRESH)
	
	# 主线订单或该阶段未解锁刷新时完全隐藏
	# 主线订单或该阶段未解锁刷新时完全隐藏
	refresh_button.visible = stage_allows_refresh and not order.is_mainline
	# 次数用尽时变灰禁用，但保持可见
	refresh_button.disabled = order.refresh_count <= 0
	
	# 背景样式使用了 Theme Variation
	if preview.is_satisfied:
		self.theme_type_variation = "Order_Satisfied"
	elif GameManager.current_ui_mode == Constants.UIMode.SUBMIT and GameManager.order_selection_index == _index:
		self.theme_type_variation = "Order_Selected"
	elif order.is_mainline:
		self.theme_type_variation = "Order_Mainline"
	else:
		self.theme_type_variation = "Order_Normal"
	
	submit_button.visible = false # 全局按钮已移至底部


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			# 核心判定：松开时是否仍在该区域内
			if Rect2(Vector2.ZERO, size).has_point(event.position):
				submit_requested.emit(_index)


func _on_refresh_button_pressed() -> void:
	refresh_requested.emit(_index)
