extends Node

## 背包系统：处理物品的添加、移除、合成和回收逻辑。

func _ready() -> void:
	EventBus.item_obtained.connect(_on_item_obtained)

func _on_item_obtained(item: ItemInstance) -> void:
	# 优先自动放入背包
	if _auto_add_to_inventory(item):
		return
		
	# 背包满了，进入待定队列
	# 注意：GameManager.pending_item 的 setter 现在会自动推入队列
	GameManager.pending_item = item
	
	GameManager.inventory_changed.emit(GameManager.inventory)

func _auto_add_to_inventory(item: ItemInstance) -> bool:
	for i in range(GameManager.inventory.size()):
		if GameManager.inventory[i] == null:
			GameManager.inventory[i] = item
			GameManager.inventory_changed.emit(GameManager.inventory)
			return true
	return false

## 处理槽位点击逻辑 (State Machine)
func handle_slot_click(index: int) -> void:
	if index < 0 or index >= GameManager.inventory.size():
		return
		
	var target_item = GameManager.inventory[index]
	
	# 如果处于订单提交选择模式
	if GameManager.order_selection_index != -1:
		if target_item == null:
			return # 只能选择有物品的格子
			
		if index in GameManager.selected_indices_for_order:
			GameManager.selected_indices_for_order.erase(index)
		else:
			GameManager.selected_indices_for_order.append(index)
		
		GameManager.inventory_changed.emit(GameManager.inventory)
		return

	var pending = GameManager.pending_item
	
	if pending != null:
		# 场景 A: 玩家正拿着新抽到的物品
		if target_item == null:
			# 1. 目标格子为空 -> 放入
			GameManager.inventory[index] = pending
			GameManager.pending_item = null
		else:
			# 2. 目标格子有物品 -> 判定合成
			if can_synthesize(pending, target_item):
				# 合成
				_perform_synthesis(pending, target_item, index)
				GameManager.pending_item = null
			else:
				# 替换/回收: 旧物品被挤掉
				salvage_item_instance(target_item)
				GameManager.inventory[index] = pending
				GameManager.pending_item = null
	else:
		# 场景 B: 玩家处于整理模式 (pending_item == null)
		var selected_idx = GameManager.selected_slot_index
		
		if selected_idx == -1:
			# 1. 当前没有选中任何格子 -> 选中该格子 (如果有物品)
			if target_item != null:
				GameManager.selected_slot_index = index
		elif selected_idx == index:
			# 2. 当前已选中同一个格子 -> 取消选中
			GameManager.selected_slot_index = -1
		else:
			# 3. 当前已选中另一个格子
			var source_item = GameManager.inventory[selected_idx]
			if source_item == null:
				GameManager.selected_slot_index = -1
				return
				
			if target_item == null:
				# 目标为空 -> 移动
				GameManager.inventory[index] = source_item
				GameManager.inventory[selected_idx] = null
			else:
				# 判定合成: 检查是否满足合成规则
				if can_synthesize(source_item, target_item):
					# 合成
					_perform_synthesis(source_item, target_item, index)
					GameManager.inventory[selected_idx] = null
				else:
					# 交换
					GameManager.inventory[index] = source_item
					GameManager.inventory[selected_idx] = target_item
					
			GameManager.selected_slot_index = -1
	
	GameManager.inventory_changed.emit(GameManager.inventory)

## 判定是否可以合成
func can_synthesize(item_a: ItemInstance, item_b: ItemInstance) -> bool:
	if item_a == null or item_b == null: return false
	if item_a.item_data.id != item_b.item_data.id: return false
	if item_a.rarity != item_b.rarity: return false
	if item_a.rarity >= Constants.Rarity.MYTHIC: return false
	if item_a.sterile or item_b.sterile: return false
	
	# 检查阶段限制
	var stage_data = GameManager.current_stage_data
	if stage_data != null:
		if not stage_data.has_merge: return false
		if item_a.rarity >= stage_data.merge_limit: return false
		
	return true

## 执行合成
func _perform_synthesis(item_a: ItemInstance, _item_b: ItemInstance, target_index: int) -> void:
	var next_rarity = item_a.rarity + 1
	var new_item = ItemInstance.new(item_a.item_data, next_rarity)
	GameManager.inventory[target_index] = new_item

## 回收物品实例
func salvage_item_instance(item: ItemInstance) -> void:
	if item == null: return
	
	var context = SalvageContext.new()
	context.item = item
	context.reward_gold = Constants.rarity_salvage_value(item.rarity)
	
	EventBus.game_event.emit(&"salvage_requested", context)
	
	if context.reward_gold > 0:
		GameManager.add_gold(context.reward_gold)
	if context.reward_tickets > 0:
		GameManager.add_tickets(context.reward_tickets)
		
	EventBus.game_event.emit(&"salvage_finished", context)

## 回收指定索引的物品
func salvage_item(index: int) -> void:
	var item = GameManager.inventory[index]
	if item != null:
		salvage_item_instance(item)
		GameManager.inventory[index] = null
		GameManager.inventory_changed.emit(GameManager.inventory)
