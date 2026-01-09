extends "res://scripts/ui/state/ui_state.gd"

## PreciseSelectionState - 精准选择（二选一）

## 引用到主控制器
var controller: Node = null

## 可选物品列表
var options: Array = []

## 来源奖池索引
var source_pool_index: int = -1

func enter(payload: Dictionary = {}) -> void:
	options = payload.get("items", []) # 注意：payload 里是 "items"
	source_pool_index = payload.get("source_pool_index", -1)
	
	if not controller:
		push_error("[PreciseSelectionState] controller 未设置")
		return

	# 锁定 UI 进行精准选择
	controller.lock_ui("precise_selection")
	
	# 设置视觉展示
	_setup_precise_display()

func exit() -> void:
	# 关闭所有精准选择打开的槽位并还原 UI
	_cleanup_precise_display()
	
	options.clear()
	source_pool_index = -1
	
	if controller:
		controller.unlock_ui("precise_selection")

func can_transition_to(_next_state: StringName) -> bool:
	return true

## 选取其中一个选项
func select_option(index: int) -> void:
	if index < 0 or index >= options.size():
		return
		
	var item_instance = options[index]
	
	# 执行逻辑添加物品
	var added = InventorySystem.add_item_instance(item_instance)
	
	if not added:
		# 如果添加失败（背包满），转换到 Replacing 状态
		machine.transition_to(&"Replacing", {"source_pool_index": source_pool_index})
	else:
		# 添加成功，先关盖，等关完后再刷新，最后回 Idle
		await _cleanup_precise_display()
		PoolSystem.refresh_pools()
		machine.transition_to(&"Idle")

func handle_input(event: InputEvent) -> bool:
	# 拦截右键，阻止取消
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		return true # 消费事件，阻止传递
	return false

func _setup_precise_display() -> void:
	if not controller: return
	
	# 显示 2 个候选物品槽位
	for i in range(3):
		var slot = controller.lottery_slots_grid.get_node("Lottery Slot_root_" + str(i))
		if i < options.size():
			var item = options[i]
			# 隐藏原有奖池标签
			_set_slot_labels_visible(slot, false)
			
			# 更新图标并展示
			slot.item_main.texture = item.item_data.icon
			slot.item_main.visible = true
			
			# 打开盖子
			slot.open_lid()
		else:
			# 第三个槽位如果本就是开着的，则关上，且不显示内容
			slot.close_lid()

func _cleanup_precise_display() -> void:
	if not controller: return
	
	for i in range(3):
		var slot = controller.lottery_slots_grid.get_node("Lottery Slot_root_" + str(i))
		if slot:
			# 使用异步关盖以便等待
			if slot.has_method("play_close_sequence"):
				await slot.play_close_sequence()
			else:
				slot.close_lid()
			
			# 还原标签显示
			_set_slot_labels_visible(slot, true)

func _set_slot_labels_visible(slot: Node, visible: bool) -> void:
	if not slot: return
	for child_name in ["PoolName_label", "Price_label", "Price_icon", "Affix_label", "Description_label"]:
		var label = slot.find_child(child_name, true)
		if label:
			label.visible = visible
