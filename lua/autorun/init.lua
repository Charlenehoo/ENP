-- lua\autorun\init.lua
if SERVER then
    -- include("modules/wall.lua")
    include("modules/core/constants.lua")
    include("modules/core/bone/bone_names.lua")
    include("modules/core/bone/bone_init.lua")
    include("modules/core/attacker_manager.lua")
    include("modules/core/tick.lua")
end
