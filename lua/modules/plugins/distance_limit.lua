-- lua/modules/plugins/distance_limit.lua
local MAX_DIST = 2048

--- 限制代理与攻击者眼睛的距离，超过最大距离则拉回到边界
--- @param tickCount number 当前游戏 tick 计数（本函数未使用）
--- @param player Player 本地玩家
--- @param attacker Entity 攻击者实体
--- @param proxy Entity 代理实体
--- @param lastPos Vector 代理当前世界位置（来自骨骼）
--- @param lastAngle Angle 代理当前角度（未修改）
--- @return Vector|nil newPos 处理后的新位置，若超出范围则返回修正位置，否则返回 nil
local function limitDistanceToAttacker(tickCount, player, attacker, proxy, lastPos, lastAngle)
    local eyePos = attacker:EyePos()
    local toProxy = lastPos - eyePos
    local distSqr = toProxy:LengthSqr()
    local maxDistSqr = MAX_DIST * MAX_DIST

    if distSqr > maxDistSqr then
        -- 计算限制后的位置：从攻击者眼睛出发，沿原方向移动 MAX_DIST 单位
        local direction = toProxy:GetNormalized()
        return eyePos + direction * MAX_DIST
    end
end

ENP.RegisterProxyUpdateHandler(limitDistanceToAttacker, ENP.CONSTANTS.PRIORITY_LAST)
