-- return if main mod is unavailable
if not IsThriller then return end

IsThrillerTAD = IsThrillerTAD or {
    active = {},        -- active zombie dancers include all members
    spiner = {},      -- active spin zombies, this only run once
    chaser = {},         -- active chasing zombies
    moveIdx = 1,        -- current move index
    walkIdx = 1,        
    moveBeat = 0,       -- current beats
    beatsPerMove = 15   -- how many beats per dancing move. about ~0.5sec per beats
}
local td = IsThrillerTAD
local st = IsThriller


td.moves = {
    "Thriller_1",
    "Thriller_2",
    "Thriller_3",
    "Thriller_3",
    "Thriller_4",
    "Thriller_2",
    "Thriller_3",
    "Thriller_3",
    "Thriller_4",
}

td.walks = {
    "MoonWalk_1",
    "Thriller_1",
    "Thriller_3",
}

local function dMsg(...)
    IsThriller.util.debugMsg("[TAD]", ...)
end

local function cancelMovement(zombie)
    pcall(function()
        local pfb = zombie:getPathFindBehavior2()
        if pfb then
            pfb:cancel()
            pfb:reset()
        end
        zombie:setPath2(nil)
        zombie:setVariable("bPathfind", false)
    end)
end

local function restoreCtrl(zombie)
    if not zombie or not td.spiner[zombie] then return end

    local sv = td.spiner[zombie]
    if sv.group then
        td[sv.group][zombie] = true

        if sv.group == "chaser" then
            td.setDance(zombie, true, "walk")
        else
            td.setDance(zombie, true)
        end

    elseif sv.target and not sv.target:isDead() then
        zombie:setTarget(sv.target)
        zombie:spotted(sv.target, true)
        zombie:setAttackedBy(sv.target)
        zombie:pathToCharacter(sv.target)
    else
        zombie:setUseless(sv.useless)
    end
end

---@param list table should be move list
---IsThrillerTAD.setMoves({"Moves_1", "Moves_2", ...})
function td.setMoves(list)
    if type(list) ~= "table" or #list == 0 then return false end
    td.moves = list
    td.moveIdx = 1
    td.moveBeat = 0

    dMsg("moves replaced, count=", #list)
    return true
end

function td.currentMove()
    return td.moves[td.moveIdx]
end

function td.currentwalks()
    return td.walks[td.walkIdx]
end

-- set from Actor.onBeats
function td.setDance(zombie, on, branch)
    if not zombie then return end

    -- if should stop dance
    if not on and not branch then
        zombie:setVariable("bThrillerDance", false)
        zombie:setVariable("ThrillerAnim", "")
        zombie:setUseless(false)
        zombie:setMoving(true)

        if td.spiner[zombie] then
            zombie:setVariable("BumpAnimFinished", true)
            restoreCtrl(zombie)
        end

        td.active[zombie] = nil
        td.chaser[zombie] = nil
        td.spiner[zombie] = nil

    -- if should dance
    elseif on then
        --check branch at first
        zombie:setVariable("bThrillerDance", true)

        if branch == "walk" then
            zombie:setUseless(false)
            zombie:setMoving(true)
            zombie:setVariable("ThrillerAnim", "MoonWalk_1")
            td.chaser[zombie] = true
            td.active[zombie] = nil

        elseif branch == "spin" then
            cancelMovement(zombie)
            zombie:setUseless(true)
            zombie:setVariable("ThrillerDone", false)
            zombie:setVariable("BumpAnimFinished", false)
            zombie:setVariable("BumpType", "ThrillerOneShot")
            zombie:setVariable("ThrillerAnim", "Soul_Spin")

        else
            cancelMovement(zombie)
            zombie:setVariable("ThrillerAnim", td.moves[td.moveIdx])
            zombie:setUseless(true)
            td.active[zombie] = true
            td.chaser[zombie] = nil
        end
    end
end

-- do spin
function td.doSpin(zombie)
    if not zombie then return false end
    if td.spiner[zombie] then return false end

    if zombie:isOnFloor()
       or zombie:isKnockedDown()
       or zombie:getVariableBoolean("bFakeDead") then 
    return false end

    local session = {
        target = zombie:getTarget(),
        useless = zombie:isUseless(),
        beats = 0
    }

    if td.active[zombie] then
        td.active[zombie] = nil
        session.group = 'active'

    elseif td.chaser[zombie] then
        td.chaser[zombie] = nil
        session.group = 'chaser'
    end

    td.spiner[zombie] = session

    zombie:setTarget(nil)
    
    td.setDance(zombie, true, "spin")

end


local function updateSpin()
    for zombie, session in pairs(td.spiner) do
        if zombie and zombie:isDead() then
            td.spiner[zombie] = nil
        else
            session.beats = session.beats + 1
            local done = zombie:getVariableBoolean("ThrillerDone")
            local timedOut = session.beats >= 24
            if done or timedOut then
                zombie:setVariable("BumpAnimFinished", true)
                td.setDance(zombie, false)

                dMsg("one-shot finished", tostring(session.anim), "timeout=", tostring(timedOut))
            end
        end
    end
end


-- check and do motion on every beats 
function td.onBeat(player)
    updateSpin()
    
    for dancer in pairs(td.active) do
        -- check if dead or not
        if dancer:isDead() then
            td.active[dancer] = nil
        else
            -- set target off while dancing on stage
            if dancer:getTarget() ~= nil then
                dancer:setTarget(nil)
            end
        end
    end

    td.moveBeat = td.moveBeat + 1
    if td.moveBeat < td.beatsPerMove then return end
    td.moveBeat = 0

    td.moveIdx = td.moveIdx % #td.moves + 1
    local move = td.moves[td.moveIdx]

    td.walkIdx = td.walkIdx % #td.walks + 1
    local walk = td.walks[td.walkIdx]

    for zombie in pairs(td.active) do
        zombie:setVariable("ThrillerAnim", move)
    end
    for zombie in pairs(td.chaser) do
        zombie:setVariable("ThrillerAnim", walk)
    end
    dMsg("move rotate ->", move)
end

-- release all
function td.release()
    for zombie in pairs(td.active) do
        td.setDance(zombie, false)
    end
    for zombie in pairs(td.chaser) do
        td.setDance(zombie, false)
    end
    for zombie in pairs(td.spiner) do
        td.setDance(zombie, false)
    end

    td.active = {}
    td.chaser = {}
    td.spiner = {}

    td.moveIdx = 1
    td.moveBeat = 0
    dMsg("all registed dancer are released")
end
