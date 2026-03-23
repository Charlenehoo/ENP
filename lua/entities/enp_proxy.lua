-- .\lua\entities\enp_proxy.lua
ENP = ENP or {}
ENP.CONSTANTS = ENP.CONSTANTS or {}

local PROXY_CLASS = "enp_proxy"
local PROXY_MODEL = "models/editor/cube_small.mdl"
local PROXY_SCALE = 0.04

AddCSLuaFile()
ENT.Base = "base_ai"
ENT.Type = "ai"

function ENT:Initialize() -- https://wiki.facepunch.com/gmod/ENTITY:Initialize
    self:SetModel(PROXY_MODEL)
    self:SetModelScale(PROXY_SCALE)
    -- self:SetNoDraw(true)
    self:SetCollisionGroup(COLLISION_GROUP_NONE)
end

ENP.CONSTANTS.PROXY_CLASS = PROXY_CLASS
