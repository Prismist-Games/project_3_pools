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


func _ready() -> void:
	# 监听全局信号
	GameManager.gold_changed.connect(_on_gold_changed)
	GameManager.tickets_changed.connect(_on_tickets_changed)
	GameManager.mainline_stage_changed.connect(_on_mainline_stage_changed)
	GameManager.inventory_changed.connect(_on_inventory_changed)
	GameManager.skills_changed.connect(_on_skills_changed)
	
	EventBus.pools_refreshed.connect(_on_pools_refreshed)
	EventBus.orders_updated.connect(_on_orders_updated)
	
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
	# 简单处理：清空并重新填满（实际可以做池化优化）
	for child in inventory_grid.get_children():
		child.queue_free()
		
	for i in items.size():
		var slot = INVENTORY_SLOT_SCENE.instantiate()
		inventory_grid.add_child(slot)
		slot.setup(items[i], i)
		slot.salvage_requested.connect(_on_item_salvage_requested)
		slot.synthesis_requested.connect(_on_item_synthesis_requested)


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


func _on_item_synthesis_requested(idx1: int, idx2: int) -> void:
	inventory_system.synthesize_items(idx1, idx2)

