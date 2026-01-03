extends Control

## 游戏主 UI：管理各面板与系统的交互。

@onready var gold_label: Label = %GoldLabel
@onready var tickets_label: Label = %TicketsLabel
@onready var stage_label: Label = %StageLabel

@onready var pools_container: Container = %PoolsContainer
@onready var orders_container: Container = %OrdersContainer
@onready var inventory_grid: Container = %InventoryGrid
@onready var skills_container: Container = %SkillsContainer

@onready var pool_system: PoolSystem = $PoolSystem
@onready var inventory_system: InventorySystem = $InventorySystem
@onready var order_system: OrderSystem = $OrderSystem

const POOL_CARD_SCENE = preload("res://scenes/ui/pool_card.tscn")
const ORDER_CARD_SCENE = preload("res://scenes/ui/order_card.tscn")
const INVENTORY_SLOT_SCENE = preload("res://scenes/ui/inventory_slot.tscn")
const SKILL_ICON_SCENE = preload("res://scenes/ui/skill_icon.tscn")
const InventorySlotUI = preload("res://scripts/ui/inventory_slot_ui.gd")


func _ready() -> void:
	# 监听全局信号
	GameManager.gold_changed.connect(_on_gold_changed)
	GameManager.tickets_changed.connect(_on_tickets_changed)
	GameManager.mainline_stage_changed.connect(_on_mainline_stage_changed)
	GameManager.inventory_changed.connect(_on_inventory_changed)
	GameManager.skills_changed.connect(_on_skills_changed)
	
	EventBus.pools_refreshed.connect(_on_pools_refreshed)
	EventBus.orders_updated.connect(_on_orders_updated)
	EventBus.modal_requested.connect(_on_modal_requested)
	EventBus.game_event.connect(_on_game_event)
	
	# 初始化显示
	_on_gold_changed(GameManager.gold)
	_on_tickets_changed(GameManager.tickets)
	_on_mainline_stage_changed(GameManager.mainline_stage)
	_on_inventory_changed(GameManager.inventory)
	_on_skills_changed(GameManager.current_skills)


func _on_gold_changed(val: int) -> void:
	gold_label.text = "金币: %d" % val


func _on_tickets_changed(val: int) -> void:
	tickets_label.text = "奖券: %d" % val


func _on_mainline_stage_changed(val: int) -> void:
	stage_label.text = "阶段: %d" % val


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


func _on_inventory_changed(items: Array) -> void:
	# 更新背包格子
	for child in inventory_grid.get_children():
		child.queue_free()
		
	var total_slots = 6
	if GameManager.current_stage_data != null:
		total_slots = GameManager.current_stage_data.inventory_size
		
	for i in total_slots:
		var slot = INVENTORY_SLOT_SCENE.instantiate()
		inventory_grid.add_child(slot)
		
		if i < items.size():
			slot.setup(items[i], i)
			slot.salvage_requested.connect(_on_item_salvage_requested)
			slot.merge_requested.connect(_on_item_merge_requested)
		else:
			slot.setup(null, i)


func _on_skills_changed(skills: Array) -> void:
	for child in skills_container.get_children():
		child.queue_free()
		
	for skill in skills:
		var icon = SKILL_ICON_SCENE.instantiate()
		skills_container.add_child(icon)
		icon.setup(skill)


func _on_pool_draw_requested(index: int) -> void:
	pool_system.draw_from_pool(index)


func _on_order_submit_requested(index: int) -> void:
	order_system.submit_order(index)


func _on_order_refresh_requested(index: int) -> void:
	order_system.refresh_order(index)


func _on_item_salvage_requested(index: int) -> void:
	inventory_system.salvage_item(index)


func _on_item_merge_requested(idx1: int, idx2: int) -> void:
	inventory_system.merge_items(idx1, idx2)


func _on_game_event(event_id: StringName, payload: Variant) -> void:
	if event_id == &"enter_selection_mode":
		InventorySlotUI.selection_mode_data = payload
		_on_inventory_changed(GameManager.inventory)


func _on_modal_requested(modal_id: StringName, payload: Dictionary) -> void:
	match modal_id:
		&"precise_selection":
			_handle_precise_selection(payload)
		&"targeted_selection":
			_handle_targeted_selection(payload)


func _handle_precise_selection(payload: Dictionary) -> void:
	var items: Array[ItemInstance] = payload.get("items", [])
	var callback: Callable = payload.get("callback")
	
	var dialog = ConfirmationDialog.new()
	dialog.title = "精准抽奖：二选一"
	dialog.dialog_text = "请选择一个物品："
	add_child(dialog)
	
	var h_box = HBoxContainer.new()
	dialog.add_child(h_box)
	
	for item in items:
		var btn = Button.new()
		btn.text = "[%s] %s" % [Constants.get_script().rarity_display_name(item.rarity), item.get_display_name()]
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
	var items: Array[ItemData] = payload.get("items", [])
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

