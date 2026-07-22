
local TICKET = "IsThriller.FanTicket"
local JUICE  = "IsThriller.KingOfPopJuice"
local HEAL   = "IsThriller.HealTheWorld"
local GHOST  = "IsThriller.GhostTicket"

local function removeItems(player, fullType, n)
    local ut = IsThriller.util
    local inv = player:getInventory()
    local removed = 0
    ut.try("removeItems." .. fullType, function()
        for _ = 1, n do
            local item = inv:getFirstTypeRecurse(fullType)
            if not item then break end
            local c = item:getContainer()
            if c then c:Remove(item) else inv:Remove(item) end
            removed = removed + 1
        end
    end)
    return removed
end

-- 消耗单个指定物品实例(从其实际所在容器移除)
local function consumeItem(player, item)
    IsThriller.util.try("consume." .. tostring(item and item:getFullType()), function()
        local c = item:getContainer()
        if c then c:Remove(item) else player:getInventory():Remove(item) end
    end)
end

-- 1) 直接使用: 清疲劳
local function useTicket(item, player)
    if not item or not player or player:isDead() then return end
    local ut = IsThriller.util

    consumeItem(player, item)
    ut.try("ticket.fatigue", function()
        local last = math.max((player:getStats():get(CharacterStat.FATIGUE) or 0) - 0.5, 0)
        player:getStats():set(CharacterStat.FATIGUE, last)
    end)
    ut.try("ticket.halo", function()
        HaloTextHelper.addTextWithArrow(player, "Encore!", true, HaloTextHelper.getColorGreen())
    end)
    ut.debugMsg("FanTicket used (fatigue clear)", ut.getPID(player))
end

-- 2~4) 兑换: 扣cost张票, 给1个目标物品
local function exchange(player, cost, resultType, resultName)
    if not player or player:isDead() then return end
    local ut = IsThriller.util

    local have = player:getInventory():getCountTypeRecurse(TICKET)
    if have < cost then return end -- 双保险(菜单已禁用不可达项)

    local removed = removeItems(player, TICKET, cost)
    if removed < cost then
        -- 极端情况(移除中途失败): 不发货, 打日志。已扣的票不回滚, 但try已打印具体失败点
        print("[isThriller][FAIL] exchange." .. resultType .. " : removed " .. removed .. "/" .. cost)
        return
    end

    ut.try("exchange.give." .. resultType, function()
        player:getInventory():AddItem(resultType)
    end)
    ut.try("exchange.halo", function()
        HaloTextHelper.addTextWithArrow(player, resultName, true, HaloTextHelper.getColorGreen())
    end)
    ut.debugMsg("FanTicket exchange:", resultType, "cost:", cost, ut.getPID(player))
end


local function exchangeJuice(_, player) exchange(player, IsThriller.config.get("JuiceExchange"), JUICE, "King of Pop Juice") end
local function exchangeHeal(_, player)  exchange(player, IsThriller.config.get("HealExchange"),  HEAL,  "Heal The World") end
local function exchangeGhost(_, player) exchange(player, IsThriller.config.get("AuraExchange"),  GHOST, "Ghost Ticket") end

-- 果汁使用入口(效果在pbuff)
local function useJuice(item, player)
    if not item or not player or player:isDead() then return end
    consumeItem(player, item)
    if IsThriller.pbuff and IsThriller.pbuff.applyJuice then
        IsThriller.pbuff.applyJuice(player)
    end
end


-- 隐身卷使用入口(效果在pbuff)
local function useGhost(item, player)
    if not item or not player or player:isDead() then return end
    consumeItem(player, item)
    if IsThriller.pbuff and IsThriller.pbuff.applyStealth then
        IsThriller.pbuff.applyStealth(player)
    end
end

-- 带票数进度的兑换选项; 票不够则置灰
local function addExchangeOption(context, player, item, have, cost, label, fn)
    local opt = context:addOption(label .. " (" .. have .. "/" .. cost .. ")", item, fn, player)
    if have < cost then
        opt.notAvailable = true
    end
    return opt
end


local function onFillInventoryObjectContextMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if not player then return end

    local ticketItem, juiceItem, ghostItem
    for _, v in ipairs(items) do
        local item = v
        if type(v) == "table" then item = v.items and v.items[1] end
        if item and item.getFullType then
            local ft = item:getFullType()
            if ft == TICKET then ticketItem = ticketItem or item end
            if ft == JUICE  then juiceItem  = juiceItem  or item end
            if ft == GHOST  then ghostItem  = ghostItem  or item end
        end
    end

    if ticketItem then
        local conf = IsThriller.config
        local have = player:getInventory():getCountTypeRecurse(TICKET)
        context:addOption("Use: Fan Ticket (clear fatigue)", ticketItem, useTicket, player)
        addExchangeOption(context, player, ticketItem, have, conf.get("JuiceExchange"), "Exchange: King of Pop Juice", exchangeJuice)
        addExchangeOption(context, player, ticketItem, have, conf.get("HealExchange"),  "Exchange: Heal The World",    exchangeHeal)
        addExchangeOption(context, player, ticketItem, have, conf.get("AuraExchange"),  "Exchange: Ghost Ticket",      exchangeGhost)
    end

    if juiceItem then
        context:addOption("Drink: King of Pop Juice", juiceItem, useJuice, player)
    end

    if ghostItem then
        context:addOption("Use: Ghost Ticket (stealth)", ghostItem, useGhost, player)
    end
end

Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)
