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
    local walls = {} -- 墙体信息列表
    local others = {} -- 非墙实体信息列表
    local epsilon = 0.5 -- 偏移量，用于进入/退出实体内部
    local stepSize = 1.0 -- 世界墙步进测量的步长（单位）

    -- 工具函数：判断点是否在世界内部（只考虑世界固体）
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

    -- 工具函数：计算入射角（度），0=掠射，90=垂直
    local function GetIncidentAngle(hitNormal, shotDir)
        local dot = shotDir:Dot(hitNormal)
        -- 取绝对值，因为法线方向可能向内或向外
        local cosAngle = math.abs(dot)
        local angleRad = math.acos(math.Clamp(cosAngle, -1, 1))
        return 90 - math.deg(angleRad)
    end

    -- 工具函数：测量世界墙的厚度（步进法）
    -- 参数：入口点hitPos，方向dir，最大搜索距离maxDist
    -- 返回：厚度，出口点，材质类型
    local function MeasureWorldThickness(hitPos, dir, maxDist)
        local inside = hitPos + dir * epsilon
        local thickness = 0
        local current = inside
        local maxIter = maxDist / stepSize + 100 -- 防止无限循环

        while thickness < maxDist and maxIter > 0 do
            maxIter = maxIter - 1
            -- 检查当前点是否仍世界内部
            if not IsPointInWorld(current) then
                -- 已穿出，从上一个内部点精确找到出口
                local prev = current - dir * stepSize
                local tr = util.TraceLine({
                    start = prev,
                    endpos = current,
                    mask = MASK_SOLID,
                    filter = function(ent)
                        return false
                    end -- 只检测世界
                })
                if tr.Hit and tr.Entity:IsWorld() then
                    thickness = hitPos:Distance(tr.HitPos)
                    return thickness, tr.HitPos, tr.MatType
                else
                    -- 回退到近似值
                    thickness = thickness - stepSize + stepSize * 0.5
                    return thickness, prev + dir * stepSize * 0.5, 0
                end
            end
            thickness = thickness + stepSize
            current = current + dir * stepSize
        end
        -- 超过最大距离仍未穿出（可能是无限空间），返回当前厚度和终点
        return thickness, current, 0
    end

    -- 工具函数：测量实体墙（或任何实体）的厚度（两次射线法）
    -- 参数：第一次击中信息tr，方向dir
    -- 返回：厚度，出口点，材质类型（材质类型可直接从tr获取）
    local function MeasureEntityThickness(tr, dir)
        local hit1 = tr.HitPos
        local ent = tr.Entity
        -- 从入口点偏移进入实体内部
        local inside = hit1 + dir * epsilon
        -- 第二次射线，只检测同一个实体，一直向前直到穿出
        local tr2 = util.TraceLine({
            start = inside,
            endpos = inside + dir * 10000, -- 足够长的距离
            mask = MASK_SHOT,
            filter = function(e)
                return e == ent
            end -- 只检测该实体
        })
        if tr2.Hit and tr2.Entity == ent then
            local exitPos = tr2.HitPos
            local thickness = hit1:Distance(exitPos)
            return thickness, exitPos, tr2.MatType
        else
            -- 未击中同一实体（可能偏移过大或实体太薄），尝试减小偏移重试？这里简单返回0厚度并退回到入口点外侧
            -- 实际应用中可考虑步进法作为后备，但此处按设计假设成功
            return 0, hit1 + dir * epsilon, tr.MatType
        end
    end

    -- 主循环：从攻击者位置开始，向目标位置逐层穿透
    local currentPos = attackerPos
    local dir = (victimPos - attackerPos):GetNormalized()
    local totalDist = attackerPos:Distance(victimPos)
    local remainingDist = totalDist
    local maxIter = 100 -- 防止无限循环（比如无限虚空）

    -- 过滤表：忽略攻击者和受害者，避免将自身或目标误作墙体
    local filterEnts = {attacker, victim}

    while remainingDist > 0 and maxIter > 0 do
        maxIter = maxIter - 1

        -- 从当前点向目标点发射射线
        local tr = util.TraceLine({
            start = currentPos,
            endpos = victimPos,
            mask = MASK_SHOT,
            filter = filterEnts
        })

        if not tr.Hit then
            -- 没有击中任何物体，到达目标点或虚空，结束
            break
        end

        -- 处理击中点
        local hitEnt = tr.Entity
        local isWorld = hitEnt:IsWorld()
        local className = isWorld and "world" or hitEnt:GetClass()

        -- 计算入射角
        local incidentAngle = GetIncidentAngle(tr.HitNormal, dir)

        -- 根据击中类型测量厚度
        local thickness, exitPos, matType
        if isWorld then
            -- 世界墙测量（步进法）
            thickness, exitPos, matType = MeasureWorldThickness(tr.HitPos, dir, remainingDist)
        else
            -- 实体测量（两次射线法）
            thickness, exitPos, matType = MeasureEntityThickness(tr, dir)
            -- 如果实体被忽略（wallClassName为nil或不匹配），则记录到others，否则记录到walls
        end

        -- 记录信息（材质类型优先使用测量返回的，若无则用tr.MatType）
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

        -- 更新当前位置到出口点外侧，准备下一层穿透
        currentPos = exitPos + dir * epsilon
        remainingDist = victimPos:Distance(currentPos)

        -- 如果出口点已经超过或接近目标，可提前结束（避免浮点误差）
        if remainingDist <= epsilon then
            break
        end
    end

    return walls, others
end
