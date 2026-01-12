extends Control

## 游戏主 UI：管理各面板与系统的交互。

@onready var gold_label: Label = %GoldLabel

@onready var pools_container: Container = %PoolsContainer
@onready var orders_container: Container = %OrdersContainer
@onready var inventory_grid: Container = %InventoryGrid
@onready var skills_container: Container = %SkillsContainer
@onready var recycle_mode_button: Button = %RecycleModeButton
@onready var submit_mode_button: Button = %SubmitModeButton
@onready var submit_mode_label: Label = %ModeLabel

# 新增待定物品容器引用
@onready var pending_container: Control = %PendingContainer

const POOL_CARD_SCENE = preload("res://scenes/ui/pool_card.tscn")
const ORDER_CARD_SCENE = preload("res://scenes/ui/order_card.tscn")
const INVENTORY_SLOT_SCENE = preload("res://scenes/ui/inventory_slot.tscn")
const SKILL_ICON_SCENE = preload("res://scenes/ui/skill_icon.tscn")
const DEBUG_CONSOLE_SCENE = preload("res://scenes/ui/debug_console.tscn")


var _debug_console: Control = null


func _ready() -> void:
	# 监听全局信号
	GameManager.gold_changed.connect(_on_gold_changed)
	# InventorySystem 信号
	InventorySystem.inventory_changed.connect(_on_inventory_changed)
	InventorySystem.pending_queue_changed.connect(_on_pending_queue_changed)
	InventorySystem.multi_selection_changed.connect(_on_multi_selection_changed)
	
	GameManager.order_selection_changed.connect(_on_order_selection_changed)
	GameManager.ui_mode_changed.connect(_on_ui_mode_changed)
	
	# SkillSystem 信号 (Refactored)
	SkillSystem.skills_changed.connect(_on_skills_changed)
	
	EventBus.pools_refreshed.connect(_on_pools_refreshed)
	EventBus.orders_updated.connect(_on_orders_updated)
	EventBus.modal_requested.connect(_on_modal_requested)
	EventBus.game_event.connect(_on_game_event)
	
	recycle_mode_button.pressed.connect(_on_recycle_mode_button_pressed)
	submit_mode_button.pressed.connect(_on_submit_mode_button_pressed)
	
	# 设置所有标签为深色以适配白色背景
	_apply_white_background_styles()
	
	# 初始化显示
	_update_ui_mode_display()
	_on_gold_changed(GameManager.gold)
	_on_inventory_changed(InventorySystem.inventory)
	_on_skills_changed(SkillSystem.current_skills)
	_on_pending_queue_changed(InventorySystem.pending_items)


func _apply_white_background_styles() -> void:
	var dark_text = Constants.COLOR_TEXT_MAIN
	gold_label.add_theme_color_override("font_color", dark_text)
	submit_mode_label.add_theme_color_override("font_color", dark_text)


func _on_ui_mode_changed(_mode: Constants.UIMode) -> void:
	_update_ui_mode_display()
	_on_inventory_changed(InventorySystem.inventory)
	_on_orders_updated(OrderSystem.current_orders)


func _update_ui_mode_display() -> void:
	var mode = GameManager.current_ui_mode
	var has_pending = InventorySystem.pending_item != null
	# 只有在普通模式且没有待定物品时，才被视为“真正的普通模式”
	var is_normal = mode == Constants.UIMode.NORMAL and not has_pending
	
	# 通用拦截：非整理模式或有待定物品时，使用 process_mode 彻底禁用交互
	pools_container.process_mode = Node.PROCESS_MODE_INHERIT if is_normal else Node.PROCESS_MODE_DISABLED
	pools_container.modulate = Color(1, 1, 1, 1.0) if is_normal else Color(1, 1, 1, 0.6)
	
	skills_container.process_mode = Node.PROCESS_MODE_INHERIT if is_normal else Node.PROCESS_MODE_DISABLED
	skills_container.modulate = Color(1, 1, 1, 1.0) if is_normal else Color(1, 1, 1, 0.6)
	
	# 只有在 NORMAL（无待定）或 SUBMIT 模式下订单区域可交互
	var can_interact_orders = is_normal or (mode == Constants.UIMode.SUBMIT and not has_pending)
	orders_container.process_mode = Node.PROCESS_MODE_INHERIT if can_interact_orders else Node.PROCESS_MODE_DISABLED
	orders_container.modulate = Color(1, 1, 1, 1.0) if can_interact_orders else Color(1, 1, 1, 0.6)

	# 特殊处理：有待定物品时的 UI 显示
	if has_pending:
		var count = InventorySystem.pending_items.size()
		if count > 1:
			submit_mode_label.text = "背包已满！还有 %d 个物品待处理，请替换或丢弃" % count
		else:
			submit_mode_label.text = "背包已满！请点击格子替换或点击右端丢弃"
		
		submit_mode_label.add_theme_color_override("font_color", Color.FIREBRICK)
		submit_mode_button.text = "丢弃新物品"
		submit_mode_button.disabled = false
		recycle_mode_button.text = "回收模式"
		recycle_mode_button.disabled = true
		return

	match mode:
		Constants.UIMode.NORMAL:
			submit_mode_label.text = "整理模式"
			submit_mode_label.add_theme_color_override("font_color", Constants.COLOR_TEXT_MAIN)
			submit_mode_button.text = "提交订单"
			submit_mode_button.disabled = false
			recycle_mode_button.text = "回收模式"
			recycle_mode_button.disabled = false
		Constants.UIMode.SUBMIT:
			submit_mode_label.text = "提交模式：请选择物品并点击订单填充"
			submit_mode_label.add_theme_color_override("font_color", Constants.COLOR_BORDER_SELECTED)
			submit_mode_button.text = "确认提交"
			submit_mode_button.disabled = true
			
			var selected_items: Array[ItemInstance] = []
			for idx in InventorySystem.multi_selected_indices:
				if idx >= 0 and idx < InventorySystem.inventory.size() and InventorySystem.inventory[idx]:
					selected_items.append(InventorySystem.inventory[idx])
			
			if GameManager.order_selection_index != -1:
				var order = OrderSystem.current_orders[GameManager.order_selection_index]
				if order.validate_selection(selected_items).valid:
					submit_mode_button.disabled = false
			else:
				# 如果没选特定订单，只要有任何一个订单被满足，就允许提交
				for order in OrderSystem.current_orders:
					if order.validate_selection(selected_items).valid:
						submit_mode_button.disabled = false
						break
			
			recycle_mode_button.text = "取消"
			recycle_mode_button.disabled = false
		Constants.UIMode.RECYCLE:
			submit_mode_label.text = "回收模式：选择物品并点击执行"
			submit_mode_label.add_theme_color_override("font_color", Constants.COLOR_RECYCLE_ACTION)
			submit_mode_button.text = "取消"
			submit_mode_button.disabled = false
			recycle_mode_button.text = "确认回收"
			recycle_mode_button.disabled = false
		Constants.UIMode.REPLACE:
			submit_mode_label.text = "以旧换新：请选择置换目标"
			submit_mode_label.add_theme_color_override("font_color", Color.GOLDENROD)
			submit_mode_button.text = "取消"
			submit_mode_button.disabled = false
			recycle_mode_button.disabled = true


func _on_submit_mode_button_pressed() -> void:
	if InventorySystem.pending_item != null:
		# 丢弃新物品逻辑
		InventorySystem.recycle_item_instance(InventorySystem.pending_item)
		InventorySystem.pending_item = null
		return

	match GameManager.current_ui_mode:
		Constants.UIMode.NORMAL:
			GameManager.current_ui_mode = Constants.UIMode.SUBMIT
			GameManager.order_selection_index = -1
		Constants.UIMode.SUBMIT:
			var success = OrderSystem.submit_order(GameManager.order_selection_index, InventorySystem.multi_selected_indices)
			if success:
				GameManager.current_ui_mode = Constants.UIMode.NORMAL
		Constants.UIMode.RECYCLE, Constants.UIMode.REPLACE:
			# 在回收或以旧换新模式下，该按钮作为“取消”
			_cancel_current_mode()


func _on_recycle_mode_button_pressed() -> void:
	match GameManager.current_ui_mode:
		Constants.UIMode.NORMAL:
			GameManager.current_ui_mode = Constants.UIMode.RECYCLE
		Constants.UIMode.RECYCLE:
			if not InventorySystem.multi_selected_indices.is_empty():
				_execute_multi_recycle()
			GameManager.current_ui_mode = Constants.UIMode.NORMAL
		Constants.UIMode.SUBMIT, Constants.UIMode.REPLACE:
			# 在提交或以旧换新模式下，该按钮作为“取消”
			_cancel_current_mode()


func _cancel_current_mode() -> void:
	GameManager.current_ui_mode = Constants.UIMode.NORMAL
	InventorySystem.multi_selected_indices.clear()
	GameManager.order_selection_index = -1

	_on_inventory_changed(InventorySystem.inventory)


func _execute_multi_recycle() -> void:
	var indices = InventorySystem.multi_selected_indices.duplicate()
	indices.sort()
	indices.reverse()
	for idx in indices:
		InventorySystem.recycle_item(idx)
	InventorySystem.multi_selected_indices.clear()


func _on_pending_queue_changed(items: Array[ItemInstance]) -> void:
	# 清空待定区域的槽位
	for child in pending_container.get_children():
		child.queue_free()
	
	for i in range(items.size()):
		var slot = INVENTORY_SLOT_SCENE.instantiate()
		pending_container.add_child(slot)
		slot.setup(items[i], -1)
		
		if i == 0:
			slot.modulate = Color(1.2, 1.2, 1.2, 1.0)
		else:
			slot.modulate = Color(0.7, 0.7, 0.7, 0.8)
	
	# 控制整个待定区域（包括标题）的显示/隐藏
	var section = pending_container.get_parent()
	if section:
		section.visible = not items.is_empty()
	
	_update_ui_mode_display()


func _on_order_selection_changed(_index: int) -> void:
	_on_orders_updated(OrderSystem.current_orders)
	_on_inventory_changed(InventorySystem.inventory)


func _on_gold_changed(val: int) -> void:
	gold_label.text = "金币: %d" % val


func _on_pools_refreshed(pools: Array) -> void:
	# 清空并重新生成池卡片
	for child in pools_container.get_children():
		child.queue_free()
		
	for i in pools.size():
		var card = POOL_CARD_SCENE.instantiate()
		pools_container.add_child(card)
		card.setup(pools[i], i)
		card.draw_requested.connect(_on_pool_draw_requested)


func _on_orders_updated(orders: Array) -> void:
	# 清空并重新生成订单卡片
	for child in orders_container.get_children():
		child.queue_free()
		
	for i in orders.size():
		var card = ORDER_CARD_SCENE.instantiate()
		orders_container.add_child(card)
		card.setup(orders[i], i)
		card.submit_requested.connect(_on_order_submit_requested)
		card.refresh_requested.connect(_on_order_refresh_requested)


func _on_inventory_changed(items: Array[ItemInstance]) -> void:
	# 更新背包格子
	for child in inventory_grid.get_children():
		child.queue_free()
		
	var total_slots = InventorySystem.inventory.size()
	if total_slots == 0: total_slots = 10
		
	for i in total_slots:
		var slot = INVENTORY_SLOT_SCENE.instantiate()
		inventory_grid.add_child(slot)
		
		var item = items[i] if i < items.size() else null
		slot.setup(item, i)
		slot.slot_clicked.connect(_on_slot_clicked)
		slot.recycle_requested.connect(_on_item_recycle_requested)
	
	# 如果处于提交模式，背包变动（如选择物品）需要刷新订单卡片的奖励预览
	if GameManager.current_ui_mode == Constants.UIMode.SUBMIT:
		_on_orders_updated(OrderSystem.current_orders)
	
	_update_ui_mode_display()


func _on_multi_selection_changed(_indices: Array[int]) -> void:
	_on_inventory_changed(InventorySystem.inventory)


func _on_slot_clicked(index: int) -> void:
	InventorySystem.handle_slot_click(index)


func _on_skills_changed(skills: Array) -> void:
	for child in skills_container.get_children():
		child.queue_free()
		
	for skill in skills:
		var icon = SKILL_ICON_SCENE.instantiate()
		skills_container.add_child(icon)
		icon.setup(skill)


func _on_pool_draw_requested(index: int) -> void:
	PoolSystem.draw_from_pool(index)


func _on_order_submit_requested(index: int) -> void:
	if GameManager.current_ui_mode != Constants.UIMode.SUBMIT:
		# 1. 自动切换到提交模式
		GameManager.current_ui_mode = Constants.UIMode.SUBMIT
	
	# 2. 执行智能填充逻辑
	GameManager.order_selection_index = index
	var order = OrderSystem.current_orders[index]
	var smart_indices = order.find_smart_selection(InventorySystem.inventory)
	
	# 冲突处理：智能填充直接覆盖多选列表
	# 使用 setter 触发信号
	InventorySystem.selected_indices_for_order = smart_indices
	
	# 获取对应的 ItemInstance 列表进行验证
	var selected_items: Array[ItemInstance] = []
	for idx in smart_indices:
		selected_items.append(InventorySystem.inventory[idx])
	
	# 检查库存是否完全满足
	if not order.validate_selection(selected_items).valid:
		EventBus.game_event.emit(&"order_card_shake_requested", ContextProxy.new({"index": index}))
	
	InventorySystem.inventory_changed.emit(InventorySystem.inventory)
	_update_ui_mode_display()


func _on_order_refresh_requested(index: int) -> void:
	OrderSystem.refresh_order(index)


func _on_item_recycle_requested(index: int) -> void:
	InventorySystem.recycle_item(index)


func _on_item_merge_requested(_idx1: int, _idx2: int) -> void:
	pass


func _on_game_event(event_id: StringName, payload: Variant) -> void:
	if event_id == &"enter_selection_mode":
		var data = payload
		if payload is ContextProxy:
			data = payload.data
		

		if data.get("type") == "trade_in":
			GameManager.current_ui_mode = Constants.UIMode.REPLACE
		
		_on_inventory_changed(InventorySystem.inventory)


func _on_modal_requested(modal_id: StringName, payload: Variant) -> void:
	# 兼容 null payload
	var data = {}
	if payload is Dictionary:
		data = payload
		
	match modal_id:
		&"skill_select":
			_handle_skill_selection(data)
		&"precise_selection":
			_handle_precise_selection(data)
		&"targeted_selection":
			_handle_targeted_selection(data)
		&"general_confirmation":
			_handle_general_confirmation(data)


func _handle_skill_selection(_payload: Dictionary) -> void:
	var skills = SkillSystem.get_selectable_skills(3)
	if skills.is_empty():
		return
		
	var dialog = AcceptDialog.new()
	dialog.title = "解锁新技能"
	add_child(dialog)
	
	var v_box = VBoxContainer.new()
	dialog.add_child(v_box)
	
	var label = Label.new()
	label.text = "请选择一个技能加入你的技能槽："
	v_box.add_child(label)
	
	var h_box = HBoxContainer.new()
	v_box.add_child(h_box)
	
	for skill in skills:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(150, 100)
		btn.text = "%s\n\n%s" % [skill.name, skill.description]
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		
		btn.pressed.connect(func():
			if SkillSystem.current_skills.size() < Constants.SKILL_SLOTS:
				SkillSystem.add_skill(skill)
			else:
				# TODO: 技能槽满时的替换逻辑
				# 暂时直接添加（演示用，实际应弹出替换面板）
				SkillSystem.add_skill(skill)
			dialog.queue_free()
		)
		h_box.add_child(btn)
	
	dialog.get_ok_button().hide() # 必须通过点击按钮关闭
	dialog.popup_centered()


func _handle_general_confirmation(payload: Dictionary) -> void:
	var title = payload.get("title", "确认")
	var text = payload.get("text", "")
	var confirm_callback = payload.get("confirm_callback")
	var cancel_callback = payload.get("cancel_callback")
	var confirm_text = payload.get("confirm_text", "确认")
	var cancel_text = payload.get("cancel_text", "取消")
	
	var dialog = ConfirmationDialog.new()
	dialog.title = title
	dialog.dialog_text = text
	add_child(dialog)
	
	dialog.get_ok_button().text = confirm_text
	dialog.get_cancel_button().text = cancel_text
	
	dialog.confirmed.connect(func():
		if confirm_callback is Callable:
			confirm_callback.call()
		dialog.queue_free()
	)
	
	dialog.canceled.connect(func():
		if cancel_callback is Callable:
			cancel_callback.call()
		dialog.queue_free()
	)
	
	dialog.popup_centered()


func _handle_precise_selection(payload: Dictionary) -> void:
	var items: Array[ItemInstance] = []
	items.assign(payload.get("items", []))
	var callback: Callable = payload.get("callback")
	
	var dialog = ConfirmationDialog.new()
	dialog.title = "精准抽奖：二选一"
	dialog.dialog_text = "请选择一个物品："
	add_child(dialog)
	
	var h_box = HBoxContainer.new()
	dialog.add_child(h_box)
	
	for item in items:
		var btn = Button.new()
		btn.text = "[%s] %s" % [Constants.rarity_display_name(item.rarity), item.get_display_name()]
		btn.pressed.connect(func():
			if callback.is_valid():
				callback.call(item)
			dialog.queue_free()
		)
		h_box.add_child(btn)
	
	dialog.get_ok_button().hide()
	dialog.get_cancel_button().text = "放弃"
	dialog.popup_centered()


func _handle_targeted_selection(payload: Dictionary) -> void:
	var items: Array[ItemData] = []
	items.assign(payload.get("items", []))
	var callback: Callable = payload.get("callback")
	
	var dialog = AcceptDialog.new()
	dialog.title = "有的放矢：选择类型"
	add_child(dialog)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 400)
	dialog.add_child(scroll)
	
	var v_box = VBoxContainer.new()
	scroll.add_child(v_box)
	
	for item_data in items:
		var btn = Button.new()
		btn.text = item_data.name
		btn.pressed.connect(func():
			if callback.is_valid():
				callback.call(item_data)
			dialog.queue_free()
		)
		v_box.add_child(btn)
	
	dialog.get_ok_button().hide()
	dialog.popup_centered()


func _input(event: InputEvent) -> void:
	# F12 打开/关闭调试控制台
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		_toggle_debug_console()
		get_viewport().set_input_as_handled()


func _toggle_debug_console() -> void:
	if _debug_console == null:
		_debug_console = DEBUG_CONSOLE_SCENE.instantiate()
		add_child(_debug_console)
	else:
		_debug_console.visible = not _debug_console.visible
