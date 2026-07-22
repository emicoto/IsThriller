local ITEM_TYPE = "IsThriller.HealTheWorld"
local BAD_STATS = {
    "FOOD_SICKNESS",    -- 食物中毒(也是尸臭的累积去向)
    "POISON",           -- 毒素
    "SICKNESS",         -- 恶心/呕吐感
    "PAIN",             -- 疼痛
    "PANIC",            -- 恐慌
    "STRESS",           -- 压力
    "UNHAPPINESS",      -- 不开心
    "FATIGUE",          -- 疲劳
    "DISCOMFORT",       -- 不适
    "ANGER",            -- 愤怒
    "BOREDOM",          -- 无聊
}


local function healBodyParts(player)
    local ut = IsThriller.util
    local bd = player:getBodyDamage()
    if not bd then return end

    local parts = bd:getBodyParts()
    if not parts then return end

    for i = 0, parts:size() - 1 do
        local part = parts:get(i)
        if part then
            local tag = "part#" .. tostring(i)
            -- 1) 伤口感染清除(不是丧尸病毒)
            ut.try(tag .. ".infection", function()
                part:setInfectedWound(false)
                part:setWoundInfectionLevel(0)
            end)
            -- 2) 止血
            ut.try(tag .. ".bleeding", function()
                part:setBleedingTime(0)
            end)
            -- 3) 取出玻璃碎片/弹头(10=最高医生等级处理)
            ut.try(tag .. ".glass", function() part:setHaveGlass(false) end)
            ut.try(tag .. ".bullet", function() part:setHaveBullet(false, 10) end)
            -- 4) 深伤口 -> 已缝合
            ut.try(tag .. ".stitch", function()
                if part:isDeepWounded() and not part:stitched() then
                    part:setStitched(true)
                end
            end)
            -- 5) 骨折 -> 上好夹板(splintFactor=10, 顶级护理)
            ut.try(tag .. ".splint", function()
                if part:getFractureTime() > 0 and not part:isSplint() then
                    part:setSplint(true, 10)
                end
            end)
            -- 6) 烧伤 -> 视为已清洗
            ut.try(tag .. ".burnwash", function()
                if part:getBurnTime() > 0 then
                    part:setNeedBurnWash(false)
                end
            end)
            -- 7) 消毒(原版ISDisinfect同通道: alcoholLevel)
            ut.try(tag .. ".disinfect", function()
                if part:HasInjury() and part:getAlcoholLevel() < 5 then
                    part:setAlcoholLevel(5)
                end
            end)
            -- 8) 高级包扎(有伤才包; 4参版=含酒精+绷带类型, 原版ISApplyBandage同款调用)
            -- bandageLife=15约等于10级医生+最高级绷带的上限
            ut.try(tag .. ".bandage", function()
                if part:HasInjury() and not part:bandaged() then
                    part:setBandaged(true, 15, true, "Base.Bandage")
                end
            end)

            -- 清除肌肉痉挛
            ut.try(tag..".stiffness", function()
                if part:getStiffness() then
                    part:setStiffness(0)
                end
            end)
        end
    end
end
local function clearBadStates(player)
    local ut = IsThriller.util

    -- 感冒全清
    local bd = player:getBodyDamage()
    if bd then
        ut.try("cold", function()
            bd:setHasACold(false)
            bd:setColdStrength(0)
            bd:setCatchACold(0)
            bd:setSneezeCoughActive(0)
        end)
    end

    local stats = player:getStats()
    if not stats then
        ut.try("stats.nil", function() error("player:getStats() returned nil") end)
        return
    end
    if not CharacterStat then
        ut.try("CharacterStat.nil", function() error("global CharacterStat is nil") end)
        return
    end

    for _, name in ipairs(BAD_STATS) do
        ut.try("stat." .. name, function()
            local stat = CharacterStat[name]
            if not stat then error("CharacterStat." .. name .. " not found") end
            stats:set(stat, 0)
        end)
    end
end

local function useHealTheWorld(item, player)
    if not item or not player or player:isDead() then return end
    local ut = IsThriller.util

    healBodyParts(player)
    clearBadStates(player)

    -- 一次性: 用掉即消失(从道具实际所在容器移除, 而非固定主背包)
    ut.try("consume", function()
        local container = item:getContainer()
        if container then
            container:Remove(item)
        else
            player:getInventory():Remove(item)
        end
    end)

    ut.try("halo", function()
        HaloTextHelper.addTextWithArrow(player, "Heal The World", true, HaloTextHelper.getColorGreen())
    end)

    ut.debugMsg("HealTheWorld used by", ut.getPID(player))
end

-- 右键菜单入口: 只在背包里有本道具时添加选项
local function onFillInventoryObjectContextMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if not player then return end

    for _, v in ipairs(items) do
        local item = v
        if type(v) == "table" then item = v.items and v.items[1] end
        if item and item.getFullType and item:getFullType() == ITEM_TYPE then
            context:addOption("Use: Heal The World", item, useHealTheWorld, player)
            return
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)
