extends PanelContainer

signal submit_requested(index: int)
signal refresh_requested(index: int)

@onready var requirements_label: Label = %RequirementsLabel
@onready var reward_label: Label = %RewardLabel
@onready var refresh_button: Button = %RefreshButton
@onready var submit_button: Button = %SubmitButton

var _index: int = -1


func setup(order: OrderData, index: int) -> void:
	_index = index
	
	var req_text = ""
	for req in order.requirements:
		var item_id = req.item_id
		var min_rarity = req.min_rarity
		var count = req.count
		
		# 尝试获取友好名称（这里简化，直接用 ID）
		var rarity_name = Constants.rarity_display_name(min_rarity)
		req_text += "%s (%s) x%d\n" % [item_id, rarity_name, count]
	
	requirements_label.text = req_text
	
	var reward_text = ""
	if order.reward_gold > 0:
		reward_text += "%d 金币 " % order.reward_gold
	if order.reward_tickets > 0:
		reward_text += "%d 奖券" % order.reward_tickets
	reward_label.text = "奖励: " + reward_text
	
	refresh_button.text = "刷新 (%d)" % order.refresh_count
	
	var can_refresh_in_stage = true
	var stage_data = GameManager.current_stage_data
	if stage_data != null and not stage_data.has_order_refresh:
		can_refresh_in_stage = false
		
	refresh_button.visible = can_refresh_in_stage and not order.is_mainline
	refresh_button.disabled = order.refresh_count <= 0
	
	# 检查是否可以提交
	submit_button.disabled = not order.can_fulfill(GameManager.inventory)
	
	if order.is_mainline:
		# 主线订单背景颜色
		self.modulate = Color.ORANGE
	else:
		self.modulate = Color.WHITE


func _on_submit_button_pressed() -> void:
	submit_requested.emit(_index)


func _on_refresh_button_pressed() -> void:
	refresh_requested.emit(_index)




