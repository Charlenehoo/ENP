-- lua\modules\hook.lua
local hook_Add = hook.Add

ENP = ENP or {}
ENP.managedAttackers = ENP.managedAttackers or {}
ENP.attackerTests = ENP.attackerTests or {}

local SINGLE_PLAYER_ALERT =
    "[ENP] 此模组仅限单机模式游玩，检测到非主机玩家，部分功能可能异常。"
local PLAYER = Entity(1)

local isPlayerInit = false

function ENP.RegisterAttackerTest(testFunc)
    table.insert(ENP.attackerTests, testFunc)
end

local function OnPlayerSpawn(player, transition)

end

hook_Add("OnEntityCreated", "ENP_OnEntityCreated", function(entity)
    for _, testFunc in ipairs(ENP.attackerTests) do
        if testFunc(entity) then
            table.insert(ENP.managedAttackers, entity)
            break
        end
    end
end)

hook_Add("EntityRemoved", "ENP_EntityRemoved", function(entity)
    for i, attacker in ipairs(ENP.managedAttackers) do
        if attacker == entity then
            table.remove(ENP.managedAttackers, i)
            break
        end
    end
end)

hook_Add("PlayerInitialSpawn", "ENP_PlayerInitialSpawn", function(player, transition)
    isPlayerInit = true
    if player ~= PLAYER then
        print(SINGLE_PLAYER_ALERT)
        return
    end
    OnPlayerSpawn(player, transition)
end)

hook_Add("PlayerSpawn", "ENP_PlayerSpawn", function(player, transition)
    if not isPlayerInit then
        return
    end
    OnPlayerSpawn(player, transition)
end)

hook_Add("PlayerTick", "ENP_PlayerTick", function(player, mv)

end)
