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
		var old = selected_slot_index
		selected_slot_index = v
		selection_changed.emit(selected_slot_index)
		
		if v != -1 and v != old:
			if v >= 0 and v < inventory.size():
				var item = inventory[v]
				if item:
					EventBus.game_event.emit(&"item_selected", item)

var multi_selected_indices: Array[int] = []
## selected_indices_for_order 是 multi_selected_indices 的别名
var selected_indices_for_order: Array[int]:
	get: return multi_selected_indices
	set(v):
		multi_selected_indices = v
		multi_selection_changed.emit(multi_selected_indices)

enum InteractionMode {NORMAL, MULTI_SELECT}
var interaction_mode: InteractionMode = InteractionMode.NORMAL

func _ready() -> void:
	EventBus.item_obtained.connect(_on_item_obtained)

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
	# 核心：为了维持队列顺序，所有新获得的物品必须先进待定队列
	# 这可以防止“插队”现象：即 Item 1 还在队列等待替换，而 Item 2 却尝试直接进入背包
	self.pending_item = item
	
	# 清除选中状态，因为新物品获取是与之前的整理操作无关的新上下文
	if selected_slot_index != -1:
		self.selected_slot_index = -1
		
	# 触发自动处理流程。如果背包有空位且满足种类限制，物品会从队列首部自动飞入背包
	try_auto_add_pending()

func add_item_instance(item: ItemInstance) -> bool:
	for i in range(inventory.size()):
		if inventory[i] == null:
			inventory[i] = item
			item_added.emit(item, i)
			inventory_changed.emit(inventory)
			EventBus.orders_updated.emit(OrderSystem.current_orders) # 触发订单UI更新，以刷新拥有状态
			return true
	return false

## 处理槽位点击逻辑 (State Machine)
func handle_slot_click(index: int) -> void:
	if index < 0 or index >= inventory.size():
		return
		
	var target_item = inventory[index]
	
	if interaction_mode == InteractionMode.MULTI_SELECT:
		if target_item == null:
			return # 只能选择有物品的格子
			
		if index in multi_selected_indices:
			multi_selected_indices.erase(index)
		else:
			multi_selected_indices.append(index)
			EventBus.game_event.emit(&"item_selected", target_item)
		
		multi_selection_changed.emit(multi_selected_indices)
		return

	var pending = self.pending_item
	
	if pending != null:
		# 场景 A: 玩家正拿着新抽到的物品
		if target_item == null:
			# ERA_3: 如果物品因为种类限制而待定，必须替换已有物品，不能放入空槽
			if would_exceed_type_limit(pending):
				# 拒绝操作，不做任何处理
				# TODO: 可以在这里触发一个提示音效或视觉反馈
				return
			
			# 1. 目标格子为空 -> 放入
			inventory[index] = pending
			self.pending_item = null
			item_added.emit(pending, index)
			
			# 尝试自动填充剩余的待定项
			try_auto_add_pending()
		else:
			# 2. 目标格子有物品 -> 判定合并
			if can_merge(pending, target_item):
				# 合并
				_perform_merge(pending, target_item, index)
				self.pending_item = null
			else:
				# 替换/回收
				# ERA_3: 如果当前物品是因为超出种类限制而待定，且玩家选择了一个已有的种类进行替换
				# 则回收该种类的所有物品，以确保真正腾出一个种类位
				var is_type_limited = would_exceed_type_limit(pending)
				
				if is_type_limited:
					# 批量回收所有同名物品
					var target_id = target_item.item_data.id
					recycle_all_by_name(target_id)
					
					# 将新物品放入当前点击的槽位（该槽位在 recycle_all_by_name 中已被置空）
					inventory[index] = pending
					item_replaced.emit(index, pending, target_item) # 这里传递的 old_item 只是为了动画效果
				else:
					# 正常单个替换 - 发出 item_recycled 信号以触发回收相关逻辑（如兔子动画）
					EventBus.item_recycled.emit(index, target_item)
					recycle_item_instance(target_item)
					inventory[index] = pending
					item_replaced.emit(index, pending, target_item)
				
				# 关键：如果有选中，清除它
				if selected_slot_index == index:
					self.selected_slot_index = -1
				self.pending_item = null
				
				# 尝试自动填充剩余的待定项 (针对稀碎奖池/批量回收后的空间释放)
				try_auto_add_pending()
		return
	else:
		# 场景 B: 玩家处于整理模式 (pending_item == null)
		var selected_idx = selected_slot_index
		
		if selected_idx == -1:
			# 1. 当前没有选中任何格子 -> 选中该格子 (如果有物品)
			if target_item != null:
				self.selected_slot_index = index
		elif selected_idx == index:
			# 2. 当前已选中同一个格子 -> 取消选中 (原地放下)
			self.selected_slot_index = -1
			if target_item != null:
				EventBus.game_event.emit(&"item_placed", target_item)
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
					var original_source = source_item
					var original_target = target_item
					
					inventory[index] = original_source
					inventory[selected_idx] = original_target
					
					# 关键修复：信号必须传递交换瞬间的原始对应关系，否则 VFX 会因数据已变而错位
					item_swapped.emit(selected_idx, index)
					
			self.selected_slot_index = -1
	
	inventory_changed.emit(inventory)
	EventBus.orders_updated.emit(OrderSystem.current_orders) # 触发订单UI更新，以刷新拥有状态

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
		
	# ERA_4: 垃圾袋（过期物品）不能合成
	if item_a.is_expired or item_b.is_expired:
		return false
	
	return true

## 执行合并
func _perform_merge(item_a: ItemInstance, item_b: ItemInstance, target_index: int) -> void:
	var next_rarity = item_a.rarity + 1
	
	# ERA_4: 保质期取两者中较长的值
	var merged_shelf_life = maxi(item_a.shelf_life, item_b.shelf_life)
	var new_item = ItemInstance.new(item_a.item_data, next_rarity, false, merged_shelf_life)
	
	inventory[target_index] = new_item
	
	# Emit merge signal with the item that was in the slot (item_b) as the target context
	item_merged.emit(target_index, new_item, item_b)
	EventBus.game_event.emit(&"item_placed", new_item)

## 回收物品实例
func recycle_item_instance(item: ItemInstance) -> void:
	if item == null: return
	
	var context = RecycleContext.new()
	context.item = item
	context.reward_gold = Constants.rarity_recycle_value(item.rarity)
	
	EventBus.game_event.emit(&"recycle_requested", context)
	
	if context.reward_gold > 0:
		GameManager.add_gold(context.reward_gold)
		
	EventBus.game_event.emit(&"recycle_finished", context)


## 回收背包中所有同名物品（用于 ERA_3 种类替换）
func recycle_all_by_name(item_id: StringName) -> int:
	var count = 0
	# 先收集索引，避免在循环中修改数组导致的问题
	var indices = get_indices_by_name(item_id)
	
	for idx in indices:
		var item = inventory[idx]
		if item != null:
			# 为每个被回收的物品触发单独的信号，以便 UI 层可以播放回收动画
			# 注意：这里先发信号，再清空槽位，这样 UI 可以获取到槽位信息
			EventBus.item_recycled.emit(idx, item)
			
			recycle_item_instance(item)
			inventory[idx] = null
			count += 1
			
	if count > 0:
		inventory_changed.emit(inventory)
		EventBus.orders_updated.emit(OrderSystem.current_orders)
		
	return count


## 尝试自动将待定队列中的物品放入背包（当空间或种类位释放时）
func try_auto_add_pending() -> void:
	# 注意：pending_item 的 setter/getter 逻辑会自动处理 pending_items 数组
	while not pending_items.is_empty():
		var next_item = pending_items[0]
		
		# 检查是否满足种类限制且有空槽
		if not would_exceed_type_limit(next_item) and _has_empty_slot():
			var added = add_item_instance(next_item)
			if added:
				# 成功添加，通过设置 pending_item = null 来触发 pop_front
				self.pending_item = null
				continue
		
		# 如果不能自动添加（种类限制或没格子），则停止自动处理，等待玩家手动交互
		break


func _has_empty_slot() -> bool:
	for item in inventory:
		if item == null: return true
	return false

## 回收指定索引的物品
func recycle_item(index: int) -> void:
	if index < 0 or index >= inventory.size(): return
	var item = inventory[index]
	if item != null:
		EventBus.item_recycled.emit(index, item)
		recycle_item_instance(item)
		inventory[index] = null
		if selected_slot_index == index:
			self.selected_slot_index = -1
		inventory_changed.emit(inventory)
		EventBus.orders_updated.emit(OrderSystem.current_orders) # 触发订单UI更新
		
		# 尝试自动填充剩余的待定项
		try_auto_add_pending()

## 批量删除物品
func remove_items(items_to_remove: Array[ItemInstance]) -> void:
	var changed = false
	for i in range(inventory.size()):
		if inventory[i] in items_to_remove:
			inventory[i] = null
			changed = true
	if changed:
		inventory_changed.emit(inventory)
		EventBus.orders_updated.emit(OrderSystem.current_orders) # 触发订单UI更新
		
		# 尝试自动填充剩余的待定项
		try_auto_add_pending()

## 检查背包中是否包含指定物品
func has_item_data(item_data: ItemData) -> bool:
	if item_data == null: return false
	for it in inventory:
		if it != null and not it.is_expired and it.item_data.id == item_data.id:
			return true
	return false

## 获取背包中某类物品的最高稀有度，如果不存在则返回 -1
func get_max_rarity_for_item(item_id: StringName) -> int:
	var max_r = -1
	for item in inventory:
		if item != null and not item.is_expired and item.item_data.id == item_id:
			if item.rarity > max_r:
				max_r = item.rarity
	return max_r


# --- ERA_3: 种类限制相关方法 ---

## 获取背包中所有不同的物品名称
func get_unique_item_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for item in inventory:
		if item != null and not item.is_expired and item.item_data.id not in names:
			names.append(item.item_data.id)
	return names


## 检查添加新物品是否会超出种类限制
func would_exceed_type_limit(new_item: ItemInstance) -> bool:
	var cfg = EraManager.current_config if EraManager else null
	if not cfg:
		return false
	
	var type_limit_effect = cfg.get_effect_of_type("ItemTypeLimitEffect")
	if not type_limit_effect:
		return false
	
	return type_limit_effect.would_exceed_limit(self, new_item)


## 获取指定物品名称的所有背包槽位索引
func get_indices_by_name(item_id: StringName) -> Array[int]:
	var indices: Array[int] = []
	for i in range(inventory.size()):
		if inventory[i] != null and not inventory[i].is_expired and inventory[i].item_data.id == item_id:
			indices.append(i)
	return indices


## 获取同名物品的总回收价值
func get_total_recycle_value_for_name(item_id: StringName) -> int:
	var total: int = 0
	for item in inventory:
		if item != null and not item.is_expired and item.item_data.id == item_id:
			total += Constants.rarity_recycle_value(item.rarity)
	return total
