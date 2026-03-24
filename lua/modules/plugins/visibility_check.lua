-- lua\modules\plugins\visibility_check.lua
local DEBUG = true

-- 插件1：设置每个代理对攻击者的可见性（最早执行）
local function setProxyVisibility(tickCount, player, attacker, proxy, lastPos, lastAngle)
    -- 使用 VisibleVec 并传入代理的当前位置（lastPos）
    local newVisible = attacker:IsLineOfSightClear(lastPos)
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

-- 插件3：根据可见性控制代理的启用/禁用状态（最后执行，优先级最高）
local function controlProxyEnable(tickCount, player, attacker, proxy, lastPos, lastAngle)
    -- 每个攻击者每个 tick 只执行一次聚合控制，避免重复遍历
    if attacker._enpControlTick == tickCount then
        return nil, nil
    end
    attacker._enpControlTick = tickCount

    local proxies = player.enpAttackerManager.attackers[attacker]
    if not proxies then
        return nil, nil
    end

    -- 获取聚合状态（由 aggregateVisibility 插件计算）
    local allNotVisible = attacker.enpAllProxiesNotVisible

    -- 如果全部不可见，则全部启用（特殊逻辑）
    if allNotVisible then
        for _, p in ipairs(proxies) do
            p:Enable()
        end
    else
        -- 否则按单个代理的可见性控制
        for _, p in ipairs(proxies) do
            if p.enpVisible then
                p:Enable()
            else
                p:Disable()
            end
        end
    end
    return nil, nil
end

-- 注册插件，优先级应高于 aggregateVisibility（即更大的数值），确保在其之后执行
ENP.RegisterProxyUpdateHandler(controlProxyEnable, ENP.CONSTANTS.PRIORITY_LAST + 2)
