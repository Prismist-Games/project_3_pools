extends PanelContainer

signal salvage_requested(index: int)
signal merge_requested(idx1: int, idx2: int)

@onready var icon_rect: TextureRect = %IconRect
@onready var name_label: Label = %NameLabel
@onready var rarity_label: Label = %RarityLabel

var _index: int = -1
var _item: ItemInstance = null

# 静态变量用于交互模式
static var selected_index: int = -1
static var selection_mode_data: Dictionary = {}


func setup(item: ItemInstance, index: int) -> void:
	_index = index
	_item = item
	
	if item == null:
		name_label.text = ""
		rarity_label.text = ""
		icon_rect.texture = null
		self.modulate = Color.WHITE
		self.modulate.a = 0.2 # 空格子半透明
		return

	self.modulate.a = 1.0
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
	
	# 如果处于选择模式，显示特殊颜色或提示
	if not selection_mode_data.is_empty():
		# 比如如果是 trade_in 模式，且不是主线物品，则允许点击
		if selection_mode_data.get("type") == "trade_in":
			if _item.item_data.item_type == Constants.ItemType.MAINLINE:
				self.modulate.a = 0.3
			else:
				self.modulate = self.modulate.lerp(Color.GOLD, 0.3)


func _on_gui_input(event: InputEvent) -> void:
	if _item == null:
		return
		
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# 优先处理全局选择模式
			if not selection_mode_data.is_empty():
				_handle_selection_mode_click()
				return
				
			if selected_index == -1:
				selected_index = _index
				EventBus.inventory_updated.emit(GameManager.inventory)
			elif selected_index == _index:
				selected_index = -1
				EventBus.inventory_updated.emit(GameManager.inventory)
			else:
				merge_requested.emit(selected_index, _index)
				selected_index = -1
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if selection_mode_data.is_empty():
				salvage_requested.emit(_index)


func _handle_selection_mode_click() -> void:
	var mode_type = selection_mode_data.get("type")
	var callback = selection_mode_data.get("callback")
	
	if mode_type == "trade_in":
		if _item.item_data.item_type == Constants.ItemType.MAINLINE:
			return # 主线物品不可置换
		
		if callback is Callable:
			callback.call(_item)
		
		# 完成后退出选择模式
		selection_mode_data = {}
		EventBus.inventory_updated.emit(GameManager.inventory)

