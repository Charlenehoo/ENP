-- lua\modules\core\tick.lua
local isHookAdded = false
local proxyUpdateHandlers = {} -- 存储 { handler, priority } 的数组，按优先级排序

function ENP.RegisterProxyUpdateHandler(handler, priority)
    priority = priority or 0
    local inserted = false
    for i, item in ipairs(proxyUpdateHandlers) do
        if priority < item.priority then
            table.insert(proxyUpdateHandlers, i, {
                handler = handler,
                priority = priority
            })
            inserted = true
            break
        end
    end
    if not inserted then
        table.insert(proxyUpdateHandlers, {
            handler = handler,
            priority = priority
        })
    end
end

hook.Add("ENP_PlayerBoneCacheInitialized", "ENP_AttackerManager_BoneCacheInitialized", function(player)
    if isHookAdded then
        return
    end
    isHookAdded = true

    hook.Add("Tick", "ENP_Tick", function()
        if not IsValid(player) then return end
        local attackerManager = player.enpAttackerManager
        if not attackerManager then
            return
        end

        local tickCount = engine.TickCount

        for attacker, proxies in pairs(attackerManager.attackers) do
            for _, proxy in ipairs(proxies) do
                local boneIndex = proxy.enpBoneIndex

                local target
                if player:Alive() then
                    target = player
                else
                    target = player:GetRagdollEntity()
                end

                local lastPos, lastAngle = target:GetBonePosition(boneIndex)

                for _, item in ipairs(proxyUpdateHandlers) do
                    local handler = item.handler
                    local newPos, newAngle = handler(tickCount, player, attacker, proxy, lastPos, lastAngle)
                    if newPos ~= nil then
                        lastPos = newPos
                    end
                    if newAngle ~= nil then
                        lastAngle = newAngle
                    end
                end

                proxy:SetPos(lastPos)
                proxy:SetAngles(lastAngle)
            end
        end
    end)
end)
