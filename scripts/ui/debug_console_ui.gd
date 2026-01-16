extends PanelContainer

## 调试控制台 UI
## 提供可视化界面手动控制 UnlockManager 的功能解锁状态。

@onready var affix_container: HFlowContainer = %AffixContainer
@onready var merge_limit_option: OptionButton = %MergeLimitOption
@onready var inventory_size_spinbox: SpinBox = %InventorySizeSpinBox
@onready var order_limit_spinbox: SpinBox = %OrderLimitSpinBox
@onready var order_item_req_min_spinbox: SpinBox = %OrderItemReqMinSpinBox
@onready var order_item_req_max_spinbox: SpinBox = %OrderItemReqMaxSpinBox
@onready var close_button: Button = %CloseButton
@onready var unlock_all_button: Button = $MarginContainer/ScrollContainer/VBoxContainer/QuickActions/UnlockAllButton
@onready var lock_all_button: Button = $MarginContainer/ScrollContainer/VBoxContainer/QuickActions/LockAllButton
@onready var apply_button: Button = %ApplyButton
@onready var gold_spinbox: SpinBox = %GoldSpinBox

@onready var generate_button: Button = %GenerateButton
@onready var generate_batch_button: Button = %GenerateBatchButton
@onready var skill_select_button: Button = %SkillSelectButton
@onready var skill_selector_option: OptionButton = %SkillSelectorOption
@onready var add_skill_button: Button = %AddSkillButton

@onready var item_type_option: OptionButton = %ItemTypeOption
@onready var item_selector_option: OptionButton = %ItemSelectorOption
@onready var item_rarity_option: OptionButton = %ItemRarityOption
@onready var item_sterile_toggle: CheckButton = %ItemSterileToggle


var _is_updating: bool = false # 防止循环更新

# 性能监控相关
var _perf_container: VBoxContainer
var _perf_labels: Dictionary = {}
const PERF_UPDATE_INTERVAL: float = 0.5
var _perf_timer: float = 0.0


func _ready() -> void:
	_setup_ui()
	_connect_signals()
	_sync_from_unlock_manager()
	
	# 连接动画测试按钮 (手动添加的节点)
	var anim_shock_btn = find_child("TestShockAnimButton", true, false)
	if anim_shock_btn:
		anim_shock_btn.pressed.connect(func():
			get_tree().call_group("debug_animator", "test_shock")
			print("[DebugConsole] 已触发震惊动画测试")
		)
	
	var anim_impatient_btn = find_child("TestImpatientAnimButton", true, false)
	if anim_impatient_btn:
		anim_impatient_btn.pressed.connect(func():
			get_tree().call_group("debug_animator", "test_impatient")
			print("[DebugConsole] 已触发不耐烦动画测试")
		)
	

	var anim_reset_btn = find_child("ResetAnimButton", true, false)
	if anim_reset_btn:
		anim_reset_btn.pressed.connect(func():
			# 强制回到 IDLE
			get_tree().call_group("debug_animator", "_transition_to_state", &"Idle")
			print("[DebugConsole] 已重置动画到 Idle")
		)
	
	_setup_performance_monitor()


func _process(delta: float) -> void:
	if not visible:
		return
		
	_perf_timer += delta
	if _perf_timer >= PERF_UPDATE_INTERVAL:
		_perf_timer = 0.0
		_update_performance_stats()


func _setup_ui() -> void:
	# 设置合成上限下拉框选项
	merge_limit_option.clear()
	for i in range(Constants.Rarity.MYTHIC + 1):
		merge_limit_option.add_item(Constants.rarity_display_name(i), i)
	
	# 设置背包大小范围
	inventory_size_spinbox.min_value = 1
	inventory_size_spinbox.max_value = 20
	inventory_size_spinbox.step = 1
	
	# 设置订单物品数量范围的限制 (硬限制: 1-6)
	const MAX_ORDER_ITEM_COUNT: int = 6
	order_item_req_min_spinbox.min_value = 1
	order_item_req_min_spinbox.max_value = MAX_ORDER_ITEM_COUNT
	order_item_req_min_spinbox.step = 1
	
	order_item_req_max_spinbox.min_value = 1
	order_item_req_max_spinbox.max_value = MAX_ORDER_ITEM_COUNT
	order_item_req_max_spinbox.step = 1
	

	_setup_affix_toggles()
	_setup_generation_ui()
	_setup_skill_list()


func _setup_generation_ui() -> void:
	# 1. 初始化种类下拉框
	item_type_option.clear()
	item_type_option.add_item("全部", -1)
	
	for type in Constants.get_normal_item_types():
		item_type_option.add_item(Constants.type_to_display_name(type), type)
	
	# 2. 初始化稀有度下拉框
	item_rarity_option.clear()
	for i in range(Constants.Rarity.MYTHIC + 1):
		item_rarity_option.add_item(Constants.rarity_display_name(i), i)
	
	# 3. 初始刷新物品选择列表
	_refresh_item_selector_list()


func _setup_affix_toggles() -> void:
	# 动态生成词缀开关
	for child in affix_container.get_children():
		child.queue_free()
	
	for affix in GameManager.all_pool_affixes:
		var toggle = CheckButton.new()
		toggle.text = affix.name
		toggle.name = "AffixToggle_" + affix.id
		toggle.button_pressed = UnlockManager.is_pool_affix_enabled(affix.id)
		toggle.toggled.connect(func(pressed: bool):
			UnlockManager.set_pool_affix_enabled(affix.id, pressed)
		)
		affix_container.add_child(toggle)


func _on_pool_affix_enabled_changed(affix_id: StringName, enabled: bool) -> void:
	var toggle = affix_container.get_node_or_null("AffixToggle_" + affix_id)
	if toggle and toggle is CheckButton:
		_is_updating = true
		toggle.button_pressed = enabled
		_is_updating = false


func _connect_signals() -> void:
	close_button.pressed.connect(_on_close_pressed)
	merge_limit_option.item_selected.connect(_on_merge_limit_selected)
	inventory_size_spinbox.value_changed.connect(_on_inventory_size_changed)
	order_limit_spinbox.value_changed.connect(_on_order_limit_changed)
	order_item_req_min_spinbox.value_changed.connect(_on_order_item_req_min_changed)
	order_item_req_max_spinbox.value_changed.connect(_on_order_item_req_max_changed)
	lock_all_button.pressed.connect(_on_lock_all_pressed)
	apply_button.pressed.connect(_on_apply_pressed)
	gold_spinbox.value_changed.connect(_on_gold_spinbox_value_changed)
	
	# 监听 UnlockManager 变化以同步 UI
	UnlockManager.unlock_changed.connect(_on_unlock_changed)
	UnlockManager.pool_affix_enabled_changed.connect(_on_pool_affix_enabled_changed)
	UnlockManager.merge_limit_changed.connect(_on_merge_limit_changed)
	UnlockManager.inventory_size_changed.connect(_on_inventory_size_value_changed)
	UnlockManager.order_limit_changed.connect(_on_order_limit_value_changed)
	UnlockManager.order_item_req_range_changed.connect(_on_order_item_req_range_value_changed)
	
	# 连接物品生成信号
	generate_button.pressed.connect(_on_generate_pressed)
	generate_batch_button.pressed.connect(_on_generate_batch_pressed)
	
	# 连接技能选择测试按钮
	skill_select_button.pressed.connect(_on_skill_select_pressed)
	add_skill_button.pressed.connect(_on_add_skill_pressed)
	
	# 监听金币变化
	GameManager.gold_changed.connect(_on_game_manager_gold_changed)


func _sync_from_unlock_manager() -> void:
	_is_updating = true
	
	# 同步合成上限
	merge_limit_option.selected = UnlockManager.merge_limit
	
	# 同步背包大小
	inventory_size_spinbox.value = UnlockManager.inventory_size
	
	# 同步金币
	gold_spinbox.value = GameManager.gold
	
	# 同步订单配置
	order_limit_spinbox.value = UnlockManager.order_limit
	order_item_req_min_spinbox.value = UnlockManager.order_item_req_min
	order_item_req_max_spinbox.value = UnlockManager.order_item_req_max
	
	_is_updating = false


func _on_merge_limit_selected(index: int) -> void:
	if _is_updating:
		return
	UnlockManager.merge_limit = index as Constants.Rarity


func _on_inventory_size_changed(value: float) -> void:
	if _is_updating:
		return
	UnlockManager.inventory_size = int(value)


func _on_unlock_changed(_feature_id: StringName, _unlocked: bool) -> void:
	_sync_from_unlock_manager()


func _on_merge_limit_changed(_limit: Constants.Rarity) -> void:
	_is_updating = true
	merge_limit_option.selected = UnlockManager.merge_limit
	_is_updating = false


func _on_inventory_size_value_changed(_size: int) -> void:
	_is_updating = true
	inventory_size_spinbox.value = UnlockManager.inventory_size
	_is_updating = false


func _on_order_limit_changed(value: float) -> void:
	if _is_updating:
		return
	UnlockManager.order_limit = int(value)


func _on_order_limit_value_changed(_limit: int) -> void:
	_is_updating = true
	order_limit_spinbox.value = UnlockManager.order_limit
	_is_updating = false


func _on_order_item_req_min_changed(value: float) -> void:
	if _is_updating:
		return
	var new_min = int(value)
	# 确保 max 不小于 min
	if new_min > UnlockManager.order_item_req_max:
		UnlockManager.order_item_req_max = new_min
	UnlockManager.order_item_req_min = new_min


func _on_order_item_req_max_changed(value: float) -> void:
	if _is_updating:
		return
	var new_max = int(value)
	# 确保 min 不大于 max
	if new_max < UnlockManager.order_item_req_min:
		UnlockManager.order_item_req_min = new_max
	UnlockManager.order_item_req_max = new_max


func _on_order_item_req_range_value_changed(min_val: int, max_val: int) -> void:
	_is_updating = true
	order_item_req_min_spinbox.value = min_val
	order_item_req_max_spinbox.value = max_val
	_is_updating = false


func _on_close_pressed() -> void:
	hide()


func _on_unlock_all_pressed() -> void:
	UnlockManager.unlock_all()


func _on_lock_all_pressed() -> void:
	UnlockManager.lock_all()


func _on_apply_pressed() -> void:
	# 刷新奖池
	if PoolSystem:
		PoolSystem.refresh_pools()
	
	# 同步金币 (点击应用时确保同步一次)
	gold_spinbox.value = GameManager.gold


func _on_gold_spinbox_value_changed(value: float) -> void:
	if _is_updating:
		return
	GameManager.gold = int(value)


func _on_game_manager_gold_changed(value: int) -> void:
	if not visible:
		return
	_is_updating = true
	gold_spinbox.value = value
	_is_updating = false


func _input(event: InputEvent) -> void:
	# 按 Escape 关闭
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if visible:
			hide()
			get_viewport().set_input_as_handled()


## 性能监控
func _setup_performance_monitor() -> void:
	var main_vbox = $MarginContainer/ScrollContainer/VBoxContainer
	if not main_vbox:
		return
		
	# 创建性能监控容器
	_perf_container = VBoxContainer.new()
	_perf_container.name = "PerformanceMonitor"
	
	# 添加标题
	var header = Label.new()
	header.text = "📊 性能监控"
	header.add_theme_font_size_override("font_size", 14)
	_perf_container.add_child(header)
	
	# 添加各项指标 Label
	var metrics = ["FPS", "Memory", "DrawCalls", "Objects", "Orphans"]
	for metric in metrics:
		var row = HBoxContainer.new()
		var label_name = Label.new()
		label_name.text = metric
		label_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var label_value = Label.new()
		label_value.name = "Value_" + metric
		label_value.text = "0"
		_perf_labels[metric] = label_value
		
		row.add_child(label_name)
		row.add_child(label_value)
		_perf_container.add_child(row)
	
	# 添加分隔符
	var sep = HSeparator.new()
	_perf_container.add_child(sep)
	
	# 插入到 Header 之后 (index 1)
	main_vbox.add_child(_perf_container)
	main_vbox.move_child(_perf_container, 2) # Header(0), HSeparator(1), then Here


func _update_performance_stats() -> void:
	if _perf_labels.is_empty():
		return
		
	# FPS
	_perf_labels["FPS"].text = str(Engine.get_frames_per_second())
	
	# Memory (MB)
	var mem = OS.get_static_memory_usage() / 1024.0 / 1024.0
	_perf_labels["Memory"].text = "%.2f MB" % mem
	
	# Draw Calls
	var draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_perf_labels["DrawCalls"].text = str(draw_calls)
	
	# Objects
	var objects = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	_perf_labels["Objects"].text = str(objects)
	
	# Orphan Nodes
	var orphans = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	_perf_labels["Orphans"].text = str(orphans)


## 物品生成逻辑

func _refresh_item_selector_list(filter_type: int = -1) -> void:
	"""刷新物品选择列表"""
	item_selector_option.clear()
	
	var all_items = GameManager.get_all_normal_items()
	for item in all_items:
		if filter_type != -1 and item.item_type != filter_type:
			continue
			
		item_selector_option.add_item(item.name)
		item_selector_option.set_item_metadata(item_selector_option.get_item_count() - 1, item)


func _on_item_type_selected(index: int) -> void:
	var type = item_type_option.get_item_id(index)
	_refresh_item_selector_list(type)


func _on_generate_pressed() -> void:
	"""点击生成按钮"""
	if item_selector_option.get_item_count() == 0:
		return
		
	var selected_item_data = item_selector_option.get_selected_metadata() as ItemData
	var selected_rarity = item_rarity_option.get_selected_id()
	var is_sterile = item_sterile_toggle.button_pressed
	
	if selected_item_data == null:
		return
		
	# 创建实例
	var instance = ItemInstance.new(selected_item_data, selected_rarity, is_sterile)
	
	# 通过 EventBus 注入，这样它会遵循正常的逻辑流程 (自动放入背包或进入待定)
	EventBus.item_obtained.emit(instance)
	
	print("[DebugConsole] 已生成物品: %s (品阶: %d, 绝育: %s)" % [selected_item_data.name, selected_rarity, "是" if is_sterile else "否"])


func _on_generate_batch_pressed() -> void:
	"""一键生成7个不同道具"""
	var all_items = GameManager.get_all_normal_items()
	if all_items.is_empty():
		return
		
	# 尽可能保证多样性
	all_items.shuffle()
	
	# 抽取 7 个（如果不足 7 个则重复）
	for i in range(7):
		var item_data = all_items[i % all_items.size()]
		# 随机稀有度 (普通到史诗)
		var rarity = GameManager.rng.randi_range(0, 3)
		var instance = ItemInstance.new(item_data, rarity, false)
		EventBus.item_obtained.emit(instance)
		
	print("[DebugConsole] 已一键批量生成 7 个道具")


func _on_skill_select_pressed() -> void:
	"""点击测试技能选择按钮"""
	EventBus.modal_requested.emit(&"skill_select", null)
	print("[DebugConsole] 已触发技能三选一流程")


func _setup_skill_list() -> void:
	"""初始化技能下拉列表"""
	skill_selector_option.clear()
	var skills = GameManager.all_skills
	for skill in skills:
		skill_selector_option.add_item(skill.name)
		skill_selector_option.set_item_metadata(skill_selector_option.get_item_count() - 1, skill)


func _on_add_skill_pressed() -> void:
	"""点击添加技能按钮"""
	if skill_selector_option.get_item_count() == 0:
		return
		
	var selected_skill = skill_selector_option.get_selected_metadata() as SkillData
	if not selected_skill:
		return

	if SkillSystem.has_skill(selected_skill.id):
		print("[DebugConsole] 玩家已拥有技能: %s" % selected_skill.name)
		return
		
	var success = SkillSystem.add_skill(selected_skill)
	if success:
		print("[DebugConsole] 已添加技能: %s" % selected_skill.name)
	else:
		print("[DebugConsole] 添加技能失败 (可能已满): %s" % selected_skill.name)
