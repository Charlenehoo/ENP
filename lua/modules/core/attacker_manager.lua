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

function AttackerManager:CreateProxy(attacker, boneIndex)
    local proxy = ents.Create(PROXY_CLASS)
    if not IsValid(proxy) then
        return
    end
    proxy.enpBoneIndex = boneIndex
    proxy:Spawn()
    return proxy
end

function AttackerManager:_ProcessAttacker(attacker)
    self.attackers[attacker] = {}
    for _, boneIndex in self.player.enpBoneCache do
        local proxy = self:CreateProxy(attacker, boneIndex)
        table.insert(self.attackers[attacker], proxy)
    end
end

-- 内部方法：处理单个实体（判定是否为攻击者，若是则初始化映射）
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

-- 当新实体创建时调用（由钩子触发）
-- @param entity Entity
function AttackerManager:OnEntityCreated(entity)
    -- 如果本地玩家模型尚未就绪（无骨骼缓存），则加入等待队列
    if not self.player.enpBoneCache then
        self.pending[entity] = true
        return
    end
    -- 模型已就绪，直接处理
    self:_ProcessEntity(entity)
end

-- 当实体被移除时调用（由钩子触发）
-- @param entity Entity
function AttackerManager:OnEntityRemoved(entity)
    if self.attackers[entity] then
        self.attackers[entity] = nil
    end
    -- 清理 pending 队列中可能残留的引用
    if self.pending[entity] then
        self.pending[entity] = nil
    end
end

-- 当所属玩家的模型就绪时调用（由 bone.lua 广播事件触发）
function AttackerManager:OnPlayerModelReady()
    -- 1. 处理所有 pending 实体（与之前相同）
    for entity, _ in pairs(self.pending) do
        self:_ProcessEntity(entity)
    end
    self.pending = {}

    -- 2. 更新所有已存在的攻击者（模型切换后需重新创建 proxy）
    for attacker, proxies in pairs(self.attackers) do
        -- 销毁旧 proxy
        for _, proxy in ipairs(proxies) do
            if IsValid(proxy) then
                proxy:Remove()
            end
        end
        -- 基于新骨骼缓存重新创建 proxy
        self.attackers[attacker] = {}
        for _, boneIndex in ipairs(self.player.enpBoneCache) do
            local proxy = self:CreateProxy(attacker, boneIndex)
            table.insert(self.attackers[attacker], proxy)
        end
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

-- 订阅自定义事件：玩家模型就绪
hook.Add("ENP_PlayerModelReady", "ENP_AttackerManager_PlayerModelReady", function(player)
    if player == localPlayer and localPlayer.enpAttackerManager then
        localPlayer.enpAttackerManager:OnPlayerModelReady()
    end
end)

-- 关键：在玩家首次生成时创建管理器实例
hook.Add("PlayerInitialSpawn", "ENP_AttackerManager_PlayerInitialSpawn", function(player)
    if player == localPlayer and not localPlayer.enpAttackerManager then
        localPlayer.enpAttackerManager = AttackerManager:New(localPlayer)
    end
end)
