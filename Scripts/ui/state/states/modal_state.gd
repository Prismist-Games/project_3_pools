extends UIState

## ModalState - 弹窗模式 (技能选择、Targeted 词缀选择等)
##
## 触发: 各种业务逻辑发出的 EventBus.modal_requested 信号
## 效果: 锁定 UI，通过 lottery_slot 投影显示选项

## 引用到主控制器
var controller: Node = null

## 弹窗类型标识
var modal_type: StringName = &""

## 弹窗选项数据
var options: Array = []

## 选择结果回调
var on_select: Callable

func enter(payload: Dictionary = {}) -> void:
	modal_type = payload.get("modal_type", &"")
	options = payload.get("options", [])
	on_select = payload.get("on_select", Callable())
	
	if not controller:
		push_error("[ModalState] controller 未设置")
		return

	# 锁定 UI
	controller.lock_ui(str(modal_type))
	
	# 根据类型进行视觉设置
	if modal_type == &"skill_select":
		_setup_skill_selection_display()
	elif modal_type == &"targeted_selection":
		_setup_targeted_selection_display()

func exit() -> void:
	# 清理视觉显示
	_cleanup_display()
	
	if controller:
		controller.unlock_ui(str(modal_type))
		
	modal_type = &""
	options.clear()
	on_select = Callable()

func can_transition_to(_next_state: StringName) -> bool:
	# 允许根据业务逻辑（选择完毕）退出到任何状态
	return true

## 处理选择结果
func select_option(index: int) -> void:
	if on_select.is_valid():
		on_select.call(index)
	
	# 完成选择后一般返回 Idle
	machine.transition_to(&"Idle")

func handle_input(event: InputEvent) -> bool:
	# 技能选择允许右键取消
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if modal_type == &"skill_select":
			machine.transition_to(&"Idle")
			return true
	return false

func _setup_skill_selection_display() -> void:
	if not controller: return
	
	for i in range(3):
		var slot = controller.lottery_slots_grid.get_node("Lottery Slot_root_" + str(i))
		if i < options.size():
			var skill = options[i]
			slot.pool_name_label.text = skill.name
			slot.item_main.texture = skill.icon
			slot.price_label.text = "CHOOSE"
			slot.affix_label.text = ""
			slot.description_label.text = skill.description
			slot.visible = true
			slot.open_lid()
		else:
			slot.visible = false

func _setup_targeted_selection_display() -> void:
	if not controller: return
	
	for i in range(3):
		var slot = controller.lottery_slots_grid.get_node("Lottery Slot_root_" + str(i))
		if i < options.size():
			var item_data = options[i]
			slot.pool_name_label.text = item_data.item_name
			slot.item_main.texture = item_data.icon
			slot.price_label.text = "SELECT"
			slot.affix_label.text = ""
			slot.description_label.text = item_data.description
			slot.visible = true
			slot.open_lid()
		else:
			slot.visible = false

func _cleanup_display() -> void:
	if not controller: return
	
	for i in range(3):
		var slot = controller.lottery_slots_grid.get_node("Lottery Slot_root_" + str(i))
		if slot:
			slot.visible = true
			slot.close_lid()
			# 刷新以恢复正常的奖池显示
			PoolSystem.refresh_pools()
