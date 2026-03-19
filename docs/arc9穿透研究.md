weapons\arc9_base\sh_penetration.lua

子弹穿透逻辑基于逐段步进检测与扩展包围盒判断，核心算法如下：

1. **前置条件**
   - 启用穿透ConVar，且当前穿透层数不超过`MaxPenetrationLayers`（默认3）。

2. **穿透系数确定**
   - 根据击中材质`tr.MatType`查表`ARC9.PenTable`获得`penmult`；若实体有`mmRHAe`则优先使用。

```lua
ARC9.PenTable = {
    [MAT_ANTLION]     = 1,
    [MAT_BLOODYFLESH] = 1,
    [MAT_CONCRETE]    = 1,
    [MAT_DIRT]        = 1,
    [MAT_EGGSHELL]    = 1,
    [MAT_FLESH]       = 1,
    [MAT_GRATE]       = 1,
    [MAT_ALIENFLESH]  = 1,
    [MAT_CLIP]        = 1,
    [MAT_SNOW]        = 1,
    [MAT_PLASTIC]     = 1,
    [MAT_METAL]       = 2,
    [MAT_SAND]        = 1,
    [MAT_FOLIAGE]     = 1,
    [MAT_COMPUTER]    = 1,
    [MAT_SLOSH]       = 1,
    [MAT_TILE]        = 1,
    [MAT_GRASS]       = 1,
    [MAT_VENT]        = 1,
    [MAT_WOOD]        = 0.5,
    [MAT_DEFAULT]     = 1,
    [MAT_GLASS]       = 0.25,
    [MAT_WARPSHIELD]  = 1,
}
```

3. **步长计算**
   - `pentracelen = clamp(penleft * penmult / 8, 1, 4)`，步长由剩余穿透力与系数决定，限制在1~4单位内。

4. **步进穿透循环**
   - 从当前击中点沿方向`dir`步进，每次执行`TraceLine`检测。
   - 使用`IsPenetrating`判断采样点是否仍在同一实体内部：
     - 对世界：`StartSolid`为false或`AllSolid`为true则认为仍在世界内。
     - 对实体：将实体AABB沿中心向外扩展25%，若`HitPos`在扩展盒内则认为仍在实体内。
   - 若满足条件且未达到步进终点，则消耗`penleft`，更新位置，继续步进；否则退出循环。

5. **穿透后续**
   - 循环结束后若`penleft > 0`，则在退出点`endpos`发射新子弹，递归调用回调处理后续穿透，并在`exitpos`反向发射零伤害子弹用于效果。
   - 若发生跳弹（根据`GetRicochetChance`），则跳过穿透，直接改变方向继续。

该算法通过离散步进模拟连续穿透，利用扩展AABB容忍命中点略超出原始包围盒（如命中四肢），实现简单且性能友好的材质与厚度消耗计算。

---

该函数 `IsPenetrating(ptr, ptrent)` 用于判断子弹在一次步进追踪后是否仍然处于同一实体（或世界）内部，是穿透算法中决定是否继续在同层内步进的关键。

## 世界实体处理

```lua
if ptrent:IsWorld() then
    return !ptr.StartSolid or ptr.AllSolid
end
```

- **逻辑**：基于 `ptr.StartSolid`（起点是否在固体中）和 `ptr.AllSolid`（整条线段是否全在固体中）的组合。
- **设计意图**：
  - 当子弹从外部击中世界表面（`!StartSolid`）后，进入世界内部，此时应继续穿透。
  - 若子弹已经位于世界内部（`AllSolid`），表示仍未穿出，也应继续。
  - 若 `StartSolid` 为真且 `AllSolid` 为假，表示起点在世界内部但终点已离开世界（穿出），此时应停止。
- **物理意义**：利用 trace 的固有属性快速判断世界这种无限大连续介质的穿透状态。

## 非世界实体处理

```lua
elseif IsValid(ptrent) then
    local mins, maxs = ptrent:WorldSpaceAABB()
    local wsc = ptrent:WorldSpaceCenter()
    mins = mins + (mins - wsc) * 0.25
    maxs = maxs + (maxs - wsc) * 0.25
    local withinbounding = ptr.HitPos:WithinAABox(mins, maxs)
    if withinbounding then return true end
end
```

- **步骤**：
  1. 获取实体的世界轴对齐包围盒（AABB）`mins`、`maxs` 及其中心 `wsc`。
  2. **向外扩展包围盒**：  
     `mins = mins + (mins - wsc) * 0.25` 将每个面沿从中心到该面的方向扩大 25%。  
     例如，最小 X 面：`mins.x` 变为 `mins.x + (mins.x - wsc.x)*0.25`，相当于将盒子向外推。
  3. 检查 `ptr.HitPos` 是否在扩展后的 AABB 内。
- **设计意图**：
  - 实体的碰撞模型由多个 hitbox 组成，AABB 是它们的粗略包围盒，但四肢等部位可能略微超出 AABB。直接使用原始 AABB 会导致命中边缘时误判为已离开实体，中断穿透。
  - 扩大 25% 是一种启发式补偿，提高穿透的连贯性（更少因命中点轻微偏移而终止），代价是可能将外部点误判为内部（降低空间精确性）。
  - 注释“more consistent but less accurate”正是此意——优先保证穿透行为在视觉和感觉上稳定，而非严格物理精确。

## 算法上下文

在 `SWEP:Penetrate` 的步进循环中：

```lua
while penleft > 0 and IsPenetrating(ptr, ptrent) and ptr.Fraction < 1 and ptrent == curr_ent do
    -- 消耗穿透力，移动起点，重新 trace
end
```

- `IsPenetrating` 确保每次步进后的采样点仍在当前实体内部，从而连续消耗厚度对应的穿透力。
- 对于世界，利用 trace 的固体标志避免复杂几何计算；对于实体，用扩展 AABB 作为代理，简单高效。

## 潜在细节

- 扩展系数 0.25 是经验值，过大可能导致误穿相邻实体，过小则无法补偿 hitbox 外露。
- 仅检查 `HitPos` 单点，假设步长较小（1~4 单位），足以捕捉连续性。
- 忽略实体的旋转（AABB 是轴对齐），但实体通常不旋转或旋转缓慢，误差可接受。

综上，该函数以性能优先、兼顾稳定性的方式解决了“子弹是否仍在同一物体内”的判定，为后续的穿透力消耗和出点计算提供基础。
