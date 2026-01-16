# 实施计划：抽奖揭示动画更新

## 目标 (Objective)
更新抽奖槽的揭示序列，使其严格遵循“稀有度阶梯上升 (Rarity Step-Up)”的视觉模式。动画应模拟一种上升的过程，即背景颜色在揭示最终物品之前，会按照稀有度等级逐级变化。

## 上下文 (Context)
- **目标文件**: `scripts/ui/components/lottery_slot_ui.gd`
- **函数**: `play_reveal_sequence`
- **着色器 (Shader)**: `assets/shaders/silhouette.gdshader` (物品上已挂载)

## 详细需求 (Detailed Requirements)

### 1. 初始状态 (揭示前)
在盖子打开之前或打开的瞬间：
- **背景颜色**: 设置为 `Constants.COLOR_BG_SLOT_EMPTY` (机器原色/底色)。
- **物品可见性**: 物品图标应可见，但处于**被遮蔽/剪影**状态。
- **Shader 效果**:
  - 在 `item_main` 上启用剪影 shader。
  - 将 `is_enabled` 设置为 `true`。
  - 将 `silhouette_color` 设置为 `Color.BLACK`。
  - **效果**: 用户只能看到机器底色背景上的一个黑色物品轮廓。

### 2. 动画逻辑 (开盖)
修改 `play_reveal_sequence` 函数，用以下顺序逻辑替换现有的“洗牌 (shuffle)”逻辑：

1.  **打开盖子**: 播放标准的 `lid_open` 动画。
2.  **稀有度升级循环**:
    - 确保lid_open动画播放完毕
    - 获取主物品 (`items[0]`) 的 `target_rarity` (目标稀有度)。
    - 从 `Rarity.COMMON` (0) 开始，逐级增加直到 `target_rarity`。
    - **每一步**:
        - 将 `backgrounds.color` 设置为当前step对应的颜色 `Constants.get_rarity_border_color(current_step_rarity)`。
        - **等待**: 添加一个小延迟 (例如 `0.5s` 到 `0.75s`) 来模拟“当...当...当...”的节奏感。
    - *示例*: 如果物品是 **稀有 (Rare)**:
        - 第1步: 颜色变为 普通 (灰色)。等待。
        - 第2步: 颜色变为 优秀 (绿色)。等待。
        - 第3步: 颜色变为 稀有 (蓝色)。等待。
3.  **最终揭示**:
    - 当step结束时 (背景颜色已匹配实际稀有度)：
    - 依然等待0.5s 到 0.75s 来模拟“当...当...当...”的节奏感的最后一下“当”
    - **禁用 Shader**: 将 `item_main` 材质上的 `is_enabled` 设置为 `false`。
    - **视觉结果**: 黑色剪影瞬间变回实际的物品贴图。

