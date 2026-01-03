# **技能效果 (Skill Effects) 实现指南**

这份文档详细定义了“抽抽乐”游戏中所有技能的具体逻辑实现方式。用于指导 Godot 项目中 SkillSystem 及相关信号监听逻辑的开发。

## **1\. 核心架构集成**

技能系统主要由 SkillSystem 节点驱动，它是一个纯逻辑节点（非 UI）。

* **监听 (Listen)**: SkillSystem 在 \_ready() 中连接 EventBus 的各种信号（如 order\_completed, draw\_requested, inventory\_updated）。  
* **判断 (Check)**: 当信号触发时，检查 GameManager.current\_skills 中是否包含特定技能 ID。  
* **执行 (Execute)**: 如果条件满足，修改数据、发送新信号或更新全局状态标志。

## **2\. 状态管理 (Skill Flags)**

部分技能依赖跨回合或跨操作的状态（如“下一次抽奖必定稀有”）。建议在 GameManager 或 SkillSystem 中维护一个字典来存储临时状态：

\# SkillSystem.gd 或 GameManager.gd  
var skill\_state \= {  
    "consecutive\_commons": 0,      \# 连续抽到普通物品次数 (安慰奖)  
    "next\_draw\_guaranteed\_rare": false, \# 下一次必定稀有 (时来运转/安慰奖)  
    "next\_draw\_extra\_item": false  \# 下一次多给一个 (自动补货)  
}

## **3\. 技能效果详解**

### **A. 金币与消耗类 (Gold & Cost)**

**触发时机**: 在 PoolSystem 计算消耗时调用。

| ID | 名称 | 触发条件 | 效果逻辑 | 实现位置 |
| :---- | :---- | :---- | :---- | :---- |
| **poverty\_relief** | **贫困救济** | 提交订单时，GameManager.gold \< 5。 | 订单基础金币奖励 \+10。 | OrderSystem.\_calculate\_reward() |
| **calculated** | **精打细算** | 抽奖前，GameManager.gold \< 10。 | 普通奖池消耗 \-2 (最低为1)。 | PoolSystem.get\_final\_cost() |
| **vip\_discount** | **贵宾折扣** | 抽奖前，奖池带有交互词缀 (precise / targeted)。 | 奖池消耗 \-1 (最低为0)。 | PoolSystem.get\_final\_cost() |
| **lucky\_7** | **幸运 7** | 抽奖计算稀有度时，GameManager.gold % 10 \== 7。 | 传说(Legendary)品质的权重 \* 2。 | PoolSystem.roll\_rarity() |

### **B. 抽奖与掉落类 (Draw & Drop)**

**触发时机**: 在 PoolSystem 生成物品或计算稀有度时。

| ID | 名称 | 触发条件 | 效果逻辑 | 实现位置 |
| :---- | :---- | :---- | :---- | :---- |
| **consolation\_prize** | **安慰奖** | 1\. 每次获得物品时检测。 2\. 抽奖前检测标志位。 | **逻辑1**: 若物品是 common，计数器 \+1；否则重置。 **逻辑2**: 若计数器 \>= 5，设置 next\_draw\_guaranteed\_rare \= true。 **逻辑3**: 下次抽奖若标志为真，强制移除 Common/Uncommon 权重，重置计数和标志。 | PoolSystem.generate\_item() SkillSystem.\_on\_item\_obtained() |
| **auto\_restock** | **自动补货** | 1\. 完成订单时。 2\. 抽奖生成物品时。 | **逻辑1**: 完成订单后，设置 next\_draw\_extra\_item \= true。 **逻辑2**: 抽奖时若标志为真，额外执行一次物品生成，并重置标志。 | SkillSystem.\_on\_order\_completed() PoolSystem.draw() |
| **turn\_fortune** | **时来运转** | 完成订单时。 | 设置 next\_draw\_guaranteed\_rare \= true。 | SkillSystem.\_on\_order\_completed() |
| **negotiator** | **谈判专家** | 获得物品时，物品品质 \>= epic。 | 所有当前订单的 remaining\_refreshes \+= 1。 | SkillSystem.\_on\_item\_obtained() |

### **C. 订单与刷新类 (Order & Refresh)**

**触发时机**: 订单生成、提交或刷新时。

| ID | 名称 | 触发条件 | 效果逻辑 | 实现位置 |
| :---- | :---- | :---- | :---- | :---- |
| **cut\_corners** | **偷工减料** | 生成新订单时。 | 20% 概率使该订单的需求物品数量 \-1 (最低为1)。 | OrderSystem.generate\_order() |
| **time\_freeze** | **时间冻结** | 刷新单个订单时。 | 20% 概率不扣除该订单的 remaining\_refreshes 计数。 | OrderSystem.refresh\_single\_order() |
| **ocd** | **强迫症** | 提交订单时，计算奖励。 | 检查提交的所有物品 pool\_id 是否一致。若一致，总奖励 \* 2。 | OrderSystem.submit\_order() |
| **big\_order\_expert** | **大订单专家** | 提交订单时，订单需求数量 \== 4。 | 额外奖励 tickets \+= 10。 | OrderSystem.submit\_order() |
| **hard\_order\_expert** | **困难订单专家** | 提交订单时，需求包含 epic 或 legendary。 | 额外奖励 tickets \+= 15。 | OrderSystem.submit\_order() |

### **D. 回收类 (Recycle)**

**触发时机**: 玩家执行回收操作时。

| ID | 名称 | 触发条件 | 效果逻辑 | 实现位置 |
| :---- | :---- | :---- | :---- | :---- |
| **alchemy** | **炼金术** | 批量回收时，被回收物品中有 \>= rare 品质。 | 对每个稀有及以上物品判定：15% 概率获得 5 张奖券。 | InventorySystem.recycle\_items() |

## **4\. GDScript 代码片段参考**

为了让 Cursor 更好地生成代码，请参考以下实现模式：

### **模式 1：数值修改 (Hook Pattern)**

在计算消耗或奖励时，传入基础值，返回修改后的值。

\# 在 SkillSystem.gd 中  
func apply\_draw\_cost\_modifiers(base\_cost: int, pool\_data: PoolData) \-\> int:  
    var final\_cost \= base\_cost  
      
    if GameManager.has\_skill("calculated") and GameManager.gold \< 10:  
        final\_cost \-= 2  
          
    if GameManager.has\_skill("vip\_discount") and pool\_data.affix\_type \== "interaction":  
        final\_cost \-= 1  
          
    return max(1, final\_cost) \# 假设最低消耗为1，除非特殊说明

### **模式 2：信号监听 (Observer Pattern)**

在 System 节点监听事件。

\# 在 SkillSystem.gd 中  
func \_ready():  
    EventBus.item\_obtained.connect(\_on\_item\_obtained)

func \_on\_item\_obtained(item: ItemData):  
    \# 实现【谈判专家】  
    if GameManager.has\_skill("negotiator"):  
        if item.rarity\_value \>= Rarity.EPIC: \# 假设 EPIC 是个常量枚举值  
            EventBus.add\_order\_refreshes\_requested.emit(1)  
              
    \# 实现【安慰奖】计数逻辑  
    if item.rarity \== "common":  
        skill\_state.consecutive\_commons \+= 1  
    else:  
        skill\_state.consecutive\_commons \= 0  
          
    if GameManager.has\_skill("consolation\_prize") and skill\_state.consecutive\_commons \>= 5:  
        skill\_state.next\_draw\_guaranteed\_rare \= true  
        skill\_state.consecutive\_commons \= 0  
        EventBus.show\_toast.emit("安慰奖触发！下次必出稀有")

### **模式 3：概率判定 (RNG)**

\# 在 OrderSystem.gd 中  
func generate\_order():  
    var req\_count \= \_get\_random\_req\_count()  
      
    \# 实现【偷工减料】  
    if GameManager.has\_skill("cut\_corners"):  
        if randf() \< 0.20 and req\_count \> 1:  
            req\_count \-= 1  
              
    \# ... 继续生成逻辑  
