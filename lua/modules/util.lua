-- lua\modules\util.lua
ENP = ENP or {}
ENP.Util = {}

local EPS = 1e-8
local ZERO_VECTOR = Vector(0, 0, 0)

-- https://wiki.facepunch.com/gmod/Vector

--- 计算直线与平面的交点
--- 直线由起点 startPoint 指向终点 endPoint 定义（方向为 endPoint - startPoint，不能为零向量），平面由一点 planePoint 和法向量 planeNormal 定义。
--- 若无唯一交点（平行或直线在平面上）返回 nil；若直线方向为零或法向量为零则报错。
--- @param startPoint Vector 直线起点
--- @param endPoint Vector 直线终点（确定方向，不能与起点重合）
--- @param planePoint Vector 平面上一点
--- @param planeNormal Vector 平面法向量（非零）
--- @return Vector intersectionPoint 交点坐标（无限直线上的点），若无唯一交点则返回 nil
function ENP.Util.ComputeLinePlaneIntersection(startPoint, endPoint, planePoint, planeNormal)
    if planeNormal:IsEqualTol(ZERO_VECTOR, EPS) then
        error("平面法向量不能为零向量", 2)
    end

    local lineVec = endPoint - startPoint
    if lineVec:IsEqualTol(ZERO_VECTOR, EPS) then
        error("直线起点与终点重合，无法定义方向", 2)
    end

    -- 归一化法向量，使平行判断的 EPS 阈值具有统一尺度
    local unitNormal = planeNormal:GetNormalized()
    local denom = lineVec:Dot(unitNormal)
    if math.abs(denom) < EPS then
        return nil
    end

    local t = -((startPoint - planePoint):Dot(unitNormal)) / denom
    return startPoint + lineVec * t
end

--- 计算过给定点且垂直于指定直线的平面
--- 直线由起点 axisStart 指向终点 axisEnd 定义（方向为 axisEnd - axisStart，不能为零向量），offset 表示从起点沿该方向移动的距离（正值为向终点方向移动）。
--- 返回平面上的点及单位法向量（指向终点方向）。若两点重合则报错。
--- @param axisStart Vector 主轴起点
--- @param axisEnd Vector 主轴终点（确定方向）
--- @param offset number 从起点沿主轴方向的距离（可为负，正值为向终点方向）
--- @return Vector planePoint 平面上的点
--- @return Vector planeNormal 单位法向量（指向终点）
--- @usage local point, normal = ENP.Util.ComputePlanePerpendicularToLine(Vector(0,0,0), Vector(1,0,0), 2)
---        -- point = (2,0,0), normal = (1,0,0)
function ENP.Util.ComputePlanePerpendicularToLine(axisStart, axisEnd, offset)
    local lineVec = axisEnd - axisStart
    if lineVec:IsEqualTol(ZERO_VECTOR, EPS) then
        error("主轴两点重合，无法定义直线", 2)
    end
    local unitDir = lineVec:GetNormalized() -- 返回单位向量，不修改原变量
    return axisStart + unitDir * offset, unitDir
end

--- 计算直线与垂直平面的交点
--- 构造一个垂直于主轴 (axisStart→axisEnd) 且过偏移点 (axisStart + direction * offset) 的平面，
--- 然后求该平面与直线 (rayStart→axisEnd) 的交点。
--- 主轴方向为 axisEnd - axisStart，offset 为正时沿该方向移动；射线方向为 axisEnd - rayStart。
--- 若无唯一交点返回 nil，若主轴方向为零或射线方向为零则报错。
--- @param rayStart Vector 另一条直线的起点（与 axisEnd 确定直线）
--- @param axisStart Vector 主轴起点
--- @param axisEnd Vector 主轴终点（同时是另一条直线的终点）
--- @param offset number 从主轴起点沿方向的距离（可为负，正值为向终点方向）
--- @return Vector intersectionPoint 交点坐标，若无唯一交点则返回 nil
function ENP.Util.ComputeLinePerpendicularPlaneIntersection(rayStart, axisStart, axisEnd, offset)
    local planePoint, planeNormal = ENP.Util.ComputePlanePerpendicularToLine(axisStart, axisEnd, offset)
    return ENP.Util.ComputeLinePlaneIntersection(rayStart, axisEnd, planePoint, planeNormal)
end

--- 计算直线与轴对齐包围盒（AABB）的交点（返回离开点）
--- 直线由起点 startPoint 指向终点 endPoint 定义（方向为 endPoint - startPoint，不能为零向量），AABB 由最小点 aabbMin 和最大点 aabbMax 定义。
--- 返回直线与 AABB 的交点中，参数 t 较大的那个点（即离开点）。若无交点则返回 nil。
--- 若直线方向为零向量则报错。
--- 注意：aabbMin 和 aabbMax 不必严格满足 min ≤ max，函数内部会进行排序。
--- @param startPoint Vector 直线起点
--- @param endPoint Vector 直线上另一点（确定方向，不能与起点重合）
--- @param aabbMin Vector AABB 最小点（各轴最小值）
--- @param aabbMax Vector AABB 最大点（各轴最大值）
--- @return Vector exitPoint 交点坐标（离开点），若无交点则返回 nil
function ENP.Util.ComputeLineAABBIntersection(startPoint, endPoint, aabbMin, aabbMax)
    local lineVec = endPoint - startPoint
    if lineVec:IsEqualTol(ZERO_VECTOR, EPS) then
        error("直线方向不能为零向量（起点与终点重合）", 2)
    end

    -- 确保盒子的各轴范围正确
    local boxMin = aabbMin:Min(aabbMax)
    local boxMax = aabbMin:Max(aabbMax)

    local tMin = -math.huge
    local tMax = math.huge

    -- 对每个轴进行 slab 测试（使用数字索引 1:x, 2:y, 3:z）
    for axis = 1, 3 do
        local d = lineVec[axis]
        local p0 = startPoint[axis]
        local min = boxMin[axis]
        local max = boxMax[axis]

        if math.abs(d) < EPS then
            -- 方向与轴平行，检查起点是否在盒子范围内（允许 EPS 误差）
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
