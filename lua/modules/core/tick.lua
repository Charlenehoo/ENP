-- lua\modules\core\tick.lua

hook.Add("PlayerTick", "ENP_PlayerTick", function(player, mv)
    local attackerManager = player.enpAttackerManager
    for attacker, proxies in pairs(attackerManager.attackers) do
        for _, proxy in ipairs(proxies) do
            local boneIndex = proxy.enpBoneIndex
            local target = player:Alive() and player or attackerManager.ragdoll
            local bonePos, boneAngle = target:GetBonePosition(boneIndex)
            proxy:SetPos(bonePos)
            proxy:SetAngles(boneAngle)
        end
    end
end)
