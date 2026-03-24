-- lua/modules/core/attacker_manager.lua
local PROXY_CLASS = ENP.CONSTANTS.PROXY_CLASS
local DEBUG = true

local AttackerManager = {}
AttackerManager.__index = AttackerManager

function AttackerManager:New(player)
    local obj = {
        player = player,
        attackers = {}, -- attacker -> list of proxy entities
        filters = {}    -- list of filter functions
    }
    setmetatable(obj, self)
    if DEBUG then
        print(string.format("[ENP] AttackerManager:New created for player %s (index %d)", player:Nick(),
            player:EntIndex()))
    end
    return obj
end

function AttackerManager:RegisterFilter(filterFunc)
    table.insert(self.filters, filterFunc)
end

function AttackerManager:CreateProxy(attacker, boneIndex)
    local player = self.player
    local proxy = ents.Create(PROXY_CLASS)
    if not IsValid(proxy) then
        return nil
    end
    local disposition, dispositionPriority = attacker:Disposition(player)
    proxy.enpAttacker = attacker
    -- proxy.enpOriginalDisposition = disposition
    proxy.enpOriginalDispositionPriority = dispositionPriority
    attacker:AddRelationship(string.format("%s %s %s", PROXY_CLASS, D_NU, dispositionPriority))
    attacker:AddEntityRelationship(player, D_NU, dispositionPriority)
    proxy.enpBoneIndex = boneIndex
    proxy:Spawn()
    return proxy
end

function AttackerManager:_ProcessAttacker(attacker)
    if self.attackers[attacker] then
        for _, proxy in ipairs(self.attackers[attacker]) do
            if IsValid(proxy) then
                proxy:Remove()
            end
        end
    end

    self.attackers[attacker] = {}
    for _, boneIndex in ipairs(self.player.enpBoneCache) do
        local proxy = self:CreateProxy(attacker, boneIndex)
        if proxy then
            table.insert(self.attackers[attacker], proxy)
        end
    end
end

function AttackerManager:_ShouldProcess(entity)
    if entity:GetClass() == PROXY_CLASS then
        return false
    end
    for _, filter in ipairs(self.filters) do
        if filter(entity) then
            return true
        end
    end
    return false
end

function AttackerManager:OnPlayerBoneCacheInitialized()
    if DEBUG then
        print(string.format("[ENP] AttackerManager: Bone cache ready, scanning all entities for player %s",
            self.player:Nick()))
    end

    for _, ent in pairs(ents.GetAll()) do
        if self:_ShouldProcess(ent) then
            self:_ProcessAttacker(ent)
        end
    end
end

function AttackerManager:OnEntityRemoved(entity)
    if entity:GetClass() == PROXY_CLASS then
        return
    end

    if self.attackers[entity] then
        for _, proxy in ipairs(self.attackers[entity]) do
            if IsValid(proxy) then
                proxy:Remove()
            end
        end
        self.attackers[entity] = nil
    end
end

function AttackerManager:OnEntityCreated(entity)
    if not self.player.enpBoneCache then
        return
    end

    if self:_ShouldProcess(entity) then
        self:_ProcessAttacker(entity)
    end
end

-- =======================================================
-- 模块初始化：注册钩子，动态确定本地玩家
-- =======================================================
local localPlayer = nil

hook.Add("OnEntityCreated", "ENP_AttackerManager_OnEntityCreated", function(entity)
    if localPlayer and localPlayer.enpAttackerManager then
        localPlayer.enpAttackerManager:OnEntityCreated(entity)
    end
end)

hook.Add("EntityRemoved", "ENP_AttackerManager_EntityRemoved", function(entity)
    if localPlayer and localPlayer.enpAttackerManager then
        localPlayer.enpAttackerManager:OnEntityRemoved(entity)
    end
end)

hook.Add("ENP_PlayerBoneCacheInitialized", "ENP_AttackerManager_BoneCacheInitialized", function(player)
    if localPlayer and player == localPlayer and localPlayer.enpAttackerManager then
        localPlayer.enpAttackerManager:OnPlayerBoneCacheInitialized()
    end
end)

local example_filter = function(ent)
    return IsValid(ent) and ent:IsNPC()
end

hook.Add("PlayerInitialSpawn", "ENP_AttackerManager_PlayerSpawn", function(player)
    if not localPlayer then
        localPlayer = player
        if not localPlayer.enpAttackerManager then
            localPlayer.enpAttackerManager = AttackerManager:New(localPlayer)

            localPlayer.enpAttackerManager:RegisterFilter(example_filter)

            if localPlayer.enpBoneCache then
                localPlayer.enpAttackerManager:OnPlayerBoneCacheInitialized()
            end
        end
    end
end)
