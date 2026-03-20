-- lua\modules\wall.lua
local PENETRATION_EPSILON = 1.0
local MAX_PENETRATION_ITERATIONS = 128
local INITIAL_STEP = 2.0
local BINARY_SEARCH_PRECISION = 2.0

--- 根据 ARC9 规则计算实体的扩展 AABB（将原包围盒从中心向外扩展 25%）。
--- @param ent Entity
--- @return Vector, Vector
local function GetExpandedAABB(ent)
    local mins, maxs = ent:WorldSpaceAABB()
    local wsc = ent:WorldSpaceCenter()
    local expMins = mins + (mins - wsc) * 0.25
    local expMaxs = maxs + (maxs - wsc) * 0.25
    return expMins, expMaxs
end

--- 判断射线点是否仍在指定实体（或世界）内部，完全贴合 ARC9 的 IsPenetrating 逻辑。
--- @param ptr TraceResult
--- @param ptrent Entity
--- @return boolean
local function IsPenetrating(ptr, ptrent)
    if ptrent:IsWorld() then
        return not ptr.StartSolid or ptr.AllSolid
    elseif IsValid(ptrent) then
        local mins, maxs = GetExpandedAABB(ptrent)
        local withinbounding = ptr.HitPos:WithinAABox(mins, maxs)
        if withinbounding then
            return true
        end
    end
    return false
end

--- 通用厚度测量：指数步进 + 二分查找。
--- 从内部点 startPos 沿 dir 方向追踪，直至穿出目标实体，返回厚度、出口点和材质。
--- @param params table { startPos, dir, entity, maxDist, firstMatType }
--- @return number, Vector, number
local function MeasureThickness(params)
    local startPos = params.startPos
    local dir = params.dir
    local target = params.entity
    local maxDist = params.maxDist
    local firstMatType = params.firstMatType or 0

    local function TraceSegment(from, to)
        return util.TraceLine({
            start = from,
            endpos = to,
            mask = MASK_SHOT
        })
    end

    local currentPos = startPos
    local lastInsidePos = currentPos
    local lastInsideTrace = nil
    local step = INITIAL_STEP
    local traveled = 0
    local foundExit = false
    local left, right, leftTrace, rightTrace

    while traveled < maxDist do
        local nextPos = currentPos + dir * step
        local trace = TraceSegment(currentPos, nextPos)
        local inside = (trace.Entity == target) and IsPenetrating(trace, target)

        if inside then
            traveled = traveled + step
            currentPos = nextPos
            lastInsidePos = currentPos
            lastInsideTrace = trace
            step = step * 2
        else
            left = lastInsidePos
            right = nextPos
            leftTrace = lastInsideTrace
            rightTrace = trace
            foundExit = true
            break
        end
    end

    if not foundExit then
        return traveled, currentPos, firstMatType
    end

    while right:Distance(left) >= BINARY_SEARCH_PRECISION do
        local mid = left + (right - left) * 0.5
        local midTrace = TraceSegment(left, mid)
        local midInside = (midTrace.Entity == target) and IsPenetrating(midTrace, target)
        if midInside then
            left = mid
            leftTrace = midTrace
        else
            right = mid
            rightTrace = midTrace
        end
    end

    local exitPos = right
    local thickness = startPos:Distance(exitPos)
    local matType = rightTrace.MatType or firstMatType
    return thickness, exitPos, matType
end

--- 实体墙快速测量：基于扩展 AABB 直接射线求交，性能更优。
--- 若起点不在扩展 AABB 内或求交失败，则自动回退到通用测量。
--- @param params table { startPos, dir, entity, maxDist, firstMatType }
--- @return number, Vector, number
local function MeasureEntityThicknessFast(params)
    local startPos = params.startPos
    local dir = params.dir
    local entity = params.entity
    local firstMatType = params.firstMatType or 0

    local expMins, expMaxs = GetExpandedAABB(entity)
    if not startPos:WithinAABox(expMins, expMaxs) then
        return MeasureThickness(params)
    end

    local function RayIntersectAABB(origin, dir, mins, maxs)
        local t1 = (mins.x - origin.x) / dir.x
        local t2 = (maxs.x - origin.x) / dir.x
        local tmin = math.min(t1, t2)
        local tmax = math.max(t1, t2)

        local ty1 = (mins.y - origin.y) / dir.y
        local ty2 = (maxs.y - origin.y) / dir.y
        tmin = math.max(tmin, math.min(ty1, ty2))
        tmax = math.min(tmax, math.max(ty1, ty2))

        local tz1 = (mins.z - origin.z) / dir.z
        local tz2 = (maxs.z - origin.z) / dir.z
        tmin = math.max(tmin, math.min(tz1, tz2))
        tmax = math.min(tmax, math.max(tz1, tz2))

        return tmin, tmax
    end

    local tmin, tmax = RayIntersectAABB(startPos, dir, expMins, expMaxs)
    if tmax > tmin and tmax > 0 then
        local exitPos = startPos + dir * tmax
        local thickness = tmax
        return thickness, exitPos, firstMatType
    else
        return MeasureThickness(params)
    end
end

--- 计算入射角（0° 掠射，90° 垂直）。
--- @param hitNormal Vector
--- @param shotDir Vector
--- @return number
local function GetIncidentAngle(hitNormal, shotDir)
    local dot = shotDir:Dot(hitNormal)
    local cosAngle = math.abs(dot)
    local angleRad = math.acos(math.Clamp(cosAngle, -1, 1))
    return 90 - math.deg(angleRad)
end

--- 主函数：从攻击者到受害者方向依次收集所有穿过的墙体信息。
--- 所有命中实体（包括世界）均视为墙体，返回信息列表。
--- @param attacker Entity
--- @param victim Entity
--- @param attackerPos Vector
--- @param victimPos Vector
--- @return table
function GetWallInfoAlongLine(attacker, victim, attackerPos, victimPos)
    local walls = {}
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

        if not trace.Hit or trace.HitSky then
            break
        end

        local hitEnt = trace.Entity
        local isWorld = hitEnt:IsWorld()
        local className = isWorld and "world" or hitEnt:GetClass()
        local incidentAngle = GetIncidentAngle(trace.HitNormal, dir)

        local measureParams = {
            startPos = trace.HitPos + dir * PENETRATION_EPSILON,
            dir = dir,
            entity = hitEnt,
            maxDist = remainingDist,
            firstMatType = trace.MatType
        }

        local thickness, exitPos, matType
        if isWorld then
            thickness, exitPos, matType = MeasureThickness(measureParams)
        else
            thickness, exitPos, matType = MeasureEntityThicknessFast(measureParams)
        end
        matType = matType or trace.MatType or 0

        table.insert(walls, {
            className = className,
            thickness = thickness,
            hitPos = trace.HitPos,
            exitPos = exitPos,
            matType = matType,
            incidentAngle = incidentAngle
        })

        if thickness == math.huge then
            break
        end

        currentPos = exitPos + dir * PENETRATION_EPSILON
        remainingDist = victimPos:Distance(currentPos)
        if remainingDist <= PENETRATION_EPSILON then
            break
        end
    end

    return walls
end
