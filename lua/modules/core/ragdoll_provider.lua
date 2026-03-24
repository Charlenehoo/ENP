-- lua/modules/core/ragdoll_provider.lua
function ENP.GetRagdoll(player)
    return player:GetRagdollEntity()
end

hook.Add("PlayerSpawn", "ENP_PlayerSpawn", function(player)
    player:SetShouldServerRagdoll(true)
end)

