extends RefCounted
class_name OrderCompletedContext

## 订单完成上下文（可被 SkillEffect 原地改写奖励等）。

var reward_gold: int = 0
var reward_tickets: int = 0

## 本次提交消耗的物品（由订单系统填充）
var submitted_items: Array[ItemInstance] = []

## 扩展数据槽（例如订单类型、是否主线订单等）
var meta: Dictionary = {}







