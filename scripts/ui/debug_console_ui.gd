extends PanelContainer

## 调试控制台 UI
## 提供可视化界面手动控制 UnlockManager 的功能解锁状态。

@onready var feature_container: VBoxContainer = %FeatureContainer
@onready var item_type_container: HFlowContainer = %ItemTypeContainer
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

# 物品生成相关
@onready var item_type_option: OptionButton = %ItemTypeOption
@onready var item_selector_option: OptionButton = %ItemSelectorOption
@onready var item_rarity_option: OptionButton = %ItemRarityOption
@onready var item_sterile_toggle: CheckButton = %ItemSterileToggle
@onready var generate_button: Button = %GenerateButton

# 订单品质概率配置
@onready var order_rarity_common_spinbox: SpinBox = %OrderRarityCommonSpinBox
@onready var order_rarity_uncommon_spinbox: SpinBox = %OrderRarityUncommonSpinBox
@onready var order_rarity_rare_spinbox: SpinBox = %OrderRarityRareSpinBox
@onready var order_rarity_epic_spinbox: SpinBox = %OrderRarityEpicSpinBox
@onready var order_rarity_legendary_spinbox: SpinBox = %OrderRarityLegendarySpinBox

# 抽取品质概率配置
@onready var pool_rarity_common_spinbox: SpinBox = %PoolRarityCommonSpinBox
@onready var pool_rarity_uncommon_spinbox: SpinBox = %PoolRarityUncommonSpinBox
@onready var pool_rarity_rare_spinbox: SpinBox = %PoolRarityRareSpinBox
@onready var pool_rarity_epic_spinbox: SpinBox = %PoolRarityEpicSpinBox
@onready var pool_rarity_legendary_spinbox: SpinBox = %PoolRarityLegendarySpinBox

var _is_updating: bool = false # 防止循环更新


func _ready() -> void:
	_setup_ui()
	_connect_signals()
	_sync_from_unlock_manager()


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
	
	# 设置订单品质概率输入框
	for spinbox in [order_rarity_common_spinbox, order_rarity_uncommon_spinbox,
		order_rarity_rare_spinbox, order_rarity_epic_spinbox, order_rarity_legendary_spinbox]:
		spinbox.min_value = 0.0
		spinbox.max_value = 1000.0
		spinbox.step = 0.1
		spinbox.allow_greater = true
		spinbox.allow_lesser = true
	
	# 设置抽取品质概率输入框
	for spinbox in [pool_rarity_common_spinbox, pool_rarity_uncommon_spinbox,
		pool_rarity_rare_spinbox, pool_rarity_epic_spinbox, pool_rarity_legendary_spinbox]:
		spinbox.min_value = 0.0
		spinbox.max_value = 1000.0
		spinbox.step = 0.1
		spinbox.allow_greater = true
		spinbox.allow_lesser = true
	
	_setup_affix_toggles()
	_setup_generation_ui()


func _setup_generation_ui() -> void:
	# 初始化物品类型下拉框
	item_type_option.clear()
	
	# 添加主线类型
	item_type_option.add_item("主线 (Mainline)")
	item_type_option.set_item_metadata(0, Constants.ItemType.MAINLINE)
	
	var normal_types = Constants.get_normal_item_types()
	for type in normal_types:
		item_type_option.add_item(Constants.type_to_display_name(type))
		item_type_option.set_item_metadata(item_type_option.get_item_count() - 1, type)
	
	# 初始化稀有度下拉框
	item_rarity_option.clear()
	for i in range(Constants.Rarity.MYTHIC + 1):
		item_rarity_option.add_item(Constants.rarity_display_name(i), i)
	
	# 初始刷新物品选择列表
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
	unlock_all_button.pressed.connect(_on_unlock_all_pressed)
	lock_all_button.pressed.connect(_on_lock_all_pressed)
	apply_button.pressed.connect(_on_apply_pressed)
	
	# 连接功能开关
	for child in feature_container.get_children():
		if child is CheckButton and child.has_meta("feature"):
			var feature: int = child.get_meta("feature")
			child.toggled.connect(func(pressed: bool): _on_feature_toggled(feature, pressed))
	
	# 连接物品类型开关
	for child in item_type_container.get_children():
		if child is CheckButton and child.has_meta("feature"):
			var feature: int = child.get_meta("feature")
			child.toggled.connect(func(pressed: bool): _on_feature_toggled(feature, pressed))
	
	# 监听 UnlockManager 变化以同步 UI
	UnlockManager.unlock_changed.connect(_on_unlock_changed)
	UnlockManager.pool_affix_enabled_changed.connect(_on_pool_affix_enabled_changed)
	UnlockManager.merge_limit_changed.connect(_on_merge_limit_changed)
	UnlockManager.inventory_size_changed.connect(_on_inventory_size_value_changed)
	UnlockManager.order_limit_changed.connect(_on_order_limit_value_changed)
	UnlockManager.order_item_req_range_changed.connect(_on_order_item_req_range_value_changed)
	
	# 连接订单品质概率输入框
	order_rarity_common_spinbox.value_changed.connect(_on_order_rarity_weight_changed.bind(0))
	order_rarity_uncommon_spinbox.value_changed.connect(_on_order_rarity_weight_changed.bind(1))
	order_rarity_rare_spinbox.value_changed.connect(_on_order_rarity_weight_changed.bind(2))
	order_rarity_epic_spinbox.value_changed.connect(_on_order_rarity_weight_changed.bind(3))
	order_rarity_legendary_spinbox.value_changed.connect(_on_order_rarity_weight_changed.bind(4))
	
	pool_rarity_legendary_spinbox.value_changed.connect(_on_pool_rarity_weight_changed.bind(4))
	
	# 连接物品生成信号
	item_type_option.item_selected.connect(func(_idx): _refresh_item_selector_list())
	generate_button.pressed.connect(_on_generate_pressed)


func _sync_from_unlock_manager() -> void:
	_is_updating = true
	
	# 同步功能开关
	for child in feature_container.get_children():
		if child is CheckButton and child.has_meta("feature"):
			var feature: int = child.get_meta("feature")
			child.button_pressed = UnlockManager.is_unlocked(feature)
	
	# 同步物品类型开关
	for child in item_type_container.get_children():
		if child is CheckButton and child.has_meta("feature"):
			var feature: int = child.get_meta("feature")
			child.button_pressed = UnlockManager.is_unlocked(feature)
	
	# 同步合成上限
	merge_limit_option.selected = UnlockManager.merge_limit
	
	# 同步背包大小
	inventory_size_spinbox.value = UnlockManager.inventory_size
	
	# 同步订单配置
	order_limit_spinbox.value = UnlockManager.order_limit
	order_item_req_min_spinbox.value = UnlockManager.order_item_req_min
	order_item_req_max_spinbox.value = UnlockManager.order_item_req_max
	
	# 同步当前阶段的品质概率配置
	_sync_rarity_weights_from_stage_data()
	
	_is_updating = false


func _create_feature_toggle(feature: UnlockManager.Feature, display_name: String) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = display_name
	toggle.set_meta("feature", feature)
	toggle.toggled.connect(func(pressed: bool): _on_feature_toggled(feature, pressed))
	return toggle


func _on_feature_toggled(feature: UnlockManager.Feature, pressed: bool) -> void:
	if _is_updating:
		return
	UnlockManager.set_unlocked(feature, pressed)


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
	# 应用品质概率修改
	_apply_rarity_weights_to_stage_data()
	
	# 刷新奖池和订单
	if PoolSystem:
		PoolSystem.refresh_pools()
	if OrderSystem:
		OrderSystem.refresh_all_orders()


func _input(event: InputEvent) -> void:
	# 按 Escape 关闭
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if visible:
			hide()
			get_viewport().set_input_as_handled()

## 品质概率配置相关函数

func _sync_rarity_weights_from_stage_data() -> void:
	"""从当前阶段数据同步品质权重到UI"""
	var stage_data = GameManager.current_stage_data
	if stage_data == null:
		return
	
	_is_updating = true
	
	# 同步订单品质权重
	order_rarity_common_spinbox.value = stage_data.order_weight_common
	order_rarity_uncommon_spinbox.value = stage_data.order_weight_uncommon
	order_rarity_rare_spinbox.value = stage_data.order_weight_rare
	order_rarity_epic_spinbox.value = stage_data.order_weight_epic
	order_rarity_legendary_spinbox.value = stage_data.order_weight_legendary
	
	# 同步抽取品质权重
	pool_rarity_common_spinbox.value = stage_data.pool_weight_common
	pool_rarity_uncommon_spinbox.value = stage_data.pool_weight_uncommon
	pool_rarity_rare_spinbox.value = stage_data.pool_weight_rare
	pool_rarity_epic_spinbox.value = stage_data.pool_weight_epic
	pool_rarity_legendary_spinbox.value = stage_data.pool_weight_legendary
	
	_is_updating = false


func _apply_rarity_weights_to_stage_data() -> void:
	"""将UI中的品质权重应用到当前阶段数据"""
	var stage_data = GameManager.current_stage_data
	if stage_data == null:
		return
	
	# 应用订单品质权重
	stage_data.order_weight_common = order_rarity_common_spinbox.value
	stage_data.order_weight_uncommon = order_rarity_uncommon_spinbox.value
	stage_data.order_weight_rare = order_rarity_rare_spinbox.value
	stage_data.order_weight_epic = order_rarity_epic_spinbox.value
	stage_data.order_weight_legendary = order_rarity_legendary_spinbox.value
	
	# 应用抽取品质权重
	stage_data.pool_weight_common = pool_rarity_common_spinbox.value
	stage_data.pool_weight_uncommon = pool_rarity_uncommon_spinbox.value
	stage_data.pool_weight_rare = pool_rarity_rare_spinbox.value
	stage_data.pool_weight_epic = pool_rarity_epic_spinbox.value
	stage_data.pool_weight_legendary = pool_rarity_legendary_spinbox.value


func _on_order_rarity_weight_changed(_value: float, rarity_index: int) -> void:
	"""订单品质权重变更回调"""
	if _is_updating:
		return
	# 实时应用到阶段数据
	_apply_order_rarity_weight(rarity_index)


func _on_pool_rarity_weight_changed(_value: float, rarity_index: int) -> void:
	"""抽取品质权重变更回调"""
	if _is_updating:
		return
	# 实时应用到阶段数据
	_apply_pool_rarity_weight(rarity_index)


func _apply_order_rarity_weight(rarity_index: int) -> void:
	"""应用单个订单品质权重"""
	var stage_data = GameManager.current_stage_data
	if stage_data == null:
		return
	
	match rarity_index:
		0: stage_data.order_weight_common = order_rarity_common_spinbox.value
		1: stage_data.order_weight_uncommon = order_rarity_uncommon_spinbox.value
		2: stage_data.order_weight_rare = order_rarity_rare_spinbox.value
		3: stage_data.order_weight_epic = order_rarity_epic_spinbox.value
		4: stage_data.order_weight_legendary = order_rarity_legendary_spinbox.value


func _apply_pool_rarity_weight(rarity_index: int) -> void:
	"""应用单个抽取品质权重"""
	var stage_data = GameManager.current_stage_data
	if stage_data == null:
		return
	
	match rarity_index:
		0: stage_data.pool_weight_common = pool_rarity_common_spinbox.value
		1: stage_data.pool_weight_uncommon = pool_rarity_uncommon_spinbox.value
		2: stage_data.pool_weight_rare = pool_rarity_rare_spinbox.value
		3: stage_data.pool_weight_epic = pool_rarity_epic_spinbox.value
		4: stage_data.pool_weight_legendary = pool_rarity_legendary_spinbox.value


## 物品生成逻辑

func _refresh_item_selector_list() -> void:
	"""根据选中的类型刷新物品选择列表"""
	var selected_type = item_type_option.get_selected_metadata() as Constants.ItemType
	item_selector_option.clear()
	
	var items = GameManager.get_items_for_type(selected_type)
	for item in items:
		item_selector_option.add_item(item.name)
		item_selector_option.set_item_metadata(item_selector_option.get_item_count() - 1, item)


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
