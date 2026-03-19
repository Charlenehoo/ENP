-- ==================== 模块级常量 ====================
local PENETRATION_EPSILON = 0.5 --- 偏移量（单位），用于进入/退出实体内部，避免表面判定歧义
local WORLD_STEP_SIZE = 1.0 --- 世界墙步进测量的步长（单位），平衡精度与性能
local WORLD_STEP_ITER_SAFETY_MARGIN = 100 --- 世界墙步进循环的安全裕量（应对浮点误差）
local MAX_TRACE_DIST = 10000 --- 实体测量第二次射线的最大距离（远大于任何可能穿透距离）
local MAX_PENETRATION_ITERATIONS = 100 --- 主循环最大迭代次数，防止无限穿透（安全保护）

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

-- ==================== 策略式厚度测量函数（接受参数表） ====================

--- 测量世界墙的厚度（步进法，使用ARC9穿透判定逻辑）
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

    local inside = hitPos + dir * PENETRATION_EPSILON
    local currentPos = inside
    local thickness = 0
    -- 理论最大步数加上安全裕量
    local maxSteps = math.ceil(maxDist / WORLD_STEP_SIZE) + WORLD_STEP_ITER_SAFETY_MARGIN
    local step = 0

    while thickness < maxDist and step < maxSteps do
        step = step + 1
        local nextPos = currentPos + dir * WORLD_STEP_SIZE
        local trace = util.TraceLine({
            start = currentPos,
            endpos = nextPos,
            mask = MASK_SHOT, -- 与ARC9一致
            collisiongroup = COLLISION_GROUP_DEBRIS -- 只与世界交互，忽略动态实体
        })

        -- ARC9的世界穿透判定：!StartSolid 或 AllSolid 为真表示仍处于世界内部
        if not trace.StartSolid or trace.AllSolid then
            -- 仍在世界内，继续步进
            thickness = thickness + WORLD_STEP_SIZE
            currentPos = nextPos
        else
            -- 已穿出世界，需要找到精确出口点
            -- 从 currentPos 向 nextPos 做一次精确射线，取 HitPos 作为出口
            local exitTrace = util.TraceLine({
                start = currentPos,
                endpos = nextPos,
                mask = MASK_SHOT,
                collisiongroup = COLLISION_GROUP_DEBRIS
            })
            if exitTrace.Hit and exitTrace.Entity:IsWorld() then
                local exitPos = exitTrace.HitPos
                thickness = hitPos:Distance(exitPos)
                return thickness, exitPos, exitTrace.MatType or firstMatType or 0
            else
                -- 理论上不应发生，若发生则返回当前累计厚度和近似出口
                return thickness, currentPos, firstMatType or 0
            end
        end
    end

    -- 超过最大距离仍未穿出，返回当前厚度和终点
    return thickness, currentPos, firstMatType or 0
end

--- 测量实体墙（或任何实体）的厚度（两次射线法）
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

    local inside = hitPos + dir * PENETRATION_EPSILON
    local exitTrace = util.TraceLine({
        start = inside,
        endpos = inside + dir * maxDist,
        mask = MASK_SHOT,
        filter = {entity}, -- 只检测该实体
        whitelist = true -- 白名单模式
    })
    if exitTrace.Hit and exitTrace.Entity == entity then
        local exitPos = exitTrace.HitPos
        local thickness = hitPos:Distance(exitPos)
        return thickness, exitPos, exitTrace.MatType or firstMatType or 0
    else
        -- 未能正常测出厚度，回退到入口点外侧并返回0厚度
        return 0, hitPos + dir * PENETRATION_EPSILON, firstMatType or 0
    end
end

-- ==================== 主函数 ====================

--- 获取从攻击者到受害者方向上的所有墙体信息，沿途依次检测并收集。
--- 世界始终被视为墙体；其他实体根据 wallClassName 参数分类为墙体或非墙体。
---
--- @param attacker {Entity} 攻击者实体，用于过滤，避免自身被计入墙体
--- @param victim {Entity} 目标实体，用于过滤，避免自身被计入墙体
--- @param attackerPos {Vector} 攻击起始位置
--- @param victimPos {Vector} 目标位置
--- @param wallClassName {string?} 被视为墙体的实体类名；若为 nil，则所有实体均不作为墙体（世界仍作为墙体）
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
function GetWallInfoAlongLine(attacker, victim, attackerPos, victimPos, wallClassName)
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

        if isWorld then
            table.insert(walls, info)
        else
            if wallClassName and hitEnt:GetClass() == wallClassName then
                table.insert(walls, info)
            else
                table.insert(others, info)
            end
        end

        currentPos = exitPos + dir * PENETRATION_EPSILON
        remainingDist = victimPos:Distance(currentPos)

        if remainingDist <= PENETRATION_EPSILON then
            break
        end
    end

    return walls, others
end
