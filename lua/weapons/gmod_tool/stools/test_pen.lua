-- 工具名称：NPC Pen Inspector (诊断版)
TOOL.Category = "Test"
TOOL.Name = "NPC Pen Inspector+"

function TOOL:LeftClick(trace)
    local ply = self:GetOwner()
    if not IsValid(ply) then
        return false
    end

    local ent = trace.Entity
    if IsValid(ent) and ent:IsNPC() then
        local wep = ent:GetActiveWeapon()
        if IsValid(wep) and wep.ARC9 then
            print("========== 武器诊断 ==========")
            print("武器类名:", wep:GetClass())
            print("武器模型:", wep:GetModel())
            print("穿透值 (GetProcessedValue):", wep:GetProcessedValue("Penetration"))
            print("穿透值 (原始字段):", wep.Penetration or "无")
            print("弹药类型:", wep:GetPrimaryAmmoType() or "未知")
            print("是否 integral 弹药?", wep:GetValue("Integral") and "是" or "否") -- 注意：Integral 是槽位属性，不是武器属性

            -- 尝试获取附件列表
            local atts = wep:GetAttachments()
            if atts and #atts > 0 then
                print("当前安装的附件（共 " .. #atts .. " 个槽位）:")
                for slot, att in ipairs(atts) do
                    if att and att.Installed then
                        print(string.format("  槽位 %d: %s", slot, att.Installed))
                    else
                        print(string.format("  槽位 %d: 空", slot))
                    end
                end
            else
                print("武器没有附件或无法获取附件列表")
            end

            -- 尝试直接检查弹药槽（假设第5槽是弹药，根据你的配置）
            -- 注意：槽位索引可能变化，更好的方法是按类别查找
            local ammoSlot = nil
            if wep.Attachments then
                for i, slotData in ipairs(wep.Attachments) do
                    if slotData.Category and
                        (type(slotData.Category) == "string" and slotData.Category:find("eft_ammo") or
                            (type(slotData.Category) == "table" and table.HasValue(slotData.Category, "eft_ammo_556"))) then
                        ammoSlot = i
                        break
                    end
                end
            end
            if ammoSlot then
                print(string.format("弹药槽位索引: %d", ammoSlot))
                -- 尝试获取该槽安装的附件
                local installed = wep:GetAttachment(ammoSlot)
                print(string.format("弹药槽安装的附件: %s", installed or "无"))
            else
                print("未找到弹药槽")
            end

            print("================================\n")
        else
            print("[NPC Pen Inspector] NPC 没有有效的 ARC9 武器")
        end
    else
        print("[NPC Pen Inspector] 请击中一个 NPC")
    end
    return true
end

-- 工具名称：Self Pen Inspector
-- 功能：左键点击后，在3秒内切换武器，自动打印新武器的穿透值
function TOOL:RightClick(trace)
    local ply = self:GetOwner()
    if not IsValid(ply) then
        return false
    end

    -- 提示玩家切换武器
    print("请在3秒内切换到要测试的武器...")

    -- 取消之前的定时器（避免重叠）
    if self.TestTimer then
        timer.Remove(self.TestTimer)
    end

    -- 创建新定时器，3秒后执行
    self.TestTimer = "SelfPenTest_" .. ply:EntIndex()
    timer.Create(self.TestTimer, 3, 1, function()
        if not IsValid(ply) then
            return
        end

        local wep = ply:GetActiveWeapon()
        if not IsValid(wep) then
            ply:ChatPrint("没有手持武器")
            return
        end
        if not wep.ARC9 then
            ply:ChatPrint("当前武器不是ARC9武器")
            return
        end
        if not wep.GetProcessedValue then
            ply:ChatPrint("武器不支持GetProcessedValue方法")
            return
        end

        local pen = wep:GetProcessedValue("Penetration")
        local msg = string.format("当前武器穿透值: %s", tostring(pen))
        ply:ChatPrint(msg)
        print("[Self Pen Inspector] 玩家 " .. ply:Name() .. " 武器 " .. wep:GetClass() .. " 穿透值: " ..
                  tostring(pen))
    end)

    return true
end
function TOOL:Reload(trace)
    return false
end
function TOOL:Think()
end

function TOOL:Reload(trace)
    return false
end
function TOOL:Think()
end
