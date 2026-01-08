extends Node

## 背包系统：处理物品的添加、移除、合并和回收逻辑。
## 
## 状态管理 (Refactored):
## - 负责持有 inventory, pending_item, selected_slot_index 等状态。
## - 所有背包数据的变更必须通过本系统。

# --- 信号 ---
signal inventory_changed(inventory: Array[ItemInstance])
signal pending_queue_changed(queue: Array[ItemInstance])
signal selection_changed(index: int)
signal multi_selection_changed(indices: Array[int])
signal item_moved(source_index: int, target_index: int)
signal item_swapped(index1: int, index2: int)
signal item_added(item: ItemInstance, index: int)
signal item_replaced(index: int, new_item: ItemInstance, old_item: ItemInstance)
signal item_merged(index: int, new_item: ItemInstance, target_item: ItemInstance)

# --- 状态 ---
var inventory: Array[ItemInstance] = []

var pending_items: Array[ItemInstance] = []
## pending_item 代表当前正在处理的（浮动在鼠标上或等待放置的）物品
var pending_item: ItemInstance:
	get:
		return pending_items[0] if not pending_items.is_empty() else null
	set(v):
		if v == null:
			if not pending_items.is_empty():
				pending_items.pop_front()
				pending_queue_changed.emit(pending_items)
		else:
			if not v in pending_items:
				pending_items.append(v)
				pending_queue_changed.emit(pending_items)

var selected_slot_index: int = -1:
	set(v):
		selected_slot_index = v
		selection_changed.emit(selected_slot_index)

var multi_selected_indices: Array[int] = []
## selected_indices_for_order 是 multi_selected_indices 的别名
var selected_indices_for_order: Array[int]:
	get: return multi_selected_indices
	set(v):
		multi_selected_indices = v
		multi_selection_changed.emit(multi_selected_indices)


func _ready() -> void:
	EventBus.item_obtained.connect(_on_item_obtained)
	
	# 如果 GameConfig 已经加载，初始化背包大小
	# 注意：GameManager 初始化顺序可能在 InventorySystem 之后（Autoload 顺序）
	# 所以这里不强求立即初始化，可以等待 GameManager 调用 initialize_inventory
	if GameManager.game_config:
		initialize_inventory(GameManager.game_config.inventory_size)


# --- 初始化与大小管理 ---

func initialize_inventory(size: int) -> void:
	inventory.clear()
	inventory.resize(size)
	inventory.fill(null)
	inventory_changed.emit(inventory)

func resize_inventory(new_size: int) -> void:
	if inventory.size() != new_size:
		var old_size = inventory.size()
		inventory.resize(new_size)
		# 如果扩容，填充 null
		if new_size > old_size:
			for i in range(old_size, new_size):
				inventory[i] = null
		inventory_changed.emit(inventory)


# --- 核心逻辑 ---

func _on_item_obtained(item: ItemInstance) -> void:
	# 优先自动放入背包
	if _auto_add_to_inventory(item):
		return
		
	# 背包满了，进入待定队列
	self.pending_item = item
	
	# 这里不需要 emit，因为 auto_add 已经 emit 了，或者 pending_item setter emit 了 pending_queue_changed

func _auto_add_to_inventory(item: ItemInstance) -> bool:
	for i in range(inventory.size()):
		if inventory[i] == null:
			inventory[i] = item
			item_added.emit(item, i)
			inventory_changed.emit(inventory)
			return true
	return false

## 处理槽位点击逻辑 (State Machine)
func handle_slot_click(index: int) -> void:
	if index < 0 or index >= inventory.size():
		return
		
	var target_item = inventory[index]
	
	# 如果处于多选模式 (订单提交 或 回收)
	# 注意：GameManager.order_selection_index != -1 对应 SUBMIT 模式
	var is_multi_select_mode = GameManager.order_selection_index != -1 or GameManager.current_ui_mode == Constants.UIMode.RECYCLE
	
	if is_multi_select_mode:
		if target_item == null:
			return # 只能选择有物品的格子
			
		if index in multi_selected_indices:
			multi_selected_indices.erase(index)
		else:
			multi_selected_indices.append(index)
		
		multi_selection_changed.emit(multi_selected_indices)
		# 为了兼容旧 UI 监听，可能还需要通知 inventory_changed？
		# 暂时不需要，选中状态通常是独立的。但如果 UI 是根据 inventory 重绘选中框，可能需要。
		return

	var pending = self.pending_item
	
	if pending != null:
		# 场景 A: 玩家正拿着新抽到的物品
		if target_item == null:
			# 1. 目标格子为空 -> 放入
			inventory[index] = pending
			self.pending_item = null
			item_added.emit(pending, index)
		else:
			# 2. 目标格子有物品 -> 判定合并
			if can_merge(pending, target_item):
				# 合并
				_perform_merge(pending, target_item, index)
				self.pending_item = null
			else:
				# 替换/回收: 旧物品被挤掉
				recycle_item_instance(target_item)
				inventory[index] = pending
				item_replaced.emit(index, pending, target_item)
				self.pending_item = null
	else:
		# 场景 B: 玩家处于整理模式 (pending_item == null)
		var selected_idx = selected_slot_index
		
		if selected_idx == -1:
			# 1. 当前没有选中任何格子 -> 选中该格子 (如果有物品)
			if target_item != null:
				self.selected_slot_index = index
		elif selected_idx == index:
			# 2. 当前已选中同一个格子 -> 取消选中
			self.selected_slot_index = -1
		else:
			# 3. 当前已选中另一个格子
			var source_item = inventory[selected_idx]
			if source_item == null:
				self.selected_slot_index = -1
				return
				
			if target_item == null:
				# 目标为空 -> 移动
				inventory[index] = source_item
				inventory[selected_idx] = null
				item_moved.emit(selected_idx, index)
			else:
				# 判定合并: 检查是否满足合并规则
				if can_merge(source_item, target_item):
					# 合并
					_perform_merge(source_item, target_item, index)
					inventory[selected_idx] = null
					item_moved.emit(selected_idx, index)
				else:
					# 交换
					inventory[index] = source_item
					inventory[selected_idx] = target_item
					item_swapped.emit(selected_idx, index)
					
			self.selected_slot_index = -1
	
	inventory_changed.emit(inventory)

## 判定是否可以合并
func can_merge(item_a: ItemInstance, item_b: ItemInstance) -> bool:
	if item_a == null or item_b == null: return false
	if item_a.item_data.id != item_b.item_data.id: return false
	if item_a.rarity != item_b.rarity: return false
	if item_a.rarity >= Constants.Rarity.MYTHIC: return false
	if item_a.sterile or item_b.sterile: return false
	
	# 检查 UnlockManager 合成解锁状态
	if not UnlockManager.is_unlocked(UnlockManager.Feature.MERGE):
		return false
	if item_a.rarity >= UnlockManager.merge_limit:
		return false
		
	return true

## 执行合并
func _perform_merge(item_a: ItemInstance, item_b: ItemInstance, target_index: int) -> void:
	var next_rarity = item_a.rarity + 1
	var new_item = ItemInstance.new(item_a.item_data, next_rarity)
	inventory[target_index] = new_item
	
	# Emit merge signal with the item that was in the slot (item_b) as the target context
	item_merged.emit(target_index, new_item, item_b)

## 回收物品实例
func recycle_item_instance(item: ItemInstance) -> void:
	if item == null: return
	
	var context = RecycleContext.new()
	context.item = item
	context.reward_gold = Constants.rarity_recycle_value(item.rarity)
	
	EventBus.game_event.emit(&"recycle_requested", context)
	
	if context.reward_gold > 0:
		GameManager.add_gold(context.reward_gold)
	if context.reward_tickets > 0:
		GameManager.add_tickets(context.reward_tickets)
		
	EventBus.game_event.emit(&"recycle_finished", context)

## 回收指定索引的物品
func recycle_item(index: int) -> void:
	if index < 0 or index >= inventory.size(): return
	var item = inventory[index]
	if item != null:
		recycle_item_instance(item)
		inventory[index] = null
		inventory_changed.emit(inventory)

## 批量删除物品
func remove_items(items_to_remove: Array[ItemInstance]) -> void:
	var changed = false
	for i in range(inventory.size()):
		if inventory[i] in items_to_remove:
			inventory[i] = null
			changed = true
	if changed:
		inventory_changed.emit(inventory)

## 检查背包中是否包含指定物品
func has_item_data(item_data: ItemData) -> bool:
	if item_data == null: return false
	for it in inventory:
		if it != null and it.item_data.id == item_data.id:
			return true
	return false
