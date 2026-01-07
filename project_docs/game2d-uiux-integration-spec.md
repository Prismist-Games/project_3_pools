### Game2D UI/UX 接入规范（基于 `scenes/Game2D.tscn`）

- **文档目的**：把现有已实现的游戏逻辑（`GameManager` / `InventorySystem` / `PoolSystem` / `OrderSystem` / `SkillSystem` / `EventBus`）接入到成品美术 mockup 场景 `scenes/Game2D.tscn`，并明确 **交互语义**、**动画时序**、**节点控制点（NodePath）** 与 **实现检查表**。
- **权威约束**：本规范以 **`scenes/Game2D.tscn` 的节点层级**为唯一 UI 壳层权威；不引入 `UIOverlay`（CanvasLayer HUD）方案。

---

### 1. 现有逻辑基线（必须保持一致）

- **核心状态源**
  - **`GameManager`（Autoload）**：金币/奖券/阶段、UI 模式、当前选中订单索引等。
  - **`InventorySystem`（Autoload）**：背包数组、选中状态、`pending_items` 队列（背包满时的“待处理物品”）。
  - **`PoolSystem`（Autoload）**：奖池生成与抽奖（基于 `DrawContext`）。
  - **`OrderSystem`（Autoload）**：订单生成/刷新/提交（基于 `OrderCompletedContext`）。
  - **`SkillSystem`（Autoload）**：监听 EventBus，把事件分发到技能效果。
  - **`EventBus`（Autoload）**：typed signals + `game_event` + `modal_requested`。

---

### 2. 交互模式与输入门控（修订版）

#### 2.1 UI 模式（沿用 `Constants.UIMode`）

- **NORMAL（整理）**：背包可整理（点选→移动/交换/合成）；订单不可点；奖池可抽（若未锁）。
- **SUBMIT（提交）**：订单 **可点**（仅此模式）；背包为多选；提交由 Submit 开关确认。
- **RECYCLE（回收）**：背包为多选；回收由 Recycle 开关确认。
- **REPLACE（以旧换新）**：背包进入单选“选择消耗品”态（来自词缀 trade-in）。

#### 2.2 取消行为

- **取消不由开关承担**：`TheMachineSwitch_*` 不作为取消键。
- **MVP 取消键**：**鼠标右键**（全局监听）：
  - 当 `current_ui_mode` 为 `SUBMIT/RECYCLE/REPLACE` 时：右键 → 回到 `NORMAL`，清理多选与订单选中。
  - 当处于“背包满待处理（pending）”强制流程时：**不允许取消流程**（只能放入/替换/丢弃）。丢弃入口见 5.2。
  - 当处于 `skill_select` 的 Lottery Slot 选择态时：右键取消（语义见 5.6）。

#### 2.3 背包满（pending）表现

- **表现规则**：
  - 抽奖产物首先出现在对应 Lottery Slot 的 `Item_example`（及 queue_1/queue_2）。
  - 若背包可自动入包：播放“飞入背包”动画，然后该 Lottery Slot 清空展示。
  - 若背包已满导致无法入包：产物 **留在 Lottery Slot 原地等待输入**，并写入 `InventorySystem.pending_items`（最多 3 个的可视队列）。
  - pending 存在时：**禁用所有奖池点击**（沿用现有 `main_ui.gd` 的“强制处理 pending”策略），只允许点击背包格子执行替换/合成/放入。

> 说明：`pending_items` 本身已支持“单次抽奖产出 3 个（Fragmented）”的队列场景；本规范将其 UI 呈现迁移到 Lottery Slot 的 item 以及 queue 节点上。

#### 2.4 订单点击门控（重要差异）

- 订单的 `Input Area`：**仅在 SUBMIT 模式可点击**。
  - NORMAL：点击订单无效（可保留 hover 高亮，但不触发模式切换/智能填充）。
  - SUBMIT：点击订单 → 智能填充（见 6.3）。

---

### 3. 节点映射（NodePath 权威清单）

> 记号：`<slot_idx>` 表示背包格子索引（0..max-1）；`<pool_idx>` 表示奖池索引（0..2）；`<order_idx>` 表示普通订单索引（1..4）。

#### 3.1 The Machine（技能/资源显示/背包/奖池/开关）

##### 3.1.1 技能槽

- **技能槽底座**：`The Machine/TheMachineSlot 1..3`
- **文字与 tooltip**：
  - `The Machine/TheMachineSlot 1/Skill Label`
  - `The Machine/TheMachineSlot 2/Skill Label`
  - `The Machine/TheMachineSlot 3/Skill Label`
- **图标**：
  - `The Machine/TheMachineSlot 1/Skill Label/Skill Icon`
  - `The Machine/TheMachineSlot 2/Skill Label/Skill Icon`
  - `The Machine/TheMachineSlot 3/Skill Label/Skill Icon`
- **绑定规则**：
  - `SkillSystem.current_skills[0..2]` → 上述 3 个槽位按顺序显示（不足 3 个则隐藏/置灰）。

##### 3.1.2 金币/奖券显示

- **金币**：`The Machine/TheMachineDisplayFill/Money_label`
- **奖券**：`The Machine/TheMachineDisplayFill/Coupon_label`
- **绑定规则**：
  - `GameManager.gold_changed` → 更新 `Money_label.text`
  - `GameManager.tickets_changed` → 更新 `Coupon_label.text`

##### 3.1.3 背包格子（预摆最大数量）

> 当前 `Game2D.tscn` 至少已存在 `Item Slot_root_0`；其余请在编辑器中按上限预摆到 `Item Slot_root_9`，并保持结构一致。

- **背包容器**：`The Machine/Item Slots Grid`（GridContainer）
- **单格模板路径（以 `<slot_idx>` 表示）**：
  - 根：`The Machine/Item Slots Grid/Item Slot_root_<slot_idx>`
  - 点击区域：`.../Input Area`
  - 遮罩：`.../Item Slot_mask`
  - 背景三片（已挂 `slot_background_color_setter.gd`）：`.../Item Slot_mask/Item Slot_backgrounds`
  - 物品根：`.../Item Slot_mask/Item Slot_item_root`
  - 物品图标：`.../Item Slot_mask/Item Slot_item_root/Item_example`
  - 阴影：`.../Item Slot_mask/Item Slot_item_root/Item_example/Item_shadow`
  - **物品词缀/标记**：`.../Item Slot_mask/Item Slot_item_root/Item_example/Item_affix`
  - 盖子：`.../Item Slot_mask/Item Slot_lid`
  - **灯（rarity）**：`.../Item Slot_mask/Item Slot_lid/Slot_led`
  - 动画：`.../AnimationPlayer`

##### 3.1.4 模式开关（Submit / Recycle）

- Submit：`The Machine/TheMachineSwitch_Submit`
  - 点击区域：`.../Input Area`
  - 需要驱动的显示节点：
    - `.../Switch_mask/Switch_background_up/Switch_off_label`
    - `.../Switch_mask/Switch_background_down/Switch_on_label`
    - `.../Switch_handle`（挂 `switch_background_follow.gd`）
- Recycle：`The Machine/TheMachineSwitch_Recycle`
  - 点击区域：`.../Input Area`
  - 需要驱动的显示节点同上

##### 3.1.5 Lottery Slot（3 个奖池槽位）

- 容器：`The Machine/Lottery Slots Grid`
- 根节点：`The Machine/Lottery Slots Grid/Lottery Slot_root_0..2`
- 每个 `Lottery Slot_root_<pool_idx>` 的关键可控节点：
  - 点击区域：`.../Input Area`
  - 物品显示根：`.../Lottery Slot_mask/Lottery Slot_item_root`
  - **主显示物品**：`.../Lottery Slot_mask/Lottery Slot_item_root/Item_example`
  - **队列槽位 1**：`.../Lottery Slot_mask/Lottery Slot_item_root/Item_example_queue_1`
  - **队列槽位 2**：`.../Lottery Slot_mask/Lottery Slot_item_root/Item_example_queue_2`
  - 盖子：`.../Lottery Slot_mask/Lottery Slot_lid`
  - **奖池名称**：`.../Lottery Slot_mask/Lottery Slot_lid/Lottery Pool Name_label`
  - 顶部屏幕：`.../Lottery Slot_top_screen`
    - **Affix Label**：`.../Lottery Slot_top_screen/Affix Label`
    - **Price Label**：`.../Lottery Slot_top_screen/Price Label`
  - 右侧屏幕：`.../Lottery Slot_right_screen`
    - **需求图标容器**：`.../Lottery Slot_right_screen/Lottery Required Items Icon Grid`
    - icon 位：`.../Lottery Required Items Icon Grid/Item Icon_example`（TextureRect；建议在编辑器预摆多个 icon 位，运行时只改 texture/显隐）
  - 动画：`.../AnimationPlayer`

---

#### 3.2 The Rabbit（订单区）

##### 3.2.1 刷新全部

- 节点：`The Rabbit/TheRabbitRefreshAll`
- 点击区域：`The Rabbit/TheRabbitRefreshAll/Input Area`

##### 3.2.2 普通订单（4 个）

- 容器：`The Rabbit/Quest Slots Grid`
- 根节点：`The Rabbit/Quest Slots Grid/Quest Slot_root_1..4`
- 每个 `Quest Slot_root_<order_idx>` 的关键可控节点：
  - 点击区域：`.../Input Area`（**仅 SUBMIT 可点击**）
  - 订单遮罩：`.../Quest Slot_mask`
  - 背景：`.../Quest Slot_mask/Quest Slot_background`（挂 `slot_background_color_setter.gd`）
  - 奖励文本：`.../Quest Slot_mask/Quest Reward Label`
  - 需求物品容器：`.../Quest Slot_mask/Quest Slot Items Grid`
    - icon 位：`.../Quest Slot Items Grid/Quest Slot Item_root`（建议预摆多个 icon 位；未预摆时可临时复制）
  - **订单盖子**：`.../Quest Slot_mask/Quest Slot_lid`
  - 单个刷新按钮：`.../Refresh Button`
    - 次数：`.../Refresh Button/Refresh Count Label`

##### 3.2.3 主线订单（1 个）

- 根节点：`The Rabbit/Main Quest Slot_root`
- 关键可控节点：
  - 点击区域：`.../Input Area`（建议同样只在 SUBMIT 可点击）
  - 背景：`.../Main Quest Slot_mask/Main Quest Slot_background`
  - 奖励文本：`.../Main Quest Slot_mask/Main Quest Reward Label`
  - 需求容器：`.../Main Quest Slot_mask/Main Quest Slot Items Grid`
  - **订单盖子**：`.../Main Quest Slot_mask/Main Quest Slot_lid`

---

### 4. 视觉状态规则（修订版）

#### 4.1 背包格子（Item Slot）视觉规则

- **空格子**：
  - `Item_example.texture = null`（或隐藏）
  - `Item Slot_backgrounds.color` = 灰（“没开灯”）
  - `Slot_led` 抬起
  - `Item_affix` 隐藏
- **有物品**：
  - `Item_example.texture = item.item_data.icon`
  - `Item Slot_backgrounds.color` = 该 rarity 对应的背景色（可用 `Constants.get_rarity_bg_color` 或更偏“灯光色”的变体）
  - `Item_affix`：用于显示标记（例如 `sterile` → “🚫” 或图标）
- **锁定/解锁与盖子**：
  - **Slot 锁定时**：`Item Slot_lid` 关闭（盖上）
  - **Slot 解锁时**：`Item Slot_lid` 打开（掀起）
  - **交换/移动/合成时**：不再动盖子（盖子只与“背包上限/锁定”关联）

> Slot 锁定触发源：全局动画序列播放中、或任何需要阻止背包点击的状态（例如 pending 强制处理期间之外的系统锁）。实现建议：由一个“UI 锁计数器”统一驱动（见 7.1）。

#### 4.2 奖池（Lottery Slot）展示规则

- `Lottery Pool Name_label`：显示池名（例：水果/药品/主线等）
- `Price Label`：显示消耗（金币或奖券）
- `Affix Label`：显示词缀名称/缩写（无词缀则为空或隐藏）

#### 4.3 奖池需求图标

- `Lottery Required Items Icon Grid`：展示“当前订单中与该奖池类型相关的需求物品 icon”（最多 N 个，建议 1~3）
- 刷新时机：`EventBus.orders_updated`、`EventBus.pools_refreshed`
- **推荐口径**：预摆固定数量（建议 3 个）的 icon 位，运行时只改 `texture`/`visible`（避免运行时 duplicate）

#### 4.4 订单奖励类别底色

提交/刷新时，订单背景色用于表达“奖励类别”（而不是 rarity）：

- **金币**（`reward_gold>0 && reward_tickets==0`）：#69d956
- **奖券**（`reward_tickets>0 && reward_gold==0`）：#5290EC
- **主线**：#fc5d60

实现节点：`Quest Slot_background.color` / `Main Quest Slot_background.color`（通过 `slot_background_color_setter.gd`）。

---

### 5. 核心交互与动画时序（修订版）

#### 5.1 背包整理（NORMAL）

- **点选**：只更新选中态高亮（不动盖子）。
- **移动/交换/合成（动画）**：
  - `UI.lock("inventory_action")`（锁定背包点击）
  - 播放“物品换位/移动”动画（建议使用临时飞行 Sprite 复制 texture）
  - 播放“背景色渐变/灯光渐变”（源槽/目标槽）
  - 刷新静态显示（最终把各 slot 的 `Item_example`、背景、灯设到正确）
  - `UI.unlock("inventory_action")`（解锁）

#### 5.2 抽奖（5.2 + 2.3）

**点击 `Lottery Slot_root_<pool_idx>/Input Area`**：

- 若 UI 被锁或 pending 存在：拒绝点击并给出反馈（抖动/闪红等）。
- 否则：
  - `UI.lock("draw")`
  - 播放抽奖展示（可跳过）：盖子/屏幕闪烁/摇晃等
  - 调用 `PoolSystem.draw_from_pool(pool_idx)` 执行逻辑抽奖
  - **展示落点规则**：
    - **自动入包成功**：在该 Lottery Slot 的 `Item_example` 短暂显示产物 → 飞入目标背包空槽 → 背包槽位背景/灯光变色
    - **自动入包失败（背包满）**：产物留在该 Lottery Slot，写入 `InventorySystem.pending_items` 并在 `Item_example_queue_1/2` 展示队列（最多 3）
  - `UI.unlock("draw")`

> 关键实现点：当 `pending_items` 非空时，应记录“本次 pending 来源的 pool_idx”，用于把队列显示绑定到正确的 `Lottery Slot_root_<pool_idx>`。

#### 5.3 提交订单（SUBMIT：订单可点）

- 进入 SUBMIT：由 Submit 开关触发（不再允许订单点击自动切模式）。
- 点击订单（仅 SUBMIT 有效）：
  - 设置 `GameManager.order_selection_index = index`
  - 执行智能填充：写入 `InventorySystem.selected_indices_for_order`
  - 不满足时：播放该订单槽位 shake（替换原 `order_card_shake_requested` 的 Panel 动画）
- 确认提交（Submit 开关）：
  - `UI.lock("order_submit")`
  - 对目标订单槽位执行 lid 序列（见 5.5）
  - 调用 `OrderSystem.submit_order(...)`
  - 刷新订单与背包显示
  - `UI.unlock("order_submit")`

#### 5.4 回收（RECYCLE）

- 进入 RECYCLE：由 Recycle 开关触发。
- 确认回收（Recycle 开关）：
  - `UI.lock("recycle")`
  - 批量回收动画：物品淡出/碎裂、金币/奖券跳动（更新 `Money_label`/`Coupon_label`）
  - `UI.unlock("recycle")`

#### 5.5 订单 lid 动画（提交/刷新共用）

对 `Quest Slot_lid`（或 `Main Quest Slot_lid`）执行序列：

1. **关盖**（lid close）
2. **更新内容**：
   - 更新奖励文本（`Quest Reward Label` / `Main Quest Reward Label`）
   - 更新背景色（`Quest Slot_background.color` / `Main Quest Slot_background.color`，用奖励类别色）
3. **开盖**（lid open）

#### 5.6 交互式选择（使用 Lottery Slot 实现）

> 目标：把 **技能选择** 与 **精准（Precise）二选一** 都“投射”到 `The Machine/Lottery Slots Grid/Lottery Slot_root_0..2` 上完成交互，不再弹出系统对话框。

##### 5.6.1 技能选择（skill_select）

- **事件入口**：`EventBus.modal_requested(&"skill_select", payload)`（payload 允许为空）。
- **展示规则（覆盖 Lottery Slot 正常状态）**：
  - 三个 `Lottery Slot_root_<pool_idx>` 分别展示 3 个技能候选项（来自 `SkillSystem.get_selectable_skills(3)`）。
  - `Lottery Pool Name_label`：显示技能名称（或“技能”+序号）。
  - `Item_example`：显示技能图标（优先用 `SkillData.icon`；若无则用占位 icon）。
  - `Affix Label`：显示技能关键词/简短描述（可选）。
  - `Price Label`：隐藏或显示为 “CHOOSE”。
  - `Item_example_queue_1/2`：隐藏（技能选择不使用队列）。
- **交互**：玩家点击任意一个 Lottery Slot → 选择该技能并关闭选择态。
  - 选择成功后：调用 `SkillSystem.add_skill(skill)`（若技能槽满，后续可扩展为替换流程）。
  - 退出后：恢复 Lottery Slot 显示为真实 pools（建议直接 `PoolSystem.refresh_pools()` 以确保一致）。
- **取消**：右键取消 → 直接退出技能选择并恢复 pools（不获得技能）。

##### 5.6.2 精准二选一（precise_selection）

- **事件入口**：`EventBus.modal_requested(&"precise_selection", payload)`。
  - 约定 payload 内包含：`items: Array[ItemInstance]`（长度 2）与 `callback: Callable`（选择后回调）。
- **展示规则（覆盖 Lottery Slot 正常状态）**：
  - 进入精准态时：**三个 Lottery Slot 全部重置显示**（清空池名/词缀/价格），并禁用“正常抽奖点击”。
  - 其中 **两个** Lottery Slot 抽出两个候选物品：
    - `Item_example` 显示候选物品 icon
    - `Item_example_queue_1/2` 隐藏
    - `Lottery Pool Name_label` 可显示物品名/稀有度（可选）
  - 第三个 Lottery Slot：置空并禁用点击（或显示 “CANCEL”）。
- **交互**：玩家点击其中一个候选物品 Slot → 触发回调并退出精准态。
  - `callback.call(chosen_item)`（chosen_item 为被点击的那一个）
  - 退出后：恢复 Lottery Slot 显示为真实 pools（建议 `PoolSystem.refresh_pools()`）。
- **取消**：右键取消 → 退出精准态并恢复 pools；不调用 callback（等价于“放弃”）。
  - 说明：若精准在进入时已扣费，则取消视为放弃该次机会（符合现有对话框的“放弃”语义）。

##### 5.6.3 有的放矢（targeted_selection）

- **仍使用弹窗（5 选 1）**：UI 尚未完成时，保持现状（系统对话框或临时 UI）。
- **后续目标**：替换为成品 5 选 1 弹窗；但不影响 skill_select/precise 的 Lottery Slot 实现。

---

### 6. 数据绑定与刷新点（实现时必须覆盖）

#### 6.1 Money/Coupon

- `GameManager.gold_changed` → `Money_label.text`
- `GameManager.tickets_changed` → `Coupon_label.text`

#### 6.2 Skills

- `SkillSystem.skills_changed` → 更新 3 个技能槽的 label/icon/tooltip
- 播放skill slot（machine slot）升降动画

#### 6.3 Orders（Rabbit）

- `EventBus.orders_updated` → 更新：
  - `Quest Slot Items Grid`（按预摆 icon 位更新 texture/显隐）
  - `Quest Reward Label` 与 `Refresh Count Label`
  - 主线订单对应节点
  - 同步刷新 Lottery Slot 的 `Lottery Required Items Icon Grid`

#### 6.4 Pools（Machine）

- `EventBus.pools_refreshed` → 更新：
  - `Lottery Pool Name_label`
  - `Price Label`
  - `Affix Label`
  - `Lottery Required Items Icon Grid`（与 orders 联动）

#### 6.5 Inventory（Machine）

- `InventorySystem.inventory_changed` → 更新每个 `Item Slot_root_<slot_idx>` 的：
  - `Item_example`、`Item_affix`、`Slot_led`、`Item Slot_backgrounds`
- `InventorySystem.pending_queue_changed` → 更新“当前来源 Lottery Slot”的：
  - `Item_example`、`Item_example_queue_1`、`Item_example_queue_2`
  - 并按 pending 状态禁用/启用 `Lottery Slot_root_*/Input Area`

---

### 7. 实现约束（给 AI 实现的硬约束）

#### 7.1 统一 UI 锁（用于关盖/禁输入）

- 必须实现一个 **引用计数型 UI 锁**（如 `lock(reason)` / `unlock(reason)`）：
  - `is_locked == true` 时：背包与奖池输入都不可触发；并驱动背包 Slot lid 关闭。
  - `is_locked == false` 时：背包 Slot lid 打开（若当前允许交互）。

#### 7.2 右键取消（全局）

- 在一个集中脚本里（建议挂在 `Game2D` 根或 Machine/Rabbit 的统一控制脚本）监听右键：
  - 若 `current_ui_mode in [SUBMIT, RECYCLE, REPLACE]`：取消到 NORMAL + 清理选择。

#### 7.3 pending 来源 pool_idx（用于“原地等待”绑定）

当 `pending_items` 非空时，必须知道它来自哪个 `Lottery Slot_root_<pool_idx>`，以便把队列显示放回“原地”：

- **最低成本方案（MVP）**：UI 在点击抽奖时记录 `last_clicked_pool_idx`；当 `pending_queue_changed` 触发且 `pending_items` 变为非空时，使用该 idx 渲染队列。
- **更稳健方案（推荐）**：在抽奖路径里记录来源（例如新增 `InventorySystem.pending_source_pool_idx: int`，由 `PoolSystem.draw_from_pool(pool_idx)` 在产出前设置/或通过 `DrawContext.meta` 传递）。

#### 7.4 模板/实例化策略（统一建议）

你现在的 `Game2D.tscn` 结构与动画诉求（稳定 NodePath、盖子/灯光/屏幕动画可控）更适合 **“预摆上限 slots + 运行时只改数据/贴图/显隐”**，不建议在热路径频繁实例化/销毁节点。

- **推荐统一口径（强烈建议）**：
  - **背包格子**：预摆 `Item Slot_root_0..9`，运行时只更新 `Item_example.texture`、`Item_affix.text`、`Slot_led.modulate`、`Item Slot_backgrounds.color` 等；空格子用 texture=null/visible=false。
  - **Lottery Slot**：固定 3 个 `Lottery Slot_root_0..2`；每个 slot 内固定 3 个 item 显示位（`Item_example` + `queue_1` + `queue_2`）。
  - **订单需求图标（Quest Slot Items Grid）**：建议同样预摆一个“最大需求数”的 icon 位（例如 4 或 6 个），超出则截断/缩放（你可以在 UX 上明确上限）。
  - **Lottery Required Items Icon Grid**：建议预摆 3 个 icon 位（`Item Icon_0..2`）并只改 texture/显隐（避免运行时 duplicate）。
- **例外（允许实例化）**：`targeted_selection` 的 5 选 1 成品弹窗（未来 UI），因其非高频且节点结构独立，做成独立 scene 动态实例化更合适。

---

### 8. 实现检查表（落地验收）

- **节点接入**：能按本规范 NodePath 找到并更新全部新增节点：
  - Skill Label/Icon、Money/Coupon、PoolName/Affix/Price、RequiredItemsGrid、Item_affix、Item_example_queue_1/2。
- **门控**：
  - 订单仅 SUBMIT 可点；NORMAL 点击订单无效。
  - 右键能退出 SUBMIT/RECYCLE/REPLACE。
  - pending 存在时奖池点击被禁用，且 pending 物品显示在来源 Lottery Slot 的队列位。
- **动画规则**：
  - 背包 slot：锁定关盖、解锁开盖；交换不动盖子；背景/灯随物品变化渐变。
  - 抽奖：可自动入包飞行动画；入包失败原地等待+队列展示（最多 3）。
  - 订单：提交/刷新用 lid 关盖→改文本/背景→开盖。
  - skill_select/precise：使用 Lottery Slot 抽出选项并完成点击选择（不弹系统对话框）。
- **逻辑一致性**：
  - 金币/奖券显示与 `GameManager` 一致。
  - 提交/回收对库存与奖励变更正确，且 UI 及时刷新。


