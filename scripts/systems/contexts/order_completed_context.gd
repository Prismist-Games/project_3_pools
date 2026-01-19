extends RefCounted
class_name OrderCompletedContext

## 订单完成上下文（可被 SkillEffect 原地改写奖励等）。

var reward_gold: int = 0

## 本次提交消耗的物品（由订单系统填充）
var submitted_items: Array = []

## 订单数据引用（用于检查订单需求）
var order_data: OrderData = null

## 扩展数据槽（例如订单类型、是否主线订单等）
var meta: Dictionary = {}
