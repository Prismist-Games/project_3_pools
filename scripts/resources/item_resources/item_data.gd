extends Resource
class_name ItemData

## 静态物品定义（.tres 实例化）。

@export var id: StringName = &""
@export var name: String = ""
@export var item_type: Constants.ItemType = Constants.ItemType.NONE
@export var icon: Texture2D = null