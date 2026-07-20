local Actor = {
    mj = nil,               -- main actor
    mjHP = nil,             -- HP since spawn, will regen to this baseHP while dancers still alive
    dcHP = nil,             -- 伴舞登场血量基准(激励回血上限)
    dancers = {},           -- 固定特殊伴舞: [absoluteID] = IsoZombie
    allDancer = {},         -- 全体舞者(主演+固定伴舞+临时群演): [absoluteID] = IsoZombie，统一打包到TAD调度

    mjDead = false,         -- 对象池修复 — 死亡账本, 引用死后不可信, 一律查这个
    mjEverHit = false,      -- 和平观演 — MJ本场是否挨过打
    dancerTotal = 0,        -- 伴舞编制总数(死亡会从dancers名单移除, 全员存活判定用这个比对)
    mjDeathPos = nil,       -- MJ死亡坐标{x,y,z}, 散场放奖励用
    waveStamp = 0,          -- 上一波群演的真实秒戳
    ctrlTick = 0,           -- 控制节流
    healTick = 0,           -- 回血节流

    -- nil=未组队 / "rally"=伴舞向MJ汇合 / "march"=编队走向玩家
    groupState = nil,
    rallyStart = -1,        -- rally起点(真实秒戳), 超时强制march
    marchTick = 0,          -- 慢速子周期计数: 每4次控制检查(~2秒)才重下寻路令, 防止每次调用重启寻路

    stageLocation = nil,    -- the IsoPlayer which triggered event

}

local st, util, conf = IsThriller, IsThriller.util, IsThriller.config
local outfit = require("IsThriller/Outfit")

function Actor:dancerCount()
    if not self.dancers then return 0 end
    local count = 0
    for _, dancer in pairs(self.dancers) do
        if dancer and not dancer:isDead() then
            count = count + 1
        end
    end
    return count
end

function Actor:allDancerNum()
    if not self.allDancer then return 0 end
    local count = 0
    for id, dancer in pairs(self.allDancer) do
        if dancer and not dancer:isDead() then
            count = count + 1
        end
    end
    return count
end

-- 联机用onlineID，单机用moving object ID；无效onlineID会回退到getID。
function Actor.getDancerID(zombie)
    if not zombie then return nil end

    local md
    pcall(function() md = zombie:getModData() end)
    if md and md.thrillerDancerID ~= nil then
        return md.thrillerDancerID
    end

    local id
    if (isClient and isClient()) or (isServer and isServer()) then
        pcall(function() id = zombie:getOnlineID() end)
    end
    if id == nil or id < 0 then
        pcall(function() id = zombie:getID() end)
    end
    return id
end

function Actor.isDancing(zombie)
    return IsThrillerTAD and IsThrillerTAD.active[zombie] == true
end

local function registerDancer(zombie, fixed)
    local id = Actor.getDancerID(zombie)
    if id == nil then
        util.debugMsg("registerDancer: zombie has no absolute ID", tostring(zombie))
        return nil
    end

    Actor.allDancer[id] = zombie
    local md = zombie:getModData()
    md.thrillerDancerID = id

    if fixed then
        Actor.dancers[id] = zombie
    end
    return id
end

function Actor.class(zombie, type)
    local md = zombie:getModData()
    local dancerRoll = false

    if type == "sprinter" then
        util.setZombieSpeed(zombie, "sprinter")
        util.doZombieStats(zombie, "Sight")
        md.isThrillerAudience = true
        dancerRoll = true
    
    elseif type == "sprinter2" then
        util.setZombieSpeed(zombie, "sprinter")
        util.doZombieStats(zombie, "Sight")
        util.doZombieStats(zombie, "Memory")
        util.doZombieStats(zombie, "Strength")

    elseif type == "shambler" then
        util.setZombieSpeed(zombie, "shambler")
        util.doZombieStats(zombie, "Strength")
        md.isThrillerAudience = true
        dancerRoll = true

    elseif type == "mj" then
        util.setZombieSpeed(zombie, "shambler")
        util.doZombieStats(zombie, "Sight")
        util.doZombieStats(zombie, "Memory")
        util.doZombieStats(zombie, "Strength")
        util.doZombieStats(zombie, "Cognition")
        md.isThrillerMJ = true
        registerDancer(zombie)

    elseif type == "dancer" then
        util.setZombieSpeed(zombie, "shambler")
        util.doZombieStats(zombie, "Sight")
        util.doZombieStats(zombie, "Memory")
        util.doZombieStats(zombie, "Strength")
        util.doZombieStats(zombie, "Cognition")
        md.isThrillerDancer = true
        registerDancer(zombie, true)
    else
        util.setZombieSpeed(zombie)
    end

    if dancerRoll and Actor:allDancerNum() < conf.get("maxActiveDancer") and ZombRand(100) < conf.get("danceRate") then
        registerDancer(zombie)
    end
end

local function signClass(zombie)
    local chance = util.getSV("SprintChance")
    local md = zombie:getModData()
    -- already signed
    if md.isThrillerMJ or md.isThrillerDancer or md.isThrillerAudience then
        return
    end

    local type = "shambler"

    if ZombRand(100) < chance then
        type = "sprinter"
    end

    Actor.class(zombie, type)
end

-- find available square to spawn
local function findSpawnSquare(center, dist)
    local cell = getCell()
    if not cell or not center then return nil end

    for _ = 1, 20 do
        local ang = ZombRand(360) * math.pi / 180
        local d = dist + ZombRand(-2, 3)
        local x = math.floor(center:getX() + math.cos(ang) * d)
        local y = math.floor(center:getY() + math.sin(ang) * d)
        local sq = cell:getGridSquare(x, y, 0)
        if sq and util.isValidLot(sq) then
            return sq
        end
    end
    return nil
end

local function mjIsAlive()
    return Actor.mj and not Actor.mj:isDead()
end

-- TAD执行器唯一调用通道, TAD不在时静默跳过
function Actor.doDance(zombie, on, move)
    if not st.hasTAD or not IsThrillerTAD then return end
    IsThrillerTAD.setDance(zombie, on, move)
end

function Actor.doSpin(zombie)
    if not st.hasTAD or not IsThrillerTAD then return end
    IsThrillerTAD.doSpin(zombie)
end


-- addZombiesInOutfit will return java array list, turn into lua table
---@return IsoZombie[] lua数组(可能为空)
function Actor.spawn(size, x, y, outfitID, femaleChance)
    local ok, arr = pcall(function()
        return addZombiesInOutfit(x, y, 0, size or 1, outfitID, femaleChance or 50)
    end)

    if not ok or not arr then
        util.debugMsg("Actor.spawn failed", "err=", tostring(arr))
        return {}
    end

    local list = {}
    pcall(function()
        for i = 0, arr:size() - 1 do
            local zb = arr:get(i)
            table.insert(list, zb)
        end
    end)
    return list
end

function Actor.auction(player)
    if not player or not player.getCell then return end

    local cell = player:getCell()
    if not cell then return end

    local res = {
        nearCount = 0,
        rangeCount = 0,
        safeCount = 0,
        targeting = 0,
        total = 0,
    }

    -- report按玩家pid分槽存
    local pid = util.getPID(player)

    local zbList = cell:getZombieList()
    if not zbList or zbList:size() == 0 then
        st.report[pid] = res
        return
    end

    local range = util.getSV("Range")

    for i = 0, zbList:size() - 1 do
        local zb = zbList:get(i)
        if zb and not zb:isDead() then
            res.total = res.total + 1
            local dist = util.countDist(zb, player)

            if dist <= conf.get("safeRange") then
                res.safeCount = res.safeCount + 1
                local targeted = false
                pcall(function() targeted = zb:getTarget() == player end)
                if targeted then
                    res.targeting = res.targeting + 1
                end
            end

            if dist <= conf.get("nearRange") then
                res.nearCount = res.nearCount + 1
            end

            if dist <= range then
                res.rangeCount = res.rangeCount + 1
            end

            -- if stage play time then sign class
            if IsThriller:isMJPlaying() and dist <= range then
                signClass(zb)
            end
        end
    end
    st.report[pid] = res
end

-- 一波群演: 视野边缘随机方位生成
function Actor.addCrowd(player)
    if not player then return end
    local ang = ZombRand(360) * math.pi / 180
    local sx = math.floor(player:getX() + math.cos(ang) * 18)
    local sy = math.floor(player:getY() + math.sin(ang) * 18)
    local size = ZombRand(2, util.getSV("MaxZombies") + 1)

    local list = Actor.spawn(size, sx, sy, nil, 50)
    local chance = util.getSV("SprintChance")

    local endPoint = Actor.mj or player

    for _, zb in ipairs(list) do
        local t = "shambler"
        if ZombRand(100) < chance then t = "sprinter" end
        Actor.class(zb, t)

        -- 如果装了AuthZ就往inventory里塞荧光棒
        if st.hasAuthZ and zb.getInventory and zb:getInventory() then
        end
        pcall(function() zb:pathToLocation(endPoint:getX(), endPoint:getY(), endPoint:getZ()) end)
    end
    return list
end

-- 每首歌前奏期的波次调度
-- 每waveSec(2真实秒)一波, 直到本歌phase刷满MaxWave * 2; 每首歌开播时Music.play会把phase归零
function Actor.waves(mt, player)
    local maxWave = (util.getSV("MaxWave") or 5) * 2
    if mt.phase < 0 or mt.phase >= maxWave then return end

    local now = util.now()
    if now - (Actor.waveStamp or 0) < (conf.get("waveSec") or 2) then return end
    Actor.waveStamp = now

    Actor.addCrowd(player)
    mt.phase = mt.phase + 1
    util.debugMsg("wave spawned", "phase=", mt.phase, "/", maxWave)
end


-- 全场唯一MJ生成: 找落点→生成→按首曲换装→HPx10→class
-- 生成失败(找不到落点)保持luring, 由checkStage的每分钟重试与超时兜底
function Actor.mjStandby(player)
    if Actor.mj then return end
    if not player then return end

    local sq = findSpawnSquare(player, conf.get("spawnDist"))
    if not sq then
       return util.debugMsg("mjStandby: no valid square, retry next minute")
    end

    local outfitID = outfit.pick(st.music.current)
    local list = Actor.spawn(1, sq:getX(), sq:getY(), outfitID, 10)
    local zb = list[1]
    if not zb then
       return util.debugMsg("mjStandby: spawn failed")
    end

    util.debugMsg("mjStandby: spawned", zb)

    outfit.set(zb, outfitID)

    pcall(function()
        local hp = zb:getHealth()
        zb:setHealth(hp * conf.get("mjHP"))
    end)
    Actor.mjHP = zb:getHealth()

    Actor.class(zb, "mj")
    Actor.mj = zb

    util.debugMsg("mjStandby: MJ spawned", "hp=", zb:getHealth(), "song=", tostring(st.music.current))
end

-- — 伴舞生成: 每个玩家对应MaxDancer只(0=随机2~5)
function Actor.dancerStandby(player)
    if Actor:dancerCount() > 0 then return end
    if not player then return end

    -- MJ还没落地时本分钟先不生成伴舞
    if not Actor.mj then
        return util.debugMsg("dancerStandby: waiting for MJ, retry next minute")
    end

    local count = util.getSV("MaxDancer")
    if count == 0 then count = ZombRand(2, 6) end

    -- 落点在MJ附近,缩短汇合路程
    local sq = findSpawnSquare(Actor.mj, conf.get("groupRange") + 1)
    if not sq then
        sq = findSpawnSquare(player, conf.get("spawnDist"))
    end
    if not sq then return end

    local outfitID = outfit.dancer[ZombRand(1, #outfit.dancer + 1)]

    local list = Actor.spawn(count, sq:getX(), sq:getY(), outfitID, 50)
    for _, zb in ipairs(list) do
        pcall(function()
            local hp = zb:getHealth()
            zb:setHealth(hp * conf.get("djHP"))
        end)
        Actor.dcHP = zb:getHealth()

        Actor.class(zb, "dancer")
    end
    Actor.dancerTotal = Actor:dancerCount()

    -- 记超时起点
    Actor.groupState = "rally"
    Actor.rallyStart = util.now()
    util.debugMsg("dancerStandby:", Actor.dancerTotal, "dancers spawned near MJ, rally begins")
end

-- the event is ready, make sure all actors and audients stand by.
-- also set class for all zombie that in event range
function Actor.crowdStandby(player)
    if not player or not player.getCell then return end

    local cell = player:getCell()
    if not cell then return end

    local zbList = cell:getZombieList()
    if not zbList or zbList:size() == 0 then
        return
    end

    local range = util.getSV("Range")

    for i = 0, zbList:size() - 1 do
        local zb = zbList:get(i)
        if zb and not zb:isDead() then
            local dist = util.countDist(zb, player)
            if dist <= range then
                -- rollspeed
                signClass(zb)
                -- spin all
                Actor.doSpin(zb)
            end
        end
    end
end



--=============                    ===============
--=============  ON DISMISS EVENT  ===============
--=============                    ===============



---@param player IsoPlayer
---@param canceled boolean|nil true=预演取消, 不掉奖励
-- 考勤: playing期在场分钟占比达attendRate
local function attendanceOk(player)
    if not player then return false end
    local pd = util.getData(player)
    local show = pd.showMin or 0
    if show <= 0 then return false end
    return (pd.attendMin or 0) >= show * (conf.get("attendRate") or 0.6)
end

-- 尝试删除actor尸体(modData识别; 认不出就保留, 不误删别的尸体)
-- OnZombieDead记录的是死亡瞬间坐标，尸体实例化后可能落到相邻格，因此扫描中心格周围3x3。
-- 使用IsoGridSquare.removeCorpse走完整尸体清理路径（含容器更新/联机通知）。
local function removeMJCorpse()
    local pos = Actor.mjDeathPos
    if not pos then return false end

    local cell = getCell()
    if not cell then return false end

    local cx = math.floor(pos.x)
    local cy = math.floor(pos.y)
    local cz = math.floor(pos.z)

    local ok, removed = pcall(function()
        for dx = -1, 1 do
            for dy = -1, 1 do
                local sq = cell:getGridSquare(cx + dx, cy + dy, cz)
                if sq then
                    local bodies = sq:getDeadBodys()
                    for i = bodies:size() - 1, 0, -1 do
                        local body = bodies:get(i)
                        local md = body and body:getModData()
                        if md and md.isThrillerMJ then
                            local bodySq = body:getSquare() or sq
                            bodySq:removeCorpse(body, false)
                            util.debugMsg("MJ corpse removed", "offset=", dx, dy)
                            return true
                        end
                    end
                end
            end
        end
        return false
    end)

    if not ok then
        util.debugMsg("MJ corpse removal failed", "err=", tostring(removed))
        return false
    end
    if not removed then
        util.debugMsg("MJ corpse not found near death position", cx, cy, cz)
    end
    return removed
end

-- reset all states variable
function Actor.dismiss()
    Actor.mj = nil
    Actor.mjHP = nil
    Actor.dcHP = nil
    Actor.dancers = {}
    Actor.allDancer = {}
    Actor.mjDead = false
    Actor.mjEverHit = false
    Actor.dancerTotal = 0
    Actor.mjDeathPos = nil
    Actor.waveStamp = 0
    Actor.groupState = nil
    Actor.rallyStart = -1
    Actor.marchTick = 0
end

-- drop reward items
local function rollDropItem(drop)
    local roll = ZombRand(1000)
    local acc = 0
    for cat, rate in pairs(drop.pickRate) do
        acc = acc + rate
        if roll < acc then
            local pool = drop.itemList[cat]
            if pool and #pool > 0 then
                return pool[ZombRand(1, #pool + 1)]
            end
        end
    end
    return nil
end

-- curtain call event
-- only drop when main actor dead. if all back dancers already dead will get extra reward
local function dropReward()
    local pos = Actor.mjDeathPos
    if not pos then return end

    local sq = getCell() and getCell():getGridSquare(pos.x, pos.y, pos.z)
    if not sq then return end

    local drop = require("IsThriller/DropList")
    local worldItem = sq:AddWorldInventoryItem(conf.get("rewardBox"), 0.5, 0.5, 0)

    local container = pcall(function() return worldItem:getItem():getItemContainer() end)
    if not container then
        util.debugMsg("dropReward: box has no inventory, fullType=", tostring(conf.get("rewardBox")))
        return
    end

    container:clear()

    local total = drop.totalRewardItems
    if Actor:dancerCount() == 0 then
        total = total + conf.get("wipeBonus")    -- 全灭加料
    end

    for _ = 1, total do
        local fullType = rollDropItem(drop)
        local item = instanceItem(fullType)
        if item then
            container:AddItem(fullType)
        end
    end
    util.debugMsg("dropReward:", total, "items in", tostring(conf.get("rewardBox")))
end


local function dropPacifist(mj)
    local sq = mj and mj:getSquare()
    if not sq then return end

    local worldItem = sq:AddWorldInventoryItem(conf.get("rewardBox"), 0.5, 0.5, 0)
    local container = pcall(function() return worldItem:getItem():getItemContainer() end)
    if not container then
        util.debugMsg("dropReward: box has no inventory, fullType=", tostring(conf.get("rewardBox")))
        return
    end

    container:clear()

    local drop = require("IsThriller/DropList")
    container:AddItem(drop.specialItem)

    local fullList = drop.special.fullList
    if #fullList == 0 then
        util.debugMsg("album gift skipped: drop.special.fullList is empty")
    else
        local fullType = fullList[ZombRand(1, #fullList + 1)]
        container:AddItem(fullType)
    end

    container:AddItem(drop.fanTicket)
    container:AddItem(drop.fanTicket)

    util.debugMsg("pacifist reward dropped.")
end

function Actor.strike(player, canceled)
    for _, zb in pairs(Actor.dancers) do
        if zb and not zb:isDead() then
            pcall(function()
                zb:removeFromWorld()
                zb:removeFromSquare()
            end)
        end
    end

    if mjIsAlive() then
        -- 完整演出+考勤达标+全程未挨打: 告别礼
        if not canceled
            and IsThriller.endReason == "complete"
            and not Actor.mjEverHit
            and attendanceOk(player) then
            dropPacifist(Actor.mj)
        end

        pcall(function()
            Actor.mj:removeFromWorld()
            Actor.mj:removeFromSquare()
        end)
    elseif Actor.mjDead then
        removeMJCorpse()
    end

    if Actor.mjDeathPos and not canceled then
        dropReward()
    end

    util.debugMsg("Actor.strike done", "canceled=", tostring(canceled), "everHit=", tostring(Actor.mjEverHit))
end


--=============               ===============
--=============    ON EVENT   ===============
--=============               ===============

-- — MJ挨打寻找安全方位瞬移
function Actor.retreat(zb)
    if not zb then return false end

    local cell = getCell()
    if not cell then return false end

    local z = zb:getZ()
    local dist = conf.get("retreatDistance")
    
    for _ = 1, 8 do
        local ang = ZombRand(360) * math.pi / 180
        local x = math.floor(zb:getX() + math.cos(ang) * dist)
        local y = math.floor(zb:getY() + math.sin(ang) * dist)
        local sq = cell:getGridSquare(x, y, z)
        if sq and util.isValidLot(sq) then
            local ok = pcall(function()
                zb:setX(x + 0.5)
                zb:setY(y + 0.5)
                zb:setZ(z)
            end)
            if ok then
                util.debugMsg("MJ retreat to", x, y)
                return true
            end
        end
    end
    return false
end


local function doCounter(zombie, player)
    -- stop dance at first
    Actor.doDance(zombie, false)
    zombie:setUseless(false)
    zombie:setTarget(player)
    zombie:addAggro(player, 3.0)

    local md = zombie:getModData()
    md.isThriller_Grudge = conf.get("grudgeBeats")
end

-- do reaction when on hit, src from onHitZombie
function Actor.onHit(zombie, player)
    if not zombie then return end

    local md = zombie:getModData()

    -- mj on hit
    if zombie == Actor.mj or md.isThrillerMJ then

        Actor.mjEverHit = true          -- hit flag set
        Actor.retreat(zombie)

        if Actor:dancerCount() > 0 then
            zombie:setHealth(Actor.mjHP)
        end
        for _, dancer in pairs(Actor.dancers) do
            if dancer and not dancer:isDead() then
                doCounter(dancer, player)
            end
        end

        util.debugMsg("Actor.onHit: MJ hit, retreat + dancers retaliate")
        return
    end

    -- dancer group on hit (include temporary dancers)
    local id = Actor.getDancerID(zombie)
    if id ~= nil and Actor.allDancer[id] then
        doCounter(zombie, player)

        -- heal 10% if mj alive
        if Actor.dancers[id] and mjIsAlive() then
            local newHP = zombie:getHealth() + (Actor.dcHP * 0.1)
            zombie:setHealth(math.min(newHP, Actor.dcHP))
        end

        util.debugMsg("Actor.onHit: dancer hit, stop dance + retaliate", "id=", id)
    end
end


-- when zombie death
-- if MJ death then mark location, else just delete from dancer list
function Actor.onDead(zombie)
    if not zombie then return end
    local md = zombie:getModData()
    -- on mj death
    if md and md.isThrillerMJ then

        Actor.doDance(zombie, false)
        Actor.mjDead = true
        Actor.mjDeathPos = {
            x = zombie:getX(),
            y = zombie:getY(),
            z = zombie:getZ()
        }

        Actor.mj = nil
        util.debugMsg("MJ died at", Actor.mjDeathPos.x, Actor.mjDeathPos.y)

        -- all dance member do a special animation then get evolve
        for _, dancer in pairs(Actor.allDancer) do
            if dancer and not dancer:isDead() then
                Actor.class(dancer, "sprinter2")
            end
        end
        return
    end

    -- on dancer death
    local id = (md and md.thrillerDancerID) or Actor.getDancerID(zombie)
    if id ~= nil then
        Actor.doDance(zombie, false)
        if Actor.allDancer[id] then
            Actor.allDancer[id] = nil
        end
        if Actor.dancers[id] then
            Actor.dancers[id] = nil
        end

        util.debugMsg("dancer died,", Actor:dancerCount(), "fixed left,", Actor:allDancerNum(), "all left")
    end
end



--=============               ===============
--=============    ON TICK    ===============
--=============               ===============

-- heal per 0.5 sec
function Actor.heal()
    Actor.healTick = Actor.healTick + 1
    if Actor.healTick < 40 then return end

    Actor.healTick = 0

    local alive = Actor:dancerCount()

    if alive > 0 and mjIsAlive() then
        Actor.mj:setHealth(Actor.mjHP)

        -- keep stand
        if Actor.mj:isCrawling() or not Actor.mj:isCanWalk() then
            Actor.mj:doFastShambler()
            Actor.mj:setCanWalk(true)
        end
    end

    for _, dancer in pairs(Actor.dancers) do
        if mjIsAlive() then
            local newHP = dancer:getHealth() + (Actor.dcHP * 0.1)
            dancer:setHealth(math.min(newHP, Actor.dcHP))
        end
    end
end

-- sound halo for audients gathering
function Actor.mjHalo()
    if not Actor.mj or not mjIsAlive() then return end

    local z = Actor.mj

    getWorldSoundManager():addSound(z, z:getX(), z:getY(), z:getX(), conf.get("radius"), 80)
end


-- when the group not marched, set path need wait a bit time.
local function rallyCtrl()
    Actor.marchTick = (Actor.marchTick + 1) % 4
    local issueOrder = (Actor.marchTick == 0) -- can order path finding or not
    local mj = Actor.mj

    if not mj or mj:isDead() then return end

    local assembled = true
    for _, dancer in pairs(Actor.dancers) do
        if dancer and not dancer:isDead() then
            local dist = dancer:DistTo(mj)
            if dist > conf.get("groupRange") then
                assembled = false
                if issueOrder then
                    local ox = (ZombRand(3) - 2) * 0.6  -- 小数偏移防叠格(反编译报告: float精确落点)
                    local oy = (ZombRand(3) - 2) * 0.6
                    dancer:setUseless(true)
                    dancer:pathToLocationF(mj:getX() + ox, mj:getY() + oy, mj:getZ())
                end
            end
        end
    end

    local timeout = (util.now() - (Actor.rallyStart or 0)) >= conf.get("rallySec")
    if assembled or timeout then
        Actor.groupState = "march"
        util.debugMsg("group rally done ->march", "assembled=", tostring(assembled), "timeout=", tostring(timeout))
    else
        -- 汇合期MJ只挂光环引怪, 不移动
        Actor.mjHalo(mj)
    end
end

-- onTick check event, dancing stage controler
function Actor.groupCtrl(player)
    if not IsThriller:isStageTime() then return end

    Actor.ctrlTick = Actor.ctrlTick + 1
    if Actor.ctrlTick < 30 then return end
    Actor.ctrlTick = 0

    if Actor.groupState == "rally" then
        rallyCtrl()
    else
    -- on marched
        Actor.dancerCtrl(player)
        Actor.mjCtrl(player)
    end

end


function Actor.mjCtrl(player)
    local dancer = Actor.mj
    if not player or not dancer or dancer:isDead() then return end

    local range = conf.get("danceRange")
    local dist = dancer:DistTo(player)

    if dist >= range and not Actor.isDancing(dancer) then
        dancer:setTarget(player)
        dancer:pathToCharacter(player)

    -- restore dancing flag if condition wrent wrong
    elseif dist < range and not Actor.isDancing(dancer) and Actor:dancerCount() > 0 and not dancer:isUseless() then
        Actor.doDance(dancer, true)
    end
end

-- dancers control: dance in 7m and around MJ, move when out of player sight
function Actor.dancerCtrl(player)
    if not player or Actor:dancerCount() == 0 then return end
    
    local anchor = player
    local range = conf.get("danceRange")
    if mjIsAlive() then
        anchor = Actor.mj
        range = conf.get("groupRange")
    end

    -- re-group if dancer move to faraway from mj or player
    for _, dancer in pairs(Actor.dancers) do
        if dancer and not dancer:isDead() and not Actor.isDancing(dancer) then
            local dist = dancer:DistTo(anchor)
            if dist >= range and Actor.groupState ~= "rally" then
                Actor.groupState = "rally"
                Actor.rallyStart = util.now()
            end
        end
    end
end

-- dancer control ~ 30 tick per beats, around 0.5 sec
-- control all dancers while TAD is on
function Actor.onBeat(mt, player)
    if not st.hasTAD or not IsThrillerTAD then return end
    if not player then return end


    local mj = Actor.mj

    -- MJ dance in range
    if mjIsAlive() then
        local dist = mj:DistTo(player)
        if Actor.isDancing(mj) then
            if dist >= conf.get("danceExitRange") or not player:CanSee(mj) then
                Actor.doDance(mj, true, "walk")
            end
        elseif dist <= conf.get("danceRange") + 1 or player:CanSee(mj) then
            Actor.doDance(mj, true)
        end
    end

    -- dancers dancing in range around mj
    local anchor = player
    local range = conf.get("danceRange")
    if mjIsAlive() then
        anchor = mj
        range = conf.get("groupRange")
    end

    for id, dancer in pairs(Actor.allDancer) do
        if dancer and not dancer:isDead() and dancer ~= mj then
            local md = dancer:getModData()
            
            -- check if got hitten
            if (md.isThriller_Grudge or 0) > 0 then
                md.isThriller_Grudge = md.isThriller_Grudge - 1
                -- if cooldown finished then clear target and resume dancing
                if md.isThriller_Grudge <= 0 then
                    dancer:setTarget(nil)
                end
            else
                local dist = dancer:DistTo(anchor)
                if Actor.isDancing(dancer) then
                    if dist > range + 1 or not player:CanSee(dancer) then
                        Actor.doDance(dancer, true, "walk")
                    end
                elseif dist <= range then
                    Actor.doDance(dancer, true)
                end
            end
        end
    end
end

return Actor