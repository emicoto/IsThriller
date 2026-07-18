-- GPTNote: 在现有尸体与演员流程上追加圆满落幕的兼容完整专辑礼物。
local Actor = {
    mj = nil,               -- main actor
    mjHP = nil,             -- HP since spawn, will regen to this baseHP while dancers still alive
    dcHP = nil,             -- 伴舞登场血量基准(激励回血上限)
    buffTick = -1,          -- tick count of mj's buff duration
    dancers = {},           -- dancers
    costume = "DJ",

    grudge = -1,            -- MJ最近一次挨打的游戏分钟戳
    mjDead = false,         -- 对象池修复 — 死亡账本, 引用死后不可信, 一律查这个
    mjEverHit = false,      -- 和平观演 — MJ本场是否挨过打(合并时丢失, 补回)
    dancerTotal = 0,        -- 伴舞编制总数(死亡会从dancers名单移除, 全员存活判定用这个比对)
    mjDeathPos = nil,       -- MJ死亡坐标{x,y,z}, 散场放奖励用
    waveStamp = 0,          -- 上一波群演的真实秒戳
    ctrlTick = 0,           -- 控制节流
    healTick = 0,           -- 回血节流

    stageLocation = nil,    -- the IsoPlayer which triggered event
}

local st, util, conf = IsThriller, IsThriller.util, IsThriller.config
local outfit = require("IsThriller/Outfit")

function Actor.class(zombie, type)
    if type == "sprinter" then
        util.setZombieSpeed(zombie, "sprinter")
        util.doZombieStats(zombie, "Sight")

    elseif type == "shambler" then
        util.setZombieSpeed(zombie, "shambler")
        util.doZombieStats(zombie, "Strength")

    elseif type == "mj" then
        util.setZombieSpeed(zombie, "shambler")
        util.doZombieStats(zombie, "Sight")
        util.doZombieStats(zombie, "Strength")

    elseif type == "dancer" then
        util.setZombieSpeed(zombie, "shambler")
        util.doZombieStats(zombie, "Sight")
        util.doZombieStats(zombie, "Memory")
        util.doZombieStats(zombie, "Strength")

    else
        util.setZombieSpeed(zombie, "shambler")
    end
end

-- addZombiesInOutfit will return java array list, turn into lua table
---@return IsoZombie[] lua数组(可能为空)
function Actor.spawn(size, x, y, outfitID, femaleChance, extra)
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
            -- 如果装了AuthZ就往inventory里塞荧光棒
            if extra and st.hasAuthZ and zb.getInventory and zb:getInventory() then
            end
            table.insert(list, zb)
        end
    end)
    return list
end

-- 在player周围找可靠的室外落点
local function findSpawnSquare(player, dist)
    local cell = getCell()
    if not cell or not player then return nil end

    for _ = 1, 20 do
        local ang = ZombRand(360) * math.pi / 180
        local d = dist + ZombRand(-2, 3)
        local x = math.floor(player:getX() + math.cos(ang) * d)
        local y = math.floor(player:getY() + math.sin(ang) * d)
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
    zb:getModData().IsThrillerMJ = true
    Actor.mj = zb

    pcall(function() zb:setTarget(player) end)
    util.debugMsg("mjStandby: MJ spawned", "hp=", zb:getHealth(), "song=", tostring(st.music.current))
end

-- — 伴舞生成: 每个玩家对应MaxDancer只(0=随机2~5)
function Actor.dancerStandby(player)
    if #Actor.dancers > 0 then return end
    if not player then return end

    local count = util.getSV("MaxDancer")
    if count == 0 then count = ZombRand(2, 6) end

    local sq = findSpawnSquare(player, conf.get("spawnDist"))
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
        zb:getModData().IsThrillerDancer = true
        pcall(function() zb:setTarget(player) end)
        table.insert(Actor.dancers, zb)
    end
    Actor.dancerTotal = #Actor.dancers
    util.debugMsg("dancerStandby:", #Actor.dancers, "dancers spawned, outfit=", tostring(outfitID))
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
        zb:getModData().IsThrillerAudience = true
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
    Actor.grudge = -1
    Actor.mjDead = false
    Actor.mjEverHit = false
    Actor.dancerTotal = 0
    Actor.mjDeathPos = nil
    Actor.waveStamp = 0
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
        Actor.retreat(zombie)   -- 主演瞬移脱离
        for _, dancer in ipairs(Actor.dancers) do
            if not dancer:isDead() then
                pcall(function() dancer:setTarget(player) end)
            end
        end
        util.debugMsg("Actor.onHit: MJ hit, retreat + dancers retaliate")
        return
    end

    for _, dancer in ipairs(Actor.dancers) do
        if zombie == dancer then
            pcall(function() zombie:setTarget(player) end)
            util.debugMsg("Actor.onHit: dancer hit, retaliate")
            return
        end
    end
end

-- OnZombieDead : mark dead location to drop items
-- MJ死亡 → mjDead=true + 记坐标 + 断开引用; 伴舞死亡 → 从名单移除(名单里恒为活体)
function Actor.onDead(zombie)
    if not zombie then return end
    local md= zombie:getModData()

    if md and md.IsThrillerMJ then
        Actor.mjDead = true
        Actor.mjDeathPos = { x = zombie:getX(), y = zombie:getY(), z = zombie:getZ() }
        Actor.mj = nil
        util.debugMsg("MJ died at", Actor.mjDeathPos.x, Actor.mjDeathPos.y)
        return
    end

    if md and md.IsThrillerDancer then
        for i = #Actor.dancers, 1, -1 do
            if zombie == Actor.dancers[i]  then
                table.remove(Actor.dancers, i)
            end
        end
        util.debugMsg("dancer died (ref swapped),", #Actor.dancers, "left")
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
    local worldItem sq:AddWorldInventoryItem(conf.get("rewardBox"), 0.5, 0.5, 0)

    local item = worldItem.getItem and worldItem:getItem()
    local inv = item and item.getInventory and item:getInventory()
    if not inv then
        util.debugMsg("dropReward: box has no inventory, fullType=", tostring(conf.get("rewardBox")))
        return
    end

    local total = drop.totalRewardItems
    if st:dancerCount() == 0 then
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
                        if md and md.IsThrillerMJ then
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

local function curtainSquare(mj, player)
    if mj then
        local sq
        pcall(function() sq = mj:getSquare() end)
        if sq then return sq end
    end

    local pos = Actor.mjDeathPos
    local cell = getCell()
    if pos and cell then
        local sq = cell:getGridSquare(math.floor(pos.x), math.floor(pos.y), math.floor(pos.z))
        if sq then return sq end
    end

    return player and player:getSquare() or nil
end

function Actor.strike(player, canceled)
    local mj = Actor.mj

    -- 圆满落幕固定赠送一张已安装兼容包中的JacketFull完整专辑。
    if not canceled and IsThriller.endReason == "complete" then
        dropAlbumGift(curtainSquare(mj, player))
    end

    for _, zb in ipairs(Actor.dancers) do
        if zb and not zb:isDead() then
            pcall(function()
                zb:removeFromWorld()
                zb:removeFromSquare()
            end)
        end
    end

    if mj and not mj:isDead() then
        -- ClaudeNote: 和平观演(补回) — 完整演出+考勤达标+全程未挨打: 告别礼
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
        -- ClaudeNote: 对象池修复 — 死亡后引用已断开(mj=nil), 用账本判断删尸
        removeMJCorpse()
    end

    if Actor.mjDeathPos and not canceled then
        dropReward()
    end

    util.debugMsg("Actor.strike done", "canceled=", tostring(canceled), "everHit=", tostring(Actor.mjEverHit))
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
            local dist = zb:DistTo(player)

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
    local chance = util.getSV("SprintChance")

    for i = 0, zbList:size() - 1 do
        local zb = zbList:get(i)
        if zb and not zb:isDead() and not zb:getModData().IsThrillerMJ and not zb:getModData().IsThrillerDancer then
            local dist = zb:DistTo(player)
            if dist <= range then
                -- rollspeed
                local type = "shambler"
                if ZombRand(100) < chance then
                    type = "sprinter"
                end

                Actor.class(zb, type)
            end
        end
    end
end

-- MJ入场控制: 3格内停控(演出位), 7格外重新指路
-- 节流~0.5秒一次; 顺带在MJ身上挂声引怪
function Actor.mjCtrl(player)
    local zb = Actor.mj
    if not zb or zb:isDead() or not player then return end

    Actor.ctrlTick = Actor.ctrlTick + 1
    if Actor.ctrlTick < 30 then return end
    Actor.ctrlTick = 0

    local dist = zb:DistTo(player)

    -- 挨打硬直期不控场(onHit已瞬移, 让它自然站位)
    local grudging = Actor.grudge >= 0 and util.countMin(Actor.grudge) < 1

    if dist > 7 and not grudging then
        pcall(function()
            zb:setTarget(player)
            zb:pathToCharacter(player)
        end)
    elseif dist <= conf.get("danceRange") then
        -- 到达演出位: 停止强制控制(跳舞动画交给TAD联动, Phase5)
    end

    -- MJ光环: 声音吸引周围丧尸聚过来当观众
    pcall(function()
        getWorldSoundManager():addSound(zb, zb:getX(), zb:getY(), 0, conf.get("radius"), 80)
    end)
end

-- 伴舞控制: 跟到玩家附近(slotArriveDist内停), 挨打反击交给onHit
function Actor.dancerCtrl(player)
    if not player or #Actor.dancers == 0 then return end
    -- 与mjCtrl共用节流周期(ctrlTick刚归零时执行)
    if Actor.ctrlTick ~= 0 then return end

    for _, zb in ipairs(Actor.dancers) do
        if zb and not zb:isDead() then
            local dist = zb:DistTo(player)
            if dist > conf.get("danceRange") + conf.get("slotArriveDist") then
                pcall(function() zb:pathToCharacter(player) end)
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

    for _, d in ipairs(Actor.dancers) do
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
