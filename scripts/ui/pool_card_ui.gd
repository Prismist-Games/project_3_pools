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
	
	self.theme_type_variation = "Pool_Normal"
	cost_label.text = tr("POOL_COST") % config.gold_cost
		
	if config.affix_data != null and config.affix_data.name != "":
		affix_label.text = tr("POOL_AFFIX") % config.affix_data.name
		affix_label.show()
	else:
		affix_label.hide()


func _on_draw_button_pressed() -> void:
	draw_requested.emit(_index)
