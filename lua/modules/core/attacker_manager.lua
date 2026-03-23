-- lua/modules/core/attacker_manager.lua
local PROXY_CLASS = ENP.CONSTANTS.PROXY_CLASS
local DEBUG = true

local AttackerManager = {}
AttackerManager.__index = AttackerManager

-- 构造函数
function AttackerManager:New(player)
    local obj = {
        player = player,
        ragdoll = nil,
        filters = {},
        attackers = {},
        pending = {}
    }
    setmetatable(obj, self)
    if DEBUG then
        print(string.format("[ENP] AttackerManager:New created for player %s (index %d)",
            player:Nick(), player:EntIndex()))
    end
    return obj
end

-- 注册筛选器（略，与之前相同）
function AttackerManager:RegisterFilter(filterFunc)
    table.insert(self.filters, filterFunc)
end

function AttackerManager:CreateProxy(attacker, boneIndex)
    local proxy = ents.Create(PROXY_CLASS)
    if not IsValid(proxy) then return end
    proxy.enpBoneIndex = boneIndex
    proxy:Spawn()
    return proxy
end

function AttackerManager:_ProcessAttacker(attacker)
    self.attackers[attacker] = {}
    for _, boneIndex in ipairs(self.player.enpBoneCache) do
        local proxy = self:CreateProxy(attacker, boneIndex)
        table.insert(self.attackers[attacker], proxy)
    end
end

function AttackerManager:_ProcessEntity(entity)
    for _, filter in ipairs(self.filters) do
        if filter(entity) then
            if not self.attackers[entity] then
                self:_ProcessAttacker(entity)
            end
            break
        end
    end
end

function AttackerManager:OnEntityCreated(entity)
    if entity:GetClass() == PROXY_CLASS then return end
    if not self.player.enpBoneCache then
        self.pending[entity] = true
        return
    end
    self:_ProcessEntity(entity)
end

function AttackerManager:OnEntityRemoved(entity)
    if self.attackers[entity] then
        self.attackers[entity] = nil
    end
    if self.pending[entity] then
        self.pending[entity] = nil
    end
end

function AttackerManager:OnPlayerModelReady()
    for entity, _ in pairs(self.pending) do
        self:_ProcessEntity(entity)
    end
    self.pending = {}
    for attacker, proxies in pairs(self.attackers) do
        for _, proxy in ipairs(proxies) do
            if IsValid(proxy) then
                proxy:Remove()
            end
        end
        self.attackers[attacker] = {}
        for _, boneIndex in ipairs(self.player.enpBoneCache) do
            local proxy = self:CreateProxy(attacker, boneIndex)
            table.insert(self.attackers[attacker], proxy)
        end
    end
end

-- =======================================================
-- 模块初始化：注册钩子，动态确定本地玩家
-- =======================================================
local localPlayer = nil -- 将在第一个 PlayerInitialSpawn 中设置

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

hook.Add("ENP_PlayerBoneCacheInitialized", "ENP_AttackerManager_PlayerBoneCacheInitialized", function(player)
    if localPlayer and player == localPlayer and localPlayer.enpAttackerManager then
        localPlayer.enpAttackerManager:OnPlayerModelReady()
    end
end)

hook.Add("PlayerInitialSpawn", "ENP_AttackerManager_PlayerInitialSpawn", function(player)
    if not localPlayer then
        localPlayer = player
        if not localPlayer.enpAttackerManager then
            localPlayer.enpAttackerManager = AttackerManager:New(localPlayer)
            localPlayer.enpAttackerManager:RegisterFilter(function(ent)
                return IsValid(ent) and ent:IsNPC()
            end)
        end
    end
end)
