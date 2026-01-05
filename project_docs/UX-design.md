# **UI/UX 设计与交互指南 (UI/UX Design Guide)**

这份文档详细描述了“抽抽乐”游戏原型的用户界面结构、视觉风格规范以及核心交互逻辑。用于指导 Godot 项目中 UI 场景的搭建 (Control 节点) 和样式调整 (Theme/StyleBox)。

## **1\. 整体布局结构 (Layout Structure)**

游戏采用 **响应式布局**，主要分为四个区域。在 Godot 中建议使用 CanvasLayer 和 Control 容器 (VBoxContainer, HBoxContainer) 实现。

### **1.1 顶部栏 (Header)**

* **左侧**: 资源显示。  
  * **金币 (Gold)**: 黄色系图标 \+ 数字。  
  * **奖券 (Tickets)**: 紫色系图标 \+ 数字。  
* **右侧**: 游戏状态。  
  * **主线进度**: Flag 图标 \+ "X/5" 文本。  
  * **系统按钮**: 重置 (Power), 设置 (Settings)。

### **1.2 左侧/上方侧边栏 (Orders Panel)**

* **功能**: 显示当前活跃的订单。  
* **布局**: 垂直列表 (VBoxContainer \+ ScrollContainer)。  
* **内容**:  
  * 1 个 **主线订单** (高亮，紫色背景，置顶)。  
  * 4 个 **普通订单** (白色背景)。  
  * 顶部固定一个 "刷新订单" 按钮。

### **1.3 中心/右侧主区域 (Pool Area)**

* **功能**: 显示当前的 3 个抽奖池。  
* **布局**: 垂直或网格列表。  
* **卡片设计**:  
  * 左侧: 巨大的 emoji 图标 (表示类型，如水果)。  
  * 中间: 名字 \+ 词缀描述 (如果有)。  
  * 右侧: 价格标签 (胶囊形状，根据货币类型变色)。  
  * *交互*: 悬停时稍微上浮 (scale 变化)，点击触发抽奖。

### **1.4 底部区域 (Footer)**

* **技能栏**: 位于背包上方，横向排列 3 个圆形技能图标。  
* **背包栏 (Inventory)**:  
  * 显示 N 个格子 (通常 10 个)。  
  * 网格布局 (GridContainer)，居中显示。  
* **操作按钮**: 悬浮在右下角的巨大圆形按钮 ("回收", "出牌")。

## **2\. 视觉规范 (Visual Style)**

### **2.1 品质颜色系统 (Rarity Colors)**

用于物品边框、背景和文字颜色。

| 品质 | 颜色代码 (参考 Tailwind) | Godot Color (Hex) |
| :---- | :---- | :---- |
| **Common** | Slate-300 / Slate-50 | \#cbd5e1 (边框), \#f8fafc (底) |
| **Uncommon** | Green-400 / Green-50 | \#4ade80 (边框), \#f0fdf4 (底) |
| **Rare** | Blue-400 / Blue-50 | \#60a5fa (边框), \#eff6ff (底) |
| **Epic** | Purple-400 / Purple-50 | \#c084fc (边框), \#faf5ff (底) |
| **Legendary** | Orange-400 / Orange-50 | \#fb923c (边框), \#fff7ed (底) |
| **Mythic** | Rose-500 / Rose-50 | \#f43f5e (边框), \#fff1f2 (底) |

### **2.2 反馈颜色**

* **选中 (Selected)**: 蓝色高亮边框 (\#2563eb)。  
* **删除/回收 (Destructive)**: 红色/琥珀色背景 (\#ef4444 / \#d97706)。  
* **可交互 (Interactive)**: 悬停时亮度降低或稍微放大。

## **3\. 核心交互模式 (Interaction Patterns)**

### **3.1 物品交互状态机 (Inventory FSM)**

背包格子的点击行为完全取决于当前的 **UI 模式**。

| 模式 | 视觉提示 | 点击行为 |
| :---- | :---- | :---- |
| **整理 (Normal)** | 无特殊提示 | **选中**一个物品，再次点击空位**移动**，点击另一物品**交换**或**合成**。 |
| **提交 (Submit)** | 按钮变蓝，提示"选择订单物品" | **多选**。点击物品切换选中状态 (加蓝色勾选标记)。点击订单卡片自动选中匹配物品。 |
| **回收 (Recycle)** | 按钮变橙，提示"选择回收物品" | **多选**。点击物品切换选中状态 (加垃圾桶标记)。 |
| **以旧换新 (Trade-in)** | 仅背包高亮，其余变暗 | **单选**。点击一个有效物品立即触发消耗逻辑。 |

### **3.2 悬停反馈 (Hover Linking)**

这是一个提升 UX 的关键细节：

* **Hover 订单需求**: 高亮背包中所有符合该需求的物品（加粗边框或弹跳动画）。  
* **Hover 奖池**: 显示该奖池可能产出的物品，如果这些物品正好是某个订单需要的，高亮该订单。  
* **Hover 技能**: 显示技能详细描述 Tooltip。

### **3.3 队列处理 (Queue Panel)**

* **触发**: 当背包已满且玩家获得新物品时。  
* **表现**: 弹出一个临时面板，显示 Pending Item (当前处理) 和 Next Items (后续队列)。  
* **操作**: 此时禁用所有其他 UI（抽奖、刷新），强制玩家处理当前物品（放入背包、替换现有、或直接丢弃）。

## **4\. Godot 实现建议**

### **4.1 节点结构推荐**

CanvasLayer (UI)  
├── MarginContainer (Padding)  
│   └── VBoxContainer (MainLayout)  
│       ├── Header (HBox)  
│       ├── HBoxContainer (Content)  
│       │   ├── OrderPanel (ScrollContainer)  
│       │   └── PoolPanel (GridContainer)  
│       └── Footer (VBox)  
│           ├── SkillBar (HBox)  
│           ├── InventoryGrid (GridContainer)  
│           └── ActionButtons (HBox)  
└── ModalLayer (CanvasLayer, z-index high)  
    ├── SkillSelectionModal  
    └── ItemQueuePanel

### **4.2 资源建议**

* **Theme**: 创建一个全局 .tres 主题，定义 PanelContainer 的圆角 (CornerRadius) 和阴影。  
* **StyleBoxFlat**: 大量使用 StyleBoxFlat 来实现不同品质的彩色边框和背景，而不是用图片素材。这样更灵活。  
* **Tween**: 使用 create\_tween() 来实现卡片悬停时的 scale 放大效果和新物品进入时的 modulate 渐变。

### **4.3 技能选择弹窗的特殊交互**

* **“按住查看” (Peek)**:  
  * 在弹窗右上角放置一个按钮。  
  * 连接 button\_down 信号 \-\> 将弹窗内容的 modulate.a 设为 0 (隐藏)。  
  * 连接 button\_up 信号 \-\> 将弹窗内容的 modulate.a 设为 1 (显示)。  
  * 这允许玩家在做选择前透过弹窗看清底下的背包状态。