-- lua\autorun\init.lua
if SERVER then
    -- include("modules/wall.lua")
    include("modules/core/constants.lua")
    include("modules/core/bone/bone_names.lua")
    include("modules/core/bone/bone_init.lua")
    include("modules/core/ragdoll_provider.lua")
    include("modules/core/attacker_manager.lua")
    include("modules/core/tick.lua")
    include("modules/util/geometry.lua")
    include("modules/plugins/align_to_plane.lua")
    include("modules/plugins/distance_limit.lua")
end
