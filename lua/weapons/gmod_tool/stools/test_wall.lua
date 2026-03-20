-- 材质名称映射表（来自参考工具）
local MAT_NAMES = {
    [65] = "MAT_ANTLION",
    [66] = "MAT_BLOODYFLESH",
    [67] = "MAT_CONCRETE",
    [68] = "MAT_DIRT",
    [69] = "MAT_EGGSHELL",
    [70] = "MAT_FLESH",
    [71] = "MAT_GRATE",
    [72] = "MAT_ALIENFLESH",
    [73] = "MAT_CLIP",
    [74] = "MAT_SNOW",
    [76] = "MAT_PLASTIC",
    [77] = "MAT_METAL",
    [78] = "MAT_SAND",
    [79] = "MAT_FOLIAGE",
    [80] = "MAT_COMPUTER",
    [83] = "MAT_SLOSH",
    [84] = "MAT_TILE",
    [85] = "MAT_GRASS",
    [86] = "MAT_VENT",
    [87] = "MAT_WOOD",
    [88] = "MAT_DEFAULT",
    [89] = "MAT_GLASS",
    [90] = "MAT_WARPSHIELD"
}

-- 辅助函数：从材质数值获取材质名称
local function GetMaterialName(matType)
    return MAT_NAMES[matType] or string.format("未知 (%d)", matType)
end

-- 辅助函数：判断值是否在表中
local function HasValue(tbl, val)
    for _, v in ipairs(tbl) do
        if v == val then
            return true
        end
    end
    return false
end

-- 工具枪定义
TOOL.Category = "Test"
TOOL.Name = "Wall Inspector"

function TOOL:Initialize()
    self.Victim = nil
    self.WallClasses = {} -- 存储墙体类名的集合（仅用于视觉高亮）
end

-- 左键：保存命中的NPC作为受害者
function TOOL:LeftClick(trace)
    local ply = self:GetOwner()
    if not IsValid(ply) then
        return false
    end

    local ent = trace.Entity
    if IsValid(ent) and ent:IsNPC() then
        self.Victim = ent
        print("[Wall Inspector] 受害者已设置为: " .. ent:GetClass())
    else
        print("[Wall Inspector] 请击中一个NPC来设置受害者")
    end
    return true
end

-- 换弹：执行墙体检测并打印结果，同时绘制路径
function TOOL:Reload(trace)
    local ply = self:GetOwner()
    if not IsValid(ply) then
        return
    end

    self.WallClasses = self.WallClasses or {}

    if not IsValid(self.Victim) then
        print("[Wall Inspector] 错误：受害者无效，请先用左键设置一个NPC")
        return
    end

    local attackerPos = ply:GetShootPos()
    local victimPos = self.Victim:EyePos()

    -- 调用墙体检测函数（新签名，只返回墙体列表）
    local walls = GetWallInfoAlongLine(ply, self.Victim, attackerPos, victimPos)

    -- 构造高亮类名字符串
    local wallClassesStr = (#self.WallClasses > 0) and table.concat(self.WallClasses, ", ") or "无"

    -- 打印结果
    print("========== 墙体检测结果 ==========")
    print(string.format("攻击者位置: %s", tostring(attackerPos)))
    print(string.format("受害者位置: %s", tostring(victimPos)))
    print(string.format("高亮类名列表: %s", wallClassesStr))

    print("--- 墙体信息 ---")
    if #walls == 0 then
        print("  无")
    else
        for i, info in ipairs(walls) do
            local matName = GetMaterialName(info.matType)
            local thicknessStr = info.thickness == math.huge and "无限" or string.format("%.2f", info.thickness)
            print(string.format("  %d. 类名: %s | 厚度: %s | 材质: %s | 入射角: %.1f°", i, info.className,
                thicknessStr, matName, info.incidentAngle))
        end
    end
    print("====================================")

    -- 绘制路径（持续 60 秒）
    local lineDuration = 60
    local colorAir = Color(200, 200, 200, 255)
    local colorWorld = Color(255, 0, 0, 255)
    local colorWall = Color(0, 255, 0, 255) -- 用户高亮的墙体类
    local colorOther = Color(0, 0, 255, 255) -- 其他墙体

    -- 合并所有段，按入射点排序
    local allSegments = {}
    for _, info in ipairs(walls) do
        table.insert(allSegments, {
            className = info.className,
            hitPos = info.hitPos,
            exitPos = info.exitPos,
            isWorld = (info.className == "world")
        })
    end
    table.sort(allSegments, function(a, b)
        return a.hitPos:DistToSqr(attackerPos) < b.hitPos:DistToSqr(attackerPos)
    end)

    local prevPos = attackerPos
    for _, seg in ipairs(allSegments) do
        -- 空气段
        if prevPos ~= seg.hitPos then
            debugoverlay.Line(prevPos, seg.hitPos, lineDuration, colorAir, true)
        end
        -- 物体内部段
        if seg.hitPos ~= seg.exitPos then
            local color
            if seg.isWorld then
                color = colorWorld
            elseif HasValue(self.WallClasses, seg.className) then
                color = colorWall
            else
                color = colorOther
            end
            debugoverlay.Line(seg.hitPos, seg.exitPos, lineDuration, color, true)
        end
        prevPos = seg.exitPos
    end
    -- 最后一段空气
    if prevPos ~= victimPos then
        debugoverlay.Line(prevPos, victimPos, lineDuration, colorAir, true)
    end
end
