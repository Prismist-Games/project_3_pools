class_name SwitchController
extends UIController

## Controller for Submit and Recycle Switches

const SWITCH_ON_Y = -213.5
const SWITCH_OFF_Y = 52.5
const HOVER_OFFSET = 30.0

var submit_switch: Node2D
var recycle_switch: Node2D

var _submit_tween: Tween
var _recycle_tween: Tween

var _is_submit_hovered: bool = false
var _is_recycle_hovered: bool = false
var _is_submit_pressed: bool = false
var _is_recycle_pressed: bool = false
var _submit_is_on: bool = false
var _recycle_is_on: bool = false
var _recycle_lid_closed_emitted: bool = false # 防止重复发送 recycle_lid_closed 信号

func setup(submit_node: Node2D, recycle_node: Node2D) -> void:
	submit_switch = submit_node
	recycle_switch = recycle_node
	_init_switches()
	update_switch_visuals(Constants.UIMode.NORMAL) # 确保初始位置正确

func _init_switches() -> void:
	if submit_switch:
		var input = submit_switch.get_node("Input Area")
		if input:
			if input.gui_input.is_connected(_on_submit_switch_input):
				input.gui_input.disconnect(_on_submit_switch_input)
			input.gui_input.connect(_on_submit_switch_input)
			
			if input.mouse_entered.is_connected(_on_submit_switch_hover):
				input.mouse_entered.disconnect(_on_submit_switch_hover)
			input.mouse_entered.connect(_on_submit_switch_hover)
			
			if input.mouse_exited.is_connected(_on_submit_switch_unhover):
				input.mouse_exited.disconnect(_on_submit_switch_unhover)
			input.mouse_exited.connect(_on_submit_switch_unhover)
		
		var off_label = submit_switch.find_child("Switch_off_label", true)
		if off_label: off_label.text = "SWITCH_SUBMIT"
		
		var on_label = submit_switch.find_child("Switch_on_label", true)
		if on_label: on_label.text = "SWITCH_CONFIRM"

	if recycle_switch:
		var input = recycle_switch.get_node("Input Area")
		if input:
			if input.gui_input.is_connected(_on_recycle_switch_input):
				input.gui_input.disconnect(_on_recycle_switch_input)
			input.gui_input.connect(_on_recycle_switch_input)
			
			if input.mouse_entered.is_connected(_on_recycle_switch_hover):
				input.mouse_entered.disconnect(_on_recycle_switch_hover)
			input.mouse_entered.connect(_on_recycle_switch_hover)
			
			if input.mouse_exited.is_connected(_on_recycle_switch_unhover):
				input.mouse_exited.disconnect(_on_recycle_switch_unhover)
			input.mouse_exited.connect(_on_recycle_switch_unhover)

		var label = recycle_switch.find_child("Switch_on_label", true)
		if label: label.text = "0"
		
		var off_label = recycle_switch.find_child("Switch_off_label", true)
		if off_label: off_label.text = "SWITCH_RECYCLE"

func update_switch_visuals(mode: Constants.UIMode) -> void:
	update_submit_visuals(mode == Constants.UIMode.SUBMIT)
	update_recycle_visuals(mode == Constants.UIMode.RECYCLE)

func update_submit_visuals(is_on: bool) -> void:
	_submit_is_on = is_on
	_refresh_switch_visual(submit_switch, _submit_is_on, _is_submit_hovered, _is_submit_pressed)

func update_recycle_visuals(is_on: bool) -> void:
	_recycle_is_on = is_on
	_refresh_switch_visual(recycle_switch, _recycle_is_on, _is_recycle_hovered, _is_recycle_pressed)
	var tween = _recycle_tween
	
	if not is_on:
		if tween:
			tween.finished.connect(func():
				if not _recycle_is_on and not _recycle_lid_closed_emitted:
					_recycle_lid_closed_emitted = true
					update_recycle_label(0)
					clear_recycle_icon()
					EventBus.game_event.emit(&"recycle_lid_closed", null)
			)
		else:
			if not _recycle_lid_closed_emitted:
				_recycle_lid_closed_emitted = true
				update_recycle_label(0)
				clear_recycle_icon()
				EventBus.game_event.emit(&"recycle_lid_closed", null)
	else:
		# 开启时重置标记
		_recycle_lid_closed_emitted = false

## 统一的视觉刷新逻辑
func _refresh_switch_visual(node: Node2D, is_on: bool, is_hovered: bool, is_pressed: bool) -> void:
	if not node: return
	var base_y = SWITCH_ON_Y if is_on else SWITCH_OFF_Y
	var target_y = base_y
	if is_hovered and not is_pressed:
		target_y += (HOVER_OFFSET if is_on else -HOVER_OFFSET)
	_tween_switch(node, target_y)

func update_recycle_label(value: int) -> void:
	if recycle_switch:
		var label = recycle_switch.find_child("Switch_on_label", true)
		if label:
			label.text = str(value)

func show_recycle_preview(value: int) -> void:
	# 先杀掉可能正在进行的关闭 Tween，防止其回调重置 label
	if _recycle_tween:
		_recycle_tween.kill()
		_recycle_tween = null
	
	_recycle_is_on = true
	update_recycle_label(value)
	_tween_switch(recycle_switch, SWITCH_ON_Y)

func hide_recycle_preview() -> void:
	_recycle_is_on = false
	_refresh_switch_visual(recycle_switch, _recycle_is_on, _is_recycle_hovered, _is_recycle_pressed)
	var tween = _recycle_tween
	if tween:
		# 使用弱引用或在 tween 开始前记录状态，防止竞争
		tween.finished.connect(func():
			if not _recycle_is_on and not _recycle_lid_closed_emitted:
				_recycle_lid_closed_emitted = true
				update_recycle_label(0)
				EventBus.game_event.emit(&"recycle_lid_closed", null)
		)
	else:
		if not _recycle_lid_closed_emitted:
			_recycle_lid_closed_emitted = true
			update_recycle_label(0)
			EventBus.game_event.emit(&"recycle_lid_closed", null)

func set_recycle_icon(texture: Texture2D) -> void:
	if recycle_switch:
		var icon: Sprite2D = recycle_switch.find_child("Item_icon", true)
		if icon:
			icon.texture = texture
			icon.modulate.a = 1.0
			icon.scale = Vector2(0.6, 0.6) # 适当缩小以适应开关内部

func clear_recycle_icon() -> void:
	if recycle_switch:
		var icon: Sprite2D = recycle_switch.find_child("Item_icon", true)
		if icon:
			icon.texture = null

func get_recycle_bin_pos() -> Vector2:
	if recycle_switch:
		var root = recycle_switch.find_child("Switch_item_root", true)
		if root: return root.global_position
	return Vector2.ZERO

func get_recycle_icon_node() -> Sprite2D:
	if recycle_switch:
		return recycle_switch.find_child("Item_icon", true) as Sprite2D
	return null

func _tween_switch(switch_node: Node2D, target_y: float) -> Tween:
	if not switch_node: return null
	var handle = switch_node.get_node_or_null("Switch_handle")
	if not handle: return null
	
	# 检查是哪个开关，并清理旧 Tween
	var is_recycle = (switch_node == recycle_switch)
	if is_recycle:
		if _recycle_tween:
			_recycle_tween.kill()
			_recycle_tween = null
	else:
		if _submit_tween:
			_submit_tween.kill()
			_submit_tween = null
	
	if abs(handle.position.y - target_y) < 0.1: return null
	
	var start_y = handle.position.y
	var tween = create_tween()
	
	if is_recycle: _recycle_tween = tween
	else: _submit_tween = tween
	
	tween.tween_method(func(val: float):
		handle.position.y = val
		if handle.has_method("_update_background_positions"):
			handle.call("_update_background_positions")
	, start_y, target_y, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	return tween

# --- Input ---

func _on_submit_switch_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_submit_pressed = true
		else:
			_is_submit_pressed = false
		
		_refresh_switch_visual(submit_switch, _submit_is_on, _is_submit_hovered, _is_submit_pressed)
		
		if not event.pressed:
			if not game_ui or not game_ui.state_machine: return
			
			# 如果 UI 已锁定，则忽略点击，防止重复触发
			if game_ui.is_ui_locked():
				print("[SwitchController] Click ignored: UI is locked")
				return
			
			# 使用 get_ui_mode() 代替 GameManager 检查
			if game_ui.state_machine.get_ui_mode() == Constants.UIMode.NORMAL:
				game_ui.state_machine.transition_to(&"Submitting")
				InventorySystem.multi_selected_indices.clear()
				# 清除单项选中状态，因为提交与整理是不同操作
				if InventorySystem.selected_slot_index != -1:
					InventorySystem.selected_slot_index = -1
			elif game_ui.state_machine.get_ui_mode() == Constants.UIMode.SUBMIT:
				var submitting_state = game_ui.state_machine.get_state(&"Submitting")
				if submitting_state:
					await submitting_state.submit_order()

func _on_recycle_switch_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_recycle_pressed = true
		else:
			_is_recycle_pressed = false
		
		_refresh_switch_visual(recycle_switch, _recycle_is_on, _is_recycle_hovered, _is_recycle_pressed)

		if not event.pressed:
			if not game_ui or not game_ui.state_machine: return

			# 如果 UI 已锁定，则忽略点击，防止重复触发
			if game_ui.is_ui_locked():
				print("[SwitchController] Click ignored: UI is locked")
				return

			var current_mode = game_ui.state_machine.get_ui_mode()

			if current_mode == Constants.UIMode.NORMAL:
				# Check single selection logic
				var selected_idx = InventorySystem.selected_slot_index
				var has_pending = not InventorySystem.pending_items.is_empty()
				
				if selected_idx != -1 or has_pending:
					# Single item recycle via GameUI coordinator due to complexity
					game_ui._handle_single_item_recycle(selected_idx)
				else:
					# Enter multi-recycle mode
					game_ui.state_machine.transition_to(&"Recycling")
					InventorySystem.multi_selected_indices.clear()
					# 清除单项选中状态，因为批量回收与整理是不同操作
					if InventorySystem.selected_slot_index != -1:
						InventorySystem.selected_slot_index = -1
					# Label update happens via signals in GameUI
					
			elif current_mode == Constants.UIMode.RECYCLE:
				var recycling_state = game_ui.state_machine.get_state(&"Recycling")
				if recycling_state:
					await recycling_state.recycle_confirm()

func _on_submit_switch_hover() -> void:
	_is_submit_hovered = true
	_refresh_switch_visual(submit_switch, _submit_is_on, _is_submit_hovered, _is_submit_pressed)

func _on_submit_switch_unhover() -> void:
	_is_submit_hovered = false
	_refresh_switch_visual(submit_switch, _submit_is_on, _is_submit_hovered, _is_submit_pressed)

func _on_recycle_switch_hover() -> void:
	_is_recycle_hovered = true
	if game_ui and game_ui.has_method("_on_recycle_switch_mouse_entered"):
		game_ui._on_recycle_switch_mouse_entered()
	
	# 更新选中/pending物品的hover状态显示
	_update_recyclable_item_hover_state(true)
	
	_refresh_switch_visual(recycle_switch, _recycle_is_on, _is_recycle_hovered, _is_recycle_pressed)


func _on_recycle_switch_unhover() -> void:
	_is_recycle_hovered = false
	if game_ui and game_ui.has_method("_on_recycle_switch_mouse_exited"):
		game_ui._on_recycle_switch_mouse_exited()
	
	# 清除选中/pending物品的hover状态显示
	_update_recyclable_item_hover_state(false)
	
	_refresh_switch_visual(recycle_switch, _recycle_is_on, _is_recycle_hovered, _is_recycle_pressed)


## 更新选中/pending物品在hover recycle switch时的视觉状态
## [param is_hovering]: true = 鼠标在recycle switch上, false = 离开
func _update_recyclable_item_hover_state(is_hovering: bool) -> void:
	if not game_ui or not game_ui.state_machine:
		return
	
	var ui_mode = game_ui.state_machine.get_ui_mode()
	
	# 仅在 NORMAL 模式或存在待处理物品的状态（Replacing 等通常属于 NORMAL 逻辑分支）下允许
	# 注意：如果正在批量回收（RECYCLE 模式），我们不在此处处理单项 hover 视觉，因为全员都是可回收的
	if ui_mode == Constants.UIMode.RECYCLE or ui_mode == Constants.UIMode.SUBMIT:
		return
	
	var selected_idx = InventorySystem.selected_slot_index
	var has_pending = not InventorySystem.pending_items.is_empty()
	
	# 选中item_slot物品时hover在recycle switch上 -> 可回收
	if selected_idx != -1:
		var slot = game_ui.inventory_controller.get_slot_node(selected_idx) as ItemSlotUI
		if slot:
			if is_hovering:
				slot.set_hover_action_state(ItemSlotUI.HoverType.RECYCLABLE)
			else:
				slot.set_hover_action_state(ItemSlotUI.HoverType.NONE)
	
	# pending时hover在recycle switch上 -> 可回收 (lottery slot中的物品)
	elif has_pending:
		# 获取pending物品所在的lottery slot
		var source_pool_idx = game_ui.pending_source_pool_idx
		if source_pool_idx >= 0:
			var pool_slot = game_ui.pool_controller._get_slot_node(source_pool_idx) as LotterySlotUI
			if pool_slot:
				if is_hovering:
					pool_slot.set_hover_action_state(LotterySlotUI.HoverType.RECYCLABLE)
				else:
					pool_slot.set_hover_action_state(LotterySlotUI.HoverType.NONE)


## 检查recycle switch是否被hover
func is_recycle_hovered() -> bool:
	return _is_recycle_hovered
