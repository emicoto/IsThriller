-- 占位骨架
-- Claude Note: myBgm模式的玩家buff(恐慌清除/兴奋加速)待实装, 草稿见 ClaudeCode/IsThriller_ExcitedBuff, 方案见规划报告
-- 也包括myBgm模式的关键进程管理
local PlayerBuff = {}

---@param st table IsThriller main object
---@param player IsoPlayer
function PlayerBuff.handle(st, player)
    -- TODO: myBgm buff handle
end


function PlayerBuff.doStart(st, player)
    st.state = "playing"
    st.music.pick()
    st.music.play(player)

    -- TODO: get buff
end

function PlayerBuff.doEnd(st, player)
    -- remove buff
end


--[[
-- ===================================================
      物品BUFF 状态机
-- ====================================================
--]]

PlayerBuff.AURA_ITEM = "IsThriller.JuiceAura"
PlayerBuff.AURA_SLOT = "IsThriller:Aura"

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
    -- ClaudeNote: addText没有(player,text,color)三参重载(反编译确认), 用带箭头版
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
end

Events.EveryOneMinute.Add(PlayerBuff.onMinuteItemBuffs)
Events.OnHitZombie.Add(PlayerBuff.onHitBreakStealth)
Events.OnWeaponHitCharacter.Add(PlayerBuff.onWeaponHitBreakStealth)
Events.OnPlayerDeath.Add(PlayerBuff.onDeathCleanup)
Events.OnCreatePlayer.Add(PlayerBuff.onCreateCleanup)

return PlayerBuff
