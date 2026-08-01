
local PlayerBuff = {}

PlayerBuff.BGM_AURA_ITEM = "IsThriller.battleAura"
PlayerBuff.BGM_BUFF_MIN  = 15

-- ClaudeNote: setWornItem/getWornItem在42.20要求ItemBodyLocation对象(非字符串), 复用Definitions已注册的全局
local function getAuraLocation()
    if ThrillerBodyLocations and ThrillerBodyLocations.Aura then
        return ThrillerBodyLocations.Aura
    end
    if ItemBodyLocation and ResourceLocation then
        local ok, loc = pcall(function()
            return ItemBodyLocation.get(ResourceLocation.of("thriller:aura"))
        end)
        if ok then return loc end
    end
    return nil
end


--[[
-- ===================================================
      myBgm「兴奋」buff  (NoBodyCanBeatMeInBGM模式)
-- ====================================================
--]]

function PlayerBuff.applyExcited(player)
    if not player or player:isDead() then return end
    local ut = IsThriller.util
    local pdata = ut.getData(player)

    local loc = getAuraLocation()
    if loc and not player:getWornItem(loc) then
        local item = player:getInventory():AddItem(PlayerBuff.BGM_AURA_ITEM)
        if item then
            player:setWornItem(loc, item)
            player:updateSpeedModifiers()
        end
    end

    ut.try("excited.panic", function()
        player:getStats():set(CharacterStat.PANIC, 0)
    end)

    pdata.excitedStart = ut.getMin()   -- 重复触发只刷新起点

    -- moodle情绪栏图标(装了MF才有), 无论有无MF都给HaloText飘字
    if IsThriller.moodle and IsThriller.moodle.show then
        ut.try("excited.moodle", function() IsThriller.moodle.show(player) end)
    end
    ut.try("excited.halo", function()
        HaloTextHelper.addTextWithArrow(player, getText("IGUI_IsThriller_Excited"), true, HaloTextHelper.getColorGreen())
    end)
    ut.debugMsg("excited buff applied", ut.getPID(player))
end

function PlayerBuff.removeExcited(player)
    if not player then return end
    local ut = IsThriller.util
    local pdata = ut.getData(player)
    if not pdata.excitedStart then return end   -- 没上过就不动(不误碰管理员/别的隐形衣)

    pdata.excitedStart = nil
    local loc = getAuraLocation()
    local worn = loc and player:getWornItem(loc)
    if worn then
        player:removeWornItem(worn)
        player:getInventory():Remove(worn)
        player:updateSpeedModifiers()
    end

    if IsThriller.moodle and IsThriller.moodle.hide then
        ut.try("excited.moodleOff", function() IsThriller.moodle.hide(player) end)
    end
    ut.debugMsg("excited buff removed", ut.getPID(player))
end


--[[
-- ===================================================
      myBgm processing
-- ====================================================
--]]

function PlayerBuff.doStart(st, player)
    st.state = "playing"

    -- 落盘状态, 保证中途存档/重进能被finishBgm正确收尾
    local md = IsThriller.util.getModData()
    if md then md.state = "playing" end

    st.music.pick()
    st.music.play(player)
    if md then md.song = st.music.current end

    PlayerBuff.applyExcited(player)
end

---@param st table IsThriller main object
---@param player IsoPlayer
function PlayerBuff.handle(st, player)
    if not player or player:isDead() then return end
    local ut = IsThriller.util
    local pdata = ut.getData(player)
    if not pdata.excitedStart then return end

    if ut.countMin(pdata.excitedStart) >= PlayerBuff.BGM_BUFF_MIN then
        PlayerBuff.removeExcited(player)
    end
end


function PlayerBuff.doEnd(st, player)
    PlayerBuff.removeExcited(player)
end


--[[
-- ===================================================
      物品BUFF 状态机
-- ====================================================
--]]

local function conf(name)
    return IsThriller.config.get(name)
end


-- ---- 果汁(KingOfPopJuice) ----
function PlayerBuff.applyJuice(player)
    if not player or player:isDead() then return end
    local ut = IsThriller.util
    local pd = ut.getData(player)

    ut.try("juice.stats", function()
        local stats = player:getStats()
        stats:set(CharacterStat.PANIC, 0)
        stats:set(CharacterStat.STRESS, 0)
        stats:set(CharacterStat.FATIGUE, 0)
        stats:set(CharacterStat.DISCOMFORT, 0)
        stats:set(CharacterStat.SICKNESS, 0)
        stats:set(CharacterStat.FOOD_SICKNESS, 0) -- 尸臭累积的病值也一并清掉
    end)

    -- 原版β阻滞剂通道: 压制期内恐慌免疫
    ut.try("juice.beta", function()
        player:setBetaDelta(1.0)
        player:setBetaEffect(6600)
    end)

    pd.juiceStart = ut.getMin() -- 重复喝只刷新起点

    ut.try("juice.halo", function()
        HaloTextHelper.addTextWithArrow(player, "King of Pop!", true, HaloTextHelper.getColorGreen())
    end)
    ut.debugMsg("juice buff applied", ut.getPID(player))
end

-- 每分钟维护: 刷β药效+按住压力/不适, 到期收尾
local function tickJuice(player, pd)
    if not pd.juiceStart then return end
    local ut = IsThriller.util
    local diff = ut.countMin(pd.juiceStart)

    if diff >= conf("ItemBuffMin") then
        pd.juiceStart = nil
        ut.try("juice.expire", function()
            player:setBetaEffect(0)
            player:setBetaDelta(0)
        end)
        ut.debugMsg("juice buff expired", ut.getPID(player))
        return
    end

    ut.try("juice.tick", function()
        player:setBetaDelta(1.0)
        player:setBetaEffect(6600)
        local stats = player:getStats()
        stats:set(CharacterStat.STRESS, 0)
        stats:set(CharacterStat.DISCOMFORT, 0)
        stats:set(CharacterStat.BOREDOM, 0)
    end)
end

-- ---- 隐身卷(GhostTicket) ----
function PlayerBuff.applyStealth(player)
    if not player or player:isDead() then return end
    local ut = IsThriller.util
    local pd = ut.getData(player)

    ut.try("stealth.on", function()
        player:setInvisible(true, true)
    end)
    pd.stealthStart = ut.getMin() -- 重复使用只刷新起点

    ut.try("stealth.halo", function()
        HaloTextHelper.addTextWithArrow(player, "Ghost Mode", true, HaloTextHelper.getColorGreen())
    end)
    ut.debugMsg("stealth applied", ut.getPID(player))
end

-- 不碰管理员/调试开的隐身(pd.stealthStart为nil时一律不管)
function PlayerBuff.breakStealth(player, reason)
    if not player then return end
    local ut = IsThriller.util
    local pd = ut.getData(player)
    if not pd.stealthStart then return end

    pd.stealthStart = nil
    ut.try("stealth.off", function()
        player:setInvisible(false, true)
    end)
    -- ClaudeNote: addText没有(player,text,color)三参重载, 用带箭头版
    ut.try("stealth.offHalo", function()
        HaloTextHelper.addTextWithArrow(player, reason == "attack" and "!" or "...", false, HaloTextHelper.getColorRed())
    end)
    ut.debugMsg("stealth ended:", reason or "expire", ut.getPID(player))
end

local function tickStealth(player, pd)
    if not pd.stealthStart then return end
    local ut = IsThriller.util
    if ut.countMin(pd.stealthStart) >= conf("ItemBuffMin") then
        PlayerBuff.breakStealth(player, "expire")
    end
end

function PlayerBuff.onMinuteItemBuffs()
    local player = getPlayer and getPlayer()
    if not player or player:isDead() then return end
    local pd = IsThriller.util.getData(player)
    tickJuice(player, pd)
    tickStealth(player, pd)
end

function PlayerBuff.onHitBreakStealth(zombie, wielder, bodypart, weapon)
    local player = getPlayer and getPlayer()
    if not player or wielder ~= player then return end
    PlayerBuff.breakStealth(player, "attack")
end

function PlayerBuff.onWeaponHitBreakStealth(wielder, victim, weapon, damageSplit)
    local player = getPlayer and getPlayer()
    if not player or wielder ~= player then return end
    PlayerBuff.breakStealth(player, "attack")
end

function PlayerBuff.onDeathCleanup(player)
    if not player then return end
    PlayerBuff.breakStealth(player, "death")
    PlayerBuff.removeExcited(player)

    local pd = IsThriller.util.getData(player)
    pd.juiceStart = nil
end

function PlayerBuff.onCreateCleanup(playerNum, player)
    if not player then return end
    local ut = IsThriller.util
    local pd = ut.getData(player)

    if pd.stealthStart and ut.countMin(pd.stealthStart) < conf("ItemBuffMin") then
        ut.try("stealth.restore", function() player:setInvisible(true, true) end)
    elseif pd.stealthStart then
        pd.stealthStart = nil
        ut.try("stealth.restoreOff", function() player:setInvisible(false, true) end)
    end


    -- 读档残留清扫mod专属隐形衣, 仍在有效期则重算速度, 否则脱除删掉
    ut.try("excited.restore", function()
        local loc = getAuraLocation()
        local worn = loc and player:getWornItem(loc)
        if worn then
            if pd.excitedStart and ut.countMin(pd.excitedStart) < PlayerBuff.BGM_BUFF_MIN then
                player:updateSpeedModifiers()
            else
                pd.excitedStart = nil
                player:removeWornItem(worn)
                player:getInventory():Remove(worn)
                player:updateSpeedModifiers()
            end
        end
    end)
end

Events.EveryOneMinute.Add(PlayerBuff.onMinuteItemBuffs)
Events.OnHitZombie.Add(PlayerBuff.onHitBreakStealth)
Events.OnWeaponHitCharacter.Add(PlayerBuff.onWeaponHitBreakStealth)
Events.OnPlayerDeath.Add(PlayerBuff.onDeathCleanup)
Events.OnCreatePlayer.Add(PlayerBuff.onCreateCleanup)

return PlayerBuff
