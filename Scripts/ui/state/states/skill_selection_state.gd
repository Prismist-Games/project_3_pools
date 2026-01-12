extends "res://scripts/ui/state/ui_state.gd"

## SkillSelectionState - 技能三选一状态
##
## 流程:
## 1. 进入时三个 lottery slot 开门展示三个可选技能
## 2. UI 更新: price="", affix=技能名, description=技能描述, item_main=技能图标
## 3. 玩家点击选择技能:
##    - 有空槽: 技能自动添加, 对应槽位升起
##    - 槽满: 关闭另外两个 slot, 进入替换模式
## 4. 替换模式: 玩家 hover/点击技能槽位选择替换
## 5. 右键取消: 关门刷新返回 Idle

## 主控制器引用
var controller: Node = null

## 可选的技能列表 (最多 3 个)
var selectable_skills: Array[SkillData] = []

## 选中的技能索引 (lottery slot index)
var selected_skill_index: int = -1

## 选中的技能数据
var selected_skill: SkillData = null

## 是否在替换模式 (槽满后等待玩家选择替换槽位)
var _in_replace_mode: bool = false

## 是否已经做出选择
var _has_made_selection: bool = false

## 推挤动画时长
const PUSH_DURATION: float = 0.4

func enter(payload: Dictionary = {}) -> void:
	selected_skill_index = -1
	selected_skill = null
	_in_replace_mode = false
	_has_made_selection = false
	
	if not controller:
		push_error("[SkillSelectionState] controller 未设置")
		return
	
	# 锁定 UI
	controller.lock_ui("skill_selection")
	
	# 获取可选技能
	selectable_skills.assign(SkillSystem.get_selectable_skills(3))
	
	if selectable_skills.is_empty():
		push_warning("[SkillSelectionState] 没有可选技能")
		machine.transition_to(&"Idle")
		return
	
	# 设置全局刷新标记，防止干扰
	if controller.pool_controller:
		controller.pool_controller._is_animating_refresh = true
	
	# 展示技能选择 UI
	_setup_skill_display()


func exit() -> void:
	# 断开槽位控制器信号
	_disconnect_skill_slot_signals()
	
	# 禁用槽位 hover 交互
	if controller.skill_slot_controller:
		controller.skill_slot_controller.set_hover_enabled(false)
	
	# 关闭所有打开的 lottery slot 并刷新
	_close_all_slots_and_refresh()
	
	# 清理状态
	_has_made_selection = false
	_in_replace_mode = false
	selected_skill_index = -1
	selected_skill = null
	selectable_skills.clear()
	
	if controller:
		controller.unlock_ui("skill_selection")


func can_transition_to(_next_state: StringName) -> bool:
	return true


func handle_input(event: InputEvent) -> bool:
	# 右键取消
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if not _has_made_selection:
			_cancel_selection()
		return true
	return false


## 玩家选择了某个技能 (点击 lottery slot)
func select_skill(index: int) -> void:
	if _has_made_selection:
		return
	
	if index < 0 or index >= selectable_skills.size():
		return
	
	selected_skill_index = index
	selected_skill = selectable_skills[index]
	
	# 检查是否有空槽
	var empty_slot_index = -1
	if controller.skill_slot_controller:
		empty_slot_index = controller.skill_slot_controller.get_empty_slot_index()
	else:
		# 兼容: 如果没有 controller, 直接检查 SkillSystem
		if SkillSystem.current_skills.size() < Constants.SKILL_SLOTS:
			empty_slot_index = SkillSystem.current_skills.size()
	
	if empty_slot_index != -1:
		# 有空槽: 直接添加技能
		_has_made_selection = true
		_add_skill_to_slot(selected_skill, empty_slot_index)
	else:
		# 槽满: 进入替换模式
		_enter_replace_mode()


## 取消技能选择 (右键)
func _cancel_selection() -> void:
	if _has_made_selection:
		return
	
	_has_made_selection = true
	machine.transition_to(&"Idle")


## 添加技能到指定槽位
func _add_skill_to_slot(skill: SkillData, _slot_index: int) -> void:
	# 添加技能到系统 (会自动触发 SkillSlotController 的升起动画)
	SkillSystem.add_skill(skill)
	
	# 等待一小段时间让动画播放
	await controller.get_tree().create_timer(0.4).timeout
	
	# 返回 Idle
	machine.transition_to(&"Idle")


## 进入替换模式 (槽满场景)
func _enter_replace_mode() -> void:
	_in_replace_mode = true
	
	# 关闭未选中的 lottery slot
	for i in range(3):
		if i != selected_skill_index:
			var slot = _get_lottery_slot(i)
			if slot:
				slot.close_lid()
	
	# 启用技能槽位的 hover 交互
	if controller.skill_slot_controller:
		controller.skill_slot_controller.set_hover_enabled(true)
		_connect_skill_slot_signals()


## 连接技能槽位控制器信号
func _connect_skill_slot_signals() -> void:
	if not controller.skill_slot_controller:
		return
	
	var skill_ctrl = controller.skill_slot_controller
	
	if not skill_ctrl.slot_clicked.is_connected(_on_skill_slot_clicked):
		skill_ctrl.slot_clicked.connect(_on_skill_slot_clicked)


## 断开技能槽位控制器信号
func _disconnect_skill_slot_signals() -> void:
	if not controller.skill_slot_controller:
		return
	
	var skill_ctrl = controller.skill_slot_controller
	
	if skill_ctrl.slot_clicked.is_connected(_on_skill_slot_clicked):
		skill_ctrl.slot_clicked.disconnect(_on_skill_slot_clicked)


## 技能槽位被点击 (替换模式下)
func _on_skill_slot_clicked(slot_index: int) -> void:
	if not _in_replace_mode or _has_made_selection or selected_skill == null:
		return
	
	_has_made_selection = true
	
	# 禁用 hover 交互
	if controller.skill_slot_controller:
		controller.skill_slot_controller.set_hover_enabled(false)
	
	# 先降下旧槽位
	if controller.skill_slot_controller:
		controller.skill_slot_controller.animate_slot_down(slot_index)
	
	# 等待降下动画
	await controller.get_tree().create_timer(0.35).timeout
	
	# 替换技能 (会自动触发 SkillSlotController 的刷新/升起动画)
	SkillSystem.replace_skill(slot_index, selected_skill)
	
	# 等待升起动画
	await controller.get_tree().create_timer(0.4).timeout
	
	# 返回 Idle
	machine.transition_to(&"Idle")


## 设置技能选择展示 UI
func _setup_skill_display() -> void:
	if not controller:
		return
	
	# 并行执行所有槽位的揭示动画
	for i in range(3):
		var slot = _get_lottery_slot(i)
		if slot:
			if i < selectable_skills.size():
				_reveal_skill_slot(slot, selectable_skills[i], i)
			else:
				slot.close_lid()
	
	# 等待动画完成的大致时长 (推挤 + 开门揭示 + 停留)
	# 0.4 (push) + 0.5 (shuffle) + 0.3 (reveal)
	await controller.get_tree().create_timer(1.5).timeout
	
	if controller.pool_controller:
		controller.pool_controller._is_animating_refresh = false


## 辅助：并行揭示单个技能槽位
func _reveal_skill_slot(slot: Control, skill: SkillData, index: int) -> void:
	# 1. 更新描述和配置
	if slot.description_label:
		slot.description_label.text = skill.description
	
	_clear_slot_hints(slot)
	
	if slot.price_icon:
		slot.price_icon.visible = false
		
	var config = {
		"price_text": "",
		"affix_name": skill.name,
		"description_text": skill.description,
		"clear_hints": true,
		"skip_lid_animation": true
	}
	
	if slot.has_method("refresh_slot_data"):
		await slot.refresh_slot_data(config, false)
	
	# 2. 播放开门揭示
	await slot.play_reveal_sequence([])
	
	# 3. 强制显示技能图标
	if slot.item_main:
		slot.item_main.texture = skill.icon
		slot.item_main.visible = true
		slot.item_main.scale = Vector2.ONE
	if slot.item_main_shadow:
		slot.item_main_shadow.visible = true
	
	# 4. 连接输入
	_connect_slot_input(slot, index)


## 清空槽位的右侧图标
func _clear_slot_hints(slot: Control) -> void:
	if not slot:
		return
	
	var items_grid = slot.get_node_or_null("Lottery Slot_right_screen/Lottery Slot_right_screen_fill/Lottery Required Items Icon Grid")
	if items_grid:
		for j in range(5):
			var icon_node = items_grid.get_node_or_null("Item Icon_" + str(j))
			if icon_node:
				icon_node.visible = false


## 连接 lottery slot 的点击输入
func _connect_slot_input(slot: Control, index: int) -> void:
	var input_area = slot.find_child("Input Area", true) as Control
	if input_area:
		# 先断开可能存在的旧连接
		if input_area.gui_input.is_connected(_on_lottery_slot_input):
			input_area.gui_input.disconnect(_on_lottery_slot_input)
		
		input_area.gui_input.connect(_on_lottery_slot_input.bind(index))


## 断开 lottery slot 的点击输入
func _disconnect_all_slot_inputs() -> void:
	for i in range(3):
		var slot = _get_lottery_slot(i)
		if not slot:
			continue
		
		var input_area = slot.find_child("Input Area", true) as Control
		if input_area and input_area.gui_input.is_connected(_on_lottery_slot_input):
			input_area.gui_input.disconnect(_on_lottery_slot_input)


## Lottery slot 输入处理
func _on_lottery_slot_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		select_skill(index)


## 关闭所有 lottery slot 并刷新奖池
func _close_all_slots_and_refresh() -> void:
	if not controller:
		return
	
	# 断开输入连接
	_disconnect_all_slot_inputs()
	
	# 关闭所有槽位
	for i in range(3):
		var slot = _get_lottery_slot(i)
		if slot and slot.is_drawing:
			slot.play_close_sequence()
	
	# 刷新奖池
	if controller.pool_controller and controller.pool_controller.has_method("play_all_refresh_animations"):
		controller.pool_controller._is_animating_refresh = true
		PoolSystem.refresh_pools()
		controller.pool_controller.play_all_refresh_animations(PoolSystem.current_pools, -1)
	else:
		PoolSystem.refresh_pools()


## 辅助: 获取 LotterySlot 节点
func _get_lottery_slot(index: int) -> Control:
	if not controller or not controller.lottery_slots_grid:
		return null
	return controller.lottery_slots_grid.get_node_or_null("Lottery Slot_root_" + str(index))
