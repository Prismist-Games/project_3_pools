extends Resource
class_name PoolAffixData

## 词缀定义（.tres 实例化）。
##
## 说明：
## - 用 id 标识词缀类型（字符串化，避免 enum 扩展需要改代码）。
## - effects 是可插拔模块列表，可自由组合。

@export var id: StringName = &""
@export var name: String = ""
@export_multiline var description: String = ""
@export var effects: Array[PoolAffixEffect] = []


