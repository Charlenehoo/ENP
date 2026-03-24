-- .\lua\entities\enp_proxy.lua
local PROXY_MODEL = "models/editor/cube_small.mdl"

AddCSLuaFile()
ENT.Base = "base_ai"
ENT.Type = "ai"

function ENT:Initialize() -- https://wiki.facepunch.com/gmod/ENTITY:Initialize
    self:SetModel(PROXY_MODEL)
    self:SetModelScale(0.03125)
    -- self:SetNoDraw(true)
    self:SetCollisionGroup(COLLISION_GROUP_NONE)
end

function ENT:Enable()
    self:SetModelScale(0.03125)
    local attacker = self.enpAttacker
    -- local disposition = self.enpOriginalDisposition
    local dispositionPriority = self.enpOriginalDispositionPriority
    attacker:AddEntityRelationship(self, D_HT, dispositionPriority + 1)
end

function ENT:Disable()
    self:SetModelScale(0.0625)
    local attacker = self.enpAttacker
    local dispositionPriority = self.enpOriginalDispositionPriority
    attacker:AddEntityRelationship(self, D_NU, dispositionPriority + 1)
end
