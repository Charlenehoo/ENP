-- lua\modules\util.lua
ENP = ENP or {}
ENP.Util = ENP.Util or {} -- 避免覆盖已有字段

local EPS = 1e-8
local ZERO_VECTOR = Vector(0, 0, 0)

--- 计算直线与平面的交点
--- 直线由起点 startPoint 指向终点 endPoint 定义（方向为 endPoint - startPoint，必须非零），
--- 平面由一点 planePoint 和单位法向量 planeNormal 定义（必须为单位向量）。
--- 若无唯一交点（平行或直线在平面上）返回 nil。
--- @param startPoint Vector 直线起点
--- @param endPoint Vector 直线终点（确定方向，不能与起点重合）
--- @param planePoint Vector 平面上一点
--- @param planeNormal Vector 平面单位法向量（必须归一化）
--- @return Vector|nil 交点坐标（无限直线上的点），若无唯一交点则返回 nil
function ENP.Util.ComputeLinePlaneIntersection(startPoint, endPoint, planePoint, planeNormal)
    local lineVec = endPoint - startPoint
    -- 注意：调用者必须保证 lineVec 非零，planeNormal 为单位向量

    local denom = lineVec:Dot(planeNormal)
    if math.abs(denom) < EPS then
        return nil -- 平行或直线在平面内
    end

    local t = -((startPoint - planePoint):Dot(planeNormal)) / denom
    return startPoint + lineVec * t
end

--- 计算直线与平面的交点
--- 直线由起点 startPoint 指向终点 endPoint 定义（方向为 endPoint - startPoint，必须非零），
--- 平面由一点 planePoint 和单位法向量 unitNormal 定义（必须为单位向量）。
--- 若无唯一交点（平行或直线在平面上）返回 nil。
--- @param startPoint Vector 直线起点
--- @param endPoint Vector 直线终点（确定方向，不能与起点重合）
--- @param planePoint Vector 平面上一点
--- @param unitNormal Vector 平面单位法向量（必须归一化）
--- @return Vector|nil 交点坐标（无限直线上的点），若无唯一交点则返回 nil
function ENP.Util.ComputeLinePlaneIntersection(startPoint, endPoint, planePoint, unitNormal)
    local lineVec = endPoint - startPoint
    -- 调用者必须保证 lineVec 非零，unitNormal 为单位向量

    local denom = lineVec:Dot(unitNormal)
    if math.abs(denom) < EPS then
        return nil -- 平行或直线在平面内
    end

    local t = -((startPoint - planePoint):Dot(unitNormal)) / denom
    return startPoint + lineVec * t
end

--- 计算直线与垂直平面的交点
--- 构造一个垂直于主轴 (axisStart→axisEnd) 且过偏移点 (axisStart + direction * offset) 的平面，
--- 然后求该平面与直线 (rayStart→axisEnd) 的交点。
--- 主轴方向必须非零，射线方向 (axisEnd - rayStart) 必须非零。
--- @param rayStart Vector 另一条直线的起点（与 axisEnd 确定直线）
--- @param axisStart Vector 主轴起点
--- @param axisEnd Vector 主轴终点（同时是另一条直线的终点）
--- @param offset number 从主轴起点沿方向的距离（可为负，正值为向终点方向）
--- @return Vector|nil 交点坐标，若无唯一交点则返回 nil
function ENP.Util.ComputeLinePerpendicularPlaneIntersection(rayStart, axisStart, axisEnd, offset)
    local planePoint, unitNormal = ENP.Util.ComputePlanePerpendicularToLine(axisStart, axisEnd, offset)
    -- ComputePlanePerpendicularToLine 返回的 unitNormal 已是单位向量
    return ENP.Util.ComputeLinePlaneIntersection(rayStart, axisEnd, planePoint, unitNormal)
end

--- 计算直线与轴对齐包围盒（AABB）的交点（返回离开点）
--- 直线由起点 startPoint 指向终点 endPoint 定义（方向必须非零），
--- AABB 由最小点 aabbMin 和最大点 aabbMax 定义（调用者应确保 aabbMin ≤ aabbMax，但函数内部会排序）。
--- 返回直线与 AABB 的交点中，参数 t 较大的那个点（即离开点）。若无交点则返回 nil。
--- @param startPoint Vector 直线起点
--- @param endPoint Vector 直线上另一点（确定方向，不能与起点重合）
--- @param aabbMin Vector AABB 最小点（各轴最小值）
--- @param aabbMax Vector AABB 最大点（各轴最大值）
--- @return Vector|nil 交点坐标（离开点），若无交点则返回 nil
function ENP.Util.ComputeLineAABBIntersection(startPoint, endPoint, aabbMin, aabbMax)
    local lineVec = endPoint - startPoint
    -- 调用者必须保证 lineVec 非零

    -- 确保盒子的各轴范围正确（调用者可选择自己排序，此处保留内部排序以增强鲁棒性）
    local boxMin = aabbMin:Min(aabbMax)
    local boxMax = aabbMin:Max(aabbMax)

    local tMin = -math.huge
    local tMax = math.huge

    for axis = 1, 3 do
        local d = lineVec[axis]
        local p0 = startPoint[axis]
        local min = boxMin[axis]
        local max = boxMax[axis]

        if math.abs(d) < EPS then
            -- 方向与轴平行，检查起点是否在盒子范围内（允许 EPS 容差）
            if p0 < min - EPS or p0 > max + EPS then
                return nil
            end
        else
            local invD = 1.0 / d
            local t1 = (min - p0) * invD
            local t2 = (max - p0) * invD
            if t1 > t2 then
                t1, t2 = t2, t1
            end
            if t1 > tMin then
                tMin = t1
            end
            if t2 < tMax then
                tMax = t2
            end
            if tMin > tMax + EPS then
                return nil
            end
        end
    end

    return startPoint + lineVec * tMax
end
