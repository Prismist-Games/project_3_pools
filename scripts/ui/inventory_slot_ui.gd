extends PanelContainer

signal slot_clicked(index: int)
signal recycle_requested(index: int)

@onready var icon_rect: TextureRect = %IconRect
@onready var name_label: Label = %NameLabel
@onready var rarity_label: Label = %RarityLabel

var _index: int = -1
var _item: ItemInstance = null
var _checkbox: Panel = null
var _is_preview: bool = false

# 静态变量用于交互模式（保留以支持原有逻辑，但主要逻辑转入 InventorySystem）
static var selection_mode_data: Dictionary = {}


@onready var state_border: Panel = $StateBorder

# 静态变量用于交互模式（保留以支持原有逻辑，但主要逻辑转入 InventorySystem）
static var selection_mode_data: Dictionary = {}


func _ready() -> void:
	# 确保 StateBorder 正常配置
	if state_border:
		state_border.mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(item: ItemInstance, index: int) -> void:
	_index = index
	_item = item
	_is_preview = false
	
	_update_visuals()


func setup_preview(item_data: ItemData, rarity: int, is_fulfilled: bool = false) -> void:
	_index = -1
	_item = null
	_is_preview = true
	
	# 1. 基础样式
	if item_data == null:
		name_label.text = ""
		rarity_label.text = ""
		icon_rect.texture = null
		self.theme_type_variation = "Slot_Empty"
	else:
		name_label.text = item_data.name
		rarity_label.text = Constants.rarity_display_name(rarity)
		icon_rect.texture = item_data.icon
		
		# 使用基础变体
		var rarity_key = Constants.rarity_id(rarity).capitalize()
		self.theme_type_variation = "Slot_" + rarity_key
		
		# 强制设置深色字体
		name_label.add_theme_color_override("font_color", Constants.COLOR_TEXT_MAIN)
		var border_col = Constants.get_rarity_border_color(rarity)
		rarity_label.add_theme_color_override("font_color", border_col.darkened(0.2))

	# 2. 预览模式交互状态
	self.mouse_filter = Control.MOUSE_FILTER_PASS
	self.modulate = Color.WHITE
	
	if is_fulfilled:
		rarity_label.text = "✅ " + rarity_label.text
		if state_border:
			state_border.theme_type_variation = "Border_Fulfilled"
	else:
		self.modulate = Color(1, 1, 1, 0.7)
		if state_border:
			state_border.theme_type_variation = "Border_None"


func _update_visuals() -> void:
	# 1. 基础内容与变体
	if _item == null:
		name_label.text = ""
		rarity_label.text = ""
		icon_rect.texture = null
		self.theme_type_variation = "Slot_Empty"
	else:
		name_label.text = _item.get_display_name()
		
		var rarity_text = Constants.rarity_display_name(_item.rarity)
		if GameManager.current_ui_mode == Constants.UIMode.RECYCLE:
			var val = Constants.rarity_recycle_value(_item.rarity)
			rarity_text += " (+%d)" % val
		rarity_label.text = rarity_text
		
		icon_rect.texture = _item.item_data.icon
		
		# 设置基础变体
		var rarity_key = Constants.rarity_id(_item.rarity).capitalize()
		self.theme_type_variation = "Slot_" + rarity_key
		
		# 字体颜色
		name_label.add_theme_color_override("font_color", Constants.COLOR_TEXT_MAIN)
		var border_col = Constants.get_rarity_border_color(_item.rarity)
		rarity_label.add_theme_color_override("font_color", border_col.darkened(0.2))
		
		if _item.sterile:
			name_label.text += " 🚫"

	# 2. 交互状态
	_update_interaction_visuals()


func _update_interaction_visuals() -> void:
	if not state_border: return
	
	var mode = GameManager.current_ui_mode
	var is_multi_selected = _index in InventorySystem.multi_selected_indices
	
	# 重置透明度
	self.modulate = Color.WHITE
	state_border.theme_type_variation = "Border_None"

	# 基础高亮：整理模式的单选
	if mode == Constants.UIMode.NORMAL and InventorySystem.selected_slot_index == _index:
		state_border.theme_type_variation = "Border_Replace" # Amber for current selection
		return

	# 模式特定高亮
	match mode:
		Constants.UIMode.SUBMIT:
			if is_multi_selected:
				state_border.theme_type_variation = "Border_Selected"
			else:
				if _item: self.modulate.a = 0.8 # 未选中变暗
		
		Constants.UIMode.RECYCLE:
			if is_multi_selected:
				state_border.theme_type_variation = "Border_Recycle"
			else:
				if _item: self.modulate.a = 0.8

		Constants.UIMode.REPLACE:
			if _item:
				if _item.item_data.item_type == Constants.ItemType.MAINLINE:
					self.modulate.a = 0.3 # 主线不可选
				else:
					state_border.theme_type_variation = "Border_Replace"


func _on_gui_input(event: InputEvent) -> void:
	if _is_preview: return # 预览模式不响应点击
	
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# 1. 优先处理特殊选择模式 (Trade-in)
			if GameManager.current_ui_mode == Constants.UIMode.REPLACE:
				_handle_selection_mode_click()
				return
			
			# 2. 处理多选模式 (提交/回收)
			if GameManager.current_ui_mode in [Constants.UIMode.SUBMIT, Constants.UIMode.RECYCLE]:
				if _item != null:
					if _index in InventorySystem.multi_selected_indices:
						InventorySystem.multi_selected_indices.erase(_index)
					else:
						InventorySystem.multi_selected_indices.append(_index)
					# 手动触发信号以更新 UI
					InventorySystem.multi_selection_changed.emit(InventorySystem.multi_selected_indices)
				return

			# 3. 普通整理模式
			slot_clicked.emit(_index)
		
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# 右键快捷进入回收模式（可选）或者直接回收
			if GameManager.current_ui_mode == Constants.UIMode.NORMAL and _item != null:
				recycle_requested.emit(_index)


func _handle_selection_mode_click() -> void:
	if _item == null:
		return
		
	var mode_type = selection_mode_data.get("type")
	var callback = selection_mode_data.get("callback")
	
	if mode_type == "trade_in":
		if _item.item_data.item_type == Constants.ItemType.MAINLINE:
			return # 主线物品不可置换
		
		if callback is Callable:
			callback.call(_item)
		
		# 完成后退出选择模式
		selection_mode_data = {}
		GameManager.current_ui_mode = Constants.UIMode.NORMAL
		InventorySystem.inventory_changed.emit(InventorySystem.inventory)
