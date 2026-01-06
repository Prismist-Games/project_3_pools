extends PanelContainer

signal slot_clicked(index: int)
signal salvage_requested(index: int)

@onready var icon_rect: TextureRect = %IconRect
@onready var name_label: Label = %NameLabel
@onready var rarity_label: Label = %RarityLabel

var _index: int = -1
var _item: ItemInstance = null
var _checkbox: Panel = null
var _is_preview: bool = false

# 静态变量用于交互模式（保留以支持原有逻辑，但主要逻辑转入 InventorySystem）
static var selection_mode_data: Dictionary = {}


func _ready() -> void:
	# 确保即使没有编辑器设置样式，也能看到格子边框
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 1.0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.4, 0.4, 1.0)
	style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", style)
	
	# 创建复选框视觉 (放在右上角)
	# 使用一个空的 Control 容器来承载复选框，避免被 PanelContainer 强制铺满
	var cb_container = Control.new()
	cb_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cb_container)
	
	_checkbox = Panel.new()
	var cb_style = StyleBoxFlat.new()
	cb_style.set_corner_radius_all(2)
	cb_style.bg_color = Color.WHITE
	cb_style.border_width_left = 1
	cb_style.border_width_top = 1
	cb_style.border_width_right = 1
	cb_style.border_width_bottom = 1
	cb_style.border_color = Color.GRAY
	_checkbox.add_theme_stylebox_override("panel", cb_style)
	_checkbox.custom_minimum_size = Vector2(16, 16)
	_checkbox.size = Vector2(16, 16)
	# 设置在右上角
	_checkbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_checkbox.offset_left = -20
	_checkbox.offset_top = 4
	_checkbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_checkbox.hide()
	cb_container.add_child(_checkbox)


func setup(item: ItemInstance, index: int) -> void:
	_index = index
	_item = item
	_is_preview = false
	
	_update_visuals()


func setup_preview(item_data: ItemData, rarity: int, is_fulfilled: bool = false) -> void:
	_index = -1
	_item = null
	_is_preview = true
	
	var style = _get_or_create_style()
	
	if item_data == null:
		name_label.text = ""
		rarity_label.text = ""
		icon_rect.texture = null
		self.modulate = Color.WHITE
		style.bg_color = Constants.COLOR_BG_SLOT_EMPTY
		style.border_color = Color("#e2e8f0")
	else:
		name_label.text = item_data.name
		
		rarity_label.text = Constants.rarity_display_name(rarity)
		icon_rect.texture = item_data.icon
		
		style.bg_color = Constants.get_rarity_bg_color(rarity)
		style.border_color = Constants.get_rarity_border_color(rarity)
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.bg_color.a = 1.0
		
		name_label.add_theme_color_override("font_color", Constants.COLOR_TEXT_MAIN)
		rarity_label.add_theme_color_override("font_color", Constants.get_rarity_border_color(rarity).darkened(0.2))

	# 预览模式下的特殊视觉
	if _checkbox: _checkbox.hide()
	self.mouse_filter = Control.MOUSE_FILTER_PASS # 允许点击穿透到订单卡片
	
	if is_fulfilled:
		# 满足需求时，显示明显的勾选或亮起
		style.border_color = Color("#22c55e") # Green-500
		style.border_width_left = 3
		style.border_width_top = 3
		style.border_width_right = 3
		style.border_width_bottom = 3
		self.modulate = Color.WHITE
		
		# 添加一个小勾选图标（可选，这里先用文字示意）
		rarity_label.text = "✅ " + rarity_label.text
	else:
		# 未满足时，稍微变暗且边框灰色
		self.modulate = Color(1, 1, 1, 0.7)
		style.border_color = style.border_color.lerp(Color.GRAY, 0.5)


func _get_or_create_style() -> StyleBoxFlat:
	var style = get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		style = style.duplicate()
		add_theme_stylebox_override("panel", style)
	return style


func _update_visuals() -> void:
	var style = _get_or_create_style()
	
	if _item == null:
		name_label.text = ""
		rarity_label.text = ""
		icon_rect.texture = null
		self.modulate = Color.WHITE
		if style:
			style.bg_color = Constants.COLOR_BG_SLOT_EMPTY
			style.border_color = Color("#e2e8f0") # Slate-200
			style.border_width_left = 2
			style.border_width_top = 2
			style.border_width_right = 2
			style.border_width_bottom = 2
	else:
		name_label.text = _item.get_display_name()
		
		var rarity_text = Constants.rarity_display_name(_item.rarity)
		if GameManager.current_ui_mode == Constants.UIMode.RECYCLE:
			var val = Constants.rarity_salvage_value(_item.rarity)
			rarity_text += " (+%d)" % val
		rarity_label.text = rarity_text
		
		icon_rect.texture = _item.item_data.icon
		
		# 使用 UX 规范颜色
		if style:
			style.bg_color = Constants.get_rarity_bg_color(_item.rarity)
			style.border_color = Constants.get_rarity_border_color(_item.rarity)
			style.border_width_left = 2
			style.border_width_top = 2
			style.border_width_right = 2
			style.border_width_bottom = 2
			style.bg_color.a = 1.0
		
		# 强制设置深色字体
		name_label.add_theme_color_override("font_color", Constants.COLOR_TEXT_MAIN)
		rarity_label.add_theme_color_override("font_color", Constants.get_rarity_border_color(_item.rarity).darkened(0.2))
		
		# 状态标记
		if _item.sterile:
			name_label.text += " 🚫"

	# 交互视觉反馈
	_update_interaction_visuals(style)


func _update_interaction_visuals(style: StyleBoxFlat) -> void:
	if not style: return
	
	var mode = GameManager.current_ui_mode
	var is_multi_selected = _index in InventorySystem.multi_selected_indices
	
	# 重置整体透明度
	self.modulate = Color.WHITE
	
	# 更新复选框
	if _checkbox:
		if mode in [Constants.UIMode.SUBMIT, Constants.UIMode.RECYCLE]:
			_checkbox.show()
			var cb_style = _checkbox.get_theme_stylebox("panel") as StyleBoxFlat
			if is_multi_selected:
				cb_style.bg_color = Constants.COLOR_BORDER_SELECTED if mode == Constants.UIMode.SUBMIT else Constants.COLOR_RECYCLE_ACTION
			else:
				cb_style.bg_color = Color.WHITE
		else:
			_checkbox.hide()

	# 基础高亮：整理模式的单选
	if mode == Constants.UIMode.NORMAL and InventorySystem.selected_slot_index == _index:
		style.border_color = Color("#f59e0b") # Amber-500
		style.border_width_left = 4
		style.border_width_top = 4
		style.border_width_right = 4
		style.border_width_bottom = 4
		return

	# 模式特定高亮
	match mode:
		Constants.UIMode.SUBMIT:
			if is_multi_selected:
				style.border_color = Constants.COLOR_BORDER_SELECTED
				style.border_width_left = 4
				style.border_width_top = 4
				style.border_width_right = 4
				style.border_width_bottom = 4
				# 选中的背景稍微加深一点蓝色
				style.bg_color = Color("#bfdbfe") # Blue-200
			else:
				# 未选中的物品，如果背景太浅，在提交模式下稍微调低透明度以示区别
				if _item:
					self.modulate.a = 0.8
		Constants.UIMode.RECYCLE:
			if is_multi_selected:
				style.border_color = Constants.COLOR_RECYCLE_ACTION
				style.border_width_left = 4
				style.border_width_top = 4
				style.border_width_right = 4
				style.border_width_bottom = 4
				style.bg_color = Color("#fecaca") # Red-200
			else:
				if _item:
					self.modulate.a = 0.8
		Constants.UIMode.TRADE_IN:
			# 以旧换新模式：非主线物品高亮，主线变暗
			if _item:
				if _item.item_data.item_type == Constants.ItemType.MAINLINE:
					self.modulate.a = 0.3
				else:
					style.border_color = Color("#eab308") # Yellow-500
					style.border_width_left = 4
					style.border_width_top = 4
					style.border_width_right = 4
					style.border_width_bottom = 4


func _on_gui_input(event: InputEvent) -> void:
	if _is_preview: return # 预览模式不响应点击
	
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# 1. 优先处理特殊选择模式 (Trade-in)
			if GameManager.current_ui_mode == Constants.UIMode.TRADE_IN:
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
				salvage_requested.emit(_index)


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
