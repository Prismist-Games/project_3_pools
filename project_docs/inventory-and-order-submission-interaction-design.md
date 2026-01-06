# **背包交互与订单提交操作逻辑指南**

这份文档旨在向 Cursor 解释“抽抽乐”游戏中 **背包管理**、**物品合成**、**订单提交** 的具体业务逻辑，以便在 Godot (GDScript) 中准确还原 React 原型的功能。

## **1\. 背包系统 (Inventory System)**

背包不仅是存储容器，还承担了“合成台”和“临时缓冲区”的功能。

### **1.1 数据结构**

* **容量**: 固定大小（例如 10 格）。  
* **存储**: Array\[ItemData\]。空槽位建议使用 null 表示。  
* **状态变量**:  
  * pending\_item: ItemData (当前鼠标/手指正“拿着”的、刚抽到的新物品，尚未放入背包)。  
  * selected\_slot\_index: int (当前选中的背包格子索引，用于移动物品)。

### **1.2 物品合成规则 (Synthesis Rules)**

两个物品能够合成的 **必要条件**：

1. **非空**: 两个物品都存在。  
2. **同名**: item\_a.name \== item\_b.name。  
3. **同品质**: item\_a.rarity.id \== item\_b.rarity.id。  
4. **非神话**: 品质不是 mythic (最高级不可合成)。  
5. **非绝育**: 两个物品的 is\_sterile 属性都为 false (由“硬化”词缀产生)。

**合成结果**:

* 移除原有的两个物品。  
* 生成一个同名、**下一级品质** (next\_rarity) 的新物品。

### **1.3 槽位点击逻辑 (State Machine)**

这是最复杂的交互部分，需在 InventorySystem 或 GameManager 中处理点击事件。

#### **场景 A: 玩家正拿着新抽到的物品 (pending\_item \!= null)**

当玩家点击背包中的第 i 个格子：

1. **目标格子为空**:  
   * **操作**: 将 pending\_item 放入第 i 格。  
   * **结果**: inventory\[i\] \= pending\_item, pending\_item \= null。  
2. **目标格子有物品 (target\_item)**:  
   * **判定合成**: 检查 pending\_item 和 target\_item 是否满足 \[1.2 合成规则\]。  
     * **是 (合成)**: 触发合成特效，inventory\[i\] 升级为下一级品质，pending\_item \= null。  
     * **否 (替换/回收)**:  
       * 旧物品 target\_item 被视为“被挤掉”，执行 **回收逻辑**（增加金币 \= 回收价值）。  
       * 新物品 pending\_item 占据该位置。  
       * *React 参考逻辑*: "Recycle replace"。

#### **场景 B: 玩家处于整理模式 (pending\_item \== null)**

当玩家点击背包中的第 i 个格子：

1. **当前没有选中任何格子 (selected\_slot\_index \== \-1)**:  
   * 若格子 i 有物品 \-\> **选中** 该格子 (selected\_slot\_index \= i)。  
   * 若格子 i 为空 \-\> 无操作。  
2. **当前已选中同一个格子 (selected\_slot\_index \== i)**:  
   * **取消选中** (selected\_slot\_index \= \-1)。  
3. **当前已选中另一个格子 (selected\_slot\_index \!= i)**:  
   * 定义: source\_item (原选中物品), target\_item (当前点击格子的物品)。  
   * **目标为空**:  
     * **移动**: 将 source\_item 移动到 i，清空原位置。  
   * **目标有物品**:  
     * **判定合成**: 检查 source\_item 和 target\_item 是否满足 \[1.2 合成规则\]。  
       * **是 (合成)**: target\_item 升级，原位置清空。  
       * **否 (交换)**: inventory\[i\] \= source\_item, inventory\[source\] \= target\_item (交换位置)。  
   * **收尾**: 无论何种操作，完成后重置 selected\_slot\_index \= \-1。

## **2\. 订单提交逻辑 (Order Submission)**

订单提交不仅要检查“有没有”，还要计算“倍率奖励”和“技能加成”。

### **2.1 匹配算法 (Matching Algorithm)**

假设玩家在“多选模式”下选中了背包里的索引列表 selected\_indices：

1. **输入**:  
   * TargetOrder (包含需求列表 requirements)。  
   * SelectedItems (玩家选中的物品列表)。  
2. **验证步骤**:  
   * 遍历订单的每一个需求 req (通常包含 name 和 required\_rarity)。  
   * 在 SelectedItems 中寻找一个 **最佳匹配**：  
     * 条件 1: 物品名称必须一致。  
     * 条件 2: 物品品质 \>= 需求品质。  
     * *策略*: 如果有多个满足条件的物品，优先消耗品质较低但刚好的？(React 原型中是优先消耗高品质的，b.rarity.bonus \- a.rarity.bonus 排序，这可能为了最大化得分，也可能为了简化。**建议**: 优先匹配满足条件的物品，并计算溢出的品质加成)。  
   * 如果所有需求都能找到独立的匹配项 \-\> **订单满足**。

### **2.2 奖励计算 (Reward Calculation)**

$$\\text{最终奖励} \= (\\text{基础奖励} \\times (1 \+ \\text{提交物品的总品质溢出加成})) \+ \\text{技能额外奖励}$$

* **基础奖励**: 订单生成时确定的数值。  
* **品质加成**: 如果订单要“普通”，你交了“传说”，会有巨大的倍率加成。  
* **技能修正**:  
  * poverty\_relief: 贫困救济 (+金币)。  
  * ocd: 强迫症 (若提交物品全为同类，奖励翻倍)。  
  * big\_order\_expert: 大订单专家 (+奖券)。

## **3\. 实现建议 (Godot Implementation)**

### **3.1 信号流 (Signal Flow)**

不要在 UI 代码中直接修改数据。使用 EventBus 或 GameManager 方法。

* **点击格子**:  
  * UI: InventorySlot.\_on\_gui\_input \-\> 发出信号 slot\_clicked(index)。  
  * System: InventorySystem 监听信号 \-\> 执行上述状态机逻辑 \-\> 修改数据 \-\> 发出 inventory\_updated。  
* **提交订单**:  
  * UI: SubmitButton Pressed \-\> 调用 OrderSystem.try\_submit\_order(order\_index, selected\_indices)。  
  * System: 验证逻辑 \-\> 计算奖励 \-\> 发出 order\_completed (触发动画/技能) \-\> 刷新订单。

### **3.2 拖拽 (Drag & Drop) 替代点击？**

虽然 React 原型使用“点击-选中-点击”逻辑，但在 Godot 中，**拖拽 (Drag & Drop)** 是更自然的交互方式。

* **建议**: 在 Godot 中同时支持两种方式，或者优先实现拖拽（利用 \_get\_drag\_data, \_can\_drop\_data, \_drop\_data）。  
* **合成逻辑**: 拖拽 A 到 B 上，如果满足合成条件，则触发合成；否则交换位置。

\# InventorySlot.gd (示例)

func \_drop\_data(at\_position, data):  
    var source\_index \= data.index  
    var target\_index \= self.index  
    InventorySystem.handle\_item\_interaction(source\_index, target\_index)  
