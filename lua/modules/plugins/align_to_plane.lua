-- lua/modules/plugins/align_to_plane.lua
local OFFSET = 64 -- 平面沿主轴偏移的距离（从玩家眼睛位置向攻击者眼睛方向）

--- 代理位置对齐处理函数
--- 将每个代理的位置移动到垂直于“玩家->攻击者”主轴的平面上，平面距离玩家眼睛位置 OFFSET 个单位
--- @param mv MoveData 移动数据（当前帧未使用，保留供其他 handler 使用）
--- @param player Player 本地玩家
--- @param attacker Entity 攻击者实体（例如 NPC）
--- @param proxy Entity 当前处理的代理实体
--- @param lastPos Vector 代理当前世界位置（来自骨骼位置）
--- @param lastAngle Angle 代理当前角度（来自骨骼角度）
--- @return Vector newPos 处理后的新位置（若交点存在则更新，否则不变）
--- @return Angle newAngle 处理后的新角度（本 handler 不修改角度）
local function alignProxyToPlane(mv, player, attacker, proxy, lastPos, lastAngle)
    local axisStart = player:EyePos()
    local axisEnd = attacker:EyePos()

    -- 使用 ENP.CONSTANTS.EPS 检查主轴方向是否有效（避免零向量）
    if axisStart:DistToSqr(axisEnd) < ENP.CONSTANTS.EPS ^ 2 then
        return
    end

    local rayStart = lastPos
    local intersection = ENP.Util.ComputeLinePerpendicularPlaneIntersection(rayStart, axisStart, axisEnd, OFFSET)

    return intersection
end

ENP.RegisterProxyUpdateHandler(alignProxyToPlane, ENP.CONSTANTS.PRIORITY_FIRST)

