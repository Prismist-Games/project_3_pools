extends Node

## 全局信号总线（Autoload）。
##
## 设计原则：
## - 重要游戏行为必须发出信号，供 SkillSystem 等监听并“被动改写”上下文。
## - UI 只监听信号与转发输入，不直接耦合到具体系统实现。

## 约定：context 为 RefCounted（通常是自定义上下文对象），可被监听者原地改写。
signal draw_requested(context: RefCounted)
signal draw_finished(context: RefCounted)

signal item_obtained(item: RefCounted)
signal item_recycled(slot_index: int, item: RefCounted) # 用于批量回收时触发单独的回收动画

signal pools_refreshed(pools: Array)
signal orders_updated(orders: Array)

signal order_completed(context: RefCounted)

## 通用事件（可扩展）。
## - 新增事件无需在这里加 signal；直接 emit `game_event(event_id, context)` 即可。
## - SkillSystem 等可只监听这一条，达到“扩展不改核心逻辑”的目标。
signal game_event(event_id: StringName, context: RefCounted)

## UI 层弹窗请求：modal_id 用于区分弹窗类型，payload 为上下文/参数。
signal modal_requested(modal_id: StringName, payload: RefCounted)
