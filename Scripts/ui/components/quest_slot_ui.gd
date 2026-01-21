class_name QuestSlotUI
extends BaseSlotUI

@onready var reward_label: RichTextLabel = find_child("Quest Reward Label", true)
@onready var reward_icon: TextureRect = find_child("Quest Reward Icon", true)
@onready var items_grid: HBoxContainer = find_child("Quest Slot Items Grid", true)
@onready var refresh_label: RichTextLabel = find_child("Refresh Count Label", true)
@onready var refresh_button: TextureButton = find_child("Refresh Button", true)

var background_setter: Node2D

var order_index: int = -1
var is_submit_mode: bool = false
var _current_order: OrderData = null
var _original_mouse_filter: Control.MouseFilter = Control.MOUSE_FILTER_STOP
var _original_background_color: Color = Color.WHITE

## 突出动画相关
const PROTRUDE_OFFSET: float = 100.0 # 向右突出的像素距离
const PROTRUDE_DURATION: float = 0.2 # 动画时长
var _protrude_tween: Tween = null
var _original_position_x: float = 0.0

## Rarity 旋转动画相关（key: 需求索引, value: Tween）
var _rarity_rotation_tweens: Dictionary = {}

func _ready() -> void:
	super._ready()
	background_setter = find_child("Quest Slot_background", true)
	if not background_setter:
		background_setter = find_child("Main Quest Slot_background", true)
		
	if background_setter:
		_original_background_color = background_setter.color

func setup(index: int) -> void:
	order_index = index
	# 订单槽位初始状态是开启的
	if anim_player.has_animation("lid_open"):
		anim_player.play("lid_open")
	
	if refresh_button:
		refresh_button.pressed.connect(_on_refresh_button_pressed)
		# 保存原始的 mouse_filter 值，用于恢复交互状态
		_original_mouse_filter = refresh_button.mouse_filter
	
	# 记录原始 position.x（只记录 x 坐标，y 由 VBoxContainer 管理）
	_original_position_x = position.x

func get_order() -> OrderData:
	return _current_order

func set_locked(locked: bool) -> void:
	is_locked = locked
	if refresh_button:
		# 如果订单本身已经没次数了，保持禁用；否则根据锁定状态设置
		var has_uses = _current_order and _current_order.refresh_count > 0
		refresh_button.disabled = locked or not has_uses

func _on_refresh_button_pressed() -> void:
	if is_locked: return
	if order_index != -1:
		EventBus.game_event.emit(&"order_refresh_button_pressed", null)
		EventBus.game_event.emit(&"order_refresh_requested", ContextProxy.new({"index": order_index - 1}))

## 设置刷新按钮的视觉状态（按下保持/弹起）和交互锁定
func set_refresh_visual(active: bool) -> void:
	if refresh_button:
		if active:
			# 刷新动画期间：保持按下视觉 + 通过 mouse_filter 锁定交互（不改变视觉）
			refresh_button.toggle_mode = true
			refresh_button.set_pressed_no_signal(true)
			refresh_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			# 动画结束后：恢复普通按钮模式和交互状态
			refresh_button.toggle_mode = false
			refresh_button.mouse_filter = _original_mouse_filter

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
	
	if reward_icon:
		reward_icon.texture = preload("res://assets/sprites/icons/money.png")
	
	if refresh_label:
		refresh_label.text = str(order_data.refresh_count)
	
	if refresh_button:
		refresh_button.disabled = order_data.refresh_count <= 0
	
	_update_requirements(order_data.requirements, req_states)
	
	# 1. 判定是否满足全部条件
	var is_satisfied = false
	if is_submit_mode:
		# 提交模式：根据当前已选中的物品判定
		is_satisfied = _check_order_satisfied(order_data, req_states)
		_set_protrude(is_satisfied)
	else:
		# 非提交模式：根据背包中是否持有足够物品判定
		is_satisfied = order_data.can_fulfill(InventorySystem.inventory)
		_reset_protrude()
	
	# 2. 更新背景颜色
	_update_background_color(is_satisfied)
	
	# 3. 更新奖励显示
	if reward_label:
		if is_submit_mode and is_satisfied:
			var selected_items: Array[ItemInstance] = []
			for idx in InventorySystem.multi_selected_indices:
				if idx >= 0 and idx < InventorySystem.inventory.size():
					var item = InventorySystem.inventory[idx]
					if item:
						selected_items.append(item)
			
			var preview = order_data.calculate_preview_rewards(selected_items)
			if preview.gold != order_data.reward_gold:
				reward_label.text = "%d[font_size=48]←%d[/font_size]" % [preview.gold, order_data.reward_gold]
			else:
				reward_label.text = str(order_data.reward_gold)
		else:
			reward_label.text = str(order_data.reward_gold)

func _update_background_color(satisfied: bool) -> void:
	if not background_setter: return
	
	if satisfied:
		background_setter.color = Color("#9ee967")
	else:
		background_setter.color = _original_background_color

func _update_requirements(reqs: Array[Dictionary], req_states: Array) -> void:
	# 适配不同名字的 Grid (Quest Slot Items Grid 或 Main Quest Slot Items Grid)
	var grid = items_grid
	var item_root_prefix = "Quest Slot Item_root_"
	if not grid:
		grid = find_child("Main Quest Slot Items Grid", true)
		item_root_prefix = "Main Quest Slot Item_root_"
	
	if not grid: return

	for i in range(4):
		# 1. 改为使用 find_child 增加对层级变化的鲁棒性
		var req_node = grid.find_child(item_root_prefix + str(i), true)
		if not req_node: continue
		
		if i < reqs.size():
			req_node.visible = true
			var req = reqs[i]
			var item_id = req.get("item_id", &"")
			var item_data = GameManager.get_item_data(item_id)
			var min_rarity = req.get("min_rarity", 0)
			
			# 获取当前拥有品质状态
			var state = req_states[i] if i < req_states.size() else {}
			var owned_max_rarity = state.get("owned_max_rarity", -1)
			
			# 判断品质是否达标
			var is_rarity_satisfied = owned_max_rarity >= min_rarity
			
			var icon = req_node.find_child("Item_icon", true)
			if icon and item_data:
				# 根据品质达标与否切换 sprite sheet（正常版 vs 描线版）
				_update_icon_sprite(icon, item_data, is_rarity_satisfied)
			
			# A. 需求品质 (Item_requirement)
			var req_sprite = req_node.find_child("Item_requirement", true)
			if req_sprite:
				req_sprite.visible = true
				req_sprite.modulate = Constants.get_rarity_border_color(min_rarity)
			
			# B. 当前拥有品质 (Item_rarity) - 带旋转动画
			var rarity_sprite = req_node.find_child("Item_rarity", true)
			if rarity_sprite:
				if owned_max_rarity != -1:
					rarity_sprite.visible = true
					rarity_sprite.modulate = Constants.get_rarity_border_color(owned_max_rarity)
					# 启动旋转动画
					_start_rarity_rotation(i, rarity_sprite)
				else:
					rarity_sprite.visible = false
					# 停止旋转动画
					_stop_rarity_rotation(i, rarity_sprite)
			
			# 更新状态图标（多选时的高亮/勾选）
			# 绿色勾需要同时满足：物品被选中 + 品质达标
			var status_sprite = req_node.find_child("Item_status", true)
			if status_sprite:
				var is_quality_met = state.get("is_quality_met", false)
				
				status_sprite.visible = is_submit_mode
				status_sprite.texture = preload("res://assets/sprites/icons/tick_green.png") if is_quality_met else preload("res://assets/sprites/icons/tick_empty.png")

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
## Item Icon Sprite 切换（品质不达标时使用描线版 sprite sheet）
## =====================================================================

## 正常版和描线版 sprite sheet 的预加载
const NORMAL_SPRITE_SHEET: Texture2D = preload("res://assets/sprites/icons/items/item_shape_centered.png")
const NOMEET_SPRITE_SHEET: Texture2D = preload("res://assets/sprites/icons/items/items_shape_centered_nomeet.PNG")

## 更新 Item_icon 的 sprite sheet（品质不达标时使用描线版）
## [param icon]: 物品图标 Sprite2D
## [param item_data]: 物品数据（用于获取正确的帧索引）
## [param is_satisfied]: 品质是否达标
func _update_icon_sprite(icon: Sprite2D, item_data: ItemData, is_satisfied: bool) -> void:
	if not icon or not item_data: return
	
	# 确保 shader material 的 width 初始化为 0（描边宽度默认关闭）
	var shader_material = icon.material as ShaderMaterial
	if shader_material:
		# 确保 material 是独立实例（避免共享 material 导致的问题）
		if not shader_material.resource_local_to_scene:
			shader_material = shader_material.duplicate() as ShaderMaterial
			shader_material.resource_local_to_scene = true
			icon.material = shader_material
			# 初始化时确保描边宽度为 0
			shader_material.set_shader_parameter("width", 0.0)
	
	# 根据品质是否达标选择 sprite sheet
	if is_satisfied:
		icon.texture = item_data.icon # 使用原始图标（正常版）
	else:
		# 使用描线版 sprite sheet，需要获取帧索引来正确显示
		# 由于 item_data.icon 是 AtlasTexture，我们需要使用相同的帧索引切换到描线版
		_set_icon_from_nomeet_sheet(icon, item_data)


## 从描线版 sprite sheet 设置图标（保持与原始图标相同的 region）
func _set_icon_from_nomeet_sheet(icon: Sprite2D, item_data: ItemData) -> void:
	if not item_data.icon: return
	
	# 获取原始图标的 AtlasTexture region 信息
	var original_atlas: AtlasTexture = item_data.icon as AtlasTexture
	if not original_atlas:
		# 如果原始图标不是 AtlasTexture，直接使用描线版整张图（fallback）
		icon.texture = NOMEET_SPRITE_SHEET
		return
	
	# 创建新的 AtlasTexture，使用描线版 sprite sheet 但保持相同的 region
	var nomeet_atlas := AtlasTexture.new()
	nomeet_atlas.atlas = NOMEET_SPRITE_SHEET
	nomeet_atlas.region = original_atlas.region
	nomeet_atlas.margin = original_atlas.margin
	nomeet_atlas.filter_clip = original_atlas.filter_clip
	
	icon.texture = nomeet_atlas

## =====================================================================
## 突出动画系统
## =====================================================================

## 检测订单是否被满足（所有需求都被选中且品质达标）
func _check_order_satisfied(order: OrderData, req_states: Array) -> bool:
	if not order or req_states.is_empty():
		return false
	
	# 检查所有需求是否都品质达标
	for i in range(order.requirements.size()):
		if i >= req_states.size():
			return false
		
		var state = req_states[i]
		# 使用 is_quality_met：物品被选中 + 品质达标
		if not state.get("is_quality_met", false):
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

## =====================================================================
## Rarity 旋转动画系统
## =====================================================================

## 启动指定需求位置的 rarity 旋转动画
func _start_rarity_rotation(req_index: int, rarity_sprite: Sprite2D) -> void:
	# 检查是否已有有效的旋转动画
	var existing_tween = _rarity_rotation_tweens.get(req_index)
	if existing_tween and existing_tween.is_valid() and existing_tween.is_running():
		return # 已经在旋转，不需要重新创建
	
	# 停止旧的动画（如果存在）
	if existing_tween:
		existing_tween.kill()
	
	# 创建新的旋转动画
	var rotation_tween = create_tween()
	rotation_tween.set_loops() # 无限循环
	rotation_tween.tween_property(rarity_sprite, "rotation", TAU, 3.0) \
		.from(0.0) \
		.set_trans(Tween.TRANS_LINEAR)
	
	_rarity_rotation_tweens[req_index] = rotation_tween

## 停止指定需求位置的 rarity 旋转动画
func _stop_rarity_rotation(req_index: int, rarity_sprite: Sprite2D) -> void:
	var existing_tween = _rarity_rotation_tweens.get(req_index)
	if existing_tween:
		existing_tween.kill()
		_rarity_rotation_tweens.erase(req_index)
	
	# 重置旋转角度
	if rarity_sprite:
		rarity_sprite.rotation = 0.0
