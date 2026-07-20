-- 和平观演奖励道具《Heal The World》使用逻辑 (Phase2追加)
-- 放置: Contents/mods/IsThriller/42/media/lua/client/IsThriller/HealTheWorld.lua
-- 效果: 全部伤口转为"高质量护理"状态(止血/缝合/清创/夹板, 不是彻底痊愈),
--       清除原版不良状态(疼痛/食物中毒/感冒/恐慌/压力/不开心/疲劳)。丧尸病毒不解。
-- API说明: BodyPart各方法在B42未逐一验证, 全部pcall包裹, 个别失效不影响整体

local ITEM_TYPE = "IsThriller.HealTheWorld"

local function healBodyParts(player)
    local bd = player:getBodyDamage()
    if not bd then return end

    local parts = bd:getBodyParts()
    if not parts then return end

    for i = 0, parts:size() - 1 do
        local part = parts:get(i)
        if part then
            -- 止血
            pcall(function() part:setBleedingTime(0) end)
            -- 深伤口 -> 已缝合
            pcall(function()
                if part:isDeepWounded() and not part:isStitched() then
                    part:setStitched(true)
                end
            end)
            -- 取出玻璃碎片/弹头
            pcall(function() part:setHaveGlass(false) end)
            pcall(function() part:setHaveBullet(false, 0) end)
            -- 伤口感染清除(不是丧尸病毒)
            pcall(function() part:setInfectedWound(false) end)
            pcall(function() part:setWoundInfectionLevel(0) end)
            -- 骨折 -> 上好夹板
            pcall(function()
                if part:getFractureTime() > 0 and not part:isSplint() then
                    part:setSplint(true, 10)
                end
            end)
            -- 高质量包扎(有伤才包)
            pcall(function()
                if part:HasInjury() and not part:bandaged() then
                    part:setBandaged(true, 10)
                end
            end)
        end
    end
end

local function clearBadStates(player)
    local bd = player:getBodyDamage()
    if bd then
        pcall(function() bd:setColdStrength(0) end)
    end

    local stats = player:getStats()
    if stats and CharacterStat then
        -- GPTNote: B42.19已将食物中毒与毒素迁移到CharacterStat。
        pcall(function() stats:set(CharacterStat.FOOD_SICKNESS, 0) end)
        pcall(function() stats:set(CharacterStat.POISON, 0) end)
        pcall(function() stats:set(CharacterStat.PAIN, 0) end)
        pcall(function() stats:set(CharacterStat.PANIC, 0) end)
        pcall(function() stats:set(CharacterStat.STRESS, 0) end)
        pcall(function() stats:set(CharacterStat.UNHAPPINESS, 0) end)
        pcall(function() stats:set(CharacterStat.FATIGUE, 0) end)
    end
end

local function useHealTheWorld(item, player)
    if not item or not player or player:isDead() then return end

    healBodyParts(player)
    clearBadStates(player)

    -- 一次性: 用掉即消失
    pcall(function()
        player:getInventory():Remove(item)
    end)

    pcall(function()
        HaloTextHelper.addTextWithArrow(player, "Heal The World", true, HaloTextHelper.getColorGreen())
    end)

    if IsThriller and IsThriller.util then
        IsThriller.util.debugMsg("HealTheWorld used by", IsThriller.util.getPID(player))
    end
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
