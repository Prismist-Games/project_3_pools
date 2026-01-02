extends PanelContainer

signal salvage_requested(index: int)
signal synthesis_requested(idx1: int, idx2: int)

@onready var icon_rect: TextureRect = %IconRect
@onready var name_label: Label = %NameLabel
@onready var rarity_label: Label = %RarityLabel

var _index: int = -1
var _item: ItemInstance = null

# 静态变量用于跨格子追踪选中项（简单合成交互）
static var selected_index: int = -1


func setup(item: ItemInstance, index: int) -> void:
	_index = index
	_item = item
	
	name_label.text = item.get_display_name()
	rarity_label.text = Constants.rarity_display_name(item.rarity)
	
	if item.sterile:
		name_label.text += " (绝育)"
		
	# 简单颜色区分
	match item.rarity:
		Constants.Rarity.COMMON: self.modulate = Color.SLATE_GRAY
		Constants.Rarity.UNCOMMON: self.modulate = Color.GREEN
		Constants.Rarity.RARE: self.modulate = Color.DODGER_BLUE
		Constants.Rarity.EPIC: self.modulate = Color.PURPLE
		Constants.Rarity.LEGENDARY: self.modulate = Color.ORANGE
		Constants.Rarity.MYTHIC: self.modulate = Color.CRIMSON
		
	# 如果是当前选中项，高亮
	if selected_index == _index:
		self.modulate = self.modulate.lightened(0.5)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if selected_index == -1:
				selected_index = _index
				# 这里由于是静态变量，需要通知 UI 刷新显示
				# 简单起见，直接发信号让外部重新 rebuild inventory
				EventBus.inventory_updated.emit(GameManager.inventory)
			elif selected_index == _index:
				selected_index = -1
				EventBus.inventory_updated.emit(GameManager.inventory)
			else:
				synthesis_requested.emit(selected_index, _index)
				selected_index = -1
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			salvage_requested.emit(_index)

