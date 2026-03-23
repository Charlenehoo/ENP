-- lua/modules/attacker_manager.lua
local PROXY_CLASS = ENP.CONSTANTS.PROXY_CLASS

local AttackerManager = {}
AttackerManager.__index = AttackerManager

-- 构造函数
-- @param player Entity 所属玩家（单机模式下为本地玩家）
function AttackerManager:New(player)
    local obj = {
        player = player,
        filters = {}, -- 攻击者筛选器列表（函数，返回布尔值）
        attackers = {}, -- 映射表: attacker 实体 -> proxy 列表
        pending = {} -- 待处理实体队列（模型未就绪时暂存）
    }
    setmetatable(obj, self)
    return obj
end

-- 注册一个攻击者筛选器
-- @param filterFunc function(Entity):boolean
function AttackerManager:RegisterFilter(filterFunc)
    table.insert(self.filters, filterFunc)
end

-- 私有方法：创建单个 proxy 实体（附着在指定攻击者的特定骨骼上）
-- @param attacker Entity
-- @param boneIndex number
-- @return Entity|nil
function AttackerManager:_CreateProxy(attacker, boneIndex)
    local proxy = ents.Create(PROXY_CLASS)
    if not IsValid(proxy) then
        return nil
    end
    proxy.enpBoneIndex = boneIndex
    proxy:Spawn()
    return proxy
end

-- 私有方法：为指定攻击者创建所有 proxy（基于当前骨骼缓存）
-- @param attacker Entity
-- @return table proxy 列表
function AttackerManager:_CreateProxies(attacker)
    local proxies = {}
    if self.player.enpBoneCache then
        for _, boneIndex in ipairs(self.player.enpBoneCache) do
            local proxy = self:_CreateProxy(attacker, boneIndex)
            if IsValid(proxy) then
                table.insert(proxies, proxy)
            end
        end
    end
    return proxies
end

-- 私有方法：销毁指定攻击者的所有 proxy 实体
-- @param attacker Entity
function AttackerManager:_DestroyProxies(attacker)
    local proxies = self.attackers[attacker]
    if not proxies then
        return
    end
    for _, proxy in ipairs(proxies) do
        if IsValid(proxy) then
            proxy:Remove()
        end
    end
end

-- 私有方法：为指定攻击者重建所有 proxy（基于当前骨骼缓存）
function AttackerManager:_RebuildProxies(attacker)
    -- 销毁旧 proxy
    self:_DestroyProxies(attacker)
    -- 创建新 proxy
    self.attackers[attacker] = self:_CreateProxies(attacker)
end

-- 私有方法：处理新出现的攻击者（首次被筛选器识别时调用）
-- @param attacker Entity
function AttackerManager:_ProcessAttacker(attacker)
    self:_RebuildProxies(attacker)
end

-- 私有方法：处理单个实体（判定是否为攻击者，若是则初始化映射）
-- @param entity Entity
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

-- 公共方法：当新实体创建时调用（由钩子触发）
-- @param entity Entity
function AttackerManager:OnEntityCreated(entity)
    -- 过滤 proxy 实体，避免它们被误判为攻击者，防止递归
    if entity:GetClass() == PROXY_CLASS then
        return
    end

    -- 先通过筛选器判断是否为潜在攻击者（只依赖实体属性，不依赖骨骼缓存）
    local isPotentialAttacker = false
    for _, filter in ipairs(self.filters) do
        if filter(entity) then
            isPotentialAttacker = true
            break
        end
    end
    if not isPotentialAttacker then
        return
    end

    -- 模型是否就绪？
    if not self.player.enpBoneCache then
        self.pending[entity] = true
        return
    end
    self:_ProcessEntity(entity)
end

-- 公共方法：当实体被移除时调用（由钩子触发）
function AttackerManager:OnEntityRemoved(entity)
    -- 清理 attackers 映射
    if self.attackers[entity] then
        self:_DestroyProxies(entity)
        self.attackers[entity] = nil
    end
    -- 清理 pending 队列
    if self.pending[entity] then
        self.pending[entity] = nil
    end
end

-- 公共方法：当所属玩家的模型重新初始化时调用（由 bone.lua 广播事件触发）
-- 此方法会在模型切换、骨骼缓存重建后执行，用于更新所有已存在的攻击者，
-- 并处理之前因模型未就绪而暂存的实体。
function AttackerManager:OnPlayerModelReinitialized()
    -- 1. 处理所有 pending 实体（模型未就绪时加入的）
    for entity, _ in pairs(self.pending) do
        self:_ProcessEntity(entity)
    end
    self.pending = {}

    -- 2. 更新所有已存在的攻击者（因为骨骼缓存已改变）
    for attacker, _ in pairs(self.attackers) do
        self:_RebuildProxies(attacker)
    end
end

-- =======================================================
-- 模块初始化：注册钩子（实例在 PlayerInitialSpawn 中创建）
-- =======================================================
local localPlayer = Entity(1)

-- 引擎钩子：实体创建
hook.Add("OnEntityCreated", "ENP_AttackerManager_OnEntityCreated", function(entity)
    if localPlayer.enpAttackerManager then
        localPlayer.enpAttackerManager:OnEntityCreated(entity)
    end
end)

-- 引擎钩子：实体移除
hook.Add("EntityRemoved", "ENP_AttackerManager_EntityRemoved", function(entity)
    if localPlayer.enpAttackerManager then
        localPlayer.enpAttackerManager:OnEntityRemoved(entity)
    end
end)

-- 订阅自定义事件：玩家模型就绪（由 bone.lua 广播）
hook.Add("ENP_PlayerModelReady", "ENP_AttackerManager_PlayerModelReady", function(player)
    if player == localPlayer and localPlayer.enpAttackerManager then
        localPlayer.enpAttackerManager:OnPlayerModelReinitialized()
    end
end)

-- 关键：在玩家首次生成时创建管理器实例
hook.Add("PlayerInitialSpawn", "ENP_AttackerManager_PlayerInitialSpawn", function(player)
    if player == localPlayer and not localPlayer.enpAttackerManager then
        localPlayer.enpAttackerManager = AttackerManager:New(localPlayer)
    end
end)

return AttackerManager
