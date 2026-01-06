extends PanelContainer

## 调试控制台 UI
## 提供可视化界面手动控制 UnlockManager 的功能解锁状态。

@onready var feature_container: VBoxContainer = %FeatureContainer
@onready var item_type_container: HFlowContainer = %ItemTypeContainer
@onready var merge_limit_option: OptionButton = %MergeLimitOption
@onready var inventory_size_spinbox: SpinBox = %InventorySizeSpinBox
@onready var close_button: Button = %CloseButton
@onready var unlock_all_button: Button = $MarginContainer/VBoxContainer/QuickActions/UnlockAllButton
@onready var lock_all_button: Button = $MarginContainer/VBoxContainer/QuickActions/LockAllButton
@onready var apply_button: Button = %ApplyButton

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


func _connect_signals() -> void:
	close_button.pressed.connect(_on_close_pressed)
	merge_limit_option.item_selected.connect(_on_merge_limit_selected)
	inventory_size_spinbox.value_changed.connect(_on_inventory_size_changed)
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
	UnlockManager.merge_limit_changed.connect(_on_merge_limit_changed)
	UnlockManager.inventory_size_changed.connect(_on_inventory_size_value_changed)


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


func _on_close_pressed() -> void:
	hide()


func _on_unlock_all_pressed() -> void:
	UnlockManager.unlock_all()


func _on_lock_all_pressed() -> void:
	UnlockManager.lock_all()


func _on_apply_pressed() -> void:
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
