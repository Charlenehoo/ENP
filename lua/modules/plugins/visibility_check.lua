-- lua\modules\plugins\visibility_check.lua
local DEBUG = true

-- 插件1：设置每个代理对攻击者的可见性（最早执行）
local function setProxyVisibility(tickCount, player, attacker, proxy, lastPos, lastAngle)
    local newVisible = attacker:Visible(proxy)
    if DEBUG then
        local oldVisible = proxy.enpVisible
        if oldVisible ~= nil and oldVisible ~= newVisible then
            print(string.format("[ENP Debug] Proxy %s (bone %d) visibility changed: %s -> %s (attacker %s)",
                tostring(proxy), proxy.enpBoneIndex or 0, tostring(oldVisible), tostring(newVisible), tostring(attacker)))
        end
    end
    proxy.enpVisible = newVisible
    return nil, nil
end
ENP.RegisterProxyUpdateHandler(setProxyVisibility, ENP.CONSTANTS.PRIORITY_FIRST)

-- 插件2：统计每个攻击者的所有代理可见性，并存储聚合标记（第二早执行）
local function aggregateVisibility(tickCount, player, attacker, proxy, lastPos, lastAngle)
    -- 使用 tick 计数确保每个 tick 每个攻击者只统计一次
    if attacker._enpVisibilityTick == tickCount then
        return nil, nil
    end
    attacker._enpVisibilityTick = tickCount

    local proxies = player.enpAttackerManager.attackers[attacker]
    if not proxies then
        return nil, nil
    end

    -- 计算新的聚合值：是否所有代理都不可见
    local allNotVisible = true
    for _, p in ipairs(proxies) do
        if p.enpVisible then
            allNotVisible = false
            break
        end
    end

    if DEBUG then
        local oldAllNotVisible = attacker.enpAllProxiesNotVisible
        if oldAllNotVisible ~= nil and oldAllNotVisible ~= allNotVisible then
            print(string.format("[ENP Debug] Attacker %s all proxies not visible changed: %s -> %s",
                tostring(attacker), tostring(oldAllNotVisible), tostring(allNotVisible)))
        end
    end

    attacker.enpAllProxiesNotVisible = allNotVisible
    return nil, nil
end
ENP.RegisterProxyUpdateHandler(aggregateVisibility, ENP.CONSTANTS.PRIORITY_FIRST + 1)
