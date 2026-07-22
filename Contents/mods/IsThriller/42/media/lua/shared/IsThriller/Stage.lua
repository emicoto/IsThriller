if not IsThriller then return end
local util, music, actor, pbuff, conf = IsThriller.util, IsThriller.music, IsThriller.actor, IsThriller.pbuff, IsThriller.config


local Stage = {
    dancerReady = -1,       -- 本场每个玩家对应的dancer是否已经被确认生成
}

local function releaseTAD()
    if not IsThriller.hasTAD or not IsThrillerTAD then return end
    IsThrillerTAD.release()
end

local function cleanStat(mt, player)
    if player then
        local md = util.getData(player)
        md.lastHit = -1
        md.lastTarget = nil
        md.showMin = nil
        md.attendMin = nil
    end
    mt.endReason = nil

    releaseTAD()

    mt:cleanState()
    actor.dismiss()
end

local function isZombieSurround(report, player)
    if not report then return false end

    local cell = player:getCell()
    local zlist = cell and cell:getZombieList()
    local zSize = zlist and zlist:size() or 0
    if not zSize or zSize == 0 then return false end

     local zRate = math.min(zSize / 120, 3.5)

    local minRange =  math.max(math.floor(conf.get("minRangeZombie") * zRate), 8)
    local minSight = math.max(conf.get("minNearZombie") * zRate, 5)
    local minNear =  math.max(math.floor(conf.get("minNearZombie") * zRate), 4)
    local minTarget = math.ceil(conf.get("minTargetZombie") * zRate)

    if report.targeting >= minTarget then return true end
    if report.sightCount >= minSight then return true end
    if report.nearCount >= minNear then return true end

    local rangeThreat = (report.rangeCount - report.areaCount) * 0.25 + report.areaCount * 0.75

    return rangeThreat >= minRange
end

local function playIsSafe(player)
    if not player then return true end
    if player:isGhostMode() then return true end

    local px = math.floor(player:getX())
    local py = math.floor(player:getY())
    local pz = math.floor(player:getZ())

    local inRVHome = ( px > 22500 and py > 12000 )
    if inRVHome then return true end

    local cell = player:getCell()

    if not cell then return true end
    
    local zlist = cell:getZombieList()
    local zSize = zlist and zlist:size()

    if not zlist or (zSize  and zSize < 10) then return true end

    -- check around 8x8 grid if inside the safehouse zone
    for dx = -4, 4 do
        for dy = -4, 4 do
            local square = cell:getGridSquare(px + dx, py + dy, pz)
            if square and SafeHouse.getSafeHouse(square) then return true end
        end
    end

    return false
end

---@param mt table theIsThriller main object
---@param player IsoPlayer
function Stage.hardStop(mt, player)
    -- 强制结束， 不做事件冷却处理
    util.debugMsg("hardStop", "state=", mt.state, "mode=", mt.mode)
    cleanStat(mt, player)
    music.stop(player)
end

-- 预演取消(luring超时/包围解除): 演员撤场, 不掉奖励, 不记冷却
function Stage.cancel(mt, player)
    util.debugMsg("stage cancel", "lure failed")
    actor.strike(player, true)
    actor.dismiss()
    cleanStat(mt, player)
    music.stop(player)
end


function Stage.onFire(mt, player, zombie)
    if not player then return end

    if not mt:isIdle() then return end
    if not Stage.checkStart(mt, player) then return end

    if mt:isMJtime() then
        Stage.doStart(mt, player)
    else
        -- bgmTime start is handlered by pbuff
        pbuff.doStart(mt, player)
    end
end

-- when entered final stage successfully
---@param mt table IsThriller main object
---@param player IsoPlayer
---@param reason string|nil "complete"=播满歌数的完整落幕; 其余(nil/"early")=提前结束
function Stage.doFinal(mt, player, reason)
    local md = util.getModData()

    if mt:isMJtime() then
        releaseTAD()
        -- 记录结束原因, strike据此判定告别礼资格
        mt.endReason = reason or "early"
        -- fading是舞台级的60游戏分钟尾声周期, 与音乐淡出解耦
        music.beginFade()

        mt.state = "fading"
        md.state = "fading"
        md.lastStage = util.getMin()
        md.fadeStart = util.getMin()
        md.cooldown = util.getHour() + util.getSV("EventCooldown") + (conf.get("finalCountDown") / 60)
        md.song = nil
        util.debugMsg("doFinal -> fading", "fadeStart=", md.fadeStart, "cooldownUntil=", md.cooldown)
    else
        return Stage.finishBgm(mt, player)
    end
end

-- 播满MaxWave首歌不立刻散场, 先看存活状态: 全员活蹦乱跳时encoreChance概率加演recall
function Stage.onSongLimit(mt, player)
    if not music.encored
        and mt:mjAlive()
        and actor:dancerCount() == actor.dancerTotal -- 固定伴舞死亡会移出名册, 比对编制总数才是"全员存活"
        and ZombRand(100) < conf.get("encoreChance") then

        music.encored = true
        Stage.onSongStart(player)

        util.debugMsg("onSongLimit: encore! recall stage", "played=", music.played)
        return
    end

    -- 播满歌数的自然落幕 = 完整演出(和平观演资格路径)
    Stage.doFinal(mt, player, "complete")
end

-- fading期的每分钟检查: finalCountDown(60)游戏分钟尾声走完后正式散场
function Stage.checkFade(mt, player)
    local md = util.getModData()
    local elapsed = util.countMin(md.fadeStart or 0)
    if elapsed < conf.get("finalCountDown") then
        return
    end
    Stage.finish(mt, player)
end

-- myBgm单曲自然播完的收场
function Stage.finishBgm(mt, player)
    local md = util.getModData()
    md.cooldown = util.getHour() + util.getSV("EventCooldown")
    md.state = "idle"
    md.lastStage = util.getMin()
    md.song = nil

    pbuff.doEnd(mt, player)
    cleanStat(mt, player)
    music.stop(player)
    util.debugMsg("finishBgm", "cooldownUntil=", md.cooldown)
end


---@param mt table  IsThriller main object
---@param player IsoPlayer
function Stage.checkStart(mt, player)

    local md = util.getModData()
    local pid = util.getPID(player)

    -- if still in cooldown
    if (md.cooldown or -1) > 0 and util.getHour() < md.cooldown then
        return false
    end

    -- 如果处于幽灵模式或无法被选中的位置（如安全屋）则跳过检测
    if playIsSafe(player) then return false end

    -- 两种模式都要求被包围; myBgm不掷骰, 只有thriller走EventChance概率
    local report = mt.report[pid]
    if not isZombieSurround(report, player) then return false end


    if not mt:isMJtime() then
        util.debugMsg("checkStart pass (myBgm)", "pid=", pid)
        return true
    end

    local chance = util.getSV('EventChance')
    if util.isNight() then
        chance = chance * 2
    end

    if ZombRand(1000) >= chance then return false end

    util.debugMsg("checkStart pass (thriller)", "pid=", pid, "chance=", chance)
    return true
end


-- 尾声周期走完后的正式散场 (由checkFade调用; 冷却已在doFinal进入fading时记录)
function Stage.finish(mt, player)
    util.debugMsg("finish", "mode=", mt.mode)
    actor.strike(player)
    cleanStat(mt, player)
    music.stop(player)
end

-- luring/playing阶段的每分钟检查
-- 返回: "ready"=可开演(StageMin转doStage) / "cancel"=预演失败 / "final"=进入尾声 / nil=维持现状
function Stage.checkStage(mt, player)
    local pid = util.getPID(player)
    local pd = util.getData(player)
    local rp = mt.report[pid]

    -- 有人被盯上就刷新"最后被注意"时间戳(安全脱离判定的基准)
    if rp and rp.targeting > 0 then
        pd.lastTarget = util.getMin()
    end


    if mt:isLuring() then

        -- 如果处于绝对安全状态
        if playIsSafe(player) then
            return "cancel"
        end
        
        -- MJ生成失败时每分钟重试(找落点可能因地形失败)
        if not actor.mj then
            actor.mjStandby(player)
        end
        -- 本场 dancer 还没生成时
        if actor:dancerCount() == 0 then
            actor.dancerStandby(player)
        end

        local elapsed = util.countMin(mt.lureStart or util.getMin())
        local timeout = elapsed >= util.toGameTime(conf.get("maxLureSec")) + util.toGameTime(conf.get("minLureSec"))
        local wait = elapsed >= util.toGameTime(conf.get("minLureSec"))

        if not wait then
            return "wait"
        end

        -- 包围解除且没有演员在场: 预演失败
        if timeout and not actor.mj then
            return "cancel"
        end

        -- 开演条件: MJ到位(danceRange+1滞回) 且 有丧尸盯上玩家; 或超时但MJ已在场附近
        if actor.mj and not actor.mj:isDead() then
            local dist = actor.mj:DistTo(player)
            local onStage = dist <= conf.get("danceRange") + 1

            if onStage or player:CanSee(actor.mj) then
                return "ready"
            end
            if timeout then
                -- 超时: MJ已接近(7格内)也强行开演, 否则取消
                if dist <= 7 then return "ready" end
                return "cancel"
            end
        end
        return nil
    end

    if mt:isPlaying() then

        --— playing每分钟记账
        pd.showMin = (pd.showMin or 0) + 1
        if actor.mj and not actor.mj:isDead()
            and actor.mj:DistTo(player) <= conf.get("attendRange") then
            pd.attendMin = (pd.attendMin or 0) + 1
        end

        -- 尾声条件a: 可感知范围(safeRange)内已无任何丧尸
        if rp and rp.safeCount == 0 then
            util.debugMsg("checkStage: area clear -> final")
            return "final"
        end

        -- 尾声条件b: 主演+伴舞全灭, 且[fadeMin真实分钟折算]时间范围内无人被丧尸盯上
        local wiped = (not actor.mj or actor.mj:isDead()) and actor:dancerCount() == 0
        if wiped then
            local idleMin = util.countMin(pd.lastTarget or util.getMin())
            if idleMin >= util.toGameTime(conf.get("fadeMin") * 60) then
                util.debugMsg("checkStage: wiped + no attention -> final")
                return "final"
            end
        end

        -- 尾声条件c(SP): 安全状态持续[safeMinSP真实分钟折算]
        if rp and rp.targeting == 0 then
            local idleMin = util.countMin(pd.lastTarget or util.getMin())
            if idleMin >= util.toGameTime(conf.get("safeMinSP") * 60) then
                util.debugMsg("checkStage: safe timeout -> final")
                return "final"
            end
        end
        return nil
    end

    return nil
end

-- 开演: 切playing, 起歌(doStart已预选首曲), 圈内观众就位, 音爆引怪
function Stage.doStage(mt, player)
    mt.state = "playing"
    mt.tadTick = 0
    local md = util.getModData()
    md.state = "playing"
    md.song = music.current

    local pd = util.getData(player)
    pd.lastTarget = util.getMin()   -- 安全脱离计时从开演起算
    
    Stage.onSongStart(player, true)

    -- 音爆: 短暂大声引怪, 包围圈内丧尸把注意力对准玩家(README音乐机制)
    pcall(function()
        getWorldSoundManager():addSound(player, player:getX(), player:getY(), 0, conf.get("radius"), 100)
    end)

    util.debugMsg("doStage -> playing", "song=", tostring(music.current))
end

function Stage.onSongStart(player, skip)
    if not skip then
        music.pick()
        local md = util.getModData()
        md.song = music.current
    end
    local ok = music.play(player)
    if not ok then return music.pick() end
    
    actor.crowdStandby(player)

    music.gapStart = -1
end

-- 条件确立，进入预演状态
function Stage.doStart(mt, player)
    mt.state = "luring"
    mt.lureStart = util.getMin()    -- lure超时计时起点(游戏分钟)
    music.pick()                    -- 预选首曲, MJ套装跟曲目走
    util.debugMsg("doStart -> luring", "pid=", util.getPID(player), "song=", tostring(music.current))

    actor.mjStandby(player)
    actor.dancerStandby(player)
end

--=============                ===============
--=============  ON TICK EVENT ===============
--=============                ===============

-- OnTick约60次/秒，舞步轮换只跟主舞台节拍走。
function Stage.doBeat(mt, player)
    if not mt.hasTAD or not IsThrillerTAD then return end

    mt.tadTick = (mt.tadTick or 0) + 1

    if mt.tadTick <= 30 then return end
    mt.tadTick = 0

    -- 主MOD侧每拍舞蹈状态机(冷却递减/起舞收舞/归队复舞), TAD只轮换舞步
    actor.onBeat(mt, player)
    IsThrillerTAD.onBeat(mt, player)
end

-- 演出期间的tick循环
function Stage.onTick(mt, player)

    -- if mj died before song limit, or at fading state, then the fan riot will happen.
    -- the stage will become dangerous.
    if mt.fanRiot then
        if  mt:isFading() or (mt:isPlaying() and music.played < util.getSV("MaxWave") and mt.phase >= 5) then
            actor.fanRiot(player)
        end
        mt.fanRiot = nil
    end

    if mt:isLuring() then
        -- 编队总控(rally汇合→march同行)
        actor.groupCtrl(player)

    elseif mt:isPlaying() then

        if mt.hasTAD then
            Stage.doBeat(mt, player)
        end

        -- 起舞/收舞在doBeat→actor.onBeat按拍处理
        actor.groupCtrl(player)
        actor.heal()
        actor.waves(mt, player)

    else
        -- fading 期间如果还存活的后续处理. 
        -- 运行落幕仪式？丧尸集体朝mj方向聚拢并挥手致敬什么的
    end
end


return Stage
