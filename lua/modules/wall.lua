-- ==================== 模块级常量 ====================
local PENETRATION_EPSILON = 0.5 --- 偏移量（单位），用于进入/退出实体内部，避免表面判定歧义
local WORLD_STEP_SIZE = 1.0 --- 世界墙步进测量的步长（单位），平衡精度与性能
local MAX_TRACE_DIST = 10000 --- 实体测量第二次射线的最大距离（远大于任何可能穿透距离）

-- ==================== 工具函数 ====================

--- 判断点是否在世界固体内部（排除所有实体）
--- @param point Vector 要检测的点
--- @return boolean
local function IsPointInWorld(point)
    local tr = util.TraceLine({
        start = point,
        endpos = point + Vector(1, 0, 0), -- 任意方向极小位移
        mask = MASK_SOLID,
        filter = function(ent)
            return false
        end -- 排除所有实体，只检测世界
    })
    return tr.StartSolid
end

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

-- ==================== 策略式厚度测量函数（统一签名） ====================

--- 测量世界墙的厚度（步进法）
--- 参数符合统一策略签名，entity 参数被忽略（传 nil 即可）
--- @param hitPos Vector 入口点（表面击中点）
--- @param dir Vector 方向（从攻击者到目标）
--- @param entity Entity? 忽略，只为保持签名一致
--- @param maxDist number 最大搜索距离（不能超过到目标的剩余距离）
--- @param firstMatType number? 后备材质（入口材质，当无法获取出口材质时使用）
--- @return number thickness 厚度
--- @return Vector exitPos 出口点
--- @return number matType 材质类型（若无法获取则使用 firstMatType 或 0）
local function MeasureWorldThickness(hitPos, dir, entity, maxDist, firstMatType)
    local inside = hitPos + dir * PENETRATION_EPSILON
    local thickness = 0
    local current = inside
    local maxIter = maxDist / WORLD_STEP_SIZE + 100

    while thickness < maxDist and maxIter > 0 do
        maxIter = maxIter - 1
        if not IsPointInWorld(current) then
            -- 已穿出，从上一个内部点精确找到出口
            local prev = current - dir * WORLD_STEP_SIZE
            local tr = util.TraceLine({
                start = prev,
                endpos = current,
                mask = MASK_SOLID,
                filter = function(ent)
                    return false
                end
            })
            if tr.Hit and tr.Entity:IsWorld() then
                thickness = hitPos:Distance(tr.HitPos)
                return thickness, tr.HitPos, tr.MatType or firstMatType or 0
            else
                thickness = thickness - WORLD_STEP_SIZE + WORLD_STEP_SIZE * 0.5
                return thickness, prev + dir * WORLD_STEP_SIZE * 0.5, firstMatType or 0
            end
        end
        thickness = thickness + WORLD_STEP_SIZE
        current = current + dir * WORLD_STEP_SIZE
    end
    -- 超过最大距离仍未穿出，返回当前厚度和终点
    return thickness, current, firstMatType or 0
end

--- 测量实体墙（或任何实体）的厚度（两次射线法）
--- @param hitPos Vector 入口点（表面击中点）
--- @param dir Vector 方向（从攻击者到目标）
--- @param entity Entity 实体对象（用于第二次射线过滤）
--- @param maxDist number 第二次射线的最大距离（通常为剩余距离或足够大的常数）
--- @param firstMatType number? 后备材质（入口材质，当第二次射线无法获取材质时使用）
--- @return number thickness 厚度
--- @return Vector exitPos 出口点
--- @return number matType 材质类型（优先使用出口材质，否则使用 firstMatType 或 0）
local function MeasureEntityThickness(hitPos, dir, entity, maxDist, firstMatType)
    local inside = hitPos + dir * PENETRATION_EPSILON
    local tr2 = util.TraceLine({
        start = inside,
        endpos = inside + dir * maxDist,
        mask = MASK_SHOT,
        filter = function(e)
            return e == entity
        end
    })
    if tr2.Hit and tr2.Entity == entity then
        local exitPos = tr2.HitPos
        local thickness = hitPos:Distance(exitPos)
        return thickness, exitPos, tr2.MatType or firstMatType or 0
    else
        -- 未能正常测出厚度（可能实体过薄或射线超出），回退到入口点外侧并返回0厚度
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
    local totalDist = attackerPos:Distance(victimPos)
    local remainingDist = totalDist
    local maxIter = 100
    local filterEnts = {attacker, victim}

    while remainingDist > 0 and maxIter > 0 do
        maxIter = maxIter - 1

        local tr = util.TraceLine({
            start = currentPos,
            endpos = victimPos,
            mask = MASK_SHOT,
            filter = filterEnts
        })

        if not tr.Hit then
            break
        end

        local hitEnt = tr.Entity
        local isWorld = hitEnt:IsWorld()
        local className = isWorld and "world" or hitEnt:GetClass()
        local incidentAngle = GetIncidentAngle(tr.HitNormal, dir)

        local thickness, exitPos, matType

        if isWorld then
            -- 世界墙测量：使用统一签名的世界测量函数
            thickness, exitPos, matType = MeasureWorldThickness(tr.HitPos, dir, nil, remainingDist, tr.MatType)
        else
            -- 实体测量：使用统一签名的实体测量函数
            -- 最大距离取 remainingDist（但实体测量内部可能用到 MAX_TRACE_DIST，此处为了统一，使用 remainingDist 即可，也可用 math.min(remainingDist, MAX_TRACE_DIST)）
            thickness, exitPos, matType = MeasureEntityThickness(tr.HitPos, dir, hitEnt, remainingDist, tr.MatType)
        end

        matType = matType or tr.MatType or 0

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
