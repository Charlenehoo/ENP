-- ==================== 模块级常量 ====================
local PENETRATION_EPSILON = 0.5 --- 偏移量（单位），用于进入/退出实体内部，避免表面判定歧义
local WORLD_STEP_SIZE = 1.0 --- 世界墙步进测量的步长（单位），平衡精度与性能
local WORLD_STEP_ITER_SAFETY_MARGIN = 100 --- 世界墙步进循环的安全裕量（应对浮点误差）
local MAX_PENETRATION_ITERATIONS = 100 --- 主循环最大迭代次数，防止无限穿透（安全保护）
local STEP_LENGTH = 2 --- 固定步长，由原 ARC9 步长公式在无限穿透力下计算得出（4 与 WORLD_STEP_SIZE*2 取小）

-- ==================== ARC9 核心判定函数 ====================

--- 判断子弹是否仍在当前实体（或世界）内部（ARC9 原版逻辑）
--- @param ptr TraceResult 当前步进的射线结果
--- @param ptrent Entity 当前穿透的实体（世界或具体实体）
--- @return boolean 仍在内部返回 true，已穿出返回 false
local function IsPenetrating(ptr, ptrent)
    if ptrent:IsWorld() then
        -- 世界判定：起点在固体中 或 整条线段全在固体中
        return ptr.StartSolid or ptr.AllSolid
    elseif IsValid(ptrent) then
        -- 实体判定：HitPos 是否在扩展 25% 的 AABB 内
        local mins, maxs = ptrent:WorldSpaceAABB()
        local wsc = ptrent:WorldSpaceCenter()
        -- 将包围盒从中心向外扩展 25%，补偿 hitbox 可能超出 AABB 的情况
        mins = mins + (mins - wsc) * 0.25
        maxs = maxs + (maxs - wsc) * 0.25
        return ptr.HitPos:WithinAABox(mins, maxs)
    end
    return false
end

-- ==================== 工具函数 ====================

--- 计算入射角（度），0=掠射，90=垂直
--- @param hitNormal Vector 击中点法线
--- @param shotDir Vector 射击方向（从枪口到击中点）
--- @return number
local function GetIncidentAngle(hitNormal, shotDir)
    local dot = shotDir:Dot(hitNormal)
    local cosAngle = math.abs(dot)
    local angleRad = math.acos(math.Clamp(cosAngle, -1, 1))
    return 90 - math.deg(angleRad)
end

-- ==================== 策略式厚度测量函数（完全对齐 ARC9 行为） ====================

--- 测量世界墙的厚度（模拟 ARC9 无限穿透力子弹）
--- @param params table 参数表，包含以下字段：
---   @field hitPos Vector 入口点
---   @field dir Vector 方向
---   @field maxDist number 最大搜索距离
---   @field firstMatType number? 后备材质
--- @return number thickness 厚度
--- @return Vector exitPos 出口点
--- @return number matType 材质类型
local function MeasureWorldThickness(params)
    local hitPos = params.hitPos
    local dir = params.dir
    local maxDist = params.maxDist
    local firstMatType = params.firstMatType

    -- 从入口点偏移进入世界内部（与 ARC9 一致）
    local currentPos = hitPos + dir * PENETRATION_EPSILON
    local thickness = 0
    local stepCount = 0
    local maxSteps = math.ceil(maxDist / WORLD_STEP_SIZE) + WORLD_STEP_ITER_SAFETY_MARGIN

    local lastTrace = nil

    while thickness < maxDist and stepCount < maxSteps do
        stepCount = stepCount + 1
        local nextPos = currentPos + dir * STEP_LENGTH

        local trace = util.TraceLine({
            start = currentPos,
            endpos = nextPos,
            mask = MASK_SHOT,
            collisiongroup = COLLISION_GROUP_DEBRIS -- 只与世界交互
        })

        -- 检测到天空盒：墙体无限厚
        if trace.HitSky then
            return math.huge, hitPos, firstMatType or 0
        end

        -- 检查是否仍处于世界内部（使用 ARC9 判定）
        if IsPenetrating(trace, trace.Entity) then
            -- 仍在世界内，继续步进
            thickness = thickness + STEP_LENGTH
            currentPos = nextPos
            lastTrace = trace
        else
            -- 已穿出世界，退出循环
            -- 出口点使用最后一次成功步进的 HitPos（性能优化，不追求极度精确）
            local exitPos = lastTrace and lastTrace.HitPos or hitPos
            local matType = (lastTrace and lastTrace.MatType) or firstMatType or 0
            return thickness, exitPos, matType
        end
    end

    -- 超过最大距离仍未穿出，返回当前厚度和终点
    return thickness, currentPos, firstMatType or 0
end

--- 测量实体墙的厚度（模拟 ARC9 无限穿透力子弹）
--- @param params table 参数表，包含以下字段：
---   @field hitPos Vector 入口点
---   @field dir Vector 方向
---   @field entity Entity 实体对象
---   @field maxDist number 第二次射线的最大距离
---   @field firstMatType number? 后备材质
--- @return number thickness 厚度
--- @return Vector exitPos 出口点
--- @return number matType 材质类型
local function MeasureEntityThickness(params)
    local hitPos = params.hitPos
    local dir = params.dir
    local entity = params.entity
    local maxDist = params.maxDist
    local firstMatType = params.firstMatType

    -- 从入口点偏移进入实体内部
    local currentPos = hitPos + dir * PENETRATION_EPSILON
    local thickness = 0
    local stepCount = 0
    local maxSteps = math.ceil(maxDist / WORLD_STEP_SIZE) + WORLD_STEP_ITER_SAFETY_MARGIN

    local lastTrace = nil

    while thickness < maxDist and stepCount < maxSteps do
        stepCount = stepCount + 1
        local nextPos = currentPos + dir * STEP_LENGTH

        local trace = util.TraceLine({
            start = currentPos,
            endpos = nextPos,
            mask = MASK_SHOT,
            filter = {entity},
            whitelist = true
        })

        -- 实体测量中也可能遇到天空盒（例如实体位于世界边缘）
        if trace.HitSky then
            return math.huge, hitPos, firstMatType or 0
        end

        -- 检查是否仍在该实体内部
        if IsPenetrating(trace, entity) then
            thickness = thickness + STEP_LENGTH
            currentPos = nextPos
            lastTrace = trace
        else
            local exitPos = lastTrace and lastTrace.HitPos or hitPos
            local matType = (lastTrace and lastTrace.MatType) or firstMatType or 0
            return thickness, exitPos, matType
        end
    end

    return thickness, currentPos, firstMatType or 0
end

-- ==================== 主函数 ====================
--- 获取从攻击者到受害者方向上的所有墙体信息，沿途依次检测并收集。
--- 世界始终被视为墙体；其他实体根据 wallClassNames 参数分类为墙体或非墙体。
---
--- @param attacker {Entity} 攻击者实体，用于过滤，避免自身被计入墙体
--- @param victim {Entity} 目标实体，用于过滤，避免自身被计入墙体
--- @param attackerPos {Vector} 攻击起始位置
--- @param victimPos {Vector} 目标位置
--- @param wallClassNames {table?} 被视为墙体的实体类名列表；若为 nil，则所有实体均不作为墙体（世界仍作为墙体）
---
--- @return { table } walls: 墙体信息列表，每项包含：
---   @field className {string} 类名（世界墙为 "world"）
---   @field thickness {number} 沿方向的厚度（浮点数）
---   @field matType {number} ARC9材质枚举，若无则为0
---   @field incidentAngle {number} 入射角，单位度，0=掠射，90=垂直
---
--- @return { table } others: 非墙体实体信息列表，每项结构与 walls 完全相同：
---   @field className {string} 实体的类名
---   @field thickness {number} 沿方向的厚度（浮点数）
---   @field matType {number} ARC9材质枚举，若无则为0
---   @field incidentAngle {number} 入射角，单位度，0=掠射，90=垂直
---
--- @note 两个返回值结构对偶，walls 记录被判定为墙的实体（包括世界），others 记录其余穿透的实体。
--- @note attacker 与 victim 均为实体，用于射线过滤，防止将自身或目标计入墙体。
function GetWallInfoAlongLine(attacker, victim, attackerPos, victimPos, wallClassNames)
    local walls = {}
    local others = {}
    local currentPos = attackerPos
    local dir = (victimPos - attackerPos):GetNormalized()
    local remainingDist = attackerPos:Distance(victimPos)
    local iter = 0
    local filterEnts = {attacker, victim}

    while remainingDist > 0 and iter < MAX_PENETRATION_ITERATIONS do
        iter = iter + 1

        local trace = util.TraceLine({
            start = currentPos,
            endpos = victimPos,
            mask = MASK_SHOT,
            filter = filterEnts
        })

        if not trace.Hit then
            break
        end

        -- 首次击中天空盒：无墙体
        if trace.HitSky then
            break
        end

        local hitEnt = trace.Entity
        local isWorld = hitEnt:IsWorld()
        local className = isWorld and "world" or hitEnt:GetClass()
        local incidentAngle = GetIncidentAngle(trace.HitNormal, dir)

        -- 构造统一的测量参数表
        local measureParams = {
            hitPos = trace.HitPos,
            dir = dir,
            maxDist = remainingDist,
            firstMatType = trace.MatType
        }
        if not isWorld then
            measureParams.entity = hitEnt
        end

        local thickness, exitPos, matType
        if isWorld then
            thickness, exitPos, matType = MeasureWorldThickness(measureParams)
        else
            thickness, exitPos, matType = MeasureEntityThickness(measureParams)
        end

        matType = matType or trace.MatType or 0

        local info = {
            className = className,
            thickness = thickness,
            matType = matType,
            incidentAngle = incidentAngle
        }

        -- 判断是否为墙体
        if isWorld then
            table.insert(walls, info)
        else
            local isWall = false
            if wallClassNames then
                for _, cls in ipairs(wallClassNames) do
                    if cls == className then
                        isWall = true
                        break
                    end
                end
            end
            if isWall then
                table.insert(walls, info)
            else
                table.insert(others, info)
            end
        end

        -- 如果厚度为无穷大，则后续无法穿透，终止循环
        if thickness == math.huge then
            break
        end

        currentPos = exitPos + dir * PENETRATION_EPSILON
        remainingDist = victimPos:Distance(currentPos)

        if remainingDist <= PENETRATION_EPSILON then
            break
        end
    end

    return walls, others
end

