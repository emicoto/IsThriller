-- GPTNote: IsThriller TestKit v1.0 compatibility backend for the merged DevTool panel (Build 42).
-- This file keeps the ITK console API while using the current actor registry and TAD branch semantics.

ITK = ITK or {}

ITK.selected = ITK.selected or nil
ITK.selectedID = ITK.selectedID or nil
ITK.selectedLabel = ITK.selectedLabel or "none"
ITK.lastResult = ITK.lastResult or "TestKit ready"

local function say(...)
    print("[ITK]", ...)
end

local function result(text)
    ITK.lastResult = tostring(text or "")
    say(ITK.lastResult)
    return ITK.lastResult
end

function ITK.checkTicks()
    ITK.gameTick = (ITK.gameTick or 0) + 1
    ITK.lastMs = ITK.lastMs or getTimestampMs()
    local elapsed = getTimestampMs() - ITK.lastMs
    if elapsed >= 1000 then
        say("tick sample:", ITK.gameTick, "ticks /", elapsed, "ms")
        ITK.gameTick = 0
        ITK.lastMs = getTimestampMs()
    end
end

local function safe(method, object, fallback)
    if not object then return fallback end
    local ok, value = pcall(function()
        local fn = object[method]
        if not fn then return fallback end
        return fn(object)
    end)
    if ok then return value end
    return fallback
end

local function fpos(object)
    if not object then return "nil" end
    local ok, text = pcall(function()
        return string.format("%.2f, %.2f, %.0f", object:getX(), object:getY(), object:getZ())
    end)
    return ok and text or "posErr"
end

local function fdist(a, b)
    if not a or not b then return -1 end
    local ok, distance = pcall(function() return a:DistTo(b) end)
    return ok and tonumber(string.format("%.2f", distance)) or -1
end

local function actorModule()
    return IsThriller and IsThriller.actor or nil
end

local function absoluteID(zombie)
    if not zombie then return nil end
    local actor = actorModule()
    if actor and actor.getDancerID then
        local ok, id = pcall(actor.getDancerID, zombie)
        if ok and id ~= nil then return id end
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

local function sortedRoster(fixedOnly)
    local actor = actorModule()
    local source = actor and (fixedOnly and actor.dancers or actor.allDancer) or nil
    local rows = {}
    for id, zombie in pairs(source or {}) do
        if zombie and not safe("isDead", zombie, true) then
            table.insert(rows, { id = id, zombie = zombie })
        end
    end
    table.sort(rows, function(a, b)
        if type(a.id) == "number" and type(b.id) == "number" then return a.id < b.id end
        return tostring(a.id) < tostring(b.id)
    end)
    return rows
end

local function scanActors()
    local list = { all = {}, dancer = {}, audience = {}, mj = nil, mjDead = false }
    local seen = {}
    local actor = actorModule()

    if actor and actor.mj and not safe("isDead", actor.mj, true) then
        list.mj = actor.mj
        table.insert(list.all, { "MJ", actor.mj })
        seen[actor.mj] = true
    elseif actor and actor.mjDead then
        list.mjDead = true
    end

    for _, row in ipairs(sortedRoster(true)) do
        local entry = { "DC:" .. tostring(row.id), row.zombie, row.id }
        table.insert(list.dancer, row.zombie)
        table.insert(list.all, entry)
        seen[row.zombie] = true
    end

    local player = getPlayer and getPlayer()
    local cell = player and player:getCell()
    local zombies = cell and cell:getZombieList()
    if zombies then
        for i = 0, zombies:size() - 1 do
            local zombie = zombies:get(i)
            if zombie and not safe("isDead", zombie, true) then
                local md = zombie:getModData()
                if md.isThrillerMJ and not list.mj then
                    list.mj = zombie
                    table.insert(list.all, { "MJ", zombie })
                    seen[zombie] = true
                end
                if md.isThrillerDancer and not seen[zombie] then
                    local id = absoluteID(zombie)
                    table.insert(list.dancer, zombie)
                    table.insert(list.all, { "DC:" .. tostring(id), zombie, id })
                    seen[zombie] = true
                end
                if md.isThrillerAudience then
                    table.insert(list.audience, zombie)
                    if not seen[zombie] then
                        table.insert(list.all, { "AD", zombie, absoluteID(zombie) })
                        seen[zombie] = true
                    end
                end
            end
        end
    end
    return list
end

local function setSelected(zombie, label)
    ITK.selected = zombie
    ITK.selectedID = absoluteID(zombie)
    ITK.selectedLabel = zombie and (label or "zombie") or "none"
    result(("selected %s id=%s ref=%s"):format(ITK.selectedLabel, tostring(ITK.selectedID), tostring(zombie)))
    return zombie
end

function ITK.getAbsoluteID(zombie)
    return absoluteID(zombie)
end

function ITK.getSelected()
    if ITK.selected and safe("isDead", ITK.selected, true) then
        ITK.selected = nil
        ITK.selectedID = nil
        ITK.selectedLabel = "none"
    end
    return ITK.selected
end

function ITK.select(zombie, label)
    return setSelected(zombie, label)
end

function ITK.p()
    local player = getPlayer and getPlayer()
    say("player:", tostring(player), "pos:", fpos(player))
    return player
end

function ITK.mj()
    local actor = actorModule()
    local zombie = actor and actor.mj or scanActors().mj
    if not zombie or safe("isDead", zombie, true) then
        result("MJ = nil/dead")
        return nil
    end
    setSelected(zombie, "MJ")
    say("  pos:", fpos(zombie), "hp=", tostring(safe("getHealth", zombie, "n/a")), "dPl=", tostring(fdist(zombie, getPlayer())))
    return zombie
end

function ITK.dancerRows()
    return sortedRoster(true)
end

function ITK.dancerByID(id)
    local actor = actorModule()
    if not actor then result("dancerByID: actor module missing") return nil end
    local key = id
    local zombie = actor.dancers and actor.dancers[key]
    if not zombie and type(id) == "string" then
        key = tonumber(id) or id
        zombie = actor.dancers and actor.dancers[key]
    end
    if not zombie then
        result("dancerByID: ID not found: " .. tostring(id))
        return nil
    end
    return setSelected(zombie, "Dancer " .. tostring(key))
end

function ITK.dc(index)
    local rows = sortedRoster(true)
    if index ~= nil then
        local row = rows[tonumber(index) or -1]
        if not row then result("dc: roster index not found: " .. tostring(index)) return nil end
        return setSelected(row.zombie, "Dancer " .. tostring(row.id))
    end
    for i, row in ipairs(rows) do
        say(("DC#%d absoluteID=%s ref=%s pos=[%s] dPl=%s"):format(i, tostring(row.id), tostring(row.zombie), fpos(row.zombie), tostring(fdist(row.zombie, getPlayer()))))
    end
    result("fixed dancer count=" .. tostring(#rows))
    return rows
end

function ITK.dancerIDs()
    local ids = {}
    local display = {}
    for _, row in ipairs(sortedRoster(true)) do
        table.insert(ids, row.id)
        table.insert(display, tostring(row.id))
    end
    result("fixed dancer absolute IDs = [" .. table.concat(display, ", ") .. "]")
    return ids
end

function ITK.allDancerIDs()
    local ids = {}
    local display = {}
    for _, row in ipairs(sortedRoster(false)) do
        table.insert(ids, row.id)
        table.insert(display, tostring(row.id))
    end
    result("all registered dancer absolute IDs = [" .. table.concat(display, ", ") .. "]")
    return ids
end

function ITK.pos(object)
    object = object or ITK.getSelected()
    say("pos:", fpos(object))
    return object and object:getX(), object and object:getY(), object and object:getZ()
end

function ITK.dist(a, b)
    a = a or ITK.getSelected()
    b = b or getPlayer()
    if not a or not b then result("dist: missing object") return nil end
    local dx = math.abs(a:getX() - b:getX())
    local dy = math.abs(a:getY() - b:getY())
    local dz = math.abs(a:getZ() - b:getZ())
    local api = fdist(a, b)
    say(string.format("DistTo=%.2f euclid=%.2f grid=%d manhattan=%.1f dz=%d", api, math.sqrt(dx * dx + dy * dy), math.floor(math.max(dx, dy)), dx + dy, math.floor(dz)))
    return api
end

function ITK.tp(zombie, x, y, z)
    zombie = zombie or ITK.getSelected()
    if not zombie then result("tp: no selected zombie") return false end
    local ok, err = pcall(function() zombie:teleportTo(x, y, z or 0) end)
    result(ok and ("teleport OK -> " .. tostring(x) .. "," .. tostring(y)) or ("teleport FAIL: " .. tostring(err)))
    return ok
end

function ITK.tpNearPlayer(zombie)
    zombie = zombie or ITK.getSelected()
    local player = getPlayer()
    if not zombie or not player then result("tpNearPlayer: missing selected/player") return false end
    return ITK.tp(zombie, math.floor(player:getX()) + 1.5, math.floor(player:getY()) + 0.5, player:getZ())
end

function ITK.calib(zombie, distance, diagonal)
    zombie = zombie or ITK.getSelected()
    local player = getPlayer()
    if not zombie or not player then result("calib: missing selected/player") return false end
    distance = tonumber(distance) or 5
    local x = math.floor(player:getX()) + distance + 0.5
    local y = diagonal and (math.floor(player:getY()) + distance + 0.5) or (math.floor(player:getY()) + 0.5)
    local ok = ITK.tp(zombie, x, y, player:getZ())
    if ok then ITK.dist(zombie, player) end
    return ok
end

function ITK.pathF(zombie, x, y, z)
    zombie = zombie or ITK.getSelected()
    if not zombie then result("pathF: no selected zombie") return false end
    local ok, err = pcall(function() zombie:pathToLocationF(x, y, z or zombie:getZ()) end)
    result(ok and "pathToLocationF OK" or ("pathToLocationF FAIL: " .. tostring(err)))
    return ok
end

function ITK.pathTo(zombie, character)
    zombie = zombie or ITK.getSelected()
    character = character or getPlayer()
    if not zombie or not character then result("pathTo: missing selected/character") return false end
    local ok, err = pcall(function() zombie:pathToCharacter(character) end)
    result(ok and "pathToCharacter OK" or ("pathToCharacter FAIL: " .. tostring(err)))
    return ok
end

function ITK.sound(zombie, x, y, z)
    zombie = zombie or ITK.getSelected()
    if not zombie then result("sound: no selected zombie") return false end
    local player = getPlayer()
    x = x or (player and player:getX())
    y = y or (player and player:getY())
    z = z or (player and player:getZ()) or 0
    if not x or not y then result("sound: missing location") return false end
    local ok, err = pcall(function() zombie:pathToSound(math.floor(x), math.floor(y), math.floor(z)) end)
    result(ok and "pathToSound OK" or ("pathToSound FAIL: " .. tostring(err)))
    return ok
end

function ITK.target(zombie, character)
    zombie = zombie or ITK.getSelected()
    if not zombie then result("target: no selected zombie") return false end
    if character == nil then character = getPlayer() end
    if character == false then character = nil end
    local ok, err = pcall(function() zombie:setTarget(character) end)
    result(ok and ("setTarget -> " .. tostring(character)) or ("setTarget FAIL: " .. tostring(err)))
    return ok
end

function ITK.getVar(zombie, name, silent)
    zombie = zombie or ITK.getSelected()
    if not zombie then return nil end
    local ok, value = pcall(function() return zombie:getVariableString(name) end)
    if not ok then ok, value = pcall(function() return zombie:getVariableBoolean(name) end) end
    local out = ok and tostring(value) or "n/a"
    if not silent then say("var", name, "=", out) end
    return out
end

function ITK.setVar(zombie, name, value)
    zombie = zombie or ITK.getSelected()
    if not zombie then result("setVar: no selected zombie") return false end
    local ok, err = pcall(function() zombie:setVariable(name, value) end)
    result(ok and ("setVariable " .. tostring(name) .. "=" .. tostring(value)) or ("setVariable FAIL: " .. tostring(err)))
    return ok
end

function ITK.vars(zombie)
    zombie = zombie or ITK.getSelected()
    if not zombie then result("vars: no selected zombie") return nil end
    for _, name in ipairs({ "bThrillerDance", "ThrillerAnim", "ThrillerDone", "BumpType", "BumpAnimFinished", "bPathfind", "zombieWalkType" }) do
        ITK.getVar(zombie, name)
    end
    say("moving=", tostring(safe("isMoving", zombie, "n/a")), "pathing=", tostring(safe("isPathing", zombie, "n/a")), "useless=", tostring(safe("isUseless", zombie, "n/a")))
    result("selected animation/path variables printed")
    return zombie
end

function ITK.path(zombie)
    zombie = zombie or ITK.getSelected()
    if not zombie then result("path: no selected zombie") return nil end
    say("hasPath=", tostring(safe("hasPath", zombie, "n/a")), "isPathing=", tostring(safe("isPathing", zombie, "n/a")), "isMoving=", tostring(safe("isMoving", zombie, "n/a")))
    say("pathTarget=", tostring(safe("getPathTargetX", zombie, "n/a")), tostring(safe("getPathTargetY", zombie, "n/a")), "bPathfind=", tostring(ITK.getVar(zombie, "bPathfind", true)))
    result("selected path state printed")
    return zombie
end

function ITK.tags(zombie)
    zombie = zombie or ITK.getSelected()
    if not zombie then result("tags: no selected zombie") return nil end
    local md = zombie:getModData()
    say("MJ=", tostring(md.isThrillerMJ), "DANCER=", tostring(md.isThrillerDancer), "AUDIENCE=", tostring(md.isThrillerAudience), "absoluteID=", tostring(absoluteID(zombie)))
    return md
end

function ITK.dance(zombie, on, move)
    local targets = {}
    if zombie == "all" then
        for _, row in ipairs(sortedRoster(false)) do table.insert(targets, row.zombie) end
    else
        table.insert(targets, zombie or ITK.getSelected())
    end

    local changed = 0
    for _, target in ipairs(targets) do
        if target and not safe("isDead", target, true) then
            if IsThrillerTAD and IsThrillerTAD.setDance then
                if on and move and move ~= "walk" and move ~= "spin" then
                    pcall(IsThrillerTAD.setDance, target, true)
                    pcall(function() target:setVariable("ThrillerAnim", move) end)
                else
                    pcall(IsThrillerTAD.setDance, target, on and true or false, move)
                end
            else
                pcall(function()
                    target:setVariable("bThrillerDance", on and true or false)
                    target:setVariable("ThrillerAnim", on and (move or "Thriller_1") or "")
                    target:setUseless(on and move ~= "walk")
                    target:setMoving(not on or move == "walk")
                end)
            end
            changed = changed + 1
        end
    end
    result(("dance on=%s branch/move=%s targets=%d"):format(tostring(on), tostring(move or "current"), changed))
    return changed
end

function ITK.move(zombie, move)
    return ITK.setVar(zombie, "ThrillerAnim", move)
end

function ITK.spin(zombie)
    zombie = zombie or ITK.getSelected()
    if not zombie then result("spin: no selected zombie") return false end
    if IsThrillerTAD and IsThrillerTAD.doSpin then
        local ok, value = pcall(IsThrillerTAD.doSpin, zombie)
        result(ok and ("one-shot spin requested: " .. tostring(value)) or ("one-shot spin FAIL: " .. tostring(value)))
        return ok
    end
    result("spin: TAD doSpin unavailable")
    return false
end

function ITK.rally()
    local actor = actorModule()
    local mj = actor and actor.mj
    if not mj or safe("isDead", mj, true) then result("rally: no living MJ") return 0 end
    local count = 0
    for _, row in ipairs(sortedRoster(true)) do
        local offsetX = (ZombRand(5) - 2) * 0.6
        local offsetY = (ZombRand(5) - 2) * 0.6
        local ok = pcall(function() row.zombie:pathToLocationF(mj:getX() + offsetX, mj:getY() + offsetY, mj:getZ()) end)
        if ok then count = count + 1 end
    end
    result("rally commands=" .. tostring(count))
    return count
end

function ITK.march()
    local actor = actorModule()
    local player = getPlayer()
    if not actor or not actor.mj or not player then result("march: missing MJ/player") return false end
    pcall(function() actor.mj:pathToCharacter(player) end)
    ITK.rally()
    result("march: MJ -> player, fixed dancers -> MJ")
    return true
end

function ITK.near(radius)
    radius = tonumber(radius) or 10
    local player = getPlayer()
    local zombies = player and player:getCell() and player:getCell():getZombieList()
    if not zombies then result("near: no zombie list") return {} end
    local rows = {}
    for i = 0, zombies:size() - 1 do
        local zombie = zombies:get(i)
        if zombie and not safe("isDead", zombie, true) and fdist(zombie, player) <= radius then
            local md = zombie:getModData()
            local tag = md.isThrillerMJ and "MJ" or (md.isThrillerDancer and "DANCER" or (md.isThrillerAudience and "AUDIENCE" or "-"))
            table.insert(rows, zombie)
            say(("#%d tag=%s absoluteID=%s d=%.1f pos=[%s] dance=%s"):format(#rows, tag, tostring(absoluteID(zombie)), fdist(zombie, player), fpos(zombie), tostring(ITK.getVar(zombie, "bThrillerDance", true))))
        end
    end
    result(("near radius=%s count=%d"):format(tostring(radius), #rows))
    return rows
end

local watchTick = 0
local watchEvery = 60
local function watchLoop()
    watchTick = watchTick + 1
    if watchTick < watchEvery then return end
    watchTick = 0
    local actor = actorModule()
    local player = getPlayer()
    if not actor or not player then return end
    local parts = {}
    if actor.mj then table.insert(parts, ("MJ dPl=%s path=%s"):format(tostring(fdist(actor.mj, player)), tostring(safe("isPathing", actor.mj, "n/a")))) end
    for _, row in ipairs(sortedRoster(true)) do
        table.insert(parts, ("DC[%s] dPl=%s path=%s dance=%s"):format(tostring(row.id), tostring(fdist(row.zombie, player)), tostring(safe("isPathing", row.zombie, "n/a")), tostring(ITK.getVar(row.zombie, "bThrillerDance", true))))
    end
    print("[ITK] W| " .. table.concat(parts, " | "))
end

function ITK.watch(on, seconds)
    Events.OnTick.Remove(watchLoop)
    ITK.watching = on and true or false
    if ITK.watching then
        watchEvery = math.max(1, math.floor((tonumber(seconds) or 1) * 60))
        watchTick = 0
        Events.OnTick.Add(watchLoop)
    end
    result("watch " .. (ITK.watching and "ON" or "OFF"))
    return ITK.watching
end

function ITK.spawn(what)
    local actor = actorModule()
    local player = getPlayer()
    if not actor or not player then result("spawn: missing actor/player") return false end
    if what == "mj" then
        local ok, err = pcall(actor.mjStandby, player)
        result(ok and ("spawn MJ -> " .. tostring(actor.mj)) or ("spawn MJ FAIL: " .. tostring(err)))
        return ok
    elseif what == "dc" then
        local ok, err = pcall(actor.dancerStandby, player)
        result(ok and ("spawn dancers alive=" .. tostring(actor:dancerCount())) or ("spawn dancers FAIL: " .. tostring(err)))
        return ok
    end
    result("spawn usage: 'mj' or 'dc'")
    return false
end

function ITK.dump()
    if IsThriller and IsThriller.util and IsThriller.util.dump then
        pcall(IsThriller.util.dump)
        result("mod state dumped to console")
    end
end

function ITK.help()
    say("-- select: mj() dc(index?) dancerByID(absoluteID) dancerIDs() allDancerIDs() getSelected()")
    say("-- inspect: p() pos(o?) dist(a?,b?) vars(z?) path(z?) tags(z?) getVar(z?,name) setVar(z?,name,value)")
    say("-- move: tp(z?,x,y,z) tpNearPlayer(z?) calib(z?,n,diagonal) pathF(z?,x,y,z) pathTo(z?,chr?) sound(z?,x?,y?,z?) target(z?,chr|false)")
    say("-- dance: dance(z|'all',on,branchOrMove?) move(z?,move) spin(z?) rally() march()")
    say("-- tools: near(radius?) watch(on,seconds?) spawn('mj'|'dc') dump()")
end

say("TestKit v1.0 loaded. ITK.help() for console commands.")
