extends PanelContainer

signal draw_requested(index: int)

@onready var title_label: Label = %TitleLabel
@onready var cost_label: Label = %CostLabel
@onready var affix_label: Label = %AffixLabel
@onready var draw_button: Button = %DrawButton

var _index: int = -1


func setup(config: PoolConfig, index: int) -> void:
	_index = index
	title_label.text = Constants.type_to_display_name(config.item_type)
	
	if config.item_type == Constants.ItemType.MAINLINE:
		title_label.text = "主线奖池"
		self.modulate = Color.GOLD
	else:
		self.modulate = Color.WHITE
	
	if config.ticket_cost > 0:
		cost_label.text = "消耗: %d 奖券" % config.ticket_cost
	else:
		cost_label.text = "消耗: %d 金币" % config.gold_cost
		
	var affix_id = config.get_affix_id()
	if affix_id != &"":
		affix_label.text = "词缀: %s" % affix_id
		affix_label.show()
	else:
		affix_label.hide()


func _on_draw_button_pressed() -> void:
	draw_requested.emit(_index)



