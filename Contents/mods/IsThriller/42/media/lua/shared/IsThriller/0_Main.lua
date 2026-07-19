-- GPTNote: 维护TAD节拍，并在模组初始化时构建已激活音乐模组的完整专辑奖励池。
IsThriller = IsThriller or {
    mode  = "thriller", -- thriller / myBgm
    state = "idle",     -- idle / luring / playing / fading
    debug = false,      -- debug mode

    phase = -1,         -- for wave spawn check
    beat  = 0,          -- current running beat
    tadTick = 0,        -- OnTick累计约60次后向TAD发送一拍

    hasTAD = false,     -- has TAD mod
    hasAuthZ = false,   -- has AuthZ mod

    lastTick = -1,
    report = {}         -- reports per players
}

-- simulate (()=>{})() js auto invoked function expression
local function lfunthr()
    print("[LuneModDebug] shared.IsThriller.0_Main loaded...")

    function IsThriller:isStageTime()
        return self.mode == "thriller" and (self.state == "luring" or self.state == "playing")
    end

    function IsThriller:isBGMTime()
        return self.mode == "myBgm" and self.state == "playing"
    end

    function IsThriller:isLuring()
        return self.state == "luring"
    end

    function IsThriller:isPlaying()
        return self.state == "playing"
    end

    function IsThriller:isMJPlaying()
        return self.mode == "thriller" and self.state == "playing"
    end

    function IsThriller:isFading()
        return self.state == "fading"
    end

    function IsThriller:isIdle()
        return self.state == "idle"
    end

    function IsThriller:mjAlive()
        local actor = self.actor
        if not actor or actor.mjDead then return false end
        return actor.mj ~= nil and not actor.mj:isDead()
    end

    function IsThriller:isMJtime()
        return self.mode == "thriller"
    end

    function IsThriller:isMyBgm()
        return self.mode == "myBgm"
    end

    -- clean all stage variable
    function IsThriller:cleanState()
        
        self.state = "idle"
        self.phase = -1
        self.tadTick = 0

        local md = IsThriller.util.getModData()
        if not md then return end

        md.state = "idle"
        md.song = nil
        md.lastStage = IsThriller.util.getMin()
    end

    function IsThriller:init()
        local md = IsThriller.util.getModData()
        if not md then return end

        if not md.state then
            md.state = "idle"
        end

        if md.state == "idle" then
            md.song = nil
        end

        md.lastStage = md.lastStage or 0
        md.cooldown = md.cooldown or -1
    end
end
pcall(lfunthr)


IsThriller.config = require("IsThriller/Config")
IsThriller.util = require("IsThriller/Utils")
IsThriller.music = require("IsThriller/Music")
IsThriller.drop = require("IsThriller/DropList")
IsThriller.actor = require("IsThriller/Actors")
IsThriller.stage = require("IsThriller/Stage")
IsThriller.pbuff = require("IsThriller/PlayerBuff")

local stage, util, music, actor, pbuff, conf, drop = IsThriller.stage, IsThriller.util, IsThriller.music, IsThriller.actor, IsThriller.pbuff, IsThriller.config, IsThriller.drop

local function initMod()
    if util.getSV("NoBodyCanBeatMeInBGM") == true then
        IsThriller.mode = "myBgm"
    else
        IsThriller.mode = "thriller"
    end

    -- compatibility check
    if getActivatedMods():contains("Authentic Z - Current") or getActivatedMods():contains("AuthenticZLite") then
        IsThriller.hasAuthZ = true
    end

    IsThriller.hasTAD = IsThrillerTAD ~= nil
    IsThriller.lastTick = util.now()

    drop.initSpecial()
    music.init()
    music.reset()

    IsThriller:init()
    util.debugMsg("initMod done", "mode=", IsThriller.mode, "hasTAD=", tostring(IsThriller.hasTAD), "hasAuthZ=", tostring(IsThriller.hasAuthZ), "songs=", #music.list, "fullAlbums=", #drop.special.fullList)
end

local function StageMin()
    local st = IsThriller
    local player = getPlayer()

    if not player or player:isDead() then
        return stage.hardStop(st, player)
    end

    if st:isIdle() then
        -- check if event should start or not
        local ok = stage.checkStart(st, player)
        if ok then
            if st:isMJtime() then
                stage.doStart(st, player)
            else
                pbuff.doStart(st, player)
            end
        end
    elseif st:isStageTime() then
        local res = stage.checkStage(st, player)
        if res == "ready" then
            stage.doStage(st, player)

        elseif res == "cancel" then
            stage.cancel(st, player)

        elseif res == "final" then
            stage.doFinal(st, player, "early")

        end
    elseif st:isBGMTime() then
        -- while playing state on bgm time
        pbuff.handle(st, player)
    
    else
        -- 60游戏分钟尾声周期计时与逐步清理
        stage.checkFade(st, player)
    end

end

local function StageTick()
    local st = IsThriller
    local player = getPlayer()

    if not player or player:isDead() then
        -- reset ticks
        st.lastTick = util.now()
        return stage.hardStop(st, player)
    end

    -- do zombie scan
    if st.lastTick + conf.scanTime < util.now() then
       st.lastTick = util.now()
       actor.auction(player)
    end

    local res = music.onTick(st, player)

    if res == "hardstop" then
        return stage.hardStop(st, player)

    -- finalstop只代表音乐淡出完毕(声音已停),
    -- 舞台的60游戏分钟尾声周期继续走, 正式散场由StageMin的checkFade负责
    elseif res == "finalstop" then
        util.debugMsg("music finalstop, stage keeps fading")

    -- 播满MaxWave首歌交由onSongLimit判定: 全员存活60%概率加演recall
    elseif res == "songlimit" then
        return stage.onSongLimit(st, player)

    -- — myBgm单曲自然播完, 正常收场并记冷却
    elseif res == "bgmdone" then
        return stage.finishBgm(st, player)
    end

    if actor:dancerCount() > 0 or st:mjAlive() or (actor:allDancerNum() > 0 and IsThriller:isPlaying() ) then
        return stage.onTick(st, player)
    end

    if st:isBGMTime() then
        return pbuff.handle(st, player)
    end
end

-- OnWeaponHitCharacter真实命中:
-- 统一写入lastHit(脱战判定基准), 空闲时兼做事件触发信号(冷却/概率判定在stage.onFire→checkStart内)
local function firedSignal(wielder, victim, weapon, damageSplit)
    local player = getPlayer()
    if not player or wielder ~= player then return end

    local md = util.getData(player)
    md.lastHit = util.getMin()

    if not IsThriller:isIdle() then return end
    stage.onFire(IsThriller, player, victim)
end

-- 同样写入lastHit; 舞台进行中时转交actor做主演/伴舞挨打反击检测
-- zombie, wielder, bodyPart, weapon
local function playerFire(zombie, wielder, bodypart, weapon)
    local player = getPlayer()
    if not player or wielder ~= player then return end

    local md = util.getData(player)
    md.lastHit = util.getMin()

    if IsThriller:isStageTime() then
        actor.onHit(zombie, player)
    end
end

-- MJ死亡坐标记录(散场奖励的锚点); 非舞台模式/空闲直接早退
local function zombieDead(zombie)
    local st = IsThriller
    if not st:isMJtime() or st:isIdle() then return end
    actor.onDead(zombie)
end

Events.OnZombieDead.Add(zombieDead)
Events.OnGameStart.Add(initMod)
Events.OnTick.Add(StageTick)
Events.OnHitZombie.Add(playerFire)
Events.EveryOneMinute.Add(StageMin)
Events.OnWeaponHitCharacter.Add(firedSignal)
