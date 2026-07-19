local Actor = {
    mj = nil,               -- main actor
    mjHP = nil,             -- HP since spawn, will regen to this baseHP while dancers still alive
    dcHP = nil,             -- 伴舞登场血量基准(激励回血上限)
    buffTick = -1,          -- tick count of mj's buff duration
    dancers = {},           -- 固定特殊伴舞: [absoluteID] = IsoZombie
    allDancer = {},         -- 全体舞者(主演+固定伴舞+临时群演): [absoluteID] = IsoZombie，统一打包到TAD调度
    costume = "DJ",

    grudge = -1,            -- MJ最近一次挨打的游戏分钟戳
    mjDead = false,         -- 对象池修复 — 死亡账本, 引用死后不可信, 一律查这个
    mjEverHit = false,      -- 和平观演 — MJ本场是否挨过打(合并时丢失, 补回)
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

    maxActiveDancer = 30,
}

local st, util, conf = IsThriller, IsThriller.util, IsThriller.config
local outfit = require("IsThriller/Outfit")

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
        elseif dancer then
            self.allDancer[id] = nil
        end
    end
    return count
end

-- TAD执行器唯一调用通道, TAD不在时静默跳过
local function tadDance(zombie, on, move)
    if not st.hasTAD or not IsThrillerTAD or not IsThrillerTAD.setDance then return end
    pcall(IsThrillerTAD.setDance, zombie, on, move)
end

-- 该丧尸当前是否在跳(以TAD active名单为准)
local function isDancing(zombie)
    return IsThrillerTAD and IsThrillerTAD.active and IsThrillerTAD.active[zombie] == true
end

function Actor.class(zombie, type)
    local md = zombie:getModData()

    if type == "sprinter" then
        util.setZombieSpeed(zombie, "sprinter")
        util.doZombieStats(zombie, "Sight")
        md.isThrillerAudience = true

    elseif type == "shambler" then
        util.setZombieSpeed(zombie, "shambler")
        util.doZombieStats(zombie, "Strength")
        md.isThrillerAudience = true

        if Actor:allDancerNum() < Actor.maxActiveDancer and ZombRand(100) < 20 then
            registerDancer(zombie)
        end

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
        registerDancer(zombie)

    else
        util.setZombieSpeed(zombie)
        if Actor:allDancerNum() < Actor.maxActiveDancer and ZombRand(100) < 20 then
            registerDancer(zombie)
        end
    end
    
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

-- 伴舞以MJ为中心生成, 任何带坐标对象均可
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
    local sq = findSpawnSquare(Actor.mj, conf.get("rallyDist") + 1)
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

    -- ClaudeNote: P5a新增 — 伴舞就位即进入rally阶段, 记超时起点
    Actor.groupState = "rally"
    Actor.rallyStart = util.now()
    util.debugMsg("dancerStandby:", Actor.dancerTotal, "dancers spawned near MJ, rally begins")
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
-- 每waveSec(2真实秒)一波, 直到本歌phase刷满MaxWave; 每首歌开播时Music.play会把phase归零
function Actor.waves(mt, player)
    local maxWave = util.getSV("MaxWave") or 5
    if mt.phase < 0 or mt.phase >= maxWave then return end

    local now = util.now()
    if now - (Actor.waveStamp or 0) < (conf.get("waveSec") or 2) then return end
    Actor.waveStamp = now

    Actor.addCrowd(player)
    mt.phase = mt.phase + 1
    util.debugMsg("wave spawned", "phase=", mt.phase, "/", maxWave)
end

function Actor.dismiss()
    Actor.mj = nil
    Actor.mjHP = nil
    Actor.dcHP = nil
    Actor.buffTick = -1
    Actor.dancers = {}
    Actor.allDancer = {}
    Actor.grudge = -1
    Actor.mjDead = false
    Actor.mjEverHit = false
    Actor.dancerTotal = 0
    Actor.mjDeathPos = nil
    Actor.waveStamp = 0
    Actor.groupState = nil
    Actor.rallyStart = -1
    Actor.marchTick = 0
end

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

-- do reaction when on hit, src from OnHitZombie
function Actor.onHit(zombie, player)
    if not zombie then return end

    if zombie == Actor.mj then
        Actor.grudge = util.getMin()
        Actor.mjEverHit = true
        
        -- 个体退舞: MJ挨打瞬移脱离不停舞蹈，但其他的会停下去反击
        Actor.retreat(zombie)   -- 主演瞬移脱离
        
        for _, dancer in pairs(Actor.dancers) do
            if not dancer:isDead() then
                tadDance(dancer, false)
                dancer:getModData().itGrudge = conf.get("grudgeBeats")
                pcall(function() dancer:setTarget(player) end)
            end
        end
        util.debugMsg("Actor.onHit: MJ hit, retreat + dancers retaliate")
        return
    end

    local id = Actor.getDancerID(zombie)
    if id ~= nil and Actor.allDancer[id] then
        -- 个体退舞反击谁挨打谁停舞去反击, 其余继续跳
        tadDance(zombie, false)
        zombie:getModData().itGrudge = conf.get("grudgeBeats")
        pcall(function() zombie:setTarget(player) end)
        util.debugMsg("Actor.onHit: dancer hit, stop dance + retaliate", "id=", id)
        return
    end
end

-- OnZombieDead : mark dead location to drop items
-- MJ死亡 → mjDead=true + 记坐标 + 断开引用; 伴舞死亡 → 从名单移除(名单里恒为活体)
function Actor.onDead(zombie)
    if not zombie then return end
    local md= zombie:getModData()

    if md and md.isThrillerMJ then
        Actor.mjDead = true
        Actor.mjDeathPos = { x = zombie:getX(), y = zombie:getY(), z = zombie:getZ() }
        Actor.mj = nil
        util.debugMsg("MJ died at", Actor.mjDeathPos.x, Actor.mjDeathPos.y)

        -- 剩下的舞团成员全员升级并播放一次特殊动画
        for _, dancer in pairs(Actor.allDancer) do
            if not dancer:isDead() then
                Actor.class(dancer, "sprinter")
            end
        end
        return
    end

    local id = (md and md.thrillerDancerID) or Actor.getDancerID(zombie)
    if id ~= nil and Actor.allDancer[id] then
        Actor.allDancer[id] = nil
        Actor.dancers[id] = nil
        tadDance(zombie, false)
        util.debugMsg("dancer died,", Actor:dancerCount(), "fixed left,", Actor:allDancerNum(), "all left")
    end
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

    local item = worldItem.getItem and worldItem:getItem()
    local inv = item and item.getInventory and item:getInventory()
    if not inv then
        util.debugMsg("dropReward: box has no inventory, fullType=", tostring(conf.get("rewardBox")))
        return
    end

    local total = drop.totalRewardItems
    if Actor:dancerCount() == 0 then
        total = total + conf.get("wipeBonus")    -- 全灭加料
    end

    for _ = 1, total do
        local fullType = rollDropItem(drop)
        if fullType then
            pcall(function() inv:AddItem(fullType) end)
        end
    end
    util.debugMsg("dropReward:", total, "items in", tostring(conf.get("rewardBox")))
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


local function dropPacifist(mj)
    local sq = mj and mj:getSquare()
    if not sq then return end

    local worldItem = sq:AddWorldInventoryItem(conf.get("rewardBox"), 0.5, 0.5, 0)
    local item = worldItem.getItem and worldItem:getItem()
    local inv = item and item.getInventory and item:getInventory()

    if not inv then
        util.debugMsg("dropReward: box has no inventory, fullType=", tostring(conf.get("rewardBox")))
        return
    end
    local drop = require("IsThriller/DropList")
    inv:AddItem(drop.specialItem)

    local fullList = drop.special.fullList
    if #fullList == 0 then
        util.debugMsg("album gift skipped: drop.special.fullList is empty")
    else
        local fullType = fullList[ZombRand(1, #fullList + 1)]
        inv:AddItem(fullType)
    end

    inv:AddItem(drop.fanTicket)
    inv:AddItem(drop.fanTicket)

    util.debugMsg("pacifist reward dropped.")
end


function Actor.strike(player, canceled)
    local mj = Actor.mj

    for _, zb in pairs(Actor.dancers) do
        if zb and not zb:isDead() then
            pcall(function()
                zb:removeFromWorld()
                zb:removeFromSquare()
            end)
        end
    end

    if mj and not mj:isDead() then
        -- 完整演出+考勤达标+全程未挨打: 告别礼
        if not canceled
            and IsThriller.endReason == "complete"
            and not Actor.mjEverHit
            and attendanceOk(player) then
            dropPacifist(mj)
        end

        pcall(function()
            mj:removeFromWorld()
            mj:removeFromSquare()
        end)
    elseif Actor.mjDead then
        removeMJCorpse()
    end

    if Actor.mjDeathPos and not canceled then
        dropReward()
    end

    util.debugMsg("Actor.strike done", "canceled=", tostring(canceled), "everHit=", tostring(Actor.mjEverHit))
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
            end
        end
    end
end

-- 编队总控
-- 节流~0.5秒判定一次; 寻路令走marchTick慢速子周期(~2秒)重下, 防止pathToLocationF每次调用重启寻路
function Actor.groupCtrl(player)
    if not player then return end

    Actor.ctrlTick = Actor.ctrlTick + 1
    if Actor.ctrlTick < 30 then return end
    Actor.ctrlTick = 0

    Actor.marchTick = (Actor.marchTick + 1) % 4
    local issueOrder = (Actor.marchTick == 0)   -- 本轮是否允许重下寻路令

    local mj = Actor.mj

    -- rally阶段: 伴舞向MJ汇合, MJ原地等
    if Actor.groupState == "rally" and mj and not mj:isDead() then
        local assembled = true
        for _, zb in pairs(Actor.dancers) do
            if zb and not zb:isDead() then
                local d = zb:DistTo(mj)
                if d > conf.get("rallyDist") then
                    assembled = false
                    if issueOrder then
                        local ox = (ZombRand(5) - 2) * 0.6  -- 小数偏移防叠格(反编译报告: float精确落点)
                        local oy = (ZombRand(5) - 2) * 0.6
                        pcall(function() zb:pathToLocationF(mj:getX() + ox, mj:getY() + oy, mj:getZ()) end)
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
            return
        end
    end

    -- march/无伴舞: MJ带队走向玩家, 伴舞跟MJ(编队同行, 不再各自直奔玩家)
    Actor.mjCtrl(player)
    Actor.dancerCtrl(player)
end

-- ClaudeNote: P5a抽出 — MJ光环: 声音吸引周围丧尸聚过来当观众(rally/march通用)
function Actor.mjHalo(zb)
    if not zb then return end
    pcall(function()
        getWorldSoundManager():addSound(zb, zb:getX(), zb:getY(), 0, conf.get("radius"), 80)
    end)
end

-- MJ入场控制: 3格内停控(演出位), 7格外重新指路
-- ClaudeNote: P5a修改 — 节流移交groupCtrl(原ctrlTick判断删除); 跳舞中(useless)不下移动令
function Actor.mjCtrl(player)
    local zb = Actor.mj
    if not zb or zb:isDead() or not player then return end

    local dist = zb:DistTo(player)

    if not isDancing(zb) and dist > 7 then
        pcall(function()
            zb:setTarget(player)
            zb:pathToCharacter(player)
        end)
    end

    Actor.mjHalo(zb)
end

-- 伴舞跟随锚点为MJ(编队核心); MJ不在(死亡)才退回跟玩家。
-- 跳舞中(useless)的个体不下移动令
function Actor.dancerCtrl(player)
    if not player or Actor:dancerCount() == 0 then return end

    local mj = Actor.mj
    local anchor = (mj and not mj:isDead()) and mj or player
    local keepDist = conf.get("dancerRange")

    for _, zb in pairs(Actor.dancers) do
        if zb and not zb:isDead() and not isDancing(zb) then
            local d = zb:DistTo(anchor)
            if d > keepDist then
                local ox = (ZombRand(5) - 2) * 0.6
                local oy = (ZombRand(5) - 2) * 0.6
                pcall(function() zb:pathToLocationF(anchor:getX() + ox, anchor:getY() + oy, anchor:getZ()) end)
            end
        end
    end
end

-- 每拍舞蹈状态机(Stage.runTADBeat驱动, playing期专用):
-- 冷却递减→距离判定→该跳的起舞/跑远的收舞。个体退舞反击的"归队复舞"也在这里完成
function Actor.onBeat(mt, player)
    if not player then return end
    if not st.hasTAD or not IsThrillerTAD then return end

    local mj = Actor.mj

    -- MJ: danceRange内起舞, danceExitRange外收舞追场(滞回防抖)
    if mj and not mj:isDead() then
        local dist = mj:DistTo(player)
        if isDancing(mj) then
            if dist > conf.get("danceExitRange") then
                tadDance(mj, false)
            end
        elseif dist <= conf.get("danceRange") + 1 then
            tadDance(mj, true)
        end
    end

    -- 伴舞: 锚定MJ(MJ不在则锚玩家), dancerRange内起舞
    local anchor = (mj and not mj:isDead()) and mj or player
    for _, zb in pairs(Actor.allDancer) do
        if zb and not zb:isDead() then
            local md = zb:getModData()
            if (md.itGrudge or 0) > 0 then
                md.itGrudge = md.itGrudge - 1
                -- 冷却结束瞬间脱战归队: 清追击目标, 下一拍距离达标自然复舞
                if md.itGrudge == 0 then
                    pcall(function() zb:setTarget(nil) end)
                end
            else
                local d = zb:DistTo(anchor)
                if isDancing(zb) then
                    if d > conf.get("dancerRange") + 2 then
                        tadDance(zb, false)
                    end
                elseif d <= conf.get("dancerRange") then
                    tadDance(zb, true)
                end
            end
        end
    end
end

-- 激励与无敌( 每Tick回血+状态检测, 节流~1秒):
-- 伴舞存活时: 主演每秒回满(接近无敌)+倒地检测(保持活蹦乱跳); 伴舞每秒回10%(healPer)
function Actor.heal(player)
    Actor.healTick = Actor.healTick + 1
    if Actor.healTick < 45 then return end
    Actor.healTick = 0

    local mj = Actor.mj
    local alive = 0

    for _, d in pairs(Actor.dancers) do
        if d and not d:isDead() then
            alive = alive + 1
            if mj and not mj:isDead() and Actor.dcHP then
                pcall(function()
                    local hp = d:getHealth()
                    if hp < Actor.dcHP then
                        d:setHealth(math.min(hp + Actor.dcHP * conf.get("healPer"), Actor.dcHP))
                    end
                end)
            end
        end
    end

    if alive > 0 and mj and not mj:isDead() and Actor.mjHP then
        pcall(function()
            if mj:getHealth() < Actor.mjHP then
                mj:setHealth(Actor.mjHP)
            end
            -- 状态检测: 别趴地上爬, 舞王要体面
            if mj:isCrawling() then
                mj:doFastShambler()
            end
        end)
    end
end

return Actor
