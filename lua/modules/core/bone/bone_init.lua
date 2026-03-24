-- lua/modules/core/bone/bone_init.lua
local BONE_NAMES = ENP.CONSTANTS.BONE_NAMES
local EPS = ENP.CONSTANTS.EPS

local function InitializeBoneCache(player)
    local model = player:GetModel()
    if model == player.enpLastModel then
        return true
    end

    player.enpBoneCache = {}
    local rootPos = player:GetPos()

    for _, boneName in ipairs(BONE_NAMES) do
        local boneIndex = player:LookupBone(boneName)
        if not boneIndex then
            print(string.format("[ENP] Bone not found: %s", boneName))
            continue
        end

        local bonePos = player:GetBonePosition(boneIndex)
        if rootPos:IsEqualTol(bonePos, EPS) then
            print(string.format("[ENP] Bone at root position (skipping): %s", boneName))
            continue
        end

        table.insert(player.enpBoneCache, boneIndex)
    end

    print(string.format("[ENP] Model changed for player %s (model: %s), reinitialized cache with %d bones.", player:Nick(), model, #player.enpBoneCache))

    if #player.enpBoneCache > 0 then
        player.enpLastModel = model
        hook.Run("ENP_PlayerBoneCacheInitialized", player)
        return true
    end
    return false
end

local function AttemptInitWithRetry(player)
    local timerID = "ENP_BoneCacheInitializing_" .. player:EntIndex()
    if timer.Exists(timerID) then
        timer.Remove(timerID)
    end

    timer.Create(timerID, 0.2, 5, function()
        if not IsValid(player) then
            timer.Remove(timerID)
            return
        end

        if InitializeBoneCache(player) then
            timer.Remove(timerID)
        end
    end)
end

hook.Add("PlayerSetModel", "ENP_PlayerSetModel", function(player)
    AttemptInitWithRetry(player)
end)
