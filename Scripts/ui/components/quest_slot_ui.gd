class_name QuestSlotUI
extends BaseSlotUI

@onready var reward_label: RichTextLabel = find_child("Quest Reward Label", true)
@onready var reward_icon: TextureRect = find_child("Quest Reward Icon", true)
@onready var items_grid: HBoxContainer = find_child("Quest Slot Items Grid", true)
@onready var backgrounds: Node2D = find_child("Quest Slot_background", true)
@onready var refresh_label: RichTextLabel = find_child("Refresh Count Label", true)

var order_index: int = -1
var is_submit_mode: bool = false
var _current_order: OrderData = null

## 突出动画相关
const PROTRUDE_OFFSET: float = 100.0 # 向右突出的像素距离
const PROTRUDE_DURATION: float = 0.2 # 动画时长
var _protrude_tween: Tween = null
var _original_position_x: float = 0.0

func setup(index: int) -> void:
	order_index = index
	# 订单槽位初始状态是开启的
	if anim_player.has_animation("lid_open"):
		anim_player.play("lid_open")
	
	var refresh_btn = find_child("Refresh Button", true)
	if refresh_btn:
		refresh_btn.pressed.connect(_on_refresh_button_pressed)
	
	# 记录原始 position.x（只记录 x 坐标，y 由 VBoxContainer 管理）
	_original_position_x = position.x

func get_order() -> OrderData:
	return _current_order

func _on_refresh_button_pressed() -> void:
	if order_index != -1:
		EventBus.game_event.emit(&"order_refresh_requested", ContextProxy.new({"index": order_index - 1}))

func play_refresh_anim() -> void:
	if anim_player.has_animation("lid_close"):
		anim_player.play("lid_close")
		await anim_player.animation_finished
		# Logic to change content happens here in parent
		if anim_player.has_animation("lid_open"):
			anim_player.play("lid_open")
			await anim_player.animation_finished

func set_submit_mode(active: bool) -> void:
	is_submit_mode = active
	# 退出提交模式时复位突出状态
	if not active:
		_reset_protrude()

func update_order_display(order_data: OrderData, req_states: Array = []) -> void:
	_current_order = order_data
	if not order_data:
		visible = false
		return
	
	visible = true
	# Update reward display
	if reward_label:
		reward_label.text = str(order_data.reward_gold)
	
	# 设置背景和图标（统一为金币，但区分主线/普通颜色）
	if order_data.is_mainline:
		# 主线订单：橙色/红色背景
		if backgrounds:
			backgrounds.color = Color("#FBB03B")
		else:
			var mainline_bg = find_child("Main Quest Slot_background", true)
			if mainline_bg:
				mainline_bg.self_modulate = Color("#FF585D")
	else:
		# 普通订单：绿色背景
		if backgrounds:
			backgrounds.color = Color("#62DC40")
			
	if reward_icon:
		reward_icon.texture = preload("res://assets/sprites/icons/money.png")
	
	if refresh_label:
		refresh_label.text = str(order_data.refresh_count)
	
	var refresh_btn = find_child("Refresh Button", true)
	if refresh_btn:
		refresh_btn.disabled = order_data.refresh_count <= 0
	
	_update_requirements(order_data.requirements, req_states)
	
	# 在提交模式下，检测订单是否被满足并设置突出状态
	if is_submit_mode:
		var is_satisfied = _check_order_satisfied(order_data, req_states)
		_set_protrude(is_satisfied)
	else:
		_reset_protrude()

func _update_requirements(reqs: Array[Dictionary], req_states: Array) -> void:
	# 适配不同名字的 Grid (Quest Slot Items Grid 或 Main Quest Slot Items Grid)
	var grid = items_grid
	var item_root_prefix = "Quest Slot Item_root_"
	if not grid:
		grid = find_child("Main Quest Slot Items Grid", true)
		item_root_prefix = "Main Quest Slot Item_root_"
	
	if not grid: return

	for i in range(4):
		var req_node = grid.get_node_or_null(item_root_prefix + str(i))
		if not req_node: continue
		
		if i < reqs.size():
			req_node.visible = true
			var req = reqs[i]
			var item_id = req.get("item_id", &"")
			var item_data = GameManager.get_item_data(item_id)
			
			var icon = req_node.find_child("Item_icon", true)
			if icon and item_data:
				icon.texture = item_data.icon
			
			# A. 需求品质 (Item_requirement)
			var req_sprite = req_node.find_child("Item_requirement", true)
			if req_sprite:
				req_sprite.visible = true
				req_sprite.modulate = Constants.get_rarity_border_color(req.get("min_rarity", 0))
			
			# B. 当前拥有品质 (Item_rarity)
			var state = req_states[i] if i < req_states.size() else {}
			var owned_max_rarity = state.get("owned_max_rarity", -1)
			
			var rarity_sprite = req_node.find_child("Item_rarity", true)
			if rarity_sprite:
				if owned_max_rarity != -1:
					rarity_sprite.visible = true
					rarity_sprite.modulate = Constants.get_rarity_border_color(owned_max_rarity)
				else:
					rarity_sprite.visible = false
			
			# 更新状态图标（多选时的高亮/勾选）
			var status_sprite = req_node.find_child("Item_status", true)
			if status_sprite:
				var is_satisfied = state.get("is_selected", false)
				
				status_sprite.visible = is_submit_mode
				status_sprite.texture = preload("res://assets/sprites/icons/tick_green.png") if is_satisfied else preload("res://assets/sprites/icons/tick_empty.png")

		else:
			req_node.visible = false

func update_submission_status(status_array: Array) -> void:
	# This method might be redundant if update_order_display handles states fully
	# But sometimes we update just status without full refresh
	for i in range(4):
		var req_node = items_grid.get_node_or_null("Quest Slot Item_root_" + str(i))
		if not req_node: continue
		
		var status_sprite = req_node.find_child("Item_status", true)
		if not status_sprite: continue
		
		if i < status_array.size():
			status_sprite.visible = true
			# status_sprite.texture = ... (tick if status_array[i] else cross)
		else:
			status_sprite.visible = false

## =====================================================================
## 突出动画系统
## =====================================================================

## 检测订单是否被满足（所有需求都被选中）
func _check_order_satisfied(order: OrderData, req_states: Array) -> bool:
	if not order or req_states.is_empty():
		return false
	
	# 检查所有需求是否都被选中
	for i in range(order.requirements.size()):
		if i >= req_states.size():
			return false
		var state = req_states[i]
		if not state.get("is_selected", false):
			return false
	
	return true

## 设置突出状态（向右突出）
func _set_protrude(protrude: bool) -> void:
	# 停止之前的动画
	if _protrude_tween and _protrude_tween.is_valid():
		_protrude_tween.kill()
		_protrude_tween = null
	
	var target_x: float
	if protrude:
		# 向右突出：在 x 方向上平移
		target_x = _original_position_x + PROTRUDE_OFFSET
	else:
		# 复位到原始位置
		target_x = _original_position_x
	
	# 如果已经在目标位置，不需要动画
	if abs(position.x - target_x) < 0.1:
		return
	
	# 创建动画（只修改 x 坐标，不影响 y）
	_protrude_tween = create_tween()
	_protrude_tween.set_trans(Tween.TRANS_QUAD)
	_protrude_tween.set_ease(Tween.EASE_OUT)
	_protrude_tween.tween_property(self, "position:x", target_x, PROTRUDE_DURATION)

## 复位突出状态
func _reset_protrude() -> void:
	_set_protrude(false)
