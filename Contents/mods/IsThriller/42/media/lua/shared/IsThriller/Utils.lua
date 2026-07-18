local Util = {}

function Util.getSV(varName)
    local sv = SandboxVars.IsThriller
    if sv and sv[varName] ~= nil then return sv[varName] end
    return IsThriller.config.sv[varName]
end

function Util.hasItem(fullType)
    local item = ScriptManager.instance:getItem(fullType)
    if not item then return false end
    return true
end


function Util.debugMsg(...)
    -- ClaudeNote: 原来的门闩是 IsThriller.enabled, 主表里只有 debug 字段, enabled永远nil
    if IsThriller.debug then
        print("[LuneModDebug] <isThriler> |  ", ...)
    end
end

-- 游戏分钟 -> 正常速度下的真实秒数
---@param min number 游戏内分钟
---@return number realSec
function Util.toRealTime(min)
    local realMinPerDay = getGameTime():getMinutesPerDay()
    return min * realMinPerDay / 24
end

-- 真实秒数 -> 游戏分钟
---@param sec number 真实秒数
---@return number gameMin
function Util.toGameTime(sec)
    local realMinPerDay = getGameTime():getMinutesPerDay()
    return sec * 24 / realMinPerDay
end

---@return number gameMinStamp get in game minutes time stamp
function Util.getMin()
    local time = getGameTime and getGameTime()
    return time and time:getMinutesStamp() or 0
end

function Util.getHour()
    local time = getGameTime and getGameTime()
    return time and time:getWorldAgeHours() or 0
end

---@return number realSecondStamp
function Util.now()
    local now = getTimestampMs and getTimestampMs() / 1000
    return math.floor(now or os.time())
end

---@return number, number diff the diff between now and last in game min
function Util.countMin(lastStamp)
    local now = Util.getMin()
    if lastStamp == nil then return 0, now end
    local diff = now - lastStamp
    if diff < 0 then
        diff = diff + 24 * 60
    end
    return diff, now
end

-- temporary change sandbox var to effect zombies
function Util.doZombieStats(zombie, typeName)
    local stats = getSandboxOptions():getOptionByName("ZombieLore."..typeName)
    local temp = stats:getValue()

    stats:setValue(1)
    zombie:DoZombieStats()
    stats:setValue(temp)
end

-- do their own func to set stats to specific zombies
function Util.setZombieSpeed(zombie, type)
    if not zombie then return end
    local ok, msg
    if type == "sprinter" then
        ok, msg = pcall(function() zombie:doSprinter() end)
    elseif type == "shambler" then
        ok, msg = pcall(function () zombie:doFastShambler() end)
    else
        ok, msg = pcall(function() zombie:doFakeShamble() end)
    end
    if not ok and IsThriller.debug then
        print("[isThriller DEBUG] setZombieSpeed failed, stack: "..tostring(msg))
    end
end

---@param player IsoPlayer
---@return string
function Util.getPID(player)
    if not player then return 'invalid' end

    if player.getOnlineID then
        local id = player:getOnlineID()
        if id and id ~= -1 then
            return 'online_'..tostring(id)
        end
    end

    if player.getPlayerNum then
        return 'local_'.. tostring(player:getPlayerNum())
    end

    return 'sp_'..tostring(player)
end

---@param num string local id
---@return IsoPlayer[] | IsoPlayer
function Util.getPlayer(num)
    if isServer() then
        return getOnlinePlayers()
    end
    return num and getSpecificPlayer(num) or getPlayer()
end

function Util.getData(player)
    local mid = IsThriller.config.modId
    if not player then return end

    if not player:getModData()[mid] then
        player:getModData()[mid] = {}
    end
    return player:getModData()[mid]
end

function Util.getModData()
    local mid = IsThriller.config.modId
    local md = ModData and ModData.getOrCreate(mid)
    return md or {}
end

function Util.isNight()
    local hour = getGameTime():getHour()

    return not (hour >= 6 and hour <= 17)
end

function Util.isValidLot(sq) -- ClaudeNote: B4修复, 原形参square与函数体sq不一致, 永远返回false
    if not sq then return false end
    local ok, valid = pcall(function()
        return sq:isOutside()
            and sq:getRoom() == nil
            and sq:isFree(false)
            and not sq:isSolid()
            and not sq:isSolidTrans()
    end)
    return ok and valid
end

-- ClaudeNote: debug工具, 一次性输出全部运行状态。不受debug开关限制, 主动调用就是想看。
-- 用法: IsThriller.util.dump()  (控制台/按键绑定/关键断点处均可)
function Util.dump()
    local st = IsThriller
    if not st then print("[isThriller DUMP] IsThriller is nil") return end

    local s = tostring
    print("=========== [isThriller DUMP] ===========")
    print(("core   | mode=%s state=%s phase=%s beat=%s debug=%s hasTAD=%s hasAuthZ=%s lastTick=%s")
        :format(s(st.mode), s(st.state), s(st.phase), s(st.beat), s(st.debug), s(st.hasTAD), s(st.hasAuthZ), s(st.lastTick)))

    local md = Util.getModData()
    print(("modData| state=%s lastStage=%s cooldown=%s song=%s nowHour=%.2f nowMin=%s")
        :format(s(md.state), s(md.lastStage), s(md.cooldown), s(md.song), Util.getHour(), s(Util.getMin())))

    local mu = st.music
    if mu then
        print(("music  | current=%s handle=%s played=%s tick=%s fade=%s fadeTimer=%s savedVol=%s listSize=%s")
            :format(s(mu.current), s(mu.handle), s(mu.played), s(mu.tick), s(mu.fade), s(mu.fadeTimer), s(mu.savedVol), s(mu.list and #mu.list)))
    end

    local ac = st.actor
    if ac then
        local mjState = ac.mj and (ac.mj:isDead() and "dead" or "alive") or "nil"
        print(("actor  | mj=%s mjHP=%s dancers=%s(alive=%s) buffTick=%s costume=%s")
            :format(mjState, s(ac.mjHP), s(ac.dancers and #ac.dancers), s(st.dancerCount and st:dancerCount()), s(ac.buffTick), s(ac.costume)))
    end

    for pid, rp in pairs(st.report or {}) do
        print(("report | pid=%s near=%s range=%s safe=%s targeting=%s total=%s")
            :format(s(pid), s(rp.nearCount), s(rp.rangeCount), s(rp.safeCount), s(rp.targeting), s(rp.total)))
    end

    local player = getPlayer and getPlayer()
    if player then
        local pd = Util.getData(player)
        print(("player | pid=%s lastHit=%s dead=%s")
            :format(Util.getPID(player), s(pd and pd.lastHit), s(player:isDead())))
    end
    print("=========================================")
end

return Util