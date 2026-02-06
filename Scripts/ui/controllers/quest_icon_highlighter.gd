class_name QuestIconHighlighter
extends RefCounted

## 订单图标高亮管理器
##
## 负责管理当鼠标悬停在奖池或物品槽位时，订单需求中相关物品图标的放大动画。
## 采用绝对目标缩放值，防止快速移动鼠标时缩放累加。

## 高亮动画配置
const HIGHLIGHT_WIDTH: float = 15.0
const NORMAL_WIDTH: float = 0.0
const ANIMATION_DURATION: float = 0.05

## 飘浮动画配置
const FLOAT_AMPLITUDE: float = 36.0
const FLOAT_CYCLE_TIME: float = 0.8

## 当前正在高亮的图标节点集合 (key: icon node, value: original scale)
var _highlighted_icons: Dictionary = {}

## 所有正在运行的 tween 引用 (用于取消)
var _active_tweens: Dictionary = {}

## 订单控制器引用
var order_controller: OrderController = null

## 游戏UI引用 (用于访问特殊面板)
var game_ui: Node = null

## 清除所有高亮
func clear_all_highlights() -> void:
	var icons_to_clear = _highlighted_icons.keys().duplicate()
	for icon in icons_to_clear:
		_unhighlight_icon(icon)

## 根据奖池类型高亮相关订单图标
## [param pool_item_type]: 奖池物品类型 (Constants.ItemType)
func highlight_by_pool_type(pool_item_type: int) -> void:
	if pool_item_type <= 0:
		return
	
	# 1. 获取该类型下所有物品的 ID
	var pool_item_ids: Array[StringName] = []
	var pool_items = GameManager.get_items_for_type(pool_item_type)
	for item_data in pool_items:
		pool_item_ids.append(item_data.id)
	
	# 2. 高亮所有匹配的订单图标
	_highlight_matching_icons(pool_item_ids)

## 根据物品 ID 高亮相关订单图标
## [param item_id]: 物品 ID
func highlight_by_item_id(item_id: StringName) -> void:
	if item_id == &"":
		return
	
	_highlight_matching_icons([item_id])

## 根据物品 ID 列表高亮相关订单图标 (用于二选一/五选一)
## [param item_ids]: 物品 ID 数组
func highlight_by_item_ids(item_ids: Array) -> void:
	if item_ids.is_empty():
		return
	
	var typed_ids: Array[StringName] = []
	for id in item_ids:
		typed_ids.append(id as StringName)
	
	_highlight_matching_icons(typed_ids)

## 内部：高亮所有匹配的图标
func _highlight_matching_icons(item_ids: Array[StringName]) -> void:
	if not order_controller:
		return
	
	# 收集所有需要高亮的图标节点
	var icons_to_highlight: Array[Node] = []
	
	# 1. 遍历普通订单槽位 (1-4)
	for slot_index in range(1, 5):
		var slot = order_controller.get_slot_node(slot_index)
		if not slot or not slot.visible:
			continue
		
		var icon_nodes = _get_matching_icons_from_slot(slot, item_ids)
		icons_to_highlight.append_array(icon_nodes)
	
	# 2. 检查主线订单（两个槽位）
	for main_slot in order_controller.main_quest_slots:
		if main_slot and main_slot.visible:
			var icon_nodes = _get_matching_icons_from_slot(main_slot, item_ids, true)
			icons_to_highlight.append_array(icon_nodes)
	
	# 3. 取消当前不在新列表中的高亮
	var to_unhighlight: Array[Node] = []
	for icon in _highlighted_icons.keys():
		if icon not in icons_to_highlight:
			to_unhighlight.append(icon)
	
	for icon in to_unhighlight:
		_unhighlight_icon(icon)
	
	# 4. 高亮新图标
	for icon in icons_to_highlight:
		if icon not in _highlighted_icons:
			_highlight_icon(icon)

## 内部：从订单槽位中获取匹配的图标节点
func _get_matching_icons_from_slot(slot: Control, item_ids: Array[StringName], is_main: bool = false) -> Array[Node]:
	var result: Array[Node] = []
	
	var order = slot.get_order() if slot.has_method("get_order") else null
	if not order:
		return result
	
	# 获取 items_grid 节点
	var grid_name = "Main Quest Slot Items Grid" if is_main else "Quest Slot Items Grid"
	var items_grid = slot.find_child(grid_name, true)
	if not items_grid:
		return result
	
	# 遍历订单需求
	var item_root_prefix = "Main Quest Slot Item_root_" if is_main else "Quest Slot Item_root_"
	for i in range(order.requirements.size()):
		var req = order.requirements[i]
		var req_item_id = req.get("item_id", &"")
		
		if req_item_id in item_ids:
			# 1. 改为使用 find_child 增加对层级变化的鲁棒性
			var req_node = items_grid.find_child(item_root_prefix + str(i), true)
			if req_node:
				var icon = req_node.find_child("Item_icon", true)
				if icon and icon.visible:
					result.append(icon)
	
	return result

## 内部：高亮单个图标
func _highlight_icon(icon: Node) -> void:
	if not is_instance_valid(icon):
		return
	
	var sprite = icon as Sprite2D
	if not sprite:
		return
		
	# 3. 运行时实例化一下所有shader，变local
	if sprite.material is ShaderMaterial:
		if not sprite.material.resource_local_to_scene:
			sprite.material = sprite.material.duplicate()
			sprite.material.resource_local_to_scene = true
	
	# 记录原始状态并启动动画
	if icon not in _highlighted_icons:
		_highlighted_icons[icon] = {
			"original_y": sprite.position.y,
			"float_tween": null
		}
	
	# 创建描边动画
	var tween = _create_tween_for_icon(icon)
	if tween:
		if sprite.material is ShaderMaterial:
			tween.tween_property(sprite.material, "shader_parameter/width", HIGHLIGHT_WIDTH, ANIMATION_DURATION) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_active_tweens[icon] = tween
	
	# 2. 增加飘动动画: Item_icon 的 position:y 上下飘动
	var float_tween = _create_tween_for_icon(icon)
	if float_tween:
		float_tween.set_loops()
		var start_y = _highlighted_icons[icon]["original_y"]
		float_tween.tween_property(sprite, "position:y", start_y - FLOAT_AMPLITUDE, FLOAT_CYCLE_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		float_tween.tween_property(sprite, "position:y", start_y, FLOAT_CYCLE_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_highlighted_icons[icon]["float_tween"] = float_tween

## 内部：取消高亮单个图标
func _unhighlight_icon(icon: Node) -> void:
	if not is_instance_valid(icon):
		_highlighted_icons.erase(icon)
		_active_tweens.erase(icon)
		return
	
	var sprite = icon as Sprite2D
	if not sprite:
		_highlighted_icons.erase(icon)
		_active_tweens.erase(icon)
		return

	# 取消之前的动画 (描边)
	if _active_tweens.has(icon) and _active_tweens[icon] != null:
		var old_tween: Tween = _active_tweens[icon]
		if old_tween.is_valid():
			old_tween.kill()
	
	# 停止飘动动画并复位位置
	if _highlighted_icons.has(icon):
		var data = _highlighted_icons[icon]
		if data["float_tween"] and data["float_tween"].is_valid():
			data["float_tween"].kill()
		
		var reset_tween = _create_tween_for_icon(icon)
		if reset_tween:
			reset_tween.tween_property(sprite, "position:y", data["original_y"], ANIMATION_DURATION) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# 创建缩小动画
	var tween = _create_tween_for_icon(icon)
	if not tween:
		# 无法创建动画，直接清理并设置最终值
		if sprite.material is ShaderMaterial:
			sprite.material.set_shader_parameter("width", NORMAL_WIDTH)
		_highlighted_icons.erase(icon)
		_active_tweens.erase(icon)
		return
	
	if sprite.material is ShaderMaterial:
		tween.tween_property(sprite.material, "shader_parameter/width", NORMAL_WIDTH, ANIMATION_DURATION) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# 动画完成后清理
	tween.finished.connect(func():
		_highlighted_icons.erase(icon)
		_active_tweens.erase(icon)
	)
	
	_active_tweens[icon] = tween

## 创建 tween (需要通过有效的场景树节点)
func _create_tween_for_icon(icon: Node) -> Tween:
	if is_instance_valid(icon) and icon.is_inside_tree():
		return icon.create_tween()
	elif game_ui and is_instance_valid(game_ui):
		return game_ui.create_tween()
	else:
		# 兜底：返回一个可能无效的 tween
		push_warning("[QuestIconHighlighter] 无法创建有效的 Tween")
		return null
