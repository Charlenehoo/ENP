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

-- 辅助函数：从 trace 或材质数值获取材质名称
local function GetMaterialName(matType)
    return MAT_NAMES[matType] or string.format("未知 (%d)", matType)
end

-- 工具枪定义
TOOL.Category = "Test"
TOOL.Name = "Wall Inspector"

-- 初始化工具实体时创建存储表
function TOOL:Initialize()
    self.Victim = nil
    self.WallClasses = {} -- 存储墙体类名的集合（去重）
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

-- 右键：将命中实体的类名添加到墙体列表
function TOOL:RightClick(trace)
    local ply = self:GetOwner()
    if not IsValid(ply) then
        return false
    end

    -- 确保 WallClasses 已初始化
    self.WallClasses = self.WallClasses or {}

    local ent = trace.Entity
    if IsValid(ent) then
        local class = ent:GetClass()
        -- 去重添加
        if not table.HasValue(self.WallClasses, class) then
            table.insert(self.WallClasses, class)
            print("[Wall Inspector] 墙体类名已添加: " .. class)
        else
            print("[Wall Inspector] 类名已存在: " .. class)
        end
        -- 打印当前列表（安全处理）
        local wallStr = (#self.WallClasses > 0) and table.concat(self.WallClasses, ", ") or "空"
        print("[Wall Inspector] 当前墙体类名列表: " .. wallStr)
    else
        print("[Wall Inspector] 未击中有效实体")
    end
    return true
end

-- 换弹：执行墙体检测并打印结果
function TOOL:Reload(trace)
    local ply = self:GetOwner()
    if not IsValid(ply) then
        return
    end

    -- 确保 WallClasses 已初始化
    self.WallClasses = self.WallClasses or {}

    -- 检查受害者是否有效
    if not IsValid(self.Victim) then
        print("[Wall Inspector] 错误：受害者无效，请先用左键设置一个NPC")
        return
    end

    -- 获取攻击者和受害者的位置
    local attackerPos = ply:GetShootPos() -- 玩家眼睛位置
    local victimPos = self.Victim:EyePos() -- NPC眼睛位置

    -- 调用墙体检测函数（传入 nil 表示所有实体都不视为墙）
    local walls, others = GetWallInfoAlongLine(ply, self.Victim, attackerPos, victimPos, nil)

    -- 根据 self.WallClasses 将 others 中符合条件的实体移到 walls
    local finalWalls = {}
    -- 先添加世界墙
    for _, w in ipairs(walls) do
        table.insert(finalWalls, w)
    end
    -- 遍历 others，如果类名在墙体列表中，则作为墙体加入
    local filteredOthers = {}
    for _, o in ipairs(others) do
        if table.HasValue(self.WallClasses, o.className) then
            table.insert(finalWalls, o)
        else
            table.insert(filteredOthers, o)
        end
    end

    -- 安全构造墙体类名字符串
    local wallClassesStr = (#self.WallClasses > 0) and table.concat(self.WallClasses, ", ") or "无"

    -- 打印结果
    print("========== 墙体检测结果 ==========")
    print(string.format("攻击者位置: %s", tostring(attackerPos)))
    print(string.format("受害者位置: %s", tostring(victimPos)))
    print(string.format("墙体类名列表: %s", wallClassesStr))

    print("--- 墙体（含世界墙） ---")
    if #finalWalls == 0 then
        print("  无")
    else
        for i, info in ipairs(finalWalls) do
            local matName = GetMaterialName(info.matType)
            local thicknessStr = info.thickness == math.huge and "无限" or string.format("%.2f", info.thickness)
            print(string.format("  %d. 类名: %s | 厚度: %s | 材质: %s | 入射角: %.1f°", i, info.className,
                thicknessStr, matName, info.incidentAngle))
        end
    end

    print("--- 其他穿透实体 ---")
    if #filteredOthers == 0 then
        print("  无")
    else
        for i, info in ipairs(filteredOthers) do
            local matName = GetMaterialName(info.matType)
            print(string.format("  %d. 类名: %s | 厚度: %.2f | 材质: %s | 入射角: %.1f°", i, info.className,
                info.thickness, matName, info.incidentAngle))
        end
    end
    print("====================================")
end

-- Think 函数（可为空）
function TOOL:Think()
end
