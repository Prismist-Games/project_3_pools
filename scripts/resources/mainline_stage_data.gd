extends Resource
class_name MainlineStageData

## 主线阶段定义（.tres 实例化）。
##
## 说明：
## - 通过在 `res://data/general/mainline/stages/` 放置多个 MainlineStageData.tres，
##   即可新增/调整主线阶段，无需修改游戏逻辑代码。

@export var stage: int = 1
@export var stage_name: String = ""

## 该阶段的主线神话道具（通常 is_mainline=true 的 ItemData）
@export var mainline_item: ItemData = null


