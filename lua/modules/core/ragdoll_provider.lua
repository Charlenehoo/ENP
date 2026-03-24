-- lua/modules/core/ragdoll_provider.lua
local RagdollProvider = {}
RagdollProvider.__index = RagdollProvider

-- 单例实例
local instance = nil

function RagdollProvider:New()
    local obj = {
        provider = nil -- 用户注册的自定义 provider
    }
    setmetatable(obj, self)
    return obj
end

function RagdollProvider:GetInstance()
    if not instance then
        instance = RagdollProvider:New()
    end
    return instance
end

function RagdollProvider:Register(provider)
    self.provider = provider
    if SERVER then
        print("[ENP] Ragdoll provider registered.")
    end
end

function RagdollProvider:GetRagdoll(player)
    if not IsValid(player) or player:Alive() then
        return nil
    end
    local rag = nil
    if self.provider then
        rag = self.provider(player)
    end
    if IsValid(rag) then
        return rag
    end
    return player:GetRagdollEntity()
end

-- 对外接口
ENP.RagdollProvider = RagdollProvider:GetInstance()
function ENP.RegisterRagdollProvider(provider)
    ENP.RagdollProvider:Register(provider)
end
function ENP.GetRagdollForPlayer(player)
    return ENP.RagdollProvider:GetRagdoll(player)
end
