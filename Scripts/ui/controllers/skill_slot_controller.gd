class_name SkillSlotController
extends UIController

## Controller for TheMachineSlot_0/1/2 skill slots
##
## 管理技能槽位的:
## - 位置动画: 降下 (-888) / 升起 (-1160) / hover (-1190)
## - 图标更新: Skill_icon 的 texture
## - Tooltip: 技能 description
## - Input Area: hover 和点击信号转发

signal slot_clicked(index: int)
signal slot_hovered(index: int)
signal slot_unhovered(index: int)

## 位置常量
const SLOT_Y_DOWN: float = -888.0    ## 降下状态 (空槽)
const SLOT_Y_UP: float = -1160.0     ## 升起状态 (有技能)
const SLOT_Y_HOVER: float = -1190.0  ## hover 状态 (选择替换时)
const ANIMATION_DURATION: float = 0.5 # 增加时长使其更明显

## 槽位节点引用
var _slot_nodes: Array[Node2D] = []

## 当前动画 Tweens
var _slot_tweens: Array[Tween] = [null, null, null]

## 记录每个槽位当前正在动画的目标 Y 坐标
var _slot_target_ys: Array[float] = [0.0, 0.0, 0.0]

## hover 交互是否启用 (仅在技能替换时启用)
var _hover_enabled: bool = false

## 当前 hover 的槽位索引 (-1 表示无)
var _current_hover_index: int = -1

func setup(slot_nodes: Array[Node2D]) -> void:
	_slot_nodes = slot_nodes
	_connect_input_signals()
	
	# 初始化目标值
	for i in range(_slot_target_ys.size()):
		if i < _slot_nodes.size() and _slot_nodes[i]:
			_slot_target_ys[i] = _slot_nodes[i].position.y
	
	# 初始化: 根据当前技能状态设置槽位位置 (瞬间完成)
	refresh_slots(SkillSystem.current_skills, false)


func _connect_input_signals() -> void:
	for i in range(_slot_nodes.size()):
		var slot = _slot_nodes[i]
		if not slot:
			continue
		
		var fill_node = slot.get_node_or_null("TheMachineSlot_fill")
		if not fill_node:
			continue
		
		var input_area = fill_node.get_node_or_null("Input Area") as Control
		if not input_area:
			continue
		
		# 清除旧连接
		if input_area.gui_input.is_connected(_on_slot_input):
			input_area.gui_input.disconnect(_on_slot_input)
		if input_area.mouse_entered.is_connected(_on_slot_mouse_entered):
			input_area.mouse_entered.disconnect(_on_slot_mouse_entered)
		if input_area.mouse_exited.is_connected(_on_slot_mouse_exited):
			input_area.mouse_exited.disconnect(_on_slot_mouse_exited)
		
		# 连接新信号
		input_area.gui_input.connect(_on_slot_input.bind(i))
		input_area.mouse_entered.connect(_on_slot_mouse_entered.bind(i))
		input_area.mouse_exited.connect(_on_slot_mouse_exited.bind(i))


## 刷新所有槽位显示
func refresh_slots(skills: Array, animated: bool = true) -> void:
	for i in range(_slot_nodes.size()):
		var slot = _slot_nodes[i]
		if not slot:
			continue
		
		var fill_node = slot.get_node_or_null("TheMachineSlot_fill")
		if not fill_node:
			continue
		
		var icon_node = fill_node.get_node_or_null("Skill_icon") as TextureRect
		var input_area = fill_node.get_node_or_null("Input Area") as Control
		
		if i < skills.size() and skills[i] != null:
			var skill: SkillData = skills[i]
			
			# 设置图标
			if icon_node:
				icon_node.texture = skill.icon
				icon_node.tooltip_text = "" # 清除旧位置 tooltip
			
			# 设置 Tooltip 到 Input Area
			if input_area:
				input_area.tooltip_text = "%s: %s" % [tr(skill.name), tr(skill.description)]
			
			# 槽位升起
			if animated:
				animate_slot_up(i)
			else:
				_set_slot_position(i, SLOT_Y_UP)
		else:
			# 空槽: 清空图标, 降下
			if icon_node:
				icon_node.texture = null
				icon_node.tooltip_text = ""
			
			if input_area:
				input_area.tooltip_text = ""
			
			if animated:
				animate_slot_down(i)
			else:
				_set_slot_position(i, SLOT_Y_DOWN)


## 带动画升起槽位
func animate_slot_up(index: int) -> void:
	if index < 0 or index >= _slot_nodes.size():
		return
	_animate_slot_to(index, SLOT_Y_UP)


## 带动画降下槽位
func animate_slot_down(index: int) -> void:
	if index < 0 or index >= _slot_nodes.size():
		return
	_animate_slot_to(index, SLOT_Y_DOWN)


## 带动画移动到 hover 位置
func animate_slot_hover(index: int) -> void:
	if index < 0 or index >= _slot_nodes.size():
		return
	_animate_slot_to(index, SLOT_Y_HOVER)


## 启用/禁用 hover 交互
func set_hover_enabled(enabled: bool) -> void:
	_hover_enabled = enabled
	
	if not enabled and _current_hover_index != -1:
		# 禁用时恢复当前 hover 槽位到升起状态
		animate_slot_up(_current_hover_index)
		_current_hover_index = -1


## 更新单个槽位的技能显示
func update_slot_skill(index: int, skill: SkillData) -> void:
	if index < 0 or index >= _slot_nodes.size():
		return
	
	var slot = _slot_nodes[index]
	if not slot:
		return
	
	var fill_node = slot.get_node_or_null("TheMachineSlot_fill")
	if not fill_node:
		return
	
	var icon_node = fill_node.get_node_or_null("Skill_icon") as TextureRect
	var input_area = fill_node.get_node_or_null("Input Area") as Control
	
	if icon_node and skill:
		icon_node.texture = skill.icon
		icon_node.tooltip_text = ""
	
	if input_area and skill:
		input_area.tooltip_text = "%s: %s" % [tr(skill.name), tr(skill.description)]


## 获取空槽位索引 (-1 表示全满)
func get_empty_slot_index() -> int:
	var skills = SkillSystem.current_skills
	for i in range(3):
		if i >= skills.size() or skills[i] == null:
			return i
	return -1


## 检查槽位是否已满
func is_slots_full() -> bool:
	return SkillSystem.current_skills.size() >= Constants.SKILL_SLOTS


## 内部: 设置槽位位置 (无动画)
func _set_slot_position(index: int, y_pos: float, _animated: bool = false) -> void:
	if index < 0 or index >= _slot_nodes.size():
		return
	
	# 停止当前动画
	if _slot_tweens[index]:
		_slot_tweens[index].kill()
		_slot_tweens[index] = null
	
	var slot = _slot_nodes[index]
	if slot:
		slot.position.y = y_pos
		_slot_target_ys[index] = y_pos
		_update_slot_input_state(index, y_pos)


## 内部: 动画移动槽位到目标位置
func _animate_slot_to(index: int, target_y: float) -> void:
	if index < 0 or index >= _slot_nodes.size():
		return
	
	var slot = _slot_nodes[index]
	if not slot:
		return
	
	# 如果已经在向该目标位置移动，则跳过
	if (_slot_tweens[index] and _slot_tweens[index].is_running() and abs(_slot_target_ys[index] - target_y) < 0.1) \
		or (not (_slot_tweens[index] and _slot_tweens[index].is_running()) and abs(slot.position.y - target_y) < 0.1):
		return
	
	# 杀掉旧 tween
	if _slot_tweens[index]:
		_slot_tweens[index].kill()
	
	_slot_target_ys[index] = target_y
	_update_slot_input_state(index, target_y)
	
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUINT)
	tween.tween_property(slot, "position:y", target_y, ANIMATION_DURATION)
	
	_slot_tweens[index] = tween


## 内部: 根据位置更新输入区域状态
func _update_slot_input_state(index: int, y_pos: float) -> void:
	var slot = _slot_nodes[index]
	if not slot:
		return
	
	var fill_node = slot.get_node_or_null("TheMachineSlot_fill")
	if not fill_node:
		return
	
	var input_area = fill_node.get_node_or_null("Input Area") as Control
	if not input_area:
		return
	
	# 如果在降下状态，忽略鼠标
	if abs(y_pos - SLOT_Y_DOWN) < 0.1:
		input_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		input_area.mouse_filter = Control.MOUSE_FILTER_STOP


## 输入处理
func _on_slot_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 只有在 hover 启用时才响应点击
		if _hover_enabled:
			slot_clicked.emit(index)


func _on_slot_mouse_entered(index: int) -> void:
	if not _hover_enabled:
		return
	
	_current_hover_index = index
	animate_slot_hover(index)
	slot_hovered.emit(index)


func _on_slot_mouse_exited(index: int) -> void:
	if not _hover_enabled:
		return
	
	if _current_hover_index == index:
		_current_hover_index = -1
		# 恢复到升起状态
		animate_slot_up(index)
		slot_unhovered.emit(index)
